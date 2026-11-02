extends "res://tools/scenarios/balance_common.gd"
## Бот баланса «ночь 3 без обороны» (#33, ADR-001 § 2: база теряет ≥ 1 машину).
##
## У релея — «обычная» база (2 ТЭЦ, 2 бура, плавильня, сборщик), обороны нет.
## Смена 3, ночь ведёт штатный директор угрозы (бюджет, состав: эхо, рой, тень;
## вентиляции, телеграф). Герой стоит у релея и базу не защищает (не бьёт;
## бессмертен, чтобы смерть не перемотала ночь к рассвету). Меряем, сколько
## машин разрушено за ночь.

const SPEED: float = 2.0
const TARGET_LOST: int = 1


func run() -> void:
	Game.time_of_day = 0.30
	await wait_game(0.3)
	var base: Dictionary = build_base(false)
	ok("база поставлена: %d машин" % base["machines"].size(), bool(base["ok"]))
	var res: Dictionary = await siege_night(3, SPEED)
	metric("night3_lost", float(res["lost"]), "машин потеряно за ночь 3 без обороны")
	ok("ночь 3 без обороны: потеряно ≥ %d машины" % TARGET_LOST, int(res["lost"]) >= TARGET_LOST,
			"%d" % int(res["lost"]))
	finish()
