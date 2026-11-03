extends "res://tools/mp/scenarios/mp_coop_base.gd"
## mp_death (ADR-002 § 3 D11, § 4.7; MP-I, #94): смерть в сети не трогает часы.
##
##  * хост убивает прокси клиента 0 (Аня): мешок с хотбаром на месте смерти, владелец —
##    uid Ани; клиент 1 (Борис) стоит на мешке — не поднимает (замок владельца);
##  * у Ани экран «ТЕБЯ НАШЛИ» с отсчётом MP_RESPAWN_DELAY (15 с), камера идёт за живым
##    товарищем, D — следующий; у Бориса марионетка Ани мертва;
##  * через 15 с Аня на базе, часы шли как шли (смена та же, время — только от хода
##    игры), экран у Ани закрыт, камера снова своя; Аня поднимает свой мешок;
##  * мешок Бориса старше MP_BAG_OWNER_LOCK — его поднимает Аня (потом — любой);
##  * личная статистика: по смерти у каждого.

const WAIT: float = 6.0

var _bag_pos: Vector2 = Vector2.ZERO


# ------------------------------------------------------------------ ХОСТ

func run_host() -> void:
	ok("хост + %d клиента вошли" % clients, await wait_players(1 + clients, 45.0))
	ok("прокси обоих клиентов с вводом", await wait_proxies(clients, 10.0))
	await barrier("in")
	var p0: Player = hero_of(0)
	var p1: Player = hero_of(1)
	var nc: NetCoop = coop()
	if p0 == null or p1 == null or nc == null:
		ok("прокси и NetCoop на месте", false)
		finish()
		return
	ok("uid героев: прокси — по профилю, свой — Net.local_profile", p0.net_uid == client_uid(0)
			and p1.net_uid == client_uid(1) and player.net_uid == int(Net.local_profile["uid"]),
			"%d %d %d" % [p0.net_uid, p1.net_uid, player.net_uid])
	var sx: int = World.world_to_cell(World.spawn_point).x
	ok("Аня отведена от базы", await teleport_proxy(p0, surface_stand(sx + 24)))
	ok("Борис отведён от базы", await teleport_proxy(p1, surface_stand(sx + 34)))
	player.global_position = surface_stand(sx - 14)
	player.vel = Vector2.ZERO
	await wait(0.5)
	var lamps1: int = p1.inv.count_of(IDs.I.LAMP)
	await barrier("ready")

	# --- Смерть Ани: мешок, отсчёт, часы.
	var day0: int = Game.day_number
	var tod0: float = Game.time_of_day
	var gt0: float = Game.game_time
	var t0: float = Game.game_time   # отсчёты NetCoop идут в _process — меряем теми же часами (часы забега)
	kill(p0)
	ok("Аня погибла (прокси)", p0.dead and p0.hp <= 0.0)
	var bag: ItemEntity = bag_of(client_uid(0))
	ok("мешок с хотбаром Ани — на месте смерти, владелец по uid", bag != null
			and bag.global_position.distance_to(p0.global_position) < 24.0,
			"мешков %d" % bags().size())
	ok("хост: респаун Ани через MP_RESPAWN_DELAY (личный отсчёт, не вайп)",
			absf(float(nc.due.get(p0, -1.0)) - Balance.MP_RESPAWN_DELAY) < 0.5 and nc.wipe_left < 0.0,
			"%.1f" % float(nc.due.get(p0, -1.0)))
	await barrier("dead")

	# --- Замок мешка: Борис стоит на мешке Ани — не поднимает.
	if bag != null:
		await wait_until(func() -> bool: return not is_instance_valid(bag) or bag.grounded, 3.0)
		_bag_pos = bag.global_position if is_instance_valid(bag) else _bag_pos
		await teleport_proxy(p1, _bag_pos + Vector2(0, -4))
		await wait(1.5)
		ok("Борис на мешке Ани — не поднял (MP_BAG_OWNER_LOCK = %d с)" % int(Balance.MP_BAG_OWNER_LOCK),
				is_instance_valid(bag) and p1.inv.count_of(IDs.I.LAMP) == lamps1,
				"ламп у Бориса %d → %d" % [lamps1, p1.inv.count_of(IDs.I.LAMP)])
		await teleport_proxy(p1, surface_stand(sx + 34))

	# --- Респаун без сдвига часов.
	var back: bool = await wait_until(func() -> bool: return not p0.dead, Balance.MP_RESPAWN_DELAY + 5.0)
	var dt: float = Game.game_time - t0
	ok("Аня возродилась через %d с" % int(Balance.MP_RESPAWN_DELAY), back
			and dt > Balance.MP_RESPAWN_DELAY - 1.0 and dt < Balance.MP_RESPAWN_DELAY + 2.5, "%.1f с" % dt)
	ok("Аня — в капсуле на базе, HP полное", at_base(p0) and p0.hp >= Player.MAX_HP,
			"%.0f px, hp %.0f" % [p0.global_position.distance_to(World.spawn_point), p0.hp])
	var expect: float = (Game.game_time - gt0) / Game.DAY_LENGTH
	var drift: float = absf(wrapf(Game.time_of_day - tod0 - expect, -0.5, 0.5))
	ok("часы не сдвинулись: смена та же, время — только от хода игры", Game.day_number == day0
			and drift < 0.002, "смена %d → %d, расхождение %.4f цикла" % [day0, Game.day_number, drift])
	await barrier("respawned")

	# --- Свой мешок владелец поднимает.
	if is_instance_valid(bag):
		await teleport_proxy(p0, _bag_pos + Vector2(0, -4))
		var wr: WeakRef = weakref(bag)   # мешок исчезнет — лямбда не держит освобождённый узел
		var took: bool = await wait_until(func() -> bool: return wr.get_ref() == null, WAIT)
		ok("Аня подняла свой мешок", took and p0.inv.count_of(IDs.I.LAMP) >= 3,
				"ламп %d" % p0.inv.count_of(IDs.I.LAMP))
	else:
		ok("мешок Ани дождался владельца", false)

	# --- Мешок старше MP_BAG_OWNER_LOCK — любой.
	kill(p1)
	var bag1: ItemEntity = bag_of(client_uid(1))
	ok("мешок Бориса выпал, владелец — Борис", bag1 != null)
	if bag1 != null:
		bag1.age = Balance.MP_BAG_OWNER_LOCK + 1.0
		var lamps0: int = p0.inv.count_of(IDs.I.LAMP)
		await wait_until(func() -> bool: return bag1.grounded, 3.0)
		await teleport_proxy(p0, bag1.global_position + Vector2(0, -4))
		var wr1: WeakRef = weakref(bag1)
		var took1: bool = await wait_until(func() -> bool: return wr1.get_ref() == null, WAIT)
		ok("мешок старше %d с поднимает чужой (Аня взяла мешок Бориса)" % int(Balance.MP_BAG_OWNER_LOCK),
				took1 and p0.inv.count_of(IDs.I.LAMP) > lamps0, "ламп %d → %d" % [lamps0, p0.inv.count_of(IDs.I.LAMP)])
	ok("личная статистика: смерть у Ани и у Бориса", int(p0.net_stats.get("deaths", 0)) == 1
			and int(p1.net_stats.get("deaths", 0)) == 1 and int(player.net_stats.get("deaths", 0)) == 0,
			"%s %s" % [str(p0.net_stats), str(p1.net_stats)])
	var lines: Array = nc.stats_lines()
	ok("строки итогов по игрокам", lines.has("Аня: смертей 1") and lines.has("Борис: смертей 1"), str(lines))
	await barrier("done")
	finish()


