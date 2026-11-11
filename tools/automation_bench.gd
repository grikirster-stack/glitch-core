extends SceneTree
## Замер автоматизации (issue #30, ADR-001 § 4.2).
##
##   * 100 манипуляторов (сундук → манипулятор → сундук), мкс на тик: все
##     переносят («в работе») и все без дела («простой» — источник пуст);
##   * пропускная способность линий за 120 с симуляции с шагом 1/60 с:
##       — сундук → манипулятор → лента → плавильня → лента → сундук (слитков/мин);
##       — бур → плавильня (слитки) → манипулятор → плавильня (пластины) →
##         манипулятор → сборщик (микросхемы) → лента → сундук: стартовая линия
##         § 4.2 (руда, слитки, пластины, микросхемы в минуту).
## Машины замеряемых линий шагаются вручную (_process с фиксированным delta,
## их собственная обработка выключена) — замер не зависит от частоты кадров.
##
## Запуск:
##   godot --headless --path . --script res://tools/automation_bench.gd -- --seed=31337
##
## В режиме --script имена автозагрузок недоступны при компиляции — узлы
## берём через get_node(), как в tools/power_bench.gd.

const INSERTERS: int = 100
const TICKS: int = 400
const WARMUP: int = 20
const DT: float = 1.0 / 60.0
const SIM_SECS: float = 120.0

var _scene: Node = null
var _frame: int = 0
var _seed_value: int = 31337
var _world: Node = null
var _game: Node = null
var _mb: GDScript = null

var _bench_ins: Array = []        ## манипуляторы замера тика
var _bench_src: Array = []        ## их сундуки-источники
var _line1: Array = []            ## машины линии 1 в порядке шага
var _line2: Array = []
var _l1_out: Node = null
var _l2_out: Node = null
var _l2_drill: Node = null
var _l2_sm_a: Node = null
var _l2_sm_b: Node = null
var _l2_asm: Node = null


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			_seed_value = int(a.substr(7))


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		seed(_seed_value)
		_scene = load("res://scenes/main.tscn").instantiate()
		root.add_child(_scene)
		current_scene = _scene
		return false
	if _frame == 3:
		_setup()
		return false
	if _frame == 10:
		_measure_inserters()
		_measure_lines()
		quit(0)
		return true
	return false


func _setup() -> void:
	_world = root.get_node("World")
	_game = root.get_node("Game")
	_mb = load("res://scripts/machines/machine_base.gd")
	var player = _scene.get("player")
	if player:
		player.invuln = 1.0e9
	# Чертежи стальной стены и решётки — если линия их варит (#169).
	while _game.next_blueprint_name() != "":
		_game.give_next_blueprint()
	var origin: Vector2i = Vector2i(20, _world.beacon_cell.y + 8)
	for x in range(origin.x - 2, origin.x + 64):
		for y in range(origin.y - 2, origin.y + 42):
			_world.set_tile(x, y, 0)
	# 100 манипуляторов: 20 рядов по 5 троек «сундук, манипулятор, сундук»,
	# ТЭЦ под серединой каждого ряда (радиус 8 покрывает ряд в 15 клеток).
	for row in 20:
		var y: int = origin.y + row * 2
		_place("CoalGen", Vector2i(origin.x + 7, y + 1))
		for col in 5:
			var c: Vector2i = Vector2i(origin.x + col * 3, y)
			_place("Chest", c)
			_place("Inserter", c + Vector2i(1, 0))
			_place("Chest", c + Vector2i(2, 0))
			_bench_src.append(_world.machines.get(c))
			_bench_ins.append(_world.machines.get(c + Vector2i(1, 0)))
	# Линия 1: сундук → манипулятор → лента → плавильня → лента → сундук.
	var l1: Vector2i = Vector2i(origin.x + 36, origin.y)
	_place("Chest", l1)
	_place("Inserter", l1 + Vector2i(1, 0))
	_place("Belt", l1 + Vector2i(2, 0))
	_place("Smelter", l1 + Vector2i(3, 0))
	_place("Belt", l1 + Vector2i(4, 0))
	_place("Chest", l1 + Vector2i(5, 0))
	_place("CoalGen", l1 + Vector2i(3, 2))
	_world.machines.get(l1).receive_item(_ids().COPPER_ORE, 99)
	_world.machines.get(l1).receive_item(_ids().COPPER_ORE, 99)
	for i in range(1, 5):
		_line1.append(_world.machines.get(l1 + Vector2i(i, 0)))
	_l1_out = _world.machines.get(l1 + Vector2i(5, 0))
	# Линия 2 (§ 4.2): бур над медной жилой → плавильня → манипулятор →
	# плавильня → манипулятор → сборщик → лента → сундук. Две ТЭЦ: нагрузка 7.
	var l2: Vector2i = Vector2i(origin.x + 36, origin.y + 8)
	_place("Drill", l2)
	_place("Smelter", l2 + Vector2i(1, 0))
	_place("Inserter", l2 + Vector2i(2, 0))
	_place("Smelter", l2 + Vector2i(3, 0))
	_place("Inserter", l2 + Vector2i(4, 0))
	_place("Assembler", l2 + Vector2i(5, 0))
	_place("Belt", l2 + Vector2i(6, 0))
	_place("Chest", l2 + Vector2i(7, 0))
	_place("CoalGen", l2 + Vector2i(1, 3))
	_place("CoalGen", l2 + Vector2i(6, 3))
	for i in 7:
		_line2.append(_world.machines.get(l2 + Vector2i(i, 0)))
	_l2_drill = _line2[0]
	_l2_sm_a = _line2[1]
	_l2_sm_b = _line2[3]
	_l2_asm = _line2[5]
	_l2_out = _world.machines.get(l2 + Vector2i(7, 0))
	_l2_asm.receive_item(_ids().CRYSTAL, 999)   ## кристаллы — не узкое место
	_refill_vein()
	for g in _world.machines.values():
		if g.kind == "CoalGen":
			g.add_fuel(12)
	# Замеряемые машины шагаем вручную.
	for m in _bench_ins + _line1 + _line2:
		m.set_process(false)


