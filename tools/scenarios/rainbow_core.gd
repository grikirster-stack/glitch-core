extends ScenarioBase
## Радужное ядро (#175): предмет ставится далеко от лагеря, смерть возвращает
## к ядру, а не к капсуле. Семь горелок с готовым топливом зажигают семь дуг
## не дольше 120 с игрового времени — верхняя граница «сколько строить».

const FAR: int = 200


func run() -> void:
	player.invuln = 1.0e9
	var camp: Vector2i = World.beacon_cell
	var chest: Chest = World.machines.get(World.camp_chest_cell)
	ok("в сундуке лагеря лежит ядро", chest != null and chest is Chest
			and _chest_has(chest, IDs.I.RAINBOW_CORE) >= 1, str(World.camp_chest_cell))
	var cell: Vector2i = _far_cell(camp)
	ok("площадка в %d клетках от лагеря" % FAR, absi(cell.x - camp.x) >= FAR, str(cell))
	if cell.x < 0:
		finish()
		return
	_clear(cell)
	var t0: float = Game.game_time
	ok("ядро поставлено далеко", MachineBase.place_machine("RainbowCore", cell)
			and Game.core_cell == cell, "%s, лагерь %s" % [str(cell), str(camp)])

	# Смерть и возрождение — до лучей: дуги не должны зависеть от того, стоит ли ядро.
	player.global_position = World.cell_to_world(cell) + Vector2(24.0, -20.0)
	player.vel = Vector2.ZERO
	var death_at: Vector2 = player.global_position
	player.invuln = 0.0
	player.damage(Player.MAX_HP * 2.0, Vector2.ZERO)
	await await_frame()
	ok("герой погиб далеко от лагеря", player.dead and death_at.distance_to(World.cell_to_world(camp)) > 1000.0)
	var back: bool = await wait_until(func() -> bool: return not player.dead, Balance.RESPAWN_DELAY + 3.0)
	var at: Vector2 = Game.respawn_point()
	ok("возродился у ядра, не у капсулы", back
			and player.global_position.distance_to(at) < 24.0
			and player.global_position.distance_to(World.spawn_point) > 200.0,
			"герой %s, точка %s, капсула %s" % [str(player.global_position), str(at), str(World.spawn_point)])
	player.invuln = 1.0e9

	var built: bool = _light_seven(cell)
	ok("семь цветов поставлены горелками и смесителями", built)
	if not built:
		finish()
		return
	if World.beams != null:
		World.beams.note_machines()
		World.beams.rebuild()
	var lit: bool = await wait_until(func() -> bool: return Game.core_arcs == 0x7F, 12.0)
	var spent: float = Game.game_time - t0
	ok("семь дуг зажглись лучом", lit, "дуг %d, маска %d" % [Game.core_arc_count(), Game.core_arcs])
	ok("от постановки до семи дуг ≤ 120 с игрового времени", spent <= 120.0, "%.2f с" % spent)
	print("  [замер] семь дуг с готовым топливом: %.2f с игрового времени (потолок 120)" % spent)
	ok("снял ядро — дуги не погасли", _dismantle(cell) and Game.core_arcs == 0x7F
			and not Game.core_placed(), "дуг %d" % Game.core_arc_count())
	finish()


func _chest_has(ch: Chest, id: int) -> int:
	var n: int = 0
	for s in ch.slots:
		if not s.is_empty() and s.id == id:
			n += s.count
	return n


func _far_cell(camp: Vector2i) -> Vector2i:
	var x: int = clampi(camp.x + FAR, 8, World.W - 16)
	if absi(x - camp.x) < FAR:
		x = clampi(camp.x - FAR, 8, World.W - 16)
	var y: int = World.surface[x] - 1
	return Vector2i(x, y)


