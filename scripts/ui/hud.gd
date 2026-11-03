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
##
## Трекер цели, обучение и мощность (ADR-001 § 4.1, § 4.3, § 4.7; #34):
##  * трекер этапа цели (Game.objective_stage, #32) и цепочка подсказок первых
##    минут (копай → крафт → ТЭЦ → питание → терминал) — строки собираются раз в
##    STATE_RECHECK_SEC (и сразу по Game.objective_changed / brownout_changed),
##    в ключ попадает только их хеш;
##  * индикатор мощности: генератор под курсором, иначе ближайший в окне
##    ±POWER_SCAN_CELLS × ±POWER_SCAN_ROWS клеток вокруг игрока (окно
##    сканируется тем же шагом STATE_RECHECK_SEC и только если игрок сменил
##    клетку или число построек изменилось; курсор — одна выборка из словаря за
##    кадр); в ключ — нагрузка и выход с шагом 0.1;
##  * «под питанием ли терминал» — Game.is_powered перебирает все генераторы,
##    поэтому ответ кэшируется на шаг STATE_RECHECK_SEC, а без единого
##    работающего генератора не спрашивается вовсе;
##  * отсчёт до ночи в сумерках — целые секунды в ключе (перерисовка раз в секунду);
##  * вентиляции и решётки (#31, World.vents_sealed) на миникарте — только под
##    открытым туманом; решётки сверяются раз в MAP_CHECK_SEC, сломанная
##    (World.grate_broken) — сразу.

## Сколько шагов у часов за полные сутки (Balance.DAY_LENGTH).
const CLOCK_STEPS: int = 256
## Как часто сверять рельеф под миникартой, с.
const MAP_CHECK_SEC: float = 1.0
## Подсказку пересчитываем и без движения игрока — постройку могли поставить
## или снять прямо под ним.
const HINT_RECHECK_SEC: float = 0.25
## Радиусы подсказок — радиусы E у героя (Player.E_*): цель выбирает Player.interact_target.
## Трекер цели, обучение и выбор генератора пересчитываются так часто, с.
const STATE_RECHECK_SEC: float = 0.25
## Окно поиска «ближайшего» генератора вокруг игрока, клеток: по горизонтали —
## радиус ТЭЦ (8), по вертикали — уровень пола ±3 (генераторы стоят рядом с героем).
const POWER_SCAN_CELLS: int = 8
const POWER_SCAN_ROWS: int = 3
## Генератор под курсором выбирается, если он в досягаемости игрока (Player.REACH;
## сам класс Player здесь не трогаем — цикл зависимостей).
const CURSOR_GEN_REACH: float = 5.6 * 16.0
## Прямоугольник миникарты относительно правого верхнего угла.
const MAP_SIZE: Vector2i = Vector2i(186, 52)
const MAP_OFFSET: Vector2 = Vector2(200, 60)
## Длина ключа состояния (см. _fill_key). [46..61] — команда в сети (MP-J).
const KEY_LEN: int = 64

# ------------------------------------------------- ЦВЕТА (ADR-003 V6, «Споровый луг»)
## Палитра мира — DB.PAL (V1); здесь только её роли в HUD и цвета плашек концепта
## (ui_* — в DB.PAL их нет, это цвета интерфейса, а не мира).
const _PAL: Dictionary = preload("res://scripts/autoload/db.gd").PAL
const C_PLATE: Color = Color("#221A20D1")      ## тёмно-сливовая плашка (ui_bg, 82 %)
const C_PLATE_HI: Color = Color("#3A2E34")     ## ячейка хотбара, полоса суток (ui_panel)
const C_LINE: Color = Color("#EFE8D8")         ## текст и тонкие рамки (ui_line)
const C_HP: Color = Color("#E8743B")           ## здоровье — цвет скафандра по умолчанию
const C_BIO: Color = _PAL["bio"]               ## импульс, трекер цели, релей
const C_INTERACT: Color = _PAL["interact"]     ## «можно взаимодействовать» (§ 3.2)
const C_DANGER: Color = _PAL["danger"]         ## угроза: ночь, мало здоровья, вентиляции
const C_HAZARD: Color = _PAL["hazard"]         ## жёлтая разметка: мощность, обучение, солнце
const C_WARN: Color = _PAL["copper"]           ## перегруз/выключено (не угроза — не danger)
const C_FRAME: Color = _PAL["frame"]
## Миникарта: верх рельефа — лишайник, песок, порода средних пещер.
const C_MAP_TOP: Color = _PAL["s_top"]
const C_MAP_SAND: Color = _PAL["sand"]
const C_MAP_STONE: Color = _PAL["m_base"]
## Уголки-скобки опасности ночью: длина плеча и толщина, px; отступ от края.
const BRACKET_LEN: float = 22.0
const BRACKET_W: float = 3.0
const BRACKET_PAD: float = 4.0
## Рамка интерактива вокруг объекта: на сколько px шире клетки и толщина линии.
const MARK_GROW: float = 2.0
const MARK_W: float = 2.0

var player = null   ## Ссылка на игрока без статического типа (иначе цикл зависимостей).
var notes: Array = []          ## [{text, color, ttl}]
var damage_flash: float = 0.0
var panel_alpha: float = 0.0
## Текущая подсказка внизу экрана ("" — нет). Читают сценарии.
var hint_text: String = ""

# ------------------------------------------- ТЕКСТЫ ПОДСКАЗОК (читают сценарии)
const HINT_TERMINAL: String = "[E] — выполнить задание (удерживать)"
const HINT_TERMINAL_NO_POWER: String = "Терминал: нет питания — поставьте рядом ТЭЦ"
const HINT_BEACON: String = "[E] — активировать релей-ядро (удерживать)"
const HINT_CHEST: String = "[E] — открыть сундук"
const HINT_GEN_COAL: String = "[E] — загрузить уголь в ТЭЦ"
const HINT_GEN_SWITCH: String = "[E] — рубильник ТЭЦ (вкл/выкл) · уголь в руке + [E] — топка"
const HINT_SOLAR_SWITCH: String = "[E] — рубильник генератора (вкл/выкл)"
## Подсказка управления в начале забега: клавиатура и мышь / телефон (#149).
const CONTROLS_KEYS: Array = [
	"WASD — движение   SPACE — прыжок   SHIFT — бег   колесо / + − — зум",
	"ЛКМ — копать / бить   ПКМ — строить   E — взаимодействовать",
	"Q — импульс   V — вентиляция   I / TAB — инвентарь и крафт   1-0 — хотбар",
]
const CONTROLS_TOUCH: Array = [
	"Джойстик — идти, вверх — прыжок   » — бег   щипок — зум",
	"Тап к стене — копать / бить   блок в хотбаре — строить",
	"«меню» или «Назад» — пауза и сохранение   I — инвентарь",
]
const HINT_INSERTER: String = "ПКМ — повернуть манипулятор · [E] с предметом — фильтр"
const HINT_HIDING: String = "Вы в вентиляции. [V] — вылезть"
const HINT_REPAIR: String = "[E] — починить хламом (удерживать)"
const HINT_LOAD: String = "[E] — загрузить в постройку"

