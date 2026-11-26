extends ScenarioBase
## Сейв посреди налёта (#316): фаза, цель, остаток и id награды живы.
## После загрузки мир играбелен: герой на месте, налёт не сносит базу сам.


const SLOT: String = "raid_mid"


func run() -> void:
	var origin: Vector2i = World.beacon_cell + Vector2i(6, -3)
	for y in range(-1, 3):
		for x in range(-1, 4):
			World.set_tile(origin.x + x, origin.y + y, IDs.T.AIR)
	ok("грядка перед налётом", RaidCommon.place_bed(origin, false) != null)
	RaidCommon.arm(5)
	Threat.tick(0.05)
	RaidCommon.tick(Game.raid_remain + 0.2)
	ok("налёт идёт", Game.raid_phase == 2, str(Game.raid_phase))
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
	var restored := World.machines.get(origin) as SporeBed
	ok("грядка на месте", restored != null and restored.hp > 0.0)
	ok("телеграф налёта восстановлен", Threat._raid_phantom_alive())
	RaidCommon.tick(Balance.VENT_TELEGRAPH + 0.2)
	var raiders := RaidCommon.raid_phantoms()
	ok("после гудка идёт один налётчик", raiders.size() == 1 and Game.raid_phase == 2)
	if raiders.size() == 1:
		var attacker: Phantom = raiders[0]
		attacker.take_damage(1.0, player.global_position)
		var pos := attacker.global_position
		var hp := attacker.hp
		ok("сейв видимого налётчика", Save.save_game(SLOT) and Save.load_game(SLOT))
		raiders = RaidCommon.raid_phantoms()
		ok("позиция и здоровье налётчика вернулись", raiders.size() == 1
				and raiders[0].global_position.is_equal_approx(pos) and is_equal_approx(raiders[0].hp, hp))
		if raiders.size() == 1:
			var scrap := player.inv.count_of(IDs.I.SCRAP)
			raiders[0].take_damage(hp, player.global_position)
			ok("защитник получил награду без поломки", Game.raid_phase == 3 and Game.raid_damage == ""
					and Game.raid_reward_id == num and player.inv.count_of(IDs.I.SCRAP) == scrap + 2)
			ok("награда пережила сохранение итога", Save.save_game(SLOT) and Save.load_game(SLOT)
					and Game.raid_reward_id == num)
			Threat.tick(0.1)
			ok("после отражения награда не удвоилась", player.inv.count_of(IDs.I.SCRAP) == scrap + 2)
	Save.remove(SLOT)
	finish()
