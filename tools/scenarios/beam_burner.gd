extends ScenarioBase
## Горелка и луч (ADR-005 § 4–5, #164).
##
## Коридор у базы: горелка с одним углём бьёт красным на 24 клетки, 25-я пуста;
## стена на 8-й клетке обрывает луч; 45 с — гаснет; сундук рядом кормит сам;
## поворот уводит луч, старых клеток в карте нет. Замер rebuild() — 20 горелок.


func run() -> void:
	player.invuln = 1.0e9
	var floor_y: int = stand_in_corridor(2)
	await wait(0.4)
	var origin: Vector2i = Vector2i(World.beacon_cell.x + 4, floor_y - 1)
	_clear_lane(origin, 30)
	var light0: float = World.light_at(origin + Vector2i(10, 0))
	ok("до загрузки на 10-й клетке темно", light0 < 0.1, "%.3f" % light0)

	ok("горелка поставлена", MachineBase.place_machine("Burner", origin), str(origin))
	var burner: Burner = World.machines.get(origin) as Burner
	if burner == null:
		finish()
		return
	ok("уголь принят", burner.add_fuel(IDs.I.COAL, 1) == 1)
	await wait(0.05)
	_flush()
	ok("луч красный на 1..24", _lane_color(origin, 1, 24, Beams.R), _lane_dump(origin, 26))
	ok("25-я клетка пуста", World.beams.color_at(origin + Vector2i(25, 0)) == 0)
	var light1: float = World.light_at(origin + Vector2i(10, 0))
	ok("свет на 10-й клетке ≥ 1", light1 >= 1.0, "%.3f (было %.3f)" % [light1, light0])

	# Стена на 8-й клетке луча: луч кончается на 7-й, сквозь породу не идёт.
	var wall: Vector2i = origin + Vector2i(8, 0)
	World.set_tile(wall.x, wall.y, IDs.T.STONE)
	_flush()
	ok("стена обрывает луч на 7-й", _lane_color(origin, 1, 7, Beams.R)
			and World.beams.color_at(origin + Vector2i(8, 0)) == 0
			and World.beams.color_at(origin + Vector2i(9, 0)) == 0, _lane_dump(origin, 12))
	World.set_tile(wall.x, wall.y, IDs.T.AIR)
	_flush()
	ok("без стены луч снова до 24", _lane_color(origin, 1, 24, Beams.R))

	# 45 с игрового времени — уголь кончился, луч погас.
	var t0: float = Game.game_time
	Engine.time_scale = 15.0
	var burned: bool = await wait_until(func() -> bool:
		return Game.game_time - t0 >= 45.5 and not burner.burning(), 50.0)
	Engine.time_scale = 1.0
	_flush()
	ok("через 45 с луч гаснет", burned and World.beams.color_at(origin + Vector2i(1, 0)) == 0,
			"время %.1f, горит %s" % [Game.game_time - t0, str(burner.burning())])

	# Сундук с 6 углями рядом: горелка сама берёт и горит дальше.
	var chest_cell: Vector2i = origin + Vector2i(0, -1)
	World.set_tile(chest_cell.x, chest_cell.y, IDs.T.AIR)
	ok("сундук рядом", MachineBase.place_machine("Chest", chest_cell))
	var chest: Chest = World.machines.get(chest_cell) as Chest
	if chest != null:
		chest.receive_item(IDs.I.COAL, 6)
	var fed: bool = await wait_until(func() -> bool: return burner.burning(), 2.5)
	_flush()
	ok("горелка сама взяла уголь и горит", fed and World.beams.color_at(origin + Vector2i(1, 0)) == Beams.R,
			"топка %d, burn %.1f" % [burner.fuel_units(), burner.burn_left])
	var left_in_chest: int = 0
	if chest != null:
		for s in chest.slots:
			if s.id == IDs.I.COAL:
				left_in_chest += s.count
	ok("из сундука ушла одна единица", left_in_chest == 5, "осталось %d" % left_in_chest)

	# Поворот: луч вниз, прежних клеток в карте нет.
	burner.turn()
	_flush()
	var down_ok: bool = true
	for k in range(1, 5):
		if World.beams.color_at(origin + Vector2i(0, k)) != Beams.R:
			down_ok = false
	ok("после поворота луч вниз", down_ok and World.beams.color_at(origin + Vector2i(1, 0)) == 0)
	ok("старых клеток в карте нет", World.beams.color_at(origin + Vector2i(3, 0)) == 0)

	_bench(origin)
	_save_roundtrip(origin, burner)
	finish()


