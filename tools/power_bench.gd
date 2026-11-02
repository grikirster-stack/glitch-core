extends SceneTree
## Замер стоимости питания (issue #25, ADR-001 § 4.3).
##
## Ставит 6 ТЭЦ и 200 потребителей (буры, плавильни, сборщики) и меряет:
##   * «опрос» — 200 вызовов Game.is_powered(): столько стоил тик питания до
##     PR-B, когда каждый потребитель сам спрашивал питание раз в 0.25 с;
##   * «раскладка» — один вызов Game.update_power_budget(): тик питания после
##     PR-B (раскладка потребителей по генераторам + load + efficiency);
##   * Game.is_powered() ×100 — не должен деградировать.
## Если раскладки в коде ещё нет (замер «до» на старом main), её строка пропускается.
##
## Запуск:
##   godot --headless --path . --script res://tools/power_bench.gd -- --seed=31337
##
## Внимание: в режиме --script имена автозагрузок недоступны при компиляции —
## узлы берём через get_node(), как в tools/power_test.gd.

const GENERATORS: int = 6
const CONSUMERS: int = 200
const TICKS: int = 400          ## сколько тиков меряем (берём медиану)
const WARMUP: int = 20

var _scene: Node = null
var _frame: int = 0
var _seed_value: int = 31337


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
	if _frame == 8:
		_measure()
		quit(0)
		return true
	return false


func _setup() -> void:
	var world = root.get_node("World")
	var mb: GDScript = load("res://scripts/machines/machine_base.gd")
	var player = _scene.get("player")
	if player:
		player.invuln = 1.0e9
	# Площадка: 6 ТЭЦ в ряд через 10 клеток, под ними 4 ряда по 50 потребителей.
	var origin: Vector2i = Vector2i(20, world.beacon_cell.y + 8)
	for x in range(origin.x - 2, origin.x + 62):
		for y in range(origin.y - 2, origin.y + 6):
			world.set_tile(x, y, 0)
	for i in GENERATORS:
		var c: Vector2i = origin + Vector2i(i * 10 + 4, 0)
		mb.place_machine("CoalGen", c)
		var g = world.machines.get(c)
		if g:
			g.add_fuel(12)
			g.power_active = true
	var kinds: Array = ["Drill", "Smelter", "Assembler"]
	var n: int = 0
	for row in 4:
		for col in 50:
			if n >= CONSUMERS:
				break
			mb.place_machine(kinds[n % 3], origin + Vector2i(col + 2, row + 2))
			n += 1


func _measure() -> void:
	var game = root.get_node("Game")
	var world = root.get_node("World")
	var pts: Array[Vector2] = []
	for m in world.machines.values():
		if m.has_method("consumes_power") and m.consumes_power():
			pts.append(m.global_position)
	print("== Замер питания ==")
	print("  генераторов %d, потребителей %d" % [GENERATORS, pts.size()])
	# Замеры чередуются в одном цикле: фоновая нагрузка машины (CI, соседние
	# процессы) делится между ними поровну, медианы сравнимы между собой.
	var has_budget: bool = game.has_method("update_power_budget")
	var poll: Array = []
	var single: Array = []
	var lay: Array = []
	var cold: Array = []
	for t in TICKS + WARMUP:
		# Опрос: 200 × is_powered — тик питания старой схемы.
		var t0: int = Time.get_ticks_usec()
		for p in pts:
			game.is_powered(p)
		var t1: int = Time.get_ticks_usec()
		# is_powered ×100.
		for i in 100:
			game.is_powered(pts[i % pts.size()])
		var t2: int = Time.get_ticks_usec()
		var t3: int = t2
		var t4: int = t2
		var t5: int = t2
		if has_budget:
			# Раскладка (PR-B): установившийся режим — итог у машин не менялся.
			game.update_power_budget()
			t3 = Time.get_ticks_usec()
			# Худший случай: итог сменился у всех потребителей (все apply_power).
			game._power_consumer_state.fill(-1.0)
			t4 = Time.get_ticks_usec()
			game.update_power_budget()
			t5 = Time.get_ticks_usec()
		if t >= WARMUP:
			poll.append(t1 - t0)
			single.append(t2 - t1)
			lay.append(t3 - t2)
			cold.append(t5 - t4)
	print("  опрос %d × is_powered (схема до PR-B): медиана %d мкс/тик, мин %d" % [
			pts.size(), _median(poll), poll.min()])
	print("  is_powered ×100: медиана %d мкс, мин %d" % [_median(single), single.min()])
	if has_budget:
		print("  раскладка update_power_budget: медиана %d мкс/тик, мин %d" % [_median(lay), lay.min()])
		print("  раскладка, итог сменился у всех: медиана %d мкс/тик, мин %d" % [_median(cold), cold.min()])
		print("  нагрузка %.1f / мощность %.1f, браун-аут %s" % [
				float(game.power_load_total), float(game.power_output_total), str(game.brownout)])
	else:
		print("  раскладки в коде нет (замер «до»)")


func _median(a: Array) -> int:
	a.sort()
	return int(a[a.size() / 2])
