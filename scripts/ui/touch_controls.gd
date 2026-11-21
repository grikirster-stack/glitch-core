class_name TouchControls
extends CanvasLayer
## Сенсорное управление для телефона (#81): джойстик слева, кнопки справа,
## тап по миру — копать/бить, в режиме «строить» — ставить предмет из хотбара,
## хотбар — тапом по ячейке. Мультитач: каждый палец ведётся по своему индексу,
## поэтому можно идти джойстиком и копать тапом одновременно.
##
## Умный прицел (#149): клетка на экране — около 3 мм, палец её закрывает, поэтому
## тап не обязан попасть в клетку. Копка: твёрдая клетка под пальцем в радиусе —
## она, иначе первая твёрдая клетка по лучу от героя к пальцу (тап за стеной или за
## радиусом копает ближнюю стену), иначе соседка в полклетки от тапа; фантом рядом с
## тапом — удар по нему. Постройка: свободная клетка под пальцем, иначе последняя
## свободная по тому же лучу — блок встаёт со своей стороны препятствия. Цель обведена
## рамкой, пока палец на экране; вокруг героя — кольцо радиуса. Удержание копает по
## лучу дальше, но не дальше пальца; постройка — одна на клетку под пальцем, ведёшь
## пальцем — ставишь линией. Долгого тапа больше нет: он спорил с копкой.
##
## Зум — щипок двумя пальцами по миру (ViewZoom.set_now): второй палец лёг на мир, пока
## первый там, — оба ведут зум, а не копку. Чтобы щипок не успел копнуть или поставить
## блок первым пальцем (пальцы ложатся не разом), палец по миру начинает работать через
## PINCH_WAIT кадров; короткий тап, отпущенный раньше, всё равно срабатывает — ещё
## PULSE_FRAMES кадров после отпускания. Пока щипок, третий палец по миру ничего не делает,
## отпущен один палец щипка — второй тоже молчит до отпускания.
##
## Режим — кнопка «копать»/«строить» в ряду боя справа (рядом с E, бегом и прыжком),
## того же размера, что прыжок: над джойстиком она пересекала зону захвата стика.
## Тап по ячейке хотбара сам выбирает режим: блок или машина — «строить», остальное —
## «копать».
##
## Своей игровой логики здесь нет. Ввод идёт через тот же шов, что у сценариев:
## TouchControls заполняет Player.touch_input в формате test_input
## ({"keys", "mouse", "mouse_buttons"}), а ходьбу, прыжок, копку, постройку и E
## делает сам Player — ровно как с клавиатурой и мышью.
##
## Показ: DisplayServer.is_touchscreen_available() или флаг --touch (проверка на
## ПК; без сенсорного экрана мышь тогда шлёт касания — Input.emulate_touch_from_mouse).
## Без того и другого узел спит: ни _process, ни _input, Player.touch_input пуст.
##
## Эмуляция мыши из касаний (input_devices/pointing/emulate_mouse_from_touch,
## в проекте по умолчанию включена) остаётся: панели инвентаря и журнала получают
## тап как клик ЛКМ. Чтобы такой «клик» не копал мир под джойстиком, пока палец на
## экране, touch_input["mouse_buttons"] заменяет кнопки мыши целиком
## (Player._mouse_down), а клики по нашим кнопкам гасятся здесь, до панелей.
## Плашки HUD (карточка «Сейчас», полосы, карта) мышь пропускают — тап, начатый
## на них, сюда не доходит как клик и раньше копал мир под карточкой. Такой палец
## гасится здесь и в мир не идёт.
##
## Раскладка при 1280×720 (не перекрывает HUD): слева снизу — джойстик;
## справа снизу — «копать»/«строить», E, бег, прыжок (ниже уведомлений, правее
## хотбара); справа под миникартой — J, I, ниже — Q и V. Q и V рисуются, только
## когда импульс готов и рядом вентиляция. Размер кнопки — не меньше MIN_MM
## на экране (в портрете потолок k = 1.6 не даёт дотянуть до пола — P2).
## Портрет (тач и высота > 1.2 ширины, как HUD._compute_layout): стик слева внизу,
## кнопки действий справа внизу, меню/журнал/инвентарь справа сверху — внутри
## safe-area и выше полосы хотбара. Краевые элементы прижаты к DisplayServer
## .get_display_safe_area(); на desktop/headless область = весь экран, отступы 0.
## Всё рисуется одним Control и только при смене видимого состояния.
##
## Сеть (#135): в сетевой игре с товарищами есть G — перекличка (NetTeam читает G через
## тот же шов Player._key, у клиента она уходит счётчиком нажатий пакета ввода). Под
## миникартой тогда плашка команды (HUD.team_plate_rect): J и I встают под неё, а Q, V и
## G — одним рядом под ними (V слева от Q, G слева от V), чтобы колонка не опустилась
## на уведомления. В одиночной игре G нет, раскладка прежняя.
##
## Пауза (#119): ESC на телефоне нет — кнопка «меню» (две полосы паузы) в ряду I и J
## (слева от J) открывает паузу (UI.toggle_pause); то же — системная «Назад» Android
## (UI.go_back, #149). Пока пауза открыта, кнопок и джойстика нет: панель паузы —
## обычные кнопки, тап по ним приходит кликом.
##
## Автоскрытие: после AUTO_HIDE_SEC без касания контролы плавно гаснут (fade
## FADE_SEC), ввод выключается. Любое касание экрана возвращает их; этот первый
## тап игрового действия не вызывает. Пока палец на стике или кнопке — не гаснут.
## HUD (хотбар, полоса цели, подсказки) живёт в своём слое и не трогается. Пока
## открыто модальное окно (инвентарь, журнал, пауза) или экран финала — не гаснут:
## I и J в окне ещё нужны, а пауза глушит их сама.

