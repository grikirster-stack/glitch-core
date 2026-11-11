class_name CampaignBase
extends RefCounted
## База экспедиции «Кербер-9» для глав кампании (ADR-004): достраивается кодом поверх
## мира сида Campaign.SEED — клетки отсчитаны от релей-ядра (World.beacon_cell),
## рельеф вокруг снят tools/campaign_map.gd (--map-dump). Чем дальше глава, тем больше
## уровней базы:
##   STATION — станция как в свободной игре (релей, терминалы, лампы, вентиляция);
##   FACTORY — ТЭЦ станции, терминалы прочитаны; «Цех» справа: навес с лампами, бур на
##             железной жиле → конвейер → плавильня → склад, сборщик на солнечных
##             панелях, сундук «Запчасти»;
##   MINE    — «Шахта» слева: ствол в стальных стенах до пещеры (~40 клеток вниз),
##             проём в 3 клетки, уступы в клетку попеременно у стен через 2 ряда:
##             наверх — прыжком с разбега (сойти с уступа к центру и прыгнуть, койот-
##             тайм героя), вниз — по центру; светокристаллы и кристаллы глитча в
##             стенах; внизу
##             штольня: ТЭЦ, два глубинных бура над рудой, сундук добычи, сундук снабжения;
##   DEFENSE — вторые ТЭЦ станции, цеха и шахты, турели у вентиляции и на краях, прожектор.
## build() возвращает именованные постройки — главы ищут их по имени (store, drill, …).

enum Tier { STATION, FACTORY, MINE, DEFENSE }

## Ствол шахты: x от релея (левая и правая клетки проёма), ряды — от пола базы.
const SHAFT_X0: int = -18
const SHAFT_X1: int = -16
const SHAFT_DEPTH: int = 43        ## пол штольни: пол базы + столько рядов
## Ряды между соседними уступами (они у разных стен). Прыжок героя — ~3 клетки, но с
## места под уступом той же стены (4 ряда выше) места на него нет: прыгают, сойдя с
## уступа к центру проёма, над которым пусто.
const LEDGE_STEP: int = 2


## Достроить базу до уровня tier. Итог: имя → постройка (MachineBase).
static func build(tier: int) -> Dictionary:
	var named: Dictionary = {}
	if tier >= Tier.FACTORY:
		_station(named)
		_factory(named)
	if tier >= Tier.MINE:
		_mine(named)
	if tier >= Tier.DEFENSE:
		_defense(named)
	return named


## Пол базы (ряд стального пола под релеем).
static func floor_row() -> int:
	return World.beacon_cell.y + 1


## Дно шахты: ряд, на котором стоят постройки штольни.
static func mine_row() -> int:
	return floor_row() + SHAFT_DEPTH - 1


## Прочитать терминалы базы (главы журнала 1–2) без уведомлений: станция давно работает.
static func read_base_terminals() -> void:
	for t in World.terminals.duplicate():
		var ch: int = int(World.terminal_chapters.get(t, -1))
		if ch < 0 or ch >= Lore.BASE_TERMINALS:
			continue
		World.terminals.erase(t)
		World.set_tile(t.x, t.y, IDs.T.PANEL)
		if not Tech.read_chapters.has(ch):
			Tech.read_chapters.append(ch)
		Game.tasks_done += 1


# ------------------------------------------------------------------ ПОСТРОЙКИ

## Поставить постройку в клетку (клетку освобождает). opts: dir (конвейер,
## манипулятор), fuel (уголь в ТЭЦ), items [[id, n], …] (сундук). null — не вышло.
static func put(kind: String, c: Vector2i, opts: Dictionary = {}) -> MachineBase:
	if World.machines.has(c):
		return World.machines[c]
	if World.get_tile_v(c) != IDs.T.AIR:
		World.set_tile(c.x, c.y, IDs.T.AIR)
	if not MachineBase.place_machine(kind, c):
		return null
	var m: MachineBase = World.machines[c]
	m.permanent = true   # постройка базы: разобрать её нельзя
	if opts.has("dir") and "dir" in m:
		m.set("dir", int(opts["dir"]))
		m.queue_redraw()
	if opts.has("fuel") and m is CoalGen:
		(m as CoalGen).add_fuel(int(opts["fuel"]))
	for e in opts.get("items", []):
		m.receive_item(int(e[0]), int(e[1]))
	return m


static func fill(x0: int, y0: int, x1: int, y1: int, id: int) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if World.get_tile(x, y) != id:
				World.set_tile(x, y, id)


# ------------------------------------------------------------------ УРОВНИ

static func _station(named: Dictionary) -> void:
	var bx: int = World.beacon_cell.x
	var row: int = World.beacon_cell.y
	read_base_terminals()
	# ТЭЦ станции между релеем и левым терминалом: накрывает оба терминала (радиус 8).
	named["gen_station"] = put("CoalGen", Vector2i(bx - 1, row), {"fuel": CoalGen.FUEL_MAX_UNITS})


