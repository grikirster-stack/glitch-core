extends ScenarioBase
## Разбор постройки («неправильно поставил — обратно взять»): удержание E над
## машиной снимает её с мира и возвращает её предмет в рюкзак. Правила: рука
## пустая, удержание Player.DISMANTLE_HOLD, постройки кампании и тайники руин
## (permanent) не трогаются, сундук с вещами сначала открывают.
##
## Проверки: подсказка «разобрать» и рамка HUD у бура; короткое нажатие E ничего
## не разбирает; удержание — бур исчез, предмет в рюкзаке; неразборная постройка
## остаётся на месте; пустой сундук разбирается, полный — открывается и не
## разбирается; манипулятор (у него своё действие E — фильтр) разбирается;
## ТЭЦ коротким E щёлкает рубильником, а удержанием снимается.

const ROW_OFF: int = 6      ## площадка под базой: столько рядов ниже релея


func run() -> void:
	player.invuln = 1.0e9
	clear_input()
	var hud: HUD = UI.hud
	var bx: int = World.beacon_cell.x
	var row: int = World.beacon_cell.y + ROW_OFF
	# Ровная площадка: пол — сталь, над ней пусто. В стороне от базы, чтобы рядом
	# не было ни релея, ни терминала, ни тайников руин.
	_platform(row, bx - 36, bx - 18)

	# ---- Зеркало: подсказка, короткое нажатие, удержание ------------------------
	var cell: Vector2i = Vector2i(bx - 34, row)
	ok("зеркало поставлено", MachineBase.place_machine("Mirror", cell), str(cell))
	var drill = World.machines.get(cell)
	if drill == null:
		finish()
		return
	var item: int = MachineBase.machine_item_id("Mirror")
	ok("у зеркала есть предмет в базе", item != IDs.I.NONE, str(item))
	_stand(cell)
	player.inv.selected = _empty_slot()
	aim(World.cell_to_world(cell))
	await wait(0.4)
	ok("цель E — разбор постройки", _target_kind() == Player.ET_DISMANTLE, _target_kind())
	ok("подсказка — разбор постройки",
			hud.hint_text == "%s: %s" % [HUD.HINT_DISMANTLE, DB.item_name(item)],
			"«%s»" % hud.hint_text)
	ok("рамка HUD — на зеркале", _mark_on(hud, drill.global_position), str(hud.mark_rect))

	var n0: int = player.inv.count_of(item)
	hold(KEY_E)
	await wait(0.3)
	release(KEY_E)
	await wait(0.2)
	ok("короткое нажатие E ничего не разбирает",
			World.machines.has(cell) and player.inv.count_of(item) == n0,
			"на месте %s, в рюкзаке %d" % [str(World.machines.has(cell)), player.inv.count_of(item)])

	player.inv.selected = _empty_slot()
	hold(KEY_E)
	await wait(1.3)
	release(KEY_E)
	await wait(0.2)
	ok("бур разобран — машины на клетке нет", not World.machines.has(cell))
	ok("предмет бура вернулся в рюкзак", player.inv.count_of(item) == n0 + 1,
			"%d → %d" % [n0, player.inv.count_of(item)])

	# ---- Неразборная постройка (кампания, тайники руин) --------------------------
	var pcell: Vector2i = Vector2i(bx - 31, row)
	ok("постройка поставлена", MachineBase.place_machine("Mirror", pcell), str(pcell))
	var perm = World.machines.get(pcell)
	if perm == null:
		finish()
		return
	perm.permanent = true
	_stand(pcell)
	player.inv.selected = _empty_slot()
	aim(World.cell_to_world(pcell))
	await wait(0.4)
	ok("неразборная постройка — не цель E", _target_kind() == "", _target_kind())
	hold(KEY_E)
	await wait(1.3)
	release(KEY_E)
	await wait(0.2)
	ok("неразборную постройку не снять", World.machines.has(pcell))
	ok("предмет не выпал в рюкзак", player.inv.count_of(item) == n0 + 1,
			"%d" % player.inv.count_of(item))

	# ---- Сундук: пустой разбирается, полный — сначала открыть -------------------
	var ccell: Vector2i = Vector2i(bx - 28, row)
	ok("сундук поставлен", MachineBase.place_machine("Chest", ccell), str(ccell))
	var chest = World.machines.get(ccell) as Chest
	if chest == null:
		finish()
		return
	var citem: int = MachineBase.machine_item_id("Chest")
	_stand(ccell)
	player.inv.selected = _empty_slot()
	aim(World.cell_to_world(ccell))
	await wait(0.4)
	ok("у пустого сундука — подсказка разбора",
			hud.hint_text == "%s: %s" % [HUD.HINT_DISMANTLE, DB.item_name(citem)],
			"«%s»" % hud.hint_text)
	hold(KEY_E)
	await wait(1.3)
	release(KEY_E)
	await wait(0.2)
	ok("пустой сундук разобран", not World.machines.has(ccell))
	ok("сундук вернулся в рюкзак", player.inv.count_of(citem) == 1,
			"%d" % player.inv.count_of(citem))

	# Полный сундук: E открывает панель, разбора нет.
	var fcell: Vector2i = Vector2i(bx - 25, row)
	ok("второй сундук поставлен", MachineBase.place_machine("Chest", fcell), str(fcell))
	var full = World.machines.get(fcell) as Chest
	if full == null:
		finish()
		return
	full.receive_item(IDs.I.STONE, 2)
	_stand(fcell)
	player.inv.selected = _empty_slot()
	aim(World.cell_to_world(fcell))
	await wait(0.4)
	ok("у полного сундука — подсказка «открыть», а не разбор",
			hud.hint_text == HUD.HINT_CHEST, "«%s»" % hud.hint_text)
	hold(KEY_E)
	var opened: bool = await wait_until(func() -> bool: return UI.panel.visible, 2.0)
	release(KEY_E)
	await wait(0.2)
	ok("полный сундук открылся по E", opened)
	ok("полный сундук не разобрался", World.machines.has(fcell))
	if UI.panel.visible:
		UI.panel.close()
	await wait(0.2)

	# ---- Горелка: короткое E — рубильник, удержание — разбор -------------------
	var gcell: Vector2i = Vector2i(bx - 22, row)
	ok("горелка поставлена", MachineBase.place_machine("Burner", gcell), str(gcell))
	var gen = World.machines.get(gcell)
	if gen == null:
		finish()
		return
	var gitem: int = MachineBase.machine_item_id("Burner")
	_stand(gcell)
	player.inv.selected = _empty_slot()
	aim(World.cell_to_world(gcell))
	await wait(0.4)
	ok("у горелки — подсказка рубильника с хвостом про разбор",
			hud.hint_text == HUD.HINT_BURNER_SWITCH + HUD.HINT_DISMANTLE_TAIL, "«%s»" % hud.hint_text)
	hold(KEY_E)
	await wait(0.3)
	release(KEY_E)
	await wait(0.2)
	ok("короткое E у горелки — рубильник, а не разбор",
			not gen.enabled and World.machines.has(gcell), "enabled=%s" % str(gen.enabled))
	player.inv.selected = _empty_slot()
	hold(KEY_E)
	await wait(1.3)
	release(KEY_E)
	await wait(0.2)
	ok("горелка разобрана удержанием", not World.machines.has(gcell))
	ok("горелка вернулась в рюкзак", player.inv.count_of(gitem) == 1,
			"%d" % player.inv.count_of(gitem))
	finish()


