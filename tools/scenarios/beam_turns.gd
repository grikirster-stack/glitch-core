extends ScenarioBase
## Повороты луча: плата зеркала — только его клетка, обрыв виден.
##
## (а) Горелка → зеркала на 6, 12 и 18-й клетке хода → маяк после последнего
## поворота принимает красный. Свет в 24 клетки проходит 24 клетки хода.
## (б) Стена после двух поворотов: break_points с причиной wall, наружу
## отдаётся маркер, сегмента нулевой длины нет.
## (в) Зеркало на 24-й клетке хода и дальше бюджета нет: обрыв budget помечен,
## отражённый луч не выбрасывается молча.


func run() -> void:
	player.invuln = 1.0e9
	stand_in_corridor(2)
	await wait(0.3)
	var origin: Vector2i = Vector2i(80, 90)
	_clear(Vector2i(8, 8), Vector2i(World.W - 8, 180))

	_check_three_turns(origin)
	_check_wall_break(origin + Vector2i(0, 40))
	_check_budget_break(origin + Vector2i(0, 80))
	finish()


## Три зеркала и потребитель. Ход: 5 + 1 + 5 + 1 + 5 + 1 + 5 + 1 = 24.
func _check_three_turns(origin: Vector2i) -> void:
	var burner: Burner = _burn(origin, IDs.I.COAL, 0)
	var m1: Vector2i = origin + Vector2i(6, 0)
	var m2: Vector2i = m1 + Vector2i(0, -6)
	# «/» вверх отражает вправо — ход не возвращается в горелку.
	var m3: Vector2i = m2 + Vector2i(6, 0)
	# Клетки 19..23 — воздух, 24-я — маяк.
	var sink: Vector2i = m3 + Vector2i(0, 6)
	ok("зеркало 1 на 6-й", MachineBase.place_machine("Mirror", m1))
	ok("зеркало 2 на 12-й", MachineBase.place_machine("Mirror", m2))
	ok("зеркало 3 на 18-й", MachineBase.place_machine("Mirror", m3))
	ok("маяк после поворота", MachineBase.place_machine("Pharos", sink))
	var a: Mirror = World.machines.get(m1) as Mirror
	var b: Mirror = World.machines.get(m2) as Mirror
	var c: Mirror = World.machines.get(m3) as Mirror
	var pharos: Pharos = World.machines.get(sink) as Pharos
	if burner == null or a == null or b == null or c == null or pharos == null:
		return
	# «/» вправо→вверх, «/» вверх→вправо, «\» вправо→вниз к маяку.
	a.dir = 0
	b.dir = 0
	c.dir = 1
	_flush()
	ok("до первого зеркала луч красный", _lane(origin, Vector2i(1, 0), 1, 5, Beams.R))
	ok("после первого зеркала вверх", _lane(m1, Vector2i(0, -1), 1, 5, Beams.R))
	ok("после второго зеркала вправо", _lane(m2, Vector2i(1, 0), 1, 5, Beams.R))
	ok("после третьего зеркала вниз до маяка", _lane(m3, Vector2i(0, 1), 1, 5, Beams.R),
			_dump(m3, Vector2i(0, 1), 8))
	ok("маяк принял красный", pharos.color == Beams.R, "цвет %d" % pharos.color)
	ok("на клетке маяка луча нет", World.beams.color_at(sink) == 0)
	ok("сегмента нулевой длины нет", not _zero_seg())
	var walked: int = _air_total()
	ok("три зеркала: пройдено 20 клеток воздуха", walked == 20, "клеток %d" % walked)
	for m in [burner, a, b, c, pharos]:
		_gone(m)
	_flush()


## Стена на пути после двух поворотов. Обрыв wall виден, нулевого сегмента нет.
func _check_wall_break(origin: Vector2i) -> void:
	var burner: Burner = _burn(origin, IDs.I.COAL, 0)
	var m1: Vector2i = origin + Vector2i(6, 0)
	var m2: Vector2i = m1 + Vector2i(0, -6)
	ok("зеркало стены 1", MachineBase.place_machine("Mirror", m1))
	ok("зеркало стены 2", MachineBase.place_machine("Mirror", m2))
	var a: Mirror = World.machines.get(m1) as Mirror
	var b: Mirror = World.machines.get(m2) as Mirror
	if burner == null or a == null or b == null:
		return
	a.dir = 0
	b.dir = 0
	# Стена через две клетки после второго поворота: одна клетка света, потом порода.
	# Второе «/» вверх уводит вправо.
	var wall: Vector2i = m2 + Vector2i(3, 0)
	World.set_tile(wall.x, wall.y, IDs.T.STONE)
	_flush()
	var br: Array = World.beams.break_points
	var hit: Dictionary = _break_at(br, wall, "wall")
	ok("обрыв стены в break_points", not hit.is_empty(), _break_dump(br))
	ok("цвет обрыва стены красный", int(hit.get("color", 0)) == Beams.R)
	ok("маркер обрыва отдан наружу", _marker_of(hit))
	var face: Vector2 = _break_face(wall)
	ok("грань стены найдена", face != Vector2.ZERO, "face %s" % str(face))
	ok("штрих искры длиннее нуля", _mark_arm() > 0.0, "arm %.2f" % _mark_arm())
	ok("у стены нет сегмента нулевой длины", not _zero_seg())
	_check_span_wall(wall)
	ok("клетка перед стеной освещена", World.beams.color_at(wall + Vector2i(-1, 0)) == Beams.R)
	ok("сквозь стену луч не прошёл", World.beams.color_at(wall + Vector2i(1, 0)) == 0)
	World.set_tile(wall.x, wall.y, IDs.T.AIR)
	for m in [burner, a, b]:
		_gone(m)
	_flush()


## Зеркало на 24-й клетке хода: его клетка — последняя, вверх бюджета нет.
## На 23-й ещё остаётся одна клетка — это не обрыв, а короткий ход.
func _check_budget_break(origin: Vector2i) -> void:
	var burner: Burner = _burn(origin, IDs.I.COAL, 0)
	# 23 клетки воздуха, зеркало — 24-я клетка хода. Вверх бюджета нет.
	var mirror_cell: Vector2i = origin + Vector2i(24, 0)
	ok("зеркало на 24-й", MachineBase.place_machine("Mirror", mirror_cell))
	var mirror: Mirror = World.machines.get(mirror_cell) as Mirror
	if burner == null or mirror == null:
		return
	mirror.dir = 0
	_flush()
	ok("до дальнего зеркала 23 клетки красного", _lane(origin, Vector2i(1, 0), 1, 23, Beams.R),
			_dump(origin, Vector2i(1, 0), 25))
	ok("вверх от дальнего зеркала пусто", World.beams.color_at(mirror_cell + Vector2i(0, -1)) == 0)
	var br: Array = World.beams.break_points
	var hit: Dictionary = _break_at(br, mirror_cell, "budget")
	ok("обрыв бюджета помечен", not hit.is_empty(), _break_dump(br))
	ok("цвет обрыва бюджета красный", int(hit.get("color", 0)) == Beams.R)
	ok("маркер бюджетного обрыва отдан", _marker_of(hit))
	ok("штрих бюджетного обрыва длиннее нуля", _mark_arm() > 0.0, "arm %.2f" % _mark_arm())
	ok("после дальнего зеркала нет нулевого сегмента", not _zero_seg())
	_check_span_budget(mirror_cell)
	_gone(burner)
	_gone(mirror)
	_flush()


func _break_at(points: Array, cell: Vector2i, reason: String) -> Dictionary:
	for p in points:
		if p is Dictionary and p.get("cell") == cell and str(p.get("reason", "")) == reason:
			return p
	return {}


func _marker_of(hit: Dictionary) -> bool:
	if hit.is_empty():
		return false
	return str(hit.get("marker", "")) != ""


