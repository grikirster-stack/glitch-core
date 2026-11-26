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
##
## Расход топлива (ADR-005 § 6, пересчёт 2026-11-20) — ЕДИНИЦЫ, не секунды:
## сколько единиц сожгли ВСЕ горелки за фазу (день / ночь). Единица сгорела,
## когда топка её взяла в пламя (fuel_units упал) или тень съела запас.
## Текущее пламя (burn_left) в единицы не переводится: недожог < 1 не считается
## целой единицей, а «топливо с» в таблице — прежний замер секунд.
## Добыча руками сюда не входит. Флаг --fuel-cycle печатает день и ночь
## по типам (уголь / медь / кристалл) и не гоняет уровни угрозы.


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
	# до его такта). Состав ведёт drive_threat — тот же Threat.tick, без второго вызова.
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
	if _flag("fuel-cycle"):
		await _fuel_cycle()
		finish()
		return
	if _flag("autopilot-post"):
		rows.append(await _level_post(repeats))
		_print_table(rows)
		finish()
		return
	if _flag("pressure-diag"):
		var only: String = ""
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--pressure-only="):
				only = a.substr(16)
		if only != "seven":
			rows.append(await _level_empty(repeats))
		if only == "" or only == "red":
			rows.append(await _level_mid(Beams.R, repeats, true))
		if only != "red":
			rows.append(await _level_seven(repeats, false))
		_print_table(rows)
		if only != "seven" and only != "red" and not rows.is_empty():
			var empty: Dictionary = rows[0]
			ok("пусто: 0 смертей за ночи 1–3", int(empty["deaths"]) == 0, "%d" % int(empty["deaths"]))
			var quiet: int = 99
			if empty["peaks"].size() >= 2:
				quiet = maxi(int(empty["peaks"][0]), int(empty["peaks"][1]))
			ok("пусто: тихие ночи 1–2 — не больше 1 фантома", quiet <= 1, "по ночам %s" % str(empty["peaks"]))
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
	var row: Dictionary = await _nights("после сигнала", [4, 5, 6], [core_c] if placed else [], repeats, NIGHT_SECS, false)
	# Доказательства прогона, не пересчёт plan_roster. B=13 ломается, если
	# THREAT_DAY_CAP_POST_RELAY откатить к 3: T застывает на 3, B = 1+2·3 = 7.
	var last_b: float = float(row["budgets"][-1]) if row["budgets"].size() > 0 else -1.0
	ok("после сигнала: B ночи 6 = 13", is_equal_approx(last_b, 13.0), "B=%.1f" % last_b)
	ok("после сигнала: ночи 4–6 состоялись", int(row["missed"]) == 0,
			"%d/%d не выпустили" % [int(row["missed"]), int(row["nights"])])
	var night6: Array = row["rosters"][2] if row["rosters"].size() > 2 else []
	ok("после сигнала: ночь 6 — двойник и копатель",
			night6.has("doppel") and night6.has("burrower"), _roster_line(night6))
	print("  состав: %s" % _roster_nights([4, 5, 6], row["rosters"]))
	return row


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
	# Стенд: весь запас в топке, мимо лимита FUEL_MAX. Иначе день+ночь
	# выжигают 12 единиц посреди фазы, и «расход» — артефакт пустой топки.
	# Сундук рядом не годится: снимок запаса его не видит.
	b.fuel = [[item, n]]
	b._ignite()
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
	var budgets: Array = []
	var rosters: Array = []
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
			budgets.append(float(res["budget"]))
			rosters.append(res["roster"])
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
		"budget": budget, "budgets": budgets, "cap": cap, "missed": missed,
		"nights": n_nights, "rosters": rosters, "note": "",
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
	var diag: bool = _flag("pressure-diag")
	var contact_s: Dictionary = {}
	var dist_sum: Dictionary = {}
	var dist_n: Dictionary = {}
	var path_sum: Dictionary = {}
	var state_s: Dictionary = {}
	var min_d: Dictionary = {}
	var spawn_log: Array = []
	var seen_ids: Dictionary = {}
	var gap_s: float = 0.0
	var gaps: Array = []
	var in_press: bool = false
	var bouts: Array = []
	var bout_s: float = 0.0
	# Состав, который директор запланировал на эту ночь. К концу roster пуст
	# (pop_front на каждом спавне) — копия сразу после планирования, до спавна.
	var planned: Array[String] = []
	while clock - t0 < secs and (hold or Game.is_night()):
		var now: float = clock
		var step: float = now - prev
		prev = now
		peak = maxi(peak, _alive())
		if _any_lit(machines):
			lit_s += step
		var pressed: bool = _under_pressure(machines)
		if pressed:
			press_s += step
			if not in_press and gap_s > 0.4:
				gaps.append(gap_s)
			if not in_press and bout_s > 0.4:
				bouts.append(bout_s)
				bout_s = 0.0
			gap_s = 0.0
			in_press = true
			bout_s += step
		else:
			if in_press:
				in_press = false
			gap_s += step
		if hit_s < 0.0 and _hp_dropped(machines, hp0):
			hit_s = now - t0
		if diag:
			_diag_sample(machines, step, contact_s, dist_sum, dist_n, path_sum, state_s, min_d, spawn_log, seen_ids, now - t0)
		await get_tree().process_frame
		# После кадра: _begin_night уже заполнил roster, первый спавн ещё впереди
		# (таймер не меньше 2.5 с). Если к концу ночи roster пуст — эта копия и есть состав.
		if planned.is_empty() and not Threat.roster.is_empty():
			planned = Threat.roster.duplicate()
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
	if diag and in_press and bout_s > 0.4:
		bouts.append(bout_s)
	if diag:
		_print_night_diag(day, planned, spent, contact_s, dist_sum, dist_n, path_sum, state_s, min_d, spawn_log, gaps, bouts)
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
		"roster": planned,
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


