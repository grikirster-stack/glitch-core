extends ScenarioBase
## Журнал (#28): J открывает и закрывает JournalPanel; пока журнал открыт,
## ЛКМ и ПКМ по миру игнорируются (как с инвентарём). Непрочитанная глава —
## «▒▒▒», прочитанная (Tech.read_chapter) — с названием из Lore.
##
## Клавиши — настоящие события через Input.parse_input_event: UI слушает
## реальный ввод, а не шов игрока (см. tools/scenarios/inventory_block.gd).

func run() -> void:
	await wait(0.3)
	var journal: JournalPanel = UI.journal
	ok("журнал создан и закрыт", journal != null and not journal.visible)
	if journal == null:
		finish()
		return
	var cell: Vector2i = find_mineable()
	ok("найден тайл для проверки", cell.x >= 0, str(cell))
	var before: int = World.get_tile_v(cell) if cell.x >= 0 else -1
	var spot: Vector2i = _find_empty_spot()
	ok("найдено пустое место под постройку", spot.x >= 0, str(spot))

	# ---- J открывает ---------------------------------------------------------
	_press_key(KEY_J)
	await wait(0.4)
	ok("журнал открылся по J", journal.visible and UI.blocking())
	ok("в журнале весь экипаж", Lore.crew.size() == 7, "экипаж %d" % Lore.crew.size())
	ok("непрочитанная глава — «▒▒▒»", journal.chapter_label(0).contains(JournalPanel.LOCKED), journal.chapter_label(0))
	ok("глав не выбрано — читать нечего", journal.selected == -1)

	if cell.x >= 0:
		aim(World.cell_to_world(cell))
		press_mouse(MOUSE_BUTTON_LEFT)
		await wait(0.6)
		ok("ЛКМ по миру игнорируется при открытом журнале",
				player.mining_progress <= 0.0 and World.get_tile_v(cell) == before,
				"прогресс %.2f" % player.mining_progress)
		release_mouse(MOUSE_BUTTON_LEFT)
	if spot.x >= 0:
		aim(World.cell_to_world(spot))
		press_mouse(MOUSE_BUTTON_RIGHT)
		await wait(0.5)
		ok("ПКМ по миру игнорируется при открытом журнале",
				World.get_tile_v(spot) == IDs.T.AIR, str(World.get_tile_v(spot)))
		release_mouse(MOUSE_BUTTON_RIGHT)

	# ---- J закрывает ---------------------------------------------------------
	_press_key(KEY_J)
	await wait(0.4)
	ok("журнал закрылся по J", not journal.visible and not UI.blocking())

	# ---- Прочитанная глава и обрывок ------------------------------------------
	ok("глава 1 читается впервые", Tech.read_chapter(0))
	ok("повторное чтение не считается", not Tech.read_chapter(0) and Tech.read_chapters.size() == 1)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	ok("обрывок записан", Tech.add_fragment(Lore.fragment(rng)) and Tech.fragments.size() == 1)
	_press_key(KEY_J)
	await wait(0.4)
	ok("журнал открыт на прочитанной главе", journal.visible and journal.selected == 0, "глава %d" % journal.selected)
	ok("у прочитанной главы название", journal.chapter_label(0).contains(Lore.chapter_title(0))
			and not journal.chapter_label(0).contains(JournalPanel.LOCKED), journal.chapter_label(0))
	ok("остальные главы закрыты", journal.chapter_label(1).contains(JournalPanel.LOCKED))

	# ---- Окно одно за раз: I поверх журнала, J поверх инвентаря --------------
	_press_key(KEY_I)
	await wait(0.3)
	ok("I закрыл журнал и открыл инвентарь", UI.panel.visible and not journal.visible)
	_press_key(KEY_J)
	await wait(0.3)
	ok("J закрыл инвентарь и открыл журнал", journal.visible and not UI.panel.visible)
	_press_key(KEY_ESCAPE)
	await wait(0.3)
	ok("ESC закрыл журнал", not journal.visible and not UI.blocking())

	# ---- Управление вернулось --------------------------------------------------
	if cell.x >= 0:
		aim(World.cell_to_world(cell))
		press_mouse(MOUSE_BUTTON_LEFT)
		var dug: bool = await wait_until(func() -> bool:
				return player.mining_progress > 0.0 or World.get_tile_v(cell) != before, 1.5)
		ok("после закрытия журнала копка работает", dug, "прогресс %.2f" % player.mining_progress)
		release_mouse(MOUSE_BUTTON_LEFT)
	finish()


## Настоящее событие клавиши — так UI её слышит.
func _press_key(code: int) -> void:
	var ev: InputEventKey = InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)


## Пустая клетка рядом с героем, куда можно поставить блок (как в inventory_block.gd).
func _find_empty_spot() -> Vector2i:
	var pc: Vector2i = World.world_to_cell(player.global_position)
	var pr: Rect2 = Rect2(player.global_position - Player.SIZE * 0.5, Player.SIZE)
	for dy in range(-2, 3):
		for dx in range(-4, 5):
			var c: Vector2i = pc + Vector2i(dx, dy)
			if World.get_tile_v(c) != IDs.T.AIR:
				continue
			if World.cell_to_world(c).distance_to(player.global_position) > Player.REACH - 4.0:
				continue
			var r: Rect2 = Rect2(Vector2(float(c.x * World.TILE), float(c.y * World.TILE)),
					Vector2(float(World.TILE), float(World.TILE)))
			if r.intersects(pr):
				continue
			return c
	return Vector2i(-1, -1)
