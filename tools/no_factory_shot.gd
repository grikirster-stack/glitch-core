extends SceneTree
## Кадр крафта без фабрики (#170): docs/img/shots/no_factory.png.
## Панель без бура, ленты, плавильни и ТЭЦ. Видны горелка, зеркало, маяк, слитки.
## Имена не режутся «…».
##
## Окно за экраном:
##   timeout 120 /tmp/godot47/Godot --path . --audio-driver Dummy --disable-vsync \
##         --fixed-fps 60 --windowed --position -10000,-10000 --resolution 1280x720 \
##         --script res://tools/no_factory_shot.gd -- --seed=31337

const OUT: String = "res://docs/img/shots/no_factory.png"
const HARD_LIMIT: float = 18.0

var scene: Node = null
var _elapsed: float = 0.0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("no_factory_shot: headless не рендерит — нужно окно за экраном")
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
		push_error("no_factory_shot: превышен лимит %.0f с" % HARD_LIMIT)
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
	var tile: int = int(world.TILE)
	var bx: int = int(world.beacon_cell.x)
	var base: int = int(world.beacon_cell.y) + 1
	p.global_position = Vector2(float((bx + 18) * tile) + 8.0, float((base + 10) * tile) + 14.0)
	p.set("vel", Vector2.ZERO)
	game.set("blueprints", PackedStringArray(["PHAROS"]))
	var inv = p.get("inv")
	for id in [ids.I.STONE, ids.I.SCRAP, ids.I.COPPER_ORE, ids.I.IRON_ORE, ids.I.COPPER_INGOT,
			ids.I.IRON_INGOT, ids.I.GLASS, ids.I.CRYSTAL]:
		inv.call("add", int(id), 8)
		inv.call("mark_seen", int(id))
	await _frames(4)

	var panel: Node = ui.get("panel")
	panel.call("open", p)
	panel.set("station_tab", 0)
	panel.set("scroll", 0)
	var want: Array = [int(ids.I.COPPER_INGOT), int(ids.I.IRON_INGOT), int(ids.I.BURNER),
			int(ids.I.MIRROR), int(ids.I.PHAROS)]
	var banned: Array = [int(ids.I.DRILL), int(ids.I.BELT), int(ids.I.SMELTER), int(ids.I.COAL_GEN)]
	var keep: Array = []
	for r in panel.call("_recipes", "hand"):
		var out_id: int = int(r["out"])
		if banned.has(out_id):
			push_error("no_factory_shot: в крафте ещё есть фабрика (%d)" % out_id)
			quit(1)
			return
		if want.has(out_id):
			var already: bool = false
			for k in keep:
				if int(k["out"]) == out_id:
					already = true
			if not already:
				keep.append(r)
	for i in keep.size():
		var r: Dictionary = keep[i]
		if int(r["out"]) != int(ids.I.PHAROS):
			continue
		var inn: Dictionary = {}
		for k in r["in"].keys():
			if int(k) == int(ids.I.CRYSTAL):
				continue
			inn[int(k)] = int(r["in"][k])
		r = r.duplicate(true)
		r["in"] = inn
		keep[i] = r
	if keep.size() != want.size():
		push_error("no_factory_shot: нет горелки, зеркала, маяка или слитка (%d)" % keep.size())
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
			push_error("no_factory_shot: имя «%s» не влезает" % title)
			quit(1)
			return
		if title.contains("…"):
			push_error("no_factory_shot: имя обрезано «%s»" % title)
			quit(1)
			return

	var img: Image = root.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path(OUT)
	var err: int = img.save_png(path)
	if err != OK:
		push_error("no_factory_shot: не записал %s (%d)" % [path, err])
		quit(1)
		return
	print("no_factory_shot: %s %dx%d" % [path, img.get_width(), img.get_height()])
	quit(0)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame
