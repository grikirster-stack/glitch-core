extends SceneTree
## Кадр приёмки поворота луча. Не часть игры: окно за экраном, HUD скрыт.
##
##   godot --path . --audio-driver Dummy --disable-vsync --fixed-fps 60 \
##     --windowed --position -10000,-10000 --resolution 1280x720 \
##     --script res://tools/beam_turns_shot.gd -- --out=/tmp/light-shots/x.png
##
## --mode=path  — весь путь и маяк (по умолчанию).
## --mode=wall  — стена после двух поворотов, камера на искре.
## --zoom=N     — зум камеры (path 1.5, wall 4).
## --check-mark — пиксели: полный цвет луча рядом с крестом и без тёмного разрыва ног.

const HARD_LIMIT: float = 25.0
## Ближайший пиксель полного цвета луча к центру креста, экранные px.
const BEAM_NEAR_MAX: float = 12.0
## Полный цвет: каналы в 0.04 от Beams.COLOR (золото #FFD86E).
const FULL_EPS: float = 0.04
## Белый крест: все каналы высокие и близки друг к другу.
const CROSS_MIN: float = 0.85

var _elapsed: float = 0.0
var _out: String = "/tmp/light-shots/beam_turns.png"
var _mode: String = "path"
var _check: bool = false
var _zoom: float = -1.0
var _seed: int = -1


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("beam_turns_shot: headless не рендерит")
		quit(1)
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--mode="):
			_mode = a.substr(7)
		elif a.begins_with("--zoom="):
			_zoom = float(a.substr(7))
		elif a == "--check-mark":
			_check = true
		elif a.begins_with("--shot-seed="):
			_seed = int(a.substr(12))
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	root.position = Vector2i(-10000, -10000)
	# --resolution меняет окно, не вьюпорт (stretch canvas_items). Кадр 1800×810
	# должен быть своим вьюпортом, иначе семплер смотрит не туда, куда луч.
	var win: Vector2i = DisplayServer.window_get_size()
	if win.x > 0 and win.y > 0:
		root.size = win
		root.content_scale_size = win
	_boot.call_deferred()


func _boot() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	# Скрипт до инстанса: иначе _ready Main уже стёр _args, и сид случайный.
	# ДО и ПОСЛЕ должны смотреть на один и тот же маяк.
	packed.set("script", null)
	var scene: Node = packed.instantiate()
	var seed: int = 31337
	for a in OS.get_cmdline_args():
		if a.begins_with("--seed="):
			seed = int(a.substr(7))
	scene.set_script(load("res://tools/beam_turns_main.gd"))
	scene.set("_args", PackedStringArray(["--seed=%d" % seed]))
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > HARD_LIMIT:
		push_error("beam_turns_shot: превышен лимит %.0f с" % HARD_LIMIT)
		quit(2)
		return true
	return false