func _diag_sample(machines: Array, step: float, contact_s: Dictionary, dist_sum: Dictionary,
		dist_n: Dictionary, path_sum: Dictionary, state_s: Dictionary, min_d: Dictionary,
		spawn_log: Array, seen_ids: Dictionary, t: float) -> void:
	var spots: Array = [player.global_position]
	for c in machines:
		spots.append(World.cell_to_world(c))
	for p in get_tree().get_nodes_in_group("phantom"):
		if not is_instance_valid(p) or not bool(p.get("alive")):
			continue
		var id: int = p.get_instance_id()
		var kind: String = String(p.get("kind"))
		if not seen_ids.has(id):
			seen_ids[id] = true
			var path_n: int = 0
			var path_v = p.get("path")
			if path_v is Array:
				path_n = path_v.size()
			var nearest_v: float = 1.0e9
			for v in World.vents:
				nearest_v = minf(nearest_v, p.global_position.distance_to(World.cell_to_world(v)))
			spawn_log.append("%s t=%.1f path=%d vent_px=%.0f seek=%s" % [
				kind, t, path_n, nearest_v, str(bool(p.get("seek_los")))])
		var best: float = 1.0e9
		for s in spots:
			best = minf(best, p.global_position.distance_to(s))
		dist_sum[kind] = float(dist_sum.get(kind, 0.0)) + best * step
		dist_n[kind] = float(dist_n.get(kind, 0.0)) + step
		if best <= PRESSURE_PX:
			contact_s[kind] = float(contact_s.get(kind, 0.0)) + step
		var st: String = kind + ":" + str(int(p.get("state")))
		state_s[st] = float(state_s.get(st, 0.0)) + step
		var path_v2 = p.get("path")
		var pn: int = path_v2.size() if path_v2 is Array else -1
		path_sum[kind] = float(path_sum.get(kind, 0.0)) + float(pn) * step
		if not min_d.has(kind) or best < float(min_d[kind]):
			min_d[kind] = best


