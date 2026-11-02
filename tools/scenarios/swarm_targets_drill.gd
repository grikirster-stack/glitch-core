extends ScenarioBase
## Рой идёт на работающий бур (ADR-001, § 4.5): стая появляется между игроком
## и запитанным буром — и летит грызть бур, а не игрока.

func run() -> void:
	var base: int = stand_in_corridor(0)
	player.invuln = 1.0e9
	var bx: int = World.beacon_cell.x
	var gen_cell: Vector2i = Vector2i(bx + 12, base - 1)
	var drill_cell: Vector2i = Vector2i(bx + 14, base - 1)
	var placed: bool = MachineBase.place_machine("CoalGen", gen_cell) \
			and MachineBase.place_machine("Drill", drill_cell)
	ok("ТЭЦ и бур поставлены", placed)
	if not placed:
		finish()
		return
	var gen: Node = World.machines[gen_cell]
	var drill: Node = World.machines[drill_cell]
	gen.add_fuel(3)
	var powered: bool = await wait_until(func(): return bool(drill.powered), 2.0)
	ok("бур запитан (работает)", powered)

	# Стая — ближе к игроку, чем к буру, но бур в её радиусе 300 px.
	var spawn: Vector2 = World.cell_to_world(Vector2i(bx + 7, base - 2))
	var pack: Array = spawn_pack_at(spawn)
	ok("стая 4–6 особей", pack.size() >= 4 and pack.size() <= 6, "n=%d" % pack.size())
	if pack.is_empty():
		finish()
		return
	var hp0: float = drill.hp
	var dpos: Vector2 = drill.global_position
	var d0: float = pack[0].global_position.distance_to(dpos)
	var hit: bool = await wait_until(func(): return _hits(pack) > 0, 8.0)
	var closest: float = INF
	var to_player: float = INF
	for p in pack:
		if is_instance_valid(p):
			closest = minf(closest, p.global_position.distance_to(dpos))
			to_player = minf(to_player, p.global_position.distance_to(player.global_position))
	ok("стая выбрала бур целью", is_instance_valid(pack[0]) and pack[0].target_machine == drill)
	ok("стая долетела до бура", closest < d0 - 40.0, "%.0f → %.0f px" % [d0, closest])
	ok("стая грызёт бур", hit, "ударов %d" % _hits(pack))
	ok("игрок стае не цель", to_player > 40.0, "до игрока %.0f px" % to_player)
	# Урон машинам — MachineBase.take_damage (#25).
	ok("hp бура упало", is_instance_valid(drill) and drill.hp < hp0,
			"%.0f → %.0f" % [hp0, drill.hp if is_instance_valid(drill) else 0.0])
	# Рой рассыпается с одного удара.
	var one: Node = pack[0]
	if is_instance_valid(one):
		one.take_damage(1.0, player.global_position)
		ok("особь роя гибнет с одного удара", not one.alive)
	finish()


func _hits(pack: Array) -> int:
	var n: int = 0
	for p in pack:
		if is_instance_valid(p):
			n += int(p.machine_hits)
	return n
