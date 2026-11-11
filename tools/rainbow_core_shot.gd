extends SceneTree
## Кадр Радужного ядра (#175): предмет стоит в мире, семь дуг горят.
## Трекер и уведомления погашены — в кадре куб, дуги и лучи, не простыня текста.
##
## Headless не рисует. Окно за экраном, без звука, скрипт сам выходит:
##   timeout 120 /tmp/godot47/Godot --path . --audio-driver Dummy --disable-vsync \
##     --windowed --position -10000,-10000 --resolution 1280x720 \
##     --script res://tools/rainbow_core_shot.gd -- --seed=31337

const OUT: String = "res://docs/img/shots/rainbow_core.png"
const HARD_LIMIT: float = 20.0

var _elapsed: float = 0.0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("rainbow_core_shot: headless не рендерит — нужен прогон с окном за экраном")
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
		push_error("rainbow_core_shot: превышен лимит %.0f с" % HARD_LIMIT)
		quit(2)
		return true
	return false


func _run() -> void:
	var world: Node = root.get_node("World")
	var game: Node = root.get_node("Game")
	game.set("time_of_day", 0.78)
	game.set("game_time", 40.0)
	await _frames(8)
	var origin: Vector2i = world.beacon_cell + Vector2i(18, -6)
	for x in range(origin.x - 8, origin.x + 10):
		for y in range(origin.y - 6, origin.y + 6):
			if world.in_bounds(x, y):
				world.set_tile(x, y, IDs.T.AIR)
	for x in range(origin.x - 8, origin.x + 10):
		world.set_tile(x, origin.y + 2, IDs.T.STONE)
	var doomed: Array = []
	for c in world.machines.keys():
		if c.x >= origin.x - 6 and c.x <= origin.x + 8 and c.y >= origin.y - 4 and c.y <= origin.y + 2:
			doomed.append(c)
	for c in doomed:
		var old = world.machines[c]
		if old.has_method("dismantle"):
			old.dismantle()
	var mb: GDScript = load("res://scripts/machines/machine_base.gd")
	var core_cell: Vector2i = origin + Vector2i(0, 1)
	if not mb.place_machine("RainbowCore", core_cell):
		push_error("rainbow_core_shot: ядро не встало")
		quit(1)
		return
	if not _burn(mb, world, origin + Vector2i(4, 1), IDs.I.COAL, 2):
		return
	if not _burn(mb, world, origin + Vector2i(4, -1), IDs.I.COPPER_ORE, 2):
		return
	if not _burn(mb, world, origin + Vector2i(-4, 1), IDs.I.CRYSTAL, 0):
		return
	if world.beams != null:
		world.beams.note_machines()
		world.beams.rebuild()
	if world.has_method("_apply_beam_lights") and world.beams != null:
		world._apply_beam_lights()
	await _frames(4)
	# Смеси в кадре не строим: четыре чистых цвета уже в ядре лучом,
	# остальные три дуги зажигаем той же маской, что core_feed.
	game.set("core_arcs", 0x7F)
	var core = world.machines[core_cell]
	if core != null:
		core.queue_redraw()
	await _frames(3)
	if int(game.core_arcs) != 0x7F:
		push_error("rainbow_core_shot: дуг %d, ждали 7" % game.call("core_arc_count"))
		quit(1)
		return
	var player: Node2D = current_scene.get("player")
	if player != null:
		player.global_position = world.cell_to_world(origin + Vector2i(2, 5))
		var cam: Camera2D = player.get("camera")
		if cam != null:
			cam.position_smoothing_enabled = false
			cam.zoom = Vector2(6.0, 6.0)
			cam.global_position = world.cell_to_world(core_cell)
			cam.reset_smoothing()
	var ui: Node = root.get_node_or_null("UI")
	var hud: Node = ui.get("hud") if ui != null else null
	if hud != null:
		hud.set("tutorial_step", 99)
		hud.set("tutorial_text", "")
		hud.set("hint_text", "")
		hud.set("notes", [])
		hud.set("tracker_title", "")
		hud.set("tracker_detail", "")
		hud.set("card_text", "")
		hud.set("hint_text", "")
		hud.set("_hint_t", 1.0e6)
	if player != null:
		player.set("test_input", {"keys": {}, "mouse": Vector2(-10000, -10000), "mouse_buttons": {}})
	await _frames(6)
	var img: Image = root.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err: int = img.save_png(path)
	print("rainbow_core_shot: %s (%d), дуг %d" % [path, err, game.call("core_arc_count")])
	quit(0 if err == OK else 1)


func _burn(mb: GDScript, world: Node, cell: Vector2i, fuel: int, dir: int) -> bool:
	if not mb.place_machine("Burner", cell):
		push_error("rainbow_core_shot: горелка не встала %s" % str(cell))
		quit(1)
		return false
	var b = world.machines[cell]
	b.dir = dir
	b.add_fuel(fuel, 4)
	return true


func _frames(n: int) -> void:
	for i in n:
		await process_frame
