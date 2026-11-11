extends ScenarioBase
## Восемь направлений луча: диагональ стоит одну клетку длины и не идёт сквозь стену.
##
## Горелка dir 4 бьёт вправо-вниз на 24 клетки. Стена на диагонали обрывает луч.
## Угол двух стен закрыт, одна стена на углу — нет. Старое зеркало dir 0..3
## отражает как раньше. Горизонтальное зеркало переводит прямой луч в диагональ.
## Смеситель, призма и маяк на ортогональном луче не ломаются.


func run() -> void:
	player.invuln = 1.0e9
	stand_in_corridor(2)
	await wait(0.3)
	var origin: Vector2i = Vector2i(80, 90)
	_clear(Vector2i(8, 8), Vector2i(World.W - 8, 180))

	_check_diagonal_length(origin)
	_check_wall(origin + Vector2i(40, 0))
	_check_corner(origin + Vector2i(80, 0))
	_check_old_mirror(origin + Vector2i(0, 40))
	_check_mirror_to_diagonal(origin + Vector2i(40, 40))
	_check_ortho_still(origin + Vector2i(90, 40))
	_check_turn_eight(origin + Vector2i(140, 40))
	finish()


## Диагональ не длиннее прямой: 24 шага, 25-й пуст. Шаг = 1 клетка.
func _check_diagonal_length(origin: Vector2i) -> void:
	var burner: Burner = _burn(origin, IDs.I.COAL, 4)
	if burner == null:
		return
	_flush()
	var step: Vector2i = Beams.DIR[4]
	ok("диагональ красная на 1..24", _lane(origin, step, 1, 24, Beams.R), _dump(origin, step, 26))
	ok("25-я клетка диагонали пуста", World.beams.color_at(origin + step * 25) == 0)
	ok("диагональ не длиннее прямой", World.beams.cells.size() == 24, "клеток %d" % World.beams.cells.size())
	# Соседние по стороне от диагонали не закрашены: луч идёт по клеткам, не по углу.
	ok("сбоку от диагонали пусто", World.beams.color_at(origin + Vector2i(1, 0)) == 0
			and World.beams.color_at(origin + Vector2i(0, 1)) == 0)
	_gone(burner)
	_flush()


## Стена на 6-й клетке диагонали: луч кончается на 5-й, сквозь породу не идёт.
func _check_wall(origin: Vector2i) -> void:
	var burner: Burner = _burn(origin, IDs.I.COAL, 4)
	if burner == null:
		return
	var step: Vector2i = Beams.DIR[4]
	var wall: Vector2i = origin + step * 6
	World.set_tile(wall.x, wall.y, IDs.T.STONE)
	_flush()
	ok("диагональ упирается в стену", _lane(origin, step, 1, 5, Beams.R)
			and World.beams.color_at(wall) == 0
			and World.beams.color_at(wall + step) == 0, _dump(origin, step, 8))
	World.set_tile(wall.x, wall.y, IDs.T.AIR)
	_flush()
	ok("без стены диагональ снова до 24", _lane(origin, step, 1, 24, Beams.R))
	_gone(burner)
	_flush()


## Две стены на углу закрывают щель. Одна стена на углу луч не держит.
func _check_corner(origin: Vector2i) -> void:
	var burner: Burner = _burn(origin, IDs.I.COAL, 4)
	if burner == null:
		return
	var step: Vector2i = Beams.DIR[4]
	# Клетка шага свободна, обе боковые — камень. Сквозь угол идти нельзя.
	var gap: Vector2i = origin + step * 3
	World.set_tile(gap.x, gap.y, IDs.T.AIR)
	# Боковые клетки угла: (gap.x, gap.y - 1) и (gap.x - 1, gap.y).
	World.set_tile(gap.x, gap.y - 1, IDs.T.STONE)
	World.set_tile(gap.x - 1, gap.y, IDs.T.STONE)
	_flush()
	ok("угол двух стен закрыт", _lane(origin, step, 1, 2, Beams.R)
			and World.beams.color_at(gap) == 0
			and World.beams.color_at(gap + step) == 0, _dump(origin, step, 6))
	# Одна стена на углу — щель есть, луч идёт дальше.
	World.set_tile(gap.x - 1, gap.y, IDs.T.AIR)
	_flush()
	ok("одна стена на углу не держит луч", World.beams.color_at(gap) == Beams.R
			and World.beams.color_at(gap + step) == Beams.R, _dump(origin, step, 6))
	World.set_tile(gap.x, gap.y - 1, IDs.T.AIR)
	_gone(burner)
	_flush()


