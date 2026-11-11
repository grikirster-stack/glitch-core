extends "res://tools/scenarios/campaign_common.gd"
## Главы «Свет» 5–6 (ADR-005 § 9, #179): «Солнце» и «Радуга».
##
## Бот проходит каждую за ≤ 120 с игрового времени. Слова на карточке — ≤ 6.
## Главы 1–4 (#177, #178) живут в своих файлах; этот их не трогает.
## Когда те главы уже в CHAPTERS, здесь же проверка «шесть подряд ≤ 10 минут».


const LIMIT: float = 120.0
const SIX: float = 600.0


func run() -> void:
	var t5: float = await _sun()
	var t6: float = await _rainbow()
	_words()
	_six(t5 + t6)
	finish()


func _started(id: String) -> bool:
	var m: Mission = start_chapter(id)
	ok("глава «%s» создана" % id, m != null and Game.mission == m)
	if m == null:
		return false
	ok("%s: мир кампании (сид %d)" % [id, Campaign.SEED], World.world_seed == Campaign.SEED)
	ok("%s: ствол шахты на месте" % id, _shaft_stands())
	return true


func _shaft_stands() -> bool:
	var c: Vector2i = LightLate.at(Vector2i(CampaignBase.SHAFT_X0, 1))
	return World.get_tile_v(c) == IDs.T.AIR


func _won(id: String, t0: float) -> float:
	# Часы главы — Game.game_time: по ним идут ночь и удержание. now() — физика, она отстаёт.
	var dt: float = Game.game_time - t0
	ok("%s: пройдена за ≤ 120 с" % id, mission.result == Mission.Result.WON and dt <= LIMIT,
			"итог %d за %.1f с" % [mission.result, dt])
	print("  [замер] %s: %.1f с" % [id, dt])
	ok("%s: в профиле" % id, Profile.load_or_create().campaign_done.has(id))
	return dt


# ------------------------------------------------------------------ 5. СОЛНЦЕ

