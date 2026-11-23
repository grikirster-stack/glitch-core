extends SceneTree
## Кадр споровой грядки (#313): белый вход, росток и волокно на лотке.
##
## Headless не рисует. Окно за экраном, без звука, скрипт сам выходит:
##   flock /tmp/godot-stand.lock timeout 120 godot --path . --audio-driver Dummy \
##     --disable-vsync --fixed-fps 60 --windowed --position -10000,-10000 \
##     --resolution 2400x1080 --script res://tools/spore_bed_shot.gd -- --seed=31337
## Запрошенные 2400×1080 дисплей обрезает: файл выходит 1850×1016.

const OUT: String = "res://docs/img/shots/spore_bed.png"
const HARD_LIMIT: float = 25.0

var _elapsed: float = 0.0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("spore_bed_shot: headless не рендерит — нужен прогон с окном за экраном")
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
		push_error("spore_bed_shot: превышен лимит %.0f с" % HARD_LIMIT)
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
	for x in range(origin.x - 4, origin.x + 16):
		for y in range(0, origin.y + 8):
			if world.in_bounds(x, y):
				world.set_tile(x, y, IDs.T.AIR)
	for x in range(origin.x - 4, origin.x + 16):
		world.set_tile(x, origin.y + 4, IDs.T.STONE)
	var mb: GDScript = load("res://scripts/machines/machine_base.gd")
	if not mb.place_machine("Collector", origin):
		push_error("spore_bed_shot: коллектор не встал")
		quit(1)
		return
	var col = world.machines[origin]
	col.dir = 0
	if col.has_method("_check_sky"):
		col._check_sky()
	var bed_cell: Vector2i = origin + Vector2i(3, 0)
	world.set_tile(bed_cell.x, bed_cell.y, IDs.T.AIR)
	if not mb.place_machine("SporeBed", bed_cell):
		push_error("spore_bed_shot: грядка не встала")
		quit(1)
		return
	var bed = world.machines[bed_cell]
	# Лоток уже с волокном, росток на середине — кадр показывает вход и выход сразу.
	bed.tray = 2
	bed.grow = 6.0
	if bed.has_method("_sync_progress"):
		bed._sync_progress()
	world.beams.note_machines()
	world.beams.rebuild()
	world._apply_beam_lights()
	world.reveal_around(bed_cell, 16)
	# Камера — дочерняя у героя: смотрит туда, где он стоит, не в свою global_position.
	var player: Node2D = current_scene.get("player")
	if player != null:
		player.global_position = world.cell_to_world(origin + Vector2i(1, 0))
		var cam: Camera2D = player.get("camera")
		if cam != null:
			cam.position_smoothing_enabled = false
			cam.zoom = Vector2(8.0, 8.0)
			cam.offset = Vector2.ZERO
			cam.reset_smoothing()
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
	var path: String = ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err: int = img.save_png(path)
	var into: int = world.beams.color_at(bed_cell + Vector2i(-1, 0))
	print("spore_bed_shot: %s (%d), белый перед входом %d, lit %s, лоток %d, стадия %d" % [
			path, err, into, bed.lit, bed.tray, bed.stage()])
	quit(0 if err == OK and into == 7 and bed.lit and bed.tray == 2 else 1)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
