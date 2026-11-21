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
## Карточка «Сейчас», обучение и мощность (ADR-001 § 4.1, § 4.3, § 4.7; #34, #160):
##  * карточка этапа цели (Game.objective_stage, #32): одна невыполненная цель —
##    картинка, ≤ 6 слов, счётчик. Строки собираются раз в STATE_RECHECK_SEC
##    (и сразу по Game.objective_changed / brownout_changed), в ключ — хеш текста
##    и отдельно иконка, have/need, видимость маркера;
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
## [62] — подпись раскладки, [63..66] — карточка: иконка, have, need, маркер (#160).
const KEY_LEN: int = 67

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
const HINT_BEACON: String = "[E] — запустить ядро (удерживать 3 с)"
const HINT_CHEST: String = "[E] — открыть сундук"
const HINT_GEN_COAL: String = "[E] — загрузить уголь в ТЭЦ"
const HINT_GEN_SWITCH: String = "[E] — рубильник ТЭЦ (вкл/выкл) · уголь в руке + [E] — топка"
const HINT_BURNER_FUEL: String = "[E] — загрузить топливо в горелку"
const HINT_BURNER_SWITCH: String = "[E] — рубильник горелки (вкл/выкл) · топливо в руке + [E] — топка"
const HINT_ACCUMULATOR: String = "[E] — накопитель: копить / отдавать"
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
## Явный забор: свежий ЛКМ или короткий тап. Имя подставляется.
const HINT_PICKUP: String = "ЛКМ — забрать: %s"
const HINT_PICKUP_BURNER: String = "ЛКМ — забрать горелку · [E] — рубильник"
## После забора предмет в руке: куда его ставить.
const HINT_PLACE: String = "ЛКМ — поставить · ПКМ — снять выбор"
## Тач-плашка короче десктопа: точные строки, без хвоста « · ».
const TOUCH_PICKUP: String = "Тапни — забрать: %s"
const TOUCH_PICKUP_BURNER: String = "Тапни горелку — забрать"
const TOUCH_PLACE: String = "Тапни клетку — поставить"
const TOUCH_BURNER_FUEL: String = "Тапни — забрать · [E] — топка"
const TOUCH_BURNER_SWITCH: String = "Тапни горелку — забрать · [E] — рубильник"

## Одна строка в нижней плашке на телефоне, пока игрок не начал действовать.
## CONTROLS_TOUCH на экране больше не рисуется — три строки закрывали карточку.
const TOUCH_HINTS: Dictionary = {
	HINT_TERMINAL: "[E] — выполнить задание",
	HINT_TERMINAL_NO_POWER: "Терминал: нет питания — нужна ТЭЦ",
	HINT_BEACON: "[E] — запустить ядро",
	HINT_CHEST: "[E] — открыть сундук",
	HINT_GEN_COAL: "[E] — уголь в ТЭЦ",
	HINT_GEN_SWITCH: "[E] — рубильник ТЭЦ",
	HINT_BURNER_FUEL: TOUCH_BURNER_FUEL,
	HINT_BURNER_SWITCH: TOUCH_BURNER_SWITCH,
	HINT_PICKUP_BURNER: TOUCH_PICKUP_BURNER,
	HINT_PLACE: TOUCH_PLACE,
	HINT_ACCUMULATOR: "[E] — накопитель",
	HINT_SOLAR_SWITCH: "[E] — рубильник",
	HINT_INSERTER: "[E] — фильтр",
	HINT_HIDING: "[V] — вылезти",
	HINT_REPAIR: "[E] — починить",
	HINT_LOAD: "[E] — загрузить",
	HINT_SIREN: "[E] — сирену",
	HINT_LENS: "[E] — линзу",
}

const INTRO_LINES: Array = [
	"Джойстик — идти",
	"Тап — копать",
	"«меню» — пауза",
]
const INTRO_STEP: float = 5.0
const INTRO_TIME: float = 15.0
const HINT_INSERTER: String = "ПКМ — повернуть · [E] с предметом — фильтр"
const HINT_HIDING: String = "Вы в вентиляции. [V] — вылезть"
const HINT_REPAIR: String = "[E] — починить хламом (удерживать)"
const HINT_LOAD: String = "[E] — загрузить в постройку"
## Разбор постройки: E удерживать — снять машину и вернуть предмет в рюкзак.
const HINT_DISMANTLE: String = "[E] (удерживать) — разобрать"
## Хвост подсказки: к своему действию E машины добавляется разбор.
const HINT_DISMANTLE_TAIL: String = " · удерживать [E] — разобрать"
## Сирена (#172): не больше шести слов — ребёнок читает кнопку, не абзац.
const HINT_SIREN: String = "[E] — включить сирену"
const HINT_LENS: String = "[E] — вставить линзу"

## Цепочка обучения: шаги по порядку, TUT_DONE — пройдена (строка скрыта).
enum Tut { DIG, CRAFT, PLACE, POWER, TERMINAL, DONE }
## Сколько хлама нужно на ТЭЦ (рецепт: 2 жел. пластины + 6 хлама, db.gd).
const TUT_SCRAP: int = 6

# ---------------------------------- КАРТОЧКА «СЕЙЧАС» / ОБУЧЕНИЕ / МОЩНОСТЬ (читают сценарии)
## Этап цели (1..3). Старые поля трекера больше не рисуются — их читает замер сети.
var tracker_stage: int = 1
var tracker_title: String = ""
var tracker_detail: String = ""
## Глава кампании (ADR-004): остальные задачи этапа. Карточка их не перечисляет.
var mission_lines: Array[String] = []
## Карточка «Сейчас»: одна невыполненная цель. card_text — ≤ 6 слов; card_icon —
## IDs.I или −1 (пиктограмма этапа); card_at — мировая точка или INF.
var card_text: String = ""
var card_have: int = 0
var card_need: int = 0
var card_icon: int = -1
var card_at: Vector2 = Vector2.INF
## Подсказка-картинка главы 6: три смеси (R+G, G+B, R+B) под заголовком.
var card_mix: bool = false
## Маркер на экране: false — цели нет или она за кадром (тогда стрелка).
var card_mark_on: bool = false
## Камера показывает цель ещё столько секунд (клик по карточке).
var card_look_left: float = 0.0
## Куда вернуть камеру после показа цели (смещение от героя).
var _card_cam_back: Vector2 = Vector2.ZERO
var _card_looking: bool = false
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
## Сколько вентиляций, решёток и терминалов руин нарисовано на миникарте в последний раз.
## Терминал руины рисуется, только если его клетка уже открыта туманом.
var stat_map_vents: int = 0
var stat_map_grates: int = 0
var stat_map_terminals: int = 0
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
var _card_hit: Control = null   ## кликабельная карточка «Сейчас»
var _tc: Node = null   ## TouchControls (без типа — цикл зависимостей)
var _map: Control = null
var _mark: Control = null
## Рамка цели в мире (#211): CanvasLayer HUD не едет за камерой, а экранный
## прямоугольник, посчитанный в _process, отстаёт на кадр — сглаживание камеры
## пишет canvas transform после idle. Слой в мировых px двигает сам рендер.
var _world_mark: Node2D = null
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
## Клетка цели карточки и фаза мигания рамки (0/1).
var _card_cell: Vector2i = Vector2i(-9999, -9999)
var _card_blink: int = 0
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
## Клетка рамки интерактива в мировых px (то, что рисует _world_mark).
var _mark_world: Rect2 = Rect2()
var _state_t: float = 0.0
var _state_hash: int = 0
var _power_cursor: Vector2i = Vector2i(-9999, -9999)
var _power_near = null          # ближайший генератор по последнему сканированию
var _last_game_time: float = 0.0
var _vent_sig: int = -1
var _scan_cell: Vector2i = Vector2i(-9999, -9999)
var _scan_machines: int = -1
var _term_power: Dictionary = {}   # клетка терминала → под питанием (кэш на шаг)
## Вводное обучение на телефоне пройдено: игрок пошёл, копнул, построил или спрятался,
## либо прошло INTRO_TIME. На ПК не используется.
var _intro_done: bool = false
## Цвета, которые уже горели на маяке в этом забеге (бит = маска Beams).
## Маяк держит один цвет: текущее стекло — не память. Между забегами не живёт.
var _pharos_seen: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_key.resize(KEY_LEN)
	_map = _make_layer(_draw_map_layer)
	_mark = _make_layer(_draw_mark_layer)
	_world_mark = Node2D.new()
	# Выше построек, WorldFX (20) и тумана (30): рамка должна читаться на предмете.
	_world_mark.z_index = 40
	_world_mark.draw.connect(_draw_world_mark)
	# Слой HUD (CanvasLayer) рисует в экранных px и не следует за камерой.
	# Мировой узел кладём в корень вьюпорта: его трансформ — трансформ камеры.
	get_tree().root.add_child.call_deferred(_world_mark)
	tree_exiting.connect(_drop_world_mark)
	_cross = _make_layer(_draw_cross_layer)
	_card_hit = Control.new()
	_card_hit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_hit.gui_input.connect(_on_card_input)
	add_child(_card_hit)
	_map_img = Image.create(MAP_SIZE.x, MAP_SIZE.y, false, Image.FORMAT_RGBA8)
	_map_tex = ImageTexture.create_from_image(_map_img)
	_fog_img = Image.create(MAP_SIZE.x, MAP_SIZE.y, false, Image.FORMAT_RGBA8)
	_fog_tex = ImageTexture.create_from_image(_fog_img)
	_fog_open.resize(MAP_SIZE.x * MAP_SIZE.y)
	World.explored_changed.connect(_on_explored)
	World.explored_reset.connect(_on_explored_reset)
	_on_explored_reset()
	# Смена этапа — пересчитать карточку в этот же кадр.
	Game.objective_changed.connect(_on_state_signal)
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
	_update_intro()
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


func notify(text: String, color: Color, icon: int = 0) -> void:
	notes.append({"text": text, "color": color, "ttl": 5.0, "icon": icon})
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
	_key[7] = Game.blueprints.size()
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
	# Питания нет (#170): ключ [40..44] остаётся нулём, длина не сдвигается.
	_key[40] = 0
	power_gen = null
	power_text = ""
	power_load_x10 = 0
	power_out_x10 = 0
	power_flags = 0
	_key[41] = 0
	_key[42] = 0
	_key[43] = 0
	_key[44] = 0
	_key[45] = 1 if Game.is_night() else 0    # скобки опасности и метка суток (V6)
	# Карточка «Сейчас» (#160): иконка, счётчик и виден ли маркер. Текст — в _state_hash.
	_key[63] = card_icon + (100 if card_mix else 0)
	_key[64] = card_have
	_key[65] = card_need
	_key[66] = 1 if card_mark_on else (2 if card_at != Vector2.INF else 0)
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


## Копает или строит: нижняя плашка мешает и гаснет. Прятки — отдельная подсказка
## («[V] — вылезти»), плашку не прячут.
func _player_acting() -> bool:
	if player == null:
		return false
	# building_cell — клетка под прицелом каждый кадр, не «строит». Стройка — удержанный
	# ПКМ (_place_cd > 0), копание — mining_progress.
	return player.mining_progress > 0.0 or player._place_cd > 0.0


## Ввод крутится первые INTRO_TIME секунд, по одной строке. Шаг и прятки его
## не гасят: иначе игрок, который сразу пошёл, вводных строк не увидит.
## Копание и стройка тоже не гасят — плашка остаётся, строка просто сменяется.
func _update_intro() -> void:
	if _intro_done or not UI.touch_on:
		return
	if Game.game_time >= INTRO_TIME:
		_intro_done = true


## Индекс вводной строки (0 на ПК и когда ввод уже погас). В ключе раскладки — чтобы
## плашка сменилась, когда строка крутится.
func _intro_index() -> int:
	if not UI.touch_on or _intro_done or Game.game_time >= INTRO_TIME:
		return 0
	if INTRO_STEP <= 0.0:
		return 0
	return int(Game.game_time / INTRO_STEP) % INTRO_LINES.size()


## Строка вводного обучения для нижней плашки или "" — ввод погас.
func _intro_line() -> String:
	if not UI.touch_on or _intro_done or Game.game_time >= INTRO_TIME:
		return ""
	return String(INTRO_LINES[_intro_index()])


## Короткая подсказка телефона. hint_text не трогаем — его читают сценарии.
func _touch_hint(text: String) -> String:
	if text == "":
		return ""
	if TOUCH_HINTS.has(text):
		return String(TOUCH_HINTS[text])
	# «ЛКМ — забрать: Горелка» → «Тапни — забрать: Горелка». Хвост не отрезаем.
	if text.begins_with("ЛКМ — забрать: "):
		return "Тапни — забрать: " + text.substr("ЛКМ — забрать: ".length())
	var s: String = text
	# Разбор: «[E] (удерживать) — разобрать: предмет» → «[E] — разобрать: предмет».
	if s.begins_with(HINT_DISMANTLE):
		s = "[E] — разобрать" + s.substr(HINT_DISMANTLE.length())
	var cut: int = s.find(" · ")
	if cut >= 0:
		s = s.substr(0, cut)
	s = s.replace(" (удерживать 3 с)", "")
	s = s.replace(" (удерживать)", "")
	return s.strip_edges()


func _set_hint(h: String) -> void:
	if h == hint_text:
		return
	hint_text = h
	_hint_hash = h.hash()


