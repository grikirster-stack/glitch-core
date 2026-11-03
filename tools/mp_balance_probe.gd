extends SceneTree
## Таблица баланса кооператива (ADR-002 § 2, § 4.7; MP-K, #96): «метрика → цель → факт»
## по числу игроков N = 1…4 и сидам. Образец — tools/balance_probe.gd (#33).
##
## Для каждого прогона, сида и N запускает хост-процесс сетевого сценария
##   godot --headless --path . -- --mp-scenario=<бот> --mp-clients=<N−1> --seed=<сид>
##         --balance-out=<файл> [флаги бота --mpb-…]
## (хост сам запускает N−1 клиентов на 127.0.0.1, все — headless; харнесс MP-A), разбирает
## строки «ключ=значение» файла метрик и печатает таблицу: цель, факт по N (среднее по
## сидам и разброс), в допуске ли. NA / «—» — не измерено.
##
## Боты — tools/mp/scenarios/mp_balance_*.gd; в «--mp-scenario=all» и в CI их нет ("manual").
## Ускорения нет (сетевые часы — по часам стены), поэтому прогон долгий: ночь ≈ 1.7 мин
## на запуск, всё на трёх сидах ≈ 1.5 ч. Части гоняются отдельно и складываются:
##   godot --headless --path . --script res://tools/mp_balance_probe.gd
##   godot --headless --path . --script res://tools/mp_balance_probe.gd -- --runs=night1,siege3 --n=1,4 --seeds=31337
##   ... -- --runs=siege3 --out=a.json        затем  ... -- --runs= --load=a.json,b.json   (только таблица)
## --logs=<папка> — вывод каждого запуска в файл <прогон>_n<N>_<сид>.txt.
## --hand-min=<мин> — минут чистой добычи релея руками одиночки (иначе — balance_hand на
## каждом сиде, ≈ 2.5 мин; нужен для оценки «релей командой»).
## Код возврата 1, если хоть одна измеренная метрика вне допуска.

const DEFAULT_SEEDS: Array = [31337, 4242, 12345]
const DEFAULT_N: Array = [1, 2, 3, 4]
## Предел на один запуск (сценарий сам укладывается в timeout_ms реестра, ≤ 4 мин).
const RUN_LIMIT_MS: int = 330000

## Прогоны: имя → сценарий, флаги хоста, при каких N (по умолчанию — все из --n).
const RUNS: Dictionary = {
	"night1": {"sc": "mp_balance_night", "flags": []},
	"night1_dark": {"sc": "mp_balance_night", "flags": ["--mpb-nolamp"], "ns": [1, 4]},
	"night3_dark": {"sc": "mp_balance_night", "flags": ["--mpb-day=3", "--mpb-nolamp", "--mpb-invuln"]},
	"night3_solo1": {"sc": "mp_balance_night", "flags": ["--mpb-day=3", "--mpb-nolamp", "--mpb-invuln", "--mpb-spot=1"], "ns": [1]},
	"night3_solo2": {"sc": "mp_balance_night", "flags": ["--mpb-day=3", "--mpb-nolamp", "--mpb-invuln", "--mpb-spot=2"], "ns": [1]},
	"night3_solo3": {"sc": "mp_balance_night", "flags": ["--mpb-day=3", "--mpb-nolamp", "--mpb-invuln", "--mpb-spot=3"], "ns": [1]},
	"siege3": {"sc": "mp_balance_siege", "flags": ["--mpb-day=3"]},
	"def3": {"sc": "mp_balance_siege", "flags": ["--mpb-day=3", "--mpb-def"]},
	"siege5": {"sc": "mp_balance_siege", "flags": ["--mpb-day=5"], "ns": [1, 4]},
	"def5": {"sc": "mp_balance_siege", "flags": ["--mpb-day=5", "--mpb-def"], "ns": [1, 4]},
	"mining": {"sc": "mp_balance_mining", "flags": []},
	"doppel": {"sc": "mp_balance_doppel", "flags": [], "ns": [2, 3, 4]},
}
const DEFAULT_RUNS: Array = ["night1", "night1_dark", "night3_dark", "night3_solo1", "night3_solo2",
		"night3_solo3", "siege3", "def3", "siege5", "def5", "mining", "doppel"]

