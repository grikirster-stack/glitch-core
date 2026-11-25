extends ScenarioBase
## Налёт при открытой двери (#316): герой в шахте, вход снаружи,
## предупреждение не короче 25 с, фантом заходит в комнату.


func run() -> void:
	var origin: Vector2i = World.beacon_cell + Vector2i(8, -4)
	var room: Dictionary = RaidCommon.build_room(origin, true)
	var bed: SporeBed = RaidCommon.place_bed(room["inside"], false)
	ok("комната с открытой дверью и грядкой", bed != null and World.get_tile_v(room["door"]) == IDs.T.DOOR_OPEN)
	# Герой в шахте: далеко от базы, копает. Налёт не должен свернуть к нему.
	var mine: Vector2i = World.beacon_cell + Vector2i(-40, 12)
	if World.in_bounds(mine.x, mine.y):
		World.set_tile(mine.x, mine.y, IDs.T.AIR)
		World.set_tile(mine.x, mine.y + 1, IDs.T.STONE)
		stand_at_cell(mine)
	ok("герой в шахте, не у двери", player.global_position.distance_to(World.cell_to_world(room["door"])) > 80.0)
	RaidCommon.arm(3)
	Threat.tick(0.05)
	ok("предупреждение началось до контакта", Game.raid_phase == 1, "фаза %d" % Game.raid_phase)
	var lead: float = Game.raid_remain
	ok("до контакта не меньше 25 с", lead >= Balance.RAID_WARN_LEAD - 0.05, "%.1f" % lead)
	var line: String = RaidCommon.plate()
	ok("плашка назвала сторону и цель", line.contains("Налёт") and not line.contains("[E]") and not line.contains("ПКМ"), "«%s»" % line)
	ok("вход ещё не внутри комнаты", Threat.raid_entrance != room["inside"])
	RaidCommon.tick(lead + 0.3)
	var waited: float = lead
	ok("контакт не раньше предупреждения", Game.raid_phase == 2 and waited >= 25.0, "фаза %d, ждали %.1f" % [Game.raid_phase, waited])
	# Гудок вентиляции 2 с: фантом ещё в очереди, вход уже выбран снаружи.
	ok("вход назначен снаружи комнаты", _spawned_outside(room), "вход %s" % str(Threat.raid_entrance))
	RaidCommon.tick(Balance.VENT_TELEGRAPH + 0.2)
	var entered: bool = await _entered(room["inside"], 12.0)
	var where: String = ""
	for ph in RaidCommon.raid_phantoms():
		where = str(World.world_to_cell(ph.global_position))
	ok("открытая дверь пустила фантома внутрь", entered, "фантом %s фаза %d" % [where, Game.raid_phase])
	ok("курс остался на базе, не на героя", _still_on_base(room["inside"]))
	finish()


func _spawned_outside(room: Dictionary) -> bool:
	var door: Vector2i = room["door"]
	var inside: Vector2i = room["inside"]
	if Threat.raid_entrance.x < 0:
		return false
	if Threat.raid_entrance == inside:
		return false
	return absi(Threat.raid_entrance.x - door.x) + absi(Threat.raid_entrance.y - door.y) >= 1


func _entered(inside: Vector2i, timeout: float) -> bool:
	var t0: float = now()
	while now() - t0 < timeout:
		await wait(0.1)
		for ph in RaidCommon.raid_phantoms():
			var c: Vector2i = World.world_to_cell(ph.global_position)
			if absi(c.x - inside.x) + absi(c.y - inside.y) <= 1:
				return true
		# Удар по цели снимает эхо в том же кадре, что и вход.
		if Game.raid_phase == 3 and Game.raid_damage != "":
			return true
		if Game.raid_phase == 3:
			return false
	return false


func _still_on_base(inside: Vector2i) -> bool:
	for p in RaidCommon.raid_phantoms():
		if p.approach_at.distance_to(World.cell_to_world(inside)) > 40.0 and Game.raid_target != inside:
			return false
	return Game.raid_target == inside or Game.raid_phase == 3
