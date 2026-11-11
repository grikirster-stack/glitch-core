extends SceneTree
## Кадр диагонали: ночь, луч наискосок упирается в стену.
##
## Headless не рисует. Окно за экраном, без звука, скрипт сам выходит:
##   timeout 120 godot --path . --audio-driver Dummy --disable-vsync --fixed-fps 60 \
##     --windowed --position -10000,-10000 --resolution 1280x720 \
##     --script res://tools/beam_diagonal_shot.gd -- --seed=31337

const OUT: String = "res://docs/img/shots/beam_diagonal.png"
const HARD_LIMIT: float = 20.0

var _elapsed: float = 0.0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("beam_diagonal_shot: headless не рендерит — нужен прогон с окном за экраном")
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
		push_error("beam_diagonal_shot: превышен лимит %.0f с" % HARD_LIMIT)
		quit(2)
		return true
	return false


func _run() -> void:
	var world: Node = root.get_node("World")
	var game: Node = root.get_node("Game")
	game.set("time_of_day", 0.82)
	game.set("game_time", 40.0)
	await _frames(8)
	var origin: Vector2i = world.beacon_cell + Vector2i(6, -12)
	for x in range(origin.x - 4, origin.x + 16):
		for y in range(origin.y - 2, origin.y + 16):
			if world.in_bounds(x, y):
				world.set_tile(x, y, IDs.T.AIR)
	# Пол и стена, в которую диагональ упирается на 8-й клетке.
	for x in range(origin.x - 4, origin.x + 16):
		world.set_tile(x, origin.y + 12, IDs.T.STONE)
	for y in range(origin.y + 6, origin.y + 12):
		world.set_tile(origin.x + 8, y, IDs.T.STONE)
	var mb: GDScript = load("res://scripts/machines/machine_base.gd")
	if not mb.place_machine("Burner", origin):
		push_error("beam_diagonal_shot: горелка не встала")
		quit(1)
		return
	var burner = world.machines[origin]
	burner.dir = 4
	burner.add_fuel(IDs.I.COAL, 3)
	# Рядом — зеркало, которое переводит прямой луч в диагональ. На кадре
	# виден именно упор в стену, не свободный угол.
	var mirror_cell: Vector2i = origin + Vector2i(-4, 2)
	if world.in_bounds(mirror_cell.x, mirror_cell.y):
		world.set_tile(mirror_cell.x, mirror_cell.y, IDs.T.AIR)
	world.beams.note_machines()
	world.beams.rebuild()
	world._apply_beam_lights()
	var player: Node2D = current_scene.get("player")
	if player != null:
		player.global_position = world.cell_to_world(origin + Vector2i(-2, 8))
		var cam: Camera2D = player.get("camera")
		if cam != null:
			cam.position_smoothing_enabled = false
			cam.zoom = Vector2(3.6, 3.6)
			cam.global_position = world.cell_to_world(origin + Vector2i(4, 5))
			cam.reset_smoothing()
	var ui: Node = root.get_node_or_null("UI")
	var hud: Node = ui.get("hud") if ui != null else null
	if hud != null:
		hud.set("tutorial_step", 5)
		hud.set("tutorial_text", "")
		hud.set("hint_text", "")
		hud.set("notes", [])
		hud.set("tracker_title", "")
		hud.set("tracker_detail", "")
		hud.visible = false
	await _frames(10)
	var img: Image = root.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err: int = img.save_png(path)
	var step: Vector2i = Vector2i(1, 1)
	var before: int = world.beams.color_at(origin + step * 7)
	var on_wall: int = world.beams.color_at(origin + step * 8)
	var past: int = world.beams.color_at(origin + step * 9)
	print("beam_diagonal_shot: %s (%d), до стены %d, стена %d, за стеной %d, клеток %d" % [
			path, err, before, on_wall, past, world.beams.cells.size()])
	quit(0 if err == OK and before == 1 and on_wall == 0 and past == 0 else 1)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
