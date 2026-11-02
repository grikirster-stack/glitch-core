extends ScenarioBase
## Ходьба: бот жмёт «вправо» → x растёт; отпускает → скорость падает;
## упирается в стену → не проходит сквозь неё.

func run() -> void:
	var base: int = stand_in_corridor()
	await wait(0.3)
	var bx: int = World.beacon_cell.x
	var x0: float = player.global_position.x

	# 1. Идём вправо.
	hold(KEY_D)
	await wait(0.9)
	var step: float = player.global_position.x - x0
	ok("герой сместился вправо", step > 80.0, "%.1f px" % step)
	ok("герой бежит вправо", player.vel.x > 100.0, "скорость %.1f" % player.vel.x)

	# 2. Отпустили — скорость падает.
	release(KEY_D)
	await wait(0.5)
	ok("герой остановился после отпускания", absf(player.vel.x) < 5.0, "скорость %.1f" % player.vel.x)

	# 3. Ставим стену и упираемся в неё.
	var wall_x: int = mini(bx + 17, World.world_to_cell(player.global_position).x + 3)
	for y in range(base - 1, base - 3, -1):
		World.set_tile(wall_x, y, IDs.T.STEEL)
	var before: float = player.global_position.x
	hold(KEY_D)
	await wait(1.6)
	release(KEY_D)
	var limit: float = float(wall_x * World.TILE) - Player.SIZE.x * 0.5
	ok("герой дошёл до стены", player.global_position.x > before + 8.0,
			"%.1f -> %.1f px" % [before, player.global_position.x])
	ok("герой не прошёл сквозь стену", player.global_position.x <= limit + 0.5,
			"x=%.1f, стена на %.1f" % [player.global_position.x, limit])
	ok("герой не в стене", not World.rect_solid(Rect2(player.global_position - Player.SIZE * 0.5, Player.SIZE)))
	ok("скорость у стены обнулена", absf(player.vel.x) < 5.0, "скорость %.1f" % player.vel.x)
	finish()
