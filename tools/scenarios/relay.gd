extends ScenarioBase
## Релей: выдать недостающие детали → удерживать E → отсчёт идёт → победа.

func run() -> void:
	# Выдаём детали, которых не хватает релею.
	for id in Game.relay_req.keys():
		player.inv.add(int(id), int(Game.relay_req[id]) + 1)
	var missing: Array = []
	for id in Game.relay_req.keys():
		if player.inv.count_of(int(id)) < int(Game.relay_req[id]):
			missing.append(DB.item_name(int(id)))
	ok("детали для релея на месте", missing.is_empty(), ", ".join(missing))

	# Встаём у релей-ядра: радиус взаимодействия — 56 px от клетки ядра.
	var placed: bool = stand_next_to_beacon()
	ok("герой встал у релея", placed, str(World.beacon_cell))
	if not placed:
		finish()
		return
	await wait(0.4)
	var dist: float = World.cell_to_world(World.beacon_cell).distance_to(player.global_position)
	ok("герой в радиусе релея", dist < 56.0, "%.0f px" % dist)

	# Держим E: отсчёт запускается.
	hold(KEY_E)
	await wait(0.8)
	ok("отсчёт релея идёт", player.task_progress > 0.05, "%.2f" % player.task_progress)
	var started: bool = await wait_until(func() -> bool: return Game.relay_active, 6.0)
	release(KEY_E)
	ok("релей запущен", started)
	ok("таймер эвакуации идёт", Game.relay_timer > 0.0, "%.1f с" % Game.relay_timer)

	# Финал считаем сами: ждать полторы минуты в тесте смысла нет.
	Game.relay_timer = 0.05
	await wait(0.6)
	ok("победа", Game.state == Game.State.WON, "state=%d" % Game.state)
	finish()
