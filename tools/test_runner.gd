extends Node
## Автотест игровой логики: копание, подбор, крафт, конвейер, питание, фантомы, релей.
## Плюс секция «== Анимации ==» — общий код из tools/anim_test.gd (issue #6).
## Запускается из main.gd флагом `--test`.
##
## Все паузы отсчитываются по реальному времени, а не по кадрам: в headless-режиме
## частота кадров не гарантирована, а симуляция машин идёт по delta.

## Общий код проверок анимаций: тот же самый, что и в отдельном
## tools/anim_test.gd (issue #6). Дублирования нет — файл подключается один раз.
const AnimTestScript = preload("res://tools/anim_test.gd")

var scene: Node = null
var step: int = 0
var player: Node = null
var fails: int = 0
var checks: int = 0
var anim: Node = null

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
		11: _t_relay()
		12: _t_anim_start()
		13: _t_anim_wait()
		14: _t_finish()


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
			if World.get_tile(x, y) != IDs.T.LOG:
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
	scene._spawn_phantom()
	var after: int = get_tree().get_nodes_in_group("phantom").size()
	_ok("фантом заспавнен", after > before, "%d -> %d" % [before, after])
	var phs: Array = get_tree().get_nodes_in_group("phantom")
	if phs.size() > 0:
		var ph: Node = phs[0]
		var hp0: float = ph.hp
		ph.take_damage(50.0, Vector2.ZERO)
		_ok("фантом получает урон", ph.hp < hp0, "hp=%d" % int(ph.hp))
	_next(11)


func _t_relay() -> void:
	print("== Релей ==")
	for id in Game.relay_req.keys():
		player.inv.add(int(id), int(Game.relay_req[id]) + 2)
	var ok: bool = Game.try_finish()
	_ok("релей запущен", ok)
	_ok("таймер идёт", Game.relay_active and Game.relay_timer > 0.0)
	Game.relay_timer = 0.05
	_next(12, 0.5)


func _t_anim_start() -> void:
	# Секция «== Анимации ==»: те же самые проверки, что и в tools/anim_test.gd.
	# Общий код — дублирования нет.
	anim = AnimTestScript.Runner.new(self)
	add_child(anim)
	anim.start(scene)
	_next(13, 0.2)


func _t_anim_wait() -> void:
	if anim == null:
		_next(14)
		return
	if anim.done:
		checks += anim.checks
		fails += anim.fails
		anim.queue_free()
		anim = null
		_next(14, 0.2)


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
