extends ScenarioBase
## HUD: трекер цели, отсчёт ночи, индикатор мощности, вентиляции на миникарте
## и FX угрозы (ADR-001 § 4.1, § 4.3, § 4.7; #34). Всё проверяется по
## состоянию HUD/WorldFX, а не по скриншоту:
##  * карточка «Сейчас»: этап 0 — «Запитай терминалы базы» 0/2; смена этапа
##    (Game.set_objective_stage, сигнал objective_changed) — новая карточка
##    в тот же кадр-два и перерисовка; текст каждой цели каждой главы ≤ 6 слов;
##  * отсчёт: в сумерках — целые секунды до ночи, днём и ночью — нет; HUD
##    перерисовывается раз в секунду, а не каждый кадр;
##  * питания нет (#170): индикатор мощности молчит, ТЭЦ не ставится;
##  * миникарта: вентиляции только под открытым туманом;
##  * миникарта: решётка (#31) рисуется решёткой, сломанная — сразу снова вентиляцией;
##  * FX: Threat.vent_warning → пар и потом пусто; spawn_arc и World.turret_fired →
##    дуга, ни одного нового узла. Турель снята (#170): живой выстрел не проверяем.

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
	ok("этап 1 — карточка «Прочитай терминал»", hud.tracker_stage == 1
			and hud.card_text == "Прочитай терминал" and hud.card_have == 0 and hud.card_need == 1,
			"«%s» %d/%d" % [hud.card_text, hud.card_have, hud.card_need])
	ok("текст карточки не длиннее 6 слов", hud.card_text.split(" ", false).size() <= 6, "«%s»" % hud.card_text)
	var r0: int = hud.stat_redraws
	Game.stats_ore = 3
	Game.set_objective_stage(2)
	await _frames(hud, 2)
	ok("этап 2 — карточка «Накопай руды»", hud.tracker_stage == 2
			and hud.card_text == "Накопай руды" and hud.card_have == 3
			and hud.card_need == Balance.FREE_ORE_NEED and hud.card_icon == IDs.I.COAL,
			"«%s» %d/%d" % [hud.card_text, hud.card_have, hud.card_need])
	ok("смена этапа → HUD перерисован", hud.stat_redraws > r0, "%d → %d" % [r0, hud.stat_redraws])
	Game.set_objective_stage(4)
	await _frames(hud, 2)
	ok("этап 4 — карточка «Зажги шесть дуг»", hud.tracker_stage == 4
			and hud.card_text == "Зажги шесть дуг" and hud.card_icon == IDs.I.RAINBOW_CORE and hud.card_need == 6,
			"«%s» иконка %d, %d/%d" % [hud.card_text, hud.card_icon, hud.card_have, hud.card_need])
	ok("этап 4: строка замера — дуги 0/6", hud.tracker_detail.begins_with("дуги 0/6"),
			"«%s»" % hud.tracker_detail)
	Game.relay_timer = 125.0
	Game.relay_active = true
	Game.set_objective_stage(6)
	await _frames(hud, 2)
	ok("этап 6: «Держись у ядра», счётчик до эвакуации", hud.card_text == "Держись у ядра"
			and hud.card_have == int(Balance.RELAY_TIME) - 125 and hud.card_need == int(Balance.RELAY_TIME),
			"«%s» %d / %d" % [hud.card_text, hud.card_have, hud.card_need])
	Game.relay_timer = 0.0
	Game.relay_active = false
	Game.stats_ore = 0
	Game.set_objective_stage(0)
	await _frames(hud, 2)
	ok("этап сброшен → снова карточка этапа 1", hud.tracker_stage == 1
			and hud.card_text == "Прочитай терминал", "«%s»" % hud.card_text)
	_card_words(hud)


## Каждая цель каждой главы — не длиннее 6 слов на карточке (#160).
func _card_words(hud: HUD) -> void:
	var long: Array = []
	for id in Campaign.CHAPTERS:
		var m: Mission = Campaign.create(id)
		if m == null:
			long.append(id)
			continue
		for st in m.stages():
			for g in st.get("goals", []):
				var words: String = hud._card_words(String(g[0]), HUD.CARD_WORDS)
				if words.split(" ", false).size() > 6:
					long.append("%s: «%s»" % [id, words])
		m.free()
	ok("текст карточки ≤ 6 слов у каждой цели каждой главы", long.is_empty(), ", ".join(long))


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
	# Покадровые анимации HUD убираем из окна замера: затухание подсказки
	# управления (game_time 16–22 с), уведомлений (Game шлёт «Цель 1/3» после
	# сброса этапа) и вспышки урона.
	Game.game_time = maxf(Game.game_time, 30.0)
	hud.notes.clear()
	hud.damage_flash = 0.0
	await _frames(hud, 3)
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

## Питание снято (#170): ТЭЦ не ставится, индикатор мощности остаётся нулём.
func _power(hud: HUD, base: int) -> void:
	var bx: int = World.beacon_cell.x
	var gcell: Vector2i = Vector2i(bx + 9, base - 1)
	ok("ТЭЦ больше не ставится", not MachineBase.place_machine("CoalGen", gcell))
	ok("индикатор мощности молчит", hud.power_out_x10 == 0 and hud.power_load_x10 == 0
			and hud.power_text == "", "«%s» выход %d" % [hud.power_text, hud.power_out_x10])
	ok("терминал читается без генератора", Game.is_powered(World.cell_to_world(Vector2i(bx, base))))


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
	ok("турель больше не ставится", not MachineBase.place_machine("Turret",
			World.world_to_cell(player.global_position) + Vector2i(2, 0)))
