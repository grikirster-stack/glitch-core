extends ScenarioBase
## Коллектор и накопитель (ADR-005 § 4, #166).
##
## (а) полдень, открытое небо → белый луч 32; блок над коллектором гасит;
## (б) накопитель на пути: за 10 с stored ≈ 10;
## (в) вечер → коллектор молчит, накопитель отдаёт W, за 10 с запас кончается;
## (г) рубильник «отдавать» при живом входе отдаёт и не копит;
## (д) красный в накопитель с зелёным запасом запас не меняет.
## Печатает, сколько секунд белого даёт коллектор за день и сколько
## накопитель отдаёт за ночь.


func run() -> void:
	player.invuln = 1.0e9
	stand_in_corridor(2)
	await wait(0.3)
	# Ниже потолка базы: белому нужно 32 клетки воздуха, столбец до y = 0 — пустой.
	var origin: Vector2i = Vector2i(80, 40)
	_clear(Vector2i(origin.x - 4, 0), Vector2i(origin.x + 40, origin.y + 8))
	Game.time_of_day = 0.30
	await await_frame()

	await _check_open(origin)
	await _check_store(origin + Vector2i(0, 6))
	await _check_night(origin + Vector2i(0, 6))
	await _check_switch(origin + Vector2i(8, 0))
	_check_foreign(origin + Vector2i(16, 0))
	_save_roundtrip(origin + Vector2i(24, 0))
	_day_yield(origin + Vector2i(0, 4))
	finish()


## (а) Полдень, открытое небо: белый на 32 клетки. Блок над ним гасит.
func _check_open(origin: Vector2i) -> void:
	ok("коллектор поставлен", MachineBase.place_machine("Collector", origin))
	var col: Collector = World.machines.get(origin) as Collector
	if col == null:
		return
	col.dir = 0
	col._check_sky()
	_flush()
	ok("днём небо открыто", col.sky_open and col.emitting(),
			"небо %s, день %.2f" % [str(col.sky_open), Game.daylight()])
	ok("белый луч длиной 32", _lane(origin, Vector2i(1, 0), 1, 32, Beams.W),
			_dump(origin, Vector2i(1, 0), 34))
	ok("33-я клетка пуста", World.beams.color_at(origin + Vector2i(33, 0)) == 0)
	# Крыша в том же столбце, не на линии луча.
	var roof: Vector2i = Vector2i(origin.x, origin.y - 3)
	World.set_tile(roof.x, roof.y, IDs.T.STONE)
	_flush()
	ok("блок над коллектором гасит луч", not col.sky_open and not col.emitting()
			and World.beams.color_at(origin + Vector2i(1, 0)) == 0,
			"небо %s, клетка %d" % [str(col.sky_open), World.beams.color_at(origin + Vector2i(1, 0))])
	World.set_tile(roof.x, roof.y, IDs.T.AIR)
	col._check_sky()
	_flush()
	ok("без крыши луч снова белый", col.emitting() and World.beams.color_at(origin + Vector2i(1, 0)) == Beams.W)
	_gone(col)
	_flush()


## (б) Накопитель на пути белого: за 10 с stored ≈ 10, наружу ещё не отдаёт.
func _check_store(origin: Vector2i) -> void:
	var acc_cell: Vector2i = origin + Vector2i(4, 0)
	ok("накопитель на пути", MachineBase.place_machine("Accumulator", acc_cell))
	var acc: Accumulator = World.machines.get(acc_cell) as Accumulator
	ok("коллектор для запаса", MachineBase.place_machine("Collector", origin))
	var col: Collector = World.machines.get(origin) as Collector
	if acc == null or col == null:
		return
	acc.dir = 0
	col.dir = 0
	col._check_sky()
	_flush()
	ok("белый доходит до накопителя", World.beams.color_at(acc_cell + Vector2i(-1, 0)) == Beams.W,
			_dump(origin, Vector2i(1, 0), 6))
	ok("сквозь накопитель луч не идёт", World.beams.color_at(acc_cell + Vector2i(1, 0)) == 0)
	var t0: float = Game.game_time
	var filled: bool = await wait_until(func() -> bool:
		return Game.game_time - t0 >= 10.0, 12.0)
	_flush()
	var dt: float = Game.game_time - t0
	print("  [замер] накопитель за %.2f с: stored %.2f (ждали ≈ 10)" % [dt, acc.stored])
	ok("за 10 с запас ≈ 10 с", filled and absf(acc.stored - 10.0) < 0.6 and acc.color == Beams.W,
			"stored %.2f, цвет %d, dt %.2f" % [acc.stored, acc.color, dt])
	ok("пока вход жив, наружу не отдаёт", not acc.emitting()
			and World.beams.color_at(acc_cell + Vector2i(1, 0)) == 0)
	_gone(col)
	_gone(acc)
	_flush()


