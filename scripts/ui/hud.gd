class_name HUD
extends Control
## Игровой интерфейс: здоровье, задачи, время суток, хотбар, миникарта, уведомления.
##
## Оптимизации (issue #7):
##  * перерисовка ленивая: каждый кадр HUD собирает «ключ» того, что видно на
##    экране (здоровье и импульс в пикселях полосок, задачи, часы, хотбар,
##    подсказка, уведомления), и перерисовывается, только если ключ сменился.
##    Анимации (мигание урона, затухание уведомлений и подсказки управления)
##    идут каждый кадр, пока живы. Часы квантуются до CLOCK_STEPS шагов за
##    сутки — солнце на дуге сдвигается на треть пикселя примерно раз в секунду.
##    ВАЖНО: всё новое, что рисует _draw(), должно попасть в ключ (_fill_key),
##    иначе на экране оно не обновится;
##  * миникарта — отдельный слой: рельеф запечён в текстуру (один
##    draw_texture вместо 320 draw_line), текстура пересобирается только при
##    изменении рельефа (сверка раз в MAP_CHECK_SEC); сам слой перерисовывается,
##    когда точка игрока сдвинулась на пиксель;
##  * туман войны на миникарте (#59) — вторая запечённая текстура поверх рельефа:
##    пиксель чёрный, пока не исследована его клетка-представитель. Правится
##    только по сигналу World.explored_changed (пиксели под новыми клетками),
##    слой карты перерисовывается лишь когда пиксель тумана реально открылся;
##  * прицел — отдельный слой из четырёх линий, перерисовывается при движении мыши;
##  * подсказки не перебирают постройки мира: смотрим только клетки вокруг
##    игрока в World.machines (словарь по клетке) — стоимость не зависит от
##    размера фабрики. Пересчёт — когда игрок сдвинулся или изменилось число
##    построек, и не реже HINT_RECHECK_SEC.

## Сколько шагов у часов за полные сутки (Balance.DAY_LENGTH).
const CLOCK_STEPS: int = 256
## Как часто сверять рельеф под миникартой, с.
const MAP_CHECK_SEC: float = 1.0
## Подсказку пересчитываем и без движения игрока — постройку могли поставить
## или снять прямо под ним.
const HINT_RECHECK_SEC: float = 0.25
## Радиусы подсказок, px (как раньше).
const HINT_TERMINAL_DIST: float = 42.0
const HINT_BEACON_DIST: float = 56.0
const HINT_MACHINE_DIST: float = 40.0
## Прямоугольник миникарты относительно правого верхнего угла.
const MAP_SIZE: Vector2i = Vector2i(186, 52)
const MAP_OFFSET: Vector2 = Vector2(200, 60)
## Длина ключа состояния (см. _fill_key).
const KEY_LEN: int = 40

var player = null   ## Ссылка на игрока без статического типа (иначе цикл зависимостей).
var notes: Array = []          ## [{text, color, ttl}]
var damage_flash: float = 0.0
var panel_alpha: float = 0.0
## Текущая подсказка внизу экрана ("" — нет). Читают сценарии.
var hint_text: String = ""

# ---------------------------------------------- СЧЁТЧИКИ (для замеров)
## Время в _process и всех _draw слоёв HUD, мкс (tools/hud_probe.gd).
var stat_us: int = 0
var stat_frames: int = 0
## Сколько раз перерисованы слои: основной, миникарта, прицел.
var stat_redraws: int = 0
var stat_map_redraws: int = 0
var stat_map_bakes: int = 0
var stat_cross_redraws: int = 0