## Коридор воздуха на len клеток вправо и пару клеток вокруг — луч не цепляет породу.
func _clear_lane(origin: Vector2i, len: int) -> void:
	for x in range(origin.x - 1, origin.x + len + 2):
		for y in range(origin.y - 2, origin.y + 6):
			if World.in_bounds(x, y):
				World.set_tile(x, y, IDs.T.AIR)


func _lane_color(origin: Vector2i, a: int, b: int, color: int) -> bool:
	for k in range(a, b + 1):
		if World.beams.color_at(origin + Vector2i(k, 0)) != color:
			return false
	return true


func _lane_dump(origin: Vector2i, n: int) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for k in range(1, n + 1):
		parts.append(str(World.beams.color_at(origin + Vector2i(k, 0))))
	return " ".join(parts)


func _flush() -> void:
	if World.beams != null:
		World.beams.rebuild()
		World._apply_beam_lights()


## 20 горелок × 24 клетки. Цель ADR/issue — не дольше 300 мкс на rebuild.
func _bench(origin: Vector2i) -> void:
	var cells: Array[Vector2i] = []
	var y0: int = origin.y + 4
	for i in 20:
		# Свои 24 клетки воздуха, без чужих горелок на пути.
		var c: Vector2i = Vector2i(40 + (i % 5) * 30, y0 + int(i / 5) * 3)
		for k in range(0, 26):
			var a: Vector2i = c + Vector2i(k, 0)
			if World.in_bounds(a.x, a.y):
				World.set_tile(a.x, a.y, IDs.T.AIR)
		if MachineBase.place_machine("Burner", c):
			var b: Burner = World.machines[c]
			b.add_fuel(IDs.I.COAL, 1)
			cells.append(c)
	_flush()
	World.beams.rebuild()   # прогрев: первый вызов платит за сборку словаря клеток
	var us: int = World.beams.rebuild()
	var again: int = World.beams.rebuild()
	print("  [замер] rebuild 20 горелок: %d мкс, повтор %d мкс (клеток %d, сегментов %d)" % [
			us, again, World.beams.cells.size(), World.beams.segments.size()])
	ok("rebuild 20 горелок ≤ 300 мкс", us <= 300 and again <= 300, "%d / %d мкс" % [us, again])
	ok("20 горелок в замере", cells.size() == 20, "%d" % cells.size())
	for c in cells:
		var m: MachineBase = World.machines.get(c)
		if m != null:
			m.destroy()
	_flush()


## Сохранение: топливо, направление и «горит» переживают F5/F9 на слоте сценария.
func _save_roundtrip(origin: Vector2i, burner: Burner) -> void:
	burner.dir = 0
	burner.add_fuel(IDs.I.COAL, 2)
	_flush()
	var fuel_n: int = burner.fuel_units()
	var burn: float = burner.burn_left
	var slot0: String = Save.slot
	Save.slot = "beam"
	Save.remove("beam")
	var packed: PackedByteArray = var_to_bytes(Save.gather())
	Save.apply(Save.decode(packed))
	var back: Burner = World.machines.get(origin) as Burner
	ok("горелка загрузилась", back != null)
	if back != null:
		_flush()
		ok("топливо и направление те же", back.dir == 0 and back.fuel_units() == fuel_n
				and absf(back.burn_left - burn) < 0.05,
				"dir %d, топка %d/%d, burn %.2f/%.2f" % [back.dir, back.fuel_units(), fuel_n, back.burn_left, burn])
		ok("после загрузки горит", back.burning() and World.beams.color_at(origin + Vector2i(1, 0)) == Beams.R)
	Save.remove("beam")
	Save.slot = slot0
