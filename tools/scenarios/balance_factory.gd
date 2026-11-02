extends "res://tools/scenarios/balance_common.gd"
## Бот баланса «релей на машинах» (#33, ADR-001 § 2: с двумя линиями буров ≤ 12 мин;
## § 4.2: одна стартовая линия мощностью 6 — 0.5 руды/с, 0.25 пластины/с).
##
## Две линии буров (настоящие машины, настоящая порода):
##   N буров в ряд → конвейер над ними → сундук-накопитель (порода остаётся в нём)
##   → манипулятор → плавильня A (руда → слиток) → манипулятор → плавильня B
##   (слиток → пластина; в линии 1 сперва сталь — в B заложен уголь)
##   → манипулятор → сундук готового. Две ТЭЦ на линию.
## «Линия буров» = столько буров, чтобы на реальной породе (доля руды в шахте
## ≈ 0.3) загрузить плавильню линии на 0.5 руды/с, — как стартовая линия § 4.2.
## Линия 1 бурит железо, линия 2 — медь, пока меди не хватит на релей, потом железо.
## Хвост: пластины, кристаллы, стекло и кристальные блоки бот перекладывает в два
## сборщика (микросхемы и антенна; энергоячейки) — засекается их работа.
##
## Честно:
##   * площадка вырыта API (галерея со стальной оболочкой, чтобы не натекла вода);
##   * шахта под буром — копия самой богатой нужной рудой шахты мира (16 клеток
##     реальной породы: руда, камень, уголь, песок). Выбурил — бот «переставляет»
##     бур на следующую по богатству шахту мгновенно; число перестановок в логе;
##   * кристаллы, стекло и блоки (их копают руками параллельно с фабрикой) бот
##     кладёт в сборщик сам; исследования (T1, T5) открыты заранее;
##   * ТЭЦ бот дозаправляет сам (уголь в логе).
## Отдельно — эталонная линия § 4.2 на чистой жиле (как tools/automation_bench.gd):
## бур → плавильня → манипулятор → плавильня → манипулятор → сборщик, одна ТЭЦ.

const TARGET_MIN: float = 12.0          ## ADR-001 § 2
const DRILLS_PER_LINE: int = 3
const LIMIT_SECS: float = 1800.0        ## страховка: игровых секунд на фабрику
const SPEED: float = 8.0
const REF_WARMUP: float = 20.0          ## эталон: замер после прогрева
const REF_WINDOW: float = 120.0
const REF_ORE_TARGET: float = 0.5       ## § 4.2
const REF_PLATE_TARGET: float = 0.25
const REF_TOL: float = 0.10             ## допуск ±10 %

var _lines: Array = []                  ## {drills, gens, ins, sm_a, sm_b, out, ore_kind, cols, moves, ore_copied, tiles_copied}
var _ranked: Dictionary = {}            ## тайл руды -> [[count, x, y], ...] по убыванию
var _rank_pos: Dictionary = {}          ## тайл руды -> индекс следующей шахты
var _used_x: Dictionary = {}
var _copper_left: int = 0               ## сколько медной руды ещё «заказать» линии 2
var _coal_fed: int = 0
var _gens: Array = []
var _ref: Dictionary = {}
var _site_x: Dictionary = {}


