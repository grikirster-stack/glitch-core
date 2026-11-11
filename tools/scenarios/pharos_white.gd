extends ScenarioBase
## Маяк под белым (ADR-005 § 5, #168).
##
## Три горелки в смеситель, белый — в маяк. 10 клеток руды в породе в радиусе
## 8 становятся разведанными за 2 с. Камень рядом — нет. Печатает мкс
## reveal_cells на 50 клетках.


func run() -> void:
	player.invuln = 1.0e9
	var floor_y: int = stand_in_corridor(1)
	await wait(0.3)
	# Глубже обзора героя: туман у базы уже открыт.
	var origin: Vector2i = Vector2i(80, 90)
	_clear(origin + Vector2i(-8, -8), 40, 20)
	player.global_position = World.cell_to_world(Vector2i(origin.x, origin.y + 24))
	var mix: Vector2i = origin + Vector2i(4, 0)
	ok("смеситель поставлен", MachineBase.place_machine("Mixer", mix))
	var red: Burner = _burn(Vector2i(mix.x - 3, mix.y), IDs.I.COAL, 0)
	var green: Burner = _burn(Vector2i(mix.x, mix.y - 3), IDs.I.COPPER_ORE, 1)
	var blue: Burner = _burn(Vector2i(mix.x, mix.y + 3), IDs.I.CRYSTAL, 3)
	var pc: Vector2i = mix + Vector2i(5, 0)
	ok("маяк поставлен", MachineBase.place_machine("Pharos", pc))
	var pharos: Pharos = World.machines.get(pc) as Pharos
	if red == null or green == null or blue == null or pharos == null:
		finish()
		return
	_flush()
	ok("белый дошёл смесью", pharos.color == Beams.W and pharos.active,
			"цвет %d, луч %d" % [pharos.color, World.beams.color_at(pc + Vector2i(-1, 0))])

	var ores: Array[Vector2i] = []
	var kinds: Array[int] = [IDs.T.COAL_ORE, IDs.T.COPPER_ORE, IDs.T.IRON_ORE, IDs.T.CRYSTAL_ORE, IDs.T.SCRAP_ORE]
	for i in 10:
		var c: Vector2i = pc + Vector2i(2 + (i % 5), 1 + int(i / 5))
		World.set_tile(c.x, c.y, kinds[i % kinds.size()])
		World.explored[c.y * World.W + c.x] = 0
		ores.append(c)
	var stone: Vector2i = pc + Vector2i(3, 3)
	World.set_tile(stone.x, stone.y, IDs.T.STONE)
	World.explored[stone.y * World.W + stone.x] = 0
	var far: Vector2i = pc + Vector2i(Balance.PHAROS_WHITE_RADIUS + 2, 0)
	World.set_tile(far.x, far.y, IDs.T.COAL_ORE)
	World.explored[far.y * World.W + far.x] = 0

	var opened: bool = await wait_until(func() -> bool:
		for c in ores:
			if not World.is_explored(c):
				return false
		return true, 2.2)
	var n: int = 0
	for c in ores:
		if World.is_explored(c):
			n += 1
	print("  [замер] белый открыл %d/10 клеток руды за ≤ 2 с (revealed %d)" % [n, pharos.revealed])
	ok("10 клеток руды разведаны за 2 с", opened and n == 10, "%d" % n)
	ok("камень не открыт", not World.is_explored(stone))
	ok("руда за радиусом 8 не открыта", not World.is_explored(far))

	_bench()
	finish()


func _bench() -> void:
	var list: Array = []
	var x0: int = 200
	var y0: int = 100
	for i in 50:
		var c: Vector2i = Vector2i(x0 + (i % 10), y0 + int(i / 10))
		if World.in_bounds(c.x, c.y):
			World.explored[c.y * World.W + c.x] = 0
			list.append(c)
	var t0: int = Time.get_ticks_usec()
	var opened: int = World.reveal_cells(list)
	var us: int = Time.get_ticks_usec() - t0
	print("  [замер] reveal_cells на %d клетках: %d мкс, открыто %d" % [list.size(), us, opened])
	ok("reveal_cells 50 клеток ≤ 500 мкс", us <= 500 and opened == list.size(), "%d мкс" % us)


func _burn(cell: Vector2i, fuel: int, dir: int) -> Burner:
	if not MachineBase.place_machine("Burner", cell):
		return null
	var b: Burner = World.machines.get(cell) as Burner
	if b == null:
		return null
	while b.dir != dir:
		b.turn()
	b.add_fuel(fuel, 2)
	return b


func _clear(origin: Vector2i, w: int, h: int) -> void:
	for x in range(origin.x, origin.x + w):
		for y in range(origin.y, origin.y + h):
			if World.in_bounds(x, y):
				World.set_tile(x, y, IDs.T.AIR)


func _flush() -> void:
	if World.beams != null:
		World.beams.rebuild()
		World._apply_beam_lights()
