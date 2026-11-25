extends ScenarioBase
## Сейв во время предупреждения (#316): фаза, цель, остаток и id награды
## возвращаются. Старый файл без полей налёт не выдумывает.


const SLOT: String = "raid_warn"


func run() -> void:
	var origin: Vector2i = World.beacon_cell + Vector2i(6, -3)
	for y in range(-1, 3):
		for x in range(-1, 4):
			World.set_tile(origin.x + x, origin.y + y, IDs.T.AIR)
	var bed: SporeBed = RaidCommon.place_bed(origin, false)
	ok("грядка для предупреждения", bed != null)
	RaidCommon.arm(4)
	Game.raid_reward_id = 0
	Threat.tick(0.05)
	RaidCommon.tick(3.0)
	ok("фаза — предупреждение", Game.raid_phase == 1)
	var phase: int = Game.raid_phase
	var num: int = Game.raid_number
	var target: Vector2i = Game.raid_target
	var remain: float = Game.raid_remain
	var reward: int = Game.raid_reward_id
	ok("сейв предупреждения", Save.save_game(SLOT))
	Game.raid_phase = 0
	Game.raid_target = Vector2i(-1, -1)
	Game.raid_remain = 0.0
	Game.raid_number = 0
	ok("загрузка предупреждения", Save.load_game(SLOT))
	ok("фаза восстановлена", Game.raid_phase == phase, str(Game.raid_phase))
	ok("номер восстановлен", Game.raid_number == num, str(Game.raid_number))
	ok("цель восстановлена", Game.raid_target == target, str(Game.raid_target))
	ok("остаток восстановлен", absf(Game.raid_remain - remain) < 0.6, "%.2f vs %.2f" % [Game.raid_remain, remain])
	ok("id награды восстановлен", Game.raid_reward_id == reward, str(Game.raid_reward_id))
	Save.remove(SLOT)
	finish()