## Цепочка обучения: шаги по порядку, TUT_DONE — пройдена (строка скрыта).
enum Tut { DIG, CRAFT, PLACE, POWER, TERMINAL, DONE }
## Сколько хлама нужно на ТЭЦ (рецепт: 2 жел. пластины + 6 хлама, db.gd).
const TUT_SCRAP: int = 6

# ---------------------------------- ТРЕКЕР / ОБУЧЕНИЕ / МОЩНОСТЬ (читают сценарии)
## Этап цели, который показывает трекер (1..4).
var tracker_stage: int = 1
var tracker_title: String = ""
var tracker_detail: String = ""
## Глава кампании (ADR-004): задачи этапа после первой (она — в tracker_detail).
var mission_lines: Array[String] = []
## Шаг цепочки обучения (Tut) и его строка ("" — цепочка пройдена).
var tutorial_step: int = Tut.DIG
var tutorial_text: String = ""
## Секунд до ночи (целые, вверх) в сумерках; -1 — не сумерки.
var night_countdown: int = -1
## Генератор индикатора мощности (под курсором или ближайший), null — нет.
var power_gen = null
## Строка индикатора мощности ("" — индикатора нет).
var power_text: String = ""
## Что показывает индикатор: нагрузка и выход ×10, флаги (= ключ [42..44]).
var power_load_x10: int = 0
var power_out_x10: int = 0
var power_flags: int = 0
const POWER_ON: int = 1
const POWER_OVER: int = 2
const POWER_NO_FUEL: int = 4

# ---------------------------------------------- СЧЁТЧИКИ (для замеров)
## Время в _process и всех _draw слоёв HUD, мкс (tools/hud_probe.gd).
var stat_us: int = 0
var stat_frames: int = 0
## Сколько раз перерисованы слои: основной, миникарта, прицел.
var stat_redraws: int = 0
var stat_map_redraws: int = 0
var stat_map_bakes: int = 0
var stat_cross_redraws: int = 0
## Разбивка stat_us для hud_probe: миникарта (_update_map + слой) и подсказки,
## трекер, обучение, выбор генератора.
var stat_map_us: int = 0
var stat_hint_us: int = 0
## Сколько вентиляций и решёток нарисовано на миникарте в последний раз.
var stat_map_vents: int = 0
var stat_map_grates: int = 0
## Сколько раз сканировались клетки вокруг игрока в поисках генератора.
var stat_power_scans: int = 0
## Сколько раз перерисован слой рамки интерактива (ADR-003 § 3.2).
var stat_mark_redraws: int = 0
## Рамка интерактива на экране (пустая — объекта рядом нет). Читают сценарии.
var mark_rect: Rect2i = Rect2i()

# ------------------------------------------------------------ ВНУТРЕННЕЕ
var _cross: Control = null
var _map: Control = null
var _mark: Control = null
## Объект, с которым можно взаимодействовать (мировые px; пустой — нет).
var _hint_target: Rect2 = Rect2()
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
var _hint_cell: Vector2i = Vector2i(-1, -1)   ## клетка под курсором (подсказка зависит от неё)
var _state_t: float = 0.0
var _state_hash: int = 0
var _power_cursor: Vector2i = Vector2i(-9999, -9999)
var _power_near = null          # ближайший генератор по последнему сканированию
var _last_game_time: float = 0.0
var _vent_sig: int = -1
var _scan_cell: Vector2i = Vector2i(-9999, -9999)
var _scan_machines: int = -1
var _term_power: Dictionary = {}   # клетка терминала → под питанием (кэш на шаг)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_key.resize(KEY_LEN)
	_map = _make_layer(_draw_map_layer)
	_mark = _make_layer(_draw_mark_layer)
	_cross = _make_layer(_draw_cross_layer)
	_map_img = Image.create(MAP_SIZE.x, MAP_SIZE.y, false, Image.FORMAT_RGBA8)
	_map_tex = ImageTexture.create_from_image(_map_img)
	_fog_img = Image.create(MAP_SIZE.x, MAP_SIZE.y, false, Image.FORMAT_RGBA8)
	_fog_tex = ImageTexture.create_from_image(_fog_img)
	_fog_open.resize(MAP_SIZE.x * MAP_SIZE.y)
	World.explored_changed.connect(_on_explored)
	World.explored_reset.connect(_on_explored_reset)
	_on_explored_reset()
	# Смена этапа и браун-аут — пересчитать трекер/индикатор в этот же кадр.
	Game.objective_changed.connect(_on_state_signal)
	Game.brownout_changed.connect(_on_state_signal)
	# Копатель сломал решётку — сверить миникарту в этот же кадр.
	World.grate_broken.connect(_on_grate_broken)


func _on_grate_broken(_cell: Vector2i) -> void:
	_map_check_t = 0.0


