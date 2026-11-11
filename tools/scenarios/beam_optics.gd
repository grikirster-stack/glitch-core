extends ScenarioBase
## Зеркало, смеситель, призма (ADR-005 § 4–5, #165).
##
## Таблица § 5: (а) красный поворачивает на зеркале «/», длина 24−2;
## (б) R+G → жёлтый; (в) G+B → голубой, R+B → пурпурный, R+G+B → белый 32−2;
## (г) белый в призме даёт R/G/B, красный проходит прямо; (д) луч в выход
## смесителя гаснет; (е) кольцо из 4 зеркал без источника заканчивается,
## с источником луч идёт по кольцу и кончается по длине; (ж) замер rebuild
## на 10 зеркалах и 3 смесителях.


func run() -> void:
	player.invuln = 1.0e9
	var floor_y: int = stand_in_corridor(2)
	await wait(0.3)
	# Ниже потолка базы: вверх от зеркала нужно 18 клеток воздуха.
	# Площадка внутри мира: горелка на 26 клеток от входа, белый выход — 30.
	var origin: Vector2i = Vector2i(60, 70)
	_clear(Vector2i(8, 8), Vector2i(World.W - 8, 150))

	_check_mirror(origin)
	_check_mixer(origin + Vector2i(40, 40))
	_check_prism(origin + Vector2i(160, 40))
	_check_mixer_sink(origin + Vector2i(280, 40))
	_check_ring(origin + Vector2i(400, 40))
	_bench(origin)
	finish()


## (а) Горелка R → зеркало «/» → луч вверх, длина 24−2.
func _check_mirror(origin: Vector2i) -> void:
	var burner: Burner = _burn(origin, IDs.I.COAL, 0)
	var mirror_cell: Vector2i = origin + Vector2i(6, 0)
	ok("зеркало поставлено", MachineBase.place_machine("Mirror", mirror_cell))
	var mirror: Mirror = World.machines.get(mirror_cell) as Mirror
	if burner == null or mirror == null:
		return
	# dir 0 — «/»: вправо уходит вверх.
	ok("зеркало «/»", mirror.dir % 2 == 0)
	_flush()
	ok("до зеркала луч красный", _lane(origin, Vector2i(1, 0), 1, 5, Beams.R), _dump(origin, Vector2i(1, 0), 8))
	ok("на зеркале луча нет", World.beams.color_at(mirror_cell) == 0)
	# 24 − 2 = 22 клетки после платы; 5 уже пройдены до зеркала → 17 вверх.
	ok("после зеркала луч вверх, длина 22", _lane(mirror_cell, Vector2i(0, -1), 1, 17, Beams.R),
			_dump(mirror_cell, Vector2i(0, -1), 19))
	ok("18-я клетка вверх пуста", World.beams.color_at(mirror_cell + Vector2i(0, -18)) == 0)
	ok("сквозь зеркало луч не прошёл", World.beams.color_at(mirror_cell + Vector2i(1, 0)) == 0)
	# Второй луч в то же зеркало отражается сам, первый не ломает.
	var side: Vector2i = Vector2i(mirror_cell.x, mirror_cell.y + 4)
	var side_b: Burner = _burn(side, IDs.I.COPPER_ORE, 3)
	if side_b != null:
		_flush()
		ok("второй луч отразился вправо", World.beams.color_at(mirror_cell + Vector2i(1, 0)) == Beams.G,
				_dump(mirror_cell, Vector2i(1, 0), 4))
		ok("первый луч всё ещё вверх", World.beams.color_at(mirror_cell + Vector2i(0, -1)) == Beams.R)
		_gone(side_b)
	_gone(burner)
	_gone(mirror)
	_flush()


