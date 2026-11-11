extends "res://tools/scenarios/campaign_common.gd"
## Кампания (ADR-004): все пять глав по порядку. Для каждой — база построена, всё, что
## должно работать, под питанием; этапы переключаются по условиям и только вперёд;
## последняя задача — победа, экран итога и отметка в профиле. Где можно — условия
## выполняет сама игра (бур → лента → плавильня, сборщик, манипулятор, глубинные буры),
## остальное бот делает напрямую. Осада ещё и проваливается: 4 разрушенные постройки.


func run() -> void:
	await _dark_station()
	await _conveyor()
	await _mine()
	await _siege()
	await _siege_lost()
	await _signal()
	await _menu_and_net()
	finish()


func _bx() -> int:
	return World.beacon_cell.x


func _row() -> int:
	return World.beacon_cell.y


## Общая проверка главы на старте.
func _started(id: String) -> bool:
	var m: Mission = start_chapter(id)
	ok("глава «%s» создана" % id, m != null and Game.mission == m)
	if m == null:
		return false
	ok("%s: мир кампании (сид %d)" % [id, Campaign.SEED], World.world_seed == Campaign.SEED)
	ok("%s: первый этап, задачи не выполнены" % id, m.stage == 0 and not m.goals.is_empty()
			and int(m.goals[0]["have"]) < int(m.goals[0]["need"]), str(m.goals))
	ok("%s: сохранение в главе закрыто" % id, Save.save_blocker() == Save.MISSION_NO_SAVE, Save.save_blocker())
	ok("%s: директор угрозы молчит" % id, Threat.scripted() == not m.director)
	return true


func _won(id: String) -> void:
	await wait_until(func() -> bool: return mission.result != Mission.Result.RUNNING, 3.0)
	ok("%s: победа" % id, mission.result == Mission.Result.WON and Game.state == Game.State.WON,
			"итог %d, состояние %d" % [mission.result, Game.state])
	var es = scene.get("end_screen")
	ok("%s: экран итога главы" % id, es != null and es.visible and String(es.title).begins_with("ГЛАВА"),
			String(es.title) if es != null else "")
	ok("%s: отмечена в профиле" % id, Profile.load_or_create().campaign_done.has(id))


# ------------------------------------------------------------------ 1. ТЁМНАЯ СТАНЦИЯ

func _dark_station() -> void:
	if not _started("dark_station"):
		return
	ok("набор главы: 2 пластины на ТЭЦ", player.inv.count_of(IDs.I.IRON_PLATE) == 2)
	player.inv.add(IDs.I.SCRAP, HUD.TUT_SCRAP)
	ok("хлам → этап «ТЭЦ»", await wait_stage(1, 2.0), str(mission.stage))
	player.inv.add(IDs.I.COAL_GEN, 1)
	ok("ТЭЦ в инвентаре → этап «Питание»", await wait_stage(2, 2.0), str(mission.stage))
	var t: Vector2i = World.terminals[0]
	build_at("CoalGen", t + Vector2i(1, 0), {"fuel": 4})
	ok("ТЭЦ даёт ток → этап «Терминал»", await wait_stage(3, 3.0), "выход %.1f" % Game.power_output_total)
	Game.complete_task()
	ok("терминал прочитан → этап «Свет»", await wait_stage(4, 2.0), str(mission.stage))
	ok("свет: задача ещё не выполнена", int(mission.goals[0]["have"]) == 0, str(mission.goals))
	for dx in [5, 6]:
		World.set_tile(_bx() + dx + 10, _row(), IDs.T.LIGHT_CRYSTAL)
	ok("два светокристалла → этап «Первая ночь»", await wait_stage(5, 2.0), str(mission.goals))
	ok("ночь наступила сразу", Game.time_of_day > Balance.DUSK_START, "%.3f" % Game.time_of_day)
	drive_threat = true
	var spawned: bool = await wait_until(func() -> bool:
		return not get_tree().get_nodes_in_group("phantom").is_empty(), 12.0)
	ok("волна эха вышла из вентиляции", spawned, "телеграфов %d" % Threat.pending.size())
	Game.time_of_day = Balance.NIGHT_END - 0.002
	await _won("dark_station")


