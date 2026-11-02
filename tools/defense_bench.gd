extends SceneTree
## Замер обороны (issue #31, ADR-001 § 4.4):
##   * пересчёт шлюзов World.update_airlocks при 20 шлюзах, мкс/тик
##     (без фантомов и с 16 фантомами у базы);
##   * свет при 10 прожекторах: World.light_at и World.get_lights_near (мкс),
##     и p95 кадра с WorldFX, перерисовываемым каждый кадр (A/B: 0 и 10
##     горящих прожекторов в кадре камеры).
##
## Запуск:
##   godot --headless --path . --script res://tools/defense_bench.gd -- --seed=31337
##
## В режиме --script имена автозагрузок недоступны при компиляции — узлы
## берём через get_node(), скрипты — через load().

const AIRLOCKS: int = 20
const PHANTOMS: int = 16
const TICKS: int = 2000
const FLOODLIGHTS: int = 10
const STAGE_FRAMES: int = 150
const WARMUP_FRAMES: int = 400   ## этап 0 — прогрев, в итог не идёт
const STAGES: int = 16          ## этапов A/B после прогрева (чередуются)
const LIGHT_ROUNDS: int = 5     ## повторов замера света (берём минимум)
const LIGHT_CALLS: int = 4000

var _scene: Node = null
var _world: Node = null
var _fx: Node = null
var _frame: int = 0
var _seed_value: int = 31337
var _stage: int = -1            ## A/B-этапы кадра: чётные — без прожекторов
var _stage_frames: int = 0
var _last_us: int = 0
var _samples: Array = []
var _results: Dictionary = {"без прожекторов": [], "10 прожекторов": []}
var _lights: Array = []
var _gens: Array = []


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
	if _frame == 4:
		_world = root.get_node("World")
		_fx = _scene.get("world_fx")
		_bench_airlocks()
		_bench_light_calls()
		_setup_gens()
		_begin_stage(0)
		return false
	if _stage < 0:
		return false
	return _frame_stage()


# ------------------------------------------------------------------ ШЛЮЗЫ

func _bench_airlocks() -> void:
	var w: Node = _world
	var bx: int = w.beacon_cell.x
	var by: int = w.beacon_cell.y
	var cells: Array = []
	for i in AIRLOCKS:
		var c: Vector2i = Vector2i(bx - 10 + i, by - 6)
		w.set_tile(c.x, c.y, IDs.T.AIRLOCK)
		cells.append(c)
	print("шлюзов в реестре: %d" % w.airlocks.size())
	var ppos: Vector2 = w.cell_to_world(cells[AIRLOCKS / 2]) + Vector2(0, 16)
	var none: PackedVector2Array = PackedVector2Array()
	var ph: PackedVector2Array = PackedVector2Array()
	for i in PHANTOMS:
		ph.append(ppos + Vector2(float(i - PHANTOMS / 2) * 30.0, 120.0))
	for label in ["без фантомов", "16 фантомов"]:
		var list: PackedVector2Array = none if label == "без фантомов" else ph
		var us: Array = []
		for k in TICKS:
			w.update_airlocks(ppos, true, list)
			us.append(int(w.airlock_tick_us))
		print("шлюзы ×%d, %s: медиана %.1f мкс/тик, p95 %d мкс, минимум %d мкс" % [AIRLOCKS, label, _median(us), _p95(us), us.min()])
	for c in cells:
		w.set_tile(c.x, c.y, IDs.T.AIR)


# ------------------------------------------------------------------ СВЕТ

func _bench_light_calls() -> void:
	var w: Node = _world
	var center: Vector2i = w.world_to_cell(w.spawn_point)
	var before: Array = [INF, INF, INF]
	var after: Array = [INF, INF, INF]
	for _r in LIGHT_ROUNDS:
		var b: Array = _light_cost(center)
		var hs: Array = []
		for i in FLOODLIGHTS:
			var p: Vector2 = w.cell_to_world(center + Vector2i(-10 + i * 2, -3))
			hs.append(w.add_light_source(p, 46.0 + 2.0 * 60.0, 2.0))
		var a: Array = _light_cost(center)
		for h in hs:
			w.remove_light_source(h)
		for k in 3:
			before[k] = minf(before[k], b[k])
			after[k] = minf(after[k], a[k])
	print("light_at у прожекторов: без %.2f мкс, с 10 прожекторами %.2f мкс" % [before[0], after[0]])
	print("light_at вдали (200 клеток): без %.2f мкс, с 10 прожекторами %.2f мкс" % [before[2], after[2]])
	print("get_lights_near (кадр камеры): без %.1f мкс, с 10 прожекторами %.1f мкс" % [before[1], after[1]])