## (б)(в) Смеси: Y, C, M и белый длиной 32−2.
func _check_mixer(origin: Vector2i) -> void:
	var mix_cell: Vector2i = origin + Vector2i(4, 0)
	ok("смеситель поставлен", MachineBase.place_machine("Mixer", mix_cell))
	var mixer: Mixer = World.machines.get(mix_cell) as Mixer
	if mixer == null:
		return
	# Выход вправо. Входы: слева (R), сверху (G), снизу (B).
	# Горелка стоит на линии своего входа и сбоку от чужого: её корпус — стена для луча.
	var left: Burner = _burn(Vector2i(mix_cell.x - 3, mix_cell.y), IDs.I.COAL, 0)
	var top: Burner = _burn(Vector2i(mix_cell.x, mix_cell.y - 3), IDs.I.COPPER_ORE, 1)
	if left == null or top == null:
		return
	_flush()
	# Клетка 1 — ещё и зелёный луч сквозь выход. Чистая смесь — со 2-й клетки.
	ok("R+G → жёлтый на выходе", World.beams.color_at(mix_cell + Vector2i(2, 0)) == Beams.Y,
			"c1=%d c2=%d" % [World.beams.color_at(mix_cell + Vector2i(1, 0)),
				World.beams.color_at(mix_cell + Vector2i(2, 0))])
	# Бюджет 24 − плата 2 = 22. Первая клетка смешана с зелёным входом, дальше — чистый жёлтый.
	ok("жёлтый длиной 22", _lane(mix_cell, Vector2i(1, 0), 2, 22, Beams.Y),
			_dump(mix_cell, Vector2i(1, 0), 24))
	ok("23-я клетка жёлтого пуста", World.beams.color_at(mix_cell + Vector2i(23, 0)) == 0)

	_gone(top)
	var bot: Burner = _burn(Vector2i(mix_cell.x, mix_cell.y + 3), IDs.I.CRYSTAL, 3)
	_flush()
	ok("R+B → пурпурный", bot != null and World.beams.color_at(mix_cell + Vector2i(2, 0)) == Beams.M,
			"color_at=%d" % World.beams.color_at(mix_cell + Vector2i(2, 0)))

	_gone(left)
	top = _burn(Vector2i(mix_cell.x, mix_cell.y - 3), IDs.I.COPPER_ORE, 1)
	_flush()
	ok("G+B → голубой", top != null and World.beams.color_at(mix_cell + Vector2i(2, 0)) == Beams.C,
			"color_at=%d" % World.beams.color_at(mix_cell + Vector2i(2, 0)))

	left = _burn(Vector2i(mix_cell.x - 3, mix_cell.y), IDs.I.COAL, 0)
	_flush()
	ok("R+G+B → белый", left != null and World.beams.color_at(mix_cell + Vector2i(2, 0)) == Beams.W,
			"color_at=%d" % World.beams.color_at(mix_cell + Vector2i(2, 0)))
	# Белый — 32, минус плата смесителя 2 → 30 клеток выхода.
	ok("белый длиной 30", _lane(mix_cell, Vector2i(1, 0), 2, 30, Beams.W),
			_dump(mix_cell, Vector2i(1, 0), 32))
	# 31-я по горизонтали — клетка синего входа, он идёт вверх сквозь выход.
	ok("31-я клетка белого пуста", World.beams.color_at(mix_cell + Vector2i(31, 0)) == 0,
			"%d" % World.beams.color_at(mix_cell + Vector2i(31, 0)))
	for m in [left, top, bot, mixer]:
		_gone(m)
	_flush()


## (г) Белый в призме → R прямо, G налево, B направо. Красный проходит прямо.
func _check_prism(origin: Vector2i) -> void:
	var prism_cell: Vector2i = origin + Vector2i(4, 0)
	ok("призма поставлена", MachineBase.place_machine("Prism", prism_cell))
	var prism: Prism = World.machines.get(prism_cell) as Prism
	if prism == null:
		return
	var mix_cell: Vector2i = prism_cell + Vector2i(-3, 0)
	ok("смеситель белого", MachineBase.place_machine("Mixer", mix_cell))
	var mixer: Mixer = World.machines.get(mix_cell) as Mixer
	var r: Burner = _burn(Vector2i(mix_cell.x - 3, mix_cell.y), IDs.I.COAL, 0)
	var g: Burner = _burn(Vector2i(mix_cell.x, mix_cell.y - 3), IDs.I.COPPER_ORE, 1)
	var b: Burner = _burn(Vector2i(mix_cell.x, mix_cell.y + 3), IDs.I.CRYSTAL, 3)
	if mixer == null or r == null or g == null or b == null:
		return
	_flush()
	ok("в призму входит белый", (World.beams.color_at(prism_cell + Vector2i(-1, 0)) & Beams.W) == Beams.W,
			"%d" % World.beams.color_at(prism_cell + Vector2i(-1, 0)))
	ok("из призмы красный прямо", World.beams.color_at(prism_cell + Vector2i(2, 0)) == Beams.R,
			_dump(prism_cell, Vector2i(1, 0), 4))
	ok("из призмы зелёный налево", World.beams.color_at(prism_cell + Vector2i(0, -1)) == Beams.G,
			_dump(prism_cell, Vector2i(0, -1), 4))
	ok("из призмы синий направо", World.beams.color_at(prism_cell + Vector2i(0, 1)) == Beams.B,
			_dump(prism_cell, Vector2i(0, 1), 4))
	# Белый 32 − 2 (смеситель) − 2 (призма) = 28 на каждом выходе.
	var red_n: int = 0
	for k in range(1, 40):
		if World.beams.color_at(prism_cell + Vector2i(k, 0)) == Beams.R:
			red_n += 1
		else:
			break
	ok("красный из призмы длиной 26", red_n == 26, "клеток %d" % red_n)
	for m in [r, g, b, mixer]:
		_gone(m)
	_flush()
	var red: Burner = _burn(Vector2i(prism_cell.x - 3, prism_cell.y), IDs.I.COAL, 0)
	_flush()
	ok("красный через призму идёт прямо", red != null
			and World.beams.color_at(prism_cell + Vector2i(1, 0)) == Beams.R
			and World.beams.color_at(prism_cell + Vector2i(0, -1)) == 0
			and World.beams.color_at(prism_cell + Vector2i(0, 1)) == 0,
			_dump(prism_cell, Vector2i(1, 0), 4))
	_gone(red)
	_gone(prism)
	_flush()


## (д) Луч в выходную грань смесителя гаснет, на выходе пусто.
func _check_mixer_sink(origin: Vector2i) -> void:
	var mix_cell: Vector2i = origin + Vector2i(4, 0)
	ok("смеситель для гашения", MachineBase.place_machine("Mixer", mix_cell))
	# Выход смотрит вправо: бьём в него справа налево, сбоку от линии выхода.
	var into: Burner = _burn(Vector2i(mix_cell.x + 3, mix_cell.y + 1), IDs.I.COAL, 2)
	_flush()
	ok("луч в выход гаснет", into != null and World.beams.color_at(mix_cell + Vector2i(-1, 0)) == 0
			and World.beams.color_at(mix_cell + Vector2i(1, 1)) == Beams.R,
			"за выходом %d, перед входом %d" % [
				World.beams.color_at(mix_cell + Vector2i(-1, 0)),
				World.beams.color_at(mix_cell + Vector2i(1, 1))])
	_gone(into)
	_gone(World.machines.get(mix_cell))
	_flush()


