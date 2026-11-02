extends ScenarioBase
## Глубинный бур (ADR-001 § 4.2, #30): достаёт руду с глубины 40 клеток, куда
## обычная буровая (16 клеток) не дотягивается. Обе шахты пустые до дна,
## на дне — железная руда; обычная буровая забирает медь с глубины 16.

const DEPTH: int = Balance.DEEP_DRILL_REACH


func run() -> void:
	player.invuln = 1.0e9
	var bx: int = World.beacon_cell.x
	var base: int = World.beacon_cell.y
	var gen_cell: Vector2i = Vector2i(bx - 36, base + 6)
	var deep_cell: Vector2i = gen_cell + Vector2i(2, 0)
	var drill_cell: Vector2i = gen_cell + Vector2i(5, 0)
	ok("шахта помещается в мир", deep_cell.y + DEPTH < World.H - 3, "y=%d H=%d" % [deep_cell.y + DEPTH, World.H])
	for x in range(gen_cell.x - 1, drill_cell.x + 3):
		for y in range(gen_cell.y - 1, gen_cell.y + 2):
			World.set_tile(x, y, IDs.T.AIR)
	# Шахты: пусто до глубины DEPTH - 1, на дне — руда.
	for c in [deep_cell, drill_cell]:
		for dy in range(1, DEPTH):
			World.set_tile(c.x, c.y + dy, IDs.T.AIR)
		World.set_tile(c.x, c.y + DEPTH, IDs.T.IRON_ORE)
	World.set_tile(drill_cell.x, drill_cell.y + Balance.DRILL_REACH, IDs.T.COPPER_ORE)

	var ok_place: bool = MachineBase.place_machine("CoalGen", gen_cell)
	ok_place = MachineBase.place_machine("DeepDrill", deep_cell) and ok_place
	ok_place = MachineBase.place_machine("Chest", deep_cell + Vector2i(1, 0)) and ok_place
	ok_place = MachineBase.place_machine("Drill", drill_cell) and ok_place
	ok_place = MachineBase.place_machine("Chest", drill_cell + Vector2i(1, 0)) and ok_place
	ok("буры, сундуки и ТЭЦ поставлены", ok_place)
	var gen: CoalGen = World.machines.get(gen_cell)
	var deep: DeepDrill = World.machines.get(deep_cell)
	var drill: Drill = World.machines.get(drill_cell)
	var deep_box: Chest = World.machines.get(deep_cell + Vector2i(1, 0))
	var drill_box: Chest = World.machines.get(drill_cell + Vector2i(1, 0))
	if not ok_place or gen == null or deep == null or drill == null:
		finish()
		return
	gen.add_fuel(CoalGen.FUEL_MAX_UNITS)
	ok("глубинный бур тянет 4 мощности", is_equal_approx(deep.power_draw, 4.0), "%.1f" % deep.power_draw)
	ok("глубинный бур: такт 1.2 с, глубина 40", is_equal_approx(deep.cycle(), 1.2) and deep.reach() == DEPTH)
	ok("цель глубинного бура — дно на 40", deep.harvest_target() == deep_cell + Vector2i(0, DEPTH),
			str(deep.harvest_target()))

	var got: bool = await wait_until(func() -> bool: return _count(deep_box, IDs.I.IRON_ORE) > 0, 6.0)
	ok("руда с глубины 40 в сундуке", got, "руды %d" % _count(deep_box, IDs.I.IRON_ORE))
	ok("тайл на глубине 40 выкопан", World.get_tile_v(deep_cell + Vector2i(0, DEPTH)) == IDs.T.AIR)
	await wait_until(func() -> bool: return _count(drill_box, IDs.I.COPPER_ORE) > 0, 6.0)
	await wait(Balance.DRILL_CYCLE + 0.5)
	ok("обычная буровая достаёт до 16", _count(drill_box, IDs.I.COPPER_ORE) == 1,
			"меди %d" % _count(drill_box, IDs.I.COPPER_ORE))
	ok("обычная буровая до 40 не достаёт",
			World.get_tile_v(drill_cell + Vector2i(0, DEPTH)) == IDs.T.IRON_ORE
			and _count(drill_box, IDs.I.IRON_ORE) == 0)
	finish()


func _count(ch: Chest, id: int) -> int:
	var n: int = 0
	if ch == null:
		return 0
	for s in ch.slots:
		if not s.is_empty() and s.id == id:
			n += s.count
	return n
