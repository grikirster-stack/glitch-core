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
## Прямоугольник миникарты: слева от правого края и сверху (логические px слоя UI).
const MAP_SIZE: Vector2i = Vector2i(186, 52)
const MAP_OFFSET: Vector2 = Vector2(194, 46)
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
## Разбор постройки: E удерживать — снять машину и вернуть предмет в рюкзак.
const HINT_DISMANTLE: String = "[E] (удерживать) — разобрать"
## Хвост подсказки: к своему действию E машины добавляется разбор.
const HINT_DISMANTLE_TAIL: String = " · удерживать [E] — разобрать"

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
## Доля удержания, нарисованная последний раз: перерисовываем рамку, только
## когда полоса заметно изменилась (иначе — перерисовка с текстом каждый кадр).
var _mark_progress: float = -1.0

# ------------------------------------------------------------ ВНУТРЕННЕЕ
var _cross: Control = null
var _tc: Node = null   ## TouchControls (без типа — цикл зависимостей)
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
## Клетка, которую копнёт ЛКМ (рамка), и клетка под курсором, которую копать нельзя (красный
## крест), в экранных px; пустой Rect2i — нет. Рисуются слоем прицела.
var _dig_rect: Rect2i = Rect2i()
var _deny_rect: Rect2i = Rect2i()
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
	_update_dig_aim()
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
	_ensure_layout()   # #159: раскладка сменилась (размер, тач-кнопки, строки) — перерисовать
	_key[62] = _lay_sig
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
		return HINT_INSERTER + _dismantle_tail(tg.get("node"))
	if kind == player.ET_CHEST:
		return HINT_CHEST
	if kind == player.ET_REPAIR:
		return HINT_REPAIR
	if kind == player.ET_LOAD:
		return HINT_LOAD
	if kind == player.ET_DISMANTLE:
		return "%s: %s" % [HINT_DISMANTLE, DB.item_name(int(tg.get("item", 0)))]
	_hint_target = Rect2()
	return ""


## Хвост подсказки про разбор — только если постройку и правда можно снять.
func _dismantle_tail(m) -> String:
	if m == null or not is_instance_valid(m):
		return ""
	if bool(m.permanent):
		return ""
	return HINT_DISMANTLE_TAIL


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
## Хвост про разбор — если генератор не кампанийный.
func generator_hint(g) -> String:
	if g is CoalGen:
		if player != null and player.inv.selected_stack().id == IDs.I.COAL:
			return HINT_GEN_COAL
		return HINT_GEN_SWITCH + _dismantle_tail(g)
	return HINT_SOLAR_SWITCH + _dismantle_tail(g)


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
	# После сигнала новой цели нет (ADR-005 § 6.4): карточка считает смены.
	if Game.signal_sent and not Game.relay_active:
		tracker_stage = Game.day_number
		tracker_title = "Смена %d · Сигнал отправлен" % Game.day_number
		tracker_detail = "ночь идёт своим чередом"
		return
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
	c.draw_string(ThemeDB.fallback_font, r.position + Vector2(4, 15), "КАРТА",
			HORIZONTAL_ALIGNMENT_LEFT, -1, UI.FONT["small"], Color(C_LINE, 0.6))
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
	var pr: float = _interact_progress()
	if r != mark_rect:
		mark_rect = r
		_mark_progress = pr
		_mark.queue_redraw()
	elif absf(pr - _mark_progress) > 0.03:
		# Плашка «E» наполняется при удержании (разбор постройки): слой
		# перерисовываем, только когда полоса изменилась заметно — перерисовка
		# каждый кадр (с текстом!) съедала бы кадр хоста.
		_mark_progress = pr
		if mark_rect.size != Vector2i.ZERO:
			_mark.queue_redraw()


## Доля удержания E (0..1): разбор постройки или чтение терминала.
func _interact_progress() -> float:
	if player == null:
		return 0.0
	return clampf(float(player.task_progress), 0.0, 1.0)


