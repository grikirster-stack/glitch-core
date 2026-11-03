extends ScenarioBase
## Сенсорное управление (#81): касания InputEventScreenTouch/ScreenDrag идут
## настоящим путём — Input.parse_input_event, вместе с эмуляцией мыши из касаний
## (как на телефоне), — и доходят до TouchControls, а оттуда через шов
## Player.touch_input до героя. Шов сценария (test_input) здесь пуст.
##
## Проверяем: без сенсорного экрана и --touch управление выключено; джойстик
## двигает героя, а эмулированный «клик» под джойстиком не копает; тап по кнопке
## прыжка (нажатие и отпускание в одном кадре) прыгает; второй палец копает тайл,
## пока первый держит джойстик (мультитач); тап по хотбару выбирает слот; долгий тап
## по пустой клетке ставит блок, короткий — нет; режим «строить» ставит коротким
## тапом; кнопки I и J открывают и закрывают окна, тап по миру при этом не копает;
## кнопка «II» открывает паузу (#119).
## В одиночной игре кнопки переклички G нет (#135; в сети её проверяет mp_doppel).

var tc: TouchControls = null


func run() -> void:
	clear_input()
	tc = get_tree().get_first_node_in_group("touch_controls")
	ok("сенсорное управление создано", tc != null)
	if tc == null:
		finish()
		return
	ok("без сенсорного экрана и --touch выключено (ПК не меняется)",
			not tc.enabled and not tc.visible and player.touch_input.is_empty())
	tc.set_enabled(true)
	ok("включается по запросу: шов игрока получил клавиши", tc.enabled and player.touch_input.has("keys"))
	await wait(0.1)
	ok("в одиночной игре кнопки G (перекличка) нет: не жмётся, колонка под миникартой на месте",
			not tc.rollcall_shown() and tc.control_at(tc.btn_center["g"]) != "g"
			and not bool(player.touch_input["keys"].get(KEY_G, false))
			and is_equal_approx(tc.btn_center["inv"].y, 126.0 + float(tc.btn_radius["inv"])),
			"под пальцем «%s», I на y=%.0f" % [tc.control_at(tc.btn_center["g"]), tc.btn_center["inv"].y])

	await _mining_with_stick_held()
	await _walk_and_jump()
	await _build_by_long_tap()
	await _windows_by_buttons()

	_lift_all()
	await wait(0.1)
	tc.set_enabled(false)
	ok("после сценария мышь отпущена и шов пуст",
			not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and player.touch_input.is_empty())
	finish()


# ------------------------------------------------------------------ ШАГИ

## Палец 0 — джойстик в центре (он же эмулирует мышь), палец 1 копает тайл.
func _mining_with_stick_held() -> void:
	await wait(0.4)
	_settle_camera()
	await wait(0.2)
	var cell: Vector2i = find_mineable()
	ok("найден тайл для копки тапом", cell.x >= 0, str(cell))
	if cell.x < 0:
		return
	var before: int = World.get_tile_v(cell)
	var x0: float = player.global_position.x
	_touch(0, tc.stick_center, true)
	await wait(0.3)
	ok("эмулированный клик под джойстиком не копает мир",
			Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and player.mining_progress <= 0.0,
			"ЛКМ эмулирована: %s, прогресс %.2f" % [Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),
			player.mining_progress])
	_touch(1, _screen(World.cell_to_world(cell)), true)
	await wait(0.35)
	ok("второй палец копает, пока первый на джойстике", player.mining_cell == cell
			and player.mining_progress > 0.0, "%s, прогресс %.2f" % [str(player.mining_cell), player.mining_progress])
	var broke: bool = await wait_until(func() -> bool: return World.get_tile_v(cell) != before, 6.0)
	ok("удержание тапа докапывает тайл", broke, DB.tile_name(before))
	ok("герой при этом стоял (джойстик в мёртвой зоне)", absf(player.global_position.x - x0) < 4.0,
			"%.1f px" % (player.global_position.x - x0))
	await wait(0.6)
	ok("докопал и держит палец — на месте тайла ничего не ставится",
			World.get_tile_v(cell) == IDs.T.AIR, DB.tile_name(World.get_tile_v(cell)))
	# Оба пальца сразу: джойстик вправо и палец на мире — шов видит и то и другое.
	_drag(0, tc.stick_center + Vector2(tc.stick_radius * 0.9, 0.0))
	await wait(0.1)
	var keys: Dictionary = player.touch_input.get("keys", {})
	var mb: Dictionary = player.touch_input.get("mouse_buttons", {})
	ok("мультитач: идти и копать одновременно", bool(keys.get(KEY_D, false))
			and bool(mb.get(MOUSE_BUTTON_LEFT, false)))
	_touch(1, _screen(World.cell_to_world(cell)), false)
	_touch(0, tc.stick_center, false)
	await wait(0.2)
	ok("пальцы сняты — мышь снова своя", not player.touch_input.has("mouse_buttons"))