func _compute_hint(_pos: Vector2) -> String:
	_hint_target = Rect2()
	if player.hiding:
		return HINT_HIDING
	# Предмет в руке и клетка под прицелом свободна — куда его ставить.
	var place: String = _place_hint()
	# Цель E выбирает сам герой (Player.interact_target, #116): подсказка и рамка
	# — у того объекта, который сработает по E (под курсором, иначе ближайший).
	# Питание терминалов — через кэш HUD (_terminal_powered).
	var tg: Dictionary = player.interact_target(_terminal_powered)
	if tg.is_empty():
		return place
	# Прицел не на этой машине, а предмет уже в руке: ставить важнее чужой горелки базы.
	if place != "" and tg.get("cell") != player.building_cell:
		_hint_target = Rect2()
		return place
	# Виды цели — константы Player.ET_*, через экземпляр (класс Player здесь не
	# называем — цикл зависимостей).
	var kind: String = String(tg["kind"])
	if kind == player.ET_TERMINAL_OFF:
		return HINT_TERMINAL
	_hint_target = _cell_rect(tg["cell"])
	if kind == player.ET_BURNER:
		return _pickup_or(burner_hint(tg["node"]), tg["node"])
	if kind == player.ET_ACCUMULATOR:
		return _pickup_or(HINT_ACCUMULATOR + _dismantle_tail(tg["node"]), tg["node"])
	if kind == player.ET_SIREN:
		return HINT_SIREN
	if kind == player.ET_LENS:
		return HINT_LENS
	if kind == player.ET_TERMINAL:
		return HINT_TERMINAL
	if kind == player.ET_BEACON:
		return HINT_BEACON
	if kind == player.ET_CHEST:
		return _pickup_or(HINT_CHEST, tg["node"])
	if kind == player.ET_REPAIR:
		return HINT_REPAIR
	if kind == player.ET_LOAD:
		return HINT_LOAD
	if kind == player.ET_DISMANTLE:
		return _pickup_line(tg["node"])
	_hint_target = Rect2()
	return place


## Подсказка забора, если машину можно снять. Иначе — обычное действие E.
func _pickup_or(fallback: String, m) -> String:
	if _can_show_pickup(m):
		return _pickup_line(m)
	return fallback


## Свою разбираемую машину можно забрать свежим ЛКМ (на тач — коротким тапом).
func _can_show_pickup(m) -> bool:
	if m == null or not is_instance_valid(m) or bool(m.permanent):
		return false
	if m is Chest and player != null and not player._chest_empty(m):
		return false
	return true


func _pickup_line(m) -> String:
	var name: String = DB.item_name(MachineBase.machine_item_id(String(m.kind)))
	if m is Burner:
		return HINT_PICKUP_BURNER
	return HINT_PICKUP % name


## Предмет в руке ставится: куда тапнуть или кликнуть. Пустая рука — пусто.
func _place_hint() -> String:
	if player == null:
		return ""
	var st: ItemStack = player.inv.selected_stack()
	if st.is_empty() or DB.item_place(st.id) == "":
		return ""
	var cell: Vector2i = player.building_cell
	if cell.x < 0 or not player.can_place_at(cell):
		return ""
	if World.cell_to_world(cell).distance_to(player.global_position) > Player.REACH:
		return ""
	return HINT_PLACE


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


## Подсказка у терминала. Питания нет (#170): терминал читается всегда.
func terminal_hint(_t: Vector2i) -> String:
	return HINT_TERMINAL


## Терминал доступен без ТЭЦ (#170). Кэш шага оставлен, чтобы не звать мир каждый кадр.
func _terminal_powered(_t: Vector2i) -> bool:
	return true


## Подсказка у горелки: топливо в руке — топка, пустая рука — рубильник (#164).
## Хвост про разбор — только если горелку можно снять (не постройка базы).
func burner_hint(b) -> String:
	if player != null and Balance.FUEL.has(player.inv.selected_stack().id):
		return HINT_BURNER_FUEL + _dismantle_tail(b)
	return HINT_BURNER_SWITCH + _dismantle_tail(b)


# ------------------------------------------------ ТРЕКЕР ЦЕЛИ, ОБУЧЕНИЕ, МОЩНОСТЬ

## Раз в STATE_RECHECK_SEC: трекер, шаг обучения, «ближайший» генератор.
## Генератор под курсором проверяется каждый кадр — одной выборкой из словаря.
func _update_state(delta: float) -> void:
	# Новый забег (перезапуск сцены): время игры пошло заново — обучение тоже.
	if Game.game_time < _last_game_time:
		tutorial_step = Tut.DIG
		_intro_done = false
		_state_t = 0.0
		_pharos_seen = 0
	_last_game_time = Game.game_time
	_state_t -= delta
	if _state_t <= 0.0:
		_state_t = STATE_RECHECK_SEC
		_compute_tracker()
		_compute_tutorial()
		_state_hash = hash([card_text, card_have, card_need, card_icon, card_at, card_mark_on,
				tutorial_text])
	_update_card_look(delta)
	_update_card_mark()


## Карточка «Сейчас» (#160): одна невыполненная цель. tracker_* заполняется тем же
## смыслом — его ещё читает замер сети, на экран он не идёт. Этап 0 показываем как первый.
func _compute_tracker() -> void:
	if Game.in_mission():
		_compute_mission()
		return
	mission_lines = []
	# После сигнала — одно следующее дело в этом забеге, не «ночь идёт».
	# Мета-прогресса между забегами нет (ADR-005 § 6.4). Пока ядро снова
	# удерживают, карточка остаётся «Держись у ядра».
	if Game.signal_sent and not Game.relay_active:
		_compute_after_signal()
		return
	var st: int = clampi(Game.objective_stage, 1, Game.OBJECTIVE_STAGES)
	if Game.relay_active:
		st = Game.OBJECTIVE_STAGES
	tracker_stage = st
	tracker_title = String(Game.OBJECTIVE_TITLES[st])
	var have: int = 0
	var need: int = 1
	var words: String = ""
	var icon: int = Game.objective_icon()
	match st:
		1:
			have = 0
			need = 1
			words = "Поставь горелку"
			tracker_detail = "камень и хлам · у базы"
		2:
			have = Game.stats_ore
			need = Balance.FREE_ORE_NEED
			words = "Накопай руды"
			tracker_detail = "руда %d/%d · хлам не считается" % [have, need]
		3:
			have = mini(Game.nights_survived, Balance.FREE_NIGHTS_NEED)
			need = Balance.FREE_NIGHTS_NEED
			words = "Переживи ночь"
			tracker_detail = "рассвет ещё не был"
		4:
			have = Game.core_arc_count()
			need = Game.arc_need_count()
			words = "Зажги шесть дуг"
			var miss: String = ", ".join(Game.core_missing_names())
			tracker_detail = "дуги %d/%d%s · белый не считается" % [have, need,
					(" · нет " + miss) if miss != "" else ""]
		5:
			have = Game.core_arc_count()
			need = Game.arc_need_count()
			words = "Запусти ядро"
			tracker_detail = "дуги готовы · [E] 3 с у ядра"
		_:
			var left: int = int(ceil(Game.relay_timer))
			have = maxi(0, int(Balance.RELAY_TIME) - left)
			need = int(Balance.RELAY_TIME)
			words = "Держись у ядра"
			tracker_detail = "до эвакуации %d:%02d" % [left / 60, left % 60]
	_set_card(words, have, need, icon, Game.objective_at())


## Глава кампании: карточка — первая невыполненная задача. Остальные не перечисляются.
func _compute_mission() -> void:
	var m = Game.mission
	tracker_stage = int(m.stage) + 1
	tracker_title = String(m.stage_title)
	var lines: Array[String] = []
	var open: Dictionary = {}
	for g in m.goals:
		var have: int = int(g["have"])
		var need: int = int(g["need"])
		var line: String = ("[+] " if have >= need else "[ ] ") + String(g["text"])
		if need > 1:
			line += " %d/%d" % [have, need]
		lines.append(line)
		if open.is_empty() and have < need:
			open = g
	tracker_detail = lines[0] if not lines.is_empty() else ""
	mission_lines = lines.slice(1)
	if open.is_empty() and not m.goals.is_empty():
		open = m.goals[0]
	if open.is_empty():
		_set_card("", 0, 0, -1, Vector2.INF)
		return
	_set_card(String(open["text"]), int(open["have"]), int(open["need"]),
			int(open.get("icon", -1)), open.get("at", Vector2.INF))
	# Глава «Радуга»: таблица смесей — три картинки, не слова клавиш.
	card_mix = String(open.get("text", "")) == "Зажги семь дуг"


## После сигнала: одно дело. Непрочитанный терминал (ближайший к герою,
## иначе к лагерю) важнее цвета маяка, которого ещё не было. Нет ни того,
## ни другого — честно про рассвет: часы сами смену не сменят.
func _compute_after_signal() -> void:
	tracker_stage = Game.day_number
	var term: Vector2i = _nearest_unread_terminal()
	if term.x >= 0:
		var left: int = World.terminals.size()
		# Счётчик — как у всех карточек: прочитано / всего, не remaining/remaining.
		var total: int = Game.tasks_done + left
		tracker_title = "Смена %d · Сигнал отправлен" % Game.day_number
		# Место не пишем: имя руины длинное, маркер и так ведёт к ближайшему.
		tracker_detail = "терминалов ещё %d" % left
		_set_card("Прочитай терминал", Game.tasks_done, maxi(total, 1), -1,
				World.cell_to_world(term))
		return
	var color: int = _unseen_pharos_color()
	if color > 0:
		var seen_n: int = _pharos_colors_count()
		var name: String = Beams.NAME[color] if color < Beams.NAME.size() else "?"
		tracker_title = "Смена %d · Сигнал отправлен" % Game.day_number
		tracker_detail = "цветов %d/7 · маяк держит один цвет" % seen_n
		_set_card("Зажги %s маяк" % name, seen_n, 7, IDs.I.PHAROS, _pharos_at())
		return
	tracker_title = "Смена %d · Сигнал отправлен" % Game.day_number
	tracker_detail = "рассвет сам не придёт"
	_set_card("Смени день", Game.day_number, 1, -1, Vector2.INF)


## Ближайший непрочитанный терминал. Прочитанные уже вычеркнуты из World.terminals.
## Героя нет — ближайший к лагерю. Нет ни одного — клетка (−1, −1).
func _nearest_unread_terminal() -> Vector2i:
	if World.terminals.is_empty():
		return Vector2i(-1, -1)
	var origin: Vector2 = World.cell_to_world(World.beacon_cell)
	if player != null and is_instance_valid(player):
		origin = player.global_position
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: float = INF
	for t in World.terminals:
		var d: float = World.cell_to_world(t).distance_squared_to(origin)
		if d < best_d:
			best_d = d
			best = t
	return best


## Цвета, которые уже горели на маяке в этом забеге (маска: бит = маска Beams).
## Текущее стекло дописывается в память: погас — цвет не забывается.
## Тёмное стекло (color == 0) в память не идёт.
func _pharos_colors_seen() -> int:
	for m in World.machines.values():
		if m == null or not is_instance_valid(m) or String(m.get("kind")) != "Pharos":
			continue
		if not bool(m.get("active")):
			continue
		var c: int = int(m.get("color")) & 7
		if c > 0:
			_pharos_seen |= 1 << c
	return _pharos_seen


## Сколько разных цветов уже было на маяках. Для счётчика карточки, не маска.
func _pharos_colors_count() -> int:
	var mask: int = _pharos_colors_seen()
	var n: int = 0
	while mask != 0:
		n += mask & 1
		mask >>= 1
	return n


## Первый цвет маяка, которого ещё не было: красный, зелёный, синий, потом смеси.
## 0 — все семь уже были (или маяка нет, тогда цвет не к чему вести).
func _unseen_pharos_color() -> int:
	var seen: int = _pharos_colors_seen()
	if seen == 0 and not _pharos_exists():
		return 0
	for c in [Beams.R, Beams.G, Beams.B, Beams.Y, Beams.C, Beams.M, Beams.W]:
		if (seen & (1 << c)) == 0:
			return c
	return 0


func _pharos_exists() -> bool:
	for m in World.machines.values():
		if m != null and is_instance_valid(m) and String(m.get("kind")) == "Pharos":
			return true
	return false


## Куда вести маркер цвета: к ближайшему маяку, иначе к ядру, иначе никуда.
func _pharos_at() -> Vector2:
	var origin: Vector2 = World.cell_to_world(World.beacon_cell)
	if player != null and is_instance_valid(player):
		origin = player.global_position
	var best: Vector2 = Vector2.INF
	var best_d: float = INF
	for m in World.machines.values():
		if m == null or not is_instance_valid(m) or String(m.get("kind")) != "Pharos":
			continue
		var p: Vector2 = m.global_position
		var d: float = p.distance_squared_to(origin)
		if d < best_d:
			best_d = d
			best = p
	if best != Vector2.INF:
		return best
	if Game.core_placed():
		return World.cell_to_world(Game.core_cell)
	return Vector2.INF


## Записать карточку. Текст длиннее 6 слов режется — полный текст глав правит G*.
func _set_card(text: String, have: int, need: int, icon: int, at: Vector2) -> void:
	card_text = _card_words(text, CARD_WORDS)
	card_have = maxi(0, have)
	card_need = maxi(0, need)
	card_icon = icon
	card_at = at if at is Vector2 else Vector2.INF
	card_mix = false


## Подсказка этапа. На тач длинная десктопная строка не влезает в плашку.
func _mission_help() -> String:
	var raw: String = String(Game.mission.hint)
	if UI.touch_on and raw.contains("забери и поставь"):
		return "Забери горелку и поставь на метку"
	return _one_hint(raw)


