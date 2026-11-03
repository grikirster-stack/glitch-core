extends "res://tools/mp/scenarios/mp_coop_base.gd"
## mp_relay_scale (ADR-002 § 4.7 «Релей вчетвером», § 8 вопрос 3; #139): требование
## релея растёт с числом героев — DB.relay_req × (1 + MP_RELAY_REQ_PER_PLAYER·(N − 1)).
##
##  * N = 2 (хост + Аня): у хоста и у Ани одно требование ×1.25 (COOP RELAY / снимок входа);
##  * хост сдаёт в ядро жел. пластин больше одиночного требования, но меньше ×1.25, и сталь;
##    Аня видит тот же вклад;
##  * Аня вышла (N = 1): требование — одиночное, но пластин — не ниже сданного (прогресс не
##    потерян), вклад цел, команде — уведомление с новым множителем;
##  * Аня вернулась (N = 2): у обоих снова ×1.25, вклад тот же (снимок входа);
##  * Аня вышла снова (N = 1): требование как в первый раз; хост докладывает недостающее —
##    релей запускается: сданное при N = 2 засчитано.
## Отсчёты — по игровым часам (wait_until), не по кадрам.

const WAIT: float = 8.0
const PLATE: int = IDs.I.IRON_PLATE
const STEEL: int = IDs.I.STEEL_PLATE


## Ожидаемое требование при n героях без вклада: base × k, по детали — до целого.
static func expected(n: int) -> Dictionary:
	var out: Dictionary = {}
	for id in DB.relay_req.keys():
		var base: int = int(DB.relay_req[id])
		out[id] = base if n <= 1 else roundi(float(base) * Game.relay_req_scale(n))
	return out


# ------------------------------------------------------------------ ХОСТ

func run_host() -> void:
	ok("хост + клиент вошли", await wait_players(2, 45.0))
	ok("прокси клиента с вводом", await wait_proxies(1, 10.0))
	await barrier("in")
	var base: Dictionary = DB.relay_req.duplicate()
	var req2: Dictionary = expected(2)
	ok("множитель N = 2 — 1.25, N = 4 — 1.75", is_equal_approx(Game.relay_req_scale(2), 1.25)
			and is_equal_approx(Game.relay_req_scale(4), 1.75) and is_equal_approx(Game.relay_req_scale(1), 1.0))
	ok("N = 2: требование хоста ×1.25 (пластин %d → %d)" % [int(base[PLATE]), int(req2[PLATE])],
			await wait_until(func() -> bool: return Game.relay_req == req2, WAIT), str(Game.relay_req))
	share_put("req", Game.relay_req.duplicate())
	await barrier("n2")

	# --- Вклад при N = 2: пластин больше одиночного требования, меньше нового.
	var plates: int = int(base[PLATE]) + (int(req2[PLATE]) - int(base[PLATE])) / 2
	var steel: int = int(base[STEEL]) / 2
	for id in Game.relay_req:
		player.inv.remove_id(int(id), player.inv.count_of(int(id)))
	player.inv.add(PLATE, plates)
	player.inv.add(STEEL, steel)
	ok("хост сдал в ядро %d пластин и %d стали" % [plates, steel], Game.relay_deposit(player).size() == 2
			and Game.relay_count(PLATE) == plates and Game.relay_count(STEEL) == steel, str(Game.relay_have))
	ok("требование вкладом не изменилось", Game.relay_req == req2)
	var have: Dictionary = Game.relay_have.duplicate()
	share_put("have", have)
	await barrier("dep")

	# --- Аня вышла: N = 1.
	notes.clear()
	await barrier("leave")
	ok("Аня вышла", await wait_until(func() -> bool: return Net.peers.size() == 1 and Game.hero_count() == 1, 15.0))
	var req1: Dictionary = base.duplicate()
	req1[PLATE] = plates
	ok("N = 1: требование одиночное, пластин — не ниже сданного (%d)" % plates,
			await wait_until(func() -> bool: return Game.relay_req == req1, WAIT), str(Game.relay_req))
	ok("N = 1: вклад цел", Game.relay_have == have, str(Game.relay_have))
	ok("уведомление команде: героев 1, ×1", notes_with("Героев на связи: 1") >= 1, str(notes))

	# --- Аня вернулась: N = 2.
	share_put("req", req2)
	relaunch(0)
	ok("Аня вошла снова", await wait_players(2, 45.0))
	ok("N = 2 снова: требование хоста ×1.25", await wait_until(func() -> bool: return Game.relay_req == req2, WAIT),
			str(Game.relay_req))
	ok("N = 2 снова: вклад тот же", Game.relay_have == have)
	await barrier("back")

	# --- Аня вышла снова: N = 1, и прогресс засчитан до победы.
	await barrier("leave2")
	ok("Аня вышла снова", await wait_until(func() -> bool: return Net.peers.size() == 1, 15.0))
	ok("N = 1 снова: требование как в первый раз", await wait_until(func() -> bool: return Game.relay_req == req1, WAIT),
			str(Game.relay_req))
	for id in Game.relay_req:
		var miss: int = int(Game.relay_req[id]) - Game.relay_count(int(id))
		if miss > 0:
			player.inv.add(int(id), miss)
	var p_left: int = player.inv.count_of(PLATE)
	ok("сданные при N = 2 пластины засчитаны — докладывать их не нужно", p_left == 0, str(p_left))
	ok("недостающее доложено — релей запущен", Game.try_finish(player) and Game.relay_active)
	Game.relay_active = false
	share_clear(["req", "have"])
	finish()


