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
	# Полдень. 0.62 — уже сумерки, тинт красит кота в розовый.
	game.set("time_of_day", 0.30)
	game.set("game_time", 40.0)
	game.set("scenario_mode", true)
	game.set("in_mission", true)
	await _frames(8)
	game.set("time_of_day", 0.30)
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
	var script: GDScript = load("res://scripts/entities/rainbow_cat.gd")
	var cat_pos: Vector2 = world.cell_to_world(home + Vector2i(3, 0))
	var cat = script.create(cat_pos)
	current_scene.add_child(cat)
	cat.global_position = cat_pos
	cat.facing = 1
	cat.tail_phase = 0.08
	# Декор и туман (z 30) закрывали корпус. Кот — поверх мирового канваса.
	# Масштаб узла сдвигает хвост (он левее локального нуля) за край кадра.
	cat.z_as_relative = false
	cat.z_index = 40
	var decor: Node = world.get("decor")
	if decor != null and decor.has_method("clear"):
		decor.clear()
	var fx = current_scene.get("world_fx")
	if fx != null:
		fx.rings.clear()
		fx.cat_trail_clear()
		fx.visible = false
	var ph_script: GDScript = load("res://scripts/entities/phantom.gd")
	var echo = ph_script.create("echo")
	echo.player = current_scene.get("player")
	current_scene.add_child(echo)
	# У лап, справа. Хвост рисуется влево от корпуса.
	echo.global_position = cat_pos + Vector2(18.0, 4.0)
	echo.hp = 1.0
	echo.facing = -1
	echo.z_as_relative = false
	echo.z_index = 39
	var player: Node2D = current_scene.get("player")
	if player != null:
		player.global_position = world.cell_to_world(home + Vector2i(0, 16))
		var cam: Camera2D = player.get("camera")
		if cam != null:
			cam.position_smoothing_enabled = false
			cam.zoom = Vector2(10.0, 10.0)
			cam.global_position = cat_pos + Vector2(4.0, 0.0)
			cam.reset_smoothing()
	if world.has_method("reveal_around"):
		world.reveal_around(home + Vector2i(3, 0), 40)
	var fog: Node = null
	for n in current_scene.get_children():
		if n.get_class() == "FogLayer" or String(n.name) == "FogLayer":
			fog = n
	if fog != null:
		fog.visible = false
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
	game.set("time_of_day", 0.30)
	await _frames(2)
	game.set("time_of_day", 0.30)
	await _frames(2)
	var img: Image = root.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err: int = img.save_png(path)
	print("rainbow_cat_shot: %s (%d)" % [path, err])
	quit(0 if err == OK else 1)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