## Слой: над HUD и панелями (UI — 10), под экраном финала (EndScreen.LAYER — 20).
const LAYER: int = 15
## Радиус обычной кнопки и кнопки прыжка, px при высоте экрана 720.
## Диаметр на экране — не меньше MIN_MM (пол 10 мм: NN/g «Touch Targets on
## Touchscreens», 2019). На мониторе k = 1, кнопки не раздуваются.
const BTN_R: float = 48.0
const JUMP_R: float = 58.0
## Джойстик: радиус основания и ручки, px.
const STICK_R: float = 100.0
const KNOB_R: float = 42.0
## Палец, поставленный чуть мимо основания, всё равно берёт джойстик (доля STICK_R).
const STICK_GRAB: float = 1.3
## Кнопка ловит палец чуть шире нарисованного круга (доля радиуса).
const BTN_GRAB: float = 1.12
## Минимальный диаметр кнопки на экране, мм. Крупнее BTN_R — раскладка растёт.
## Пол 10 мм — NN/g «Touch Targets on Touchscreens» (2019); 9 мм был ниже него.
## Портрет по-прежнему упирается в потолок k = 1.6 (P2): там диаметр около 7,8 мм.
const MIN_MM: float = 10.0
## Мёртвая зона джойстика по горизонтали и порог «вверх — прыжок» (доля радиуса).
const DEAD: float = 0.28
const STICK_JUMP: float = 0.6
## Умный прицел (#149): шаг луча от героя к пальцу, допуск тапа мимо копаемой клетки
## и радиус «тап по фантому» — px мира.
const RAY_STEP: float = 3.0
const AIM_SLOP: float = 12.0
const PHANTOM_GRAB: float = 26.0
## Цели нет.
const NO_CELL: Vector2i = Vector2i(-1, -1)
## Рамка цели: копка, постройка, фантом.
const C_DIG: Color = Color(1.0, 0.72, 0.32)
const C_BUILD: Color = Color(0.45, 0.9, 1.0)
const C_FOE: Color = Color(1.0, 0.4, 0.4)
## Короткий тап держит клавишу хотя бы столько физических кадров: нажатие и
## отпускание в одном кадре иначе прошли бы мимо Player.
const PULSE_FRAMES: int = 3
## Палец по миру начинает копать и строить через столько физических кадров (~67 мс):
## успеет лечь второй палец щипка, и щипок ничего не копнёт.
const PINCH_WAIT: int = 4
## Длина ключа видимого состояния (см. _fill_key).
const KEY_LEN: int = 16
## Без касания столько секунд — контролы гаснут. Касание сбрасывает отсчёт.
const AUTO_HIDE_SEC: float = 15.0
## Плавное гашение и появление, с. Пока идёт fade, ввод ещё жив: палец, лёгший
## в последнюю четверть секунды, не теряется.
const FADE_SEC: float = 0.25

## Кнопки: id, клавиша шва (0 — действие без клавиши), подпись крупно и мелко.
## Раскладка — в _layout().
const BUTTONS: Array = [
	{"id": "jump", "key": KEY_SPACE, "glyph": "", "cap": "прыжок"},
	{"id": "run", "key": KEY_SHIFT, "glyph": "", "cap": "бег"},
	{"id": "e", "key": KEY_E, "glyph": "E", "cap": "держать"},
	{"id": "q", "key": KEY_Q, "glyph": "Q", "cap": "импульс"},
	{"id": "v", "key": KEY_V, "glyph": "V", "cap": "укрытие"},
	{"id": "inv", "key": 0, "glyph": "I", "cap": "инвентарь"},
	{"id": "journal", "key": 0, "glyph": "J", "cap": "журнал"},
	{"id": "build", "key": 0, "glyph": "", "cap": "копать"},   # подпись — по режиму (#149)
	{"id": "g", "key": KEY_G, "glyph": "G", "cap": "перекличка"},   # только в сети (rollcall_shown)
	{"id": "pause", "key": 0, "glyph": "", "cap": "меню"},   # #119: ESC на телефоне
]

## Включено ли сенсорное управление (видно и читает касания).
var enabled: bool = false
## Режим «строить»: тап по миру ставит предмет (ПКМ), а не копает.
var build_mode: bool = false
## Клетка, по которой сейчас работает палец по миру (умный прицел, #149); NO_CELL — цели нет.
var aim_cell: Vector2i = NO_CELL
## Цель — фантом (бьём его), а не клетка.
var aim_foe: bool = false
## Бег защёлкой: тап — бежать, ещё тап — идти. Держать кнопку и джойстик
## одновременно неудобно.
var run_latched: bool = false

## Центры и радиусы кнопок по id (_layout).
var btn_center: Dictionary = {}
var btn_radius: Dictionary = {}
var stick_center: Vector2 = Vector2.ZERO
var stick_radius: float = STICK_R
## Отклонение джойстика, длина ≤ 1.
var stick_vec: Vector2 = Vector2.ZERO

var _pad: Control = null
var _layout_size: Vector2 = Vector2.ZERO
## Размер интерфейса, под который посчитана раскладка (UI.ui_scale).
var _layout_ui: float = 1.0
## Отступы safe-area в px канваса, под которые посчитана раскладка.
var _layout_insets: Vector4 = Vector4.ZERO
## Строк плашки команды, под которые сдвинута правая колонка (_team_rows; 0 — плашки нет).
var _layout_team: int = 0
## NetTeam (без типа — цикл зависимостей, как в HUD); ищется только в сети.
var _team: Node = null
var _k: float = 1.0
## Пальцы на экране: индекс -> {"kind": "stick"|"btn"|"world"|"hotbar"|"none", "id": String}.
var _fingers: Dictionary = {}
var _stick_finger: int = -1
var _world_finger: int = -1
var _world_screen: Vector2 = Vector2.ZERO
var _world_start: Vector2 = Vector2.ZERO
## Клетка под пальцем по миру: сменилась — прицел начинается заново.
var _world_cell: Vector2i = NO_CELL
## Допуск «мимо клетки» ещё действует: после первой выкопанной клетки копаем только
## строго по лучу к пальцу — удержание не уходит за палец.
var _world_loose: bool = true
## Постройка по этому касанию сделана — ждём, пока палец уйдёт на другую клетку.
var _world_spent: bool = false
## Кадров до того, как палец по миру начнёт работать (PINCH_WAIT).
var _world_wait: int = 0
## Короткий тап отпущен до конца ожидания: столько кадров он ещё работает по _world_screen.
var _world_ghost: int = 0
## Щипок: пальцы (−1 — щипка нет), расстояние между ними и зум в начале.
var _pinch_a: int = -1
var _pinch_b: int = -1
var _pinch_dist: float = 1.0
var _pinch_zoom: float = ViewZoom.DEFAULT
## Мировая точка цели для шва (центр клетки или фантом) и направление ленты или
## манипулятора под прицелом (поворот — один на касание; -1 — не они).
var _aim_point: Vector2 = Vector2.ZERO
var _aim_dir: int = -1
## Пальцев на кнопке (id -> int) и оставшиеся кадры короткого нажатия (id -> int).
var _btn_hold: Dictionary = {}
var _btn_pulse: Dictionary = {}
## Секунды без касания. AUTO_HIDE_SEC — пора гаснуть. Пока палец на стике или
## кнопке, отсчёт стоит на нуле.
var idle_sec: float = 0.0
## 1 — контролы видны, 0 — скрыты. Между — плавное гашение или появление.
var controls_alpha: float = 1.0
## Контролы погасли и ввод выключен. Касание экрана их вернёт, само действие
## не вызовет (reveal_armed).
var controls_hidden: bool = false
## Следующее касание только возвращает контролы и поглощается.
var reveal_armed: bool = false
## Состояние шва: живут всё время, меняются только значения — без аллокаций.
var _keys: Dictionary = {}
var _mbtn: Dictionary = {MOUSE_BUTTON_LEFT: false, MOUSE_BUTTON_RIGHT: false}
var _key: PackedInt32Array = PackedInt32Array()
var _last_key: PackedInt32Array = PackedInt32Array()