## [мкс на light_at, мкс на get_lights_near] вокруг клетки.
func _light_cost(center: Vector2i) -> Array:
	var w: Node = _world
	var t0: int = Time.get_ticks_usec()
	var acc: float = 0.0
	for i in LIGHT_CALLS:
		acc += w.light_at(center + Vector2i((i % 41) - 20, (i / 41) % 21 - 10))
	var la: float = float(Time.get_ticks_usec() - t0) / float(LIGHT_CALLS)
	# Вдали от прожекторов (фантомы в глубине): рамка дальнобойных отсекает список.
	var far: Vector2i = Vector2i((center.x + 200) % w.W, center.y + 40)
	t0 = Time.get_ticks_usec()
	for i in LIGHT_CALLS:
		acc += w.light_at(far + Vector2i((i % 41) - 20, (i / 41) % 21 - 10))
	var lf: float = float(Time.get_ticks_usec() - t0) / float(LIGHT_CALLS)
	var view: Rect2 = Rect2(w.spawn_point - Vector2(480, 270), Vector2(960, 540)).grow(192.0)
	t0 = Time.get_ticks_usec()
	for i in 400:
		w.get_lights_near(view)
	var ln: float = float(Time.get_ticks_usec() - t0) / 400.0
	return [la, ln, lf, acc]


# ------------------------------------------------------------------ КАДР

func _setup_gens() -> void:
	var w: Node = _world
	var mb: GDScript = load("res://scripts/machines/machine_base.gd")
	var center: Vector2i = w.world_to_cell(w.spawn_point)
	for dx in [-4, 6]:
		var c: Vector2i = center + Vector2i(dx, -5)
		w.set_tile(c.x, c.y, IDs.T.AIR)
		if mb.place_machine("CoalGen", c):
			var g = w.machines[c]
			g.add_fuel(g.FUEL_MAX_UNITS)
			_gens.append(g)


func _begin_stage(i: int) -> void:
	_stage = i
	_stage_frames = 0
	_samples.clear()
	_last_us = 0
	var w: Node = _world
	var mb: GDScript = load("res://scripts/machines/machine_base.gd")
	var center: Vector2i = w.world_to_cell(w.spawn_point)
	# Чётный этап — прожекторов нет, нечётный — 10 горящих в кадре.
	for m in _lights:
		if is_instance_valid(m):
			w.machines.erase(m.cell)
			m.queue_free()
	_lights.clear()
	if i % 2 == 1:
		for k in FLOODLIGHTS:
			var c: Vector2i = center + Vector2i(-6 + k, -4)
			w.set_tile(c.x, c.y, IDs.T.AIR)
			if mb.place_machine("Floodlight", c):
				_lights.append(w.machines[c])


func _frame_stage() -> bool:
	var now: int = Time.get_ticks_usec()
	if _last_us > 0 and _stage_frames > 30:
		_samples.append(now - _last_us)
	_last_us = now
	_stage_frames += 1
	if _fx != null:
		_fx.queue_redraw()
	if _stage_frames < (WARMUP_FRAMES if _stage == 0 else STAGE_FRAMES):
		return false
	var key: String = "10 прожекторов" if _stage % 2 == 1 else "без прожекторов"
	var lit: int = 0
	for m in _lights:
		if is_instance_valid(m) and bool(m.lit):
			lit += 1
	print("этап %d, %-16s: кадр среднее %.2f мс, p95 %.2f мс (горит %d, источников света %d)"
			% [_stage, key, _mean(_samples) / 1000.0, float(_p95(_samples)) / 1000.0, lit, _world.lights.size()])
	if _stage > 0:
		_results[key].append(_p95(_samples))
	if _stage >= STAGES:
		var a: float = _median(_results["без прожекторов"]) / 1000.0
		var b: float = _median(_results["10 прожекторов"]) / 1000.0
		print("ИТОГ: p95 кадра с WorldFX (медиана по этапам) — без прожекторов %.2f мс, с 10 прожекторами %.2f мс (%+.1f %%)"
				% [a, b, (b / maxf(a, 0.0001) - 1.0) * 100.0])
		quit(0)
		return true
	_begin_stage(_stage + 1)
	return false


func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s: float = 0.0
	for v in a:
		s += float(v)
	return s / float(a.size())


func _median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var b: Array = a.duplicate()
	b.sort()
	return float(b[b.size() / 2])


func _p95(a: Array) -> int:
	if a.is_empty():
		return 0
	var b: Array = a.duplicate()
	b.sort()
	return int(b[mini(b.size() - 1, int(float(b.size()) * 0.95))])
