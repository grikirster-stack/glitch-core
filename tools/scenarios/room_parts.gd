extends ScenarioBase
## Каркас пристройки (ADR-006 § 3.1, #312).
##
## На main до правки падает: панели не ставятся, двери нет, обшивки нет,
## причины отказа пустые, шлюз не открывается как дверь игрока.
##
## Равный набор собирает открытый навес и закрытую пристройку с другим входом.
## Перестановка стены и двери меняет проход и луч. Обшивка меняет вид, не луч.
## Save и снимок LAN возвращают оба состояния двери и фон. Фабричный шлюз
## старого файла становится камнем. Серия правок одного прохода меряется
## по кадрам и идёт через set_tile / _solid_tbl.


const SLOT: String = "room_parts"

var _plot_floor: int = 0


func run() -> void:
	player.invuln = 1.0e9
	var origin: Vector2i = Vector2i(40, 30)
	_plot_floor = origin.y + 4
	_clear(origin + Vector2i(-2, -6), origin + Vector2i(18, 8))
	_floor(origin)
	stand_at_cell(origin + Vector2i(0, 2))
	await await_frame()
	_kit()
	await _denials(origin)
	await _factory_gateway(origin)
	_kit()
	await _canopy(origin)
	_refund_all(origin)
	await _annex(origin)
	await _sheath(origin)
	await _save_roundtrip(origin)
	await _join_snapshot(origin)
	await _burst(origin + Vector2i(12, 0))
	finish()


func _kit() -> void:
	for i in player.inv.slots.size():
		player.inv.slots[i] = ItemStack.new()
	player.inv.add(IDs.I.PANEL, Balance.ROOM_KIT_PANELS)
	player.inv.add(IDs.I.DOOR, Balance.ROOM_KIT_DOORS)
	player.inv.add(IDs.I.SHEATH, Balance.ROOM_KIT_SHEATH)
	player.inv.add(IDs.I.COAL, 4)
	ok("стартовый набор: панели, дверь, обшивка",
			player.inv.count_of(IDs.I.PANEL) == Balance.ROOM_KIT_PANELS
			and player.inv.count_of(IDs.I.DOOR) == Balance.ROOM_KIT_DOORS
			and player.inv.count_of(IDs.I.SHEATH) == Balance.ROOM_KIT_SHEATH)


func _denials(origin: Vector2i) -> void:
	_select(IDs.I.PANEL)
	# Далеко: герой на полу площадки, курсор за REACH (5.6 клетки).
	_stand_on(origin + Vector2i(0, 2))
	var far: Vector2i = origin + Vector2i(8, 2)
	aim(World.cell_to_world(far))
	press_mouse(MOUSE_BUTTON_RIGHT)
	await wait(0.3)
	release_mouse(MOUSE_BUTTON_RIGHT)
	await wait(0.1)
	ok("далеко — «Далеко»", _last_note() == Player.DENY_FAR, _last_note())
	# Занято: камень над полом, герой стоит в соседней клетке того же ряда.
	var busy: Vector2i = origin + Vector2i(2, 2)
	World.set_tile(busy.x, busy.y, IDs.T.STONE)
	_stand_on(busy + Vector2i(1, 0))
	aim(World.cell_to_world(busy))
	press_mouse(MOUSE_BUTTON_RIGHT)
	await wait(0.3)
	release_mouse(MOUSE_BUTTON_RIGHT)
	await wait(0.1)
	ok("камень — «Занято»", _last_note() == Player.DENY_BUSY, _last_note())
	World.set_tile(busy.x, busy.y, IDs.T.AIR)
	# Пересечение: курсор в клетке корпуса. Пол под ногами — не эта клетка.
	var feet: Vector2i = World.world_to_cell(player.global_position)
	aim(World.cell_to_world(feet))
	press_mouse(MOUSE_BUTTON_RIGHT)
	await wait(0.3)
	release_mouse(MOUSE_BUTTON_RIGHT)
	await wait(0.1)
	ok("клетка героя — «Пересекается с героем»", _last_note() == Player.DENY_HERO, _last_note())
	ok("отказ не потратил панель", player.inv.count_of(IDs.I.PANEL) == Balance.ROOM_KIT_PANELS)


