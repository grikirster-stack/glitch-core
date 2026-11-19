extends "res://tools/scenarios/balance_common.gd"
## Ночь на автопилоте (ADR-005 § 6.2, #173, методики после «Света»).
##
## Три уровня базы. Бот стоит у ядра под светокристаллом и не дерётся: меряем,
## что ночь делает сама. Маяк есть (#167): уровни ставят его и кормят лучом,
## а не печатают «маяка ещё нет».
##
## Уровни (бест-практики B1, не заглушка из одних горелок):
##   пусто        — ночи 1–3, один светокристалл;
##   средняя      — 2 горелки + 1 маяк; по цвету (7) и «оставили красный»;
##   семь цветов  — 2 горелки на чистых цветах + 7 маяков;
##   удержание    — та же база, Balance.RELAY_TIME с, Game.relay_active (THREAT_RELAY).
##
## Дефолт — дым для CI (шард сценариев 12 мин): пусто, средняя «оставили красный»,
## семь цветов, удержание, по одному прогону. Флаги не входят в `--scenario=all`:
##   --autopilot-colors     средняя по каждому цвету (7) + «оставили красный»
##   --autopilot-repeats=N  повторов ночи внутри сида (дефолт 1; для решения — 5)
##
## Печатает пик живых, бюджет, cap, потери машин, топливо, секунды до первого
## удара, uptime луча, долю ночи под давлением. «Ночь не состоялась» — отдельно,
## не как зелёный ноль спавнов. S = B/D — справочно, порог прогон не режет.


const NIGHT_SECS: float = 90.0
const SPEED: float = 4.0
## Фантом ближе — ночь «под давлением» (бест-практики A2).
const PRESSURE_PX: float = 7.0 * 16.0
## Цвета маяка по порядку прогона средней базы. Имена — Beams.NAME.
const COLOR_ORDER: Array[int] = [Beams.R, Beams.G, Beams.B, Beams.Y, Beams.C, Beams.M, Beams.W]
## Топливо горелки под чистый цвет. Смеси собирает смеситель из чистых.
const FUEL_OF: Dictionary = {Beams.R: IDs.I.COAL, Beams.G: IDs.I.COPPER_ORE, Beams.B: IDs.I.CRYSTAL}


func _process(delta: float) -> void:
	# Удержание длиннее ночи. При ×4 кадр проскакивает рассвет, и автолоад-
	# директор закрывает смену. Часы для него оставляем дневными (не пиним
	# до его такта), состав ведём своим tick — тот же Threat, те же формулы.
	super(delta)
	if not _pin_night:
		return
	if not _hold_opened:
		var saved: float = Game.time_of_day
		Game.time_of_day = Balance.NIGHT_START + 0.05
		Game.relay_active = true
		Threat._begin_night()
		Game.time_of_day = saved
		_hold_opened = true
	Game.relay_active = true
	Threat.tick(delta)


func run() -> void:
	player.invuln = 1.0e9
	var repeats: int = _flag_int("autopilot-repeats", 1)
	var colors: bool = _flag("autopilot-colors")
	print("  режим: повторов %d, цвета %s (дым CI — без --autopilot-colors)" % [
			repeats, "все 7 + красный" if colors else "только красный"])
	var dawn: float = await _dawn_to_night()
	print("  первая ночь через %.1f с после старта (рассвет %.2f → ночь %.2f)" % [
			dawn, Balance.START_TIME, Balance.NIGHT_START])
	metric("first_night_s", dawn, "секунд от старта до первой ночи")
	ok("первая ночь не раньше 140 с", dawn >= 140.0, "%.1f с" % dawn)

	var rows: Array = []
	if _flag("autopilot-post"):
		rows.append(await _level_post(repeats))
		_print_table(rows)
		finish()
		return
	rows.append(await _level_empty(repeats))
	if colors:
		for mask in COLOR_ORDER:
			rows.append(await _level_mid(int(mask), repeats, false))
		rows.append(await _level_mid(Beams.R, repeats, true))
	else:
		rows.append(await _level_mid(Beams.R, repeats, true))
	rows.append(await _level_seven(repeats, false))
	rows.append(await _level_seven(repeats, true))
	_print_table(rows)
	var empty: Dictionary = rows[0]
	ok("пусто: 0 смертей за ночи 1–3", int(empty["deaths"]) == 0, "%d" % int(empty["deaths"]))
	var quiet: int = 99
	if empty["peaks"].size() >= 2:
		quiet = maxi(int(empty["peaks"][0]), int(empty["peaks"][1]))
	ok("пусто: тихие ночи 1–2 — не больше 1 фантома", quiet <= 1, "по ночам %s" % str(empty["peaks"]))
	finish()


func _flag(name: String) -> bool:
	for a in OS.get_cmdline_user_args():
		if a == "--" + name or a.begins_with("--" + name + "="):
			return true
	return false


func _flag_int(name: String, fallback: int) -> int:
	var key: String = "--" + name + "="
	for a in OS.get_cmdline_user_args():
		if a.begins_with(key):
			return maxi(1, int(a.substr(key.length())))
	return fallback


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
## После сигнала, пустая база: ядро стоит, signal_sent, ночи 4–6.
## В CI не входит (--autopilot-post). Меряет, растёт ли B со сменой.
func _level_post(repeats: int) -> Dictionary:
	_wipe_built()
	stand_next_to_beacon()
	_put_lamp()
	var core_c: Vector2i = World.beacon_cell + Vector2i(2, -1)
	World.set_tile(core_c.x, core_c.y, IDs.T.AIR)
	var placed: bool = MachineBase.place_machine("RainbowCore", core_c)
	ok("ядро поставлено", placed)
	Game.signal_sent = true
	return await _nights("после сигнала", [4, 5, 6], [core_c] if placed else [], repeats, NIGHT_SECS, false)


func _level_empty(repeats: int) -> Dictionary:
	_wipe_built()
	stand_next_to_beacon()
	_put_lamp()
	return await _nights("пусто", [1, 2, 3], [], repeats, NIGHT_SECS, false)


## «Средняя»: 2 горелки + 1 маяк под цветом mask. stuck_red — цвет не переключали.
func _level_mid(mask: int, repeats: int, stuck_red: bool) -> Dictionary:
	_wipe_built()
	stand_next_to_beacon()
	_put_lamp()
	var built: Dictionary = _build_mid(mask, 8)
	var title: String = "оставили красный" if stuck_red else "средняя %s" % _color_name(mask)
	ok("%s: маяк под лучом" % title, int(built["lit"]) == 1, "маяков %d" % int(built["lit"]))
	var row: Dictionary = await _nights(title, [3], built["cells"], repeats, NIGHT_SECS, false)
	row["color"] = mask
	return row


## «Семь цветов»: 7 маяков под своими цветами, горят ровно 2 горелки
## (уголь и медь) — бест-практики B1, T считает пару. Синий и смеси держит
## накопитель с запасом луча: он отдаёт цвет и не жжёт топливо, в T входит
## как накопитель (0,25), не как третья топка.
## hold — удержание сигнала RELAY_TIME с, T += THREAT_RELAY.
func _level_seven(repeats: int, hold: bool) -> Dictionary:
	_wipe_built()
	stand_next_to_beacon()
	_put_lamp()
	var built: Dictionary = _build_seven(8)
	var title: String = "удержание" if hold else "семь цветов"
	ok("%s: семь маяков под лучом" % title, int(built["lit"]) == 7, "маяков %d" % int(built["lit"]))
	ok("%s: горят 2 горелки" % title, int(built["burners"]) == 2, "%d" % int(built["burners"]))
	var day: int = 3 if hold else 6
	var secs: float = Balance.RELAY_TIME if hold else NIGHT_SECS
	return await _nights(title, [day], built["cells"], repeats, secs, hold)


func _put_lamp() -> void:
	var lamp: Vector2i = World.world_to_cell(player.global_position) + Vector2i(0, -2)
	if World.get_tile_v(lamp) == IDs.T.AIR:
		World.set_tile(lamp.x, lamp.y, IDs.T.LIGHT_CRYSTAL)


## Средняя база: ровно 2 горящие горелки и 1 маяк. Смесь берёт обе горелки.
## Чистый цвет — вторая горелка того же топлива, луч в стенку (маяк один).
func _build_mid(mask: int, units: int) -> Dictionary:
	var origin: Vector2i = _clear_pad(World.beacon_cell + Vector2i(6, -3), 16, 6)
	var arm: Dictionary = _arm_color(origin, mask, units, true)
	return {"cells": arm["cells"], "lit": 1 if bool(arm["lit"]) else 0}


