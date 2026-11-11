extends ScenarioBase
## Маяк под красным (ADR-005 § 5, #167).
##
## Горелка с углём бьёт в маяк. Эхо в 5 клетках, в прямой видимости, умирает
## за ≤ 5 с (100 HP / 20 за 0.8 с = 4 с). За стеной — не бьётся. Замер:
## урон/с маяка и героя, мкс кадра при 10 маяках.


const KILL_LIMIT: float = 5.0


func run() -> void:
	player.invuln = 1.0e9
	var floor_y: int = stand_in_corridor(1)
	await wait(0.3)
	# Коридор в стороне от базы: свет релея не должен поднимать light_at.
	var origin: Vector2i = Vector2i(clampi(World.beacon_cell.x + 40, 8, World.W - 40), floor_y + 8)
	_clear(origin, 28, 8)
	ok("горелка поставлена", MachineBase.place_machine("Burner", origin))
	var burner: Burner = World.machines.get(origin) as Burner
	var pc: Vector2i = origin + Vector2i(6, 0)
	ok("маяк поставлен", MachineBase.place_machine("Pharos", pc))
	var pharos: Pharos = World.machines.get(pc) as Pharos
	if burner == null or pharos == null:
		finish()
		return
	ok("уголь принят", burner.add_fuel(IDs.I.COAL, 4) == 4)
	_flush()
	ok("красный луч дошёл до маяка и погас в нём", World.beams.color_at(pc + Vector2i(-1, 0)) == Beams.R
			and World.beams.color_at(pc) == 0 and World.beams.color_at(pc + Vector2i(1, 0)) == 0,
			_dump(origin, 10))
	ok("маяк принял красный", pharos.color == Beams.R and pharos.active, "цвет %d" % pharos.color)

	# Эхо в 5 клетках, сбоку от луча: в самой линии свет 1.0, эхо от него убегает.
	var echo_cell: Vector2i = pc + Vector2i(4, 2)
	var echo: Node = spawn_phantom_at(_foot(echo_cell), "echo")
	# Эхо после удара бежит на героя и за 0.8 с выходит из 7 клеток. Для замера
	# урона/с держим его на месте: маяк бьёт стоящую цель, как турель в коробке.
	if echo != null:
		echo.set_process(false)
		echo.set_physics_process(false)
	ok("эхо появилось в 5 клетках", echo != null and pharos.global_position.distance_to(echo.global_position) <= 6.0 * 16.0,
			"%.0f px" % pharos.global_position.distance_to(echo.global_position if echo != null else Vector2.ZERO))
	var t0: float = now_proc()
	var ref: WeakRef = weakref(echo)
	var dead: bool = await wait_until(func() -> bool:
		var n = ref.get_ref()
		return n == null or not n.alive, KILL_LIMIT + 1.0)
	var secs: float = now_proc() - t0
	ok("эхо убито маяком за ≤ 5 с", dead and secs <= KILL_LIMIT,
			"%.2f с, выстрелов %d" % [secs, pharos.shots])
	var dps: float = float(pharos.shots) * Balance.PHAROS_RED_DAMAGE / maxf(secs, 0.01)
	print("  [замер] урон/с маяка под красным: %.1f (выстрелов %d за %.2f с; цель 25)" % [dps, pharos.shots, secs])
	print("  [замер] урон/с героя: %.1f (38 урона / 0.45 с; цель 84)" % (38.0 / 0.45))
	ok("маяк бьёт около 25 урона/с", dps >= 22.0 and dps <= 28.0, "%.1f" % dps)
	ok("на эхо ушло 5 разрядов", pharos.shots == 5, "выстрелов %d" % pharos.shots)

	# За стеной не бьётся: новый эхо за камнем, секунда тишины.
	# Стена на 3 клетки вправо и на 3 ряда: луч видимости идёт по центрам и
	# сквозь один угол не считается попаданием.
	for k in range(1, 4):
		for row in range(0, 4):
			var wall: Vector2i = pc + Vector2i(k, row)
			World.set_tile(wall.x, wall.y, IDs.T.STONE)
	var hidden: Node = spawn_phantom_at(_foot(pc + Vector2i(5, 2)), "echo")
	if hidden != null:
		hidden.set_process(false)
		hidden.set_physics_process(false)
	var shots0: int = pharos.shots
	await wait(1.2)
	ok("за стеной маяк не стреляет", hidden != null and is_instance_valid(hidden) and hidden.alive
			and pharos.shots == shots0 and pharos.pick_target() == null,
			"выстрелов %d, hp %.0f" % [pharos.shots - shots0, hidden.hp if hidden != null else -1])
	if hidden != null and is_instance_valid(hidden):
		hidden.queue_free()
	for k in range(1, 4):
		for row in range(0, 4):
			var wall: Vector2i = pc + Vector2i(k, row)
			World.set_tile(wall.x, wall.y, IDs.T.AIR)

	# Приоритет тот же, что у турели: тень раньше эха.
	var e2: Node = spawn_phantom_at(_foot(pc + Vector2i(3, 2)), "echo")
	var sh: Node = spawn_phantom_at(_foot(pc + Vector2i(5, 2)), "shade")
	for p in [e2, sh]:
		if p != null:
			p.set_process(false)
			p.set_physics_process(false)
	await await_frame()
	var pick: Node = pharos.pick_target()
	ok("приоритет: тень раньше эха", pick == sh, "цель %s" % (String(pick.kind) if pick != null else "нет"))
	for p in [e2, sh]:
		if p != null and is_instance_valid(p):
			p.queue_free()

	_bench(origin)
	_save(origin, pharos)
	finish()


