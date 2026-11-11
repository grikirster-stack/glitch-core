extends ScenarioBase
## Плавильня и чертёж (#57, #169).
##
## 1. Без питания горнило не светится: цвет горнила (Smelter.furnace_color) —
##    ровный тёмный в любой момент времени; под питанием — пульсирует.
## 2. Стена (#171) больше не рецепт плавильни: стальную пластину станок берёт
##    (сталь открыта). Стена — руками и только с чертежом: до чертежа её нет
##    в панели, после — клик кладёт 4 стены.
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

	# ---- Прокат и сталь открыты; стена — руками и только с чертежом ------------
	ok("медный слиток принимается сразу (прокат открыт)", sm.input_accepts(IDs.I.COPPER_INGOT))
	ok("уголь принимается (сталь открыта)", sm.input_accepts(IDs.I.COAL))
	ok("железный слиток принимается (сталь открыта)", sm.input_accepts(IDs.I.IRON_INGOT))
	ok("руда принимается", sm.input_accepts(IDs.I.COPPER_ORE))
	ok("верстак сразу берёт пластину и кристалл", asm.input_accepts(IDs.I.COPPER_PLATE)
			and asm.input_accepts(IDs.I.CRYSTAL) and asm.receive_item(IDs.I.COPPER_PLATE, 1) == 0)

	var wall: Dictionary = {}
	for r in DB.recipes_for("hand"):
		if int(r["out"]) == IDs.I.STEEL_WALL:
			wall = r
	ok("стена — ручной рецепт на слитках", not wall.is_empty()
			and int(wall["in"].get(IDs.I.IRON_INGOT, 0)) == 2 and int(wall["amount"]) == 4)
	player.inv.mark_seen(IDs.I.IRON_INGOT)
	player.inv.mark_seen(IDs.I.COAL)
	var panel: InventoryPanel = UI.panel
	panel.open(player)
	ok("без чертежа стены нет в панели", not panel._recipes("hand").has(wall))
	while Game.next_blueprint_name() != "" and Game.next_blueprint_name() != "STEEL_WALL":
		Game.give_next_blueprint()
	ok("чертёж стальной стены выдан", Game.give_next_blueprint() == IDs.I.STEEL_WALL
			and Game.has_blueprint(IDs.I.STEEL_WALL))
	panel._check_cache()
	ok("после чертежа стена в панели", panel._recipes("hand").has(wall))
	player.inv.add(IDs.I.IRON_INGOT, 2)
	player.inv.add(IDs.I.COAL, 1)
	panel._craft(wall)
	ok("стена скрафчена руками, 4 штуки", player.inv.count_of(IDs.I.STEEL_WALL) == 4,
			"стен %d" % player.inv.count_of(IDs.I.STEEL_WALL))
	panel.close()
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