func _on_state_signal(_v = null) -> void:
	_state_t = 0.0


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

	var th: int = Time.get_ticks_usec()
	_update_hint(delta)
	_update_state(delta)
	_update_mark()
	_update_team(delta)   # СЕТЬ (MP-J): товарищи и маячки
	stat_hint_us += Time.get_ticks_usec() - th

	# Основной слой: каждый кадр — пока идёт анимация (и ещё один кадр после неё),
	# иначе — только при смене ключа.
	var anim: bool = damage_flash > 0.0 or fading \
			or (Game.game_time < 22.0 and Game.game_time > 16.0)
	_fill_key()
	if anim or _animating or _key != _last_key:
		_last_key = _key.duplicate()
		queue_redraw()
	_animating = anim

	var tm: int = Time.get_ticks_usec()
	_update_map(delta)
	stat_map_us += Time.get_ticks_usec() - tm

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
	_key[38] = _state_hash
	night_countdown = _night_countdown()
	_key[39] = night_countdown
	_key[40] = 1 if Game.brownout else 0
	var g = power_gen
	if g != null and is_instance_valid(g):
		_key[41] = g.get_instance_id() & 0x7fffffff
		power_load_x10 = int(float(g.power_load) * 10.0)
		power_out_x10 = int(g.current_output() * 10.0)
		power_flags = (POWER_ON if g.enabled else 0) | (POWER_OVER if g.overloaded() else 0) 				| (POWER_NO_FUEL if _gen_no_fuel(g) else 0)
	else:
		_key[41] = 0
		power_load_x10 = 0
		power_out_x10 = 0
		power_flags = 0
	_key[42] = power_load_x10
	_key[43] = power_out_x10
	_key[44] = power_flags
	_key[45] = 1 if Game.is_night() else 0    # скобки опасности и метка суток (V6)
	_fill_team_key()   # СЕТЬ (MP-J): [46..61]
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
		_hint_target = Rect2()
		return
	var pos: Vector2 = player.global_position
	if _hint_t > 0.0 and pos.distance_squared_to(_hint_pos) < 0.25 \
			and World.machines.size() == _hint_machines and player.hiding == _hint_hiding \
			and player.building_cell == _hint_cell:
		return
	_hint_t = HINT_RECHECK_SEC
	_hint_pos = pos
	_hint_machines = World.machines.size()
	_hint_hiding = player.hiding
	_hint_cell = player.building_cell
	_set_hint(_compute_hint(pos))


func _set_hint(h: String) -> void:
	if h == hint_text:
		return
	hint_text = h
	_hint_hash = h.hash()


func _compute_hint(_pos: Vector2) -> String:
	_hint_target = Rect2()
	if player.hiding:
		return HINT_HIDING
	# Цель E выбирает сам герой (Player.interact_target, #116): подсказка и рамка
	# — у того объекта, который сработает по E (под курсором, иначе ближайший).
	# Питание терминалов — через кэш HUD (_terminal_powered).
	var tg: Dictionary = player.interact_target(_terminal_powered)
	if tg.is_empty():
		return ""
	# Виды цели — константы Player.ET_*, через экземпляр (класс Player здесь не
	# называем — цикл зависимостей).
	var kind: String = String(tg["kind"])
	if kind == player.ET_TERMINAL_OFF:
		return HINT_TERMINAL_NO_POWER   # без питания E не работает — и рамки нет
	_hint_target = _cell_rect(tg["cell"])
	if kind == player.ET_GENERATOR:
		return generator_hint(tg["node"])
	if kind == player.ET_TERMINAL:
		return HINT_TERMINAL
	if kind == player.ET_BEACON:
		return HINT_BEACON
	if kind == player.ET_INSERTER:
		return HINT_INSERTER
	if kind == player.ET_CHEST:
		return HINT_CHEST
	if kind == player.ET_REPAIR:
		return HINT_REPAIR
	if kind == player.ET_LOAD:
		return HINT_LOAD
	_hint_target = Rect2()
	return ""


## Клетка мира как прямоугольник в мировых px (для рамки интерактива).
static func _cell_rect(c: Vector2i) -> Rect2:
	return Rect2(Vector2(c * World.TILE), Vector2(World.TILE, World.TILE))


## Подсказка у терминала: без питания E не работает (#29) — так и пишем.
func terminal_hint(t: Vector2i) -> String:
	return HINT_TERMINAL if _terminal_powered(t) else HINT_TERMINAL_NO_POWER


## Под питанием ли терминал. Game.is_powered перебирает все генераторы мира,
## поэтому: ни одного работающего — сразу нет; иначе ответ кэшируется до
## следующего пересчёта состояния (STATE_RECHECK_SEC — тот же шаг, что у
## раскладки питания).
func _terminal_powered(t: Vector2i) -> bool:
	if Game.power_output_total <= 0.0:
		return false
	var v = _term_power.get(t)
	if v == null:
		v = Game.is_powered(World.cell_to_world(t))
		_term_power[t] = v
	return bool(v)


## Подсказка у генератора: ТЭЦ с углём в руке — топка, иначе — рубильник (#25).
func generator_hint(g) -> String:
	if g is CoalGen:
		if player != null and player.inv.selected_stack().id == IDs.I.COAL:
			return HINT_GEN_COAL
		return HINT_GEN_SWITCH
	return HINT_SOLAR_SWITCH


# ------------------------------------------------ ТРЕКЕР ЦЕЛИ, ОБУЧЕНИЕ, МОЩНОСТЬ

## Раз в STATE_RECHECK_SEC: трекер, шаг обучения, «ближайший» генератор.
## Генератор под курсором проверяется каждый кадр — одной выборкой из словаря.
func _update_state(delta: float) -> void:
	# Новый забег (перезапуск сцены): время игры пошло заново — обучение тоже.
	if Game.game_time < _last_game_time:
		tutorial_step = Tut.DIG
		_state_t = 0.0
	_last_game_time = Game.game_time
	_state_t -= delta
	var cursor_changed: bool = false
	if player != null and player.building_cell != _power_cursor:
		_power_cursor = player.building_cell
		cursor_changed = true
	if _state_t <= 0.0:
		_state_t = STATE_RECHECK_SEC
		_term_power.clear()
		_power_near = _scan_power_gen()
		_compute_tracker()
		_compute_tutorial()
		cursor_changed = true
	if cursor_changed:
		power_gen = _pick_power_gen()
		power_text = _power_line(power_gen)
		_state_hash = hash([tracker_title, tracker_detail, tutorial_text, power_text, mission_lines])


## Генератор под курсором (в досягаемости), иначе ближайший к игроку.
func _pick_power_gen():
	if player == null:
		return null
	var m = World.machines.get(_power_cursor)
	if m is Generator and is_instance_valid(m) \
			and m.global_position.distance_to(player.global_position) <= CURSOR_GEN_REACH:
		return m
	if _power_near != null and is_instance_valid(_power_near):
		return _power_near
	return null


