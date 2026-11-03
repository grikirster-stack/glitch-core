class_name ViewZoom
extends Node
## Зум камеры своего героя: ближе — рассмотреть, дальше — увидеть картину целиком.
##
## ПК: колесо мыши (и прокрутка трекпада) — шаг STEP, + и − (и на цифровом блоке) —
## тоже, средняя кнопка мыши — сброс к DEFAULT, щипок трекпада (InputEventMagnifyGesture).
## Колесо и клавиши доводят зум плавно (SMOOTH). Телефон: щипок двумя пальцами по миру
## ведёт TouchControls — set_now() без доводки, зум идёт ровно за пальцами.
##
## Зум не трогаем, пока открыта панель или пауза (колесо там листает списки) и вне
## забега. Камера при зуме остаётся на герое: он в центре кадра, как и был.
##
## Выбранный зум живёт в профиле ([view] zoom, Profile.read_zoom/write_zoom) и
## переживает перезапуск. Пишем не на каждый шаг колеса, а через SAVE_DELAY после
## последнего изменения (и при уходе узла). В тестовом прогоне профиль свой
## (TestEnv) — тесты видят DEFAULT.
##
## Камеру пишем, только пока зум доводится: инструменты (gallery_dump) ставят
## camera.zoom сами, и устоявшийся ViewZoom им не мешает.

## Зум по умолчанию: px экрана на px мира (прежний постоянный зум игры).
const DEFAULT: float = 2.2
## Дальше всего: обзор вдвое шире обычного.
const MIN: float = 1.1
## Ближе всего: вдвое ближе обычного.
const MAX: float = 4.4
## Шаг колеса и клавиш (множитель).
const STEP: float = 1.2
## Скорость доводки к цели, 1/с: за 0,2 с проходит ~95 % пути.
const SMOOTH: float = 14.0
## Через сколько секунд после последнего изменения зум уходит в профиль.
const SAVE_DELAY: float = 1.0

## Камера героя (Player создаёт её и этот узел вместе).
var camera: Camera2D = null
## Куда идёт зум и где он сейчас.
var target: float = DEFAULT
var current: float = DEFAULT
## До записи в профиль, с; < 0 — писать нечего.
var _save_t: float = -1.0


func _ready() -> void:
	name = "ViewZoom"
	var saved: float = Profile.read_zoom()
	target = clampf(saved, MIN, MAX) if saved > 0.0 else DEFAULT
	current = target
	_apply()


## Шагнуть зумом: steps > 0 — ближе, < 0 — дальше (дробные — прокрутка трекпада).
func step(steps: float) -> void:
	zoom_to(target * pow(STEP, steps))


## Плавно к зуму z.
func zoom_to(z: float) -> void:
	z = clampf(z, MIN, MAX)
	if z == target:
		return
	target = z
	_save_t = SAVE_DELAY


## Сразу зум z, без доводки (щипок: зум идёт за пальцами).
func set_now(z: float) -> void:
	zoom_to(z)
	current = target
	_apply()


func reset() -> void:
	zoom_to(DEFAULT)


## Зум сейчас можно менять: идёт забег, нет панели и паузы.
func allowed() -> bool:
	return camera != null and Game.state == Game.State.PLAYING and not UI.blocking()


func _unhandled_input(event: InputEvent) -> void:
	if not allowed():
		return
	var used: bool = true
	if event is InputEventMouseButton and event.pressed:
		var mb: InputEventMouseButton = event
		var f: float = mb.factor if mb.factor > 0.0 else 1.0
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				step(f)
			MOUSE_BUTTON_WHEEL_DOWN:
				step(-f)
			MOUSE_BUTTON_MIDDLE:
				reset()
			_:
				used = false
	elif event is InputEventKey and event.pressed:
		match (event as InputEventKey).keycode:
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
				step(1.0)
			KEY_MINUS, KEY_KP_SUBTRACT:
				step(-1.0)
			_:
				used = false
	elif event is InputEventMagnifyGesture:
		zoom_to(target * (event as InputEventMagnifyGesture).factor)
	else:
		used = false
	if used:
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if current != target:
		current = target + (current - target) * exp(-SMOOTH * delta)
		if absf(current - target) < 0.002:
			current = target
		_apply()
	if _save_t >= 0.0:
		_save_t -= delta
		if _save_t < 0.0:
			Profile.write_zoom(target)


func _exit_tree() -> void:
	if _save_t >= 0.0:
		_save_t = -1.0
		Profile.write_zoom(target)


func _apply() -> void:
	if camera != null:
		camera.zoom = Vector2(current, current)
