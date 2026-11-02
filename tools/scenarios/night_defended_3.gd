extends "res://tools/scenarios/balance_common.gd"
## Бот баланса «ночь 3 с 2 турелями + стеной» (#33, ADR-001 § 2: 0 потерь).
##
## Та же база и та же ночь, что в night_siege_3, плюс 2 турели-разрядника и
## стальная стена по бокам. Турель — зона обороны (#31): пока её нет в игре
## (MachineBase.place_machine("Turret") не ставит), сценарий честно отложен —
## пишет «[баланс] night3_def_lost=NA» и цель не проверяет.

const SPEED: float = 3.0


func run() -> void:
	Game.time_of_day = 0.30
	await wait_game(0.3)
	if not _turret_available():
		print("  SKIP турели ещё нет в игре — цель отложена до обороны (#31)")
		metric_na("night3_def_lost", "нет турели (#31)")
		finish()
		return
	var base: Dictionary = build_base(true)
	ok("база с обороной поставлена: %d машин, турелей %d" % [base["machines"].size(), int(base["turrets"])],
			bool(base["ok"]) and int(base["turrets"]) == 2)
	var res: Dictionary = await siege_night(3, SPEED)
	metric("night3_def_lost", float(res["lost"]), "машин потеряно за ночь 3 с 2 турелями и стеной")
	ok("ночь 3 с 2 турелями и стеной: 0 потерь", int(res["lost"]) == 0, "%d" % int(res["lost"]))
	finish()


## Есть ли турель в игре: пробная постройка в свободной клетке и снос.
func _turret_available() -> bool:
	var c: Vector2i = Vector2i(World.beacon_cell.x + 9, World.beacon_cell.y - 6)
	if World.get_tile_v(c) != IDs.T.AIR or World.machines.has(c):
		return false
	if not MachineBase.place_machine("Turret", c):
		return false
	var m = World.machines[c]
	World.machines.erase(c)
	m.queue_free()
	return true