## Ровная площадка: пол — сталь, над ним пусто.
func _platform(row: int, x0: int, x1: int) -> void:
	for x in range(x0, x1 + 1):
		World.set_tile(x, row + 1, IDs.T.STEEL)
		World.set_tile(x, row, IDs.T.AIR)
		World.set_tile(x, row - 1, IDs.T.AIR)


## Встать справа от постройки (в 16 px от неё) — на пол площадки.
func _stand(cell: Vector2i) -> void:
	player.global_position = Vector2(float((cell.x + 1) * World.TILE) + 8.0,
			float((cell.y + 1) * World.TILE) - 11.0)
	player.vel = Vector2.ZERO


## Что E сделает с целью под курсором (пусто — ничего).
func _target_kind() -> String:
	return String(player.interact_target().get("kind", ""))


## Рамка HUD вокруг точки мира. Клетка в мировых px: экранный кэш в _process
## отстаёт от сглаженной камеры (#211).
func _mark_on(hud: HUD, world_pos: Vector2) -> bool:
	return hud.mark_on_world(world_pos)


## Пустой слот хотбара (рука должна быть пустой — иначе E грузит, а не разбирает).
func _empty_slot() -> int:
	for i in 10:
		if player.inv.get_slot(i).is_empty():
			return i
	player.inv.slots[9] = ItemStack.new()
	return 9
