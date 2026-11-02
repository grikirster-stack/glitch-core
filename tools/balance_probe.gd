extends SceneTree
## Таблица баланса (#33, ADR-001 § 2): «метрика → цель → факт» на нескольких сидах.
##
## Для каждого сида запускает дочерний Godot с ботами баланса
## (tools/scenarios/balance_*.gd, night_*.gd), разбирает их строки
## «[баланс] ключ=значение» и печатает таблицу: цель, факт по сидам, мин/макс,
## в допуске ли. NA — метрика не измерена (зависимость ещё не в main).
##
## Запуск:
##   godot --headless --path . --script res://tools/balance_probe.gd
##   godot --headless --path . --script res://tools/balance_probe.gd -- --seeds=31337,4242 --only=balance_factory
## Код возврата 1, если хоть одна измеренная метрика вне допуска.

const DEFAULT_SEEDS: Array = [31337, 4242, 12345]
const SCENARIOS: Array = ["balance_hand", "balance_factory", "night_survive_1",
		"night_siege_3", "night_defended_3"]

## Цели ADR-001 § 2 (и § 4.2 для стартовой линии). op: ">=", "<=", ">", "==", "~" (±tol доли).
const TARGETS: Array = [
	{"key": "hand_relay_min", "title": "релей «руками» (бот копает, крафтит вручную), мин добычи", "op": ">=", "v": 25.0},
	{"key": "factory_relay_min", "title": "релей с двумя линиями буров, мин", "op": "<=", "v": 12.0},
	{"key": "night1_hp_end", "title": "ночь 1, 3 лампы, без построек: hp через 90 с", "op": ">", "v": 0.0},
	{"key": "night3_lost", "title": "ночь 3 без обороны: машин потеряно", "op": ">=", "v": 1.0},
	{"key": "night3_def_lost", "title": "ночь 3 с 2 турелями + стеной: машин потеряно", "op": "==", "v": 0.0},
	{"key": "line_ore_per_s", "title": "одна стартовая линия (мощность 6): руды/с", "op": "~", "v": 0.5, "tol": 0.10},
	{"key": "line_plate_per_s", "title": "одна стартовая линия (мощность 6): пластины/с", "op": "~", "v": 0.25, "tol": 0.10},
]
## Справочные цифры (без цели) — печатаются под таблицей.
const INFO: Array = [
	{"key": "night1_nolamp_hp_end", "title": "ночь 1 без ламп (для сравнения): hp через 90 с"},
	{"key": "night1_deaths", "title": "ночь 1 с лампами: смертей"},
]


func _initialize() -> void:
	var seeds: Array = DEFAULT_SEEDS.duplicate()
	var names: Array = SCENARIOS.duplicate()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds.clear()
			for s in a.substr(8).split(",", false):
				seeds.append(int(s))
		elif a.begins_with("--only="):
			names = Array(a.substr(7).split(",", false))
	var exe: String = OS.get_executable_path()
	var proj: String = ProjectSettings.globalize_path("res://")
	var facts: Dictionary = {}        ## key -> {seed -> value (float) | "NA"}
	var fails_run: Array = []
	for s in seeds:
		var t0: int = Time.get_ticks_msec()
		var out: Array = []
		# Метрики боты пишут ещё и в файл: stdout дочернего процесса на Windows
		# приходит в системной кодировке, кириллицу по нему не разобрать.
		var mfile: String = OS.get_user_data_dir().path_join("balance_probe_%d.txt" % int(s))
		if FileAccess.file_exists(mfile):
			DirAccess.remove_absolute(mfile)
		var args: PackedStringArray = ["--headless", "--path", proj, "--",
				"--scenario=" + ",".join(names), "--seed=%d" % int(s), "--balance-out=" + mfile]
		var code: int = OS.execute(exe, args, out, true)
		var text: String = FileAccess.get_file_as_string(mfile)
		for line in text.split("\n", false):
			var kv: PackedStringArray = line.strip_edges().split("=")
			if kv.size() == 2:
				if not facts.has(kv[0]):
					facts[kv[0]] = {}
				facts[kv[0]][int(s)] = "NA" if kv[1] == "NA" else float(kv[1])
		if code != 0:
			fails_run.append(int(s))
		print("сид %d: %.0f с, код %d" % [int(s), float(Time.get_ticks_msec() - t0) / 1000.0, code])
	var bad: int = _print_table(seeds, facts)
	if not fails_run.is_empty():
		print("сценарии с провалами на сидах: %s" % str(fails_run))
	quit(1 if bad > 0 else 0)


func _print_table(seeds: Array, facts: Dictionary) -> int:
	var bad: int = 0
	print("")
	print("| Метрика | Цель | " + " | ".join(seeds.map(func(s): return "сид %d" % int(s))) + " | Итог |")
	print("|---|---|" + "---|".repeat(seeds.size()) + "---|")
	for t in TARGETS:
		var row: Array = []
		var any: bool = false
		var all_ok: bool = true
		var na: bool = false
		for s in seeds:
			var v = facts.get(t["key"], {}).get(int(s), null)
			if v == null:
				row.append("—")
				all_ok = false
			elif v is String:
				row.append("NA")
				na = true
			else:
				any = true
				var good: bool = _check(t, float(v))
				all_ok = all_ok and good
				row.append(("%.2f" % float(v)) + ("" if good else " ✗"))
		var verdict: String = "в допуске" if (any and all_ok) else ("отложено" if na and not any else "ВНЕ ДОПУСКА")
		if verdict == "ВНЕ ДОПУСКА":
			bad += 1
		print("| %s | %s | %s | %s |" % [t["title"], _goal(t), " | ".join(row), verdict])
	for t in INFO:
		var vals: Array = []
		for s in seeds:
			var v = facts.get(t["key"], {}).get(int(s), null)
			vals.append("—" if v == null else ("NA" if v is String else "%.1f" % float(v)))
		print("  справочно: %s — %s" % [t["title"], ", ".join(vals)])
	return bad


func _check(t: Dictionary, v: float) -> bool:
	var g: float = float(t["v"])
	match String(t["op"]):
		">=": return v >= g
		"<=": return v <= g
		">": return v > g
		"==": return is_equal_approx(v, g)
		"~": return absf(v - g) <= g * float(t.get("tol", 0.1))
	return false


func _goal(t: Dictionary) -> String:
	var g: float = float(t["v"])
	match String(t["op"]):
		"~": return "%.2f ± %d %%" % [g, int(float(t.get("tol", 0.1)) * 100.0)]
		"==": return "= %s" % str(g)
	return "%s %s" % [String(t["op"]).replace(">=", "≥").replace("<=", "≤"), str(g)]
