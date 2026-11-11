extends SceneTree
## Кадр списка рецептов (#171): docs/img/shots/ingot_recipes.png.
## Только строки: слиток, стекло, светокристалл, имена целиком.
## Без простыни «Сундук не открыт», без второго хотбара и без плашки терминала.
##
## Headless не рисует кадр. Окно — за пределами экрана, без звука; скрипт сам
## выходит (≤ 18 с):
##   timeout 120 /tmp/godot47/Godot --path . --audio-driver Dummy --disable-vsync \
##         --fixed-fps 60 --windowed --position -10000,-10000 --resolution 1280x720 \
##         --script res://tools/ingot_recipes_shot.gd -- --seed=31337

const OUT: String = "res://docs/img/shots/ingot_recipes.png"
const HARD_LIMIT: float = 18.0

var scene: Node = null
var _elapsed: float = 0.0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("ingot_recipes_shot: headless не рендерит — нужен прогон с окном за экраном")
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
		push_error("ingot_recipes_shot: превышен лимит %.0f с — выходим" % HARD_LIMIT)
		quit(2)
	return false


func _run() -> void:
	var game: Node = root.get_node("Game")
	var ui: Node = root.get_node("UI")
	var ids: GDScript = load("res://scripts/core/ids.gd")
	scene.set("scenario_mode", true)
	game.set("scenario_mode", true)
	game.set("game_time", 30.0)
	game.set("time_of_day", 0.40)
	root.size = Vector2i(1280, 720)
	ui.call("set_ui_scale", 1.0, false)
	await _frames(12)

	var world: Node = root.get_node("World")
	var p: Node = scene.get("player")
	p.set_physics_process(false)
	p.set_process(false)
	# В стороне от терминала базы: иначе HUD режет «Терминал: нет питания…».
	var tile: int = int(world.TILE)
	var bx: int = int(world.beacon_cell.x)
	var base: int = int(world.beacon_cell.y) + 1
	p.global_position = Vector2(float((bx + 18) * tile) + 8.0, float((base + 10) * tile) + 14.0)
	p.set("vel", Vector2.ZERO)
	var inv = p.get("inv")
	inv.call("add", int(ids.I.SAND), 4)
	inv.call("add", int(ids.I.COPPER_ORE), 4)
	inv.call("add", int(ids.I.IRON_ORE), 2)
	inv.call("add", int(ids.I.CRYSTAL), 2)
	inv.call("add", int(ids.I.COPPER_INGOT), 4)
	await _frames(4)

	var panel: Node = ui.get("panel")
	panel.call("open", p)
	panel.set("station_tab", 0)
	panel.set("scroll", 0)
	var want: Array = [int(ids.I.COPPER_INGOT), int(ids.I.IRON_INGOT), int(ids.I.GLASS), int(ids.I.LAMP)]
	var keep: Array = []
	for r in panel.call("_recipes", "hand"):
		var out_id: int = int(r["out"])
		if want.has(out_id) and keep.size() < want.size():
			var already: bool = false
			for k in keep:
				if int(k["out"]) == out_id:
					already = true
			if not already:
				keep.append(r)
	if keep.size() != want.size():
		push_error("ingot_recipes_shot: в списке нет слитка, стекла или светокристалла (%d)" % keep.size())
		quit(1)
		return
	panel.set("_shot_rows", keep)
	panel.set("_shot_list_only", true)
	panel.set("mouse_pos", Vector2(-1, -1))
	var hud: Node = ui.get("hud")
	if hud != null:
		hud.visible = false
	await _frames(8)

	var db: Node = root.get_node("DB")
	for rec in keep:
		var title: String = String(db.call("item_name", int(rec["out"])))
		if panel.call("_w", title, 14) > 360.0:
			push_error("ingot_recipes_shot: имя «%s» не влезает в строку" % title)
			quit(1)
			return

	var img: Image = root.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path(OUT)
	var err: int = img.save_png(path)
	if err != OK:
		push_error("ingot_recipes_shot: не записал %s (%d)" % [path, err])
		quit(1)
		return
	print("ingot_recipes_shot: %s %dx%d" % [path, img.get_width(), img.get_height()])
	quit(0)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame
