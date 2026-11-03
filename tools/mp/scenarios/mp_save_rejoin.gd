extends "res://tools/mp/scenarios/mp_coop_base.gd"
## mp_save_rejoin (ADR-002 § 3 D13, § 4.9; MP-I, #94): сохраняет хост, вещи — по uid.
##
##  * четверо в игре, у каждого клиента своё место, HP и метка в инвентаре; хост
##    сохраняет — файл версии 2: session, players по uid (все 4), раздел player (хост);
##    ЗАМЕР размера и времени сохранения с 4 игроками;
##  * у клиента F5 молчит («сохраняет хост»), F9 в сети выключена у всех;
##  * после сохранения хост портит Аню (метка долой, в сторону); все выходят — их герои
##    в Net.parked (у Ани — испорченная); хост грузит сохранение — в парковке снова
##    сохранённые герои (ЗАМЕР загрузки);
##  * Аня (тот же uid) входит снова — её место, HP и метка из сохранения, стартового
##    набора второй раз нет.

const SLOT: String = "mp_test_rejoin"
const WAIT: float = 8.0
const MARKS: Array = [IDs.I.SCRAP, IDs.I.SAND, IDs.I.LOG]


func _mark(i: int) -> int:
	return int(MARKS[i])


# ------------------------------------------------------------------ ХОСТ

func run_host() -> void:
	ok("хост + %d клиента вошли" % clients, await wait_players(1 + clients, 60.0))
	ok("прокси клиентов с вводом", await wait_proxies(clients, 15.0))
	await barrier("in")
	var sx: int = World.world_to_cell(World.spawn_point).x
	var spots: Array = []
	for i in clients:
		var p: Player = hero_of(i)
		if p == null:
			ok("прокси клиента %d" % i, false)
			finish()
			return
		var s: Vector2 = surface_stand(sx + 8 + 7 * i)
		spots.append(s)
		await teleport_proxy(p, s)
		p.inv.add(_mark(i), 7 + i)
		p.hp = 70.0 - 10.0 * float(i)
		p._regen = -600.0         # реген (+6 HP раз в 6 с) не мешает сверке HP
	await wait(0.5)
	share_put("spots", spots)
	Save.remove(SLOT)
	var saved: bool = Save.save_game(SLOT)
	ok("хост сохранил сетевую игру", saved, Save.last_error)
	print("  ЗАМЕР сохранение с %d игроками: %.1f КБ (сырые %.1f КБ), %.1f мс" % [1 + clients,
			float(Save.last_size) / 1024.0, float(Save.last_raw_size) / 1024.0, Save.last_save_ms])
	var d: Dictionary = Save.decode(FileAccess.get_file_as_bytes(Save.path_for(SLOT)))
	var players: Dictionary = d.get("players", {})
	ok("файл версии %d: session и players по uid — все %d" % [Save.VERSION, 1 + clients],
			int(d.get("version", 0)) == 2 and players.size() == 1 + clients
			and String((d.get("session", {}) as Dictionary).get("name", "")) == String(Net.session["session_name"])
			and players.has(int(Net.local_profile["uid"])) and d.has("player"),
			"версия %d, игроки %s" % [int(d.get("version", 0)), str(players.keys())])
	var e0: Dictionary = players.get(client_uid(0), {})
	ok("запись Ани: ник, метка в инвентаре", String(e0.get("nick", "")) == "Аня"
			and _count_in(e0.get("state", {}), _mark(0)) == 7, str(e0.get("nick", "")))
	ok("F9 в сети выключена (хост)", not UI.quick_load() and Save.last_error == Save.NET_LOAD_IN_MENU)
	await barrier("saved")
	await barrier("tried")

	# --- Портим Аню после сохранения; все выходят.
	var p0: Player = hero_of(0)
	p0.inv.remove_id(_mark(0), 7)
	await teleport_proxy(p0, surface_stand(sx - 20))
	await wait(0.3)
	await barrier("leave")
	ok("все вышли", await wait_until(func() -> bool: return Net.peers.size() == 1, 10.0))
	ok("герои вышедших — в Net.parked по uid", Net.parked.size() == clients
			and Net.parked.has(client_uid(0)), str(Net.parked.keys()))
	ok("в парковке Аня — какой вышла (без метки)",
			_count_in((Net.parked.get(client_uid(0), {}) as Dictionary).get("state", {}), _mark(0)) == 0)

	# --- Загрузка сетевого сохранения.
	var loaded: bool = Save.load_net(SLOT)
	ok("хост загрузил сетевое сохранение", loaded, Save.last_error)
	print("  ЗАМЕР загрузка сохранения с %d игроками в сети: %.1f мс" % [1 + clients, Save.last_load_ms])
	ok("после загрузки — в парковке все трое из файла, у Ани метка",
			Net.parked.size() == clients and _count_in((Net.parked.get(client_uid(0), {}) as Dictionary)
			.get("state", {}), _mark(0)) == 7, str(Net.parked.keys()))

	# --- Аня возвращается.
	relaunch(0)
	ok("Аня вошла снова", await wait_players(2, 45.0))
	await wait_until(func() -> bool: return hero_of(0) != null, 10.0)
	var back: Player = hero_of(0)   # лямбда захватывает копию переменной — присваиваем снаружи
	var restored: bool = back != null and await wait_until(func() -> bool:
		return back.inv.count_of(_mark(0)) == 7 and back.global_position.distance_to(spots[0]) < 24.0, WAIT)
	ok("Аня (тот же uid) — из сохранения: место и метка", restored,
			"%s, метка %d" % [str(back.global_position) if back != null else "—",
			back.inv.count_of(_mark(0)) if back != null else -1])
	ok("Аня: HP из сохранения", back != null and absf(back.hp - 70.0) < 0.5, "%.1f" % (back.hp if back != null else -1.0))
	ok("Аня: стартового набора второй раз нет", back != null and back.inv.count_of(IDs.I.LAMP) == 3,
			"ламп %d" % (back.inv.count_of(IDs.I.LAMP) if back != null else -1))
	ok("Аня ушла из парковки, Борис и Вера ждут", not Net.parked.has(client_uid(0)) and Net.parked.size() == clients - 1)
	await barrier("rejoined")
	Save.remove(SLOT)
	share_clear(["spots"])
	finish()


