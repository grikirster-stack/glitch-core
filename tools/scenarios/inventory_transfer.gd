extends ScenarioBase
## Сундук ↔ инвентарь (#69) настоящими кликами мыши.
##
## Клики — настоящие события InputEventMouseButton/Motion в обработчик ввода
## панели (_gui_input), с позицией в координатах экрана, как их отдаёт вьюпорт.
## В headless вьюпорт мышь до контролов не доводит (ни parse_input_event,
## ни push_input), поэтому событие подаётся прямо в _gui_input — дальше путь
## тот же, что у человека. Раньше _gui_input вычитал из позиции начало панели,
## и мышью нельзя было взять ничего: попадание уезжало на ~(230, 125) px.
## Прямой вызов _click() в старых сценариях этого не ловил.
##
## Проверки: тайник открывается по E и подписан именем руины; ЛКМ берёт стопку
## «в руку»; Shift+ЛКМ перекладывает стопку в обе стороны; «Забрать всё»
## и «Сложить всё»; Shift+ЛКМ без сундука — хотбар ⇄ рюкзак; предмет в руке
## не теряется при закрытии панели — ни в обычном случае, ни при полном инвентаре.

var panel: InventoryPanel = null
var ch: Chest = null


func run() -> void:
	player.invuln = 1.0e9
	panel = UI.panel
	var caches: Array = World.ruin_caches
	ok("есть тайник руины", not caches.is_empty())
	if caches.is_empty():
		finish()
		return
	var cache: Dictionary = caches[0]
	ch = cache["chest"]
	for i in Chest.CAP:
		ch.slots[i] = ItemStack.new()
	ch.slots[0] = ItemStack.new(IDs.I.SCRAP, 9)
	ch.slots[1] = ItemStack.new(IDs.I.STONE, 5)
	ch.slots[2] = ItemStack.new(IDs.I.GLASS, 3)
	# Стартовый набор несёт тот же хлам, камень и стекло-нет, но хлам и камень — да.
	player.inv.remove_id(IDs.I.SCRAP, player.inv.count_of(IDs.I.SCRAP))
	player.inv.remove_id(IDs.I.STONE, player.inv.count_of(IDs.I.STONE))

	# ---- Открыть тайник, как человек: держать E --------------------------------
	place_near(World.cell_to_world(cache["cell"]), [Vector2(0, -4), Vector2(16, -4), Vector2(-16, -4),
			Vector2(0, -20), Vector2(16, -20), Vector2(-16, -20)])
	hold(KEY_E)
	var opened: bool = await wait_until(func() -> bool: return panel.visible and panel.chest == ch, 3.0)
	release(KEY_E)
	clear_input()
	ok("тайник открыт по E", opened)
	if not opened:
		finish()
		return
	await wait(0.2)
	ok("в заголовке имя тайника", panel._chest_title.contains(String(cache["name"])),
			"«%s»" % panel._chest_title)

	# ---- ЛКМ: стопка «в руку», потом в ячейку инвентаря --------------------------
	await _click(panel._chest_slot_rect(0).get_center(), MOUSE_BUTTON_LEFT)
	ok("ЛКМ мышью по ячейке сундука берёт стопку в руку",
			panel.held.id == IDs.I.SCRAP and panel.held.count == 9 and ch.slots[0].is_empty(),
			str(panel.held))
	await _move(panel._inv_slot_rect(20).get_center() + Vector2(3, 3))
	ok("предмет в руке рисуется у курсора", panel.mouse_pos.distance_to(panel._inv_slot_rect(20).get_center()) < 8.0)
	await _click(panel._inv_slot_rect(20).get_center(), MOUSE_BUTTON_LEFT)
	ok("ЛКМ кладёт стопку в ячейку инвентаря",
			panel.held.is_empty() and player.inv.slots[20].id == IDs.I.SCRAP and player.inv.slots[20].count == 9)

	# ---- Shift+ЛКМ в обе стороны --------------------------------------------------
	var tip: Array = panel._tooltip_for(panel._hover_target())
	ok("подсказка по наведению на стопку называет Shift+ЛКМ", _joined(tip).contains("Shift+ЛКМ"), _joined(tip))
	await _click(panel._inv_slot_rect(20).get_center(), MOUSE_BUTTON_LEFT, true)
	ok("Shift+ЛКМ: инвентарь → сундук", player.inv.count_of(IDs.I.SCRAP) == 0 and _chest_count(IDs.I.SCRAP) == 9,
			"в инвентаре %d, в сундуке %d" % [player.inv.count_of(IDs.I.SCRAP), _chest_count(IDs.I.SCRAP)])
	ok("после Shift+ЛКМ рука пуста", panel.held.is_empty())
	await _click(panel._chest_slot_rect(1).get_center(), MOUSE_BUTTON_LEFT, true)
	ok("Shift+ЛКМ: сундук → инвентарь", player.inv.count_of(IDs.I.STONE) == 5 and _chest_count(IDs.I.STONE) == 0,
			"в инвентаре %d, в сундуке %d" % [player.inv.count_of(IDs.I.STONE), _chest_count(IDs.I.STONE)])
	ok("обратная связь о перекладке", panel.last_feedback.contains("Камень"), panel.last_feedback)

	# ---- «Забрать всё» и «Сложить всё» -------------------------------------------
	await _click(panel._take_all_rect().get_center(), MOUSE_BUTTON_LEFT)
	ok("«Забрать всё» опустошает сундук", _chest_total() == 0, "в сундуке %d" % _chest_total())
	ok("всё забранное — в инвентаре", player.inv.count_of(IDs.I.SCRAP) == 9 and player.inv.count_of(IDs.I.GLASS) == 3)
	var lamps: int = player.inv.count_of(IDs.I.LAMP)
	# Хлам — в рюкзак (ячейка 15), чтобы «Сложить всё» было что складывать.
	var si: int = _slot_of(IDs.I.SCRAP)
	await _click(panel._inv_slot_rect(si).get_center(), MOUSE_BUTTON_LEFT)
	await _click(panel._inv_slot_rect(15).get_center(), MOUSE_BUTTON_LEFT)
	ok("хлам переложен в рюкзак", player.inv.slots[15].id == IDs.I.SCRAP)
	await _click(panel._put_all_rect().get_center(), MOUSE_BUTTON_LEFT)
	ok("«Сложить всё» кладёт рюкзак в сундук", _chest_count(IDs.I.SCRAP) == 9 and player.inv.slots[15].is_empty())
	ok("«Сложить всё» не трогает хотбар", player.inv.count_of(IDs.I.LAMP) == lamps and player.inv.count_of(IDs.I.GLASS) == 3)

	# ---- Предмет в руке не теряется при закрытии --------------------------------
	var scrap_slot: int = _chest_slot_of(IDs.I.SCRAP)
	await _click(panel._chest_slot_rect(scrap_slot).get_center(), MOUSE_BUTTON_LEFT)
	ok("хлам снова в руке", panel.held.id == IDs.I.SCRAP and panel.held.count == 9)
	_press_key(KEY_I)
	await wait(0.3)
	ok("I закрыл панель", not panel.visible)
	ok("предмет из руки вернулся в инвентарь", player.inv.count_of(IDs.I.SCRAP) == 9 and panel.held.is_empty(),
			"хлама %d" % player.inv.count_of(IDs.I.SCRAP))

	# Инвентарь забит: предмет из руки возвращается в сундук.
	player.inv.remove_id(IDs.I.GLASS, player.inv.count_of(IDs.I.GLASS))
	ch.slots[0] = ItemStack.new(IDs.I.GLASS, 3)
	UI.open_chest(ch)
	await wait(0.2)
	await _click(panel._chest_slot_rect(0).get_center(), MOUSE_BUTTON_LEFT)
	ok("стекло из сундука в руке", panel.held.id == IDs.I.GLASS and panel.held.count == 3, str(panel.held))
	for i in player.inv.size:
		if player.inv.slots[i].is_empty():
			player.inv.slots[i] = ItemStack.new(IDs.I.SAND, DB.item_max_stack(IDs.I.SAND))
	ok("инвентарь полон", player.inv.is_full())
	_press_key(KEY_ESCAPE)
	await wait(0.3)
	ok("Esc закрыл панель", not panel.visible)
	ok("при полном инвентаре предмет из руки вернулся в сундук",
			_chest_count(IDs.I.GLASS) == 3 and player.inv.count_of(IDs.I.GLASS) == 0 and panel.held.is_empty(),
			"стекла в сундуке %d" % _chest_count(IDs.I.GLASS))

	# ---- Без сундука: Shift+ЛКМ — хотбар ⇄ рюкзак ---------------------------------
	for i in player.inv.size:
		if player.inv.slots[i].id == IDs.I.SAND:
			player.inv.slots[i] = ItemStack.new()
	_press_key(KEY_I)
	await wait(0.3)
	ok("инвентарь открыт без сундука", panel.visible and panel.chest == null)
	var lamp_slot: int = _slot_of(IDs.I.LAMP)
	await _click(panel._inv_slot_rect(lamp_slot).get_center(), MOUSE_BUTTON_LEFT, true)
	var now_slot: int = _slot_of(IDs.I.LAMP)
	ok("Shift+ЛКМ уносит стопку из хотбара в рюкзак", lamp_slot < player.inv.hotbar_size and now_slot >= player.inv.hotbar_size,
			"ячейка %d → %d" % [lamp_slot, now_slot])
	_press_key(KEY_I)
	await wait(0.3)
	ok("панель закрыта", not UI.blocking())
	finish()