func _draw_mark_layer() -> void:
	var t0: int = Time.get_ticks_usec()
	stat_mark_redraws += 1
	if mark_rect.size == Vector2i.ZERO:
		stat_us += Time.get_ticks_usec() - t0
		return
	var inv_s: float = 1.0 / UI.ui_scale   # рамка считается в px холста, слой рисует в логических
	var r: Rect2 = Rect2(Vector2(mark_rect.position) * inv_s, Vector2(mark_rect.size) * inv_s).grow(MARK_GROW)
	var w: float = MARK_W
	# Рамка — четыре полосы (не draw_rect с обводкой: углы остаются квадратными).
	_mark.draw_rect(Rect2(r.position, Vector2(r.size.x, w)), C_INTERACT)
	_mark.draw_rect(Rect2(r.position.x, r.end.y - w, r.size.x, w), C_INTERACT)
	_mark.draw_rect(Rect2(r.position, Vector2(w, r.size.y)), C_INTERACT)
	_mark.draw_rect(Rect2(r.end.x - w, r.position.y, w, r.size.y), C_INTERACT)
	# Клавиша «E»: сливовая плашка с жёлтой кромкой над объектом.
	var k: Rect2 = Rect2(roundf(r.get_center().x - 11.0), r.position.y - 28.0, 22.0, 22.0)
	_mark.draw_rect(k, C_PLATE)
	_mark.draw_rect(Rect2(k.position, Vector2(k.size.x, 2.0)), C_INTERACT)
	_mark.draw_string(ThemeDB.fallback_font, k.position + Vector2(0, 18), "E",
			HORIZONTAL_ALIGNMENT_CENTER, k.size.x, UI.FONT["body"], C_INTERACT)
	# Удержание E (разбор постройки): плашка наполняется бирюзовой полосой.
	var pr: float = _interact_progress()
	if pr > 0.0:
		_mark.draw_rect(Rect2(k.position + Vector2(1.0, k.size.y - 4.0),
				Vector2((k.size.x - 2.0) * pr, 3.0)), C_BIO)
	stat_us += Time.get_ticks_usec() - t0


# ------------------------------------------------------------ ПРИЦЕЛ

## Рамка цели копки и красный крест «сюда нельзя» (копка по лучу). На телефоне цель
## обводит TouchControls, поэтому здесь — только для мыши.
func _update_dig_aim() -> void:
	var dig: Rect2i = Rect2i()
	var deny: Rect2i = Rect2i()
	if player != null and not UI.touch_on:
		var xf: Transform2D = get_viewport().get_canvas_transform()
		if player.dig_cell.x >= 0:
			dig = _cell_screen_rect(xf, player.dig_cell)
		if player.dig_denied_t > 0.0 and player.dig_denied_cell.x >= 0:
			deny = _cell_screen_rect(xf, player.dig_denied_cell)
	if dig != _dig_rect or deny != _deny_rect:
		_dig_rect = dig
		_deny_rect = deny
		_cross.queue_redraw()


static func _cell_screen_rect(xf: Transform2D, c: Vector2i) -> Rect2i:
	var sr: Rect2 = xf * World.cell_rect(c)
	return Rect2i(sr.position.round(), sr.size.round())


func _draw_cross_layer() -> void:
	stat_cross_redraws += 1
	# Курсор и рамки — в px холста; слой рисует в логических, размер прицела не растёт с коэффициентом.
	var k: float = 1.0 / UI.ui_scale
	if _dig_rect.size != Vector2i.ZERO:
		var r: Rect2 = Rect2(Vector2(_dig_rect.position) * k, Vector2(_dig_rect.size) * k).grow(-1.0 * k)
		var w: float = 2.0 * k
		_cross.draw_rect(Rect2(r.position, Vector2(r.size.x, w)), C_HAZARD)
		_cross.draw_rect(Rect2(r.position.x, r.end.y - w, r.size.x, w), C_HAZARD)
		_cross.draw_rect(Rect2(r.position, Vector2(w, r.size.y)), C_HAZARD)
		_cross.draw_rect(Rect2(r.end.x - w, r.position.y, w, r.size.y), C_HAZARD)
	if _deny_rect.size != Vector2i.ZERO:
		var q: Rect2 = Rect2(Vector2(_deny_rect.position) * k, Vector2(_deny_rect.size) * k).grow(-3.0 * k)
		_cross.draw_line(q.position, q.end, C_DANGER, 3.0 * k)
		_cross.draw_line(Vector2(q.end.x, q.position.y), Vector2(q.position.x, q.end.y), C_DANGER, 3.0 * k)
	var mp: Vector2 = _mouse * k
	var cross: Color = Color(C_LINE, 0.75)
	_cross.draw_line(mp - Vector2(7, 0) * k, mp - Vector2(3, 0) * k, cross, 1.5 * k)
	_cross.draw_line(mp + Vector2(3, 0) * k, mp + Vector2(7, 0) * k, cross, 1.5 * k)
	_cross.draw_line(mp - Vector2(0, 7) * k, mp - Vector2(0, 3) * k, cross, 1.5 * k)
	_cross.draw_line(mp + Vector2(0, 3) * k, mp + Vector2(0, 7) * k, cross, 1.5 * k)


# ------------------------------------------------------------ РАСКЛАДКА (#159)
## Всё на экране считается в логических px слоя UI (size = холст / UI.ui_scale) одной
## функцией _compute_layout(): её же читают _draw и тест (layout_rects). Блоки сверху вниз:
## слева — здоровье, импульс, статус (трекер, обучение); справа — сутки, миникарта, команда;
## снизу по центру — хотбар, над ним подсказка и уведомления. Всё, что не помещается
## (низкие экраны при больших коэффициентах), отбрасывается строками по приоритету, а не
## налезает на соседей. На телефоне блоки обходят кнопки TouchControls.

