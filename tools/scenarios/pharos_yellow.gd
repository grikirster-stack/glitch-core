extends ScenarioBase
## Маяк под жёлтым (ADR-005 § 5, #167).
##
## Смесителя ещё нет (#165): жёлтый луч подаём в маяк напрямую, как вход.
## Свет в 4 клетках ≥ 2.0. Эхо рядом уходит в FLEE за 2 с.


func run() -> void:
	player.invuln = 1.0e9
	var floor_y: int = stand_in_corridor(1)
	await wait(0.3)
	var origin: Vector2i = Vector2i(clampi(World.beacon_cell.x + 48, 8, World.W - 30), floor_y + 10)
	for x in range(origin.x - 8, origin.x + 12):
		for y in range(origin.y - 6, origin.y + 6):
			if World.in_bounds(x, y):
				World.set_tile(x, y, IDs.T.AIR)
	ok("маяк поставлен", MachineBase.place_machine("Pharos", origin))
	var pharos: Pharos = World.machines.get(origin) as Pharos
	if pharos == null:
		finish()
		return
	var dark: float = World.light_at(origin + Vector2i(4, 0))
	ok("до жёлтого в 4 клетках темно", dark < 0.5, "%.3f" % dark)
	# Жёлтый — смесь. Пока нет смесителя, цвет приходит лучом-входом маяка.
	pharos.beam_receive(Beams.Y)
	ok("маяк принял жёлтый", pharos.color == Beams.Y and pharos.active and pharos._lit)
	var lit: float = World.light_at(origin + Vector2i(4, 0))
	print("  [замер] light_at в 4 клетках под жёлтым: %.3f (было %.3f, цель ≥ 2.0)" % [lit, dark])
	ok("свет в 4 клетках ≥ 2.0", lit >= 2.0, "%.3f" % lit)
	# Край радиуса прожектора — около 10 клеток; за ним темно.
	var far: float = World.light_at(origin + Vector2i(14, 0))
	ok("за радиусом света нет", far < 0.5, "%.3f" % far)

	var echo: Node = spawn_phantom_at(World.cell_to_world(origin + Vector2i(2, 0)), "echo")
	ok("эхо рядом с маяком", echo != null)
	var fled: bool = await wait_until(func() -> bool:
		return echo != null and is_instance_valid(echo) and echo.state == Phantom.St.FLEE, 2.0)
	ok("эхо ушло в FLEE за 2 с", fled, "состояние %s" % (str(echo.state) if echo != null and is_instance_valid(echo) else "нет"))
	if echo != null and is_instance_valid(echo):
		echo.queue_free()

	# Смена цвета гасит свет. Разрушение — тоже.
	pharos.beam_receive(0)
	ok("без луча свет погас", not pharos._lit and World.light_at(origin + Vector2i(4, 0)) < 0.5)
	pharos.beam_receive(Beams.Y)
	pharos.destroy()
	await await_frame()
	ok("разрушенный маяк не светит", World.light_at(origin + Vector2i(4, 0)) < 0.5)
	finish()
