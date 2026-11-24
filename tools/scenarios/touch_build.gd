extends ScenarioBase
## Сенсорная стройка и инвентарь (#310). На коде до фикса падает:
## первый тап после 15 с не прыгает; удержание стройки уже тратит камень;
## второй палец, пришедший после PINCH_WAIT, крутит горелку; Q на перезарядке
## не рисуется; отсчёт ночи на телефоне не закреплён в нижней трети.
##
## Касания — тем же путём, что touch_controls: Input.parse_input_event.
## Панель — ЛКМ с DEVICE_ID_EMULATION, как её видит телефон.
## Реальный Android здесь не проверяется.

var tc: TouchControls = null
var panel: InventoryPanel = null
var _down: Dictionary = {}


func run() -> void:
	player.invuln = 1.0e9
	tc = get_tree().get_first_node_in_group("touch_controls")
	panel = UI.panel
	ok("TouchControls на месте", tc != null)
	if tc == null:
		finish()
		return
	tc.set_enabled(true)
	stand_in_corridor(4)
	await wait(0.3)
	await _idle_jump()
	await _build_preview()
	await _pinch_keeps()
	await _late_pinch()
	await _q_cooldown()
	await _countdown_pin()
	await _finger_craft()
	await _chest_both_layouts()
	tc.build_mode = false
	tc.set_enabled(false)
	finish()


## После 15 с первый тап по прыжку прыгает. Пустой тап только возвращает контролы.
func _idle_jump() -> void:
	_lift_all()
	await wait(0.2)
	await wait(TouchControls.AUTO_HIDE_SEC + 0.8)
	ok("после 15 с контролы скрыты и control_at пуст",
			tc.controls_hidden and tc.controls_alpha <= 0.0
			and tc.control_at(tc.btn_center["jump"]) == "",
			"alpha %.3f" % tc.controls_alpha)
	await wait_until(func() -> bool: return player.on_ground, 1.5)
	var y0: float = player.global_position.y
	_tap(2, tc.btn_center["jump"])
	var rose: bool = await wait_until(func() -> bool: return player.global_position.y < y0 - 8.0, 0.6)
	ok("первый тап по прыжку после 15 с прыгает",
			rose and tc.controls_shown() and not tc.held("jump"),
			"dy %.1f" % (y0 - player.global_position.y))
	await wait_until(func() -> bool: return player.on_ground, 2.0)
	await wait(TouchControls.AUTO_HIDE_SEC + 0.8)
	_tap(4, Vector2(8, 8))
	await wait(0.15)
	ok("тап мимо кнопок после 15 с только возвращает",
			tc.controls_shown() and not tc.held("jump")
			and not player.touch_input.has("mouse_buttons"),
			"hidden %s" % tc.controls_hidden)


## Удержание показывает клетку и стрелку и не тратит камень. Отпуск ставит один раз.
func _build_preview() -> void:
	_clear_hotbar()
	player.inv.selected = 5
	player.inv.add(IDs.I.STONE, 2)
	# add кладёт в первую свободную; переносим в слот 5, чтобы тап хотбара был однозначен.
	_move_id_to(IDs.I.STONE, 5)
	var before: int = player.inv.count_of(IDs.I.STONE)
	_tap(1, UI.hud.hotbar_slot_rect(5).get_center())
	await wait(0.1)
	ok("тап по камню включает стройку", tc.build_mode and player.inv.selected == 5,
			"build %s slot %d" % [tc.build_mode, player.inv.selected])
	var cell: Vector2i = _free_cell()
	ok("есть свободная клетка в радиусе", cell.x >= 0)
	if cell.x < 0:
		return
	var screen: Vector2 = _screen(World.cell_to_world(cell))
	_touch(3, screen, true)
	await wait(0.12)   # PINCH_WAIT и кадр прицела, палец ещё держит
	ok("до отпускания видна клетка и стрелка новой машины (вправо)",
			tc.aim_cell == cell and tc._aim_dir < 0 and tc._world_finger >= 0,
			"aim %s dir %d" % [tc.aim_cell, tc._aim_dir])
	ok("удержание стройки не тратит камень и не ставит тайл",
			player.inv.count_of(IDs.I.STONE) == before
			and World.get_tile_v(cell) == IDs.T.AIR and not World.machines.has(cell),
			"камень %d" % player.inv.count_of(IDs.I.STONE))
	_touch(3, screen, false)
	await wait(0.35)
	ok("отпускание ставит один камень",
			World.get_tile_v(cell) == IDs.T.STONE
			and player.inv.count_of(IDs.I.STONE) == before - 1,
			"тайл %d камень %d" % [World.get_tile_v(cell), player.inv.count_of(IDs.I.STONE)])
	World.set_tile(cell.x, cell.y, IDs.T.AIR)


