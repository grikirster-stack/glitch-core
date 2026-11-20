extends SceneTree
## Таблица баланса после «Света» (#239, M1): «метрика → цель → факт» на сидах.
##
## Фабричные цели сняты вместе с линиями буров (#170): factory_relay_min,
## line_ore_per_s, line_plate_per_s. Победа больше не «релей руками» (#212) —
## balance_hand в дефолт не входит, секундомер копки жив флагом --hand.
##
## Для каждого сида гоняет каждый сценарий отдельным дочерним Godot (свой
## --balance-out): один процесс на список сценариев тащит состояние между
## ними, и автопилот после ночных сценариев не доходит до удержания.
## Разбирает строки «ключ=значение» и печатает таблицу. Код сида ненулевой,
## если упал хоть один дочерний процесс. Коридоры потерь и uptime —
## справочно, пока нет линии отсчёта: резать прогон ними значит снова красить
## зонд из-за констант, которые эта задача не трогает. Режут только то, что
## уже было приёмкой и не зависит от тюнинга: первая ночь, тихие смерти,
## «ночь не состоялась». S = B/D сценарий печатает строкой, в допуск не входит.
##
## Запуск:
##   godot --headless --path . --script res://tools/balance_probe.gd
##   godot --headless --path . --script res://tools/balance_probe.gd -- --seeds=31337 --hand
##   godot --headless --path . --script res://tools/balance_probe.gd -- --out=a.json
##   godot --headless --path . --script res://tools/balance_probe.gd -- --load=a.json,b.json
## --load без новых сидов печатает таблицу из файлов (A/B констант). Код возврата 1,
## если хоть одна измеренная метрика вне допуска или сценарий упал.


const DEFAULT_SEEDS: Array = [31337, 4242, 12345]
## Дефолт дыма. balance_hand — только --hand (минуты мёртвого релея не цель).
const SCENARIOS: Array = ["night_survive_1", "night_siege_3", "night_defended_3", "night_autopilot"]

