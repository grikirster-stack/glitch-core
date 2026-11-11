extends "res://tools/mp/scenarios/mp_threat_base.gd"
## mp_threat_scale (ADR-002 § 4.7, D9; MP-F, #92): угроза растёт с числом игроков.
##
## Таблица множителей сети (формулы Threat.*_n, ADR-002 § 4.7): бюджет, cap и
## интервал при N = 1…4. T ночи — по ADR-005 § 6.2, пустая база: ночь 1 тихая
## (T = 1, бюджет 2, cap 1), ночь 4 (T = 3, бюджет 7, cap 4). Релей — cap 10.
## cap не выше MAX_PHANTOMS, интервал не меньше MP_SPAWN_INTERVAL_MIN;
## при N = 1 — ровно формулы одиночной игры.
## Вживую: клиенты входят по одному — N = 1, 2, 3, 4 героев на связи; директор
## начинает ночь — бюджет × (1 + 0.5·(N − 1)), N ночи запомнен, пауза до следующего
## фантома — интервал_N. Вчетвером: спавн — у героя с наименьшим числом
## преследователей (ничья — дальний от базы, спрятавшийся — не в счёт); чёрный ящик в
## инвентаре товарища вскрыт хостом; шлюз открывается товарищу, а не только хосту.

const EPS: float = 0.0001
## N → [B ночь 1 (T=1, тихая), cap ночь 1, интервал ночи 1,
## B ночь 4 (T=3), cap ночь 4, cap релей]. Множители сети прежние.
## Интервал сверяем по формуле, не по округлению до 0.1: 6.5/1.35 = 4.814…,
## snapped(4.81) даёт 4.8 и роняет сравнение.
const TABLE: Dictionary = {
	1: [2.0, 1, 7.0, 4, 10],
	2: [3.0, 3, 10.5, 6, 12],
	3: [4.0, 5, 14.0, 8, 14],
	4: [5.0, 7, 17.5, 10, 16],
}


func _init() -> void:
	auto_launch = false


# ------------------------------------------------------------------ ХОСТ

func run_host() -> void:
	_table()
	for k in 4:
		if k > 0:
			launch([k - 1])
			ok("вошёл клиент %d (N = %d)" % [k - 1, k + 1], await wait_players(k + 1, 45.0))
			ok("прокси клиентов с вводом", await wait_proxies(k, 10.0))
		var n: int = Threat.players_online()
		ok("N = %d героев на связи" % (k + 1), n == k + 1, "players_online %d, Game.players %d" % [
				n, Game.players.size()])
		_night(k + 1)
	invulnerable_all()
	await _spawn_side()
	await _black_box()
	await _airlock()
	await barrier("done", -1, 30.0)
	clear_phantoms()
	finish()


