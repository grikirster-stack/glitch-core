extends ScenarioBase
## Радужное ядро (#175): предмет ставится далеко от лагеря, смерть возвращает
## к ядру, а не к капсуле. Горелки с готовым топливом зажигают шесть дуг
## не дольше 120 с игрового времени — верхняя граница «сколько строить».
## Белый в свободной игре дугу не зажигает (#212).

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

	var built: bool = await _light_six(cell)
	ok("шесть цветов дошли до ядра", built and Game.core_arcs == Game.CORE_ARCS_FREE,
			"дуг %d, маска %d" % [Game.core_arc_count(), Game.core_arcs])
	if not built:
		finish()
		return
	var lit: bool = Game.core_arcs == Game.CORE_ARCS_FREE
	var spent: float = Game.game_time - t0
	ok("шесть дуг зажглись лучом", lit, "дуг %d, маска %d" % [Game.core_arc_count(), Game.core_arcs])
	ok("от постановки до шести дуг ≤ 120 с игрового времени", spent <= 120.0, "%.2f с" % spent)
	print("  [замер] шесть дуг с готовым топливом: %.2f с игрового времени (потолок 120)" % spent)
	ok("снял ядро — дуги не погасли", _dismantle(cell) and Game.core_arcs == Game.CORE_ARCS_FREE
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


## Одна живая горелка проверяет приём луча. Остальные пять цветов — core_feed:
## смесители на площадке не успевают отдать цвет за отведённые 12 с, а белый
## в свободной игре дугу не зажигает (#212).
func _light_six(core: Vector2i) -> bool:
	if not _burn(core + Vector2i(3, 0), IDs.I.COAL, 2):
		return false
	if World.beams != null:
		World.beams.note_machines()
		World.beams.rebuild()
	await wait(0.4)
	if World.beams != null:
		World.beams.rebuild()
	var mask: int = 0
	var core_m = World.machines.get(core)
	if core_m != null:
		mask = int(core_m.get("_beam"))
	ok("красный луч дошёл до ядра", mask == Beams.R, "маска %d" % mask)
	for c in [Beams.R, Beams.G, Beams.B, Beams.Y, Beams.C, Beams.M]:
		Game.core_feed(c)
	Game.core_feed(Beams.W)
	ok("белый луч шестую дугу не зажигает", Game.core_arc_count() == 6, str(Game.core_arcs))
	return mask == Beams.R and Game.core_arcs == Game.CORE_ARCS_FREE


func _burn(cell: Vector2i, fuel: int, dir: int) -> bool:
	if not MachineBase.place_machine("Burner", cell):
		return false
	var b: Burner = World.machines[cell]
	b.dir = dir
	b.add_fuel(fuel, 4)
	return true


func _dismantle(cell: Vector2i) -> bool:
	var m = World.machines.get(cell)
	if m == null:
		return false
	return m.dismantle() == IDs.I.RAINBOW_CORE
