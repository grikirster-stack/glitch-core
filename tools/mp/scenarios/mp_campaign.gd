extends "res://tools/mp/scenarios/mp_coop_base.gd"
## mp_campaign (ADR-004, ADR-005 § 9): глава «Копай» по сети.
##
##  * хост запускает «Копай» до входа клиента (как из «Создать игру» → «Режим»): id главы
##    в Net.session — клиент получает его в приветствии, базу и состояние главы — в снимке;
##  * у клиента: глава-марионетка с этапом и задачей хоста, жила угля у базы, набор главы
##    (светокристаллы), сохранение закрыто, HUD — карточка «Накопай 5 угля»;
##  * хост кладёт уголь — у клиента этап «Свет»; лампа у входа — победа у обоих,
##    экран итога главы у клиента и отметка в его профиле.
## Фабрики нет (#170): турели и бура в снимке не появляются.

const MISSION: String = "dig"
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
		return p0 != null and p0.inv.count_of(IDs.I.LAMP) >= 3, WAIT))
	ok("хост: турели и бура нет", Mission.machines_of("Turret") == 0
			and Mission.machines_of("Drill") == 0 and Mission.machines_of("DeepDrill") == 0
			and Mission.machines_of("Belt") == 0 and Mission.machines_of("Smelter") == 0
			and Mission.machines_of("CoalGen") == 0)
	await barrier("in")
	await barrier("seen")
	# Уголь в инвентаре хоста — у клиента этап «Свет».
	player.inv.add(IDs.I.COAL, 5 + int(m.get("_coal0")))
	ok("хост: уголь накопан → «Свет»", await wait_until(func() -> bool: return m.stage == 1, WAIT), str(m.goals))
	await barrier("light")
	var door: Vector2i = CampaignBase.camp_door()
	World.set_tile(door.x, door.y, IDs.T.LIGHT_CRYSTAL)
	ok("хост: лампа у входа — победа", await wait_until(func() -> bool:
		return m.result == Mission.Result.WON and Game.state == Game.State.WON, WAIT))
	await barrier("won")
	finish()


# ------------------------------------------------------------------ КЛИЕНТ

func run_client(_i: int) -> void:
	ok("клиент: id главы в приветствии хоста", String(Net.session.get("mission", "")) == MISSION,
			str(Net.session.get("mission", "")))
	var got: bool = await wait_until(func() -> bool:
		return Game.in_mission() and bool(Game.mission.puppet) and String(Game.mission.stage_title) == "Уголь", WAIT)
	ok("клиент: марионетка главы, этап «Уголь»", got)
	await barrier("in")
	var m = Game.mission
	ok("клиент: задача хоста", m != null and m.goals.size() == 1, str(m.goals) if m != null else "")
	var vein: Vector2i = CampaignBase.coal_spot()
	var coal: int = 0
	for dy in range(CampaignBase.COAL_N):
		if World.get_tile(vein.x, vein.y - 2 + dy) == IDs.T.COAL_ORE:
			coal += 1
	ok("клиент: жила угля из снимка", coal == CampaignBase.COAL_N, "клеток %d" % coal)
	ok("клиент: база без фабрики", Mission.machines_of("Turret") == 0
			and Mission.machines_of("Drill") == 0 and Mission.machines_of("DeepDrill") == 0
			and Mission.machines_of("Belt") == 0 and Mission.machines_of("Smelter") == 0
			and Mission.machines_of("CoalGen") == 0)
	ok("клиент: набор главы — светокристаллы, без турели", await wait_until(func() -> bool:
		return player.inv.count_of(IDs.I.LAMP) >= 3 and player.inv.count_of(IDs.I.TURRET) == 0, WAIT))
	ok("клиент: сохранение закрыто", Save.save_blocker() != "")
	var hud: HUD = UI.hud
	if hud != null:
		hud._compute_tracker()
		ok("клиент: HUD — карточка «Накопай 5 угля»", hud.card_text == "Накопай 5 угля"
				and hud.card_need == 5 and hud.card_icon == IDs.I.COAL,
				"«%s» %d/%d" % [hud.card_text, hud.card_have, hud.card_need])
	await barrier("seen")
	ok("клиент: этап «Свет» от хоста", await wait_until(func() -> bool:
		return m != null and is_instance_valid(m) and m.stage == 1 and String(m.stage_title) == "Свет", WAIT),
			str(m.stage_title) if m != null else "")
	await barrier("light")
	ok("клиент: победа вместе с хостом", await wait_until(func() -> bool:
		return Game.state == Game.State.WON and m.result == Mission.Result.WON, WAIT))
	var es = scene.get("end_screen")
	ok("клиент: экран итога главы", es != null and es.visible and String(es.title) == "ГЛАВА 1 ПРОЙДЕНА",
			String(es.title) if es != null else "")
	ok("клиент: глава отмечена в его профиле", Profile.load_or_create().campaign_done.has(MISSION))
	await barrier("won")
	finish()
