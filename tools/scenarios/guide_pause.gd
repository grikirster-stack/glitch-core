extends ScenarioBase
## Причина паузы грядки (C3, #317). Строка из факта устройства.
## Координаты стены — только если Beams.break_points честно знает клетку.


func run() -> void:
	player.invuln = 1.0e9
	var hud: HUD = UI.hud
	ok("HUD на месте", hud != null)
	if hud == null:
		finish()
		return
	Game.help_hidden = false
	Game.time_of_day = 0.30
	hud._guide_work = null
	var origin: Vector2i = Game.base_mark_cell() + Vector2i(6, 0)
	_air(origin.x - 2, 0, origin.x + 8, origin.y + 3)
	ok("грядка для паузы", MachineBase.place_machine("SporeBed", origin))
	var bed: SporeBed = World.machines.get(origin) as SporeBed
	if bed == null:
		finish()
		return
	# Каркас и дверь уже есть, иначе шаг ещё не про луч.
	World.set_tile(origin.x - 2, origin.y, IDs.T.ROOM_PANEL)
	World.set_tile(origin.x - 2, origin.y - 1, IDs.T.DOOR)
	Game.guide_latch = 3
	_flush()
	await _frames(hud, 3)
	ok("без луча днём: «Нет белого луча»", hud.guide_pause == "Нет белого луча",
			"«%s»" % hud.guide_pause)
	ok("плашка равна причине", hud.plate_text() == "Нет белого луча", "«%s»" % hud.plate_text())
	# Стена на пути белого. Координата — клетка стены, не догадка.
	var col_cell: Vector2i = origin + Vector2i(-4, 0)
	World.set_tile(col_cell.x, col_cell.y, IDs.T.AIR)
	ok("коллектор для стены", MachineBase.place_machine("Collector", col_cell), str(col_cell))
	var col: Collector = World.machines.get(col_cell) as Collector
	if col == null:
		finish()
		return
	col.dir = 0
	# Стена сразу за коллектором. Каркас на origin-2 не трогаем: без него шаг
	# падает ниже луча и причина паузы обнуляется.
	var wall: Vector2i = col_cell + Vector2i(1, 0)
	World.set_tile(wall.x, wall.y, IDs.T.STONE)
	World.set_tile(origin.x - 2, origin.y, IDs.T.ROOM_PANEL)
	col._check_sky()
	_flush()
	var want: String = "Луч перекрыт: стена (%d, %d)" % [wall.x, wall.y]
	var saw_wall: bool = await wait_until(func() -> bool: return hud.guide_pause == want, 1.5)
	var pts: String = ""
	if World.beams != null:
		for p in World.beams.break_points:
			if str(p.get("reason", "")) == "wall" and (int(p.get("color", 0)) & 7) == 7:
				pts += str(p.get("cell")) + " "
	ok("стена из break_points", saw_wall, "«%s»" % hud.guide_pause)
	World.set_tile(wall.x, wall.y, IDs.T.AIR)
	col._check_sky()
	_flush()
	bed.tray = Balance.SPORE_BED_TRAY
	var saw_full: bool = await wait_until(func() -> bool:
		return hud.guide_pause == "Выход полон — забери", 1.5)
	ok("полный лоток: «Выход полон — забери»", saw_full, "«%s»" % hud.guide_pause)
	bed.tray = 0
	Game.time_of_day = Balance.NIGHT_START + 0.02
	_flush()
	var saw_night: bool = await wait_until(func() -> bool:
		return hud.guide_pause == "Ночь: свет гаснет", 1.5)
	ok("ночь: «Ночь: свет гаснет»", saw_night, "«%s»" % hud.guide_pause)
	Game.time_of_day = 0.30
	finish()


func _air(x0: int, y0: int, x1: int, y1: int) -> void:
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			if World.in_bounds(x, y):
				World.set_tile(x, y, IDs.T.AIR)


func _flush() -> void:
	if World.beams != null:
		World.beams.note_machines()
		World.beams.rebuild()


func _frames(hud: HUD, n: int) -> void:
	var f0: int = hud.stat_frames
	await wait_until(func() -> bool: return hud.stat_frames >= f0 + n, 5.0)