# ------------------------------------------------------------------ 2. КОНВЕЙЕР

func _conveyor() -> void:
	if not _started("conveyor"):
		return
	var b: Dictionary = mission.get("b")
	ok("цех: бур, плавильня, склад, сборщик, панели", b.has("drill") and b.has("smelter")
			and b.has("store") and b.has("assembler") and b.has("solar1"))
	ok("в линии разрыв", not World.belts.has(mission.get("_gap")))
	await wait(0.6)   # питание раскладывается раз в Balance.POWER_CHECK_INTERVAL
	ok("бур и плавильня под питанием", b["drill"].powered and b["smelter"].powered)
	ok("терминалы станции уже прочитаны", Game.tasks_done == Lore.BASE_TERMINALS, str(Game.tasks_done))
	var gap: Vector2i = mission.get("_gap")
	build_at("Belt", gap, {"dir": 0})
	var ingot: bool = await wait_until(func() -> bool:
		return Mission.chest_has(b["store"], IDs.I.IRON_INGOT) >= 1, 25.0)
	ok("линия сама довезла первый слиток до склада", ingot)
	ok("→ этап «Склад»", await wait_stage(1, 2.0), str(mission.stage))
	(b["store"] as Chest).receive_item(IDs.I.IRON_INGOT, 8)
	ok("8 слитков → этап «Сборщик»", await wait_stage(2, 2.0), str(mission.stage))
	var asm: Assembler = b["assembler"]
	ok("сборщик под питанием (солнце стоит)", asm.powered, "время %.2f" % Game.time_of_day)
	var parts: Chest = b["parts"]
	asm.receive_item(IDs.I.COPPER_PLATE, Mission.chest_has(parts, IDs.I.COPPER_PLATE))
	asm.receive_item(IDs.I.CRYSTAL, Mission.chest_has(parts, IDs.I.CRYSTAL))
	ok("сборщик собрал 2 микросхемы из запчастей → этап «Манипулятор»", await wait_stage(3, 15.0),
			"%d в сундуке" % Mission.chest_has(b["asm_out"], IDs.I.CIRCUIT))
	var st: Vector2i = (b["store"] as MachineBase).cell
	build_at("Inserter", st + Vector2i(1, 0), {"dir": 0})
	build_at("Chest", st + Vector2i(2, 0))
	await _won_within("conveyor", 12.0)


func _won_within(id: String, secs: float) -> void:
	await wait_until(func() -> bool: return mission.result != Mission.Result.RUNNING, secs)
	await _won(id)


# ------------------------------------------------------------------ 3. ШАХТА

func _mine() -> void:
	if not _started("mine"):
		return
	var b: Dictionary = mission.get("b")
	ok("шахта: ТЭЦ, два глубинных бура, сундуки", b.has("gen_mine") and b.has("deep1")
			and b.has("deep2") and b.has("mine_chest") and b.has("mine_supply"))
	await wait(0.6)
	ok("на дне перегруз: 2 бура по 4 на одной ТЭЦ", Game.brownout, "нагрузка %.1f" % Game.power_load_total)
	ok("в сундуке снабжения — ТЭЦ", Mission.chest_has(b["mine_supply"], IDs.I.COAL_GEN) == 1)
	var crystals: int = 0
	for y in range(CampaignBase.floor_row(), CampaignBase.mine_row()):
		for x in range(_bx() + CampaignBase.SHAFT_X0 - 1, _bx() + CampaignBase.SHAFT_X1 + 2):
			if World.get_tile(x, y) == IDs.T.CRYSTAL_ORE:
				crystals += 1
	ok("в стенах ствола 6 кристаллов", crystals == 6, str(crystals))
	stand_at_cell(Vector2i(_bx() + CampaignBase.SHAFT_X0 + 3, CampaignBase.mine_row()))
	ok("герой в штольне → этап «Перегруз»", await wait_stage(1, 2.0), str(mission.stage))
	build_at("CoalGen", Vector2i(_bx() - 4, CampaignBase.mine_row()), {"fuel": 6})
	ok("вторая ТЭЦ → перегруза нет → этап «Добыча»", await wait_stage(2, 3.0), "браун-аут %s" % str(Game.brownout))
	ok("буры сами набрали 20 руды → этап «Кристаллы»", await wait_stage(3, 25.0),
			str(mission.goals))
	player.inv.add(IDs.I.CRYSTAL, 6)
	ok("6 кристаллов → этап «Анализатор»", await wait_stage(4, 2.0), str(mission.stage))
	ok("анализатор у релея под питанием", b["analyzer"].powered)
	var an = b["analyzer"]
	an.receive_item(IDs.I.CRYSTAL, 1)
	an._busy = true
	an._timer = Balance.ANALYZER_PERIOD
	await _won("mine")


