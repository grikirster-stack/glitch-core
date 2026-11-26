extends ScenarioBase
## Нулевые панели (#316): встаёт одно устройство. Камень или хлам
## запускают его снова. Награда — ровно один раз на id налёта.


func run() -> void:
	var origin: Vector2i = World.beacon_cell + Vector2i(4, -2)
	for y in range(-1, 3):
		for x in range(-1, 4):
			World.set_tile(origin.x + x, origin.y + y, IDs.T.AIR)
	var bed: SporeBed = RaidCommon.place_bed(origin, false)
	ok("панелей нет, грядка есть", bed != null and _panels_near(origin) == 0)
	player.inv.add(IDs.I.STONE, 4)
	RaidCommon.arm(3)
	Threat.tick(0.05)
	RaidCommon.tick(Game.raid_remain + 0.2)
	RaidCommon.tick(Balance.VENT_TELEGRAPH + 0.2)
	var ph: Node = _one()
	ok("волна без панелей вышла", ph != null)
	if ph != null:
		ph.global_position = World.cell_to_world(origin)
		ph.approach_at = ph.global_position
		ph.approach_t = 4.0
		ph.state = ph.St.CHASE
	var reward_before: int = Game.raid_reward_id
	for _i in 8:
		RaidCommon.step_frame(self, 0.05)
	ok("встало устройство, не участок", Game.raid_damage == "device" and bed.raid_stopped, Game.raid_damage)
	bed.beam_receive(Beams.W)
	var made_before := bed.made
	bed._process(Balance.SPORE_BED_SECONDS + 0.1)
	ok("свет на повреждённой грядке не даёт волокна", bed.made == made_before)
	ok("грядка подсказывает материал для ремонта", bed.status_text() == MachineBase.REPAIR_AFTER_RAID)
	ok("награда выдана один раз", Game.raid_reward_id == Game.raid_number and Game.raid_reward_id != reward_before)
	var scrap_after: int = player.inv.count_of(IDs.I.SCRAP)
	# Повторный финиш той же волны награду не удваивает.
	Threat._raid_finish(true)
	ok("повтор той же id награду не даёт", player.inv.count_of(IDs.I.SCRAP) == scrap_after, str(player.inv.count_of(IDs.I.SCRAP)))
	# Камень в руке, E у грядки — цепочка снова жива.
	player.inv.slots[0] = ItemStack.new(IDs.I.STONE, 4)
	player.inv.selected = 0
	var stone0: int = player.inv.count_of(IDs.I.STONE)
	player.global_position = World.cell_to_world(origin) + Vector2(18.0, 0.0)
	player.vel = Vector2.ZERO
	aim(bed.global_position)
	hold(KEY_E)
	for _i in 16:
		RaidCommon.step_frame(self, 0.05)
	release(KEY_E)
	ok("камень запустил устройство", not bed.raid_stopped and player.inv.count_of(IDs.I.STONE) < stone0,
			"стоп %s, камень %d" % [str(bed.raid_stopped), player.inv.count_of(IDs.I.STONE)])
	bed.beam_receive(Beams.W)
	bed._process(Balance.SPORE_BED_SECONDS + 0.1)
	ok("починка вернула выпуск", bed.made == made_before + 1)
	finish()


func _panels_near(origin: Vector2i) -> int:
	var n: int = 0
	for y in range(origin.y - 4, origin.y + 5):
		for x in range(origin.x - 4, origin.x + 5):
			if World.in_bounds(x, y) and World.get_tile_v(Vector2i(x, y)) == IDs.T.ROOM_PANEL:
				n += 1
	return n


func _one() -> Node:
	var list: Array = RaidCommon.raid_phantoms()
	return list[0] if not list.is_empty() else null
