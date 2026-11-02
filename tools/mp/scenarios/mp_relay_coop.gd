extends "res://tools/mp/scenarios/mp_coop_base.gd"
## mp_relay_coop (ADR-002 § 4.7 «Релей вчетвером»; решение #99; MP-I, #94).
##
##  * вклад деталей: у Ани половина relay_req, у Бориса — остальное; Аня держит E у ядра —
##    сдаёт своё (у всех Game.relay_have то же, COOP RELAY), отсчёт не пошёл; Борис держит
##    E — набрано всё, отсчёт пошёл;
##  * зона удержания (только в сети): все дальше MP_RELAY_HOLD_RADIUS_TILES от ядра —
##    отсчёт стоит (не сбрасывается), «Сигнал без присмотра» у всех; Борис вернулся —
##    отсчёт идёт.

const WAIT: float = 6.0
const HOLD_E: float = 3.6        ## удержание E у ядра — 3 с, с запасом


# ------------------------------------------------------------------ ХОСТ

func run_host() -> void:
	ok("хост + %d клиента вошли" % clients, await wait_players(1 + clients, 45.0))
	ok("прокси обоих клиентов с вводом", await wait_proxies(clients, 10.0))
	await barrier("in")
	var p0: Player = hero_of(0)
	var p1: Player = hero_of(1)
	if p0 == null or p1 == null:
		finish()
		return
	ok("хост у ядра", stand_next_to_beacon())
	var at_core: Vector2 = player.global_position
	ok("Аня у ядра", await teleport_proxy(p0, at_core))
	ok("Борис у ядра", await teleport_proxy(p1, at_core))
	# Детали: у Ани — половина каждой, у Бориса — остальное (стартовые пластины — долой).
	var half: Dictionary = {}
	for id in Game.relay_req:
		var need: int = int(Game.relay_req[id])
		for p in [p0, p1, player]:
			p.inv.remove_id(int(id), p.inv.count_of(int(id)))
		half[id] = need / 2
		if need / 2 > 0:
			p0.inv.add(int(id), need / 2)
		p1.inv.add(int(id), need - need / 2)
	await wait(0.3)
	await barrier("give")

	# --- Аня сдаёт половину.
	var got: bool = await wait_until(func() -> bool: return not Game.relay_have.is_empty(), HOLD_E + 3.0)
	await wait(0.3)
	var exact: bool = true
	for id in Game.relay_req:
		if Game.relay_count(int(id)) != int(half[id]) or p0.inv.count_of(int(id)) != 0:
			exact = false
	ok("Аня сдала в ядро свою половину — из своего инвентаря", got and exact, str(Game.relay_have))
	ok("набрано не всё — отсчёт не пошёл", not Game.relay_active)
	ok("у хоста и Бориса детали на месте", p1.inv.count_of(IDs.I.IRON_PLATE) == int(Game.relay_req[IDs.I.IRON_PLATE]) - int(half[IDs.I.IRON_PLATE]))
	share_put("half", Game.relay_have.duplicate())
	await barrier("c0_done")

	# --- Борис докладывает — отсчёт пошёл.
	var started: bool = await wait_until(func() -> bool: return Game.relay_active, HOLD_E + 3.0)
	ok("Борис доложил остальное — релей запущен", started and Game.relay_have.is_empty())
	ok("у Бориса детали ушли в ядро", p1.inv.count_of(IDs.I.IRON_PLATE) == 0)
	ok("отсчёт — %d с" % int(Balance.RELAY_TIME), absf(Game.relay_timer - Balance.RELAY_TIME) < 2.0,
			"%.1f" % Game.relay_timer)
	await barrier("started")

	# --- Зона удержания.
	var a: float = Game.relay_timer
	await wait(1.0)
	ok("все у ядра — отсчёт идёт", a - Game.relay_timer > 0.5 and not Game.relay_unattended,
			"%.2f → %.2f" % [a, Game.relay_timer])
	var sx: int = World.beacon_cell.x
	var far: Vector2 = surface_stand(sx + int(Balance.MP_RELAY_HOLD_RADIUS_TILES) + 14)
	notes.clear()
	player.global_position = surface_stand(sx - int(Balance.MP_RELAY_HOLD_RADIUS_TILES) - 14)
	player.vel = Vector2.ZERO
	await teleport_proxy(p0, far)
	await teleport_proxy(p1, far)
	await wait(0.5)
	var b: float = Game.relay_timer
	await wait(1.5)
	ok("все дальше %d клеток — отсчёт стоит (не сброшен)" % int(Balance.MP_RELAY_HOLD_RADIUS_TILES),
			Game.relay_unattended and absf(b - Game.relay_timer) < 0.01 and Game.relay_timer < a,
			"%.2f → %.2f" % [b, Game.relay_timer])
	ok("хост: «Сигнал без присмотра»", notes_with("Сигнал без присмотра") == 1, str(notes))
	await barrier("away")
	await barrier("c_away")
	await teleport_proxy(p1, at_core)
	await wait(0.4)
	var c: float = Game.relay_timer
	await wait(1.0)
	ok("Борис вернулся — отсчёт идёт", not Game.relay_unattended and c - Game.relay_timer > 0.5,
			"%.2f → %.2f" % [c, Game.relay_timer])
	await barrier("back")
	Game.relay_active = false
	finish()


# ------------------------------------------------------------------ КЛИЕНТЫ

func run_client(i: int) -> void:
	await barrier("in")
	await barrier("give")
	if i == 0:
		hold(KEY_E)
		await wait(HOLD_E)
		release(KEY_E)
	await barrier("c0_done")
	var half = share_get("half")
	ok("c%d: вклад Ани виден у клиента (COOP RELAY)" % i, await wait_until(func() -> bool:
		return half is Dictionary and Game.relay_have == half, WAIT), "%s / %s" % [str(Game.relay_have), str(half)])
	if i == 1:
		hold(KEY_E)
		await wait(HOLD_E)
		release(KEY_E)
	await barrier("started")
	ok("c%d: релей запущен, вклад обнулён" % i, await wait_until(func() -> bool:
		return Game.relay_active and Game.relay_have.is_empty(), WAIT))
	await barrier("away")
	ok("c%d: у ядра никого — «без присмотра», отсчёт стоит" % i, await wait_until(func() -> bool:
		return Game.relay_unattended, WAIT))
	var t: float = Game.relay_timer
	await wait(1.0)
	ok("c%d: свой отсчёт тоже стоит" % i, absf(Game.relay_timer - t) < 0.05, "%.2f → %.2f" % [t, Game.relay_timer])
	ok("c%d: уведомление «Сигнал без присмотра»" % i, notes_with("Сигнал без присмотра") >= 1)
	await barrier("c_away")
	await barrier("back")
	ok("c%d: Борис у ядра — отсчёт идёт" % i, await wait_until(func() -> bool:
		return not Game.relay_unattended, WAIT))
	finish()
