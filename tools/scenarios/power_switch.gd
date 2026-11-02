extends ScenarioBase
## Рубильник (ADR-001 § 4.3, #25): E по ТЭЦ с углём в хотбаре загружает топку,
## E с другим предметом — выключает ТЭЦ. Выключенная ТЭЦ за 60 с игрового
## времени не тратит уголь, буры в её радиусе стоят. Повторное E — включает.
##
## 60 игровых секунд проматываем ускорением времени (Engine.time_scale), чтобы
## сценарий уложился в отведённую раннером минуту.

const OFF_GAME_SECS: float = 60.0
const TIME_SCALE: float = 5.0


func run() -> void:
	player.invuln = 1.0e9
	# Коридор справа от релея; герой — подальше от ядра (радиус E у релея 56 px).
	var floor_y: int = stand_in_corridor(10)
	await wait(0.4)
	var pc: Vector2i = World.world_to_cell(player.global_position)
	var gen_cell: Vector2i = Vector2i(pc.x + 2, floor_y - 1)
	for x in range(gen_cell.x, gen_cell.x + 6):
		World.set_tile(x, gen_cell.y, IDs.T.AIR)
	ok("ТЭЦ поставлена", MachineBase.place_machine("CoalGen", gen_cell), str(gen_cell))
	var gen: CoalGen = World.machines.get(gen_cell)
	if gen == null:
		finish()
		return
	var drills: Array = []
	for i in 2:
		var c: Vector2i = gen_cell + Vector2i(3 + i, 0)
		MachineBase.place_machine("Drill", c)
		drills.append(World.machines.get(c))
	ok("буры в радиусе ТЭЦ поставлены", not drills.has(null))
	var dist: float = gen.global_position.distance_to(player.global_position)
	ok("герой у ТЭЦ", dist < 40.0, "%.0f px" % dist)

	# Слот 2 — уголь из стартового набора. E — уголь уходит в топку.
	var coal0: int = player.inv.count_of(IDs.I.COAL)
	await _tap(KEY_2)
	await _tap(KEY_E)
	ok("E с углём загрузило топку", gen.fuel > 0.0 and player.inv.count_of(IDs.I.COAL) < coal0,
			"fuel=%.0f, угля %d → %d" % [gen.fuel, coal0, player.inv.count_of(IDs.I.COAL)])
	ok("уголь не выключил ТЭЦ", gen.enabled)
	await wait(0.6)
	ok("ТЭЦ работает", gen.power_active)
	ok("буры под питанием", drills[0].powered and drills[1].powered)

	# Слот 1 — лампа. E — рубильник: ТЭЦ выключена.
	await _tap(KEY_1)
	await _tap(KEY_E)
	ok("E выключило ТЭЦ", not gen.enabled)
	await wait(0.6)
	ok("выключенная ТЭЦ не даёт питания", not gen.power_active and not Game.is_powered(drills[0].global_position))
	ok("буры без питания", not drills[0].powered and not drills[1].powered)

	# 60 игровых секунд в выключенном состоянии.
	var fuel0: float = gen.fuel
	var work0: float = drills[0].work_time + drills[1].work_time
	var t0: float = Game.game_time
	Engine.time_scale = TIME_SCALE
	var passed: bool = await wait_until(func() -> bool: return Game.game_time - t0 >= OFF_GAME_SECS,
			OFF_GAME_SECS * 1.5)   # игровые секунды: под time_scale это ~18 с стены
	Engine.time_scale = 1.0
	ok("прошло 60 игровых секунд", passed, "%.1f с" % (Game.game_time - t0))
	ok("выключенная ТЭЦ не тратит уголь", is_equal_approx(gen.fuel, fuel0), "fuel %.2f → %.2f" % [fuel0, gen.fuel])
	var work1: float = drills[0].work_time + drills[1].work_time
	ok("буры в радиусе стоят", is_equal_approx(work1, work0), "наработка %.2f → %.2f" % [work0, work1])

	# E ещё раз — ТЭЦ снова в деле и жжёт уголь.
	await _tap(KEY_E)
	ok("E включило ТЭЦ", gen.enabled)
	await wait(1.0)
	ok("включённая ТЭЦ жжёт уголь", gen.fuel < fuel0, "fuel %.2f → %.2f" % [fuel0, gen.fuel])
	ok("буры снова под питанием", drills[0].powered and drills[1].powered)
	finish()


## Нажать и отпустить клавишу (как человек: несколько кадров зажата).
func _tap(code: int) -> void:
	hold(code)
	await wait(0.2)
	release(code)
	await wait(0.15)