## Семь маяков. Красный и зелёный — от двух горящих горелок. Остальные пять
## цветов — накопитель с запасом (Accumulator отдаёт, пока stored > 0).
func _build_seven(units: int) -> Dictionary:
	var cells: Array = []
	var lit: int = 0
	var origin: Vector2i = _clear_pad(World.beacon_cell + Vector2i(4, -12), 14, 24)
	lit += _burner_pharos(origin, Beams.R, units, cells)
	lit += _burner_pharos(origin + Vector2i(0, 3), Beams.G, units, cells)
	var y: int = origin.y + 6
	for mask in [Beams.B, Beams.Y, Beams.C, Beams.M, Beams.W]:
		lit += _accum_pharos(Vector2i(origin.x, y), int(mask), cells)
		y += 3
	return {"cells": cells, "lit": lit, "burners": _burning(cells)}


## Горелка вправо, маяк через две клетки воздуха. 1 — цвет дошёл.
func _burner_pharos(burner_c: Vector2i, mask: int, units: int, cells: Array) -> int:
	if not _place_burner(burner_c, int(FUEL_OF[mask]), units, 0):
		return 0
	cells.append(burner_c)
	var pharos_c: Vector2i = burner_c + Vector2i(3, 0)
	World.set_tile(pharos_c.x - 1, pharos_c.y, IDs.T.AIR)
	if not MachineBase.place_machine("Pharos", pharos_c):
		return 0
	cells.append(pharos_c)
	_flush_beams()
	var ph: Pharos = World.machines[pharos_c] as Pharos
	return 1 if ph != null and ph.active and int(ph.color) == mask else 0


## Накопитель с запасом цвета отдаёт луч вправо, в маяк. Горелки нет.
func _accum_pharos(acc_c: Vector2i, mask: int, cells: Array) -> int:
	if acc_c.x < 1 or acc_c.y < 1 or acc_c.x >= World.W - 5 or acc_c.y >= World.H - 2:
		return 0
	World.set_tile(acc_c.x, acc_c.y, IDs.T.AIR)
	if not MachineBase.place_machine("Accumulator", acc_c):
		return 0
	var acc: Accumulator = World.machines[acc_c] as Accumulator
	acc.dir = 0
	acc.mode = Accumulator.MODE_EMIT
	acc.stored = Balance.ACCUMULATOR_CAP
	acc.color = mask
	cells.append(acc_c)
	var pharos_c: Vector2i = acc_c + Vector2i(3, 0)
	World.set_tile(pharos_c.x - 1, pharos_c.y, IDs.T.AIR)
	if not MachineBase.place_machine("Pharos", pharos_c):
		return 0
	cells.append(pharos_c)
	_flush_beams()
	var ph: Pharos = World.machines[pharos_c] as Pharos
	return 1 if ph != null and ph.active and int(ph.color) == mask else 0


func _burning(cells: Array) -> int:
	var n: int = 0
	for c in cells:
		var m = World.machines.get(c)
		if m is Burner and is_instance_valid(m) and m.burning():
			n += 1
	return n


## Одна оптическая рука. force_two — чистый цвет всё равно получает вторую горелку.
func _arm_color(slot: Vector2i, mask: int, units: int, force_two: bool) -> Dictionary:
	var cells: Array = []
	var pharos_c: Vector2i = slot + Vector2i(8, 0)
	if _needs_mix(mask):
		var fuels: Array = _mix_fuels(mask)
		var mix_c: Vector2i = slot + Vector2i(3, 0)
		if not _place_burner(slot, int(fuels[0]), units, 0):
			return {"cells": cells, "lit": false}
		# Вторая (и третья для белого) горелка смотрит вверх, в нижнюю грань смесителя.
		if not _place_burner(mix_c + Vector2i(0, 1), int(fuels[1]), units, 3):
			return {"cells": cells, "lit": false}
		cells.append(slot)
		cells.append(mix_c + Vector2i(0, 1))
		if fuels.size() > 2:
			if not _place_burner(mix_c + Vector2i(0, -1), int(fuels[2]), units, 1):
				return {"cells": cells, "lit": false}
			cells.append(mix_c + Vector2i(0, -1))
		if not MachineBase.place_machine("Mixer", mix_c):
			return {"cells": cells, "lit": false}
		(World.machines[mix_c] as Mixer).dir = 0
		cells.append(mix_c)
		pharos_c = mix_c + Vector2i(3, 0)
	else:
		if not _place_burner(slot, int(FUEL_OF[mask]), units, 0):
			return {"cells": cells, "lit": false}
		cells.append(slot)
		if force_two:
			var extra: Vector2i = slot + Vector2i(0, 2)
			if _place_burner(extra, int(FUEL_OF[mask]), units, 2):
				cells.append(extra)
	for c in [pharos_c + Vector2i(-1, 0), pharos_c]:
		if not World.machines.has(c):
			World.set_tile(c.x, c.y, IDs.T.AIR)
	if not MachineBase.place_machine("Pharos", pharos_c):
		return {"cells": cells, "lit": false}
	cells.append(pharos_c)
	_flush_beams()
	if _needs_mix(mask):
		_flush_beams()
	var ph: Pharos = World.machines[pharos_c] as Pharos
	return {"cells": cells, "lit": ph != null and ph.active and int(ph.color) == mask}


