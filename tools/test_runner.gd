extends Node
## Автотест игровой логики: копание, подбор, крафт, конвейер, питание, фантомы, релей.
## Плюс секция «== Анимации ==» — общий код из tools/anim_test.gd (issue #6),
## секция «== Индекс питания ==» — общий код из tools/power_test.gd (issue #11),
## секции «== Данные ==» и «== Сутки ==» — согласованность IDs/DB/Balance и цикл смены (#24),
## секция «== Лор ==» — общий код из tools/lore_test.gd (issue #26),
## секция «== Звук ==» — общий код из tools/sfx_test.gd (issue #36),
## секция «== Тайники руин ==» — сундуки и таблички руин (issue #35),
## секция «== Сохранение ==» — общий код из tools/save_test.gd (issue #37),
## секция «== Небесный тайник ==» — обломок «Кербер-9» в небе (issue #60),
## секция «== Размер интерфейса ==» — tools/ui_scale_test.gd (#159),
## секция «== Хотбар ==» — tools/hotbar_test.gd (#161),
## секция «== Меню и профиль ==» — общий код из tools/menu_test.gd (ADR-002, MP-B, #87).
## Запускается из main.gd флагом `--test`.
##
## Все паузы отсчитываются по реальному времени, а не по кадрам: в headless-режиме
## частота кадров не гарантирована, а симуляция машин идёт по delta.

## Общий код проверок анимаций: тот же самый, что и в отдельном
## tools/anim_test.gd (issue #6). Дублирования нет — файл подключается один раз.
const AnimTestScript = preload("res://tools/anim_test.gd")
## Общий код регрессий индекса питания: tools/power_test.gd (issue #11).
const PowerTestScript = preload("res://tools/power_test.gd")
## Общий код проверок генеративного лора: tools/lore_test.gd (issue #26).
const LoreTestScript = preload("res://tools/lore_test.gd")
## Общий код проверок процедурного звука: tools/sfx_test.gd (issue #36).
const SfxTestScript = preload("res://tools/sfx_test.gd")
## Общий код проверок сохранения: tools/save_test.gd (issue #37).
const SaveTestScript = preload("res://tools/save_test.gd")
## Общий код проверок профиля и меню: tools/menu_test.gd (ADR-002, MP-B, #87).
const MenuTestScript = preload("res://tools/menu_test.gd")
## Размер интерфейса: tools/ui_scale_test.gd (#159).
const UiScaleTestScript = preload("res://tools/ui_scale_test.gd")
## Хотбар 6/10: tools/hotbar_test.gd (#161).
const HotbarTestScript = preload("res://tools/hotbar_test.gd")

var scene: Node = null
var step: int = 0
var player: Node = null
var fails: int = 0
var checks: int = 0
var anim: Node = null
var power: Node = null
var lore: Node = null
var sfx_t: Node = null
var save_t: Node = null
var menu_t: Node = null   ## меню и профиль (MP-B, #87)
var ui_scale_t: Node = null   ## размер интерфейса (#159)
var hotbar_t: Node = null     ## хотбар 6/10 (#161)

var _wait_until_ms: int = 0

# Замер времени кадра (только предупреждение, провалом не считаем).
var _frame_us: int = 0
var _frame_n: int = 0
var _frame_sum_ms: float = 0.0
var _frame_max_ms: float = 0.0
var _frame_slow: int = 0

var mine_cell: Vector2i = Vector2i.ZERO
var drill_cell: Vector2i = Vector2i.ZERO
var chest_cell: Vector2i = Vector2i.ZERO
var gen_cell: Vector2i = Vector2i.ZERO
var smelter_cell: Vector2i = Vector2i.ZERO
var prod_chest_cell: Vector2i = Vector2i.ZERO
var assembler_cell: Vector2i = Vector2i.ZERO
var prod_chest2_cell: Vector2i = Vector2i.ZERO
var water_hole: Vector2i = Vector2i(-1, -1)
var water_src: Vector2i = Vector2i(-1, -1)

var _day0: int = 0            ## смена на момент проверки суток
var _day_signals: int = 0     ## сколько раз пришёл Game.day_started


func start(main_scene: Node) -> void:
	scene = main_scene
	_next(1, 0.5)


func _process(_delta: float) -> void:
	# Замер времени кадра: между кадрами считаем разницу Time.get_ticks_usec.
	# Это предупреждение, а не провал (см. секцию «== Производительность ==»).
	var now_us: int = Time.get_ticks_usec()
	if _frame_us > 0:
		var ms: float = float(now_us - _frame_us) / 1000.0
		_frame_n += 1
		_frame_sum_ms += ms
		if ms > _frame_max_ms:
			_frame_max_ms = ms
		if ms > 100.0:
			_frame_slow += 1
	_frame_us = now_us

	if step == 0:
		return
	if Time.get_ticks_msec() < _wait_until_ms:
		return
	match step:
		1: _t_world()
		2: _t_mine()
		3: _t_pickup()
		4: _t_craft()
		5: _t_machines()
		6: _t_power()
		7: _t_belt()
		8: _t_production()
		9: _t_production_result()
		10: _t_phantom()
		11: _t_day_noon()
		12: _t_day_dawn()
		13: _t_day_result()
		14: _t_relay()
		15: _t_water_dig()
		16: _t_water_check()
		17: _t_anim_start()
		18: _t_anim_wait()
		19: _t_power_start()
		20: _t_power_wait()
		21: _t_lore_start()
		22: _t_lore_wait()
		23: _t_sfx_start()
		24: _t_sfx_wait()
		25: _t_save_start()
		26: _t_save_wait()
		27: _t_menu_start()   # меню и профиль (MP-B, #87)
		28: _t_menu_wait()
		29: _t_finish()
		30: _t_ui_scale_start()   # размер интерфейса (#159)
		31: _t_ui_scale_wait()
		32: _t_hotbar_start()     # хотбар 6/10 (#161)
		33: _t_hotbar_wait()


func _ok(label: String, cond: bool, extra: String = "") -> void:
	checks += 1
	if cond:
		print("  OK   %s %s" % [label, extra])
	else:
		fails += 1
		print("  FAIL %s %s" % [label, extra])


## Переход к следующему шагу с паузой в реальные секунды.
func _next(s: int, secs: float = 0.1) -> void:
	step = s
	_wait_until_ms = Time.get_ticks_msec() + int(secs * 1000.0)