static func _factory(named: Dictionary) -> void:
	var bx: int = World.beacon_cell.x
	var row: int = World.beacon_cell.y
	var fl: int = floor_row()
	var x0: int = bx + 13
	var x1: int = bx + 36
	# Площадка цеха — продолжение пола базы, над ней навес на высоте 4 рядов.
	fill(x0, row - 8, x1, row, IDs.T.AIR)
	fill(x0, fl, x1, fl + 1, IDs.T.STEEL)
	fill(x0, row - 4, x1, row - 4, IDs.T.PANEL)
	for lx in [x0 + 3, x0 + 11, x0 + 19]:
		World.set_tile(int(lx), row - 3, IDs.T.LIGHT_CRYSTAL)
	# Железная жила под буром: бур берёт нижнюю руду шахты, сталь пола он бы срыл.
	var dx: int = bx + 18
	fill(dx, fl, dx, fl + Balance.DRILL_REACH - 1, IDs.T.IRON_ORE)
	named["gen_factory"] = put("CoalGen", Vector2i(bx + 15, row), {"fuel": CoalGen.FUEL_MAX_UNITS})
	named["drill"] = put("Drill", Vector2i(dx, row))
	for k in 3:
		named["belt%d" % k] = put("Belt", Vector2i(dx + 1 + k, row), {"dir": 0})
	named["smelter"] = put("Smelter", Vector2i(bx + 22, row))
	named["store"] = put("Chest", Vector2i(bx + 23, row))
	named["assembler"] = put("Assembler", Vector2i(bx + 26, row))
	named["asm_out"] = put("Chest", Vector2i(bx + 27, row))
	named["solar1"] = put("Solar", Vector2i(bx + 29, row))
	named["solar2"] = put("Solar", Vector2i(bx + 30, row))
	named["parts"] = put("Chest", Vector2i(bx + 33, row))


static func _mine(named: Dictionary) -> void:
	var bx: int = World.beacon_cell.x
	var fl: int = floor_row()
	var sx0: int = bx + SHAFT_X0
	var sx1: int = bx + SHAFT_X1
	var bottom: int = fl + SHAFT_DEPTH       # пол штольни
	var mrow: int = bottom - 1
	# Ствол: проём, стальные стены, светокристаллы в стенах через 6 рядов.
	fill(sx0, fl - 1, sx1, bottom - 1, IDs.T.AIR)
	fill(sx0 - 1, fl, sx0 - 1, bottom - 1, IDs.T.STEEL_WALL)
	fill(sx1 + 1, fl, sx1 + 1, bottom - 1, IDs.T.STEEL_WALL)
	var y: int = fl + 4
	while y < bottom - 3:
		World.set_tile(sx0 - 1, y, IDs.T.LIGHT_CRYSTAL)
		World.set_tile(sx1 + 1, y + 3, IDs.T.LIGHT_CRYSTAL)
		y += 6
	World.fix_floating_near(Vector2i(sx0, fl - 1))   # свечник над стволом — без опоры
	# Уступы в клетку попеременно у стен, через LEDGE_STEP рядов: верхний — у правой
	# стены, на ряд ниже кромки (оттуда шаг к базе), нижний — прыжок с пола штольни.
	var k: int = 0
	y = fl + 1
	while y <= bottom - LEDGE_STEP:
		World.set_tile(sx1 if k % 2 == 0 else sx0, y, IDs.T.STEEL)
		k += 1
		y += LEDGE_STEP
	# Кристаллы глитча в нишах стен — копать руками (глава «Шахта»).
	for cy in range(fl + 26, fl + 29):
		World.set_tile(sx0 - 1, cy, IDs.T.CRYSTAL_ORE)
	for cy in range(fl + 32, fl + 35):
		World.set_tile(sx1 + 1, cy, IDs.T.CRYSTAL_ORE)
	# Штольня на восток до пещеры: пол и потолок из стали, лампы в потолке.
	var tx1: int = bx - 2
	fill(sx0 - 1, bottom, tx1, bottom, IDs.T.STEEL)
	fill(sx1 + 1, mrow - 2, tx1, mrow, IDs.T.AIR)
	fill(sx1 + 2, mrow - 3, tx1, mrow - 3, IDs.T.STEEL_WALL)
	for lx in [bx - 11, bx - 5]:
		World.set_tile(int(lx), mrow - 3, IDs.T.LIGHT_CRYSTAL)
	# Глубинные буры над рудными колоннами (железо и медь через ряд) на всю глубину бура:
	# бур берёт нижнюю клетку шахты — камня в колонне не будет.
	for ddx in [bx - 9, bx - 7]:
		for yy in range(bottom + 1, mini(mrow + Balance.DEEP_DRILL_REACH + 1, World.H - 2)):
			World.set_tile(int(ddx), yy, IDs.T.IRON_ORE if (yy + int(ddx)) % 2 == 0 else IDs.T.COPPER_ORE)
	named["gen_mine"] = put("CoalGen", Vector2i(bx - 12, mrow), {"fuel": CoalGen.FUEL_MAX_UNITS})
	named["deep1"] = put("DeepDrill", Vector2i(bx - 9, mrow))
	named["mine_chest"] = put("Chest", Vector2i(bx - 8, mrow))
	named["deep2"] = put("DeepDrill", Vector2i(bx - 7, mrow))
	named["mine_supply"] = put("Chest", Vector2i(bx - 10, mrow))


static func _defense(named: Dictionary) -> void:
	var bx: int = World.beacon_cell.x
	var row: int = World.beacon_cell.y
	var mrow: int = mine_row()
	# Потребитель берёт ток у ближайшего генератора (Game.update_power_budget): у каждой
	# группы построек — своя ТЭЦ, солнечные панели цеха (по 2) кормят только сборщик.
	named["gen_station2"] = put("CoalGen", Vector2i(bx + 1, row), {"fuel": CoalGen.FUEL_MAX_UNITS})
	named["gen_mine2"] = put("CoalGen", Vector2i(bx - 4, mrow), {"fuel": CoalGen.FUEL_MAX_UNITS})
	named["gen_factory2"] = put("CoalGen", Vector2i(bx + 32, row), {"fuel": CoalGen.FUEL_MAX_UNITS})
	named["turret1"] = put("Turret", Vector2i(bx - 8, row))
	named["turret2"] = put("Turret", Vector2i(bx + 7, row))
	named["turret3"] = put("Turret", Vector2i(bx + 35, row))
	named["flood1"] = put("Floodlight", Vector2i(bx + 34, row))
