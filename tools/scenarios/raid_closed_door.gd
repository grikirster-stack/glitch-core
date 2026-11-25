extends ScenarioBase
## Закрытая дверь (#316): фантом метит достижимый внешний участок.
## Входа снаружи нет — попытка кончается по таймеру, внутрь не спавним.


func run() -> void:
	var origin: Vector2i = World.beacon_cell + Vector2i(8, -4)
	var room: Dictionary = RaidCommon.build_room(origin, false)
	ok("дверь закрыта", World.get_tile_v(room["door"]) == IDs.T.DOOR and World.is_solid_cell(room["door"]))
	RaidCommon.place_bed(room["inside"], false)
	stand_at_cell(World.beacon_cell + Vector2i(-30, 8))
	RaidCommon.arm(3)
	Threat.tick(0.05)
	ok("предупреждение есть и при закрытой двери", Game.raid_phase == 1 and Game.raid_remain >= 25.0)
	var line: String = RaidCommon.plate()
	ok("плашка без клавиш мыши", line.contains("Налёт") and not line.contains("ПКМ") and not line.contains("[E]"), "«%s»" % line)
	RaidCommon.tick(Game.raid_remain + 0.3)
	ok("контакт пошёл", Game.raid_phase == 2, "фаза %d" % Game.raid_phase)
	var entrance: Vector2i = Threat.raid_entrance
	if entrance.x >= 0:
		ok("вход снаружи комнаты", entrance != room["inside"] and not _inside(entrance, room))
		ok("вход смотрит на внешний участок", _faces_shell(entrance))
		var gone: bool = await _until_done(50.0)
		ok("закрытый периметр не пустил внутрь", not _phantom_inside(room) and gone)
	else:
		ok("прохода нет — попытка без спавна внутрь", true)
		var done: bool = await _until_done(Balance.RAID_GIVE_UP + 2.0)
		ok("попытка кончилась по таймеру", done and Game.raid_phase != 2)
		ok("внутрь никто не появился", not _phantom_inside(room))
	finish()


func _inside(c: Vector2i, room: Dictionary) -> bool:
	var o: Vector2i = room["origin"]
	return c.x > o.x and c.x < o.x + 4 and c.y > o.y and c.y < o.y + 2


func _faces_shell(c: Vector2i) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var id: int = World.get_tile_v(c + d)
		if id == IDs.T.ROOM_PANEL or id == IDs.T.DOOR:
			return true
	return false


func _phantom_inside(room: Dictionary) -> bool:
	for p in RaidCommon.raid_phantoms():
		if _inside(World.world_to_cell(p.global_position), room):
			return true
	return false


func _until_done(timeout: float) -> bool:
	var t0: float = now()
	while now() - t0 < timeout and Game.raid_phase == 2:
		# Сценарий глушит _process. Часы сдачи идут в tick, шаг — в дереве.
		Threat.tick(0.2)
		await wait(0.2)
	return Game.raid_phase != 2
