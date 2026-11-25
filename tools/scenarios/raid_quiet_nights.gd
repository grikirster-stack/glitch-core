extends ScenarioBase
## Ночи 1–2 без налёта (#316). Ночь 3 при живом устройстве начинает предупреждение.
## Окно предупреждения тикаем целиком: фазы 1 за эти ночи не появляется.


func run() -> void:
	var origin: Vector2i = World.beacon_cell + Vector2i(6, -2)
	for y in range(-1, 3):
		for x in range(-1, 4):
			var c: Vector2i = origin + Vector2i(x, y)
			if World.in_bounds(c.x, c.y):
				World.set_tile(c.x, c.y, IDs.T.AIR)
	var bed: SporeBed = RaidCommon.place_bed(origin, false)
	ok("устройство у базы", bed != null)
	Game.relay_active = false
	for night in [1, 2]:
		_arm_night(night)
		RaidCommon.tick(Balance.RAID_WARN_LEAD + 1.0)
		ok("ночь %d без налёта" % night, Game.raid_phase == 0 and RaidCommon.raid_phantoms().is_empty(),
				"фаза %d" % Game.raid_phase)
	_arm_night(3)
	Threat.tick(0.05)
	ok("ночь 3 начинает предупреждение", Game.raid_phase == 1, "фаза %d" % Game.raid_phase)
	finish()


func _arm_night(night: int) -> void:
	Game.day_number = night
	Game.time_of_day = 0.70
	Game.raid_phase = 0
	Game.raid_active = false
	Game.raid_damage = ""
	Threat.active = true
	Threat.night_day = night
	Threat.roster.clear()
	Threat.pending.clear()
