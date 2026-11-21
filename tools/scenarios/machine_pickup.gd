extends "res://tools/scenarios/campaign_common.gd"
## Забор своей машины: свежий ЛКМ (и короткий тап) снимает её сразу и даёт
## поставить заново. Удержание E остаётся. Постройка базы и непустой сундук
## не забираются — причина в уведомлении.
##
## Проверки: ПКМ поставил горелку не туда → ЛКМ забрал и выбрал предмет →
## поставил в нужную клетку; глава «Огонь» не считает горелку вне метки и
## говорит забрать; постоянная машина и полный сундук остаются; смеситель
## забирается так же; тап выбирает предмет и включает режим постройки.


func run() -> void:
	player.invuln = 1.0e9
	clear_input()
	await _free_play()
	await _campaign()
	await _permanent_and_chest()
	await _mixer()
	await _touch()
	finish()


# ------------------------------------------------------- СВОБОДНАЯ ИГРА

func _free_play() -> void:
	var base: int = stand_in_corridor(2)
	var bx: int = World.beacon_cell.x
	var wrong: Vector2i = Vector2i(bx + 5, base - 1)
	var right: Vector2i = Vector2i(bx + 8, base - 1)
	player.inv.add(IDs.I.BURNER, 1)
	player.inv.selected = _slot(IDs.I.BURNER)
	ok("клетка для постановки свободна", World.get_tile_v(wrong) == IDs.T.AIR, str(wrong))
	aim(World.cell_to_world(wrong))
	await wait(0.15)
	press_mouse(MOUSE_BUTTON_RIGHT)
	await wait(0.35)
	release_mouse(MOUSE_BUTTON_RIGHT)
	await wait(0.15)
	ok("ПКМ поставил горелку не туда", _kind_at(wrong) == "Burner", str(wrong))
	ok("горелка ушла из рюкзака", player.inv.count_of(IDs.I.BURNER) == 0)
	var hud: HUD = UI.hud
	await wait(0.3)
	ok("подсказка — забрать горелку", hud.hint_text == HUD.HINT_PICKUP_BURNER,
			"«%s»" % hud.hint_text)

	aim(World.cell_to_world(wrong))
	press_mouse(MOUSE_BUTTON_LEFT)
	await wait(0.25)
	release_mouse(MOUSE_BUTTON_LEFT)
	await wait(0.2)
	ok("ЛКМ забрал горелку — клетки пуста", not World.machines.has(wrong))
	ok("горелка вернулась и выбрана", player.inv.count_of(IDs.I.BURNER) == 1
			and player.inv.selected_stack().id == IDs.I.BURNER,
			"слот %d" % player.inv.selected)
	ok("уведомление — «Забрано»", _note_has("Забрано"), _last_note())

	aim(World.cell_to_world(right))
	await wait(0.15)
	press_mouse(MOUSE_BUTTON_RIGHT)
	await wait(0.35)
	release_mouse(MOUSE_BUTTON_RIGHT)
	await wait(0.2)
	ok("поставил в нужную клетку", _kind_at(right) == "Burner", str(right))
	ok("старой горелки нет", not World.machines.has(wrong))
	_erase(right)


# --------------------------------------------------------------- КАМПАНИЯ

func _campaign() -> void:
	var m: Mission = start_chapter("fire")
	ok("глава «Огонь» началась", m != null and m.id == "fire", str(m))
	if m == null:
		return
	var mark: Vector2i = m.call("mark")
	var wrong: Vector2i = mark + Vector2i(-3, 0)
	ok("метка пуста", World.get_tile_v(mark) == IDs.T.AIR and not World.machines.has(mark),
			str(mark))
	World.set_tile(wrong.x, wrong.y, IDs.T.AIR)
	stand_at_cell(wrong + Vector2i(2, 1))
	player.inv.selected = _slot(IDs.I.BURNER)
	aim(World.cell_to_world(wrong))
	await wait(0.15)
	press_mouse(MOUSE_BUTTON_RIGHT)
	await wait(0.35)
	release_mouse(MOUSE_BUTTON_RIGHT)
	await wait(0.4)
	ok("горелка стоит не на метке", _kind_at(wrong) == "Burner" and not World.machines.has(mark))
	ok("этап 1 не засчитан", m.stage == 0 and int(m.goals[0]["have"]) == 0,
			"этап %d, %d/%d" % [m.stage, int(m.goals[0]["have"]), int(m.goals[0]["need"])])
	var hinted: bool = await wait_until(func() -> bool:
		return String(m.hint).contains("забери и поставь"), 2.0)
	ok("подсказка — забери и поставь на метку", hinted, "«%s»" % m.hint)

	aim(World.cell_to_world(wrong))
	press_mouse(MOUSE_BUTTON_LEFT)
	await wait(0.25)
	release_mouse(MOUSE_BUTTON_LEFT)
	await wait(0.2)
	ok("ЛКМ забрал горелку главы", not World.machines.has(wrong)
			and player.inv.selected_stack().id == IDs.I.BURNER)
	stand_at_cell(mark + Vector2i(2, 1))
	aim(World.cell_to_world(mark))
	await wait(0.15)
	press_mouse(MOUSE_BUTTON_RIGHT)
	await wait(0.35)
	release_mouse(MOUSE_BUTTON_RIGHT)
	var advanced: bool = await wait_stage(1, 2.0)
	ok("горелка на метке → этап 1/1 и дальше", advanced and m.stage >= 1
			and _kind_at(mark) == "Burner", "этап %d" % m.stage)
	end_chapter()
	clear_input()