func run() -> void:
	player.invuln = 1.0e9
	Game.time_of_day = 0.30
	Game.research = 999
	Tech.unlock("T1")

	# ---- бюджет: металл линиям, остальное — хвосту
	var machine: Array = ["smelter", "assembler"]
	var stop: Array = [IDs.I.IRON_PLATE, IDs.I.COPPER_PLATE, IDs.I.STEEL_PLATE,
			IDs.I.CRYSTAL, IDs.I.GLASS, IDs.I.CRYSTAL_BLOCK]
	var metal: Dictionary = {}
	for id in Balance.RELAY_REQ.keys():
		expand(int(id), int(Balance.RELAY_REQ[id]), machine, metal, stop)
	var ore: Dictionary = {}
	for id in Balance.RELAY_REQ.keys():
		expand(int(id), int(Balance.RELAY_REQ[id]), machine, ore)
	var need_ip: int = int(metal.get(IDs.I.IRON_PLATE, 0))
	var need_cp: int = int(metal.get(IDs.I.COPPER_PLATE, 0))
	var need_st: int = int(metal.get(IDs.I.STEEL_PLATE, 0))
	_copper_left = int(ore.get(IDs.I.COPPER_ORE, 0))
	print("  [бюджет машинами] металл: %s" % items_str(metal))
	print("  [бюджет машинами] сырьё: %s" % items_str(ore))

	# ---- площадка и линии
	var bx: int = World.beacon_cell.x
	var y0: int = World.beacon_cell.y + 14
	_rank_columns(IDs.T.IRON_ORE)
	_rank_columns(IDs.T.COPPER_ORE)
	var built: bool = true
	built = _build_line(bx + 20, y0, IDs.T.IRON_ORE, need_st) and built
	built = _build_line(bx + 40, y0, IDs.T.COPPER_ORE, 0) and built
	built = _build_ref(bx + 60, y0) and built
	var tail: Dictionary = _build_tail(bx + 80, y0)
	built = not tail.is_empty() and built
	ok("фабрика поставлена (2 линии, эталон, хвост)", built)
	if not built:
		finish()
		return
	Game.update_power_budget()
	await wait_game(0.5)
	var eff_ok: bool = true
	for L in _lines:
		for m in L["drills"] + [L["sm_a"], L["sm_b"]]:
			if not m.powered or m.efficiency < 0.99:
				eff_ok = false
	ok("линии под полным питанием", eff_ok)

	# ---- прогон
	speed_up(SPEED)
	var t0: float = clock
	var ref_t0: float = -1.0
	var ref_ore0: int = 0
	var ref_pl0: int = 0
	var ref_done: bool = false
	var t_metal: float = -1.0
	while clock - t0 < LIMIT_SECS:
		await get_tree().process_frame
		_tick_lines()
		_refuel()
		_ref_refill()
		var el: float = clock - t0
		if ref_t0 < 0.0 and el >= REF_WARMUP:
			ref_t0 = clock
			ref_ore0 = int(_ref["ore"])
			ref_pl0 = int(_ref["i2"].moved)
		if not ref_done and ref_t0 >= 0.0 and clock - ref_t0 >= REF_WINDOW:
			ref_done = true
			var span: float = clock - ref_t0
			var ore_s: float = float(int(_ref["ore"]) - ref_ore0) / span
			var pl_s: float = float(int(_ref["i2"].moved) - ref_pl0) / span
			print("  [эталон § 4.2] бур→плавильня→манипулятор→плавильня→манипулятор→сборщик, ТЭЦ 1: нагрузка %.1f из %.1f, efficiency %.2f" % [
					_ref["gen"].power_load, _ref["gen"].current_output(), _ref["drill"].efficiency])
			metric("line_ore_per_s", ore_s, "руды/с на чистой жиле")
			metric("line_plate_per_s", pl_s, "пластин/с")
			ok("стартовая линия: %.2f руды/с ± %d %%" % [REF_ORE_TARGET, int(REF_TOL * 100.0)],
					absf(ore_s - REF_ORE_TARGET) <= REF_ORE_TARGET * REF_TOL, "%.3f" % ore_s)
			ok("стартовая линия: %.2f пластины/с ± %d %%" % [REF_PLATE_TARGET, int(REF_TOL * 100.0)],
					absf(pl_s - REF_PLATE_TARGET) <= REF_PLATE_TARGET * REF_TOL, "%.3f" % pl_s)
		if t_metal < 0.0 and _sum_out(IDs.I.IRON_PLATE) >= need_ip \
				and _sum_out(IDs.I.COPPER_PLATE) >= need_cp and _sum_out(IDs.I.STEEL_PLATE) >= need_st:
			t_metal = el
			break
	ok("линии выдали металл релея", t_metal > 0.0, "жел. %d/%d, мед. %d/%d, сталь %d/%d" % [
			_sum_out(IDs.I.IRON_PLATE), need_ip, _sum_out(IDs.I.COPPER_PLATE), need_cp,
			_sum_out(IDs.I.STEEL_PLATE), need_st])
	for i in _lines.size():
		var L: Dictionary = _lines[i]
		var f: float = float(L["ore_copied"]) / maxf(1.0, float(L["tiles_copied"]))
		print("  [линия %d] перестановок бура %d, шахт %d, доля руды в шахтах %.2f, руды в плавильню %d" % [
				i + 1, int(L["moves"]), int(L["cols"]), f, int(L["ins"][0].moved)])
	print("  [ТЭЦ] угля заложено ботом %d" % _coal_fed)
	if t_metal < 0.0:
		metric("factory_relay_min", (clock - t0) / 60.0, "не успели за предел — нижняя оценка")
		ok("релей с двумя линиями буров ≤ %.0f мин" % TARGET_MIN, false)
		finish()
		return

	# ---- хвост: сборщики
	var t1: float = clock
	_feed_tail(tail)
	var asm_done: bool = await wait_game_until(func() -> bool: return _tail_done(tail), 300.0)
	var t_tail: float = clock - t1
	ok("сборщики собрали микросхемы, ячейки и антенну", asm_done, "%.0f с" % t_tail)
	var total_min: float = (t_metal + t_tail) / 60.0
	print("  [фабрика] металл %.1f мин + сборщики %.1f мин" % [t_metal / 60.0, t_tail / 60.0])
	metric("factory_relay_min", total_min, "минут работы двух линий до деталей релея")
	ok("релей с двумя линиями буров ≤ %.0f мин" % TARGET_MIN, asm_done and total_min <= TARGET_MIN,
			"%.1f мин" % total_min)
	finish()


