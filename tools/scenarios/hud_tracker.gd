extends ScenarioBase
## HUD: трекер цели, отсчёт ночи, индикатор мощности, вентиляции на миникарте
## и FX угрозы (ADR-001 § 4.1, § 4.3, § 4.7; #34). Всё проверяется по
## состоянию HUD/WorldFX, а не по скриншоту:
##  * трекер: этап 0 показывается как 1/4; смена этапа (Game.set_objective_stage,
##    сигнал objective_changed) — новая строка в тот же кадр-два и перерисовка;
##  * отсчёт: в сумерках — целые секунды до ночи, днём и ночью — нет; HUD
##    перерисовывается раз в секунду, а не каждый кадр;
##  * мощность: ближайшая ТЭЦ — нагрузка/выход; перегруз; рубильник; генератор
##    под курсором важнее ближайшего;
##  * миникарта: вентиляции только под открытым туманом;
##  * миникарта: решётка (#31) рисуется решёткой, сломанная — сразу снова вентиляцией;
##  * FX: Threat.vent_warning → пар и потом пусто; spawn_arc и World.turret_fired →
##    дуга, ни одного нового узла; настоящая турель: дуг ровно столько, сколько выстрелов.

const FRAMES_SETTLE: int = 3


func run() -> void:
	var base: int = stand_in_corridor(6)   # герой на bx+7
	clear_input()
	var hud: HUD = UI.hud
	var fx: WorldFX = UI.world_fx
	ok("HUD и эффекты на месте", hud != null and fx != null)
	if hud == null or fx == null:
		finish()
		return
	await _frames(hud, FRAMES_SETTLE)
	await _tracker(hud)
	await _countdown(hud)
	await _power(hud, base)
	await _minimap(hud)
	await _fx(fx)
	finish()


## Подождать n кадров HUD (а не секунд: первый кадр бывает длинным).
func _frames(hud: HUD, n: int) -> void:
	var f0: int = hud.stat_frames
	await wait_until(func() -> bool: return hud.stat_frames >= f0 + n, 5.0)


# ------------------------------------------------------------ ТРЕКЕР

func _tracker(hud: HUD) -> void:
	ok("этап 0 показан как 1/4", hud.tracker_stage == 1 and hud.tracker_title.contains("1/4")
			and hud.tracker_title.contains("ЗАПИТАТЬ СТАНЦИЮ"), "«%s»" % hud.tracker_title)
	ok("этап 1: терминалы базы без питания 0/2", hud.tracker_detail.contains("0/2"),
			"«%s»" % hud.tracker_detail)
	var r0: int = hud.stat_redraws
	Game.set_objective_stage(2)
	await _frames(hud, 2)
	ok("смена этапа → трекер «СОБРАТЬ ДАННЫЕ» сразу", hud.tracker_stage == 2
			and hud.tracker_title.contains("СОБРАТЬ ДАННЫЕ"), "«%s»" % hud.tracker_title)
	ok("смена этапа → HUD перерисован", hud.stat_redraws > r0, "%d → %d" % [r0, hud.stat_redraws])
	var data0: int = Game.research
	Game.research = data0 + 7
	await wait_until(func() -> bool: return hud.tracker_detail.contains("данные %d/" % (data0 + 7)), 1.0)
	ok("счётчик данных в трекере", hud.tracker_detail.contains("данные %d/%d" % [data0 + 7, Tech.cost("T1")]),
			"«%s»" % hud.tracker_detail)
	Game.set_objective_stage(3)
	await _frames(hud, 2)
	ok("этап 3: детали релея", hud.tracker_title.contains("СОБРАТЬ РЕЛЕЙ")
			and hud.tracker_detail.contains("детали 0/%d" % Game.relay_req.size()), "«%s» «%s»" % [
			hud.tracker_title, hud.tracker_detail])
	Game.relay_timer = 125.0
	Game.set_objective_stage(4)
	await _frames(hud, 2)
	ok("этап 4: отсчёт сигнала м:сс", hud.tracker_title.contains("УДЕРЖАТЬ СИГНАЛ")
			and hud.tracker_detail.contains("2:05"), "«%s»" % hud.tracker_detail)
	Game.relay_timer = 0.0
	Game.research = data0
	Game.set_objective_stage(0)
	await _frames(hud, 2)
	ok("этап сброшен → снова 1/4", hud.tracker_stage == 1, "«%s»" % hud.tracker_title)


