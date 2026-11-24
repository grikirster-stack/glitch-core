extends SceneTree
## Кадр пресса (#314): грядка → сундук → пресс → сундук.
## Зелёная щель — вход, светлая — выход. Партия в работе, панель на выходе.
##
## Headless не рисует. Окно за экраном, без звука:
##   flock /tmp/godot-stand.lock timeout 120 ~/godot-4.7.2/godot --path . \
##     --audio-driver Dummy --disable-vsync --fixed-fps 60 --windowed \
##     --position -10000,-10000 --resolution 1280x720 \
##     --script res://tools/press_shot.gd -- --seed=31337
## Телефонный угол — тот же скрипт с --resolution 720x1280.

const OUT_WIDE: String = "res://docs/img/shots/press.png"
const OUT_PHONE: String = "res://docs/img/shots/press_phone.png"
const HARD_LIMIT: float = 25.0

var _elapsed: float = 0.0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("press_shot: headless не рендерит — нужен прогон с окном за экраном")
		quit(1)
		return
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	root.position = Vector2i(-10000, -10000)
	_boot.call_deferred()


func _boot() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > HARD_LIMIT:
		push_error("press_shot: превышен лимит %.0f с" % HARD_LIMIT)
		quit(2)
		return true
	return false


func _run() -> void:
	var world: Node = root.get_node("World")
	var game: Node = root.get_node("Game")
	game.set("time_of_day", 0.30)
	game.set("game_time", 40.0)
	await _frames(8)
	var origin: Vector2i = Vector2i(world.beacon_cell.x + 28, world.beacon_cell.y + 8)
	for x in range(origin.x - 6, origin.x + 14):
		for y in range(0, origin.y + 8):
			if world.in_bounds(x, y):
				world.set_tile(x, y, IDs.T.AIR)
	for x in range(origin.x - 6, origin.x + 14):
		world.set_tile(x, origin.y + 4, IDs.T.STONE)
	var mb: GDScript = load("res://scripts/machines/machine_base.gd")
	if not mb.place_machine("Collector", origin):
		push_error("press_shot: коллектор не встал")
		quit(1)
		return
	var col = world.machines[origin]
	col.dir = 0
	if col.has_method("_check_sky"):
		col._check_sky()
	var bed_cell: Vector2i = origin + Vector2i(3, 0)
	var chest_cell: Vector2i = origin + Vector2i(4, 0)
	var press_cell: Vector2i = origin + Vector2i(5, 0)
	var out_cell: Vector2i = origin + Vector2i(6, 0)
	world.set_tile(bed_cell.x, bed_cell.y, IDs.T.AIR)
	if not mb.place_machine("SporeBed", bed_cell):
		push_error("press_shot: грядка не встала")
		quit(1)
		return
	if not mb.place_machine("Chest", chest_cell) or not mb.place_machine("Press", press_cell) \
			or not mb.place_machine("Chest", out_cell):
		push_error("press_shot: цепочка не встала")
		quit(1)
		return
	var bed = world.machines[bed_cell]
	var press = world.machines[press_cell]
	var inn = world.machines[chest_cell]
	var outc = world.machines[out_cell]
	bed.dir = 0
	bed.tray = 2
	bed.grow = 6.0
	if bed.has_method("_sync_progress"):
		bed._sync_progress()
	press.dir = 2
	press.batch = 2
	press.job = 4.0
	press.out_buf = 2
	press.queued = 1
	if press.has_method("_sync_progress"):
		press._sync_progress()
	inn.receive_item(IDs.I.SPORE_FIBER, 2)
	outc.receive_item(IDs.I.PANEL, 4)
	world.beams.note_machines()
	world.beams.rebuild()
	world._apply_beam_lights()
	world.reveal_around(press_cell, 16)
	# Иначе за 12 кадров пресс сам отдаст буфер в сундук, и партия на кадре не видна.
	press.set_process(false)
	# Камера героя смотрит в его точку и не дальше зума 4.4: цепочка из пяти
	# станков в 16 px не читается. Своя камера на прессе, герой спрятан.
	var player: Node2D = current_scene.get("player")
	if player != null:
		player.visible = false
		player.set_physics_process(false)
		player.set_process(false)
		var pcam: Camera2D = player.get("camera")
		if pcam != null:
			pcam.enabled = false
			pcam.set_process(false)
	# Камера — дочерняя мира: position в мировых px, не в локальных сцены.
	var cam := Camera2D.new()
	cam.position_smoothing_enabled = false
	cam.zoom = Vector2(8.0, 8.0)
	cam.limit_left = -100000
	cam.limit_top = -100000
	cam.limit_right = 100000
	cam.limit_bottom = 100000
	cam.limit_smoothed = false
	cam.position = world.cell_to_world(press_cell)
	world.add_child(cam)
	cam.make_current()
	cam.reset_smoothing()
	cam.force_update_scroll()
	var ui: Node = root.get_node_or_null("UI")
	var hud: Node = ui.get("hud") if ui != null else null
	if hud != null:
		hud.set("tutorial_step", 5)
		hud.set("tutorial_text", "")
		hud.set("hint_text", "")
		hud.set("notes", [])
		hud.visible = false
	await _frames(12)
	var img: Image = root.get_texture().get_image()
	var wide: bool = img.get_width() >= img.get_height()
	var path: String = ProjectSettings.globalize_path(OUT_WIDE if wide else OUT_PHONE)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err: int = img.save_png(path)
	var into: int = world.beams.color_at(bed_cell + Vector2i(-1, 0))
	print("press_shot: %s (%d) %dx%d, белый %d, lit %s, партия %d, буфер %d, вход %s, выход %s" % [
			path, err, img.get_width(), img.get_height(), into, bed.lit,
			press.batch, press.out_buf, press.in_cell(), press.out_cell()])
	quit(0 if err == OK and into == 7 and bed.lit and press.batch == 2 and press.out_buf >= 1 else 1)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