# ------------------------------------------------------------ ВНУТРЕННЕЕ
var _cross: Control = null
var _map: Control = null
var _map_img: Image = null
var _map_tex: ImageTexture = null
var _map_sig: PackedInt32Array = PackedInt32Array()
var _map_check_t: float = 0.0
var _map_dot: Vector2i = Vector2i(-9999, -9999)
var _map_rect: Rect2 = Rect2()
var _fog_img: Image = null
var _fog_tex: ImageTexture = null
var _fog_dirty: bool = false
var _fog_open: PackedByteArray = PackedByteArray()   # 1 — пиксель тумана открыт
var _mouse: Vector2 = Vector2(-1.0, -1.0)
var _key: PackedInt32Array = PackedInt32Array()
var _last_key: PackedInt32Array = PackedInt32Array()
var _note_serial: int = 0
var _animating: bool = false
var _hint_hash: int = 0
var _hint_t: float = 0.0
var _hint_pos: Vector2 = Vector2(INF, INF)
var _hint_machines: int = -1
var _hint_hiding: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_key.resize(KEY_LEN)
	_map = _make_layer(_draw_map_layer)
	_cross = _make_layer(_draw_cross_layer)
	_map_img = Image.create(MAP_SIZE.x, MAP_SIZE.y, false, Image.FORMAT_RGBA8)
	_map_tex = ImageTexture.create_from_image(_map_img)
	_fog_img = Image.create(MAP_SIZE.x, MAP_SIZE.y, false, Image.FORMAT_RGBA8)
	_fog_tex = ImageTexture.create_from_image(_fog_img)
	_fog_open.resize(MAP_SIZE.x * MAP_SIZE.y)
	World.explored_changed.connect(_on_explored)
	World.explored_reset.connect(_on_explored_reset)
	_on_explored_reset()


func _make_layer(cb: Callable) -> Control:
	var c: Control = Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.draw.connect(cb)
	add_child(c)
	return c


func _process(delta: float) -> void:
	var t0: int = Time.get_ticks_usec()
	stat_frames += 1
	damage_flash = maxf(0.0, damage_flash - delta * 2.0)
	var fading: bool = false
	var i: int = notes.size() - 1
	while i >= 0:
		notes[i]["ttl"] = float(notes[i]["ttl"]) - delta
		if float(notes[i]["ttl"]) <= 0.0:
			notes.remove_at(i)
		elif float(notes[i]["ttl"]) < 1.5:
			fading = true
		i -= 1
	# Скрытый HUD рисовать незачем; при показе Godot перерисует слои сам.
	if not is_visible_in_tree():
		stat_us += Time.get_ticks_usec() - t0
		return

	_update_hint(delta)

	# Основной слой: каждый кадр — пока идёт анимация (и ещё один кадр после неё),
	# иначе — только при смене ключа.
	var anim: bool = damage_flash > 0.0 or fading \
			or (Game.game_time < 22.0 and Game.game_time > 16.0)
	_fill_key()
	if anim or _animating or _key != _last_key:
		_last_key = _key.duplicate()
		queue_redraw()
	_animating = anim

	_update_map(delta)

	var mp: Vector2 = get_viewport().get_mouse_position()
	if mp != _mouse:
		_mouse = mp
		_cross.queue_redraw()
	stat_us += Time.get_ticks_usec() - t0


func notify(text: String, color: Color) -> void:
	notes.append({"text": text, "color": color, "ttl": 5.0})
	while notes.size() > 6:
		notes.remove_at(0)
	_note_serial += 1


## Ключ видимого состояния основного слоя. Значения квантуются до того шага,
## на котором картинка реально меняется (пиксель полоски, шаг часов).
func _fill_key() -> void:
	_key[0] = int(size.x)
	_key[1] = int(size.y)
	_key[2] = _note_serial
	_key[3] = notes.size()
	_key[4] = _hint_hash
	_key[5] = Game.tasks_done
	_key[6] = Game.tasks_total
	_key[7] = Game.research
	_key[8] = Game.day_number
	_key[9] = int(Game.time_of_day * float(CLOCK_STEPS))
	_key[10] = int(Game.daylight() * 32.0)
	_key[11] = 1 if Game.game_time < 22.0 else 0
	_key[37] = Game.phase_name().hash()
	if player == null:
		_key[12] = 0
		return
	_key[12] = 1
	var frac: float = clampf(player.hp / 100.0, 0.0, 1.0)
	_key[13] = int(206.0 * frac)
	_key[14] = int(player.hp)
	_key[15] = int(148.0 * (1.0 - player.emp_cd / player.emp_max))
	_key[16] = player.inv.selected
	for s in 10:
		var st: ItemStack = player.inv.get_slot(s)
		_key[17 + s * 2] = st.id
		_key[18 + s * 2] = st.count


