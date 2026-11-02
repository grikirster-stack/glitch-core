extends ScenarioBase
## Уголь с конвейера (ADR-001 § 4.3, #25): уголь, положенный на ленту, доезжает
## до ТЭЦ и попадает в топку; не-уголь ТЭЦ не берёт; полная топка уголь не
## «съедает» — он остаётся на ленте.


func run() -> void:
	player.invuln = 1.0e9
	var bx: int = World.beacon_cell.x
	var base: int = World.beacon_cell.y
	var start: Vector2i = Vector2i(bx - 34, base + 6)
	var gen_cell: Vector2i = start + Vector2i(3, 0)
	for x in range(start.x - 1, gen_cell.x + 2):
		for y in range(start.y - 1, start.y + 2):
			World.set_tile(x, y, IDs.T.AIR)
	# Три ленты вправо → ТЭЦ.
	var belts: Array = []
	for i in 3:
		var c: Vector2i = start + Vector2i(i, 0)
		MachineBase.place_machine("Belt", c)
		var b: Belt = World.belts.get(c)
		if b:
			b.dir = 0
		belts.append(b)
	ok("конвейер поставлен", not belts.has(null))
	ok("ТЭЦ поставлена", MachineBase.place_machine("CoalGen", gen_cell))
	var gen: CoalGen = World.machines.get(gen_cell)
	if gen == null or belts.has(null):
		finish()
		return
	ok("ТЭЦ без угля не работает", gen.fuel <= 0.0 and not gen.power_active)
	ok("ТЭЦ принимает уголь", gen.input_accepts(IDs.I.COAL))

	# Уголь на начало ленты — он должен доехать до топки.
	belts[0].add_item(IDs.I.COAL, 1)
	var got: bool = await wait_until(func() -> bool: return gen.fuel > 0.0, 8.0)
	ok("уголь с конвейера попал в топку", got, "fuel=%.1f" % gen.fuel)
	await wait(0.3)
	ok("ТЭЦ работает на угле с ленты", gen.power_active)
	ok("лента пуста", _belt_items(belts) == 0, "предметов %d" % _belt_items(belts))

	# Не-уголь ТЭЦ не берёт: руда остаётся на ленте.
	belts[2].add_item(IDs.I.IRON_ORE, 1)
	await wait(1.5)
	ok("руду ТЭЦ не взяла", belts[2].items.size() == 1 and int(belts[2].items[0]["id"]) == IDs.I.IRON_ORE)
	belts[2].items.clear()

	# Полная топка: уголь не пропадает, ждёт на ленте.
	gen.fuel = CoalGen.BURN * float(CoalGen.FUEL_MAX_UNITS)
	belts[2].add_item(IDs.I.COAL, 1)
	await wait(1.5)
	ok("полная топка уголь не съела", _belt_items(belts) == 1, "на ленте %d" % _belt_items(belts))
	ok("топка не переполнена", gen.fuel <= CoalGen.BURN * float(CoalGen.FUEL_MAX_UNITS))
	finish()


func _belt_items(belts: Array) -> int:
	var n: int = 0
	for b in belts:
		n += (b as Belt).items.size()
	return n