func _needs_mix(mask: int) -> bool:
	return mask == Beams.Y or mask == Beams.C or mask == Beams.M or mask == Beams.W


func _mix_fuels(mask: int) -> Array:
	match mask:
		Beams.Y:
			return [IDs.I.COAL, IDs.I.COPPER_ORE]
		Beams.C:
			return [IDs.I.COPPER_ORE, IDs.I.CRYSTAL]
		Beams.M:
			return [IDs.I.COAL, IDs.I.CRYSTAL]
		_:
			return [IDs.I.COAL, IDs.I.COPPER_ORE, IDs.I.CRYSTAL]


func _place_burner(c: Vector2i, item: int, n: int, dir: int) -> bool:
	if c.x < 1 or c.y < 1 or c.x >= World.W - 1 or c.y >= World.H - 1:
		return false
	if World.machines.has(c):
		return false
	World.set_tile(c.x, c.y, IDs.T.AIR)
	if not MachineBase.place_machine("Burner", c):
		return false
	var b: Burner = World.machines[c] as Burner
	b.dir = dir
	b.add_fuel(item, n)
	return b.burning()


func _clear_pad(origin: Vector2i, w: int, h: int) -> Vector2i:
	var x0: int = clampi(origin.x, 2, World.W - w - 2)
	var y0: int = clampi(origin.y, 2, World.H - h - 2)
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			var c: Vector2i = Vector2i(x, y)
			if World.machines.has(c):
				var m = World.machines[c]
				World.machines.erase(c)
				if is_instance_valid(m):
					m.queue_free()
			World.set_tile(x, y, IDs.T.AIR)
	return Vector2i(x0, y0)


func _flush_beams() -> void:
	if World.beams == null:
		return
	World.beams.note_machines()
	World.beams.rebuild()


func _color_name(mask: int) -> String:
	if mask >= 0 and mask < Beams.NAME.size():
		return Beams.NAME[mask]
	return str(mask)


## Ночи days, repeats раз. machines — клетки построек (урон, топливо, луч).
func _nights(name: String, days: Array, machines: Array, repeats: int, secs: float,
		hold: bool) -> Dictionary:
	var spawned: int = 0
	var kills: int = 0
	var deaths: int = 0
	var fuel: float = 0.0
	var peak: int = 0
	var peaks: Array = []
	var min_hp: float = 1.0
	var lost: int = 0
	var hit_s: float = -1.0
	var uptime: float = 0.0
	var pressure: float = 0.0
	var budget: float = 0.0
	var cap: int = 0
	var missed: int = 0
	var n_nights: int = 0
	for _r in repeats:
		for day in days:
			var res: Dictionary = await _one_night(int(day), machines, secs, hold)
			n_nights += 1
			spawned += int(res["spawned"])
			kills += int(res["kills"])
			deaths += int(res["deaths"])
			lost += int(res["lost"])
			fuel += float(res["fuel"])
			peak = maxi(peak, int(res["peak"]))
			peaks.append(int(res["peak"]))
			min_hp = minf(min_hp, float(res["min_hp"]))
			uptime += float(res["uptime"])
			pressure += float(res["pressure"])
			budget = float(res["budget"])
			cap = int(res["cap"])
			if float(res["hit_s"]) >= 0.0 and (hit_s < 0.0 or float(res["hit_s"]) < hit_s):
				hit_s = float(res["hit_s"])
			if int(res["spawned"]) == 0 and not _quiet_day(int(day), hold):
				missed += 1
	var div: float = float(maxi(1, n_nights))
	return {
		"name": name, "spawned": spawned, "kills": kills, "deaths": deaths,
		"dmg": 1.0 - min_hp, "fuel": fuel / div, "peak": peak, "peaks": peaks,
		"lost": lost, "hit_s": hit_s, "uptime": uptime / div, "pressure": pressure / div,
		"budget": budget, "cap": cap, "missed": missed, "nights": n_nights, "note": "",
	}


