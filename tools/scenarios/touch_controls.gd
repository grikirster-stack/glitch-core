extends ScenarioBase
## Сенсорное управление (#81): касания InputEventScreenTouch/ScreenDrag идут
## настоящим путём — Input.parse_input_event, вместе с эмуляцией мыши из касаний
## (как на телефоне), — и доходят до TouchControls, а оттуда через шов
## Player.touch_input до героя. Шов сценария (test_input) здесь пуст.
##
## Проверяем: без сенсорного экрана и --touch управление выключено; джойстик
## двигает героя, а эмулированный «клик» под джойстиком не копает; тап по кнопке
## прыжка (нажатие и отпускание в одном кадре) прыгает; второй палец копает тайл,
## пока первый держит джойстик (мультитач); тап по хотбару выбирает слот и режим
## (блок — «строить», пустая ячейка — «копать»); умный прицел (#149): тап по свободной
## клетке ставит один блок, тап за препятствием — блок со своей стороны, тап за радиусом
## копает ближнюю стену по лучу, тап на полклетки мимо камня копает камень; кнопки I и J
## открывают и закрывают окна, тап по миру при этом не копает; кнопка «меню» открывает
## паузу (#119); «Назад» Android закрывает окно, открывает и закрывает паузу, свернули
## приложение — пауза и сохранение (#149). Щипок двумя пальцами по миру ведёт зум
## (ViewZoom) и ничего не копает и не ставит; короткий тап быстрее ожидания щипка
## всё равно ставит блок.
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
	await _smart_aim()
	await _pinch_zoom()
	await _windows_by_buttons()
	await _back_and_app_pause()

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
	# Пустую клетку умный прицел (#149) не копает — возвращаем тайл под палец.
	World.set_tile(cell.x, cell.y, before)
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


## Тап по хотбару выбирает слот и режим; умный прицел (#149) ставит и копает, даже
## когда палец не попал в клетку.
func _smart_aim() -> void:
	var base: int = stand_in_corridor(3)
	_settle_camera()
	await wait(0.6)
	player.inv.slots[5] = ItemStack.new(IDs.I.STONE, 10)
	player.inv.slots[6] = ItemStack.new()
	_tap(3, UI.hud.hotbar_slot_rect(5).get_center())
	await wait(0.1)
	ok("тап по хотбару выбирает слот, блок в руке включает «строить»",
			player.inv.selected == 5 and tc.build_mode, "слот %d, строить %s" % [player.inv.selected, tc.build_mode])

	var pc: Vector2i = World.world_to_cell(player.global_position)
	var near: Vector2i = Vector2i(pc.x + 1, base - 1)
	var a: Vector2i = Vector2i(pc.x + 2, base - 1)
	var far: Vector2i = Vector2i(pc.x + 9, base - 1)
	ok("рядом пустые клетки под постройку", World.get_tile_v(near) == IDs.T.AIR
			and World.get_tile_v(a) == IDs.T.AIR, "%s %s" % [str(near), str(a)])

	# Короткий тап по свободной клетке — блок; палец держится — второй не ставится.
	var stones: int = player.inv.slots[5].count
	_touch(1, _screen(World.cell_to_world(a)), true)
	var placed: bool = await wait_until(func() -> bool: return World.get_tile_v(a) == IDs.T.STONE, 0.6)
	await wait(0.5)
	_touch(1, _screen(World.cell_to_world(a)), false)
	ok("тап по свободной клетке ставит один блок (палец держится — второй не встаёт)",
			placed and player.inv.slots[5].count == stones - 1 and World.get_tile_v(near) == IDs.T.AIR,
			"камней %d → %d" % [stones, player.inv.slots[5].count])

	# Тап далеко за камнем (за радиусом): блок встаёт перед камнем, со своей стороны.
	_touch(1, _screen(World.cell_to_world(far)), true)
	placed = await wait_until(func() -> bool: return World.get_tile_v(near) == IDs.T.STONE, 0.6)
	_touch(1, _screen(World.cell_to_world(far)), false)
	ok("тап за препятствием и радиусом ставит блок со своей стороны", placed,
			DB.tile_name(World.get_tile_v(near)))

	# Пустая ячейка хотбара — «копать»; тап за радиусом копает ближнюю стену по лучу.
	_tap(3, UI.hud.hotbar_slot_rect(6).get_center())
	await wait(0.1)
	ok("пустая ячейка хотбара включает «копать»", player.inv.selected == 6 and not tc.build_mode)
	_touch(1, _screen(World.cell_to_world(far)), true)
	await wait(0.1)
	ok("тап за радиусом целит в ближнюю стену по лучу", tc.aim_cell == near, str(tc.aim_cell))
	var dug: bool = await wait_until(func() -> bool: return World.get_tile_v(near) == IDs.T.AIR, 6.0)
	_touch(1, _screen(World.cell_to_world(far)), false)
	ok("удержание выкапывает её", dug, DB.tile_name(World.get_tile_v(near)))
	await wait(0.1)
	ok("палец снят — цели нет", tc.aim_cell == TouchControls.NO_CELL)

	# Палец на полклетки мимо камня (над ним, в воздухе) — копаем камень.
	World.set_tile(a.x, a.y, IDs.T.AIR)
	var rock: Vector2i = Vector2i(pc.x + 3, base - 1)
	World.set_tile(rock.x, rock.y, IDs.T.STONE)
	var miss: Vector2 = World.cell_to_world(rock + Vector2i(0, -1)) + Vector2(0.0, 5.0)
	_touch(1, _screen(miss), true)
	await wait(0.15)
	ok("тап на полклетки мимо камня целит в камень", tc.aim_cell == rock and player.mining_cell == rock,
			"%s, копается %s" % [str(tc.aim_cell), str(player.mining_cell)])
	_touch(1, _screen(miss), false)
	await wait(0.1)
	World.set_tile(rock.x, rock.y, IDs.T.AIR)