## Поля экрана и шаг строк текста (FONT.body + плашка), px.
const PAD: float = 8.0
const ROW_H: float = 24.0
## Ширина полос здоровья и импульса, высота здоровья и импульса.
const HP_W: float = 160.0
const HP_H: float = 24.0
const EMP_H: float = 16.0
## Ширина полосы суток.
const STRIP_W: float = 112.0
## Ячейка хотбара: не больше SLOT_MAX, на телефоне (6 ячеек) — не меньше SLOT_TOUCH
## и не больше SLOT_TOUCH_MAX. Число ячеек — inv.hotbar_size, не константа (#161).
const SLOT_MAX: float = 46.0
## Потолок ячеек в пакете и в ключе HUD: рисуется hotbar_size, ключ держит все 10.
const SLOT_COUNT: int = 10
## На 6 ячейках шаг = min(42 × 10 / hotbar_size, 64) — ячейка крупнее 42 px (#161).
const SLOT_TOUCH: float = 42.0
const SLOT_TOUCH_MAX: float = 64.0
## Низ хотбара над краем холста, px.
const HOTBAR_BOTTOM: float = 32.0

var _lay: Dictionary = {}
var _lay_sig: int = -1

## Прямоугольники блоков HUD в логических px — для теста «ничего не наезжает»: здоровье, импульс,
## строки статуса (каждая — своя плашка), сутки, отсчёт до ночи, миникарта, команда, хотбар,
## подсказка, уведомления. Нет блока на экране — нет и его прямоугольника.
func layout_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	out.assign(layout_named().values())
	return out


## То же с именами блоков: «status0», «status1»… — строки статуса.
func layout_named() -> Dictionary:
	_ensure_layout()
	var out: Dictionary = {}
	for k in LAYOUT_RECTS:
		if k == "status":
			var rows: Array = _lay["rows"]
			for i in rows.size():
				out["status%d" % i] = Rect2(PAD, float(rows[i]["y"]), float(rows[i]["w"]) + 20.0, ROW_H)
		elif _lay.has(k):
			out[k] = _lay[k]
	return out


## Раскладка по имени блока (для сценариев): Rect2 или пустой Rect2.
func layout_rect(key: String) -> Rect2:
	_ensure_layout()
	return _lay.get(key, Rect2())


const LAYOUT_RECTS: Array = ["hp", "emp", "status", "day", "countdown", "map", "team", "hotbar",
		"hint", "notes"]


func _ensure_layout() -> void:
	var sig: int = _layout_sig()
	if sig != _lay_sig or _lay.is_empty():
		_lay_sig = sig
		_lay = _compute_layout()


## Сколько ячеек хотбара рисовать (#161). Героя ещё нет — 10, как у Inventory по умолчанию.
func _hotbar_count() -> int:
	if player == null or player.inv == null:
		return SLOT_COUNT
	return clampi(player.inv.hotbar_size, 1, SLOT_COUNT)


## Подпись входов раскладки: размер, коэффициент, строки, число уведомлений, состав команды,
## положение кнопок тач-управления, размер хотбара.
func _layout_sig() -> int:
	var tc: Node = _touch()
	var tsig: int = 0
	if tc != null:
		tsig = hash([tc.btn_center, tc.stick_center, tc.stick_radius])
	return hash([size, UI.ui_scale, _state_hash, _hint_hash, _note_serial, notes.size(),
			team_mates.size(), night_countdown, Game.day_number, Game.phase_name(), tsig,
			player != null, _hotbar_count(), Game.signal_sent])


## Узел TouchControls, если сенсорное управление включено (иначе null).
func _touch() -> Node:
	if not UI.touch_on:
		return null
	if _tc == null or not is_instance_valid(_tc):
		_tc = get_tree().get_first_node_in_group("touch_controls")
	return _tc


## Кнопки и джойстик TouchControls в логических px: id -> Rect2 (пусто — без тач-управления).
func _touch_rects() -> Dictionary:
	var out: Dictionary = {}
	var tc: Node = _touch()
	if tc == null:
		return out
	var k: float = 1.0 / UI.ui_scale
	for id in tc.btn_center:
		var c: Vector2 = tc.btn_center[id]
		var r: float = float(tc.btn_radius[id])
		out[id] = Rect2((c - Vector2(r, r)) * k, Vector2(r, r) * 2.0 * k)
	var sr: float = float(tc.stick_radius)
	out["stick"] = Rect2((tc.stick_center - Vector2(sr, sr)) * k, Vector2(sr, sr) * 2.0 * k)
	return out


## Ширина строки шрифтом fs (в логических px).
func _tw(text: String, fs: int) -> float:
	return ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