func _quiet_day(day: int, hold: bool) -> bool:
	return day <= Balance.QUIET_NIGHTS and not hold


## Одна ночь. hold — удержание сигнала: T получает THREAT_RELAY, окно Balance.RELAY_TIME.
func _one_night(day: int, machines: Array, secs: float, hold: bool) -> Dictionary:
	clear_phantoms()
	Threat.reset()
	_refuel(machines)
	seed_threat(day + _repeat_salt())
	Game.day_number = day
	# Реле до первого tick. Часы на удержании не идут: при ×4 кадр длиннее
	# ночи, advance_clock перескакивает рассвет и директор закрывает смену.
	Game.relay_active = hold
	# Не из ночи: _begin_night ловит фронт «стало ночью». Пин после такта
	# не даёт часам уйти в день, пока меряем окно удержания.
	Game.time_of_day = 0.50 if hold else Balance.NIGHT_START - 1.0 / Balance.DAY_LENGTH
	_pin_night = false
	player.hp = Player.MAX_HP
	player.invuln = 1.0e9
	var deaths0: int = Game.stats_deaths
	var kills0: int = Game.stats_kills
	var spawned0: int = Threat.spawned_total
	var fuel0: float = _fuel_seconds(machines)
	var hp0: Dictionary = _hp_of(machines)
	drive_threat = true
	speed_up(SPEED)
	if hold:
		_pin_night = true
	else:
		await wait_game_until(func() -> bool: return Game.is_night(), 8.0)
	var t0: float = clock
	var peak: int = 0
	var lit_s: float = 0.0
	var press_s: float = 0.0
	var hit_s: float = -1.0
	var prev: float = clock
	while clock - t0 < secs and (hold or Game.is_night()):
		var now: float = clock
		var step: float = now - prev
		prev = now
		peak = maxi(peak, _alive())
		if _any_lit(machines):
			lit_s += step
		if _under_pressure(machines):
			press_s += step
		if hit_s < 0.0 and _hp_dropped(machines, hp0):
			hit_s = now - t0
		await get_tree().process_frame
	normal_speed()
	drive_threat = false
	_pin_night = false
	_hold_opened = false
	Game.relay_active = false
	var spent: float = maxf(clock - t0, 0.01)
	var min_hp: float = 1.0
	var lost: int = 0
	for c in machines:
		var m = World.machines.get(c)
		if m == null or not is_instance_valid(m):
			lost += 1
			min_hp = 0.0
		elif m is MachineBase:
			min_hp = minf(min_hp, m.hp / m.max_hp)
			if m.hp <= 0.0:
				lost += 1
	return {
		"spawned": Threat.spawned_total - spawned0,
		"kills": Game.stats_kills - kills0,
		"deaths": Game.stats_deaths - deaths0,
		"peak": peak,
		"min_hp": min_hp,
		"lost": lost,
		"fuel": maxf(0.0, fuel0 - _fuel_seconds(machines)),
		"uptime": lit_s / spent,
		"pressure": press_s / spent,
		"hit_s": hit_s,
		"budget": Threat.budget,
		"cap": Threat.cap_for(day, hold, Threat.threat_level()),
	}


var _salt: int = 0
var _pin_night: bool = false
var _hold_opened: bool = false


func _repeat_salt() -> int:
	_salt += 17
	return _salt


func _refuel(machines: Array) -> void:
	for c in machines:
		var m = World.machines.get(c)
		if m is Burner and is_instance_valid(m) and m.fuel_units() < 4:
			var item: int = IDs.I.COAL
			if int(m.color) == Beams.G:
				item = IDs.I.COPPER_ORE
			elif int(m.color) == Beams.B:
				item = IDs.I.CRYSTAL
			m.add_fuel(item, 6)


func _any_lit(machines: Array) -> bool:
	for c in machines:
		var m = World.machines.get(c)
		if m is Pharos and is_instance_valid(m) and bool(m.get("active")):
			return true
	return false


