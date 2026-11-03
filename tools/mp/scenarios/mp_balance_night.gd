extends "res://tools/mp/scenarios/mp_balance_common.gd"
## mp_balance_night (ADR-002 § 2 «кооп-баланс», § 4.7; MP-K, #96): ночь «по шахтам» на N героев.
##
## Сетевой двойник night_survive_1 (#33): каждый герой — в своей тёмной точке (≥ 30 клеток
## друг от друга, у каждой — своя вентиляция в радиусе спавна), ставит три лампы
## своим швом (ПКМ; у клиента — через прокси хоста), копает (шум) и бьёт подошедших (ЛКМ,
## Q вплотную).
## Ночь ведёт штатный директор угрозы с формулами N (бюджет, cap, интервал, спавн у
## наименее занятого героя). Меряем за NIGHT_SECS: смерти и hp, встречи с фантомами на
## героя (фантом ближе ENC_PX), охотников на героя (фантом выбрал его целью), урон на
## героя, фантомов вышло, трафик хост → клиент и клиент → хост.
##
## «Давление на игрока» = встречи на героя при N / при N = 1 (тот же сид, та же первая
## точка) — считает tools/mp_balance_probe.gd, цель ADR-002 § 2: 0.6–1.0.
##
## Точки — в пещерах «по шахтам»: каждая в CAVE_MIN..CAVE_MAX шагах по воздуху от своей
## вентиляции (фантом до героя дойдёт). У #33 тёмная точка поверхности оказалась вне
## досягаемости: ночь 1 даже без ламп не давала ни одной встречи — давление не измерить.
##
## Флаги хоста: --mpb-day=<смена> (по умолчанию 1), --mpb-nolamp — без ламп, --mpb-surface —
## тёмные точки поверхности, как night_survive_1; --mpb-invuln — герои бессмертны (замер
## давления: смерть и респаун на базе меняли бы, где герой и кто цель); --mpb-debug — лог.

const NIGHT_SECS: float = 90.0
var _sidx: Array = []            ## номер точки героя k
const CAVE_MIN: int = 12
const CAVE_MAX: int = 22
const CAVE_GAP: int = 30         ## клеток между героями
const BASE_GAP: int = 40         ## клеток по x от релея: свет базы не в счёт


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
	# Точек всегда MAX: при любом N герой k стоит в точке k; --mpb-spot=j — одиночка в точке j
	# (база «давления»: тот же герой в той же точке один и с товарищами).
	var all_spots: Array = spread_spots(Balance.MP_MAX_PLAYERS) if flag("surface") else cave_spots(Balance.MP_MAX_PLAYERS)
	_sidx.clear()
	for k in heroes_n():
		_sidx.append(flag_int("spot", 0) if heroes_n() == 1 else k)
	var spots: Array = []
	for j in _sidx:
		if int(j) < all_spots.size():
			spots.append(all_spots[int(j)])
	ok("точки «по шахтам» для %d героев (%s)" % [heroes_n(), "поверхность" if flag("surface") else "пещеры у вентиляций"],
			spots.size() == heroes_n(), "%s, точки № %s" % [str(spots), str(_sidx)])
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
			(h as Player).invuln = 1.0e9 if flag("invuln") else 0.0
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
		work_step()
		night_track_step()
		max_alive = maxi(max_alive, Threat.units_alive())
		if flag("debug") and int(Game.game_time - t0) / 10 != _dbg_t:
			_dbg_t = int(Game.game_time - t0) / 10
			var parts: Array = []
			for p in alive_phantoms():
				var ph: Phantom = p
				var tgt: Node2D = ph.player as Node2D
				parts.append("%s ст%d %.0fpx" % [ph.kind, int(ph.state),
						ph.global_position.distance_to(tgt.global_position) if tgt != null else -1.0])
			print("    t=%.0f: %s; шум героя %.0f" % [Game.game_time - t0, ", ".join(parts), player.noise])
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
		print("  [герой %d, точка %d] встреч %d, охотились %d (дольше всего — %d), урон %.0f, смертей %d, мин. hp %.0f, hp в конце %.0f" % [
				k, int(_sidx[k]), int(r["enc"][k]), int(r["hunt"][k]), int(r["own"][k]), float(r["dmg"][k]),
				int(r["deaths"][k]), float(r["min_hp"][k]), float(r["hp_end"][k])])
		metric("night_enc_h%d" % int(_sidx[k]), float(r["enc"][k]))
		metric("night_own_h%d" % int(_sidx[k]), float(r["own"][k]))
	print("  [ночь %d, N = %d%s] бюджет %.1f, cap %d, вышло %d, одновременно до %d, ночь %.0f с; трафик хост → клиент %.0f Б/с, клиент → хост %s Б/с" % [
			day, heroes_n(), "" if lamps else ", без ламп", budget, cap, spawned, max_alive, secs,
			h2c, ", ".join(c2h.map(func(x): return "%.0f" % float(x)))])
	metric("night_hp_min", amin(r["hp_end"]), "мин. hp героя в конце ночи (0 — кто-то погиб)")
	metric("night_deaths", asum(r["deaths"]), "смертей за ночь, все герои")
	metric("night_enc_pp", mean(r["enc"]), "встреч с фантомами на героя")
	metric("night_hunt_pp", mean(r["hunt"]), "фантомов, хоть раз выбравших героя целью, на героя")
	metric("night_own_pp", mean(r["own"]), "фантомов на героя (каждый — за кем охотился дольше)")
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