## Открытый навес: крыша и бока, вход с юга, луч с востока проходит внутрь.
func _canopy(origin: Vector2i) -> void:
	var roof: Array[Vector2i] = [
		origin + Vector2i(1, -1), origin + Vector2i(2, -1), origin + Vector2i(3, -1),
	]
	var walls: Array[Vector2i] = [
		origin + Vector2i(1, 0), origin + Vector2i(1, 1),
		origin + Vector2i(3, 0), origin + Vector2i(3, 1),
	]
	for c in roof:
		ok("крыша навеса %s" % str(c), await _place_panel(c))
	for c in walls:
		ok("стена навеса %s" % str(c), await _place_panel(c))
	var door: Vector2i = origin + Vector2i(2, 2)
	ok("дверь навеса с юга", await _place_door(door))
	var inside: Vector2i = origin + Vector2i(2, 0)
	ok("под навесом воздух", World.get_tile_v(inside) == IDs.T.AIR)
	ok("закрытая дверь — стена", World.is_solid_cell(door) and World.rect_solid(_cell_rect(door)))
	var lamp: Vector2i = origin + Vector2i(6, 1)
	var east_wall: Vector2i = origin + Vector2i(3, 1)
	_lamp(lamp, 2)
	_rebuild_beams()
	var blocked: bool = _beam_stops(east_wall)
	ok("закрытая дверь гасит луч", blocked and World.beams.color_at(inside) == 0,
			"обрыв %s, внутри %d" % [blocked, World.beams.color_at(inside)])
	_gone_lamp(lamp)
	# Намеренный проём: дверь открыта, луч с юга идёт сквозь неё в навес.
	await _open_door(door)
	var south_lamp: Vector2i = origin + Vector2i(2, 4)
	_lamp(south_lamp, 3)
	_rebuild_beams()
	ok("открытая дверь — не стена", not World.is_solid_cell(door))
	ok("луч через открытую дверь", World.beams.color_at(door) != 0 and World.beams.color_at(inside) != 0,
			"дверь %d, внутри %d" % [World.beams.color_at(door), World.beams.color_at(inside)])
	_gone_lamp(south_lamp)
	var left_panels: int = 0
	var left_doors: int = 0
	for x in range(origin.x - 2, origin.x + 16):
		for y in range(origin.y - 6, origin.y + 8):
			var id: int = World.get_tile(x, y)
			if id == IDs.T.ROOM_PANEL:
				left_panels += 1
			elif id == IDs.T.DOOR or id == IDs.T.DOOR_OPEN:
				left_doors += 1
	var drop_p: int = 0
	var drop_d: int = 0
	for e in _drops():
		if e.item_id == IDs.I.PANEL:
			drop_p += e.count
		elif e.item_id == IDs.I.DOOR:
			drop_d += e.count
	_collect_drops()


## Закрытая пристройка из того же числа панелей: вход с востока, не с юга.
func _annex(origin: Vector2i) -> void:
	var before: int = player.inv.count_of(IDs.I.PANEL)
	ok("после снятия навеса панели вернулись", before == Balance.ROOM_KIT_PANELS, str(before))
	# Южная стена сплошная — вход прошлого силуэта закрыт панелью.
	var south: Array[Vector2i] = [
		origin + Vector2i(1, 2), origin + Vector2i(2, 2), origin + Vector2i(3, 2),
	]
	var ring: Array[Vector2i] = [
		origin + Vector2i(1, -1), origin + Vector2i(2, -1), origin + Vector2i(3, -1),
		origin + Vector2i(1, 0), origin + Vector2i(1, 1),
		origin + Vector2i(3, 0), origin + Vector2i(3, 1),
	]
	for c in south:
		ok("южная стена %s" % str(c), await _place_panel(c))
	for c in ring:
		ok("кольцо %s" % str(c), await _place_panel(c))
	var door: Vector2i = origin + Vector2i(4, 0)
	ok("дверь пристройки с востока", await _place_door(door))
	ok("другой вход: юг закрыт панелью, восток — дверью",
			World.get_tile_v(origin + Vector2i(2, 2)) == IDs.T.ROOM_PANEL
			and World.get_tile_v(door) == IDs.T.DOOR)
	var inside: Vector2i = origin + Vector2i(2, 0)
	var lamp: Vector2i = origin + Vector2i(7, 1)
	_lamp(lamp, 2)
	_rebuild_beams()
	ok("закрытая пристройка: луч встал в дверь", _beam_stops(origin + Vector2i(3, 1)) and World.beams.color_at(inside) == 0)
	# Перестановка: дверь на юг, восток — панель. Проход и луч меняются.
	_mine(door)
	var south_door: Vector2i = origin + Vector2i(2, 2)
	_mine(south_door)
	_collect_drops()
	var moved: bool = await _place_door(south_door)
	ok("дверь переехала на юг", moved)
	ok("восток закрыт панелью", await _place_panel(door))
	_rebuild_beams()
	var east_open: bool = World.beams.color_at(origin + Vector2i(3, 1)) != 0
	ok("после перестановки восток глух", World.is_solid_cell(door) and not east_open)
	await _open_door(south_door)
	_gone_lamp(lamp)
	var south_lamp: Vector2i = origin + Vector2i(2, 4)
	_lamp(south_lamp, 3)
	_rebuild_beams()
	ok("после перестановки луч входит с юга",
			not World.is_solid_cell(south_door) and World.beams.color_at(inside) != 0,
			"внутри %d" % World.beams.color_at(inside))
	_gone_lamp(south_lamp)
	# Вернуть закрытую дверь на восток. Клик стоит на две клетки в стороне
	# и до двери не достаёт — закрываем тем же set_tile, которым её ставили.
	_mine(south_door)
	World.set_tile(south_door.x, south_door.y, IDs.T.AIR)
	await _place_panel(south_door)
	_mine(door)
	_collect_drops()
	if World.get_tile_v(door) != IDs.T.DOOR:
		World.set_tile(door.x, door.y, IDs.T.DOOR)
		player.inv.remove_id(IDs.I.DOOR, 1)