## Старый сейв: dir 0..3 отражает как раньше. «/» вправо → вверх, длина 24−2.
func _check_old_mirror(origin: Vector2i) -> void:
	var burner: Burner = _burn(origin, IDs.I.COAL, 0)
	var mirror_cell: Vector2i = origin + Vector2i(6, 0)
	ok("старое зеркало поставлено", MachineBase.place_machine("Mirror", mirror_cell))
	var mirror: Mirror = World.machines.get(mirror_cell) as Mirror
	if burner == null or mirror == null:
		return
	mirror.load_state({"dir": 0})
	ok("сейв dir 0 остаётся «/»", mirror.dir == 0)
	mirror.load_state({"dir": 1})
	ok("сейв dir 1 остаётся «\\»", mirror.dir == 1)
	mirror.dir = 0
	_flush()
	ok("старое «/»: вправо уходит вверх", _lane(mirror_cell, Vector2i(0, -1), 1, 17, Beams.R),
			_dump(mirror_cell, Vector2i(0, -1), 19))
	ok("старое зеркало не пускает насквозь", World.beams.color_at(mirror_cell + Vector2i(1, 0)) == 0)
	# Восемь шагов: 0 → 1 → … и снова «/».
	for _i in 8:
		mirror.turn()
	ok("восемь поворотов возвращают «/»", mirror.dir == 0)
	_gone(burner)
	_gone(mirror)
	_flush()


## Пологая «/» (dir 4): прямой луч вправо уходит вправо-вверх.
## Обратно диагональ в то же зеркало выходит прямой. Длина 24−2.
func _check_mirror_to_diagonal(origin: Vector2i) -> void:
	var burner: Burner = _burn(origin, IDs.I.COAL, 0)
	var mirror_cell: Vector2i = origin + Vector2i(5, 0)
	ok("зеркало для диагонали", MachineBase.place_machine("Mirror", mirror_cell))
	var mirror: Mirror = World.machines.get(mirror_cell) as Mirror
	if burner == null or mirror == null:
		return
	mirror.dir = 4
	_flush()
	var up_right: Vector2i = Beams.DIR[7]
	ok("прямой луч стал диагональю", _lane(mirror_cell, up_right, 1, 17, Beams.R),
			_dump(mirror_cell, up_right, 19))
	ok("за зеркалом по прямой пусто", World.beams.color_at(mirror_cell + Vector2i(1, 0)) == 0)
	# 4 клетки до зеркала, плата 2, остаток 18. 19-я пуста.
	ok("19-я клетка диагонали пуста", World.beams.color_at(mirror_cell + up_right * 19) == 0)
	_gone(burner)
	_gone(mirror)
	_flush()
	# Обратно — на самой таблице: диагональный вход выходит прямой.
	# В мире горелка на этой диагонали сама себе стена, проверка была бы ложной.
	ok("диагональ в пологой «/» выходит прямой вверх", Mirror._reflect(4, 4) == 3)
	ok("прямая вниз в пологой «/» выходит диагональю", Mirror._reflect(3, 4) == 4)


## Смеситель, призма и маяк на прямом луче — как до восьми направлений.
func _check_ortho_still(origin: Vector2i) -> void:
	var mix_cell: Vector2i = origin + Vector2i(4, 0)
	ok("смеситель на прямом", MachineBase.place_machine("Mixer", mix_cell))
	var left: Burner = _burn(Vector2i(mix_cell.x - 3, mix_cell.y), IDs.I.COAL, 0)
	var top: Burner = _burn(Vector2i(mix_cell.x, mix_cell.y - 3), IDs.I.COPPER_ORE, 1)
	if left == null or top == null:
		return
	_flush()
	ok("R+G на прямом всё ещё жёлтый", World.beams.color_at(mix_cell + Vector2i(2, 0)) == Beams.Y,
			"%d" % World.beams.color_at(mix_cell + Vector2i(2, 0)))
	var prism_cell: Vector2i = mix_cell + Vector2i(6, 0)
	ok("призма на жёлтом", MachineBase.place_machine("Prism", prism_cell))
	_flush()
	ok("жёлтый сквозь призму идёт прямо", World.beams.color_at(prism_cell + Vector2i(1, 0)) == Beams.Y)
	var pharos_cell: Vector2i = mix_cell + Vector2i(0, 6)
	ok("маяк поставлен", MachineBase.place_machine("Pharos", pharos_cell))
	var into: Burner = _burn(pharos_cell + Vector2i(-3, 0), IDs.I.COAL, 0)
	_flush()
	var pharos: Pharos = World.machines.get(pharos_cell) as Pharos
	ok("маяк принял прямой красный", into != null and pharos != null and pharos.color == Beams.R
			and World.beams.color_at(pharos_cell) == 0,
			"цвет %d" % (pharos.color if pharos != null else -1))
	for m in [left, top, into, World.machines.get(mix_cell), World.machines.get(prism_cell), pharos]:
		_gone(m)
	_flush()


