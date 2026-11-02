extends ScenarioBase
## Прыжок: y уменьшается, потом растёт обратно; после приземления on_ground;
## двойного прыжка нет.

func run() -> void:
	stand_in_corridor()
	await wait(0.4)
	ok("герой стоит на земле", player.on_ground)
	var y0: float = player.global_position.y

	# Держим пробел: прыжок должен быть ровно один (кнопка ловится по фронту).
	var min_y: float = y0
	hold(KEY_SPACE)
	var t0: float = now()
	while now() - t0 < 1.2:
		min_y = minf(min_y, player.global_position.y)
		await wait(0.03)
	release(KEY_SPACE)
	var height: float = y0 - min_y
	ok("прыжок вверх", height > 20.0, "высота %.1f px" % height)
	ok("двойного прыжка нет", height < 70.0, "высота %.1f px" % height)

	# Ждём приземления.
	var landed: bool = false
	var t1: float = now()
	while now() - t1 < 3.0:
		if player.on_ground and player.global_position.y >= y0 - 1.0:
			landed = true
			break
		await wait(0.05)
	ok("герой приземлился", landed)
	ok("высота после приземления вернулась", absf(player.global_position.y - y0) < 3.0,
			"y=%.1f (было %.1f)" % [player.global_position.y, y0])
	ok("герой снова на земле", player.on_ground)
	finish()
