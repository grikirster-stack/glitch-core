extends ScenarioBase
## Зум камеры (ViewZoom): колесо мыши и + / − — настоящими событиями через
## Input.parse_input_event, как у человека.
##
## Проверяем: старт с DEFAULT (профиль теста пуст); колесо вверх — ближе, вниз — дальше,
## доводка плавная (не скачком), герой остаётся в центре кадра; + и − тоже шагают;
## пределы MIN и MAX держатся; средняя кнопка — сброс; при открытом инвентаре колесо
## зум не трогает (там оно листает); зум уходит в профиль через SAVE_DELAY.

var vz: ViewZoom = null


func run() -> void:
	clear_input()
	stand_in_corridor()
	await wait(0.4)
	vz = player.view_zoom
	ok("у своего героя есть зум", vz != null and vz.camera == player.camera)
	if vz == null:
		finish()
		return
	ok("старт — зум по умолчанию", is_equal_approx(vz.current, ViewZoom.DEFAULT)
			and is_equal_approx(player.camera.zoom.x, ViewZoom.DEFAULT), "%.2f" % player.camera.zoom.x)

	# ---- Колесо: плавно ближе, герой в центре -----------------------------------
	_wheel(MOUSE_BUTTON_WHEEL_UP)
	await get_tree().process_frame
	await get_tree().process_frame
	var mid: float = player.camera.zoom.x
	var want: float = ViewZoom.DEFAULT * ViewZoom.STEP
	ok("колесо вверх — цель ближе на шаг", is_equal_approx(vz.target, want), "%.3f" % vz.target)
	ok("зум доводится плавно, не скачком", mid > ViewZoom.DEFAULT and mid < want, "%.3f" % mid)
	await wait(0.5)
	ok("доводка дошла до цели", is_equal_approx(player.camera.zoom.x, want), "%.3f" % player.camera.zoom.x)
	player.camera.reset_smoothing()
	await get_tree().process_frame
	var center: Vector2 = get_viewport().get_canvas_transform().affine_inverse() \
			* (get_viewport().get_visible_rect().size * 0.5)
	ok("герой в центре кадра", center.distance_to(player.global_position) < 24.0,
			"%.1f px" % center.distance_to(player.global_position))

	_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	await wait(0.5)
	ok("колесо вниз — дальше", is_equal_approx(vz.current, ViewZoom.DEFAULT / ViewZoom.STEP),
			"%.3f" % vz.current)

	# ---- Клавиши и пределы ---------------------------------------------------------
	_key(KEY_EQUAL)
	await wait(0.5)
	ok("+ — ближе", is_equal_approx(vz.current, ViewZoom.DEFAULT), "%.3f" % vz.current)
	_key(KEY_MINUS)
	await wait(0.5)
	ok("− — дальше", is_equal_approx(vz.current, ViewZoom.DEFAULT / ViewZoom.STEP), "%.3f" % vz.current)
	for i in 12:
		_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	await wait(0.6)
	ok("дальше MIN не уходит", is_equal_approx(vz.current, ViewZoom.MIN), "%.3f" % vz.current)
	for i in 12:
		_key(KEY_KP_ADD)
	await wait(0.6)
	ok("ближе MAX не уходит", is_equal_approx(vz.current, ViewZoom.MAX), "%.3f" % vz.current)
	_wheel(MOUSE_BUTTON_MIDDLE)
	await wait(0.6)
	ok("средняя кнопка — сброс", is_equal_approx(vz.current, ViewZoom.DEFAULT), "%.3f" % vz.current)

	# ---- Инвентарь открыт — колесо не зумит ------------------------------------------
	UI.toggle_inventory()
	await wait(0.2)
	_wheel(MOUSE_BUTTON_WHEEL_UP)
	_key(KEY_EQUAL)
	await wait(0.3)
	ok("при открытом инвентаре зум стоит", UI.blocking() and is_equal_approx(vz.target, ViewZoom.DEFAULT),
			"%.3f" % vz.target)
	UI.toggle_inventory()
	await wait(0.2)

	# ---- Профиль ------------------------------------------------------------------
	_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	await wait(ViewZoom.SAVE_DELAY * 0.5)
	ok("до SAVE_DELAY в профиль не пишется", Profile.read_zoom() != vz.target, "%.3f" % Profile.read_zoom())
	await wait(ViewZoom.SAVE_DELAY + 0.3)
	ok("зум ушёл в профиль", is_equal_approx(Profile.read_zoom(), vz.target), "%.3f" % Profile.read_zoom())

	# Следующие сценарии процесса — с зумом по умолчанию.
	vz.set_now(ViewZoom.DEFAULT)
	Profile.write_zoom(ViewZoom.DEFAULT)
	finish()


func _wheel(button: int) -> void:
	for pressed in [true, false]:
		var e: InputEventMouseButton = InputEventMouseButton.new()
		e.button_index = button
		e.pressed = pressed
		e.factor = 1.0
		e.position = get_viewport().get_visible_rect().size * 0.5
		Input.parse_input_event(e)


func _key(code: int) -> void:
	for pressed in [true, false]:
		var e: InputEventKey = InputEventKey.new()
		e.keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)
