extends "res://tools/scenarios/campaign_common.gd"
## Главы «Свет» 3–4 (ADR-005 § 9, #178): «Зеркало» и «Цвета».
##
## Бот проходит каждую за ≤ 120 с игрового времени. Слова на карточке — ≤ 6.
## Главы 1–2 (#177) живут в campaign_light.gd; этот файл их не трогает.


const LIMIT: float = 120.0


func run() -> void:
	await _mirror()
	await _colors()
	_words()
	finish()


func _bx() -> int:
	return World.beacon_cell.x


func _started(id: String) -> bool:
	var m: Mission = start_chapter(id)
	ok("глава «%s» создана" % id, m != null and Game.mission == m)
	if m == null:
		return false
	ok("%s: мир кампании (сид %d)" % [id, Campaign.SEED], World.world_seed == Campaign.SEED)
	ok("%s: директор молчит" % id, not m.director and Threat.scripted())
	ok("%s: ствол шахты на месте" % id, _shaft_stands())
	return true


func _shaft_stands() -> bool:
	var c: Vector2i = Vector2i(_bx() + CampaignBase.SHAFT_X0, CampaignBase.floor_row())
	return World.get_tile_v(c) == IDs.T.AIR or World.get_tile_v(c) == IDs.T.STEEL


func _won(id: String, t0: float) -> void:
	var dt: float = now() - t0
	ok("%s: пройдена за ≤ 120 с" % id, mission.result == Mission.Result.WON and dt <= LIMIT,
			"итог %d за %.1f с" % [mission.result, dt])
	print("  [замер] %s: %.1f с игрового времени" % [id, dt])
	ok("%s: в профиле" % id, Profile.load_or_create().campaign_done.has(id))


# ------------------------------------------------------------------ 3. ЗЕРКАЛО

func _mirror() -> void:
	var t0: float = now()
	if not _started("mirror"):
		return
	ok("набор: два зеркала", player.inv.count_of(IDs.I.MIRROR) == 2)
	var burner: Burner = World.machines.get(LightLayout.at(LightLayout.BURNER)) as Burner
	ok("горелка лагеря горит", burner != null and burner.burning() and burner.color == Beams.R)
	ok("подвал ещё тёмный", World.beams.color_at(LightLayout.at(LightLayout.CELLAR)) == 0)
	var corner: Vector2i = LightLayout.at(LightLayout.CORNER)
	ok("на повороте зеркала нет", not World.machines.has(corner), str(corner))
	# Один тап по уже верному зеркалу главу не закрывает: его ещё нет.
	var early: bool = await wait_until(func() -> bool:
		return mission.result != Mission.Result.RUNNING, 0.6)
	ok("одним тапом по готовому зеркалу не закрывается", not early and mission.stage == 0,
			"этап %d, итог %d" % [mission.stage, mission.result])
	# Первое действие: поставить зеркало. Грань после постановки — 0, «/»:
	# вниз-идущий луч уходит вверх, в сталь, подвал остаётся тёмным.
	_place("Mirror", corner, 0)
	var placed: bool = await wait_until(func() -> bool:
		return mission.stage >= 1, 2.0)
	ok("зеркало поставлено, этап луча", placed, str(mission.stage))
	ok("промах: подвал ещё тёмный", World.beams.color_at(LightLayout.at(LightLayout.CELLAR)) == 0)
	var mirror: Mirror = World.machines.get(corner) as Mirror
	ok("неверная грань не закрывает главу", mirror != null and mission.result == Mission.Result.RUNNING)
	# Второе действие: повернуть. dir 0 → 4 (диагональ, всё ещё мимо) → 1 «\».
	var taps: int = 0
	if mirror != null:
		while (mirror.dir & 7) != 1 and taps < 8:
			mirror.turn()
			taps += 1
			if World.beams != null:
				World.beams.mark_dirty()
			await await_frame()
	ok("поворот — второй тап, не один", taps >= 1, "тапов %d" % taps)
	print("  [замер] зеркало: поставлено + %d поворот(ов)" % taps)
	if World.beams != null:
		World.beams.mark_dirty()
	var lit: bool = await wait_until(func() -> bool:
		return World.beams.color_at(LightLayout.at(LightLayout.CELLAR)) != 0, 3.0)
	ok("луч дошёл до подвала", lit, "цвет %d, грань %d" % [
			World.beams.color_at(LightLayout.at(LightLayout.CELLAR)),
			mirror.dir if mirror != null else -1])
	var opened: bool = await wait_until(func() -> bool:
		return mission.result != Mission.Result.RUNNING, 3.0)
	ok("сундук открылся", opened and _note_has("Находка"))
	await _won("mirror", t0)


