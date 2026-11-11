extends ScenarioBase
## ПКМ ставит постройку (путь игрока, а не прямой вызов MachineBase).
##
## Регресс: в player.gd вид машины брался из строки «machine:» через substr(7),
## то есть вместе с двоеточием, — match в MachineBase не сходился. Ставим
## горелку кликом и проверяем, что она на месте.


func run() -> void:
	await wait(0.3)
	var bx: int = World.beacon_cell.x
	var row: int = World.beacon_cell.y
	stand_in_corridor(2)                      # герой в колонке bx+3
	player.inv.add(IDs.I.BURNER, 1)
	var slot: int = -1
	for i in player.inv.slots.size():
		if player.inv.slots[i].id == IDs.I.BURNER:
			slot = i
			break
	ok("горелка в хотбаре", slot >= 0, "слот %d" % slot)
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

	ok("ПКМ поставил горелку", World.machines.has(cell) and World.machines[cell].kind == "Burner",
			str(cell))
	ok("горелка ушла из хотбара", player.inv.count_of(IDs.I.BURNER) == 0)
	finish()