## Ближайший к игроку генератор в прямоугольнике ±POWER_SCAN_CELLS клеток по
## горизонтали и ±POWER_SCAN_ROWS по вертикали — только клетки вокруг игрока,
## не все постройки мира. Пока игрок в той же клетке и число построек то же —
## прошлый ответ (сканирование — сотня выборок из словаря).
func _scan_power_gen():
	if player == null:
		return null
	var pos: Vector2 = player.global_position
	var pc: Vector2i = World.world_to_cell(pos)
	if pc == _scan_cell and World.machines.size() == _scan_machines 			and (_power_near == null or is_instance_valid(_power_near)):
		return _power_near
	_scan_cell = pc
	_scan_machines = World.machines.size()
	stat_power_scans += 1
	var r: int = POWER_SCAN_CELLS
	var best = null
	var best_d2: float = INF
	for dy in range(-POWER_SCAN_ROWS, POWER_SCAN_ROWS + 1):
		for dx in range(-r, r + 1):
			var m = World.machines.get(pc + Vector2i(dx, dy))
			if not (m is Generator) or not is_instance_valid(m):
				continue
			var d2: float = m.global_position.distance_squared_to(pos)
			if d2 < best_d2:
				best_d2 = d2
				best = m
	return best


static func _gen_no_fuel(g) -> bool:
	return g is CoalGen and g.enabled and float(g.fuel) <= 0.0


static func _gen_name(g) -> String:
	if g is CoalGen:
		return "ТЭЦ"
	if g is Solar:
		return "Солнечная панель"
	return "Генератор"


## Строка индикатора мощности (без чисел нагрузки — они рисуются из ключа).
func _power_line(g) -> String:
	if g == null or not is_instance_valid(g):
		return ""
	return _gen_name(g)


## Этап цели (#32: Game.objective_stage, названия — Game.OBJECTIVE_TITLES) и
## строка под ним. Этап 0 («ещё не пересчитан») показываем как первый. Отсчёт
## удержания — в строке под этапом (м:сс), поэтому заголовок без него.
func _compute_tracker() -> void:
	if Game.in_mission():
		_compute_mission()
		return
	mission_lines = []
	var st: int = clampi(Game.objective_stage, 1, Game.OBJECTIVE_STAGES)
	if Game.relay_active:
		st = Game.OBJECTIVE_STAGES
	tracker_stage = st
	tracker_title = "ЦЕЛЬ %d/%d: %s" % [st, Game.OBJECTIVE_STAGES, Game.OBJECTIVE_TITLES[st]]
	match st:
		1:
			var tot: int = 0
			var okc: int = 0
			for c in World.terminal_chapters:
				if int(World.terminal_chapters[c]) >= Lore.BASE_TERMINALS:
					continue      # главы 1–2 — терминалы базы, остальные — руины
				tot += 1
				if not World.terminals.has(c) or _terminal_powered(c):
					okc += 1
			tracker_detail = "терминалы базы под питанием %d/%d · данные %d" % [okc, tot, Game.research]
		2:
			var opened: int = 0
			var next: String = ""
			for n in Tech.ORDER:
				if n == "T0":
					continue
				if Tech.is_unlocked(n):
					opened += 1
				elif next == "":
					next = n
			if next == "":
				tracker_detail = "данные %d · все узлы открыты" % Game.research
			else:
				tracker_detail = "данные %d/%d · узлы %d/5 · следующий %s" % [
					Game.research, Tech.cost(next), opened, next]
		3:
			var have_all: int = 0
			var miss: String = ""
			for id in Game.relay_req:
				var need: int = int(Game.relay_req[id])
				var have: int = Game.relay_count(id) + (player.inv.count_of(id) if player != null else 0)   # + сдано в ядро (MP-I)
				if have >= need:
					have_all += 1
				elif miss == "":
					miss = " · %s %d/%d" % [DB.item_name(id), have, need]
			tracker_detail = "детали %d/%d%s · [E] у ядра" % [have_all, Game.relay_req.size(), miss]
		_:
			var left: int = int(ceil(Game.relay_timer))
			tracker_detail = "до эвакуации %d:%02d · %s" % [left / 60, left % 60,
					"СИГНАЛ БЕЗ ПРИСМОТРА" if Game.relay_unattended else "держитесь"]   # MP-I: зона удержания


## Глава кампании (ADR-004): «ГЛАВА n · НАЗВАНИЕ — этап k/N», задачи этапа строками
## «[+] текст» / «[ ] текст есть/нужно»; первая — в tracker_detail.
func _compute_mission() -> void:
	var m = Game.mission
	tracker_stage = int(m.stage) + 1
	tracker_title = "ГЛАВА %d · %s — %s %d/%d" % [int(m.chapter), String(m.title).to_upper(),
			String(m.stage_title), mini(int(m.stage) + 1, maxi(1, m.stages_total())), maxi(1, m.stages_total())]
	var lines: Array[String] = []
	for g in m.goals:
		var have: int = int(g["have"])
		var need: int = int(g["need"])
		var line: String = ("[+] " if have >= need else "[ ] ") + String(g["text"])
		if need > 1:
			line += " %d/%d" % [have, need]
		lines.append(line)
	tracker_detail = lines[0] if not lines.is_empty() else ""
	mission_lines = lines.slice(1)


## Шаг обучения: самый дальний выполненный признак (вперёд — сразу, назад — никогда).
## В главе кампании вместо цепочки — подсказка этапа (Mission.hint).
func _compute_tutorial() -> void:
	if Game.in_mission():
		tutorial_text = String(Game.mission.hint)
		return
	if tutorial_step == Tut.DONE:
		tutorial_text = ""
		return
	var lvl: int = Tut.DIG
	var scrap: int = 0
	if player != null:
		scrap = player.inv.count_of(IDs.I.SCRAP)
	if Game.tasks_done > 0 or Game.objective_stage >= 2:
		lvl = Tut.DONE
	elif _base_terminal_powered():
		lvl = Tut.TERMINAL
	elif Game.power_output_total > 0.0:
		lvl = Tut.POWER
	elif _power_near != null or (player != null and player.inv.count_of(IDs.I.COAL_GEN) > 0):
		lvl = Tut.PLACE
	elif scrap >= TUT_SCRAP:
		lvl = Tut.CRAFT
	tutorial_step = maxi(tutorial_step, lvl)
	var n: int = tutorial_step + 1
	match tutorial_step:
		Tut.DIG:
			tutorial_text = "%d/5 Копай: %s по земле — хлам %d/%d на ТЭЦ" % [n,
					"тап" if UI.touch_on else "ЛКМ", mini(scrap, TUT_SCRAP), TUT_SCRAP]
		Tut.CRAFT:
			tutorial_text = "%d/5 Крафт: I — «Угольная ТЭЦ»" % n
		Tut.PLACE:
			tutorial_text = ("%d/5 ТЭЦ: выбери в хотбаре, тап у терминала; [E] с углём — топка" if UI.touch_on
					else "%d/5 ТЭЦ: ПКМ — у терминала, [E] с углём — топка") % n
		Tut.POWER:
			tutorial_text = "%d/5 Питание: терминал вне зоны (P — радиус)" % n
		Tut.TERMINAL:
			tutorial_text = "%d/5 Терминал под питанием: держите [E]" % n
		_:
			tutorial_text = ""


