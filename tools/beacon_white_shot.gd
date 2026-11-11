extends SceneTree
## Кадр маяка под белым (#168): белый луч вошёл в башню, руда видна сквозь породу.
##
## Три горелки и смеситель дают белый честно. Руда в камне рядом с башней
## уже разведана — ребёнок видит жилу, не абзац.
##
## Headless не рисует. Окно за экраном, без звука, скрипт сам выходит:
##   timeout 120 /tmp/godot47/Godot --path . --audio-driver Dummy --disable-vsync \
##     --windowed --position -10000,-10000 --resolution 1280x720 \
##     --script res://tools/beacon_white_shot.gd -- --seed=31337

const OUT: String = "res://docs/img/shots/beacon_white.png"
const HARD_LIMIT: float = 25.0

var _elapsed: float = 0.0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("beacon_white_shot: headless не рендерит — нужен прогон с окном за экраном")
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
		push_error("beacon_white_shot: превышен лимит %.0f с" % HARD_LIMIT)
		quit(2)
		return true
	return false


func _run() -> void:
	var world: Node = root.get_node("World")
	var game: Node = root.get_node("Game")
	# День: и луч, и руда в породе читаются. Герой далеко — обзор жилу не открывает.
	game.set("time_of_day", 0.30)
	game.set("game_time", 30.0)
	await _frames(8)
	# Ниже базы и тумана старта: руда должна проступить, а не быть уже открытой.
	# Внутри мира: камера с зумом 4.5 не должна упираться в limit_left.
	# Ниже поверхности и правее края: камера с зумом 4.5 не упирается в пределы мира.
	var origin: Vector2i = Vector2i(maxi(world.beacon_cell.x - 10, 40), world.beacon_cell.y + 28)
	for x in range(origin.x - 6, origin.x + 22):
		for y in range(origin.y - 8, origin.y + 10):
			if world.in_bounds(x, y):
				world.set_tile(x, y, IDs.T.STONE)
				world.explored[y * world.W + x] = 0
	# Пол и воздух над ним — чтобы луч и башня читались.
	# Снизу нужен воздух до горелки кристалла (смеситель + 3).
	for x in range(origin.x - 4, origin.x + 18):
		for y in range(origin.y - 6, origin.y + 6):
			world.set_tile(x, y, IDs.T.AIR)
	for x in range(origin.x - 4, origin.x + 18):
		world.set_tile(x, origin.y + 6, IDs.T.STONE)
	var doomed: Array = []
	for c in world.machines.keys():
		if c.x >= origin.x - 4 and c.x <= origin.x + 18 and c.y >= origin.y - 6 and c.y <= origin.y + 6:
			doomed.append(c)
	for c in doomed:
		var old = world.machines[c]
		if old.has_method("dismantle"):
			old.dismantle()
	var mb: GDScript = load("res://scripts/machines/machine_base.gd")
	# Смеситель: уголь слева, медь сверху, кристалл снизу, белый — вправо в маяк.
	var mix: Vector2i = origin + Vector2i(3, 0)
	if not mb.place_machine("Mixer", mix):
		push_error("beacon_white_shot: смеситель не встал")
		quit(1)
		return
	if not _place(mb, world, "Burner", mix + Vector2i(-3, 0), 0, IDs.I.COAL):
		return
	if not _place(mb, world, "Burner", mix + Vector2i(0, -3), 1, IDs.I.COPPER_ORE):
		return
	if not _place(mb, world, "Burner", mix + Vector2i(0, 3), 3, IDs.I.CRYSTAL):
		return
	# Близко к смесителю: белая линия ещё яркая, когда входит в башню.
	var pc: Vector2i = mix + Vector2i(2, 0)
	if not mb.place_machine("Pharos", pc):
		push_error("beacon_white_shot: маяк не встал")
		quit(1)
		return
	# Жила в породе сразу справа от башни. Кристалл и уголь читаются на камне.
	# Соседний камень открываем тоже: иначе жила тонет в чёрном тумане.
	var vein: Array[Vector2i] = [
		pc + Vector2i(2, 1), pc + Vector2i(3, 1), pc + Vector2i(4, 1),
		pc + Vector2i(2, 2), pc + Vector2i(3, 2),
	]
	var kinds: Array[int] = [IDs.T.CRYSTAL_ORE, IDs.T.CRYSTAL_ORE, IDs.T.COAL_ORE, IDs.T.COPPER_ORE, IDs.T.IRON_ORE]
	for i in vein.size():
		world.set_tile(vein[i].x, vein[i].y, kinds[i])
		world.explored[vein[i].y * world.W + vein[i].x] = 0
	for dx in range(1, 6):
		for dy in range(0, 4):
			var sc: Vector2i = pc + Vector2i(dx, dy)
			if world.get_tile(sc.x, sc.y) == IDs.T.STONE:
				world.reveal_cells([sc])
	if world.beams != null:
		world.beams.note_machines()
		world.beams.rebuild()
		world._apply_beam_lights()
	var pharos = world.machines[pc]
	# Белый открывает руду сам, раз в секунду. Кадр не ждёт таймер:
	# reveal_cells шлёт explored_changed, туман слушает его сам.
	if pharos.has_method("_ore_hidden"):
		var hidden: Array = pharos._ore_hidden()
		world.reveal_cells(hidden)
	var player: Node2D = current_scene.get("player")
	if player != null:
		# Ниже жилы: круг обзора героя её не открывает, руду показывает маяк.
		player.global_position = world.cell_to_world(pc + Vector2i(0, 8))
		var cam: Camera2D = player.get("camera")
		if cam != null:
			cam.position_smoothing_enabled = false
			cam.zoom = Vector2(4.5, 4.5)
			cam.global_position = world.cell_to_world(pc + Vector2i(-1, 0))
			cam.reset_smoothing()
	var ui: Node = root.get_node_or_null("UI")
	var hud: Node = ui.get("hud") if ui != null else null
	if hud != null:
		hud.set("tutorial_step", 5)
		hud.set("tutorial_text", "")
		hud.set("hint_text", "")
		hud.set("notes", [])
		hud.set("tracker_title", "")
		hud.set("tracker_detail", "")
		hud.set("card_text", "")
		hud.set("card_need", 0)
		hud.visible = false
	await _frames(6)
	var img: Image = root.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err: int = img.save_png(path)
	var color: int = int(pharos.color)
	print("beacon_white_shot: %s (%d), цвет маяка %d, руда открыта %s" % [
			path, err, color, str(_vein_open(world, vein))])
	quit(0 if err == OK and color == 7 and _vein_open(world, vein) else 1)


func _place(mb: GDScript, world: Node, kind: String, cell: Vector2i, dir: int, fuel: int) -> bool:
	if not mb.place_machine(kind, cell):
		push_error("beacon_white_shot: %s не встал в %s" % [kind, str(cell)])
		quit(1)
		return false
	var m = world.machines[cell]
	while int(m.dir) != dir:
		m.turn()
	m.add_fuel(fuel, 3)
	return true


func _vein_open(world: Node, vein: Array) -> bool:
	for c in vein:
		if not world.is_explored(c):
			return false
	return true


func _frames(n: int) -> void:
	for i in n:
		await process_frame
