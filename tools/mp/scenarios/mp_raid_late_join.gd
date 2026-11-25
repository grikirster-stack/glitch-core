extends "res://tools/mp/scenarios/mp_coop_base.gd"
## Поздний вход видит фазу и цель налёта (#316, PROTO 27).
## Хост владеет таймером. Клиент читает GLOBAL, не считает сам.


const WAIT: float = 12.0


func run_host() -> void:
	ok("хост + клиент вошли", await wait_players(2, 45.0))
	await barrier("in")
	var origin: Vector2i = World.beacon_cell + Vector2i(4, 0)
	if World.get_tile_v(origin) != IDs.T.AIR:
		World.set_tile(origin.x, origin.y, IDs.T.AIR)
	MachineBase.place_machine("SporeBed", origin)
	var bed = World.machines.get(origin)
	if bed != null:
		bed.beam_receive(0)
	Game.day_number = 3
	Game.time_of_day = 0.70
	Threat.active = true
	Game.raid_phase = 1
	Game.raid_number = 2
	Game.raid_target = origin
	Game.raid_remain = 18.0
	Game.raid_reward_id = 1
	Game.raid_active = false
	if Game.net_world != null and Game.net_world.has_method("publish_global"):
		Game.net_world.publish_global()
	share_put("phase", Game.raid_phase)
	share_put("target", Game.raid_target)
	share_put("number", Game.raid_number)
	await barrier("shown")
	await barrier("leave")
	ok("клиент вышел", await wait_until(func() -> bool: return Net.peers.size() == 1, 15.0))
	# Поздний вход: фаза уже в снимке и в живом GLOBAL.
	Game.raid_phase = 2
	Game.raid_active = true
	Game.raid_remain = 12.0
	Game.raid_reward_id = 2
	if Game.net_world != null and Game.net_world.has_method("publish_global"):
		Game.net_world.publish_global()
	share_put("phase2", Game.raid_phase)
	share_put("remain2", Game.raid_remain)
	share_put("reward2", Game.raid_reward_id)
	share_put("target2", Game.raid_target)
	relaunch(0)
	ok("клиент вошёл снова", await wait_players(2, 45.0))
	await barrier("back")
	share_clear(["phase", "target", "number", "phase2", "remain2", "reward2", "target2"])
	finish()


func run_client(_i: int) -> void:
	if is_rejoin():
		var back: bool = await wait_until(func() -> bool:
			return int(Net.session.get("port", 0)) != 0 and Game.net_world != null and Game.net_world.is_joined, WAIT)
		var want = share_get("phase2")
		var want_reward = share_get("reward2")
		var want_remain = share_get("remain2")
		var want_target = share_get("target2")
		var got: bool = back and await wait_until(func() -> bool:
			return Game.raid_phase == int(want) \
					and Game.raid_reward_id == int(want_reward) \
					and absf(Game.raid_remain - float(want_remain)) < 1.5 \
					and Game.raid_target == want_target, WAIT)
		ok("поздний вход видит фазу, цель, награду и остаток", got,
				"фаза %s, цель %s, награда %s, остаток %.1f" % [
					str(Game.raid_phase), str(Game.raid_target), str(Game.raid_reward_id), Game.raid_remain])
		await barrier("back")
		finish()
		return
	await barrier("in")
	var shown: bool = await wait_until(func() -> bool:
		return Game.raid_phase == 1 and Game.raid_target.x >= 0, WAIT)
	ok("уже вошедший видит предупреждение живым пакетом", shown,
			"фаза %d, цель %s" % [Game.raid_phase, str(Game.raid_target)])
	await barrier("shown")
	await barrier("leave")
	finish()
