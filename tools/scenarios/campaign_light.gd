extends "res://tools/scenarios/campaign_common.gd"
## Главы «Свет» 1–2 (ADR-005 § 9, #177). Бот проходит каждую за ≤ 120 с игрового
## времени. Текст каждой цели каждой главы — не длиннее 6 слов на карточке.
## Эхо глав безвредно: к герою подходит, урона нет.


func run() -> void:
	_goal_words()
	await _dig()
	await _fire()
	finish()


## Общая проверка глав G1–G3: текст цели на карточке ≤ 6 слов.
func _goal_words() -> void:
	var long: Array = []
	for id in Campaign.CHAPTERS:
		var m: Mission = Campaign.create(id)
		if m == null:
			long.append(id)
			continue
		for st in m.stages():
			for g in st.get("goals", []):
				var words: String = HUD._card_words(String(g[0]), HUD.CARD_WORDS)
				if words.split(" ", false).size() > 6:
					long.append("%s: «%s»" % [id, words])
			var hint: String = String(st.get("hint", ""))
			if hint.find("·") >= 0:
				long.append("%s: hint «%s»" % [id, hint])
			var say: Array = st.get("say", [])
			if say.size() > 2:
				long.append("%s: say %d" % [id, say.size()])
		m.free()
	ok("текст каждой цели ≤ 6 слов, hint без «·», say ≤ 2", long.is_empty(), ", ".join(long))


func _started(id: String) -> bool:
	var m: Mission = start_chapter(id)
	ok("глава «%s» создана" % id, m != null and Game.mission == m)
	if m == null:
		return false
	ok("%s: мир кампании (сид %d)" % [id, Campaign.SEED], World.world_seed == Campaign.SEED)
	ok("%s: директор молчит" % id, Threat.scripted())
	ok("%s: сохранение закрыто" % id, Save.save_blocker() == Save.MISSION_NO_SAVE)
	return true


func _won(id: String, secs: float) -> void:
	await wait_until(func() -> bool: return mission.result != Mission.Result.RUNNING, 4.0)
	ok("%s: победа за %.0f с (лимит 120)" % [id, secs],
			mission.result == Mission.Result.WON and Game.state == Game.State.WON and secs <= 120.0,
			"итог %d, %.1f с" % [mission.result, secs])
	var es = scene.get("end_screen")
	ok("%s: экран итога" % id, es != null and es.visible and String(es.title).begins_with("ГЛАВА"),
			String(es.title) if es != null else "")
	ok("%s: отмечена в профиле" % id, Profile.load_or_create().campaign_done.has(id))


# ------------------------------------------------------------------ 1. КОПАЙ

func _dig() -> void:
	if not _started("dig"):
		return
	var t0: float = now()
	var vein: Vector2i = CampaignBase.coal_spot()
	var coal_n: int = 0
	for dy in range(CampaignBase.COAL_N):
		if World.get_tile(vein.x, vein.y - 2 + dy) == IDs.T.COAL_ORE:
			coal_n += 1
	ok("жила: 6 клеток угля в 10 от базы", coal_n == 6
			and absi(vein.x - World.beacon_cell.x) == 10, "клеток %d, dx %d" % [coal_n,
			vein.x - World.beacon_cell.x])
	# Герой в ходе, лицом к жиле. Дальняя клетка — за стеной угля.
	stand_at_cell(vein + Vector2i(1, -1))
	player.facing = -1
	aim(World.cell_to_world(vein + Vector2i(-1, 0)))
	press_mouse(MOUSE_BUTTON_LEFT)
	await wait(0.15)
	var crossed: bool = player.dig_denied_t > 0.0 and player.dig_denied_cell == vein + Vector2i(-1, 0)
	ok("клетка за стеной — красный крест", crossed or player.dig_cell != vein + Vector2i(-1, 0),
			"dig %s denied %s t %.2f" % [str(player.dig_cell), str(player.dig_denied_cell), player.dig_denied_t])
	release_mouse(MOUSE_BUTTON_LEFT)
	# Копаем верхние клетки жилы, пока не наберём 5 угля.
	var dug: int = 0
	for dy in range(CampaignBase.COAL_N):
		if player.inv.count_of(IDs.I.COAL) >= 5:
			break
		var c: Vector2i = Vector2i(vein.x, vein.y - 2 + dy)
		stand_at_cell(c + Vector2i(1, 0))
		player.facing = -1
		aim(World.cell_to_world(c))
		press_mouse(MOUSE_BUTTON_LEFT)
		var broke: bool = await wait_until(func() -> bool: return World.get_tile_v(c) == IDs.T.AIR, 4.0)
		release_mouse(MOUSE_BUTTON_LEFT)
		if broke:
			dug += 1
			_pick_near(c)
	ok("накопано 5 угля", player.inv.count_of(IDs.I.COAL) >= 5, "уголь %d, клеток %d" % [
			player.inv.count_of(IDs.I.COAL), dug])
	# Карточку читаем до победы: последний этап закрывается в том же кадре,
	# и goals уже пуст, когда wait_stage вернулся.
	var card_box: Array = [""]
	var lit: bool = await wait_until(func() -> bool:
		if mission.stage < 1 or mission.goals.is_empty():
			return false
		var raw: String = String(mission.goals[0].get("text", ""))
		if raw != "":
			card_box[0] = raw
		return true, 4.0)
	var saw_card: String = String(card_box[0])
	ok("→ этап «Свет»", lit, str(mission.stage))
	ok("сумерки наступили", Game.is_dusk() or Game.is_night(), "%.3f" % Game.time_of_day)
	var door: Vector2i = CampaignBase.camp_door()
	ok("карточка «Поставь свет у входа», 4 слова", saw_card == "Поставь свет у входа"
			and saw_card.split(" ", false).size() == 4, "«%s»" % saw_card)
	# Эхо выходит с ночью и за секунды уходит в глубину: бот читает флаг главы.
	ok("безвредное эхо вышло к входу", bool(mission.get("echo_out")))
	# Лампа у входа. Эхо безвредно: урона нет.
	var hp0: float = player.hp
	World.set_tile(door.x, door.y, IDs.T.AIR)
	stand_at_cell(door + Vector2i(1, 0))
	player.inv.selected = _slot(IDs.I.LAMP)
	aim(World.cell_to_world(door))
	press_mouse(MOUSE_BUTTON_RIGHT)
	await wait(0.3)
	release_mouse(MOUSE_BUTTON_RIGHT)
	ok("светокристалл у входа", World.get_tile_v(door) == IDs.T.LIGHT_CRYSTAL, str(door))
	await _won("dig", now() - t0)
	ok("эхо не било героя", player.hp >= hp0 - 0.1, "hp %.0f → %.0f" % [hp0, player.hp])


