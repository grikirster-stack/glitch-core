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
##  * FX: Threat.vent_warning → пар и потом пусто; spawn_arc и сигнал «fired»
##    турели → дуга; ни одного нового узла.

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
	if World.get("vents_sealed") == null and not World.has_method("is_vent_sealed"):
		print("  ..   решётки (#31): World.vents_sealed ещё нет — проверка решёток пропущена")


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
	ok("spawn_arc → дуга", fx.arcs.size() == 1)
	# Турель (#31) шлёт сигнал fired(from, to) — WorldFX подписан сам.
	var gs: GDScript = GDScript.new()
	gs.source_code = "extends MachineBase\nsignal fired(from: Vector2, to: Vector2)\n"
	gs.reload()
	var fake: Node2D = gs.new()
	scene.add_child(fake)
	fake.emit_signal("fired", player.global_position, player.global_position + Vector2(-50, 0))
	ok("сигнал турели fired → дуга", fx.stat_arcs == a0 + 2, "дуг выпущено %d" % (fx.stat_arcs - a0))
	scene.remove_child(fake)
	fake.free()
	await wait(0.4)
	ok("дуги гаснут", fx.arcs.is_empty(), "дуг %d" % fx.arcs.size())
	ok("FX не создаёт узлов", get_tree().get_node_count() == nodes0,
			"%d → %d" % [nodes0, get_tree().get_node_count()])
