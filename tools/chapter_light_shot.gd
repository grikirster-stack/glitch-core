extends SceneTree
## Кадр старта главы «Копай» (#177): docs/img/shots/chapter_light_1.png.
##
## Headless не рисует. Окно за экраном, без звука; скрипт сам выходит.
##
##   timeout 120 /tmp/godot47/Godot --path . --audio-driver Dummy --disable-vsync \
##         --fixed-fps 60 --windowed --position -10000,-10000 --resolution 1280x720 \
##         --script res://tools/chapter_light_shot.gd -- --seed=31337
##
## Кадр: карточка «Сейчас» (картинка угля, «Накопай 5 угля», счётчик), поле видно.
## Подсказка управления погашена (game_time 30).

const OUT: String = "res://docs/img/shots/chapter_light_1.png"
const HARD_LIMIT: float = 25.0
const ZOOM: float = 1.6

var scene: Node = null
var _elapsed: float = 0.0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("chapter_light_shot: headless не рендерит — нужен прогон с окном за экраном")
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
		push_error("chapter_light_shot: превышен лимит %.0f с — выходим" % HARD_LIMIT)
		quit(2)
	return false


func _run() -> void:
	var game: Node = root.get_node("Game")
	var world: Node = root.get_node("World")
	scene.set("seed_value", 31337)
	scene.set("scenario_mode", true)
	game.set("scenario_mode", true)
	game.set("game_time", 30.0)
	game.set("time_of_day", 0.30)
	root.size = Vector2i(1280, 720)
	var hud: Node = root.get_node("UI").get("hud")
	if hud == null:
		push_error("chapter_light_shot: HUD нет")
		quit(1)
		return
	hud.set("notes", [])
	await _frames(8)
	if int(world.world_seed) != 31337:
		world.generate(31337)
	var campaign: GDScript = load("res://scripts/campaign/campaign.gd")
	var mission: Node = campaign.start(scene, "dig")
	if mission == null:
		push_error("chapter_light_shot: глава «Копай» не стартовала")
		quit(1)
		return
	var p: Node2D = scene.get("player")
	mission.call("give_kit", p)
	# Кадр — старт главы: день, первая цель. Игру останавливаем, чтобы этап не ушёл.
	game.set_process(false)
	game.set("state", 1)             ## PLAYING
	game.set("game_time", 30.0)
	game.set("time_of_day", 0.30)
	mission.set("stage", 0)
	var ids: GDScript = load("res://scripts/core/ids.gd")
	var base: GDScript = load("res://scripts/campaign/campaign_base.gd")
	mission.set("goals", [{
		"text": "Накопай 5 угля", "have": 0, "need": 5,
		"icon": int(ids.I.COAL),
		"at": world.cell_to_world(base.coal_spot()),
	}])
	mission.set("hint", "Копать можно только то, до чего достаёт луч от тебя")
	# Правее лагеря: у терминала курсор рисует «поставьте ТЭЦ», а кадр главы — про уголь.
	var stand: Vector2 = world.cell_to_world(world.beacon_cell + Vector2i(16, 1))
	p.set_physics_process(false)
	p.set_process(false)
	p.global_position = stand
	p.set("vel", Vector2.ZERO)
	p.set("facing", -1)
	var cam: Camera2D = p.get("camera")
	cam.position_smoothing_enabled = false
	cam.global_position = stand
	cam.zoom = Vector2(ZOOM, ZOOM)
	var vz: Node = p.get("view_zoom")
	if vz != null:
		vz.set("current", ZOOM)
		vz.set("target", ZOOM)
	cam.reset_smoothing()
	hud.set("notes", [])
	hud.set("hint_text", "")
	hud.set("_hint_t", 10.0)
	# Кадр главы не учит ТЭЦ: курсор у терминала иначе рисует «поставьте ТЭЦ».
	var mouse: Vector2 = cam.get_canvas_transform() * (stand + Vector2(0.0, -80.0))
	root.warp_mouse(mouse)
	Input.warp_mouse(mouse)
	hud.call("_compute_tracker")
	await _frames(4)
	hud.set("notes", [])
	hud.set("hint_text", "")
	cam.reset_smoothing()
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null or img.is_empty():
		push_error("chapter_light_shot: пустой кадр")
		quit(1)
		return
	var err: int = img.save_png(ProjectSettings.globalize_path(OUT))
	print("снято: %s (%dx%d), код %d; карточка «%s» %d / %d" % [
		OUT, img.get_width(), img.get_height(), err,
		hud.get("card_text"), int(hud.get("card_have")), int(hud.get("card_need"))])
	quit(0 if err == OK and String(hud.get("card_text")) == "Накопай 5 угля" else 1)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
