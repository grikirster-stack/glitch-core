extends SceneTree
## Кадр главы 3 «Зеркало» (#216): docs/img/shots/chapter_mirror.png.
##
## Карточка «Поставь зеркало на поворот», на повороте пусто, поле видно.
## Headless не рисует. Окно за экраном, без звука; скрипт пишет кадр и выходит.
##
##   timeout 120 /tmp/godot47/Godot --path . --audio-driver Dummy --disable-vsync \
##         --fixed-fps 60 --windowed --position -10000,-10000 --resolution 1280x720 \
##         --script res://tools/chapter_mirror_shot.gd -- --seed=31337

const OUT: String = "res://docs/img/shots/chapter_mirror.png"
const HARD_LIMIT: float = 25.0

var _elapsed: float = 0.0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("chapter_mirror_shot: headless не рендерит — нужен прогон с окном за экраном")
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
		push_error("chapter_mirror_shot: превышен лимит %.0f с" % HARD_LIMIT)
		quit(2)
	return false


func _run() -> void:
	var game: Node = root.get_node("Game")
	var world: Node = root.get_node("World")
	current_scene.set("scenario_mode", true)
	game.set("scenario_mode", true)
	game.set("game_time", 30.0)
	root.size = Vector2i(1280, 720)
	await _frames(10)
	current_scene.set("seed_value", 31337)
	var campaign: GDScript = load("res://scripts/campaign/campaign.gd")
	var m: Node = campaign.start(current_scene, "mirror")
	if m == null:
		push_error("chapter_mirror_shot: глава не стартовала")
		quit(1)
		return
	await _frames(8)
	var layout: GDScript = load("res://scripts/campaign/light_layout.gd")
	var corner: Vector2i = layout.at(layout.CORNER)
	if world.machines.has(corner):
		push_error("chapter_mirror_shot: на повороте уже стоит постройка")
		quit(1)
		return
	var beams = world.get("beams")
	if beams != null:
		beams.note_machines()
		beams.rebuild()
	var p: Node2D = current_scene.get("player")
	p.set_physics_process(false)
	p.set_process(false)
	# Герой под карточкой: круг тумана (16 клеток) должен накрыть её правый край.
	# Камера чуть правее — поворот и пустая клетка в кадре, не под текстом.
	var beacon: Vector2i = world.beacon_cell
	p.global_position = world.cell_to_world(beacon + Vector2i(-1, -2))
	p.set("vel", Vector2.ZERO)
	var cam: Camera2D = p.get("camera")
	cam.zoom = Vector2(1.45, 1.45)
	cam.position = world.cell_to_world(corner + Vector2i(-3, -3)) - p.global_position
	cam.reset_smoothing()
	var hud: Node = root.get_node("UI").get("hud")
	hud.set("notes", [])
	hud.set("tutorial_text", "")
	hud.set("hint_text", "")
	game.set("state", 1)
	game.set("game_time", 30.0)
	m.call("evaluate")
	hud.call("_compute_tracker")
	await _frames(4)
	cam.reset_smoothing()
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null or img.is_empty() or img.get_width() != 1280 or img.get_height() != 720:
		push_error("chapter_mirror_shot: пустой или не тот размер")
		quit(1)
		return
	var err: int = img.save_png(ProjectSettings.globalize_path(OUT))
	print("снято: %s (%dx%d), код %d; карточка «%s»" % [
		OUT, img.get_width(), img.get_height(), err, hud.get("card_text")])
	quit(0 if err == OK and String(hud.get("card_text")) == "Поставь зеркало на поворот" else 1)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