## Шаг обучения: самый дальний выполненный признак (вперёд — сразу, назад — никогда).
## В главе кампании вместо цепочки — подсказка этапа (Mission.hint).
func _compute_tutorial() -> void:
	if Game.in_mission():
		tutorial_text = _mission_help()
		return
	if tutorial_step == Tut.DONE:
		tutorial_text = ""
		return
	var lvl: int = Tut.DIG
	var scrap: int = 0
	if player != null:
		scrap = player.inv.count_of(IDs.I.SCRAP)
	# Питания нет (#170): хлам → крафт горелки → поставить → терминал.
	# Цепочку закрывает прочитанный терминал (tasks_done), а не этап 1:
	# горелка ставится раньше, и шаг «держи E» должен успеть показаться.
	if Game.tasks_done > 0 or Game.objective_stage >= 4:
		lvl = Tut.DONE
	elif player != null and _burner_near():
		lvl = Tut.TERMINAL
	elif player != null and player.inv.count_of(IDs.I.BURNER) > 0:
		lvl = Tut.PLACE
	elif scrap >= TUT_SCRAP:
		lvl = Tut.CRAFT
	tutorial_step = maxi(tutorial_step, lvl)
	var n: int = tutorial_step + 1
	match tutorial_step:
		Tut.DIG:
			tutorial_text = "%d/4 Копай: %s по земле — хлам %d/%d на горелку" % [n,
					"тап" if UI.touch_on else "ЛКМ", mini(scrap, TUT_SCRAP), TUT_SCRAP]
		Tut.CRAFT:
			tutorial_text = "%d/4 Крафт: I — «Горелка»" % n
		Tut.PLACE:
			tutorial_text = ("%d/4 Горелка: выбери в хотбаре, тап у базы" if UI.touch_on
					else "%d/4 Горелка: ПКМ — у базы") % n
		Tut.TERMINAL:
			tutorial_text = "%d/4 Терминал: держите [E]" % n
		_:
			tutorial_text = ""


## Первые n слов, без обрезки «…». Пустая строка остаётся пустой.
static func _card_words(text: String, n: int) -> String:
	var parts: PackedStringArray = text.split(" ", false)
	if parts.size() <= n:
		return " ".join(parts)
	var cut: PackedStringArray = PackedStringArray()
	for i in n:
		cut.append(parts[i])
	return " ".join(cut)


## Подсказка этапа — одна фраза: до первого «·», без склейки клавиш.
static func _one_hint(text: String) -> String:
	var i: int = text.find("·")
	if i < 0:
		return text.strip_edges()
	return text.substr(0, i).strip_edges()


## Маркер цели: на экране — мигающая рамка, за краем — стрелка.
func _update_card_mark() -> void:
	var on: bool = false
	var cell: Vector2i = Vector2i(-9999, -9999)
	if card_at != Vector2.INF and player != null and player.camera != null:
		cell = World.world_to_cell(card_at)
		var sr: Rect2 = get_viewport().get_canvas_transform() * World.cell_rect(cell)
		var vis: Rect2 = get_viewport().get_visible_rect().grow(-8.0)
		on = vis.encloses(sr)
	var blink: int = int(Game.game_time * 4.0) % 2
	if on != card_mark_on or cell != _card_cell or (on and blink != _card_blink):
		card_mark_on = on
		_card_cell = cell
		_card_blink = blink
		# Рамка цели — в мире, стрелка — на слое HUD. Оба слоя, чтобы не осталась
		# стрелка, когда цель вошла в кадр, и наоборот.
		_redraw_world_mark()
		if _mark != null:
			_mark.queue_redraw()


## Клик по карточке: камера на 2 с уезжает к цели и возвращается. Герой не двигается.
func _on_card_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if card_at == Vector2.INF or player == null or player.camera == null:
		return
	_card_hit.accept_event()
	var cam: Camera2D = player.camera
	if not _card_looking:
		_card_cam_back = cam.position
	_card_looking = true
	card_look_left = CARD_LOOK_SEC
	cam.position = card_at - player.global_position
	cam.reset_smoothing()


## Показ цели кончился — камера встаёт обратно на героя.
func _update_card_look(delta: float) -> void:
	if not _card_looking:
		return
	card_look_left -= delta
	if card_look_left > 0.0 and player != null and is_instance_valid(player):
		return
	_card_looking = false
	card_look_left = 0.0
	if player != null and player.camera != null:
		player.camera.position = _card_cam_back
		player.camera.reset_smoothing()


## Горелка рядом с героем — шаг «поставить» пройден. Питания больше нет (#170).
func _burner_near() -> bool:
	if player == null:
		return false
	var pc: Vector2i = World.world_to_cell(player.global_position)
	for dy in range(-3, 4):
		for dx in range(-8, 9):
			var m = World.machines.get(pc + Vector2i(dx, dy))
			if m != null and m.kind == "Burner":
				return true
	return false


## Целых секунд до ночи (вверх) в сумерках, иначе -1.
func _night_countdown() -> int:
	if not Game.is_dusk():
		return -1
	return int(ceil((Balance.NIGHT_START - Game.time_of_day) * Balance.DAY_LENGTH))


# ------------------------------------------------------------ МИНИКАРТА

## Прямоугольник миникарты. На ПК — правый верх. На телефоне — из раскладки
## (ужатая карта в нижней трети) или пусто, если в треть не влезла.
func _map_rect_now() -> Rect2:
	if UI.touch_on:
		_ensure_layout()
		return _lay.get("map", Rect2())
	return Rect2(size.x - MAP_OFFSET.x, MAP_OFFSET.y, MAP_SIZE.x, MAP_SIZE.y)


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
	var r: Rect2 = _map_rect_now()
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
	if r.size.x < 1.0:
		return
	c.draw_rect(r, C_PLATE)
	# ПК: r == MAP_SIZE, rect совпадает с draw_texture. Тач: текстура вписана.
	# Нативный размер (ПК, 186×52) — draw_texture: тест миникарты зовёт слой вне
	# _draw, а draw_texture_rect там падает. Ужатая карта телефона — только в _draw.
	if r.size == Vector2(MAP_SIZE):
		c.draw_texture(_map_tex, r.position)
		c.draw_texture(_fog_tex, r.position)
	else:
		c.draw_texture_rect(_map_tex, r, false)
		c.draw_texture_rect(_fog_tex, r, false)
	c.draw_rect(r, Color(C_LINE, 0.25), false, 1.0)
	var sx: float = r.size.x / float(World.W)
	var sy: float = r.size.y / float(World.H)
	# Терминалы руин — только под открытым туманом. Иначе разрез миникарты
	# (сталь комнаты под травой) ведёт к плюшке, как точки на карте.
	var nt: int = 0
	for t in World.terminals:
		if int(World.terminal_chapters.get(t, -1)) < Lore.BASE_TERMINALS:
			continue
		if not map_explored_at(t):
			continue
		nt += 1
		var tp: Vector2 = (r.position + Vector2((float(t.x) + 0.5) * sx, (float(t.y) + 0.5) * sy)).floor()
		c.draw_rect(Rect2(tp - Vector2(1, 1), Vector2(3, 3)), C_BIO)
	stat_map_terminals = nt
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
	# Активное ядро (нет ядра — точка не рисуется: лагерь и так виден рельефом).
	if Game.core_placed():
		var bp: Vector2 = r.position + Vector2(Game.core_cell.x * sx, Game.core_cell.y * sy)
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
## и клавиша «E» над ним. Рисуется в мировых px (_world_mark): камера, тряска
## и зум двигают её вместе с клеткой. Экранный кэш в _process отставал на кадр
## (#211) — сглаживание камеры пишет canvas transform после idle. mark_rect
## остаётся для сценариев: экранный прямоугольник клетки, пересчитанный в _draw.

func _update_mark() -> void:
	var pr: float = _interact_progress()
	var changed: bool = _hint_target != _mark_world
	if changed:
		_mark_world = _hint_target
		_mark_progress = pr
		_redraw_world_mark()
	elif absf(pr - _mark_progress) > 0.03:
		# Плашка «E» наполняется при удержании (разбор постройки): слой
		# перерисовываем, только когда полоса изменилась заметно — перерисовка
		# каждый кадр (с текстом!) съедала бы кадр хоста.
		_mark_progress = pr
		if _mark_world.size != Vector2.ZERO:
			_redraw_world_mark()


## Есть ли рамка интерактива. Не mark_rect: тот пишется в _draw и в _process ещё пуст.
func mark_visible() -> bool:
	return _mark_world.size != Vector2.ZERO


## Точка мира внутри клетки рамки. Допуск — клетка: центр машины на середине,
## а клетка рисуется от угла.
func mark_on_world(world_pos: Vector2) -> bool:
	if _mark_world.size == Vector2.ZERO:
		return false
	return _mark_world.grow(float(World.TILE)).has_point(world_pos)


## Экранный прямоугольник рамки при текущей камере (не кэш прошлого кадра).
func mark_live_rect() -> Rect2:
	if _mark_world.size == Vector2.ZERO:
		return Rect2()
	return get_viewport().get_canvas_transform() * _mark_world


## На сколько экранных px рамка уехала от клетки предмета при текущей камере.
## Клетка мировая, поэтому цифра — 0: сдвиг камеры двигает рамку вместе с ней.
## До #211 кэш _process отставал от сглаживания (на прыжке — 7 px).
func mark_screen_lag() -> float:
	if _mark_world.size == Vector2.ZERO or player == null:
		return -1.0
	var cell: Vector2i = World.world_to_cell(_mark_world.get_center())
	var live: Rect2 = mark_live_rect()
	var expect: Rect2 = get_viewport().get_canvas_transform() * World.cell_rect(cell)
	return live.position.distance_to(expect.position)


## Экранный прямоугольник рамки. Считается в _draw мирового слоя — там canvas
## transform уже тот, которым рисуется кадр. Из _process его читать нельзя:
## сглаживание камеры пишет трансформ после idle (#211).
func _sync_mark_rect() -> void:
	if _mark_world.size == Vector2.ZERO:
		mark_rect = Rect2i()
		return
	var sr: Rect2 = get_viewport().get_canvas_transform() * _mark_world
	mark_rect = Rect2i(sr.position.round(), sr.size.round())


func _drop_world_mark() -> void:
	if _world_mark != null and is_instance_valid(_world_mark):
		_world_mark.queue_free()
	_world_mark = null


func _redraw_world_mark() -> void:
	if _world_mark != null and is_instance_valid(_world_mark):
		_world_mark.queue_redraw()


## Доля удержания E (0..1): разбор постройки или чтение терминала.
func _interact_progress() -> float:
	if player == null:
		return 0.0
	return clampf(float(player.task_progress), 0.0, 1.0)


## Стрелка цели карточки — экранная, её слой по-прежнему в HUD.
## stat_mark_redraws считает мировую рамку (_draw_world_mark), не стрелку.
func _draw_mark_layer() -> void:
	var t0: int = Time.get_ticks_usec()
	_draw_card_arrow()
	stat_us += Time.get_ticks_usec() - t0


## Рамка интерактива и мигающая рамка цели карточки — в мировых px.
## Толщина линий делится на зум: на экране она та же, что была у слоя HUD.
func _draw_world_mark() -> void:
	var t0: int = Time.get_ticks_usec()
	stat_mark_redraws += 1
	_sync_mark_rect()
	var zoom: float = get_viewport().get_canvas_transform().get_scale().x
	if zoom < 0.01:
		zoom = 1.0
	var w: float = MARK_W / zoom
	if _mark_world.size != Vector2.ZERO:
		var r: Rect2 = _mark_world.grow(MARK_GROW / zoom)
		_world_mark.draw_rect(Rect2(r.position, Vector2(r.size.x, w)), C_INTERACT)
		_world_mark.draw_rect(Rect2(r.position.x, r.end.y - w, r.size.x, w), C_INTERACT)
		_world_mark.draw_rect(Rect2(r.position, Vector2(w, r.size.y)), C_INTERACT)
		_world_mark.draw_rect(Rect2(r.end.x - w, r.position.y, w, r.size.y), C_INTERACT)
		# Клавиша «E»: сливовая плашка с жёлтой кромкой над объектом.
		var box: float = 22.0 / zoom
		var gap: float = 6.0 / zoom
		var k: Rect2 = Rect2(r.get_center().x - box * 0.5, r.position.y - gap - box, box, box)
		_world_mark.draw_rect(k, C_PLATE)
		_world_mark.draw_rect(Rect2(k.position, Vector2(k.size.x, 2.0 / zoom)), C_INTERACT)
		var fs: int = UI.FONT["body"]
		_world_mark.draw_set_transform(k.position, 0.0, Vector2.ONE / zoom)
		_world_mark.draw_string(ThemeDB.fallback_font, Vector2(0, 18), "E",
				HORIZONTAL_ALIGNMENT_CENTER, 22.0, fs, C_INTERACT)
		_world_mark.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var pr: float = _interact_progress()
		if pr > 0.0:
			_world_mark.draw_rect(Rect2(k.position + Vector2(1.0, k.size.y - 4.0) / zoom,
					Vector2((22.0 - 2.0) * pr, 3.0) / zoom), C_BIO)
	_draw_card_frame(w, zoom)
	stat_us += Time.get_ticks_usec() - t0


## Мигающая рамка цели карточки на клетке мира. Видимость решает _update_card_mark.
func _draw_card_frame(w: float, zoom: float) -> void:
	if not card_mark_on or card_at == Vector2.INF:
		return
	if int(Game.game_time * 4.0) % 2 != 0:
		return
	var cell: Vector2i = World.world_to_cell(card_at)
	var r: Rect2 = World.cell_rect(cell).grow(MARK_GROW / zoom)
	_world_mark.draw_rect(Rect2(r.position, Vector2(r.size.x, w)), C_INTERACT)
	_world_mark.draw_rect(Rect2(r.position.x, r.end.y - w, r.size.x, w), C_INTERACT)
	_world_mark.draw_rect(Rect2(r.position, Vector2(w, r.size.y)), C_INTERACT)
	_world_mark.draw_rect(Rect2(r.end.x - w, r.position.y, w, r.size.y), C_INTERACT)


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

