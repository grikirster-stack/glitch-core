extends ScenarioBase
## Приоритет E (#116, #170): сундук рядом с терминалом открывается по E.
##
## Регресс: player._do_interact перебирал объекты жёстким порядком «терминал
## раньше сундука», и терминал руины в ~37 px от тайника забирал E —
## тайник было не открыть (CI main на сиде 12345, inventory_transfer). Теперь цель
## E одна — Player.interact_target(): объект под курсором (если дотягиваемся),
## иначе ближайший. Питания больше нет: терминал читается без ТЭЦ.
##
## Проверки: сундук через клетку от терминала базы, герой между ними
## ближе к сундуку — цель E сундук, подсказка и рамка HUD на нём, E открывает его;
## курсор на терминале — цель он, подсказка «выполнить задание», E начинает
## отсчёт и сундук не открывает; курсор на сундуке — снова сундук.

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
	ok("терминал базы читается без ТЭЦ", Game.is_powered(World.cell_to_world(t)))

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
	ok("цель E — сундук, а не терминал", tg.get("kind", "") == Player.ET_CHEST
			and tg.get("node") == ch, str(tg))
	ok("подсказка HUD — «открыть сундук»", hud.hint_text == HUD.HINT_CHEST, "«%s»" % hud.hint_text)
	ok("рамка HUD — вокруг сундука", _mark_on(hud, ch.global_position), str(hud.mark_rect))

	Game.notification.connect(_on_note)
	hold(KEY_E)
	var opened: bool = await wait_until(func() -> bool: return UI.panel.visible and UI.panel.chest == ch, 2.0)
	release(KEY_E)
	ok("сундук рядом с терминалом открыт по E", opened)
	ok("терминал не перехватил E", _task_notes() == 0, str(_notices))
	if UI.panel.visible:
		UI.panel.close()
	await wait(0.2)

	# Курсор на терминале: цель — он, подсказка задания. Питание не нужно (#170).
	aim(World.cell_to_world(t))
	await wait(0.4)
	tg = player.interact_target()
	ok("курсор на терминале — цель E терминал",
			tg.get("kind", "") == Player.ET_TERMINAL and tg.get("cell", Vector2i(-1, -1)) == t, str(tg))
	ok("подсказка HUD — выполнить задание", hud.hint_text == HUD.HINT_TERMINAL, "«%s»" % hud.hint_text)
	_notices.clear()
	hold(KEY_E)
	var ticking: bool = await wait_until(func() -> bool: return player.task_progress > 0.05, 1.5)
	release(KEY_E)
	await wait(0.1)
	ok("E по терминалу начинает отсчёт", ticking, "%.2f" % player.task_progress)
	ok("сундук при этом не открылся", not UI.panel.visible)

	# Курсор на сундуке — снова сундук (цель под курсором главнее).
	aim(ch.global_position)
	await wait(0.4)
	tg = player.interact_target()
	ok("курсор на сундуке — цель сундук", tg.get("kind", "") == Player.ET_CHEST and tg.get("node") == ch, str(tg))
	ok("рамка HUD — снова вокруг сундука", _mark_on(hud, ch.global_position), str(hud.mark_rect))
	Game.notification.disconnect(_on_note)
	clear_input()
	finish()


## Рамка интерактива вокруг точки мира. Клетка в мировых px (#211).
func _mark_on(hud: HUD, world_pos: Vector2) -> bool:
	return hud.mark_on_world(world_pos)


func _empty_slot() -> int:
	for i in 10:
		if player.inv.get_slot(i).is_empty():
			return i
	player.inv.slots[9] = ItemStack.new()
	return 9


func _task_notes() -> int:
	var n: int = 0
	for s in _notices:
		if String(s).contains("Терминал"):
			n += 1
	return n


func _on_note(text: String, _color: Color) -> void:
	_notices.append(text)
