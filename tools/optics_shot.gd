extends SceneTree
## Кадр оптики (#165): ночь, стена, зеркало поворачивает луч, смеситель даёт другой цвет.
##
## Headless не рисует. Окно за экраном, без звука, скрипт сам выходит:
##   timeout 120 godot --path . --audio-driver Dummy --disable-vsync --fixed-fps 60 \
##     --windowed --position -10000,-10000 --resolution 1280x720 \
##     --script res://tools/optics_shot.gd -- --seed=31337

const OUT: String = "res://docs/img/shots/optics.png"
const HARD_LIMIT: float = 25.0

var _elapsed: float = 0.0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("optics_shot: headless не рендерит — нужен прогон с окном за экраном")
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
		push_error("optics_shot: превышен лимит %.0f с" % HARD_LIMIT)
		quit(2)
		return true
	return false


func _run() -> void:
	var world: Node = root.get_node("World")
	var game: Node = root.get_node("Game")
	game.set("time_of_day", 0.82)
	game.set("game_time", 40.0)
	await _frames(8)
	var origin: Vector2i = world.beacon_cell + Vector2i(2, -4)
	for x in range(origin.x - 8, origin.x + 24):
		for y in range(origin.y - 14, origin.y + 8):
			if world.in_bounds(x, y):
				world.set_tile(x, y, IDs.T.AIR)
	for x in range(origin.x - 8, origin.x + 24):
		world.set_tile(x, origin.y + 4, IDs.T.STONE)
	# Стена сразу за зеркалом, только на линии красного. Сквозь камень луч не идёт.
	var mirror_cell: Vector2i = origin + Vector2i(5, 0)
	for y in range(origin.y - 1, origin.y + 4):
		world.set_tile(mirror_cell.x + 1, y, IDs.T.STONE)
	var mb: GDScript = load("res://scripts/machines/machine_base.gd")
	if not _place(mb, world, "Burner", origin, 0, IDs.I.COAL):
		return
	if not mb.place_machine("Mirror", mirror_cell):
		push_error("optics_shot: зеркало не встало")
		quit(1)
		return
	# Смеситель слева и выше столба: красный снизу, зелёный слева, выход — жёлтый.
	# Линии не пересекаются, поэтому жёлтый на кадре остаётся жёлтым.
	var mix_cell: Vector2i = origin + Vector2i(-2, -8)
	if not mb.place_machine("Mixer", mix_cell):
		push_error("optics_shot: смеситель не встал")
		quit(1)
		return
	if not _place(mb, world, "Burner", mix_cell + Vector2i(0, 3), 3, IDs.I.COAL):
		return
	if not _place(mb, world, "Burner", mix_cell + Vector2i(-4, 0), 0, IDs.I.COPPER_ORE):
		return
	# Призма на жёлтом выходе: не белый — проходит прямо, цвет на выходе другой.
	var prism_cell: Vector2i = mix_cell + Vector2i(4, 0)
	if not mb.place_machine("Prism", prism_cell):
		push_error("optics_shot: призма не встала")
		quit(1)
		return
	world.beams.note_machines()
	world.beams.rebuild()
	world._apply_beam_lights()
	var player: Node2D = current_scene.get("player")
	if player != null:
		player.global_position = world.cell_to_world(origin + Vector2i(0, 3))
		var cam: Camera2D = player.get("camera")
		if cam != null:
			cam.position_smoothing_enabled = false
			cam.zoom = Vector2(3.6, 3.6)
			cam.global_position = world.cell_to_world(origin + Vector2i(2, -4))
			cam.reset_smoothing()
	var ui: Node = root.get_node_or_null("UI")
	var hud: Node = ui.get("hud") if ui != null else null
	if hud != null:
		hud.set("tutorial_step", 5)
		hud.set("tutorial_text", "")
		hud.set("hint_text", "")
		hud.set("notes", [])
		# Карточка «Сейчас» рисуется на самом HUD. Прячем слой, не текст.
		hud.visible = false
	await _frames(10)
	var img: Image = root.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err: int = img.save_png(path)
	var turned: int = world.beams.color_at(mirror_cell + Vector2i(0, -2))
	var mixed: int = world.beams.color_at(prism_cell + Vector2i(2, 0))
	var through: int = world.beams.color_at(mirror_cell + Vector2i(2, 0))
	print("optics_shot: %s (%d), поворот %d, смесь %d, сквозь %d" % [
			path, err, turned, mixed, through])
	quit(0 if err == OK and turned == 1 and mixed == 3 and through == 0 else 1)


func _place(mb: GDScript, world: Node, kind: String, cell: Vector2i, dir: int, fuel: int) -> bool:
	if not mb.place_machine(kind, cell):
		push_error("optics_shot: %s не встала в %s" % [kind, str(cell)])
		quit(1)
		return false
	var m = world.machines[cell]
	m.dir = dir
	if fuel >= 0 and m.has_method("add_fuel"):
		m.add_fuel(fuel, 2)
	return true


func _frames(n: int) -> void:
	for i in n:
		await process_frame
