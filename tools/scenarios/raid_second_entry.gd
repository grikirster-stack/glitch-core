extends ScenarioBase
## Второй налёт (#316): вход не тот, что уже проверен, если снаружи есть другой.
## Первый удар доигрываем телепортом — замер контакта живёт в raid_first_contact.


func run() -> void:
	var origin: Vector2i = World.beacon_cell + Vector2i(8, -4)
	var room: Dictionary = RaidCommon.build_room(origin, true)
	# Западный проём дальше восточной двери: первый налёт берёт ближний восток,
	# второй обязан уйти на запад, а не на соседнюю клетку той же двери.
	var west_door: Vector2i = origin + Vector2i(0, 1)
	var west: Vector2i = origin + Vector2i(-6, 1)
	World.set_tile(west_door.x, west_door.y, IDs.T.DOOR_OPEN)
	World.set_tile(west_door.x - 1, west.y, IDs.T.STONE)
	for x in range(west.x, west_door.x - 1):
		World.set_tile(x, west.y, IDs.T.AIR)
		World.set_tile(x, west.y + 1, IDs.T.STONE)
	World.set_tile(west.x, west.y + 1, IDs.T.STONE)
	RaidCommon.place_bed(room["inside"], false)
	RaidCommon.arm(3)
	Threat.tick(0.05)
	ok("первый налёт начался", Game.raid_phase == 1 and Game.raid_number == 1, "номер %d" % Game.raid_number)
	RaidCommon.tick(Game.raid_remain + 0.2)
	var first: Vector2i = Threat.raid_entrance
	var east_out: Vector2i = room["outside"]
	ok("первый вход снаружи и валиден", first.x >= 0 and first != room["inside"], str(first))
	ok("первый налёт с восточной двери", absi(first.x - east_out.x) + absi(first.y - east_out.y) <= 1,
			"%s, восток %s" % [str(first), str(east_out)])
	var first_side: String = Threat.raid_side
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
	# Ближайшая клетка западного проёма, не дальний воздух и не сосед восточной двери.
	var near_west: bool = second.x < west_door.x and second.x >= west.x - 1 and absi(second.y - west.y) <= 1
	var same_door: bool = absi(second.x - first.x) + absi(second.y - first.y) <= 2
	ok("второй вход снаружи и валиден", second.x >= 0 and second != room["inside"], str(second))
	ok("второй налёт с другой стороны", Threat.raid_side != first_side and near_west and not same_door,
			"%s → %s, сторона %s → %s" % [str(first), str(second), first_side, Threat.raid_side])
	ok("путь от западного проёма до цели есть", Threat._raid_reaches(second, room["inside"]))
	finish()


func _one() -> Node:
	var list: Array = RaidCommon.raid_phantoms()
	return list[0] if not list.is_empty() else null


