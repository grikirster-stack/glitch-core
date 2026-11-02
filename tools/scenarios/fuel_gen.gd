extends ScenarioBase
## ТЭЦ, поставленное вплотную к терминалу, всё равно заправляется углём.
##
## Регресс: терминал перехватывал E в радиусе 42 px, поэтому у терминала
## (а ТЭЦ подсказка просит ставить именно рядом) E до ТЭЦ не доходило:
## вместо загрузки угля приходило «Терминал: нет питания». Теперь E уходит
## постройке под курсором, если в руке уголь.


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

	# Клетка вплотную к терминалу: у базы слева от терминала пусто.
	var cell: Vector2i = t + Vector2i(-1, 0)
	ok("клетка рядом с терминалом свободна", World.get_tile_v(cell) == IDs.T.AIR, str(cell))
	ok("ТЭЦ поставлена вплотную к терминалу", MachineBase.place_machine("CoalGen", cell))
	var gen: CoalGen = World.machines.get(cell) as CoalGen
	if gen == null:
		finish()
		return

	# Уголь в руке.
	player.inv.add(IDs.I.COAL, 3)
	var slot: int = -1
	for i in player.inv.slots.size():
		if player.inv.slots[i].id == IDs.I.COAL:
			slot = i
			break
	ok("уголь в хотбаре", slot >= 0, "слот %d" % slot)
	if slot < 0:
		finish()
		return
	player.inv.selected = slot

	# Герой вплотную к терминалу — как и стоит, чтобы заправить ТЭЦ.
	player.global_position = World.cell_to_world(cell)
	player.vel = Vector2.ZERO
	await wait(0.3)

	Game.notification.connect(_on_note)
	# Курсор на ТЭЦ, E с углём в руке.
	aim(World.cell_to_world(cell))
	await wait(0.2)
	press_mouse(MOUSE_BUTTON_LEFT)   # ЛКМ не нужен: снимаем фокус с мира
	release_mouse(MOUSE_BUTTON_LEFT)
	hold(KEY_E)
	await wait(0.4)
	release(KEY_E)
	await wait(0.2)

	ok("уголь загружен в ТЭЦ", gen.fuel > 0.0, "топка %.1f с" % gen.fuel)
	ok("уголь ушёл из хотбара", player.inv.count_of(IDs.I.COAL) == 0,
			"осталось %d" % player.inv.count_of(IDs.I.COAL))
	var no_power: int = 0
	for n in _notices:
		if String(n).contains("нет питания"):
			no_power += 1
	ok("терминал не перехватил E", no_power == 0, str(_notices))
	finish()


func _on_note(text: String, _color: Color) -> void:
	_notices.append(text)
