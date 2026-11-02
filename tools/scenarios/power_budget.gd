extends ScenarioBase
## Бюджет мощности (ADR-001 § 4.3, #25): 1 ТЭЦ + 4 бура → efficiency 0.75,
## бур работает на 25 % медленнее, чем при 3 бурах (efficiency 1.0).
## Заодно: браун-аут (флаг и сигнал) и прочность машины — разрушенный бур
## снимает нагрузку, и мощности снова хватает всем.

const MEASURE_SECS: float = 3.0     ## окно замера наработки, игровые секунды
const TOLERANCE: float = 0.03       ## допуск на замедление (± 3 %)

var _brownout_log: Array = []


func run() -> void:
	player.invuln = 1.0e9
	Game.brownout_changed.connect(_on_brownout)
	# Площадка слева от базы: ни игрока, ни чужих генераторов рядом.
	var bx: int = World.beacon_cell.x
	var base: int = World.beacon_cell.y
	var gen_cell: Vector2i = Vector2i(bx - 34, base + 6)
	for x in range(gen_cell.x - 1, gen_cell.x + 7):
		for y in range(gen_cell.y - 1, gen_cell.y + 2):
			World.set_tile(x, y, IDs.T.AIR)
	ok("ТЭЦ поставлена", MachineBase.place_machine("CoalGen", gen_cell))
	var gen: CoalGen = World.machines.get(gen_cell)
	if gen == null:
		finish()
		return
	gen.add_fuel(CoalGen.FUEL_MAX_UNITS)
	var drills: Array = []
	for i in 3:
		var c: Vector2i = gen_cell + Vector2i(2 + i, 0)
		MachineBase.place_machine("Drill", c)
		drills.append(World.machines.get(c))
	ok("три бура поставлены", drills.size() == 3 and not drills.has(null))
	# Раскладка питания идёт раз в Balance.POWER_CHECK_INTERVAL игрового времени —
	# ждём её результат, а не фиксированную паузу (под нагрузкой кадры длинные).
	await wait_until(func() -> bool: return is_equal_approx(gen.power_load, 6.0), 3.0)
	await wait(Balance.POWER_CHECK_INTERVAL * 2.0)

	# Три бура: нагрузка 6 при мощности 6 — efficiency 1.0.
	var d0: Drill = drills[0]
	ok("ТЭЦ работает", gen.power_active, "fuel=%.0f" % gen.fuel)
	ok("нагрузка ТЭЦ = 3 × 2", is_equal_approx(gen.power_load, 6.0), "load=%.2f" % gen.power_load)
	ok("при 3 бурах efficiency = 1.0", is_equal_approx(d0.efficiency, 1.0), "eff=%.3f" % d0.efficiency)
	ok("браун-аута нет", not Game.brownout)
	var rate_full: float = await _work_rate(d0)

	# Четвёртый бур: нагрузка 8 при мощности 6 — efficiency 0.75.
	var c4: Vector2i = gen_cell + Vector2i(5, 0)
	MachineBase.place_machine("Drill", c4)
	var d4: Drill = World.machines.get(c4)
	ok("четвёртый бур поставлен", d4 != null)
	await wait_until(func() -> bool: return is_equal_approx(gen.power_load, 8.0), 3.0)
	await wait(Balance.POWER_CHECK_INTERVAL * 2.0)
	ok("нагрузка ТЭЦ = 4 × 2", is_equal_approx(gen.power_load, 8.0), "load=%.2f" % gen.power_load)
	ok("ТЭЦ: efficiency 0.75", is_equal_approx(gen.efficiency, 0.75), "eff=%.3f" % gen.efficiency)
	var all_075: bool = true
	for d in [drills[0], drills[1], drills[2], d4]:
		if d == null or not is_equal_approx(d.efficiency, 0.75):
			all_075 = false
	ok("все 4 бура получают efficiency 0.75", all_075, "eff=%.3f" % d0.efficiency)
	ok("браун-аут: флаг поднят", Game.brownout)
	ok("браун-аут: сигнал ушёл", _brownout_log.has(true), str(_brownout_log))
	ok("ТЭЦ перегружена", gen.overloaded())
	var rate_low: float = await _work_rate(d0)
	var slow: float = 1.0 - rate_low / maxf(rate_full, 0.0001)
	ok("бур медленнее на 25 % ± 3 %", absf(slow - 0.25) <= TOLERANCE,
			"полная %.3f, при перегрузе %.3f, замедление %.1f %%" % [rate_full, rate_low, slow * 100.0])

	# Прочность: урон снимает hp, разрушенный бур уходит из мира и с нагрузки.
	d4.take_damage(10.0)
	ok("урон снимает hp", is_equal_approx(d4.hp, Balance.MACHINE_HP - 10.0), "hp=%.0f" % d4.hp)
	d4.take_damage(Balance.MACHINE_HP)
	ok("бур разрушен и убран из мира", not World.machines.has(c4))
	await wait_until(func() -> bool: return is_equal_approx(gen.power_load, 6.0) and not Game.brownout, 3.0)
	await wait(Balance.POWER_CHECK_INTERVAL * 2.0)
	ok("после разрушения нагрузка снова 6", is_equal_approx(gen.power_load, 6.0), "load=%.2f" % gen.power_load)
	ok("после разрушения efficiency снова 1.0", is_equal_approx(d0.efficiency, 1.0), "eff=%.3f" % d0.efficiency)
	ok("браун-аут снят", not Game.brownout and _brownout_log.has(false), str(_brownout_log))
	Game.brownout_changed.disconnect(_on_brownout)
	finish()


## Наработка бура за секунду игрового времени (work_time / game_time).
func _work_rate(d: Drill) -> float:
	var w0: float = d.work_time
	var t0: float = Game.game_time
	await wait(MEASURE_SECS)
	var dt: float = Game.game_time - t0
	if dt <= 0.0:
		return 0.0
	return (d.work_time - w0) / dt


func _on_brownout(active: bool) -> void:
	_brownout_log.append(active)
