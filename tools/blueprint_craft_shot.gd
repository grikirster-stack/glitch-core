extends SceneTree
## Кадр панели крафта с чертежом (#169) для PR: docs/img/shots/blueprint_craft.png.
##
## Headless не рисует кадр. Окно — за пределами экрана, без звука; скрипт сам
## выходит (≤ 18 с):
##   timeout 120 /tmp/godot47/Godot --path . --audio-driver Dummy --disable-vsync \
##         --fixed-fps 60 --windowed --position -10000,-10000 --resolution 1920x1080 \
##         --script res://tools/blueprint_craft_shot.gd -- --seed=31337
##
## Окно шире 1280: панель 820×540 при масштабе 100 % влезает целиком, и имя
## «Стальная стена» не режется в «…». Кадр пишется как есть.
##
## Что в кадре: открыта панель крафта, вкладка «Плавильня». Чертёж «Стальная
## стена» — строка рецепта с иконкой и коротким именем. Подарок терминала —
## иконки в ячейках инвентаря, не строка «Кристалл глитча ×1, Уголь ×7…».
## Строки HUD (нагрузка ТЭЦ, подсказка) на время кадра скрыты; игровой HUD
## не меняется.
## Флаг --out=путь пишет снимок не в docs/img/shots, а в указанный файл.

const OUT: String = "res://docs/img/shots/blueprint_craft.png"
const HARD_LIMIT: float = 18.0

var out_path: String = OUT
var scene: Node = null
var _elapsed: float = 0.0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("blueprint_craft_shot: headless не рендерит — нужен прогон с окном за экраном")
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
		push_error("blueprint_craft_shot: превышен лимит %.0f с — выходим" % HARD_LIMIT)
		quit(2)
	return false


func _run() -> void:
	var world: Node = root.get_node("World")
	var game: Node = root.get_node("Game")
	var ui: Node = root.get_node("UI")
	var ids: GDScript = load("res://scripts/core/ids.gd")
	var steel: int = int(ids.I.STEEL_WALL)
	scene.set("scenario_mode", true)
	game.set("scenario_mode", true)
	game.set("game_time", 30.0)
	game.set("time_of_day", 0.40)
	# 1920×1080 и масштаб 100 %: панель не сжимается, подписи не режутся «…».
	root.size = Vector2i(1920, 1080)
	ui.call("set_ui_scale", 1.0, false)
	await _frames(12)

	var term: Vector2i = _terminal_of(world, 0)
	if term.x < 0:
		push_error("blueprint_craft_shot: нет терминала базы (глава 1)")
		quit(1)
		return
	var p: Node2D = scene.get("player")
	p.set_physics_process(false)
	# Плавильня рядом: вкладка без ярлыка «нет станка», имя чертежа не режется.
	# Питание не ставим — строка нагрузки ТЭЦ на кадр не нужна.
	var mb: GDScript = load("res://scripts/machines/machine_base.gd")
	var smelter_cell: Vector2i = term + Vector2i(1, 0)
	if not mb.place_machine("Smelter", smelter_cell):
		smelter_cell = term + Vector2i(-1, 0)
		if not mb.place_machine("Smelter", smelter_cell):
			push_error("blueprint_craft_shot: плавильня не встала у терминала %s" % str(term))
			quit(1)
			return
	p.global_position = world.cell_to_world(smelter_cell) + Vector2(8.0, 6.0)
	var cam: Camera2D = p.get("camera")
	cam.reset_smoothing()
	await _frames(2)

	# Тот же путь, что у игрока: глава, чертёж, подарок. Питание не ставим —
	# иначе HUD рисует «ТЭЦ: нагрузка …», а кадр этого не должен показывать.
	p.call("_read_terminal", term)
	if not game.has_blueprint(steel):
		push_error("blueprint_craft_shot: чертёж «Стальная стена» не выдан: %s" % str(game.blueprints))
		quit(1)
		return

	var gift: Array = world.terminal_gift(0)
	var inv = p.get("inv")
	for e in gift:
		inv.add(int(e[0]), int(e[1]))
	# Подарок на полу не оставляем: панель его закрывает, а в уведомлении
	# он был бы текстом. На кадре те же предметы — иконками в ячейках.
	for c in scene.get_children():
		if c.get("item_id") != null and c.get("vel") != null:
			c.queue_free()

	ui.get("hud").set("notes", [])
	ui.get("hud").set("hint_text", "")
	ui.get("hud").set("tutorial_text", "")
	ui.get("hud").set("power_gen", null)
	ui.get("hud").set("power_text", "")
	ui.toggle_inventory()
	var panel: Control = ui.get("panel")
	if panel == null or not panel.visible:
		push_error("blueprint_craft_shot: панель крафта не открылась")
		quit(1)
		return
	panel.set("station_tab", 1)
	panel.set("scroll", 0)
	panel.queue_redraw()
	await _frames(6)
	# Панель рисуется поверх HUD. На кадр гасим строки HUD: постоянный HUD не трогаем.
	ui.get("hud").visible = false
	await _frames(2)

	var saw_wall: bool = false
	var wall_row: int = -1
	var recipes: Array = panel._recipes("smelter")
	for i in recipes.size():
		var rec: Dictionary = recipes[i]
		if int(rec["out"]) == steel and String(rec["name"]) == "Стальная стена":
			saw_wall = true
			wall_row = i
	if not saw_wall or wall_row < 0 or wall_row >= int(panel.get("RECIPE_ROWS")):
		push_error("blueprint_craft_shot: в списке плавильни нет «Стальной стены»")
		quit(1)
		return
	var filled: int = 0
	for st in inv.slots:
		if not st.is_empty():
			filled += 1
	if filled < gift.size():
		push_error("blueprint_craft_shot: подарок не лёг в ячейки (%d < %d)" % [filled, gift.size()])
		quit(1)
		return
	# Имя рецепта должно влезть целиком: ярлык «нет станка» его режет.
	var row: Rect2 = panel._recipe_row_rect(wall_row)
	var title: String = "Стальная стена ×4"
	var tag_w: float = minf(panel._w("клик — загрузить", 14), 170.0)
	var name_w: float = row.size.x - 42.0 - tag_w - 18.0
	if panel._w(title, 14) > name_w:
		push_error("blueprint_craft_shot: «%s» не влезает (%.0f > %.0f)" % [title, panel._w(title, 14), name_w])
		quit(1)
		return

	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null or img.is_empty():
		push_error("blueprint_craft_shot: пустой кадр")
		quit(1)
		return
	var err: int = img.save_png(ProjectSettings.globalize_path(out_path))
	print("снято: %s (%dx%d), код %d, чертёж %s, подарок %s" % [
			out_path, img.get_width(), img.get_height(), err, str(game.blueprints), str(gift)])
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
