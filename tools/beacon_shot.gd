extends SceneTree
## Кадр маяка (#167): ночь, красный луч вошёл в башню, башня жжёт.
## Рядом фантом и вспышка дуги — ребёнок видит, куда делся луч.
##
## Headless не рисует. Окно за экраном, без звука, скрипт сам выходит:
##   timeout 120 /tmp/godot47/Godot --path . --audio-driver Dummy --disable-vsync \
##     --windowed --position -10000,-10000 --resolution 1280x720 \
##     --script res://tools/beacon_shot.gd -- --seed=31337

const OUT: String = "res://docs/img/shots/beacon_red.png"
const HARD_LIMIT: float = 20.0

var _elapsed: float = 0.0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("beacon_shot: headless не рендерит — нужен прогон с окном за экраном")
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
		push_error("beacon_shot: превышен лимит %.0f с" % HARD_LIMIT)
		quit(2)
		return true
	return false


func _run() -> void:
	var world: Node = root.get_node("World")
	var game: Node = root.get_node("Game")
	var threat: Node = root.get_node("Threat")
	game.set("time_of_day", 0.80)
	game.set("game_time", 30.0)
	await _frames(8)
	# Площадка у базы, не у руин: ребёнок видит луч, башню и фантома на пустом небе.
	var origin: Vector2i = world.beacon_cell + Vector2i(-16, -4)
	for x in range(origin.x - 4, origin.x + 20):
		for y in range(origin.y - 6, origin.y + 8):
			if world.in_bounds(x, y):
				world.set_tile(x, y, IDs.T.AIR)
	for x in range(origin.x - 4, origin.x + 20):
		world.set_tile(x, origin.y + 3, IDs.T.STONE)
	# Постройки базы на пути луча — снять, иначе луч упирается не в маяк.
	var doomed: Array = []
	for c in world.machines.keys():
		if c.x >= origin.x - 1 and c.x <= origin.x + 16 and c.y >= origin.y - 2 and c.y <= origin.y + 2:
			doomed.append(c)
	for c in doomed:
		var old = world.machines[c]
		if old.has_method("dismantle"):
			old.dismantle()
	var mb: GDScript = load("res://scripts/machines/machine_base.gd")
	var ph_script: GDScript = load("res://scripts/entities/phantom.gd")
	if not mb.place_machine("Burner", origin):
		push_error("beacon_shot: горелка не встала")
		quit(1)
		return
	var pc: Vector2i = origin + Vector2i(6, 0)
	if not mb.place_machine("Pharos", pc):
		push_error("beacon_shot: маяк не встал")
		quit(1)
		return
	var burner = world.machines[origin]
	burner.add_fuel(IDs.I.COAL, 3)
	if world.beams != null:
		world.beams.note_machines()
	world.beams.rebuild()
	world._apply_beam_lights()

	var pharos = world.machines[pc]
	# Фантом справа от башни, в линии выстрела. Дугу рисуем сами: кадр не ждёт 0.8 с.
	var echo = ph_script.create("echo")
	echo.player = current_scene.get("player")
	current_scene.add_child(echo)
	echo.global_position = world.cell_to_world(pc + Vector2i(3, 1))
	var fx = current_scene.get("world_fx")
	if fx != null and fx.has_method("spawn_arc"):
		var red: Color = load("res://scripts/world/beams.gd").COLOR[1]
		fx.spawn_arc(pharos.global_position + Vector2(0.0, -6.0), echo.global_position, red)
	var player: Node2D = current_scene.get("player")
	if player != null:
		# Ниже луча, чтобы подсказка E не закрывала горелку.
		player.global_position = world.cell_to_world(origin + Vector2i(1, 5))
		var cam: Camera2D = player.get("camera")
		if cam != null:
			cam.position_smoothing_enabled = false
			cam.zoom = Vector2(4.5, 4.5)
			cam.global_position = world.cell_to_world(origin + Vector2i(5, 1))
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
	await _frames(6)
	var img: Image = root.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err: int = img.save_png(path)
	print("beacon_shot: %s (%d), цвет маяка %d, луч %d клеток" % [
			path, err, int(pharos.color), world.beams.cells.size()])
	quit(0 if err == OK and int(pharos.color) == 1 else 1)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