# ------------------------------------------------------------------ 4. ОСАДА

func _siege() -> void:
	if not _started("siege"):
		return
	var b: Dictionary = mission.get("b")
	await wait(0.6)
	ok("три турели и прожектор под питанием", mission.call("_powered", "Turret") == 3
			and mission.call("_powered", "Floodlight") == 1,
			"турелей %d, прожекторов %d" % [mission.call("_powered", "Turret"), mission.call("_powered", "Floodlight")])
	ok("перегруза на базе нет", not Game.brownout, _overloaded())
	ok("в наборе турель, решётка, прожектор", player.inv.count_of(IDs.I.TURRET) == 1
			and player.inv.count_of(IDs.I.VENT_GRATE) == 1 and player.inv.count_of(IDs.I.FLOODLIGHT) == 1)
	var t0: float = Game.time_of_day
	await wait(2.0)
	ok("сумерки ждут подготовки", Game.time_of_day <= mission.hold_time + 0.0001 and not Game.is_dusk(),
			"%.3f → %.3f" % [t0, Game.time_of_day])
	build_at("Turret", Vector2i(_bx() - 5, _row()))
	var vent: Vector2i = mission.get("_vent")
	World.set_tile(vent.x, vent.y, IDs.T.VENT_GRATE)
	build_at("Floodlight", Vector2i(_bx() + 5, _row()))
	ok("база готова → этап «Осада»", await wait_stage(1, 3.0), str(mission.goals))
	ok("ночь через пару секунд сумерек", await wait_until(func() -> bool: return Game.is_night(), 4.0),
			"%.3f" % Game.time_of_day)
	drive_threat = true
	var spawned: bool = await wait_until(func() -> bool:
		return not get_tree().get_nodes_in_group("phantom").is_empty(), 15.0)
	ok("вентиляция базы под решёткой — фантомы идут из других", spawned and World.is_vent_sealed(vent))
	ok("подсказка осады считает потери", String(mission.hint).begins_with("Построек потеряно"), mission.hint)
	Game.time_of_day = Balance.NIGHT_END - 0.002
	await _won("siege")


## Перегруженные генераторы: «вид (x,y) нагрузка/выход» — для провала проверки.
func _overloaded() -> String:
	var out: PackedStringArray = PackedStringArray()
	for c in World.machines:
		var m = World.machines[c]
		if m is Generator and m.overloaded():
			out.append("%s %s %.1f/%.1f" % [m.kind, str(c), m.power_load, m.power_output])
	return ", ".join(out)


