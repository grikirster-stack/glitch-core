extends ScenarioBase
## Анализатор (ADR-001 § 4.2, #30; #169): один кристалл сгорает за 20 ± 1 с
## игрового времени (счётчик данных снят, produced растёт на 1). Кристалл
## закладывает игрок — E с кристаллом в хотбаре. Без второго кристалла
## produced не растёт; без питания анализатор стоит.

const TOLERANCE: float = 1.0


func run() -> void:
	player.invuln = 1.0e9
	var bx: int = World.beacon_cell.x
	var base: int = World.beacon_cell.y
	var an_cell: Vector2i = Vector2i(bx - 34, base + 6)
	var gen_cell: Vector2i = an_cell + Vector2i(4, 0)
	for x in range(an_cell.x - 3, gen_cell.x + 2):
		for y in range(an_cell.y - 3, an_cell.y + 2):
			World.set_tile(x, y, IDs.T.AIR)
	ok("анализатор поставлен", MachineBase.place_machine("Analyzer", an_cell))
	var an: Analyzer = World.machines.get(an_cell)
	if an == null:
		finish()
		return
	ok("анализатор принимает кристалл", an.input_accepts(IDs.I.CRYSTAL))
	ok("анализатор не берёт руду", an.receive_item(IDs.I.IRON_ORE, 1) == 1)

	# Без питания кристалл лежит, produced не растёт.
	an.receive_item(IDs.I.CRYSTAL, 1)
	await wait(1.0)
	ok("без питания анализатор стоит", an.crystals == 1 and an.produced == 0,
			"кристаллов %d, сожжено %d" % [an.crystals, an.produced])
	an.crystals = 0

	ok("ТЭЦ поставлена", MachineBase.place_machine("CoalGen", gen_cell))
	var gen: CoalGen = World.machines.get(gen_cell)
	if gen == null:
		finish()
		return
	gen.add_fuel(CoalGen.FUEL_MAX_UNITS)
	await wait(0.8)
	ok("анализатор под питанием", an.powered and is_equal_approx(an.efficiency, 1.0),
			"eff=%.2f" % an.efficiency)

	# Игрок: E с одним кристаллом у анализатора.
	player.inv.add(IDs.I.CRYSTAL, 1)
	player.inv.selected = _slot_of(IDs.I.CRYSTAL)
	player.global_position = World.cell_to_world(an_cell + Vector2i(-1, 0))
	aim(World.cell_to_world(an_cell + Vector2i(-2, -2)))
	var r0: int = an.produced
	hold(KEY_E)
	await wait_until(func() -> bool: return an.crystals > 0 or an.progress > 0.0, 2.0)
	var t0: float = Game.game_time
	release(KEY_E)
	clear_input()
	ok("кристалл заложен клавишей E", an.crystals > 0 or an.progress > 0.0)
	ok("кристалл ушёл из инвентаря", player.inv.count_of(IDs.I.CRYSTAL) == 0)
	var got: bool = await wait_until(func() -> bool: return an.produced > r0, 30.0)
	var took: float = Game.game_time - t0
	ok("кристалл сожжён", got and an.produced == r0 + 1, "сожжено %d → %d" % [r0, an.produced])
	ok("за 20 ± 1 с", got and absf(took - Balance.ANALYZER_PERIOD) <= TOLERANCE, "%.2f с" % took)
	await wait(1.5)
	ok("без второго кристалла produced не растёт", an.produced == r0 + 1)
	finish()


func _slot_of(id: int) -> int:
	for i in player.inv.slots.size():
		if player.inv.slots[i].id == id:
			return i
	return 0
