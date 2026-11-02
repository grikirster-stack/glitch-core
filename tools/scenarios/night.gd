extends ScenarioBase
## Ночь: форсируем ночь → фантом идёт на игрока → hp падает.
##
## Фантомы убегают из света (порог 0.55), поэтому охота проверяется в тёмном
## месте поверхности: там фантом видит героя и бьёт его.

func run() -> void:
	# Форсируем ночь.
	Game.time_of_day = 0.75
	await wait(0.3)
	ok("наступила ночь", Game.is_night(), "время %.2f" % Game.time_of_day)

	# Тёмное место на поверхности: там фантом не убежит от света.
	var cell: Vector2i = find_dark_spot()
	ok("найдено тёмное место", cell.x >= 0, str(cell))
	if cell.x < 0:
		finish()
		return
	stand_at_cell(cell)
	await wait(0.3)

	var dir: Vector2 = clear_direction_strict(120.0)
	ok("к герою есть прямая видимость", dir != Vector2.ZERO, str(dir))
	if dir == Vector2.ZERO:
		finish()
		return
	var ph: Node = spawn_phantom_at(player.global_position + dir * 120.0)
	ok("фантом появился ночью", ph != null)
	if ph == null:
		finish()
		return
	var hp0: float = player.hp
	var d0: float = ph.global_position.distance_to(player.global_position)
	var closest: float = d0
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 6000:
		closest = minf(closest, ph.global_position.distance_to(player.global_position))
		if player.hp < hp0:
			break
		await wait(0.05)
	ok("фантом пошёл на игрока", closest < d0 - 10.0, "%.1f → %.1f px" % [d0, closest])
	ok("здоровье игрока упало", player.hp < hp0, "hp %.0f → %.0f" % [hp0, player.hp])
	finish()