func _run() -> void:
	var world: Node = root.get_node("World")
	var game: Node = root.get_node("Game")
	game.set("time_of_day", 0.82)
	game.set("game_time", 40.0)
	# Туман пишет vis_far из FOG_RADIUS каждый свой кадр. Глушим сразу после
	# _start, круг на путь ставим перед снимком. В игре процесс не трогаем.
	var fog0: Node = _fog_node()
	if fog0 != null:
		fog0.set_process(false)
	await _frames(8)
	print("shot seed beacon=%s world_seed=%s" % [str(world.beacon_cell), str(world.get("world_seed"))])
	var origin: Vector2i = world.beacon_cell + Vector2i(8, 14)
	_clear(world, origin + Vector2i(-8, -16), origin + Vector2i(30, 14))
	var focus: Vector2i
	var mark_cell: Vector2i
	var want_pharos: bool = _mode != "wall"
	if _mode == "wall":
		mark_cell = _place_wall(world, origin)
		# Зум 4 видит ~20×11 клеток. Крест в центре обрезает первую ногу.
		focus = origin + Vector2i(4, -2)
	else:
		var sink: Vector2i = _place_path(world, origin)
		if sink == Vector2i(-1, -1):
			return
		# Зум 1.5: 1280×720 видит ~53×30 клеток, 1800×810 — ~75×34.
		# Маяк на origin+(12, 6). Фокус чуть левее и выше маяка, чтобы
		# и он, и первая нога не ушли за край на узком кадре.
		focus = origin + Vector2i(4, 2)
		mark_cell = sink
	var player: Node2D = current_scene.get("player")
	var zoom: float = _zoom
	if zoom <= 0.0:
		zoom = 4.0 if _mode == "wall" else 1.5
	if player != null:
		# Круг обзора тумана — вокруг героя, не камеры. Герой рядом с
		# фокусом, но не на линии: спрайт не закрывает луч и крест.
		# FOG_RADIUS 8 клеток, мягкий край 3 — смещение на 2 клетки
		# оставляет ноги внутри vis_near.
		# Путь длинный: герой в фокусе кадра, иначе дальние ноги вне круга
		# обзора и туман гасит золото. Стена — на две клетки ниже креста,
		# чтобы спрайт не закрыл искру.
		var hero_cell: Vector2i = focus if _mode != "wall" else focus + Vector2i(0, 2)
		player.global_position = world.cell_to_world(hero_cell)
		var cam: Camera2D = player.get("camera")
		if cam != null:
			cam.position_smoothing_enabled = false
			cam.limit_smoothed = false
			cam.zoom = Vector2(zoom, zoom)
			cam.global_position = world.cell_to_world(focus)
			cam.reset_smoothing()
			cam.make_current()
		world.reveal_around(hero_cell, 10)

	# Туман войны (z 30) закрывает неоткрытые клетки поверх луча (z 20).
	for seg in world.beams.segments:
		world.reveal_around(seg["from"], 2)
		world.reveal_around(seg["to"], 2)
	if _mode == "wall":
		world.reveal_around(mark_cell, 2)
	_hide_hud()
	await _frames(8)
	# Часы не должны увести ночь в рассвет между установкой и кадром.
	game.set("time_of_day", 0.82)
	Engine.time_scale = 0.0
	# Сглаживание камеры уже выключено, но на широком кадре позиция
	# ещё догоняет фокус. Ставим её снова прямо перед снимком.
	if player != null:
		var cam2: Camera2D = player.get("camera")
		if cam2 != null:
			cam2.position_smoothing_enabled = false
			cam2.limit_smoothed = false
			cam2.global_position = world.cell_to_world(focus)
			cam2.reset_smoothing()
			cam2.make_current()
	await _frames(4)
	# Круг обзора — вокруг героя и уже 8 клеток. Путь длиннее: на кадре
	# приёмки круг держим на весь путь и глушим _process тумана, иначе он
	# вернёт FOG_RADIUS до отрисовки. В игре радиус не меняем.
	var fog: Node = _fog_node()
	if fog != null and player != null and fog.material is ShaderMaterial:
		var fm: ShaderMaterial = fog.material
		fm.set_shader_parameter("hero", player.global_position)
		fm.set_shader_parameter("vis_far", 800.0)
		fm.set_shader_parameter("vis_near", 760.0)
		# _process тумана каждый кадр возвращает FOG_RADIUS. На кадре он молчит.
		fog.set_process(false)
		fog.set_process_mode(Node.PROCESS_MODE_DISABLED)
	if player != null:
		var cam3: Camera2D = player.get("camera")
		if cam3 != null:
			cam3.force_update_scroll()
	await _frames(2)
	var img: Image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
	var err: int = img.save_png(_out)
	var pharos = world.machines.get(mark_cell) if want_pharos else null
	var got: int = int(pharos.color) if pharos != null else -1
	var air: int = 0
	for s in world.beams.segments:
		air += int(s.get("air", 0))
	var dist: float = -1.0
	var gaps: String = ""
	var px_ok: bool = true
	if _check:
		gaps = _leg_gaps(img, world)
		px_ok = gaps == ""
		# Крест есть только у обрыва. Маяк — приёмник, не обрыв: расстояние
		# до него не меряем, иначе стекло маяка сойдёт за конец линии.
		if _mode == "wall":
			dist = _beam_to_cross(img, world, mark_cell)
			px_ok = px_ok and dist >= 0.0 and dist <= BEAM_NEAR_MAX
	var sink_px: Vector2 = root.get_canvas_transform() * world.cell_to_world(mark_cell)
	print("маяк_px=%s фокус=%s" % [str(sink_px), str(focus)])
	var cross_w: Vector2 = _cross_world(world, mark_cell)
	var cross_px: Vector2 = root.get_canvas_transform() * cross_w
	print("beam_turns_shot: %s err=%d маяк=%d воздух=%d сегментов=%d размер=%dx%d зум=%.2f крест→луч=%.1f разрывы=%s крест_мир=%s крест_px=%s" % [
			_out, err, got, air, world.beams.segments.size(), img.get_width(), img.get_height(), zoom, dist,
			gaps if gaps != "" else "нет", str(cross_w), str(cross_px)])
	_dump_legs(world)
	var breaks: int = world.beams.break_points.size() if world.beams != null and "break_points" in world.beams else 0
	var ok_shot: bool = err == OK and (got == 1 if want_pharos else breaks > 0)
	quit(0 if ok_shot and px_ok else 1)