# ------------------------------------------------------------------ КЛИЕНТЫ

func run_client(i: int) -> void:
	await barrier("in")
	await barrier("ready")
	await barrier("dead")
	if i == 0:
		await _victim()
	else:
		var a: Player = hero_of(0)
		ok("c1: марионетка Ани мертва (флаг в STATE)",
				await wait_until(func() -> bool: return a != null and a.dead, WAIT))
		await barrier("respawned")
		ok("c1: Аня снова жива", await wait_until(func() -> bool: return a != null and not a.dead, WAIT))
	await barrier("done")
	finish()


func _victim() -> void:
	var es: EndScreen = end_screen()
	var nc: NetCoop = coop()
	var shown: bool = await wait_until(func() -> bool:
		return player.dead and es != null and es.visible and es.net_death, WAIT)
	ok("c0: свой герой мёртв, экран смерти в сети", shown)
	if not shown:
		await barrier("respawned")
		return
	ok("c0: отсчёт до капсулы ≈ %d с, не зритель" % int(Balance.MP_RESPAWN_DELAY),
			es.net_respawn_left() > Balance.MP_RESPAWN_DELAY - 4.0 and not es.net_spectator and not es.net_wipe,
			"%.1f с" % es.net_respawn_left())
	ok("c0: камера за живым товарищем", await wait_until(func() -> bool:
		return (nc.watching != null and not nc.watching.dead
				and player.camera.position.distance_to(nc.watching.global_position - player.global_position) < 1.0), 3.0))
	var first: Player = nc.watching
	ok("c0: на экране — чьими глазами", es.net_watch != "" and es.net_watch == String(first.nick), es.net_watch)
	await tap(KEY_D)
	ok("c0: D — следующий товарищ", await wait_until(func() -> bool:
		return nc.watching != null and nc.watching != first, 2.0),
			"%s → %s" % [first.nick, nc.watching.nick if nc.watching != null else "—"])
	await tap(KEY_A)
	ok("c0: A — обратно", await wait_until(func() -> bool: return nc.watching == first, 2.0))
	# До барьера: сразу после него хост ведёт Аню к мешку.
	ok("c0: возродился — экран закрыт, герой на базе", await wait_until(func() -> bool:
		return not player.dead and not es.visible and at_base(player), Balance.MP_RESPAWN_DELAY + WAIT),
			"%.0f px от капсулы" % player.global_position.distance_to(World.spawn_point))
	# Камеру возвращает NetCoop в своём кадре отрисовки — после флага «жив» из OWN, не в том же кадре.
	ok("c0: камера снова своя", await wait_until(func() -> bool:
		return player.camera.position == Vector2.ZERO and nc.watching == null, WAIT),
			"%s, глазами %s" % [str(player.camera.position), nc.watching.nick if nc.watching != null else "—"])
	await barrier("respawned")
