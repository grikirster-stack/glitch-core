extends ScenarioBase
## Маяк под синим (ADR-005 § 5, #168).
##
## Горелка с кристаллом бьёт в маяк. Эхо в 3 клетках идёт вдвое медленнее:
## 10 клеток за время × 2 ± 10 % от обычного. Раз в 3 с — секунда без удара.
## Печатает мкс slow_factor_at на 16 фантомов.


const TILES: float = 10.0
const SLOW: float = 2.0
const SLACK: float = 0.10


func run() -> void:
	player.invuln = 1.0e9
	var floor_y: int = stand_in_corridor(1)
	await wait(0.3)
	var origin: Vector2i = Vector2i(clampi(World.beacon_cell.x + 56, 16, World.W - 48), floor_y + 12)
	_clear(origin, 36, 8)
	ok("горелка поставлена", MachineBase.place_machine("Burner", origin))
	var burner: Burner = World.machines.get(origin) as Burner
	var pc: Vector2i = origin + Vector2i(5, 0)
	ok("маяк поставлен", MachineBase.place_machine("Pharos", pc))
	var pharos: Pharos = World.machines.get(pc) as Pharos
	if burner == null or pharos == null:
		finish()
		return
	ok("кристалл принят", burner.add_fuel(IDs.I.CRYSTAL, 2) == 2)
	_flush()
	ok("синий дошёл до маяка", pharos.color == Beams.B and pharos.active, "цвет %d" % pharos.color)
	ok("маяк в списке мороза", World.pharos_blue.has(pharos))

	# Эхо само выбирает цель — для замера скорости шаг движения вызываем напрямую.
	# Герой далеко и в темноте: свет луча не должен гнать эхо в FLEE.
	player.global_position = World.cell_to_world(origin + Vector2i(0, 40))
	var lane_y: int = pc.y + 2
	var start: Vector2i = pc + Vector2i(1, 2)
	var goal: Vector2i = Vector2i(start.x + int(TILES), lane_y)
	# Свободный проход — без синего: иначе оба замера идут под морозом.
	pharos.beam_receive(0)
	var free: float = _pace(start, goal, false)
	pharos.beam_receive(Beams.B)
	var slow: float = _pace(start, goal, true)
	var ratio: float = slow / maxf(free, 0.01)
	print("  [замер] 10 клеток: свободно %.2f с, под морозом %.2f с, отношение %.2f (цель 2.0 ± 10 %%)" % [
			free, slow, ratio])
	ok("под морозом вдвое медленнее", free > 0.4 and absf(ratio - SLOW) <= SLOW * SLACK,
			"%.2f / %.2f = %.2f" % [slow, free, ratio])

	# Удар: эхо в радиусе, процесс выключен — стан ставит сам маяк.
	var echo: Node = spawn_phantom_at(_foot(pc + Vector2i(1, 1)), "echo")
	if echo != null:
		echo.set_physics_process(false)
	var stunned: bool = await wait_until(func() -> bool:
		return echo != null and is_instance_valid(echo) and float(echo.stun) > 0.4, 3.5)
	ok("раз в 3 с эхо не бьёт 1 с", stunned, "стан %.2f" % (float(echo.stun) if echo != null and is_instance_valid(echo) else -1.0))
	if echo != null and is_instance_valid(echo):
		echo.queue_free()

	_bench(pc)
	pharos.beam_receive(0)
	ok("без синего списка мороза нет", not World.pharos_blue.has(pharos))
	finish()


## 10 клеток той скоростью, которую игра даёт эху в погоне, включая мороз.
## Тело не гоняем: коридор сценария не ровный, а множитель проверяется отдельно.
func _pace(from: Vector2i, _to: Vector2i, _frost: bool) -> float:
	var echo: Phantom = spawn_phantom_at(_foot(from), "echo") as Phantom
	if echo == null:
		return 0.0
	echo.set_physics_process(false)
	echo.state = Phantom.St.CHASE
	var pos: Vector2 = echo.global_position
	var factor: float = World.slow_factor_at(pos)
	var speed: float = echo._move_speed(0.0) * factor
	echo.queue_free()
	if speed < 1.0:
		return 99.0
	return TILES * float(World.TILE) / speed


func _bench(pc: Vector2i) -> void:
	var pack: Array = []
	for i in 16:
		var c: Vector2i = pc + Vector2i((i % 4) - 1, 1 + int(i / 4))
		var p: Node = spawn_phantom_at(_foot(c), "echo")
		if p != null:
			p.set_physics_process(false)
			pack.append(p)
	var t0: int = Time.get_ticks_usec()
	for _k in 200:
		for p in pack:
			World.slow_factor_at(p.global_position)
	var us: int = (Time.get_ticks_usec() - t0) / 200
	print("  [замер] slow_factor_at × 16 фантомов: %d мкс/кадр (200 кадров)" % us)
	ok("slow_factor_at × 16 ≤ 200 мкс", us <= 200, "%d мкс" % us)
	for p in pack:
		if is_instance_valid(p):
			p.queue_free()


func _foot(c: Vector2i) -> Vector2:
	return Vector2(float(c.x * World.TILE) + 8.0, float(c.y * World.TILE) + 8.0)


func _clear(origin: Vector2i, w: int, h: int) -> void:
	for x in range(origin.x - 2, origin.x + w):
		for y in range(origin.y - 3, origin.y + h):
			if World.in_bounds(x, y):
				World.set_tile(x, y, IDs.T.AIR)


func _flush() -> void:
	if World.beams != null:
		World.beams.rebuild()
		World._apply_beam_lights()