## Цели. key — «прогон.метрика»; ratio — факт при N делится на факт при N = 1 того же сида;
## ns — при каких N проверять. op: ">=", "<=", "==", "in" (lo..hi).
const TARGETS: Array = [
	{"key": "est.pressure_own", "ns": [2, 3, 4], "op": "in", "lo": 0.6, "hi": 1.0,
		"title": "давление на игрока: фантомов на героя, доля от одиночки в той же точке (ночь 3 без ламп, по шахтам)"},
	{"key": "est.pressure_enc", "ns": [2, 3, 4], "op": "in", "lo": 0.6, "hi": 1.0,
		"title": "давление на игрока: встреч с фантомами (ближе 48 px) на героя, доля от одиночки в той же точке"},
	{"key": "night1.night_deaths", "ns": [1, 2, 3, 4], "op": "==", "v": 0.0,
		"title": "ночь 1, по 3 лампы, по шахтам: смертей (выжили все)"},
	{"key": "siege3.siege_lost", "ns": [1, 2, 3, 4], "op": ">=", "v": 1.0,
		"title": "ночь 3 без обороны: машин потеряно"},
	{"key": "def3.siege_lost", "ns": [1, 2, 3, 4], "op": "==", "v": 0.0,
		"title": "ночь 3, 2 турели + стена: машин потеряно"},
	{"key": "night1.night_h2c_bps", "ns": [2, 3, 4], "op": "<=", "v": 12288.0,
		"title": "трафик хост → клиент, обычная ночь (по шахтам), Б/с"},
	{"key": "siege3.siege_h2c_bps", "ns": [2, 3, 4], "op": "<=", "v": 12288.0,
		"title": "трафик хост → клиент, осада базы (база в зоне интереса), Б/с"},
	{"key": "night1.night_c2h_bps", "ns": [2, 3, 4], "op": "<=", "v": 4096.0,
		"title": "трафик клиент → хост, Б/с"},
	{"key": "est.win_min", "ns": [4], "op": "in", "lo": 30.0, "hi": 45.0,
		"title": "оценка первой победы вчетвером, мин (модель ниже)"},
]
## Справочные строки (без цели).
const INFO: Array = [
	{"key": "night3_dark.night_own_pp", "title": "ночь 3 без ламп: фантомов на героя"},
	{"key": "night3_dark.night_enc_pp", "title": "ночь 3 без ламп: встреч на героя"},
	{"key": "night3_dark.night_spawned", "title": "ночь 3 без ламп: фантомов вышло (рой — поштучно)"},
	{"key": "night3_dark.night_budget", "title": "ночь 3 без ламп: бюджет ночи"},
	{"key": "night1.night_hp_min", "title": "ночь 1 с лампами: мин. hp героя в конце"},
	{"key": "night1.night_enc_pp", "title": "ночь 1 с лампами: встреч на героя"},
	{"key": "night1.night_spawned", "title": "ночь 1 с лампами: фантомов вышло"},
	{"key": "night1_dark.night_deaths", "title": "ночь 1 без ламп: смертей"},
	{"key": "night1_dark.night_enc_pp", "title": "ночь 1 без ламп: встреч на героя"},
	{"key": "siege3.siege_spawned", "title": "ночь 3, осада: фантомов вышло"},
	{"key": "siege3.siege_hits", "title": "ночь 3 без обороны: ударов по машинам"},
	{"key": "def3.siege_hits", "title": "ночь 3 с обороной: ударов по машинам"},
	{"key": "def3.siege_min_hp", "title": "ночь 3 с обороной: мин. hp уцелевших машин, %"},
	{"key": "siege5.siege_lost", "title": "ночь 5 без обороны: машин потеряно"},
	{"key": "def5.siege_lost", "title": "ночь 5, 2 турели + стена: машин потеряно"},
	{"key": "def5.siege_min_hp", "title": "ночь 5 с обороной: мин. hp уцелевших машин, %"},
	{"key": "night1.night_h2c_bps", "title": "трафик хост → клиент, ночь 1 по шахтам, Б/с"},
	{"key": "night3_dark.night_h2c_bps", "title": "трафик хост → клиент, ночь 3 по шахтам, Б/с"},
	{"key": "mining.mine_spu", "title": "добыча через сеть: с на единицу железной руды (среднее по героям)"},
	{"key": "mining.mine_spu_max", "title": "добыча: с/ед у самого медленного героя"},
	{"key": "est.team_mine_min", "title": "релей руками командой: минут чистой добычи"},
	{"key": "est.win_lo", "title": "оценка первой победы, мин, если одиночка — 40 мин"},
	{"key": "est.win_hi", "title": "оценка первой победы, мин, если одиночка — 60 мин"},
	{"key": "doppel.doppel_life", "title": "двойник: с от появления до раскрытия (первого удара)"},
	{"key": "doppel.doppel_dmg", "title": "двойник: урон героям до раскрытия"},
	{"key": "doppel.rollcall_net_lat", "title": "перекличка: задержка ответа по сети, с"},
	{"key": "doppel.rollcall_false_red", "title": "перекличка: доля окна, когда ответивший снова красный"},
]

