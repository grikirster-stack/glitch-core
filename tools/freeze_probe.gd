extends SceneTree
## Сторож фризов: гоняет настоящую сцену под нагрузкой и ловит кадры-долготы.
##
## Запуск (headless, так же, как в CI):
##   godot --headless --path . --script res://tools/freeze_probe.gd -- --allow-hitch
## Запуск с окном (добавляются замеры отрисовки):
##   godot --path . --script res://tools/freeze_probe.gd -- --probe --windowed
##
## Ключи (через OS.get_cmdline_user_args(), после --):
##   --hitch-ms=100   порог фриза в миллисекундах (по умолчанию 100)
##   --allow-hitch    не возвращать ненулевой код из-за фризов (только отчёт)
##   --probe          добавить в отчёт замеры отрисовки (draw calls, TIME_PROCESS, FPS)
##   --seed=31337     сид генерации мира
##
## Классификация: «фриз» — кадр длиннее порога, «жёсткий фриз» — длиннее 500 мс.
## Код возврата: 0 — фризов нет, 1 — были (с --allow-hitch всегда 0).
##
## Отчёт печатается в stdout и пишется в res://.tools/freeze_report.txt.
##
## Внимание: файл запускается как главный цикл движка (--script), а в этом
## режиме глобальные имена автозагрузок (World/Game/DB/UI) на этапе компиляции
## ещё недоступны — поэтому узлы берём через get_node(), а скрипты — через load().

const HARD_HITCH_MS: float = 500.0
const REPORT_PATH: String = "res://.tools/freeze_report.txt"

const SCENARIOS: Array = [
	{"name": "База: мир + свет", "kind": "idle", "frames": 60},
	{"name": "Копание 200 тайлов", "kind": "mine", "frames": 100},
	{"name": "30 фантомов", "kind": "phantoms", "frames": 90},
	{"name": "Цепочка из 60 конвейеров", "kind": "belts", "frames": 90},
	{"name": "1000 частиц + 100 колец + 100 взмахов", "kind": "fx", "frames": 60},
	{"name": "200 построек подряд", "kind": "build", "frames": 60},
	{"name": "Цикл день→ночь с волнами фантомов", "kind": "daynight", "frames": 180},
]

var scene: Node = null
var world = null
var game = null
var world_fx: Node = null
var player: Node = null

var hitch_ms: float = 100.0
var allow_hitch: bool = false
var probe_render: bool = false
var seed_value: int = 31337

var _started: bool = false
var _last_us: int = 0
var _scen_idx: int = -1
var _frame: int = 0
var _samples: Array = []
var _results: Array = []
var _st: Dictionary = {}
var _gen_ms: float = 0.0
var _scene_ms: float = 0.0
var _gen_stats: Dictionary = {}
var _lines: Array = []
var _skip_first: bool = false
var _setup_ms: float = 0.0
var _cleanup_ms: float = 0.0
var _total_hitch: int = 0
var _total_hard: int = 0
var _worst_name: String = "-"
var _worst_ms: float = 0.0
var _worst_scen: String = "-"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hitch-ms="):
			hitch_ms = maxf(1.0, float(a.substr(10)))
		elif a == "--allow-hitch":
			allow_hitch = true
		elif a == "--probe" or a == "--windowed":
			probe_render = true
		elif a.begins_with("--seed="):
			seed_value = int(a.substr(7))


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_setup()
		return false
	var now: int = Time.get_ticks_usec()
	if _last_us > 0:
		# Первый кадр после перехода содержит уборку прошлого сценария и
		# подготовку текущего — их считаем отдельно, в статистику не идёт.
		if _skip_first:
			_skip_first = false
		else:
			_samples.append(float(now - _last_us) / 1000.0)
	_last_us = now
	if _scen_idx < SCENARIOS.size():
		if _tick():
			_end_scenario()
	else:
		_finish()
		return true
	return false


# --------------------------------------------------------------------- запуск

func _setup() -> void:
	# Фиксированный сид: сценарии должны быть воспроизводимы.
	seed(seed_value)
	var t0: int = Time.get_ticks_usec()
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_scene_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	world = root.get_node("World")
	game = root.get_node("Game")
	world_fx = scene.get("world_fx")
	player = scene.get("player")
	# Отдельный чистый замер World.generate (постадийно — из gen_stats, если он есть).
	var t1: int = Time.get_ticks_usec()
	world.generate(seed_value)
	_gen_ms = float(Time.get_ticks_usec() - t1) / 1000.0
	var gs: Variant = world.get("gen_stats")
	if gs is Dictionary:
		_gen_stats = gs
	if player:
		player.invuln = 1.0e9
		player.global_position = world.spawn_point
	print("=== СТОРОЖ ФРИЗОВ — Glitch-Core ===")
	print("сид: %d   порог фриза: %.0f мс   жёсткий фриз: %.0f мс" % [seed_value, hitch_ms, HARD_HITCH_MS])
	print("режим: %s%s" % ["headless" if DisplayServer.get_name() == "headless" else "окно",
			"   (замеры отрисовки включены)" if probe_render else ""])
	print("генерация мира: %.1f мс   сцена целиком: %.1f мс   источников света: %d"
			% [_gen_ms, _scene_ms, world.lights.size()])
	if not _gen_stats.is_empty():
		print("постадийно (World.gen_stats): " + str(_gen_stats))
	print("")
	_start_scenario(0)


func _start_scenario(idx: int) -> void:
	_scen_idx = idx
	_frame = 0
	_samples = []
	_st = {}
	_skip_first = true
	_setup_ms = 0.0
	_cleanup_ms = 0.0
	if idx < SCENARIOS.size():
		var t0: int = Time.get_ticks_usec()
		_scenario_setup(SCENARIOS[idx]["kind"])
		_setup_ms = float(Time.get_ticks_usec() - t0) / 1000.0
		print(">> Сценарий: %s   (подготовка %.1f мс)" % [SCENARIOS[idx]["name"], _setup_ms])


func _tick() -> bool:
	_frame += 1
	var kind: String = SCENARIOS[_scen_idx]["kind"]
	var frames: int = int(SCENARIOS[_scen_idx]["frames"])
	_scenario_tick(kind, _frame, frames)
	return _frame >= frames


func _end_scenario() -> void:
	var s: Array = _samples.duplicate()
	s.sort()
	var n: int = s.size()
	var avg: float = 0.0
	var p95: float = 0.0
	var p99: float = 0.0
	var mx: float = 0.0
	if n > 0:
		var sum: float = 0.0
		for v in s:
			sum += float(v)
		avg = sum / float(n)
		p95 = _percentile(s, 0.95)
		p99 = _percentile(s, 0.99)
		mx = float(s[n - 1])
	var hitches: int = 0
	var hards: int = 0
	for v in s:
		if float(v) > hitch_ms:
			hitches += 1
		if float(v) > HARD_HITCH_MS:
			hards += 1
	_total_hitch += hitches
	_total_hard += hards
	if mx > _worst_ms:
		_worst_ms = mx
		_worst_name = SCENARIOS[_scen_idx]["name"]
		_worst_scen = SCENARIOS[_scen_idx]["name"]
	var draws: float = 0.0
	var proc_ms: float = 0.0
	var fps: float = 0.0
	if probe_render:
		draws = float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		proc_ms = float(Performance.get_monitor(Performance.TIME_PROCESS))
		fps = float(Performance.get_monitor(Performance.TIME_FPS))
	var tc: int = Time.get_ticks_usec()
	_scenario_cleanup(SCENARIOS[_scen_idx]["kind"])
	_cleanup_ms = float(Time.get_ticks_usec() - tc) / 1000.0
	_results.append({
		"name": SCENARIOS[_scen_idx]["name"],
		"frames": n, "avg": avg, "p95": p95, "p99": p99, "max": mx,
		"hitches": hitches, "hard": hards, "draws": draws, "proc": proc_ms, "fps": fps,
		"setup": _setup_ms, "cleanup": _cleanup_ms,
	})
	print("   кадров %d   среднее %7.2f мс   p95 %7.2f   p99 %7.2f   макс %8.2f   фризов %d   жёстких %d%s"
			% [n, avg, p95, p99, mx, hitches, hards,
			("   draw calls %d" % int(draws)) if probe_render else ""])
	if _scen_idx + 1 < SCENARIOS.size():
		_start_scenario(_scen_idx + 1)
	else:
		_scen_idx = SCENARIOS.size()


func _finish() -> void:
	print("")
	print("=== ИТОГОВАЯ ТАБЛИЦА ===")
	print("%-44s %6s %9s %9s %9s %9s %7s %7s %10s %9s"
			% ["сценарий", "кадров", "среднее", "p95", "p99", "макс", "фризов", "жёстких", "подготов.", "уборка"])
	for r in _results:
		print("%-44s %6d %9.2f %9.2f %9.2f %9.2f %7d %7d %10.2f %9.2f"
				% [r["name"], r["frames"], r["avg"], r["p95"], r["p99"], r["max"], r["hitches"], r["hard"],
				r["setup"], r["cleanup"]])
	if probe_render:
		print("")
		print("%-44s %12s %12s %10s" % ["сценарий", "draw calls", "TIME_PROCESS", "FPS"])
		for r in _results:
			print("%-44s %12d %11.2f мс %10.1f"
					% [r["name"], int(r["draws"]), r["proc"], r["fps"]])
	print("")
	print("=== СВОДКА ===")
	print("всего фризов (> %.0f мс): %d" % [hitch_ms, _total_hitch])
	print("всего жёстких фризов (> %.0f мс): %d" % [HARD_HITCH_MS, _total_hard])
	print("худший сценарий: %s (макс %.2f мс)" % [_worst_name, _worst_ms])
	print("максимальный кадр: %.2f мс в сценарии «%s»" % [_worst_ms, _worst_scen])
	print("источников света в мире: %d" % world.lights.size())
	var code: int = 0
	if _total_hitch > 0 and not allow_hitch:
		code = 1
	print("код возврата: %d%s" % [code, "  (--allow-hitch: отчёт без штрафа)" if allow_hitch else ""])
	_write_report()
	quit(code)


func _write_report() -> void:
	var dir: String = ProjectSettings.globalize_path("res://.tools")
	DirAccess.make_dir_recursive_absolute(dir)
	var f: FileAccess = FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f == null:
		print("не удалось записать отчёт: ", FileAccess.get_open_error())
		return
	f.store_line("=== СТОРОЖ ФРИЗОВ — Glitch-Core ===")
	f.store_line("сид: %d   порог фриза: %.0f мс   жёсткий фриз: %.0f мс   режим: %s"
			% [seed_value, hitch_ms, HARD_HITCH_MS,
			"headless" if DisplayServer.get_name() == "headless" else "окно"])
	f.store_line("генерация мира: %.1f мс   сцена целиком: %.1f мс   источников света: %d"
			% [_gen_ms, _scene_ms, world.lights.size()])
	if not _gen_stats.is_empty():
		f.store_line("постадийно (World.gen_stats): " + str(_gen_stats))
	f.store_line("")
	f.store_line("%-44s %6s %9s %9s %9s %9s %7s %7s %10s %9s"
			% ["сценарий", "кадров", "среднее", "p95", "p99", "макс", "фризов", "жёстких", "подготов.", "уборка"])
	for r in _results:
		f.store_line("%-44s %6d %9.2f %9.2f %9.2f %9.2f %7d %7d %10.2f %9.2f"
				% [r["name"], r["frames"], r["avg"], r["p95"], r["p99"], r["max"], r["hitches"], r["hard"],
				r["setup"], r["cleanup"]])
	if probe_render:
		f.store_line("")
		f.store_line("%-44s %12s %12s %10s" % ["сценарий", "draw calls", "TIME_PROCESS", "FPS"])
		for r in _results:
			f.store_line("%-44s %12d %11.2f мс %10.1f"
					% [r["name"], int(r["draws"]), r["proc"], r["fps"]])
	f.store_line("")
	f.store_line("=== СВОДКА ===")
	f.store_line("всего фризов (> %.0f мс): %d" % [hitch_ms, _total_hitch])
	f.store_line("всего жёстких фризов (> %.0f мс): %d" % [HARD_HITCH_MS, _total_hard])
	f.store_line("худший сценарий: %s (макс %.2f мс)" % [_worst_name, _worst_ms])
	f.store_line("максимальный кадр: %.2f мс в сценарии «%s»" % [_worst_ms, _worst_scen])
	f.store_line("источников света в мире: %d" % world.lights.size())
	f.close()
	print("отчёт записан: ", REPORT_PATH)