func _print_night_diag(day: int, planned: Array, spent: float, contact_s: Dictionary,
		dist_sum: Dictionary, dist_n: Dictionary, path_sum: Dictionary, state_s: Dictionary,
		min_d: Dictionary, spawn_log: Array, gaps: Array, bouts: Array) -> void:
	print("  ДИАГ ночь %d состав=%s давление-окно %.1f с" % [day, _roster_line(planned), spent])
	for line in spawn_log:
		print("    спавн %s" % line)
	for kind in contact_s.keys():
		var cn: float = maxf(float(dist_n.get(kind, 0.0)), 0.01)
		print("    %s контакт=%.1f с (%.0f %%) средн=%.0f px мин=%.0f path=%.1f" % [
			kind, float(contact_s[kind]), float(contact_s[kind]) / spent * 100.0,
			float(dist_sum.get(kind, 0.0)) / cn, float(min_d.get(kind, -1.0)),
			float(path_sum.get(kind, 0.0)) / cn])
	var parts: PackedStringArray = []
	for st in state_s.keys():
		parts.append("%s=%.1f" % [st, float(state_s[st])])
	print("    состояния %s" % " ".join(parts))
	var gap_sum: float = 0.0
	for g in gaps:
		gap_sum += float(g)
	print("    пауз>0.4с: %d, сумма %.1f с" % [gaps.size(), gap_sum])
	var bout_sum: float = 0.0
	var bout_max: float = 0.0
	for b in bouts:
		bout_sum += float(b)
		bout_max = maxf(bout_max, float(b))
	print("    откатов>0.4с: %d, сумма %.1f с, длиннейший %.1f с" % [bouts.size(), bout_sum, bout_max])
	print("    отзывов волны: %d" % int(Threat.wave_recalls))
	var hf := 0
	var ff := 0
	var fired := 0
	for ph in get_tree().get_nodes_in_group("phantom"):
		hf += int(ph.get("_hold_frames"))
		ff += int(ph.get("_hold_fail"))
		fired += int(ph.get("_breath_n"))
	print("    кадров удержания: %d, путь не найден: %d, передышек: %d" % [hf, ff, fired])


func _print_diag(key: String, row: Dictionary) -> void:
	if not row.has("diag") or row["diag"].is_empty():
		return
	# Диагностика печатается по последней ночи уровня (repeats=1).
	var d: Dictionary = row["diag"]
	var spent: float = maxf(float(d.get("spent", 1.0)), 0.01)
	print("  ДИАГ %s состав=%s" % [key, _roster_line(row["roster"]) if row.has("roster") else "?"])
	for line in d.get("spawns", []):
		print("    спавн %s" % line)
	var contact: Dictionary = d.get("contact", {})
	var dist_sum: Dictionary = d.get("dist_sum", {})
	var dist_n: Dictionary = d.get("dist_n", {})
	var path_sum: Dictionary = d.get("path_sum", {})
	var min_d: Dictionary = d.get("min_d", {})
	for kind in contact.keys():
		var cn: float = maxf(float(dist_n.get(kind, 0.0)), 0.01)
		print("    %s контакт=%.1f с (%.0f %%) средн=%.0f px мин=%.0f path=%.1f" % [
			kind, float(contact[kind]), float(contact[kind]) / spent * 100.0,
			float(dist_sum.get(kind, 0.0)) / cn, float(min_d.get(kind, -1.0)),
			float(path_sum.get(kind, 0.0)) / cn])
	var states: Dictionary = d.get("state", {})
	var parts: PackedStringArray = []
	for st in states.keys():
		parts.append("%s=%.1f" % [st, float(states[st])])
	print("    состояния %s" % " ".join(parts))
	var gaps: Array = d.get("gaps", [])
	var gap_sum: float = 0.0
	for g in gaps:
		gap_sum += float(g)
	print("    пауз>0.4с: %d, сумма %.1f с" % [gaps.size(), gap_sum])


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


## Запас всех горелок мира: целые единицы в топке + 1, если пламя уже взято,
## плюс топливо, которое машина высыпала на землю (разрушение — не сжигание).
## Ключ 0 — «единица в огне» (тип уже сожжён при розжиге, предмет не вернуть).
func _stock_units() -> Dictionary:
	var out: Dictionary = {}
	for c in World.machines.keys():
		var m = World.machines[c]
		if not (m is Burner) or not is_instance_valid(m):
			continue
		var b: Burner = m
		for e in b.fuel:
			var item: int = int(e[0])
			out[item] = int(out.get(item, 0)) + int(e[1])
		if b.burn_left > 0.0 and b.color != 0:
			out[0] = int(out.get(0, 0)) + 1
	var host = get_tree().current_scene
	if host == null:
		return out
	for n in host.get_children():
		if not (n is ItemEntity) or not is_instance_valid(n):
			continue
		var e: ItemEntity = n
		if not Balance.FUEL.has(e.item_id) or e.count <= 0:
			continue
		out[e.item_id] = int(out.get(e.item_id, 0)) + e.count
	return out


