extends ScenarioBase
## Второй налёт (#316): вход не тот, что уже проверен, если снаружи есть другой.
## Первый удар доигрываем телепортом — замер контакта живёт в raid_first_contact.


func run() -> void:
	var origin: Vector2i = World.beacon_cell + Vector2i(8, -4)
	var room: Dictionary = RaidCommon.build_room(origin, true)
	# Второй выход: слева, на той же высоте, с камнем под ногами.
	var west: Vector2i = origin + Vector2i(-2, 1)
	World.set_tile(west.x, west.y, IDs.T.AIR)
	World.set_tile(west.x, west.y + 1, IDs.T.STONE)
	World.set_tile(origin.x - 1, origin.y + 1, IDs.T.AIR)
	RaidCommon.place_bed(room["inside"], false)
	RaidCommon.arm(3)
	Threat.tick(0.05)
	ok("первый налёт начался", Game.raid_phase == 1 and Game.raid_number == 1, "номер %d" % Game.raid_number)
	RaidCommon.tick(Game.raid_remain + 0.2)
	var first: Vector2i = Threat.raid_entrance
	ok("первый вход снаружи и валиден", first.x >= 0 and first != room["inside"], str(first))
	RaidCommon.tick(Balance.VENT_TELEGRAPH + 0.2)
	var ph: Node = _one()
	if ph != null:
		ph.global_position = World.cell_to_world(room["inside"])
		ph.approach_at = ph.global_position
		ph.approach_t = 4.0
		ph.state = ph.St.CHASE
	for _i in 8:
		RaidCommon.step_frame(self, 0.05)
	ok("первый налёт закончился ударом", Game.raid_phase == 3 and Game.raid_damage != "", Game.raid_damage)
	# Фаза 3 держит номер. Ждём сброс, затем следующая ночь — второй набор.
	RaidCommon.tick(Game.raid_remain + 0.3)
	ok("проверенный вход помним", Game.raid_checked == first,
			"фаза %d, checked %s" % [Game.raid_phase, str(Game.raid_checked)])
	Game.day_number = 4
	Game.time_of_day = 0.70
	Threat.night_day = 4
	Threat.tick(0.05)
	ok("номер вырос", Game.raid_number == 2 and Game.raid_phase == 1, "номер %d фаза %d" % [Game.raid_number, Game.raid_phase])
	var second: Vector2i = Threat.raid_entrance
	var alt: bool = _other_outside(room["inside"], first)
	ok("второй вход снаружи и валиден", second.x >= 0 and second != room["inside"], str(second))
	if alt:
		ok("второй вход другой", second != first, "%s → %s" % [str(first), str(second)])
	else:
		ok("другого входа нет, тот же допустим", second == first, "геометрия без альтернативы, %s" % str(second))
	finish()


func _one() -> Node:
	var list: Array = RaidCommon.raid_phantoms()
	return list[0] if not list.is_empty() else null


func _other_outside(target: Vector2i, skip: Vector2i) -> bool:
	for y in range(target.y - 4, target.y + 5):
		for x in range(target.x - 10, target.x + 11):
			var c: Vector2i = Vector2i(x, y)
			if c == skip or not World.in_bounds(x, y):
				continue
			if World.get_tile_v(c) != IDs.T.AIR:
				continue
			if absi(c.x - target.x) + absi(c.y - target.y) < 2:
				continue
			var floor: Vector2i = c + Vector2i(0, 1)
			if World.in_bounds(floor.x, floor.y) and World.get_tile_v(floor) == IDs.T.STONE:
				return true
	return false
