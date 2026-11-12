extends ScenarioBase
## Этапы цели (ADR-005 § 6.3–6.4, #175, #212): 1 → 2 → 3 → 4 → 5 → 6.
##   1 → 2: прочитан терминал (чертёж).
##   2 → 3: добыто Balance.FREE_ORE_NEED руды. Хлам не считается.
##   3 → 4: пережита ночь (рассвет).
##   4 → 5: шесть дуг. Белый луч дугу не зажигает.
##   5 → 6: E у ядра 3 с — Game.core_launch(). Раньше этапов 1–3 запуск отказывает.
## Сигнал objective_changed уходит по разу на этап, по порядку.

var _seen: Array = []


func run() -> void:
	player.invuln = 1.0e9
	Game.objective_changed.connect(_on_stage)
	var started: bool = await wait_until(func() -> bool: return Game.objective_stage == 1, 2.0)
	ok("старт забега — этап 1", started, str(Game.objective_stage))
	ok("строка цели «ЦЕЛЬ 1/6»", Game.objective_text().begins_with("ЦЕЛЬ 1/6"), Game.objective_text())

	var cell: Vector2i = World.beacon_cell + Vector2i(3, 0)
	World.set_tile(cell.x, cell.y, IDs.T.AIR)
	MachineBase.place_machine("RainbowCore", cell)
	ok("ядро без терминала — всё ещё этап 1", Game.objective_stage == 1 and Game.core_placed(),
			Game.objective_text())
	ok("шесть дуг без этапов 1–3 запуск не дают", _feed(6) and not Game.core_launch()
			and not Game.relay_active and Game.objective_stage == 1, Game.free_block_text())

	Game.tasks_done = 1
	Game.update_objective()
	ok("терминал прочитан → этап 2", Game.objective_stage == 2, Game.objective_text())
	ok("хлам добычу не закрывает", _scrap() and Game.objective_stage == 2 and not Game.free_mined(),
			"руда %d" % Game.stats_ore)
	for _i in Balance.FREE_ORE_NEED:
		Game.stats_ore += 1
		Game.update_objective()
	ok("руда %d → этап 3" % Balance.FREE_ORE_NEED, Game.objective_stage == 3
			and Game.free_mined(), Game.objective_text())
	ok("до ночи запуск отказывает", not Game.core_launch() and not Game.relay_active,
			Game.free_block_text())
	# Соседний сценарий мог уже зажечь шесть дуг: ночь должна открыть этап 4, не 5.
	Game.core_arcs = 0
	Game.relay_active = false
	Game.time_of_day = 0.99
	Game.advance_clock(0.06)
	var dawn: bool = Game.nights_survived >= 1
	ok("рассвет → этап 4", dawn and Game.objective_stage == 4, Game.objective_text())

	Game.core_arcs = 0
	ok("пять дуг — ещё этап 4", _feed(5) and Game.objective_stage == 4 and Game.core_arc_count() == 5)
	var before_w: int = Game.core_arc_count()
	Game.core_feed(Beams.W)
	ok("белый луч дугу не зажигает", Game.core_arc_count() == before_w)
	ok("с пятью дугами запуск отказывает", not Game.core_launch() and not Game.relay_active)
	var miss: String = ", ".join(Game.core_missing_names())
	ok("перечень недостающих — одно имя", miss != "" and miss.find(",") < 0, miss)
	ok("шестая дуга → этап 5", _feed(6) and Game.objective_stage == 5
			and Game.core_arcs == Game.CORE_ARCS_FREE, Game.objective_text())
	ok("запуск ядра → этап 6", Game.core_launch() and Game.objective_stage == 6, Game.objective_text())
	ok("строка цели с отсчётом", Game.objective_text().begins_with("ЦЕЛЬ 6/6")
			and Game.objective_text().ends_with(" с"), Game.objective_text())
	ok("этапы по порядку 1 → 6, по разу", _seen == [1, 2, 3, 4, 5, 6], str(_seen))
	_end()


func _feed(n: int) -> bool:
	var colors: Array = [Beams.R, Beams.G, Beams.B, Beams.Y, Beams.C, Beams.M]
	for i in mini(n, colors.size()):
		Game.core_feed(colors[i])
	return Game.core_arc_count() == n


## Хлам и камень в счётчик руды не входят — как сломанная поверхность.
func _scrap() -> bool:
	var before: int = Game.stats_ore
	var cell: Vector2i = World.beacon_cell + Vector2i(6, 2)
	World.set_tile(cell.x, cell.y, IDs.T.DIRT)
	player._break_tile(cell)
	var dirt_ok: bool = Game.stats_ore == before
	World.set_tile(cell.x, cell.y, IDs.T.COAL_ORE)
	player._break_tile(cell)
	var coal_ok: bool = Game.stats_ore == before + 1
	Game.stats_ore = before
	return dirt_ok and coal_ok


func _end() -> void:
	if Game.objective_changed.is_connected(_on_stage):
		Game.objective_changed.disconnect(_on_stage)
	finish()


func _on_stage(s: int) -> void:
	_seen.append(s)