# ------------------------------------------------------------------ тесты

func _t_world() -> void:
	print("== Мир ==")
	player = scene.get("player")
	_ok("игрок создан", player != null)
	_ok("мир сгенерирован", World.tiles.size() == World.W * World.H)
	_ok("терминалы есть", World.terminals.size() > 0, "n=%d" % World.terminals.size())
	_ok("релей на месте", World.get_tile_v(World.beacon_cell) == IDs.T.RELAY_CORE)
	_ok("игрок не в стене", not World.rect_solid(Rect2(player.global_position - Vector2(6, 11), Vector2(12, 22))))
	_ok("задачи назначены", Game.tasks_total == World.terminals.size())
	_check_floating_trees()
	print("   инвентарь: ", _inv_dump())
	_check_data()
	_check_ruin_caches()
	_check_sky_cache()
	_check_defense()   # оборона (#31)
	_next(2)


## Деревья не должны висеть в воздухе: ствол стоит на грунте, листва связана
## со стволом. Плюс форма: у дерева есть высокий ствол и широкая крона.
func _check_floating_trees() -> void:
	var bad: Array = World.floating_tree_cells()
	_ok("деревья не висят в воздухе", bad.is_empty(), str(bad.slice(0, 6)))
	var st: Dictionary = _tree_stats()
	_ok("ствол у дерева высокий (>=5 брёвен)", int(st["min_trunk"]) >= 5,
			"минимальный %d" % int(st["min_trunk"]))
	_ok("крона широкая (>=3 клетки)", int(st["min_crown"]) >= 3,
			"минимальная %d" % int(st["min_crown"]))
	_ok("деревьев в мире достаточно", int(st["trees"]) >= 30,
			"деревьев %d" % int(st["trees"]))
	_check_tree_passable()


## Сквозь ствол дерева должен проходить игрок: лес не запирает его между
## стволами. Проверяем клетку земли у каждого дерева — там, где стоит игрок.
func _check_tree_passable() -> void:
	var trunks: int = 0
	var solid_trunks: int = 0
	for x in range(World.W):
		var ground: int = World.surface[x]
		if World.get_tile(x, ground - 1) != IDs.T.TREE:
			continue
		trunks += 1
		if World.rect_solid(World.cell_rect(Vector2i(x, ground - 1))):
			solid_trunks += 1
	_ok("ствол дерева проходимый", trunks > 0 and solid_trunks == 0,
			"стволов %d, твёрдых %d" % [trunks, solid_trunks])


## Статистика по деревьям: сколько деревьев, какая минимальная высота ствола
## и какая ширина кроны у самого скромного дерева.
## Крона считается в пределах ±2 клеток от ствола: иначе листва соседних
## деревьев слипается и ширина получается завышенной.
func _tree_stats() -> Dictionary:
	var trees: int = 0
	var min_trunk: int = 999
	var min_crown: int = 999
	for x in range(World.W):
		var ground: int = World.surface[x]
		var h: int = 0
		for y in range(ground - 1, maxi(ground - 12, 0), -1):
			if World.get_tile(x, y) != IDs.T.TREE:
				break
			h += 1
		if h == 0:
			continue
		trees += 1
		min_trunk = mini(min_trunk, h)
		var crown: int = 0
		for row in range(ground - h - 8, ground - h):
			var w: int = 0
			for c in range(x - 2, x + 3):
				if World.get_tile(c, row) == IDs.T.LEAVES:
					w += 1
			crown = maxi(crown, w)
		min_crown = mini(min_crown, crown)
	return {"trees": trees, "min_trunk": min_trunk, "min_crown": min_crown}


func _inv_dump() -> String:
	var parts: Array = []
	for i in range(player.inv.slots.size()):
		var s: ItemStack = player.inv.slots[i]
		if not s.is_empty():
			parts.append("%s x%d" % [DB.item_name(s.id), s.count])
	return ", ".join(parts)


func _t_mine() -> void:
	print("== Добыча ==")
	var pc: Vector2i = World.world_to_cell(player.global_position)
	mine_cell = Vector2i(-1, -1)
	for dx in range(-6, 7):
		for dy in range(0, 3):
			var c: Vector2i = pc + Vector2i(dx, dy)
			var t: int = World.get_tile_v(c)
			if t == IDs.T.AIR:
				continue
			if DB.tile_hard(t) > 100.0:
				continue
			if DB.tile_drop(t) == IDs.I.NONE:
				continue
			mine_cell = c
			break
		if mine_cell.x >= 0:
			break
	_ok("найден тайл для добычи", mine_cell.x >= 0, str(mine_cell))
	if mine_cell.x < 0:
		_next(3)
		return
	var before: int = World.get_tile_v(mine_cell)
	var guard: int = 0
	while World.get_tile_v(mine_cell) == before and guard < 300:
		player._do_mining(mine_cell, 0.25)
		guard += 1
	_ok("тайл сломан", World.get_tile_v(mine_cell) == IDs.T.AIR, "вызовов %d" % guard)
	# Подходим к дропу, чтобы он подобрался
	player.global_position = World.cell_to_world(mine_cell) - Vector2(0, 12)
	_next(3, 2.0)


func _t_pickup() -> void:
	print("== Подбор ==")
	var total: int = 0
	for i in range(player.inv.slots.size()):
		var s: ItemStack = player.inv.slots[i]
		if not s.is_empty():
			total += s.count
	_ok("предметы в инвентаре", total > 0, "всего %d" % total)
	_next(4)