## Карточка «Сейчас» (#160): левый верх, под полосами здоровья. Высота 64.
## Слов в заголовке — не больше 6.
const CARD_X: float = 14.0
const CARD_Y: float = 54.0
const CARD_H: float = 64.0
const CARD_ICON: float = 48.0
const CARD_WORDS: int = 6
## Телефон: карточка ниже и уже по шрифту — иначе на 2.5 она занимает треть HUD.
const CARD_H_TOUCH: float = 48.0
const CARD_ICON_TOUCH: float = 32.0
## Зазор нижней плашки над хотбаром. На ПК — 4 (скриншоты README); на телефоне — 10.
## Ландшафт телефона теснее: между верхом нижней трети и хотбаром ~54 лог. px,
## и 10+24+10+24 не влезают. Там зазор 6, строка плашки 20, цель остаётся 22.
const HINT_GAP: float = 4.0
const HINT_GAP_TOUCH: float = 10.0
const HINT_GAP_LAND: float = 6.0
## Высота строки нижней плашки. Портрет — ROW_H (24). Ландшафт — 20, иначе
## цель и подсказка не умещаются в нижней трети над хотбаром.
const HINT_H_LAND: float = 20.0
## Низ хотбара на телефоне ближе к краю: 12 px мира по центру. На ПК HOTBAR_BOTTOM не трогаем.
const HOTBAR_BOTTOM_TOUCH: float = 20.0
## Ландшафт телефона: хотбар у самого края, чтобы над плашкой влезла карточка.
const HOTBAR_BOTTOM_LAND: float = 4.0
## Карточка телефона одной строкой: иконка 16, кегль small, этап и счётчик в той же строке.
## Высота 22–24 лог. px. Если строка не влезает — сначала режем поля и иконку, не текст.
const CARD_H_TOUCH_LINE: float = 24.0
const CARD_H_TOUCH_MIN: float = 22.0
const CARD_ICON_LINE: float = 16.0
const CARD_ICON_LINE_MIN: float = 12.0
const CARD_LINE_PAD: float = 8.0
const CARD_LINE_PAD_MIN: float = 2.0
## Ниже FONT.small полоса не обещает: только если щель между захватами
## уже шести слов. Текст не режем, «…» нет.
const CARD_FONT_LINE_MIN: int = 10
## Телефон: весь HUD в нижней трети. Верх и центр — игровое поле.
## Доля высоты, с которой блок может начинаться (position.y ≥ size.y * 2/3 − 0.5).
const TOUCH_BAND: float = 2.0 / 3.0
## Полосы здоровья и импульса на телефоне уже: в нижней трети рядом с карточкой.
const HP_W_TOUCH: float = 96.0
## Миникарта на телефоне уже и ниже: 186×52 в нижней трети не помещается.
const MAP_SIZE_TOUCH: Vector2i = Vector2i(96, 28)
## Отступ миникарты от правого края на телефоне, px.
const MAP_RIGHT_TOUCH: float = 8.0
## Клик по карточке показывает цель столько секунд, потом камера возвращается.
const CARD_LOOK_SEC: float = 2.0
## Стрелка у края экрана: сторона квадрата и отступ от края, px.
const CARD_ARROW: float = 28.0
const CARD_ARROW_PAD: float = 36.0

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
## Портрет: полоса над рядом боя, шаг 82 (ячейка 78 + зазор 4). 78 лог. px при 250 %
## на 1080×2400 ≈ 9.95 мм — пол MIN_MM. Уже 36 номер слота не рисуется (_draw_hotbar).
const SLOT_PORTRAIT: float = 82.0
const SLOT_DIGIT_MIN: float = 36.0
## Кегль цифры слота и счётчика стака. Плашка подсказки не крупнее него.
const SLOT_FONT: int = 14
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


## Блок раскладки на экране, px холста. Касания приходят в px холста, а не слоя UI
## (как hotbar_slot_rect). Пустого блока нет — пустой Rect2.
func layout_screen_rect(key: String) -> Rect2:
	var r: Rect2 = layout_rect(key)
	if r.size == Vector2.ZERO:
		return Rect2()
	return Rect2(r.position * UI.ui_scale, r.size * UI.ui_scale)


## Палец лёг на нарисованную панель HUD, а не на мир. Карточка «Сейчас» кликабельна
## только мышью (_card_hit), сам HUD мышь пропускает (MOUSE_FILTER_IGNORE) — тап
## TouchControls иначе читает как мир и копает или ставит клетку под панелью.
func covers_screen(pos: Vector2) -> bool:
	for key in ["card", "hp", "emp", "day", "countdown", "map", "team", "hint", "notes", "status"]:
		var r: Rect2 = layout_screen_rect(key)
		if r.size != Vector2.ZERO and r.has_point(pos):
			return true
	return false


const LAYOUT_RECTS: Array = ["hp", "emp", "card", "status", "day", "countdown", "map", "team", "hotbar",
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
			player != null, _hotbar_count(), card_text, card_have, card_need, Game.signal_sent,
			1 if UI.touch_on else 0, 1 if _intro_done else 0, _intro_index(),
			1 if _player_acting() else 0])


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


## Круги захвата пальца (BTN_GRAB / STICK_GRAB), не видимые круги. Блок HUD,
## пересекающий захват, забирает тап у кнопки.
## Верх захвата стика и нижнего ряда боя (прыжок, бег, E, копать), логические px.
## Меню и Q/V/G сюда не входят: они выше и полосу хотбара не задают.
func _combat_grab_top(h: float) -> float:
	var top: float = h
	var tc: Node = _touch()
	if tc == null:
		return top
	var k: float = 1.0 / UI.ui_scale
	for id in ["jump", "run", "e", "build"]:
		if not tc.btn_center.has(id) or not tc._shown(id, false):
			continue
		var c: Vector2 = tc.btn_center[id] * k
		var rad: float = float(tc.btn_radius[id]) * TouchControls.BTN_GRAB * k
		top = minf(top, c.y - rad)
	top = minf(top, tc.stick_center.y * k - float(tc.stick_radius) * TouchControls.STICK_GRAB * k)
	return top


func _grab_circles() -> Array:
	var out: Array = []
	var tc: Node = _touch()
	if tc == null:
		return out
	var k: float = 1.0 / UI.ui_scale
	for id in tc.btn_center:
		if not tc._shown(id, false):
			continue
		out.append({"c": tc.btn_center[id] * k, "r": float(tc.btn_radius[id]) * TouchControls.BTN_GRAB * k})
	out.append({"c": tc.stick_center * k, "r": float(tc.stick_radius) * TouchControls.STICK_GRAB * k})
	return out


func _hits_grab(r: Rect2, grabs: Array) -> bool:
	for g in grabs:
		var c: Vector2 = g["c"]
		var closest := Vector2(clampf(c.x, r.position.x, r.end.x), clampf(c.y, r.position.y, r.end.y))
		if c.distance_to(closest) < float(g["r"]) - 0.01:
			return true
	return false


## Самый низкий y в [band, top], на котором полоса ширины need свободна от захватов.
## Возвращает x и y; не влезла — пустой Rect2.
## Любой свободный отрезок ширины need на высоте [band, top]: между двумя
## захватами, не только у края. _grab_free_slot режет полосу с одной стороны
## и середину между стиком и Q не видит.
func _grab_gap_slot(grabs: Array, band: float, top: float, need: float, hgt: float) -> Rect2:
	var w: float = size.x
	var y: float = top - hgt
	while y + 0.5 >= band:
		var cuts: Array = []
		for g in grabs:
			var c: Vector2 = g["c"]
			var rad: float = float(g["r"])
			var dy: float = 0.0
			if c.y < y:
				dy = y - c.y
			elif c.y > y + hgt:
				dy = c.y - (y + hgt)
			if dy >= rad:
				continue
			var dx: float = sqrt(rad * rad - dy * dy)
			cuts.append(Vector2(c.x - dx, c.x + dx))
		cuts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		var cursor: float = PAD
		var best_x: float = -1.0
		var best_w: float = -1.0
		for cut in cuts:
			var span: float = cut.x - cursor
			if span > best_w:
				best_w = span
				best_x = cursor
			cursor = maxf(cursor, cut.y)
		var tail: float = w - PAD - cursor
		if tail > best_w:
			best_w = tail
			best_x = cursor
		if best_w + 0.5 >= need:
			var x: float = clampf((w - need) * 0.5, best_x, best_x + best_w - need)
			return Rect2(x, y, need, hgt)
		y -= 1.0
	return Rect2()



## Ряд плашки на фиксированной высоте: центр хотбара, иначе любой промежуток
## между захватами той же высоты. Пустой — на этой высоте щели нет.
func _hint_row(grabs: Array, y: float, need: float, hgt: float, prefer_x: float) -> Rect2:
	var w: float = size.x
	var cx: float = clampf(prefer_x - need * 0.5, PAD, maxf(PAD, w - PAD - need))
	var centered: Rect2 = Rect2(cx, y, need, hgt)
	if not _hits_grab(centered, grabs):
		return centered
	var gap_r: Rect2 = _grab_gap_slot(grabs, y, y + hgt, need, hgt)
	if gap_r.has_area():
		return Rect2(gap_r.position.x, y, need, hgt)
	return Rect2()


func _grab_free_slot(grabs: Array, band: float, top: float, need: float, hgt: float) -> Rect2:
	var w: float = size.x
	var y: float = top - hgt
	while y + 0.5 >= band:
		var lo: float = PAD
		var hi: float = w - PAD
		for g in grabs:
			var c: Vector2 = g["c"]
			var rad: float = float(g["r"])
			var dy: float = 0.0
			if c.y < y:
				dy = y - c.y
			elif c.y > y + hgt:
				dy = c.y - (y + hgt)
			if dy >= rad:
				continue
			var dx: float = sqrt(rad * rad - dy * dy)
			var left: float = c.x - dx
			var right: float = c.x + dx
			if right <= lo or left >= hi:
				continue
			if c.x >= (lo + hi) * 0.5:
				hi = minf(hi, left)
			else:
				lo = maxf(lo, right)
		if hi - lo + 0.5 >= need:
			var x: float = clampf((w - need) * 0.5, lo, hi - need)
			return Rect2(x, y, need, hgt)
		y -= 1.0
	return Rect2()


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


## Текст нижней плашки. На ПК — hint_text как есть (пустой, если цели нет).
## На телефоне плашка не пустая в играбельном состоянии, одна строка без переноса:
##   1. контекстная подсказка действия (_touch_hint);
##   2. вводная строка — по одной, первые INTRO_TIME секунд (раньше туториала);
##   3. шаг обучения (tutorial_text), одна строка;
##   4. короткая подсказка этапа цели (_touch_stage_help).
## Копание и стройка плашку не прячут: подсказка нужна и во время действия.
func _plate_text() -> String:
	if not UI.touch_on:
		return hint_text
	var short: String = _touch_hint(hint_text)
	if short != "":
		return short
	var intro: String = _intro_line()
	if intro != "":
		return intro
	var tut: String = _touch_tutorial()
	if tut != "":
		return tut
	return _touch_stage_help()


## Шаг обучения — одна короткая строка без переносов. Пусто, пока идёт ввод
## (его отдаёт _plate_text раньше) или цепочка пройдена.
func _touch_tutorial() -> String:
	var t: String = tutorial_text.strip_edges()
	if t == "":
		return ""
	var cut: int = t.find("\n")
	if cut >= 0:
		t = t.substr(0, cut)
	return t.strip_edges()


## Строка плашки, которая влезает в max_w без «…». Сначала как есть. Если не
## влезла — хвост с глаголом, иначе короткая подсказка этапа. Фрагмент без
## действия («Руда в камне») не возвращаем и плашку не прячем.
func _touch_plate_fit(text: String, fs: int, max_w: float) -> String:
	var line: String = text.strip_edges()
	if line == "":
		return ""
	if max_w <= 8.0 or _tw(line, fs) <= max_w + 0.5:
		return line
	# Хвост после разделителя — только если в нём действие. Голову «Руда в камне»
	# не возвращаем: это описание без глагола, игрок не знает, что нажать.
	for sep in [" — ", " · ", ": "]:
		var cut: int = line.find(sep)
		if cut <= 0:
			continue
		var tail: String = line.substr(cut + sep.length()).strip_edges()
		if _touch_has_action(tail) and _tw(tail, fs) <= max_w + 0.5:
			return tail
	var stage: String = _touch_stage_help()
	if stage != "" and stage != line and _tw(stage, fs) <= max_w + 0.5:
		return stage
	var parts: PackedStringArray = line.split(" ", false)
	while parts.size() > 1:
		parts.resize(parts.size() - 1)
		var joined: String = " ".join(parts)
		if _touch_has_action(joined) and _tw(joined, fs) <= max_w + 0.5:
			return joined
	if stage != "":
		return stage
	return line


## Короткая подсказка этапа, когда нет ни действия, ни ввода, ни шага обучения.
## Свободная игра — этапы 1–6; глава — подсказка этапа, иначе та же формула.
## Тексты сверены с _compute_tracker / Game.OBJECTIVE_TITLES, не с догадкой.
## Есть ли в строке действие, а не только описание предмета.
func _touch_has_action(text: String) -> bool:
	var low: String = text.to_lower()
	for verb in ["копай", "тап", "держи", "стой", "пережди", "крафт", "луч", "иди", "меню"]:
		if low.contains(verb):
			return true
	return false


