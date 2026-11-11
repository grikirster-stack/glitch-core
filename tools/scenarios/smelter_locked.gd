extends ScenarioBase
## Плавильня и чертёж (#57, #169).
##
## 1. Без питания горнило не светится: цвет горнила (Smelter.furnace_color) —
##    ровный тёмный в любой момент времени; под питанием — пульсирует.
## 2. Рецепт без чертежа станок не принимает. Прокат меди открыт сразу;
##    стальная стена — только с чертежом. До чертежа стальную пластину не берут
##    ни receive_item, ни манипулятор, ни E; после выдачи чертежа — берут.
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
	ok("новый забег: чертежа стальной стены нет", not Game.has_blueprint(IDs.I.STEEL_WALL),
			str(Game.blueprints))

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

	# ---- Прокат открыт сразу; стена — только с чертежом -------------------------
	ok("медный слиток принимается сразу (прокат открыт)", sm.input_accepts(IDs.I.COPPER_INGOT))
	ok("стальная пластина без чертежа не принимается", not sm.input_accepts(IDs.I.STEEL_PLATE))
	ok("receive_item вернул стальную пластину", sm.receive_item(IDs.I.STEEL_PLATE, 2) == 2
			and sm.stock.is_empty(), str(sm.stock))
	ok("железный слиток принимается (сталь открыта)", sm.input_accepts(IDs.I.IRON_INGOT))
	ok("руда принимается", sm.input_accepts(IDs.I.COPPER_ORE))
	ok("сборщик сразу берёт пластину и кристалл", asm.input_accepts(IDs.I.COPPER_PLATE)
			and asm.input_accepts(IDs.I.CRYSTAL) and asm.receive_item(IDs.I.COPPER_PLATE, 1) == 0)

	src.receive_item(IDs.I.STEEL_PLATE, INGOTS)
	await wait(1.5)
	ok("манипулятор не тащит вход без чертежа", _count(src, IDs.I.STEEL_PLATE) == INGOTS
			and sm.stock.is_empty() and ins.held == IDs.I.NONE,
			"в сундуке %d, в станке %s" % [_count(src, IDs.I.STEEL_PLATE), str(sm.stock)])

	player.inv.add(IDs.I.STEEL_PLATE, 2)
	player.inv.selected = _slot_of(IDs.I.STEEL_PLATE)
	player.global_position = World.cell_to_world(c0 + Vector2i(3, 0))
	aim(World.cell_to_world(c0 + Vector2i(3, -2)))
	hold(KEY_E)
	await wait(0.4)
	release(KEY_E)
	await wait(0.1)
	ok("E не загрузил вход без чертежа", player.inv.count_of(IDs.I.STEEL_PLATE) == 2 and sm.stock.is_empty(),
			"в руке %d, в станке %s" % [player.inv.count_of(IDs.I.STEEL_PLATE), str(sm.stock)])

	while Game.next_blueprint_name() != "" and Game.next_blueprint_name() != "STEEL_WALL":
		Game.give_next_blueprint()
	ok("чертёж стальной стены выдан", Game.give_next_blueprint() == IDs.I.STEEL_WALL
			and Game.has_blueprint(IDs.I.STEEL_WALL))
	ok("после чертежа стальная пластина принимается", sm.input_accepts(IDs.I.STEEL_PLATE))

	player.global_position = World.cell_to_world(c0 + Vector2i(3, 0))
	hold(KEY_E)
	await wait_until(func() -> bool: return player.inv.count_of(IDs.I.STEEL_PLATE) == 0, 2.0)
	release(KEY_E)
	clear_input()
	ok("E загрузил пластины после чертежа", player.inv.count_of(IDs.I.STEEL_PLATE) == 0,
			"в руке %d" % player.inv.count_of(IDs.I.STEEL_PLATE))

	var moved: bool = await wait_until(func() -> bool: return _count(src, IDs.I.STEEL_PLATE) == 0, 10.0)
	ok("манипулятор перенёс пластины после чертежа", moved, "в сундуке %d" % _count(src, IDs.I.STEEL_PLATE))
	var rolled: bool = await wait_until(func() -> bool: return _ground_count(IDs.I.STEEL_WALL) > 0, 12.0)
	ok("плавильня льёт стальную стену", rolled)
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
