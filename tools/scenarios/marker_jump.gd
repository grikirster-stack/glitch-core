extends ScenarioBase
## Жёлтая рамка интерактива при прыжке (#211).
##
## Камера сглаживается и в прыжке отстаёт от героя. Раньше HUD кэшировал экранный
## прямоугольник в _process — canvas transform там ещё прошлый, и рамка ехала
## за камерой, а не за предметом. Теперь рамка рисуется в мировых px клетки.
##
## Кадр прыжка в headless не снять: камеру ставим в то же смещение (герой уехал
## вверх, камера ещё внизу) и сверяем, что рамка на клетке предмета.


func run() -> void:
	var base: int = stand_in_corridor(12)
	clear_input()
	var bx: int = World.beacon_cell.x
	var cell: Vector2i = Vector2i(bx + 14, base - 1)
	ok("сундук поставлен", MachineBase.place_machine("Chest", cell))
	var chest: Node2D = World.machines[cell]
	(chest as Chest).receive_item(IDs.I.STONE, 1)
	player.global_position = chest.global_position + Vector2(-22.0, 0.0)
	player.vel = Vector2.ZERO
	aim(chest.global_position)
	await wait(0.4)
	var hud: HUD = UI.hud
	ok("рамка на сундуке в покое", hud.mark_on_world(chest.global_position), str(hud.mark_rect))

	# Смещение прыжка: герой выше, сглаженная камера ещё на полу.
	var cam: Camera2D = player.camera
	var y0: float = player.global_position.y
	player.global_position.y = y0 - 48.0
	cam.position_smoothing_enabled = false
	cam.position = Vector2(0.0, 48.0)
	cam.force_update_scroll()
	# Подсказка и рамка сверяются не каждый кадр (HINT_RECHECK_SEC).
	await wait(0.4)
	var before: Rect2 = hud.mark_live_rect()
	var n_px: float = 40.0
	cam.position = Vector2(0.0, 48.0 - n_px / cam.zoom.y)
	cam.force_update_scroll()
	var after: Rect2 = hud.mark_live_rect()
	var shift: float = after.position.distance_to(before.position)
	var lag: float = hud.mark_screen_lag()
	ok("рамка на клетке сундука при смещении камеры", hud.mark_on_world(chest.global_position),
			str(after))
	ok("смещение рамки от клетки — 0 px", lag < 1.0, "%.2f px" % lag)
	# Камера сдвинулась на N px — экранный прямоугольник рамки тоже на N px.
	ok("экран рамки сдвинулся на те же %.0f px, что и камера" % n_px,
			absf(shift - n_px) < 1.5, "рамка %.2f px, камера %.0f px" % [shift, n_px])
	var moved: float = cam.get_screen_center_position().distance_to(player.global_position)
	ok("камера смещена как в прыжке", moved > 20.0, "камера %.1f px от героя" % moved)
	print("  СМЕЩЕНИЕ рамки от клетки предмета %.2f px (было 7 px); сдвиг экрана %.2f px при сдвиге камеры %.0f px" % [
		lag, shift, n_px])
	cam.position = Vector2.ZERO
	cam.position_smoothing_enabled = true
	cam.reset_smoothing()
	player.global_position.y = y0
	finish()
