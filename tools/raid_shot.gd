extends SceneTree
## Кадр предупреждения и итога налёта (#316). Окно живое, не SubViewport.
##
##   DISPLAY=:47 godot --path . --audio-driver Dummy --touch \
##         --resolution 1280x2560 --position 0,0 \
##         --script res://tools/raid_shot.gd -- --mode=warn --out=res://docs/img/shots/raid_warn_phone.png --seed=31337
##
## --mode=warn|result. --touch включает сенсорную плашку. Без --touch — ПК.

const HARD_LIMIT: float = 25.0

var scene: Node = null
var _elapsed: float = 0.0
var mode: String = "warn"
var out_path: String = ""
var want: Vector2i = Vector2i(1280, 720)


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("raid_shot: headless не рендерит")
		quit(1)
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			mode = a.substr(7)
		elif a.begins_with("--out="):
			out_path = a.substr(6)
	want = DisplayServer.window_get_size()
	if want.x < 64 or want.y < 64:
		want = Vector2i(1280, 720)
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	root.position = Vector2i(0, 0)
	root.size = want
	_boot.call_deferred()


func _boot() -> void:
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	scene = main_scene.instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > HARD_LIMIT:
		push_error("raid_shot: лимит")
		quit(2)
	return false


func _run() -> void:
	var game: Node = root.get_node("Game")
	var world: Node = root.get_node("World")
	var threat: Node = root.get_node("Threat")
	scene.set("scenario_mode", true)
	game.set("scenario_mode", true)
	game.set("game_time", 40.0)
	game.set("time_of_day", 0.70)
	game.set("day_number", 3)
	root.size = want
	await _frames(12)
	var ui: Node = root.get_node("UI")
	if OS.get_cmdline_user_args().has("--touch"):
		ui.set("touch_on", true)
	var hud: Node = ui.get("hud")
	var player: Node2D = scene.get("player")
	var origin: Vector2i = world.beacon_cell + Vector2i(10, -4)
	_room(world, origin, true)
	var inside: Vector2i = origin + Vector2i(2, 1)
	world.set_tile(inside.x, inside.y, IDs.T.AIR)
	var MachineBase = load("res://scripts/machines/machine_base.gd")
	MachineBase.place_machine("SporeBed", inside)
	var bed = world.machines.get(inside)
	if bed != null and bed.has_method("beam_receive"):
		bed.beam_receive(0)
	# Герой в стороне, чтобы стрелка цели была у края, а не в кадре.
	var away: Vector2i = world.beacon_cell + Vector2i(-24, 10)
	if world.in_bounds(away.x, away.y):
		world.set_tile(away.x, away.y, IDs.T.AIR)
		world.set_tile(away.x, away.y + 1, IDs.T.STONE)
		player.global_position = world.cell_to_world(away)
	player.vel = Vector2.ZERO
	if player.get("camera") != null:
		player.camera.reset_smoothing()
	hud.hint_text = ""
	hud.tutorial_text = ""
	hud.notes.clear()
	if hud.get("_intro_done") != null:
		hud.set("_intro_done", true)
	threat.set("active", true)
	threat.tick(0.05)
	if mode == "result":
		game.set("raid_phase", 3)
		game.set("raid_damage", "section")
		threat.set("raid_side", "востока")
		hud.raid_line = "Налёт с востока: участок встанет за сутки"
		hud.raid_cell = inside
	else:
		if int(game.raid_phase) != 1:
			game.set("raid_phase", 1)
			game.set("raid_target", inside)
			game.set("raid_remain", 25.0)
			hud.raid_line = "Налёт с востока, цель — грядка"
			hud.raid_cell = inside
	await _frames(6)
	var plate: String = hud.plate_text() if hud.has_method("plate_text") else ""
	print("raid_shot: плашка «%s»" % plate)
	if plate.contains("[E]") or plate.contains("ПКМ"):
		push_error("raid_shot: в плашке клавиша")
		quit(3)
		return
	if plate == "":
		push_error("raid_shot: плашка пуста")
		quit(4)
		return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		push_error("raid_shot: пустой кадр")
		quit(5)
		return
	print("raid_shot: кадр %dx%d окно %s" % [img.get_width(), img.get_height(), str(want)])
	if img.get_width() != want.x or img.get_height() != want.y:
		push_error("raid_shot: размер не совпал")
		quit(6)
		return
	var path: String = ProjectSettings.globalize_path(out_path)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err: int = img.save_png(path)
	print("raid_shot: %s (%d)" % [path, err])
	quit(0 if err == OK else 1)


func _room(world: Node, origin: Vector2i, door_open: bool) -> void:
	var door: Vector2i = origin + Vector2i(4, 1)
	for y in range(0, 3):
		for x in range(0, 5):
			var c: Vector2i = origin + Vector2i(x, y)
			if not world.in_bounds(c.x, c.y):
				continue
			if c == door:
				world.set_tile(c.x, c.y, IDs.T.DOOR_OPEN if door_open else IDs.T.DOOR)
			elif y == 0 or y == 2 or x == 0 or x == 4:
				world.set_tile(c.x, c.y, IDs.T.ROOM_PANEL)
			else:
				world.set_tile(c.x, c.y, IDs.T.AIR)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