# ------------------------------------------------------------------ ПЛОЩАДКА

## Галерея со стальной оболочкой: воздух внутри, вода и лава не натекут.
func _carve(x0: int, y_top: int, x1: int, y_bot: int, open_cols: Array) -> void:
	for x in range(x0 - 1, x1 + 2):
		for y in range(y_top - 1, y_bot + 2):
			var edge: bool = x == x0 - 1 or x == x1 + 1 or y == y_top - 1 or y == y_bot + 1
			if edge:
				if y == y_bot + 1 and open_cols.has(x):
					continue
				World.set_tile(x, y, IDs.T.STEEL)
			else:
				World.set_tile(x, y, IDs.T.AIR)


func _place(kind: String, c: Vector2i) -> MachineBase:
	if not MachineBase.place_machine(kind, c):
		return null
	return World.machines.get(c)


## Линия буров. x — первый бур, y — ряд буров (конвейер — рядом выше).
func _build_line(x: int, y: int, ore_kind: int, coal_for_steel: int) -> bool:
	var drill_cols: Array = []
	for i in DRILLS_PER_LINE:
		drill_cols.append(x + i)
	var n: int = DRILLS_PER_LINE
	# Ряд буров y, конвейер y-1, ТЭЦ y-3.
	_carve(x, y - 3, x + n + 8, y, drill_cols)
	var drills: Array = []
	for i in n:
		var d: MachineBase = _place("Drill", Vector2i(x + i, y))
		if d == null:
			return false
		drills.append(d)
	for i in n + 1:
		var b: MachineBase = _place("Belt", Vector2i(x + i, y - 1))
		if b == null:
			return false
		(b as Belt).dir = 0
	var cx: int = x + n + 1
	var buf: MachineBase = _place("Chest", Vector2i(cx, y - 1))
	var i1: MachineBase = _place("Inserter", Vector2i(cx + 1, y - 1))
	var sm_a: MachineBase = _place("Smelter", Vector2i(cx + 2, y - 1))
	var i2: MachineBase = _place("Inserter", Vector2i(cx + 3, y - 1))
	var sm_b: MachineBase = _place("Smelter", Vector2i(cx + 4, y - 1))
	var i3: MachineBase = _place("Inserter", Vector2i(cx + 5, y - 1))
	var out: MachineBase = _place("Chest", Vector2i(cx + 6, y - 1))
	var g1: MachineBase = _place("CoalGen", Vector2i(x + 1, y - 3))
	var g2: MachineBase = _place("CoalGen", Vector2i(cx + 2, y - 3))
	for m in [buf, i1, sm_a, i2, sm_b, i3, out, g1, g2]:
		if m == null:
			return false
	for g in [g1, g2]:
		g.add_fuel(CoalGen.FUEL_MAX_UNITS)
		_gens.append(g)
	if coal_for_steel > 0:
		sm_b.receive_item(IDs.I.COAL, coal_for_steel)
	var L: Dictionary = {
		"drills": drills, "ins": [i1, i2, i3], "sm_a": sm_a, "sm_b": sm_b, "out": out,
		"ore_kind": ore_kind, "cols": 0, "moves": 0, "ore_copied": 0, "tiles_copied": 0,
		"y": y,
	}
	_lines.append(L)
	for d in drills:
		_reload_column(L, d)
		L["moves"] = int(L["moves"]) - 1     ## первая шахта — не перестановка
	return true


