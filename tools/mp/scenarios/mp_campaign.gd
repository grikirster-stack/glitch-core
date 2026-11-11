extends "res://tools/mp/scenarios/mp_coop_base.gd"
## mp_campaign (ADR-004): глава кампании по сети.
##
##  * хост запускает «Осаду» до входа клиента (как из «Создать игру» → «Режим»): id главы
##    в Net.session — клиент получает его в приветствии, базу и состояние главы — в снимке;
##  * у клиента: глава-марионетка с этапом и задачами хоста, постройки базы (турели,
##    глубинные буры), набор главы в инвентаре, сохранение закрыто, HUD — карточка первой цели;
##  * хост готовит базу — у клиента этап «Осада»; рассвет — победа у обоих, экран итога
##    главы у клиента и отметка в его профиле.

const MISSION: String = "siege"
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
		return p0 != null and p0.inv.count_of(IDs.I.TURRET) == 1, WAIT))
	await barrier("in")
	await barrier("seen")
	# Подготовка базы — у клиента этап «Осада».
	var bx: int = World.beacon_cell.x
	var row: int = World.beacon_cell.y
	CampaignBase.put("Turret", Vector2i(bx - 5, row))
	var vent: Vector2i = m.get("_vent")
	World.set_tile(vent.x, vent.y, IDs.T.VENT_GRATE)
	CampaignBase.put("Floodlight", Vector2i(bx + 5, row))
	ok("хост: база готова → «Осада»", await wait_until(func() -> bool: return m.stage == 1, WAIT), str(m.goals))
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
		return Game.in_mission() and bool(Game.mission.puppet) and String(Game.mission.stage_title) == "Подготовка", WAIT)
	ok("клиент: марионетка главы, этап «Подготовка»", got)
	await barrier("in")
	var m = Game.mission
	ok("клиент: задачи хоста", m != null and m.goals.size() == 3, str(m.goals) if m != null else "")
	ok("клиент: база главы из снимка — турели и глубинные буры", Mission.machines_of("Turret") >= 3
			and Mission.machines_of("DeepDrill") == 2,
			"турелей %d, буров %d" % [Mission.machines_of("Turret"), Mission.machines_of("DeepDrill")])
	ok("клиент: набор главы — турель, решётка, прожектор", await wait_until(func() -> bool:
		return player.inv.count_of(IDs.I.TURRET) == 1 and player.inv.count_of(IDs.I.VENT_GRATE) == 1, WAIT))
	ok("клиент: сохранение закрыто", Save.save_blocker() != "")
	var hud: HUD = UI.hud
	if hud != null:
		hud._compute_tracker()
		ok("клиент: HUD — карточка первой цели главы 4", hud.card_text != "" and hud.card_need == 4
				and hud.card_icon == IDs.I.TURRET, "«%s» %d/%d" % [hud.card_text, hud.card_have, hud.card_need])
	await barrier("seen")
	ok("клиент: этап «Осада» от хоста", await wait_until(func() -> bool:
		return m != null and is_instance_valid(m) and m.stage == 1 and String(m.stage_title) == "Осада", WAIT),
			str(m.stage_title) if m != null else "")
	await barrier("night")
	ok("клиент: победа вместе с хостом", await wait_until(func() -> bool:
		return Game.state == Game.State.WON and m.result == Mission.Result.WON, WAIT))
	var es = scene.get("end_screen")
	ok("клиент: экран итога главы", es != null and es.visible and String(es.title) == "ГЛАВА 4 ПРОЙДЕНА",
			String(es.title) if es != null else "")
	ok("клиент: глава отмечена в его профиле", Profile.load_or_create().campaign_done.has(MISSION))
	await barrier("won")
	finish()