static func _percentile(sorted: Array, p: float) -> float:
	if sorted.is_empty():
		return 0.0
	var idx: int = int(ceil(p * float(sorted.size()))) - 1
	idx = clampi(idx, 0, sorted.size() - 1)
	return float(sorted[idx])


# ------------------------------------------------------------------ сценарии

func _scenario_setup(kind: String) -> void:
	match kind:
		"mine":
			_st["cells"] = _find_mine_cells(200)
		"phantoms":
			_st["made"] = _spawn_phantoms(30)
		"belts":
			_st["orig"] = _build_belt_chain(60)
		"fx":
			_st["chips"] = world_fx.chips.size()
			_st["rings"] = world_fx.rings.size()
			_st["slashes"] = world_fx.slashes.size()
			for i in 250:
				world_fx.spawn_chip(world.world_to_cell(player.global_position), Color(0.9, 0.5, 0.2))
			for i in 100:
				world_fx.spawn_ring(player.global_position + Vector2(float(i) * 3.0, 0.0), Color(0.4, 0.9, 1.0))
			for i in 100:
				world_fx.spawn_slash(player.global_position + Vector2(0.0, float(i) * 2.0))
		"build":
			_st["orig"] = _build_machine_field(200)
		"daynight":
			_st["tod"] = float(game.time_of_day)
			game.state = 0
		_:
			pass


func _scenario_tick(kind: String, frame: int, frames: int) -> void:
	match kind:
		"mine":
			var cells: Array = _st.get("cells", [])
			for i in 2:
				var idx: int = (frame - 1) * 2 + i
				if idx < cells.size():
					var c: Vector2i = cells[idx]["cell"]
					world.set_tile(c.x, c.y, IDs.T.AIR)
		"daynight":
			var t: float = 0.30 + 0.50 * float(frame) / float(maxi(1, frames))
			game.time_of_day = t
			if t >= 0.62:
				# Ночь: включаем волны фантомов.
				scene.spawn_timer = 0.0
		_:
			pass


func _scenario_cleanup(kind: String) -> void:
	match kind:
		"mine":
			var cells: Array = _st.get("cells", [])
			for s in cells:
				var c: Vector2i = s["cell"]
				_set_tile_fast(c.x, c.y, int(s["tile"]))
			_rebuild_lights_fast()
		"phantoms":
			_free_phantoms()
		"belts":
			_remove_machines_at(_st.get("orig", []))
			_restore_tiles(_st.get("orig", []))
		"build":
			_remove_machines_at(_st.get("orig", []))
			_restore_tiles(_st.get("orig", []))
		"fx":
			world_fx.chips.clear()
			world_fx.rings.clear()
			world_fx.slashes.clear()
		"daynight":
			_free_phantoms()
			game.time_of_day = float(_st.get("tod", 0.3))
			game.state = 0
		_:
			pass