func _sun() -> float:
	if not _started("sun"):
		return 0.0
	var t0: float = Game.game_time
	ok("солнце: директор молчит", not mission.director and Threat.scripted())
	ok("набор: коллектор, призма, накопитель, 2 зеркала",
			player.inv.count_of(IDs.I.COLLECTOR) == 1
			and player.inv.count_of(IDs.I.PRISM) == 1
			and player.inv.count_of(IDs.I.ACCUMULATOR) == 1
			and player.inv.count_of(IDs.I.MIRROR) == 2)
	var spot: Vector2i = LightLate.at(LightLate.COLLECTOR)
	ok("площадка коллектора пуста", World.get_tile_v(spot) == IDs.T.AIR, str(spot))
	# Носик влево: белый по ряду y−1 до зеркала над маяком.
	_place("Collector", spot, 2)
	var col: Collector = World.machines.get(spot) as Collector
	if col != null:
		col.dir = 2
		col._check_sky()
	_flush()
	var step: Vector2i = spot + Vector2i(-1, 0)
	var white: bool = await wait_until(func() -> bool:
		return col != null and col.emitting() and World.beams.color_at(step) == Beams.W, 3.0)
	ok("белый луч из коллектора", white, "небо %s, цвет %d" % [
			str(col.sky_open) if col != null else "?",
			World.beams.color_at(step) if World.beams != null else -1])
	ok("этап ствола", await wait_stage(1, 2.0), str(mission.stage))
	# Коллектор бьёт влево (вход 2). dir 0 «/»: столбец 2 = 1, то есть вниз, в маяк.
	var bend: Vector2i = LightLate.at(LightLate.BEND)
	_air(bend)
	_place("Mirror", bend, 0)
	var mir: Mirror = World.machines.get(bend) as Mirror
	if mir != null:
		mir.dir = 0
	var tower: Vector2i = LightLate.at(LightLate.PHAROS)
	for y in range(bend.y + 1, tower.y):
		_air(Vector2i(bend.x, y))
	_flush()
	var shown: bool = await wait_until(func() -> bool:
		return _pharos_color() == Beams.W and _crystals_open() >= 5, 6.0)
	ok("белый открыл ≥ 5 клеток кристалла", shown,
			"маяк %d, клеток %d" % [_pharos_color(), _crystals_open()])
	ok("этап копки", await wait_stage(2, 2.0), str(mission.stage))
	_dig_crystals(3)
	ok("накопано 3 кристалла", player.inv.count_of(IDs.I.CRYSTAL) >= 3,
			"кристаллов %d" % player.inv.count_of(IDs.I.CRYSTAL))
	ok("этап запаса", await wait_stage(3, 2.0), str(mission.stage))
	var burner: Burner = World.machines.get(LightLate.at(LightLate.BURNER)) as Burner
	var acc: Accumulator = World.machines.get(LightLate.at(LightLate.ACCUM)) as Accumulator
	ok("призма, горелка и накопитель стоят", burner != null and acc != null
			and World.machines.has(LightLate.at(LightLate.PRISM)))
	if burner != null:
		player.inv.selected = _slot(IDs.I.CRYSTAL)
		burner.add_fuel(IDs.I.CRYSTAL, 1)
		player.inv.remove_id(IDs.I.CRYSTAL, 1)
	var blue: bool = await wait_until(func() -> bool:
		return burner != null and burner.burning() and burner.color == Beams.B, 2.0)
	ok("кристалл дал синий", blue, "цвет %d" % (burner.color if burner != null else -1))
	_flush()
	# Запас растёт в _process машин. Ждём по Game.game_time: часы сценария отстают.
	Engine.time_scale = 8.0
	var t_store: float = Game.game_time
	var stored: bool = false
	while Game.game_time - t_store < 40.0:
		if acc != null and acc.color == Beams.B and acc.stored >= LightLate.STORE_NEED:
			stored = true
			break
		await get_tree().process_frame
	Engine.time_scale = 1.0
	ok("накопитель держит ≥ 30 с синего", stored, "запас %.1f, цвет %d" % [
			acc.stored if acc != null else -1.0, acc.color if acc != null else -1])
	ok("этап ночи", await wait_stage(4, 2.0), str(mission.stage))
	ok("ночь наступила", Game.is_night(), "%.3f" % Game.time_of_day)
	drive_threat = true
	var spawned: bool = await wait_until(func() -> bool:
		return _burrower() != null, 8.0)
	ok("копатель вышел", spawned)
	var burr: Node = _burrower()
	var far: bool = true
	if burr != null:
		var ph: Pharos = World.machines.get(LightLate.at(LightLate.PHAROS)) as Pharos
		# Ставим у кромки мороза, справа от маяка: скорость падает, до построек не доходит.
		# Радиус синего — 4 клетки. Ставим внутри, иначе мороз не берёт.
		burr.global_position = World.cell_to_world(LightLate.at(LightLate.PHAROS) + Vector2i(3, 0))
		await wait(0.4)
		var slow: float = World.slow_factor_at(burr.global_position)
		ok("синий маяк морозит копателя", ph != null and ph.color == Beams.B and slow < 0.99,
				"цвет %d, скорость ×%.2f" % [ph.color if ph != null else -1, slow])
		var base_pos: Vector2 = World.cell_to_world(World.beacon_cell)
		far = burr.global_position.distance_to(base_pos) > 48.0
	# Ночь главы считает _process. Ждём по Game.game_time, не по физике.
	Engine.time_scale = 6.0
	var t_night: float = Game.game_time
	var done: bool = false
	while Game.game_time - t_night < 80.0:
		if mission.result != Mission.Result.RUNNING:
			done = true
			break
		await get_tree().process_frame
	Engine.time_scale = 1.0
	ok("ночь 60 с — победа, постройки целы", done and mission.result == Mission.Result.WON, str(mission.result))
	ok("копатель не дошёл до построек", far)
	return await _won("sun", t0)


# ------------------------------------------------------------------ 6. РАДУГА