func _ready() -> void:
	layer = LAYER
	name = "TouchControls"
	add_to_group("touch_controls")
	# Пауза ставит дерево на paused. Отсчёт бездействия и fade должны дотикать,
	# иначе контролы зависнут полупрозрачными, пока меню открыто.
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -10   # шов заполняем до Player._physics_process
	_key.resize(KEY_LEN)
	for b in BUTTONS:
		if int(b["key"]) != 0:
			_keys[int(b["key"])] = false
	for k in [KEY_A, KEY_D, KEY_W]:
		_keys[k] = false
	_pad = Control.new()
	_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pad.draw.connect(_draw_pad)
	add_child(_pad)
	var forced: bool = OS.get_cmdline_user_args().has("--touch")
	var touch: bool = DisplayServer.is_touchscreen_available()
	if forced and not touch:
		# Проверка на ПК: ЛКМ шлёт касание — кнопки и джойстик жмутся мышью.
		Input.emulate_touch_from_mouse = true
	set_enabled(touch or forced)


## Включить или выключить сенсорное управление (сценарии включают его сами).
func set_enabled(on: bool) -> void:
	enabled = on
	UI.touch_on = on   # подсказки HUD — про тапы, а не про ЛКМ и ПКМ
	visible = on
	set_process(on)
	set_physics_process(on)
	set_process_input(on)
	release_all()
	_show_controls()
	var p: Player = _player()
	if p != null:
		p.touch_input = {"keys": _keys} if on else {}
	if on:
		_relayout()


## Контролы видны и принимают ввод (не погасли по бездействию).
func controls_shown() -> bool:
	return enabled and not controls_hidden and controls_alpha > 0.0


## Вернуть контролы сразу: альфа 1, отсчёт бездействия с нуля, ввод включён.
func _show_controls() -> void:
	idle_sec = 0.0
	controls_alpha = 1.0
	controls_hidden = false
	reveal_armed = false
	if _pad != null:
		_pad.modulate = Color(1, 1, 1, 1)
		_pad.queue_redraw()


## Погасить до конца: альфа 0, ввод выключен, следующее касание только вернёт.
func _hide_controls() -> void:
	controls_alpha = 0.0
	controls_hidden = true
	reveal_armed = true
	release_all()
	if _pad != null:
		_pad.modulate = Color(1, 1, 1, 0)


## Отпустить все пальцы: смерть, пауза приложения, выключение.
func release_all() -> void:
	_fingers.clear()
	_btn_hold.clear()
	_btn_pulse.clear()
	_stick_finger = -1
	_world_finger = -1
	_world_ghost = 0
	_pinch_a = -1
	_pinch_b = -1
	aim_cell = NO_CELL
	aim_foe = false
	stick_vec = Vector2.ZERO
	for k in _keys:
		_keys[k] = false
	var p: Player = _player()
	if p != null:
		p.touch_input.erase("mouse_buttons")
		p.touch_input.erase("mouse")


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		release_all()


func _player() -> Player:
	var p = Game.player
	if p == null or not is_instance_valid(p):
		return null
	return p


## Управление сейчас работает: герой жив, забег идёт. Автоскрытие сюда не входит:
## рисунок и условные Q/V/пауза живут как раньше, ввод глушит controls_hidden.
func _active() -> bool:
	var p: Player = _player()
	return enabled and p != null and not p.dead and Game.state == Game.State.PLAYING


## Открыто окно, которое забирает ввод, или экран финала/смерти. Пока так —
## контролы не гаснут: I и J в инвентаре и журнале ещё нужны, пауза глушит
## кнопки сама (_shown), а финал живёт выше и тап по нему не наш.
func _modal_open() -> bool:
	if UI.blocking():
		return true
	var sc: Node = get_tree().current_scene if get_tree() != null else null
	if sc == null:
		return false
	var end: Node = sc.get("end_screen")
	return end != null and is_instance_valid(end) and bool(end.visible)


# ------------------------------------------------------------------ РАСКЛАДКА

## Кнопка переклички G есть: сетевая игра и в ней есть товарищи.
func rollcall_shown() -> bool:
	return Net.is_online() and Game.players.size() > 1


## Идёт перекличка (кнопка G подсвечена: тап — ответить).
func _rollcall_on() -> bool:
	if not rollcall_shown():
		return false
	if _team == null or not is_instance_valid(_team):
		_team = get_tree().get_first_node_in_group("net_team")
	return _team != null and bool(_team.call("rollcall_on"))


## Товарищей на плашке команды HUD (её рисует HUD при игроках > 1): 0 — плашки нет.
## force_team_rows >= 0 — подстановка теста (headless сети не поднимает).
func _team_rows() -> int:
	if force_team_rows >= 0:
		return force_team_rows
	return mini(Game.players.size() - 1, HUD.TEAM_MAX) if Game.players.size() > 1 else 0


## Кнопку видно и она жмётся: G — только в сети, при открытой панели — только I и J.
## Q и V в боевом ряду не живут: Q — пока импульс готов, V — пока рядом вентиляция
## или герой уже в ней (выйти). Дырка в ряду, центры не едут. Клавиши Q и V на ПК
## читает Player._key из Input — видимость кнопки их не глушит.
func _shown(id: String, blocking: bool) -> bool:
	if UI.pause != null and UI.pause.visible:
		return false   # #119: в паузе — только её панель
	if blocking and id != "inv" and id != "journal":
		return false
	if id == "q":
		return _q_ready()
	if id == "v":
		return _v_ready()
	return id != "g" or rollcall_shown()


## Импульс готов: тот же emp_cd, что пускает Player._empulse. Героя нет — кнопку не рисуем.
func _q_ready() -> bool:
	var p: Player = _player()
	return p != null and p.emp_cd <= 0.0


## Вентиляция рядом — тот же порог 40 px, что у Player._toggle_hide. В укрытии кнопка
## остаётся: иначе из вентиляции не выйти. Отдельного «рядом» в игре нет — не выдумываем.
func _v_ready() -> bool:
	var p: Player = _player()
	if p == null:
		return false
	if p.hiding:
		return true
	for v in World.vents:
		if World.cell_to_world(v).distance_to(p.global_position) < 40.0:
			return true
	return false


## Множитель раскладки, заданный тестом (> 0): окно headless — 64×64 px, по нему dpi не посчитать.
var force_k: float = 0.0
## Отступы safe-area, заданные тестом (лево, верх, право, низ), px канваса. Отрицательное —
## читать DisplayServer. На desktop/headless безопасная область = весь экран.
var force_insets: Vector4 = Vector4(-1, -1, -1, -1)
## Строк плашки команды, заданных тестом. Отрицательное — считать по Game.players.
var force_team_rows: int = -1


## Множитель раскладки: кнопка не меньше MIN_MM на экране этого устройства.
func _scale() -> float:
	if force_k > 0.0:
		return force_k
	var dpi: int = DisplayServer.screen_get_dpi()
	var win: Vector2i = get_window().size
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if dpi <= 0 or win.y <= 0 or vp.y <= 0.0:
		return 1.0
	var px_per_mm: float = float(dpi) / 25.4 * vp.y / float(win.y)
	return clampf(MIN_MM * px_per_mm / (BTN_R * 2.0), 1.0, 1.6)


func _relayout() -> void:
	_layout_size = get_viewport().get_visible_rect().size
	_layout_ui = UI.ui_scale
	_layout_team = _team_rows()
	_layout_insets = safe_insets(_layout_size)
	_layout(_layout_size)
	_pad.queue_redraw()


