extends "res://tools/scenarios/balance_common.gd"
## Бот баланса «ночь 3 без обороны» (#33, ADR-001 § 2: база теряет ≥ 1 машину).
##
## У релея — «обычная» база (2 ТЭЦ, 2 бура, плавильня, сборщик), обороны нет.
## С #173 угроза считается от горелок и маяков, не от генераторов: две горящие
## горелки открывают рой, иначе пустая смена 3 — только эхо, и база не теряет
## машин. Смена 3, ночь ведёт штатный директор. Герой стоит у релея и базу не
## защищает (бессмертен, чтобы смерть не перемотала ночь к рассвету).

const SPEED: float = 2.0
const TARGET_LOST: int = 1


func run() -> void:
	Game.time_of_day = 0.30
	await wait_game(0.3)
	var base: Dictionary = build_base(false)
	ok("база поставлена: %d машин" % base["machines"].size(), bool(base["ok"]))
	var lit: int = _light_two_burners(base["machines"])
	ok("две горелки горят (рой открыт)", lit == 2, "%d" % lit)
	var res: Dictionary = await siege_night(3, SPEED)
	metric("night3_lost", float(res["lost"]), "машин потеряно за ночь 3 без обороны")
	ok("ночь 3 без обороны: потеряно ≥ %d машины" % TARGET_LOST, int(res["lost"]) >= TARGET_LOST,
			"%d" % int(res["lost"]))
	finish()


## Две горелки рядом с базой, с углём: рою есть куда лететь, ночи есть бюджет.
func _light_two_burners(machines: Array) -> int:
	var row: int = World.beacon_cell.y
	var bx: int = World.beacon_cell.x
	var lit: int = 0
	for dx in [4, 15]:
		var c: Vector2i = Vector2i(bx + dx, row - 1)
		if World.get_tile_v(c) != IDs.T.AIR or World.machines.has(c):
			continue
		if not MachineBase.place_machine("Burner", c):
			continue
		var b: Burner = World.machines[c]
		b.add_fuel(IDs.I.COAL, 8)
		machines.append(b)
		b.destroyed.connect(func(mb: MachineBase) -> void: _lost.append(mb.kind))
		lit += 1
	return lit
