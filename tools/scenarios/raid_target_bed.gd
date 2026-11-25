extends ScenarioBase
## Ночью исправная грядка без солнечного луча — цель налёта (#316).
## Горелка рядом не перебивает грядку. Светлая грядка целью не становится.


func run() -> void:
	var origin: Vector2i = World.beacon_cell + Vector2i(6, -3)
	for y in range(-1, 4):
		for x in range(-1, 6):
			World.set_tile(origin.x + x, origin.y + y, IDs.T.AIR)
	var bed_cell: Vector2i = origin + Vector2i(1, 1)
	var burner_cell: Vector2i = origin + Vector2i(3, 1)
	var bed: SporeBed = RaidCommon.place_bed(bed_cell, false)
	MachineBase.place_machine("Burner", burner_cell)
	ok("тёмная грядка и горелка стоят", bed != null and not bed.lit and World.machines.has(burner_cell))
	RaidCommon.arm(3)
	Threat.tick(0.05)
	ok("цель — тёмная грядка, не горелка", Game.raid_target == bed_cell, "цель %s" % str(Game.raid_target))
	var line: String = RaidCommon.plate()
	ok("плашка назвала грядку", line.contains("грядка") and not line.contains("[E]"), "«%s»" % line)
	# Светлая грядка ночью целью не выбирается: луч включён.
	Game.raid_phase = 0
	bed.beam_receive(Beams.W)
	Threat.tick(0.05)
	ok("зажжённая грядка не приоритет", Game.raid_target != bed_cell or bed.lit == false, "цель %s lit %s" % [str(Game.raid_target), str(bed.lit)])
	finish()