## Сколько единиц ушло из запаса с прошлого снимка. Дозаправка сценария
## (_refuel) между фазами в дельту не попадает: снимок берётся после неё.
func _units_burned(before: Dictionary, after: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var keys: Array = before.keys()
	for k in after.keys():
		if not keys.has(k):
			keys.append(k)
	for k in keys:
		var d: int = int(before.get(k, 0)) - int(after.get(k, 0))
		if d > 0:
			out[int(k)] = d
	return out


func _units_total(burned: Dictionary) -> int:
	var n: int = 0
	for k in burned.keys():
		n += int(burned[k])
	return n


func _fuel_name(item: int) -> String:
	if item == IDs.I.COAL:
		return "уголь"
	if item == IDs.I.COPPER_ORE:
		return "медь"
	if item == IDs.I.CRYSTAL:
		return "кристалл"
	if item == 0:
		return "в огне"
	return "предмет %d" % item


## «уголь=2 медь=3 кристалл=1» — только то, что реально сгорело.
func _fuel_line(burned: Dictionary) -> String:
	var parts: PackedStringArray = []
	for item in [IDs.I.COAL, IDs.I.COPPER_ORE, IDs.I.CRYSTAL, 0]:
		if int(burned.get(item, 0)) <= 0:
			continue
		parts.append("%s=%d" % [_fuel_name(item), int(burned[item])])
	if parts.is_empty():
		return "0"
	return " ".join(parts)


## День, затем ночь: горелки горят сами, бот не копает и не дозаправляет.
## Печатает единицы по типам. Это замер цели § 6, не проверка угрозы.
func _fuel_cycle() -> void:
	_wipe_built()
	stand_next_to_beacon()
	_put_lamp()
	# 40 на горелку: день+ночь при укороченном топливе, с двукратным запасом.
	var built: Dictionary = _build_seven(40)
	ok("цикл: семь маяков под лучом", int(built["lit"]) == 7, "маяков %d" % int(built["lit"]))
	ok("цикл: горят 2 горелки", int(built["burners"]) == 2, "%d" % int(built["burners"]))
	var burners: int = 0
	for c in World.machines.keys():
		var m = World.machines[c]
		if m is Burner and is_instance_valid(m) and (m as Burner).burning():
			burners += 1
	print("  цикл топлива: горящих горелок %d, запас %s" % [burners, _fuel_line(_stock_units())])
	Game.day_number = 1
	Game.time_of_day = Balance.START_TIME
	Game.relay_active = false
	drive_threat = false
	var day_burned: Dictionary = await _phase_until(func() -> bool: return Game.is_night(), 200.0, "день")
	_guard_fuel_left("день")
	drive_threat = true
	var night_burned: Dictionary = await _phase_until(func() -> bool: return not Game.is_night(), 140.0, "ночь")
	_guard_fuel_left("ночь")
	drive_threat = false
	normal_speed()
	# 20–30 в ADR — это добыча руками за день, а не сжигание; день печатаем справочно.
	_print_fuel_phase("день", day_burned, 0, 0, "справочно; 20–30 по ADR — добыча руками, не сжигание")
	_print_fuel_phase("ночь", night_burned, 10, 15)


func _phase_until(done: Callable, limit: float, label: String) -> Dictionary:
	speed_up(SPEED)
	var before: Dictionary = _stock_units()
	var t0: float = clock
	var ok_wait: bool = await wait_game_until(done, limit)
	var burned: Dictionary = _units_burned(before, _stock_units())
	print("  фаза %s: %.1f с%s, единиц %d (%s)" % [
			label, clock - t0, "" if ok_wait else " ОБРЫВ", _units_total(burned), _fuel_line(burned)])
	if not ok_wait:
		ok("фаза %s дошла до границы" % label, false, "лимит %.0f с" % limit)
	return burned


## Сторож: горящие горелки не должны выжечь уголь и медь до нуля.
## Иначе «расход» фазы — артефакт пустой топки, а не устойчивое сжигание.
func _guard_fuel_left(phase: String) -> void:
	var coal_left: int = -1
	var copper_left: int = -1
	var burning: int = 0
	for c in World.machines.keys():
		var m = World.machines[c]
		if not (m is Burner) or not is_instance_valid(m) or not (m as Burner).burning():
			continue
		burning += 1
		var b: Burner = m
		var left: Dictionary = _burner_left(b)
		var chest: Dictionary = _chest_beside(b.cell)
		var coal: int = int(left.get(IDs.I.COAL, 0)) + int(chest.get(IDs.I.COAL, 0))
		var copper: int = int(left.get(IDs.I.COPPER_ORE, 0)) + int(chest.get(IDs.I.COPPER_ORE, 0))
		# Горелка жжёт свой цвет. Сторож — по её топливу, не по сумме мира:
		# чужой запас не кормит погасшую топку.
		if b.color == Beams.R:
			coal_left = coal if coal_left < 0 else mini(coal_left, coal)
		elif b.color == Beams.G:
			copper_left = copper if copper_left < 0 else mini(copper_left, copper)
	var enough: bool = burning >= 2 and coal_left > 0 and copper_left > 0
	ok("запас после фазы «%s» не исчерпан" % phase, enough,
			"горелок %d, уголь=%d медь=%d" % [burning, coal_left, copper_left])


## Остаток одной горелки: единицы в топке + та, что сейчас в огне.
func _burner_left(b: Burner) -> Dictionary:
	var out: Dictionary = {}
	for e in b.fuel:
		var item: int = int(e[0])
		out[item] = int(out.get(item, 0)) + int(e[1])
	if b.burn_left > 0.0 and b.color != 0:
		var lit: int = _item_of_color(b.color)
		if lit != 0:
			out[lit] = int(out.get(lit, 0)) + 1
	return out


func _item_of_color(mask: int) -> int:
	if mask == Beams.R:
		return IDs.I.COAL
	if mask == Beams.G:
		return IDs.I.COPPER_ORE
	if mask == Beams.B:
		return IDs.I.CRYSTAL
	return 0


## Топливо в сундуках рядом с горелками — запас, который горелка ещё заберёт.
func _chest_beside(burner_c: Vector2i) -> Dictionary:
	var out: Dictionary = {}
	for d in Burner.NEIGHBORS:
		var m = World.machines.get(burner_c + d)
		if not (m is Chest) or not is_instance_valid(m):
			continue
		for s in (m as Chest).slots:
			if s.is_empty() or not Balance.FUEL.has(s.id):
				continue
			out[s.id] = int(out.get(s.id, 0)) + s.count
	return out


func _print_fuel_phase(phase: String, burned: Dictionary, lo: int, hi: int, note: String = "") -> void:
	var total: int = _units_total(burned)
	var tail: String = note
	if tail == "":
		tail = "цель %d–%d | %s" % [lo, hi, "в цели" if total >= lo and total <= hi else "вне цели"]
	print("  РАСХОД %s: %d единиц (%s) | %s" % [phase, total, _fuel_line(burned), tail])
	metric("fuel_%s_units" % ("day" if phase == "день" else "night"), float(total),
			"единиц сожжено всеми горелками за %s" % phase)
	for item in [IDs.I.COAL, IDs.I.COPPER_ORE, IDs.I.CRYSTAL]:
		var key: String = "coal" if item == IDs.I.COAL else ("copper" if item == IDs.I.COPPER_ORE else "crystal")
		metric("fuel_%s_%s" % [("day" if phase == "день" else "night"), key], float(burned.get(item, 0)))


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
	print("  | уровень | пик | B | cap | потери | топливо с | удар с | uptime | давление | ночей пропущено |")
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
		if r.has("rosters"):
			for i in r["rosters"].size():
				print("  состав/%s[%d]: %s" % [key, i, _roster_line(r["rosters"][i])])
		_print_diag(key, r)


const KIND_RU: Dictionary = {
	"echo": "эхо", "swarm": "рой", "shade": "тень",
	"burrower": "копатель", "doppel": "двойник",
}


## «эхо×3+копатель+двойник» — из захваченного состава, не из plan_roster.
func _roster_line(roster: Array) -> String:
	var counts: Dictionary = {}
	var order: Array[String] = []
	for k in roster:
		var kind: String = String(k)
		if not counts.has(kind):
			order.append(kind)
			counts[kind] = 0
		counts[kind] = int(counts[kind]) + 1
	if order.is_empty():
		return "пусто"
	var parts: PackedStringArray = []
	for kind in order:
		var label: String = String(KIND_RU.get(kind, kind))
		var n: int = int(counts[kind])
		parts.append("%s×%d" % [label, n] if n > 1 else label)
	return "+".join(parts)


## «ночь 4 — …; ночь 5 — …» по первому проходу дней.
func _roster_nights(days: Array, rosters: Array) -> String:
	var parts: PackedStringArray = []
	var n: int = mini(days.size(), rosters.size())
	for i in n:
		parts.append("ночь %d — %s" % [int(days[i]), _roster_line(rosters[i])])
	if parts.is_empty():
		return "ночей нет"
	return "; ".join(parts)


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
