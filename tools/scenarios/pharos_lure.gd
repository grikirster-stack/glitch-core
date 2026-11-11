extends ScenarioBase
## Маяк под пурпурным (ADR-005 § 5, #168).
##
## Красный и синий через смеситель. Рой в 20 клетках за 15 с оказывается
## у маяка, а не у горелки в 5 клетках от роя. Маяк под пурпурным — 200 HP.


func run() -> void:
	player.invuln = 1.0e9
	var floor_y: int = stand_in_corridor(1)
	await wait(0.3)
	var origin: Vector2i = Vector2i(clampi(World.beacon_cell.x + 80, 24, World.W - 48), floor_y + 16)
	_clear(origin + Vector2i(-4, -8), 40, 16)
	var mix: Vector2i = origin + Vector2i(4, 0)
	ok("смеситель поставлен", MachineBase.place_machine("Mixer", mix))
	var red: Burner = _burn(Vector2i(mix.x - 3, mix.y), IDs.I.COAL, 0)
	var blue: Burner = _burn(Vector2i(mix.x, mix.y + 3), IDs.I.CRYSTAL, 3)
	var pc: Vector2i = mix + Vector2i(4, 0)
	ok("маяк поставлен", MachineBase.place_machine("Pharos", pc))
	var pharos: Pharos = World.machines.get(pc) as Pharos
	if red == null or blue == null or pharos == null:
		finish()
		return
	_flush()
	ok("пурпурный дошёл смесью", pharos.color == Beams.M and pharos.active,
			"цвет %d" % pharos.color)
	ok("маяк под пурпурным крепче", is_equal_approx(pharos.max_hp, Balance.PHAROS_LURE_HP)
			and is_equal_approx(pharos.hp, Balance.PHAROS_LURE_HP), "hp %.0f / %.0f" % [pharos.hp, pharos.max_hp])

	# Горелка-приманка старого роя: ближе к стае, чем маяк. Рой всё равно идёт к маяку.
	var bait: Vector2i = pc + Vector2i(15, 0)
	World.set_tile(bait.x, bait.y, IDs.T.AIR)
	ok("горелка-приманка", MachineBase.place_machine("Burner", bait))
	var burner: Burner = World.machines.get(bait) as Burner
	if burner != null:
		burner.add_fuel(IDs.I.COAL, 2)
	# Рой в 20 клетках от маяка и в 5 от горелки.
	var spawn: Vector2i = pc + Vector2i(20, 0)
	World.set_tile(spawn.x, spawn.y, IDs.T.AIR)
	player.global_position = World.cell_to_world(origin + Vector2i(0, 30))
	var swarm: Node = spawn_phantom_at(_foot(spawn), "swarm")
	ok("рой появился", swarm != null)
	if swarm == null:
		finish()
		return
	var near: bool = await wait_until(func() -> bool:
		return is_instance_valid(swarm) and swarm.global_position.distance_to(pharos.global_position) < 28.0, 15.0)
	var to_pharos: float = swarm.global_position.distance_to(pharos.global_position) if is_instance_valid(swarm) else -1.0
	var to_burner: float = swarm.global_position.distance_to(burner.global_position) if is_instance_valid(swarm) and burner != null else -1.0
	print("  [замер] рой за 15 с: до маяка %.0f px, до горелки %.0f px" % [to_pharos, to_burner])
	ok("рой пришёл к маяку, не к горелке", near and swarm.target_machine == pharos and to_pharos < to_burner,
			"цель %s, до маяка %.0f, до горелки %.0f" % [
				String(swarm.target_machine.kind) if swarm.target_machine != null else "нет", to_pharos, to_burner])

	# Смена цвета возвращает 100 HP, текущее не выше нового максимума.
	pharos.hp = 150.0
	pharos.beam_receive(Beams.R)
	ok("без пурпурного снова 100 HP", is_equal_approx(pharos.max_hp, Balance.PHAROS_HP) and pharos.hp <= Balance.PHAROS_HP,
			"hp %.0f / %.0f" % [pharos.hp, pharos.max_hp])
	if is_instance_valid(swarm):
		swarm.queue_free()
	finish()


func _burn(cell: Vector2i, fuel: int, dir: int) -> Burner:
	if not MachineBase.place_machine("Burner", cell):
		return null
	var b: Burner = World.machines.get(cell) as Burner
	if b == null:
		return null
	while b.dir != dir:
		b.turn()
	b.add_fuel(fuel, 2)
	return b


func _foot(c: Vector2i) -> Vector2:
	return Vector2(float(c.x * World.TILE) + 8.0, float(c.y * World.TILE) + 8.0)


func _clear(origin: Vector2i, w: int, h: int) -> void:
	for x in range(origin.x, origin.x + w):
		for y in range(origin.y, origin.y + h):
			if World.in_bounds(x, y):
				World.set_tile(x, y, IDs.T.AIR)


func _flush() -> void:
	if World.beams != null:
		World.beams.rebuild()
		World._apply_beam_lights()