## Щипок в окне PINCH_WAIT не ставит. Поздний второй палец — отдельная проверка.
func _pinch_keeps() -> void:
	var before: int = player.inv.count_of(IDs.I.STONE)
	var cell: Vector2i = _free_cell()
	if cell.x < 0:
		ok("клетка для щипка", false)
		return
	var screen: Vector2 = _screen(World.cell_to_world(cell))
	_touch(3, screen, true)
	await wait(0.02)
	_touch(5, screen + Vector2(40, 8), true)
	await wait(0.2)
	_touch(5, screen + Vector2(40, 8), false)
	_touch(3, screen, false)
	await wait(0.3)
	ok("щипок в окне ожидания не тратит камень и не ставит",
			player.inv.count_of(IDs.I.STONE) == before
			and World.get_tile_v(cell) == IDs.T.AIR,
			"камень %d" % player.inv.count_of(IDs.I.STONE))


## Второй палец после PINCH_WAIT не крутит горелку и не двигает её.
func _late_pinch() -> void:
	var cell: Vector2i = _free_cell()
	ok("клетка для горелки", cell.x >= 0 and MachineBase.place_machine("Burner", cell))
	if cell.x < 0 or not World.machines.has(cell):
		return
	var burner: MachineBase = World.machines[cell]
	var pos0: Vector2 = burner.global_position
	var dir0: int = burner.dir
	player.inv.selected = 5
	player.inv.slots[5].take(player.inv.slots[5].count)
	# Пустой слот — копка. Берём горелку в руку, чтобы режим был «строить».
	player.inv.add(IDs.I.BURNER, 1)
	_move_id_to(IDs.I.BURNER, 5)
	_tap(1, UI.hud.hotbar_slot_rect(5).get_center())
	await wait(0.1)
	var screen: Vector2 = _screen(World.cell_to_world(cell))
	_touch(3, screen, true)
	await wait(0.2)   # дольше PINCH_WAIT: на старом коде копка/поворот уже идут
	ok("до щипка стрелка показывает следующий шаг, горелка не крутится",
			tc.aim_cell == cell and tc._aim_dir == (dir0 + 1) % burner.turn_steps
			and burner.dir == dir0 and burner.global_position == pos0,
			"aim_dir %d dir %d" % [tc._aim_dir, burner.dir])
	var stones: int = player.inv.count_of(IDs.I.STONE)
	var burners: int = player.inv.count_of(IDs.I.BURNER)
	_touch(6, screen + Vector2(48, -12), true)
	await wait(0.25)
	_touch(6, screen + Vector2(48, -12), false)
	_touch(3, screen, false)
	await wait(0.35)
	ok("поздний щипок не крутит и не двигает горелку",
			burner.dir == dir0 and burner.global_position == pos0
			and World.machines.get(cell) == burner,
			"dir %d → %d pos %s" % [dir0, burner.dir, burner.global_position])
	ok("поздний щипок не тратит материалы",
			player.inv.count_of(IDs.I.STONE) == stones
			and player.inv.count_of(IDs.I.BURNER) == burners,
			"камень %d горелка %d" % [player.inv.count_of(IDs.I.STONE), player.inv.count_of(IDs.I.BURNER)])
	if is_instance_valid(burner):
		burner.dismantle()


