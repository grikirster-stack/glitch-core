extends ScenarioBase
## Ядро (ADR-005 § 6.3, #175, #212): шесть дуг → E 3 с у ядра → этап 6,
## отсчёт Balance.RELAY_TIME (180 с) → победа, на финальном экране — эпилог Lore.
## Ждать три минуты в тесте смысла нет: отсчёт ускоряется (Game.relay_speed).

const SPEED: float = 60.0          ## 180 с удержания — за 3 с реального времени


func run() -> void:
	player.invuln = 1.0e9
	var cell: Vector2i = _place_core()
	ok("ядро поставлено", cell.x >= 0 and Game.core_cell == cell, str(cell))
	if cell.x < 0:
		finish()
		return
	_feed_all()
	ok("шесть дуг горят", Game.core_arcs == Game.CORE_ARCS_FREE, str(Game.core_arcs))
	# Этапы 1–3 свободной игры (#212): без них E у ядра отсчёт не начинает.
	Game.tasks_done = 1
	Game.stats_ore = Balance.FREE_ORE_NEED
	Game.nights_survived = Balance.FREE_NIGHTS_NEED
	Game.update_objective()

	var placed: bool = stand_next_to_cell(cell)
	ok("герой встал у ядра", placed, str(cell))
	if not placed:
		finish()
		return
	await wait(0.4)
	var dist: float = World.cell_to_world(cell).distance_to(player.global_position)
	ok("герой в радиусе ядра", dist < 56.0, "%.0f px" % dist)

	hold(KEY_E)
	await wait(0.8)
	ok("отсчёт запуска идёт", player.task_progress > 0.05, "%.2f" % player.task_progress)
	var started: bool = await wait_until(func() -> bool: return Game.relay_active, 6.0)
	release(KEY_E)
	ok("ядро запущено", started)
	ok("удержание — %d с" % int(Balance.RELAY_TIME), Balance.RELAY_TIME == 180.0
			and absf(Game.relay_timer - Balance.RELAY_TIME) < 2.0, "%.1f с" % Game.relay_timer)
	ok("этап цели 6 — удержать сигнал", Game.objective_stage == 6, Game.objective_text())

	Game.relay_speed = SPEED
	var t0: float = Game.relay_timer
	await wait(0.5)
	ok("отсчёт ускорен тестом", t0 - Game.relay_timer > 10.0, "%.1f → %.1f с" % [t0, Game.relay_timer])
	var won: bool = await wait_until(func() -> bool: return Game.state == Game.State.WON,
			Balance.RELAY_TIME / SPEED + 4.0)
	ok("победа", won, "state=%d" % Game.state)
	ok("ядро отработало", not Game.relay_active and Game.relay_timer == 0.0)

	var es: EndScreen = scene.get("end_screen")
	await await_frame()
	ok("финальный экран показан", es != null and es.visible and es.title == "ЭВАКУАЦИЯ",
			es.title if es != null else "нет экрана")
	if es != null:
		var want: String = Lore.epilogue(Game.epilogue_stats())
		ok("эпилог из Lore на экране", es.epilogue != "" and es.epilogue == want,
				es.epilogue.left(80))
		ok("экран в CanvasLayer поверх мира", es.get_parent() is CanvasLayer
				and (es.get_parent() as CanvasLayer).layer > UI.layer)
	Game.relay_speed = 1.0
	finish()


func _place_core() -> Vector2i:
	var cell: Vector2i = World.beacon_cell + Vector2i(2, 0)
	if World.get_tile_v(cell) != IDs.T.AIR:
		World.set_tile(cell.x, cell.y, IDs.T.AIR)
	if not MachineBase.place_machine("RainbowCore", cell):
		return Vector2i(-1, -1)
	return cell


func _feed_all() -> void:
	# Белый дугу не зажигает (#212): седьмой цвет — пурпурный, не маска 7.
	for c in [Beams.R, Beams.G, Beams.B, Beams.Y, Beams.C, Beams.M]:
		Game.core_feed(c)


func stand_next_to_cell(cell: Vector2i) -> bool:
	var base: int = cell.y + 1
	for dx in [1, -1, 2, -2, 0]:
		var px: int = cell.x + int(dx)
		if not World.is_solid_cell(Vector2i(px, base)):
			World.set_tile(px, base, IDs.T.STEEL)
		for y in range(base - 3, base):
			if World.get_tile_v(Vector2i(px, y)) != IDs.T.AIR and Vector2i(px, y) != cell:
				World.set_tile(px, y, IDs.T.AIR)
		player.global_position = Vector2(float(px * World.TILE) + 8.0, float(base * World.TILE) - 11.0)
		player.vel = Vector2.ZERO
		return true
	return false
