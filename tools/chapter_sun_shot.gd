extends SceneTree
## Кадр главы 5 «Солнце» (#218): docs/img/shots/chapter_sun.png.
##
## Копатель на пути к маяку, не в углу. Поле и карточка видны.
## Headless не рисует. Окно за экраном, без звука; скрипт пишет кадр и выходит.
##
##   timeout 120 /tmp/godot47/Godot --path . --audio-driver Dummy --disable-vsync \
##         --fixed-fps 60 --windowed --position -10000,-10000 --resolution 1280x720 \
##         --script res://tools/chapter_sun_shot.gd -- --seed=31337

const OUT: String = "res://docs/img/shots/chapter_sun.png"
const HARD_LIMIT: float = 30.0

var _elapsed: float = 0.0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("chapter_sun_shot: headless не рендерит — нужен прогон с окном за экраном")
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
		push_error("chapter_sun_shot: превышен лимит %.0f с" % HARD_LIMIT)
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
	var m: Node = campaign.start(current_scene, "sun")
	if m == null:
		push_error("chapter_sun_shot: глава не стартовала")
		quit(1)
		return
	# Тот же выход, что у ночи главы: ход вырезан, копатель идёт к маяку.
	# Ждём несколько кадров хода, потом ставим на путь — не в угол мира.
	m.set("stage", 4)
	m.call("_begin_night")
	game.set("state", 1)
	game.set("time_of_day", 0.80)
	game.set("game_time", 30.0)
	var late: GDScript = load("res://scripts/campaign/light_late.gd")
	var tower: Vector2i = late.at(late.PHAROS)
	var burr = null
	for i in 90:
		await process_frame
		burr = m.get("burrower")
		if burr != null and is_instance_valid(burr):
			var here: Vector2i = world.world_to_cell(burr.global_position)
			if absi(here.x - tower.x) <= 6 and absi(here.x - tower.x) >= 2 and here.y == tower.y:
				break
	if burr == null or not is_instance_valid(burr):
		push_error("chapter_sun_shot: копатель не вышел")
		quit(1)
		return
	# На пути, в двух клетках от башни: кадр не ждёт, пока он доползёт, и не ставит в угол.
	burr.global_position = world.cell_to_world(tower + Vector2i(-2, 0))
	var here: Vector2i = world.world_to_cell(burr.global_position)
	if absi(here.x - tower.x) > 4 or here.y != tower.y:
		push_error("chapter_sun_shot: копатель не на пути %s" % str(here))
		quit(1)
		return
	burr.set_physics_process(false)
	burr.set_process(false)
	var p: Node2D = current_scene.get("player")
	p.set_physics_process(false)
	p.set_process(false)
	# Герой под карточкой: круг тумана накрывает текст, копатель остаётся на пути.
	p.global_position = world.cell_to_world(tower + Vector2i(1, -1))
	p.set("vel", Vector2.ZERO)
	var cam: Camera2D = p.get("camera")
	cam.zoom = Vector2(1.85, 1.85)
	cam.position = world.cell_to_world(tower + Vector2i(-1, 0)) - p.global_position
	cam.reset_smoothing()
	var hud: Node = root.get_node("UI").get("hud")
	hud.set("notes", [])
	hud.set("tutorial_text", "")
	hud.set("hint_text", "")
	m.call("evaluate")
	hud.call("_compute_tracker")
	await _frames(4)
	cam.reset_smoothing()
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null or img.is_empty() or img.get_width() != 1280 or img.get_height() != 720:
		push_error("chapter_sun_shot: пустой или не тот размер")
		quit(1)
		return
	var err: int = img.save_png(ProjectSettings.globalize_path(OUT))
	print("снято: %s (%dx%d), код %d; карточка «%s», копатель %s, маяк %s" % [
		OUT, img.get_width(), img.get_height(), err, hud.get("card_text"),
		str(here), str(tower)])
	quit(0 if err == OK and String(hud.get("card_text")) == "Переживи ночь" else 1)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