func _t_craft() -> void:
	print("== Крафт ==")
	# Регресс: id предметов не должны «съезжать» относительно enum.
	_ok("названия предметов на месте",
			DB.item_name(IDs.I.COPPER_ORE) == "Медная руда"
			and DB.item_name(IDs.I.LAMP) == "Светокристалл"
			and DB.item_name(IDs.I.DRILL) == "Буровая станция")
	_ok("стак руды больше 1", DB.item_max_stack(IDs.I.COPPER_ORE) > 1)
	_ok("буровая ставится", DB.item_place(IDs.I.DRILL) == "machine:Drill")
	var ore_before: int = player.inv.count_of(IDs.I.COPPER_ORE)
	player.inv.add(IDs.I.COPPER_ORE, 5)
	var recipes: Array = DB.recipes_for("hand")
	var found: Dictionary = {}
	for r in recipes:
		if int(r["out"]) == IDs.I.COPPER_INGOT:
			found = r
	_ok("есть рецепт медного слитка", not found.is_empty())
	if not found.is_empty():
		var panel: InventoryPanel = UI.panel
		panel.open(player)
		panel._craft(found)
		var ing: int = player.inv.count_of(IDs.I.COPPER_INGOT)
		_ok("слиток получен", ing > 0, "count=%d" % ing)
		var ore_after: int = player.inv.count_of(IDs.I.COPPER_ORE)
		_ok("руда списана", ore_after < ore_before + 5,
				"было %d, стало %d" % [ore_before, ore_after])
		# Регресс: клик мышью по рецепту (не прямой вызов) не должен падать.
		# Раньше прямоугольник слота считался тернарником внутри вызова Rect2,
		# и без сундука получалось Rect2(Rect2, Vector2) — «Nonexistent 'Rect2'
		# constructor»: выплавка меди на клик не работала.
		var ing_before: int = player.inv.count_of(IDs.I.COPPER_INGOT)
		panel.scroll = 0
		var pp: Vector2 = panel._panel_pos()
		panel._click(pp + Vector2(390, 126), false)
		var ing_after: int = player.inv.count_of(IDs.I.COPPER_INGOT)
		_ok("клик по рецепту крафтит и не падает", ing_after > ing_before,
				"до %d, после %d" % [ing_before, ing_after])
		panel.close()
	_next(5)


func _t_machines() -> void:
	print("== Постройки ==")
	var bx: int = World.beacon_cell.x
	var base: int = World.beacon_cell.y
	drill_cell = Vector2i(bx - 30, base + 6)
	chest_cell = drill_cell + Vector2i(2, 0)
	gen_cell = Vector2i(bx - 34, base + 6)
	for i in 4:
		for dy in range(-1, 2):
			World.set_tile(gen_cell.x + i, gen_cell.y + dy, IDs.T.AIR)
			World.set_tile(chest_cell.x + i, chest_cell.y + dy, IDs.T.AIR)
			World.set_tile(drill_cell.x + i, drill_cell.y + dy, IDs.T.AIR)
	_ok("буровая поставлена", MachineBase.place_machine("Drill", drill_cell))
	_ok("конвейер поставлен", MachineBase.place_machine("Belt", drill_cell + Vector2i(1, 0)))
	_ok("сундук поставлен", MachineBase.place_machine("Chest", chest_cell))
	_ok("ТЭЦ поставлена", MachineBase.place_machine("CoalGen", gen_cell))
	var b: Belt = World.belts.get(drill_cell + Vector2i(1, 0))
	if b:
		b.dir = 0
	var gen: Node = World.machines.get(gen_cell)
	if gen:
		gen.add_fuel(3)
	_next(6, 1.0)


func _t_power() -> void:
	print("== Питание ==")
	var gen: Node = World.machines.get(gen_cell)
	var drill: Node = World.machines.get(drill_cell)
	_ok("ТЭЦ работает", gen != null and gen.power_active, "fuel=%.1f" % (gen.fuel if gen else 0.0))
	_ok("зона питания покрывает буровую", Game.is_powered(World.cell_to_world(drill_cell)))
	_ok("буровая под питанием", drill != null and drill.powered)
	_next(7, 5.0)


func _t_belt() -> void:
	print("== Конвейер и добыча ==")
	var chest: Chest = World.machines.get(chest_cell)
	var found: int = -1
	if chest:
		for s in chest.slots:
			if not s.is_empty():
				found = s.id
				break
	_ok("предмет доехал до сундука", found >= 0, "id=%d" % found)
	var drill: Node = World.machines.get(drill_cell)
	_ok("бурова на месте", drill != null)
	_next(8)


func _t_production() -> void:
	print("== Производство ==")
	var bx: int = World.beacon_cell.x
	var base: int = World.beacon_cell.y
	smelter_cell = Vector2i(bx - 32, base + 6)
	prod_chest_cell = Vector2i(bx - 31, base + 6)
	assembler_cell = Vector2i(bx - 33, base + 8)
	prod_chest2_cell = Vector2i(bx - 32, base + 8)
	# Расчищаем площадку под цех.
	for x in range(bx - 35, bx - 26):
		for y in range(base + 4, base + 9):
			World.set_tile(x, y, IDs.T.AIR)
	_ok("плавильня поставлена", MachineBase.place_machine("Smelter", smelter_cell))
	_ok("сундук цеха поставлен", MachineBase.place_machine("Chest", prod_chest_cell))
	_ok("сборщик поставлен", MachineBase.place_machine("Assembler", assembler_cell))
	_ok("сундук сборщика поставлен", MachineBase.place_machine("Chest", prod_chest2_cell))
	var sm: Smelter = World.machines.get(smelter_cell)
	var asm: Assembler = World.machines.get(assembler_cell)
	if sm:
		_ok("плавильня принимает руду", sm.input_accepts(IDs.I.COPPER_ORE))
		_ok("руда загружена в плавильню", sm.receive_item(IDs.I.COPPER_ORE, 2) == 0)
	if asm:
		_ok("сборщик принимает пластину", asm.input_accepts(IDs.I.COPPER_PLATE))
		_ok("пластина загружена", asm.receive_item(IDs.I.COPPER_PLATE, 1) == 0)
		_ok("кристалл загружен", asm.receive_item(IDs.I.CRYSTAL, 2) == 0)
	_next(9, 5.0)


func _t_production_result() -> void:
	print("== Результат производства ==")
	var sm: Smelter = World.machines.get(smelter_cell)
	var asm: Assembler = World.machines.get(assembler_cell)
	_ok("плавильня под питанием", sm != null and sm.powered)
	_ok("сборщик под питанием", asm != null and asm.powered)
	var chest: Chest = World.machines.get(prod_chest_cell)
	var ingots: int = 0
	if chest:
		for s in chest.slots:
			if not s.is_empty() and s.id == IDs.I.COPPER_INGOT:
				ingots += s.count
	_ok("слиток доехал до сундука", ingots > 0, "слитков %d" % ingots)
	var chest2: Chest = World.machines.get(prod_chest2_cell)
	var circuits: int = 0
	if chest2:
		for s in chest2.slots:
			if not s.is_empty() and s.id == IDs.I.CIRCUIT:
				circuits += s.count
	_ok("микросхема доехала до сундука", circuits > 0, "микросхем %d" % circuits)
	_next(10)


