extends ScenarioBase
## Приоритет E (#116): сундук рядом с терминалом без питания открывается по E.
##
## Регресс: player._do_interact перебирал объекты жёстким порядком «терминал
## раньше сундука», и терминал руины без питания в ~37 px от тайника забирал E —
## тайник было не открыть (CI main на сиде 12345, inventory_transfer). Теперь цель
## E одна — Player.interact_target(): объект под курсором (если дотягиваемся),
## иначе ближайший (при равенстве терминал без питания уступает). Что у самого
## терминала E достаётся терминалу, проверяет chest_vs_terminal.
##
## Проверки: сундук через клетку от терминала базы без питания, герой между ними
## ближе к сундуку — цель E сундук, подсказка и рамка HUD на нём, E открывает его
## без «нет питания»; курсор на терминале — цель
## он, подсказка «нет питания» (рамки нет: без питания E не работает, V6), E даёт
## «нет питания» и сундук не открывает; курсор на сундуке — снова сундук.

var _notices: Array = []


func run() -> void:
	player.invuln = 1.0e9
	await wait(0.3)
	var hud: HUD = UI.hud
	var t: Vector2i = Vector2i(-1, -1)
	for c in World.terminals:
		if int(World.terminal_chapters.get(c, -1)) == 0:
			t = c
			break
	ok("есть терминал базы", t.x >= 0, str(t))
	if t.x < 0:
		finish()
		return
	ok("терминал базы без питания", not Game.is_powered(World.cell_to_world(t)))

	# Слева от терминала у базы пусто: герой — в соседней клетке, сундук — через одну.
	var stand: Vector2i = t + Vector2i(-1, 0)
	var chest_cell: Vector2i = t + Vector2i(-2, 0)
	if World.get_tile_v(chest_cell) != IDs.T.AIR:
		World.set_tile(chest_cell.x, chest_cell.y, IDs.T.AIR)
	ok("клетка рядом с героем свободна", World.get_tile_v(stand) == IDs.T.AIR, str(stand))
	ok("сундук поставлен через клетку от терминала", MachineBase.place_machine("Chest", chest_cell))
	var ch: Chest = World.machines.get(chest_cell) as Chest
	if ch == null:
		finish()
		return
	ch.receive_item(IDs.I.STONE, 3)

	# Пустая рука: в слоте не должно быть ни хлама (ремонт), ни того, что берёт станок.
	player.inv.selected = _empty_slot()
	# Чуть ближе к сундуку, но терминал — тоже в радиусе E (как тайник руины в ~37 px).
	player.global_position = World.cell_to_world(stand) + Vector2(-4, 0)
	player.vel = Vector2.ZERO
	# Курсор далеко вверху — ни на чём: цель выбирается по близости.
	aim(player.global_position + Vector2(0, -300))
	await wait(0.5)
	var p: Vector2 = player.global_position
	var td: float = World.cell_to_world(t).distance_to(p)
	var cd: float = ch.global_position.distance_to(p)
	ok("герой в радиусе E и терминала, и сундука (к сундуку ближе)",
			td < Player.E_TERMINAL and cd < Player.E_MACHINE and cd < td,
			"до терминала %.0f px, до сундука %.0f px" % [td, cd])

	var tg: Dictionary = player.interact_target()
	ok("цель E — сундук, а не терминал без питания", tg.get("kind", "") == Player.ET_CHEST
			and tg.get("node") == ch, str(tg))
	ok("подсказка HUD — «открыть сундук»", hud.hint_text == HUD.HINT_CHEST, "«%s»" % hud.hint_text)
	ok("рамка HUD — вокруг сундука", _mark_on(hud, ch.global_position), str(hud.mark_rect))

	Game.notification.connect(_on_note)
	hold(KEY_E)
	var opened: bool = await wait_until(func() -> bool: return UI.panel.visible and UI.panel.chest == ch, 2.0)
	release(KEY_E)
	ok("сундук рядом с терминалом открыт по E", opened)
	ok("терминал не перехватил E", _no_power_notes() == 0, str(_notices))
	if UI.panel.visible:
		UI.panel.close()
	await wait(0.2)

	# Курсор на терминале: цель — он, подсказка «нет питания».
	aim(World.cell_to_world(t))
	await wait(0.4)
	tg = player.interact_target()
	ok("курсор на терминале — цель E терминал без питания",
			tg.get("kind", "") == Player.ET_TERMINAL_OFF and tg.get("cell", Vector2i(-1, -1)) == t, str(tg))
	ok("подсказка HUD — «нет питания»", hud.hint_text == HUD.HINT_TERMINAL_NO_POWER, "«%s»" % hud.hint_text)
	ok("рамки нет: без питания E не работает (и не на сундуке)", hud.mark_rect.size == Vector2i.ZERO,
			str(hud.mark_rect))
	_notices.clear()
	hold(KEY_E)
	await wait(0.3)
	release(KEY_E)
	await wait(0.1)
	ok("E по терминалу — «нет питания»", _no_power_notes() == 1, str(_notices))
	ok("сундук при этом не открылся", not UI.panel.visible)
	ok("отсчёт задания не идёт", player.task_progress <= 0.0, "%.2f" % player.task_progress)

	# Курсор на сундуке — снова сундук (цель под курсором главнее).
	aim(ch.global_position)
	await wait(0.4)
	tg = player.interact_target()
	ok("курсор на сундуке — цель сундук", tg.get("kind", "") == Player.ET_CHEST and tg.get("node") == ch, str(tg))
	ok("рамка HUD — снова вокруг сундука", _mark_on(hud, ch.global_position), str(hud.mark_rect))
	Game.notification.disconnect(_on_note)
	clear_input()
	finish()


## Рамка интерактива вокруг точки мира (допуск 8 px, как в hud_hints).
func _mark_on(hud: HUD, world_pos: Vector2) -> bool:
	var sp: Vector2 = hud.get_viewport().get_canvas_transform() * world_pos
	return hud.mark_rect.size != Vector2i.ZERO and Rect2(hud.mark_rect).grow(8.0).has_point(sp)


func _empty_slot() -> int:
	for i in 10:
		if player.inv.get_slot(i).is_empty():
			return i
	player.inv.slots[9] = ItemStack.new()
	return 9


func _no_power_notes() -> int:
	var n: int = 0
	for s in _notices:
		if String(s).contains("нет питания"):
			n += 1
	return n


func _on_note(text: String, _color: Color) -> void:
	_notices.append(text)
