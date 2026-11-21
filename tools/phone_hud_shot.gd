extends SceneTree
## Снимок HUD телефона до/после правки раскладки. Окно за экраном, без звука.
##
##   godot --path . --audio-driver Dummy --windowed --position -10000,-10000 --touch \
##         --script res://tools/phone_hud_shot.gd -- --size=2400x1080 \
##         --ui-scale=2.5 --state=terminal --mission=dig --out=/tmp/phone.png
##
## Кадр снимается с настоящей растяжкой проекта (canvas_items/expand): окно берётся
## того же соотношения сторон, что и телефон, и такое, чтобы холст получился
## 1600x720 (HUD 640x288 при ui_scale=2.5) — ровно как на телефоне 2400x1080.
## Затем PNG увеличивается до --size для отчёта. Если задать --capture=WxH,
## окно будет этого размера (холст всё равно считается растяжкой).
##
## --state=intro: свободная игра, game_time=1, вводная строка в нижней плашке.
## --state=terminal: длинная подсказка терминала. Старый HUD без _intro_done
## тоже снимается (проверки на наличие полей — ниже).

const HARD_LIMIT: float = 20.0
const SCREEN_MAX: Vector2i = Vector2i(1920, 1080)

var scene: Node = null
var _elapsed: float = 0.0
var target_size: Vector2i = Vector2i(2400, 1080)
var capture_size: Vector2i = Vector2i.ZERO
var ui_scale: float = 2.5
var shot_state: String = "terminal"
var forced_time: float = -1.0
var keep_notes: bool = false
var out_path: String = ""


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("phone_hud_shot: headless не рендерит — нужен прогон с окном за экраном")
		quit(1)
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--size="):
			var parts: PackedStringArray = a.substr(7).split("x")
			if parts.size() == 2:
				target_size = Vector2i(int(parts[0]), int(parts[1]))
		elif a.begins_with("--capture="):
			var parts: PackedStringArray = a.substr(10).split("x")
			if parts.size() == 2:
				capture_size = Vector2i(int(parts[0]), int(parts[1]))
		elif a.begins_with("--ui-scale="):
			ui_scale = float(a.substr(11))
		elif a.begins_with("--state="):
			shot_state = a.substr(8)
		elif a.begins_with("--time="):
			forced_time = float(a.substr(7))
		elif a == "--keep-notes":
			keep_notes = true
		elif a.begins_with("--out="):
			out_path = a.substr(6)
	if capture_size == Vector2i.ZERO:
		capture_size = _pick_capture(target_size)
	if out_path == "" or out_path.contains("docs/img"):
		push_error("phone_hud_shot: нужен --out=путь вне docs/img")
		quit(1)
		return
	# Растяжку НЕ трогаем: canvas_items/expand из project.godot — как в игре.
	# Окно только задаёт соотношение сторон и плотность рендера.
	root.size = capture_size
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	root.position = Vector2i(-10000, -10000)
	_boot.call_deferred()


## Наибольшее окно нужного соотношения сторон, влезающее в экран стенда.
func _pick_capture(target: Vector2i) -> Vector2i:
	var aspect: float = float(target.x) / float(target.y)
	var w: int = SCREEN_MAX.x
	var h: int = int(round(float(w) / aspect))
	if h > SCREEN_MAX.y:
		h = SCREEN_MAX.y
		w = int(round(float(h) * aspect))
	return Vector2i(maxi(w, 2), maxi(h, 2))


func _boot() -> void:
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	scene = main_scene.instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > HARD_LIMIT:
		push_error("phone_hud_shot: превышен лимит %.0f с — выходим" % HARD_LIMIT)
		quit(2)
	return false


func _run() -> void:
	var game: Node = root.get_node("Game")
	scene.set("scenario_mode", true)
	game.set("scenario_mode", true)
	game.set("time_of_day", 0.40)
	root.size = capture_size
	root.get_node("UI").call("set_ui_scale", ui_scale, false)
	await _frames(20)
	var tc: Node = get_first_node_in_group("touch_controls")
	if tc == null or not bool(tc.get("enabled")):
		push_error("phone_hud_shot: сенсорное управление не включено (нужен --touch)")
		quit(1)
		return
	var p: Node2D = scene.get("player")
	p.set_physics_process(false)
	p.get("camera").reset_smoothing()
	tc.set("stick_vec", Vector2(0.65, 0))
	await _frames(8)
	var hud: Node = root.get_node("UI").get("hud")
	if hud == null:
		push_error("phone_hud_shot: HUD нет")
		quit(1)
		return
	if shot_state == "intro":
		game.set("game_time", 1.0 if forced_time < 0.0 else forced_time)
		p.vel = Vector2.ZERO
		# Игрок стоит у терминала — контекстная подсказка перебила бы вводную.
		hud.hint_text = ""
		hud._hint_hash = "".hash()
		if hud.get("_intro_done") != null:
			hud.set("_intro_done", false)
	else:
		var t: float = forced_time
		if t < 0.0:
			t = 10.0 if shot_state == "mission" else 30.0
		game.set("game_time", t)
		hud.hint_text = "[E] — выполнить задание (удерживать)"
		hud._hint_hash = hash(hud.hint_text)
	if not keep_notes:
		# Стартовые реплики ПСА — не часть раскладки; для чистого кадра убираем.
		hud.notes.clear()
	paused = true
	hud._lay_sig = -1
	if hud.has_method("layout_named"):
		hud.layout_named()
	hud.queue_redraw()
	# Первый кадр после ресайза — ещё прежний размер. Ждём следующий.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var src: Image = root.get_viewport().get_texture().get_image()
	if src == null or src.is_empty():
		push_error("phone_hud_shot: пустой кадр")
		quit(1)
		return
	var canvas: Vector2 = root.get_viewport().get_visible_rect().size
	var hud_size: Vector2 = hud.size
	print("phone_hud_shot: окно %s, холст %s, ui_scale %.2f, HUD %s (ожидался %s), кадр %dx%d" % [
		str(root.size), str(canvas), ui_scale, str(hud_size),
		str(canvas / ui_scale), src.get_width(), src.get_height()])
	var img: Image = src.duplicate()
	if img.get_size() != target_size:
		img.resize(target_size.x, target_size.y, Image.INTERPOLATE_LANCZOS)
	var err: int = img.save_png(ProjectSettings.globalize_path(out_path))
	print("снято: %s (%dx%d), код %d" % [out_path, img.get_width(), img.get_height(), err])
	quit(0 if err == OK else 1)


func _frames(n: int) -> void:
	for i in n:
		await process_frame