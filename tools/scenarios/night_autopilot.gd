extends "res://tools/scenarios/balance_common.gd"
## Ночь на автопилоте (ADR-005 § 6.2, § 11 шаг 7, #173).
##
## Три уровня базы, по 90 с ночи. Бот стоит у ядра/капсулы под светокристаллом
## и не дерётся: меряем, что ночь делает сама. Маяка (#167) ещё нет — крючок
## pharos_lit() даёт 0, уровни с маяком честно отложены (метрика NA).
##
## Печатает таблицу «уровень → спавнов, убитых, урон, смертей, топлива»
## и секунды до первой ночи со старта на рассвете.

const NIGHT_SECS: float = 90.0
const SPEED: float = 4.0
## Урон по блокам «меньше 50 % HP»: мин. доля HP уцелевших построек уровня.
const HOLD_HP: float = 0.5


func run() -> void:
	player.invuln = 1.0e9
	var dawn: float = await _dawn_to_night()
	print("  первая ночь через %.1f с после старта (рассвет %.2f → ночь %.2f)" % [
			dawn, Balance.START_TIME, Balance.NIGHT_START])
	metric("first_night_s", dawn, "секунд от старта до первой ночи")
	ok("первая ночь не раньше 140 с", dawn >= 140.0, "%.1f с" % dawn)

	var rows: Array = []
	rows.append(await _level_empty())
	rows.append(await _level_burner_pharos())
	rows.append(await _level_seven())
	_print_table(rows)
	finish()


## От старта на рассвете до первой ночи, игровые секунды. Директор молчит.
func _dawn_to_night() -> float:
	Threat.reset()
	Game.day_number = 1
	Game.time_of_day = Balance.START_TIME
	Game.relay_active = false
	drive_threat = false
	speed_up(SPEED)
	var t0: float = clock
	var ok_wait: bool = await wait_game_until(func() -> bool: return Game.is_night(), 200.0)
	normal_speed()
	if not ok_wait:
		return -1.0
	return clock - t0


## «Пусто»: ничего не построено, один светокристалл у героя. Ночи 1–3.
func _level_empty() -> Dictionary:
	_wipe_built()
	stand_next_to_beacon()
	var lamp: Vector2i = World.world_to_cell(player.global_position) + Vector2i(0, -2)
	if World.get_tile_v(lamp) == IDs.T.AIR:
		World.set_tile(lamp.x, lamp.y, IDs.T.LIGHT_CRYSTAL)
	var row: Dictionary = await _nights("пусто", [1, 2, 3], [])
	ok("пусто: 0 смертей за ночи 1–3", int(row["deaths"]) == 0, "%d" % int(row["deaths"]))
	var quiet: int = maxi(int(row["peaks"][0]), int(row["peaks"][1])) if row["peaks"].size() >= 2 else 99
	ok("пусто: тихие ночи 1–2 — не больше 1 фантома", quiet <= 1,
			"по ночам %s" % str(row["peaks"]))
	return row


## «Горелка + маяк R», ночь 3. Маяка нет — в мире только горелка, вклад маяка 0.
## Ожидание ADR (T = 4.5) заработает, когда появится Pharos; пока печатаем факт.
func _level_burner_pharos() -> Dictionary:
	_wipe_built()
	stand_next_to_beacon()
	var cells: Array = _place_burners(1, 6)
	var lamp: Vector2i = World.world_to_cell(player.global_position) + Vector2i(0, -2)
	if World.get_tile_v(lamp) == IDs.T.AIR:
		World.set_tile(lamp.x, lamp.y, IDs.T.LIGHT_CRYSTAL)
	if not _kind_placed("Pharos"):
		print("  маяка ещё нет (#167): pharos_lit = 0, в уровне только горелка")
	var row: Dictionary = await _nights("горелка+маяк", [3], cells)
	row["note"] = "маяка нет, T от горелки" if not _kind_placed("Pharos") else ""
	ok("горелка+маяк: 0 смертей", int(row["deaths"]) == 0, "%d" % int(row["deaths"]))
	return row


## «Семь цветов»: 3 горелки (маяков и смесителя ещё нет — их вклад 0).
## Ожидание «маяки держат» проверится, когда Pharos появится; пока — факт горелок.
func _level_seven() -> Dictionary:
	_wipe_built()
	stand_next_to_beacon()
	var cells: Array = _place_burners(3, 8)
	if not _kind_placed("Pharos"):
		print("  маяка и смесителя ещё нет: в уровне три горелки, pharos_lit = 0")
	var row: Dictionary = await _nights("семь цветов", [6], cells)
	row["note"] = "маяка нет" if not _kind_placed("Pharos") else ""
	var held: bool = float(row["dmg"]) < HOLD_HP
	ok("семь цветов: ни одна горелка не разрушена", held, "урон %.0f %%" % (float(row["dmg"]) * 100.0))
	ok("семь цветов: 0 смертей", int(row["deaths"]) == 0, "%d" % int(row["deaths"]))
	return row


func _kind_placed(kind: String) -> bool:
	for m in World.machines.values():
		if is_instance_valid(m) and String(m.get("kind")) == kind:
			return true
	return false


