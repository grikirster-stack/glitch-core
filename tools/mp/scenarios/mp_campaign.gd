extends "res://tools/mp/scenarios/mp_coop_base.gd"
## mp_campaign (ADR-004): глава кампании по сети.
##
##  * хост запускает «Тёмную станцию» до входа клиента: id главы в Net.session —
##    клиент получает его в приветствии, базу и состояние главы — в снимке;
##  * у клиента: глава-марионетка, набор главы, сохранение закрыто, HUD — карточка первой цели;
##  * хлам у прокси двигает этап; рассвет — победа у обоих (#170: глав 2–5 нет).

const MISSION: String = "dark_station"
const WAIT: float = 8.0


func _init() -> void:
	auto_launch = false


# ------------------------------------------------------------------ ХОСТ

func run_host() -> void:
	ok("мир хоста — сид кампании", World.world_seed == Campaign.SEED, str(World.world_seed))
	Net.session["mission"] = MISSION
	var m: Mission = Campaign.start(scene, MISSION)
	ok("хост: глава запущена", m != null and Game.in_mission())
	if m == null:
		finish()
		return
	m.give_kit(player)
	launch([0])
	ok("хост + клиент вошли", await wait_players(2, 45.0))
	ok("прокси клиента с вводом", await wait_proxies(1, 10.0))
	var p0: Player = hero_of(0)
	ok("хост: прокси клиента получил набор главы", await wait_until(func() -> bool:
		return p0 != null and p0.inv.count_of(IDs.I.LAMP) >= 1, WAIT))
	await barrier("in")
	await barrier("seen")
	# Хлам у прокси двигает этап. Турелей и буров больше нет (#170).
	if p0 != null:
		p0.inv.add(IDs.I.SCRAP, HUD.TUT_SCRAP)
	ok("хост: хлам → следующий этап", await wait_until(func() -> bool: return m.stage >= 1, WAIT), str(m.goals))
	# Рассвет побеждает только на этапе «Первая ночь». До него — цели главы,
	# как в одиночном сценарии: горелка, топка, терминал, два светокристалла.
	if p0 != null:
		p0.inv.add(IDs.I.BURNER, 1)
	ok("хост: горелка → этап «Свет базы»", await wait_until(func() -> bool: return m.stage >= 2, WAIT), str(m.stage))
	var term: Vector2i = _base_terminal()
	var burner = CampaignBase.put("Burner", term + Vector2i(1, 0), {"fuel": 4})
	ok("хост: горящая горелка → этап «Терминал»", burner != null
			and await wait_until(func() -> bool: return m.stage >= 3, WAIT), str(m.stage))
	Game.complete_task()
	ok("хост: терминал → этап «Свет»", await wait_until(func() -> bool: return m.stage >= 4, WAIT), str(m.stage))
	var row: int = World.beacon_cell.y
	for dx in [5, 6]:
		World.set_tile(World.beacon_cell.x + dx + 10, row, IDs.T.LIGHT_CRYSTAL)
	ok("хост: свет → этап «Первая ночь»", await wait_until(func() -> bool: return m.stage >= 5, WAIT), str(m.stage))
	await barrier("night")
	Game.time_of_day = Balance.NIGHT_END - 0.002
	ok("хост: рассвет — победа", await wait_until(func() -> bool:
		return m.result == Mission.Result.WON and Game.state == Game.State.WON, WAIT))
	await barrier("won")
	finish()


# ------------------------------------------------------------------ КЛИЕНТ

func run_client(_i: int) -> void:
	ok("клиент: id главы в приветствии хоста", String(Net.session.get("mission", "")) == MISSION,
			str(Net.session.get("mission", "")))
	var got: bool = await wait_until(func() -> bool:
		return Game.in_mission() and bool(Game.mission.puppet) and String(Game.mission.id) == MISSION, WAIT)
	ok("клиент: марионетка главы, первый этап", got)
	await barrier("in")
	var m = Game.mission
	ok("клиент: задачи хоста", m != null and m.goals.size() >= 1, str(m.goals) if m != null else "")
	ok("клиент: база главы без фабрики", Mission.machines_of("Burner") >= 1
			and Mission.machines_of("Turret") == 0 and Mission.machines_of("DeepDrill") == 0,
			"горелок %d" % Mission.machines_of("Burner"))
	ok("клиент: набор главы — лампы, без турели", await wait_until(func() -> bool:
		return player.inv.count_of(IDs.I.LAMP) >= 1 and player.inv.count_of(IDs.I.TURRET) == 0, WAIT))
	ok("клиент: сохранение закрыто", Save.save_blocker() != "")
	var hud: HUD = UI.hud
	if hud != null:
		hud._compute_tracker()
		ok("клиент: HUD — карточка первой цели", hud.card_text != "" and hud.card_need >= 1,
				"«%s» %d/%d" % [hud.card_text, hud.card_have, hud.card_need])
	await barrier("seen")
	ok("клиент: этап сдвинулся от хоста", await wait_until(func() -> bool:
		return m != null and is_instance_valid(m) and m.stage >= 1, WAIT),
			str(m.stage_title) if m != null else "")
	await barrier("night")
	ok("клиент: победа вместе с хостом", await wait_until(func() -> bool:
		return Game.state == Game.State.WON and m.result == Mission.Result.WON, WAIT))
	var es = scene.get("end_screen")
	ok("клиент: экран итога главы", es != null and es.visible and String(es.title) == "ГЛАВА 1 ПРОЙДЕНА",
			String(es.title) if es != null else "")
	ok("клиент: глава отмечена в его профиле", Profile.load_or_create().campaign_done.has(MISSION))
	await barrier("won")
	finish()


func _base_terminal() -> Vector2i:
	for c in World.terminal_chapters.keys():
		if int(World.terminal_chapters[c]) == 0:
			return c
	return World.beacon_cell
