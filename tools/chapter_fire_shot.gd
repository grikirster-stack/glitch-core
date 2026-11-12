extends SceneTree
## Кадр главы «Огонь» (#215): docs/img/shots/chapter_fire_echo.png.
##
## Эхо само дошло до красного луча и отступает. Headless не рисует.
## Окно за экраном, без звука; скрипт сам выходит.
##
##   timeout 120 /tmp/godot47/Godot --path . --audio-driver Dummy --disable-vsync \
##         --fixed-fps 60 --windowed --position -10000,-10000 --resolution 1280x720 \
##         --script res://tools/chapter_fire_shot.gd -- --seed=31337

const OUT: String = "res://docs/img/shots/chapter_fire_echo.png"
const HARD_LIMIT: float = 40.0

var _elapsed: float = 0.0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("chapter_fire_shot: headless не рендерит — нужен прогон с окном за экраном")
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
		push_error("chapter_fire_shot: превышен лимит %.0f с" % HARD_LIMIT)
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
	var m: Node = campaign.start(current_scene, "fire")
	if m == null:
		push_error("chapter_fire_shot: глава не стартовала")
		quit(1)
		return
	var p: Node2D = current_scene.get("player")
	m.call("give_kit", p)
	var ids: GDScript = load("res://scripts/core/ids.gd")
	var base: GDScript = load("res://scripts/campaign/campaign_base.gd")
	# Ночь сразу: эхо выходит, не ждём 40 с сумерек. begin() ставит день и
	# hold_time 0.40 — ночь надо поставить после старта, иначе солнце откатывается.
	game.set("state", 1)
	game.set("time_of_day", 0.67)
	m.set("hold_time", 0.72)
	var mark: Vector2i = m.call("mark")
	# Горелку на метку ставит игрок. В кадре — та же клетка, носик вверх, уголь в топке.
	var burner = base.put("Burner", mark, {"dir": 3, "fuel": 3})
	if burner == null:
		push_error("chapter_fire_shot: горелка на метке не встала")
		quit(1)
		return
	var guard: int = 0
	while int(burner.dir) != 3 and guard < 8:
		burner.turn()
		guard += 1
	if int(burner.fuel_units()) <= 0 and not burner.burning():
		burner.add_fuel(ids.I.COAL, 3)
	await _frames(6)
	var beams = world.get("beams")
	if beams != null:
		beams.note_machines()
		beams.rebuild()
		world._apply_beam_lights()
	# Герой в стороне: не зовёт эхо и не закрывает луч.
	p.set_physics_process(false)
	p.set_process(false)
	p.global_position = world.cell_to_world(mark + Vector2i(3, 2))
	p.set("vel", Vector2.ZERO)
	var cam: Camera2D = p.get("camera")
	cam.zoom = Vector2(2.2, 2.2)
	# Камера на луч, не на героя: эхо и горелка в центре кадра.
	cam.position = world.cell_to_world(mark + Vector2i(-3, -1)) - p.global_position
	cam.reset_smoothing()
	var hud: Node = root.get_node("UI").get("hud")
	hud.set("notes", [])
	hud.set("tutorial_text", "")
	hud.set("hint_text", "")
	game.set("state", 1)
	game.set("time_of_day", 0.67)
	# Этап «Сумерки» до тика главы: иначе evaluate вернёт «Поставь горелку».
	m.set("stage", 2)
	m.call("evaluate")
	# Глава в кадре сама эхо не выпускает (on_tick не тикает до PLAYING-кадра
	# после begin). Точка и ход — те же, что у главы: _echo_spot и approach.
	var threat: Node = root.get_node("Threat")
	var spot: Vector2i = m.call("_echo_spot")
	var made: Array = threat.spawn_phantom("echo", world.cell_to_world(spot), {"harmless": true})
	if made.is_empty():
		push_error("chapter_fire_shot: эхо не вышло, клетка %s" % str(spot))
		quit(1)
		return
	var echo = made[0]
	m.set("_echo", echo)
	var seen: bool = false
	for i in 240:
		await process_frame
		if not is_instance_valid(echo) or not echo.alive:
			break
		var at: Vector2 = m.call("_approach_at")
		if at != Vector2.ZERO and int(echo.state) != 3:
			echo.approach(2.0, at)
		var here: Vector2i = world.world_to_cell(echo.global_position)
		var near: float = 999.0
		if world.beams != null:
			for c in world.beams.cells.keys():
				if int(world.beams.cells[c]) & 1 == 0:
					continue
				if c.x != mark.x and not (c.y == mark.y and c.x < mark.x + 6 and c.x > world.beacon_cell.x + 1):
					continue
				near = minf(near, Vector2(here - c).length())
		# Свет луча (радиус 20 px) достаёт соседнюю клетку. FLEE — эхо уже отступает.
		if near <= 2.0 and int(echo.state) == 3:
			seen = true
			# Камера на эхо и луч, не на пустой пол.
			cam.position = echo.global_position - p.global_position + Vector2(0.0, -24.0)
			break
	if not seen:
		push_error("chapter_fire_shot: эхо не дошло до луча")
		quit(1)
		return
	await _frames(2)
	cam.reset_smoothing()
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null or img.is_empty():
		push_error("chapter_fire_shot: пустой кадр")
		quit(1)
		return
	var err: int = img.save_png(ProjectSettings.globalize_path(OUT))
	print("снято: %s (%dx%d), код %d" % [OUT, img.get_width(), img.get_height(), err])
	quit(0 if err == OK else 1)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