func _t_phantom() -> void:
	print("== Фантомы ==")
	var before: int = get_tree().get_nodes_in_group("phantom").size()
	Threat.spawn_in_cave("echo")   # спавн ведёт директор угрозы (#27)
	var after: int = get_tree().get_nodes_in_group("phantom").size()
	_ok("фантом заспавнен", after > before, "%d -> %d" % [before, after])
	var phs: Array = get_tree().get_nodes_in_group("phantom")
	if phs.size() > 0:
		var ph: Node = phs[0]
		var hp0: float = ph.hp
		ph.take_damage(50.0, Vector2.ZERO)
		_ok("фантом получает урон", ph.hp < hp0, "hp=%d" % int(ph.hp))
	_next(11)


# ------------------------------------------------------------ данные (ADR-001, #24)

## Согласованность данных: id предметов совпадают с IDs.I, рецепты ссылаются
## на существующие предметы и узлы технологий, у каждого тайла и предмета есть
## текстура, константы Balance положительные.
func _check_data() -> void:
	print("== Данные ==")
	# IDs.I ↔ DB.item_defs: каждый id описан, лишних нет.
	var missing: Array = []
	for v in IDs.I.values():
		if not DB.item_defs.has(int(v)):
			missing.append(int(v))
	_ok("все IDs.I описаны в DB", missing.is_empty() and DB.item_defs.size() == IDs.I.size(),
			"нет %s, в DB %d, в IDs %d" % [str(missing), DB.item_defs.size(), IDs.I.size()])
	# Рецепты: выход и входы существуют. Поле tech снято (#169): выход из
	# BLUEPRINT_ORDER без чертежа скрыт, остальные открыты.
	var bad: Array = []
	for r in DB.recipes:
		if not DB.item_defs.has(int(r["out"])):
			bad.append(String(r["name"]) + ":out")
		for k in r["in"].keys():
			if not DB.item_defs.has(int(k)):
				bad.append(String(r["name"]) + ":in")
		if r.has("tech"):
			bad.append(String(r["name"]) + ":tech")
	_ok("рецепты ссылаются на существующие предметы", bad.is_empty(), str(bad))
	_ok("стальная стена без чертежа закрыта", not DB.recipe_unlocked({"out": IDs.I.STEEL_WALL}))
	_ok("маяк без чертежа закрыт", not DB.recipe_unlocked({"out": IDs.I.PHAROS}))
	var first: int = Game.give_next_blueprint()
	# Порядок BLUEPRINT_ORDER: смесителя ещё нет (#165), первый доступный — маяк.
	_ok("первый чертёж — маяк, стена всё ещё закрыта", first == IDs.I.PHAROS
			and Game.has_blueprint(IDs.I.PHAROS) and DB.recipe_unlocked({"out": IDs.I.PHAROS})
			and not DB.recipe_unlocked({"out": IDs.I.STEEL_WALL}),
			"выдан %s" % DB.item_name(first))
	_ok("рецептов достаточно", DB.recipes.size() >= 30, "n=%d" % DB.recipes.size())
	# Релей: только существующие предметы, количества положительные.
	var bad_relay: bool = false
	for id in DB.relay_req.keys():
		if not DB.item_defs.has(int(id)) or int(DB.relay_req[id]) <= 0:
			bad_relay = true
	_ok("требования релея корректны", not bad_relay and DB.relay_req.size() >= 4, str(DB.relay_req))
	# Текстуры предметов: у каждого есть непрозрачные пиксели — ловит забытую форму.
	var blank_items: Array = []
	for id in DB.item_defs.keys():
		if int(id) == IDs.I.NONE:
			continue
		if _opaque_pixels(DB.item_texture(int(id)).get_image(), Vector2i.ZERO) == 0:
			blank_items.append(DB.item_name(int(id)))
	_ok("у каждого предмета есть текстура", blank_items.is_empty(), str(blank_items))
	# Атлас: каждый тайл, кроме воздуха, нарисован.
	var atlas: Image = DB.atlas_texture.get_image()
	var blank_tiles: Array = []
	for id in range(1, IDs.TILE_COUNT):
		var a: Vector2i = DB.atlas_of_tile[id]
		if _opaque_pixels(atlas, a * DB.TILE_SIZE) == 0:
			blank_tiles.append(DB.tile_name(id))
	_ok("каждый тайл нарисован", blank_tiles.is_empty(), str(blank_tiles))
	# Копаемость для копателя (§ 4.4): порода — да, построенное — нет.
	_ok("копатель роет породу, но не постройки",
			DB.tile_diggable(IDs.T.STONE) and DB.tile_diggable(IDs.T.DIRT)
			and not DB.tile_diggable(IDs.T.IRON_BLOCK) and not DB.tile_diggable(IDs.T.STEEL_WALL))
	# Balance: все числа положительные (INF — «никогда» — тоже положительное).
	var consts: Dictionary = load("res://scripts/core/balance.gd").get_script_constant_map()
	var nonpos: Array = []
	for k in consts.keys():
		_collect_nonpositive(consts[k], String(k), nonpos)
	_ok("константы Balance положительные", consts.size() >= 30 and nonpos.is_empty(),
			"констант %d, плохих %s" % [consts.size(), str(nonpos)])
	_check_style_v1(atlas)