## Портрет — как HUD._compute_layout: тач и высота > 1.2 ширины. Иначе ландшафт.
func _portrait(sz: Vector2) -> bool:
	return UI.touch_on and sz.y > sz.x * 1.2


## Отступы safe-area в px канваса контрола: (лево, верх, право, низ).
## DisplayServer.get_display_safe_area() — экранные пиксели. В те же единицы
## канваса: (окно / экран) × (канвас / окно) = канвас / экран — окно сокращается,
## доли выреза от экрана переносятся на холст. На desktop/headless безопасная
## область = весь экран — отступы нулевые. Тест подставляет force_insets.
func safe_insets(canvas: Vector2) -> Vector4:
	if force_insets.x >= 0.0:
		return force_insets
	var screen: Vector2i = DisplayServer.screen_get_size()
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	if screen.x <= 0 or screen.y <= 0 or safe.size.x <= 0 or safe.size.y <= 0:
		return Vector4.ZERO
	var win: Vector2i = DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0:
		win = get_window().size
	if win.x <= 0 or win.y <= 0 or canvas.x <= 0.0 or canvas.y <= 0.0:
		return Vector4.ZERO
	# Экранные px → px окна (окно может быть меньше экрана), затем → px канваса.
	var to_canvas: Vector2 = Vector2(canvas.x / float(win.x), canvas.y / float(win.y))
	var win_over_screen: Vector2 = Vector2(float(win.x) / float(screen.x), float(win.y) / float(screen.y))
	var s: Vector2 = win_over_screen * to_canvas
	var left: float = maxf(0.0, float(safe.position.x) * s.x)
	var top: float = maxf(0.0, float(safe.position.y) * s.y)
	var right: float = maxf(0.0, float(screen.x - safe.end.x) * s.x)
	var bottom: float = maxf(0.0, float(screen.y - safe.end.y) * s.y)
	# Вырез больше канваса — не сдвигаем элементы за противоположный край.
	if left + right >= canvas.x:
		left = 0.0
		right = 0.0
	if top + bottom >= canvas.y:
		top = 0.0
		bottom = 0.0
	return Vector4(left, top, right, bottom)


func _layout(sz: Vector2) -> void:
	_k = _scale()
	var r: float = BTN_R * _k
	var jr: float = JUMP_R * _k
	var m: float = 24.0 * _k
	var g: float = 14.0 * _k
	var inset: Vector4 = safe_insets(sz)
	_layout_insets = inset
	stick_radius = STICK_R * _k
	var left: float = inset.x
	var top_in: float = inset.y
	var right: float = inset.z
	var bottom: float = inset.w
	if _portrait(sz):
		_layout_portrait(sz, r, jr, m, g, left, top_in, right, bottom)
		return
	# Ландшафт. «копать»/«строить» — в ряду боя, не над стиком. Отступы нулевые
	# на desktop — колонка I/J/паузы на прежних местах.
	stick_center = Vector2(left + m + 10.0 * _k + stick_radius, sz.y - bottom - m - stick_radius)
	var jump: Vector2 = Vector2(sz.x - right - m - jr, sz.y - bottom - m - jr)
	var run: Vector2 = Vector2(jump.x - jr - g - r, sz.y - bottom - m - r)
	# Под правым столбцом HUD (миникарта, плашка команды: HUD.right_column_bottom) — I и J,
	# под ними столбиком Q и V. В сети с товарищами и при размере интерфейса выше 100 % —
	# Q, V и G (перекличка) одним рядом: колонка ниже налезла бы на уведомления и нижние кнопки.
	# 126 — прежний якорь под миникартой; вырез только поднимает его, не опускает.
	var top: float = maxf(126.0, top_in + m + r)
	top = maxf(top, HUD.right_column_bottom(sz.x / UI.ui_scale, _layout_team) * UI.ui_scale + 8.0)
	var inv: Vector2 = Vector2(sz.x - right - m - r, top + r)
	var step: float = 2.0 * r + g
	var q: Vector2 = Vector2(inv.x, inv.y + step)
	var v: Vector2 = Vector2(inv.x, q.y + step)
	var one_row: bool = _layout_team > 0 or UI.ui_scale > 1.0
	if one_row:
		v = Vector2(q.x - step, q.y)
	var e: Vector2 = Vector2(run.x - step, run.y)
	# «копать»/«строить» — четвёртая кнопка ряда боя, слева от E, размером с прыжок.
	# Над стиком её круг захвата пересекал джойстик (зазор около −10 px при k=1).
	# Центры I/J/паузы и Q/V/G не трогаем: сценарий стережёт колонку I.
	var build: Vector2 = Vector2(e.x - r - g - jr, e.y)
	btn_center = {
		"jump": jump,
		"run": run,
		"e": e,
		"inv": inv,
		"journal": Vector2(inv.x - step, inv.y),
		"pause": Vector2(inv.x - 2.0 * step, inv.y),   # #119
		"q": q,
		"v": v,
		"g": Vector2(v.x - step, q.y) if one_row else Vector2(q.x - step, q.y),
		"build": build,
	}
	btn_radius = {}
	for id in btn_center:
		btn_radius[id] = jr if id == "jump" or id == "build" else r


## Портрет: стик слева внизу, действия справа внизу, меню/пауза сверху справа.
## Ряд меню — под правым столбцом HUD: миникарта и, в сети, плашка команды
## (HUD.right_column_bottom). Нижний ряд — выше полосы хотбара (хотбар сидит
## над верхом стика/кнопок). Q/V/G — справа, ниже карточки «Сейчас» (HUD кладёт
## её под ряд меню): слева накрыли бы карточку, над стиком — полосу хотбара.
func _layout_portrait(sz: Vector2, r: float, jr: float, m: float, g: float,
		left: float, top_in: float, right: float, bottom: float) -> void:
	var step: float = 2.0 * r + g
	stick_center = Vector2(left + m + 10.0 * _k + stick_radius, sz.y - bottom - m - stick_radius)
	var jump: Vector2 = Vector2(sz.x - right - m - jr, sz.y - bottom - m - jr)
	var run: Vector2 = Vector2(jump.x, jump.y - jr - g - r)
	var e: Vector2 = Vector2(jump.x - jr - g - r, jump.y)
	var build: Vector2 = Vector2(e.x, run.y)
	# Меню / журнал / инвентарь — правый верх, под вырезом и под правым столбцом
	# HUD (миникарта, плашка команды: HUD.right_column_bottom — как ландшафт).
	# При нуле товарищей низ столбца = низ миникарты, ряд не сдвигается. Карточка
	# задания опускается под этот ряд сама.
	var col_bottom: float = HUD.right_column_bottom(sz.x / UI.ui_scale, _layout_team) * UI.ui_scale
	var row_y: float = maxf(top_in + m + r, col_bottom + 8.0 + r)
	# Горизонталь — у правого края, не у выреза. Левый отступ safe-area (панель
	# задач на desktop, вырез слева) сдвигал бы ряд на карточку «Сейчас»: HUD
	# режет её только по миникарте и сам этот ряд не двигает. Верхний вырез
	# поднимает ряд (row_y), правый — нижние действия.
	var inv: Vector2 = Vector2(sz.x - m - r, row_y)
	var journal: Vector2 = Vector2(inv.x - step, row_y)
	var pause: Vector2 = Vector2(inv.x - 2.0 * step, row_y)
	# Q, V, G — правый край, ниже карточки «Сейчас». HUD опускает её под ряд
	# pause/journal/inv (низ круга + 4 лог. px, высота CARD_H_TOUCH) и сам
	# этот ряд не двигает. Сразу под кругами кнопки накрыли бы карточку.
	var card_end: float = row_y + r + (4.0 + HUD.CARD_H_TOUCH) * UI.ui_scale
	var q: Vector2 = Vector2(inv.x, card_end + 8.0 * UI.ui_scale + r)
	var v: Vector2 = Vector2(journal.x, q.y)
	var gg: Vector2 = Vector2(pause.x, q.y)
	btn_center = {
		"jump": jump,
		"run": run,
		"e": e,
		"inv": inv,
		"journal": journal,
		"pause": pause,
		"q": q,
		"v": v,
		"g": gg,
		"build": build,
	}
	btn_radius = {}
	for id in btn_center:
		btn_radius[id] = jr if id == "jump" else r