## (е) Кольцо из 4 зеркал. Без источника rebuild заканчивается. С источником
## луч идёт по кольцу и кончается по длине — бесконечного прохода нет.
func _check_ring(origin: Vector2i) -> void:
	# Квадрат 3×3, зеркала по углам. «/» и «\» чередуются, чтобы луч шёл по кругу.
	var corners: Array[Vector2i] = [
		origin, origin + Vector2i(0, -3),
		origin + Vector2i(3, -3), origin + Vector2i(3, 0),
	]
	var mirrors: Array = []
	for i in corners.size():
		if not MachineBase.place_machine("Mirror", corners[i]):
			ok("зеркало кольца %d" % i, false)
			return
		var m: Mirror = World.machines[corners[i]]
		# По фактическому отражению: «/» вправо→вверх, «/» вверх→вправо,
		# «\» вправо→вниз, «\» вниз→вправо. Квадрат замыкается.
		m.dir = 0 if i < 2 else 1
		mirrors.append(m)
	var t0: int = Time.get_ticks_usec()
	_flush()
	var us: int = Time.get_ticks_usec() - t0
	ok("кольцо без источника: rebuild завершился", us < 50000 and World.beams.cells.is_empty(),
			"%d мкс, клеток %d" % [us, World.beams.cells.size()])
	# Слева в левое верхнее «/»: вправо отражается вверх, дальше кольцо.
	var burner: Burner = _burn(Vector2i(origin.x - 3, origin.y), IDs.I.COAL, 0)
	_flush()
	# Подход к первому зеркалу и четыре отражения — пять красных отрезков.
	var painted: int = 0
	for s in World.beams.segments:
		if int(s["color"]) == Beams.R and int(s["air"]) > 0:
			painted += 1
	ok("с источником луч идёт по кольцу", burner != null and painted == 5
			and World.beams.color_at(origin + Vector2i(0, -1)) == Beams.R
			and World.beams.color_at(origin + Vector2i(1, -3)) == Beams.R,
			"сегментов %d" % painted)
	# 24 − 2×4 зеркала = 16: 2 до кольца и 14 по нему, дальше пусто.
	var total: int = World.beams.cells.size()
	ok("луч кольца кончился по длине", total == 16, "клеток %d" % total)
	ok("за кольцом луч кончается", World.beams.color_at(origin + Vector2i(12, 0)) == 0,
			"%d" % World.beams.color_at(origin + Vector2i(12, 0)))
	_gone(burner)
	for m in mirrors:
		_gone(m)
	_flush()


## (ж) 10 зеркал и 3 смесителя на пути лучей. Печатает мкс rebuild.
func _bench(origin: Vector2i) -> void:
	var nodes: Array = []
	var y0: int = 130
	for i in 10:
		var c: Vector2i = Vector2i(40 + i * 8, y0)
		_clear(c + Vector2i(-1, -2), c + Vector2i(2, 2))
		if MachineBase.place_machine("Mirror", c):
			nodes.append(World.machines[c])
	for i in 3:
		var c: Vector2i = Vector2i(50 + i * 16, y0 + 8)
		_clear(c + Vector2i(-4, -4), c + Vector2i(8, 4))
		var fed: Burner = _burn(Vector2i(c.x - 3, c.y), IDs.I.COAL, 0)
		var g: Burner = _burn(Vector2i(c.x, c.y - 3), IDs.I.COPPER_ORE, 1)
		if MachineBase.place_machine("Mixer", c):
			nodes.append(World.machines[c])
		if fed != null:
			nodes.append(fed)
		if g != null:
			nodes.append(g)
	_flush()
	World.beams.rebuild()
	var us: int = World.beams.rebuild()
	var again: int = World.beams.rebuild()
	print("  [замер] rebuild 10 зеркал + 3 смесителя: %d мкс, повтор %d мкс (клеток %d, сегментов %d)" % [
			us, again, World.beams.cells.size(), World.beams.segments.size()])
	ok("rebuild оптики уложился в 2 мс", us <= 2000 and again <= 2000, "%d / %d мкс" % [us, again])
	for m in nodes:
		_gone(m)
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
	if b.cell != cell:
		ok("горелка стоит где просили %s" % str(cell), false, str(b.cell))
		return null
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


## Снять постройку сразу. destroy() только ставит queue_free — до конца кадра
## клетка ещё занята, и следующий луч упирается в «снятое» зеркало.
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