## Горелка, три зеркала, маяк. Возвращает клетку маяка.
func _place_path(world: Node, origin: Vector2i) -> Vector2i:
	var m1: Vector2i = origin + Vector2i(6, 0)
	var m2: Vector2i = m1 + Vector2i(0, -6)
	var m3: Vector2i = m2 + Vector2i(6, 0)
	var sink: Vector2i = m3 + Vector2i(0, 6)
	var mb: GDScript = load("res://scripts/machines/machine_base.gd")
	if not mb.place_machine("Burner", origin):
		push_error("beam_turns_shot: горелка не встала")
		quit(1)
		return Vector2i(-1, -1)
	var burner = world.machines[origin]
	burner.dir = 0
	burner.add_fuel(IDs.I.COAL, 3)
	for cell in [m1, m2, m3]:
		if not mb.place_machine("Mirror", cell):
			push_error("beam_turns_shot: зеркало не встало %s" % str(cell))
			quit(1)
			return Vector2i(-1, -1)
	world.machines[m1].dir = 0
	world.machines[m2].dir = 0
	world.machines[m3].dir = 1
	if not mb.place_machine("Pharos", sink):
		push_error("beam_turns_shot: маяк не встал")
		quit(1)
		return Vector2i(-1, -1)
	world.beams.note_machines()
	world.beams.rebuild()
	world._apply_beam_lights()
	# Кадр приёмки: маяк должен читаться ночью. В игре z не меняем.
	var pharos = world.machines.get(sink)
	if pharos != null:
		pharos.z_as_relative = false
		pharos.z_index = 42
	return sink


## Два зеркала и стена через две клетки. Возвращает клетку стены.
func _place_wall(world: Node, origin: Vector2i) -> Vector2i:
	var m1: Vector2i = origin + Vector2i(6, 0)
	var m2: Vector2i = m1 + Vector2i(0, -6)
	var wall: Vector2i = m2 + Vector2i(3, 0)
	var mb: GDScript = load("res://scripts/machines/machine_base.gd")
	if not mb.place_machine("Burner", origin):
		push_error("beam_turns_shot: горелка не встала")
		quit(1)
		return wall
	var burner = world.machines[origin]
	burner.dir = 0
	burner.add_fuel(IDs.I.COAL, 3)
	for cell in [m1, m2]:
		if not mb.place_machine("Mirror", cell):
			push_error("beam_turns_shot: зеркало не встало %s" % str(cell))
			quit(1)
			return wall
	world.machines[m1].dir = 0
	world.machines[m2].dir = 0
	world.set_tile(wall.x, wall.y, IDs.T.STONE)
	world.beams.note_machines()
	world.beams.rebuild()
	world._apply_beam_lights()
	print("стена клетка=%s мир=%s tile=%s solid=%s" % [
			str(wall), str(world.cell_to_world(wall)), str(world.get_tile(wall.x, wall.y)),
			str(world.is_solid_cell(wall))])
	return wall