## Та же геометрия, что рисует WorldFX._break_face: to сегмента уже на клетке
## стены, to + step промахивается. Headless не рисует — проверяем данные.
func _break_face(cell: Vector2i) -> Vector2:
	for s in World.beams.segments:
		var step: Vector2i = Beams.DIR[int(s["dir"]) & 7]
		if s["to"] == cell:
			return Vector2(step)
	for s in World.beams.segments:
		var step: Vector2i = Beams.DIR[int(s["dir"]) & 7]
		if s["to"] + step == cell:
			return Vector2(step)
	return Vector2.ZERO


## Экранная длина штриха. WorldFX.BREAK_MARK_PX — тот же крест, что на кадре.
func _mark_arm() -> float:
	return WorldFX.BREAK_MARK_PX


## Геометрия линии без отрисовки. На 7a6cef9 хвост ноги имел альфу ~0.85,
## а конец стены совпадал с центром клетки, не с гранью.
func _fx() -> GDScript:
	return load("res://scripts/ui/world_fx.gd")


func _check_span_wall(wall: Vector2i) -> void:
	var fx: GDScript = _fx()
	var tile: float = float(World.TILE)
	var found: bool = false
	for s in World.beams.segments:
		var span: Dictionary = fx.beam_span(s)
		ok("альфа линии стены 1", is_equal_approx(float(span["alpha"]), 1.0),
				"alpha %.3f" % float(span["alpha"]))
		if s["to"] != wall:
			continue
		found = true
		var step: Vector2 = Vector2(Beams.DIR[int(s["dir"]) & 7])
		var face: Vector2 = World.cell_to_world(wall) - step * tile * 0.5
		ok("конец стены на грани", span["b"].is_equal_approx(face),
				"b %s грань %s" % [str(span["b"]), str(face)])
		var mark: Vector2 = fx.break_mark_at(wall, "wall")
		ok("крест стены на конце линии", mark.is_equal_approx(span["b"]),
				"крест %s линия %s" % [str(mark), str(span["b"])])
	ok("нога стены найдена", found)


func _check_span_budget(cell: Vector2i) -> void:
	var fx: GDScript = _fx()
	var found: bool = false
	for s in World.beams.segments:
		var span: Dictionary = fx.beam_span(s)
		ok("альфа линии бюджета 1", is_equal_approx(float(span["alpha"]), 1.0),
				"alpha %.3f" % float(span["alpha"]))
		var step: Vector2i = Beams.DIR[int(s["dir"]) & 7]
		# Сегмент закрывается на последней освещённой: зеркало на 24-й — следующая.
		if s["to"] + step != cell and s["to"] != cell:
			continue
		found = true
		var center: Vector2 = World.cell_to_world(s["to"])
		ok("конец бюджета в центре последней клетки", span["b"].is_equal_approx(center),
				"b %s центр %s" % [str(span["b"]), str(center)])
		var mark: Vector2 = fx.break_mark_at(cell, "budget")
		ok("крест бюджета на конце линии", mark.is_equal_approx(span["b"]),
				"крест %s линия %s" % [str(mark), str(span["b"])])
	ok("нога бюджета найдена", found)


func _break_dump(points: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for p in points:
		if p is Dictionary:
			parts.append("%s %s %s" % [str(p.get("cell")), str(p.get("reason")), str(p.get("color"))])
	return " ".join(parts) if not parts.is_empty() else "пусто"


func _zero_seg() -> bool:
	for s in World.beams.segments:
		if int(s.get("air", 0)) <= 0 or float(s.get("strength", 1.0)) <= 0.0:
			return true
	return false


func _air_total() -> int:
	var n: int = 0
	for s in World.beams.segments:
		n += int(s.get("air", 0))
	return n


func _burn(cell: Vector2i, fuel: int, dir: int) -> Burner:
	if not World.in_bounds(cell.x, cell.y):
		ok("горелка в пределах мира %s" % str(cell), false)
		return null
	_clear(cell + Vector2i(-1, -1), cell + Vector2i(1, 1))
	if not MachineBase.place_machine("Burner", cell):
		ok("горелка в %s" % str(cell), false)
		return null
	var b: Burner = World.machines[cell]
	b.dir = dir & 3
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
