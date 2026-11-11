extends SceneTree
## Кадр приёмки чертежа (#169): docs/img/shots/blueprint_journal.png.
##
## Журнал, не панель крафта. Чертёж «Стальная стена» — иконка и короткое имя
## целиком. Нет вкладки «Плавильня», нет «стальной пластины», нет строки
## «Чертежи: N из M · …» и нет счётчика деталей (микросхема, энергоячейка,
## антенна). Подарок терминала — иконки в хотбаре из 6 ячеек, не абзац.
##
## Headless не рисует кадр. Окно — за пределами экрана, без звука; скрипт сам
## выходит (≤ 18 с):
##   timeout 120 /tmp/godot47/Godot --path . --audio-driver Dummy --disable-vsync \
##         --fixed-fps 60 --windowed --position -10000,-10000 --resolution 1280x720 \
##         --script res://tools/blueprint_journal_shot.gd -- --seed=31337
##
## Флаг --out=путь пишет снимок не в docs/img/shots, а в указанный файл.
## docs/img/shots/blueprint_craft.png и blueprint_terminal.png к приёмке не относятся.

const OUT: String = "res://docs/img/shots/blueprint_journal.png"
const HARD_LIMIT: float = 18.0

var out_path: String = OUT
var scene: Node = null
var _elapsed: float = 0.0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("blueprint_journal_shot: headless не рендерит — нужен прогон с окном за экраном")
		quit(1)
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_path = a.substr(6)
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	root.position = Vector2i(-10000, -10000)
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	scene = main_scene.instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > HARD_LIMIT:
		push_error("blueprint_journal_shot: превышен лимит %.0f с — выходим" % HARD_LIMIT)
		quit(2)
	return false


func _run() -> void:
	# --script не поднимает имена автозагрузок на компиляции: только get_node.
	var world: Node = root.get_node("World")
	var game: Node = root.get_node("Game")
	var ui: Node = root.get_node("UI")
	var db: Node = root.get_node("DB")
	var ids: GDScript = load("res://scripts/core/ids.gd")
	var steel: int = int(ids.I.STEEL_WALL)
	scene.set("scenario_mode", true)
	game.set("scenario_mode", true)
	game.set("game_time", 30.0)
	game.set("time_of_day", 0.40)
	root.size = Vector2i(1280, 720)
	ui.call("set_ui_scale", 1.0, false)
	await _frames(12)

	var term: Vector2i = _terminal_of(world, 0)
	if term.x < 0:
		push_error("blueprint_journal_shot: нет терминала базы (глава 1)")
		quit(1)
		return
	var p: Node2D = scene.get("player")
	p.set_physics_process(false)
	# Кадр приёмки — как на телефоне после #161: 6 ячеек, не десятка ПК.
	# Только снимок: профиль игрока не пишем.
	p.call("apply_hotbar_size", 6)
	p.global_position = world.cell_to_world(term) + Vector2(18.0, 8.0)
	var cam: Camera2D = p.get("camera")
	cam.reset_smoothing()
	await _frames(2)

	# Тот же путь, что у игрока: глава, чертёж, подарок. Питание не ставим —
	# иначе HUD рисует «ТЭЦ: нагрузка …».
	p.call("_read_terminal", term)
	if not game.has_blueprint(steel):
		push_error("blueprint_journal_shot: чертёж «Стальная стена» не выдан: %s" % str(game.blueprints))
		quit(1)
		return
	if game.blueprints.size() != 1:
		push_error("blueprint_journal_shot: в кадре должен быть один чертёж, есть %d" % game.blueprints.size())
		quit(1)
		return

	var gift: Array = world.terminal_gift(0)
	var inv = p.get("inv")
	for e in gift:
		inv.add(int(e[0]), int(e[1]))
	# Подарок на полу панель закрывает. На кадре те же предметы — иконками в хотбаре.
	for c in scene.get_children():
		if c.get("item_id") != null and c.get("vel") != null:
			c.queue_free()

	ui.get("hud").set("notes", [])
	ui.get("hud").set("hint_text", "")
	ui.get("hud").set("tutorial_text", "")
	ui.get("hud").set("power_gen", null)
	ui.get("hud").set("power_text", "")
	ui.toggle_journal()
	var journal: Control = ui.get("journal")
	if journal == null or not journal.visible:
		push_error("blueprint_journal_shot: журнал не открылся")
		quit(1)
		return
	if int(journal.get("selected")) < 0:
		push_error("blueprint_journal_shot: глава не выбрана")
		quit(1)
		return
	var cap: String = String(journal.call("blueprint_caption", 0))
	if cap == "" and game.blueprints.size() == 1:
		cap = String(db.call("item_name", steel))
	if cap != "Стальная стена":
		push_error("blueprint_journal_shot: подпись «%s», ждали «Стальная стена»" % cap)
		quit(1)
		return
	if cap.contains("…") or cap.contains("из"):
		push_error("blueprint_journal_shot: подпись обрезана или со счётчиком: «%s»" % cap)
		quit(1)
		return
	var row: Rect2 = journal.call("blueprint_rect", 0)
	var font: Font = ThemeDB.fallback_font as Font
	var name_w: float = font.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	if name_w > row.size.x - 48.0:
		push_error("blueprint_journal_shot: «%s» не влезает (%.0f)" % [cap, name_w])
		quit(1)
		return
	var filled: int = 0
	for st in inv.slots:
		if not st.is_empty():
			filled += 1
	if filled < gift.size():
		push_error("blueprint_journal_shot: подарок не лёг в ячейки (%d < %d)" % [filled, gift.size()])
		quit(1)
		return

	journal.queue_redraw()
	await _frames(4)
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null or img.is_empty() or img.get_width() < 100:
		push_error("blueprint_journal_shot: пустой кадр")
		quit(1)
		return
	# Пустой кадр Godot 4.3 — почти чёрный. Живой журнал не такой.
	if img.get_pixel(img.get_width() / 2, img.get_height() / 2).get_luminance() < 0.02:
		push_error("blueprint_journal_shot: кадр почти чёрный")
		quit(1)
		return
	var err: int = img.save_png(ProjectSettings.globalize_path(out_path))
	print("снято: %s (%dx%d), код %d, чертёж «%s», подарок %s" % [
			out_path, img.get_width(), img.get_height(), err, cap, str(gift)])
	quit(0 if err == OK else 1)


func _terminal_of(world: Node, chapter: int) -> Vector2i:
	var chapters: Dictionary = world.get("terminal_chapters")
	for t in world.get("terminals"):
		if int(chapters.get(t, -1)) == chapter:
			return t
	return Vector2i(-1, -1)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