## Что под пальцем: "stick", id кнопки или "". При открытой панели живы только I и J,
## G — только в сети (_shown). Погасшие контролы палец не ловят.
func control_at(pos: Vector2) -> String:
	if controls_hidden or controls_alpha <= 0.0:
		return ""
	var blocking: bool = UI.blocking()
	var best: String = ""
	var best_d: float = INF
	for id in btn_center:
		if not _shown(id, blocking):
			continue
		var d: float = pos.distance_to(btn_center[id])
		if d <= float(btn_radius[id]) * BTN_GRAB and d < best_d:
			best = id
			best_d = d
	if best != "":
		return best
	if not blocking and pos.distance_to(stick_center) <= stick_radius * STICK_GRAB:
		return "stick"
	return ""


## Ячейка хотбара под пальцем или -1. Перебираем inv.hotbar_size, не вшитую десятку (#161):
## пустое место за 6-й ячейкой — не хотбар.
func hotbar_slot_at(pos: Vector2) -> int:
	var hud: HUD = UI.hud
	if hud == null:
		return -1
	var n: int = hud._hotbar_count()
	for i in n:
		if hud.hotbar_slot_rect(i).grow(2.0).has_point(pos):
			return i
	return -1


# ------------------------------------------------------------------ КАСАНИЯ

func _input(event: InputEvent) -> void:
	if not enabled:
		return
	var eat: bool = false
	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		if st.pressed and (reveal_armed or controls_hidden):
			# Первый тап после автоскрытия только возвращает контролы.
			_show_controls()
			get_viewport().set_input_as_handled()
			return
		idle_sec = 0.0
		eat = _finger_down(st.index, st.position) if st.pressed else _finger_up(st.index)
	elif event is InputEventScreenDrag:
		if controls_hidden:
			return
		idle_sec = 0.0
		var sd: InputEventScreenDrag = event
		eat = _finger_move(sd.index, sd.position)
	elif event is InputEventMouseButton:
		# Клик (настоящий или эмулированный из касания) по нашей кнопке — не панелям.
		eat = controls_shown() and _active() and control_at((event as InputEventMouseButton).position) != ""
	if eat:
		get_viewport().set_input_as_handled()


## Палец коснулся экрана. true — касание наше (кнопка, джойстик, хотбар).
func _finger_down(index: int, pos: Vector2) -> bool:
	if not _active() or controls_hidden:
		return false
	var hit: String = control_at(pos)
	if hit == "stick" and _stick_finger < 0:
		_stick_finger = index
		_fingers[index] = {"kind": "stick", "id": ""}
		_set_stick(pos)
		return true
	if hit != "" and hit != "stick":
		_fingers[index] = {"kind": "btn", "id": hit}
		_press(hit)
		return true
	if UI.blocking():
		return false   # тап по панели — панели (эмулированным кликом)
	# Карточка «Сейчас» и остальные плашки HUD не ловят касание (HUD пропускает мышь),
	# но нарисованы поверх мира. Палец, начатый на них, не копает и не ставит.
	var hud: HUD = UI.hud
	if hud != null and hud.covers_screen(pos):
		_fingers[index] = {"kind": "hud", "id": ""}
		return true
	var slot: int = hotbar_slot_at(pos)
	if slot >= 0:
		var inv: Inventory = _player().inv
		inv.selected = slot
		# Взял блок или машину — строим, остальное — копаем (#149).
		var st: ItemStack = inv.selected_stack()
		build_mode = not st.is_empty() and DB.item_place(st.id) != ""
		_fingers[index] = {"kind": "hotbar", "id": ""}
		return true
	if _world_finger >= 0 and _pinch_a < 0 and _zoom() != null:
		_pinch_start(index, pos)
		return true
	if _world_finger < 0 and _pinch_a < 0:
		_world_finger = index
		_world_screen = pos
		_world_start = pos
		_world_wait = PINCH_WAIT
		_world_ghost = 0
		_world_aim_reset(pos)
		_fingers[index] = {"kind": "world", "id": ""}
	else:
		_fingers[index] = {"kind": "none", "id": ""}
	return false


func _finger_up(index: int) -> bool:
	if not _fingers.has(index):
		return false
	var f: Dictionary = _fingers[index]
	_fingers.erase(index)
	var kind: String = String(f["kind"])
	match kind:
		"stick":
			_stick_finger = -1
			stick_vec = Vector2.ZERO
		"btn":
			var id: String = String(f["id"])
			_btn_hold[id] = maxi(0, int(_btn_hold.get(id, 0)) - 1)
		"world":
			_world_finger = -1
			if _world_wait > 0:
				_world_ghost = PULSE_FRAMES   # короткий тап: отработает и отпущенный
				_world_wait = 0
			else:
				aim_cell = NO_CELL
				aim_foe = false
		"pinch":
			var other: int = _pinch_b if index == _pinch_a else _pinch_a
			if _fingers.has(other):
				_fingers[other] = {"kind": "none", "id": ""}   # оставшийся палец не копает
			_pinch_a = -1
			_pinch_b = -1
	return kind == "stick" or kind == "btn" or kind == "hotbar" or kind == "pinch" or kind == "hud"


func _finger_move(index: int, pos: Vector2) -> bool:
	if not _fingers.has(index):
		return false
	var kind: String = String(_fingers[index]["kind"])
	if kind == "stick":
		_set_stick(pos)
	elif kind == "world":
		_world_screen = pos
		if World.world_to_cell(world_point(pos)) != _world_cell:
			_world_aim_reset(pos)   # палец ушёл на другую клетку — прицел заново
	elif kind == "pinch":
		_fingers[index]["pos"] = pos
		_pinch_update()
	return kind == "stick" or kind == "btn" or kind == "hotbar" or kind == "pinch" or kind == "hud"


