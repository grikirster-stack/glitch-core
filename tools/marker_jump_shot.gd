extends SceneTree
## Кадр #211: герой в прыжке, жёлтая рамка на предмете, не в воздухе.
##
##   timeout 120 /tmp/godot47/Godot --path . --audio-driver Dummy --disable-vsync \
##         --fixed-fps 60 --windowed --position -10000,-10000 --resolution 1280x720 \
##         --script res://tools/marker_jump_shot.gd -- --seed=31337

const OUT: String = "res://docs/img/shots/marker_jump.png"
const HARD_LIMIT: float = 20.0

var scene: Node = null
var _elapsed: float = 0.0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("marker_jump_shot: headless не рендерит")
		quit(1)
		return
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	root.position = Vector2i(-10000, -10000)
	_boot.call_deferred()


func _boot() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > HARD_LIMIT:
		push_error("marker_jump_shot: превышен лимит")
		quit(2)
		return true
	return false


func _run() -> void:
	var game: Node = root.get_node("Game")
	var world: Node = root.get_node("World")
	scene.set("scenario_mode", true)
	game.set("scenario_mode", true)
	game.set("game_time", 30.0)
	game.set("time_of_day", 0.40)
	root.size = Vector2i(1280, 720)
	await _frames(12)

	var p: Node2D = scene.get("player")
	var ids: GDScript = load("res://scripts/core/ids.gd")
	var tile: int = int(world.TILE)
	var bx: int = int(world.beacon_cell.x)
	var base: int = int(world.beacon_cell.y) + 1
	var cell: Vector2i = Vector2i(bx + 10, base - 1)
	for dx in range(-3, 6):
		for dy in range(-6, 2):
			var c: Vector2i = cell + Vector2i(dx, dy)
			world.set_tile(c.x, c.y, ids.T.AIR if dy < 1 else ids.T.STEEL)
	var mb: GDScript = load("res://scripts/machines/machine_base.gd")
	if not mb.place_machine("Chest", cell):
		push_error("marker_jump_shot: сундук не встал")
		quit(1)
		return
	world.machines[cell].call("receive_item", ids.I.STONE, 1)
	var aim: Vector2 = world.cell_to_world(cell)
	# Почти над сундуком: прыжок остаётся в радиусе E (40 px), рамка не гаснет.
	p.global_position = Vector2(aim.x, float(base * tile) - 11.0)
	p.set("vel", Vector2.ZERO)
	p.set("facing", 1)
	p.set("test_input", {"keys": {}, "mouse": aim, "mouse_buttons": {}})
	var cam: Camera2D = p.get("camera")
	cam.zoom = Vector2(3.0, 3.0)
	var vz: Node = p.get("view_zoom")
	if vz != null:
		vz.set("current", 3.0)
		vz.set("target", 3.0)
	cam.reset_smoothing()
	await _frames(8)
	cam.reset_smoothing()
	var hud: Node = root.get_node("UI").get("hud")
	hud.set("notes", [])
	await _frames(20)
	if not hud.call("mark_on_world", aim):
		push_error("marker_jump_shot: рамки нет до прыжка, hint='%s'" % hud.hint_text)
		quit(1)
		return
	# Прыжок. Кадр — в воздухе, рамка ещё на сундуке. HUD прячем: стрелка карточки
	# не должна спорить с рамкой предмета. Мировой слой рамки от HUD не зависит.
	p.set("test_input", {"keys": {KEY_SPACE: true}, "mouse": aim, "mouse_buttons": {}})
	var shot: bool = false
	var floor_y: float = float(base * tile) - 11.0
	for i in 40:
		await process_frame
		if p.get("on_ground") or p.global_position.y > floor_y - 22.0:
			continue
		if not hud.call("mark_on_world", aim):
			continue
		hud.visible = false
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		var err: int = img.save_png(ProjectSettings.globalize_path(OUT))
		print("снято: %s код %d; y=%.1f floor=%.1f vel=%s on_chest=%s" % [
			OUT, err, p.global_position.y, floor_y, p.get("vel"), hud.call("mark_on_world", aim)])
		shot = err == OK
		break
	if not shot:
		push_error("marker_jump_shot: кадр прыжка не снят")
		quit(1)
		return
	quit(0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
