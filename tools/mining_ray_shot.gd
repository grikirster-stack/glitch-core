extends SceneTree
## Кадр копки по лучу (#162) для PR: docs/img/shots/mining_ray.png.
##
## gallery_dump этот кадр не умеет: рамка цели и красный крест живут в HUD и
## гаснут за 0,3 с, а прицел рисуется по экранной мыши, не по test_input.
## Headless не рендерит — окно ЗА ПРЕДЕЛАМИ ЭКРАНА, без звука; скрипт сам выходит.
##
##   timeout 120 godot --path . --audio-driver Dummy --disable-vsync --fixed-fps 60 \
##         --windowed --position -10000,-10000 --resolution 1280x720 \
##         --script res://tools/mining_ray_shot.gd -- --seed=31337
##
## Кадр: герой, стена из двух клеток, курсор на жиле за стеной. Копается первая
## твёрдая клетка (рамка), дальняя помечена красным крестом.

const OUT: String = "res://docs/img/shots/mining_ray.png"
const HARD_LIMIT: float = 18.0
const ZOOM: float = 3.0

var scene: Node = null
var _elapsed: float = 0.0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("mining_ray_shot: headless не рендерит — нужен прогон с окном за экраном")
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
		push_error("mining_ray_shot: превышен лимит %.0f с — выходим" % HARD_LIMIT)
		quit(2)
	return false


func _run() -> void:
	var game: Node = root.get_node("Game")
	var world: Node = root.get_node("World")
	scene.set("scenario_mode", true)
	game.set("scenario_mode", true)
	game.set("game_time", 30.0)              ## подсказка управления уже погасла
	game.set("time_of_day", 0.40)
	root.size = Vector2i(1280, 720)
	var hud: Node = root.get_node("UI").get("hud")
	if hud != null:
		hud.set("notes", [])
	await _frames(20)

	var p: Node2D = scene.get("player")
	var ids: GDScript = load("res://scripts/core/ids.gd")
	var tile: int = int(world.TILE)
	var bx: int = int(world.beacon_cell.x)
	var base: int = int(world.beacon_cell.y) + 1
	# Правее площадки базы (±12): там деревья и руины, их надо убрать, иначе крест
	# садится на декор, а не на жилу.
	var hx: int = bx + 16
	var hy: int = base - 1
	var machines: Dictionary = world.machines
	var decor: Node = world.get("decor")
	for dx in range(-1, 12):
		for dy in range(-4, 3):
			var c: Vector2i = Vector2i(hx + dx, hy + dy)
			if machines.has(c):
				var m: Node = machines[c]
				machines.erase(c)
				if is_instance_valid(m):
					m.queue_free()
			if dy < 0:
				world.set_tile(c.x, c.y, ids.T.AIR)      ## воздух над полом
			elif dy == 0:
				world.set_tile(c.x, c.y, ids.T.STEEL)    ## пол без флоры
			if decor != null:
				decor.call("on_cell", c.x, c.y)
	# Луч копки идёт от центра клетки героя. Герой стоит клеткой выше пола,
	# стена — в его ряду: пол луч не задевает, копается ближняя клетка стены.
	world.set_tile(hx + 2, hy - 1, ids.T.STONE)      ## ближняя клетка стены
	world.set_tile(hx + 3, hy - 1, ids.T.STONE)      ## вторая клетка стены
	world.set_tile(hx + 5, hy - 1, ids.T.IRON_ORE)   ## жила за стеной, под курсором
	if decor != null:
		for dx in range(1, 7):
			decor.call("on_cell", hx + dx, hy - 1)
	p.set_physics_process(false)
	p.global_position = Vector2(float(hx * tile) + 8.0, float((hy - 1) * tile) + 14.0)
	p.set("vel", Vector2.ZERO)
	p.set("facing", 1)
	var cam: Camera2D = p.get("camera")
	cam.zoom = Vector2(ZOOM, ZOOM)
	var vz: Node = p.get("view_zoom")
	if vz != null:
		vz.set("current", ZOOM)
		vz.set("target", ZOOM)
	cam.reset_smoothing()
	await _frames(8)
	cam.reset_smoothing()
	await _frames(4)

	# Курсор — на жиле за стеной. Прицел HUD читает экранную мышь, не test_input.
	var vein: Vector2 = world.cell_to_world(Vector2i(hx + 5, hy - 1))
	var screen: Vector2 = cam.get_canvas_transform() * vein
	root.warp_mouse(screen)
	Input.warp_mouse(screen)
	p.set("test_input", {
		"keys": {},
		"mouse": vein,
		"mouse_buttons": {MOUSE_BUTTON_LEFT: true},
	})
	# Кадр физики: dig_cell, копка ближней клетки, красный крест на жиле.
	p.set_physics_process(true)
	await _frames(1)
	p.set_physics_process(false)
	var denied: float = float(p.get("dig_denied_t"))
	if Vector2i(p.get("dig_cell")) != Vector2i(hx + 2, hy - 1) \
			or Vector2i(p.get("dig_denied_cell")) != Vector2i(hx + 5, hy - 1) or denied <= 0.0:
		push_error("mining_ray_shot: цель не встала (dig=%s denied=%s t=%.3f)" % [
			str(p.get("dig_cell")), str(p.get("dig_denied_cell")), denied])
		quit(1)
		return
	# Крест гаснет за 0,3 с: кадр сразу, пока рамка и крест ещё на слое прицела.
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null or img.is_empty():
		push_error("mining_ray_shot: пустой кадр")
		quit(1)
		return
	var err: int = img.save_png(ProjectSettings.globalize_path(OUT))
	print("снято: %s (%dx%d), код %d; dig=%s denied=%s t=%.3f" % [
		OUT, img.get_width(), img.get_height(), err,
		str(p.get("dig_cell")), str(p.get("dig_denied_cell")), float(p.get("dig_denied_t"))])
	quit(0 if err == OK else 1)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
