extends ScenarioBase
## Добыча: навести «мышь» на тайл, держать ЛКМ → mining_progress растёт →
## тайл сломан → выпал предмет.

func run() -> void:
	await wait(0.3)
	var cell: Vector2i = find_mineable()
	ok("найден тайл для добычи", cell.x >= 0, str(cell))
	if cell.x < 0:
		finish()
		return
	var before: int = World.get_tile_v(cell)
	var mined_before: int = Game.stats_mined
	var drop: int = DB.tile_drop(before)

	# Наводим курсор на тайл и держим ЛКМ.
	aim(World.cell_to_world(cell))
	press_mouse(MOUSE_BUTTON_LEFT)
	await wait(0.35)
	ok("прогресс копки растёт", player.mining_progress > 0.0, "%.2f" % player.mining_progress)
	ok("копка идёт по наведённому тайлу", player.mining_cell == cell, str(player.mining_cell))

	# Ждём, пока тайл сломается.
	var broke: bool = await wait_until(func() -> bool: return World.get_tile_v(cell) != before, 6.0)
	release_mouse(MOUSE_BUTTON_LEFT)
	ok("тайл сломан", broke, "%s → воздух" % DB.tile_name(before))
	ok("счётчик добычи вырос", Game.stats_mined > mined_before,
			"%d → %d" % [mined_before, Game.stats_mined])

	# Выпал ли предмет.
	var found: bool = false
	for n in scene.get_children():
		if n is ItemEntity and n.item_id == drop:
			found = true
			break
	ok("после разрушения выпал предмет", found, DB.item_name(drop))
	finish()
