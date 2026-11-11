extends ScenarioBase
## Крафт понятен без README (#69): подсказка рецепта и обратная связь клика.
##
## Мышь — настоящими событиями в _gui_input панели, как в inventory_transfer.
## 1. Наведение на рецепт с нехваткой: подсказка называет вход словами,
##    «есть 0 / нужно 2» и причину «Не хватает: …».
## 2. Клик по нему: ничего не скрафчено, строка обратной связи называет нехватку,
##    строка рецепта вспыхивает красным.
## 3. Рецепт без чертежа в списке не рисуется (#169).
## 4. Вкладка плавильни без плавильни рядом: причина — станок.
## 5. Успешный ручной крафт: «Скрафчено: …», вспышка зелёная.
## 6. Плавильня рядом: «Загружено в плавильню», сырьё ушло в станок.

var panel: InventoryPanel = null


func run() -> void:
	player.invuln = 1.0e9
	panel = UI.panel
	stand_in_corridor(12)
	await wait(0.3)
	player.inv.remove_id(IDs.I.COPPER_ORE, player.inv.count_of(IDs.I.COPPER_ORE))
	var hand: Array = DB.recipes_for("hand")
	var copper: Dictionary = _find(hand, IDs.I.COPPER_INGOT)
	var asm: Dictionary = _find(hand, IDs.I.ASSEMBLER)
	ok("рецепты медного слитка и сборщика есть", not copper.is_empty() and not asm.is_empty())
	if copper.is_empty() or asm.is_empty():
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

	# ---- 3. Рецепт без чертежа скрыт; сборщик открыт сразу -------------------------
	var wall: Dictionary = _find(DB.recipes_for("smelter"), IDs.I.STEEL_WALL)
	ok("стальная стена без чертежа не в списке панели", wall.is_empty() or not panel._recipes("smelter").has(wall))
	for id in asm["in"].keys():
		player.inv.add(int(id), int(asm["in"][id]))
	var arow: Rect2 = _row_of(panel._recipes("hand"), asm)
	await _click(arow.position + Vector2(60, 12))
	ok("сборщик скрафчен без дерева технологий", player.inv.count_of(IDs.I.ASSEMBLER) == 1)
	panel.scroll = 0

	# ---- 4. Плавильня: станка рядом нет --------------------------------------------
	await _click(panel._tab_rect(1).get_center())
	ok("вкладка «Плавильня» выбрана кликом", panel.station_tab == 1)
	var smelt: Array = DB.recipes_for("smelter")
	var iron: Dictionary = _find(smelt, IDs.I.IRON_INGOT)
	player.inv.add(IDs.I.IRON_ORE, 2)
	await _click(_row_of(panel._recipes("smelter"), iron).position + Vector2(60, 12))
	ok("без плавильни рядом руда не ушла", player.inv.count_of(IDs.I.IRON_ORE) == 2)
	ok("причина: нужна плавильня рядом", panel.last_feedback.to_lower().contains("плавильн"), panel.last_feedback)

	# ---- 5. Успешный ручной крафт --------------------------------------------------
	await _click(panel._tab_rect(0).get_center())
	player.inv.add(IDs.I.COPPER_ORE, 4)
	await _click(_row_of(panel._recipes("hand"), copper).position + Vector2(60, 12))
	ok("слиток скрафчен кликом мыши", player.inv.count_of(IDs.I.COPPER_INGOT) == ingots + 1)
	ok("обратная связь «Скрафчено: Медный слиток»", panel.last_feedback.begins_with("Скрафчено: Медный слиток"),
			panel.last_feedback)
	ok("строка рецепта вспыхнула зелёным", panel._flash_ok and panel._flash_rec == copper)

	# ---- 6. Плавильня рядом: загрузка ----------------------------------------------
	var pc: Vector2i = World.world_to_cell(player.global_position)
	var sc: Vector2i = pc + Vector2i(2, 0)
	World.set_tile(sc.x, sc.y, IDs.T.AIR)
	ok("плавильня поставлена рядом", MachineBase.place_machine("Smelter", sc))
	var sm: Smelter = World.machines.get(sc)
	await _click(panel._tab_rect(1).get_center())
	await _click(_row_of(panel._recipes("smelter"), iron).position + Vector2(60, 12))
	ok("руда ушла в плавильню", sm != null and player.inv.count_of(IDs.I.IRON_ORE) == 1
			and int(sm.stock.get(IDs.I.IRON_ORE, 0)) >= 1,
			"руды в инвентаре %d, в станке %s" % [player.inv.count_of(IDs.I.IRON_ORE), str(sm.stock) if sm else "—"])
	ok("обратная связь «Загружено в плавильню»", panel.last_feedback.begins_with("Загружено в плавильню"),
			panel.last_feedback)

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