## n горелок в ряд над полом базы, с углём на ночь. Возвращает их клетки.
func _place_burners(n: int, coal: int) -> Array:
	var bx: int = World.beacon_cell.x
	var row: int = World.beacon_cell.y
	var cells: Array = []
	var placed: int = 0
	for dx in range(-6, 12):
		if placed >= n:
			break
		var c: Vector2i = Vector2i(bx + dx, row - 1)
		if World.get_tile_v(c) != IDs.T.AIR or World.machines.has(c):
			continue
		if not MachineBase.place_machine("Burner", c):
			continue
		(World.machines[c] as Burner).add_fuel(IDs.I.COAL, coal)
		cells.append(c)
		placed += 1
	ok("поставлено горелок: %d" % n, placed == n, "%d" % placed)
	return cells


## Ночи days подряд. machines — клетки построек уровня (урон и топливо по ним).
func _nights(name: String, days: Array, machines: Array) -> Dictionary:
	var spawned: int = 0
	var kills: int = 0
	var deaths: int = 0
	var fuel: int = 0
	var peak: int = 0
	var peaks: Array = []
	var min_hp: float = 1.0
	for day in days:
		var fuel0: int = _fuel_of(machines)
		var res: Dictionary = await _one_night(int(day), machines)
		spawned += int(res["spawned"])
		kills += int(res["kills"])
		deaths += int(res["deaths"])
		peak = maxi(peak, int(res["peak"]))
		peaks.append(int(res["peak"]))
		min_hp = minf(min_hp, float(res["min_hp"]))
		fuel += fuel0 - _fuel_of(machines)

	var dmg: float = 1.0 - min_hp
	return {"name": name, "spawned": spawned, "kills": kills, "dmg": dmg,
			"deaths": deaths, "fuel": fuel, "peak": peak, "peaks": peaks, "note": ""}


## Одна ночь: от её начала NIGHT_SECS, бот стоит. Директор штатный.
func _one_night(day: int, machines: Array) -> Dictionary:
	clear_phantoms()
	Threat.reset()
	seed_threat(day)
	Game.day_number = day
	Game.relay_active = false
	Game.time_of_day = Balance.NIGHT_START - 1.0 / Balance.DAY_LENGTH
	player.hp = Player.MAX_HP
	player.invuln = 1.0e9
	var deaths0: int = Game.stats_deaths
	var kills0: int = Game.stats_kills
	var spawned0: int = Threat.spawned_total
	drive_threat = true
	speed_up(SPEED)
	await wait_game_until(func() -> bool: return Game.is_night(), 5.0)
	var t0: float = clock
	var peak: int = 0
	while clock - t0 < NIGHT_SECS and Game.is_night():
		peak = maxi(peak, _alive())
		await get_tree().process_frame
	normal_speed()
	drive_threat = false
	var min_hp: float = 1.0
	for c in machines:
		var m = World.machines.get(c)
		if m is MachineBase and is_instance_valid(m):
			min_hp = minf(min_hp, m.hp / m.max_hp)
	return {
		"spawned": Threat.spawned_total - spawned0,
		"kills": Game.stats_kills - kills0,
		"deaths": Game.stats_deaths - deaths0,
		"peak": peak,
		"min_hp": min_hp,
	}


func _alive() -> int:
	var n: int = 0
	for p in get_tree().get_nodes_in_group("phantom"):
		if is_instance_valid(p) and bool(p.get("alive")):
			n += 1
	return n


func _fuel_of(machines: Array) -> int:
	var n: int = 0
	for c in machines:
		var m = World.machines.get(c)
		if m is Burner and is_instance_valid(m):
			n += m.fuel_units() + (1 if m.burning() else 0)
	return n


## Снять постройки, которые поставил этот сценарий (не стартовый лагерь).
func _wipe_built() -> void:
	clear_phantoms()
	Threat.reset()
	var drop: Array = []
	for c in World.machines.keys():
		var m = World.machines[c]
		if is_instance_valid(m) and String(m.get("kind")) in ["Burner", "Pharos", "Accumulator", "Mixer"]:
			drop.append(c)
	for c in drop:
		var m = World.machines[c]
		World.machines.erase(c)
		if is_instance_valid(m):
			m.queue_free()


func _print_table(rows: Array) -> void:
	print("  ТАБЛИЦА night_autopilot (сид %d)" % int(scene.get("seed_value")))
	print("  | уровень | спавнов | убитых | урон | смертей | топлива |")
	for r in rows:
		var note: String = ("  # " + String(r["note"])) if String(r["note"]) != "" else ""
		print("  | %s | %d | %d | %.0f %% | %d | %d |%s" % [r["name"], int(r["spawned"]),
				int(r["kills"]), float(r["dmg"]) * 100.0, int(r["deaths"]), int(r["fuel"]), note])
		metric("autopilot_%s_spawned" % _key(String(r["name"])), float(r["spawned"]))
		metric("autopilot_%s_deaths" % _key(String(r["name"])), float(r["deaths"]))


func _key(name: String) -> String:
	if name.begins_with("пусто"):
		return "empty"
	if name.begins_with("семь"):
		return "seven"
	return "burner"