## Первая победа одиночки (ADR-001 § 2): 40–60 мин, середина — 50.
const SOLO_WIN_MIN: Array = [40.0, 50.0, 60.0]

var facts: Dictionary = {}    ## ключ → {N → {сид → значение | "NA"}}


func _initialize() -> void:
	var seeds: Array = DEFAULT_SEEDS.duplicate()
	var ns: Array = DEFAULT_N.duplicate()
	var runs: Array = DEFAULT_RUNS.duplicate()
	var hand_min: float = -1.0
	var out_path: String = ""
	var logs: String = ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = Array(a.substr(8).split(",", false)).map(func(s): return int(s))
		elif a.begins_with("--n="):
			ns = Array(a.substr(4).split(",", false)).map(func(s): return int(s))
		elif a.begins_with("--runs="):
			runs = Array(a.substr(7).split(",", false))
		elif a.begins_with("--hand-min="):
			hand_min = float(a.substr(11))
		elif a.begins_with("--out="):
			out_path = a.substr(6)
		elif a.begins_with("--logs="):
			logs = a.substr(7)
		elif a.begins_with("--load="):
			for p in a.substr(7).split(",", false):
				_load(String(p))
	var exe: String = OS.get_executable_path()
	var proj: String = ProjectSettings.globalize_path("res://")
	var failed: Array = []
	for run in runs:
		if not RUNS.has(run):
			print("нет прогона %s (есть: %s)" % [run, ", ".join(RUNS.keys())])
			continue
		for s in seeds:
			for n in ns:
				if RUNS[run].has("ns") and not (RUNS[run]["ns"] as Array).has(int(n)):
					continue
				var t0: int = Time.get_ticks_msec()
				var mfile: String = OS.get_user_data_dir().path_join("mp_balance_probe_%d.txt" % OS.get_process_id())
				if FileAccess.file_exists(mfile):
					DirAccess.remove_absolute(mfile)
				var args: PackedStringArray = ["--headless", "--path", proj, "--",
						"--mp-scenario=" + String(RUNS[run]["sc"]), "--mp-clients=%d" % (int(n) - 1),
						"--seed=%d" % int(s), "--balance-out=" + mfile]
				args.append_array(PackedStringArray(RUNS[run]["flags"]))
				var res: Dictionary = _run(exe, args, RUN_LIMIT_MS)
				var code: int = int(res["code"])
				if logs != "":
					var lf: FileAccess = FileAccess.open(logs.path_join("%s_n%d_%d.txt" % [run, int(n), int(s)]), FileAccess.WRITE)
					if lf != null:
						lf.store_buffer(res["out"])
						lf.close()
				for line in FileAccess.get_file_as_string(mfile).split("\n", false):
					var kv: PackedStringArray = line.strip_edges().split("=")
					if kv.size() == 2:
						_put("%s.%s" % [run, kv[0]], int(n), int(s), "NA" if kv[1] == "NA" else float(kv[1]))
				if code != 0:
					failed.append("%s N=%d сид %d" % [run, int(n), int(s)])
				print("%s, N = %d, сид %d: %.0f с, код %d" % [run, int(n), int(s),
						float(Time.get_ticks_msec() - t0) / 1000.0, code])
	if runs.has("mining") or facts.has("mining.mine_spu"):
		_estimate(seeds, hand_min, exe, proj)
	for m in ["own", "enc"]:
		_pressure(m)
	if out_path != "":
		var f: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(facts))
			f.close()
	var bad: int = _print_table()
	if not failed.is_empty():
		print("сценарии с провалами проверок: %s" % ", ".join(failed))
	quit(1 if bad > 0 else 0)


