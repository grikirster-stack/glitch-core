extends ScenarioBase
## Релей (ADR-001 § 4.7, #32): выдать детали → удерживать E у ядра → этап 4,
## отсчёт Balance.RELAY_TIME (180 с) → победа, на финальном экране — эпилог Lore.
## Ждать три минуты в тесте смысла нет: отсчёт ускоряется (Game.relay_speed).

const SPEED: float = 60.0          ## 180 с удержания — за 3 с реального времени


func run() -> void:
	player.invuln = 1.0e9
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
	ok("удержание — %d с" % int(Balance.RELAY_TIME), Balance.RELAY_TIME == 180.0
			and absf(Game.relay_timer - Balance.RELAY_TIME) < 2.0, "%.1f с" % Game.relay_timer)
	ok("этап цели 4 — удержать сигнал", Game.objective_stage == 4, Game.objective_text())

	# Ускоряем отсчёт: 180 с проходят за RELAY_TIME / SPEED реальных секунд.
	Game.relay_speed = SPEED
	var t0: float = Game.relay_timer
	await wait(0.5)
	ok("отсчёт ускорен тестом", t0 - Game.relay_timer > 10.0, "%.1f → %.1f с" % [t0, Game.relay_timer])
	var won: bool = await wait_until(func() -> bool: return Game.state == Game.State.WON,
			Balance.RELAY_TIME / SPEED + 4.0)
	ok("победа", won, "state=%d" % Game.state)
	ok("релей отработал", not Game.relay_active and Game.relay_timer == 0.0)

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
