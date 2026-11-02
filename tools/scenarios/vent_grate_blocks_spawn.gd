extends ScenarioBase
## Решётка вентиляции (ADR-001 § 4.4, #31): решётка на вентиляции закрывает
## спавн из неё (World.vents_sealed, Threat.nearest_vents); копатель рядом
## ломает решётку (HP 40) примерно за 8 с — вентиляция снова «дышит».
## Решётку ставят только на вентиляцию.

const EXTRA_DX: Array = [14, 22, -24, 32]
const REQUESTS: int = 8

var _warned: Array = []


func run() -> void:
	player.invuln = 1.0e9
	Game.time_of_day = Balance.START_TIME
	Threat.reset()
	ok("в мире хватает вентиляций", World.vents.size() >= 10, "n=%d" % World.vents.size())
	# Свои вентиляции на поверхности рядом с героем — как в vent_spawn.
	var pc: Vector2i = World.world_to_cell(player.global_position)
	for dx in EXTRA_DX:
		var x: int = clampi(pc.x + int(dx), 2, World.W - 3)
		var c: Vector2i = Vector2i(x, int(World.surface[x]) - 1)
		if World.get_tile_v(c) == IDs.T.AIR and not World.vents.has(c):
			World.vents.append(c)
	var near: Array[Vector2i] = Threat.nearest_vents(player.global_position)
	ok("есть кандидаты в вентиляции", near.size() >= 2, str(near))
	if near.is_empty():
		finish()
		return

	# 1. Решётка — только на вентиляцию; на вентиляции она запечатывает.
	var off: Vector2i = near[0] + Vector2i(0, -2)
	ok("решётку нельзя поставить мимо вентиляции", not World.tile_place_ok(off, IDs.T.VENT_GRATE))
	var v: Vector2i = near[0]
	ok("на вентиляцию — можно", World.tile_place_ok(v, IDs.T.VENT_GRATE))
	World.set_tile(v.x, v.y, IDs.T.VENT_GRATE)
	ok("вентиляция запечатана", World.is_vent_sealed(v)
			and is_equal_approx(float(World.vents_sealed[v]), Balance.GRATE_HP),
			"HP %s" % str(World.vents_sealed.get(v)))
	ok("запечатанная выбыла из кандидатов", not Threat.nearest_vents(player.global_position).has(v))

	# 2. Запечатаны все — из вентиляций никто не выходит (поиск пещеры).
	for w in World.vents:
		if World.get_tile_v(w) == IDs.T.AIR:
			World.set_tile(w.x, w.y, IDs.T.VENT_GRATE)
	ok("все вентиляции запечатаны", World.vents_sealed.size() >= World.vents.size(),
			"%d из %d" % [World.vents_sealed.size(), World.vents.size()])
	Threat.vent_warning.connect(_on_warning)
	for i in REQUESTS:
		Threat.request_spawn("echo")
	ok("ни одного телеграфа из вентиляций", _warned.is_empty() and Threat.pending.is_empty(),
			"телеграфов %d" % _warned.size())
	Threat.vent_warning.disconnect(_on_warning)
	for p in get_tree().get_nodes_in_group("phantom"):
		p.get_parent().remove_child(p)
		p.queue_free()
	await await_frame()

	# 3. Копатель в закрытом кармане с решёткой — грызёт её ~8 с.
	var pocket: Vector2i = _find_pocket()
	ok("найдено место под карман", pocket.x >= 0, str(pocket))
	if pocket.x < 0:
		finish()
		return
	var g: Vector2i = _build_pocket(pocket)
	ok("решётка кармана запечатана", World.is_vent_sealed(g))
	# Ночь: далёкий от героя копатель не растворяется (DESPAWN_DIST_NIGHT);
	# директор угрозы в сценарии молчит.
	Game.time_of_day = 0.8
	var bur: Node = spawn_phantom_at(Vector2(float((g.x + 1) * World.TILE) + 8.0,
			float((g.y + 1) * World.TILE) - 12.0), "burrower")
	ok("копатель появился", bur != null)
	var t0: int = Time.get_ticks_msec()
	var broke: bool = await wait_until(func(): return not World.is_vent_sealed(g), Balance.GRATE_BREAK_TIME + 4.0)
	var secs: float = float(Time.get_ticks_msec() - t0) / 1000.0
	ok("копатель сломал решётку", broke, "%.1f с" % secs)
	ok("решётка держится ≈ 8 с", secs >= Balance.GRATE_BREAK_TIME - 1.0 and secs <= Balance.GRATE_BREAK_TIME + 2.0,
			"%.1f с" % secs)
	ok("на месте решётки снова воздух", World.get_tile_v(g) == IDs.T.AIR)
	if bur != null and is_instance_valid(bur):
		bur.get_parent().remove_child(bur)
		bur.queue_free()
	# Карман — вентиляция: после поломки решётки она снова в кандидатах
	# (смотрим от точки рядом с ней, чтобы попасть в кольцо дистанций).
	var probe: Vector2 = World.cell_to_world(g) + Vector2(Balance.VENT_SPAWN_MIN_PX + 8.0, 0.0)
	ok("сломанная решётка — вентиляция снова открыта", Threat.nearest_vents(probe, 64).has(g))
	finish()


func _on_warning(cell: Vector2i) -> void:
	_warned.append(cell)


## Карман 2×2 в стальной стене (копатель её не роет): левая нижняя клетка —
## вентиляция с решёткой, копатель — справа от неё. Возвращает клетку решётки.
func _build_pocket(o: Vector2i) -> Vector2i:
	for y in 4:
		for x in 4:
			World.set_tile(o.x + x, o.y + y, IDs.T.STEEL_WALL)
	for y in [1, 2]:
		for x in [1, 2]:
			World.set_tile(o.x + int(x), o.y + int(y), IDs.T.AIR)
	var g: Vector2i = o + Vector2i(1, 2)
	if not World.vents.has(g):
		World.vents.append(g)
	World.set_tile(g.x, g.y, IDs.T.VENT_GRATE)
	return g


## Тёмное место под землёй вдали от героя (копатель убегает от света > 0.8).
func _find_pocket() -> Vector2i:
	for dx in [60, -60, 80, -80, 100, -100]:
		var x: int = World.beacon_cell.x + int(dx)
		if x < 4 or x + 4 > World.W - 4:
			continue
		var y: int = int(World.surface[x]) + 18
		if y + 4 >= World.H - 6:
			continue
		var c: Vector2i = Vector2i(x, y)
		if World.light_at(c + Vector2i(1, 2)) < 0.6:
			return c
	return Vector2i(-1, -1)
