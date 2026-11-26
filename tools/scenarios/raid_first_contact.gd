extends ScenarioBase
## Первый контакт (#316, ADR-006 §4): от начала фазы 2 до удара не дольше
## RAID_CONTACT_MAX. Без телепорта и без подстановки approach_at/approach_t.
## Часы — сумма Threat.tick, не стена и не sim_time (физика может отстать).


func run() -> void:
	var origin: Vector2i = World.beacon_cell + Vector2i(8, -4)
	var room: Dictionary = RaidCommon.build_room(origin, true)
	var bed: SporeBed = RaidCommon.place_bed(room["inside"], false)
	ok("комната с дверью и грядкой", bed != null and World.get_tile_v(room["door"]) == IDs.T.DOOR_OPEN)
	var mine: Vector2i = World.beacon_cell + Vector2i(-40, 12)
	if World.in_bounds(mine.x, mine.y):
		World.set_tile(mine.x, mine.y, IDs.T.AIR)
		World.set_tile(mine.x, mine.y + 1, IDs.T.STONE)
		stand_at_cell(mine)
	ok("герой в шахте", player.global_position.distance_to(World.cell_to_world(room["door"])) > 80.0)
	RaidCommon.arm(3)
	Threat.tick(0.05)
	var lead: float = Game.raid_remain
	ok("предупреждение не короче 25 с", Game.raid_phase == 1 and lead >= Balance.RAID_WARN_LEAD - 0.05, "%.1f" % lead)
	# До конца предупреждения фантома ещё нет. Контакт — начало фазы 2.
	var terrain := hash(World.tiles)
	RaidCommon.tick(lead + 0.05)
	ok("выход фантома сохранил геометрию базы", hash(World.tiles) == terrain)
	ok("фаза 2 началась", Game.raid_phase == 2, "фаза %d" % Game.raid_phase)
	var spawn: Vector2i = Threat.raid_entrance
	ok("вход назначен снаружи", spawn.x >= 0 and spawn != room["inside"])
	var elapsed: float = 0.0
	var moved: float = 0.0
	var saw: bool = false
	var born: Vector2 = Vector2.ZERO
	# Гудок и путь строит дерево. Директор в сценарии молчит — тикаем сами.
	while elapsed < Balance.RAID_CONTACT_MAX + 2.0 and Game.raid_damage == "":
		await wait(0.1)
		Threat.tick(0.1)
		elapsed += 0.1
		for ph in RaidCommon.raid_phantoms():
			if not saw:
				born = ph.global_position
				saw = true
			moved = maxf(moved, ph.global_position.distance_to(born))
		if Game.raid_phase == 3:
			break
	print("  замер контакта: %.2f с" % elapsed)
	ok("удар случился", Game.raid_phase == 3 and Game.raid_damage != "", Game.raid_damage)
	ok("контакт не дольше 45 с и не мгновенный", elapsed > 0.2 and elapsed <= Balance.RAID_CONTACT_MAX + 0.05,
			"%.2f" % elapsed)
	ok("фантом сместился от входа", saw and moved > 16.0, "%.1f px от %s" % [moved, str(spawn)])
	finish()