## Палец по миру встал на новую клетку: допуск снова действует, постройка снова можно.
func _world_aim_reset(pos: Vector2) -> void:
	_world_cell = World.world_to_cell(world_point(pos))
	_world_loose = true
	_world_spent = false


func _set_stick(pos: Vector2) -> void:
	stick_vec = ((pos - stick_center) / stick_radius).limit_length(1.0)


## Нажата кнопка: окна и защёлки — сразу, клавиши шва — пока палец на кнопке.
func _press(id: String) -> void:
	match id:
		"inv":
			UI.toggle_inventory()
		"journal":
			UI.toggle_journal()
		"pause":
			UI.toggle_pause()   # #119
		"run":
			run_latched = not run_latched
		"build":
			build_mode = not build_mode
		_:
			_btn_hold[id] = int(_btn_hold.get(id, 0)) + 1
			_btn_pulse[id] = PULSE_FRAMES


## Кнопка «нажата» для шва: палец на ней или короткий тап ещё не дожит.
func held(id: String) -> bool:
	return int(_btn_hold.get(id, 0)) > 0 or int(_btn_pulse.get(id, 0)) > 0


## Мировая точка под пальцем (та же формула, что get_global_mouse_position).
func world_point(screen: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen


# ------------------------------------------------------------------ ЩИПОК

## Зум камеры своего героя или null.
func _zoom() -> ViewZoom:
	var p: Player = _player()
	return p.view_zoom if p != null and p.view_zoom != null and p.view_zoom.allowed() else null


## Второй палец лёг на мир, пока первый там: оба — щипок, копка первого отменяется.
func _pinch_start(index: int, pos: Vector2) -> void:
	_pinch_a = _world_finger
	_pinch_b = index
	_fingers[_pinch_a] = {"kind": "pinch", "id": "", "pos": _world_screen}
	_fingers[_pinch_b] = {"kind": "pinch", "id": "", "pos": pos}
	_world_finger = -1
	_world_wait = 0
	aim_cell = NO_CELL
	aim_foe = false
	_pinch_dist = maxf(_world_screen.distance_to(pos), 1.0)
	_pinch_zoom = _zoom().current


## Пальцы щипка сдвинулись: зум — во столько раз, во сколько изменилось расстояние.
func _pinch_update() -> void:
	var z: ViewZoom = _zoom()
	if z == null or not _fingers.has(_pinch_a) or not _fingers.has(_pinch_b):
		return
	var d: float = Vector2(_fingers[_pinch_a]["pos"]).distance_to(Vector2(_fingers[_pinch_b]["pos"]))
	z.set_now(_pinch_zoom * d / _pinch_dist)


# ------------------------------------------------------------------ ШОВ

func _physics_process(delta: float) -> void:
	_tick_autohide(delta)
	var p: Player = _player()
	if p == null:
		return
	if not _active() or controls_hidden:
		if not _fingers.is_empty() or bool(_keys.get(KEY_SHIFT, false)):
			release_all()
		return
	if not p.touch_input.has("keys"):
		p.touch_input["keys"] = _keys   # сценарий мог снять шов
	_keys[KEY_A] = stick_vec.x < -DEAD
	_keys[KEY_D] = stick_vec.x > DEAD
	_keys[KEY_W] = stick_vec.y < -STICK_JUMP
	_keys[KEY_SPACE] = held("jump")
	_keys[KEY_SHIFT] = run_latched
	_keys[KEY_E] = held("e")
	# Скрытая кнопка палец не держит и шов не жмёт. Клавиатура идёт мимо: Player._key
	# читает Input, если шов не зажат.
	var blocking: bool = UI.blocking()
	_keys[KEY_Q] = _shown("q", blocking) and held("q")
	_keys[KEY_V] = _shown("v", blocking) and held("v")
	_keys[KEY_G] = held("g")
	for id in _btn_pulse:
		_btn_pulse[id] = maxi(0, int(_btn_pulse[id]) - 1)
	# Пока палец на экране, кнопки мыши — только наши: эмулированный клик
	# под джойстиком или кнопкой мир не копает.
	if _fingers.is_empty() and _world_ghost <= 0:
		p.touch_input.erase("mouse_buttons")
		p.touch_input.erase("mouse")
		return
	var waiting: bool = _world_finger >= 0 and _world_wait > 0
	if waiting:
		_world_wait -= 1   # ждём второй палец щипка: мир пока не трогаем
	var world: bool = (_world_finger >= 0 and not waiting) or _world_ghost > 0
	if world:
		_update_aim(p)
	var aimed: bool = world and aim_cell != NO_CELL
	_mbtn[MOUSE_BUTTON_LEFT] = aimed and not build_mode
	_mbtn[MOUSE_BUTTON_RIGHT] = aimed and build_mode
	p.touch_input["mouse_buttons"] = _mbtn
	if aimed:
		p.touch_input["mouse"] = _aim_point
	elif world:
		p.touch_input["mouse"] = world_point(_world_screen)
	elif not p.touch_input.has("mouse"):
		p.touch_input["mouse"] = world_point(_world_start)
	if _world_ghost > 0:
		_world_ghost -= 1
		if _world_ghost == 0:
			aim_cell = NO_CELL   # отпущенный тап отработал
			aim_foe = false


# ------------------------------------------------------------------ УМНЫЙ ПРИЦЕЛ (#149)

## Цель пальца по миру на этот кадр: aim_cell, aim_foe, _aim_point.
func _update_aim(p: Player) -> void:
	# Цель прошлого кадра отработана: выкопана — дальше копаем только строго по лучу;
	# поставлено или повёрнуто — ждём, пока палец уйдёт на другую клетку.
	if aim_cell != NO_CELL and not aim_foe:
		if build_mode:
			var m = World.machines.get(aim_cell)
			if _aim_dir >= 0:
				_world_spent = m == null or int(m.dir) != _aim_dir
			else:
				_world_spent = not p.can_place_at(aim_cell)
		elif not diggable(aim_cell):
			_world_loose = false
	aim_cell = NO_CELL
	aim_foe = false
	_aim_dir = -1
	if build_mode and _world_spent:
		return
	var tap: Vector2 = world_point(_world_screen)
	var t: Dictionary = place_target(p, tap) if build_mode else dig_target(p, tap, _world_loose)
	if t.is_empty():
		return
	aim_cell = t["cell"]
	_aim_point = t["point"]
	aim_foe = t.has("foe")
	var turn: MachineBase = World.machines.get(aim_cell) if build_mode else null
	if turn != null and turn.can_turn:
		_aim_dir = turn.dir


## Цель копки для тапа в мировой точке tap: {"cell", "point"[, "foe"]} или {} — копать
## нечего. Фантом рядом с тапом — удар; иначе первая твёрдая по лучу от героя к пальцу;
## иначе (loose) копаемая соседка не дальше AIM_SLOP от тапа — палец промахнулся на полклетки.
func dig_target(p: Player, tap: Vector2, loose: bool) -> Dictionary:
	var from: Vector2 = p.global_position
	for ph in get_tree().get_nodes_in_group("phantom"):
		var pp: Vector2 = (ph as Node2D).global_position
		if pp.distance_to(tap) <= PHANTOM_GRAB and pp.distance_to(from) <= Player.REACH:
			return {"cell": World.world_to_cell(pp), "point": pp, "foe": true}
	var c: Vector2i = World.world_to_cell(tap)
	# От центра клетки героя, как у мыши: луч из точки ног цепляет пол.
	var hit: Vector2i = World.first_solid_on_ray(World.cell_to_world(World.world_to_cell(from)), tap, true, true)
	if hit != NO_CELL and diggable(hit) and _in_reach(from, hit):
		return _cell_target(hit)
	if not loose:
		return {}
	var best: Vector2i = NO_CELL
	var best_d: float = AIM_SLOP
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var n: Vector2i = c + Vector2i(dx, dy)
			if n == c or not diggable(n) or not _in_reach(from, n):
				continue
			var r: Rect2 = Rect2(Vector2(n * World.TILE), Vector2(World.TILE, World.TILE))
			var d: float = tap.distance_to(tap.clamp(r.position, r.end))
			if d <= best_d:
				best_d = d
				best = n
	return _cell_target(best) if best != NO_CELL else {}


## Цель постройки: лента или манипулятор под пальцем (повернуть), свободная клетка под
## пальцем в радиусе, иначе последняя свободная по лучу от героя к пальцу — до первого
## препятствия. {} — ставить некуда.
func place_target(p: Player, tap: Vector2) -> Dictionary:
	var from: Vector2 = p.global_position
	var c: Vector2i = World.world_to_cell(tap)
	if _in_reach(from, c):
		var m = World.machines.get(c)
		if (m != null and m.can_turn) or p.can_place_at(c):
			return _cell_target(c)
	var free: Vector2i = _ray(from, tap, p)
	return _cell_target(free) if free != NO_CELL else {}


## Копать клетку можно: твёрдая и не слишком крепкая (как Player._do_mining).
static func diggable(c: Vector2i) -> bool:
	var tid: int = World.get_tile_v(c)
	return tid != IDs.T.AIR and not DB.is_liquid(tid) and DB.tile_hard(tid) <= 100.0


static func _in_reach(from: Vector2, c: Vector2i) -> bool:
	return World.cell_to_world(c).distance_to(from) <= Player.REACH


static func _cell_target(c: Vector2i) -> Dictionary:
	return {"cell": c, "point": World.cell_to_world(c)}


## Луч от героя к пальцу (не дальше радиуса) для постройки: последняя клетка, куда можно
## поставить, до первой занятой. Копка идёт по World.first_solid_on_ray.
func _ray(from: Vector2, to: Vector2, p: Player) -> Vector2i:
	var d: Vector2 = to - from
	var dist: float = d.length()
	if dist < 0.01:
		return NO_CELL
	var dir: Vector2 = d / dist
	var length: float = minf(dist, Player.REACH + World.TILE * 0.5)
	var prev: Vector2i = NO_CELL
	var last_free: Vector2i = NO_CELL
	var t: float = 0.0
	while t <= length:
		var c: Vector2i = World.world_to_cell(from + dir * t)
		t += RAY_STEP
		if c == prev:
			continue
		prev = c
		var tid: int = World.get_tile_v(c)
		var solid: bool = tid != IDs.T.AIR and not DB.is_liquid(tid)
		if solid or World.machines.has(c):
			break
		if _in_reach(from, c) and p.can_place_at(c):
			last_free = c
	return last_free


# ------------------------------------------------------------------ РИСОВАНИЕ

func _process(delta: float) -> void:
	var vp_now: Vector2 = get_viewport().get_visible_rect().size
	var insets_now: Vector4 = safe_insets(vp_now)
	if vp_now != _layout_size or _team_rows() != _layout_team or UI.ui_scale != _layout_ui \
			or not insets_now.is_equal_approx(_layout_insets):
		_relayout()
	_fill_key()
	if _key != _last_key:
		_last_key = _key.duplicate()
		_pad.queue_redraw()
	elif _world_finger >= 0 and _active():
		_pad.queue_redraw()   # рамка цели и кольцо радиуса едут за камерой


## Отсчёт бездействия и плавное гашение. Тикает в физике: сценарии ждут
## sim_time, а headless не гарантирует кадры отрисовки. Палец на стике или
## кнопке, открытое окно и выключенное управление отсчёт не двигают. Погасшие
## контролы ждут касания (reveal_armed) и сами не возвращаются. Пока идёт fade,
## ввод ещё жив.
func _tick_autohide(delta: float) -> void:
	if not enabled or controls_hidden:
		return
	var holding: bool = _stick_finger >= 0 or _btn_down()
	if holding or _modal_open() or not _run_alive():
		idle_sec = 0.0
		return
	idle_sec += delta
	if idle_sec < AUTO_HIDE_SEC:
		return
	var step: float = delta / FADE_SEC
	controls_alpha = move_toward(controls_alpha, 0.0, step)
	if _pad != null:
		_pad.modulate = Color(1, 1, 1, controls_alpha)
	if controls_alpha <= 0.0:
		_hide_controls()


## Палец держит кнопку (не короткий импульс отпущенного тапа — тот отсчёт не держит).
func _btn_down() -> bool:
	for id in _btn_hold:
		if int(_btn_hold[id]) > 0:
			return true
	return false


## Забег идёт и герой жив. Мёртвый или финал — прятать контролы незачем, и
## отсчёт тогда не копится: после респауна они на месте.
func _run_alive() -> bool:
	var p: Player = _player()
	return p != null and not p.dead and Game.state == Game.State.PLAYING


## Ключ видимого состояния: перерисовываемся, только когда он сменился.
func _fill_key() -> void:
	var p: Player = _player()
	_key[0] = 1 if _active() else 0
	_key[1] = 1 if UI.blocking() else 0
	_key[2] = int(stick_vec.x * 32.0)
	_key[3] = int(stick_vec.y * 32.0)
	var mask: int = 0
	for i in BUTTONS.size():
		if held(String(BUTTONS[i]["id"])):
			mask |= 1 << i
	_key[4] = mask
	_key[5] = 1 if run_latched else 0
	_key[6] = 1 if build_mode else 0
	_key[7] = int(_layout_size.x)
	_key[8] = int(_layout_size.y)
	if p == null:
		return
	_key[9] = int(24.0 * (1.0 - p.emp_cd / p.emp_max))
	_key[10] = 1 if p.hiding else 0
	_key[11] = int(p.task_progress * 24.0)
	_key[12] = 1 if _world_finger >= 0 else 0
	_key[13] = (1 if rollcall_shown() else 0) | (2 if _rollcall_on() else 0)
	# Q и V появляются и пропадают, не сдвигая ряд: без этих бит дырка не перерисуется.
	_key[14] = 1 if _q_ready() else 0
	_key[15] = 1 if _v_ready() else 0
	# Альфа в ключе не нужна: modulate круга не зависит от _draw_pad.


func _draw_pad() -> void:
	if not _active() or controls_alpha <= 0.0:
		return
	var font: Font = ThemeDB.fallback_font
	var blocking: bool = UI.blocking()
	var p: Player = _player()
	if not blocking:
		_draw_aim(p)
		_draw_stick()
	for b in BUTTONS:
		var id: String = String(b["id"])
		if not _shown(id, blocking):
			continue
		var on: bool = held(id)
		if id == "run":
			on = run_latched
		elif id == "build":
			on = build_mode
		elif id == "v":
			on = on or p.hiding
		elif id == "g":
			on = on or _rollcall_on()   # идёт перекличка — G отвечает
		elif id == "inv":
			on = UI.panel.visible
		elif id == "journal":
			on = UI.journal.visible
		var cap: String = String(b["cap"])
		if id == "build" and build_mode:
			cap = "строить"
		_draw_button(font, id, String(b["glyph"]), cap, on, p)


## Пока палец на мире: кольцо радиуса вокруг героя и рамка клетки-цели (#149).
func _draw_aim(p: Player) -> void:
	if _world_finger < 0:
		return
	var xf: Transform2D = get_viewport().get_canvas_transform()
	var zoom: float = xf.get_scale().x
	var col: Color = C_BUILD if build_mode else C_DIG
	_pad.draw_arc(xf * p.global_position, Player.REACH * zoom, 0.0, TAU, 64,
			Color(col, 0.22 if aim_cell != NO_CELL else 0.45), 1.5 * _k, true)
	if aim_cell == NO_CELL:
		return
	if aim_foe:
		col = C_FOE
	var r: Rect2 = Rect2(xf * Vector2(aim_cell * World.TILE), Vector2(World.TILE, World.TILE) * zoom)
	_pad.draw_rect(r, Color(col, 0.18))
	_pad.draw_rect(r.grow(1.0), Color(col, 0.95), false, 2.5)

func _draw_stick() -> void:
	var c: Vector2 = stick_center
	var r: float = stick_radius
	_pad.draw_circle(c, r, Color(1, 1, 1, 0.22))
	_pad.draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, 0.62), 2.0 * _k, true)
	# Стрелки: влево/вправо — идти, вверх — прыжок.
	var a: Color = Color(1, 1, 1, 0.35)
	var s: float = 9.0 * _k
	for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP]:
		var tip: Vector2 = c + d * (r - 10.0 * _k)
		var back: Vector2 = tip - d * s
		var side: Vector2 = Vector2(-d.y, d.x) * s * 0.8
		_pad.draw_colored_polygon(PackedVector2Array([tip, back + side, back - side]), a)
	var knob: Vector2 = c + stick_vec * (r - KNOB_R * _k * 0.5)
	var held_now: bool = _stick_finger >= 0
	_pad.draw_circle(knob, KNOB_R * _k, Color(0.75, 0.9, 1.0, 0.78 if held_now else 0.40))
	_pad.draw_arc(knob, KNOB_R * _k, 0.0, TAU, 32, Color(1, 1, 1, 0.55), 2.0 * _k, true)


