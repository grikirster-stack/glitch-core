extends SceneTree
## Кадр луча (#164): ночь, горелка горит, луч виден на пустых клетках и упирается в стену.
##
## Headless не рисует. Окно за экраном, без звука, скрипт сам выходит:
##   timeout 120 godot --path . --audio-driver Dummy --disable-vsync \
##     --windowed --position -10000,-10000 --resolution 1280x720 \
##     --script res://tools/beam_shot.gd -- --seed=31337

const OUT: String = "res://docs/img/shots/light_beam.png"
const HARD_LIMIT: float = 20.0

var _elapsed: float = 0.0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("beam_shot: headless не рендерит — нужен прогон с окном за экраном")
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
		push_error("beam_shot: превышен лимит %.0f с" % HARD_LIMIT)
		quit(2)
		return true
	return false


func _run() -> void:
	var world: Node = root.get_node("World")
	var game: Node = root.get_node("Game")
	game.set("time_of_day", 0.80)   # ночь: луч должен читаться без дневного света
	game.set("game_time", 30.0)     # стартовые подсказки уже погасли
	await _frames(8)
	var origin: Vector2i = world.beacon_cell + Vector2i(22, -4)
	for x in range(origin.x - 3, origin.x + 22):
		for y in range(origin.y - 3, origin.y + 6):
			if world.in_bounds(x, y):
				world.set_tile(x, y, IDs.T.AIR)
	# Пол под коридором и стена, в которую луч упирается.
	for x in range(origin.x - 3, origin.x + 22):
		world.set_tile(x, origin.y + 3, IDs.T.STONE)
	for y in range(origin.y - 2, origin.y + 3):
		world.set_tile(origin.x + 16, y, IDs.T.STONE)
	var mb: GDScript = load("res://scripts/machines/machine_base.gd")
	if not mb.place_machine("Burner", origin):
		push_error("beam_shot: горелка не встала")
		quit(1)
		return
	var burner = world.machines[origin]
	burner.add_fuel(IDs.I.COAL, 3)
	world.beams.rebuild()
	world._apply_beam_lights()
	var player: Node2D = current_scene.get("player")
	if player != null:
		player.global_position = world.cell_to_world(origin + Vector2i(2, 2))
		var cam: Camera2D = player.get("camera")
		if cam != null:
			cam.position_smoothing_enabled = false
			cam.zoom = Vector2(3.6, 3.6)
			cam.global_position = world.cell_to_world(origin + Vector2i(8, 0))
			cam.reset_smoothing()
	var ui: Node = root.get_node_or_null("UI")
	var hud: Node = ui.get("hud") if ui != null else null
	if hud != null:
		hud.set("tutorial_text", "")
		hud.set("hint_text", "")
		hud.set("notes", [])
		hud.set("tracker_title", "")
		hud.set("tracker_detail", "")
	await _frames(8)
	var img: Image = root.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err: int = img.save_png(path)
	print("beam_shot: %s (%d), луч %d клеток" % [path, err, world.beams.cells.size()])
	quit(0 if err == OK else 1)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