func _touch_stage_help() -> String:
	if Game.in_mission() and Game.mission != null:
		var mh: String = _mission_help()
		if mh != "":
			return mh
	var st: int = clampi(Game.objective_stage, 1, Game.OBJECTIVE_STAGES)
	if Game.relay_active:
		st = Game.OBJECTIVE_STAGES
	# Короткие строки с глаголом: живой ландшафтный слот ~250 лог. px при кегле 14.
	# Длинный текст подгонка срезала до описания без действия.
	match st:
		1:
			return "Крафт I, тап у базы"
		2:
			return "Копай тапом по земле"
		3:
			return "Пережди ночь у базы"
		4:
			return "Луч в ядро — не белый"
		5:
			return "Держи [E] у ядра"
		_:
			return "Стой у ядра, держи сигнал"


## Высота карточки, сторона иконки и кегли заголовка и счётчика. На ПК — как было.
func _card_h() -> float:
	return CARD_H_TOUCH if UI.touch_on else CARD_H


func _card_icon() -> float:
	return CARD_ICON_TOUCH if UI.touch_on else CARD_ICON


func _card_title_font() -> int:
	return UI.FONT["body"] if UI.touch_on else UI.FONT["title"]


func _card_sub_font() -> int:
	return UI.FONT["small"] if UI.touch_on else UI.FONT["body"]


func _compute_layout() -> Dictionary:
	var L: Dictionary = {}
	var w: float = size.x
	var h: float = size.y
	var fb: int = UI.FONT["body"]
	var fs: int = UI.FONT["small"]
	var tb: Dictionary = _touch_rects()
	var touch: bool = UI.touch_on
	var portrait: bool = touch and h > w * 1.2
	# На ПК верх экрана — здоровье, импульс, сутки, карта. На телефоне эти блоки
	# кладёт _place_touch_top: верх и центр — игровое поле, HUD только в нижней трети.
	if not touch:
		if player:
			L["hp"] = Rect2(PAD, 8.0, HP_W, HP_H)
			L["emp"] = Rect2(PAD, 8.0 + HP_H + 4.0, HP_W, EMP_H)
		var dw: float = maxf(_tw(day_label(), fs), STRIP_W)
		L["day"] = Rect2(w - PAD - dw, 6.0, dw, 34.0)
		if night_countdown >= 0:
			var cw: float = _tw("НОЧЬ ЧЕРЕЗ %d с" % night_countdown, fb) + 24.0
			L["countdown"] = Rect2((w - cw) * 0.5, 8.0, cw, 26.0)
		L["map"] = Rect2(w - MAP_OFFSET.x, MAP_OFFSET.y, MAP_SIZE.x, MAP_SIZE.y)
	var n_team: int = team_mates.size()
	if n_team > 0 and not touch:
		L["team"] = team_plate_rect(w, n_team)
	var right_bottom: float = right_column_bottom(w, n_team)
	# ---- Низ: хотбар по центру свободной полосы между джойстиком и кнопками справа.
	# Портрет: щели между стиком и E нет — хотбар полосой над рядом боя,
	# целиком выше захватов. Кнопки не двигаем. Ландшафт остаётся в щели:
	# захват стика там доходит до ~59 % высоты, треть — только 96 px.
	var lo: float = 0.0
	var hi: float = w
	var n_slots: int = _hotbar_count()
	var slot: float = SLOT_MAX
	var hb_w: float = 0.0
	var hx: float = 0.0
	var hy: float = 0.0
	var hint_max: float = minf(w - 2.0 * PAD, 600.0)
	if portrait:
		# Щели между стиком и E нет: ячейка там сжималась до 27 px (3.4 мм).
		# Полоса над рядом боя, шаг не от щели X. 6 слотов — SLOT_PORTRAIT
		# (ячейка 78). 10 слотов — min(82, пол ширины / 10), ячейка не меньше
		# 36, чтобы номер рисовался. Кнопки не двигаем.
		var step: float = SLOT_PORTRAIT
		if n_slots >= SLOT_COUNT:
			step = minf(SLOT_PORTRAIT, floorf((w - 2.0 * PAD) / float(n_slots)))
		slot = maxf(step, SLOT_DIGIT_MIN + 4.0)
		hb_w = slot * float(n_slots) - 4.0
		# Холст уже шести крупных ячеек (1080×2400 при 250 % — 432 лог. px):
		# полоса не должна выходить за край. Номер слота тогда не рисуется.
		var fit: float = w - 2.0 * PAD
		if hb_w > fit + 0.5:
			slot = maxf(16.0, floorf((fit + 4.0) / float(n_slots)))
			hb_w = slot * float(n_slots) - 4.0
		hx = clampf((w - hb_w) * 0.5, PAD, maxf(PAD, w - PAD - hb_w))
		var cell_h: float = slot - 4.0
		# Низ полосы — у верхнего захвата стика и нижнего ряда боя
		# (прыжок, бег, E, копать). Меню сверху и Q/V/G в захват не входят:
		# иначе полоса уезжает к верхней трети.
		var grab_top: float = _combat_grab_top(h)
		hy = grab_top - cell_h
		hy = grab_top - cell_h
		var band_y: float = h * (2.0 / 3.0)
		if hy + 0.5 < band_y:
			hy = band_y
		lo = PAD
		hi = w - PAD
		hint_max = hi - lo
	else:
		if tb.has("stick") and tb.has("e"):
			lo = (tb["stick"] as Rect2).end.x + PAD
			hi = (tb["e"] as Rect2).position.x - PAD
			# «копать»/«строить» — слева от E и крупнее: полоса кончается у неё, не у E.
			if tb.has("build"):
				hi = minf(hi, (tb["build"] as Rect2).position.x - PAD)
		var slot_cap: float = SLOT_MAX
		# 6 ячеек — крупнее: min(42 × 10 / n, 64). На телефоне потолок 42: 64 px
		# на 2.5 съедает полосу мира.
		if n_slots < SLOT_COUNT:
			slot_cap = minf(SLOT_TOUCH * float(SLOT_COUNT) / float(n_slots), SLOT_TOUCH_MAX)
			if touch:
				slot_cap = SLOT_TOUCH
		slot = clampf(floorf((hi - lo) / float(n_slots)), 16.0, slot_cap)
		hb_w = slot * float(n_slots) - 4.0
		hx = clampf(w * 0.5 - hb_w * 0.5, lo, maxf(lo, hi - hb_w))
		var bottom: float = HOTBAR_BOTTOM_LAND if touch else HOTBAR_BOTTOM
		hy = h - bottom - (slot - 4.0)
		# На телефоне хотбар остаётся у нижнего края (HOTBAR_BOTTOM_LAND, 4 px).
		# Ряд боя его не поднимает: поднятие сажало полосу на героя и выносило
		# её из нижней трети. На ПК tb пуст — HOTBAR_BOTTOM не меняется.
		hint_max = minf(minf(w - 2.0 * PAD, 600.0), hi - lo)
	L["slot"] = slot
	L["hotbar"] = Rect2(hx, hy, hb_w, slot - 4.0)
	# Ландшафт: захват стика шире видимого круга и задевает хотбар у нижнего
	# края. Сужаем по X, высоту не трогаем. Портрет уже выше всех захватов —
	# сужение по X снова зажало бы ячейку до 27 px, его нет.
	if touch and not portrait:
		var hb_grabs: Array = _grab_circles()
		if _hits_grab(L["hotbar"], hb_grabs):
			var shrunk: Rect2 = _shrink_off_grabs(L["hotbar"], hb_grabs)
			if shrunk.size.x >= 48.0:
				L["hotbar"] = shrunk
				hx = shrunk.position.x
				hb_w = shrunk.size.x
	var stack_top: float = hy
	var gap: float = HINT_GAP_TOUCH if touch else HINT_GAP
	var hint_h: float = ROW_H
	# Ландшафт: 54 лог. px между верхом нижней трети и хотбаром. Цель 22 + зазор 6
	# + строка 20 + зазор 6 = 54. Портрет не сжимаем: там 24/10 и хотбар 78.
	if touch and not portrait:
		gap = HINT_GAP_LAND
		hint_h = HINT_H_LAND
	# Телефон: цель раньше плашки. На узком ландшафте единственная широкая щель —
	# у границы нижней трети, выше стика. Плашка, севшая туда первой, прятала этап.
	# Но вводной строке нужен свой ряд: иначе цель занимает щель над хотбаром и
	# плашка пересекает карточку. Резерв — высота строки и зазор, не сама плашка.
	if touch and _plate_text() != "":
		stack_top -= hint_h + gap
	if touch:
		_place_touch_top(L, tb, h * TOUCH_BAND, portrait, stack_top)
		if L.has("card"):
			stack_top = minf(stack_top, (L["card"] as Rect2).position.y)
	var plate: String = _plate_text()
	if plate != "":
		var hfont: int = fb
		var ht: String = plate
		if touch:
			# Кегль плашки не крупнее цифр ячеек хотбара. Ширина = текст + поля,
			# не на весь экран. Не влезла в щель — короче текст, плашку не прячем.
			hfont = _slot_font()
			var hpad: float = 0.0 if portrait else 16.0
			ht = _touch_plate_fit(plate, hfont, hint_max - hpad)
		else:
			ht = _fit_text(plate, fb, hint_max - 16.0)
		if ht != "":
			L["hint_text"] = ht
			L["hint_font"] = hfont
			var side: float = 0.0 if portrait else 16.0
			var hw: float = _tw(ht, hfont) + side
			var grabs: Array = _grab_circles()
			var slot_r: Rect2 = Rect2()
			var hint_ceiling: float = stack_top
			if L.has("card"):
				hint_ceiling = minf(hint_ceiling, (L["card"] as Rect2).position.y - gap)
			if portrait:
				var hx0: float = clampf(hx + hb_w * 0.5 - hw * 0.5, PAD, maxf(PAD, w - PAD - hw))
				slot_r = Rect2(hx0, hy - gap - hint_h, hw, hint_h)
				# Цель уже над хотбаром — плашка уходит под неё, не на неё.
				if L.has("card") and slot_r.intersects(L["card"]):
					slot_r.position.y = (L["card"] as Rect2).end.y + gap
				if slot_r.end.y > hy - gap + 0.5:
					slot_r = Rect2()
			elif not grabs.is_empty():
				# Прямо над хотбаром, в нижней трети. Свободный поиск сажал плашку
				# в щель у границы трети и вытеснял цель — здесь ряд фиксирован.
				var y_hint: float = hy - gap - hint_h
				if y_hint + 0.5 >= h * TOUCH_BAND:
					slot_r = _hint_row(grabs, y_hint, hw, hint_h, hx + hb_w * 0.5)
					if not slot_r.has_area():
						var shorter: String = _touch_plate_fit(ht, hfont, maxf(48.0, hw * 0.55))
						if shorter != "" and _tw(shorter, hfont) + side + 0.5 < hw:
							hw = _tw(shorter, hfont) + side
							ht = shorter
							slot_r = _hint_row(grabs, y_hint, hw, hint_h, hx + hb_w * 0.5)
				if slot_r.has_area():
					L["hint_text"] = ht
			else:
				var h_lo: float = maxf(PAD, lo)
				var h_hi: float = hi
				var hcx: float = clampf(hx + hb_w * 0.5 - hw * 0.5, h_lo, maxf(h_lo, minf(w - PAD, h_hi) - hw))
				slot_r = Rect2(hcx, hy - gap - hint_h, hw, hint_h)
			if slot_r.has_area() and not _hits_grab(slot_r, grabs):
				L["hint"] = slot_r
				stack_top = minf(stack_top, slot_r.position.y)
	if touch:
		_drop_grab_hits(L)
		return L
	# ---- Слева: карточка «Сейчас» (x=14, y=54), под ней — одна строка подсказки
	# этапа. Мощность и старый трекер на экран не идут (#160).
	var rows: Array = _status_rows()
	var card_y: float = CARD_Y
	var card_x: float = CARD_X
	if L.has("emp"):
		card_y = maxf(card_y, (L["emp"] as Rect2).end.y + 6.0)
	var y0: float = card_y
	if player and card_text != "":
		var cap: float = (L["map"] as Rect2).position.x - card_x - 8.0
		var ch: float = _card_h()
		var cw: float = minf(_card_width(), maxf(96.0, cap))
		L["card"] = Rect2(card_x, card_y, cw, ch)
		_fit_card_title(L, cw)
		y0 = card_y + ch + 4.0
	# На телефоне между низом верхнего стека и верхом нижней плашки — не меньше
	# 40 логических px мира. На ПК зазор прежний (4).
	var s_limit: float = stack_top - (40.0 if UI.touch_on else 4.0)
	if not notes.is_empty():
		s_limit -= ROW_H
	if tb.has("build"):
		s_limit = minf(s_limit, (tb["build"] as Rect2).position.y - 4.0)
	var blockers: Array = [L["map"]]
	if L.has("team"):
		blockers.append(L["team"])
	blockers.append_array(tb.values())
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
	var rows_end: float = s_bottom if not rows.is_empty() else (CARD_Y + _card_h() if L.has("card") else 0.0)
	for id in tb:
		if id == "e" or id == "run" or id == "jump" or id == "build":
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
		var pad: float = 22.0 if int(nt.get("icon", 0)) > 0 else 0.0
		var txt: String = _fit_text(String(nt["text"]), fb, minf(n_right - n_left, 620.0) - pad)
		lines.append(txt)
		nw = maxf(nw, _tw(txt, fb))
	if cnt > 0:
		L["notes"] = Rect2(n_right - nw, n_bottom - float(cnt) * ROW_H, nw, float(cnt) * ROW_H)
		L["note_lines"] = lines
	return L