# --- ADR-003 V1 (#103): палитра, варианты атласа, биомы по глубине -----------
func _check_style_v1(atlas: Image) -> void:
	# Каждый вариант атласа нарисован и твёрдые тайлы непрозрачны целиком («всё квадратное»).
	var holes: Array = []
	for id in range(1, IDs.TILE_COUNT):
		for v in DB.VARIANTS:
			var c: Vector2i = DB.atlas_var[id * DB.VARIANTS + v]
			var n: int = _opaque_pixels(atlas, c * DB.TILE_SIZE) if c.x >= 0 else 0
			var need: int = DB.TILE_SIZE * DB.TILE_SIZE if DB.tile_solid(id) and id != IDs.T.GLASS else 1
			if n < need:
				holes.append("%s/%d" % [DB.tile_name(id), v])
				break
	_ok("V1: все варианты атласа нарисованы, твёрдые — сплошной квадрат", holes.is_empty(), str(holes))
	# Руды различимы при дейтеранопии (ADR-003 § 5): ΔE (CIE76) между любыми двумя ≥ 20.
	var ores: Array = DB.ORE_PAL.keys()
	var worst: float = 999.0
	var pair: String = ""
	for i in ores.size():
		for j in range(i + 1, ores.size()):
			var a: Color = DB.deutan(DB.PAL[DB.ORE_PAL[ores[i]]])
			var b: Color = DB.deutan(DB.PAL[DB.ORE_PAL[ores[j]]])
			var de: float = DB.delta_e(a, b)
			if de < worst:
				worst = de
				pair = "%s/%s" % [DB.ORE_PAL[ores[i]], DB.ORE_PAL[ores[j]]]
	_ok("V1: руды различимы при дейтеранопии (мин. ΔE ≥ 20)", worst >= 20.0, "мин. ΔE %.1f (%s)" % [worst, pair])
	# Биомы по глубине: у поверхности — поверхность, у дна — глубина; камень в разных
	# биомах — разные клетки атласа, а тайл (id) тот же.
	var bx: int = World.beacon_cell.x
	var top: int = int(World.surface[bx])
	_ok("V1: биомы по глубине (поверхность → пещеры → глубина)",
			World.biome_at(bx, top + 2) == 0 and World.biome_at(bx, top + int((World.H - top) * 0.4)) == 1
			and World.biome_at(bx, World.H - 5) == 2,
			"%d/%d/%d" % [World.biome_at(bx, top + 2), World.biome_at(bx, top + int((World.H - top) * 0.4)),
			World.biome_at(bx, World.H - 5)])
	var s0: Vector2i = DB.atlas_var[IDs.T.STONE * DB.VARIANTS + DB.variant_index(0, 0, 0)]
	var s2: Vector2i = DB.atlas_var[IDs.T.STONE * DB.VARIANTS + DB.variant_index(2, 0, 0)]
	_ok("V1: камень на поверхности и в глубине — разные клетки атласа", s0 != s2, "%s / %s" % [s0, s2])


## Число непрозрачных пикселей в квадрате TILE_SIZE от origin.
func _opaque_pixels(img: Image, origin: Vector2i) -> int:
	if img == null:
		return 0
	var n: int = 0
	for y in DB.TILE_SIZE:
		for x in DB.TILE_SIZE:
			if img.get_pixel(origin.x + x, origin.y + y).a > 0.05:
				n += 1
	return n


## Собирает пути к неположительным числам внутри константы (словари — рекурсивно).
func _collect_nonpositive(v, path: String, out: Array) -> void:
	if v is Dictionary:
		for k in v.keys():
			_collect_nonpositive(v[k], "%s.%s" % [path, str(k)], out)
	elif v is Array:
		for i in v.size():
			_collect_nonpositive(v[i], "%s[%d]" % [path, i], out)
	elif v is int or v is float:
		if not (float(v) > 0.0):
			out.append(path)
	elif v is String:
		pass


# ------------------------------------------------------------- сутки (ADR-001, #24)

func _t_day_noon() -> void:
	print("== Сутки ==")
	var ns: float = Balance.NIGHT_START
	var ne: float = Balance.NIGHT_END
	_ok("ночь начинается с NIGHT_START", _night_at(ns) and not _night_at(ns - 0.01), "%.2f" % ns)
	_ok("ночь кончается на NIGHT_END", _night_at(ne - 0.01) and not _night_at(ne), "%.2f" % ne)
	var jump: float = _daylight_max_jump()
	_ok("свет без скачков", jump < 0.2, "макс. скачок за сотую цикла %.3f" % jump)
	_ok("солнце гаснет ровно к ночи",
			_daylight_at(ns) <= Balance.SOLAR_MIN_DAYLIGHT + 0.001
			and _daylight_at(ns - 0.02) > Balance.SOLAR_MIN_DAYLIGHT,
			"daylight(%.2f)=%.2f" % [ns, _daylight_at(ns)])
	_ok("цикл суток 240 с", Game.DAY_LENGTH >= 240.0, "%.0f с" % Game.DAY_LENGTH)
	# Полдень: смена меняться не должна. Регресс: раньше day_number = 1 + int(t * 2)
	# прыгал на t = 0.5 и дважды за цикл слал «Смена N».
	_day0 = Game.day_number
	_day_signals = 0
	Game.day_started.connect(_on_day_started)
	Game.time_of_day = 0.499
	_next(12, 0.6)   # 0.6 с = 0.0025 цикла → t ≈ 0.5015, полдень пройден


func _t_day_dawn() -> void:
	_ok("смена не меняется в полдень", Game.day_number == _day0 and _day_signals == 0,
			"t=%.3f смена %d" % [Game.time_of_day, Game.day_number])
	# Рассвет: ставим время за 0.001 цикла (0.24 с) до конца ночи —
	# через 0.7 с смена должна вырасти ровно на единицу.
	Game.time_of_day = Balance.NIGHT_END - 0.001
	_next(13, 0.7)


func _t_day_result() -> void:
	_ok("смена растёт на рассвете", Game.day_number == _day0 + 1,
			"было %d, стало %d, t=%.3f" % [_day0, Game.day_number, Game.time_of_day])
	_ok("day_started пришёл один раз", _day_signals == 1, "n=%d" % _day_signals)
	Game.day_started.disconnect(_on_day_started)
	_next(14)


func _on_day_started(_day: int) -> void:
	_day_signals += 1


## is_night() в заданный момент цикла, не трогая текущее время.
func _night_at(t: float) -> bool:
	var saved: float = Game.time_of_day
	Game.time_of_day = t
	var r: bool = Game.is_night()
	Game.time_of_day = saved
	return r


func _daylight_at(t: float) -> float:
	var saved: float = Game.time_of_day
	Game.time_of_day = t
	var r: float = Game.daylight()
	Game.time_of_day = saved
	return r


## Максимальный скачок daylight() между соседними сотыми цикла.
func _daylight_max_jump() -> float:
	var worst: float = 0.0
	var prev: float = _daylight_at(0.0)
	for i in range(1, 100):
		var cur: float = _daylight_at(float(i) / 100.0)
		worst = maxf(worst, absf(cur - prev))
		prev = cur
	return worst


