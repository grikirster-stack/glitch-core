extends SceneTree
## Кадр забора машины на телефоне: горелка не у входа, плашка «забрать»,
## короткий тап, предмет в руке, плашка «поставить». Окно за экраном.
##
##   DISPLAY=:0 godot --path . --audio-driver Dummy --windowed \
##       --position -10000,-10000 --touch \
##       --script res://tools/machine_pickup_shot.gd -- \
##       --size=2400x1080 --ui-scale=2.5 --out-dir=/tmp/machine-pickup --tag=land

const HARD_LIMIT: float = 40.0
const SCREEN_MAX: Vector2i = Vector2i(1920, 1080)

var scene: Node = null
var _elapsed: float = 0.0
var target_size: Vector2i = Vector2i(2400, 1080)
var capture_size: Vector2i = Vector2i.ZERO
var ui_scale: float = 2.5
var out_dir: String = "/tmp/machine-pickup"
var tag: String = "land"
var _hold_mouse: Vector2 = Vector2(-1.0, -1.0)


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("machine_pickup_shot: headless не рендерит")
		quit(1)
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--size="):
			var parts: PackedStringArray = a.substr(7).split("x")
			if parts.size() == 2:
				target_size = Vector2i(int(parts[0]), int(parts[1]))
		elif a.begins_with("--capture="):
			var parts: PackedStringArray = a.substr(10).split("x")
			if parts.size() == 2:
				capture_size = Vector2i(int(parts[0]), int(parts[1]))
		elif a.begins_with("--ui-scale="):
			ui_scale = float(a.substr(11))
		elif a.begins_with("--out-dir="):
			out_dir = a.substr(10)
		elif a.begins_with("--tag="):
			tag = a.substr(6)
	if capture_size == Vector2i.ZERO:
		capture_size = _pick_capture(target_size)
	if out_dir == "" or out_dir.contains("docs/img"):
		push_error("machine_pickup_shot: нужен --out-dir вне docs/img")
		quit(1)
		return
	root.size = capture_size
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	root.position = Vector2i(-10000, -10000)
	_boot.call_deferred()


func _pick_capture(target: Vector2i) -> Vector2i:
	var aspect: float = float(target.x) / float(target.y)
	var w: int = SCREEN_MAX.x
	var h: int = int(round(float(w) / aspect))
	if h > SCREEN_MAX.y:
		h = SCREEN_MAX.y
		w = int(round(float(h) * aspect))
	return Vector2i(maxi(w, 2), maxi(h, 2))


func _boot() -> void:
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	scene = main_scene.instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _process(delta: float) -> bool:
	_elapsed += delta
	# После физики тача: он стирает шов, если пальца нет. Точка кадра — наша.
	if _hold_mouse.x >= 0.0 and scene != null:
		var pl: Node = scene.get("player")
		if pl != null:
			pl.touch_input["mouse"] = _hold_mouse
	if _elapsed > HARD_LIMIT:
		push_error("machine_pickup_shot: превышен лимит")
		quit(2)
	return false


