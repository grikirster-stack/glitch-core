extends ScenarioBase
## Ремонт (ADR-001 § 4.4, #29): E с хламом в хотбаре по повреждённой машине —
## +Balance.REPAIR_PER_SCRAP HP за единицу хлама. Целую машину хлам не чинит
## (и не тратится), а E с хламом по повреждённой ТЭЦ не дёргает рубильник.


func run() -> void:
	player.invuln = 1.0e9
	var floor_y: int = stand_in_corridor(8)
	await wait(0.4)
	var pc: Vector2i = World.world_to_cell(player.global_position)
	var cell: Vector2i = Vector2i(pc.x + 2, floor_y - 1)
	ok("ТЭЦ поставлена", MachineBase.place_machine("CoalGen", cell), str(cell))
	var gen: CoalGen = World.machines.get(cell)
	if gen == null:
		finish()
		return
	var d: float = gen.global_position.distance_to(player.global_position)
	ok("герой у ТЭЦ", d < 40.0, "%.0f px" % d)
	gen.take_damage(50.0)
	ok("ТЭЦ повреждена", gen.hp < gen.max_hp, "hp %.0f/%.0f" % [gen.hp, gen.max_hp])

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

	# Целая машина: E с хламом — обычное действие (здесь рубильник), хлам цел.
	await _tap(KEY_E)
	ok("целую машину хлам не чинит", player.inv.count_of(IDs.I.SCRAP) == 2)
	ok("у целой ТЭЦ E — снова рубильник", not gen.enabled)
	finish()


## Нажать и отпустить клавишу (как человек: несколько кадров зажата).
func _tap(code: int) -> void:
	hold(code)
	await wait(0.2)
	release(code)
	await wait(0.15)