## Миникарта телефона: 96×28, в нижней трети, не на кнопках и не на захватах.
## Сначала правый край, не влезла — карман над рядом боя. Кнопки не двигаем.
func _touch_map_rect(tb: Dictionary, band: float, h: float, occupied: Array = []) -> Rect2:
	var w: float = size.x
	var mw: float = float(MAP_SIZE_TOUCH.x)
	var mh: float = float(MAP_SIZE_TOUCH.y)
	var candidates: Array = []
	candidates.append(Rect2(w - MAP_RIGHT_TOUCH - mw, maxf(band + CARD_H_TOUCH_LINE + 4.0, h - HOTBAR_BOTTOM_TOUCH - mh - 6.0), mw, mh))
	var row_top: float = h
	var row_left: float = w
	for id in ["build", "e", "run", "jump"]:
		if tb.has(id):
			var br: Rect2 = tb[id]
			row_top = minf(row_top, br.position.y)
			row_left = minf(row_left, br.position.x)
	if row_top < h:
		candidates.append(Rect2(maxf(row_left, w - MAP_RIGHT_TOUCH - mw), row_top - mh - 4.0, mw, mh))
	var grabs: Array = _grab_circles()
	for c in candidates:
		var cr: Rect2 = c
		if cr.position.y + 0.5 < band:
			continue
		if cr.end.y > h + 0.5 or cr.end.x > w - MAP_RIGHT_TOUCH + 0.5 or cr.position.x < 0.0:
			continue
		if _hits(cr, tb.values()) or _hits(cr, occupied) or _hits_grab(cr, grabs):
			continue
		return cr
	return Rect2()


## Полоса цели телефона. Всегда, пока card_text не пуст: 22–24 px над плашкой
## (если она есть) иначе над хотбаром, зазор HINT_GAP_TOUCH, y ≥ band.
## Текст не режется. Не влезла — меньше поля и иконка. Захват сдвигает по X.
## Пересечения с плашкой, хотбаром, HP, импульсом, силуэтом и захватом нет:
## если на выбранной высоте X занят — берём свободный промежуток той же полосы.
func _place_touch_card(L: Dictionary, tb: Dictionary, band: float, hint_top: float) -> Rect2:
	var portrait: bool = size.y > size.x * 1.2
	var line: String = _card_line_text()
	if line == "":
		return Rect2()
	var w: float = size.x
	var line_h: float = CARD_H_TOUCH_LINE
	var card_gap: float = HINT_GAP_LAND if not portrait else HINT_GAP_TOUCH
	var top: float = hint_top - card_gap
	if top - line_h + 0.5 < band:
		line_h = CARD_H_TOUCH_MIN
	var y0: float = top - line_h
	if y0 + 0.5 < band:
		y0 = band
	var floor_y: float = size.y - line_h
	if L.has("hotbar"):
		var hb_gap: float = card_gap if portrait else HINT_GAP_TOUCH
		floor_y = minf(floor_y, (L["hotbar"] as Rect2).position.y - hb_gap - line_h)
	# Ландшафт с плашкой: единственный ряд цели — над ней, у границы трети.
	# Поиск снизу вверх сажает цель на хотбар или прячет. Ряд фиксируем.
	if not portrait and hint_top + 0.5 < (L["hotbar"] as Rect2).position.y if L.has("hotbar") else false:
		floor_y = minf(floor_y, maxf(band, hint_top - card_gap - line_h))
	# Плашка ещё не стоит, но ввод её потребует: оставляем под целью ряд и зазор,
	# иначе полоса садится на единственную широкую щель и ввод пропадает.
	# Выше границы трети не поднимаем — цель должна остаться в нижней трети.
	var grabs: Array = _grab_circles()
	var fs: int = UI.FONT["small"]
	var pad: float = CARD_LINE_PAD
	var icon: float = CARD_ICON_LINE
	var text_w: float = _tw(line, fs)
	var need: float = pad + icon + pad + text_w + pad
	# Плашка ещё не стоит. Если под целью останется ряд и зазор, а строка цели
	# всё ещё влезает выше — оставляем этот ряд плашке. Иначе цель как была.
	if not L.has("hint") and _plate_text() != "" and L.has("hotbar"):
		var plate_w: float = _tw(_plate_text(), _slot_font()) + (0.0 if portrait else 16.0)
		var plate_gap: float = HINT_GAP_LAND if not portrait else HINT_GAP_TOUCH
		var plate_h: float = HINT_H_LAND if not portrait else ROW_H
		var plate_top: float = (L["hotbar"] as Rect2).position.y - plate_gap
		# Ландшафт: ряд плашки фиксирован над хотбаром. Не ищем щель выше —
		# иначе цель отдаёт плашке верх трети и сама вытесняется.
		var plate_slot: Rect2 = Rect2()
		if not portrait:
			plate_slot = _grab_gap_slot(grabs, plate_top - plate_h, plate_top, plate_w, plate_h)
		else:
			plate_slot = _grab_gap_slot(grabs, band, plate_top, plate_w, plate_h)
		var card_h: float = CARD_H_TOUCH_MIN if plate_slot.position.y - plate_gap - CARD_H_TOUCH_LINE + 0.5 < band else CARD_H_TOUCH_LINE
		if plate_slot.has_area() and plate_slot.position.y + 0.5 >= band + plate_gap + card_h:
			var raised: float = maxf(band, plate_slot.position.y - plate_gap - card_h)
			if _card_x_gap(raised, card_h, need, [], grabs, 0.0, w).size.x + 0.5 >= need:
				floor_y = minf(floor_y, raised)
				line_h = card_h
	# Сначала ряд, куда строка влезает целиком при FONT.small, иконке 16 и полях 8.
	# Нет такого — режем поля и иконку. Всё ещё нет (стик и Q на 512 лог. px
	# оставляют 349, строка 381) — кегль, не текст и не «…».
	var picked: Rect2 = _card_pick_row(line_h, need, band, floor_y, L, grabs)
	while not picked.has_area() and pad > CARD_LINE_PAD_MIN + 0.01:
		pad = maxf(CARD_LINE_PAD_MIN, pad - 2.0)
		need = pad + icon + pad + text_w + pad
		picked = _card_pick_row(line_h, need, band, floor_y, L, grabs)
	while not picked.has_area() and icon > CARD_ICON_LINE_MIN + 0.01:
		icon = maxf(CARD_ICON_LINE_MIN, icon - 2.0)
		need = pad + icon + pad + text_w + pad
		picked = _card_pick_row(line_h, need, band, floor_y, L, grabs)
	while not picked.has_area() and icon > 0.5:
		icon = 0.0
		pad = 0.0
		need = text_w
		picked = _card_pick_row(line_h, need, band, floor_y, L, grabs)
	while not picked.has_area() and fs > CARD_FONT_LINE_MIN:
		fs -= 1
		text_w = _tw(line, fs)
		need = text_w
		picked = _card_pick_row(line_h, need, band, floor_y, L, grabs)
	if not picked.has_area():
		# Полосу не стираем: самый широкий ряд, даже если строка чуть шире.
		var best: Rect2 = Rect2()
		var yb: float = band
		while yb <= floor_y + 0.5:
			if not _card_row_blocked(yb, line_h, L):
				var gap: Rect2 = _card_x_gap(yb, line_h, need, [], grabs, 0.0, w)
				if gap.size.x > best.size.x:
					best = gap
			yb += 1.0
		picked = best if best.has_area() else Rect2(0.0, y0, w, line_h)
		while fs > CARD_FONT_LINE_MIN and _tw(line, fs) > picked.size.x + 0.5:
			fs -= 1
		text_w = _tw(line, fs)
	var cr: Rect2 = picked
	if cr.size.x > text_w + 0.5 and pad <= 0.5 and icon <= 0.5:
		var room: float = cr.size.x - text_w
		if room + 0.5 >= CARD_ICON_LINE_MIN + 3.0 * CARD_LINE_PAD_MIN:
			icon = CARD_ICON_LINE_MIN
			pad = CARD_LINE_PAD_MIN
		elif room + 0.5 >= 3.0 * CARD_LINE_PAD_MIN:
			pad = minf(CARD_LINE_PAD_MIN, floor(room / 3.0))
	if cr.position.y + 0.5 < band:
		cr.position.y = band
	if cr.size.y + 0.5 < CARD_H_TOUCH_MIN:
		cr.size.y = CARD_H_TOUCH_MIN
	elif cr.size.y > CARD_H_TOUCH_LINE + 0.5:
		cr.size.y = CARD_H_TOUCH_LINE
	# Рамка не шире щели: рост задевает захват. Текст уже вписан кеглем.
	if cr.size.x > picked.size.x:
		cr.size.x = picked.size.x
	L["card_icon_px"] = icon
	L["card_pad"] = pad
	L["card_font"] = fs
	return cr


## Ряд в [band, floor], куда строка ширины need влезает между захватами,
## не на плашку и не на хотбар. Сначала запрошенная высота, потом выше неё.
func _card_pick_row(line_h: float, need: float, band: float, floor_y: float, L: Dictionary, grabs: Array) -> Rect2:
	# Снизу вверх: самый нижний свободный ряд. Верхний (граница трети) оставляем
	# плашке ввода — иначе она пропадает, а цель садится в её щель.
	var y: float = floor_y
	while y + 0.5 >= band:
		if not _card_row_blocked(y, line_h, L):
			var gap: Rect2 = _card_x_gap(y, line_h, need, [], grabs, 0.0, size.x)
			if gap.size.x + 0.5 >= need:
				var cw: float = minf(need, gap.size.x)
				var cx: float = clampf((size.x - cw) * 0.5, gap.position.x, gap.end.x - cw)
				var cr: Rect2 = Rect2(cx, y, cw, line_h)
				if not _card_blocked(cr, [], grabs):
					return cr
				return Rect2(gap.position.x, y, cw, line_h)
		y -= 1.0
	return Rect2()


func _card_clear_rect(y: float, line_h: float, cw: float, need: float, avoid: Array, grabs: Array, lo: float, hi: float) -> Rect2:
	var cx: float = clampf((size.x - cw) * 0.5, lo, maxf(lo, hi - cw))
	var cr: Rect2 = Rect2(cx, y, cw, line_h)
	if not _card_blocked(cr, avoid, grabs):
		return cr
	var gap: Rect2 = _card_x_gap(y, line_h, need, avoid, grabs, lo, hi)
	if not gap.has_area():
		return Rect2()
	if gap.size.x + 0.5 >= cw:
		cx = clampf(cx, gap.position.x, gap.end.x - cw)
		cr = Rect2(cx, y, cw, line_h)
	elif gap.size.x + 0.5 >= need:
		cr = Rect2(gap.position.x, y, minf(gap.size.x, cw), line_h)
	else:
		return Rect2()
	if _card_blocked(cr, avoid, grabs):
		return Rect2()
	return cr


## Высота занята плашкой или хотбаром: туда полосу не опускаем.
func _card_row_blocked(y: float, line_h: float, L: Dictionary) -> bool:
	var row: Rect2 = Rect2(0.0, y, size.x, line_h)
	if L.has("hint") and row.intersects(L["hint"]):
		return true
	if L.has("hotbar") and row.intersects(L["hotbar"]):
		return true
	return false


## Силуэт игрока в центре логического холста. Тот же прямоугольник, что в тесте.
func _player_silhouette() -> Rect2:
	return Rect2(size * 0.5 - Vector2(24, 32), Vector2(48, 64))


func _card_blocked(r: Rect2, avoid: Array, grabs: Array) -> bool:
	return _hits(r, avoid) or _hits_grab(r, grabs)


## Свободный по X промежуток на высоте полосы: не задевает hint, хотбар, кнопки,
## силуэт и круги захвата. Пустой — промежутка шириной хотя бы 48 нет.
func _card_x_gap(y: float, line_h: float, _need: float, avoid: Array, grabs: Array, lo: float, hi: float) -> Rect2:
	var cuts: Array = []
	for b in avoid:
		var br: Rect2 = b
		if br.end.y <= y + 0.5 or br.position.y >= y + line_h - 0.5:
			continue
		if br.end.x <= lo or br.position.x >= hi:
			continue
		cuts.append([maxf(lo, br.position.x), minf(hi, br.end.x)])
	for g in grabs:
		var c: Vector2 = g["c"]
		var rad: float = float(g["r"])
		var dy: float = 0.0
		if c.y < y:
			dy = y - c.y
		elif c.y > y + line_h:
			dy = c.y - (y + line_h)
		if dy >= rad:
			continue
		var dx: float = sqrt(rad * rad - dy * dy)
		cuts.append([maxf(lo, c.x - dx), minf(hi, c.x + dx)])
	cuts.sort_custom(func(a, b): return a[0] < b[0])
	var best_x: float = lo
	var best_w: float = 0.0
	var cursor: float = lo
	for cut in cuts:
		if cut[0] - cursor > best_w:
			best_w = cut[0] - cursor
			best_x = cursor
		cursor = maxf(cursor, cut[1])
	if hi - cursor > best_w:
		best_w = hi - cursor
		best_x = cursor
	# Порог 48 отбрасывал единственную щель шире строки: на 512 лог. px она 393,
	# а строка 381. Узкий промежуток отсечёт вызывающий по need, не этот порог.
	if best_w <= 0.5:
		return Rect2()
	return Rect2(best_x, y, best_w, line_h)


## Строка полосы: «этап/всего  цель», при need > 1 ещё «  есть / нужно».
## 0 / 1 не пишем. Свободная игра — clampi(objective_stage, 1, 6); глава — stage главы.
func _card_line_text() -> String:
	if card_text == "":
		return ""
	var st: int = 1
	var total: int = Game.OBJECTIVE_STAGES
	if Game.in_mission() and Game.mission != null:
		st = int(Game.mission.stage) + 1
		total = maxi(1, int(Game.mission.stages_total()))
	else:
		st = clampi(Game.objective_stage, 1, Game.OBJECTIVE_STAGES)
		if Game.relay_active:
			st = Game.OBJECTIVE_STAGES
	var line: String = "%d/%d  %s" % [st, total, card_text]
	if card_need > 1:
		line += "  %d / %d" % [card_have, card_need]
	return line


