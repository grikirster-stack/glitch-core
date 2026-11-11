extends "res://tools/mp/scenarios/mp_coop_base.gd"
## mp_relay_coop (ADR-002 § 4.7; #175). Свободная сеть запускает ядро семью дугами,
## не вкладом деталей (вклад остался у главы «Сигнал»).
##
##  * хост ставит ядро, шесть дуг — E не запускает; седьмая — кадр CORE, отсчёт пошёл;
##  * зона удержания (только в сети): все дальше MP_RELAY_HOLD_RADIUS_TILES от ядра —
##    отсчёт стоит (не сбрасывается), «Сигнал без присмотра» у всех; Борис вернулся —
##    отсчёт идёт. Радиус меряется от Game.core_cell.

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
	var cell: Vector2i = _place_core()
	ok("ядро поставлено", cell.x >= 0 and Game.core_cell == cell, str(cell))
	if cell.x < 0:
		finish()
		return
	ok("хост у ядра", stand_next_to_cell(cell))
	var at_core: Vector2 = player.global_position
	ok("Аня у ядра", await teleport_proxy(p0, at_core + Vector2(16, 0)))
	ok("Борис у ядра", await teleport_proxy(p1, at_core + Vector2(-16, 0)))
	_feed(6)
	share_put("arcs", Game.core_arcs)
	await wait(0.3)
	await barrier("give")
	ok("шесть дуг — отсчёт не пошёл", Game.core_arc_count() == 6 and not Game.relay_active, str(Game.core_arcs))
	await barrier("c0_done")

	# --- Седьмая дуга — отсчёт пошёл. E у ядра то же самое, что core_launch.
	Game.core_feed(Beams.W)
	var started: bool = Game.try_finish(player)
	ok("семь дуг — ядро запущено", started and Game.relay_active and Game.core_arcs == 0x7F)
	ok("отсчёт — %d с" % int(Balance.RELAY_TIME), absf(Game.relay_timer - Balance.RELAY_TIME) < 2.0,
			"%.1f" % Game.relay_timer)
	await barrier("started")

	# --- Зона удержания.
	var a: float = Game.relay_timer
	await wait(1.0)
	ok("все у ядра — отсчёт идёт", a - Game.relay_timer > 0.5 and not Game.relay_unattended,
			"%.2f → %.2f" % [a, Game.relay_timer])
	var sx: int = Game.core_cell.x
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
	await teleport_proxy(p1, at_core + Vector2(-16, 0))
	await wait(0.4)
	var c: float = Game.relay_timer
	await wait(1.0)
	ok("Борис вернулся — отсчёт идёт", not Game.relay_unattended and c - Game.relay_timer > 0.5,
			"%.2f → %.2f" % [c, Game.relay_timer])
	await barrier("back")
	# Кот (#176): клиент видит марионетку, не фантома. Выход — из ядра.
	Game.time_of_day = Balance.NIGHT_START + 0.01
	var cat: RainbowCat = Game.cat_hatch_at(player.global_position + Vector2(48.0, -24.0))
	ok("хост выпустил кота", cat != null)
	var np = player.get_node_or_null("/root/NetPlayers") if false else null
	# Несколько тактов: SPAWN по каналу 0 и строка CAT должны дойти до барьера.
	await wait(0.4)
	await barrier("cat")
	await wait(0.3)
	if cat != null and is_instance_valid(cat):
		cat.queue_free()
	Game.relay_active = false
	finish()


# ------------------------------------------------------------------ КЛИЕНТЫ

func run_client(i: int) -> void:
	await barrier("in")
	await barrier("give")
	var arcs = share_get("arcs")
	ok("c%d: шесть дуг видны (COOP CORE)" % i, await wait_until(func() -> bool:
		return arcs is int and Game.core_arcs == int(arcs) and Game.core_arc_count() == 6, WAIT),
			str(Game.core_arcs))
	await barrier("c0_done")
	await barrier("started")
	ok("c%d: ядро запущено, семь дуг" % i, await wait_until(func() -> bool:
		return Game.relay_active and Game.core_arcs == 0x7F, WAIT), str(Game.core_arcs))
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
	await barrier("cat")
	var puppet: Node = null
	var found_now: Array = get_tree().get_nodes_in_group("rainbow_cat")
	if not found_now.is_empty():
		puppet = found_now[0]
	var seen: bool = puppet != null or await wait_until(func() -> bool:
		var found: Array = get_tree().get_nodes_in_group("rainbow_cat")
		if found.is_empty():
			return false
		puppet = found[0]
		return true
	, WAIT)
	var script_ok: bool = puppet != null and puppet.get_script() != null \
			and str(puppet.get_script().resource_path).ends_with("rainbow_cat.gd")
	ok("c%d: клиент видит кота" % i, seen and script_ok and not puppet.is_in_group("phantom"),
			"узел %s" % (puppet.name if puppet != null else "нет"))
	finish()


func _place_core() -> Vector2i:
	var cell: Vector2i = World.beacon_cell + Vector2i(2, 0)
	World.set_tile(cell.x, cell.y, IDs.T.AIR)
	if not MachineBase.place_machine("RainbowCore", cell):
		return Vector2i(-1, -1)
	return cell


func _feed(n: int) -> void:
	var colors: Array = [Beams.R, Beams.G, Beams.B, Beams.Y, Beams.C, Beams.M]
	for i in mini(n, colors.size()):
		Game.core_feed(colors[i])


func stand_next_to_cell(cell: Vector2i) -> bool:
	var base: int = cell.y + 1
	for dx in [1, -1, 2, -2]:
		var px: int = cell.x + int(dx)
		if not World.is_solid_cell(Vector2i(px, base)):
			World.set_tile(px, base, IDs.T.STEEL)
		player.global_position = Vector2(float(px * World.TILE) + 8.0, float(base * World.TILE) - 11.0)
		player.vel = Vector2.ZERO
		return true
	return false