# ------------------------------------------------------------ ПОДСКАЗКИ

func _update_hint(delta: float) -> void:
	_hint_t -= delta
	if player == null:
		_set_hint("")
		return
	var pos: Vector2 = player.global_position
	if _hint_t > 0.0 and pos.distance_squared_to(_hint_pos) < 0.25 \
			and World.machines.size() == _hint_machines and player.hiding == _hint_hiding:
		return
	_hint_t = HINT_RECHECK_SEC
	_hint_pos = pos
	_hint_machines = World.machines.size()
	_hint_hiding = player.hiding
	_set_hint(_compute_hint(pos))


func _set_hint(h: String) -> void:
	if h == hint_text:
		return
	hint_text = h
	_hint_hash = h.hash()


func _compute_hint(pos: Vector2) -> String:
	if player.hiding:
		return "Вы в вентиляции. [V] — вылезть"
	for t in World.terminals:
		if World.cell_to_world(t).distance_to(pos) < HINT_TERMINAL_DIST:
			return "[E] — выполнить задание (удерживать)"
	if World.cell_to_world(World.beacon_cell).distance_to(pos) < HINT_BEACON_DIST:
		return "[E] — активировать релей-ядро (удерживать)"
	# Только клетки в радиусе подсказки, а не все постройки мира.
	var r: int = int(ceil(HINT_MACHINE_DIST / float(World.TILE))) + 1
	var pc: Vector2i = World.world_to_cell(pos)
	var chest: bool = false
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var m = World.machines.get(pc + Vector2i(dx, dy))
			if m == null or not is_instance_valid(m):
				continue
			if m.global_position.distance_to(pos) >= HINT_MACHINE_DIST:
				continue
			if m is CoalGen:
				return "[E] — загрузить уголь в ТЭЦ"
			if m is Chest:
				chest = true
	if chest:
		return "[E] — открыть сундук"
	return ""


# ------------------------------------------------------------ МИНИКАРТА

func _update_map(delta: float) -> void:
	_map_check_t -= delta
	if _map_check_t <= 0.0:
		_map_check_t = MAP_CHECK_SEC
		if _bake_map_if_changed():
			_map.queue_redraw()
	if _fog_dirty:
		_fog_dirty = false
		_fog_tex.update(_fog_img)
		_map.queue_redraw()
	var r: Rect2 = Rect2(size.x - MAP_OFFSET.x, MAP_OFFSET.y, MAP_SIZE.x, MAP_SIZE.y)
	if r != _map_rect:
		_map_rect = r
		_map.queue_redraw()
	if player == null:
		return
	var pc: Vector2i = World.world_to_cell(player.global_position)
	var dot: Vector2i = Vector2i(int(float(pc.x * MAP_SIZE.x) / float(World.W)),
			int(float(pc.y * MAP_SIZE.y) / float(World.H)))
	if dot != _map_dot:
		_map_dot = dot
		_map.queue_redraw()


