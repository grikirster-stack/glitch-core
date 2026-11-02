class_name TouchControls
extends CanvasLayer
## Сенсорное управление для телефона (#81): джойстик слева, кнопки справа,
## тап по миру — копать/бить, долгий тап или режим «строить» — ставить предмет
## из хотбара, хотбар — тапом по ячейке. Мультитач: каждый палец ведётся по
## своему индексу, поэтому можно идти джойстиком и копать тапом одновременно.
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
##
## Раскладка при 1280×720 (не перекрывает HUD): слева снизу — джойстик и «строить»;
## справа снизу — E, бег, прыжок (ниже уведомлений, правее хотбара); справа под
## миникартой — J, I, ниже — Q и V. Размер кнопки — не меньше MIN_MM на экране.
## Всё рисуется одним Control и только при смене видимого состояния.

## Слой: над HUD и панелями (UI — 10), под экраном финала (EndScreen.LAYER — 20).
const LAYER: int = 15
## Радиус обычной кнопки и кнопки прыжка, px при высоте экрана 720.
## Диаметр 96 px на телефоне (720 логических px ≈ 70 мм) — около 9,5 мм.
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
const MIN_MM: float = 9.0
## Мёртвая зона джойстика по горизонтали и порог «вверх — прыжок» (доля радиуса).
const DEAD: float = 0.28
const STICK_JUMP: float = 0.6
## Долгий тап, с: палец стоит на пустой клетке — ставим предмет из хотбара.
const LONG_TAP: float = 0.4
## Насколько палец может уехать и всё ещё «стоять», px.
const TAP_SLOP: float = 18.0
## Короткий тап держит клавишу хотя бы столько физических кадров: нажатие и
## отпускание в одном кадре иначе прошли бы мимо Player.
const PULSE_FRAMES: int = 3
## Длина ключа видимого состояния (см. _fill_key).
const KEY_LEN: int = 16

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
	{"id": "build", "key": 0, "glyph": "", "cap": "строить"},
]

## Включено ли сенсорное управление (видно и читает касания).
var enabled: bool = false
## Режим «строить»: тап по миру сразу ставит предмет (ПКМ), а не копает.
var build_mode: bool = false
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
var _k: float = 1.0
## Пальцы на экране: индекс -> {"kind": "stick"|"btn"|"world"|"hotbar"|"none", "id": String}.
var _fingers: Dictionary = {}
var _stick_finger: int = -1
var _world_finger: int = -1
var _world_screen: Vector2 = Vector2.ZERO
var _world_start: Vector2 = Vector2.ZERO
var _world_t: float = 0.0
## Палец по миру перешёл в постройку (долгий тап или режим «строить»).
var _world_place: bool = false
## Палец встал на пустую клетку: только такой тап может стать долгим. Докопал
## тайл и держишь дальше — это копка, а не постройка на месте выкопанного.
var _world_start_empty: bool = false
## Пальцев на кнопке (id -> int) и оставшиеся кадры короткого нажатия (id -> int).
var _btn_hold: Dictionary = {}
var _btn_pulse: Dictionary = {}
## Состояние шва: живут всё время, меняются только значения — без аллокаций.
var _keys: Dictionary = {}
var _mbtn: Dictionary = {MOUSE_BUTTON_LEFT: false, MOUSE_BUTTON_RIGHT: false}
var _key: PackedInt32Array = PackedInt32Array()
var _last_key: PackedInt32Array = PackedInt32Array()


func _ready() -> void:
	layer = LAYER
	name = "TouchControls"
	add_to_group("touch_controls")
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
	visible = on
	set_process(on)
	set_physics_process(on)
	set_process_input(on)
	release_all()
	var p: Player = _player()
	if p != null:
		p.touch_input = {"keys": _keys} if on else {}
	if on:
		_relayout()


## Отпустить все пальцы: смерть, пауза приложения, выключение.
func release_all() -> void:
	_fingers.clear()
	_btn_hold.clear()
	_btn_pulse.clear()
	_stick_finger = -1
	_world_finger = -1
	_world_place = false
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


## Управление сейчас работает: герой жив, забег идёт.
func _active() -> bool:
	var p: Player = _player()
	return enabled and p != null and not p.dead and Game.state == Game.State.PLAYING


# ------------------------------------------------------------------ РАСКЛАДКА

## Множитель раскладки: кнопка не меньше MIN_MM на экране этого устройства.
func _scale() -> float:
	var dpi: int = DisplayServer.screen_get_dpi()
	var win: Vector2i = get_window().size
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if dpi <= 0 or win.y <= 0 or vp.y <= 0.0:
		return 1.0
	var px_per_mm: float = float(dpi) / 25.4 * vp.y / float(win.y)
	return clampf(MIN_MM * px_per_mm / (BTN_R * 2.0), 1.0, 1.6)