func _sheath(origin: Vector2i) -> void:
	var inside: Vector2i = origin + Vector2i(2, 0)
	var before: Vector2i = World.tilemap.get_cell_atlas_coords(inside)
	ok("обшивка легла", await _place_sheath(inside))
	ok("обшивка не стена и не тайл", not World.is_solid_cell(inside)
			and World.get_tile_v(inside) == IDs.T.AIR
			and World.sheath_at(inside) == World.SHEATH_BACK)
	var painted: bool = World.sheathmap != null and World.sheathmap.get_cell_atlas_coords(inside).x >= 0
	ok("обшивка меняет вид, тайл воздуха тот же", painted
			and World.tilemap.get_cell_atlas_coords(inside) == before)
	# Дверь закрыта с востока. Открываем и светим с юга — обшивка луч не гасит.
	# Южная клетка после возврата двери — панель; для луча нужен воздух.
	var door: Vector2i = origin + Vector2i(4, 0)
	var south: Vector2i = origin + Vector2i(2, 2)
	if World.get_tile_v(door) != IDs.T.DOOR:
		World.set_tile(door.x, door.y, IDs.T.DOOR)
	if World.get_tile_v(south) == IDs.T.ROOM_PANEL:
		World.set_tile(south.x, south.y, IDs.T.AIR)
	await _open_door(door)
	var lamp: Vector2i = origin + Vector2i(2, 4)
	_lamp(lamp, 3)
	_rebuild_beams()
	ok("луч сквозь обшивку", World.beams.color_at(inside) != 0,
			"внутри %d" % World.beams.color_at(inside))
	_gone_lamp(lamp)
	# Вернуть южную панель: снимок закрытой пристройки без проёма снизу.
	if World.get_tile_v(south) == IDs.T.AIR:
		World.set_tile(south.x, south.y, IDs.T.ROOM_PANEL)
	var had: int = player.inv.count_of(IDs.I.SHEATH)
	await _mine_sheath(inside)
	var got: int = player.inv.count_of(IDs.I.SHEATH)
	ok("обшивка снимается в инвентарь", World.sheath_at(inside) == World.SHEATH_NONE
			and got == had + 1, "слой %d, было %d, стало %d" % [World.sheath_at(inside), had, got])
	await _place_sheath(inside)


