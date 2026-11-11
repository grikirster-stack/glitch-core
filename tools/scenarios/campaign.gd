extends "res://tools/scenarios/campaign_common.gd"
## Кампания: одна глава «Тёмная станция» (#170). Главы 2–5 ушли с фабрикой.
## Главы «Свет» — #177, здесь их нет.


func run() -> void:
	await _dark_station()
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
	ok("набор главы: уголь и камень, без пластин", player.inv.count_of(IDs.I.COAL) >= 6
			and player.inv.count_of(IDs.I.IRON_PLATE) == 0)
	player.inv.add(IDs.I.SCRAP, HUD.TUT_SCRAP)
	ok("хлам → этап «Горелка»", await wait_stage(1, 2.0), str(mission.stage))
	player.inv.add(IDs.I.BURNER, 1)
	ok("горелка в инвентаре → этап «Свет базы»", await wait_stage(2, 2.0), str(mission.stage))
	var t: Vector2i = World.terminals[0]
	var burner = build_at("Burner", t + Vector2i(1, 0), {"fuel": 4})
	ok("горящая горелка → этап «Терминал»", burner != null and await wait_stage(3, 3.0),
			str(mission.stage))
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


# Главы 2–5 удалены вместе с файлами миссий (#170). Ниже — меню и сеть.

func _menu_and_net() -> void:
	ok("единственная глава пройдена — открыта", Campaign.unlocked("dark_station",
			Profile.load_or_create().campaign_done))
	ok("неизвестная глава закрыта", not Campaign.unlocked("siege", PackedStringArray(["dark_station"])))
	ok("сессия главы — сид кампании", int(MainMenu.campaign_session("dark_station")["seed"]) == Campaign.SEED
			and String(MainMenu.campaign_session("dark_station")["mission"]) == "dark_station")
	var host_m: Mission = start_chapter("dark_station")
	var d: Dictionary = NetCodec.decode_mission(NetCodec.encode_mission(host_m.state()))
	end_chapter()
	Campaign.net_apply(d)
	var pup = Game.mission
	ok("клиент: марионетка главы из кадра MISSION", pup != null and pup.puppet
			and String(pup.id) == "dark_station" and pup.goals.size() >= 1, str(d))
	var hud: HUD = UI.hud
	if hud != null:
		hud._compute_tracker()
		ok("HUD клиента: карточка первой цели", hud.card_text != "" and hud.card_need >= 1,
				"«%s» %d/%d" % [hud.card_text, hud.card_have, hud.card_need])
	mission = pup