## Строка, обрезанная с «…» до ширины max_w.
func _fit_text(text: String, fs: int, max_w: float) -> String:
	if _tw(text, fs) <= max_w:
		return text
	var lo: int = 0
	var hi: int = text.length()
	while lo < hi:
		var mid: int = (lo + hi + 1) / 2
		if _tw(text.left(mid).strip_edges(false, true) + "…", fs) <= max_w:
			lo = mid
		else:
			hi = mid - 1
	return text.left(lo).strip_edges(false, true) + "…"


func day_label() -> String:
	var s: String = "Смена %d — %s" % [Game.day_number, Game.phase_name()]
	if Game.signal_sent:
		s += " · Сигнал отправлен"
	return s


## Правый столбец (миникарта, плашка команды) кончается на этой высоте при ширине w и n
## товарищах: под ним тач-раскладка ставит кнопки (TouchControls._layout).
static func right_column_bottom(w: float, n: int) -> float:
	if n > 0:
		return team_plate_rect(w, n).end.y
	return MAP_OFFSET.y + MAP_SIZE.y


func _compute_layout() -> Dictionary:
	var L: Dictionary = {}
	var w: float = size.x
	var h: float = size.y
	var fb: int = UI.FONT["body"]
	var fs: int = UI.FONT["small"]
	var tb: Dictionary = _touch_rects()
	# ---- Верх: здоровье, импульс (слева), сутки (справа), отсчёт до ночи (по центру).
	if player:
		L["hp"] = Rect2(PAD, 8.0, HP_W, HP_H)
		L["emp"] = Rect2(PAD, 8.0 + HP_H + 4.0, HP_W, EMP_H)
	var dw: float = maxf(_tw(day_label(), fs), STRIP_W)
	L["day"] = Rect2(w - PAD - dw, 6.0, dw, 34.0)
	if night_countdown >= 0:
		var cw: float = _tw("НОЧЬ ЧЕРЕЗ %d с" % night_countdown, fb) + 24.0
		L["countdown"] = Rect2((w - cw) * 0.5, 8.0, cw, 26.0)
	# ---- Правый столбец: миникарта, команда.
	L["map"] = Rect2(w - MAP_OFFSET.x, MAP_OFFSET.y, MAP_SIZE.x, MAP_SIZE.y)
	var n_team: int = team_mates.size()
	if n_team > 0:
		L["team"] = team_plate_rect(w, n_team)
	var right_bottom: float = right_column_bottom(w, n_team)
	# ---- Низ: хотбар по центру свободной полосы между джойстиком и кнопками справа.
	var lo: float = 0.0
	var hi: float = w
	if tb.has("stick") and tb.has("e"):
		lo = (tb["stick"] as Rect2).end.x + PAD
		hi = (tb["e"] as Rect2).position.x - PAD
	var n_slots: int = _hotbar_count()
	var slot_cap: float = SLOT_MAX
	# 6 ячеек — крупнее: min(42 × 10 / n, 64), и всё равно вписываемся в свободную полосу.
	if n_slots < SLOT_COUNT:
		slot_cap = minf(SLOT_TOUCH * float(SLOT_COUNT) / float(n_slots), SLOT_TOUCH_MAX)
	var slot: float = clampf(floorf((hi - lo) / float(n_slots)), 16.0, slot_cap)
	var hb_w: float = slot * float(n_slots) - 4.0
	var hx: float = clampf(w * 0.5 - hb_w * 0.5, lo, maxf(lo, hi - hb_w))
	var hy: float = h - HOTBAR_BOTTOM - (slot - 4.0)
	L["slot"] = slot
	L["hotbar"] = Rect2(hx, hy, hb_w, slot - 4.0)
	var stack_top: float = hy
	if hint_text != "":
		var ht: String = _fit_text(hint_text, fb, minf(minf(w - 2.0 * PAD, 600.0), hi - lo) - 16.0)
		L["hint_text"] = ht
		var hw: float = _tw(ht, fb) + 16.0
		var h_lo: float = maxf(PAD, lo)
		var hcx: float = clampf(hx + hb_w * 0.5 - hw * 0.5, h_lo, maxf(h_lo, minf(w - PAD, hi) - hw))
		L["hint"] = Rect2(hcx, hy - 4.0 - ROW_H, hw, ROW_H)
		stack_top = hy - 4.0 - ROW_H
	# ---- Слева: статус. Не ниже подсказки и кнопки «копать» (над джойстиком). Есть
	# уведомление — статус оставляет ему строку: на низких экранах уступает он, а не оно.
	var s_limit: float = stack_top - 4.0
	if not notes.is_empty():
		s_limit -= ROW_H
	if tb.has("build"):
		s_limit = minf(s_limit, (tb["build"] as Rect2).position.y - 4.0)
	var blockers: Array = [L["map"]]
	if L.has("team"):
		blockers.append(L["team"])
	blockers.append_array(tb.values())
	var rows: Array = _status_rows()
	var y0: float = 8.0 + HP_H + 4.0 + EMP_H + 6.0 if player else 8.0
	var s_bottom: float = _status_place(rows, y0, s_limit, blockers)
	L["rows"] = rows
	if not rows.is_empty():
		var sw: float = 0.0
		for r in rows:
			sw = maxf(sw, float(r["w"]))
		L["status"] = Rect2(PAD, y0, sw + 20.0, s_bottom - y0)
	# ---- Уведомления: над подсказкой и нижним рядом кнопок, под статусом и правым столбцом.
	# Два варианта: у правого края (под миникартой и колонкой кнопок) и левее колонки кнопок
	# (на низких экранах) — берём тот, куда влезает больше строк. Джойстик и «копать» обходятся.
	var n_bottom: float = stack_top - 4.0
	var rows_end: float = s_bottom if not rows.is_empty() else 0.0
	for id in tb:
		if id == "e" or id == "run" or id == "jump":
			n_bottom = minf(n_bottom, (tb[id] as Rect2).position.y - 4.0)
	var top_a: float = maxf(right_bottom, rows_end) + 4.0
	var top_b: float = rows_end + 4.0
	var x_b: float = w - PAD
	for id in tb:
		var b: Rect2 = tb[id]
		if id == "e" or id == "run" or id == "jump" or id == "stick" or id == "build":
			continue
		if b.position.y < n_bottom:
			if b.end.x > w - PAD - 240.0:
				top_a = maxf(top_a, b.end.y + 4.0)
			if b.end.y > top_b:
				x_b = minf(x_b, b.position.x - PAD)
	if x_b > (L["map"] as Rect2).position.x - PAD:
		top_b = maxf(top_b, right_bottom + 4.0)
	var n_right: float = w - PAD
	var n_top: float = top_a
	var n_left: float = PAD
	var best_fit: int = -1
	for opt in [[w - PAD, top_a], [x_b, top_b]]:
		var xr: float = opt[0]
		var tp: float = opt[1]
		var xl: float = PAD
		for id in ["stick", "build"]:
			if tb.has(id):
				var lb: Rect2 = tb[id]
				if lb.end.y > tp and lb.position.y < n_bottom:
					xl = maxf(xl, lb.end.x + PAD)
		var ft: int = int(floorf((n_bottom - tp) / ROW_H)) if xr - xl >= 120.0 else 0
		if ft > best_fit:
			best_fit = ft
			n_right = xr
			n_top = tp
			n_left = xl
	var cnt: int = clampi(mini(notes.size(), maxi(best_fit, 0)), 0, notes.size())
	var nw: float = 0.0
	var lines: Array = []
	for i in cnt:
		var nt: Dictionary = notes[notes.size() - 1 - i]   # свежие внизу
		var txt: String = _fit_text(String(nt["text"]), fb, minf(n_right - n_left, 620.0))
		lines.append(txt)
		nw = maxf(nw, _tw(txt, fb))
	if cnt > 0:
		L["notes"] = Rect2(n_right - nw, n_bottom - float(cnt) * ROW_H, nw, float(cnt) * ROW_H)
		L["note_lines"] = lines
	return L