## Запуск дочернего Godot с пределом времени: сценарий, который не загрузился (ошибка
## разбора — игра пошла обычным забегом), не выходит сам — его убиваем, это провал.
## Вывод читается всё время, иначе полный канал остановил бы процесс.
func _run(exe: String, args: PackedStringArray, limit_ms: int) -> Dictionary:
	var r: Dictionary = OS.execute_with_pipe(exe, args, false)
	if r.is_empty():
		return {"code": -1, "out": PackedByteArray()}
	var pid: int = int(r["pid"])
	var buf: PackedByteArray = PackedByteArray()
	var t0: int = Time.get_ticks_msec()
	var killed: bool = false
	while true:
		for f in [r["stdio"], r["stderr"]]:
			for _k in 64:
				var chunk: PackedByteArray = (f as FileAccess).get_buffer(4096)
				if chunk.is_empty():
					break
				buf.append_array(chunk)
		if not OS.is_process_running(pid):
			break
		if Time.get_ticks_msec() - t0 > limit_ms:
			OS.kill(pid)
			killed = true
			break
		OS.delay_msec(200)
	return {"code": -2 if killed else OS.get_process_exit_code(pid), "out": buf}


func _put(key: String, n: int, s: int, v) -> void:
	if not facts.has(key):
		facts[key] = {}
	if not facts[key].has(n):
		facts[key][n] = {}
	facts[key][n][s] = v


func _load(path: String) -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		print("не прочитать %s" % path)
		return
	for key in d:
		for n in d[key]:
			for s in d[key][n]:
				_put(String(key), int(n), int(s), d[key][n][s])


# ------------------------------------------------------------------ ОЦЕНКА ЗАБЕГА

## Оценка первой победы командой (честная модель, не прогон забега: бота «забег целиком»
## у ADR-001 нет, его 40–60 мин — цель плейтеста). Из забега одиночки R1 параллелится
## только чистая добыча сырья релея руками M1 (balance_hand): N героев копают
## одновременно со своей скоростью по сети (mp_balance_mining, с/ед при N против N = 1).
## Остальное (разведка, исследования — данные общие, терминал один на команду, — стройка,
## ночи, удержание сигнала 180 с) берём как у одиночки: R_N = R1 − M1 + M_N,
## M_N = M1 · (с/ед при N ÷ с/ед при N = 1) ÷ N.
func _estimate(seeds: Array, hand_min: float, exe: String, proj: String) -> void:
	for s in seeds:
		var m1: float = hand_min
		if m1 < 0.0:
			var mfile: String = OS.get_user_data_dir().path_join("mp_balance_probe_hand_%d.txt" % OS.get_process_id())
			if FileAccess.file_exists(mfile):
				DirAccess.remove_absolute(mfile)
			_run(exe, PackedStringArray(["--headless", "--path", proj, "--", "--scenario=balance_hand",
					"--seed=%d" % int(s), "--balance-out=" + mfile]), RUN_LIMIT_MS)
			for line in FileAccess.get_file_as_string(mfile).split("\n", false):
				var kv: PackedStringArray = line.strip_edges().split("=")
				if kv.size() == 2 and kv[0] == "hand_relay_min" and kv[1] != "NA":
					m1 = float(kv[1])
			print("balance_hand, сид %d: %.2f мин добычи" % [int(s), m1])
		if m1 < 0.0:
			continue
		var spu: Dictionary = facts.get("mining.mine_spu", {})
		var base = spu.get(1, {}).get(int(s), null)
		for n in spu:
			var v = spu[n].get(int(s), null)
			if v == null or v is String or base == null or base is String or float(base) <= 0.0:
				continue
			var mn: float = m1 * (float(v) / float(base)) / float(n)
			_put("est.team_mine_min", int(n), int(s), mn)
			_put("est.win_lo", int(n), int(s), SOLO_WIN_MIN[0] - m1 + mn)
			_put("est.win_min", int(n), int(s), SOLO_WIN_MIN[1] - m1 + mn)
			_put("est.win_hi", int(n), int(s), SOLO_WIN_MIN[2] - m1 + mn)


## Давление на игрока при N: Σ по героям k < N метрики героя в точке k при N, делённая на
## Σ той же метрики одиночки в точке k (night3_dark при N = 1 — точка 0, night3_soloK — K).
## Тот же герой, та же точка, та же ночь сида — разница только в товарищах и формулах N.
func _pressure(m: String) -> void:
	var seeds: Array = _seeds_seen()
	for s in seeds:
		var solo: Array = []
		for k in 4:
			var run: String = "night3_dark" if k == 0 else "night3_solo%d" % k
			solo.append(facts.get("%s.night_%s_h%d" % [run, m, k], {}).get(1, {}).get(int(s), null))
		for n in [2, 3, 4]:
			var num: float = 0.0
			var den: float = 0.0
			var full: bool = true
			for k in n:
				var v = facts.get("night3_dark.night_%s_h%d" % [m, k], {}).get(n, {}).get(int(s), null)
				if v == null or v is String or solo[k] == null or solo[k] is String:
					full = false
					break
				num += float(v)
				den += float(solo[k])
			if full:
				_put("est.pressure_" + m, n, int(s), num / den if den > 0.0 else "NA")