func _rainbow() -> float:
	if not _started("rainbow"):
		return 0.0
	var t0: float = Game.game_time
	ok("радуга: директор включён", mission.director and not Threat.scripted())
	var chest: Chest = World.machines.get(LightLate.at(LightLate.CHEST)) as Chest
	ok("сундук: уголь 12, медь 12, кристалл 8, ядро", chest != null
			and Mission.chest_has(chest, IDs.I.COAL) >= 12
			and Mission.chest_has(chest, IDs.I.COPPER_ORE) >= 12
			and Mission.chest_has(chest, IDs.I.CRYSTAL) >= 8
			and Mission.chest_has(chest, IDs.I.RAINBOW_CORE) >= 1)
	_take_core(chest)
	var core: Vector2i = LightLate.at(LightLate.CORE)
	if World.machines.has(core):
		var old = World.machines[core]
		World.machines.erase(core)
		if is_instance_valid(old):
			old.free()
	# Пол под ядром — сталь: копатель ночи не роет его, пока бот зажигает дуги.
	var floor: Vector2i = core + Vector2i(0, 1)
	if World.get_tile_v(floor) != IDs.T.STEEL:
		World.set_tile(floor.x, floor.y, IDs.T.STEEL)
	_air(core)
	var placed: bool = MachineBase.place_machine("RainbowCore", core)
	ok("ядро поставлено", placed and Game.core_placed(), "клетка %s" % str(core))
	ok("этап дуг", await wait_stage(1, 2.0), str(mission.stage))
	var hud: HUD = UI.hud
	if hud != null:
		hud._compute_tracker()
		ok("карточка «Зажги семь дуг» и три смеси", hud.card_text == "Зажги семь дуг" and hud.card_mix,
				"«%s» mix %s" % [hud.card_text, str(hud.card_mix)])
	await _light_seven(core)
	ok("семь дуг горят", Game.core_arc_count() == 7, str(Game.core_arcs))
	ok("этап запуска", await wait_stage(2, 2.0), str(mission.stage))
	# E берёт клетку под курсором. 12 px — ещё та же клетка соседства, до центра < 56.
	for s in player.inv.slots:
		s.take(s.count)
	player.global_position = World.cell_to_world(core) + Vector2(12.0, 0.0)
	player.vel = Vector2.ZERO
	aim(World.cell_to_world(core) + Vector2(-2.0, 0.0))
	await await_frame()
	hold(KEY_E)
	# Отсчёт E идёт в _process игрока. Ждём по Game.game_time.
	var t_launch: float = Game.game_time
	var launched: bool = false
	while Game.game_time - t_launch < 8.0:
		if Game.relay_active:
			launched = true
			break
		await get_tree().process_frame
	release(KEY_E)
	ok("ядро запущено", launched)
	ok("этап удержания", await wait_stage(3, 2.0), str(mission.stage))
	ok("скорость удержания 2", is_equal_approx(Game.relay_speed, 2.0), str(Game.relay_speed))
	drive_threat = true
	var night: bool = await wait_until(func() -> bool: return Game.is_night(), 3.0)
	ok("ночь осады", night)
	var cat: bool = await wait_until(func() -> bool:
		return RainbowCat.live != null and is_instance_valid(RainbowCat.live), 4.0)
	ok("кот вылетел из ядра", cat)
	ok("двойника нет", _no_doppel())
	Engine.time_scale = 8.0
	var t_hold: float = Game.game_time
	var done: bool = false
	while Game.game_time - t_hold < 60.0:
		if mission.result != Mission.Result.RUNNING:
			done = true
			break
		await get_tree().process_frame
	Engine.time_scale = 1.0
	ok("удержание 90 с — победа", done and mission.result == Mission.Result.WON,
			"итог %d, держали %.1f" % [mission.result, float(mission.get("_held"))])
	Game.relay_speed = 1.0
	return await _won("rainbow", t0)


# ------------------------------------------------------------------ СЛОВА

func _words() -> void:
	var long: Array = []
	for id in ["sun", "rainbow"]:
		var m: Mission = Campaign.create(id)
		if m == null:
			long.append(id)
			continue
		for st in m.stages():
			var hint: String = String(st.get("hint", ""))
			if hint.find("·") >= 0 or _has_key(hint):
				long.append("%s hint «%s»" % [id, hint])
			for g in st.get("goals", []):
				var words: PackedStringArray = String(g[0]).split(" ", false)
				if words.size() > 6 or g.size() < 3:
					long.append("%s: «%s» (%d)" % [id, String(g[0]), words.size()])
			if st.get("say", []).size() > 2:
				long.append("%s say" % id)
		m.free()
	ok("карточка ≤ 6 слов, hint без «·» и без клавиш, say ≤ 2", long.is_empty(), ", ".join(long))


## Шесть глав в списке. 1–4 проходит их сценарий (campaign, campaign_light_late);
## здесь — что они на месте и что свои две уложились в остаток десяти минут.
func _six(own: float) -> void:
	var ids: Array = ["dig", "fire", "mirror", "colors", "sun", "rainbow"]
	print("  [замер] главы 5–6: %.1f с; шесть в списке %s" % [own, str(_chapters_end_with(ids))])
	ok("шесть глав в CHAPTERS по порядку", _chapters_end_with(ids), str(Campaign.CHAPTERS))
	ok("главы 5–6 ≤ 10 минут", own <= SIX and own > 0.0, "%.1f с" % own)