## Формулы против таблицы § 4.7 и пределов.
func _table() -> void:
	var all_ok: bool = true
	var note: Array = []
	for n in TABLE:
		var row: Array = TABLE[n]
		var b1: float = Threat.night_budget_n(1.0, n, 1, false)
		var c1: int = Threat.cap_for_n(1, false, n, 1.0)
		var b4: float = Threat.night_budget_n(3.0, n, 4, false)
		var c4: int = Threat.cap_for_n(4, false, n, 3.0)
		var cr: int = Threat.cap_for_n(1, true, n)
		var denom: float = 1.0 if n <= 1 else 1.0 + Balance.MP_INTERVAL_PER_PLAYER * float(n - 1)
		var floor_i: float = Balance.SPAWN_INTERVAL_MIN if n <= 1 else Balance.MP_SPAWN_INTERVAL_MIN
		var want_i: float = clampf((Balance.SPAWN_INTERVAL_MAX - Balance.SPAWN_INTERVAL_PER_T) / denom,
				floor_i, Balance.SPAWN_INTERVAL_MAX)
		var good: bool = absf(b1 - float(row[0])) < EPS and c1 == int(row[1]) \
				and is_equal_approx(Threat.interval_for_n(1.0, n), want_i) \
				and absf(b4 - float(row[2])) < EPS and c4 == int(row[3]) and cr == int(row[4])
		all_ok = all_ok and good
		note.append("N%d: %.1f/%d/%.2f с, %.1f/%d, релей %d" % [n, b1, c1, want_i, b4, c4, cr])
		print("  | %d | %.1f | %d | %.2f с | %.1f | %d | %d |" % [n, b1, c1, want_i, b4, c4, cr])
	ok("таблица § 4.7: бюджет, cap, интервал при N = 1…4", all_ok, "; ".join(note))
	# N = 1 — ровно одиночные формулы (и вне таблицы: большой T, релей).
	var same: bool = true
	for t in [0.0, 1.0, 3.0, 9.0, 20.0]:
		same = same and Threat.night_budget_n(t, 1, 4, false) == Threat.night_budget(t, 4, false) \
				and Threat.interval_for_n(t, 1) == Threat.interval_for(t)
	for d in [1, 4, 8, 12]:
		same = same and Threat.cap_for_n(d, false, 1) == Threat.cap_for(d, false) \
				and Threat.cap_for_n(d, true, 1) == Threat.cap_for(d, true)
	ok("N = 1: формулы одиночной игры без множителей (интервал не меньше %.1f с)" % Balance.SPAWN_INTERVAL_MIN,
			same and Threat.interval_for_n(20.0, 1) == Balance.SPAWN_INTERVAL_MIN)
	ok("cap не выше MAX_PHANTOMS = %d (релей, 5 игроков; ночь 12, 8 игроков)" % Balance.MAX_PHANTOMS,
			Threat.cap_for_n(1, true, 5) == Balance.MAX_PHANTOMS
			and Threat.cap_for_n(12, false, 8, 3.0) == Balance.MAX_PHANTOMS)
	ok("интервал в сети не меньше MP_SPAWN_INTERVAL_MIN = %.1f с" % Balance.MP_SPAWN_INTERVAL_MIN,
			Threat.interval_for_n(20.0, 4) == Balance.MP_SPAWN_INTERVAL_MIN
			and Threat.interval_for_n(-20.0, 4) == Balance.SPAWN_INTERVAL_MAX)


## Директор начинает ночь при n героях: бюджет и пауза — по N.
func _night(n: int) -> void:
	clear_phantoms()
	Threat.reset()
	Game.time_of_day = Balance.NIGHT_START + 0.01
	Threat.tick(0.016)
	var t: float = Threat.threat_level()
	var want_b: float = Threat.night_budget(t, Game.day_number, false) \
			* (1.0 + Balance.MP_BUDGET_PER_PLAYER * float(n - 1))
	ok("N = %d: ночь началась, бюджет × %.1f" % [n, 1.0 + 0.5 * (n - 1)], Threat.active
			and Threat.night_players == n and absf(Threat.budget - want_b) < EPS,
			"T %.2f, бюджет %.2f (ждали %.2f), состав %d" % [t, Threat.budget, want_b, Threat.roster.size()])
	var cap: int = Threat.cap_for_n(Threat.night_day, false, Threat.players_online(), t)
	ok("N = %d: cap = min(%d + 2·%d, 16) = %d" % [n, Threat.cap_for(Threat.night_day, false, t), n - 1, cap],
			cap == mini(Threat.cap_for(Threat.night_day, false, t) + 2 * (n - 1), Balance.MAX_PHANTOMS))
	# Следующий выход: пауза — интервал_N.
	Threat.spawn_timer = 0.0
	var before: int = Threat.roster.size()
	Threat.tick(0.016)
	var want_i: float = Threat.interval_for_n(t, n)
	ok("N = %d: фантом вышел, пауза до следующего %.2f с" % [n, want_i], Threat.roster.size() == before - 1
			and absf(Threat.spawn_timer - want_i) < EPS, "пауза %.3f с" % Threat.spawn_timer)
	Game.time_of_day = 0.3
	Threat.tick(0.016)
	Threat.reset()
	clear_phantoms()


