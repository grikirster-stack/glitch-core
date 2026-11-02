extends ScenarioBase
## Укрытие: V → герой залезает в вентиляцию и становится неуязвимым.
##
## Укрытие — это защита: игрок в укрытии неуязвим (invuln), поэтому удар
## фантома не проходит. Проверяем на паре «без укрытия / в укрытии»:
## сначала удар проходит (контроль), потом тот же удар гасится.
##
## Фантомы убегают из света, а база освещена, поэтому надёжный источник удара
## здесь — сам игровой вход урона (player.damage), ровно тот, которым бьёт
## фантом. Рядом с героем при этом стоит настоящий фантом.

func run() -> void:
	ok("в мире есть вентиляция", World.vents.size() > 0, "n=%d" % World.vents.size())
	if World.vents.is_empty():
		finish()
		return

	# Встаём у вентиляции: она всегда есть у базы, в пещере — рядом с ней.
	var vent: Vector2i = World.vents[0]
	for v in World.vents:
		if World.cell_to_world(v).distance_to(World.cell_to_world(World.beacon_cell)) > 40.0:
			vent = v
			break
	stand_vent(vent)
	await wait(0.2)
	var dvent: float = World.cell_to_world(vent).distance_to(player.global_position)
	ok("герой у вентиляции", dvent < 40.0, "%.0f px" % dvent)
	if dvent >= 40.0:
		finish()
		return

	# Контроль: без укрытия удар проходит.
	var hp0: float = player.hp
	player.damage(24.0, Vector2.ZERO)
	await wait(0.8)
	ok("без укрытия удар проходит", player.hp < hp0, "hp %.0f → %.0f" % [hp0, player.hp])

	# Прячемся. Клавиша V переключает укрытие каждый кадр, пока её держат,
	# поэтому жмём короткими нажатиями, проверяя состояние после каждого кадра.
	var hidden: bool = false
	for attempt in 8:
		hold(KEY_V)
		for f in 8:
			await await_frame()
			if player.hiding:
				hidden = true
				break
		release(KEY_V)
		await wait(0.05)
		if hidden:
			break
	ok("герой спрятался по клавише V", hidden, str(vent))
	if not hidden:
		finish()
		return
	ok("спрятавшийся герой неуязвим", player.invuln > 0.0, "%.1f с" % player.invuln)

	# Рядом появляется фантом — спрятавшегося героя он не берёт.
	var dir: Vector2 = clear_direction_strict(40.0)
	if dir == Vector2.ZERO:
		dir = Vector2(1, 0)
	var ph: Node = spawn_phantom_at(player.global_position + dir * 40.0)
	ok("фантом появился рядом", ph != null)
	var hp1: float = player.hp
	if ph != null:
		await wait(1.5)
	ok("спрятавшийся герой не пострадал от фантома", player.hp >= hp1, "hp %.0f" % player.hp)

	# Тот же удар в укрытии не проходит.
	player.damage(24.0, Vector2.ZERO)
	await wait(0.2)
	ok("удар в укрытии не проходит", player.hp >= hp1, "hp %.0f" % player.hp)
	ok("герой всё ещё в укрытии", player.hiding)
	finish()


## Встать рядом с вентиляцией: клетка может быть занята постройкой — берём
## свободную клетку с твёрдым полом в пределах двух клеток от вентиляции.
func stand_vent(vent: Vector2i) -> void:
	for r in range(0, 3):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var cell: Vector2i = vent + Vector2i(dx, dy)
				if World.is_solid_cell(cell):
					continue
				if not World.is_solid_cell(Vector2i(cell.x, cell.y + 1)):
					continue
				stand_at_cell(cell)
				return
	stand_at_cell(vent)
