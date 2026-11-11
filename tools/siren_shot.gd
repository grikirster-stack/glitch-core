extends SceneTree
## Кадр сирены (#172): блок виден, кольцо и рой уходят от него.
## Ребёнок должен понять: нажал — стая бежит прочь.
##
## Headless не рисует. Окно за экраном:
##   timeout 120 /tmp/godot47/Godot --path . --audio-driver Dummy --disable-vsync \
##     --windowed --position -10000,-10000 --resolution 1280x720 \
##     --script res://tools/siren_shot.gd -- --seed=31337

const OUT: String = "res://docs/img/shots/siren.png"
const HARD_LIMIT: float = 20.0

var _elapsed: float = 0.0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("siren_shot: headless не рендерит — нужен прогон с окном за экраном")
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
		push_error("siren_shot: превышен лимит %.0f с" % HARD_LIMIT)
		quit(2)
		return true
	return false


func _run() -> void:
	var world: Node = root.get_node("World")
	var game: Node = root.get_node("Game")
	game.set("time_of_day", 0.80)
	game.set("game_time", 30.0)
	await _frames(8)
	var origin: Vector2i = world.beacon_cell + Vector2i(-14, -4)
	for x in range(origin.x - 6, origin.x + 22):
		for y in range(origin.y - 6, origin.y + 8):
			if world.in_bounds(x, y):
				world.set_tile(x, y, IDs.T.AIR)
	for x in range(origin.x - 6, origin.x + 22):
		world.set_tile(x, origin.y + 3, IDs.T.STONE)
	var doomed: Array = []
	for c in world.machines.keys():
		if c.x >= origin.x - 2 and c.x <= origin.x + 16 and c.y >= origin.y - 2 and c.y <= origin.y + 2:
			doomed.append(c)
	for c in doomed:
		var old = world.machines[c]
		if old.has_method("dismantle"):
			old.dismantle()
	var mb: GDScript = load("res://scripts/machines/machine_base.gd")
	var ph_script: GDScript = load("res://scripts/entities/phantom.gd")
	if not mb.place_machine("Burner", origin):
		push_error("siren_shot: горелка не встала")
		quit(1)
		return
	var sc: Vector2i = origin + Vector2i(4, 0)
	if not mb.place_machine("Siren", sc):
		push_error("siren_shot: сирена не встала")
		quit(1)
		return
	var burner = world.machines[origin]
	burner.add_fuel(IDs.I.COAL, 3)
	if world.beams != null:
		world.beams.note_machines()
		world.beams.rebuild()
	world._apply_beam_lights()
	var siren = world.machines[sc]
	siren.charge = 60.0
	siren.charging = true
	# Рой и тень уже справа от рупора и смотрят прочь: ребёнок видит, куда гонит.
	# Под сиреной тень стояла бы на месте — у пешего гона нет горизонтали вверх.
	var pack: Array = []
	for i in 5:
		var moth = ph_script.create("swarm")
		moth.player = current_scene.get("player")
		current_scene.add_child(moth)
		moth.global_position = world.cell_to_world(sc + Vector2i(5 + i % 3, -2 + int(i / 3)))
		moth.force_flee(10.0, siren.global_position)
		moth.facing = 1
		pack.append(moth)
	var shade = ph_script.create("shade")
	shade.player = current_scene.get("player")
	current_scene.add_child(shade)
	shade.global_position = world.cell_to_world(sc + Vector2i(6, 2))
	shade.force_flee(10.0, siren.global_position)
	shade.facing = 1
	var fx = current_scene.get("world_fx")
	if fx != null and fx.has_method("spawn_ring"):
		fx.spawn_ring(siren.global_position, Color(1.0, 0.55, 0.15))
		# Кольцо чуть подросло: на нулевом кадре его почти не видно.
		if fx.rings.size() > 0:
			fx.rings[fx.rings.size() - 1]["t"] = 0.18
	siren._ring = 0.55
	var player: Node2D = current_scene.get("player")
	if player != null:
		player.global_position = world.cell_to_world(origin + Vector2i(0, 5))
		var cam: Camera2D = player.get("camera")
		if cam != null:
			cam.position_smoothing_enabled = false
			cam.zoom = Vector2(4.0, 4.0)
			cam.global_position = world.cell_to_world(sc + Vector2i(2, 0))
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
	await _frames(8)
	var img: Image = root.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err: int = img.save_png(path)
	print("siren_shot: %s (%d), заряд %.0f, рой %d" % [path, err, float(siren.charge), pack.size()])
	quit(0 if err == OK else 1)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame
