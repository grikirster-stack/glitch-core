extends SceneTree
## Сторож фризов: гоняет настоящую сцену под нагрузкой и ловит кадры-долготы.
##
## Запуск (headless, так же, как в CI):
##   godot --headless --path . --script res://tools/freeze_probe.gd -- --seed=31337
## Запуск с окном (добавляются замеры отрисовки):
##   godot --path . --script res://tools/freeze_probe.gd -- --probe --windowed --seed=31337
##
## Ключи (через OS.get_cmdline_user_args(), после --):
##   --hitch-ms=100   порог «мягкого» фриза в миллисекундах (по умолчанию 100)
##   --allow-hitch    не возвращать ненулевой код из-за фризов (только отчёт)
##   --strict         считать провалом любой фриз, а не только жёсткий
##   --probe          добавить в отчёт замеры отрисовки (draw calls, TIME_PROCESS, FPS)
##   --windowed       то же самое, что --probe: окно вместо headless
##   --seed=31337     сид генерации мира
##
## Классификация: «фриз» — кадр длиннее --hitch-ms, «жёсткий фриз» — длиннее 500 мс.
## Провал сценария = жёсткий фриз в нём (либо любой фриз при --strict).
## Код возврата: 0 — провалов нет, 1 — были (с --allow-hitch всегда 0).
##
## Формат вывода тот же, что у основного тест-раннера: в конце строки
##   ИТОГ: проверок N, провалов M
## где N — число выполненных сценариев, M — число сценариев с провалом.
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
	{"name": "Фантомы (предел копий)", "kind": "phantoms", "frames": 90},
	{"name": "16 фантомов пяти типов в погоне", "kind": "kinds", "frames": 240},
	{"name": "60 горелок", "kind": "burners", "frames": 90},
	{"name": "Эффекты на пределе лимитов", "kind": "fx", "frames": 90},
	{"name": "200 построек подряд", "kind": "build", "frames": 60},
	{"name": "Цикл день→ночь с волнами", "kind": "daynight", "frames": 180},
]

var scene: Node = null
var world = null
var game = null
var world_fx: Node = null
var player: Node = null

var hitch_ms: float = 100.0
var allow_hitch: bool = false
var strict: bool = false
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

# Накопители замеров отрисовки (только в режиме --probe).
var _draw_max: float = 0.0
var _draw_sum: float = 0.0
var _draw_n: int = 0
var _proc_max: float = 0.0
var _proc_sum: float = 0.0
var _fps_min: float = 0.0
var _fps_sum: float = 0.0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--hitch-ms="):
			# "--hitch-ms=" — 11 символов, значение начинается с индекса 11.
			hitch_ms = maxf(1.0, float(a.substr(11)))
		elif a == "--allow-hitch":
			allow_hitch = true
		elif a == "--strict":
			strict = true
		elif a == "--probe" or a == "--windowed":
			probe_render = true
		elif a.begins_with("--seed="):
			seed_value = int(a.substr(7))
	# Сид мира: main.gd читает --seed= из тех же пользовательских аргументов
	# и сам генерирует мир, поэтому отдельного «проброса» не нужно — достаточно
	# передать --seed= в командной строке. Если сид не задан, мир всё равно
	# получается воспроизводимым: seed() ниже фиксирует ГСЧ до создания сцены,
	# а main.gd берёт из него randi(). Реально применённый сид печатается в
	# отчёте (world.world_seed).


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
			_sample_render()
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
	# _ready сцены уже сгенерировал мир (main.gd делает World.generate сам).
	# Вторую генерацию не делаем: это и лишние ~250 мс, и «двойной» отчёт.
	_scene_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	world = root.get_node("World")
	game = root.get_node("Game")
	world_fx = scene.get("world_fx")
	player = scene.get("player")
	# Сид, который реально применился (main.gd мог взять свой).
	var used_seed: int = int(world.get("world_seed"))
	if used_seed != seed_value:
		seed_value = used_seed
	# Сценарии используют общий ГСЧ — возвращаем его в детерминированное
	# состояние уже после генерации мира.
	seed(seed_value)
	var gs: Variant = world.get("gen_stats")
	if gs is Dictionary:
		_gen_stats = gs
	if _gen_stats.has("gen_ms"):
		_gen_ms = float(_gen_stats["gen_ms"])
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
	if probe_render and DisplayServer.get_name() == "headless":
		print("внимание: headless не считает draw calls — запустите с окном для этих чисел")
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
	_draw_max = 0.0
	_draw_sum = 0.0
	_draw_n = 0
	_proc_max = 0.0
	_proc_sum = 0.0
	_fps_min = 0.0
	_fps_sum = 0.0
	if idx < SCENARIOS.size():
		var t0: int = Time.get_ticks_usec()
		_scenario_setup(SCENARIOS[idx]["kind"])
		_setup_ms = float(Time.get_ticks_usec() - t0) / 1000.0
		print(">> Сценарий: %s   (подготовка %.1f мс)" % [SCENARIOS[_scen_idx]["name"], _setup_ms])


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
	var draws_max: float = _draw_max
	var draws_avg: float = _draw_sum / maxf(1.0, float(_draw_n))
	var proc_avg: float = _proc_sum / maxf(1.0, float(_draw_n))
	var proc_max: float = _proc_max
	var fps_avg: float = _fps_sum / maxf(1.0, float(_draw_n))
	var fps_min: float = _fps_min
	var tc: int = Time.get_ticks_usec()
	_scenario_cleanup(SCENARIOS[_scen_idx]["kind"])
	_cleanup_ms = float(Time.get_ticks_usec() - tc) / 1000.0
	var note: String = str(_st.get("note", ""))
	# Провал сценария: жёсткий фриз внутри него. При --strict проваливает
	# любой фриз (даже мягкий) — так порог можно опустить вручную.
	var failed: bool = hards > 0 or (strict and hitches > 0)
	_results.append({
		"name": SCENARIOS[_scen_idx]["name"],
		"frames": n, "avg": avg, "p95": p95, "p99": p99, "max": mx,
		"hitches": hitches, "hard": hards, "fail": failed,
		"draws_max": draws_max, "draws_avg": draws_avg,
		"proc_avg": proc_avg, "proc_max": proc_max,
		"fps_avg": fps_avg, "fps_min": fps_min,
		"setup": _setup_ms, "cleanup": _cleanup_ms, "note": note,
	})
	print("   кадров %d   среднее %7.2f мс   p95 %7.2f   p99 %7.2f   макс %8.2f   фризов %d   жёстких %d%s%s"
			% [n, avg, p95, p99, mx, hitches, hards,
			("   draw calls %d" % int(draws_max)) if probe_render else "",
			("   " + note) if note != "" else ""])
	if _scen_idx + 1 < SCENARIOS.size():
		_start_scenario(_scen_idx + 1)
	else:
		_scen_idx = SCENARIOS.size()


func _sample_render() -> void:
	if not probe_render:
		return
	var d: float = float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_draw_sum += d
	_draw_n += 1
	if d > _draw_max:
		_draw_max = d
	var p: float = float(Performance.get_monitor(Performance.TIME_PROCESS))
	_proc_sum += p
	if p > _proc_max:
		_proc_max = p
	var f: float = float(Performance.get_monitor(Performance.TIME_FPS))
	_fps_sum += f
	if _fps_min <= 0.0 or f < _fps_min:
		_fps_min = f


func _finish() -> void:
	print("")
	print("=== ИТОГОВАЯ ТАБЛИЦА ===")
	print("%-44s %6s %9s %9s %9s %9s %7s %7s %10s %9s"
			% ["сценарий", "кадров", "среднее", "p95", "p99", "макс", "фризов", "жёстких", "подготов.", "уборка"])
	for r in _results:
		print("%-44s %6d %9.2f %9.2f %9.2f %9.2f %7d %7d %10.2f %9.2f"
				% [r["name"], r["frames"], r["avg"], r["p95"], r["p99"], r["max"], r["hitches"], r["hard"],
				r["setup"], r["cleanup"]])
	print("")
	print("--- заметки по сценариям ---")
	for r in _results:
		if str(r["note"]) != "":
			print("  %s: %s" % [r["name"], r["note"]])
	if probe_render:
		print("")
		print("%-44s %11s %11s %12s %11s %9s"
				% ["сценарий", "draw max", "draw сред", "TIME_PROC", "FPS сред", "FPS мин"])
		for r in _results:
			print("%-44s %11d %11.1f %11.2f мс %11.1f %9.1f"
					% [r["name"], int(r["draws_max"]), r["draws_avg"], r["proc_avg"], r["fps_avg"], r["fps_min"]])
	print("")
	print("=== СВОДКА ===")
	print("всего фризов (> %.0f мс): %d" % [hitch_ms, _total_hitch])
	print("всего жёстких фризов (> %.0f мс): %d" % [HARD_HITCH_MS, _total_hard])
	print("худший сценарий: %s (макс %.2f мс)" % [_worst_name, _worst_ms])
	print("максимальный кадр: %.2f мс в сценарии «%s»" % [_worst_ms, _worst_scen])
	print("источников света в мире: %d" % world.lights.size())
	# Проверка — по одной на сценарий: сценарий без жёсткого фриза — «OK».
	var checks: int = _results.size()
	var fails: int = 0
	for r in _results:
		if bool(r["fail"]):
			fails += 1
			print("  FAIL %s: фризов %d (жёстких %d), максимум %.2f мс"
					% [r["name"], int(r["hitches"]), int(r["hard"]), float(r["max"])])
		else:
			print("  OK   %s: максимум %.2f мс" % [r["name"], float(r["max"])])
	var code: int = 0
	if fails > 0 and not allow_hitch:
		code = 1
	# Мягкие фризы (длиннее порога, но короче жёсткого) — предупреждение:
	# сборку они не роняют, но в отчёте остаются.
	if fails == 0 and _total_hitch > 0:
		print("  ПРЕДУПРЕЖДЕНИЕ  мягких фризов: %d (длиннее %.0f мс, но не длиннее %.0f мс) — не провал"
				% [_total_hitch, hitch_ms, HARD_HITCH_MS])
	print("")
	print("ИТОГ: проверок %d, провалов %d" % [checks, fails])
	print("код возврата: %d%s" % [code,
			"  (--allow-hitch: отчёт без штрафа)" if allow_hitch else ""])
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
	f.store_line("")
	f.store_line("--- заметки по сценариям ---")
	for r in _results:
		if str(r["note"]) != "":
			f.store_line("  %s: %s" % [r["name"], r["note"]])
	if probe_render:
		f.store_line("")
		f.store_line("%-44s %11s %11s %12s %11s %9s"
				% ["сценарий", "draw max", "draw сред", "TIME_PROC", "FPS сред", "FPS мин"])
		for r in _results:
			f.store_line("%-44s %11d %11.1f %11.2f мс %11.1f %9.1f"
					% [r["name"], int(r["draws_max"]), r["draws_avg"], r["proc_avg"], r["fps_avg"], r["fps_min"]])
	f.store_line("")
	f.store_line("=== СВОДКА ===")
	f.store_line("всего фризов (> %.0f мс): %d" % [hitch_ms, _total_hitch])
	f.store_line("всего жёстких фризов (> %.0f мс): %d" % [HARD_HITCH_MS, _total_hard])
	f.store_line("худший сценарий: %s (макс %.2f мс)" % [_worst_name, _worst_ms])
	f.store_line("максимальный кадр: %.2f мс в сценарии «%s»" % [_worst_ms, _worst_scen])
	f.store_line("источников света в мире: %d" % world.lights.size())
	var rfails: int = 0
	for r in _results:
		if bool(r["fail"]):
			rfails += 1
			f.store_line("  FAIL %s: фризов %d (жёстких %d), максимум %.2f мс"
					% [r["name"], int(r["hitches"]), int(r["hard"]), float(r["max"])])
		else:
			f.store_line("  OK   %s: максимум %.2f мс" % [r["name"], float(r["max"])])
	f.store_line("")
	f.store_line("ИТОГ: проверок %d, провалов %d" % [_results.size(), rfails])
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
			_st["note"] = "выкопано тайлов: %d" % _st.get("cells", []).size()
		"phantoms":
			var made: int = _spawn_phantoms(30)
			_st["made"] = made
			_st["peak"] = _alive_phantoms()
			_st["note"] = "создано фантомов: %d, живых в сцене: %d (лимит Phantom.MAX_PHANTOMS = %d)" \
					% [made, _alive_phantoms(), _phantom_limit()]
		"kinds":
			# В темноте: на освещённой базе эхо и копатель бы только убегали.
			_st["ppos"] = player.global_position
			var dark: Vector2i = _find_dark_surface()
			if dark.x >= 0:
				player.global_position = world.cell_to_world(dark)
			player.set("invuln", 1.0e9)
			_st["made"] = _spawn_mixed_phantoms()
			_st["note"] = "фантомов в сцене: %d (типы: %s)" % [_alive_phantoms(), _kinds_note()]
		"burners":
			var saved: Array = _build_burner_row(60)
			_st["orig"] = saved
			_st["note"] = "горелок поставлено: %d" % saved.size()
		"fx":
			_st["note"] = "лимиты WorldFX: частиц %d, колец %d, взмахов %d" \
					% [_fx_limit("MAX_CHIPS"), _fx_limit("MAX_RINGS"), _fx_limit("MAX_SLASHES")]
		"build":
			var saved2: Array = _build_machine_field(200)
			_st["orig"] = saved2
			_st["note"] = "построек в мире: %d" % world.machines.size()
		"daynight":
			_st["tod"] = float(game.time_of_day)
			_st["day"] = int(game.day_number)
			game.state = 0
			# Три ночи подряд — волны фантомов заметно тяжелее.
			game.day_number = 3
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
		"phantoms":
			# Держим в сцене максимум фантомов: лишние копии растворяются сами.
			if frame % 10 == 0:
				_spawn_phantoms(4)
			var alive: int = _alive_phantoms()
			if alive > int(_st.get("peak", 0)):
				_st["peak"] = alive
				_st["note"] = "живых фантомов в сцене: %d (лимит Phantom.MAX_PHANTOMS = %d)" \
						% [alive, _phantom_limit()]
		"fx":
			# Каждый кадр добиваем эффекты до предельных лимитов WorldFX:
			# так измеряется стоимость кадра при полной нагрузке, а не пустого.
			_fill_fx()
		"daynight":
			var t: float = 0.30 + 0.50 * float(frame) / float(maxi(1, frames))
			game.time_of_day = t
			if t >= 0.62 and frame % 30 == 0:
				# Ночь: торопим директора угрозы (#27) — волны идут чаще.
				var threat: Node = root.get_node_or_null("Threat")
				if threat != null:
					threat.set("spawn_timer", 0.0)
		_:
			pass


func _scenario_cleanup(kind: String) -> void:
	match kind:
		"mine":
			var cells: Array = _st.get("cells", [])
			for s in cells:
				var c: Vector2i = s["cell"]
				world.set_tile(c.x, c.y, int(s["tile"]))
		"phantoms":
			_free_phantoms()
		"kinds":
			_free_phantoms()
			player.global_position = _st.get("ppos", player.global_position)
			player.set("invuln", 0.0)
		"burners":
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
			game.day_number = int(_st.get("day", 1))
			game.state = 0
		_:
			pass


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
	# Ищем настоящие пустые клетки под землёй: берём столбец и ищем вниз
	# первую воздушную клетку с полом под ней. Так фантомы действительно
	# появляются, а не отбрасываются из-за «не той» породы.
	var attempts: int = 0
	var limit: int = count * 40
	while made < count and attempts < limit:
		attempts += 1
		var x: int = randi_range(8, world.W - 8)
		var top: int = world.surface[x]
		var y: int = -1
		for yy in range(top + 2, mini(world.H - 6, top + 30)):
			if world.get_tile(x, yy) == IDs.T.AIR and world.get_tile(x, yy + 1) != IDs.T.AIR:
				y = yy
				break
		if y < 0:
			continue
		var p: Node = ph_script.new()
		p.set("player", player)
		scene.add_child(p)
		p.global_position = world.cell_to_world(Vector2i(x, y))
		made += 1
	return made


## Смесь пяти типов (#27): 6 эхо, стая роя из 5, 2 тени, 2 копателя, двойник —
## 16 фантомов вокруг игрока, все в погоне. На старой версии (без типов)
## поле kind просто игнорируется — выходит то же число эхо (до лимита).
const MIXED_KINDS: Array = ["echo", "echo", "echo", "echo", "echo", "echo",
		"swarm", "swarm", "swarm", "swarm", "swarm",
		"shade", "shade", "burrower", "burrower", "doppel"]


func _spawn_mixed_phantoms() -> int:
	var ph_script: GDScript = load("res://scripts/entities/phantom.gd")
	var made: int = 0
	# Фантомы прошлого сценария ещё в группе до конца кадра (queue_free) —
	# убираем их из дерева сразу, иначе лимит копий отбросит новых.
	for old in get_nodes_in_group("phantom"):
		if is_instance_valid(old):
			old.get_parent().remove_child(old)
			old.queue_free()
	var pc: Vector2i = world.world_to_cell(player.global_position)
	for i in MIXED_KINDS.size():
		# Кольцо вокруг игрока: ближайшая воздушная клетка в 6–14 клетках.
		var cell: Vector2i = Vector2i(-1, -1)
		for r in range(6, 15):
			var ang: float = TAU * float(i) / float(MIXED_KINDS.size())
			var c: Vector2i = pc + Vector2i(int(round(cos(ang) * r)), int(round(sin(ang) * r * 0.5)))
			if world.get_tile(c.x, c.y) == IDs.T.AIR:
				cell = c
				break
		if cell.x < 0:
			cell = pc + Vector2i(6 + i, -2)
		var p: Node = ph_script.new()
		p.set("kind", String(MIXED_KINDS[i]))
		p.set("player", player)
		if String(MIXED_KINDS[i]) == "swarm":
			p.set("pack_id", 1)
		scene.add_child(p)
		p.global_position = world.cell_to_world(cell)
		p.set("alert", 30.0)
		made += 1
	return made


## Тёмная клетка на поверхности (свет < 0.3) с полом под ней.
func _find_dark_surface() -> Vector2i:
	for x in range(20, world.W - 20, 3):
		var c: Vector2i = Vector2i(x, int(world.surface[x]) - 1)
		if world.get_tile(c.x, c.y) != IDs.T.AIR:
			continue
		if world.light_at(c) < 0.3:
			return c
	return Vector2i(-1, -1)


func _kinds_note() -> String:
	var counts: Dictionary = {}
	for p in get_nodes_in_group("phantom"):
		if is_instance_valid(p) and bool(p.get("alive")):
			var k = p.get("kind")
			var name: String = String(k) if k != null else "echo"
			counts[name] = int(counts.get(name, 0)) + 1
	var parts: Array = []
	for k in counts.keys():
		parts.append("%s %d" % [k, int(counts[k])])
	return ", ".join(parts)


func _alive_phantoms() -> int:
	var n: int = 0
	for p in get_nodes_in_group("phantom"):
		if is_instance_valid(p) and bool(p.get("alive")):
			n += 1
	return n


## Лимит живых копий фантома — из самого скрипта, чтобы не расходиться с кодом.
func _phantom_limit() -> int:
	var ph_script: GDScript = load("res://scripts/entities/phantom.gd")
	return int(ph_script.get_script_constant_map().get("MAX_PHANTOMS", 12))


## Предел эффекта WorldFX — тоже из самого скрипта.
func _fx_limit(name: String) -> int:
	if world_fx == null:
		return 0
	return int(world_fx.get_script().get_script_constant_map().get(name, 0))


## Добивает частицы, кольца и взмахи до предельных лимитов.
func _fill_fx() -> void:
	if world_fx == null:
		return
	var cell: Vector2i = world.world_to_cell(player.global_position)
	var chip_limit: int = maxi(1, _fx_limit("MAX_CHIPS"))
	var ring_limit: int = maxi(1, _fx_limit("MAX_RINGS"))
	var slash_limit: int = maxi(1, _fx_limit("MAX_SLASHES"))
	# spawn_chip добавляет сразу 4 частицы.
	var want_chips: int = int(ceil(float(chip_limit - world_fx.chips.size()) / 4.0))
	for i in want_chips:
		world_fx.spawn_chip(cell, Color(0.9, 0.5, 0.2))
	for i in ring_limit - world_fx.rings.size():
		world_fx.spawn_ring(player.global_position + Vector2(float(i) * 3.0, 0.0), Color(0.4, 0.9, 1.0))
	for i in slash_limit - world_fx.slashes.size():
		world_fx.spawn_slash(player.global_position + Vector2(0.0, float(i) * 2.0))


func _free_phantoms() -> void:
	for p in get_nodes_in_group("phantom"):
		if is_instance_valid(p):
			p.queue_free()


## Ряд горелок с углём. Ленты сняты (#170). Возвращает «клетка → старый тайл».
func _build_burner_row(count: int) -> Array:
	var saved: Array = []
	var mb: GDScript = load("res://scripts/machines/machine_base.gd")
	var ids: Script = load("res://scripts/core/ids.gd")
	var x0: int = 40
	var y0: int = 100
	for i in count:
		var cell: Vector2i = Vector2i(x0 + i, y0)
		saved.append({"cell": cell, "tile": world.get_tile(cell.x, cell.y)})
		world.set_tile(cell.x, cell.y, IDs.T.AIR)
		if mb.place_machine("Burner", cell):
			var b: Node = world.machines.get(cell)
			if b != null and b.has_method("add_fuel"):
				b.call("add_fuel", ids.I.COAL, 2)
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
			world.set_tile(cell.x, cell.y, IDs.T.AIR)
			mb.place_machine("Chest", cell)
			placed += 1
	return saved


func _remove_machines_at(saved: Array) -> void:
	for s in saved:
		var cell: Vector2i = s["cell"]
		var node: Node = world.machines.get(cell)
		if node != null and is_instance_valid(node):
			world.machines.erase(cell)
			node.queue_free()


func _restore_tiles(saved: Array) -> void:
	for s in saved:
		var cell: Vector2i = s["cell"]
		world.set_tile(cell.x, cell.y, int(s["tile"]))