## Сверить рельеф с запечённым и при отличии перерисовать текстуру.
## Одна сверка — MAP_SIZE.x чтений тайлов; запекание — столько же fill_rect.
func _bake_map_if_changed() -> bool:
	if World.surface.is_empty():
		return false
	var sig: PackedInt32Array = PackedInt32Array()
	sig.resize(MAP_SIZE.x * 2)
	for px in MAP_SIZE.x:
		var x: int = mini(World.W - 1, int(float(px) * float(World.W) / float(MAP_SIZE.x)))
		var top: int = World.surface[x]
		sig[px * 2] = top
		sig[px * 2 + 1] = World.get_tile(x, top)
	if sig == _map_sig:
		return false
	_map_sig = sig
	stat_map_bakes += 1
	_map_img.fill(Color(0, 0, 0, 0))
	var sy: float = float(MAP_SIZE.y) / float(World.H)
	for px in MAP_SIZE.x:
		var c: Color = Color(0.20, 0.45, 0.20)
		var tid: int = sig[px * 2 + 1]
		if tid == IDs.T.SAND:
			c = Color(0.70, 0.62, 0.35)
		elif tid == IDs.T.STONE:
			c = Color(0.35, 0.35, 0.40)
		var y0: int = clampi(int(float(sig[px * 2]) * sy), 0, MAP_SIZE.y - 1)
		_map_img.fill_rect(Rect2i(px, y0, 1, MAP_SIZE.y - y0), c)
	_map_tex.update(_map_img)
	return true


func _draw_map_layer() -> void:
	var t0: int = Time.get_ticks_usec()
	stat_map_redraws += 1
	if World.surface.is_empty():
		return
	var r: Rect2 = _map_rect
	var c: Control = _map
	c.draw_rect(r, Color(0.05, 0.06, 0.09, 0.72))
	c.draw_texture(_map_tex, r.position)
	c.draw_texture(_fog_tex, r.position)
	c.draw_rect(r, Color(1, 1, 1, 0.25), false, 1.0)
	var sx: float = r.size.x / float(World.W)
	var sy: float = r.size.y / float(World.H)
	# Релей
	var bp: Vector2 = r.position + Vector2(World.beacon_cell.x * sx, World.beacon_cell.y * sy)
	c.draw_rect(Rect2(bp - Vector2(3, 3), Vector2(6, 6)), Color(0.3, 0.95, 1.0))
	# Игрок
	if player:
		c.draw_circle(r.position + Vector2(_map_dot), 3.0, Color(0.95, 0.25, 0.28))
	c.draw_string(ThemeDB.fallback_font, r.position + Vector2(4, 12), "КАРТА",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.6))
	stat_us += Time.get_ticks_usec() - t0


# ------------------------------------------------------------ ТУМАН НА МИНИКАРТЕ (#59)

## Клетка мира, по которой решается, открыт ли пиксель миникарты (центр пикселя).
func _map_cell(px: int, py: int) -> Vector2i:
	return Vector2i(mini(World.W - 1, int((float(px) + 0.5) * float(World.W) / float(MAP_SIZE.x))),
			mini(World.H - 1, int((float(py) + 0.5) * float(World.H) / float(MAP_SIZE.y))))


## Карта исследования заменена: всё чёрное, потом открываем по ней (после
## загрузки #37 — полный проход по пикселям, при новом мире карта ещё пуста).
func _on_explored_reset() -> void:
	_fog_img.fill(Color(0, 0, 0, 1))
	_fog_open.fill(0)
	_fog_dirty = true
	if World.explore_cells == 0:
		return
	for py in MAP_SIZE.y:
		# Ряд пикселей, под которым ни одной открытой клетки, — одна нативная проверка.
		var row: int = _map_cell(0, py).y * World.W
		if not World.explored.slice(row, row + World.W).has(1):
			continue
		for px in MAP_SIZE.x:
			_open_fog_px(px, py)


## Открылись клетки: смотрим только пиксели миникарты под новыми клетками.
func _on_explored(_rect: Rect2i) -> void:
	var ww: int = World.W
	var hh: int = World.H
	var mw: int = MAP_SIZE.x
	var mh: int = MAP_SIZE.y
	var last: int = -1
	for idx in World.explore_new:
		var px: int = (idx % ww) * mw / ww
		var py: int = (idx / ww) * mh / hh
		var fi: int = py * mw + px
		if fi == last or _fog_open[fi] != 0:
			continue
		last = fi
		_open_fog_px(px, py)