## Строки блока под здоровьем: {text, kind, prio, color, w}. prio — порядок отбрасывания при
## нехватке места (больше — раньше). Трекер и подсказка шага обучения — главное.
func _status_rows() -> Array:
	var fb: int = UI.FONT["body"]
	var rows: Array = []
	if tracker_title != "":
		rows.append({"text": tracker_title, "kind": "title", "prio": 0,
				"color": C_BIO.lerp(C_LINE, 0.3)})
	if tracker_detail != "":
		rows.append({"text": tracker_detail, "kind": "detail", "prio": 0, "color": Color(C_LINE, 0.95)})
	if tutorial_text != "":
		rows.append({"text": ("» " if Game.in_mission() else "ОБУЧЕНИЕ ") + tutorial_text,
				"kind": "tutorial", "prio": 1, "color": C_HAZARD.lerp(C_LINE, 0.35)})
	var g = power_gen
	if g != null and is_instance_valid(g):
		var out: float = g.current_output()
		var ld: float = float(g.power_load)
		var state: String = ""
		if not g.enabled:
			state = " · ВЫКЛ"
		elif _gen_no_fuel(g):
			state = " · нет угля"
		elif g.overloaded():
			state = " · ПЕРЕГРУЗ"
		var warn: bool = g.overloaded() or not g.enabled
		rows.append({"text": "%s: нагрузка %.1f / выход %.1f%s" % [power_text, ld, out, state],
				"kind": "power", "prio": 2, "gen": g, "load": ld, "out": out,
				"color": C_WARN.lerp(C_LINE, 0.25) if warn else Color(C_HAZARD.lerp(C_LINE, 0.55), 0.95)})
	elif Game.brownout:
		rows.append({"text": "ПЕРЕГРУЗ СЕТИ — станки замедлены", "kind": "brownout", "prio": 2,
				"color": C_WARN.lerp(C_LINE, 0.25)})
	for line in mission_lines:
		rows.append({"text": line, "kind": "mission", "prio": 3, "color": Color(C_LINE, 0.95)})
	for r in rows:
		r["full"] = r["text"]   # полный текст: обрезается заново под свободную ширину (_status_place)
	return rows