func _relayout() -> void:
	_layout_size = get_viewport().get_visible_rect().size
	_layout(_layout_size)
	_pad.queue_redraw()


func _layout(sz: Vector2) -> void:
	_k = _scale()
	var r: float = BTN_R * _k
	var jr: float = JUMP_R * _k
	var m: float = 24.0 * _k
	var g: float = 14.0 * _k
	stick_radius = STICK_R * _k
	stick_center = Vector2(m + 10.0 * _k + stick_radius, sz.y - m - stick_radius)
	var jump: Vector2 = Vector2(sz.x - m - jr, sz.y - m - jr)
	var run: Vector2 = Vector2(jump.x - jr - g - r, sz.y - m - r)
	# Под миникартой (HUD: до y = 112) — I и J, под ними столбиком Q и V.
	var inv: Vector2 = Vector2(sz.x - m - r, 126.0 + r)
	btn_center = {
		"jump": jump,
		"run": run,
		"e": Vector2(run.x - 2.0 * r - g, run.y),
		"inv": inv,
		"journal": Vector2(inv.x - 2.0 * r - g, inv.y),
		"q": Vector2(inv.x, inv.y + 2.0 * r + g),
		"v": Vector2(inv.x, inv.y + 4.0 * r + 2.0 * g),
		"build": Vector2(m + r, stick_center.y - stick_radius - g - r),
	}
	btn_radius = {}
	for id in btn_center:
		btn_radius[id] = jr if id == "jump" else r


## Что под пальцем: "stick", id кнопки или "". При открытой панели живы только I и J.
func control_at(pos: Vector2) -> String:
	var blocking: bool = UI.blocking()
	var best: String = ""
	var best_d: float = INF
	for id in btn_center:
		if blocking and id != "inv" and id != "journal":
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


## Ячейка хотбара под пальцем или -1.
func hotbar_slot_at(pos: Vector2) -> int:
	var hud: HUD = UI.hud
	if hud == null:
		return -1
	for i in 10:
		if hud.hotbar_slot_rect(i).grow(2.0).has_point(pos):
			return i
	return -1


# ------------------------------------------------------------------ КАСАНИЯ

func _input(event: InputEvent) -> void:
	var eat: bool = false
	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		eat = _finger_down(st.index, st.position) if st.pressed else _finger_up(st.index)
	elif event is InputEventScreenDrag:
		var sd: InputEventScreenDrag = event
		eat = _finger_move(sd.index, sd.position)
	elif event is InputEventMouseButton:
		# Клик (настоящий или эмулированный из касания) по нашей кнопке — не панелям.
		eat = _active() and control_at((event as InputEventMouseButton).position) != ""
	if eat:
		get_viewport().set_input_as_handled()


## Палец коснулся экрана. true — касание наше (кнопка, джойстик, хотбар).
func _finger_down(index: int, pos: Vector2) -> bool:
	if not _active():
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
	var slot: int = hotbar_slot_at(pos)
	if slot >= 0:
		_player().inv.selected = slot
		_fingers[index] = {"kind": "hotbar", "id": ""}
		return true
	if _world_finger < 0:
		_world_finger = index
		_world_screen = pos
		_world_start = pos
		_world_t = 0.0
		_world_place = build_mode
		_world_start_empty = _cell_empty(world_point(pos))
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
			_world_place = false
	return kind == "stick" or kind == "btn" or kind == "hotbar"


func _finger_move(index: int, pos: Vector2) -> bool:
	if not _fingers.has(index):
		return false
	var kind: String = String(_fingers[index]["kind"])
	if kind == "stick":
		_set_stick(pos)
	elif kind == "world":
		_world_screen = pos
	return kind == "stick" or kind == "btn" or kind == "hotbar"


func _set_stick(pos: Vector2) -> void:
	stick_vec = ((pos - stick_center) / stick_radius).limit_length(1.0)


## Нажата кнопка: окна и защёлки — сразу, клавиши шва — пока палец на кнопке.
func _press(id: String) -> void:
	match id:
		"inv":
			UI.toggle_inventory()
		"journal":
			UI.toggle_journal()
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


# ------------------------------------------------------------------ ШОВ