## Под питанием ли хоть один терминал базы (главы 1–2) — обучение про них.
func _base_terminal_powered() -> bool:
	if Game.power_output_total <= 0.0:
		return false
	for t in World.terminals:
		var ch: int = int(World.terminal_chapters.get(t, -1))
		if ch >= 0 and ch < Lore.BASE_TERMINALS and _terminal_powered(t):
			return true
	return false


## Целых секунд до ночи (вверх) в сумерках, иначе -1.
func _night_countdown() -> int:
	if not Game.is_dusk():
		return -1
	return int(ceil((Balance.NIGHT_START - Game.time_of_day) * Balance.DAY_LENGTH))


# ------------------------------------------------------------ МИНИКАРТА

func _update_map(delta: float) -> void:
	_map_check_t -= delta
	if _map_check_t <= 0.0:
		_map_check_t = MAP_CHECK_SEC
		if _bake_map_if_changed():
			_map.queue_redraw()
		# Решётки ставит/снимает игрок (#31), копатель их ломает — сверка раз в
		# MAP_CHECK_SEC по ~15 вентиляциям.
		var vs: int = _vents_signature()
		if vs != _vent_sig:
			_vent_sig = vs
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
		var c: Color = C_MAP_TOP
		var tid: int = sig[px * 2 + 1]
		if tid == IDs.T.SAND:
			c = C_MAP_SAND
		elif tid == IDs.T.STONE:
			c = C_MAP_STONE
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
	c.draw_rect(r, C_PLATE)
	c.draw_texture(_map_tex, r.position)
	c.draw_texture(_fog_tex, r.position)
	c.draw_rect(r, Color(C_LINE, 0.25), false, 1.0)
	var sx: float = r.size.x / float(World.W)
	var sy: float = r.size.y / float(World.H)
	# Вентиляции и решётки (#31) — только под открытым туманом.
	var nv: int = 0
	var ng: int = 0
	for v in World.vents:
		if not map_explored_at(v):
			continue
		var vp: Vector2 = (r.position + Vector2((float(v.x) + 0.5) * sx, (float(v.y) + 0.5) * sy)).floor()
		if WorldFX.is_vent_sealed(v):
			ng += 1
			c.draw_rect(Rect2(vp - Vector2(2, 2), Vector2(5, 5)), C_FRAME)
			c.draw_rect(Rect2(vp - Vector2(2, 0), Vector2(5, 1)), C_PLATE_HI)
		else:
			# Открытая вентиляция — отсюда лезут фантомы: цвет угрозы.
			nv += 1
			c.draw_rect(Rect2(vp - Vector2(2, 2), Vector2(5, 5)), C_DANGER)
	stat_map_vents = nv
	stat_map_grates = ng
	# Релей
	var bp: Vector2 = r.position + Vector2(World.beacon_cell.x * sx, World.beacon_cell.y * sy)
	c.draw_rect(Rect2(bp - Vector2(3, 3), Vector2(6, 6)), C_BIO)
	# Маячки товарищей (MP-J, § 4.7): только по правилу — рядом или в зоне питания.
	for i in range(0, _team_dots.size(), 3):
		var tp: Vector2 = r.position + Vector2(_team_dots[i], _team_dots[i + 1])
		c.draw_rect(Rect2(tp - Vector2(2, 2), Vector2(5, 5)), C_PLATE)
		c.draw_rect(Rect2(tp - Vector2(1, 1), Vector2(3, 3)), Avatar.suit_color(_team_dots[i + 2]))
	# Игрок — квадрат цвета скафандра в светлой рамке
	if player:
		var pp: Vector2 = r.position + Vector2(_map_dot)
		c.draw_rect(Rect2(pp - Vector2(3, 3), Vector2(6, 6)), C_LINE)
		c.draw_rect(Rect2(pp - Vector2(2, 2), Vector2(4, 4)), C_HP)
	c.draw_string(ThemeDB.fallback_font, r.position + Vector2(4, 12), "КАРТА",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(C_LINE, 0.6))
	var dt: int = Time.get_ticks_usec() - t0
	stat_us += dt
	stat_map_us += dt


## Подпись состава вентиляций: число и какие запечатаны (битами по порядку).
func _vents_signature() -> int:
	var sig: int = World.vents.size()
	for i in World.vents.size():
		if WorldFX.is_vent_sealed(World.vents[i]):
			sig = sig * 31 + i + 1
	return sig


# ------------------------------------------------------------ ТУМАН НА МИНИКАРТЕ (#59)

## Клетка мира, по которой решается, открыт ли пиксель миникарты (центр пикселя).
func _map_cell(px: int, py: int) -> Vector2i:
	return Vector2i(mini(World.W - 1, int((float(px) + 0.5) * float(World.W) / float(MAP_SIZE.x))),
			mini(World.H - 1, int((float(py) + 0.5) * float(World.H) / float(MAP_SIZE.y))))


## Карта исследования заменена: всё чёрное, потом открываем по ней (после
## загрузки #37 — полный проход по пикселям, при новом мире карта ещё пуста).
func _on_explored_reset() -> void:
	_fog_img.fill(Color(C_PLATE, 1.0))   # туман — та же сливовая плашка, непрозрачная
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


# ------------------------------------------------------------ РАМКА ИНТЕРАКТИВА
## ADR-003 § 3.2: рамка цвета `interact` вокруг объекта, с которым сработает E,
## и клавиша «E» над ним. Отдельный слой: перерисовывается, только когда рамка
## сдвинулась на экране (камера/объект) или появилась/пропала, — основной слой
## и его ключ не трогает.

func _update_mark() -> void:
	var r: Rect2i = Rect2i()
	if _hint_target.size != Vector2.ZERO:
		var sr: Rect2 = get_viewport().get_canvas_transform() * _hint_target
		r = Rect2i(sr.position.round(), sr.size.round())
	if r != mark_rect:
		mark_rect = r
		_mark.queue_redraw()


