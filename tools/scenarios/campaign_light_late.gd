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
	var mirror: Mirror = World.machines.get(LightLayout.at(LightLayout.CORNER)) as Mirror
	ok("зеркало у поворота", mirror != null)
	if mirror != null:
		# «/» (dir 0) уводит вниз-идущий луч вверх. Один поворот — «\», вниз → вправо.
		mirror.turn()
	if World.beams != null:
		World.beams.mark_dirty()
	var lit: bool = await wait_until(func() -> bool:
		return World.beams.color_at(LightLayout.at(LightLayout.CELLAR)) != 0, 3.0)
	ok("луч дошёл до подвала", lit, "цвет %d" % World.beams.color_at(LightLayout.at(LightLayout.CELLAR)))
	var opened: bool = await wait_until(func() -> bool:
		return mission.result != Mission.Result.RUNNING, 3.0)
	ok("сундук открылся", opened and _note_has("Находка"))
	await _won("mirror", t0)


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
	var bend: Mirror = World.machines.get(LightLayout.at(LightLayout.MIRROR4)) as Mirror
	if bend != null:
		for i in 8:
			bend.turn()
			if World.beams != null:
				World.beams.mark_dirty()
			await wait(0.2)
			var ph: Pharos = World.machines.get(LightLayout.at(LightLayout.PHAROS)) as Pharos
			if ph != null and ph.color == Beams.Y:
				break
	var out_c: int = World.beams.color_at(LightLayout.at(LightLayout.MIX_OUT))
	var pharos_now: Pharos = World.machines.get(LightLayout.at(LightLayout.PHAROS)) as Pharos
	ok("на выходе смесителя жёлтый", out_c == Beams.Y or (pharos_now != null and pharos_now.color == Beams.Y),
			"выход %d, маяк %d" % [out_c, pharos_now.color if pharos_now != null else -1])
	ok("этап маяка", await wait_stage(2, 2.0), str(mission.stage))
	var pharos: Pharos = World.machines.get(LightLayout.at(LightLayout.PHAROS)) as Pharos
	var lit: bool = await wait_until(func() -> bool:
		return pharos != null and pharos.color == Beams.Y and pharos.active, 3.0)
	ok("маяк принял жёлтый", lit, "цвет %d" % (pharos.color if pharos != null else -1))
	ok("этап ночи", await wait_stage(3, 2.0), str(mission.stage))
	drive_threat = true
	var spawned: bool = await wait_until(func() -> bool:
		return get_tree().get_nodes_in_group("phantom").size() >= 1, 12.0)
	ok("два эхо вышли", spawned, "фантомов %d" % get_tree().get_nodes_in_group("phantom").size())
	var echo: Node = _first_echo()
	if echo != null:
		ok("эхо главы 4 бьёт", float(echo.get("dmg")) > 0.0, "урон %.0f" % float(echo.get("dmg")))
	var fled: bool = await wait_until(func() -> bool:
		return _any_flee(), 4.0)
	ok("эхо ушло от жёлтого света", fled)
	var done: bool = await wait_until(func() -> bool:
		return mission.result != Mission.Result.RUNNING, 50.0)
	ok("ночь кончилась победой", done and mission.result == Mission.Result.WON)
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