## Q видна на перезарядке, дуга не полная, шов Q не зажат.
func _q_cooldown() -> void:
	player.emp_cd = player.emp_max * 0.5
	tc._fill_key()
	ok("Q нарисована на перезарядке", tc._shown("q", false) and int(tc._key[14]) == 1
			and int(tc._key[9]) > 0 and int(tc._key[9]) < 24,
			"key9 %d key14 %d" % [int(tc._key[9]), int(tc._key[14])])
	_touch(2, tc.btn_center["q"], true)
	await wait(0.1)
	var keys: Dictionary = player.touch_input.get("keys", {})
	ok("удержание Q на перезарядке не жмёт шов", not bool(keys.get(KEY_Q, false))
			and player.emp_cd > 0.0,
			"cd %.2f" % player.emp_cd)
	_touch(2, tc.btn_center["q"], false)
	player.emp_cd = 0.0


## Сумерки: отсчёт в нижней трети и в ландшафте, и в портрете. Захват его не стирает.
func _countdown_pin() -> void:
	Game.time_of_day = Balance.DUSK_START + 0.01
	await wait(0.15)
	ok("сумерки дают секунды", UI.hud.night_countdown >= 0, "%d" % UI.hud.night_countdown)
	var hud_size0: Vector2 = UI.hud.size
	for pair in [[Vector2(1280, 720), "ландшафт"], [Vector2(720, 1280), "портрет"]]:
		var vp: Vector2 = pair[0]
		var label: String = String(pair[1])
		tc.force_k = 1.0
		tc._layout(vp)
		UI.hud.size = vp
		UI.hud._lay_sig = -1
		var L: Dictionary = UI.hud.layout_named()
		var cd: Rect2 = L.get("countdown", Rect2())
		var band: float = vp.y * HUD.TOUCH_BAND
		ok("отсчёт закреплён в нижней трети (%s)" % label,
				cd.has_area() and cd.position.y + 0.5 >= band and cd.end.y <= vp.y + 0.5,
				"rect %s band %.0f" % [cd, band])
	UI.hud.size = hud_size0
	UI.hud._lay_sig = -1
	tc.force_k = 0.0
	tc._relayout()
	Game.time_of_day = Balance.START_TIME


## Осмотр стекла, крафт пальцем, результат в инвентаре. Стопка песка при осмотре цела.
func _finger_craft() -> void:
	player.inv.remove_id(IDs.I.SAND, player.inv.count_of(IDs.I.SAND))
	player.inv.remove_id(IDs.I.GLASS, player.inv.count_of(IDs.I.GLASS))
	player.inv.mark_seen(IDs.I.SAND)
	player.inv.add(IDs.I.SAND, 2)
	var sand_i: int = _index_of(IDs.I.SAND)
	ok("песок в инвентаре", sand_i >= 0, "слот %d" % sand_i)
	_tap(2, tc.btn_center["inv"])
	await wait(0.2)
	ok("инвентарь открыт пальцем", panel.visible)
	if not panel.visible or sand_i < 0:
		return
	_panel_tap(panel._inspect_rect().get_center())
	_panel_tap(panel._inv_slot_rect(sand_i).get_center())
	var sand_n: int = player.inv.count_of(IDs.I.SAND)
	ok("осмотр ячейки не берёт песок", sand_n == 2
			and String(panel._inspect.get("kind", "")) == "inv"
			and panel.held.is_empty(),
			"песок %d kind %s" % [sand_n, panel._inspect.get("kind", "")])
	var recipes: Array = panel._recipes("hand")
	var glass: Dictionary = {}
	for rec in recipes:
		if int(rec["out"]) == IDs.I.GLASS:
			glass = rec
			break
	ok("стекло в списке после осмотра песка", not glass.is_empty())
	if glass.is_empty():
		panel.close()
		return
	var row: int = recipes.find(glass)
	var vis: int = row
	if row >= InventoryPanel.RECIPE_ROWS:
		panel.scroll = row
		vis = 0
	_panel_tap(panel._inspect_rect().get_center())   # снять защёлку
	_panel_tap(panel._inspect_rect().get_center())   # снова осмотр
	_panel_tap(panel._recipe_row_rect(vis).get_center())
	var tip: String = _joined(panel._tooltip_for(panel._inspect))
	ok("осмотр рецепта называет песок и стекло",
			tip.contains("Стекло") and tip.contains("Песок"), tip)
	_panel_tap(panel._recipe_row_rect(vis).get_center())
	await wait(0.2)
	ok("второй тап по рецепту кладёт стекло в инвентарь",
			player.inv.count_of(IDs.I.GLASS) == 1
			and player.inv.count_of(IDs.I.SAND) == 0,
			"стекло %d песок %d" % [player.inv.count_of(IDs.I.GLASS), player.inv.count_of(IDs.I.SAND)])
	_panel_tap(panel._close_rect().get_center())
	await wait(0.1)
	ok("закрыть убирает панель", not panel.visible)


