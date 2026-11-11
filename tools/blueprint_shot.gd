extends SceneTree
## Кадр терминала с чертежом (#169) для PR: docs/img/shots/blueprint_terminal.png.
##
## Headless не рисует кадр. Окно — за пределами экрана, без звука; скрипт сам
## выходит (≤ 18 с):
##   timeout 120 /home/ros2/godot --path . --audio-driver Dummy --disable-vsync \
##         --fixed-fps 60 --windowed --position -10000,-10000 --resolution 1280x720 \
##         --script res://tools/blueprint_shot.gd -- --seed=31337
##
## Что в кадре: терминал базы (глава 1) прочитан под питанием ТЭЦ, уведомления
## «Чертёж» / глава журнала / подарок, подарок лежит на полу у терминала.
## Флаг --out=путь пишет снимок не в docs/img/shots, а в указанный файл.

const OUT: String = "res://docs/img/shots/blueprint_terminal.png"
const HARD_LIMIT: float = 18.0

var out_path: String = OUT
var scene: Node = null
var _elapsed: float = 0.0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("blueprint_shot: headless не рендерит — нужен прогон с окном за экраном")
		quit(1)
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_path = a.substr(6)
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	root.position = Vector2i(-10000, -10000)
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	scene = main_scene.instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > HARD_LIMIT:
		push_error("blueprint_shot: превышен лимит %.0f с — выходим" % HARD_LIMIT)
		quit(2)
	return false


func _run() -> void:
	var world: Node = root.get_node("World")
	var game: Node = root.get_node("Game")
	var ui: Node = root.get_node("UI")
	scene.set("scenario_mode", true)
	game.set("scenario_mode", true)
	game.set("game_time", 30.0)
	game.set("time_of_day", 0.40)
	root.size = Vector2i(1280, 720)
	await _frames(12)
	ui.get("hud").set("notes", [])

	var term: Vector2i = _terminal_of(world, 0)
	if term.x < 0:
		push_error("blueprint_shot: нет терминала базы (глава 1)")
		quit(1)
		return
	var mb: GDScript = load("res://scripts/machines/machine_base.gd")
	var gen_cell: Vector2i = term + Vector2i(2, 0)
	if not mb.place_machine("CoalGen", gen_cell):
		gen_cell = term + Vector2i(-2, 0)
		if not mb.place_machine("CoalGen", gen_cell):
			push_error("blueprint_shot: ТЭЦ не встала у терминала %s" % str(term))
			quit(1)
			return
	world.machines[gen_cell].add_fuel(6)
	await _frames(4)
	var spot: Vector2 = world.cell_to_world(term)
	if not game.is_powered(spot):
		push_error("blueprint_shot: терминал без питания")
		quit(1)
		return

	var p: Node2D = scene.get("player")
	p.set_physics_process(false)
	p.global_position = spot + Vector2(18.0, -8.0)
	p.set("facing", -1)
	var cam: Camera2D = p.get("camera")
	cam.zoom = Vector2(2.6, 2.6)
	cam.reset_smoothing()
	await _frames(4)
	cam.reset_smoothing()

	p.call("_read_terminal", term)
	# Подарок падает с импульсом: на кадре он уже на полу, не в полёте.
	for c in scene.get_children():
		if c.get_class() == "Node2D" and c.get("item_id") != null and c.get("vel") != null:
			c.set("vel", Vector2.ZERO)
			c.set("grounded", true)
			c.global_position = spot + Vector2(10.0, 6.0)
	ui.get("world_fx").set("show_power", true)
	p.queue_redraw()
	await _frames(8)

	var notes: Array = ui.get("hud").get("notes")
	var saw: bool = false
	for n in notes:
		if String(n.get("text", "")).begins_with("Чертёж:"):
			saw = true
	if not saw:
		push_error("blueprint_shot: в уведомлениях нет строки «Чертёж»")
		quit(1)
		return
	if game.blueprints.is_empty():
		push_error("blueprint_shot: чертёж не выдан")
		quit(1)
		return

	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null or img.is_empty():
		push_error("blueprint_shot: пустой кадр")
		quit(1)
		return
	var err: int = img.save_png(ProjectSettings.globalize_path(out_path))
	print("снято: %s (%dx%d), код %d, чертёж %s" % [
			out_path, img.get_width(), img.get_height(), err, str(game.blueprints)])
	quit(0 if err == OK else 1)


func _terminal_of(world: Node, chapter: int) -> Vector2i:
	var chapters: Dictionary = world.get("terminal_chapters")
	for t in world.get("terminals"):
		if int(chapters.get(t, -1)) == chapter:
			return t
	return Vector2i(-1, -1)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