## Быстрая замена тайла без полной пересборки света.
## Нужна для подготовки/уборки сценариев: сам сценарий «копки» намеренно
## меряет честный World.set_tile (с пересборкой всех источников света).
func _set_tile_fast(x: int, y: int, id: int) -> void:
	world.set_tile_raw(x, y, id)
	world.call("_update_astar", x, y)


func _rebuild_lights_fast() -> void:
	world.call("_rebuild_lights")


## Клетки под землёй, которые можно «выкопать» (соседние с поверхностью).
func _find_mine_cells(count: int) -> Array:
	var out: Array = []
	var bx: int = world.beacon_cell.x
	for x in range(bx - 40, bx + 40):
		if out.size() >= count:
			break
		var top: int = world.surface[clampi(x, 0, world.W - 1)]
		for y in range(top + 1, mini(world.H - 4, top + 24)):
			if out.size() >= count:
				break
			var t: int = world.get_tile(x, y)
			if t == IDs.T.AIR or t == IDs.T.BEDROCK:
				continue
			out.append({"cell": Vector2i(x, y), "tile": t})
	return out


func _spawn_phantoms(count: int) -> int:
	var ph_script: GDScript = load("res://scripts/entities/phantom.gd")
	var made: int = 0
	for i in count:
		var x: int = randi_range(8, world.W - 8)
		var top: int = world.surface[x]
		var y: int = randi_range(top + 4, mini(world.H - 6, top + 30))
		if world.get_tile(x, y) != IDs.T.AIR:
			continue
		var p: Node = ph_script.new()
		p.set("player", player)
		scene.add_child(p)
		p.global_position = world.cell_to_world(Vector2i(x, y))
		made += 1
	return made


func _free_phantoms() -> void:
	for p in get_nodes_in_group("phantom"):
		if is_instance_valid(p):
			p.queue_free()


## Цепочка конвейеров с предметами. Возвращает список «клетка → старый тайл».
func _build_belt_chain(count: int) -> Array:
	var saved: Array = []
	var mb: GDScript = load("res://scripts/machines/machine_base.gd")
	var x0: int = 40
	var y0: int = 100
	for i in count:
		var cell: Vector2i = Vector2i(x0 + i, y0)
		saved.append({"cell": cell, "tile": world.get_tile(cell.x, cell.y)})
		_set_tile_fast(cell.x, cell.y, IDs.T.AIR)
		mb.place_machine("Belt", cell)
		var b: Node = world.belts.get(cell)
		if b:
			b.set("dir", 0)
			b.call("add_item", 1, 1)
	_rebuild_lights_fast()
	return saved


## Поле из 200 построек. Возвращает список «клетка → старый тайл».
func _build_machine_field(count: int) -> Array:
	var saved: Array = []
	var mb: GDScript = load("res://scripts/machines/machine_base.gd")
	var x0: int = 300
	var y0: int = 110
	var placed: int = 0
	for dy in 10:
		for dx in 20:
			if placed >= count:
				break
			var cell: Vector2i = Vector2i(x0 + dx, y0 + dy)
			saved.append({"cell": cell, "tile": world.get_tile(cell.x, cell.y)})
			_set_tile_fast(cell.x, cell.y, IDs.T.AIR)
			mb.place_machine("Chest", cell)
			placed += 1
	_rebuild_lights_fast()
	return saved


func _remove_machines_at(saved: Array) -> void:
	for s in saved:
		var cell: Vector2i = s["cell"]
		var node: Node = world.machines.get(cell)
		if node != null and is_instance_valid(node):
			world.machines.erase(cell)
			if world.belts.has(cell):
				world.belts.erase(cell)
			node.queue_free()


func _restore_tiles(saved: Array) -> void:
	for s in saved:
		var cell: Vector2i = s["cell"]
		_set_tile_fast(cell.x, cell.y, int(s["tile"]))
	_rebuild_lights_fast()