# ------------------------------------------------------------ ОТСЧЁТ ДО НОЧИ

func _countdown(hud: HUD) -> void:
	var t_save: float = Game.time_of_day
	ok("днём отсчёта нет", hud.night_countdown == -1, str(hud.night_countdown))
	Game.time_of_day = Balance.DUSK_START + 0.5 * (Balance.NIGHT_START - Balance.DUSK_START)
	await _frames(hud, 2)
	var want: int = int(ceil((Balance.NIGHT_START - Game.time_of_day) * Balance.DAY_LENGTH))
	ok("в сумерках — секунды до ночи", hud.night_countdown > 0 and absi(hud.night_countdown - want) <= 1,
			"HUD %d, ожидали %d" % [hud.night_countdown, want])
	# Отсчёт идёт и HUD перерисовывается по секундам, а не каждый кадр.
	var c0: int = hud.night_countdown
	var r0: int = hud.stat_redraws
	var f0: int = hud.stat_frames
	await wait(2.2)
	var redraws: int = hud.stat_redraws - r0
	var frames: int = hud.stat_frames - f0
	ok("отсчёт уменьшается", hud.night_countdown <= c0 - 1 and hud.night_countdown >= c0 - 3,
			"%d → %d" % [c0, hud.night_countdown])
	ok("отсчёт перерисовывает HUD по секундам", redraws >= 1 and (redraws <= 8 or redraws * 3 < frames),
			"перерисовок %d за %d кадров" % [redraws, frames])
	Game.time_of_day = Balance.NIGHT_START + 0.02
	await _frames(hud, 2)
	ok("ночью отсчёта нет", hud.night_countdown == -1, str(hud.night_countdown))
	Game.time_of_day = t_save
	await _frames(hud, 2)


# ------------------------------------------------------------ МОЩНОСТЬ

func _power(hud: HUD, base: int) -> void:
	var bx: int = World.beacon_cell.x
	var gcell: Vector2i = Vector2i(bx + 9, base - 1)
	ok("ТЭЦ поставлена", MachineBase.place_machine("CoalGen", gcell))
	var gen = World.machines.get(gcell)
	if gen == null:
		return
	gen.add_fuel(3)
	await wait(0.6)            # раскладка мощности — раз в 0.25 с
	await _frames(hud, 2)
	ok("индикатор: ближайшая ТЭЦ", hud.power_gen == gen and hud.power_text == "ТЭЦ",
			"«%s»" % hud.power_text)
	ok("индикатор: выход 6.0, нагрузка 0", hud.power_out_x10 == int(Balance.POWER_OUT["CoalGen"] * 10.0)
			and hud.power_load_x10 == 0 and (hud.power_flags & HUD.POWER_ON) != 0,
			"выход %d, нагрузка %d, флаги %d" % [hud.power_out_x10, hud.power_load_x10, hud.power_flags])
	# Перегруз: четыре сборщика по 2.0 на ТЭЦ 6.0.
	var placed: int = 0
	for dx in [11, 12, 13, 14]:
		if MachineBase.place_machine("Assembler", Vector2i(bx + int(dx), base - 1)):
			placed += 1
	await wait(0.6)
	await _frames(hud, 2)
	ok("сборщики поставлены", placed == 4, "%d" % placed)
	ok("индикатор: нагрузка 8.0 — перегруз", hud.power_load_x10 == 80
			and (hud.power_flags & HUD.POWER_OVER) != 0 and Game.brownout,
			"нагрузка %d, флаги %d, brownout %s" % [hud.power_load_x10, hud.power_flags, Game.brownout])
	gen.set_enabled(false)
	await wait(0.4)
	await _frames(hud, 2)
	ok("рубильник: индикатор ВЫКЛ, выход 0", (hud.power_flags & HUD.POWER_ON) == 0 and hud.power_out_x10 == 0,
			"флаги %d, выход %d" % [hud.power_flags, hud.power_out_x10])
	gen.set_enabled(true)
	# Под курсором — другой генератор: он важнее ближайшего.
	var scell: Vector2i = Vector2i(bx + 4, base - 1)
	ok("солнечная панель поставлена", MachineBase.place_machine("Solar", scell))
	var solar = World.machines.get(scell)
	if solar != null:
		aim(solar.global_position)
		await _frames(hud, 3)
		ok("генератор под курсором важнее ближайшего", hud.power_gen == solar
				and hud.power_text == "Солнечная панель", "«%s»" % hud.power_text)
		clear_input()


