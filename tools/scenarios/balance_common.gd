extends ScenarioBase
## Общая часть ботов баланса (#33, ADR-001 § 2, § 5.3 «PR-J»).
##
## Боты меряют целевые метрики в ИГРОВОМ времени: своё ускорение
## (Engine.time_scale) и свои часы (clock — сумма delta кадров узла сценария).
## Game.game_time не годится: он стоит, пока игрок мёртв или забег окончен.
##
## Метрика печатается строкой «  [баланс] ключ=значение» — её разбирает
## tools/balance_probe.gd и собирает таблицу «метрика → цель → факт» по сидам.
##
## Директор угрозы в сценариях молчит (Threat.in_scenario); бот ночи включает
## drive_threat — тогда этот узел сам зовёт Threat.tick(delta) каждый кадр,
## и ночь идёт штатным директором (бюджет, состав, вентиляции, телеграф).

## Игровые секунды с начала сценария (растут и при Engine.time_scale > 1).
var clock: float = 0.0
## Вести директора угрозы из сценария (ночные боты).
var drive_threat: bool = false


func _process(delta: float) -> void:
	clock += delta
	if drive_threat and Game.state == Game.State.PLAYING:
		Threat.tick(delta)


## Сценарий снят раннером (в том числе по таймауту) — скорость назад, иначе
## ускорение утечёт в следующие сценарии.
func _exit_tree() -> void:
	Engine.time_scale = 1.0


## Ускорить игру в k раз (игровое время, физика догоняет шагами).
func speed_up(k: float) -> void:
	Engine.time_scale = k


func normal_speed() -> void:
	Engine.time_scale = 1.0


## Конец сценария: вернуть скорость и снять шов ввода.
func finish() -> void:
	normal_speed()
	drive_threat = false
	if player != null:
		clear_input()
	super()


## Подождать игровые секунды.
func wait_game(secs: float) -> void:
	var t_end: float = clock + secs
	while clock < t_end:
		await get_tree().process_frame


## Ждать условия, но не дольше timeout игровых секунд.
func wait_game_until(cond: Callable, timeout: float) -> bool:
	var t_end: float = clock + timeout
	while clock < t_end:
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


## Метрика для balance_probe: «  [баланс] ключ=значение» + человеческая подпись.
func metric(key: String, value: float, note: String = "") -> void:
	print("  [баланс] %s=%.3f%s" % [key, value, ("  # " + note) if note != "" else ""])
	_metric_to_file("%s=%.3f" % [key, value])


## Пометка «не измерено» (зависимость ещё не в main) — probe покажет «отложено».
func metric_na(key: String, why: String) -> void:
	print("  [баланс] %s=NA  # %s" % [key, why])
	_metric_to_file("%s=NA" % key)


## --balance-out=ПУТЬ (его передаёт balance_probe): метрики ещё и строками в файл —
## вывод дочернего процесса на Windows приходит в чужой кодировке.
func _metric_to_file(line: String) -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--balance-out="):
			continue
		var path: String = a.substr(14)
		var f: FileAccess = FileAccess.open(path, FileAccess.READ_WRITE)
		if f == null:
			f = FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			return
		f.seek_end()
		f.store_line(line)
		f.close()


# ------------------------------------------------------------------ БОЙ

var _q_down: bool = false

## Простой боец на месте (через шов ввода, как человек): фантом в досягаемости
## удара — навести «мышь» на него и бить ЛКМ; фантом вплотную и импульс готов —
## Q. Никуда не ходит. Звать каждый кадр.
func fight_step(strike_px: float = 44.0) -> void:
	var near: Node2D = null
	var best: float = strike_px
	for p in get_tree().get_nodes_in_group("phantom"):
		if not is_instance_valid(p) or not bool(p.get("alive")):
			continue
		var d: float = p.global_position.distance_to(player.global_position)
		if d < best:
			best = d
			near = p
	if near == null or player.dead:
		release_mouse(MOUSE_BUTTON_LEFT)
		if _q_down:
			_q_down = false
			release(KEY_Q)
		return
	aim(near.global_position)
	press_mouse(MOUSE_BUTTON_LEFT)
	# Импульс — по фронту нажатия: зажали на кадр, отпустили.
	if _q_down:
		_q_down = false
		release(KEY_Q)
	elif best < 36.0 and player.emp_cd <= 0.0:
		_q_down = true
		hold(KEY_Q)


## Выбрать слот хотбара с предметом id (как клавишей 1–0). false — нет предмета.
func select_item(id: int) -> bool:
	for i in player.inv.hotbar_size:
		if player.inv.slots[i].id == id and not player.inv.slots[i].is_empty():
			var key: int = KEY_1 + i if i < 9 else KEY_0
			hold(key)
			await get_tree().physics_frame
			await get_tree().physics_frame
			release(key)
			return player.inv.selected == i
	return false


## Поставить выбранный предмет в клетку через шов (навести, ПКМ, ждать).
func place_selected(c: Vector2i, expect_tile: int) -> bool:
	aim(World.cell_to_world(c))
	press_mouse(MOUSE_BUTTON_RIGHT)
	var done_ok: bool = await wait_game_until(func() -> bool: return World.get_tile_v(c) == expect_tile, 1.5)
	release_mouse(MOUSE_BUTTON_RIGHT)
	await get_tree().physics_frame
	return done_ok


