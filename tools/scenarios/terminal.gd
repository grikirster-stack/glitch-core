extends ScenarioBase
## Терминал: подойти к терминалу, удерживать E → task_progress растёт,
## задание засчитано.

func run() -> void:
	ok("в мире есть терминалы", World.terminals.size() > 0, "n=%d" % World.terminals.size())
	if World.terminals.is_empty():
		finish()
		return
	var t: Vector2i = World.terminals[0]
	var spot: Vector2 = World.cell_to_world(t)
	var placed: bool = place_near(spot, [Vector2(24, 0), Vector2(-24, 0), Vector2(0, 24),
			Vector2(24, 24), Vector2(-24, 24), Vector2(0, -24)])
	ok("герой встал рядом с терминалом", placed, str(t))
	if not placed:
		finish()
		return
	await wait(0.4)
	ok("герой рядом с терминалом", player.global_position.distance_to(spot) < 42.0,
			"%.1f px" % player.global_position.distance_to(spot))

	var done_before: int = Game.tasks_done
	hold(KEY_E)
	await wait(0.6)
	ok("прогресс задания растёт", player.task_progress > 0.05, "%.2f" % player.task_progress)

	var done: bool = await wait_until(func() -> bool: return Game.tasks_done > done_before, 5.0)
	release(KEY_E)
	ok("задание засчитано", done, "%d → %d" % [done_before, Game.tasks_done])
	ok("терминал отработал", World.get_tile_v(t) == IDs.T.PANEL, str(World.get_tile_v(t)))
	finish()
