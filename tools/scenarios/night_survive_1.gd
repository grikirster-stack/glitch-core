extends "res://tools/scenarios/balance_common.gd"
## Бот баланса «ночь 1 без построек» (#33, ADR-001 § 2: игрок с 3 лампами
## переживает 90 с).
##
## Герой со стартовым набором уходит от базы на тёмную поверхность, ставит
## три светокристалла (ПКМ через шов ввода) и стоит. Ночь ведёт штатный
## директор угрозы (бюджет смены 1, вентиляции, телеграф) — сценарий только
## зовёт Threat.tick. Бот-боец бьёт фантома, если тот подошёл на удар, и жмёт Q
## вплотную. Меряем hp через 90 с ночи и число смертей.
##
## Для сравнения (не проверка, только цифра в логе): та же ночь в другом тёмном
## месте без ламп — видно, что ночь кусается и лампы что-то решают.

const NIGHT_SECS: float = 90.0
const SPEED: float = 3.0


func run() -> void:
	Game.time_of_day = 0.30
	await wait_game(0.3)
	var spot: Vector2i = dark_surface_spot(40, 160)
	ok("тёмное место на поверхности вдали от базы", spot.x >= 0, str(spot))
	if spot.x < 0:
		finish()
		return
	stand_at_cell(spot)
	await wait_game(0.4)
	var lamps0: int = player.inv.count_of(IDs.I.LAMP)
	ok("в стартовом наборе 3 лампы", lamps0 >= 3, "%d" % lamps0)

	# Три лампы вокруг: слева и справа у пола, третья — над головой (или рядом,
	# если клетка занята рельефом).
	var pc: Vector2i = World.world_to_cell(player.global_position)
	var placed: int = 0
	if await select_item(IDs.I.LAMP):
		for c in [pc + Vector2i(-2, 0), pc + Vector2i(2, 0), pc + Vector2i(0, -3),
				pc + Vector2i(-3, 0), pc + Vector2i(3, 0), pc + Vector2i(-1, -3),
				pc + Vector2i(1, -3), pc + Vector2i(-2, -2), pc + Vector2i(2, -2)]:
			if placed >= 3:
				break
			if World.get_tile_v(c) == IDs.T.AIR and await place_selected(c, IDs.T.LIGHT_CRYSTAL):
				placed += 1
	ok("три лампы поставлены через шов (ПКМ)", placed == 3, "%d" % placed)
	var light: float = World.light_at(World.world_to_cell(player.global_position))
	print("  свет на герое %.2f (эхо убегает от > %.2f)" % [light, float(Balance.PHANTOMS["echo"]["light_flee"])])

	var res: Dictionary = await _night(1)
	metric("night1_hp_end", float(res["hp"]), "hp через 90 с ночи 1 с тремя лампами")
	metric("night1_deaths", float(res["deaths"]))
	print("  [ночь 1, 3 лампы] фантомов вышло %d, одновременно до %d, мин. hp %.0f, смертей %d" % [
			int(res["spawned"]), int(res["max_alive"]), float(res["min_hp"]), int(res["deaths"])])
	ok("ночь 1 с тремя лампами: hp > 0 через %.0f с" % NIGHT_SECS,
			int(res["deaths"]) == 0 and float(res["hp"]) > 0.0, "hp %.0f" % float(res["hp"]))

	# ---- для сравнения: без ламп
	clear_phantoms()
	Threat.reset()
	player.hp = Player.MAX_HP
	var spot2: Vector2i = dark_surface_spot(170, 300)
	if spot2.x >= 0:
		stand_at_cell(spot2)
		await wait_game(0.4)
		var res2: Dictionary = await _night(1)
		metric("night1_nolamp_hp_end", float(res2["hp"]), "для сравнения: та же ночь без ламп")
		print("  [ночь 1, без ламп] фантомов вышло %d, мин. hp %.0f, смертей %d" % [
				int(res2["spawned"]), float(res2["min_hp"]), int(res2["deaths"])])
	finish()


## Прожить ночь day: от начала ночи NIGHT_SECS игровых секунд, бот-боец на месте.
func _night(day: int) -> Dictionary:
	Game.day_number = day
	Game.time_of_day = Balance.NIGHT_START - 1.0 / Balance.DAY_LENGTH
	seed_threat(day)
	var deaths0: int = Game.stats_deaths
	var spawned0: int = Threat.spawned_total
	drive_threat = true
	speed_up(SPEED)
	await wait_game_until(func() -> bool: return Game.is_night(), 5.0)
	var t0: float = clock
	var min_hp: float = player.hp
	var max_alive: int = 0
	while clock - t0 < NIGHT_SECS:
		fight_step()
		min_hp = minf(min_hp, player.hp)
		max_alive = maxi(max_alive, Threat.units_alive())
		await get_tree().process_frame
	normal_speed()
	drive_threat = false
	release_mouse(MOUSE_BUTTON_LEFT)
	release(KEY_Q)
	var deaths: int = Game.stats_deaths - deaths0
	return {
		"hp": 0.0 if (deaths > 0 or player.dead) else player.hp,
		"min_hp": 0.0 if deaths > 0 else min_hp,
		"deaths": deaths,
		"spawned": Threat.spawned_total - spawned0,
		"max_alive": max_alive,
	}
