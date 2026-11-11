extends ScenarioBase
## Маяк под зелёным (ADR-005 § 5, #167).
##
## Горелка с медной рудой бьёт в маяк. Машина с 40 HP рядом доходит до 100
## за 9 с (+20 раз в 3 с). Сам маяк от take_damage(50) HP не теряет.


func run() -> void:
	player.invuln = 1.0e9
	var floor_y: int = stand_in_corridor(1)
	await wait(0.3)
	var origin: Vector2i = Vector2i(clampi(World.beacon_cell.x + 36, 8, World.W - 24), floor_y + 8)
	for x in range(origin.x - 2, origin.x + 14):
		for y in range(origin.y - 4, origin.y + 5):
			if World.in_bounds(x, y):
				World.set_tile(x, y, IDs.T.AIR)
	ok("горелка поставлена", MachineBase.place_machine("Burner", origin))
	var burner: Burner = World.machines.get(origin) as Burner
	var pc: Vector2i = origin + Vector2i(4, 0)
	ok("маяк поставлен", MachineBase.place_machine("Pharos", pc))
	var pharos: Pharos = World.machines.get(pc) as Pharos
	var chest_cell: Vector2i = pc + Vector2i(2, 0)
	ok("сундук рядом", MachineBase.place_machine("Chest", chest_cell))
	var chest: Chest = World.machines.get(chest_cell) as Chest
	if burner == null or pharos == null or chest == null:
		finish()
		return
	ok("медь принята", burner.add_fuel(IDs.I.COPPER_ORE, 2) == 2)
	_flush()
	ok("зелёный дошёл до маяка", pharos.color == Beams.G and pharos.active, "цвет %d" % pharos.color)
	ok("луч в маяке погас", World.beams.color_at(pc) == 0 and World.beams.color_at(pc + Vector2i(1, 0)) == 0)

	chest.hp = 40.0
	var hp0: float = pharos.hp
	pharos.take_damage(50.0)
	ok("маяк под зелёным не теряет HP", is_equal_approx(pharos.hp, hp0), "hp %.0f" % pharos.hp)

	var t0: float = now_proc()
	var full: bool = await wait_until(func() -> bool: return chest.hp >= chest.max_hp - 0.01, 9.5)
	var secs: float = now_proc() - t0
	print("  [замер] лечение: сундук 40 → %.0f за %.2f с (цель 100 за ≤ 9 с, +20 / 3 с)" % [chest.hp, secs])
	ok("сундук починен до 100 за ≤ 9 с", full and secs <= 9.0 and is_equal_approx(chest.hp, chest.max_hp),
			"hp %.0f за %.2f с, починок %d" % [chest.hp, secs, pharos.heals])
	ok("починок было три", pharos.heals == 3, "%d" % pharos.heals)
	# Сам маяк зелёный не лечит — ему и так не больно.
	ok("маяк сам себя не чинил", is_equal_approx(pharos.hp, hp0))

	# Дальше 3 клеток — не достаёт.
	var far_cell: Vector2i = pc + Vector2i(5, 0)
	World.set_tile(far_cell.x, far_cell.y, IDs.T.AIR)
	ok("дальний сундук поставлен", MachineBase.place_machine("Chest", far_cell))
	var far: Chest = World.machines.get(far_cell) as Chest
	if far != null:
		far.hp = 40.0
		var heals0: int = pharos.heals
		await wait(3.2)
		ok("за 3 клетками маяк не чинит", is_equal_approx(far.hp, 40.0) and pharos.heals == heals0,
				"hp %.0f, починок %d" % [far.hp, pharos.heals - heals0])
	finish()


func _flush() -> void:
	if World.beams != null:
		World.beams.rebuild()
		World._apply_beam_lights()
