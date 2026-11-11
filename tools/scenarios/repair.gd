extends ScenarioBase
## Ремонт (ADR-001 § 4.4, #29): E с хламом в хотбаре по повреждённой машине —
## +Balance.REPAIR_PER_SCRAP HP за единицу хлама. Целую машину хлам не чинит
## (и не тратится). ТЭЦ снята (#170): рубильник остался у горелки, но только
## с пустой руки. Хлам в руке у целой горелки, маяка и сундука ничего не делает.


func run() -> void:
	player.invuln = 1.0e9
	var floor_y: int = stand_in_corridor(8)
	await wait(0.4)
	var pc: Vector2i = World.world_to_cell(player.global_position)
	var cell: Vector2i = Vector2i(pc.x + 2, floor_y - 1)
	ok("горелка поставлена", MachineBase.place_machine("Burner", cell), str(cell))
	var gen = World.machines.get(cell)
	if gen == null:
		finish()
		return
	aim(gen.global_position)
	var d: float = gen.global_position.distance_to(player.global_position)
	ok("герой у горелки", d < 40.0, "%.0f px" % d)
	gen.take_damage(50.0)
	ok("горелка повреждена", gen.hp < gen.max_hp, "hp %.0f/%.0f" % [gen.hp, gen.max_hp])

	player.inv.remove_id(IDs.I.SCRAP, player.inv.count_of(IDs.I.SCRAP))
	player.inv.slots[4] = ItemStack.new(IDs.I.SCRAP, 5)
	await _tap(KEY_5)
	var hp0: float = gen.hp
	await _tap(KEY_E)
	ok("E с хламом чинит машину", is_equal_approx(gen.hp, hp0 + Balance.REPAIR_PER_SCRAP),
			"hp %.0f → %.0f" % [hp0, gen.hp])
	ok("одна единица хлама потрачена", player.inv.count_of(IDs.I.SCRAP) == 4,
			"хлама %d" % player.inv.count_of(IDs.I.SCRAP))
	ok("рубильник не тронут", gen.enabled)

	# Держим E: чиним до полного, лишний хлам не тратится.
	hold(KEY_E)
	await wait(1.5)
	release(KEY_E)
	await wait(0.1)
	ok("машина починена полностью", is_equal_approx(gen.hp, gen.max_hp), "hp %.0f/%.0f" % [gen.hp, gen.max_hp])
	ok("хлама ушло ровно на ремонт", player.inv.count_of(IDs.I.SCRAP) == 2,
			"хлама %d (было 5, нужно 3)" % player.inv.count_of(IDs.I.SCRAP))

	# Целая горелка: хлам в руке не рубильник и не топка.
	await _tap(KEY_E)
	ok("целую горелку хлам не чинит", player.inv.count_of(IDs.I.SCRAP) == 2)
	ok("у целой горелки хлам не дёргает рубильник", gen.enabled
			and gen.fuel_units() == 0, "топлива %d" % gen.fuel_units())

	# Маяк и сундук рубильника не имеют. Целые — хлам цел, E их не ломает.
	await _intact("маяк", "Pharos", Vector2i(pc.x + 4, floor_y - 1))
	await _intact("сундук", "Chest", Vector2i(pc.x - 2, floor_y - 1))
	finish()


## Целая машина: E с хламом не тратит хлам и не снимает постройку.
func _intact(title: String, kind: String, cell: Vector2i) -> void:
	if World.get_tile_v(cell) != IDs.T.AIR:
		World.set_tile(cell.x, cell.y, IDs.T.AIR)
	ok("%s поставлен" % title, MachineBase.place_machine(kind, cell), str(cell))
	var m = World.machines.get(cell)
	if m == null:
		return
	aim(m.global_position)
	await wait(0.2)
	var scrap: int = player.inv.count_of(IDs.I.SCRAP)
	await _tap(KEY_E)
	ok("целый %s хлам не чинит" % title, player.inv.count_of(IDs.I.SCRAP) == scrap,
			"хлама %d" % player.inv.count_of(IDs.I.SCRAP))
	ok("%s на месте" % title, World.machines.get(cell) == m)


## Нажать и отпустить клавишу (как человек: несколько кадров зажата).
func _tap(code: int) -> void:
	hold(code)
	await wait(0.2)
	release(code)
	await wait(0.15)