## (в) Вечер: коллектор молчит, накопитель с 10 с белого отдаёт и пустеет.
func _check_night(origin: Vector2i) -> void:
	var acc_cell: Vector2i = origin + Vector2i(4, 0)
	ok("накопитель на ночь", MachineBase.place_machine("Accumulator", acc_cell))
	var acc: Accumulator = World.machines.get(acc_cell) as Accumulator
	ok("коллектор на ночь", MachineBase.place_machine("Collector", origin))
	var col: Collector = World.machines.get(origin) as Collector
	if acc == null or col == null:
		return
	acc.dir = 0
	col.dir = 0
	acc.stored = 10.0
	acc.color = Beams.W
	acc._idle = Accumulator.IDLE
	acc._emitting = true
	Game.time_of_day = Balance.NIGHT_START + 0.02
	col._check_sky()
	_flush()
	ok("ночью коллектор молчит", not col.emitting() and World.beams.color_at(origin + Vector2i(1, 0)) == 0,
			"день %.3f" % Game.daylight())
	ok("накопитель отдаёт белый", acc.emitting()
			and World.beams.color_at(acc_cell + Vector2i(1, 0)) == Beams.W,
			_dump(acc_cell, Vector2i(1, 0), 4))
	var t0: float = Game.game_time
	var empty: bool = await wait_until(func() -> bool:
		return acc.stored <= 0.05 and not acc.emitting(), 12.0)
	_flush()
	var dt: float = Game.game_time - t0
	print("  [замер] отдача 10 с запаса: %.2f с, stored %.3f" % [dt, acc.stored])
	ok("через 10 с запас пуст и луч погас", empty and World.beams.color_at(acc_cell + Vector2i(1, 0)) == 0,
			"stored %.3f, dt %.2f" % [acc.stored, dt])
	_gone(col)
	_gone(acc)
	Game.time_of_day = 0.30
	_flush()


## (г) Рубильник «отдавать» при живом входе: отдаёт, не копит.
func _check_switch(origin: Vector2i) -> void:
	var acc_cell: Vector2i = origin + Vector2i(3, 0)
	ok("накопитель с рубильником", MachineBase.place_machine("Accumulator", acc_cell))
	var acc: Accumulator = World.machines.get(acc_cell) as Accumulator
	var burner: Burner = _burn(origin, IDs.I.COAL, 0)
	if acc == null or burner == null:
		return
	acc.dir = 0
	_flush()
	# Сначала копит, чтобы был цвет и запас.
	var warmed: bool = await wait_until(func() -> bool: return acc.stored >= 1.0, 3.0)
	ok("до рубильника копится красный", warmed and acc.color == Beams.R, "stored %.2f" % acc.stored)
	var before: float = acc.stored
	acc.set_mode(Accumulator.MODE_EMIT)
	await wait(1.0)
	_flush()
	ok("рубильник «отдавать» при входе отдаёт", acc.emitting()
			and World.beams.color_at(acc_cell + Vector2i(1, 0)) == Beams.R,
			_dump(acc_cell, Vector2i(1, 0), 4))
	ok("при входе накопления нет", acc.stored < before,
			"было %.2f, стало %.2f" % [before, acc.stored])
	_gone(burner)
	_gone(acc)
	_flush()


