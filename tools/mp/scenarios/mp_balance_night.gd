extends "res://tools/mp/scenarios/mp_balance_common.gd"
## mp_balance_night (ADR-002 § 2 «кооп-баланс», § 4.7; MP-K, #96): ночь «по шахтам» на N героев.
##
## Сетевой двойник night_survive_1 (#33): каждый герой — в своей тёмной точке поверхности
## (≥ 30 клеток друг от друга, у каждой — вентиляция в радиусе спавна), ставит три лампы
## своим швом (ПКМ; у клиента — через прокси хоста) и бьёт подошедших (ЛКМ, Q вплотную).
## Ночь ведёт штатный директор угрозы с формулами N (бюджет, cap, интервал, спавн у
## наименее занятого героя). Меряем за NIGHT_SECS: смерти и hp, встречи с фантомами на
## героя (фантом ближе ENC_PX), охотников на героя (фантом выбрал его целью), урон на
## героя, фантомов вышло, трафик хост → клиент и клиент → хост.
##
## «Давление на игрока» = встречи на героя при N / при N = 1 (тот же сид, та же первая
## точка) — считает tools/mp_balance_probe.gd, цель ADR-002 § 2: 0.6–1.0.
##
## Флаги хоста: --mpb-day=<смена> (по умолчанию 1), --mpb-nolamp — без ламп (для сравнения).

const NIGHT_SECS: float = 90.0


# ------------------------------------------------------------------ ХОСТ

func run_host() -> void:
	var day: int = flag_int("day", 1)
	var lamps: bool = not flag("nolamp")
	if not await host_join():
		finish()
		return
	await barrier("in")
	Game.time_of_day = 0.30
	clear_phantoms()
	var spots: Array = spread_spots(heroes_n())
	ok("тёмные точки «по шахтам» для %d героев" % heroes_n(), spots.size() == heroes_n(), str(spots))
	var vented: int = 0
	for c in spots:
		if not Threat.nearest_vents(World.cell_to_world(c), 1).is_empty():
			vented += 1
	print("  точки: %s; с вентиляцией в радиусе спавна %d из %d" % [str(spots), vented, spots.size()])
	var placed_all: bool = spots.size() == heroes_n()
	for k in mini(spots.size(), heroes_n()):
		placed_all = await place_hero(k, stand_pos(spots[k])) and placed_all
	ok("герои расставлены по точкам", placed_all)
	await wait(0.5)
	await barrier("spots")
	if lamps:
		var n: int = await place_lamps(3)
		ok("хост: три лампы через шов (ПКМ)", n == 3, "%d" % n)
	await barrier("lamps", -1, 40.0)
	for h in heroes():
		if h != null:
			(h as Player).hp = Player.MAX_HP
			(h as Player).invuln = 0.0
	var light: Array = []
	for h in heroes():
		light.append("%.2f" % World.light_at(World.world_to_cell((h as Node2D).global_position)) if h != null else "—")
	print("  свет на героях: %s (эхо убегает от > %.2f)" % [", ".join(light), float(Balance.PHANTOMS["echo"]["light_flee"])])

	# --- ночь
	var s0: int = Threat.spawned_total
	await night_begin(day)
	var budget: float = Threat.budget
	var cap: int = Threat.cap_for_n(Threat.night_day, false, Threat.players_online())
	night_track_begin()
	traffic_begin()
	var t0: float = Game.game_time
	var max_alive: int = 0
	while Game.game_time - t0 < NIGHT_SECS and Game.is_night():
		fight_step()
		night_track_step()
		max_alive = maxi(max_alive, Threat.units_alive())
		await get_tree().process_frame
	var secs: float = Game.game_time - t0
	night_end()
	var h2c: float = traffic_bps()
	await barrier("end", -1, 30.0)
	await barrier("shared", -1, 30.0)
	var c2h: Array = []
	for i in clients:
		var v = share_get("c2h_%d" % i)
		if v != null:
			c2h.append(float(v))
	var r: Dictionary = night_track_result()
	var spawned: int = Threat.spawned_total - s0
	for k in heroes_n():
		print("  [герой %d] встреч %d, охотников %d, урон %.0f, смертей %d, мин. hp %.0f, hp в конце %.0f" % [
				k, int(r["enc"][k]), int(r["hunt"][k]), float(r["dmg"][k]), int(r["deaths"][k]),
				float(r["min_hp"][k]), float(r["hp_end"][k])])
	print("  [ночь %d, N = %d%s] бюджет %.1f, cap %d, вышло %d, одновременно до %d, ночь %.0f с; трафик хост → клиент %.0f Б/с, клиент → хост %s Б/с" % [
			day, heroes_n(), "" if lamps else ", без ламп", budget, cap, spawned, max_alive, secs,
			h2c, ", ".join(c2h.map(func(x): return "%.0f" % float(x)))])
	metric("night_hp_min", amin(r["hp_end"]), "мин. hp героя в конце ночи (0 — кто-то погиб)")
	metric("night_deaths", asum(r["deaths"]), "смертей за ночь, все герои")
	metric("night_enc_pp", mean(r["enc"]), "встреч с фантомами на героя")
	metric("night_hunt_pp", mean(r["hunt"]), "фантомов-охотников на героя")
	metric("night_dmg_pp", mean(r["dmg"]), "урона на героя")
	metric("night_spawned", float(spawned), "фантомов вышло")
	metric("night_budget", budget)
	metric("night_max_alive", float(max_alive))
	if clients > 0:
		metric("night_h2c_bps", h2c, "полезная нагрузка хост → клиент, Б/с")
		metric("night_c2h_bps", mean(c2h), "полезная нагрузка клиент → хост, Б/с")
	ok("ночь %d%s, %d героев: никто не погиб за %.0f с" % [day, "" if lamps else " без ламп", heroes_n(), NIGHT_SECS],
			asum(r["deaths"]) == 0.0 and amin(r["hp_end"]) > 0.0, "мин. hp %.0f, смертей %d" % [
			amin(r["hp_end"]), int(asum(r["deaths"]))])
	await barrier("done", -1, 30.0)
	var keys: Array = []
	for i in clients:
		keys.append("c2h_%d" % i)
	share_clear(keys)
	clear_phantoms()
	finish()


# ------------------------------------------------------------------ КЛИЕНТЫ

func client_args(i: int) -> PackedStringArray:
	var a: PackedStringArray = super(i)
	if flag("nolamp"):
		a.append("--mpb-nolamp")
	return a


func run_client(i: int) -> void:
	await barrier("in", -1, 60.0)
	await barrier("spots", -1, 60.0)
	if not flag("nolamp"):
		var n: int = await place_lamps(3)
		ok("c%d: три лампы через шов (ПКМ → прокси хоста)" % i, n == 3, "%d" % n)
	await barrier("lamps", -1, 40.0)
	traffic_begin()
	wait_end_async("end", NIGHT_SECS + 60.0)
	while not _end_flag:
		fight_step()
		await get_tree().process_frame
	stop_fight()
	share_put("c2h_%d" % i, traffic_bps())
	await barrier("shared", -1, 30.0)
	await barrier("done", -1, 30.0)
	finish()