func _draw_button(font: Font, id: String, glyph: String, cap: String, on: bool, p: Player) -> void:
	var c: Vector2 = btn_center[id]
	var r: float = float(btn_radius[id])
	var fill: Color = Color(0.55, 0.85, 1.0, 0.36) if on else Color(1, 1, 1, 0.12)
	if id == "build" and not on:
		fill = Color(C_DIG, 0.3)   # режим виден и без подписи: «копать» — тёплый, «строить» — голубой
	_pad.draw_circle(c, r, fill)
	_pad.draw_arc(c, r, 0.0, TAU, 40, Color(1, 1, 1, 0.65 if on else 0.35), 2.0 * _k, true)
	var ink: Color = Color(1, 1, 1, 0.92)
	var dy: float = -6.0 * _k
	match id:
		"jump":
			var s: float = 16.0 * _k
			var tip: Vector2 = c + Vector2(0, dy - s)
			_pad.draw_colored_polygon(PackedVector2Array([tip, c + Vector2(s, dy + s * 0.6),
					c + Vector2(-s, dy + s * 0.6)]), ink)
		"run":
			for i in 2:
				var x: float = (-8.0 + 12.0 * float(i)) * _k
				_pad.draw_polyline(PackedVector2Array([c + Vector2(x - 5.0 * _k, dy - 11.0 * _k),
						c + Vector2(x + 5.0 * _k, dy), c + Vector2(x - 5.0 * _k, dy + 11.0 * _k)]),
						ink, 3.0 * _k, true)
		"build" when build_mode:
			# Блок из четырёх клеток — «строить».
			var q: float = 9.0 * _k
			for i in 4:
				var o: Vector2 = Vector2(float(i % 2) - 1.0, float(i / 2) - 1.0) * (q + 2.0 * _k)
				_pad.draw_rect(Rect2(c + Vector2(0, dy) + o + Vector2(1.0, 1.0) * _k, Vector2(q, q)), ink)
		"build":
			# Свет из перчатки — «копать»: короткий столбик квадратов и вспышка.
			var beam: float = 4.0 * _k
			var gap: float = 2.0 * _k
			var mid: Vector2 = c + Vector2(0, dy)
			var glove: Vector2 = mid + Vector2(-beam, beam * 1.5)
			_pad.draw_rect(Rect2(glove, Vector2(beam, beam)), ink)
			for i in 2:
				var o: Vector2 = Vector2(float(i + 1) * (beam + gap), -float(i + 1) * (beam + gap))
				_pad.draw_rect(Rect2(glove + o, Vector2(beam, beam)), ink)
			var flare: Vector2 = glove + Vector2(3.0 * (beam + gap) - beam * 0.5, -3.0 * (beam + gap) - beam * 0.5)
			_pad.draw_rect(Rect2(flare, Vector2(beam * 2.0, beam * 2.0)), ink)
		"pause":
			# Две полосы паузы.
			var bh: float = 12.0 * _k
			for x in [-6.5, 2.5]:
				_pad.draw_rect(Rect2(c + Vector2(float(x) * _k, dy - bh), Vector2(4.0 * _k, bh * 2.0)), ink)
		_:
			var fs: int = int(28.0 * _k)
			_pad.draw_string(font, Vector2(c.x - r, c.y + dy + fs * 0.36), glyph,
					HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, ink)
	var cs: int = maxi(int(UI.FONT["small"]), int(12.0 * _k))
	_pad.draw_string(font, Vector2(c.x - r, c.y + r * 0.62), cap, HORIZONTAL_ALIGNMENT_CENTER,
			r * 2.0, cs, Color(1, 1, 1, 0.75))
	# Перезарядка импульса и прогресс удержания E — дугой по кромке.
	var frac: float = -1.0
	if id == "q" and p.emp_cd > 0.0:
		frac = 1.0 - p.emp_cd / p.emp_max
	elif id == "e" and p.task_progress > 0.0:
		frac = p.task_progress
	if frac >= 0.0:
		_pad.draw_arc(c, r - 3.0 * _k, -PI * 0.5, -PI * 0.5 + TAU * clampf(frac, 0.0, 1.0), 40,
				Color(0.4, 0.9, 1.0, 0.9), 4.0 * _k, true)
