extends SceneTree
## Кадр каркаса пристройки (#312): навес с открытой дверью и лучом,
## закрытая пристройка с другой дверью, обшивка фоном.
##
## Headless не рисует. Окно за экраном, без звука:
##   flock /tmp/godot-stand.lock timeout 120 ~/godot-4.7.2/godot --path . \
##     --audio-driver Dummy --disable-vsync --fixed-fps 60 --windowed \
##     --position -10000,-10000 --resolution 2400x1080 \
##     --script res://tools/room_parts_shot.gd -- --seed=31337

const OUT: String = "res://docs/img/shots/room_parts.png"
const HARD_LIMIT: float = 25.0

var _elapsed: float = 0.0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("room_parts_shot: headless не рендерит — нужен прогон с окном за экраном")
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
		push_error("room_parts_shot: превышен лимит %.0f с" % HARD_LIMIT)
		quit(2)
		return true
	return false


func _run() -> void:
	var world: Node = root.get_node("World")
	var game: Node = root.get_node("Game")
	game.set("time_of_day", 0.35)
	await _frames(6)
	var origin: Vector2i = Vector2i(world.beacon_cell.x + 24, world.beacon_cell.y + 6)
	for x in range(origin.x - 3, origin.x + 18):
		for y in range(origin.y - 4, origin.y + 6):
			if world.in_bounds(x, y):
				world.set_tile(x, y, IDs.T.AIR)
				world.set_sheath(Vector2i(x, y), world.SHEATH_NONE)
	# Навес слева: крыша, бока, открытая дверь снизу, луч сквозь проём.
	for c in [Vector2i(1, -1), Vector2i(2, -1), Vector2i(3, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(3, 0), Vector2i(3, 1)]:
		world.set_tile((origin + c).x, (origin + c).y, IDs.T.ROOM_PANEL)
	var door_l: Vector2i = origin + Vector2i(2, 2)
	world.set_tile(door_l.x, door_l.y, IDs.T.DOOR_OPEN)
	# Закрытая пристройка справа: вход с востока, дверь закрыта.
	var annex: Vector2i = origin + Vector2i(8, 0)
	for c in [Vector2i(1, -1), Vector2i(2, -1), Vector2i(3, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(3, 0), Vector2i(3, 1)]:
		world.set_tile((annex + c).x, (annex + c).y, IDs.T.ROOM_PANEL)
	var door_r: Vector2i = annex + Vector2i(4, 0)
	world.set_tile(door_r.x, door_r.y, IDs.T.DOOR)
	var inside: Vector2i = annex + Vector2i(2, 0)
	world.set_sheath(inside, world.SHEATH_BACK)
	world.set_sheath(annex + Vector2i(2, 1), world.SHEATH_BACK)
	var mb: GDScript = load("res://scripts/machines/machine_base.gd")
	var lamp: Vector2i = origin + Vector2i(2, 5)
	if not mb.place_machine("Burner", lamp):
		push_error("room_parts_shot: горелка не встала")
		quit(1)
		return
	var b = world.machines[lamp]
	b.dir = 3
	b.add_fuel(IDs.I.COAL, 2)
	world.beams.note_machines()
	world.beams.rebuild()
	world._apply_beam_lights()
	world.reveal_around(origin, 18)
	var player: Node2D = current_scene.get("player")
	if player != null:
		player.global_position = world.cell_to_world(origin + Vector2i(5, 3))
		var cam: Camera2D = player.get("camera")
		if cam != null:
			cam.position_smoothing_enabled = false
			cam.zoom = Vector2(5.0, 5.0)
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
	var through: int = world.beams.color_at(origin + Vector2i(2, 1))
	var stopped: int = world.beams.color_at(inside)
	print("room_parts_shot: %s (%d), луч в навесе %d, внутри закрытой %d, обшивка %d" % [
			path, err, through, stopped, world.sheath_at(inside)])
	quit(0 if err == OK and through != 0 and stopped == 0 and world.sheath_at(inside) == world.SHEATH_BACK else 1)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
