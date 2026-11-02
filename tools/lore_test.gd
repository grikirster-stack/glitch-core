extends SceneTree
class_name LoreTest
## Автотест генеративного лора (ADR-001, § 4.9; issue #26).
##
## На 100 сидах проверяет: генерация без сбоев, нет незакрытых `{` и `}` в выводе,
## один сид даёт одинаковый вывод, другой сид — другой экипаж, «не тот» никогда не
## автор записей, длина каждой главы ≥ 120 символов, у каждого члена экипажа есть
## имя, роль и позывной. Плюс прямые проверки согласования рода и числа.
##
## Отдельный запуск (мир не нужен, он не генерируется):
##   godot --headless --path . --script res://tools/lore_test.gd
## В составе общего прогона те же самые проверки вызывает tools/test_runner.gd
## (секция «== Лор ==») — общий код, без дублирования.
##
## Внимание: файл запускается как главный цикл движка (--script), а в этом
## режиме глобальные имена автозагрузок (Lore/World) на этапе компиляции ещё
## недоступны — поэтому все узлы берём через get_node(), а типы не указываем.

# --------------------------------------------------------------- КОНСТАНТЫ
## Сколько сидов гоняем.
const SEED_COUNT: int = 100
## Длина главы, меньше которой текст считается недописанным.
const MIN_CHAPTER_LEN: int = 120
## Роли в том порядке, в котором они закреплены в экипаже.
const ROLES: Array = ["капитан", "инженер", "медик", "геолог", "связист", "пилот", "техник"]
## Статистика для проверки эпилога.
const STATS: Dictionary = {"days": 5, "kills": 21, "deaths": 2, "time": 2700.0}


## --------------------------------------------------------------------- исполнитель
class Runner extends Node:
	## Все проверки синхронные: Lore — чистые данные, ждать кадров нечего.
	var host: Node = null          ## кто-то снаружи (test_runner)
	var scene: Node = null
	var lore = null                ## узел автозагрузки Lore
	var world = null               ## узел автозагрузки World

	var checks: int = 0
	var fails: int = 0
	var done: bool = false

	## Сид → строка, чтобы показать, на каком сиде упала проверка.
	var _bad: Dictionary = {}
	var _min_len: int = 1000000
	var _gen_sum_ms: float = 0.0
	var _gen_max_ms: float = 0.0


	func _init(p_host: Node = null) -> void:
		host = p_host


	## Запуск: main_scene — корень сцены игры или null (отдельный запуск).
	func start(main_scene: Node) -> void:
		scene = main_scene
		print("== Лор ==")
		lore = get_tree().root.get_node_or_null("Lore")
		world = get_tree().root.get_node_or_null("World")
		_ok("автозагрузка Lore на месте", lore != null)
		_ok("автозагрузка World на месте", world != null)
		if lore == null or world == null:
			done = true
			return
		# Тест сам переключает сид Lore — возвращаем всё как было.
		var world_seed0: int = int(world.world_seed)
		var quiet0: bool = bool(lore.quiet)
		lore.quiet = true

		var seeds: Array = _seeds()
		var sigs: Dictionary = {}
		var prev_sig: String = ""
		var same_neighbor: Array = []
		for s in seeds:
			var sig: String = _check_seed(int(s))
			sigs[sig] = true
			if sig == prev_sig:
				same_neighbor.append(int(s))
			prev_sig = sig
		_report(seeds.size())
		_ok("другой сид — другой экипаж (%d сидов, %d разных составов)" % [seeds.size(), sigs.size()],
				sigs.size() == seeds.size() and same_neighbor.is_empty(), str(same_neighbor))

		_check_render()
		_check_lazy(world_seed0)
		_check_api()

		lore.quiet = quiet0
		lore.generate(world_seed0)
		done = true


	func _ok(label: String, cond: bool, extra: String = "") -> void:
		checks += 1
		if cond:
			print("  OK   %s %s" % [label, extra])
		else:
			fails += 1
			print("  FAIL %s %s" % [label, extra])


	# ------------------------------------------------------------------ сиды

	## 100 сидов: контрольные, граничные и случайные (но всегда одни и те же).
	func _seeds() -> Array:
		var out: Array = [31337, 4242, 12345, 0, 1, -7, 4294967295]
		var r: RandomNumberGenerator = RandomNumberGenerator.new()
		r.seed = 20261102
		while out.size() < SEED_COUNT:
			var v: int = int(r.randi())
			if not out.has(v):
				out.append(v)
		return out


	## Запоминает, на каком сиде упала проверка (первый плохой сид).
	func _flag(key: String, s: int) -> void:
		if not _bad.has(key):
			_bad[key] = []
		_bad[key].append(s)


	## Все проверки одного сида. Возвращает «подпись» экипажа для сравнения сидов.
	func _check_seed(s: int) -> String:
		lore.generate(s)
		var ms: float = float(lore.last_gen_ms)
		_gen_sum_ms += ms
		_gen_max_ms = maxf(_gen_max_ms, ms)

		var crew: Array = lore.crew
		var imp: Dictionary = lore.impostor

		# 1. Генерация без сбоев: ошибка в скрипте оставила бы пустые значения.
		var shape_ok: bool = crew.size() == 7 and int(lore.chapter_count()) == 9 \
				and int(lore.fragment_count()) == 20 and not imp.is_empty()
		for i in int(lore.chapter_count()):
			if String(lore.chapter(i)) == "" or String(lore.chapter_title(i)) == "" \
					or String(lore.chapter_place(i)) == "":
				shape_ok = false
		if not shape_ok:
			_flag("shape", s)

		# 2. Роли закреплены, у каждого есть имя, фамилия, позывной, род.
		var roles_ok: bool = crew.size() == ROLES.size()
		var fields_ok: bool = true
		var syl_ok: bool = true
		var impostors: int = 0
		var names: Dictionary = {}
		var signs: Dictionary = {}
		for i in crew.size():
			var c: Dictionary = crew[i]
			if String(c["role"]) != String(ROLES[i]) or int(c["idx"]) != i:
				roles_ok = false
			for key in ["role", "name", "name_r", "name_d", "name_v", "name_t", "surname", "surname_gen", "callsign", "full"]:
				if String(c.get(key, "")) == "":
					fields_ok = false
			if not (String(c.get("gender", "")) in ["m", "f"]):
				fields_ok = false
			if bool(c["impostor"]):
				impostors += 1
			names[String(c["name"])] = true
			signs[String(c["callsign"])] = true
			# Имя и фамилия (в мужской форме) — по 2–3 слога.
			var n1: int = _syllables(String(c["name"]))
			var n2: int = _syllables(String(c["surname_m"]))
			if n1 < 2 or n1 > 3 or n2 < 2 or n2 > 3:
				syl_ok = false
		if not roles_ok:
			_flag("roles", s)
		if not fields_ok:
			_flag("fields", s)
		if not syl_ok:
			_flag("syllables", s)
		if impostors != 1 or not bool(imp.get("impostor", false)) or not crew.has(imp):
			_flag("impostor_one", s)
		if names.size() != 7 or signs.size() != 7:
			_flag("unique", s)

		# 3. «Не тот» ни разу не автор; длина глав.
		var authors_ok: bool = true
		for i in int(lore.chapter_count()):
			var a: Dictionary = lore.chapter_author(i)
			if a.is_empty() or int(a["idx"]) == int(imp["idx"]) or bool(a["impostor"]):
				authors_ok = false
			var len_i: int = String(lore.chapter(i)).length()
			_min_len = mini(_min_len, len_i)
			if len_i < MIN_CHAPTER_LEN:
				_flag("short", s)
		if not authors_ok:
			_flag("author", s)

		# 4. Места: непустые, руины и тоннели различаются.
		var places_ok: bool = String(lore.place_name("crystal", 0)) != ""
		var ruins: Dictionary = {}
		var tunnels: Dictionary = {}
		for i in 7:
			ruins[String(lore.place_name("ruin", i))] = true
		for i in 4:
			tunnels[String(lore.place_name("tunnel", i))] = true
		for i in 2:
			if String(lore.place_name("base", i)) == "":
				places_ok = false
		if ruins.size() != 7 or tunnels.size() != 4 or not places_ok:
			_flag("places", s)

		# 5. Никаких «хвостов» шаблонов в выводе, ни в одном тексте.
		var snap1: String = _snapshot()
		if snap1.find("{") >= 0 or snap1.find("}") >= 0:
			_flag("braces", s)

		# 6. Один сид — один вывод (между прогонами лор собирается по другому сиду).
		lore.generate(s + 1)
		lore.generate(s)
		var snap2: String = _snapshot()
		if snap1 != snap2:
			_flag("determinism", s)

		var parts: PackedStringArray = PackedStringArray()
		for c in crew:
			parts.append(String(c["full"]) + "/" + String(c["callsign"]) + "/" + String(c["role"]))
		parts.append(str(imp["idx"]))
		return ",".join(parts)


	## Все публичные тексты лора одной строкой. Эпитафии берутся по порядку:
	## повторная генерация сбрасывает очередь, поэтому вывод сравним.
	func _snapshot() -> String:
		var parts: PackedStringArray = PackedStringArray()
		for c in lore.crew:
			parts.append("%s|%s|%s|%s|%s|%s" % [c["role"], c["name"], c["surname"], c["callsign"], c["gender"], c["surname_gen"]])
		parts.append(str(lore.impostor["idx"]))
		for i in 7:
			parts.append(String(lore.place_name("ruin", i)) + "/" + str(lore.ruin_owner(i)["idx"]))
		for i in 4:
			parts.append(String(lore.place_name("tunnel", i)))
		for i in 2:
			parts.append(String(lore.place_name("base", i)))
		parts.append(String(lore.place_name("crystal", 0)))
		for i in int(lore.chapter_count()):
			parts.append(String(lore.chapter_title(i)))
			parts.append(String(lore.chapter_place(i)))
			parts.append(str(lore.chapter_author(i)["idx"]))
			parts.append(String(lore.chapter(i)))
		var frng: RandomNumberGenerator = RandomNumberGenerator.new()
		frng.seed = 777
		for i in int(lore.fragment_count()):
			parts.append(String(lore.fragment_at(i, frng)))
		for i in 3:
			parts.append(String(lore.fragment(frng)))
		for i in 10:
			parts.append(String(lore.epitaph()))
		parts.append(String(lore.epilogue(STATS)))
		parts.append(String(lore.epilogue({})))
		return "\n".join(parts)


	## Число гласных = число слогов.
	func _syllables(word: String) -> int:
		var n: int = 0
		for ch in word.to_lower():
			if "аеёиоуыэюя".contains(ch):
				n += 1
		return n


	## Итог по всем сидам: по одной строке на проверку.
	func _report(total: int) -> void:
		var rows: Array = [
			["shape", "генерация без сбоев (экипаж 7, глав 9, обрывков 20, тексты непустые)"],
			["braces", "нет незакрытых { и } в выводе"],
			["determinism", "один сид — одинаковый вывод"],
			["author", "«не тот» не автор ни одной главы"],
			["short", "длина каждой главы ≥ %d символов (минимум %d)" % [MIN_CHAPTER_LEN, _min_len]],
			["roles", "роли экипажа закреплены"],
			["fields", "у каждого члена экипажа есть имя, фамилия, роль, позывной, род"],
			["syllables", "имя и фамилия — по 2–3 слога"],
			["impostor_one", "ровно один «не тот», он из состава экипажа"],
			["unique", "имена и позывные в экипаже не повторяются"],
			["places", "имена мест непустые, руины и тоннели различаются"],
		]
		for row in rows:
			var key: String = String(row[0])
			var bad: Array = _bad.get(key, [])
			_ok("%s (%d сидов)" % [row[1], total], bad.is_empty(),
					"" if bad.is_empty() else "плохих сидов %d, первые %s" % [bad.size(), str(bad.slice(0, 4))])
		var avg_ms: float = _gen_sum_ms / maxf(1.0, float(total))
		print("  ЗАМЕР  время генерации лора на сид: среднее %.2f мс, максимум %.2f мс; шаблонных строк в словарях: %d"
				% [avg_ms, _gen_max_ms, int(lore.template_count())])


	# ------------------------------------------------------- прямые проверки

	## Шаблонизатор: род автора, «героя», «не того», число, неизвестный ключ.
	func _check_render() -> void:
		var f: Dictionary = {"_ga": "f", "_gs": "m", "_gi": "f", "n": 2}
		var m: Dictionary = {"_ga": "m", "_gs": "f", "_gi": "m", "n": 5}
		_ok("род автора: {решил|решила}",
				lore.render("{решил|решила}", f) == "решила" and lore.render("{решил|решила}", m) == "решил")
		_ok("род «героя»: {~он|она}",
				lore.render("{~он|она}", f) == "он" and lore.render("{~он|она}", m) == "она")
		_ok("род «не того»: {^встал|встала}",
				lore.render("{^встал|встала}", f) == "встала" and lore.render("{^встал|встала}", m) == "встал")
		_ok("суффиксы рода: сказал{|а}, не успел{^|а}",
				lore.render("сказал{|а}", f) == "сказала" and lore.render("сказал{|а}", m) == "сказал"
				and lore.render("не успел{^|а}", f) == "не успела")
		var plural: String = "{#час|часа|часов}"
		var got: PackedStringArray = PackedStringArray()
		for n in [1, 2, 4, 5, 11, 12, 21, 22, 25, 111]:
			got.append(String(lore.render(plural, {"n": n})))
		_ok("число: час / часа / часов", ",".join(got) == "час,часа,часа,часов,часов,часов,час,часа,часов,часов",
				",".join(got))
		_ok("неизвестный ключ остаётся в тексте (его поймает проверка на `{`)",
				lore.render("а {нет_такого} б", {}) == "а {нет_такого} б")
		_ok("подстановка и число: «{имя}: {n}»", lore.render("{имя}: {n}", {"имя": "Ян", "n": 3}) == "Ян: 3")
		var man: Dictionary = lore.decline("Ардан", false)
		var woman: Dictionary = lore.decline("Ника", true)
		var soft: Dictionary = lore.decline("Роля", true)
		_ok("падежи имени: Ардан, Ника, Роля",
				man == {"r": "Ардана", "d": "Ардану", "v": "Ардана", "t": "Арданом"}
				and woman == {"r": "Ники", "d": "Нике", "v": "Нику", "t": "Никой"}
				and soft == {"r": "Роли", "d": "Роле", "v": "Ролю", "t": "Ролей"},
				str(man) + str(woman) + str(soft))


	## Lore сам пересобирается, когда сменился World.world_seed (World.generate не трогаем).
	func _check_lazy(world_seed0: int) -> void:
		var a: int = world_seed0 + 1000003
		lore.generate(a)
		var snap_a: String = _snapshot()
		lore.generate(a + 5)
		world.world_seed = a
		var lazy: String = _snapshot()
		world.world_seed = world_seed0
		var back: String = String(lore.chapter(0))
		lore.generate(world_seed0)
		_ok("Lore пересобирается при смене World.world_seed", lazy == snap_a)
		_ok("и возвращается к прежнему сиду", back == String(lore.chapter(0)))


	## API: границы индексов, обрывки, эпитафии и эпилог.
	func _check_api() -> void:
		lore.generate(31337)
		_ok("глава вне диапазона — пустая строка", lore.chapter(-1) == "" and lore.chapter(9) == "")
		_ok("автор главы вне диапазона — пустой словарь", lore.chapter_author(99).is_empty())
		_ok("неизвестный вид места — запасное имя", String(lore.place_name("нет", 0)) != "")
		_ok("место: индекс замыкается по кругу", lore.place_name("ruin", 0) == lore.place_name("ruin", 7))
		var r1: RandomNumberGenerator = RandomNumberGenerator.new()
		var r2: RandomNumberGenerator = RandomNumberGenerator.new()
		r1.seed = 99
		r2.seed = 99
		_ok("обрывок: тот же rng — тот же текст", lore.fragment(r1) == lore.fragment(r2))
		var seen: Dictionary = {}
		var rr: RandomNumberGenerator = RandomNumberGenerator.new()
		rr.seed = 5
		for i in 200:
			seen[String(lore.fragment(rr))] = true
		_ok("обрывки разнообразны", seen.size() >= 15, "разных строк %d" % seen.size())
		var ep: String = String(lore.epitaph())
		_ok("эпитафия не пуста и без хвостов", ep != "" and ep.find("{") < 0 and ep.find("}") < 0, ep)
		var full: String = String(lore.epilogue(STATS))
		_ok("эпилог: экипаж и статистика на месте",
				full.find("7") >= 0 and full.find("5 смен") >= 0 and full.find("21 фантом") >= 0
				and full.find("2 смерти") >= 0 and full.find("45 минут") >= 0, full.replace("\n", " ⏎ "))
		_ok("эпилог без статистики не пуст", String(lore.epilogue({})) != "")


# ------------------------------------------------------------- отдельный запуск

var _runner: Node = null
var _started: bool = false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_runner = Runner.new(null)
		root.add_child(_runner)
		_runner.start(null)
		return false
	if _runner == null:
		return false
	if _runner.done:
		print("")
		print("ИТОГ: проверок %d, провалов %d" % [_runner.checks, _runner.fails])
		quit(1 if _runner.fails > 0 else 0)
		return true
	return false