## Тёмная точка поверхности: свободно на две клетки вверх, твёрдый пол, свет
## ниже max_light; расстояние от релея по x — в [min_dx, max_dx]. Ближайшая к min_dx.
func dark_surface_spot(min_dx: int, max_dx: int, max_light: float = 0.3) -> Vector2i:
	var bx: int = World.beacon_cell.x
	for k in range(min_dx, max_dx + 1):
		for x in [bx + k, bx - k]:
			if x < 3 or x >= World.W - 3:
				continue
			var c: Vector2i = Vector2i(x, World.surface[x] - 1)
			if World.get_tile_v(c) != IDs.T.AIR or World.get_tile_v(c + Vector2i(0, -1)) != IDs.T.AIR:
				continue
			if not World.is_solid_cell(c + Vector2i(0, 1)):
				continue
			if World.light_at(c) > max_light:
				continue
			return c
	return Vector2i(-1, -1)


## Случай директора угрозы (выбор вентиляции, состав, размер стаи) — от сида
## мира: один сид — одна и та же ночь, таблица balance_probe воспроизводима.
func seed_threat(day: int) -> void:
	Threat._rng.seed = int(scene.get("seed_value")) * 31 + day


## Убрать всех фантомов (между фазами одного сценария).
func clear_phantoms() -> void:
	for n in get_tree().get_nodes_in_group("phantom"):
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.queue_free()


# ------------------------------------------------------------------ ОСАДА БАЗЫ

var _lost: Array = []

## «Обычная» база § 4.5 у релея: 2 ТЭЦ, 2 бура, плавильня, сборщик (все под
## питанием — добыча для роя). defended — ещё 2 турели и стальная стена по бокам.
## Возвращает {ok, machines, turrets}.
func build_base(defended: bool) -> Dictionary:
	var bx: int = World.beacon_cell.x
	var row: int = World.beacon_cell.y
	stand_in_corridor(0)
	var plan: Array = [["CoalGen", 5], ["Drill", 7], ["Drill", 8], ["Smelter", 10],
			["Assembler", 12], ["CoalGen", 14]]
	if defended:
		plan.append(["Turret", 6])
		plan.append(["Turret", 13])
	var machines: Array = []
	var turrets: int = 0
	var all_ok: bool = true
	for e in plan:
		var c: Vector2i = Vector2i(bx + int(e[1]), row)
		World.set_tile(c.x, c.y, IDs.T.AIR)
		if not MachineBase.place_machine(String(e[0]), c):
			all_ok = false
			continue
		var m: MachineBase = World.machines[c]
		machines.append(m)
		if m.kind == "Turret":
			turrets += 1
		if m is CoalGen:
			(m as CoalGen).add_fuel(CoalGen.FUEL_MAX_UNITS)
		m.destroyed.connect(func(mb: MachineBase) -> void: _lost.append(mb.kind))
	if defended:
		for x in [bx + 3, bx + 16]:
			for y in range(row - 3, row + 1):
				if World.get_tile(x, y) == IDs.T.AIR and not World.machines.has(Vector2i(x, y)):
					World.set_tile(x, y, IDs.T.STEEL_WALL)
	# Плавильне — руды: пусть база работает, а не стоит.
	for m in machines:
		if m is Smelter:
			m.receive_item(IDs.I.IRON_ORE, 40)
	Game.update_power_budget()
	return {"ok": all_ok, "machines": machines, "turrets": turrets}


## Ночь day у базы: герой стоит у релей-ядра и базу не защищает (не бьёт, не
## жмёт импульс; бессмертен — иначе смерть перемотает время к рассвету и ночь
## кончится раньше). Директор угрозы штатный: меряем, что ночь делает с базой.
## Возвращает {lost, kinds, spawned, deaths}.
func siege_night(day: int, speed: float) -> Dictionary:
	_lost.clear()
	var bx: int = World.beacon_cell.x
	var row: int = World.beacon_cell.y
	stand_next_to_beacon()
	player.invuln = 1.0e9
	seed_threat(day)
	Game.day_number = day
	Game.time_of_day = Balance.NIGHT_START - 1.0 / Balance.DAY_LENGTH
	var deaths0: int = Game.stats_deaths
	var spawned0: int = Threat.spawned_total
	var kinds: Dictionary = {}
	var on_spawn: Callable = func(ph: Node) -> void:
		var k: String = String(ph.get("kind"))
		kinds[k] = int(kinds.get(k, 0)) + 1
		if OS.get_cmdline_user_args().has("--balance-debug"):
			print("    спавн %s в %.0f px от героя, %.0f px от машин" % [k,
					ph.global_position.distance_to(player.global_position),
					ph.global_position.distance_to(World.cell_to_world(Vector2i(bx + 10, row)))])
	Threat.phantom_spawned.connect(on_spawn)
	if OS.get_cmdline_user_args().has("--balance-debug"):
		var ds: Array = []
		for v in World.vents:
			ds.append(int(World.cell_to_world(v).distance_to(player.global_position)))
		ds.sort()
		print("    вентиляции от героя, px: %s" % str(ds))
	drive_threat = true
	speed_up(speed)
	await wait_game_until(func() -> bool: return Game.is_night(), 5.0)
	var t0: float = clock
	var night_len: float = (1.0 - Balance.NIGHT_START + Balance.NIGHT_END) * Balance.DAY_LENGTH
	var kills0: int = Game.stats_kills
	var hits: Dictionary = {}          ## фантом -> ударов по машинам (для лога)
	var gens_out: int = 0
	while clock - t0 < night_len + 2.0 and Game.is_night():
		for p in get_tree().get_nodes_in_group("phantom"):
			if is_instance_valid(p):
				hits[p.get_instance_id()] = int(p.get("machine_hits"))
		await get_tree().process_frame
	var min_hp: float = INF
	for m in World.machines.values():
		if m is CoalGen and not m.power_active:
			gens_out += 1
		if m is MachineBase and is_instance_valid(m) and absi(m.cell.x - bx) < 20 \
				and absi(m.cell.y - row) < 6:
			min_hp = minf(min_hp, m.hp / m.max_hp)
	if OS.get_cmdline_user_args().has("--balance-debug"):
		for p in get_tree().get_nodes_in_group("phantom"):
			print("    к рассвету: %s в %.0f px от машин, цель-машина %s, состояние %d" % [
					String(p.get("kind")),
					p.global_position.distance_to(World.cell_to_world(Vector2i(bx + 10, row))),
					str(p.get("target_machine") != null), int(p.get("state"))])
	normal_speed()
	drive_threat = false
	release_mouse(MOUSE_BUTTON_LEFT)
	release(KEY_Q)
	Threat.phantom_spawned.disconnect(on_spawn)
	var hit_sum: int = 0
	for k in hits.keys():
		hit_sum += int(hits[k])
	print("  [ночь %d] бюджет %.1f, вышло %s; ударов по машинам %d; машин потеряно %d %s; мин. hp уцелевших %d %%; ТЭЦ погасло %d; убито фантомов %d; смертей героя %d; ночь %.0f с" % [
			day, Threat.budget, str(kinds), hit_sum, _lost.size(), str(_lost),
			int(round(min_hp * 100.0)) if min_hp < INF else 0, gens_out,
			Game.stats_kills - kills0, Game.stats_deaths - deaths0, clock - t0])
	return {"lost": _lost.size(), "kinds": kinds, "spawned": Threat.spawned_total - spawned0,
			"deaths": Game.stats_deaths - deaths0}


# ------------------------------------------------------------------ РЕЦЕПТЫ

## Сырьё — то, что добывается из тайлов (руда, кристалл, уголь, песок, камень, хлам).
static func is_raw(id: int) -> bool:
	return id in [IDs.I.IRON_ORE, IDs.I.COPPER_ORE, IDs.I.CRYSTAL, IDs.I.COAL,
			IDs.I.SAND, IDs.I.STONE, IDs.I.SCRAP, IDs.I.LOG]


## Рецепт предмета: сначала со станции из prefer (по порядку), иначе любой.
## skip — выходы, чей рецепт на этой станции не брать (стена руками не сталь линии).
static func recipe_of(id: int, prefer: Array, skip: Array = []) -> Dictionary:
	for st in prefer:
		for r in DB.recipes_for(String(st)):
			if int(r["out"]) == id and not skip.has(int(r["out"])):
				return r
	if skip.has(id):
		return {}
	return DB.find_recipe_for(id)


## Разложить n предметов id до сырья (или до stop) — в acc: id -> count.
## prefer — порядок станций: ["hand"] — «руками», ["smelter", "assembler"] — «на машинах».
## times (необязательно) — накопить секунды работы станций: станция -> с.
static func expand(id: int, n: int, prefer: Array, acc: Dictionary, stop: Array = [],
		times: Dictionary = {}, skip: Array = []) -> void:
	if n <= 0:
		return
	if is_raw(id) or stop.has(id):
		acc[id] = int(acc.get(id, 0)) + n
		return
	var r: Dictionary = recipe_of(id, prefer, skip)
	if r.is_empty():
		acc[id] = int(acc.get(id, 0)) + n
		return
	var crafts: int = int(ceil(float(n) / float(r["amount"])))
	var st: String = String(r["station"])
	times[st] = float(times.get(st, 0.0)) + float(crafts) * float(r["time"])
	for k in r["in"].keys():
		expand(int(k), crafts * int(r["in"][k]), prefer, acc, stop, times, skip)


## Подпись предметов словаря «id -> count» для лога.
static func items_str(d: Dictionary) -> String:
	var parts: Array = []
	for id in d.keys():
		parts.append("%s %d" % [DB.item_name(int(id)), int(d[id])])
	return ", ".join(parts)


## Сколько предметов id в сундуке.
static func chest_count(ch: Node, id: int) -> int:
	var n: int = 0
	if ch == null or not is_instance_valid(ch):
		return 0
	for s in ch.slots:
		if not s.is_empty() and s.id == id:
			n += s.count
	return n