## Эталонная линия § 4.2 на чистой железной жиле: одна ТЭЦ (мощность 6).
func _build_ref(x: int, y: int) -> bool:
	_carve(x, y - 3, x + 8, y, [x])
	var drill: MachineBase = _place("Drill", Vector2i(x, y))
	var sm_a: MachineBase = _place("Smelter", Vector2i(x + 1, y))
	var i1: MachineBase = _place("Inserter", Vector2i(x + 2, y))
	var sm_b: MachineBase = _place("Smelter", Vector2i(x + 3, y))
	var i2: MachineBase = _place("Inserter", Vector2i(x + 4, y))
	var asm: MachineBase = _place("Assembler", Vector2i(x + 5, y))
	var belt: MachineBase = _place("Belt", Vector2i(x + 6, y))
	var out: MachineBase = _place("Chest", Vector2i(x + 7, y))
	var gen: MachineBase = _place("CoalGen", Vector2i(x + 3, y - 3))
	for m in [drill, sm_a, i1, sm_b, i2, asm, belt, out, gen]:
		if m == null:
			return false
	(belt as Belt).dir = 0
	gen.add_fuel(CoalGen.FUEL_MAX_UNITS)
	_gens.append(gen)
	asm.receive_item(IDs.I.CRYSTAL, 999)    ## кристаллы — не узкое место
	for dy in range(1, Balance.DRILL_REACH + 1):
		World.set_tile(x, y + dy, IDs.T.IRON_ORE)
	World.set_tile(x, y + Balance.DRILL_REACH + 1, IDs.T.STEEL)
	_ref = {"drill": drill, "i2": i2, "gen": gen, "ore": 0, "x": x, "y": y}
	return true


## Два сборщика хвоста со своей ТЭЦ; готовое — в сундуки рядом.
func _build_tail(x: int, y: int) -> Dictionary:
	_carve(x, y - 3, x + 6, y, [])
	var a1: MachineBase = _place("Assembler", Vector2i(x, y))
	var c1: MachineBase = _place("Chest", Vector2i(x + 1, y))
	var a2: MachineBase = _place("Assembler", Vector2i(x + 4, y))
	var c2: MachineBase = _place("Chest", Vector2i(x + 5, y))
	var gen: MachineBase = _place("CoalGen", Vector2i(x + 2, y - 3))
	for m in [a1, c1, a2, c2, gen]:
		if m == null:
			return {}
	gen.add_fuel(CoalGen.FUEL_MAX_UNITS)
	_gens.append(gen)
	return {"a1": a1, "c1": c1, "a2": a2, "c2": c2}


# ------------------------------------------------------------------ ШАХТЫ

## Для каждого x — окно в 16 клеток с наибольшим числом клеток руды; по убыванию.
func _rank_columns(ore_tile: int) -> void:
	var reach: int = Balance.DRILL_REACH
	var out: Array = []
	for x in range(2, World.W - 2):
		var best: int = 0
		var best_y: int = -1
		var top: int = World.surface[x]
		for y in range(top, World.H - reach - 2):
			var n: int = 0
			for dy in range(1, reach + 1):
				if World.get_tile(x, y + dy) == ore_tile:
					n += 1
			if n > best:
				best = n
				best_y = y
		if best > 0:
			out.append([best, x, best_y])
	out.sort_custom(func(a, b): return int(a[0]) > int(b[0]))
	_ranked[ore_tile] = out
	_rank_pos[ore_tile] = 0


## Следующая непочатая шахта мира для этой руды: [count, x, y] или [].
func _next_column(ore_tile: int) -> Array:
	var list: Array = _ranked[ore_tile]
	var i: int = int(_rank_pos[ore_tile])
	while i < list.size():
		var e: Array = list[i]
		i += 1
		if _used_x.has(int(e[1])):
			continue
		_used_x[int(e[1])] = true
		_rank_pos[ore_tile] = i
		return e
	_rank_pos[ore_tile] = i
	return []