# ------------------------------------------------------------------ 2. ОГОНЬ

func _fire() -> void:
	if not _started("fire"):
		return
	var t0: float = now()
	ok("набор: горелка и 3 угля", player.inv.count_of(IDs.I.BURNER) == 1
			and player.inv.count_of(IDs.I.COAL) == 3)
	var mark: Vector2i = mission.call("mark")
	ok("метка на полу пуста", World.get_tile_v(mark) == IDs.T.AIR, str(mark))
	# Рядом, не вплотную: тело героя закрывает клетку, и ПКМ ничего не ставит.
	stand_at_cell(mark + Vector2i(2, 1))
	player.inv.selected = _slot(IDs.I.BURNER)
	aim(World.cell_to_world(mark))
	press_mouse(MOUSE_BUTTON_RIGHT)
	await wait(0.35)
	release_mouse(MOUSE_BUTTON_RIGHT)
	var burner: Burner = World.machines.get(mark) as Burner
	ok("горелка на метке → этап «Уголь»", burner != null and await wait_stage(1, 2.0), str(mission.stage))
	if burner == null:
		return
	# Носик вверх: вправо на +3 стоит лампа базы, луч упрётся в неё.
	while burner.dir != 3:
		burner.turn()
	player.inv.selected = _slot(IDs.I.COAL)
	aim(burner.global_position)
	hold(KEY_E)
	await wait(0.4)
	release(KEY_E)
	if World.beams != null:
		World.beams.mark_dirty()
		World.beams.rebuild()
		World._apply_beam_lights()
	var span: int = 0
	for k in range(1, 13):
		if World.beams != null and World.beams.color_at(mark + Vector2i(0, -k)) == Beams.R:
			span += 1
	ok("красный луч через лагерь", burner.burning() and span >= 4, "клеток %d, горит %s" % [
			span, str(burner.burning())])
	ok("→ этап «Сумерки»", await wait_stage(2, 2.0), str(mission.stage))
	var t_coal: float = Game.game_time
	drive_threat = true
	# До сумерек около 40 с игрового времени. Часы игры идут по process-кадрам.
	Engine.time_scale = 8.0
	var dusk: bool = await wait_until(func() -> bool: return Game.is_dusk() or Game.is_night(), 50.0)
	var waited: float = Game.game_time - t_coal
	# Эхо выходит ночью: днём оно само уходит в глубину. До ночи ещё ~14 с.
	if not Game.is_night():
		await wait_until(func() -> bool: return Game.is_night(), 20.0)
	Engine.time_scale = 1.0
	ok("сумерки через ~40 с", dusk and waited >= 30.0 and waited <= 55.0, "%.1f с" % waited)
	await wait(0.4)
	ok("безвредное эхо вышло", Threat.chapter_echo)
	var hp0: float = player.hp
	# Эхо само боится света луча. Если оно ещё в мире и не бежит — ставим на луч.
	var echo: Node = null
	var nodes: Array = get_tree().get_nodes_in_group("phantom")
	if not nodes.is_empty():
		echo = nodes[0]
	if echo != null and is_instance_valid(echo) and int(echo.state) != Phantom.St.FLEE:
		echo.global_position = World.cell_to_world(mark + Vector2i(0, -2))
	var fled: bool = await wait_until(func() -> bool:
		return bool(mission.get("_retreated")) or (
				echo != null and is_instance_valid(echo) and int(echo.state) == Phantom.St.FLEE), 6.0)
	ok("эхо отступило от луча", fled, "флаг %s" % str(mission.get("_retreated")))
	await _won("fire", now() - t0)
	ok("эхо не било героя", player.hp >= hp0 - 0.1, "hp %.0f → %.0f" % [hp0, player.hp])
	Engine.time_scale = 1.0


## Текст, который карточка покажет по текущим целям главы (HUD режет до 6 слов).
func _card_of(m: Mission) -> String:
	if m == null:
		return ""
	for g in m.goals:
		var have: int = int(g.get("have", 0))
		var need: int = int(g.get("need", 1))
		if have < need:
			return HUD._card_words(String(g.get("text", "")), HUD.CARD_WORDS)
	if m.goals.is_empty():
		return ""
	return HUD._card_words(String(m.goals[0].get("text", "")), HUD.CARD_WORDS)


func _slot(id: int) -> int:
	for i in player.inv.slots.size():
		if player.inv.slots[i].id == id and player.inv.slots[i].count > 0:
			return i
	return 0


## Поднять выпавшее рядом: бот не бегает за каждой крошкой.
func _pick_near(c: Vector2i) -> void:
	var spot: Vector2 = World.cell_to_world(c)
	for n in scene.get_children():
		if n is ItemEntity and n.global_position.distance_to(spot) < 48.0:
			n.global_position = player.global_position
	await wait(0.3)