## (д) Красный в накопитель с зелёным запасом запас не меняет.
func _check_foreign(origin: Vector2i) -> void:
	var acc_cell: Vector2i = origin + Vector2i(3, 0)
	ok("накопитель с чужим цветом", MachineBase.place_machine("Accumulator", acc_cell))
	var acc: Accumulator = World.machines.get(acc_cell) as Accumulator
	var burner: Burner = _burn(origin, IDs.I.COAL, 0)
	if acc == null or burner == null:
		return
	acc.dir = 0
	acc.stored = 4.0
	acc.color = Beams.G
	_flush()
	var before: float = acc.stored
	await wait(1.0)
	_flush()
	ok("красный не меняет зелёный запас", absf(acc.stored - before) < 0.05 and acc.color == Beams.G,
			"stored %.2f → %.2f, цвет %d" % [before, acc.stored, acc.color])
	ok("чужой луч наружу не прошёл", World.beams.color_at(acc_cell + Vector2i(1, 0)) == 0)
	_gone(burner)
	_gone(acc)
	_flush()


## Сохранение: запас, цвет, режим и направление переживают gather/apply.
func _save_roundtrip(origin: Vector2i) -> void:
	ok("накопитель в сохранение", MachineBase.place_machine("Accumulator", origin))
	var acc: Accumulator = World.machines.get(origin) as Accumulator
	if acc == null:
		return
	acc.dir = 1
	acc.stored = 37.5
	acc.color = Beams.B
	acc.mode = Accumulator.MODE_EMIT
	acc._emitting = true
	var slot0: String = Save.slot
	Save.slot = "solar"
	Save.remove("solar")
	var packed: PackedByteArray = var_to_bytes(Save.gather())
	Save.apply(Save.decode(packed))
	var back: Accumulator = World.machines.get(origin) as Accumulator
	ok("накопитель загрузился", back != null)
	if back != null:
		_flush()
		ok("запас, цвет, режим и направление те же",
				back.dir == 1 and back.color == Beams.B and back.mode == Accumulator.MODE_EMIT
				and absf(back.stored - 37.5) < 0.05,
				"dir %d, цвет %d, режим %d, stored %.2f" % [back.dir, back.color, back.mode, back.stored])
		ok("после загрузки отдаёт синий", back.emitting()
				and World.beams.color_at(origin + Vector2i(0, 1)) == Beams.B)
	Save.remove("solar")
	Save.slot = slot0


## Сколько секунд белого даёт один коллектор за световой день.
## Порог — COLLECTOR_MIN_DAYLIGHT, тот же, что у панели. Шаг 0,001 цикла.
func _day_yield(_origin: Vector2i) -> void:
	var secs: float = 0.0
	var step: float = 0.001
	var t: float = 0.0
	while t < 1.0:
		Game.time_of_day = t
		if Game.daylight() >= Balance.COLLECTOR_MIN_DAYLIGHT:
			secs += step * Balance.DAY_LENGTH
		t += step
	Game.time_of_day = 0.30
	var night: float = Balance.DAY_LENGTH - secs
	print("  [замер] коллектор за день: %.1f с белого (порог daylight %.2f, цикл %.0f с)" % [
			secs, Balance.COLLECTOR_MIN_DAYLIGHT, Balance.DAY_LENGTH])
	print("  [замер] ночь без коллектора: %.1f с; накопитель отдаёт не больше %.0f с" % [
			night, Balance.ACCUMULATOR_CAP])
	ok("коллектор светит дольше ёмкости накопителя", secs > Balance.ACCUMULATOR_CAP,
			"день %.1f с, ёмкость %.0f" % [secs, Balance.ACCUMULATOR_CAP])


func _burn(cell: Vector2i, fuel: int, dir: int) -> Burner:
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