## Перенос из сундука и закрытие в обеих раскладках телефона. Панель одна.
func _chest_both_layouts() -> void:
	var cell: Vector2i = _free_cell()
	if cell.x < 0 or not MachineBase.place_machine("Chest", cell):
		ok("сундук поставлен", false)
		return
	var chest: Chest = World.machines[cell]
	chest.slots[0].id = IDs.I.SCRAP
	chest.slots[0].count = 3
	player.global_position = World.cell_to_world(cell) + Vector2(20, 0)
	await wait(0.1)
	for pair in [[Vector2(1280, 720), "ландшафт"], [Vector2(720, 1280), "портрет"]]:
		UI.hud.size = pair[0]
		UI.hud._lay_sig = -1
		panel.open_chest(player, chest)
		await wait(0.05)
		var scrap0: int = player.inv.count_of(IDs.I.SCRAP)
		_panel_tap(panel._move_rect().get_center())
		_panel_tap(panel._chest_slot_rect(0).get_center())
		ok("перенос из сундука пальцем (%s)" % pair[1],
				player.inv.count_of(IDs.I.SCRAP) == scrap0 + 3 and chest.slots[0].is_empty(),
				"хлам %d" % player.inv.count_of(IDs.I.SCRAP))
		# Вернуть, чтобы вторая раскладка снова переносила.
		chest.slots[0].id = IDs.I.SCRAP
		chest.slots[0].count = 3
		player.inv.remove_id(IDs.I.SCRAP, 3)
		ok("закрыть достаётся в раскладке %s" % pair[1],
				panel._close_rect().has_area() and panel.visible)
		_panel_tap(panel._close_rect().get_center())
		ok("панель закрыта (%s)" % pair[1], not panel.visible)
	UI.hud.size = get_viewport().get_visible_rect().size / UI.ui_scale
	UI.hud._lay_sig = -1
	if is_instance_valid(chest):
		chest.dismantle()


func _free_cell() -> Vector2i:
	var origin: Vector2i = World.world_to_cell(player.global_position)
	for dy in range(-2, 1):
		for dx in range(1, 5):
			var c: Vector2i = origin + Vector2i(dx, dy)
			if player.can_place_at(c) and World.cell_to_world(c).distance_to(player.global_position) <= Player.REACH:
				return c
	return Vector2i(-1, -1)


func _clear_hotbar() -> void:
	for i in player.inv.hotbar_size:
		player.inv.slots[i].take(player.inv.slots[i].count)


func _index_of(id: int) -> int:
	for i in player.inv.size:
		if player.inv.slots[i].id == id and player.inv.slots[i].count > 0:
			return i
	return -1


func _move_id_to(id: int, dest: int) -> void:
	var src: int = _index_of(id)
	if src < 0 or src == dest:
		return
	var tmp: ItemStack = player.inv.slots[dest]
	player.inv.slots[dest] = player.inv.slots[src]
	player.inv.slots[src] = tmp


func _joined(lines: Array) -> String:
	var parts: PackedStringArray = []
	for l in lines:
		parts.append(String(l.get("t", "")))
	return " ".join(parts)


func _screen(world: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world


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


func _tap(index: int, pos: Vector2) -> void:
	_touch(index, pos, true)
	_touch(index, pos, false)


func _lift_all() -> void:
	for i in _down.keys():
		_touch(int(i), Vector2(_down[i]), false)


func _panel_tap(pos: Vector2) -> void:
	for pressed in [true, false]:
		var e: InputEventMouseButton = InputEventMouseButton.new()
		e.device = InputEvent.DEVICE_ID_EMULATION
		e.button_index = MOUSE_BUTTON_LEFT
		e.position = pos
		e.pressed = pressed
		panel._gui_input(e)