# ----------------------------------------- ПОСТОЯННАЯ И ПОЛНЫЙ СУНДУК

func _permanent_and_chest() -> void:
	var base: int = stand_in_corridor(2)
	var bx: int = World.beacon_cell.x
	var pcell: Vector2i = Vector2i(bx + 5, base - 1)
	ok("постоянная поставлена", MachineBase.place_machine("Burner", pcell))
	var perm = World.machines.get(pcell)
	perm.permanent = true
	_stand_near(pcell)
	aim(World.cell_to_world(pcell))
	await wait(0.2)
	press_mouse(MOUSE_BUTTON_LEFT)
	await wait(0.25)
	release_mouse(MOUSE_BUTTON_LEFT)
	await wait(0.2)
	ok("постоянную постройку базы не забрать", World.machines.has(pcell))
	ok("причина — постройка базы", _note_has("постройка базы"), _last_note())
	_erase(pcell)

	var ccell: Vector2i = Vector2i(bx + 8, base - 1)
	ok("сундук поставлен", MachineBase.place_machine("Chest", ccell))
	var chest: Chest = World.machines.get(ccell) as Chest
	chest.receive_item(IDs.I.STONE, 2)
	_stand_near(ccell)
	aim(World.cell_to_world(ccell))
	await wait(0.2)
	press_mouse(MOUSE_BUTTON_LEFT)
	await wait(0.25)
	release_mouse(MOUSE_BUTTON_LEFT)
	await wait(0.2)
	ok("непустой сундук не забран", World.machines.has(ccell) and not _chest_empty(chest))
	ok("причина — сундук не пуст", _note_has("Сундук не пуст"), _last_note())
	_erase(ccell)


# ---------------------------------------------------------------- СМЕСИТЕЛЬ

func _mixer() -> void:
	var base: int = stand_in_corridor(2)
	# +5 занят после главы «Огонь» (метка горелки). Берём свободную клетку коридора.
	var cell: Vector2i = _free_cell(base, 4, 12)
	ok("клетка смесителя свободна", cell.x >= 0 and World.get_tile_v(cell) == IDs.T.AIR
			and not World.machines.has(cell), str(cell))
	if cell.x < 0:
		return
	player.inv.add(IDs.I.MIXER, 1)
	player.inv.selected = _slot(IDs.I.MIXER)
	aim(World.cell_to_world(cell))
	await wait(0.15)
	press_mouse(MOUSE_BUTTON_RIGHT)
	await wait(0.35)
	release_mouse(MOUSE_BUTTON_RIGHT)
	await wait(0.15)
	ok("смеситель поставлен", _kind_at(cell) == "Mixer")
	var n0: int = player.inv.count_of(IDs.I.MIXER)
	aim(World.cell_to_world(cell))
	press_mouse(MOUSE_BUTTON_LEFT)
	await wait(0.25)
	release_mouse(MOUSE_BUTTON_LEFT)
	await wait(0.2)
	ok("смеситель забран, как горелка", not World.machines.has(cell)
			and player.inv.count_of(IDs.I.MIXER) == n0 + 1
			and player.inv.selected_stack().id == IDs.I.MIXER)
	ok("уведомление смесителя — «Забрано»", _note_has("Забрано"), _last_note())


# --------------------------------------------------------------------- ТАЧ