const _DIR: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1), Vector2i(1, -1),
]


func _break_face(world: Node, cell: Vector2i) -> Vector2:
	for s in world.beams.segments:
		var step: Vector2i = _DIR[int(s["dir"]) & 7]
		if s["to"] == cell:
			return Vector2(step)
	for s in world.beams.segments:
		var step: Vector2i = _DIR[int(s["dir"]) & 7]
		if s["to"] + step == cell:
			return Vector2(step)
	return Vector2.ZERO


## Центр креста на кадре. После фикса — WorldFX.break_mark_at.
## На 7a6cef9 помощника нет: та же формула, что рисовала искра (центр минус грань).
func _cross_world(world: Node, cell: Vector2i) -> Vector2:
	var fx: GDScript = load("res://scripts/ui/world_fx.gd")
	if fx.has_method("break_mark_at"):
		var points: Array = world.beams.break_points if world.beams != null and "break_points" in world.beams else []
		for p in points:
			if p["cell"] == cell:
				return fx.break_mark_at(cell, str(p["reason"]))
	var center: Vector2 = world.cell_to_world(cell)
	var face: Vector2 = _break_face(world, cell)
	var tile: float = float(world.get("TILE"))
	var points2: Array = world.beams.break_points if world.beams != null and "break_points" in world.beams else []
	for p in points2:
		if p["cell"] == cell and str(p["reason"]) == "wall" and face != Vector2.ZERO:
			return center - face * tile * 0.5
	return center


