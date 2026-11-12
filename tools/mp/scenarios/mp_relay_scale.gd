extends "res://tools/mp/scenarios/mp_coop_base.gd"
## mp_relay_scale (#139, переписан под #175): свободная сеть запускает ядро дугами.
## Требование деталей от N остаётся в Game (глава «Сигнал»), но запуск его не ждёт.
##
##  * N = 2: дуги хоста видны Ане (COOP CORE), требование ×1.25 всё ещё считается;
##  * пять дуг — запуск отказывает; шестая — ядро запущено; белый не седьмая;
##  * Аня вышла и вернулась — дуги на месте (не гаснут), команде — уведомление о N.
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

	var cell: Vector2i = World.beacon_cell + Vector2i(2, 0)
	World.set_tile(cell.x, cell.y, IDs.T.AIR)
	ok("ядро поставлено", MachineBase.place_machine("RainbowCore", cell) and Game.core_cell == cell)
	for c in [Beams.R, Beams.G, Beams.B, Beams.Y, Beams.C, Beams.M]:
		Game.core_feed(c)
	ok("шесть дуг — запуск отказывает", Game.core_arc_count() == 6 and not Game.try_finish(player))
	share_put("arcs", Game.core_arcs)
	await barrier("dep")

	# --- Аня вышла: N = 1.
	notes.clear()
	await barrier("leave")
	ok("Аня вышла", await wait_until(func() -> bool: return Net.peers.size() == 1 and Game.hero_count() == 1, 15.0))
	# Вклада не было: N = 1 — ровно базовое требование, не «пластины из воздуха».
	var req1: Dictionary = base.duplicate()
	ok("N = 1: требование одиночное",
			await wait_until(func() -> bool: return Game.relay_req == req1, WAIT), str(Game.relay_req))
	ok("N = 1: дуги целы", Game.core_arcs == int(share_get("arcs")), str(Game.core_arcs))
	ok("уведомление команде: героев 1, ×1", notes_with("Героев на связи: 1") >= 1, str(notes))

	# --- Аня вернулась: N = 2.
	share_put("req", req2)
	relaunch(0)
	ok("Аня вошла снова", await wait_players(2, 45.0))
	ok("N = 2 снова: требование хоста ×1.25", await wait_until(func() -> bool: return Game.relay_req == req2, WAIT),
			str(Game.relay_req))
	ok("N = 2 снова: дуги те же", Game.core_arcs == int(share_get("arcs")))
	await barrier("back")

	# --- Аня вышла снова: N = 1, и прогресс засчитан до победы.
	await barrier("leave2")
	ok("Аня вышла снова", await wait_until(func() -> bool: return Net.peers.size() == 1, 15.0))
	ok("N = 1 снова: требование как в первый раз", await wait_until(func() -> bool: return Game.relay_req == req1, WAIT),
			str(Game.relay_req))
	Game.core_feed(Beams.M)
	Game.tasks_done = 1
	Game.stats_ore = Balance.FREE_ORE_NEED
	Game.nights_survived = Balance.FREE_NIGHTS_NEED
	ok("шестая дуга — ядро запущено", Game.try_finish(player) and Game.relay_active
			and Game.core_arcs == Game.CORE_ARCS_FREE)
	Game.relay_active = false
	share_clear(["req", "arcs"])
	finish()


# ------------------------------------------------------------------ КЛИЕНТ

func run_client(_i: int) -> void:
	if is_rejoin():
		var want = share_get("req")
		ok("c0: вернулся — требование ×1.25, как у хоста", want is Dictionary and await wait_until(
				func() -> bool: return Game.relay_req == want, WAIT), "%s / %s" % [str(Game.relay_req), str(want)])
		var arcs = share_get("arcs")
		ok("c0: дуги те же, что у хоста (COOP CORE)", arcs is int and await wait_until(
				func() -> bool: return Game.core_arcs == int(arcs), WAIT), str(Game.core_arcs))
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
		# Этап 2 теперь добыча (#212). Дуги — строка этапа 4, её клиент ещё не видит.
		ok("c0: HUD этапа добычи", line.begins_with("руда "), "«%s»" % line)
		# Счётчик деталей с панели снят (#169): требование читает трекер HUD, не окно крафта.
		ok("c0: панель крафта больше не рисует счётчик деталей", UI.panel != null
				and not UI.panel.has_method("_goal_req"))
	await barrier("dep")
	var arcs = share_get("arcs")
	ok("c0: дуги хоста видны (COOP CORE)", arcs is int and await wait_until(
			func() -> bool: return Game.core_arcs == int(arcs), WAIT), str(Game.core_arcs))
	ok("c0: требование вкладом не изменилось", Game.relay_req == req)
	await barrier("leave")
	finish()


## Строка трекера HUD на этапе 2 «Собрать релей» (#169: этап 3 — уже удержание;
## этап здесь — только на время пересчёта: у клиента его ведёт глобальный пакет хоста).
func _hud_line() -> String:
	var hud: HUD = UI.hud
	if hud == null:
		return ""
	var st: int = Game.objective_stage
	var hold: bool = Game.relay_active
	Game.objective_stage = 2
	Game.relay_active = false
	hud._compute_tracker()
	Game.objective_stage = st
	Game.relay_active = hold
	return hud.tracker_detail