func _save_roundtrip(origin: Vector2i) -> void:
	var door: Vector2i = origin + Vector2i(4, 0)
	# Открытую кладём далеко: E берёт ближайшую дверь в 40 px и иначе откроет восточную.
	var open_at: Vector2i = origin + Vector2i(10, 1)
	World.set_tile(open_at.x, open_at.y, IDs.T.AIR)
	if player.inv.count_of(IDs.I.DOOR) <= 0:
		player.inv.add(IDs.I.DOOR, 1)
	await _place_door(open_at)
	await _open_door(open_at)
	if World.get_tile_v(door) != IDs.T.DOOR:
		World.set_tile(door.x, door.y, IDs.T.DOOR)
	var sheath_at: Vector2i = origin + Vector2i(2, 0)
	var closed_solid: bool = World.is_solid_cell(door)
	var open_pass: bool = not World.is_solid_cell(open_at)
	Save.remove(SLOT)
	ok("сейв комнаты", Save.save_game(SLOT))
	# Снести, чтобы загрузка отличалась от текущего кадра.
	_mine(door)
	_mine(open_at)
	World.set_sheath(sheath_at, World.SHEATH_NONE)
	ok("загрузка комнаты", Save.load_game(SLOT))
	ok("закрытая дверь восстановилась стеной", World.get_tile_v(door) == IDs.T.DOOR
			and World.is_solid_cell(door) == closed_solid)
	ok("открытая дверь восстановилась проходом", World.get_tile_v(open_at) == IDs.T.DOOR_OPEN
			and (not World.is_solid_cell(open_at)) == open_pass,
			"тайл %d" % World.get_tile_v(open_at))
	ok("обшивка восстановилась", World.sheath_at(sheath_at) == World.SHEATH_BACK)
	var lamp: Vector2i = origin + Vector2i(7, 1)
	_lamp(lamp, 2)
	_rebuild_beams()
	ok("после загрузки закрытая дверь снова гасит луч", _beam_stops(origin + Vector2i(3, 1)))
	_gone_lamp(lamp)
	Save.remove(SLOT)
	_mine(open_at)


func _join_snapshot(origin: Vector2i) -> void:
	var door: Vector2i = origin + Vector2i(4, 0)
	var sheath_at: Vector2i = origin + Vector2i(2, 0)
	var snap: Dictionary = Save.gather_join()
	World.set_tile(door.x, door.y, IDs.T.AIR)
	World.set_sheath(sheath_at, World.SHEATH_NONE)
	ok("снимок LAN лёг", Save.apply_join(snap), Save.last_error)
	ok("снимок вернул закрытую дверь", World.get_tile_v(door) == IDs.T.DOOR and World.is_solid_cell(door))
	ok("снимок вернул обшивку", World.sheath_at(sheath_at) == World.SHEATH_BACK)
	# Открытая дверь в том же снимке: пересобрать и применить ещё раз.
	World.set_tile(door.x, door.y, IDs.T.DOOR_OPEN)
	var open_snap: Dictionary = Save.gather_join()
	World.set_tile(door.x, door.y, IDs.T.DOOR)
	ok("снимок открытой двери", Save.apply_join(open_snap))
	ok("снимок вернул проход", World.get_tile_v(door) == IDs.T.DOOR_OPEN and not World.is_solid_cell(door))
	World.set_tile(door.x, door.y, IDs.T.DOOR)


func _factory_gateway(origin: Vector2i) -> void:
	var d: Dictionary = Save.gather()
	var machines: Array = d.get("machines", [])
	machines.append({"kind": "CoalGen", "cell": Vector2i(8, 8), "hp": 40.0})
	d["machines"] = machines
	var wd: Dictionary = d["world"]
	var tiles: PackedByteArray = wd["tiles"]
	var closed: Vector2i = origin + Vector2i(0, 5)
	var opened: Vector2i = origin + Vector2i(1, 5)
	tiles[closed.y * World.W + closed.x] = IDs.T.AIRLOCK
	tiles[opened.y * World.W + opened.x] = IDs.T.AIRLOCK_OPEN
	wd["tiles"] = tiles
	var pd: Dictionary = d["player"]
	var slots: Array = Array(pd.get("inv", [])).duplicate(true)
	var planted: bool = false
	for i in slots.size():
		var e = slots[i]
		if e is Array and e.size() >= 2 and int(e[1]) <= 0:
			slots[i] = [IDs.I.AIRLOCK, 1]
			planted = true
			break
	if not planted and not slots.is_empty():
		slots[0] = [IDs.I.AIRLOCK, 1]
	pd["inv"] = slots
	var path: String = Save.path_for(SLOT + "_factory")
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(Save.encode(d))
	f.close()
	ok("старый фабричный файл читается", Save.load_game(SLOT + "_factory"), Save.last_error)
	ok("исторический шлюз стал камнем",
			World.get_tile_v(closed) == IDs.T.STONE and World.get_tile_v(opened) == IDs.T.STONE,
			"%d / %d" % [World.get_tile_v(closed), World.get_tile_v(opened)])
	ok("предмет шлюза конвертирован", player.inv.count_of(IDs.I.AIRLOCK) == 0)
	var iron_n: int = _count_world(IDs.I.IRON_INGOT)
	var coal_n: int = _count_world(IDs.I.COAL)
	ok("конверсия шлюза дала железо и уголь", iron_n >= 4 and coal_n >= 2, "%d / %d" % [iron_n, coal_n])
	Save.remove(SLOT + "_factory")