## Джойстик вправо — идёт; тап по кнопке прыжка — прыгает; джойстик вверх — прыгает.
func _walk_and_jump() -> void:
	stand_in_corridor(2)
	_settle_camera()
	await wait(0.6)
	var x0: float = player.global_position.x
	_touch(0, tc.stick_center, true)
	_drag(0, tc.stick_center + Vector2(tc.stick_radius * 0.9, 0.0))
	await wait(0.6)
	_touch(0, tc.stick_center, false)
	var dx: float = player.global_position.x - x0
	ok("джойстик вправо двигает героя", dx > 24.0, "%.1f px" % dx)
	await wait(0.4)

	await wait_until(func() -> bool: return player.on_ground, 1.5)
	var y0: float = player.global_position.y
	# Нажатие и отпускание в одном кадре — короткий тап не теряется.
	_touch(2, tc.btn_center["jump"], true)
	_touch(2, tc.btn_center["jump"], false)
	var rose: bool = await wait_until(func() -> bool: return player.global_position.y < y0 - 8.0, 0.6)
	ok("короткий тап по кнопке прыжка — прыжок", rose, "%.1f px" % (y0 - player.global_position.y))
	await wait_until(func() -> bool: return player.on_ground, 2.0)
	await wait(0.2)
	y0 = player.global_position.y
	_touch(0, tc.stick_center, true)
	_drag(0, tc.stick_center + Vector2(0.0, -tc.stick_radius))
	rose = await wait_until(func() -> bool: return player.global_position.y < y0 - 8.0, 0.6)
	_touch(0, tc.stick_center, false)
	ok("джойстик вверх — прыжок", rose, "%.1f px" % (y0 - player.global_position.y))
	await wait_until(func() -> bool: return player.on_ground, 2.0)


## Тап по хотбару выбирает слот; долгий тап ставит блок, короткий — нет;
## режим «строить» ставит коротким тапом.
func _build_by_long_tap() -> void:
	var base: int = stand_in_corridor(3)
	_settle_camera()
	await wait(0.6)
	player.inv.slots[5] = ItemStack.new(IDs.I.STONE, 10)
	_tap(3, UI.hud.hotbar_slot_rect(5).get_center())
	await wait(0.1)
	ok("тап по хотбару выбирает слот", player.inv.selected == 5, str(player.inv.selected))

	var pc: Vector2i = World.world_to_cell(player.global_position)
	var a: Vector2i = Vector2i(pc.x + 2, base - 1)
	var b: Vector2i = Vector2i(pc.x + 3, base - 1)
	ok("рядом пустые клетки под постройку", World.get_tile_v(a) == IDs.T.AIR
			and World.get_tile_v(b) == IDs.T.AIR, "%s %s" % [str(a), str(b)])

	# Короткий тап по пустой клетке — не постройка.
	_touch(1, _screen(World.cell_to_world(a)), true)
	await wait(0.15)
	_touch(1, _screen(World.cell_to_world(a)), false)
	await wait(0.3)
	ok("короткий тап по пустой клетке ничего не ставит", World.get_tile_v(a) == IDs.T.AIR)

	# Долгий тап (≥ 0.4 с) — ставит блок из хотбара.
	var stones: int = player.inv.slots[5].count
	_touch(1, _screen(World.cell_to_world(a)), true)
	var placed: bool = await wait_until(func() -> bool: return World.get_tile_v(a) == IDs.T.STONE, 1.5)
	_touch(1, _screen(World.cell_to_world(a)), false)
	ok("долгий тап ставит блок из хотбара", placed and player.inv.slots[5].count == stones - 1,
			"камней %d → %d" % [stones, player.inv.slots[5].count])

	# Режим «строить»: короткий тап — сразу постройка.
	_tap(2, tc.btn_center["build"])
	await wait(0.1)
	ok("кнопка «строить» включает режим", tc.build_mode)
	_touch(1, _screen(World.cell_to_world(b)), true)
	placed = await wait_until(func() -> bool: return World.get_tile_v(b) == IDs.T.STONE, 0.4)
	_touch(1, _screen(World.cell_to_world(b)), false)
	ok("в режиме «строить» короткий тап ставит блок", placed)
	_tap(2, tc.btn_center["build"])
	await wait(0.1)
	ok("повторный тап выключает режим", not tc.build_mode)