func _draw_mark_layer() -> void:
	var t0: int = Time.get_ticks_usec()
	stat_mark_redraws += 1
	if mark_rect.size == Vector2i.ZERO:
		stat_us += Time.get_ticks_usec() - t0
		return
	var r: Rect2 = Rect2(mark_rect).grow(MARK_GROW)
	var w: float = MARK_W
	# Рамка — четыре полосы (не draw_rect с обводкой: углы остаются квадратными).
	_mark.draw_rect(Rect2(r.position, Vector2(r.size.x, w)), C_INTERACT)
	_mark.draw_rect(Rect2(r.position.x, r.end.y - w, r.size.x, w), C_INTERACT)
	_mark.draw_rect(Rect2(r.position, Vector2(w, r.size.y)), C_INTERACT)
	_mark.draw_rect(Rect2(r.end.x - w, r.position.y, w, r.size.y), C_INTERACT)
	# Клавиша «E»: сливовая плашка с жёлтой кромкой над объектом.
	var k: Rect2 = Rect2(roundf(r.get_center().x - 9.0), r.position.y - 24.0, 18.0, 18.0)
	_mark.draw_rect(k, C_PLATE)
	_mark.draw_rect(Rect2(k.position, Vector2(k.size.x, 2.0)), C_INTERACT)
	_mark.draw_string(ThemeDB.fallback_font, k.position + Vector2(0, 14), "E",
			HORIZONTAL_ALIGNMENT_CENTER, k.size.x, 13, C_INTERACT)
	stat_us += Time.get_ticks_usec() - t0


# ------------------------------------------------------------ ПРИЦЕЛ

func _draw_cross_layer() -> void:
	stat_cross_redraws += 1
	var mp: Vector2 = _mouse
	var cross: Color = Color(C_LINE, 0.75)
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
		draw_rect(Rect2(0, 0, w, h), Color(C_DANGER, damage_flash * 0.25))

	# ---- Здоровье ------------------------------------------------------------
	if player:
		var hp_rect: Rect2 = Rect2(14, 12, 210, 20)
		draw_rect(hp_rect, C_PLATE)
		var frac: float = clampf(player.hp / 100.0, 0.0, 1.0)
		# Здоровье — цвет скафандра; мало здоровья — цвет угрозы.
		var hp_col: Color = C_HP if frac > 0.35 else C_DANGER
		var hp_fill: Rect2 = Rect2(hp_rect.position + Vector2(2, 2), Vector2((hp_rect.size.x - 4) * frac, hp_rect.size.y - 4))
		draw_rect(hp_fill, hp_col)
		draw_rect(Rect2(hp_fill.position, Vector2(hp_fill.size.x, 2)), hp_col.lightened(0.3))
		draw_rect(hp_rect, Color(C_LINE, 0.35), false, 1.0)
		draw_string(font, hp_rect.position + Vector2(8, 15), "%d" % int(player.hp),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(C_LINE, 0.95))

		# Индикатор заряда импульса
		var emp_rect: Rect2 = Rect2(14, 38, 150, 8)
		draw_rect(emp_rect, C_PLATE)
		var ef: float = 1.0 - player.emp_cd / player.emp_max
		draw_rect(Rect2(emp_rect.position + Vector2(1, 1), Vector2((emp_rect.size.x - 2) * ef, emp_rect.size.y - 2)),
				C_BIO)
		draw_string(font, emp_rect.position + Vector2(156, 8), "ИМПУЛЬС [Q]",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(C_BIO, 0.85))

		# Трекер цели, мощность, обучение (#34)
		_draw_status_block(font)

	# ---- Время суток ---------------------------------------------------------
	# Полоса суток с квадратной меткой (ADR-003): днём метка жёлтая, ночью —
	# цвет угрозы. Метку ставим по квантованному времени — ровно тому, что в
	# ключе перерисовки.
	var strip: Rect2 = Rect2(w - 176, 36, 112, 4)
	draw_rect(strip.grow(1.0), C_PLATE)
	draw_rect(strip, C_PLATE_HI)
	var tq: float = float(int(Game.time_of_day * float(CLOCK_STEPS))) / float(CLOCK_STEPS)
	var mx: float = roundf(strip.position.x + tq * strip.size.x)
	var night: bool = Game.is_night()
	var dl: float = Game.daylight()
	var sun: Color = C_DANGER if night else C_PLATE_HI.lerp(C_HAZARD, 0.35 + 0.65 * dl)
	draw_rect(Rect2(mx - 4, 32, 8, 12), C_PLATE)
	draw_rect(Rect2(mx - 3, 33, 6, 10), sun)
	draw_string(font, Vector2(w - 176, 26), "Смена %d — %s" % [Game.day_number, Game.phase_name()],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_DANGER.lerp(C_LINE, 0.35) if night else C_LINE)

	# ---- Отсчёт до ночи (сумерки, § 4.1) -----------------------------------
	if night_countdown >= 0:
		var cd: String = "НОЧЬ ЧЕРЕЗ %d с" % night_countdown
		var cw: float = 240.0
		var cr: Rect2 = Rect2(w * 0.5 - cw * 0.5, 12, cw, 28)
		draw_rect(cr, C_PLATE)
		draw_rect(cr, Color(C_DANGER, 0.7), false, 1.0)
		# Последние 5 с — ярче, мигает раз в секунду (ключ — целые секунды).
		var hot: bool = night_countdown <= 5 and night_countdown % 2 == 1
		draw_string(font, cr.position + Vector2(0, 20), cd, HORIZONTAL_ALIGNMENT_CENTER, cw, 16,
				C_DANGER.lerp(C_LINE, 0.6) if hot else C_DANGER.lerp(C_LINE, 0.25))

	# ---- Команда в сети: товарищи и перекличка (MP-J) ---------------------
	_draw_team(font, w)

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
		draw_string(font, Vector2(size.x * 0.5 - 300, size.y - 116), hint_text,
				HORIZONTAL_ALIGNMENT_CENTER, 600, 15, Color(C_INTERACT, 0.95))

	# ---- Подсказка управления (затухает) ------------------------------------
	if Game.game_time < 22.0:
		var ta: float = clampf((22.0 - Game.game_time) / 6.0, 0.0, 1.0)
		var lines: Array = CONTROLS_TOUCH if UI.touch_on else CONTROLS_KEYS
		for i in lines.size():
			draw_string(font, Vector2(size.x * 0.5 - 260, size.y * 0.30 + i * 20), String(lines[i]),
					HORIZONTAL_ALIGNMENT_CENTER, 520, 14, Color(C_LINE, ta))

	# ---- Ночь: уголки-скобки опасности по краям (ADR-003 § 3.2) ------------
	# Опасность кодируется не только цветом: скобки видны и при дальтонизме.
	if night:
		_draw_brackets(w, h)
	stat_us += Time.get_ticks_usec() - t0


