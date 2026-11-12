extends SceneTree
## Кадр главы 4 «Цвета» (#217): docs/img/shots/chapter_colors.png.
##
## Ночь, эхо у героя, прожектор погашен, карточка не обрезана, поле видно.
## Headless не рисует. Окно за экраном, без звука; скрипт пишет кадр и выходит.
##
##   timeout 120 /tmp/godot47/Godot --path . --audio-driver Dummy --disable-vsync \
##         --fixed-fps 60 --windowed --position -10000,-10000 --resolution 1280x720 \
##         --script res://tools/chapter_colors_shot.gd -- --seed=31337

const OUT: String = "res://docs/img/shots/chapter_colors.png"
const HARD_LIMIT: float = 30.0

var _elapsed: float = 0.0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("chapter_colors_shot: headless не рендерит — нужен прогон с окном за экраном")
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
		push_error("chapter_colors_shot: превышен лимит %.0f с" % HARD_LIMIT)
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
	var m: Node = campaign.start(current_scene, "colors")
	if m == null:
		push_error("chapter_colors_shot: глава не стартовала")
		quit(1)
		return
	# Ночь и погашенный прожектор. Жёлтый на маяк кладёт сам кадр: этап «Сведи
	# лучи» бот не проходит, а без жёлтого лампы нет и гасить нечего.
	var layout: GDScript = load("res://scripts/campaign/light_layout.gd")
	var beams = world.get("beams")
	var pharos = world.machines.get(layout.at(layout.PHAROS))
	if pharos == null:
		push_error("chapter_colors_shot: маяка нет")
		quit(1)
		return
	if beams != null:
		beams.note_machines()
		beams.rebuild()
	pharos.beam_receive(3)
	pharos.lamp_off = true
	pharos.relight()
	m.set("stage", 3)
	m.set("hold_time", -1.0)
	m.call("_begin_night")
	game.set("state", 1)
	game.set("time_of_day", 0.80)
	game.set("game_time", 30.0)
	if int(pharos.get("color")) != 3 or not bool(pharos.get("lamp_off")) or bool(pharos.get("_lit")):
		push_error("chapter_colors_shot: прожектор не погашен, цвет %s лампа %s свет %s" % [
			str(pharos.get("color")), str(pharos.get("lamp_off")), str(pharos.get("_lit"))])
		quit(1)
		return
	var p: Node2D = current_scene.get("player")
	p.set_physics_process(false)
	p.set_process(false)
	# Герой под карточкой: круг тумана накрывает её правый край. Эхо рядом.
	var stand: Vector2i = world.beacon_cell + Vector2i(1, -1)
	p.global_position = world.cell_to_world(stand)
	p.set("vel", Vector2.ZERO)
	var threat: Node = root.get_node("Threat")
	var spot: Vector2i = m.call("_echo_spot")
	var made: Array = threat.spawn_phantom("echo", world.cell_to_world(spot), {})
	if made.is_empty():
		push_error("chapter_colors_shot: эхо не вышло")
		quit(1)
		return
	var echo = made[0]
	# На полу у героя, в круге тумана: эхо читается рядом с ним.
	echo.global_position = p.global_position + Vector2(28.0, 6.0)
	echo.set("state", 2)
	echo.set("approach_t", 8.0)
	echo.set("approach_at", p.global_position)
	var cam: Camera2D = p.get("camera")
	cam.zoom = Vector2(1.7, 1.7)
	cam.position = p.global_position + Vector2(48.0, -8.0) - p.global_position
	cam.reset_smoothing()
	var hud: Node = root.get_node("UI").get("hud")
	hud.set("notes", [])
	hud.set("tutorial_text", "")
	hud.set("hint_text", "")
	# Подсказка этапа 0 остаётся после прыжка на ночь и не относится к кадру.
	m.set("hint", "Эхо бьёт, пока прожектор погашен")
	m.call("evaluate")
	hud.call("_compute_tracker")
	hud.call("_compute_tutorial")
	await _frames(6)
	cam.reset_smoothing()
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null or img.is_empty() or img.get_width() != 1280 or img.get_height() != 720:
		push_error("chapter_colors_shot: пустой или не тот размер")
		quit(1)
		return
	var err: int = img.save_png(ProjectSettings.globalize_path(OUT))
	print("снято: %s (%dx%d), код %d; карточка «%s», лампа %s" % [
		OUT, img.get_width(), img.get_height(), err, hud.get("card_text"),
		str(pharos.get("lamp_off"))])
	quit(0 if err == OK and String(hud.get("card_text")) == "Переживи короткую ночь" else 1)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