## Серия правок одного прохода: кадры и мкс. До фичи тот же путь set_tile
## на камне; после — панель и дверь идут им же, луч помечается dirty.
func _burst(origin: Vector2i) -> void:
	_clear(origin + Vector2i(-2, -2), origin + Vector2i(12, 4))
	var cells: Array[Vector2i] = []
	for i in 8:
		cells.append(origin + Vector2i(i, 0))
	# Горелка слева от ряда, луч вправо: обрыв «wall» есть только если луч реально идёт.
	var lamp: Vector2i = origin + Vector2i(-1, 0)
	_lamp(lamp, 0)
	_rebuild_beams()
	var stone_us: int = _stamp(cells, IDs.T.STONE)
	var stone_frames: int = await _frames_until_clean()
	ok("камень серии — стена луча", _beam_stops(cells[0]))
	for c in cells:
		World.set_tile(c.x, c.y, IDs.T.AIR)
	await _frames_until_clean()
	var panel_us: int = _stamp(cells, IDs.T.ROOM_PANEL)
	var panel_frames: int = await _frames_until_clean()
	ok("панель серии — стена, как камень", World.is_solid_cell(cells[0]) and _beam_stops(cells[0]))
	var door_us: int = 0
	var t0: int = Time.get_ticks_usec()
	World.set_tile(cells[0].x, cells[0].y, IDs.T.DOOR)
	World.set_tile(cells[0].x, cells[0].y, IDs.T.DOOR_OPEN)
	World.set_tile(cells[0].x, cells[0].y, IDs.T.DOOR)
	door_us = Time.get_ticks_usec() - t0
	var door_frames: int = await _frames_until_clean()
	ok("дверь серии закрылась стеной", World.is_solid_cell(cells[0]) and _beam_stops(cells[0]))
	World.set_tile(cells[0].x, cells[0].y, IDs.T.DOOR_OPEN)
	for i in range(1, cells.size()):
		World.set_tile(cells[i].x, cells[i].y, IDs.T.AIR)
	_rebuild_beams()
	ok("дверь серии открылась — луч прошёл", not World.is_solid_cell(cells[0])
			and not _beam_stops(cells[0]) and World.beams.color_at(cells[1]) != 0,
			"цвет %d" % World.beams.color_at(cells[1]))
	_gone_lamp(lamp)
	print("[замер] room_parts серия 8 клеток: камень %d мкс / %d кадров, панель %d мкс / %d кадров, дверь×3 %d мкс / %d кадров" % [
			stone_us, stone_frames, panel_us, panel_frames, door_us, door_frames])
	ok("серия уложилась в кадры, не в новый трассировщик",
			stone_frames <= 3 and panel_frames <= 3 and door_frames <= 3,
			"кадры %d/%d/%d" % [stone_frames, panel_frames, door_frames])
	for c in cells:
		World.set_tile(c.x, c.y, IDs.T.AIR)


func _stamp(cells: Array[Vector2i], id: int) -> int:
	var t0: int = Time.get_ticks_usec()
	for c in cells:
		World.set_tile(c.x, c.y, id)
	return Time.get_ticks_usec() - t0


func _rebuild_beams() -> void:
	World.beams._sig = -1
	World.beams.rebuild()


func _frames_until_clean() -> int:
	var n: int = 0
	while World.beams.dirty and n < 8:
		await await_frame()
		n += 1
	if World.beams.dirty:
		_rebuild_beams()
	return n


## Постановка через ПКМ. Вызывать только с await: внутри кадры ввода.
func _place_panel(c: Vector2i) -> bool:
	var ok_press: bool = await _press_place(c, IDs.I.PANEL)
	return ok_press and World.get_tile_v(c) == IDs.T.ROOM_PANEL