## Спавн у героя с наименьшим числом преследователей; ничья — дальний от базы.
func _spawn_side() -> void:
	var hs: Array = [hero_of(0), hero_of(1), hero_of(2)]
	if hs.has(null):
		ok("прокси трёх клиентов", false)
		return
	var sx: int = World.world_to_cell(World.spawn_point).x
	player.global_position = surface_stand(sx)
	var placed: int = 0
	for k in 3:
		if await teleport_proxy(hs[k], surface_stand(sx + [-30, 30, 60][k])):
			placed += 1
	ok("герои расставлены (база — хост, клиенты в 30, 30 и 60 клетках)", placed == 3)
	clear_phantoms()
	await wait(0.05)
	for spec in [[player, 4], [player, -4], [hs[0], 4], [hs[1], 4]]:
		for p in spawn_near(spec[0], int(spec[1]), "echo"):
			(p as Phantom).stun = 60.0
	await wait(0.8)
	var counts: Array = []
	for h in Game.players:
		counts.append("%s %d" % [(h as Player).nick, Threat.pursuers_of(h)])
	ok("спавн — у героя без преследователей (клиент 2)", Threat.spawn_hero() == hs[2], ", ".join(counts))
	for p in spawn_near(hs[2], 4, "echo"):
		(p as Phantom).stun = 60.0
	await wait(0.8)
	ok("ничья по преследователям — дальний от базы (клиент 2)", Threat.spawn_hero() == hs[2]
			and Threat.pursuers_of(hs[0]) == Threat.pursuers_of(hs[2]))
	ok("точка спавна — у этого героя", Threat.spawn_anchor() == (hs[2] as Player).global_position)
	hs[2].hiding = true
	hs[2].hide_timer = 30.0
	var nxt: Node2D = Threat.spawn_hero()
	ok("спрятавшийся — не в счёт: другой герой с наименьшим числом преследователей",
			nxt != hs[2] and nxt != null and Threat.pursuers_of(nxt) == 1, str(nxt.get("nick") if nxt != null else ""))
	hs[2].hiding = false
	hs[2].hide_timer = 0.0
	clear_phantoms()


## Чёрный ящик, подобранный товарищем, вскрывает хост: 2 кристалла в инвентарь
## хоста (клиентский ящик хост видит через инвентарь прокси) и обрывок журнала.
func _black_box() -> void:
	var p1: Player = hero_of(1)
	if p1 == null:
		return
	var c0: int = player.inv.count_of(IDs.I.CRYSTAL)
	var f0: int = Tech.fragments.size()
	p1.inv.add(IDs.I.BLACK_BOX, 1)
	await wait(0.2)
	ok("чёрный ящик клиента 1 вскрыт хостом: +%d кристалла" % Balance.BLACK_BOX_CRYSTALS,
			p1.inv.count_of(IDs.I.BLACK_BOX) == 0
			and player.inv.count_of(IDs.I.CRYSTAL) >= c0 + Balance.BLACK_BOX_CRYSTALS
			and Tech.fragments.size() == f0 + 1,
			"кристаллов %d → %d" % [c0, player.inv.count_of(IDs.I.CRYSTAL)])


## Шлюз открывается товарищу (свой герой хоста далеко), уходит — закрывается.
func _airlock() -> void:
	var p0: Player = hero_of(0)
	if p0 == null:
		return
	var hc: Vector2i = World.world_to_cell(p0.global_position)
	var cell: Vector2i = Vector2i(-1, -1)
	for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(1, -1), Vector2i(-1, -1)]:
		var c: Vector2i = hc + off
		if World.get_tile_v(c) == IDs.T.AIR and World.cell_to_world(c).distance_to(p0.global_position) \
				<= Balance.AIRLOCK_OPEN_DIST_TILES * World.TILE:
			cell = c
			break
	ok("клетка для шлюза рядом с клиентом 0", cell.x >= 0, str(cell))
	if cell.x < 0:
		return
	World.set_tile(cell.x, cell.y, IDs.T.AIRLOCK)
	await wait(0.4)
	ok("шлюз открылся товарищу (хост далеко)", World.get_tile_v(cell) == IDs.T.AIRLOCK_OPEN
			and player.global_position.distance_to(p0.global_position) > 200.0, DB.tile_name(World.get_tile_v(cell)))
	await teleport_proxy(p0, surface_stand(hc.x - 12))
	await wait(0.4)
	ok("товарищ ушёл — шлюз закрылся", World.get_tile_v(cell) == IDs.T.AIRLOCK)
	World.set_tile(cell.x, cell.y, IDs.T.AIR)


# ------------------------------------------------------------------ КЛИЕНТЫ

func client_args(i: int) -> PackedStringArray:
	return PackedStringArray(["--nick=" + ["Аня", "Борис", "Вера"][i]])


func run_client(_i: int) -> void:
	await barrier("done", -1, 80.0)
	finish()