## Как игрок: place_machine, не CampaignBase.put. put помечает постройку
## неразборной и для зеркала на луче этого хватает, чтобы луч оборвался.
func _place(kind: String, c: Vector2i, dir: int) -> void:
	if World.get_tile_v(c) != IDs.T.AIR and not World.machines.has(c):
		World.set_tile(c.x, c.y, IDs.T.AIR)
	if not MachineBase.place_machine(kind, c):
		return
	var m: MachineBase = World.machines.get(c)
	if m != null and "dir" in m:
		m.set("dir", dir)


func _note_has(part: String) -> bool:
	# Уведомление живёт в HUD.notes: [{text, color, t, icon}].
	var hud = UI.hud
	if hud == null:
		return false
	for n in hud.notes:
		if String(n.get("text", "")).find(part) >= 0:
			return true
	return false


# ------------------------------------------------------------------ 4. ЦВЕТА

func _colors() -> void:
	var t0: float = now()
	if not _started("colors"):
		return
	ok("набор: 4 медной руды", player.inv.count_of(IDs.I.COPPER_ORE) == 4)
	var red: Burner = World.machines.get(LightLayout.at(LightLayout.BURNER_R)) as Burner
	ok("красная горелка горит", red != null and red.burning() and red.color == Beams.R)
	var green: Burner = World.machines.get(LightLayout.at(LightLayout.BURNER_G)) as Burner
	ok("вторая горелка пустая", green != null and not green.burning())
	if green != null:
		player.inv.selected = 0
		green.interact(player)
	var got_g: bool = await wait_until(func() -> bool:
		return green != null and green.burning() and green.color == Beams.G, 2.0)
	ok("медь дала зелёный", got_g, "цвет %d" % (green.color if green != null else -1))
	ok("этап смеси", await wait_stage(1, 2.0), str(mission.stage))
	# Смесь не закрывается маяком: пока зеркало смотрит мимо, этап открыт.
	ok("смесь не закрылась сама", mission.stage == 1, str(mission.stage))
	var bend: Mirror = World.machines.get(LightLayout.at(LightLayout.MIRROR4)) as Mirror
	var mix_taps: int = 0
	if bend != null:
		for i in 8:
			bend.turn()
			mix_taps += 1
			if World.beams != null:
				World.beams.mark_dirty()
			await wait(0.2)
			if World.beams.color_at(LightLayout.at(LightLayout.MIX_OUT)) == Beams.Y:
				break
	print("  [замер] смесь: %d тап(ов) по зеркалу" % mix_taps)
	var out_c: int = World.beams.color_at(LightLayout.at(LightLayout.MIX_OUT))
	ok("на выходе смесителя жёлтый", out_c == Beams.Y, "выход %d" % out_c)
	ok("этап маяка", await wait_stage(2, 2.0), str(mission.stage))
	var pharos: Pharos = World.machines.get(LightLayout.at(LightLayout.PHAROS)) as Pharos
	var lit: bool = await wait_until(func() -> bool:
		return pharos != null and pharos.color == Beams.Y and pharos.active, 3.0)
	ok("маяк принял жёлтый", lit, "цвет %d" % (pharos.color if pharos != null else -1))
	# Свой этап, не следствие смеси: прожектор гасится тапом, луч остаётся.
	ok("прожектор ещё горит", pharos != null and pharos._lit and not pharos.lamp_off)
	if pharos != null:
		pharos.interact(player)
	var doused: bool = await wait_until(func() -> bool:
		return pharos != null and pharos.lamp_off and not pharos._lit, 1.5)
	ok("тап погасил прожектор", doused, "погашен %s" % str(pharos.lamp_off if pharos != null else false))
	ok("этап ночи", await wait_stage(3, 2.0), str(mission.stage))
	# Герой у входа, не в клетке эха: удар должен дойти, а не случиться на спавне.
	var spot: Vector2i = mission.call("_echo_spot")
	stand_at_cell(spot + Vector2i(5, 0))
	player.invuln = 0.0
	player.hp = Player.MAX_HP
	var spawned: bool = await wait_until(func() -> bool:
		return _first_echo() != null, 8.0)
	ok("эхо вышло", spawned)
	var echo: Node = _first_echo()
	if echo != null:
		ok("эхо главы 4 бьёт", float(echo.get("dmg")) > 0.0, "урон %.0f" % float(echo.get("dmg")))
	# Стоим. Эхо идёт само и бьёт — ночь не проходит ожиданием.
	var struck: bool = await wait_until(func() -> bool:
		return bool(mission.get("echo_struck")) or player.hp < Player.MAX_HP - 0.5, 12.0)
	var strike_s: float = float(mission.get("strike_at"))
	print("  [замер] эхо ударило через %.1f с ночи, hp %.0f" % [strike_s, player.hp])
	ok("эхо дошло и ударило", struck, "hp %.0f, флаг %s" % [player.hp, str(mission.get("echo_struck"))])
	# Второе действие ночи: зажечь прожектор. Эхо отступает, глава не валится.
	player.invuln = 1.0e9
	if pharos != null and pharos.lamp_off:
		pharos.interact(player)
	var lit_back: bool = await wait_until(func() -> bool:
		return pharos != null and not pharos.lamp_off and pharos._lit, 1.5)
	ok("тап зажёг прожектор", lit_back)
	var fled: bool = await wait_until(func() -> bool:
		return _any_flee() or bool(mission.get("lamp_lit")), 4.0)
	ok("эхо отступило от прожектора", fled)
	Engine.time_scale = 8.0
	var t_night: float = Game.game_time
	var done: bool = false
	while Game.game_time - t_night < 50.0:
		if mission.result != Mission.Result.RUNNING:
			done = true
			break
		await get_tree().process_frame
	Engine.time_scale = 1.0
	ok("ночь кончилась победой, не ожиданием", done and mission.result == Mission.Result.WON
			and (bool(mission.get("echo_struck")) or bool(mission.get("lamp_lit"))),
			"итог %d" % mission.result)
	await _won("colors", t0)