# ------------------------------------------------------------------ ТАБЛИЦА

## Значения строки при N по сидам (ratio — делённые на N = 1 того же сида). null — нет.
func _vals(t: Dictionary, n: int) -> Array:
	var out: Array = []
	var by_n: Dictionary = facts.get(String(t["key"]), {})
	var row: Dictionary = by_n.get(n, {})
	for s in row:
		var v = row[s]
		if v is String:
			out.append("NA")
			continue
		if bool(t.get("ratio", false)):
			var b = by_n.get(1, {}).get(s, null)
			if b == null or b is String or float(b) <= 0.0:
				out.append("NA")
				continue
			out.append(float(v) / float(b))
		else:
			out.append(float(v))
	return out


func _cell(vals: Array, t: Dictionary, check: bool) -> Dictionary:
	var nums: Array = vals.filter(func(x): return not x is String)
	if nums.is_empty():
		return {"text": "NA" if not vals.is_empty() else "—", "ok": null}
	var lo: float = INF
	var hi: float = -INF
	var sum: float = 0.0
	var good: bool = true
	for x in nums:
		lo = minf(lo, float(x))
		hi = maxf(hi, float(x))
		sum += float(x)
		if check:
			good = good and _check(t, float(x))
	var avg: float = sum / float(nums.size())
	var fmt: String = "%.2f" if absf(avg) < 100.0 else "%.0f"
	var text: String = fmt % avg
	if nums.size() > 1 and not is_equal_approx(lo, hi):
		text += (" (" + fmt + "–" + fmt + ")") % [lo, hi]
	if check and not good:
		text += " ✗"
	return {"text": text, "ok": good if check else null}


func _print_table() -> int:
	var bad: int = 0
	var ns: Array = DEFAULT_N
	print("")
	print("Факт — среднее по сидам (разброс мин–макс). Сиды: %s." % ", ".join(_seeds_seen().map(func(s): return str(s))))
	print("")
	print("| Метрика | Цель (ADR-002 § 2) | " + " | ".join(ns.map(func(n): return "N = %d" % n)) + " | Итог |")
	print("|---|---|" + "---|".repeat(ns.size()) + "---|")
	for t in TARGETS:
		var cells: Array = []
		var any: bool = false
		var all_ok: bool = true
		for n in ns:
			var check: bool = (t["ns"] as Array).has(n)
			var c: Dictionary = _cell(_vals(t, n), t, check)
			if check:
				if c["ok"] == null:
					all_ok = false
				else:
					any = true
					all_ok = all_ok and bool(c["ok"])
			cells.append(c["text"] if check or c["text"] != "—" else "")
		var verdict: String = "в допуске" if any and all_ok else ("ВНЕ ДОПУСКА" if any else "не измерено")
		if verdict == "ВНЕ ДОПУСКА":
			bad += 1
		print("| %s | %s | %s | %s |" % [t["title"], _goal(t), " | ".join(cells), verdict])
	print("")
	print("Справочно:")
	print("")
	print("| Метрика | " + " | ".join(ns.map(func(n): return "N = %d" % n)) + " |")
	print("|---|" + "---|".repeat(ns.size()))
	for t in INFO:
		var cells: Array = []
		for n in ns:
			cells.append(_cell(_vals(t, n), t, false)["text"])
		print("| %s | %s |" % [t["title"], " | ".join(cells)])
	return bad


func _seeds_seen() -> Array:
	var out: Array = []
	for key in facts:
		for n in facts[key]:
			for s in facts[key][n]:
				if not out.has(int(s)):
					out.append(int(s))
	out.sort()
	return out


func _check(t: Dictionary, v: float) -> bool:
	match String(t["op"]):
		">=": return v >= float(t["v"]) - 0.0001
		"<=": return v <= float(t["v"]) + 0.0001
		"==": return is_equal_approx(v, float(t["v"]))
		"in": return v >= float(t["lo"]) - 0.0001 and v <= float(t["hi"]) + 0.0001
	return false


func _goal(t: Dictionary) -> String:
	match String(t["op"]):
		"in": return "%s–%s" % [str(t["lo"]), str(t["hi"])]
		"==": return "= %s" % str(t["v"])
		">=": return "≥ %s" % str(t["v"])
		"<=": return "≤ %s" % str(t["v"])
	return ""
