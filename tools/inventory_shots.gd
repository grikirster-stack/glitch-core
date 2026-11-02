extends SceneTree
## Скриншоты панели инвентаря у сундука (#69) — «до» и «после» для PR и README.
##
## Запуск (headless не рендерит, поэтому окно ЗА ПРЕДЕЛАМИ ЭКРАНА, без звука;
## скрипт сам выходит, ≤ 20 с):
##   godot --path . --audio-driver Dummy --windowed --position -10000,-10000 \
##         --resolution 1280x720 --script res://tools/inventory_shots.gd -- --prefix=after
##
## За один прогон снимаются оба размера окна: 1280×720 и 960×540 (окно
## меняет размер само). Файлы — docs/img/inventory_<prefix>_<ширина>.png;
## если у панели есть подсказки по наведению (#69), ещё
## docs/img/inventory_<prefix>_tip_<ширина>.png — курсор над запертым/неполным рецептом.
##
## Состояние — как на скриншоте игрока из #69: открыт тайник руины, вкладка
## «Ручной крафт», в инвентаре стартовый набор и немного добра.
## Мышь двигается событием прямо в панель (_gui_input) — курсор системы не трогается.

const OUT: String = "res://docs/img/"
const HARD_LIMIT: float = 18.0
const SIZES: Array = [Vector2i(1280, 720), Vector2i(960, 540)]

var scene: Node = null
var prefix: String = "shot"
var saved: int = 0
var _elapsed: float = 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--prefix="):
			prefix = String(a).substr(9)
	if DisplayServer.get_name() == "headless":
		print("inventory_shots: headless не рендерит — нужен прогон с окном за экраном")
		quit(1)
		return
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
		push_error("inventory_shots: превышен лимит %.0f с — выходим" % HARD_LIMIT)
		quit(2)
	return false


func _run() -> void:
	var world: Node = root.get_node("World")
	var game: Node = root.get_node("Game")
	var ui: Node = root.get_node("UI")
	scene.set("scenario_mode", true)
	game.set("scenario_mode", true)
	game.set("game_time", 30.0)              ## подсказка управления уже погасла
	game.set("time_of_day", 0.40)
	await _frames(10)
	ui.get("hud").set("notes", [])

	var p: Node2D = scene.get("player")
	var inv = p.get("inv")
	for e in [[IDs.I.SCRAP, 6], [IDs.I.STONE, 4], [IDs.I.IRON_PLATE, 1]]:
		inv.add(int(e[0]), int(e[1]))
	# Тайник первой руины — сундук с именем места.
	var caches: Array = world.get("ruin_caches")
	var chest: Node2D = null
	for c in caches:
		if c["chest"] != null:
			chest = c["chest"]
			break
	if chest == null:
		push_error("нет тайника руины")
		quit(1)
		return
	p.set_physics_process(false)
	p.global_position = chest.global_position + Vector2(-20, 0)
	var cam: Camera2D = p.get("camera")
	cam.reset_smoothing()
	await _frames(6)
	ui.open_chest(chest)
	var panel: Control = ui.get("panel")
	await _frames(4)

	for sz in SIZES:
		root.size = sz
		await _frames(6)
		var w: int = int(sz.x)
		# Мышь вне рецептов: общий вид панели.
		_mouse(panel, Vector2(8, 8))
		await _frames(2)
		await _grab("inventory_%s_%d.png" % [prefix, w])
		# Подсказка по наведению — только если панель её умеет (#69):
		# «Ковка железа» — железной руды нет, видно нехватку.
		if panel.has_method("_recipe_row_rect"):
			var r: Rect2 = panel._recipe_row_rect(1)
			_mouse(panel, r.position + Vector2(60, 20))
			await _frames(2)
			await _grab("inventory_%s_tip_%d.png" % [prefix, w])
			# Стопка из тайника «в руке» у курсора, над инвентарём.
			if w == 1280:
				panel._click(panel._chest_slot_rect(0).get_center(), false)
				_mouse(panel, panel._inv_slot_rect(22).get_center())
				await _frames(2)
				await _grab("inventory_%s_held_%d.png" % [prefix, w])
				panel._click(panel._chest_slot_rect(0).get_center(), false)
	print("ИТОГ: сохранено PNG: %d" % saved)
	quit(0)


## Событие движения мыши прямо в панель: системный курсор не двигается.
func _mouse(panel: Control, pos: Vector2) -> void:
	var ev: InputEventMouseMotion = InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	panel._gui_input(ev)
	panel.queue_redraw()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _grab(rel: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null or img.is_empty():
		push_error("пустой кадр: %s" % rel)
		return
	var err: int = img.save_png(ProjectSettings.globalize_path(OUT + rel))
	if err != OK:
		push_error("не сохранён %s (код %d)" % [rel, err])
		return
	saved += 1
	print("снято: %s (%dx%d)" % [rel, img.get_width(), img.get_height()])
