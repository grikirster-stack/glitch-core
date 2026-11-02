extends ScenarioBase
## Сундук рядом с терминалом: E достаётся тому, что ближе.
##
## Регресс на падение CI (сид 12345, сценарий «сундук ↔ инвентарь»):
## терминал руины стоит в 36 px от её тайника, а терминал перехватывал E в
## радиусе 42 px — тайник было невозможно открыть, вместо панели сундука
## приходило «Терминал: нет питания». Теперь E уходит тому, что ближе к
## герою: сундук рядом — открывается сундук, а у самого терминала — терминал.

var _notices: Array = []


func run() -> void:
	await wait(0.3)
	var t: Vector2i = Vector2i(-1, -1)
	for c in World.terminals:
		if int(World.terminal_chapters.get(c, -1)) == 0:
			t = c
			break
	ok("есть терминал базы", t.x >= 0, str(t))
	if t.x < 0:
		finish()
		return

	# Сундук вплотную к терминалу — ровно как тайник руины.
	var side: int = 0
	for s in [-1, 1]:
		if World.get_tile_v(t + Vector2i(s, 0)) == IDs.T.AIR:
			side = s
			break
	ok("сбоку от терминала есть пустая клетка", side != 0, str(t))
	if side == 0:
		finish()
		return
	var cell: Vector2i = t + Vector2i(side, 0)
	ok("сундук поставлен вплотную к терминалу", MachineBase.place_machine("Chest", cell))
	var ch: Chest = World.machines.get(cell) as Chest
	if ch == null:
		finish()
		return
	ch.slots[0] = ItemStack.new(IDs.I.SCRAP, 2)

	Game.notification.connect(_on_note)

	# ---- Герой у сундука: сундук ближе терминала — E открывает сундук -------------
	# Смещения — в сторону от терминала, чтобы герой был заведомо ближе к сундуку.
	var chest_spots: Array = [Vector2(0, -24), Vector2(side * 24, 0), Vector2(side * 24, -24)]
	var stood: bool = place_near(World.cell_to_world(cell), chest_spots)
	ok("герой встал у сундука", stood)
	await wait(0.3)
	hold(KEY_E)
	var opened: bool = await wait_until(func() -> bool:
			return UI.panel.visible and UI.panel.chest == ch, 3.0)
	release(KEY_E)
	clear_input()
	ok("сундук открыт по E", opened)
	ok("терминал не перехватил E", _no_power() == 0, str(_notices))
	UI.panel.close()
	await wait(0.2)

	# ---- Герой у терминала: терминал ближе сундука — E уходит терминалу -----------
	_notices.clear()
	var term_spots: Array = [Vector2(0, -24), Vector2(-side * 24, 0), Vector2(0, -40)]
	stood = place_near(World.cell_to_world(t), term_spots)
	ok("герой встал у терминала", stood)
	await wait(0.3)
	hold(KEY_E)
	await wait(0.6)
	release(KEY_E)
	clear_input()
	ok("у терминала сундук не открылся", not (UI.panel.visible and UI.panel.chest == ch))
	ok("терминал отвечает сам", _no_power() > 0, str(_notices))
	finish()


func _no_power() -> int:
	var n: int = 0
	for s in _notices:
		if String(s).contains("нет питания"):
			n += 1
	return n


func _on_note(text: String, _color: Color) -> void:
	_notices.append(text)
