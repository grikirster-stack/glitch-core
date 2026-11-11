extends ScenarioBase
## Терминал без питания (ADR-001 § 4.6, #29): подойти к терминалу базы,
## удерживать E → подсказка «нет питания», прогресс не растёт, задание
## не засчитано, глава журнала не прочитана. С питанием — сценарий terminal_powered.

var _hints: Array = []


func run() -> void:
	ok("в мире есть терминалы", World.terminals.size() > 0, "n=%d" % World.terminals.size())
	var t: Vector2i = terminal_of_chapter(0)
	ok("есть терминал базы (глава 1)", t.x >= 0, str(t))
	if t.x < 0:
		finish()
		return
	var spot: Vector2 = World.cell_to_world(t)
	ok("терминал без питания", not Game.is_powered(spot))
	if not await stand_at_terminal(t):
		finish()
		return

	Game.notification.connect(_on_hint)
	var done_before: int = Game.tasks_done
	var bp_before: int = Game.blueprints.size()
	hold(KEY_E)
	await wait(3.0)
	ok("прогресс задания не растёт", player.task_progress <= 0.0, "%.2f" % player.task_progress)
	release(KEY_E)
	Game.notification.disconnect(_on_hint)
	var no_power: int = 0
	for h in _hints:
		if String(h).contains("нет питания"):
			no_power += 1
	ok("подсказка «нет питания»", no_power > 0, str(_hints))
	ok("подсказка одна на нажатие", no_power == 1, "показана %d раз" % no_power)
	ok("задание не засчитано", Game.tasks_done == done_before, "%d → %d" % [done_before, Game.tasks_done])
	ok("чертёж не выдан", Game.blueprints.size() == bp_before, str(Game.blueprints))
	ok("глава не прочитана", not Tech.is_chapter_read(0))
	ok("терминал на месте", World.get_tile_v(t) == IDs.T.TERMINAL and World.terminals.has(t))
	finish()


func _on_hint(text: String, _color: Color) -> void:
	_hints.append(text)


## Терминал, который выдаёт главу i; (-1, -1) — нет такого.
func terminal_of_chapter(i: int) -> Vector2i:
	for t in World.terminals:
		if int(World.terminal_chapters.get(t, -1)) == i:
			return t
	return Vector2i(-1, -1)


## Встать у терминала (радиус E — 42 px от клетки терминала).
func stand_at_terminal(t: Vector2i) -> bool:
	var spot: Vector2 = World.cell_to_world(t)
	var placed: bool = place_near(spot, [Vector2(0, -24), Vector2(24, 0), Vector2(-24, 0),
			Vector2(24, -24), Vector2(-24, -24), Vector2(0, -40)])
	ok("герой встал рядом с терминалом", placed, str(t))
	if not placed:
		return false
	await wait(0.5)
	var d: float = player.global_position.distance_to(spot)
	ok("герой рядом с терминалом", d < 42.0, "%.1f px" % d)
	return d < 42.0
