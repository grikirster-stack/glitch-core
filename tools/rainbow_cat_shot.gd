extends SceneTree
## Кадр радужного кота (#176): docs/img/shots/rainbow_cat.png.
## Кот виден, фантом рядом или уже снесён так, что понятно. Без простыни текста.
##
## Headless не рисует. Окно за экраном, без звука, скрипт сам выходит:
##   timeout 120 /tmp/godot47/Godot --path . --audio-driver Dummy --disable-vsync \
##     --windowed --position -10000,-10000 --resolution 1280x720 \
##     --script res://tools/rainbow_cat_shot.gd -- --seed=31337

const OUT: String = "res://docs/img/shots/rainbow_cat.png"
const HARD_LIMIT: float = 25.0

var _elapsed: float = 0.0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("rainbow_cat_shot: headless не рендерит — нужен прогон с окном за экраном")
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
		push_error("rainbow_cat_shot: превышен лимит %.0f с" % HARD_LIMIT)
		quit(2)
		return true
	return false


func _run() -> void:
	var world: Node = root.get_node("World")
	var game: Node = root.get_node("Game")
	# День: ночной тинт гасит серого кота, на кадре его не разобрать.
	game.set("time_of_day", 0.62)
	game.set("game_time", 40.0)
	game.set("scenario_mode", true)
	game.set("in_mission", true)
	await _frames(8)
	var home: Vector2i = world.beacon_cell + Vector2i(4, -3)
	for x in range(home.x - 6, home.x + 18):
		for y in range(home.y - 5, home.y + 6):
			if world.in_bounds(x, y):
				world.set_tile(x, y, 0)
	var ids: GDScript = load("res://scripts/core/ids.gd")
	for x in range(home.x - 6, home.x + 18):
		if world.in_bounds(x, home.y + 3):
			world.set_tile(x, home.y + 3, ids.T.STONE)
	var doomed: Array = []
	for c in world.machines.keys():
		if c.x >= home.x - 4 and c.x <= home.x + 14 and c.y >= home.y - 3 and c.y <= home.y + 3:
			doomed.append(c)
	for c in doomed:
		var old = world.machines[c]
		if old.has_method("dismantle"):
			old.dismantle()
	var mb: GDScript = load("res://scripts/machines/machine_base.gd")
	mb.place_machine("RainbowCore", home)
	var script: GDScript = load("res://scripts/entities/rainbow_cat.gd")
	var cat_pos: Vector2 = world.cell_to_world(home + Vector2i(3, 0))
	var cat = script.create(cat_pos)
	current_scene.add_child(cat)
	cat.global_position = cat_pos
	cat.facing = 1
	cat.z_index = 8
	var fx = current_scene.get("world_fx")
	if fx != null:
		fx.rings.clear()
		for i in 8:
			fx.cat_trail(cat_pos + Vector2(-float(8 - i) * 10.0, sin(float(i) * 0.8) * 5.0))
	var ph_script: GDScript = load("res://scripts/entities/phantom.gd")
	var echo = ph_script.create("echo")
	echo.player = current_scene.get("player")
	current_scene.add_child(echo)
	echo.global_position = cat_pos + Vector2(28.0, 6.0)
	echo.hp = 12.0
	var player: Node2D = current_scene.get("player")
	if player != null:
		player.global_position = world.cell_to_world(home + Vector2i(0, 14))
		var cam: Camera2D = player.get("camera")
		if cam != null:
			cam.position_smoothing_enabled = false
			cam.zoom = Vector2(5.0, 5.0)
			cam.global_position = cat_pos + Vector2(8.0, 4.0)
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
		hud.set("card_text", "")
		hud.set("card_at", Vector2.INF)
		hud.set("_state_t", 1.0e6)
		hud.set("_hint_t", 1.0e6)
	await _frames(4)
	var img: Image = root.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err: int = img.save_png(path)
	print("rainbow_cat_shot: %s (%d)" % [path, err])
	quit(0 if err == OK else 1)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