func _foot(c: Vector2i) -> Vector2:
	return Vector2(float(c.x * World.TILE) + 8.0, float(c.y * World.TILE) + 8.0)


func _clear(origin: Vector2i, w: int, h: int) -> void:
	for x in range(origin.x - 2, origin.x + w):
		for y in range(origin.y - 3, origin.y + h):
			if World.in_bounds(x, y):
				World.set_tile(x, y, IDs.T.AIR)


func _dump(origin: Vector2i, n: int) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for k in n:
		parts.append(str(World.beams.color_at(origin + Vector2i(k, 0))))
	return " ".join(parts)


func _flush() -> void:
	if World.beams != null:
		World.beams.rebuild()
		World._apply_beam_lights()


## 10 красных маяков: мкс кадра _process (поиск цели, стрелять не в кого).
func _bench(origin: Vector2i) -> void:
	var cells: Array[Vector2i] = []
	for i in 10:
		var c: Vector2i = Vector2i(30 + (i % 5) * 4, origin.y + 6 + int(i / 5) * 3)
		if not World.in_bounds(c.x, c.y):
			continue
		World.set_tile(c.x, c.y, IDs.T.AIR)
		if MachineBase.place_machine("Pharos", c):
			var m: Pharos = World.machines[c]
			m.beam_receive(Beams.R)
			cells.append(c)
	var t0: int = Time.get_ticks_usec()
	for _k in 200:
		for c in cells:
			var m: Pharos = World.machines.get(c)
			if m != null:
				m._process(0.016)
	var us: int = (Time.get_ticks_usec() - t0) / 200
	print("  [замер] 10 маяков под красным: %d мкс/кадр _process (200 кадров)" % us)
	ok("10 маяков ≤ 500 мкс/кадр", us <= 500, "%d мкс" % us)
	for c in cells:
		var m: MachineBase = World.machines.get(c)
		if m != null:
			m.destroy()


func _save(origin: Vector2i, pharos: Pharos) -> void:
	var col: int = pharos.color
	var slot0: String = Save.slot
	Save.slot = "pharos"
	Save.remove("pharos")
	var packed: PackedByteArray = var_to_bytes(Save.gather())
	Save.apply(Save.decode(packed))
	var back: Pharos = World.machines.get(pharos.cell) as Pharos
	ok("маяк загрузился красным", back != null and back.color == col and back.active,
			"цвет %s" % (str(back.color) if back != null else "нет"))
	if back != null:
		back.beam_receive(Beams.Y)
		var packed2: PackedByteArray = var_to_bytes(Save.gather())
		Save.apply(Save.decode(packed2))
		var lit: Pharos = World.machines.get(pharos.cell) as Pharos
		ok("жёлтый после загрузки снова светит", lit != null and lit.color == Beams.Y and lit._lit
				and World.light_at(pharos.cell + Vector2i(4, 0)) >= 2.0,
				"цвет %s" % (str(lit.color) if lit != null else "нет"))
	Save.remove("pharos")
	Save.slot = slot0