func _place_door(c: Vector2i) -> bool:
	var ok_press: bool = await _press_place(c, IDs.I.DOOR)
	return ok_press and World.get_tile_v(c) == IDs.T.DOOR


func _place_sheath(c: Vector2i) -> bool:
	var ok_press: bool = await _press_place(c, IDs.I.SHEATH)
	return ok_press and World.sheath_at(c) == World.SHEATH_BACK


func _press_place(c: Vector2i, item: int) -> bool:
	if not _select(item):
		return false
	# Сбоку от цели: корпус 22 px не влезает в клетку над головой, а соседняя — в REACH.
	_stand_on(c + Vector2i(2, 1))
	aim(World.cell_to_world(c))
	press_mouse(MOUSE_BUTTON_RIGHT)
	await wait(0.3)
	release_mouse(MOUSE_BUTTON_RIGHT)
	await wait(0.1)
	return true


func _open_door(c: Vector2i) -> void:
	_stand_beside(c)
	player.building_cell = c
	aim(World.cell_to_world(c))
	hold(KEY_E)
	await wait(0.3)
	release(KEY_E)
	await wait(0.1)
	var tg: Dictionary = player.interact_target()
	_restore_stand_floor()


func _mine(c: Vector2i) -> void:
	player._break_tile(c)


func _mine_sheath(c: Vector2i) -> void:
	# Сбоку, не под панелью: луч копки из центра клетки героя не должен встретить стену.
	var stand: Vector2i = c + Vector2i(1, 0)
	if World.get_tile_v(stand) != IDs.T.AIR:
		stand = c + Vector2i(-1, 0)
	var floor: Vector2i = stand + Vector2i(0, 1)
	var floor_was: int = World.get_tile_v(floor)
	if floor_was == IDs.T.AIR:
		World.set_tile(floor.x, floor.y, IDs.T.STONE)
	stand_at_cell(stand)
	player.vel = Vector2.ZERO
	player.on_ground = true
	aim(World.cell_to_world(c))
	player.inv.selected = _empty_hotbar()
	# Тот же путь, что ЛКМ пустой рукой по воздуху: снять фон и уронить предмет.
	player._break_sheath(c)
	_collect_drops()
	if floor_was == IDs.T.AIR:
		World.set_tile(floor.x, floor.y, IDs.T.AIR)


func _empty_hotbar() -> int:
	for i in 8:
		if player.inv.slots[i].is_empty():
			return i
	return 0


func _select(item: int) -> bool:
	for i in player.inv.slots.size():
		if player.inv.slots[i].id == item and player.inv.slots[i].count > 0:
			player.inv.selected = i
			return true
	return false


func _lamp(cell: Vector2i, dir: int) -> void:
	World.set_tile(cell.x, cell.y, IDs.T.AIR)
	if not MachineBase.place_machine("Burner", cell):
		return
	var b: Burner = World.machines[cell]
	b.dir = dir & 7
	World.beams.note_machines()
	b.add_fuel(IDs.I.COAL, 1)
	var step: Vector2i = Beams.DIR[dir & 7]
	var bits: PackedStringArray = PackedStringArray()
	for k in 8:
		var c: Vector2i = cell + step * k
		bits.append("%s:%d" % [str(c), World.get_tile_v(c)])
	World.beams._sig = -1
	_rebuild_beams()
	var us: int = World.beams.last_rebuild_us
	var lit: PackedStringArray = PackedStringArray()
	for k in range(1, 6):
		var c: Vector2i = cell + step * k
		lit.append("%d" % World.beams.color_at(c))


func _gone_lamp(cell: Vector2i) -> void:
	var b = World.machines.get(cell)
	if b != null and is_instance_valid(b):
		World.machines.erase(cell)
		b.queue_free()
	World.beams.note_machines()


func _beam_stops(wall: Vector2i) -> bool:
	for p in World.beams.break_points:
		if p.get("cell") == wall and str(p.get("reason")) == "wall":
			return true
	return false


func _cell_rect(c: Vector2i) -> Rect2:
	return Rect2(Vector2(c * World.TILE) + Vector2(1, 1), Vector2(World.TILE - 2, World.TILE - 2))