## Ширина полосы нагрузки в строке мощности (с зазором), px.
const STATUS_BAR_W: float = 128.0


## Расставить строки от y0 вниз. Строка обрезается «…» до свободной ширины между левым краем
## и ближайшим блоком справа на её высоте (blockers: миникарта, плашка команды, тач-кнопки);
## места нет — строка отбрасывается. Не влезает до limit — отбрасываются самые «дальние»
## по prio. Возвращает низ блока.
func _status_place(rows: Array, y0: float, limit: float, blockers: Array) -> float:
	var fb: int = UI.FONT["body"]
	var y: float = y0
	while true:
		y = y0
		var kept: Array = []
		for r in rows:
			var bar: float = STATUS_BAR_W if r["kind"] == "power" else 0.0
			var avail: float = size.x - 2.0 * PAD - 20.0
			for b in blockers:
				var br: Rect2 = b
				if br.position.x > PAD + 40.0 and br.position.y < y + ROW_H and br.end.y > y:
					avail = minf(avail, br.position.x - 2.0 * PAD - 20.0)
			if avail - bar < 96.0:
				continue   # справа кнопка вплотную: строка не поместится
			r["text"] = _fit_text(String(r["full"]), fb, avail - bar)
			r["w"] = _tw(String(r["text"]), fb) + bar
			r["y"] = y
			y += ROW_H
			kept.append(r)
		rows.assign(kept)
		if rows.is_empty() or y <= limit:
			break
		var worst: int = 0
		for i in rows.size():
			if int(rows[i]["prio"]) >= int(rows[worst]["prio"]):
				worst = i
		rows.remove_at(worst)
	return y


# ------------------------------------------------------------ ОСНОВНОЙ СЛОЙ