func _t_relay() -> void:
	print("== Релей ==")
	for id in Game.relay_req.keys():
		player.inv.add(int(id), int(Game.relay_req[id]) + 2)
	var ok: bool = Game.try_finish()
	_ok("релей запущен", ok)
	_ok("таймер идёт", Game.relay_active and Game.relay_timer > 0.0)
	Game.relay_timer = 0.05
	_next(15, 0.5)


## Вода должна течь. Ставим воду на ровную землю, рядом копаем настоящую яму
## и смотрим, стекла ли вода вниз.
func _t_water_dig() -> void:
	print("== Вода ==")
	var bx: int = World.beacon_cell.x
	# Ищем две соседние колонки с одинаковой высотой земли: на ровном месте
	# вода не растекается по сторонам, а копится в яме.
	var found: bool = false
	for x in range(bx + 8, min(bx + 60, World.W - 2)):
		var g: int = World.surface[x]
		if g != World.surface[x + 1]:
			continue
		if World.get_tile(x, g - 1) != IDs.T.AIR:
			continue
		if World.get_tile(x + 1, g - 1) != IDs.T.AIR:
			continue
		if World.get_tile(x + 1, g) == IDs.T.AIR:
			continue
		water_src = Vector2i(x, g - 1)
		water_hole = Vector2i(x + 1, g)
		found = true
		break
	_ok("нашлась ровная площадка под воду", found,
			"источник %s, яма %s" % [str(water_src), str(water_hole)])
	if not found:
		_next(16, 1.0)
		return
	World.set_tile(water_src.x, water_src.y, IDs.T.WATER)
	# Яма: копаем клетку земли у соседней колонки.
	World.set_tile(water_hole.x, water_hole.y, IDs.T.AIR)
	_ok("вода поставлена", World.get_tile_v(water_src) == IDs.T.WATER)
	_ok("яма выкопана", World.get_tile_v(water_hole) == IDs.T.AIR)
	_next(16, 1.0)


func _t_water_check() -> void:
	var lvl: int = World.fluid_level(water_hole)
	_ok("вода стекла в выкопанную яму", lvl > 0, "уровень %d" % lvl)
	_ok("в яме появилась вода", World.get_tile_v(water_hole) == IDs.T.WATER,
			"тайл %d" % World.get_tile_v(water_hole))
	# По ровной земле вода расползаться не должна: иначе озеро растеклось бы
	# плёнкой по всей площадке.
	var flat: Vector2i = Vector2i(water_src.x - 2, water_src.y)
	_ok("вода не растеклась по ровной земле",
			World.get_tile_v(flat) != IDs.T.WATER and World.fluid_level(flat) == 0,
			"клетка %s тайл %d" % [str(flat), World.get_tile_v(flat)])
	_next(17)


func _t_anim_start() -> void:
	# Секция «== Анимации ==»: те же самые проверки, что и в tools/anim_test.gd.
	# Общий код — дублирования нет.
	anim = AnimTestScript.Runner.new(self)
	add_child(anim)
	anim.start(scene)
	_next(18, 0.2)


func _t_anim_wait() -> void:
	if anim == null:
		_next(19)
		return
	if anim.done:
		checks += anim.checks
		fails += anim.fails
		anim.queue_free()
		anim = null
		_next(19, 0.2)


func _t_power_start() -> void:
	# Секция «== Индекс питания ==»: те же проверки, что и в tools/power_test.gd.
	# Общий код — дублирования нет.
	power = PowerTestScript.Runner.new(self)
	add_child(power)
	power.start(scene)
	_next(20, 0.2)


func _t_power_wait() -> void:
	if power == null:
		_next(21)
		return
	if power.done:
		checks += power.checks
		fails += power.fails
		power.queue_free()
		power = null
		_next(21, 0.2)


func _t_lore_start() -> void:
	# Секция «== Лор ==»: те же проверки, что и в tools/lore_test.gd.
	# Общий код — дублирования нет. Проверки синхронные, мир не трогают.
	lore = LoreTestScript.Runner.new(self)
	add_child(lore)
	lore.start(scene)
	_next(22, 0.1)


func _t_lore_wait() -> void:
	if lore == null:
		_next(23)
		return
	if lore.done:
		checks += lore.checks
		fails += lore.fails
		lore.queue_free()
		lore = null
		_next(23, 0.1)


# --- Звук (issue #36) ---------------------------------------------------------
func _t_sfx_start() -> void:
	# Секция «== Звук ==»: те же проверки, что и в tools/sfx_test.gd.
	sfx_t = SfxTestScript.Runner.new(self)
	add_child(sfx_t)
	sfx_t.start(scene)
	_next(24, 0.1)


func _t_sfx_wait() -> void:
	if sfx_t == null:
		_next(25)
		return
	if sfx_t.done:
		checks += sfx_t.checks
		fails += sfx_t.fails
		sfx_t.queue_free()
		sfx_t = null
		_next(25, 0.1)


# --- Сохранение (issue #37) ----------------------------------------------------
func _t_save_start() -> void:
	# Секция «== Сохранение ==»: те же проверки, что и в tools/save_test.gd, на сиде прогона.
	save_t = SaveTestScript.Runner.new(self)
	add_child(save_t)
	save_t.start(scene, [int(scene.get("seed_value"))])
	_next(26, 0.1)


func _t_save_wait() -> void:
	if save_t == null:
		_next(30)
		return
	if save_t.done:
		checks += save_t.checks
		fails += save_t.fails
		save_t.queue_free()
		save_t = null
		_next(30, 0.1)


# --- Размер интерфейса (#159) --------------------------------------------------
func _t_ui_scale_start() -> void:
	# Секция «== Размер интерфейса ==»: tools/ui_scale_test.gd. Идёт до меню: меню меняет сцену.
	ui_scale_t = UiScaleTestScript.new()
	add_child(ui_scale_t)
	ui_scale_t.start(scene)
	_next(31, 0.1)


func _t_ui_scale_wait() -> void:
	if ui_scale_t == null or ui_scale_t.done:
		if ui_scale_t != null:
			checks += ui_scale_t.checks
			fails += ui_scale_t.fails
			ui_scale_t.queue_free()
			ui_scale_t = null
		_next(32)


func _t_hotbar_start() -> void:
	hotbar_t = HotbarTestScript.new()
	add_child(hotbar_t)
	hotbar_t.start(scene)
	_next(33, 0.1)