func _refund_all(origin: Vector2i) -> void:
	var removed: int = 0
	for x in range(origin.x - 2, origin.x + 16):
		for y in range(origin.y - 6, origin.y + 8):
			var id: int = World.get_tile(x, y)
			if id == IDs.T.ROOM_PANEL:
				World.set_tile(x, y, IDs.T.AIR)
				player.inv.add(IDs.I.PANEL, 1)
				removed += 1
			elif id == IDs.T.DOOR or id == IDs.T.DOOR_OPEN:
				World.set_tile(x, y, IDs.T.AIR)
				player.inv.add(IDs.I.DOOR, 1)
				removed += 1
			if World.sheath_at(Vector2i(x, y)) != World.SHEATH_NONE:
				World.set_sheath(Vector2i(x, y), World.SHEATH_NONE)
				player.inv.add(IDs.I.SHEATH, 1)



func _count_world(id: int) -> int:
	var n: int = player.inv.count_of(id)
	for c in World.machines.values():
		if c is Chest:
			for slot in c.slots:
				if slot.id == id:
					n += slot.count
	for e in _drops():
		if e.item_id == id:
			n += e.count
	return n


func _collect_drops() -> void:
	for e in _drops():
		if e.item_id == IDs.I.PANEL or e.item_id == IDs.I.DOOR or e.item_id == IDs.I.SHEATH:
			player.inv.add(e.item_id, e.count)
			e.queue_free()


func _drops() -> Array:
	var out: Array = []
	var host: Node = World.get_tree().current_scene if World.get_tree() != null else null
	if host == null:
		host = World
	for c in host.get_children():
		if c is ItemEntity:
			out.append(c)
	return out


func _clear(a: Vector2i, b: Vector2i) -> void:
	for x in range(a.x, b.x):
		for y in range(a.y, b.y):
			if World.in_bounds(x, y) and World.get_tile(x, y) != IDs.T.AIR:
				World.set_tile(x, y, IDs.T.AIR)
			if World.in_bounds(x, y):
				World.set_sheath(Vector2i(x, y), World.SHEATH_NONE)


## Пол под площадкой. Без него герой падает за кадр ввода и любой клик — «Далеко».
func _floor(origin: Vector2i) -> void:
	for x in range(origin.x - 2, origin.x + 18):
		World.set_tile(x, origin.y + 4, IDs.T.STONE)


## Встать на пол площадки (origin.y+3), не кладя камень в клетку постройки.
## Скорость нулевая — кадр физики не уносит.
## Встать на пол площадки под целью по X. Камень в клетку постройки не кладём.
## В одной клетке от двери: E берёт цель только в 40 px. Пол временный и снимается.
func _stand_beside(cell: Vector2i) -> void:
	var stand: Vector2i = cell + Vector2i(-1, 0)
	if World.get_tile_v(stand) != IDs.T.AIR:
		stand = cell + Vector2i(1, 0)
	if World.get_tile_v(stand) != IDs.T.AIR:
		stand = cell + Vector2i(0, -1)
	var floor: Vector2i = stand + Vector2i(0, 1)
	var floor_was: int = World.get_tile_v(floor)
	if floor_was == IDs.T.AIR:
		World.set_tile(floor.x, floor.y, IDs.T.STONE)
	stand_at_cell(stand)
	player.vel = Vector2.ZERO
	player.on_ground = true
	player.set_meta("room_stand_floor", floor)
	player.set_meta("room_stand_was", floor_was)


func _restore_stand_floor() -> void:
	if not player.has_meta("room_stand_floor"):
		return
	var floor: Vector2i = player.get_meta("room_stand_floor")
	var was: int = int(player.get_meta("room_stand_was"))
	if was == IDs.T.AIR and World.get_tile_v(floor) == IDs.T.STONE:
		World.set_tile(floor.x, floor.y, IDs.T.AIR)
	player.remove_meta("room_stand_floor")
	player.remove_meta("room_stand_was")


func _stand_on(cell: Vector2i) -> void:
	var stand: Vector2i = Vector2i(cell.x, _plot_floor - 1)
	if World.get_tile_v(Vector2i(stand.x, _plot_floor)) == IDs.T.AIR:
		World.set_tile(stand.x, _plot_floor, IDs.T.STONE)
	stand_at_cell(stand)
	player.vel = Vector2.ZERO
	player.on_ground = true


func _last_note() -> String:
	var hud: Node = UI.hud
	if hud == null:
		return ""
	var notes: Array = hud.get("notes")
	if notes.is_empty():
		return ""
	return str(notes[notes.size() - 1].get("text", ""))