func _open_fog_px(px: int, py: int) -> void:
	if World.is_explored(_map_cell(px, py)):
		_fog_open[py * MAP_SIZE.x + px] = 1
		_fog_img.set_pixel(px, py, Color(0, 0, 0, 0))
		_fog_dirty = true


## Открыт ли туман миникарты над клеткой мира (для сценария fog_reveal).
func map_explored_at(c: Vector2i) -> bool:
	var px: int = clampi(c.x * MAP_SIZE.x / World.W, 0, MAP_SIZE.x - 1)
	var py: int = clampi(c.y * MAP_SIZE.y / World.H, 0, MAP_SIZE.y - 1)
	return _fog_open[py * MAP_SIZE.x + px] != 0


# ------------------------------------------------------------ ПРИЦЕЛ

func _draw_cross_layer() -> void:
	stat_cross_redraws += 1
	var mp: Vector2 = _mouse
	var cross: Color = Color(1, 1, 1, 0.75)
	_cross.draw_line(mp - Vector2(7, 0), mp - Vector2(3, 0), cross, 1.5)
	_cross.draw_line(mp + Vector2(3, 0), mp + Vector2(7, 0), cross, 1.5)
	_cross.draw_line(mp - Vector2(0, 7), mp - Vector2(0, 3), cross, 1.5)
	_cross.draw_line(mp + Vector2(0, 3), mp + Vector2(0, 7), cross, 1.5)


# ------------------------------------------------------------ ОСНОВНОЙ СЛОЙ

