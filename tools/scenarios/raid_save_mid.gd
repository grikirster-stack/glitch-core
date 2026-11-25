extends ScenarioBase
## Сейв посреди налёта (#316): фаза, цель, остаток и id награды живы.
## После загрузки мир играбелен: герой на месте, налёт не сносит базу сам.


const SLOT: String = "raid_mid"


func run() -> void:
	var origin: Vector2i = World.beacon_cell + Vector2i(6, -3)
	for y in range(-1, 3):
		for x in range(-1, 4):
			World.set_tile(origin.x + x, origin.y + y, IDs.T.AIR)
	var bed: SporeBed = RaidCommon.place_bed(origin, false)
	RaidCommon.arm(5)
	Threat.tick(0.05)
	RaidCommon.tick(Game.raid_remain + 0.2)
	ok("налёт идёт", Game.raid_phase == 2, str(Game.raid_phase))
	Game.raid_reward_id = Game.raid_number
	var phase: int = Game.raid_phase
	var target: Vector2i = Game.raid_target
	var remain: float = Game.raid_remain
	var reward: int = Game.raid_reward_id
	var num: int = Game.raid_number
	ok("сейв середины налёта", Save.save_game(SLOT))
	Game.raid_phase = 0
	Game.raid_active = false
	Game.raid_target = Vector2i(1, 1)
	Game.raid_remain = 1.0
	Game.raid_reward_id = 0
	ok("загрузка середины", Save.load_game(SLOT))
	ok("фаза середины", Game.raid_phase == phase, str(Game.raid_phase))
	ok("номер середины", Game.raid_number == num, str(Game.raid_number))
	ok("цель середины", Game.raid_target == target, str(Game.raid_target))
	ok("остаток середины", absf(Game.raid_remain - remain) < 0.6, "%.2f vs %.2f" % [Game.raid_remain, remain])
	ok("id награды середины", Game.raid_reward_id == reward, str(Game.raid_reward_id))
	ok("после загрузки герой жив", player != null and player.hp > 0.0)
	ok("грядка на месте", World.machines.has(origin) and bed.hp > 0.0)
	Save.remove(SLOT)
	finish()