func _under_pressure(machines: Array) -> bool:
	var spots: Array = [player.global_position]
	for c in machines:
		spots.append(World.cell_to_world(c))
	for p in get_tree().get_nodes_in_group("phantom"):
		if not is_instance_valid(p) or not bool(p.get("alive")):
			continue
		for s in spots:
			if p.global_position.distance_to(s) <= PRESSURE_PX:
				return true
	return false


func _hp_of(machines: Array) -> Dictionary:
	var out: Dictionary = {}
	for c in machines:
		var m = World.machines.get(c)
		if m is MachineBase and is_instance_valid(m):
			out[c] = m.hp
	return out


func _hp_dropped(machines: Array, hp0: Dictionary) -> bool:
	for c in hp0.keys():
		var m = World.machines.get(c)
		if m == null or not is_instance_valid(m):
			return true
		if m is MachineBase and m.hp < float(hp0[c]) - 0.5:
			return true
	return false


func _fuel_seconds(machines: Array) -> float:
	var n: float = 0.0
	for c in machines:
		var m = World.machines.get(c)
		if m is Burner and is_instance_valid(m):
			n += m.burn_left
			for e in m.fuel:
				var item: int = int(e[0])
				n += float(e[1]) * float(Balance.FUEL.get(item, Balance.COAL_BURN))
	return n


func _alive() -> int:
	var n: int = 0
	for p in get_tree().get_nodes_in_group("phantom"):
		if is_instance_valid(p) and bool(p.get("alive")):
			n += 1
	return n


## Снять постройки, которые поставил этот сценарий (не стартовый лагерь).
func _wipe_built() -> void:
	clear_phantoms()
	Threat.reset()
	Game.relay_active = false
	_salt = 0
	var drop: Array = []
	for c in World.machines.keys():
		var m = World.machines[c]
		if is_instance_valid(m) and String(m.get("kind")) in ["Burner", "Pharos", "Accumulator", "Mixer", "Mirror", "Prism"]:
			drop.append(c)
	for c in drop:
		var m = World.machines[c]
		World.machines.erase(c)
		if is_instance_valid(m):
			m.queue_free()


func _print_table(rows: Array) -> void:
	print("  ТАБЛИЦА night_autopilot (сид %d)" % int(scene.get("seed_value")))
	print("  | уровень | пик | B | cap | потери | топливо с | удар с | uptime | давление | ночь не состоялась |")
	for r in rows:
		var missed: String = "%d/%d" % [int(r["missed"]), int(r["nights"])]
		var hit: String = "—" if float(r["hit_s"]) < 0.0 else "%.1f" % float(r["hit_s"])
		print("  | %s | %d | %.1f | %d | %d | %.0f | %s | %.0f %% | %.0f %% | %s |" % [
				r["name"], int(r["peak"]), float(r["budget"]), int(r["cap"]), int(r["lost"]),
				float(r["fuel"]), hit, float(r["uptime"]) * 100.0, float(r["pressure"]) * 100.0, missed])
		var key: String = _key(String(r["name"]))
		metric("autopilot_%s_spawned" % key, float(r["spawned"]))
		metric("autopilot_%s_deaths" % key, float(r["deaths"]))
		metric("autopilot_%s_peak" % key, float(r["peak"]))
		metric("autopilot_%s_budget" % key, float(r["budget"]))
		metric("autopilot_%s_cap" % key, float(r["cap"]))
		metric("autopilot_%s_lost" % key, float(r["lost"]))
		metric("autopilot_%s_fuel_s" % key, float(r["fuel"]))
		metric("autopilot_%s_uptime" % key, float(r["uptime"]))
		metric("autopilot_%s_pressure" % key, float(r["pressure"]))
		metric("autopilot_%s_missed" % key, float(r["missed"]))
		if float(r["hit_s"]) >= 0.0:
			metric("autopilot_%s_hit_s" % key, float(r["hit_s"]))
		# S = B/D справочно: D не из чего считать, бот не дерётся и цвет не выбирает.
		if float(r["budget"]) > 0.0:
			print("  [баланс] S/%s=справ  # B=%.1f, D не считали" % [key, float(r["budget"])])


func _key(name: String) -> String:
	if name.begins_with("пусто"):
		return "empty"
	if name.begins_with("семь"):
		return "seven"
	if name.begins_with("удерж"):
		return "hold"
	if name.begins_with("оставили"):
		return "stuck_red"
	return "mid"