## ПКМ-поворот горелки: восемь положений, не свободный угол.
func _check_turn_eight(origin: Vector2i) -> void:
	var burner: Burner = _burn(origin, IDs.I.COAL, 0)
	if burner == null:
		return
	var seen: Dictionary = {}
	for i in 8:
		_flush()
		var step: Vector2i = Beams.DIR[burner.dir]
		ok("поворот %d бьёт в DIR" % i, World.beams.color_at(origin + step) == Beams.R, "dir %d" % burner.dir)
		seen[burner.dir] = true
		burner.turn()
	ok("восемь разных направлений", seen.size() == 8, "%d" % seen.size())
	ok("после восьми поворотов снова вправо", burner.dir == 0)
	# Сеть: байт направления переживает net_state, старый пакет без него не ломает.
	burner.dir = 4
	var packed: PackedByteArray = burner.net_state()
	burner.dir = 0
	var ate: int = burner.apply_net_state(packed)
	ok("сеть вернула диагональ горелки", ate == 6 and burner.dir == 4, "dir %d, съел %d" % [burner.dir, ate])
	# Старый пакет собирался при dir 1: два бита базы, старшие биты пламени — нули.
	burner.dir = 1
	var old: PackedByteArray = burner.net_state()
	old[4] = int(old[4]) & 31
	burner.dir = 4
	ok("старый пакет горелки без наклона читается", burner.apply_net_state(old) == 6 and burner.dir == 1,
			"dir %d" % burner.dir)
	var mirror: Mirror = null
	if MachineBase.place_machine("Mirror", origin + Vector2i(2, 2)):
		mirror = World.machines[origin + Vector2i(2, 2)]
		mirror.dir = 4
		var mb: PackedByteArray = mirror.net_state()
		mirror.dir = 0
		ok("сеть вернула наклон зеркала", mirror.apply_net_state(mb) == 5 and mirror.dir == 4,
				"dir %d" % mirror.dir)
		mirror.dir = 1
		var mold: PackedByteArray = mirror.net_state().slice(0, 4)
		mirror.dir = 4
		ok("старый пакет зеркала без байта читается", mirror.apply_net_state(mold) == 4 and mirror.dir == 1,
				"dir %d" % mirror.dir)
		_gone(mirror)
	_gone(burner)
	_flush()


func _burn(cell: Vector2i, fuel: int, dir: int) -> Burner:
	if not World.in_bounds(cell.x, cell.y):
		ok("горелка в пределах мира %s" % str(cell), false)
		return null
	_clear(cell + Vector2i(-1, -1), cell + Vector2i(1, 1))
	if not MachineBase.place_machine("Burner", cell):
		ok("горелка в %s" % str(cell), false)
		return null
	var b: Burner = World.machines[cell]
	b.dir = dir & 7
	if World.beams != null:
		World.beams.note_machines()
	b.add_fuel(fuel, 1)
	return b


func _clear(a: Vector2i, b: Vector2i) -> void:
	for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
		for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
			if World.in_bounds(x, y):
				World.set_tile(x, y, IDs.T.AIR)


func _lane(origin: Vector2i, step: Vector2i, a: int, b: int, color: int) -> bool:
	for k in range(a, b + 1):
		if World.beams.color_at(origin + step * k) != color:
			return false
	return true


func _dump(origin: Vector2i, step: Vector2i, n: int) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for k in range(1, n + 1):
		parts.append(str(World.beams.color_at(origin + step * k)))
	return " ".join(parts)


func _gone(m) -> void:
	if m == null or not is_instance_valid(m):
		return
	if World.machines.get(m.cell) == m:
		World.machines.erase(m.cell)
	if World.beams != null:
		World.beams.note_machines()
	m.queue_free()


func _flush() -> void:
	if World.beams != null:
		World.beams.rebuild()
		World._apply_beam_lights()