## Щипок: второй палец лёг на мир чуть позже первого (как у человека) — оба ведут зум,
## прицела нет, в режиме «строить» ни один блок не встаёт. Короткий тап ставит блок.
func _pinch_zoom() -> void:
	var base: int = stand_in_corridor(4)
	var vz: ViewZoom = player.view_zoom
	vz.set_now(ViewZoom.DEFAULT)
	_settle_camera()
	await wait(0.6)
	player.inv.slots[5] = ItemStack.new(IDs.I.STONE, 10)
	_tap(3, UI.hud.hotbar_slot_rect(5).get_center())
	await wait(0.1)
	ok("щипок проверяем в режиме «строить»", tc.build_mode)
	var stones: int = player.inv.slots[5].count
	var c: Vector2 = _screen(player.global_position) + Vector2(0.0, -30.0)
	_touch(4, c + Vector2(-50.0, 0.0), true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_touch(5, c + Vector2(50.0, 0.0), true)
	await wait(0.1)
	ok("второй палец на мире — щипок, прицела нет", tc.aim_cell == TouchControls.NO_CELL
			and not bool(player.touch_input.get("mouse_buttons", {}).get(MOUSE_BUTTON_RIGHT, false)))
	_drag(4, c + Vector2(-100.0, 0.0))
	_drag(5, c + Vector2(100.0, 0.0))
	await wait(0.1)
	ok("пальцы разошлись вдвое — зум вдвое ближе (до MAX)",
			is_equal_approx(vz.current, minf(ViewZoom.DEFAULT * 2.0, ViewZoom.MAX))
			and is_equal_approx(player.camera.zoom.x, vz.current), "%.3f" % vz.current)
	_drag(4, c + Vector2(-25.0, 0.0))
	_drag(5, c + Vector2(25.0, 0.0))
	await wait(0.1)
	ok("свели — зум дальше, не дальше MIN",
			is_equal_approx(vz.current, maxf(ViewZoom.DEFAULT * 0.5, ViewZoom.MIN)), "%.3f" % vz.current)
	_touch(4, c + Vector2(-25.0, 0.0), false)
	await wait(0.3)
	ok("один палец щипка отпущен — второй не строит", tc.aim_cell == TouchControls.NO_CELL
			and player.inv.slots[5].count == stones)
	_touch(5, c + Vector2(25.0, 0.0), false)
	await wait(0.2)
	ok("щипок не поставил ни блока", player.inv.slots[5].count == stones,
			"камней %d → %d" % [stones, player.inv.slots[5].count])

	vz.set_now(ViewZoom.DEFAULT)
	_settle_camera()
	await wait(0.2)
	var pc: Vector2i = World.world_to_cell(player.global_position)
	var cell: Vector2i = Vector2i(pc.x + 2, base - 1)
	_tap(4, _screen(World.cell_to_world(cell)))
	var placed: bool = await wait_until(func() -> bool: return World.get_tile_v(cell) == IDs.T.STONE, 0.6)
	ok("короткий тап (быстрее ожидания щипка) ставит блок", placed and player.inv.slots[5].count == stones - 1,
			DB.tile_name(World.get_tile_v(cell)))
	World.set_tile(cell.x, cell.y, IDs.T.AIR)
	_tap(3, UI.hud.hotbar_slot_rect(6).get_center())
	await wait(0.1)


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
	# Пауза (#119): ESC на телефоне нет — кнопка «меню» рядом с J; в паузе кнопок нет.
	_tap(2, tc.btn_center["pause"])
	await get_tree().process_frame
	await get_tree().process_frame
	ok("кнопка «меню» открывает паузу (дерево стоит), кнопок и джойстика нет", UI.pause.visible
			and get_tree().paused and tc.control_at(tc.btn_center["inv"]) == ""
			and tc.control_at(tc.btn_center["pause"]) == "" and tc.control_at(tc.stick_center) == "")
	UI.pause.continue_button.pressed.emit()
	ok("«Продолжить» — пауза закрыта, кнопка «меню» снова жмётся", not UI.pause.visible
			and not get_tree().paused and tc.control_at(tc.btn_center["pause"]) == "pause")


## «Назад» Android (#149): окно — закрыть, иначе пауза; в паузе — продолжить. Свернули
## приложение — пауза и сохранение в слот F5.
func _back_and_app_pause() -> void:
	ok("приложение не закрывается само по «Назад»",
			not bool(ProjectSettings.get_setting("application/config/quit_on_go_back", true)))
	_tap(2, tc.btn_center["inv"])
	await wait(0.2)
	get_tree().root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await get_tree().process_frame
	ok("«Назад» закрывает инвентарь, паузы нет", not UI.panel.visible and not UI.pause.visible)
	get_tree().root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await get_tree().process_frame
	ok("«Назад» открывает паузу", UI.pause.visible and get_tree().paused)
	get_tree().root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await get_tree().process_frame
	ok("ещё раз «Назад» — пауза закрыта", not UI.pause.visible and not get_tree().paused)
	Save.remove(Save.slot)
	UI.app_paused()
	ok("свернули приложение — пауза и сохранение в слот F5", UI.pause.visible and get_tree().paused
			and Save.exists(Save.slot), Save.path_for(Save.slot))
	UI.pause.close()
	Save.remove(Save.slot)
	await get_tree().process_frame


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
