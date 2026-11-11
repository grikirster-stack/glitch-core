extends SceneTree
## Кадр «Остаться на планете» (ADR-005 § 6.4, #174): docs/img/shots/endless.png.
##
## Headless не рисует. Окно за экраном, без звука, скрипт сам выходит:
##   timeout 120 godot --path . --audio-driver Dummy --disable-vsync --fixed-fps 60 \
##     --windowed --position -10000,-10000 --resolution 1280x720 \
##     --script res://tools/endless_shot.gd -- --seed=31337 --less-glitch
##
## Победа свободной игры: эпилог, итоги и кнопка «Остаться на планете». Мир под
## экраном — база на сиде, не простыня трекера.

const OUT: String = "res://docs/img/shots/endless.png"
const HARD_LIMIT: float = 40.0

var _elapsed: float = 0.0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("endless_shot: headless не рендерит — нужен прогон с окном за экраном")
		quit(1)
		return
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	root.position = Vector2i(-10000, -10000)
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var scene: Node = main_scene.instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred(scene)


func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > HARD_LIMIT:
		push_error("endless_shot: превышен лимит %.0f с — выходим" % HARD_LIMIT)
		quit(2)
	return false


func _run(scene: Node) -> void:
	var game: Node = root.get_node("Game")
	scene.set("scenario_mode", true)
	game.set("scenario_mode", true)
	root.size = Vector2i(1280, 720)
	for _i in 8:
		await process_frame
	var player: Node = scene.get("player")
	if player != null:
		player.set("invuln", 1.0e9)
	game.set("game_time", 40.0)
	game.set("time_of_day", 0.42)
	var ui: Node = root.get_node("UI")
	var hud: Node = ui.get("hud")
	# Подсказка E пересчитывается сама: глушим её до запуска ядра.
	if hud != null:
		hud.set("tutorial_step", 99)
		hud.set("tutorial_text", "")
		hud.set("notes", [])
		hud.set("hint_text", "")
		hud.set("_hint_t", 1.0e6)
	var core: Vector2i = world.beacon_cell + Vector2i(2, 0)
	world.set_tile(core.x, core.y, 0)
	MachineBase.place_machine("RainbowCore", core)
	for c in [1, 2, 4, 3, 6, 5, 7]:
		game.call("core_feed", c)
	game.call("try_finish", player)
	game.set("relay_timer", 0.02)
	var es: Node = scene.get("end_screen")
	var t0: int = Time.get_ticks_msec()
	while game.get("state") != game.State.WON and Time.get_ticks_msec() - t0 < 4000:
		await process_frame
	if es == null or not bool(es.get("visible")) or not bool(es.get("can_stay")):
		push_error("endless_shot: экран победы без кнопки «Остаться»")
		quit(1)
		return
	if hud != null:
		hud.set("notes", [])
		hud.set("hint_text", "")
		hud.set("tutorial_text", "")
		hud.set("_hint_t", 1.0e6)
		hud.queue_redraw()
	# Миг кнопки — на яркой фазе, не на провале синуса.
	es.set("t", 0.4)
	for _i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path(OUT)
	var err: int = img.save_png(path)
	if err != OK:
		push_error("endless_shot: не сохранён %s (код %d)" % [path, err])
		quit(1)
		return
	print("SCREENSHOT: ", path, " ", img.get_width(), "x", img.get_height())
	quit(0)
