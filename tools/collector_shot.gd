extends SceneTree
## Кадр коллектора (#166): день, белый луч виден, упирается в стену и входит в накопитель.
##
## Headless не рисует. Окно за экраном, без звука, скрипт сам выходит:
##   timeout 120 godot --path . --audio-driver Dummy --disable-vsync --fixed-fps 60 \
##     --windowed --position -10000,-10000 --resolution 1280x720 \
##     --script res://tools/collector_shot.gd -- --seed=31337

const OUT: String = "res://docs/img/shots/collector.png"
const HARD_LIMIT: float = 25.0

var _elapsed: float = 0.0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("collector_shot: headless не рендерит — нужен прогон с окном за экраном")
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
		push_error("collector_shot: превышен лимит %.0f с" % HARD_LIMIT)
		quit(2)
		return true
	return false


func _run() -> void:
	var world: Node = root.get_node("World")
	var game: Node = root.get_node("Game")
	# Полдень: коллектор светит, дневной свет не должен съесть белую линию.
	game.set("time_of_day", 0.30)
	game.set("game_time", 40.0)
	await _frames(8)
	# Ниже потолка базы и в стороне от руин: луч идёт по открытому небу.
	var origin: Vector2i = Vector2i(world.beacon_cell.x + 28, world.beacon_cell.y + 8)
	for x in range(origin.x - 4, origin.x + 24):
		for y in range(0, origin.y + 10):
			if world.in_bounds(x, y):
				world.set_tile(x, y, IDs.T.AIR)
	for x in range(origin.x - 4, origin.x + 24):
		world.set_tile(x, origin.y + 5, IDs.T.STONE)
	# Стена сразу за накопителем: луч входит в него и дальше не идёт.
	for y in range(origin.y - 3, origin.y + 5):
		world.set_tile(origin.x + 10, y, IDs.T.STONE)
	var mb: GDScript = load("res://scripts/machines/machine_base.gd")
	if not mb.place_machine("Collector", origin):
		push_error("collector_shot: коллектор не встал")
		quit(1)
		return
	var col = world.machines[origin]
	col.dir = 0
	if col.has_method("_check_sky"):
		col._check_sky()
	# Накопитель сбоку от стены, чтобы луч в него входил, а не обрывался раньше.
	var acc_cell: Vector2i = origin + Vector2i(8, 0)
	world.set_tile(acc_cell.x, acc_cell.y, IDs.T.AIR)
	if not mb.place_machine("Accumulator", acc_cell):
		push_error("collector_shot: накопитель не встал")
		quit(1)
		return
	var acc = world.machines[acc_cell]
	acc.dir = 0
	acc.stored = 40.0
	acc.color = 7
	world.beams.note_machines()
	world.beams.rebuild()
	world._apply_beam_lights()
	# Туман войны закрыл бы стену и накопитель: кадр должен их показать.
	world.reveal_around(origin + Vector2i(8, 0), 24)
	var player: Node2D = current_scene.get("player")
	if player != null:
		player.global_position = world.cell_to_world(origin + Vector2i(-2, 4))
		var cam: Camera2D = player.get("camera")
		if cam != null:
			cam.position_smoothing_enabled = false
			cam.zoom = Vector2(3.6, 3.6)
			cam.global_position = world.cell_to_world(origin + Vector2i(7, 0))
			cam.reset_smoothing()
	var ui: Node = root.get_node_or_null("UI")
	var hud: Node = ui.get("hud") if ui != null else null
	if hud != null:
		hud.set("tutorial_step", 5)
		hud.set("tutorial_text", "")
		hud.set("hint_text", "")
		hud.set("notes", [])
		hud.visible = false
	await _frames(10)
	var img: Image = root.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err: int = img.save_png(path)
	var beam: int = world.beams.color_at(origin + Vector2i(2, 0))
	var into: int = world.beams.color_at(acc_cell + Vector2i(-1, 0))
	var past: int = world.beams.color_at(acc_cell + Vector2i(1, 0))
	print("collector_shot: %s (%d), луч %d, в накопитель %d, сквозь %d" % [
			path, err, beam, into, past])
	quit(0 if err == OK and beam == 7 and into == 7 and past == 0 else 1)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
