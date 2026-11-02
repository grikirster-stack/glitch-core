extends ScenarioBase
## Плавильня и замок технологий (#57).
##
## 1. Без питания горнило не светится: цвет горнила (Smelter.furnace_color) —
##    ровный тёмный в любой момент времени; под питанием — пульсирует.
## 2. Вход запертого рецепта станок не принимает: медный слиток нужен плавильне
##    только для проката меди (T1), детали сборщика — только рецептам T1+.
##    До T1 слиток не берут ни receive_item, ни манипулятор (#30), ни E игрока;
##    после открытия T1 — берут все три пути.
##
## Линия: сундук → манипулятор → плавильня, ТЭЦ через три клетки. Игрок встаёт
## справа от плавильни — дальше 40 px от сундука и ТЭЦ, чтобы E шла в станок.

## Моменты времени для цвета горнила: 0 и пик синуса (sin(262 * 0.006) ≈ 1).
const T_LOW: int = 0
const T_PEAK: int = 262
const INGOTS: int = 4


func run() -> void:
	player.invuln = 1.0e9
	var bx: int = World.beacon_cell.x
	var base: int = World.beacon_cell.y
	var c0: Vector2i = Vector2i(bx - 36, base + 6)   ## сундук-источник
	var dark_cell: Vector2i = c0 + Vector2i(-14, 0)  ## плавильня вне радиуса ТЭЦ
	var asm_cell: Vector2i = dark_cell + Vector2i(2, 0)
	for x in range(dark_cell.x - 1, c0.x + 9):
		for y in range(c0.y - 2, c0.y + 2):
			World.set_tile(x, y, IDs.T.AIR)
	ok("новый забег: T1 закрыт", not Tech.is_unlocked("T1"), str(Tech.unlocked))

	# ---- Горнило без питания -------------------------------------------------
	ok("тёмная плавильня и сборщик поставлены", MachineBase.place_machine("Smelter", dark_cell)
			and MachineBase.place_machine("Assembler", asm_cell))
	var dark: Smelter = World.machines.get(dark_cell)
	var asm: Assembler = World.machines.get(asm_cell)
	if dark == null or asm == null:
		finish()
		return
	await wait(0.5)
	ok("плавильня без питания", not dark.powered)
	ok("без питания горнило тёмное", dark.furnace_color(T_LOW) == Smelter.FURNACE_COLD
			and dark.furnace_color(T_PEAK) == Smelter.FURNACE_COLD,
			"%s / %s" % [dark.furnace_color(T_LOW), dark.furnace_color(T_PEAK)])
	ok("без питания перерисовки каждый кадр нет", not dark.has_time_animation()
			and not asm.has_time_animation())

	# ---- Линия под питанием ----------------------------------------------------
	var ok_place: bool = true
	ok_place = MachineBase.place_machine("Chest", c0) and ok_place
	ok_place = MachineBase.place_machine("Inserter", c0 + Vector2i(1, 0)) and ok_place
	ok_place = MachineBase.place_machine("Smelter", c0 + Vector2i(2, 0)) and ok_place
	ok_place = MachineBase.place_machine("CoalGen", c0 + Vector2i(6, 0)) and ok_place
	ok("линия поставлена", ok_place)
	var src: Chest = World.machines.get(c0)
	var ins: Inserter = World.machines.get(c0 + Vector2i(1, 0))
	var sm: Smelter = World.machines.get(c0 + Vector2i(2, 0))
	var gen: CoalGen = World.machines.get(c0 + Vector2i(6, 0))
	if not ok_place or src == null or ins == null or sm == null or gen == null:
		finish()
		return
	ins.dir = 0
	gen.add_fuel(CoalGen.FUEL_MAX_UNITS)
	await wait_until(func() -> bool: return sm.powered and ins.powered, 2.0)
	ok("плавильня и манипулятор под питанием", sm.powered and ins.powered)
	ok("под питанием горнило пульсирует", sm.furnace_color(T_LOW) != sm.furnace_color(T_PEAK)
			and sm.furnace_color(T_LOW) != Smelter.FURNACE_COLD and sm.has_time_animation())

	# ---- Запертый вход: не принимается ------------------------------------------
	ok("медный слиток до T1 не принимается", not sm.input_accepts(IDs.I.COPPER_INGOT))
	ok("receive_item вернул всё", sm.receive_item(IDs.I.COPPER_INGOT, 2) == 2 and sm.stock.is_empty(),
			str(sm.stock))
	ok("стальная пластина до T2 не принимается", not sm.input_accepts(IDs.I.STEEL_PLATE))
	ok("железный слиток принимается (сталь — T0)", sm.input_accepts(IDs.I.IRON_INGOT))
	ok("руда принимается (T0)", sm.input_accepts(IDs.I.COPPER_ORE))
	ok("сборщик до T1 не берёт пластину и кристалл",
			not asm.input_accepts(IDs.I.COPPER_PLATE) and not asm.input_accepts(IDs.I.CRYSTAL)
			and asm.receive_item(IDs.I.COPPER_PLATE, 1) == 1)

	src.receive_item(IDs.I.COPPER_INGOT, INGOTS)
	await wait(1.5)
	ok("манипулятор не тащит запертый вход", _count(src, IDs.I.COPPER_INGOT) == INGOTS
			and sm.stock.is_empty() and ins.held == IDs.I.NONE,
			"в сундуке %d, в станке %s" % [_count(src, IDs.I.COPPER_INGOT), str(sm.stock)])

	# E игрока с медным слитком в руке — не загружается.
	player.inv.add(IDs.I.COPPER_INGOT, 2)
	player.inv.selected = _slot_of(IDs.I.COPPER_INGOT)
	player.global_position = World.cell_to_world(c0 + Vector2i(3, 0))
	aim(World.cell_to_world(c0 + Vector2i(3, -2)))
	hold(KEY_E)
	await wait(0.4)
	release(KEY_E)
	await wait(0.1)
	ok("E не загрузил запертый вход", player.inv.count_of(IDs.I.COPPER_INGOT) == 2 and sm.stock.is_empty(),
			"в руке %d, в станке %s" % [player.inv.count_of(IDs.I.COPPER_INGOT), str(sm.stock)])

	# ---- Открываем T1: вход принимается -----------------------------------------
	Game.research += Tech.cost("T1")
	ok("T1 открыт", Tech.unlock("T1") and Tech.is_unlocked("T1"))
	ok("после T1 медный слиток принимается", sm.input_accepts(IDs.I.COPPER_INGOT))
	ok("после T1 сборщик берёт пластину", asm.input_accepts(IDs.I.COPPER_PLATE)
			and asm.receive_item(IDs.I.COPPER_PLATE, 1) == 0)
	ok("стальная пластина до T2 всё ещё не принимается", not sm.input_accepts(IDs.I.STEEL_PLATE))

	player.global_position = World.cell_to_world(c0 + Vector2i(3, 0))
	hold(KEY_E)
	await wait_until(func() -> bool: return player.inv.count_of(IDs.I.COPPER_INGOT) == 0, 2.0)
	release(KEY_E)
	clear_input()
	ok("E загрузил слитки после T1", player.inv.count_of(IDs.I.COPPER_INGOT) == 0,
			"в руке %d" % player.inv.count_of(IDs.I.COPPER_INGOT))

	var moved: bool = await wait_until(func() -> bool: return _count(src, IDs.I.COPPER_INGOT) == 0, 10.0)
	ok("манипулятор перенёс слитки после T1", moved, "в сундуке %d" % _count(src, IDs.I.COPPER_INGOT))
	var rolled: bool = await wait_until(func() -> bool: return _ground_count(IDs.I.COPPER_PLATE) > 0, 10.0)
	ok("плавильня катает медную пластину", rolled)
	finish()


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


func _ground_count(id: int) -> int:
	var n: int = 0
	for ch in scene.get_children():
		if ch is ItemEntity and ch.item_id == id:
			n += ch.count
	return n