func _place_touch_top(L: Dictionary, tb: Dictionary, band: float, portrait: bool, stack_top: float) -> void:
	var w: float = size.x
	var h: float = size.y
	var fb: int = UI.FONT["body"]
	var fs: int = UI.FONT["small"]
	var taken: Array = []
	for id in tb:
		taken.append(tb[id])
	var hint_top: float = stack_top
	if L.has("hint"):
		hint_top = (L["hint"] as Rect2).position.y
	var ceiling: float = hint_top - HINT_GAP_TOUCH
	# Плашка команды на телефоне скрыта: team_plate_rect — якорь кнопок меню
	# (TouchControls._layout). Сдвинуть её в нижнюю треть — сдвинуть I/J/паузу.
	var room: float = ceiling - band
	var y: float = band
	# Цель всегда на экране, пока есть текст: полоса 22–24 px над плашкой
	# (если она есть) иначе над хотбаром, зазор HINT_GAP_TOUCH, внутри нижней
	# трети. Не влезла по ширине — режем поля и иконку, не текст. Захват
	# сдвигает полосу по X, не стирает её.
	if player and card_text != "":
		var card_r: Rect2 = _place_touch_card(L, tb, band, hint_top)
		if card_r.has_area():
			L["card_line"] = true
			L["card"] = card_r
			_fit_card_title(L, card_r.size.x)
			taken.append(card_r)
			if card_r.position.y <= band + 0.5:
				y = card_r.end.y + 4.0
				room = ceiling - y
	# Карта после карточки: карточка важнее, карта берёт оставшийся карман.
	# Карта — ужатая 96×28, в нижней трети, не на кнопках. Сначала правый край,
	# не влезла — карман над рядом боя (кнопки не двигаем). 186×52 сюда не лезет.
	var map_r: Rect2 = _touch_map_rect(tb, band, h, [L.get("hint", Rect2()), L.get("hotbar", Rect2()), L.get("card", Rect2())])
	if map_r.has_area():
		L["map"] = map_r
		taken.append(map_r)
	# Ландшафт: полоса HP 4 px сразу под хотбаром. Ниже края — скрыта.
	if not portrait and player and L.has("hotbar"):
		var hb: Rect2 = L["hotbar"]
		var strip: Rect2 = Rect2(hb.position.x, hb.end.y, hb.size.x, 4.0)
		if strip.end.y <= h + 0.5 and strip.position.y + 0.5 >= band and not _hits(strip, taken):
			L["hp"] = strip
			taken.append(strip)
	# Здоровье и импульс — узкие полосы слева, под карточкой или вместо неё.
	if not L.has("hp") and player and room + 0.5 >= HP_H + 4.0 + EMP_H:
		var hp: Rect2 = Rect2(PAD, y, HP_W_TOUCH, HP_H)
		var emp: Rect2 = Rect2(PAD, y + HP_H + 4.0, HP_W_TOUCH, EMP_H)
		if emp.end.y <= ceiling + 0.5 and not _hits(hp, taken) and not _hits(emp, taken):
			L["hp"] = hp
			L["emp"] = emp
			taken.append(hp)
			taken.append(emp)
			y = emp.end.y + 4.0
			room = ceiling - y
	# Строка этапа — под здоровьем, если осталась высота строки.
	var rows: Array = _status_rows()
	L["rows"] = []
	if not rows.is_empty() and room + 0.5 >= ROW_H:
		var s_bottom: float = _status_place(rows, y, ceiling, taken)
		if not rows.is_empty():
			var sw: float = 0.0
			for r in rows:
				sw = maxf(sw, float(r["w"]))
			var sr: Rect2 = Rect2(PAD, y, sw + 20.0, s_bottom - y)
			if sr.position.y + 0.5 >= band and not _hits(sr, taken):
				L["rows"] = rows
				L["status"] = sr
				taken.append(sr)
				y = sr.end.y + 4.0
				room = ceiling - y
	# Сутки — справа, над картой, если полоса 34 px влезает.
	var dw: float = maxf(_tw(day_label(), fs), STRIP_W)
	if room + 0.5 >= 34.0:
		var dx: float = w - PAD - dw
		if L.has("map"):
			dx = minf(dx, (L["map"] as Rect2).position.x - 8.0 - dw)
		var dr: Rect2 = Rect2(maxf(PAD, dx), y, dw, 34.0)
		if dr.end.x <= w - PAD + 0.5 and dr.end.y <= ceiling + 0.5 and not _hits(dr, taken):
			L["day"] = dr
			taken.append(dr)
			y = maxf(y, dr.end.y + 4.0)
	if night_countdown >= 0:
		var cw2: float = _tw("НОЧЬ ЧЕРЕЗ %d с" % night_countdown, fs) + 24.0
		var cr2: Rect2 = Rect2((w - cw2) * 0.5, band, cw2, 26.0)
		if cr2.end.y <= ceiling + 0.5 and not _hits(cr2, taken):
			L["countdown"] = cr2
			taken.append(cr2)
	# Уведомления — над плашкой, в свободной полосе нижней трети. Не влезли — скрыты.
	_place_touch_notes(L, tb, taken, band, ceiling)


## Блок, чей прямоугольник пересекает захват кнопки, не рисуем: тап ушёл бы в кнопку.
func _drop_grab_hits(L: Dictionary) -> void:
	var grabs: Array = _grab_circles()
	if grabs.is_empty():
		return
	var drop: Array = []
	for id in ["hint", "map", "hp", "emp", "day", "status", "countdown", "notes"]:
		if L.has(id) and _hits_grab(L[id], grabs):
			drop.append(id)
	# Полосу цели не стираем: _place_touch_card уже сдвинула её по X.
	# Хотбар уже сужен до захватов выше. Здесь его не прячем: без него нет
	# нижней полосы, и тест «хотбар у нижнего края» падает.
	for id in drop:
		L.erase(id)
	if "status" in drop:
		L["rows"] = []


## Сузить прямоугольник по X, пока он не выйдет из кругов захвата. Высоту не трогаем.
func _shrink_off_grabs(r: Rect2, grabs: Array) -> Rect2:
	var lo: float = r.position.x
	var hi: float = r.end.x
	for g in grabs:
		var c: Vector2 = g["c"]
		var rad: float = float(g["r"])
		var dy: float = 0.0
		if c.y < r.position.y:
			dy = r.position.y - c.y
		elif c.y > r.end.y:
			dy = c.y - r.end.y
		if dy >= rad:
			continue
		var dx: float = sqrt(rad * rad - dy * dy)
		if c.x < (lo + hi) * 0.5:
			lo = maxf(lo, c.x + dx)
		else:
			hi = minf(hi, c.x - dx)
	if hi - lo < 48.0:
		return Rect2()
	return Rect2(lo, r.position.y, hi - lo, r.size.y)


func _hits(r: Rect2, taken: Array) -> bool:
	for b in taken:
		if (b as Rect2).intersects(r):
			return true
	return false


## Уведомления телефона: одна-две строки над плашкой, не на кнопках и не выше нижней трети.
func _place_touch_notes(L: Dictionary, tb: Dictionary, taken: Array, band: float, ceiling: float) -> void:
	if notes.is_empty():
		return
	var w: float = size.x
	var fb: int = UI.FONT["body"]
	var top: float = band
	for b in taken:
		var br: Rect2 = b
		if br.end.y > top and br.position.y < ceiling:
			top = maxf(top, br.end.y + 4.0)
	var n_bottom: float = ceiling
	var left: float = PAD
	var right: float = w - PAD
	for id in tb:
		var br2: Rect2 = tb[id]
		if br2.end.y > top and br2.position.y < n_bottom:
			if br2.position.x < w * 0.5:
				left = maxf(left, br2.end.x + PAD)
			else:
				right = minf(right, br2.position.x - PAD)
	if right - left < 120.0 or n_bottom - top < ROW_H:
		return
	var fit: int = int(floorf((n_bottom - top) / ROW_H))
	var cnt: int = clampi(mini(notes.size(), fit), 0, notes.size())
	var nw: float = 0.0
	var lines: Array = []
	for i in cnt:
		var nt: Dictionary = notes[notes.size() - 1 - i]
		var pad: float = 22.0 if int(nt.get("icon", 0)) > 0 else 0.0
		var txt: String = _fit_text(String(nt["text"]), fb, minf(right - left, 620.0) - pad)
		lines.append(txt)
		nw = maxf(nw, _tw(txt, fb))
	if cnt > 0:
		var nr: Rect2 = Rect2(right - nw, n_bottom - float(cnt) * ROW_H, nw, float(cnt) * ROW_H)
		if nr.position.y + 0.5 >= band and not _hits(nr, taken):
			L["notes"] = nr
			L["note_lines"] = lines




## Строки под карточкой: {text, kind, prio, color, w}. prio — порядок отбрасывания при
## нехватке места (больше — раньше). На экране — только подсказка этапа (в главе)
## и шаг обучения. Трекер, мощность и список задач карточка не дублирует (#160).
func _status_rows() -> Array:
	var rows: Array = []
	if tutorial_text != "" and Game.in_mission():
		rows.append({"text": tutorial_text, "kind": "tutorial", "prio": 1,
				"color": C_HAZARD.lerp(C_LINE, 0.35), "full": tutorial_text,
				"wide": UI.touch_on})
	return rows


## Ширина полосы нагрузки в строке мощности (с зазором), px.
const STATUS_BAR_W: float = 128.0