func _draw() -> void:
	var t0: int = Time.get_ticks_usec()
	stat_redraws += 1
	_ensure_layout()
	var w: float = size.x
	var h: float = size.y
	var font: Font = ThemeDB.fallback_font
	var fb: int = UI.FONT["body"]
	var fs: int = UI.FONT["small"]

	if damage_flash > 0.0:
		draw_rect(Rect2(0, 0, w, h), Color(C_DANGER, damage_flash * 0.25))

	# ---- Здоровье ------------------------------------------------------------
	if player:
		var hp_rect: Rect2 = _lay["hp"]
		draw_rect(hp_rect, C_PLATE)
		var frac: float = clampf(player.hp / 100.0, 0.0, 1.0)
		# Здоровье — цвет скафандра; мало здоровья — цвет угрозы.
		var hp_col: Color = C_HP if frac > 0.35 else C_DANGER
		var hp_fill: Rect2 = Rect2(hp_rect.position + Vector2(2, 2), Vector2((hp_rect.size.x - 4) * frac, hp_rect.size.y - 4))
		draw_rect(hp_fill, hp_col)
		draw_rect(Rect2(hp_fill.position, Vector2(hp_fill.size.x, 2)), hp_col.lightened(0.3))
		draw_rect(hp_rect, Color(C_LINE, 0.35), false, 1.0)
		_text_outlined(font, hp_rect.position + Vector2(8, 19), "%d" % int(player.hp), fb, Color(C_LINE, 0.95))

		# Индикатор заряда импульса: подпись — на самой полосе.
		var emp_rect: Rect2 = _lay["emp"]
		draw_rect(emp_rect, C_PLATE)
		var ef: float = 1.0 - player.emp_cd / player.emp_max
		draw_rect(Rect2(emp_rect.position + Vector2(1, 1), Vector2((emp_rect.size.x - 2) * ef, emp_rect.size.y - 2)),
				Color(C_BIO, 0.55))
		_text_outlined(font, emp_rect.position + Vector2(6, 13), "ИМПУЛЬС [Q]", fs, Color(C_LINE, 0.95))

		# Трекер цели, мощность, обучение (#34)
		_draw_status_block(font)

	# ---- Время суток ---------------------------------------------------------
	# Полоса суток с квадратной меткой (ADR-003): днём метка жёлтая, ночью —
	# цвет угрозы. Метку ставим по квантованному времени — ровно тому, что в
	# ключе перерисовки.
	var day: Rect2 = _lay["day"]
	var strip: Rect2 = Rect2(day.end.x - STRIP_W, 30.0, STRIP_W, 4)
	draw_rect(strip.grow(1.0), C_PLATE)
	draw_rect(strip, C_PLATE_HI)
	var tq: float = float(int(Game.time_of_day * float(CLOCK_STEPS))) / float(CLOCK_STEPS)
	var mx: float = roundf(strip.position.x + tq * strip.size.x)
	var night: bool = Game.is_night()
	var dl: float = Game.daylight()
	var sun: Color = C_DANGER if night else C_PLATE_HI.lerp(C_HAZARD, 0.35 + 0.65 * dl)
	draw_rect(Rect2(mx - 4, 26, 8, 12), C_PLATE)
	draw_rect(Rect2(mx - 3, 27, 6, 10), sun)
	_text_outlined(font, Vector2(day.end.x - _tw(day_label(), fs), 21.0), day_label(), fs,
			C_DANGER.lerp(C_LINE, 0.35) if night else C_LINE)

	# ---- Отсчёт до ночи (сумерки, § 4.1) -----------------------------------
	if _lay.has("countdown"):
		var cr: Rect2 = _lay["countdown"]
		draw_rect(cr, C_PLATE)
		draw_rect(cr, Color(C_DANGER, 0.7), false, 1.0)
		# Последние 5 с — ярче, мигает раз в секунду (ключ — целые секунды).
		var hot: bool = night_countdown <= 5 and night_countdown % 2 == 1
		draw_string(font, cr.position + Vector2(0, 19), "НОЧЬ ЧЕРЕЗ %d с" % night_countdown,
				HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, fb,
				C_DANGER.lerp(C_LINE, 0.6) if hot else C_DANGER.lerp(C_LINE, 0.25))

	# ---- Команда в сети: товарищи и перекличка (MP-J) ---------------------
	_draw_team(font, w)

	# ---- Уведомления --------------------------------------------------------
	if _lay.has("notes"):
		var nr: Rect2 = _lay["notes"]
		var lines: Array = _lay["note_lines"]
		var y: float = nr.end.y - 6.0
		for i in lines.size():
			var n: Dictionary = notes[notes.size() - 1 - i]
			var a: float = clampf(float(n["ttl"]) / 1.5, 0.0, 1.0)
			var tw: float = _tw(String(lines[i]), fb)
			_text_outlined(font, Vector2(nr.end.x - tw, y), String(lines[i]), fb,
					Color(n["color"].r, n["color"].g, n["color"].b, a))
			y -= ROW_H

	# ---- Хотбар --------------------------------------------------------------
	if player:
		_draw_hotbar(font)

	# ---- Подсказки -----------------------------------------------------------
	if _lay.has("hint"):
		var hr: Rect2 = _lay["hint"]
		draw_rect(hr, C_PLATE)
		draw_string(font, hr.position + Vector2(8, 18), String(_lay["hint_text"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, fb, Color(C_INTERACT, 0.95))

	# ---- Подсказка управления (затухает) ------------------------------------
	if Game.game_time < 22.0:
		var ta: float = clampf((22.0 - Game.game_time) / 6.0, 0.0, 1.0)
		var lines: Array = CONTROLS_TOUCH if UI.touch_on else CONTROLS_KEYS
		var cw: float = minf(w - 2.0 * PAD, 640.0)
		var cy: float = size.y * 0.30
		for i in lines.size():
			var cl: String = _fit_text(String(lines[i]), fs, cw)
			_text_outlined(font, Vector2((w - _tw(cl, fs)) * 0.5, cy + i * 20), cl, fs, Color(C_LINE, ta))

	# ---- Ночь: уголки-скобки опасности по краям (ADR-003 § 3.2) ------------
	# Опасность кодируется не только цветом: скобки видны и при дальтонизме.
	if night:
		_draw_brackets(w, h)
	stat_us += Time.get_ticks_usec() - t0


## Блок под здоровьем: трекер цели, мощность генератора, шаг обучения (строки — из
## раскладки: что не влезло, уже отброшено).
## Всё, что здесь рисуется, — в ключе: _state_hash (строки), [39..44] (числа).
func _draw_status_block(font: Font) -> void:
	var rows: Array = _lay["rows"]
	var fb: int = UI.FONT["body"]
	var x: float = PAD
	var bar_y0: float = -1.0
	var bar_y1: float = 0.0
	for r in rows:
		var y: float = float(r["y"])
		var kind: String = String(r["kind"])
		if kind == "title" or kind == "detail":
			if bar_y0 < 0.0:
				bar_y0 = y
			bar_y1 = y + ROW_H
		var tx: float = x + 10.0
		if kind == "power":
			var g = r["gen"]
			var out: float = float(r["out"])
			var ld: float = float(r["load"])
			var bar: Rect2 = Rect2(tx, y + 9.0, 112.0, 7.0)
			draw_rect(bar, C_PLATE)
			var frac: float = clampf(ld / maxf(out, 0.001), 0.0, 1.0) if out > 0.0 else (1.0 if ld > 0.0 else 0.0)
			var col: Color = C_WARN if (is_instance_valid(g) and g.overloaded()) else C_HAZARD
			draw_rect(Rect2(bar.position + Vector2(1, 1), Vector2((bar.size.x - 2) * frac, bar.size.y - 2)), col)
			draw_rect(bar, Color(C_LINE, 0.3), false, 1.0)
			tx += STATUS_BAR_W
		_text_on_plate(font, Vector2(tx, y + 19.0), String(r["text"]), fb, r["color"])
	if bar_y0 >= 0.0:
		draw_rect(Rect2(x, bar_y0, 4, bar_y1 - bar_y0), C_BIO)


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


## Текст без плашки, с тёмным контуром (на светлом небе и тёмной шахте одинаково читается).
func _text_outlined(font: Font, pos: Vector2, text: String, fsize: int, col: Color) -> void:
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 3,
			Color(0.0, 0.0, 0.0, 0.85 * col.a))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


## Ячейка хотбара i в логических px слоя UI (то, что рисует HUD).
## i за пределом hotbar_size — пустой прямоугольник: тап мимо хотбара ничего не выбирает.
func hotbar_slot_logical(i: int) -> Rect2:
	_ensure_layout()
	if i < 0 or i >= _hotbar_count():
		return Rect2()
	var hb: Rect2 = _lay["hotbar"]
	var slot: float = float(_lay["slot"])
	return Rect2(hb.position.x + float(i) * slot, hb.position.y, slot - 4.0, slot - 4.0)


## Ячейка хотбара i на экране, px холста. Ею же попадает тап по хотбару
## (TouchControls, #81): касания приходят в px холста, а не слоя UI.
func hotbar_slot_rect(i: int) -> Rect2:
	var r: Rect2 = hotbar_slot_logical(i)
	return Rect2(r.position * UI.ui_scale, r.size * UI.ui_scale)


func _draw_hotbar(font: Font) -> void:
	var fs: int = UI.FONT["small"]
	for i in _hotbar_count():
		var r: Rect2 = hotbar_slot_logical(i)
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
				var isz: float = roundf(r.size.x * 0.66)
				draw_texture_rect(tex, Rect2(r.position + (r.size - Vector2(isz, isz)) * 0.5,
						Vector2(isz, isz)), false)
			if st.count > 1:
				_text_outlined(font, Vector2(r.end.x - _tw(str(st.count), fs) - 3.0, r.end.y - 4.0), str(st.count), fs,
						Color(C_LINE, 0.95))
		if r.size.x >= 36.0:   # в узкой ячейке номер налез бы на значок
			draw_string(font, r.position + Vector2(3, 13), str((i + 1) % 10),
					HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(C_INTERACT, 0.8) if sel else Color(C_LINE, 0.45))


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
const TEAM_ROW_H: float = 20.0
const TEAM_HEAD_H: float = 20.0

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
	var fs: int = UI.FONT["small"]
	var head: String = _fit_text("КОМАНДА" if win <= 0 else "ПЕРЕКЛИЧКА %d с · [G] — ответить" % win, fs, plate.size.x - 8.0)
	draw_string(font, Vector2(x + 4, y + 15), head, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			C_BIO if win > 0 else Color(C_LINE, 0.6))
	y += TEAM_HEAD_H
	for i in n:
		var m = team_mates[i]
		if not is_instance_valid(m):
			continue
		var ry: float = y + float(i) * TEAM_ROW_H
		var col: Color = Avatar.suit_color(int(m.look))
		draw_rect(Rect2(x + 4, ry + 5, 10, 10), C_LINE)
		draw_rect(Rect2(x + 5, ry + 6, 8, 8), col)
		draw_string(font, Vector2(x + 18, ry + 15), _fit_text(String(m.nick), fs, 76.0), HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				col.lightened(0.55))
		if m.dead:
			draw_string(font, Vector2(x + 98, ry + 15), "погиб", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, C_DANGER)
		else:
			var bar: Rect2 = Rect2(x + 98, ry + 8, 60, 5)
			var f: float = clampf(float(m.hp) / 100.0, 0.0, 1.0)
			draw_rect(bar, C_PLATE_HI)
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), C_HP if f > 0.35 else C_DANGER)
		# Огонёк переклички: зелёный — ответил, красный — идёт перекличка без ответа.
		if not m.dead and float(m.rollcall_t) > 0.0:
			draw_rect(Rect2(x + 168, ry + 6, 8, 8), Avatar.ROLLCALL_GREEN)
		elif not m.dead and win > 0:
			draw_rect(Rect2(x + 168, ry + 6, 8, 8), Avatar.ROLLCALL_RED)