func _draw() -> void:
	var t0: int = Time.get_ticks_usec()
	stat_redraws += 1
	var w: float = size.x
	var h: float = size.y
	var font: Font = ThemeDB.fallback_font

	if damage_flash > 0.0:
		draw_rect(Rect2(0, 0, w, h), Color(0.8, 0.1, 0.1, damage_flash * 0.25))

	# ---- Здоровье ------------------------------------------------------------
	if player:
		var hp_rect: Rect2 = Rect2(14, 12, 210, 20)
		draw_rect(hp_rect, Color(0, 0, 0, 0.55))
		var frac: float = clampf(player.hp / 100.0, 0.0, 1.0)
		var hp_col: Color = Color(0.85, 0.22, 0.28) if frac > 0.35 else Color(0.95, 0.45, 0.15)
		draw_rect(Rect2(hp_rect.position + Vector2(2, 2), Vector2((hp_rect.size.x - 4) * frac, hp_rect.size.y - 4)), hp_col)
		draw_rect(hp_rect, Color(1, 1, 1, 0.35), false, 1.0)
		draw_string(font, hp_rect.position + Vector2(8, 15), "%d" % int(player.hp),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.9))

		# Индикатор заряда импульса
		var emp_rect: Rect2 = Rect2(14, 38, 150, 8)
		draw_rect(emp_rect, Color(0, 0, 0, 0.5))
		var ef: float = 1.0 - player.emp_cd / player.emp_max
		draw_rect(Rect2(emp_rect.position + Vector2(1, 1), Vector2((emp_rect.size.x - 2) * ef, emp_rect.size.y - 2)),
				Color(0.35, 0.8, 1.0))
		draw_string(font, emp_rect.position + Vector2(156, 8), "ИМПУЛЬС [Q]",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.85, 1.0, 0.85))

		# Инвентарь подсказка
		draw_string(font, Vector2(14, 66), "Задачи: %d/%d   Данные: %d" % [Game.tasks_done, Game.tasks_total, Game.research],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.92, 1.0, 0.9))

	# ---- Время суток ---------------------------------------------------------
	# Солнце ставим по квантованному времени — ровно тому, что в ключе перерисовки.
	var clock_pos: Vector2 = Vector2(w - 120, 46)
	draw_arc(clock_pos, 22.0, PI, TAU, 32, Color(0, 0, 0, 0.45), 3.0)
	var tq: float = float(int(Game.time_of_day * float(CLOCK_STEPS))) / float(CLOCK_STEPS)
	var ang: float = PI + tq * PI
	var sun: Vector2 = clock_pos + Vector2(cos(ang), sin(ang)) * 22.0
	var dl: float = Game.daylight()
	var sky: Color = Color(0.25, 0.30, 0.45).lerp(Color(1.0, 0.85, 0.35), dl)
	draw_circle(sun, 6.0, sky)
	draw_string(font, Vector2(w - 176, 26), "Смена %d — %s" % [Game.day_number, Game.phase_name()],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.9, 0.92, 1.0))

	# ---- Уведомления --------------------------------------------------------
	var y: float = h - 150
	for i in range(notes.size() - 1, -1, -1):
		var n: Dictionary = notes[i]
		var a: float = clampf(float(n["ttl"]) / 1.5, 0.0, 1.0)
		# Длинные сообщения не режем — сдвигаем их влево, чтобы текст целиком влезал.
		var txt: String = String(n["text"])
		var tw: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var nx: float = minf(w - 430.0, w - tw - 24.0)
		draw_string(font, Vector2(nx, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
				Color(n["color"].r, n["color"].g, n["color"].b, a))
		y -= 20

	# ---- Хотбар --------------------------------------------------------------
	if player:
		_draw_hotbar(font)

	# ---- Подсказки -----------------------------------------------------------
	if hint_text != "":
		draw_string(font, Vector2(size.x * 0.5 - 190, size.y - 116), hint_text,
				HORIZONTAL_ALIGNMENT_CENTER, 380, 15, Color(1.0, 0.95, 0.75, 0.95))

	# ---- Подсказка управления (затухает) ------------------------------------
	if Game.game_time < 22.0:
		var ta: float = clampf((22.0 - Game.game_time) / 6.0, 0.0, 1.0)
		var lines: Array = [
			"WASD — движение   SPACE — прыжок   SHIFT — бег",
			"ЛКМ — копать / бить   ПКМ — строить   E — взаимодействовать",
			"Q — импульс   V — вентиляция   I / TAB — инвентарь и крафт   1-0 — хотбар",
		]
		for i in lines.size():
			draw_string(font, Vector2(size.x * 0.5 - 260, size.y * 0.30 + i * 20), String(lines[i]),
					HORIZONTAL_ALIGNMENT_CENTER, 520, 14, Color(0.85, 0.92, 1.0, ta))
	stat_us += Time.get_ticks_usec() - t0


func _draw_hotbar(font: Font) -> void:
	var slot: float = 46.0
	var count: int = 10
	var total: float = slot * count
	var x0: float = size.x * 0.5 - total * 0.5
	var y0: float = size.y - 74
	for i in count:
		var r: Rect2 = Rect2(x0 + i * slot, y0, slot - 4, slot - 4)
		var sel: bool = (player.inv.selected == i)
		draw_rect(r, Color(0.08, 0.09, 0.12, 0.82))
		draw_rect(r, Color(1, 1, 1, 0.85) if sel else Color(1, 1, 1, 0.22), false, 2.0 if sel else 1.0)
		var st: ItemStack = player.inv.get_slot(i)
		if not st.is_empty():
			var tex: ImageTexture = DB.item_texture(st.id)
			if tex:
				draw_texture_rect(tex, Rect2(r.position + Vector2(7, 7), Vector2(28, 28)), false)
			if st.count > 1:
				draw_string(font, r.position + Vector2(2, r.size.y - 4), str(st.count),
						HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 6, 12, Color(1, 1, 1, 0.95))
		draw_string(font, r.position + Vector2(3, 12), str((i + 1) % 10),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.45))