func _t_hotbar_wait() -> void:
	if hotbar_t == null or hotbar_t.done:
		if hotbar_t != null:
			checks += hotbar_t.checks
			fails += hotbar_t.fails
			hotbar_t.queue_free()
			hotbar_t = null
		_next(27, 0.1)


# --- Меню и профиль (ADR-002, MP-B, #87) ---------------------------------------
func _t_menu_start() -> void:
	# Секция «== Меню и профиль ==»: те же проверки, что и в tools/menu_test.gd,
	# без смены сцены и замера (они — только в отдельном запуске).
	menu_t = MenuTestScript.Runner.new(self)
	add_child(menu_t)
	menu_t.start(scene)
	_next(28, 0.1)


func _t_menu_wait() -> void:
	if menu_t == null:
		_next(29)
		return
	if menu_t.done:
		checks += menu_t.checks
		fails += menu_t.fails
		menu_t.queue_free()
		menu_t = null
		_next(29, 0.1)


func _t_finish() -> void:
	print("== Производительность ==")
	var avg_ms: float = _frame_sum_ms / maxf(1.0, float(_frame_n))
	# Это предупреждение, а не провал: fails здесь не растёт.
	print("  ПРЕДУПРЕЖДЕНИЕ  время кадра: среднее %.2f мс, максимум %.2f мс, кадров > 100 мс: %d из %d (не провал)"
			% [avg_ms, _frame_max_ms, _frame_slow, _frame_n])
	print("== Финал ==")
	_ok("состояние WON", Game.state == Game.State.WON, "state=%d" % Game.state)
	print("")
	print("ИТОГ: проверок %d, провалов %d" % [checks, fails])
	get_tree().quit(1 if fails > 0 else 0)


# ------------------------------------------------------------------ тайники руин (#35)

## В каждой руине — сундук с 3–6 предметами по роли хозяина (Lore.ruin_owner)
## и табличка с именем из Lore. Содержимое и имена детерминированы сидом мира.
func _check_ruin_caches() -> void:
	print("== Тайники руин ==")
	var caches: Array = World.ruin_caches
	_ok("у каждой руины есть тайник", caches.size() == Lore.RUIN_COUNT,
			"%d из %d, генерация %.2f мс" % [caches.size(), Lore.RUIN_COUNT, World.ruin_cache_ms])
	var no_chest: Array = []
	var bad_n: Array = []
	var bad_role: Array = []
	var bad_det: Array = []
	var bad_name: Array = []
	var names: Array = []
	for c in caches:
		var i: int = int(c["index"])
		var chest = c["chest"]
		if chest == null or not is_instance_valid(chest) or World.machines.get(c["cell"]) != chest:
			no_chest.append(i)
			continue
		var items: Array = []
		for s in chest.slots:
			if not s.is_empty():
				items.append([s.id, s.count])
		if items.size() < World.RUIN_CACHE_MIN or items.size() > World.RUIN_CACHE_MAX:
			bad_n.append("%d:%d" % [i, items.size()])
		var role: String = String(Lore.ruin_owner(i)["role"])
		var allowed: Array = []
		for e in World.RUIN_LOOT.get(role, []):
			allowed.append(int(e[0]))
		for it in items:
			if c["role"] != role or not allowed.has(int(it[0])):
				bad_role.append("%d:%s:%s" % [i, role, DB.item_name(int(it[0]))])
		if items != World.ruin_cache_loot(i, role):
			bad_det.append(i)
		var nm: String = Lore.place_name("ruin", i)
		if nm == "" or c["name"] != nm or not is_instance_valid(c["sign"]) or c["sign"].title != nm:
			bad_name.append(i)
		names.append(nm)
	_ok("в каждом тайнике сундук", no_chest.is_empty(), str(no_chest))
	_ok("в тайнике 3–6 предметов", bad_n.is_empty(), str(bad_n))
	_ok("предметы по роли хозяина руины", bad_role.is_empty(), str(bad_role))
	_ok("содержимое тайника определено сидом", bad_det.is_empty(), str(bad_det))
	_ok("табличка с именем места из Lore", bad_name.is_empty(), str(bad_name))
	# Имена по сиду: тот же сид — те же имена, другой сид — другие. Lore после
	# проверки возвращаем к сиду мира.
	var quiet0: bool = Lore.quiet
	Lore.quiet = true
	var other: Array = []
	Lore.generate(World.world_seed + 1)
	for i in Lore.RUIN_COUNT:
		other.append(Lore.place_name("ruin", i))
	Lore.generate(World.world_seed)
	var again: Array = []
	for i in Lore.RUIN_COUNT:
		again.append(Lore.place_name("ruin", i))
	Lore.quiet = quiet0
	_ok("имена мест детерминированы сидом", again == names, str(names))
	_ok("другой сид — другие имена мест", other != names, str(other))
	_check_ruin_terminals()


## Терминалы и главы журнала (#29): в каждой руине — терминал с главой
## BASE_TERMINALS + i, на базе — два терминала с главами 0–1. Раньше стены руины
## занимали весь нижний ряд, и терминал руины не ставился ни на одном сиде.
func _check_ruin_terminals() -> void:
	var no_term: Array = []
	for c in World.ruin_caches:
		var i: int = int(c["index"])
		var found: bool = false
		for t in World.terminals:
			if int(World.terminal_chapters.get(t, -1)) == Lore.BASE_TERMINALS + i \
					and World.get_tile_v(t) == IDs.T.TERMINAL and absi(t.x - int(c["cell"].x)) <= 8:
				found = true
		if not found:
			no_term.append(i)
	_ok("в каждой руине есть терминал", not World.ruin_caches.is_empty() and no_term.is_empty(),
			"без терминала: %s" % str(no_term))
	var chapters: Array = []
	for t in World.terminals:
		chapters.append(int(World.terminal_chapters.get(t, -1)))
	chapters.sort()
	_ok("у каждого терминала своя глава журнала", chapters == range(Lore.chapter_count()),
			"терминалов %d, главы %s" % [World.terminals.size(), str(chapters)])


# ------------------------------------------------------- небесный тайник (#60)

