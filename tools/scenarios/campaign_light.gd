extends "res://tools/scenarios/campaign_common.gd"
## Главы «Свет» 1–2 (ADR-005 § 9, #177). Бот проходит каждую за ≤ 120 с игрового
## времени. Текст каждой цели каждой главы — не длиннее 6 слов на карточке.
## Эхо глав безвредно: к герою подходит, урона нет.


func run() -> void:
	_goal_words()
	await _dig()
	await _fire()
	await _fire_timeout()
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
	var t_night: float = Game.game_time
	# Герой в стороне: не перекрывает ход и не зовёт эхо шумом.
	stand_at_cell(mark + Vector2i(3, 2))
	player.vel = Vector2.ZERO
	await wait(0.4)
	ok("безвредное эхо вышло", Threat.chapter_echo)
	var hp0: float = player.hp
	var fled: bool = await wait_until(func() -> bool:
		return bool(mission.get("_retreated")), 30.0)
	var retreat_s: float = Game.game_time - t_night
	var near: float = float(mission.get("echo_near"))
	print("[глава 2] секунд до отступления %.1f, мин. клеток до луча %.1f" % [retreat_s, near])
	ok("эхо само дошло до луча", near <= 1.5, "мин. клеток %.1f" % near)
	ok("эхо отступило от луча", fled and bool(mission.get("_retreated")),
			"за %.1f с, флаг %s" % [retreat_s, str(mission.get("_retreated"))])
	ok("этап «Сумерки» закрылся", mission.stage > 2 or mission.result != Mission.Result.RUNNING,
			"этап %d" % mission.stage)
	await _won("fire", now() - t0)
	ok("эхо не било героя", player.hp >= hp0 - 0.1, "hp %.0f → %.0f" % [hp0, player.hp])
	Engine.time_scale = 1.0


## Эхо этой главы (безвредное). Чужих фантомов в сценарии нет.
func _chapter_echo() -> Node:
	for n in get_tree().get_nodes_in_group("phantom"):
		if is_instance_valid(n) and bool(n.get("harmless")):
			return n
	return null


## Клеток до красного луча (по центрам). Горелка станции тоже красная —
## её не считаем, эхо идёт к лучу метки. Нет луча — большое число.
func _dist_to_beam(pos: Vector2, mark: Vector2i) -> float:
	if World.beams == null:
		return 999.0
	var best: float = 999.0
	var here: Vector2i = World.world_to_cell(pos)
	for c in World.beams.cells.keys():
		if int(World.beams.cells[c]) & Beams.R == 0:
			continue
		if absi(c.x - mark.x) > 1:
			continue
		var d: float = Vector2(here - c).length()
		if d < best:
			best = d
	return best


## Эхо не пришло к лучу — этап всё равно закрывается, солнце не стоит вечно (#215).
func _fire_timeout() -> void:
	if not _started("fire"):
		return
	var mark: Vector2i = mission.call("mark")
	var burner: Burner = CampaignBase.put("Burner", mark, {"dir": 3, "fuel": 3}) as Burner
	ok("таймаут: горелка уже горит", burner != null and burner.burning())
	# Носик вверх, как ставит игрок. Иначе луч бьёт вправо и этап «Уголь» молчит.
	# Прямой dir из put() носик не перестраивает. turn() помечает луч грязным,
	# мир перестроит его на следующем кадре — ручной rebuild здесь сбивает подпись.
	if burner != null:
		while burner.dir != 3:
			burner.turn()
	await wait(0.3)
	if not await wait_stage(2, 3.0):
		ok("таймаут: этап «Сумерки»", false, "этап %d" % mission.stage)
		return
	# Луч гасим: эхо идёт, но отступить от света не может.
	if burner != null:
		burner.enabled = false
	if World.beams != null:
		World.beams.mark_dirty()
		World.beams.rebuild()
		World._apply_beam_lights()
	Game.time_of_day = Balance.NIGHT_START
	var t0: float = Game.game_time
	Engine.time_scale = 8.0
	var closed: bool = await wait_until(func() -> bool:
		return mission.result != Mission.Result.RUNNING, 40.0)
	Engine.time_scale = 1.0
	var waited: float = Game.game_time - t0
	ok("глава не висит, если эхо не дошло до луча", closed and mission.result == Mission.Result.WON,
			"за %.1f с, итог %d" % [waited, mission.result])
	ok("таймаут этапа конечный", waited < 40.0, "%.1f с" % waited)


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