# ------------------------------------------------------------------ МЫШЬ

## Движение мыши событием — как у человека.
func _move(pos: Vector2) -> void:
	var mv: InputEventMouseMotion = InputEventMouseMotion.new()
	mv.position = pos
	mv.global_position = pos
	panel._gui_input(mv)
	await wait(0.08)


## Клик кнопкой button в точке pos (координаты экрана = панели), shift — с Shift.
func _click(pos: Vector2, button: int, shift: bool = false) -> void:
	await _move(pos)
	for pressed in [true, false]:
		var ev: InputEventMouseButton = InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		ev.shift_pressed = shift
		panel._gui_input(ev)
	await wait(0.1)


func _press_key(code: int) -> void:
	var ev: InputEventKey = InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)


# ------------------------------------------------------------------ СЧЁТ

func _chest_count(id: int) -> int:
	var n: int = 0
	for s in ch.slots:
		if s.id == id:
			n += s.count
	return n


func _chest_total() -> int:
	var n: int = 0
	for s in ch.slots:
		n += s.count
	return n


func _chest_slot_of(id: int) -> int:
	for i in Chest.CAP:
		if ch.slots[i].id == id:
			return i
	return 0


func _slot_of(id: int) -> int:
	for i in player.inv.size:
		if player.inv.slots[i].id == id:
			return i
	return -1


func _joined(lines: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for l in lines:
		parts.append(String(l["t"]))
	return " | ".join(parts)