## Расставить строки от y0 вниз. Строка обрезается «…» до свободной ширины между левым краем
## и ближайшим блоком справа на её высоте (blockers: миникарта, плашка команды, тач-кнопки);
## места нет — строка отбрасывается. Не влезает до limit — отбрасываются самые «дальние»
## по prio. Возвращает низ блока.
func _status_place(rows: Array, y0: float, limit: float, blockers: Array) -> float:
	var fb: int = UI.FONT["body"]
	var fs: int = UI.FONT["small"]
	var y: float = y0
	while true:
		y = y0
		var kept: Array = []
		for r in rows:
			var bar: float = STATUS_BAR_W if r["kind"] == "power" else 0.0
			var avail: float = size.x - 2.0 * PAD - 20.0
			# Обучение на телефоне — на всю ширину под карточкой: карта кончается выше.
			var wide: bool = bool(r.get("wide", false))
			for b in blockers:
				if wide:
					continue
				var br: Rect2 = b
				if br.position.x > PAD + 40.0 and br.position.y < y + ROW_H and br.end.y > y:
					avail = minf(avail, br.position.x - 2.0 * PAD - 20.0)
			if avail - bar < 96.0:
				continue   # справа кнопка вплотную: строка не поместится
			# Длинная подсказка обучения на телефоне: если в body не влезает, берём small —
			# текст этапа обязан читаться целиком, а не обрываться «…».
			var fsize: int = fb
			var fit: String = _fit_text(String(r["full"]), fsize, avail - bar)
			if fit.ends_with("…"):
				if wide:
					fsize = fs
					fit = _fit_text(String(r["full"]), fsize, avail - bar)
				# На телефоне «…» нет: не влезла целиком — строка скрыта, не обрезана.
				if UI.touch_on and fit.ends_with("…"):
					continue
			r["text"] = fit
			r["font"] = fsize
			r["w"] = _tw(fit, fsize) + bar
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
		if _lay.has("hp"):
			var hp_rect: Rect2 = _lay["hp"]
			draw_rect(hp_rect, C_PLATE)
			var frac: float = clampf(player.hp / 100.0, 0.0, 1.0)
			# Здоровье — цвет скафандра; мало здоровья — цвет угрозы.
			var hp_col: Color = C_HP if frac > 0.35 else C_DANGER
			var hp_fill: Rect2 = Rect2(hp_rect.position + Vector2(2, 2), Vector2((hp_rect.size.x - 4) * frac, hp_rect.size.y - 4))
			draw_rect(hp_fill, hp_col)
			draw_rect(Rect2(hp_fill.position, Vector2(hp_fill.size.x, 2)), hp_col.lightened(0.3))
			draw_rect(hp_rect, Color(C_LINE, 0.35), false, 1.0)
			if hp_rect.size.y >= 16.0:
				_text_outlined(font, hp_rect.position + Vector2(8, 19), "%d" % int(player.hp), fb, Color(C_LINE, 0.95))

		# Индикатор заряда импульса: подпись — на самой полосе.
		if _lay.has("emp"):
			var emp_rect: Rect2 = _lay["emp"]
			draw_rect(emp_rect, C_PLATE)
			var ef: float = 1.0 - player.emp_cd / player.emp_max
			draw_rect(Rect2(emp_rect.position + Vector2(1, 1), Vector2((emp_rect.size.x - 2) * ef, emp_rect.size.y - 2)),
					Color(C_BIO, 0.55))
			_text_outlined(font, emp_rect.position + Vector2(6, 13), "ИМПУЛЬС [Q]" if not UI.touch_on else "Q", fs, Color(C_LINE, 0.95))

		# Карточка «Сейчас» и одна строка подсказки (#160)
		_draw_card(font)
		_draw_status_block(font)

	# ---- Время суток ---------------------------------------------------------
	# Полоса суток с квадратной меткой (ADR-003): днём метка жёлтая, ночью —
	# цвет угрозы. Метку ставим по квантованному времени — ровно тому, что в
	# ключе перерисовки. night — на уровне функции: скобки в конце _draw
	# читают ту же переменную и когда блока суток в раскладке нет.
	var night: bool = Game.is_night()
	var dl: float = Game.daylight()
	if _lay.has("day"):
		var day: Rect2 = _lay["day"]
		# На ПК day.y = 6: полоса на 30, метка на 26, текст на 21 — те же пиксели.
		var strip: Rect2 = Rect2(day.end.x - STRIP_W, day.position.y + 24.0, STRIP_W, 4)
		draw_rect(strip.grow(1.0), C_PLATE)
		draw_rect(strip, C_PLATE_HI)
		var tq: float = float(int(Game.time_of_day * float(CLOCK_STEPS))) / float(CLOCK_STEPS)
		var mx: float = roundf(strip.position.x + tq * strip.size.x)
		var sun: Color = C_DANGER if night else C_PLATE_HI.lerp(C_HAZARD, 0.35 + 0.65 * dl)
		draw_rect(Rect2(mx - 4, day.position.y + 20.0, 8, 12), C_PLATE)
		draw_rect(Rect2(mx - 3, day.position.y + 21.0, 6, 10), sun)
		_text_outlined(font, Vector2(day.end.x - _tw(day_label(), fs), day.position.y + 15.0), day_label(), fs,
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
			var icon_id: int = int(n.get("icon", 0))
			var pad: float = 22.0 if icon_id > 0 else 0.0
			if icon_id > 0:
				var tex: ImageTexture = DB.item_texture(icon_id)
				if tex:
					draw_texture_rect(tex, Rect2(nr.end.x - tw - 20.0, y - 14.0, 16.0, 16.0), false,
							Color(1, 1, 1, a))
			_text_outlined(font, Vector2(nr.end.x - tw, y), String(lines[i]), fb,
					Color(n["color"].r, n["color"].g, n["color"].b, a))
			y -= ROW_H

	# ---- Хотбар --------------------------------------------------------------
	if player:
		_draw_hotbar(font)

	# ---- Подсказки -----------------------------------------------------------
	if _lay.has("hint"):
		var hr: Rect2 = _lay["hint"]
		var hf: int = int(_lay.get("hint_font", fb))
		draw_rect(hr, C_PLATE)
		# ПК: базовая линия на 18, как раньше. Телефон — по ascent выбранного кегля.
		var hy: float = 18.0 if not UI.touch_on else 6.0 + font.get_ascent(hf)
		draw_string(font, hr.position + Vector2(8, hy), String(_lay["hint_text"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, hf, Color(C_INTERACT, 0.95))

	# ---- Подсказка управления (затухает) ------------------------------------
	# На телефоне три строки CONTROLS_TOUCH закрывали карточку и мир: ввод —
	# одна строка в нижней плашке (_intro_line). На ПК блок прежний.
	if Game.game_time < 22.0 and not UI.touch_on:
		var ta: float = clampf((22.0 - Game.game_time) / 6.0, 0.0, 1.0)
		var lines: Array = CONTROLS_KEYS
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


## Ширина карточки: иконка и текст заголовка (не уже счётчика). На ПК формула прежняя
## (иконка 48, зазор 8, заголовок title). На телефоне иконка 32, зазор 12, body/small.
## Потолок по карте считает вызывающий.
func _card_width_line() -> float:
	var line: String = _card_line_text() if UI.touch_on else card_text
	return CARD_LINE_PAD + CARD_ICON_LINE + CARD_LINE_PAD + _tw(line, UI.FONT["small"]) + CARD_LINE_PAD

func _card_width() -> float:
	var ft: int = _card_title_font()
	var fb: int = _card_sub_font()
	var tw: float = _tw(card_text, ft)
	if card_need > 1:
		tw = maxf(tw, _tw("%d / %d" % [card_have, card_need], fb))
	if card_mix:
		tw = maxf(tw, 92.0)
	if not UI.touch_on:
		return CARD_ICON + 16.0 + tw + 12.0
	return 8.0 + _card_icon() + 12.0 + tw + 12.0


## Заголовок и счётчик, вписанные в карточку: title → body → «…». На телефоне счётчик
## тоже подгоняется. Рисует _draw_card, читает тест. inner — ширина текста внутри рамки.
func _fit_card_title(L: Dictionary, cw: float) -> void:
	var pad: float = float(L.get("card_pad", CARD_LINE_PAD))
	var icon: float = float(L.get("card_icon_px", CARD_ICON_LINE))
	var inner: float = cw - pad - icon - pad - pad if L.get("card_line", false) else _card_inner(cw)
	var ft: int = _card_title_font()
	var title: String = card_text
	if L.get("card_line", false):
		# Кегль уже подобрал _place_touch_card под щель между захватами.
		var picked: int = int(L.get("card_font", UI.FONT["small"]))
		ft = picked if picked > 0 else UI.FONT["small"]
		title = _card_line_text()
	elif _fit_text(title, ft, inner).ends_with("…"):
		var smaller: int = UI.FONT["body"]
		if smaller < ft:
			ft = smaller
		title = _fit_text(title, ft, inner)
	else:
		title = _fit_text(title, ft, inner)
	L["card_title"] = title
	L["card_font"] = ft
	L["card_inner"] = inner
	if card_need > 1 and not L.get("card_line", false):
		var sf: int = _card_sub_font()
		L["card_counter"] = "%d / %d" % [card_have, card_need]
		L["card_sub_font"] = sf


## Ширина текста внутри карточки: слева поле и иконка, справа поле. На ПК зазор после
## иконки 8 (как раньше), на телефоне 12.
func _card_inner(cw: float) -> float:
	if UI.touch_on:
		return cw - 8.0 - _card_icon() - 12.0 - 12.0
	return cw - 8.0 - CARD_ICON - 8.0 - 12.0


## Карточка «Сейчас»: плашка 64 px, картинка 48×48, ≤ 6 слов, счётчик если need > 1.
func _draw_card(font: Font) -> void:
	if not _lay.has("card") or card_text == "":
		if _card_hit != null:
			_card_hit.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return
	var r: Rect2 = _lay["card"]
	if _card_hit != null:
		_card_hit.mouse_filter = Control.MOUSE_FILTER_STOP
		_card_hit.position = r.position
		_card_hit.size = r.size
	draw_rect(r, C_PLATE)
	draw_rect(r, Color(C_LINE, 0.35), false, 1.0)
	var touch: bool = UI.touch_on
	var line: bool = bool(_lay.get("card_line", false))
	var isz: float = float(_lay.get("card_icon_px", CARD_ICON_LINE)) if line else _card_icon()
	var icon_pad: float = float(_lay.get("card_pad", CARD_LINE_PAD)) if line else 8.0
	var icon_r: Rect2
	var tx: float = r.position.x + icon_pad
	if isz > 0.5:
		if touch:
			var iy: float = r.position.y + (r.size.y - isz) * 0.5
			icon_r = Rect2(Vector2(r.position.x + icon_pad, iy), Vector2(isz, isz))
		else:
			icon_r = Rect2(r.position + Vector2(8.0, 8.0), Vector2(CARD_ICON, CARD_ICON))
		draw_rect(icon_r, C_PLATE_HI)
		if card_icon >= 0:
			var tex: ImageTexture = DB.item_texture(card_icon)
			if tex:
				draw_texture_rect(tex, icon_r.grow(-4.0), false)
		else:
			_draw_stage_glyph(icon_r, tracker_stage)
		tx = icon_r.end.x + (float(_lay.get("card_pad", CARD_LINE_PAD)) if line else (12.0 if touch else 8.0))
	var ft: int = int(_lay.get("card_font", _card_title_font()))
	var title: String = String(_lay.get("card_title", card_text))
	if line:
		var ascent: float = font.get_ascent(ft)
		var base: float = r.position.y + (r.size.y - float(ft)) * 0.5 + ascent
		# Этап, цель и счётчик — одна строка, одна базовая линия. «…» нет.
		_text_outlined(font, Vector2(tx, base), title, ft, C_LINE)
	else:
		# ПК: те же координаты, что были до телефона. Текст уже вписан, длинная цель не лезет на карту.
		_text_outlined(font, Vector2(tx, r.position.y + 8.0 + float(ft)), title, ft, C_LINE)
		if card_mix:
			_draw_mix_row(Vector2(tx, r.position.y + 8.0 + float(ft) + 6.0))
		elif card_need > 1:
			var sf2: int = int(_lay.get("card_sub_font", UI.FONT["body"]))
			var counter2: String = String(_lay.get("card_counter", "%d / %d" % [card_have, card_need]))
			_text_outlined(font, Vector2(tx, r.position.y + 8.0 + float(ft) + 4.0 + float(sf2)),
					counter2, sf2, C_BIO.lerp(C_LINE, 0.25))


## Три смеси на карточке: R+G, G+B, R+B. Квадраты, без букв и клавиш.
func _draw_mix_row(at: Vector2) -> void:
	var pairs: Array = [[Beams.R, Beams.G], [Beams.G, Beams.B], [Beams.R, Beams.B]]
	var x: float = at.x
	for pair in pairs:
		draw_rect(Rect2(x, at.y, 6.0, 6.0), Beams.COLOR[int(pair[0])])
		draw_rect(Rect2(x + 8.0, at.y, 6.0, 6.0), Beams.COLOR[int(pair[1])])
		draw_rect(Rect2(x + 16.0, at.y, 6.0, 6.0), Beams.COLOR[int(pair[0]) | int(pair[1])])
		x += 30.0


## Пиктограмма этапа, когда у цели нет предмета: куб с дугами, молния — квадратами.
func _draw_stage_glyph(r: Rect2, stage: int) -> void:
	var c: Color = C_BIO.lerp(C_LINE, 0.2)
	var s: float = 6.0
	var o: Vector2 = r.position + (r.size - Vector2(s * 3.0, s * 3.0)) * 0.5
	if stage <= 1:
		# Антенна: мачта и перекладина.
		draw_rect(Rect2(o + Vector2(s, 0.0), Vector2(s, s * 3.0)), c)
		draw_rect(Rect2(o + Vector2(0.0, s), Vector2(s * 3.0, s)), c)
	elif stage == 2:
		# Жила: тёмный квадрат и яркая сердцевина.
		draw_rect(Rect2(o + Vector2(0.0, s), Vector2(s * 3.0, s)), c)
		draw_rect(Rect2(o + Vector2(s, 0.0), Vector2(s, s * 3.0)), c)
		draw_rect(Rect2(o + Vector2(s, s), Vector2(s, s)), C_LINE)
	elif stage == 3:
		# Луна: дуга из двух квадратов.
		draw_rect(Rect2(o + Vector2(s, 0.0), Vector2(s, s * 3.0)), c)
		draw_rect(Rect2(o + Vector2(s * 2.0, s), Vector2(s, s)), c)
	else:
		# Молния: три ступени.
		draw_rect(Rect2(o + Vector2(s, 0.0), Vector2(s * 2.0, s)), c)
		draw_rect(Rect2(o + Vector2(s, s), Vector2(s, s)), c)
		draw_rect(Rect2(o + Vector2(0.0, s * 2.0), Vector2(s * 2.0, s)), c)


## Стрелка-квадрат у края экрана и расстояние в клетках. Рамка на клетке цели —
## в мировом слое (_draw_card_frame): экранный прямоугольник отставал от камеры.
func _draw_card_arrow() -> void:
	if card_at == Vector2.INF or player == null or card_mark_on:
		return
	var inv_s: float = 1.0 / UI.ui_scale
	var xf: Transform2D = get_viewport().get_canvas_transform()
	var cell: Vector2i = World.world_to_cell(card_at)
	var vis: Rect2 = get_viewport().get_visible_rect()
	var center: Vector2 = vis.get_center()
	var target: Vector2 = xf * card_at
	var dir: Vector2 = target - center
	if dir.length_squared() < 1.0:
		return
	dir = dir.normalized()
	var half: Vector2 = vis.size * 0.5 - Vector2(CARD_ARROW_PAD, CARD_ARROW_PAD) * UI.ui_scale
	var scale: float = INF
	if absf(dir.x) > 0.001:
		scale = minf(scale, half.x / absf(dir.x))
	if absf(dir.y) > 0.001:
		scale = minf(scale, half.y / absf(dir.y))
	var tip: Vector2 = (center + dir * scale) * inv_s
	var box: float = CARD_ARROW
	var br: Rect2 = Rect2(tip - Vector2(box, box) * 0.5, Vector2(box, box))
	_mark.draw_rect(br, C_PLATE)
	_mark.draw_rect(br, C_INTERACT, false, 2.0)
	# Носик стрелки — маленький квадрат со стороны цели.
	var nose: Vector2 = dir * (box * 0.55)
	_mark.draw_rect(Rect2(br.get_center() + nose - Vector2(4, 4), Vector2(8, 8)), C_INTERACT)
	var dist: int = absi(cell.x - World.world_to_cell(player.global_position).x) \
			+ absi(cell.y - World.world_to_cell(player.global_position).y)
	var label: String = "%d" % dist
	var fs: int = UI.FONT["body"]
	_mark.draw_string(ThemeDB.fallback_font, br.position + Vector2(0, 20), label,
			HORIZONTAL_ALIGNMENT_CENTER, br.size.x, fs, C_LINE)


## Блок под карточкой: одна строка подсказки (что не влезло — уже отброшено).
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
		var fsize: int = int(r.get("font", fb))
		_text_on_plate(font, Vector2(tx, y + 19.0), String(r["text"]), fsize, r["color"])
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


func _slot_font() -> int:
	return SLOT_FONT


func _draw_hotbar(font: Font) -> void:
	var fs: int = _slot_font()
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
		if r.size.x >= SLOT_DIGIT_MIN:   # в узкой ячейке номер налез бы на значок
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
	var plate: Rect2 = _lay.get("team", Rect2()) if UI.touch_on else team_plate_rect(w, n)
	if plate.size.y < 1.0:
		return
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