# ------------------------------------------------------------------ КЛИЕНТ

func run_client(_i: int) -> void:
	if is_rejoin():
		var want = share_get("req")
		ok("c0: вернулся — требование ×1.25, как у хоста", want is Dictionary and await wait_until(
				func() -> bool: return Game.relay_req == want, WAIT), "%s / %s" % [str(Game.relay_req), str(want)])
		var have = share_get("have")
		ok("c0: вклад тот же, что у хоста (снимок входа)", have is Dictionary and await wait_until(
				func() -> bool: return Game.relay_have == have, WAIT), "%s / %s" % [str(Game.relay_have), str(have)])
		await barrier("back")
		await barrier("leave2")
		finish()
		return
	await barrier("in")
	await barrier("n2")
	var req = share_get("req")
	ok("c0: N = 2 — требование то же, что у хоста", req is Dictionary and await wait_until(
			func() -> bool: return Game.relay_req == req, WAIT), "%s / %s" % [str(Game.relay_req), str(req)])
	if req is Dictionary:
		var line: String = _hud_line()
		var want: String = "%s %d/%d" % [DB.item_name(PLATE),   # сдано (хост мог уже сдать) + своё
				Game.relay_count(PLATE) + player.inv.count_of(PLATE), int(req[PLATE])]
		ok("c0: HUD (этап 3) — «%s»" % want, line.contains(want), "«%s»" % line)
		ok("c0: окно цели в инвентаре — то же требование", UI.panel != null and UI.panel._goal_req() == req)
	await barrier("dep")
	var have = share_get("have")
	ok("c0: вклад хоста виден (COOP RELAY)", have is Dictionary and await wait_until(
			func() -> bool: return Game.relay_have == have, WAIT), "%s / %s" % [str(Game.relay_have), str(have)])
	ok("c0: требование вкладом не изменилось", Game.relay_req == req)
	await barrier("leave")
	finish()


## Строка трекера HUD на этапе 3 «Собрать релей» (этап здесь — только на время пересчёта:
## у клиента его ведёт глобальный пакет хоста).
func _hud_line() -> String:
	var hud: HUD = UI.hud
	if hud == null:
		return ""
	var st: int = Game.objective_stage
	Game.objective_stage = 3
	hud._compute_tracker()
	Game.objective_stage = st
	return hud.tracker_detail