## Перечисление IDs.I (через load: в режиме --script так надёжнее).
func _ids() -> Dictionary:
	return load("res://scripts/core/ids.gd").I


func _place(kind: String, c: Vector2i) -> void:
	_mb.place_machine(kind, c)
	var b = _world.belts.get(c)
	if b:
		b.dir = 0


## Медная жила под буром второй линии: вся шахта — руда, бур не простаивает.
func _refill_vein() -> void:
	var c: Vector2i = _l2_drill.cell
	for dy in range(1, 17):
		if _world.get_tile(c.x, c.y + dy) == 0:
			_world.set_tile(c.x, c.y + dy, load("res://scripts/core/ids.gd").T.COPPER_ORE)


func _measure_inserters() -> void:
	_game.update_power_budget()
	print("== Замер автоматизации ==")
	var powered: int = 0
	for m in _bench_ins:
		if m.powered:
			powered += 1
	print("  манипуляторов %d, под питанием %d" % [_bench_ins.size(), powered])
	var ore: int = _ids().COPPER_ORE
	# В работе: источники полны, все переносят.
	for s in _bench_src:
		s.receive_item(ore, 99)
	var busy: Array = []
	for t in TICKS + WARMUP:
		var t0: int = Time.get_ticks_usec()
		for m in _bench_ins:
			m._process(DT)
		if t >= WARMUP:
			busy.append(Time.get_ticks_usec() - t0)
	var moved: int = 0
	for m in _bench_ins:
		moved += int(m.moved)
	# Простой: источники пусты, манипуляторы ждут.
	for s in _bench_src:
		for sl in s.slots:
			sl.take(sl.count)
	for m in _bench_ins:
		m.held = 0
	var idle: Array = []
	for t in TICKS + WARMUP:
		var t0: int = Time.get_ticks_usec()
		for m in _bench_ins:
			m._process(DT)
		if t >= WARMUP:
			idle.append(Time.get_ticks_usec() - t0)
	print("  100 манипуляторов в работе: медиана %d мкс/тик, мин %d (перенесено %d за %.1f с)" % [
			_median(busy), busy.min(), moved, float(TICKS + WARMUP) * DT])
	print("  100 манипуляторов в простое: медиана %d мкс/тик, мин %d" % [_median(idle), idle.min()])


func _measure_lines() -> void:
	var ids: Dictionary = _ids()
	var steps: int = int(SIM_SECS / DT)
	var first_circuit: float = -1.0
	var t_sim: float = 0.0
	var ore_mined: int = 0
	var vein_t: float = 0.0
	for i in steps:
		_game.update_power_budget()
		for m in _line1:
			m._process(DT)
		for m in _line2:
			m._process(DT)
		t_sim += DT
		vein_t += DT
		if vein_t >= 1.0:
			vein_t = 0.0
			_refill_vein()
		if first_circuit < 0.0 and _count(_l2_out, ids.CIRCUIT) > 0:
			first_circuit = t_sim
	var ingots: int = _count(_l1_out, ids.COPPER_INGOT)
	var circuits: int = _count(_l2_out, ids.CIRCUIT)
	var minutes: float = SIM_SECS / 60.0
	print("  линия 1 сундук→манипулятор→лента→плавильня→лента→сундук: %.1f слитков/мин" % [
			float(ingots) / minutes])
	print("  линия 2 бур→плавильня→манипулятор→плавильня→манипулятор→сборщик: %.1f микросхем/мин" % [
			float(circuits) / minutes])
	if first_circuit > 0.0 and circuits > 1:
		print("    установившийся темп (после первой микросхемы на %.1f с): %.1f микросхем/мин" % [
				first_circuit, float(circuits - 1) / ((SIM_SECS - first_circuit) / 60.0)])
	print("    наработка (с из %d): бур %.0f, плавильня A %.0f, плавильня B %.0f, сборщик %.0f" % [
			int(SIM_SECS), _l2_drill.work_time, _l2_sm_a.work_time, _l2_sm_b.work_time, _l2_asm.work_time])
	print("    efficiency: бур %.2f, сборщик %.2f; на земле предметов %d" % [
			_l2_drill.efficiency, _l2_asm.efficiency, _ground_items()])


func _count(ch: Node, id: int) -> int:
	var n: int = 0
	for s in ch.slots:
		if not s.is_empty() and s.id == id:
			n += s.count
	return n


func _ground_items() -> int:
	var n: int = 0
	for c in _scene.get_children():
		if c.get_class() == "Node2D" and c.get("item_id") != null:
			n += 1
	return n


func _median(a: Array) -> int:
	a.sort()
	return int(a[a.size() / 2])