func _clear(cell: Vector2i) -> void:
	for x in range(cell.x - 16, cell.x + 16):
		for y in range(cell.y - 14, cell.y + 2):
			if World.in_bounds(x, y):
				World.set_tile(x, y, IDs.T.AIR)
	for x in range(cell.x - 16, cell.x + 16):
		if World.in_bounds(x, cell.y + 1):
			World.set_tile(x, cell.y + 1, IDs.T.STEEL)


## Семь цветов отдельными линиями. Смесь идёт в зеркало, зеркало — в ядро:
## лучи не пересекаются и не гасят друг друга. Смеситель отдаёт цвет со второго
## прохода, зеркало — сразу. Топливо уже в топке.
func _light_seven(core: Vector2i) -> bool:
	# Красный справа, зелёный сверху, синий слева.
	if not _burn(core + Vector2i(3, 0), IDs.I.COAL, 2):
		return false
	if not _burn(core + Vector2i(0, -3), IDs.I.COPPER_ORE, 1):
		return false
	if not _burn(core + Vector2i(-3, 0), IDs.I.CRYSTAL, 0):
		return false
	# Четыре линии на разных рядах: зеркало, смеситель и горелки не делят клетку.
	if not _lane(core + Vector2i(2, -5), IDs.I.COAL, IDs.I.COPPER_ORE):
		return false
	if not _lane(core + Vector2i(2, -8), IDs.I.COPPER_ORE, IDs.I.CRYSTAL):
		return false
	if not _lane(core + Vector2i(-6, -5), IDs.I.COAL, IDs.I.CRYSTAL):
		return false
	if not _lane3(core + Vector2i(-6, -8)):
		return false
	return true


func _burn(cell: Vector2i, fuel: int, dir: int) -> bool:
	if not MachineBase.place_machine("Burner", cell):
		return false
	var b: Burner = World.machines[cell]
	b.dir = dir
	b.add_fuel(fuel, 4)
	return true


## Смеситель справа от зеркала: выход влево в зеркало «/», зеркало шлёт вниз.
## Горелки — справа и сверху от смесителя, выше пола.
func _lane(mirror: Vector2i, fuel_a: int, fuel_b: int) -> bool:
	if not _mirror_down(mirror):
		return false
	# Горелка справа бьёт влево, горелка сверху — вниз. Обе выше пола.
	return _mix(mirror + Vector2i(2, 0), 2, fuel_a, 2, fuel_b, 1)


func _lane3(mirror: Vector2i) -> bool:
	if not _mirror_down(mirror):
		return false
	return _mix3(mirror + Vector2i(2, 0), 2, IDs.I.COAL, IDs.I.COPPER_ORE, IDs.I.CRYSTAL)


func _mirror_down(cell: Vector2i) -> bool:
	if not MachineBase.place_machine("Mirror", cell):
		return false
	var m: Mirror = World.machines[cell]
	m.dir = 0
	return true


## Смеситель: выход dir, два входа с соседних горелок.
func _mix(cell: Vector2i, dir: int, fuel_a: int, dir_a: int, fuel_b: int, dir_b: int) -> bool:
	if not MachineBase.place_machine("Mixer", cell):
		return false
	var m: Mixer = World.machines[cell]
	m.dir = dir
	var a: Vector2i = cell + _back(dir_a, 2)
	var b: Vector2i = cell + _back(dir_b, 2)
	return _burn(a, fuel_a, dir_a) and _burn(b, fuel_b, dir_b)


func _mix3(cell: Vector2i, dir: int, fuel_a: int, fuel_b: int, fuel_c: int) -> bool:
	if not _mix(cell, dir, fuel_a, 2, fuel_b, 1):
		return false
	return _burn(cell + Vector2i(0, 2), fuel_c, 3)


func _back(dir: int, n: int) -> Vector2i:
	return -Beams.DIR[dir] * n


func _dismantle(cell: Vector2i) -> bool:
	var m = World.machines.get(cell)
	if m == null:
		return false
	return m.dismantle() == IDs.I.RAINBOW_CORE