# ------------------------------------------------------------ МИНИКАРТА

func _minimap(hud: HUD) -> void:
	# Сдвигаем героя на пару пикселей миникарты — слой карты перерисуется.
	var r0: int = hud.stat_map_redraws
	stand_in_corridor(14)
	await _frames(hud, 3)
	await wait_until(func() -> bool: return hud.stat_map_redraws > r0, 2.0)
	var want: int = 0
	for v in World.vents:
		if hud.map_explored_at(v):
			want += 1
	ok("на миникарте нарисованы открытые вентиляции", hud.stat_map_vents + hud.stat_map_grates == want,
			"нарисовано %d+%d, открытых %d из %d" % [hud.stat_map_vents, hud.stat_map_grates, want, World.vents.size()])
	ok("вентиляция базы видна на миникарте", want >= 1, "%d" % want)
	# Вентиляция в закрытой пещере: в тумане её на карте нет, открыли — есть.
	var hidden: Vector2i = _unexplored_cell()
	ok("нашлась закрытая клетка для вентиляции", hidden.x >= 0, str(hidden))
	if hidden.x < 0:
		return
	World.vents.append(hidden)
	r0 = hud.stat_map_redraws
	await wait_until(func() -> bool: return hud.stat_map_redraws > r0, 2.5)   # сверка раз в 1 с
	ok("новая вентиляция в тумане на карте не видна", hud.stat_map_vents + hud.stat_map_grates == want,
			"нарисовано %d+%d, ожидали %d" % [hud.stat_map_vents, hud.stat_map_grates, want])
	r0 = hud.stat_map_redraws
	World.reveal_around(hidden, 6)
	await wait_until(func() -> bool: return hud.stat_map_redraws > r0, 2.0)
	ok("туман открыт — вентиляция на карте", hud.stat_map_vents + hud.stat_map_grates == want + 1,
			"нарисовано %d+%d, ожидали %d" % [hud.stat_map_vents, hud.stat_map_grates, want + 1])
	World.vents.erase(hidden)

	# Решётка (#31): открытая вентиляция → решётка на карте; копатель сломал —
	# снова вентиляция, и сразу (World.grate_broken), без ожидания сверки.
	var gv: Vector2i = Vector2i(-1, -1)
	for v in World.vents:
		if hud.map_explored_at(v) and not World.is_vent_sealed(v):
			gv = v
			break
	ok("есть открытая вентиляция под решётку", gv.x >= 0, str(gv))
	if gv.x < 0:
		return
	var open_n: int = 0
	for v in World.vents:
		if hud.map_explored_at(v):
			open_n += 1
	World.set_tile(gv.x, gv.y, IDs.T.VENT_GRATE)
	ok("решётка поставлена (World.vents_sealed)", World.is_vent_sealed(gv))
	await wait_until(func() -> bool: return hud.stat_map_grates == 1, 2.5)   # сверка раз в 1 с
	ok("решётка на миникарте", hud.stat_map_grates == 1 and hud.stat_map_vents == open_n - 1,
			"решёток %d, вентиляций %d (открытых всего %d)" % [hud.stat_map_grates, hud.stat_map_vents, open_n])
	ok("решётку сломали", World.damage_grate(gv, Balance.GRATE_HP + 1.0))
	# Сигнал grate_broken → сверка в следующем кадре HUD, перерисовка — в том же.
	for k in 4:
		await get_tree().process_frame
	ok("сломанная решётка ушла с миникарты за 4 кадра", hud.stat_map_grates == 0
			and hud.stat_map_vents == open_n, "решёток %d, вентиляций %d" % [hud.stat_map_grates, hud.stat_map_vents])


