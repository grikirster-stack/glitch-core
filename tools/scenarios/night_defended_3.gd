extends "res://tools/scenarios/balance_common.gd"
## Бот баланса «ночь 3 с 2 красными маяками + стеной» (#170).
## Та же база, что night_siege_3, плюс 2 маяка под красным (горелка и зеркало)
## и стальная стена по бокам.

const SPEED: float = 2.0


func run() -> void:
	Game.time_of_day = 0.30
	await wait_game(0.3)
	var base: Dictionary = build_base(true)
	ok("база с обороной поставлена: %d машин, маяков %d" % [base["machines"].size(), int(base["turrets"])],
			bool(base["ok"]) and int(base["turrets"]) == 2)
	var res: Dictionary = await siege_night(3, SPEED)
	metric("night3_def_lost", float(res["lost"]), "машин потеряно за ночь 3 с 2 маяками и стеной")
	ok("ночь 3 с 2 красными маяками и стеной: 0 потерь", int(res["lost"]) == 0, "%d" % int(res["lost"]))
	finish()
