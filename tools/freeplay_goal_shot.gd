extends SceneTree
## Кадр карточки свободной цели (#212): docs/img/shots/freeplay_goal.png.
##
## Headless не рисует. Окно за экраном, без звука; скрипт сам выходит.
##
##   timeout 120 /tmp/godot47/Godot --path . --audio-driver Dummy --disable-vsync \
##         --fixed-fps 60 --windowed --position -10000,-10000 --resolution 1280x720 \
##         --script res://tools/freeplay_goal_shot.gd -- --seed=31337
##
## Одна короткая карточка «Прочитай терминал». Подсказки и хотбар на кадре погашены.

const OUT: String = "res://docs/img/shots/freeplay_goal.png"
const HARD_LIMIT: float = 20.0

var scene: Node = null
var _elapsed: float = 0.0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("freeplay_goal_shot: headless не рендерит — нужен прогон с окном за экраном")
		quit(1)
		return
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	root.position = Vector2i(-10000, -10000)
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
		push_error("freeplay_goal_shot: превышен лимит %.0f с — выходим" % HARD_LIMIT)
		quit(2)
	return false


func _run() -> void:
	var game: Node = root.get_node("Game")
	var world: Node = root.get_node("World")
	scene.set("seed_value", 31337)
	scene.set("scenario_mode", true)
	game.set("scenario_mode", true)
	game.set("game_time", 40.0)
	game.set("time_of_day", 0.35)
	root.size = Vector2i(1280, 720)
	var hud: Node = root.get_node("UI").get("hud")
	if hud == null:
		push_error("freeplay_goal_shot: HUD нет")
		quit(1)
		return
	hud.set("notes", [])
	await _frames(10)
	if int(world.world_seed) != 31337:
		world.generate(31337)
	game.set_process(false)
	game.set("state", 1)
	game.set("game_time", 40.0)
	game.set("time_of_day", 0.35)
	game.set("objective_stage", 1)
	game.set("tasks_done", 0)
	game.set("blueprints", PackedStringArray())
	var p: Node2D = scene.get("player")
	# Левее лагеря: карточка слева экрана, терминал остаётся в кадре.
	var stand: Vector2 = world.cell_to_world(world.beacon_cell + Vector2i(-8, 1))
	p.set_physics_process(false)
	p.set_process(false)
	p.global_position = stand
	p.set("vel", Vector2.ZERO)
	var cam: Camera2D = p.get("camera")
	cam.position_smoothing_enabled = false
	cam.global_position = stand + Vector2(40.0, -24.0)
	cam.zoom = Vector2(1.35, 1.35)
	var vz: Node = p.get("view_zoom")
	if vz != null:
		vz.set("current", 1.35)
		vz.set("target", 1.35)
	cam.reset_smoothing()
	hud.call("_compute_tracker")
	_quiet(hud)
	await _frames(4)
	hud.call("_compute_tracker")
	_quiet(hud)
	cam.reset_smoothing()
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null or img.is_empty():
		push_error("freeplay_goal_shot: пустой кадр")
		quit(1)
		return
	var err: int = img.save_png(ProjectSettings.globalize_path(OUT))
	print("снято: %s (%dx%d), код %d; карточка «%s» %d / %d" % [
		OUT, img.get_width(), img.get_height(), err,
		hud.get("card_text"), int(hud.get("card_have")), int(hud.get("card_need"))])
	quit(0 if err == OK and String(hud.get("card_text")) == "Прочитай терминал" else 1)


func _quiet(hud: Node) -> void:
	hud.set("tutorial_text", "")
	hud.set("hint_text", "")
	hud.set("_hint_t", 10.0)
	hud.set("notes", [])
	hud.set("mission_lines", [])
	hud.set("_state_t", 10.0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