## Клетка глубоко под землёй, чей пиксель миникарты ещё под туманом.
func _unexplored_cell() -> Vector2i:
	for x in range(8, World.W - 8, 23):
		for y in range(World.H - 12, World.surface[x] + 6, -7):
			var c: Vector2i = Vector2i(x, y)
			if not UI.hud.map_explored_at(c) and not World.is_explored(c):
				return c
	return Vector2i(-1, -1)


# ------------------------------------------------------------ FX

func _fx(fx: WorldFX) -> void:
	var nodes0: int = get_tree().get_node_count()
	var vent: Vector2i = World.vents[World.vents.size() - 1]
	var w0: int = fx.stat_vent_warnings
	Threat.vent_warning.emit(vent)
	ok("vent_warning → вентиляция «выдыхает»", fx.stat_vent_warnings == w0 + 1 and fx.steam_vents.size() >= 1,
			"выдохов %d" % fx.steam_vents.size())
	await wait(0.4)
	ok("пар идёт", fx.steams.size() > 0, "клубов %d" % fx.steams.size())
	var lim: Dictionary = fx.get_script().get_script_constant_map()
	await wait_until(func() -> bool: return fx.steams.is_empty() and fx.steam_vents.is_empty(),
			Balance.VENT_TELEGRAPH + float(lim["STEAM_LIFE"]) + 1.5)
	ok("пар рассеялся", fx.steams.is_empty() and fx.steam_vents.is_empty(), "клубов %d" % fx.steams.size())
	ok("лимит пара соблюдён", fx.peak_steams <= int(lim["MAX_STEAM"]), "пик %d" % fx.peak_steams)

	var a0: int = fx.stat_arcs
	fx.spawn_arc(player.global_position, player.global_position + Vector2(60, -20))
	ok("spawn_arc → дуга", fx.arcs.size() == 1 and fx.stat_arcs == a0 + 1)
	# Глобальный World.turret_fired (#31) — ровно одна дуга на выстрел.
	World.turret_fired.emit(player.global_position, player.global_position + Vector2(-50, 0))
	ok("World.turret_fired → дуга", fx.stat_arcs == a0 + 2, "дуг выпущено %d" % (fx.stat_arcs - a0))
	await wait(0.4)
	ok("дуги гаснут", fx.arcs.is_empty(), "дуг %d" % fx.arcs.size())
	ok("FX не создаёт узлов", get_tree().get_node_count() == nodes0,
			"%d → %d" % [nodes0, get_tree().get_node_count()])
	await _turret_arcs(fx)


## Настоящая турель (#31) бьёт эхо: она шлёт и Turret.fired, и World.turret_fired —
## дуг ровно столько, сколько выстрелов (двойной дуги нет).
func _turret_arcs(fx: WorldFX) -> void:
	var tk: GDScript = load("res://tools/scenarios/turret_kills_echo.gd")
	player.invuln = 1.0e9
	var o: Vector2i = tk.find_box_spot(self, 12, 6)
	ok("место под турель найдено", o.x >= 0, str(o))
	if o.x < 0:
		return
	var turret: Turret = tk.build_turret_box(self, o, 12, 6)
	ok("турель поставлена", turret != null)
	if turret == null:
		return
	await wait_until(func(): return turret.powered and turret.efficiency >= 0.999, 2.0)
	var a0: int = fx.stat_arcs
	var s0: int = turret.shots
	var echo: Node = spawn_phantom_at(Vector2(float((o.x + 8) * World.TILE) + 8.0,
			float((o.y + 4) * World.TILE) - 12.0), "echo")
	ok("эхо появилось", echo != null)
	await wait_until(func(): return turret.shots - s0 >= 2, 4.0)
	var shots: int = turret.shots - s0
	ok("турель стреляет", shots >= 2, "выстрелов %d" % shots)
	ok("одна дуга на выстрел (без двойной)", fx.stat_arcs - a0 == shots,
			"дуг %d, выстрелов %d" % [fx.stat_arcs - a0, shots])
	if echo != null and is_instance_valid(echo):
		echo.get_parent().remove_child(echo)
		echo.queue_free()
