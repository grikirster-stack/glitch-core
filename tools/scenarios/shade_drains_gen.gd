extends ScenarioBase
## Тень дренирует ТЭЦ (ADR-001, § 4.5): свет её не пугает, у ТЭЦ она сжигает
## 1 уголь за SHADE_DRAIN_PERIOD секунд сверх обычного горения.

func run() -> void:
	var base: int = stand_in_corridor(0)
	player.invuln = 1.0e9
	var bx: int = World.beacon_cell.x
	var gen_cell: Vector2i = Vector2i(bx + 14, base - 1)
	ok("ТЭЦ поставлена", MachineBase.place_machine("CoalGen", gen_cell))
	var gen: Node = World.machines.get(gen_cell)
	if gen == null:
		finish()
		return
	gen.add_fuel(10)
	await wait(0.3)
	var light: float = World.light_at(gen_cell)
	var spawn: Vector2 = World.cell_to_world(Vector2i(bx + 9, base - 1)) + Vector2(0.0, -3.0)
	var ph: Node = spawn_phantom_at(spawn, "shade")
	ok("тень появилась", ph != null and ph.kind == "shade")
	if ph == null:
		finish()
		return
	var fuel0: float = float(gen.fuel)
	var t0: int = Time.get_ticks_msec()
	var drained: bool = await wait_until(func(): return int(ph.coal_drained) >= 1, 10.0)
	var elapsed: float = float(Time.get_ticks_msec() - t0) / 1000.0
	var lost: float = fuel0 - float(gen.fuel)
	ok("тень пошла к ТЭЦ, а не к игроку", ph.target_machine == gen)
	ok("тень не боится света", ph.state != Phantom.St.FLEE, "свет у ТЭЦ %.2f" % light)
	ok("тень сожгла уголь", drained, "сожжено %d" % int(ph.coal_drained))
	ok("ТЭЦ потеряла уголь сверх горения", lost - elapsed >= Balance.COAL_BURN * 0.9,
			"потеря %.0f с топлива за %.1f с" % [lost, elapsed])
	ok("ТЭЦ тень не ломает", is_instance_valid(gen) and gen.hp >= gen.max_hp)

	# Касание гасит солнечную панель (рубильник #25).
	gen.destroy()
	var sol_cell: Vector2i = Vector2i(bx + 16, base - 1)
	ok("солнечная панель поставлена", MachineBase.place_machine("Solar", sol_cell))
	var sol: Node = World.machines.get(sol_cell)
	if sol == null:
		finish()
		return
	var off: bool = await wait_until(func(): return not sol.enabled, 8.0)
	ok("касание тени выключило солнце", off, "цель %s" % str(ph.target_machine))
	finish()
