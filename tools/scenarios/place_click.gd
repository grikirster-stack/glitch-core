extends ScenarioBase
## ПКМ ставит постройку (путь игрока, а не прямой вызов MachineBase).
##
## Регресс: в player.gd вид машины брался из строки «machine:» через substr(7),
## то есть вместе с двоеточием («:CoalGen»), — match в MachineBase не сходился,
## и любая постройка, поставленная правой кнопкой, отвечала «Сюда нельзя
## поставить». Ставим ТЭЦ кликом и проверяем, что она на месте.


func run() -> void:
	await wait(0.3)
	var bx: int = World.beacon_cell.x
	var row: int = World.beacon_cell.y
	stand_in_corridor(2)                      # герой в колонке bx+3
	# ТЭЦ в хотбаре, в руке.
	player.inv.add(IDs.I.COAL_GEN, 1)
	var slot: int = -1
	for i in player.inv.slots.size():
		if player.inv.slots[i].id == IDs.I.COAL_GEN:
			slot = i
			break
	ok("ТЭЦ в хотбаре", slot >= 0, "слот %d" % slot)
	if slot < 0:
		finish()
		return
	player.inv.selected = slot
	await wait(0.2)

	# Свободная клетка в двух шагах от героя: не под ним, в досягаемости.
	var cell: Vector2i = Vector2i(bx + 5, row)
	ok("клетка свободна", World.get_tile_v(cell) == IDs.T.AIR, str(cell))

	aim(World.cell_to_world(cell))
	await wait(0.2)
	press_mouse(MOUSE_BUTTON_RIGHT)
	await wait(0.4)
	release_mouse(MOUSE_BUTTON_RIGHT)
	await wait(0.2)

	ok("ПКМ поставил ТЭЦ", World.machines.has(cell) and World.machines[cell] is CoalGen,
			str(cell))
	ok("ТЭЦ ушла из хотбара", player.inv.count_of(IDs.I.COAL_GEN) == 0)
	finish()
