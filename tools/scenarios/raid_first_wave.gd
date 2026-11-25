extends ScenarioBase
## Первая волна при живой обороне (#316): один участок повреждён и
## встаёт за сутки производства. Стартовая оборона не сносится.


func run() -> void:
	var origin: Vector2i = World.beacon_cell + Vector2i(8, -4)
	var room: Dictionary = RaidCommon.build_room(origin, true)
	var panels_before: int = _panels(origin)
	ok("стартовая оборона из панелей", panels_before >= 8, str(panels_before))
	RaidCommon.place_bed(room["inside"], false)
	# Подогнать фантома к участку: предупреждение уже проверено отдельно.
	RaidCommon.arm(3)
	Threat.tick(0.05)
	var lead: float = Game.raid_remain
	RaidCommon.tick(lead + 0.2)
	# Гудок 2 с: фантом ещё в очереди, пока телеграф не кончится.
	RaidCommon.tick(Balance.VENT_TELEGRAPH + 0.2)
	var t0: float = now()
	var ph: Node = _raid_one()
	ok("волна вышла", ph != null, "фаза %d" % Game.raid_phase)
	if ph != null:
		ph.global_position = World.cell_to_world(room["inside"])
		ph.approach_at = ph.global_position
		ph.approach_t = 4.0
		ph.state = ph.St.CHASE
	for _i in 8:
		RaidCommon.step_frame(self, 0.05)
	var wave_s: float = now() - t0
	ok("повреждён один участок", Game.raid_damage == "section", Game.raid_damage)
	var panels_after: int = _panels(origin)
	ok("снята одна панель, не вся оборона", panels_after == panels_before - 1, "%d → %d" % [panels_before, panels_after])
	var hp_bed: float = float(World.machines[room["inside"]].hp) if World.machines.has(room["inside"]) else -1.0
	ok("устройство живо", hp_bed > 0.0, "hp %.0f" % hp_bed)
	print("  замер волны: %.2f с, урон %s, hp грядки %.0f" % [wave_s, Game.raid_damage, hp_bed])
	# Сутки производства — таймер участка, не реальный день игрока.
	Threat.raid_section_t = 1.0
	RaidCommon.tick(1.2)
	ok("участок встал за сутки", _panels(origin) == panels_before, str(_panels(origin)))
	finish()


func _panels(origin: Vector2i) -> int:
	var n: int = 0
	for y in range(0, 3):
		for x in range(0, 5):
			if World.get_tile_v(origin + Vector2i(x, y)) == IDs.T.ROOM_PANEL:
				n += 1
	return n


func _raid_one() -> Node:
	var list: Array = RaidCommon.raid_phantoms()
	return list[0] if not list.is_empty() else null