func _chapters_end_with(tail: Array) -> bool:
	if Campaign.CHAPTERS.size() < tail.size():
		return false
	var off: int = Campaign.CHAPTERS.size() - tail.size()
	for i in tail.size():
		if Campaign.CHAPTERS[off + i] != tail[i]:
			return false
	return true


# ------------------------------------------------------------------ МЕЛОЧИ

func _place(kind: String, c: Vector2i, dir: int) -> void:
	_air(c)
	var m: MachineBase = CampaignBase.put(kind, c, {"dir": dir})
	if m != null and "dir" in m:
		m.set("dir", dir)


func _air(c: Vector2i) -> void:
	if World.get_tile_v(c) != IDs.T.AIR:
		World.set_tile(c.x, c.y, IDs.T.AIR)


## Ждать условие по кадрам отрисовки (машины, E, запас). now() — физика, она отстаёт.
func _until_proc(cond: Callable, timeout: float) -> bool:
	var t0: float = now_proc()
	while now_proc() - t0 < timeout:
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


func _flush() -> void:
	if World.beams == null:
		return
	World.beams.note_machines()
	World.beams.mark_dirty()
	World.beams.rebuild()


func _pharos_color() -> int:
	var p: Pharos = World.machines.get(LightLate.at(LightLate.PHAROS)) as Pharos
	return p.color if p != null else -1


func _crystals_open() -> int:
	var n: int = 0
	for row in LightLate.CRYSTAL_ROWS:
		var c: Vector2i = LightLate.crystal_cell(int(row))
		if World.get_tile_v(c) == IDs.T.CRYSTAL_ORE and World.is_explored(c):
			n += 1
	return n


func _dig_crystals(n: int) -> void:
	var got: int = 0
	for row in LightLate.CRYSTAL_ROWS:
		if got >= n:
			break
		var c: Vector2i = LightLate.crystal_cell(int(row))
		if World.get_tile_v(c) != IDs.T.CRYSTAL_ORE:
			continue
		World.set_tile(c.x, c.y, IDs.T.AIR)
		player.inv.add(IDs.I.CRYSTAL, 1)
		got += 1


func _burrower() -> Node:
	for p in get_tree().get_nodes_in_group("phantom"):
		if is_instance_valid(p) and String(p.get("kind")) == "burrower":
			return p
	return null


func _take_core(chest: Chest) -> void:
	if chest == null:
		player.inv.add(IDs.I.RAINBOW_CORE, 1)
		return
	for s in chest.slots:
		if s.id == IDs.I.RAINBOW_CORE and s.count > 0:
			s.take(1)
			player.inv.add(IDs.I.RAINBOW_CORE, 1)
			return


## Семь чистых цветов в ядро. Один реальный луч (уголь → красный) проверяет
## приём; остальные шесть — core_feed, чтобы горелки не открыли рой на ночи.
func _light_seven(core: Vector2i) -> void:
	var c: Vector2i = core + Vector2i(-3, 0)
	_air(c)
	_air(c + Vector2i(1, 0))
	_air(c + Vector2i(2, 0))
	var b: Burner = CampaignBase.put("Burner", c, {"dir": 0}) as Burner
	if b != null:
		b.dir = 0
		b.add_fuel(IDs.I.COAL, 1)
		_flush()
		await wait(0.3)
		b.enabled = false
		b.burn_left = 0.0
		b.color = 0
		if World.beams != null:
			World.beams.mark_dirty()
	for col in [Beams.R, Beams.G, Beams.B, Beams.Y, Beams.C, Beams.M, Beams.W]:
		Game.core_feed(col)
	_flush()


func _no_doppel() -> bool:
	for p in get_tree().get_nodes_in_group("phantom"):
		if is_instance_valid(p) and String(p.get("kind")) == "doppel":
			return false
	return true


func _slot(id: int) -> int:
	for i in player.inv.slots.size():
		if player.inv.slots[i].id == id and player.inv.slots[i].count > 0:
			return i
	return 0


func _has_key(text: String) -> bool:
	for k in ["ЛКМ", "ПКМ", "E ", " E", "[E]", "клавиш"]:
		if text.find(k) >= 0:
			return true
	return false
