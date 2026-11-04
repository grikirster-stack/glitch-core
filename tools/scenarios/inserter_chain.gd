extends ScenarioBase
## Манипулятор (ADR-001 § 4.2, #30): сундук → манипулятор → конвейер →
## плавильня → конвейер → сундук. 10 слитков за ≤ 40 с игрового времени.
## Заодно: фильтр (песок остаётся в сундуке), выдача готового станком через
## take_output (плавильня без ленты → манипулятор → сундук, на землю ничего),
## поворот ПКМ и фильтр клавишей E — через шов игрока.

const TARGET: int = 10
const LIMIT_SECS: float = 40.0


func run() -> void:
	player.invuln = 1.0e9
	var bx: int = World.beacon_cell.x
	var base: int = World.beacon_cell.y
	var c0: Vector2i = Vector2i(bx - 36, base + 6)   ## сундук-источник
	for x in range(c0.x - 1, c0.x + 8):
		for y in range(c0.y - 1, c0.y + 6):
			World.set_tile(x, y, IDs.T.AIR)
	# Линия: сундук, манипулятор, лента, плавильня, лента, сундук. ТЭЦ — под ней,
	# через ряд, чтобы плавильня не отдавала слитки в неё и не на входную ленту.
	var ok_place: bool = true
	ok_place = MachineBase.place_machine("Chest", c0) and ok_place
	ok_place = MachineBase.place_machine("Inserter", c0 + Vector2i(1, 0)) and ok_place
	ok_place = MachineBase.place_machine("Belt", c0 + Vector2i(2, 0)) and ok_place
	ok_place = MachineBase.place_machine("Smelter", c0 + Vector2i(3, 0)) and ok_place
	ok_place = MachineBase.place_machine("Belt", c0 + Vector2i(4, 0)) and ok_place
	ok_place = MachineBase.place_machine("Chest", c0 + Vector2i(5, 0)) and ok_place
	ok_place = MachineBase.place_machine("CoalGen", c0 + Vector2i(3, 2)) and ok_place
	ok("линия поставлена", ok_place)
	var src: Chest = World.machines.get(c0)
	var ins: Inserter = World.machines.get(c0 + Vector2i(1, 0))
	var sm: Smelter = World.machines.get(c0 + Vector2i(3, 0))
	var dst: Chest = World.machines.get(c0 + Vector2i(5, 0))
	var gen: CoalGen = World.machines.get(c0 + Vector2i(3, 2))
	if not ok_place or src == null or ins == null or sm == null or dst == null or gen == null:
		finish()
		return
	for c in [c0 + Vector2i(2, 0), c0 + Vector2i(4, 0)]:
		(World.belts[c] as Belt).dir = 0
	gen.add_fuel(CoalGen.FUEL_MAX_UNITS)

	# Шов игрока: ПКМ по манипулятору поворачивает его, четыре раза — круг.
	player.global_position = World.cell_to_world(c0 + Vector2i(1, 3))
	aim(World.cell_to_world(c0 + Vector2i(1, 0)))
	press_mouse(MOUSE_BUTTON_RIGHT)
	await wait_until(func() -> bool: return ins.dir != 0, 2.0)
	var dir_first: int = ins.dir
	await wait(0.5)   # кнопка удержана ещё ~3 периода повтора (0,16 с): по кругу крутить нельзя
	release_mouse(MOUSE_BUTTON_RIGHT)
	ok("ПКМ поворачивает манипулятор", dir_first == 1, "dir=%d" % dir_first)
	ok("удержание ПКМ — один поворот на нажатие", ins.dir == dir_first, "dir=%d → %d" % [dir_first, ins.dir])
	ins.dir = 0

	# Фильтр: E с рудой в руке — только руда; песок в сундуке остаётся.
	player.inv.selected = _slot_of(IDs.I.COPPER_ORE)
	hold(KEY_E)
	await wait_until(func() -> bool: return ins.filter != IDs.I.NONE, 2.0)
	release(KEY_E)
	ok("E с рудой ставит фильтр", ins.filter == IDs.I.COPPER_ORE, "filter=%d" % ins.filter)
	player.global_position = World.spawn_point
	clear_input()

	src.receive_item(IDs.I.SAND, 6)
	src.receive_item(IDs.I.COPPER_ORE, TARGET + 2)
	await wait(0.5)
	ok("манипулятор под питанием", ins.powered and is_equal_approx(ins.efficiency, 1.0),
			"eff=%.2f" % ins.efficiency)
	var t0: float = Game.game_time
	var got: bool = await wait_until(func() -> bool: return _count(dst, IDs.I.COPPER_INGOT) >= TARGET,
			LIMIT_SECS + 10.0)
	var took: float = Game.game_time - t0
	var ingots: int = _count(dst, IDs.I.COPPER_INGOT)
	ok("10 слитков дошли до сундука", got, "слитков %d" % ingots)
	ok("за ≤ 40 с игрового времени", got and took <= LIMIT_SECS, "%.1f с" % took)
	if took > 0.0:
		print("  [замер] линия сундук→манипулятор→плавильня→сундук: %.1f слитков/мин (%d за %.1f с)"
				% [float(ingots) / took * 60.0, ingots, took])
	ok("песок остался в сундуке (фильтр)", _count(src, IDs.I.SAND) == 6, "песка %d" % _count(src, IDs.I.SAND))
	ok("плавильня не получила песок", int(sm.stock.get(IDs.I.SAND, 0)) == 0)

	# Готовое из станка через take_output: плавильня без ленты отдаёт манипулятору.
	await _take_output_case(c0 + Vector2i(0, 4))
	finish()


## Плавильня → манипулятор → сундук: слитки не падают на землю, а уходят
## манипулятором. Площадка — ряд под основной линией, в радиусе той же ТЭЦ.
func _take_output_case(c: Vector2i) -> void:
	var ok_place: bool = MachineBase.place_machine("Smelter", c)
	ok_place = MachineBase.place_machine("Inserter", c + Vector2i(1, 0)) and ok_place
	ok_place = MachineBase.place_machine("Chest", c + Vector2i(2, 0)) and ok_place
	ok("цепочка take_output поставлена", ok_place)
	var sm: Smelter = World.machines.get(c)
	var ins: Inserter = World.machines.get(c + Vector2i(1, 0))
	var box: Chest = World.machines.get(c + Vector2i(2, 0))
	if not ok_place or sm == null or ins == null or box == null:
		return
	var items_before: int = _ground_items()
	sm.receive_item(IDs.I.COPPER_ORE, 3)
	var got: bool = await wait_until(func() -> bool: return _count(box, IDs.I.COPPER_INGOT) >= 3, 15.0)
	ok("станок отдал готовое манипулятору (take_output)", got,
			"слитков %d" % _count(box, IDs.I.COPPER_INGOT))
	ok("на землю ничего не выпало", _ground_items() == items_before,
			"предметов на земле %d → %d" % [items_before, _ground_items()])


func _count(ch: Chest, id: int) -> int:
	var n: int = 0
	for s in ch.slots:
		if not s.is_empty() and s.id == id:
			n += s.count
	return n


func _slot_of(id: int) -> int:
	for i in player.inv.slots.size():
		if player.inv.slots[i].id == id:
			return i
	return 0


func _ground_items() -> int:
	var n: int = 0
	for ch in scene.get_children():
		if ch is ItemEntity:
			n += 1
	return n