## op: ">=", "<=", ">", "==", "in" (lo..hi). Эти строки режут прогон.
const TARGETS: Array = [
	{"key": "night1_hp_end", "title": "ночь 1, 3 лампы: hp через 90 с", "op": ">", "v": 0.0},
	{"key": "night3_lost", "title": "ночь 3 без обороны: машин потеряно", "op": ">=", "v": 1.0},
	{"key": "night3_def_lost", "title": "ночь 3, 2 красных маяка: машин потеряно", "op": "==", "v": 0.0},
	{"key": "first_night_s", "title": "секунд от старта до первой ночи", "op": ">=", "v": 140.0},
	{"key": "autopilot_empty_deaths", "title": "пусто, ночи 1–3: смертей", "op": "==", "v": 0.0},
	{"key": "autopilot_empty_missed", "title": "пусто: ночей без спавна вне тихих 1–2", "op": "==", "v": 0.0},
	{"key": "autopilot_hold_deaths", "title": "удержание 180 с: смертей бота", "op": "==", "v": 0.0},
]
## Коридоры бест-практик. Печатаются с пометкой, прогон не режут: линия отсчёта
## для тюнинга Balance, не приёмка этой задачи.
const CORRIDORS: Array = [
	{"key": "autopilot_stuck_red_lost", "title": "средняя, оставили красный: машин потеряно", "op": "in", "lo": 0.0, "hi": 1.0},
	{"key": "autopilot_stuck_red_uptime", "title": "средняя: доля ночи с лучом (beam_uptime)", "op": ">=", "v": 0.5},
	{"key": "autopilot_stuck_red_pressure", "title": "средняя: доля ночи под давлением", "op": "in", "lo": 0.25, "hi": 0.60},
	{"key": "autopilot_seven_lost", "title": "семь цветов: машин потеряно", "op": "==", "v": 0.0},
	{"key": "autopilot_seven_uptime", "title": "семь цветов: доля ночи с лучом", "op": ">=", "v": 0.5},
	{"key": "autopilot_seven_pressure", "title": "семь цветов: доля ночи под давлением", "op": "in", "lo": 0.25, "hi": 0.60},
]
const INFO: Array = [
	{"key": "night1_nolamp_hp_end", "title": "ночь 1 без ламп: hp через 90 с"},
	{"key": "night1_deaths", "title": "ночь 1 с лампами: смертей"},
	{"key": "autopilot_empty_peak", "title": "пусто: пик живых"},
	{"key": "autopilot_empty_budget", "title": "пусто: бюджет последней ночи"},
	{"key": "autopilot_stuck_red_budget", "title": "средняя: бюджет B"},
	{"key": "autopilot_stuck_red_peak", "title": "средняя: пик живых"},
	{"key": "autopilot_stuck_red_cap", "title": "средняя: cap"},
	{"key": "autopilot_stuck_red_fuel_s", "title": "средняя: топливо за ночь, с (fuel_spent)"},
	{"key": "autopilot_stuck_red_hit_s", "title": "средняя: секунд до первого удара (secs_to_first_hit)"},
	{"key": "autopilot_seven_budget", "title": "семь цветов: бюджет B"},
	{"key": "autopilot_seven_peak", "title": "семь цветов: пик живых"},
	{"key": "autopilot_seven_fuel_s", "title": "семь цветов: топливо, с"},
	{"key": "autopilot_seven_hit_s", "title": "семь цветов: секунд до первого удара"},
	{"key": "autopilot_hold_budget", "title": "удержание: бюджет B"},
	{"key": "autopilot_hold_peak", "title": "удержание: пик живых"},
	{"key": "autopilot_hold_uptime", "title": "удержание: доля окна с лучом"},
	{"key": "autopilot_hold_fuel_s", "title": "удержание: топливо, с"},
	{"key": "ore_secs_day", "title": "секунд чистой копки за световой день (ore_secs_day, флаг --hand)"},
	{"key": "hand_relay_min", "title": "минут добычи legacy-релея (не цель победы, #212)"},
]


func _initialize() -> void:
	var seeds: Array = DEFAULT_SEEDS.duplicate()
	var names: Array = SCENARIOS.duplicate()
	var out_path: String = ""
	var loads: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds.clear()
			for s in a.substr(8).split(",", false):
				seeds.append(int(s))
		elif a.begins_with("--only="):
			names = Array(a.substr(7).split(",", false))
		elif a == "--hand":
			if not names.has("balance_hand"):
				names.append("balance_hand")
		elif a.begins_with("--out="):
			out_path = a.substr(6)
		elif a.begins_with("--load="):
			loads.append_array(a.substr(7).split(",", false))
	var facts: Dictionary = {}
	if not loads.is_empty() and names.is_empty():
		for p in loads:
			_load(String(p), facts)
		_print_table(_seeds_of(facts, seeds), facts)
		quit(0)
		return
	for p in loads:
		_load(String(p), facts)
	var exe: String = OS.get_executable_path()
	var proj: String = ProjectSettings.globalize_path("res://")
	var fails_run: Array = []
	for s in seeds:
		var t0: int = Time.get_ticks_msec()
		var code: int = 0
		for name in names:
			var mfile: String = OS.get_user_data_dir().path_join(
					"balance_probe_%d_%s.txt" % [int(s), String(name)])
			if FileAccess.file_exists(mfile):
				DirAccess.remove_absolute(mfile)
			var args: PackedStringArray = ["--headless", "--path", proj, "--",
					"--scenario=" + String(name), "--seed=%d" % int(s), "--balance-out=" + mfile]
			var child: int = OS.execute(exe, args, [], true)
			var text: String = FileAccess.get_file_as_string(mfile)
			for line in text.split("\n", false):
				var kv: PackedStringArray = line.strip_edges().split("=")
				if kv.size() == 2 and kv[1] != "справ":
					if not facts.has(kv[0]):
						facts[kv[0]] = {}
					facts[kv[0]][int(s)] = "NA" if kv[1] == "NA" else float(kv[1])
			if child != 0:
				code = child
		if code != 0:
			fails_run.append(int(s))
		print("сид %d: %.0f с, код %d" % [int(s), float(Time.get_ticks_msec() - t0) / 1000.0, code])
	if out_path != "":
		_save(out_path, facts)
	var bad: int = _print_table(seeds, facts)
	if not fails_run.is_empty():
		print("сценарии с провалами на сидах: %s" % str(fails_run))
		bad += fails_run.size()
	quit(1 if bad > 0 else 0)