## Сколько предмета id в записи Player.save_state().
static func _count_in(state, id: int) -> int:
	if not (state is Dictionary):
		return -1
	var n: int = 0
	for e in (state as Dictionary).get("inv", []):
		if e is Array and int(e[0]) == id:
			n += int(e[1])
	return n


# ------------------------------------------------------------------ КЛИЕНТЫ

func run_client(i: int) -> void:
	if is_rejoin():
		await _rejoin(i)
		return
	await barrier("in")
	await barrier("saved")
	notes.clear()
	ok("c%d: F5 у клиента молчит" % i, not UI.quick_save())
	ok("c%d: подсказка «сохраняет хост»" % i, notes_with(Save.NET_HOST_SAVES) == 1, str(notes))
	ok("c%d: F9 в сети выключена" % i, not UI.quick_load() and notes_with(Save.NET_LOAD_IN_MENU) == 1, str(notes))
	await barrier("tried")
	await barrier("leave")
	finish()


func _rejoin(i: int) -> void:
	var spots = share_get("spots")
	var spot: Vector2 = spots[i] if spots is Array else Vector2.INF
	ok("c%d: вернулся — место из сохранения" % i, await wait_until(func() -> bool:
		return player.global_position.distance_to(spot) < 24.0, WAIT),
			"%s / %s" % [str(player.global_position), str(spot)])
	ok("c%d: инвентарь из сохранения (метка)" % i, await wait_until(func() -> bool:
		return player.inv.count_of(_mark(i)) == 7 + i, WAIT), "%d" % player.inv.count_of(_mark(i)))
	ok("c%d: HP из сохранения" % i, await wait_until(func() -> bool:
		return absf(player.hp - (70.0 - 10.0 * float(i))) < 1.0, WAIT), "%.1f" % player.hp)
	await barrier("rejoined")
	finish()