## Обломок «Кербер-9» в небе: есть, каждая его клетка выше прыжка героя (с ростом)
## над рельефом под ней, в пределах мира, миникарта (рельеф World.surface) его не
## видит, в сундуке 3–6 предметов из Balance.SKY_LOOT, всё определено сидом.
func _check_sky_cache() -> void:
	print("== Небесный тайник ==")
	var sc: Dictionary = World.sky_cache
	var chest = sc.get("chest")
	_ok("обломок с тайником есть", not sc.is_empty() and chest != null and is_instance_valid(chest)
			and World.machines.get(sc.get("cell")) == chest,
			"«%s», нос x=%d, пол y=%d, генерация %.2f мс"
			% [String(sc.get("name", "")), int(sc.get("x0", -1)), int(sc.get("floor_y", -1)), World.sky_cache_ms])
	if sc.is_empty():
		return
	# Прыжок с места: v²/2g; достать до клетки — подняться ногами на высоту роста выше неё.
	var jump_px: float = Player.JUMP_VELOCITY * Player.JUMP_VELOCITY / (2.0 * Player.GRAVITY)
	var reach_px: float = jump_px + Player.SIZE.y
	var low: Array = []
	var min_gap: int = 999
	var out_of_world: Array = []
	var on_map: Array = []
	for c in World.sky_cells:
		var gap: int = World.sky_ground(c.x, c.x) - c.y - 1
		min_gap = mini(min_gap, gap)
		if float(gap * World.TILE) <= reach_px:
			low.append(c)
		if c.y < Balance.SKY_TOP_MARGIN or c.x < 0 or c.x >= World.W:
			out_of_world.append(c)
		if World.surface[c.x] <= c.y:
			on_map.append(c)
	_ok("обломок выше прыжка над рельефом под ним", low.is_empty() and min_gap >= Balance.SKY_CLEARANCE_MIN,
			"зазор от %d клеток (%d px) > прыжок %.0f px + рост %.0f px; низко: %s"
			% [min_gap, min_gap * World.TILE, jump_px, Player.SIZE.y, str(low.slice(0, 4))])
	_ok("обломок в пределах мира", out_of_world.is_empty(), str(out_of_world.slice(0, 4)))
	_ok("миникарта (рельеф) обломок не видит", on_map.is_empty(), str(on_map.slice(0, 4)))
	var items: Array = []
	for s in chest.slots:
		if not s.is_empty():
			items.append([s.id, s.count])
	var foreign: Array = []
	for it in items:
		if not Balance.SKY_LOOT.has(int(it[0])):
			foreign.append(DB.item_name(int(it[0])))
	_ok("в небесном тайнике 3–6 предметов", items.size() >= Balance.SKY_CACHE_MIN
			and items.size() <= Balance.SKY_CACHE_MAX and foreign.is_empty(),
			"%d: %s" % [items.size(), str(items)])
	var plan: Dictionary = World.sky_plan()
	var same: bool = not plan.is_empty()
	for k in plan.keys():
		if plan[k] != sc.get(k):
			same = false
	_ok("тайник определён сидом", same and items == World.sky_cache_loot()
			and sc.get("fragment") == World.sky_fragment(), str(plan))
	var frag: String = String(sc.get("fragment", ""))
	_ok("в самописце обрывок журнала", frag != "" and not frag.contains("{"), "«%s»" % frag)
# ------------------------------------------------------------- оборона (#31)

## Вентиляции и оборона (#31): генератор мира ставит Balance.VENTS_RANDOM
## вентиляций на полу пещер (раньше на сиде 31337 выходила одна), флаги тайлов
## dig/phantom_solid, реестры шлюзов и решёток, свет прожектора.
func _check_defense() -> void:
	print("== Оборона ==")
	var bad: Array = []
	for v in World.vents:
		if World.get_tile_v(v) != IDs.T.AIR or not World.is_solid_cell(v + Vector2i(0, 1)):
			bad.append(v)
	_ok("вентиляций в мире достаточно", World.vents.size() >= Balance.VENTS_RANDOM - 2,
			"n=%d (случайных %d + база)" % [World.vents.size(), Balance.VENTS_RANDOM])
	_ok("вентиляции стоят на полу пещер", bad.is_empty(), str(bad))
	_ok("флаги тайлов: шлюз — стена для фантома всегда, для героя — когда закрыт",
			DB.tile_solid(IDs.T.AIRLOCK) and not DB.tile_solid(IDs.T.AIRLOCK_OPEN)
			and World._psolid_tbl[IDs.T.AIRLOCK_OPEN] == 1 and World._psolid_tbl[IDs.T.AIR] == 0)
	_ok("флаг dig: камень — да, стальная стена и шлюз — нет",
			World.is_diggable(IDs.T.STONE) and not World.is_diggable(IDs.T.STEEL_WALL)
			and not World.is_diggable(IDs.T.AIRLOCK))
	# Реестры заполняются через set_tile и чистятся при снятии тайла.
	var c: Vector2i = Vector2i(World.beacon_cell.x - 15, World.beacon_cell.y - 4)
	var t0: int = World.get_tile_v(c)
	World.set_tile(c.x, c.y, IDs.T.AIRLOCK)
	var in_reg: bool = World.airlocks.has(c) and World.astar.is_point_solid(c)
	World.set_tile(c.x, c.y, IDs.T.VENT_GRATE)
	var sealed: bool = World.vents_sealed.has(c) and not World.airlocks.has(c)
	World.set_tile(c.x, c.y, t0)
	_ok("реестры шлюзов и решёток следуют за set_tile", in_reg and sealed
			and not World.airlocks.has(c) and not World.vents_sealed.has(c))
	# Свет прожектора: публичный источник, light_at его видит, снятие — убирает.
	var p: Vector2 = World.cell_to_world(c)
	var far: Vector2i = c + Vector2i(8, 0)
	var l0: float = World.light_at(far)
	var n0: int = World.lights.size()
	var h: Dictionary = World.add_light_source(p, Floodlight.light_radius(), Balance.FLOODLIGHT_POWER)
	var lit: float = World.light_at(far)
	var near: bool = World.get_lights_near(Rect2(p, Vector2(1, 1))).has(h)
	World.remove_light_source(h)
	_ok("add/remove_light_source: свет ≈ 10 клеток, снимается без следа",
			is_equal_approx(lit, l0 + Balance.FLOODLIGHT_POWER) and near and World.lights.size() == n0
			and is_equal_approx(World.light_at(far), l0),
			"свет в 8 клетках %.2f → %.2f, источников %d → %d" % [l0, lit, n0, World.lights.size()])
