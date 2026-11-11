extends ScenarioBase
## Крафт понятен без README (#69): подсказка рецепта и обратная связь клика.
##
## Мышь — настоящими событиями в _gui_input панели, как в inventory_transfer.
## 1. Наведение на рецепт с нехваткой: подсказка называет вход словами,
##    «есть 0 / нужно 2» и причину «Не хватает: …».
## 2. Клик по нему: ничего не скрафчено, строка обратной связи называет нехватку,
##    строка рецепта вспыхивает красным.
## 3. Рецепт без чертежа в списке не рисуется (#169).
## Станков больше нет (#170): вкладка одна, «Крафт».
## 4. Успешный ручной крафт: «Скрафчено: …», вспышка зелёная.

var panel: InventoryPanel = null


func run() -> void:
	player.invuln = 1.0e9
	panel = UI.panel
	stand_in_corridor(12)
	await wait(0.3)
	player.inv.remove_id(IDs.I.COPPER_ORE, player.inv.count_of(IDs.I.COPPER_ORE))
	player.inv.mark_seen(IDs.I.COPPER_ORE)
	var hand: Array = DB.recipes_for("hand")
	var copper: Dictionary = _find(hand, IDs.I.COPPER_INGOT)
	var burner: Dictionary = _find(hand, IDs.I.BURNER)
	ok("рецепты медного слитка и горелки есть", not copper.is_empty() and not burner.is_empty())
	if copper.is_empty() or burner.is_empty():
		finish()
		return

	_press_key(KEY_I)
	await wait(0.3)
	ok("панель открыта", panel.visible)

	# ---- 1. Подсказка рецепта с нехваткой ----------------------------------------
	# Строка — в списке панели, не в полном DB: закрытые чертежи там не рисуются.
	var row: Rect2 = _row_of(panel._recipes("hand"), copper)
	await _move(row.position + Vector2(60, 12))
	var tip: String = _joined(panel._tooltip_for(panel._hover_target()))
	ok("подсказка называет вход словами и «есть/нужно»", tip.contains("Медная руда — есть 0 / нужно 2"), tip)
	ok("подсказка называет выход и станцию", tip.contains("Медный слиток") and tip.contains("Станция: руками"), tip)
	ok("подсказка объясняет нехватку", tip.contains("Не хватает: Медная руда (ещё 2)"), tip)

	# ---- 2. Клик с нехваткой --------------------------------------------------------
	var ingots: int = player.inv.count_of(IDs.I.COPPER_INGOT)
	await _click(row.position + Vector2(60, 12))
	ok("с нехваткой ничего не скрафчено", player.inv.count_of(IDs.I.COPPER_INGOT) == ingots)
	ok("обратная связь: чего не хватает", panel.last_feedback.begins_with("Не хватает")
			and panel.last_feedback.contains("Медная руда"), panel.last_feedback)
	ok("строка рецепта вспыхнула красным", not panel._flash_ok and panel._flash_rec == copper)

	# ---- 3. Рецепт без чертежа скрыт; горелка открыта сразу -------------------------
	var wall: Dictionary = _find(DB.recipes, IDs.I.STEEL_WALL)
	ok("стальная стена без чертежа не в списке панели", wall.is_empty() or not panel._recipes("hand").has(wall))
	ok("вкладка одна — «Крафт»", panel.TABS.size() == 1 and String(panel.TABS[0]) == "Крафт")
	for id in burner["in"].keys():
		player.inv.add(int(id), int(burner["in"][id]))
	panel._check_cache()
	var arow: Rect2 = _row_of(panel._recipes("hand"), burner)
	await _click(arow.position + Vector2(60, 12))
	ok("горелка скрафчена без дерева технологий", player.inv.count_of(IDs.I.BURNER) == 1)
	panel.scroll = 0

	# ---- 4. Успешный ручной крафт --------------------------------------------------
	player.inv.add(IDs.I.COPPER_ORE, 4)
	await _click(_row_of(panel._recipes("hand"), copper).position + Vector2(60, 12))
	ok("слиток скрафчен кликом мыши", player.inv.count_of(IDs.I.COPPER_INGOT) == ingots + 1)
	ok("обратная связь «Скрафчено: Медный слиток»", panel.last_feedback.begins_with("Скрафчено: Медный слиток"),
			panel.last_feedback)
	ok("строка рецепта вспыхнула зелёным", panel._flash_ok and panel._flash_rec == copper)

	_press_key(KEY_I)
	await wait(0.3)
	ok("панель закрыта", not UI.blocking())
	finish()


func _find(list: Array, out_id: int) -> Dictionary:
	for r in list:
		if int(r["out"]) == out_id:
			return r
	return {}


## Строка рецепта rec: список листается так, чтобы она была видна.
func _row_of(list: Array, rec: Dictionary) -> Rect2:
	var idx: int = list.find(rec)
	panel.scroll = mini(idx, panel._max_scroll())
	return panel._recipe_row_rect(idx - panel.scroll)


func _move(pos: Vector2) -> void:
	var mv: InputEventMouseMotion = InputEventMouseMotion.new()
	mv.position = pos
	mv.global_position = pos
	panel._gui_input(mv)
	await wait(0.08)


func _click(pos: Vector2) -> void:
	await _move(pos)
	for pressed in [true, false]:
		var ev: InputEventMouseButton = InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		panel._gui_input(ev)
	await wait(0.1)


func _press_key(code: int) -> void:
	var ev: InputEventKey = InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)


func _joined(lines: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for l in lines:
		parts.append(String(l["t"]))
	return " | ".join(parts)