## Точки в пещерах для k героев: вентиляции по удалённости от релея (не ближе BASE_GAP
## по x), от каждой — обход по воздуху; точка «стоя» в CAVE_MIN..CAVE_MAX шагах и не ближе
## VENT_SPAWN_MIN_PX по прямой (иначе вентиляция у героя не «выдыхает»); ближе всех к
## середине диапазона. Друг от друга ≥ CAVE_GAP клеток. Порядок — от сида мира.
func cave_spots(k: int) -> Array:
	var bx: int = World.beacon_cell.x
	var vs: Array = []
	for v in World.vents:
		if not World.is_vent_sealed(v) and absi(v.x - bx) >= BASE_GAP:
			vs.append(v)
	vs.sort_custom(func(a, b): return absi(a.x - bx) < absi(b.x - bx) or (absi(a.x - bx) == absi(b.x - bx) and a.y < b.y))
	var out: Array = []
	for v in vs:
		if out.size() >= k:
			break
		var far: bool = true
		for o in out:
			if (o as Vector2i).distance_to(v) < float(CAVE_GAP):
				far = false
		if not far:
			continue
		var c: Vector2i = _cave_stand_from(v)
		if c.x >= 0:
			out.append(c)
	return out


func _cave_stand_from(v: Vector2i) -> Vector2i:
	var dist: Dictionary = {v: 0}
	var q: Array = [v]
	var best: Vector2i = Vector2i(-1, -1)
	var best_score: int = 1 << 30
	var mid: int = (CAVE_MIN + CAVE_MAX) / 2
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		var d: int = int(dist[c])
		if d >= CAVE_MIN and World.get_tile_v(c + Vector2i(0, -1)) == IDs.T.AIR 				and World.is_solid_cell(c + Vector2i(0, 1)) 				and World.cell_to_world(c).distance_to(World.cell_to_world(v)) >= Balance.VENT_SPAWN_MIN_PX + 8.0 				and not World.rect_solid(Rect2(stand_pos(c) - Player.SIZE * 0.5, Player.SIZE)):
			var score: int = absi(d - mid)
			if score < best_score:
				best_score = score
				best = c
		if d >= CAVE_MAX:
			continue
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + o
			if dist.has(n) or n.x < 1 or n.y < 1 or n.x >= World.W - 1 or n.y >= World.H - 1:
				continue
			if World.get_tile_v(n) != IDs.T.AIR:
				continue
			dist[n] = d + 1
			q.append(n)
	return best


## Герой работает, как человек ночью в шахте: копает ближний тайл (шум копки 46 — эхо
## слышит его за 260 px), фантом подошёл на удар — бьёт его (fight_step). Стоящий молча
## герой эху не виден дальше 170 px — ночь «по шахтам» без работы ничего не мерит.
func work_step() -> void:
	var near: bool = false
	for p in get_tree().get_nodes_in_group("phantom"):
		if is_instance_valid(p) and bool(p.get("alive")) and (p as Node2D).visible 				and (p as Node2D).global_position.distance_to(player.global_position) < 44.0:
			near = true
			break
	if near or player.dead:
		_dig = Vector2i(-1, -1)
		fight_step()
		return
	if _dig.x < 0 or World.get_tile_v(_dig) == IDs.T.AIR:
		_dig = _dig_cell()
	if _dig.x < 0:
		release_mouse(MOUSE_BUTTON_LEFT)
		return
	aim(World.cell_to_world(_dig))
	press_mouse(MOUSE_BUTTON_LEFT)


var _dig: Vector2i = Vector2i(-1, -1)


## Ближний копаемый тайл в досягаемости: сначала в рядах тела (стена сбоку), потом под
## ногами; любая порода (в пещерах она твёрже 1.0 — find_mineable её не берёт).
func _dig_cell() -> Vector2i:
	var pc: Vector2i = World.world_to_cell(player.global_position)
	for band in [[0, -1], [1, 2]]:
		var best: Vector2i = Vector2i(-1, -1)
		var best_d: float = INF
		for dy in band:
			for dx in range(-4, 5):
				var c: Vector2i = pc + Vector2i(dx, dy)
				var t: int = World.get_tile_v(c)
				if t == IDs.T.AIR or DB.tile_hard(t) > 100.0 or World.machines.has(c):
					continue
				var d: float = World.cell_to_world(c).distance_to(player.global_position)
				if d <= Player.REACH - 4.0 and d < best_d:
					best_d = d
					best = c
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)
var _dbg_t: int = -1


# ------------------------------------------------------------------ КЛИЕНТЫ

func client_args(i: int) -> PackedStringArray:
	var a: PackedStringArray = super(i)
	if flag("nolamp"):
		a.append("--mpb-nolamp")
	if flag("surface"):
		a.append("--mpb-surface")
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
		work_step()
		await get_tree().process_frame
	stop_fight()
	share_put("c2h_%d" % i, traffic_bps())
	await barrier("shared", -1, 30.0)
	await barrier("done", -1, 30.0)
	finish()
