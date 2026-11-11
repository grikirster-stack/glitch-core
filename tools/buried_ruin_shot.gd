extends SceneTree
## Кадр погребённой руины для PR: docs/img/shots/buried_ruin.png.
##
## Разрез: порода над станцией, терминал внутри комнаты, не на траве.
## Headless не рендерит — окно ЗА ПРЕДЕЛАМИ ЭКРАНА, без звука; скрипт сам выходит.
##
##   timeout 120 /tmp/godot47/Godot --path . --audio-driver Dummy --disable-vsync \
##         --fixed-fps 60 --windowed --position -10000,-10000 --resolution 1280x720 \
##         --script res://tools/buried_ruin_shot.gd -- --seed=31337

const OUT: String = "res://docs/img/shots/buried_ruin.png"
const HARD_LIMIT: float = 25.0
const ZOOM: float = 2.0

var scene: Node = null
var _elapsed: float = 0.0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("buried_ruin_shot: headless не рендерит — нужен прогон с окном за экраном")
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
		push_error("buried_ruin_shot: превышен лимит %.0f с — выходим" % HARD_LIMIT)
		quit(2)
	return false


func _run() -> void:
	var game: Node = root.get_node("Game")
	var world: Node = root.get_node("World")
	var lore: Node = root.get_node("Lore")
	scene.set("scenario_mode", true)
	game.set("scenario_mode", true)
	game.set("game_time", 30.0)
	game.set("time_of_day", 0.42)
	root.size = Vector2i(1280, 720)
	var ui: Node = root.get_node("UI")
	var hud: Node = ui.get("hud")
	if hud != null:
		hud.set("notes", [])
		hud.visible = false
	await _frames(16)

	var caches: Array = world.get("ruin_caches")
	var best: Dictionary = {}
	var best_d: int = 999
	# Средняя глубина: в кадре и порода над станцией, и терминал, не только крыша.
	for c in caches:
		var cell: Vector2i = c["cell"]
		var top: int = int(world.surface[cell.x])
		var depth: int = cell.y - top
		if depth >= 18 and depth < best_d:
			best_d = depth
			best = c
	if best.is_empty():
		for c in caches:
			best = c
			break
	if best.is_empty():
		push_error("buried_ruin_shot: руины не найдены")
		quit(1)
		return
	var cell: Vector2i = best["cell"]
	var floor_y: int = int(best.get("floor", cell.y + 1))
	var cx: int = int(best.get("cx", cell.x))
	var half: int = int(best.get("half", 4))
	var top: int = int(world.surface[cx])
	print("руина %s пол=%d поверхность=%d глубина=%d" % [str(cell), floor_y, top, cell.y - top])

	# Туман над комнатой открываем, иначе кадр чёрный. Поверхность в кадре остаётся.
	var c0: Vector2i = Vector2i(cx, floor_y - 2)
	world.reveal_around(c0, 18)
	var p: Node2D = scene.get("player")
	p.set_physics_process(false)
	p.visible = false
	var cam: Camera2D = p.get("camera")
	# Центр — терминал: над ним порода, комната целиком в кадре.
	p.global_position = world.cell_to_world(Vector2i(cx, floor_y - 6))
	cam.zoom = Vector2(ZOOM, ZOOM)
	var vz: Node = p.get("view_zoom")
	if vz != null:
		vz.set("current", ZOOM)
		vz.set("target", ZOOM)
	cam.reset_smoothing()
	await _frames(8)
	cam.reset_smoothing()
	await _frames(6)
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null or img.is_empty():
		push_error("buried_ruin_shot: пустой кадр")
		quit(1)
		return
	var err: int = img.save_png(ProjectSettings.globalize_path(OUT))
	print("снято: %s (%dx%d), код %d; терминал главы %d, полуширина %d" % [
		OUT, img.get_width(), img.get_height(), err,
		int(lore.BASE_TERMINALS) + int(best.get("index", 0)), half])
	quit(0 if err == OK else 1)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