func _physics_process(dt: float) -> void:
	var p: Player = _player()
	if p == null:
		return
	if not _active():
		if not _fingers.is_empty() or bool(_keys.get(KEY_SHIFT, false)):
			release_all()
		return
	if not p.touch_input.has("keys"):
		p.touch_input["keys"] = _keys   # сценарий мог снять шов
	# Долгий тап по пустой клетке — постройка (как ПКМ); начат на твёрдой — копаем дальше.
	if _world_finger >= 0 and not _world_place and _world_start_empty:
		_world_t += dt
		if _world_t >= LONG_TAP and _world_screen.distance_to(_world_start) <= TAP_SLOP \
				and _cell_empty(world_point(_world_screen)):
			_world_place = true
	_keys[KEY_A] = stick_vec.x < -DEAD
	_keys[KEY_D] = stick_vec.x > DEAD
	_keys[KEY_W] = stick_vec.y < -STICK_JUMP
	_keys[KEY_SPACE] = held("jump")
	_keys[KEY_SHIFT] = run_latched
	_keys[KEY_E] = held("e")
	_keys[KEY_Q] = held("q")
	_keys[KEY_V] = held("v")
	for id in _btn_pulse:
		_btn_pulse[id] = maxi(0, int(_btn_pulse[id]) - 1)
	# Пока палец на экране, кнопки мыши — только наши: эмулированный клик
	# под джойстиком или кнопкой мир не копает.
	if _fingers.is_empty():
		p.touch_input.erase("mouse_buttons")
		p.touch_input.erase("mouse")
		return
	var world: bool = _world_finger >= 0
	_mbtn[MOUSE_BUTTON_LEFT] = world and not _world_place
	_mbtn[MOUSE_BUTTON_RIGHT] = world and _world_place
	p.touch_input["mouse_buttons"] = _mbtn
	if world:
		p.touch_input["mouse"] = world_point(_world_screen)
	elif not p.touch_input.has("mouse"):
		p.touch_input["mouse"] = world_point(_world_start)


## Клетка пустая — копать нечего, долгий тап ставит предмет.
func _cell_empty(world: Vector2) -> bool:
	var tid: int = World.get_tile_v(World.world_to_cell(world))
	return tid == IDs.T.AIR or DB.is_liquid(tid)


# ------------------------------------------------------------------ РИСОВАНИЕ

func _process(_delta: float) -> void:
	if get_viewport().get_visible_rect().size != _layout_size:
		_relayout()
	_fill_key()
	if _key != _last_key:
		_last_key = _key.duplicate()
		_pad.queue_redraw()


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
	_key[12] = 1 if (_world_finger >= 0 and _world_place) else 0


func _draw_pad() -> void:
	if not _active():
		return
	var font: Font = ThemeDB.fallback_font
	var blocking: bool = UI.blocking()
	if not blocking:
		_draw_stick()
	var p: Player = _player()
	for b in BUTTONS:
		var id: String = String(b["id"])
		if blocking and id != "inv" and id != "journal":
			continue
		var on: bool = held(id)
		if id == "run":
			on = run_latched
		elif id == "build":
			on = build_mode or (_world_finger >= 0 and _world_place)
		elif id == "v":
			on = on or p.hiding
		elif id == "inv":
			on = UI.panel.visible
		elif id == "journal":
			on = UI.journal.visible
		_draw_button(font, id, String(b["glyph"]), String(b["cap"]), on, p)


func _draw_stick() -> void:
	var c: Vector2 = stick_center
	var r: float = stick_radius
	_pad.draw_circle(c, r, Color(1, 1, 1, 0.08))
	_pad.draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, 0.32), 2.0 * _k, true)
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
	_pad.draw_circle(knob, KNOB_R * _k, Color(0.75, 0.9, 1.0, 0.42 if held_now else 0.26))
	_pad.draw_arc(knob, KNOB_R * _k, 0.0, TAU, 32, Color(1, 1, 1, 0.55), 2.0 * _k, true)


func _draw_button(font: Font, id: String, glyph: String, cap: String, on: bool, p: Player) -> void:
	var c: Vector2 = btn_center[id]
	var r: float = float(btn_radius[id])
	var fill: Color = Color(0.55, 0.85, 1.0, 0.36) if on else Color(1, 1, 1, 0.12)
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
		"build":
			# Блок из четырёх клеток — «поставить».
			var q: float = 9.0 * _k
			for i in 4:
				var o: Vector2 = Vector2(float(i % 2) - 1.0, float(i / 2) - 1.0) * (q + 2.0 * _k)
				_pad.draw_rect(Rect2(c + Vector2(0, dy) + o + Vector2(1.0, 1.0) * _k, Vector2(q, q)), ink)
		_:
			var fs: int = int(28.0 * _k)
			_pad.draw_string(font, Vector2(c.x - r, c.y + dy + fs * 0.36), glyph,
					HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, ink)
	var cs: int = int(12.0 * _k)
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