func _save(path: String, facts: Dictionary) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("не записать %s" % path)
		return
	f.store_string(JSON.stringify(facts))
	f.close()
	print("факты: %s" % path)


func _load(path: String, facts: Dictionary) -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		print("не прочитать %s" % path)
		return
	for key in d:
		var slot: String = String(key)
		if facts.has(slot):
			slot = "%s@%s" % [key, path.get_file()]
		facts[slot] = d[key]
	print("загружено %s" % path)


func _seeds_of(facts: Dictionary, fallback: Array) -> Array:
	var out: Array = []
	for key in facts:
		for s in facts[key]:
			if not out.has(int(s)):
				out.append(int(s))
	out.sort()
	return out if not out.is_empty() else fallback


func _print_table(seeds: Array, facts: Dictionary) -> int:
	var bad: int = 0
	var head: Array = []
	for s in seeds:
		head.append("сид %d" % int(s))
	print("")
	print("| Метрика | Цель | " + " | ".join(head) + " | Итог |")
	print("|---|---|" + "---|".repeat(seeds.size()) + "---|")
	bad += _rows(TARGETS, seeds, facts, true)
	print("")
	print("Коридоры (линия отсчёта, прогон не режут):")
	_rows(CORRIDORS, seeds, facts, false)
	for t in INFO:
		var vals: Array = []
		for s in seeds:
			var v = facts.get(t["key"], {}).get(int(s), null)
			vals.append("—" if v == null else ("NA" if v is String else "%.1f" % float(v)))
		print("  справочно: %s — %s" % [t["title"], ", ".join(vals)])
	return bad


func _rows(table: Array, seeds: Array, facts: Dictionary, cut: bool) -> int:
	var bad: int = 0
	for t in table:
		var row: Array = []
		var any: bool = false
		var all_ok: bool = true
		for s in seeds:
			var v = facts.get(t["key"], {}).get(int(s), null)
			if v == null:
				row.append("—")
				all_ok = false
			elif v is String:
				row.append("NA")
				all_ok = false
			else:
				any = true
				var good: bool = _check(t, float(v))
				all_ok = all_ok and good
				row.append(("%.2f" % float(v)) + ("" if good else " ✗"))
		var verdict: String = "в допуске" if (any and all_ok) else "ВНЕ ДОПУСКА"
		if not cut:
			verdict = "коридор" if any else "нет цифры"
		elif verdict == "ВНЕ ДОПУСКА":
			bad += 1
		print("| %s | %s | %s | %s |" % [t["title"], _goal(t), " | ".join(row), verdict])
	return bad


func _check(t: Dictionary, v: float) -> bool:
	match String(t["op"]):
		">=": return v >= float(t["v"]) - 0.0001
		"<=": return v <= float(t["v"]) + 0.0001
		">": return v > float(t["v"])
		"==": return is_equal_approx(v, float(t["v"]))
		"in": return v >= float(t["lo"]) - 0.0001 and v <= float(t["hi"]) + 0.0001
	return false


func _goal(t: Dictionary) -> String:
	match String(t["op"]):
		"in": return "%s–%s" % [str(t["lo"]), str(t["hi"])]
		"==": return "= %s" % str(t["v"])
		">=": return "≥ %s" % str(t["v"])
		"<=": return "≤ %s" % str(t["v"])
		">": return "> %s" % str(t["v"])
	return ""
