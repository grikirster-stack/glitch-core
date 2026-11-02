extends ScenarioBase
## Блокировка инвентаря: открыт инвентарь → ЛКМ и ПКМ по миру игнорируются.
##
## Панель инвентаря открывается настоящей клавишей I: UI слушает реальные
## события ввода, а не игровой шов. Поэтому здесь событие клавиатуры
## подкладывается через Input.parse_input_event — доходит оно до UI целиком.

func run() -> void:
	await wait(0.3)
	var cell: Vector2i = find_mineable()
	ok("найден тайл для проверки", cell.x >= 0, str(cell))
	if cell.x < 0:
		finish()
		return
	var before: int = World.get_tile_v(cell)
	var spot: Vector2i = _find_empty_spot()
	ok("найдено пустое место под постройку", spot.x >= 0, str(spot))

	# Открываем инвентарь.
	_press_key(KEY_I)
	await wait(0.4)
	ok("инвентарь открылся по клавише I", UI.blocking())

	# ЛКМ по миру игнорируется.
	aim(World.cell_to_world(cell))
	press_mouse(MOUSE_BUTTON_LEFT)
	await wait(0.6)
	ok("ЛКМ по миру игнорируется при открытом инвентаре",
			player.mining_progress <= 0.0 and World.get_tile_v(cell) == before,
			"прогресс %.2f" % player.mining_progress)
	release_mouse(MOUSE_BUTTON_LEFT)

	# ПКМ (постройка) тоже игнорируется.
	if spot.x >= 0:
		aim(World.cell_to_world(spot))
		press_mouse(MOUSE_BUTTON_RIGHT)
		await wait(0.5)
		ok("ПКМ по миру игнорируется при открытом инвентаре",
				World.get_tile_v(spot) == IDs.T.AIR, str(World.get_tile_v(spot)))
		release_mouse(MOUSE_BUTTON_RIGHT)

	# Закрываем инвентарь — управление возвращается.
	_press_key(KEY_I)
	await wait(0.4)
	ok("инвентарь закрылся", not UI.blocking())

	aim(World.cell_to_world(cell))
	press_mouse(MOUSE_BUTTON_LEFT)
	await wait(0.5)
	ok("после закрытия инвентаря копка работает",
			player.mining_progress > 0.0 or World.get_tile_v(cell) != before,
			"прогресс %.2f" % player.mining_progress)
	release_mouse(MOUSE_BUTTON_LEFT)

	if spot.x >= 0:
		aim(World.cell_to_world(spot))
		press_mouse(MOUSE_BUTTON_RIGHT)
		await wait(0.5)
		ok("после закрытия инвентаря постройка ставится",
				World.get_tile_v(spot) != IDs.T.AIR, str(World.get_tile_v(spot)))
		release_mouse(MOUSE_BUTTON_RIGHT)
	finish()


## Настоящее событие клавиши — так UI и панель инвентаря её слышат.
func _press_key(code: int) -> void:
	var ev: InputEventKey = InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)


## Пустая клетка рядом с героем, в которую можно поставить блок.
func _find_empty_spot() -> Vector2i:
	var pc: Vector2i = World.world_to_cell(player.global_position)
	var pr: Rect2 = Rect2(player.global_position - Player.SIZE * 0.5, Player.SIZE)
	for dy in range(-2, 3):
		for dx in range(-4, 5):
			var c: Vector2i = pc + Vector2i(dx, dy)
			if World.get_tile_v(c) != IDs.T.AIR:
				continue
			var w: Vector2 = World.cell_to_world(c)
			if w.distance_to(player.global_position) > Player.REACH - 4.0:
				continue
			var r: Rect2 = Rect2(Vector2(float(c.x * World.TILE), float(c.y * World.TILE)),
					Vector2(float(World.TILE), float(World.TILE)))
			if r.intersects(pr):
				continue
			return c
	return Vector2i(-1, -1)
