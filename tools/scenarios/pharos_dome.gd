extends ScenarioBase
## Маяк под голубым (ADR-005 § 5, #168).
##
## Зелёный и синий через смеситель. Горелка в 2 клетках не теряет HP от 5
## ударов эха: купол принимает 100 и гаснет. Через 10 с купол снова есть.


func run() -> void:
	player.invuln = 1.0e9
	var floor_y: int = stand_in_corridor(1)
	await wait(0.3)
	var origin: Vector2i = Vector2i(clampi(World.beacon_cell.x - 70, 20, World.W - 40), floor_y + 14)
	_clear(origin + Vector2i(-6, -8), 28, 18)
	var mix: Vector2i = origin + Vector2i(4, 0)
	ok("смеситель поставлен", MachineBase.place_machine("Mixer", mix))
	var mixer: Mixer = World.machines.get(mix) as Mixer
	var green: Burner = _burn(Vector2i(mix.x, mix.y - 3), IDs.I.COPPER_ORE, 1)
	var blue: Burner = _burn(Vector2i(mix.x, mix.y + 3), IDs.I.CRYSTAL, 3)
	var pc: Vector2i = mix + Vector2i(4, 0)
	ok("маяк поставлен", MachineBase.place_machine("Pharos", pc))
	var pharos: Pharos = World.machines.get(pc) as Pharos
	if mixer == null or green == null or blue == null or pharos == null:
		finish()
		return
	_flush()
	ok("голубой дошёл смесью", pharos.color == Beams.C and pharos.active,
			"цвет %d, луч %d" % [pharos.color, World.beams.color_at(pc + Vector2i(-1, 0))])
	ok("купол включён", pharos.dome_up and World.pharos_dome.has(pharos) and World.dome_at(pc + Vector2i(2, 0)) == pharos)

	var burner_cell: Vector2i = pc + Vector2i(2, 0)
	ok("горелка под куполом", MachineBase.place_machine("Burner", burner_cell))
	var under: Burner = World.machines.get(burner_cell) as Burner
	if under == null:
		finish()
		return
	var hp0: float = under.hp
	# Эхо бьёт 24. Пять ударов — 120, купол держит 100 и гаснет на пятом.
	for _i in 5:
		under.take_damage(Balance.PHANTOMS["echo"]["dmg"])
	ok("горелка под куполом не потеряла HP", is_equal_approx(under.hp, hp0), "hp %.0f" % under.hp)
	ok("купол принял 100 и погас", not pharos.dome_up and pharos.dome_hp <= 0.0, "dome_hp %.0f" % pharos.dome_hp)
	ok("шестой удар уже по горелке", _hurt(under) and under.hp < hp0, "hp %.0f" % under.hp)

	var back: bool = await wait_until(func() -> bool: return pharos.dome_up, 10.5)
	ok("через 10 с купол снова есть", back and is_equal_approx(pharos.dome_hp, Balance.PHAROS_DOME_HP),
			"up %s hp %.0f" % [str(pharos.dome_up), pharos.dome_hp])
	# Дальше 3 клеток (манхэттен) купола нет.
	ok("за 3 клетками купола нет", World.dome_at(pc + Vector2i(4, 0)) == null)
	finish()


func _hurt(m: MachineBase) -> bool:
	var before: float = m.hp
	m.take_damage(Balance.PHANTOMS["echo"]["dmg"])
	return m.hp < before


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


func _clear(origin: Vector2i, w: int, h: int) -> void:
	for x in range(origin.x, origin.x + w):
		for y in range(origin.y, origin.y + h):
			if World.in_bounds(x, y):
				World.set_tile(x, y, IDs.T.AIR)


func _flush() -> void:
	if World.beams != null:
		World.beams.rebuild()
		World._apply_beam_lights()