func _run() -> void:
	var game: Node = root.get_node("Game")
	scene.set("scenario_mode", true)
	game.set("scenario_mode", true)
	game.set("time_of_day", 0.40)
	game.set("game_time", 30.0)   # вводные 15 с не перекрывают плашку забора
	root.size = capture_size
	root.get_node("UI").call("set_ui_scale", ui_scale, false)
	await _frames(24)
	var tc: Node = get_first_node_in_group("touch_controls")
	if tc == null or not bool(tc.get("enabled")):
		push_error("machine_pickup_shot: нет сенсорного управления (нужен --touch)")
		quit(1)
		return
	var p: Node2D = scene.get("player")
	var world: Node = root.get_node("World")
	var bx: int = int(world.get("beacon_cell").x)
	var by: int = int(world.get("beacon_cell").y)
	var base: int = by + 1
	for x in range(bx + 1, bx + 16):
		world.set_tile(x, base - 1, 0)   # AIR
	# Вплотную: радиус E у горелки 40 px, иначе плашка не про забор.
	var cell: Vector2i = Vector2i(bx + 4, base - 1)
	# Ноги на полу клетки base, как stand_in_corridor: иначе герой падает из кадра.
	p.global_position = Vector2(float((bx + 3) * 16) + 8.0, float(base * 16) - 11.0)
	p.vel = Vector2.ZERO
	p.on_ground = true
	var cam = p.get("camera")
	# Камера — ребёнок героя: якорь это position, не global_position.
	cam.position = Vector2.ZERO
	cam.offset = Vector2.ZERO
	cam.reset_smoothing()
	cam.force_update_scroll()
	var inv = p.get("inv")
	# Стартовый набор не должен перебить плашку. Горелку ставим шовом ПКМ, без
	# прямой ссылки на MachineBase: скрипт SceneTree грузится до автозагрузок.
	inv.selected = 0
	inv.slots[0] = ItemStack.new()
	var ids = load("res://scripts/core/ids.gd")
	var burner_id: int = int(ids.I.BURNER)
	inv.add(burner_id, 1)
	inv.selected = 0
	for i in inv.slots.size():
		if int(inv.slots[i].id) == burner_id:
			inv.selected = i
			break
	var place_pos: Vector2 = world.cell_to_world(cell)
	p.test_input = {
		"mouse": place_pos,
		"mouse_buttons": {MOUSE_BUTTON_RIGHT: true},
	}
	await _frames(3)
	p.test_input = {}
	if not world.machines.has(cell):
		push_error("machine_pickup_shot: горелка не встала %s" % str(cell))
		quit(1)
		return
	inv.selected = 0
	inv.slots[0] = ItemStack.new()
	tc.set("build_mode", false)
	var hud0: Node = root.get_node("UI").get("hud")
	hud0.tutorial_text = ""
	hud0.tutorial_step = 5   # Tut.DONE: шаг обучения не перебивает «забрать»
	await _frames(12)
	cam.position = Vector2.ZERO
	cam.reset_smoothing()
	cam.force_update_scroll()
	await _frames(4)
	print("machine_pickup_shot cam: герой %s камера %s scroll %s" % [
		str(p.global_position), str(cam.global_position), str(cam.get_screen_center_position())])
	var hud: Node = root.get_node("UI").get("hud")
	_report("before", hud)
	var before_ok: bool = await _shot("before")
	var plate: Rect2 = hud.layout_screen_rect("hint")
	if not hud.pickup_plate_at(plate.get_center()):
		push_error("machine_pickup_shot: плашка не «Забрать» «%s» %s" % [
			String(hud._plate_text()), str(plate)])
		quit(1)
		return
	# Короткий тап по плашке в нижней трети, не по клетке мира.
	_touch(1, plate.get_center(), true)
	await _frames(1)
	_touch(1, plate.get_center(), false)
	await _frames(16)
	cam.position = Vector2.ZERO
	cam.reset_smoothing()
	cam.force_update_scroll()
	# Прицел на свободную клетку справа — плашка «поставить».
	# Курсор кадра — шов тача: экранная мышь после тапа по плашке остаётся на HUD
	# и перекрывает клетку (ландшафт 2400×1080). Палец не держим: иначе тач
	# пересчитает клетку из точки экрана и поставит блок до кадра.
	var dest: Vector2i = Vector2i(cell.x + 3, cell.y)
	var mouse: Vector2 = world.cell_to_world(dest)
	p.test_input = {}
	# Физика тача каждый кадр переписывает шов из экранной мыши. Для кадра
	# «поставить» её глушим и держим точку мира сами.
	tc.set_physics_process(false)
	_hold_mouse = mouse
	p.touch_input["mouse"] = mouse
	await _frames(8)
	var hud_now: Node = root.get_node("UI").get("hud")
	print("machine_pickup_shot aim: клетка %s building %s can_place %s hint «%s»" % [
		str(dest), str(p.building_cell), str(p.can_place_at(dest)),
		String(hud_now.hint_text)])
	_report("after", hud)
	var after_ok: bool = await _shot("after")
	var taken: bool = not world.machines.has(cell)
	var selected: int = int(inv.selected_stack().id)
	var armed: bool = bool(tc.get("build_mode"))
	print("machine_pickup_shot: забрано=%s выбран=%d build_mode=%s до=%s после=%s" % [
		str(taken), selected, str(armed), str(before_ok), str(after_ok)])
	quit(0 if before_ok and after_ok and taken and armed else 1)


func _report(label: String, hud: Node) -> void:
	var canvas: Vector2 = root.get_viewport().get_visible_rect().size
	var plate: String = String(hud._plate_text())
	var hint: Rect2 = hud._lay.get("hint", Rect2())
	var band: float = canvas.y * float(hud.TOUCH_BAND) / ui_scale
	print("machine_pickup_shot %s: холст %s логич. %s ui_scale %.2f плашка «%s» rect %s низ_трети_y=%.1f" % [
		label, str(canvas), str(canvas / ui_scale), ui_scale, plate, str(hint), band])


func _shot(label: String) -> bool:
	var hud: Node = root.get_node("UI").get("hud")
	hud._lay_sig = -1
	if hud.has_method("layout_named"):
		hud.layout_named()
	hud.queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var src: Image = root.get_viewport().get_texture().get_image()
	if src == null or src.is_empty():
		push_error("machine_pickup_shot: пустой кадр %s" % label)
		return false
	var img: Image = src.duplicate()
	if img.get_size() != target_size:
		img.resize(target_size.x, target_size.y, Image.INTERPOLATE_LANCZOS)
	var path: String = "%s/%s-%s.png" % [out_dir, tag, label]
	var err: int = img.save_png(ProjectSettings.globalize_path(path))
	print("снято: %s (%dx%d), код %d" % [path, img.get_width(), img.get_height(), err])
	return err == OK


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e: InputEventScreenTouch = InputEventScreenTouch.new()
	e.index = index
	e.position = root.get_viewport().get_final_transform() * pos
	e.pressed = pressed
	Input.parse_input_event(e)


func _frames(n: int) -> void:
	var p: Node = scene.get("player") if scene != null else null
	var cam = p.get("camera") if p != null else null
	for i in n:
		if cam != null:
			cam.position = Vector2.ZERO
			cam.offset = Vector2.ZERO
		await process_frame