## I и J открывают и закрывают окна; при открытом окне тап по миру не копает.
func _windows_by_buttons() -> void:
	_tap(2, tc.btn_center["inv"])
	await wait(0.2)
	ok("кнопка I открывает инвентарь", UI.panel.visible)
	# Палец листает рецепты. Событие — прямо в _gui_input панели: в headless
	# вьюпорт касания до контролов не доводит (как и мышь, см. inventory_transfer).
	var panel: InventoryPanel = UI.panel
	# Тап по ячейке — эмулированный из касания клик ЛКМ: стопка в руку и обратно.
	var slot_pos: Vector2 = panel._inv_slot_rect(0).get_center()
	var id0: int = player.inv.slots[0].id
	_panel_tap(panel, slot_pos)
	var took: bool = panel.held.id == id0 and player.inv.slots[0].is_empty()
	_panel_tap(panel, slot_pos)
	ok("тап по ячейке инвентаря: стопка в руку и обратно", took and panel.held.is_empty()
			and player.inv.slots[0].id == id0, DB.item_name(id0))
	if panel._max_scroll() >= 2:
		var s0: int = panel.scroll
		_panel_drag(panel, -InventoryPanel.RECIPE_H * 2.2)
		var s1: int = panel.scroll
		_panel_drag(panel, InventoryPanel.RECIPE_H * 2.2)
		ok("палец листает рецепты вниз и обратно", s1 == s0 + 2 and panel.scroll == s0,
				"%d → %d → %d" % [s0, s1, panel.scroll])
	var cell: Vector2i = find_mineable()
	if cell.x >= 0:
		_touch(1, _screen(World.cell_to_world(cell)), true)
		await wait(0.4)
		ok("при открытом инвентаре тап по миру не копает", player.mining_progress <= 0.0,
				"прогресс %.2f" % player.mining_progress)
		_touch(1, _screen(World.cell_to_world(cell)), false)
	ok("при открытом окне кнопка I на месте, джойстик спрятан",
			tc.control_at(tc.btn_center["inv"]) == "inv" and tc.control_at(tc.stick_center) == "")
	_tap(2, tc.btn_center["inv"])
	await wait(0.2)
	ok("повторный тап по I закрывает инвентарь", not UI.panel.visible)
	_tap(2, tc.btn_center["journal"])
	await wait(0.2)
	ok("кнопка J открывает журнал", UI.journal.visible)
	_tap(2, tc.btn_center["journal"])
	await wait(0.2)
	ok("повторный тап по J закрывает журнал", not UI.journal.visible and not UI.blocking())
	# Пауза (#119): ESC на телефоне нет — кнопка «II» рядом с J; в паузе кнопок нет.
	_tap(2, tc.btn_center["pause"])
	await get_tree().process_frame
	await get_tree().process_frame
	ok("кнопка «II» открывает паузу (дерево стоит), кнопок и джойстика нет", UI.pause.visible
			and get_tree().paused and tc.control_at(tc.btn_center["inv"]) == ""
			and tc.control_at(tc.btn_center["pause"]) == "" and tc.control_at(tc.stick_center) == "")
	UI.pause.continue_button.pressed.emit()
	ok("«Продолжить» — пауза закрыта, кнопка «II» снова жмётся", not UI.pause.visible
			and not get_tree().paused and tc.control_at(tc.btn_center["pause"]) == "pause")


# ------------------------------------------------------------------ КАСАНИЯ

var _down: Dictionary = {}   ## индекс пальца -> последняя точка


## Экранная точка (координаты вьюпорта) мировой позиции.
func _screen(world: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world


## Вьюпорт → окно: события Input.parse_input_event приходят в координатах окна.
func _win(pos: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * pos


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e: InputEventScreenTouch = InputEventScreenTouch.new()
	e.index = index
	e.position = _win(pos)
	e.pressed = pressed
	Input.parse_input_event(e)
	if pressed:
		_down[index] = pos
	else:
		_down.erase(index)


func _drag(index: int, pos: Vector2) -> void:
	var e: InputEventScreenDrag = InputEventScreenDrag.new()
	e.index = index
	e.position = _win(pos)
	e.relative = _win(pos) - _win(Vector2(_down.get(index, pos)))
	Input.parse_input_event(e)
	_down[index] = pos


## Тап по панели так, как его видит панель на телефоне: ЛКМ с device эмуляции.
func _panel_tap(panel: InventoryPanel, pos: Vector2) -> void:
	for pressed in [true, false]:
		var e: InputEventMouseButton = InputEventMouseButton.new()
		e.device = InputEvent.DEVICE_ID_EMULATION
		e.button_index = MOUSE_BUTTON_LEFT
		e.position = pos
		e.pressed = pressed
		panel._gui_input(e)


func _panel_drag(panel: InventoryPanel, dy: float) -> void:
	var e: InputEventScreenDrag = InputEventScreenDrag.new()
	e.position = panel._list_rect().get_center()
	e.relative = Vector2(0.0, dy)
	panel._gui_input(e)


## Короткий тап: нажатие и отпускание подряд.
func _tap(index: int, pos: Vector2) -> void:
	_touch(index, pos, true)
	_touch(index, pos, false)


func _lift_all() -> void:
	for i in _down.keys():
		_touch(int(i), Vector2(_down[i]), false)


## Камера догоняет героя плавно; для тапов по миру ставим её сразу на место.
func _settle_camera() -> void:
	player.camera.reset_smoothing()
