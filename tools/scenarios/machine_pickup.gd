extends "res://tools/scenarios/campaign_common.gd"
## Забор своей машины — явная команда, не удар и не копка.
## ПК: [X] по клетке. Телефон: тап по плашке «Забрать» в нижней трети.
## ЛКМ и короткий тап по миру машину не снимают.
##
## Проверки: ПКМ поставил горелку не туда → [X] забрал и выбрал предмет →
## поставил в нужную клетку; глава «Огонь» не считает горелку вне метки;
## постоянная машина и полный сундук остаются; смеситель забирается так же;
## тап по плашке включает режим постройки; удержание E у ядра его не снимает;
## ЛКМ рядом с фантомом горелку не снимает; клик по карточке цели мир не трогает.


func run() -> void:
	player.invuln = 1.0e9
	clear_input()
	await _free_play()
	await _campaign()
	await _permanent_and_chest()
	await _mixer()
	await _lmb_does_not_pickup()
	await _core_hold()
	await _attack_hold()
	await _card_click()
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
	ok("подсказка постановки говорит ПКМ", HUD.HINT_PLACE.contains("ПКМ — поставить")
			and not HUD.HINT_PLACE.begins_with("ЛКМ"))

	aim(World.cell_to_world(wrong))
	press_mouse(MOUSE_BUTTON_LEFT)
	await wait(0.25)
	release_mouse(MOUSE_BUTTON_LEFT)
	await wait(0.2)
	ok("ЛКМ горелку не забрал", World.machines.has(wrong) and _kind_at(wrong) == "Burner")

	aim(World.cell_to_world(wrong))
	hold(KEY_X)
	await wait(0.2)
	release(KEY_X)
	await wait(0.2)
	ok("[X] забрал горелку — клетки пуста", not World.machines.has(wrong))
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
	hold(KEY_X)
	await wait(0.2)
	release(KEY_X)
	await wait(0.2)
	ok("[X] забрал горелку главы", not World.machines.has(wrong)
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
	hold(KEY_X)
	await wait(0.2)
	release(KEY_X)
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
	hold(KEY_X)
	await wait(0.2)
	release(KEY_X)
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
	hold(KEY_X)
	await wait(0.2)
	release(KEY_X)
	await wait(0.2)
	ok("смеситель забран, как горелка", not World.machines.has(cell)
			and player.inv.count_of(IDs.I.MIXER) == n0 + 1
			and player.inv.selected_stack().id == IDs.I.MIXER)
	ok("уведомление смесителя — «Забрано»", _note_has("Забрано"), _last_note())


# ------------------------------------------------ ЛКМ НЕ ЗАБИРАЕТ

func _lmb_does_not_pickup() -> void:
	var base: int = stand_in_corridor(4)
	var cell: Vector2i = _free_cell(base, 5, 10)
	ok("клетка для ЛКМ свободна", cell.x >= 0, str(cell))
	if cell.x < 0:
		return
	ok("горелка для ЛКМ поставлена", MachineBase.place_machine("Burner", cell))
	_stand_near(cell)
	aim(World.cell_to_world(cell))
	press_mouse(MOUSE_BUTTON_LEFT)
	await wait(0.4)
	release_mouse(MOUSE_BUTTON_LEFT)
	ok("удержание ЛКМ по горелке её не снимает", World.machines.has(cell))
	_erase(cell)


# ----------------------------------------------------------- ЯДРО

func _core_hold() -> void:
	var cell: Vector2i = _place_core()
	ok("ядро для удержания поставлено", cell.x >= 0 and Game.core_cell == cell, str(cell))
	if cell.x < 0:
		return
	var placed: bool = _stand_next_to(cell)
	ok("герой встал у ядра", placed, str(cell))
	if not placed:
		return
	aim(World.cell_to_world(cell))
	player.inv.selected = _empty_slot()
	await wait(0.35)
	var hud: HUD = UI.hud
	ok("у неготового ядра подсказка — причина, не разбор",
			hud.hint_text == HUD.HINT_BEACON_WAIT or hud.hint_text == HUD.HINT_BEACON_ARCS,
			"«%s»" % hud.hint_text)
	# Разбор обычной машины — 0.9 с. Ядро за это время не должно исчезнуть.
	hold(KEY_E)
	await wait(1.4)
	release(KEY_E)
	await wait(0.2)
	ok("удержание E 1.4 с ядро не разобрало", World.machines.has(cell)
			and String(World.machines[cell].kind) == "RainbowCore")
	# Причина запуска — когда отсчёт дошёл до конца и ворота закрыты (3 с).
	hold(KEY_E)
	await wait(3.4)
	release(KEY_E)
	await wait(0.2)
	ok("удержание E 3 с ядро не разобрало", World.machines.has(cell)
			and String(World.machines[cell].kind) == "RainbowCore")
	ok("причина запуска сказана у ядра", _note_has("Рано") or _note_has("дуг")
			or _note_has("запуск"), _last_note())

	Game.tasks_done = 1
	Game.stats_ore = Balance.FREE_ORE_NEED
	Game.nights_survived = Balance.FREE_NIGHTS_NEED
	for c in [Beams.R, Beams.G, Beams.B, Beams.Y, Beams.C, Beams.M]:
		Game.core_feed(c)
	Game.update_objective()
	await wait(0.35)
	ok("готовое ядро просит удержать E", hud.hint_text == HUD.HINT_BEACON,
			"«%s»" % hud.hint_text)
	hold(KEY_E)
	var started: bool = await wait_until(func() -> bool: return Game.relay_active, 5.0)
	release(KEY_E)
	await wait(0.2)
	ok("удержание запустило ядро и не сняло его", started and World.machines.has(cell)
			and String(World.machines[cell].kind) == "RainbowCore")
	Game.relay_active = false
	Game.relay_timer = 0.0
	_erase(cell)
	clear_input()


# ---------------------------------------------------- УДАР СКВОЗЬ КУЛДАУН

func _attack_hold() -> void:
	var base: int = stand_in_corridor(5)
	var cell: Vector2i = _free_cell(base, 4, 8)
	ok("горелка у фантома поставлена", cell.x >= 0 and MachineBase.place_machine("Burner", cell),
			str(cell))
	if cell.x < 0:
		return
	_stand_near(cell)
	var ph: Node = spawn_phantom_at(World.cell_to_world(cell) + Vector2(10, -6), "echo")
	ok("фантом рядом с горелкой", ph != null and is_instance_valid(ph))
	if ph == null:
		_erase(cell)
		return
	ph.set_physics_process(false)
	ph.hp = 200.0
	var hp0: float = float(ph.hp)
	aim(ph.global_position)
	press_mouse(MOUSE_BUTTON_LEFT)
	await wait(0.15)
	ok("первый удар прошёл", float(ph.hp) < hp0 - 1.0, "%.0f → %.0f" % [hp0, float(ph.hp)])
	ok("удар на кулдауне", player.slash_cd > 0.0, "%.2f" % player.slash_cd)
	var hp1: float = float(ph.hp)
	# Кулдаун 0.45 с. Держим ЛКМ: кадр перезарядки не должен забрать горелку,
	# а следующий взмах проходит без отпускания кнопки.
	await wait(0.55)
	ok("ЛКМ у фантома горелку не снял", World.machines.has(cell))
	ok("удержание дало второй удар без отпускания", float(ph.hp) < hp1 - 1.0,
			"%.0f → %.0f" % [hp1, float(ph.hp)])
	release_mouse(MOUSE_BUTTON_LEFT)
	if is_instance_valid(ph):
		ph.queue_free()
	_erase(cell)
	clear_input()


# ------------------------------------------------ КЛИК ПО КАРТОЧКЕ ЦЕЛИ

func _card_click() -> void:
	var base: int = stand_in_corridor(6)
	var cell: Vector2i = _free_cell(base, 5, 9)
	ok("клетка под карточкой свободна для копки", cell.x >= 0, str(cell))
	if cell.x < 0:
		return
	World.set_tile(cell.x, cell.y, IDs.T.STONE)
	ok("камень под прицелом", World.get_tile_v(cell) == IDs.T.STONE)
	_stand_near(cell)
	var hud: HUD = UI.hud
	await wait(0.4)
	var card: Rect2 = hud.layout_screen_rect("card")
	ok("карточка цели на экране", card.has_area() and hud.card_text != "",
			"«%s» %s" % [hud.card_text, str(card)])
	if not card.has_area():
		World.set_tile(cell.x, cell.y, IDs.T.AIR)
		return
	aim(World.cell_to_world(cell))
	var prog0: float = player.mining_progress
	press_mouse(MOUSE_BUTTON_LEFT)
	# press_mouse пересобирает шов и стирает экранную точку — кладём её снова.
	player.test_input["screen_mouse"] = card.get_center()
	await wait(0.35)
	release_mouse(MOUSE_BUTTON_LEFT)
	ok("клик по карточке не копает мир", player.mining_progress <= prog0 + 0.001
			and World.get_tile_v(cell) == IDs.T.STONE,
			"прогресс %.3f" % player.mining_progress)
	player.inv.add(IDs.I.BURNER, 1)
	player.inv.selected = _slot(IDs.I.BURNER)
	World.set_tile(cell.x, cell.y, IDs.T.AIR)
	aim(World.cell_to_world(cell))
	press_mouse(MOUSE_BUTTON_RIGHT)
	player.test_input["screen_mouse"] = card.get_center()
	await wait(0.35)
	release_mouse(MOUSE_BUTTON_RIGHT)
	ok("клик по карточке не ставит", not World.machines.has(cell))
	player.test_input.erase("screen_mouse")
	clear_input()


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
	# Клик по карточке оставляет горелку в рюкзаке. add докладывает в неё,
	# и remove_at снимает одну — рука после постановки не пустая. Сбрасываем.
	player.inv.remove_id(IDs.I.BURNER, player.inv.count_of(IDs.I.BURNER))
	player.inv.add(IDs.I.BURNER, 1)
	player.inv.selected = _slot(IDs.I.BURNER)
	ok("в руке одна горелка", player.inv.selected_stack().id == IDs.I.BURNER
			and player.inv.selected_stack().count == 1
			and player.inv.count_of(IDs.I.BURNER) == 1)
	tc.build_mode = true
	_settle_camera()
	await wait(0.3)
	var screen: Vector2 = _screen(World.cell_to_world(cell))
	var hud: HUD = UI.hud
	ok("тап по клетке не попадает в HUD", not hud.covers_screen(screen)
			and tc.control_at(screen) == "", "экран %s" % str(screen))
	await _tap(1, screen)
	await get_tree().physics_frame
	var placed: bool = await wait_until(func() -> bool: return _kind_at(cell) == "Burner", 1.5)
	ok("тап в режиме постройки поставил горелку", placed, str(cell))
	ok("после постановки рука пуста", player.inv.selected_stack().is_empty())
	tc.build_mode = false
	tc.aim_cell = TouchControls.NO_CELL
	_settle_camera()
	await wait(0.35)
	ok("тач-плашка — забрать горелку", hud._plate_text() == HUD.TOUCH_PICKUP_BURNER,
			"«%s»" % hud._plate_text())
	ok("тач-строка влезает без обрезки", not hud._plate_text().contains("…"))
	var plate: Rect2 = hud.layout_screen_rect("hint")
	ok("плашка «Забрать» в нижней трети", plate.has_area()
			and plate.position.y >= hud.size.y * hud.TOUCH_BAND * UI.ui_scale - 1.0,
			str(plate))
	screen = _screen(World.cell_to_world(cell))
	await _tap(2, screen)
	await get_tree().physics_frame
	await wait(0.4)
	ok("тап по миру горелку не забрал", World.machines.has(cell))
	ok("плашка ловит тап забора", hud.pickup_plate_at(plate.get_center()), str(plate))
	await _tap(3, plate.get_center())
	await get_tree().physics_frame
	var taken: bool = await wait_until(func() -> bool:
		return not World.machines.has(cell) and player.inv.selected_stack().id == IDs.I.BURNER,
		1.5)
	ok("тап по плашке забрал горелку и выбрал её", taken, "слот %d" % player.inv.selected)
	ok("после забора включён режим постройки", tc.build_mode)
	_settle_camera()
	aim(World.cell_to_world(dest))
	await wait(0.35)
	ok("тач-плашка — поставить", hud._plate_text() == HUD.TOUCH_PLACE, "«%s»" % hud._plate_text())
	var dest_screen: Vector2 = _screen(World.cell_to_world(dest))
	ok("клетка постановки не под плашкой", not hud.covers_screen(dest_screen), str(dest_screen))
	await _tap(4, dest_screen)
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


func _empty_slot() -> int:
	for i in 10:
		if player.inv.get_slot(i).is_empty():
			return i
	player.inv.slots[9] = ItemStack.new()
	return 9


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


func _place_core() -> Vector2i:
	var cell: Vector2i = World.beacon_cell + Vector2i(2, 0)
	if World.get_tile_v(cell) != IDs.T.AIR:
		World.set_tile(cell.x, cell.y, IDs.T.AIR)
	if World.machines.has(cell):
		var old = World.machines[cell]
		if old != null and is_instance_valid(old):
			old.dismantle()
	if not MachineBase.place_machine("RainbowCore", cell):
		return Vector2i(-1, -1)
	return cell


func _stand_next_to(cell: Vector2i) -> bool:
	var base: int = cell.y + 1
	for dx in [1, -1, 2, -2, 0]:
		var px: int = cell.x + int(dx)
		if not World.is_solid_cell(Vector2i(px, base)):
			World.set_tile(px, base, IDs.T.STEEL)
		for y in range(base - 3, base):
			if World.get_tile_v(Vector2i(px, y)) != IDs.T.AIR and Vector2i(px, y) != cell:
				World.set_tile(px, y, IDs.T.AIR)
		player.global_position = Vector2(float(px * World.TILE) + 8.0, float(base * World.TILE) - 11.0)
		player.vel = Vector2.ZERO
		return true
	return false


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
	await get_tree().physics_frame
	_touch_at(index, pos, false)
