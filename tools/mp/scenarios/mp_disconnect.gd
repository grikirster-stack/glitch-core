extends "res://tools/mp/scenarios/mp_coop_base.gd"
## mp_disconnect (ADR-002 § 4.4; MP-I, #94): обрыв клиента → парковка → возврат.
##
##  * у Ани место, HP 64 и метка в инвентаре; хост убивает процесс клиента (обрыв, не
##    выход): по таймауту ENet (3–8 с) прокси убран, герой — в Net.parked по uid;
##    отключение не наказывается: хотбар не упал (мешка нет), герой жив;
##  * тот же uid вернулся — позиция, HP, инвентарь как были (у хоста и у клиента).

const WAIT: float = 8.0
const MARK: int = IDs.I.SCRAP


# ------------------------------------------------------------------ ХОСТ

func run_host() -> void:
	ok("хост + клиент вошли", await wait_players(2, 45.0))
	ok("прокси клиента с вводом", await wait_proxies(1, 10.0))
	await barrier("in")
	var p0: Player = hero_of(0)
	if p0 == null:
		finish()
		return
	var sx: int = World.world_to_cell(World.spawn_point).x
	var spot: Vector2 = surface_stand(sx + 18)
	ok("Аня на своём месте", await teleport_proxy(p0, spot))
	p0.hp = 64.0
	p0._regen = -600.0             # реген (+6 HP раз в 6 с) не мешает сверке HP
	p0.inv.add(MARK, 5)
	await wait(1.0)
	share_put("spot", spot)
	await barrier("set")
	var hotbar: int = 0
	var hb: int = p0.inv.hotbar_size
	for k in hb:
		if not p0.inv.slots[k].is_empty():
			hotbar += 1
	var bags0: int = bags().size()
	var t0: float = now()
	ok("обрыв: процесс клиента убит", await kill_client(0))
	# ENet: таймаут 3–8 с после последнего подтверждения, и ещё такт проверки — с запасом.
	var gone: bool = await wait_until(func() -> bool: return Net.peers.size() == 1, 25.0)
	print("  ЗАМЕР обрыв замечен через %.1f с (таймаут ENet %d–%d мс)" % [now() - t0,
			Net.PEER_TIMEOUT_MIN_MS, Net.PEER_TIMEOUT_MAX_MS])
	ok("хост заметил обрыв (таймаут ENet)", gone)
	var e: Dictionary = Net.parked.get(client_uid(0), {})
	ok("герой Ани — в Net.parked по uid", not e.is_empty() and String(e.get("nick", "")) == "Аня",
			str(Net.parked.keys()))
	ok("в парковке: место, HP и метка как были", not e.is_empty()
			and (e["state"]["pos"] as Vector2).distance_to(spot) < 24.0
			and absf(float(e["state"]["hp"]) - 64.0) < 1.0 and _count_in(e["state"], MARK) == 5)
	ok("обрыв не наказывается: мешка нет, герой жив", bags().size() == bags0 and not bool(e.get("dead", true)))
	ok("прокси убран из игроков", Game.players.size() == 1 and hero_of(0) == null)
	ok("хотбар цел (было %d стопок)" % hotbar, not e.is_empty() and _hotbar_in(e["state"], hb) == hotbar)

	# --- Возврат того же uid.
	relaunch(0)
	ok("Аня вошла снова", await wait_players(2, 45.0))
	await wait_until(func() -> bool: return hero_of(0) != null, 10.0)
	var back: Player = hero_of(0)   # лямбда захватывает копию переменной — присваиваем снаружи
	ok("возврат: позиция, HP, инвентарь как были", back != null and await wait_until(func() -> bool:
		return (back.global_position.distance_to(spot) < 24.0 and absf(back.hp - 64.0) < 1.0
				and back.inv.count_of(MARK) == 5), WAIT),
			"%s hp %.0f метка %d" % [str(back.global_position), back.hp, back.inv.count_of(MARK)] if back != null else "—")
	ok("парковка Ани освобождена", not Net.parked.has(client_uid(0)))
	await barrier("back", 1)
	share_clear(["spot"])
	finish()


static func _count_in(state, id: int) -> int:
	var n: int = 0
	for s in (state as Dictionary).get("inv", []):
		if s is Array and int(s[0]) == id:
			n += int(s[1])
	return n


static func _hotbar_in(state, size: int) -> int:
	var n: int = 0
	var inv: Array = (state as Dictionary).get("inv", [])
	for k in mini(size, inv.size()):
		if inv[k] is Array and int(inv[k][1]) > 0:
			n += 1
	return n


# ------------------------------------------------------------------ КЛИЕНТ

func run_client(_i: int) -> void:
	if not is_rejoin():
		await barrier("in")
		await barrier("set")
		await wait(60.0)             # хост убьёт процесс — это и есть обрыв
		finish()
		return
	var spot = share_get("spot")
	ok("c0: вернулся на своё место", spot is Vector2 and await wait_until(func() -> bool:
		return player.global_position.distance_to(spot) < 24.0, WAIT),
			"%s / %s" % [str(player.global_position), str(spot)])
	ok("c0: HP как было (OWN)", await wait_until(func() -> bool: return absf(player.hp - 64.0) < 1.0, WAIT),
			"%.1f" % player.hp)
	ok("c0: инвентарь как был (INV)", await wait_until(func() -> bool: return player.inv.count_of(MARK) == 5, WAIT))
	await barrier("back")
	finish()
