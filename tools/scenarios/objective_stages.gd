extends ScenarioBase
## Этапы цели (ADR-005 § 6.3, #175): 1 → 2 → 3 → 4.
##   1 → 2: поставлено Радужное ядро.
##   2 → 3: семь дуг (по лучу каждого чистого цвета).
##   3 → 4: E у ядра 3 с — Game.core_launch(). С шестью дугами запуск отказывает.
## Сигнал objective_changed уходит по разу на этап, по порядку.
## Терминалы базы в этапах не участвуют.

var _seen: Array = []


func run() -> void:
	player.invuln = 1.0e9
	Game.objective_changed.connect(_on_stage)
	var started: bool = await wait_until(func() -> bool: return Game.objective_stage == 1, 2.0)
	ok("старт забега — этап 1", started, str(Game.objective_stage))
	ok("строка цели «ЦЕЛЬ 1/4»", Game.objective_text().begins_with("ЦЕЛЬ 1/4"), Game.objective_text())
	ok("карточка ведёт к сундуку лагеря", Game.objective_at().distance_to(
			World.cell_to_world(World.camp_chest_cell)) < 2.0, str(Game.objective_at()))

	var cell: Vector2i = World.beacon_cell + Vector2i(3, 0)
	World.set_tile(cell.x, cell.y, IDs.T.AIR)
	ok("ядро поставлено → этап 2", MachineBase.place_machine("RainbowCore", cell)
			and Game.objective_stage == 2, Game.objective_text())
	ok("шесть дуг — ещё этап 2", _feed(6) and Game.objective_stage == 2 and Game.core_arc_count() == 6)
	ok("с шестью дугами запуск отказывает", not Game.core_launch() and not Game.relay_active)
	var miss: String = ", ".join(Game.core_missing_names())
	ok("перечень недостающих — одно имя", miss != "" and miss.find(",") < 0, miss)
	ok("седьмая дуга → этап 3", _feed(7) and Game.objective_stage == 3, Game.objective_text())
	ok("запуск ядра → этап 4", Game.core_launch() and Game.objective_stage == 4, Game.objective_text())
	ok("строка цели с отсчётом", Game.objective_text().begins_with("ЦЕЛЬ 4/4")
			and Game.objective_text().ends_with(" с"), Game.objective_text())
	ok("этапы по порядку 1 → 2 → 3 → 4, по разу", _seen == [1, 2, 3, 4], str(_seen))
	_end()


func _feed(n: int) -> bool:
	var colors: Array = [Beams.R, Beams.G, Beams.B, Beams.Y, Beams.C, Beams.M, Beams.W]
	for i in mini(n, colors.size()):
		Game.core_feed(colors[i])
	return Game.core_arc_count() == n


func _end() -> void:
	if Game.objective_changed.is_connected(_on_stage):
		Game.objective_changed.disconnect(_on_stage)
	finish()


func _on_stage(s: int) -> void:
	_seen.append(s)