func _siege_lost() -> void:
	if not _started("siege"):
		return
	mission.hold_time = -1.0
	mission._advance()   # подготовку пропускаем — сразу ночь
	ok("сразу ночь осады", mission.stage == 1 and await wait_until(func() -> bool: return Game.is_night(), 4.0),
			str(mission.stage))
	var victims: Array = []
	for c in World.machines:
		var m = World.machines[c]
		if m is Chest or m is Solar:
			victims.append(m)
	var need: int = int(mission.get_script().get_script_constant_map()["LOST_MAX"])
	ok("есть что разрушить", victims.size() >= need, str(victims.size()))
	for i in mini(need, victims.size()):
		victims[i].destroy()
	await wait_until(func() -> bool: return mission.result != Mission.Result.RUNNING, 2.0)
	ok("4 разрушенные постройки — глава провалена", mission.result == Mission.Result.LOST
			and Game.state == Game.State.DEAD, "%d, потерь %d" % [mission.result, int(mission.get("lost"))])
	var es = scene.get("end_screen")
	ok("экран провала без «следующей главы»", es != null and es.visible and not es.can_next
			and String(es.title) == "ГЛАВА ПРОВАЛЕНА", String(es.title) if es != null else "")


# ------------------------------------------------------------------ 5. СИГНАЛ

func _signal() -> void:
	if not _started("signal"):
		return
	var b: Dictionary = mission.get("b")
	ok("антенна в рецептах сборщика", not DB.recipes_for("assembler").is_empty())
	var core: Chest = b["core_parts"]
	var full: bool = true
	for id_item in Game.relay_req:
		if int(id_item) != IDs.I.RELAY_ANTENNA and Mission.chest_has(core, int(id_item)) < int(Game.relay_req[id_item]):
			full = false
	ok("в сундуке у релея — все детали ядра, кроме антенны", full)
	var asm: Assembler = b["assembler"]
	var parts: Chest = b["parts"]
	for id_item in [IDs.I.COPPER_PLATE, IDs.I.GLASS, IDs.I.CRYSTAL_BLOCK]:
		asm.receive_item(id_item, Mission.chest_has(parts, id_item))
	ok("сборщик собрал антенну → этап «Ядро»", await wait_stage(1, 20.0),
			"антенн в сундуке %d" % Mission.chest_has(b["asm_out"], IDs.I.RELAY_ANTENNA))
	for id_item in Game.relay_req:
		player.inv.add(int(id_item), int(Game.relay_req[id_item]))
	ok("детали сданы — релей запущен", Game.try_finish(player))
	ok("→ этап «Сигнал»: директор угрозы ведёт ночь, отсчёт ×2", await wait_stage(2, 2.0)
			and mission.director and not Threat.scripted() and is_equal_approx(Game.relay_speed, 2.0),
			"этап %d, скорость %.1f" % [mission.stage, Game.relay_speed])
	Game.relay_timer = 0.5
	await wait_until(func() -> bool: return Game.state != Game.State.PLAYING, 3.0)
	await _won("signal")


# ------------------------------------------------------------------ МЕНЮ И СЕТЬ

func _menu_and_net() -> void:
	ok("все главы пройдены — открыты все", Campaign.CHAPTERS.all(func(id: String) -> bool:
		return Campaign.unlocked(id, Profile.load_or_create().campaign_done)))
	ok("без прошлой главы следующая закрыта", not Campaign.unlocked("siege", PackedStringArray(["dark_station"])))
	ok("сессия главы — сид кампании", int(MainMenu.campaign_session("mine")["seed"]) == Campaign.SEED
			and String(MainMenu.campaign_session("mine")["mission"]) == "mine")
	# Марионетка клиента: состояние хоста туда и обратно через кодек MISSION.
	var host_m: Mission = start_chapter("siege")
	var d: Dictionary = NetCodec.decode_mission(NetCodec.encode_mission(host_m.state()))
	end_chapter()
	Campaign.net_apply(d)
	var pup = Game.mission
	ok("клиент: марионетка главы из кадра MISSION", pup != null and pup.puppet and String(pup.id) == "siege"
			and String(pup.stage_title) == "Подготовка" and pup.goals.size() == 3, str(d))
	var hud: HUD = UI.hud
	if hud != null:
		hud._compute_tracker()
		ok("HUD клиента: глава и задачи", hud.tracker_title.begins_with("ГЛАВА 4") and hud.mission_lines.size() == 2,
				hud.tracker_title)
	mission = pup