## Блок под здоровьем: трекер цели, мощность генератора, шаг обучения.
## Всё, что здесь рисуется, — в ключе: _state_hash (строки), [39..44] (числа).
func _draw_status_block(font: Font) -> void:
	var x: float = 14.0
	var y: float = 54.0
	# Трекер цели
	draw_rect(Rect2(x, y, 4, 34), C_BIO)
	_text_on_plate(font, Vector2(x + 10, y + 13), tracker_title, 13, C_BIO.lerp(C_LINE, 0.3))
	_text_on_plate(font, Vector2(x + 10, y + 30), tracker_detail, 12, Color(C_LINE, 0.95))
	y += 44.0
	if not mission_lines.is_empty():   # ADR-004: остальные задачи этапа
		draw_rect(Rect2(x, y - 10, 4, 16.0 * mission_lines.size()), C_BIO)
		for line in mission_lines:
			_text_on_plate(font, Vector2(x + 10, y + 2), line, 12, Color(C_LINE, 0.95))
			y += 16.0
		y += 4.0
	# Мощность: выбранный/ближайший генератор (§ 4.3)
	var g = power_gen
	if g != null and is_instance_valid(g):
		var out: float = g.current_output()
		var ld: float = float(g.power_load)
		var bar: Rect2 = Rect2(x, y + 8, 120, 7)
		draw_rect(bar, C_PLATE)
		var cap: float = maxf(out, 0.001)
		var frac: float = clampf(ld / cap, 0.0, 1.0) if out > 0.0 else (1.0 if ld > 0.0 else 0.0)
		var over: bool = g.overloaded()
		var col: Color = C_WARN if over else C_HAZARD
		draw_rect(Rect2(bar.position + Vector2(1, 1), Vector2((bar.size.x - 2) * frac, bar.size.y - 2)), col)
		draw_rect(bar, Color(C_LINE, 0.3), false, 1.0)
		var state: String = ""
		if not g.enabled:
			state = " · ВЫКЛ"
		elif _gen_no_fuel(g):
			state = " · нет угля"
		elif over:
			state = " · ПЕРЕГРУЗ"
		_text_on_plate(font, Vector2(x + 128, y + 15), "%s: нагрузка %.1f / выход %.1f%s" % [power_text, ld, out, state],
				12, C_WARN.lerp(C_LINE, 0.25) if (over or not g.enabled) else Color(C_HAZARD.lerp(C_LINE, 0.55), 0.95))
		y += 22.0
	elif Game.brownout:
		_text_on_plate(font, Vector2(x, y + 15), "ПЕРЕГРУЗ СЕТИ — станки замедлены", 12, C_WARN.lerp(C_LINE, 0.25))
		y += 22.0
	# Обучение: копай → крафт → ТЭЦ → питание → терминал
	if tutorial_text != "":
		_text_on_plate(font, Vector2(x, y + 14), ("» " if Game.in_mission() else "ОБУЧЕНИЕ ") + tutorial_text,
				13, C_HAZARD.lerp(C_LINE, 0.35))


## Тёмная подложка строк блока под здоровьем: днём жёлтый и белый текст терялся на
## светлом небе. Прямоугольник по ширине строки (квадратно, ADR-003) и тёмный контур букв.
const C_TEXT_BACK: Color = Color("#221A20B8")   ## та же сливовая плашка, что C_PLATE, прозрачнее


func _text_on_plate(font: Font, pos: Vector2, text: String, fsize: int, col: Color) -> void:
	if text == "":
		return
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	draw_rect(Rect2(pos.x - 5.0, pos.y - float(fsize) - 1.0, w + 10.0, float(fsize) + 6.0), C_TEXT_BACK)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 3, Color(0.0, 0.0, 0.0, 0.85))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


## Ячейка хотбара i (0…9) на экране. Ею же попадает тап по хотбару (TouchControls, #81).
func hotbar_slot_rect(i: int) -> Rect2:
	var slot: float = 46.0
	var x0: float = size.x * 0.5 - slot * 10.0 * 0.5
	return Rect2(x0 + i * slot, size.y - 74, slot - 4, slot - 4)


func _draw_hotbar(font: Font) -> void:
	var count: int = 10
	for i in count:
		var r: Rect2 = hotbar_slot_rect(i)
		var sel: bool = (player.inv.selected == i)
		draw_rect(r, C_PLATE)
		draw_rect(r.grow(-2.0), Color(C_PLATE_HI, 0.6))
		# Выбранный слот — та же рамка `interact`, что вокруг объектов (§ 3.2).
		if sel:
			draw_rect(r, C_INTERACT, false, 2.0)
		else:
			draw_rect(r, Color(C_LINE, 0.22), false, 1.0)
		var st: ItemStack = player.inv.get_slot(i)
		if not st.is_empty():
			var tex: ImageTexture = DB.item_texture(st.id)
			if tex:
				draw_texture_rect(tex, Rect2(r.position + Vector2(7, 7), Vector2(28, 28)), false)
			if st.count > 1:
				draw_string(font, r.position + Vector2(2, r.size.y - 4), str(st.count),
						HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 6, 12, Color(C_LINE, 0.95))
		draw_string(font, r.position + Vector2(3, 12), str((i + 1) % 10),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(C_INTERACT, 0.8) if sel else Color(C_LINE, 0.45))


## Уголки-скобки опасности в четырёх углах экрана (ночь). Квадратные L-плечи.
func _draw_brackets(w: float, h: float) -> void:
	var l: float = BRACKET_LEN
	var t: float = BRACKET_W
	var p: float = BRACKET_PAD
	for cx in 2:
		for cy in 2:
			var x: float = p if cx == 0 else w - p - l
			var y: float = p if cy == 0 else h - p - l
			var vx: float = p if cx == 0 else w - p - t
			var hy: float = p if cy == 0 else h - p - t
			draw_rect(Rect2(x, hy, l, t), C_DANGER)
			draw_rect(Rect2(vx, y, t, l), C_DANGER)


# ------------------------------------------------------------ СЕТЬ: КОМАНДА (ADR-002 § 4.7–4.8, MP-J #95)
## Список товарищей под миникартой (ник цветом скафандра, здоровье, огонёк
## переклички, «погиб»), строка переклички и маячки товарищей на миникарте.
## Маячок товарища — только если он ближе MP_TEAM_RADIO_TILES клеток к своему герою
## или в радиусе питания работающего генератора («маячок скафандра питается от сети
## базы»); двойника на карте нет никогда — он не герой. Состав и маячки — раз в
## STATE_RECHECK_SEC; в ключ — число товарищей, счётчик событий NetTeam, секунды
## переклички, подпись ников и по товарищу hp, флаги, вид. Без товарищей (одиночная
## игра) раздел не работает, ключ [46..61] — нули.