func _first_echo() -> Node:
	for p in get_tree().get_nodes_in_group("phantom"):
		if is_instance_valid(p) and String(p.get("kind")) == "echo":
			return p
	return null


func _any_flee() -> bool:
	for p in get_tree().get_nodes_in_group("phantom"):
		if is_instance_valid(p) and int(p.get("state")) == Phantom.St.FLEE:
			return true
	return false


# ------------------------------------------------------------------ СЛОВА

## Общая проверка карточки. Главы 1–2 (#177) вызовут её же из своего файла.
func _words() -> void:
	var long: Array = []
	for id in ["mirror", "colors"]:
		var m: Mission = Campaign.create(id)
		if m == null:
			long.append(id)
			continue
		for st in m.stages():
			var hint: String = String(st.get("hint", ""))
			if hint.find("·") >= 0:
				long.append("%s hint «%s»" % [id, hint])
			for g in st.get("goals", []):
				var words: PackedStringArray = String(g[0]).split(" ", false)
				if words.size() > 6 or g.size() < 4:
					long.append("%s: «%s» (%d)" % [id, String(g[0]), words.size()])
			var say: Array = st.get("say", [])
			if say.size() > 2:
				long.append("%s say %d" % [id, say.size()])
		m.free()
	ok("карточка ≤ 6 слов, hint без «·», say ≤ 2", long.is_empty(), ", ".join(long))