func _touch() -> void:
	var tc: TouchControls = get_tree().get_first_node_in_group("touch_controls")
	ok("сенсорное управление есть", tc != null)
	if tc == null:
		return
	tc.set_enabled(true)
	clear_input()
	var base: int = stand_in_corridor(3)
	var cell: Vector2i = _free_cell(base, 5, 10)
	var dest: Vector2i = _free_cell(base, cell.x - World.beacon_cell.x + 2, 14)
	ok("клетки тапа свободны и не под плашкой", cell.x >= 0 and dest.x >= 0
			and dest != cell, "%s → %s" % [str(cell), str(dest)])
	if cell.x < 0 or dest.x < 0:
		tc.set_enabled(false)
		return
	player.inv.add(IDs.I.BURNER, 1)
	player.inv.selected = _slot(IDs.I.BURNER)
	tc.build_mode = true
	_settle_camera()
	await wait(0.3)
	var screen: Vector2 = _screen(World.cell_to_world(cell))
	var hud: HUD = UI.hud
	ok("тап по клетке не попадает в HUD", not hud.covers_screen(screen)
			and tc.control_at(screen) == "", "экран %s" % str(screen))
	_tap(1, screen)
	await get_tree().physics_frame
	var placed: bool = await wait_until(func() -> bool: return _kind_at(cell) == "Burner", 1.5)
	ok("тап в режиме постройки поставил горелку", placed, str(cell))
	ok("после постановки рука пуста", player.inv.count_of(IDs.I.BURNER) == 0)
	tc.build_mode = false
	tc.aim_cell = TouchControls.NO_CELL
	_settle_camera()
	await wait(0.35)
	ok("тач-плашка — забрать горелку", hud._plate_text() == HUD.TOUCH_PICKUP_BURNER,
			"«%s»" % hud._plate_text())
	ok("тач-строка влезает без обрезки", not hud._plate_text().contains("…"))
	screen = _screen(World.cell_to_world(cell))
	_tap(2, screen)
	await get_tree().physics_frame
	var taken: bool = await wait_until(func() -> bool:
		return not World.machines.has(cell) and player.inv.selected_stack().id == IDs.I.BURNER,
		1.5)
	ok("тап забрал горелку и выбрал её", taken, "слот %d" % player.inv.selected)
	ok("после забора включён режим постройки", tc.build_mode)
	_settle_camera()
	aim(World.cell_to_world(dest))
	await wait(0.35)
	ok("тач-плашка — поставить", hud._plate_text() == HUD.TOUCH_PLACE, "«%s»" % hud._plate_text())
	var dest_screen: Vector2 = _screen(World.cell_to_world(dest))
	ok("клетка постановки не под плашкой", not hud.covers_screen(dest_screen), str(dest_screen))
	_tap(3, dest_screen)
	await get_tree().physics_frame
	var moved: bool = await wait_until(func() -> bool: return _kind_at(dest) == "Burner", 1.5)
	ok("следующий тап поставил горелку", moved and not World.machines.has(cell), str(dest))
	tc.set_enabled(false)
	clear_input()


# ------------------------------------------------------------------ МЕЛОЧИ


func _free_cell(base: int, dx0: int, dx1: int) -> Vector2i:
	var bx: int = World.beacon_cell.x
	for dx in range(dx0, dx1 + 1):
		var c: Vector2i = Vector2i(bx + dx, base - 1)
		if World.get_tile_v(c) == IDs.T.AIR and not World.machines.has(c):
			return c
	return Vector2i(-1, -1)


func _chest_empty(chest: Chest) -> bool:
	for s in chest.slots:
		if not s.is_empty():
			return false
	return true


func _kind_at(c: Vector2i) -> String:
	var m = World.machines.get(c)
	return String(m.kind) if m != null else ""


func _slot(id: int) -> int:
	for i in player.inv.slots.size():
		if player.inv.slots[i].id == id:
			return i
	return 0


func _stand_near(cell: Vector2i) -> void:
	player.global_position = Vector2(float((cell.x + 1) * World.TILE) + 8.0,
			float((cell.y + 1) * World.TILE) - 11.0)
	player.vel = Vector2.ZERO


func _erase(c: Vector2i) -> void:
	var m = World.machines.get(c)
	if m != null and is_instance_valid(m):
		m.dismantle()


func _note_has(part: String) -> bool:
	for n in UI.hud.notes:
		if String(n.get("text", "")).contains(part):
			return true
	return false


func _last_note() -> String:
	if UI.hud.notes.is_empty():
		return ""
	return String(UI.hud.notes.back().get("text", ""))


func _screen(world: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world


func _settle_camera() -> void:
	if player.camera == null:
		return
	player.camera.reset_smoothing()
	player.camera.global_position = player.global_position
	player.camera.force_update_scroll()


var _down: Dictionary = {}


func _touch_at(index: int, pos: Vector2, pressed: bool) -> void:
	var e: InputEventScreenTouch = InputEventScreenTouch.new()
	e.index = index
	e.position = get_viewport().get_final_transform() * pos
	e.pressed = pressed
	Input.parse_input_event(e)
	if pressed:
		_down[index] = pos
	else:
		_down.erase(index)


func _tap(index: int, pos: Vector2) -> void:
	_touch_at(index, pos, true)
	_touch_at(index, pos, false)