const TEAM_MAX: int = 3            ## товарищей на HUD (4 игрока — хост и 3 клиента)
const TEAM_ROW_H: float = 16.0
const TEAM_HEAD_H: float = 14.0

## Товарищи на HUD и чьи маячки сейчас на миникарте (Player без типа). Читают сценарии.
var team_mates: Array = []
var team_beacons: Array = []
## false — раздел выключен (замер «до» в mp_doppel).
var team_on: bool = true
var _team: Node = null              ## NetTeam (без типа — цикл зависимостей)
var _team_t: float = 0.0
var _team_nick_sig: int = 0
var _team_dots: PackedInt32Array = PackedInt32Array()       ## x, y (px миникарты), look
var _team_dots_new: PackedInt32Array = PackedInt32Array()


## Маячок этого товарища на миникарте по правилу § 4.7 (для сценариев).
func team_beacon_rule(h) -> bool:
	if h == null or not is_instance_valid(h) or h.dead or player == null:
		return false
	var pos: Vector2 = h.global_position
	return player.global_position.distance_to(pos) <= Balance.MP_TEAM_RADIO_TILES * World.TILE \
			or Game.is_powered(pos)


func _update_team(delta: float) -> void:
	if Game.players.size() <= 1 or not team_on:
		if not team_mates.is_empty() or not _team_dots.is_empty():
			team_mates.clear()
			team_beacons.clear()
			_team_dots.resize(0)
			_map.queue_redraw()
		return
	_team_t -= delta
	if _team_t > 0.0:
		return
	_team_t = STATE_RECHECK_SEC
	if _team == null or not is_instance_valid(_team):
		_team = get_tree().get_first_node_in_group("net_team")
	team_mates.clear()
	team_beacons.clear()
	_team_nick_sig = 0
	_team_dots_new.resize(0)
	for h in Game.players:
		if h == player or not is_instance_valid(h):
			continue
		if team_mates.size() < TEAM_MAX:
			team_mates.append(h)
			_team_nick_sig = (_team_nick_sig * 31 + String(h.nick).hash()) & 0x7fffffff
		if not team_beacon_rule(h):
			continue
		team_beacons.append(h)
		var c: Vector2i = World.world_to_cell(h.global_position)
		_team_dots_new.append(int(float(c.x * MAP_SIZE.x) / float(World.W)))
		_team_dots_new.append(int(float(c.y * MAP_SIZE.y) / float(World.H)))
		_team_dots_new.append(int(h.look))
	if _team_dots_new != _team_dots:
		_team_dots = _team_dots_new.duplicate()
		_map.queue_redraw()


func _fill_team_key() -> void:
	var n: int = team_mates.size()
	var tm: Node = _team if n > 0 and _team != null and is_instance_valid(_team) else null
	_key[46] = n
	_key[47] = int(tm.serial) if tm != null else 0
	_key[48] = ceili(float(tm.window_left)) if tm != null else 0
	_key[49] = _team_nick_sig if n > 0 else 0
	for i in TEAM_MAX:
		var b: int = 50 + i * 4
		var m = team_mates[i] if i < n else null
		if m == null or not is_instance_valid(m):
			_key[b] = 0
			_key[b + 1] = 0
			_key[b + 2] = 0
			_key[b + 3] = 0
			continue
		_key[b] = int(m.hp)
		_key[b + 1] = (1 if m.dead else 0) | (2 if m.rollcall_t > 0.0 else 0) | (4 if m.hiding else 0)
		_key[b + 2] = int(m.look)
		_key[b + 3] = m.get_instance_id() & 0x7fffffff


## Рамка плашки команды при ширине экрана w и n товарищах (её обходит и сенсорная
## раскладка, TouchControls._layout).
static func team_plate_rect(w: float, n: int) -> Rect2:
	return Rect2(w - MAP_OFFSET.x, MAP_OFFSET.y + MAP_SIZE.y + 6.0, MAP_SIZE.x,
			TEAM_HEAD_H + TEAM_ROW_H * n + 2.0)


## Плашка команды под миникартой. Всё, что здесь рисуется, — в ключе [46..61].
func _draw_team(font: Font, w: float) -> void:
	var n: int = team_mates.size()
	if n == 0:
		return
	var plate: Rect2 = team_plate_rect(w, n)
	var x: float = plate.position.x
	var y: float = plate.position.y
	var win: int = _key[48]
	draw_rect(plate, C_PLATE)
	var head: String = "КОМАНДА" if win <= 0 else "ПЕРЕКЛИЧКА %d с · [G] — ответить" % win
	draw_string(font, Vector2(x + 4, y + 11), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			C_BIO if win > 0 else Color(C_LINE, 0.6))
	y += TEAM_HEAD_H
	for i in n:
		var m = team_mates[i]
		if not is_instance_valid(m):
			continue
		var ry: float = y + float(i) * TEAM_ROW_H
		var col: Color = Avatar.suit_color(int(m.look))
		draw_rect(Rect2(x + 4, ry + 3, 8, 8), C_LINE)
		draw_rect(Rect2(x + 5, ry + 4, 6, 6), col)
		draw_string(font, Vector2(x + 16, ry + 11), String(m.nick), HORIZONTAL_ALIGNMENT_LEFT, 90, 11,
				col.lightened(0.55))
		if m.dead:
			draw_string(font, Vector2(x + 110, ry + 11), "погиб", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_DANGER)
		else:
			var bar: Rect2 = Rect2(x + 110, ry + 5, 52, 4)
			var f: float = clampf(float(m.hp) / 100.0, 0.0, 1.0)
			draw_rect(bar, C_PLATE_HI)
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), C_HP if f > 0.35 else C_DANGER)
		# Огонёк переклички: зелёный — ответил, красный — идёт перекличка без ответа.
		if not m.dead and float(m.rollcall_t) > 0.0:
			draw_rect(Rect2(x + 170, ry + 4, 6, 6), Avatar.ROLLCALL_GREEN)
		elif not m.dead and win > 0:
			draw_rect(Rect2(x + 170, ry + 4, 6, 6), Avatar.ROLLCALL_RED)