## «Переставить» бур на новую шахту: копируем под него 16 клеток реальной породы.
func _reload_column(L: Dictionary, d: MachineBase) -> void:
	var kind: int = int(L["ore_kind"])
	if kind == IDs.T.COPPER_ORE and _copper_left <= 0:
		kind = IDs.T.IRON_ORE
	var e: Array = _next_column(kind)
	if e.is_empty():
		return
	var sx: int = int(e[1])
	var sy: int = int(e[2])
	var reach: int = Balance.DRILL_REACH
	var ore_n: int = 0
	var tiles_n: int = 0
	for dy in range(1, reach + 1):
		var t: int = World.get_tile(sx, sy + dy)
		if DB.is_liquid(t) or DB.tile_hard(t) > 100.0:
			t = IDs.T.AIR
		World.set_tile(d.cell.x, d.cell.y + dy, t)
		if t != IDs.T.AIR:
			tiles_n += 1
		if t == IDs.T.COPPER_ORE:
			_copper_left -= 1
		if t == IDs.T.IRON_ORE or t == IDs.T.COPPER_ORE:
			ore_n += 1
	# Под шахтой — сталь: бур не уйдёт глубже окна.
	World.set_tile(d.cell.x, d.cell.y + reach + 1, IDs.T.STEEL)
	L["cols"] = int(L["cols"]) + 1
	L["moves"] = int(L["moves"]) + 1
	L["ore_copied"] = int(L["ore_copied"]) + ore_n
	L["tiles_copied"] = int(L["tiles_copied"]) + tiles_n


func _tick_lines() -> void:
	for L in _lines:
		for d in L["drills"]:
			if (d as Drill).harvest_target().x < 0:
				_reload_column(L, d)


## Чистая жила эталона: выбуренные клетки снова руда (счёт руды — по восполнению).
func _ref_refill() -> void:
	if _ref.is_empty():
		return
	var d: MachineBase = _ref["drill"]
	for dy in range(1, Balance.DRILL_REACH + 1):
		if World.get_tile(d.cell.x, d.cell.y + dy) == IDs.T.AIR:
			World.set_tile(d.cell.x, d.cell.y + dy, IDs.T.IRON_ORE)
			_ref["ore"] = int(_ref["ore"]) + 1


## Игрок подкидывает уголь в ТЭЦ, пока топка не опустела.
func _refuel() -> void:
	for g in _gens:
		if is_instance_valid(g) and g.fuel < Balance.COAL_BURN * 2.0:
			_coal_fed += g.add_fuel(CoalGen.FUEL_MAX_UNITS)


func _sum_out(id: int) -> int:
	var n: int = 0
	for L in _lines:
		n += chest_count(L["out"], id)
	return n


# ------------------------------------------------------------------ ХВОСТ

## Забрать из сундуков линий n предметов id.
func _take_out(id: int, n: int) -> int:
	var got: int = 0
	for L in _lines:
		var ch: Chest = L["out"]
		for i in ch.slots.size():
			if got >= n:
				return got
			var s: ItemStack = ch.slots[i]
			if s.is_empty() or s.id != id:
				continue
			got += ch.take_at(i, mini(s.count, n - got))
	return got


## Разложить детали хвоста по сборщикам: a2 — энергоячейки, a1 — остальное.
func _feed_tail(tail: Dictionary) -> void:
	# Хвост открывает антенну (T5): исследования здесь не меряются.
	for node in ["T2", "T3", "T4", "T5"]:
		Tech.unlock(node)
	for id in Balance.RELAY_REQ.keys():
		var r: Dictionary = recipe_of(int(id), ["assembler"])
		if r.is_empty() or String(r["station"]) != "assembler":
			continue
		var asm: MachineBase = tail["a2"] if int(id) == IDs.I.POWER_CELL else tail["a1"]
		var crafts: int = int(ceil(float(Balance.RELAY_REQ[id]) / float(r["amount"])))
		for k in r["in"].keys():
			var n: int = crafts * int(r["in"][k])
			if int(k) in [IDs.I.IRON_PLATE, IDs.I.COPPER_PLATE, IDs.I.STEEL_PLATE]:
				n = _take_out(int(k), n)
			asm.receive_item(int(k), n)


func _tail_done(tail: Dictionary) -> bool:
	for id in Balance.RELAY_REQ.keys():
		var r: Dictionary = recipe_of(int(id), ["assembler"])
		if r.is_empty() or String(r["station"]) != "assembler":
			continue
		var ch: Node = tail["c2"] if int(id) == IDs.I.POWER_CELL else tail["c1"]
		if chest_count(ch, int(id)) < int(Balance.RELAY_REQ[id]):
			return false
	return true