## Ближайший пиксель полного цвета луча к центру креста, экранные px.
func _beam_to_cross(img: Image, world: Node, cell: Vector2i) -> float:
	var canvas: Transform2D = root.get_canvas_transform()
	var px: Vector2 = canvas * _cross_world(world, cell)
	var beam: Color = Color("#FFD86E")
	var best: float = 1.0e9
	var r: int = 96
	var x0: int = int(floor(px.x)) - r
	var y0: int = int(floor(px.y)) - r
	for y in range(y0, y0 + r * 2 + 1):
		for x in range(x0, x0 + r * 2 + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			if not _full_beam(img.get_pixel(x, y), beam):
				continue
			var d: float = Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(px)
			if d < best:
				best = d
	return best if best < 1.0e8 else -1.0


## Вдоль каждой ноги нет тёмного разрыва длиннее половины клетки.
## Возвращает строку провалов (пусто — ноги целые).
func _leg_gaps(img: Image, world: Node) -> String:
	var canvas: Transform2D = root.get_canvas_transform()
	var tile: float = float(world.get("TILE"))
	var zoom: float = canvas.get_scale().x
	var half: float = tile * zoom * 0.5
	var beam: Color = Color("#FFD86E")
	var fx: GDScript = load("res://scripts/ui/world_fx.gd")
	var use_span: bool = fx.has_method("beam_span")
	var bad: PackedStringArray = PackedStringArray()
	var i: int = 0
	for s in world.beams.segments:
		var a_w: Vector2
		var b_w: Vector2
		if use_span:
			var span: Dictionary = fx.beam_span(s)
			a_w = span["a"]
			b_w = span["b"]
		else:
			# 7a6cef9: линия от центра from до центра to, плюс полклетки к машине.
			var step: Vector2i = _DIR[int(s["dir"]) & 7]
			a_w = world.cell_to_world(s["from"])
			b_w = world.cell_to_world(s["to"])
			if world.machines.has(s["to"] + step):
				b_w += Vector2(step) * tile * 0.5
		# Клетка источника закрыта окном машины. Линия проверяется с границы
		# следующей клетки — там луч уже в воздухе.
		var skip: float = tile
		if a_w.distance_to(b_w) > skip + 1.0:
			a_w = a_w.move_toward(b_w, skip)
		var a: Vector2 = canvas * a_w
		var b: Vector2 = canvas * b_w
		var run: float = 0.0
		var worst: float = 0.0
		var steps: int = int(ceil(a.distance_to(b))) + 1
		for k in range(steps + 1):
			var t: float = float(k) / float(maxi(1, steps))
			# Центр полосы 4 px мира на зуме 1.5 — между пикселями. Смотрим
			# центр пикселя, иначе семплер идёт по краю линии и видит разрыв.
			var p: Vector2 = (a.lerp(b, t) + Vector2(0.5, 0.5)).floor()
			var lit: bool = _near_full(img, p, beam, 2)
			if lit:
				worst = maxf(worst, run)
				run = 0.0
			else:
				run += a.distance_to(b) / float(maxi(1, steps))
		worst = maxf(worst, run)
		if worst > half:
			bad.append("%d:%.1f" % [i, worst])
		i += 1
	return " ".join(bad)


func _near_full(img: Image, p: Vector2, beam: Color, rad: int) -> bool:
	var x0: int = int(floor(p.x)) - rad
	var y0: int = int(floor(p.y)) - rad
	for y in range(y0, y0 + rad * 2 + 1):
		for x in range(x0, x0 + rad * 2 + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			if Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(p) > float(rad) + 0.5:
				continue
			if _full_beam(img.get_pixel(x, y), beam):
				return true
	return false


func _full_beam(c: Color, beam: Color) -> bool:
	return absf(c.r - beam.r) <= FULL_EPS and absf(c.g - beam.g) <= FULL_EPS and absf(c.b - beam.b) <= FULL_EPS


func _dump_legs(world: Node) -> void:
	var tile: float = float(world.get("TILE"))
	var i: int = 0
	for s in world.beams.segments:
		var step: Vector2i = _DIR[int(s["dir"]) & 7]
		var a_w: Vector2 = world.cell_to_world(s["from"])
		var b_w: Vector2 = world.cell_to_world(s["to"])
		if world.machines.has(s["to"] + step):
			b_w += Vector2(step) * tile * 0.5
		var face: Vector2 = Vector2(step)
		var wall_b: Vector2 = world.cell_to_world(s["to"]) - face * tile * 0.5
		print("нога %d from=%s to=%s dir=%s a=%s b_центр=%s грань=%s strength=%.3f" % [
				i, str(s["from"]), str(s["to"]), str(step), str(a_w), str(b_w), str(wall_b), float(s["strength"])])
		i += 1
	if world.beams != null:
		for p in world.beams.break_points:
			print("обрыв %s %s" % [str(p.get("cell")), str(p.get("reason"))])


func _fog_node() -> Node:
	# FogLayer — class_name поверх Node2D: get_class() остаётся Node2D, имени нет.
	for n in current_scene.get_children():
		var sc: Script = n.get_script()
		if sc != null and str(sc.resource_path).ends_with("fog_layer.gd"):
			return n
	return null


func _hide_hud() -> void:
	var ui: Node = root.get_node_or_null("UI")
	var hud: Node = ui.get("hud") if ui != null else null
	if hud == null:
		return
	hud.set("tutorial_step", 5)
	hud.set("tutorial_text", "")
	hud.set("hint_text", "")
	hud.set("notes", [])
	hud.set("tracker_title", "")
	hud.set("tracker_detail", "")
	hud.visible = false


func _clear(world: Node, a: Vector2i, b: Vector2i) -> void:
	for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
		for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
			if world.in_bounds(x, y):
				world.set_tile(x, y, IDs.T.AIR)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame
