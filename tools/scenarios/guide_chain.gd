extends ScenarioBase
## Цепочка новичка на ПК (C3, #317). Один ближайший шаг из факта мира.
## Первое волокно — по Game.game_time, без перемотки суток и без шахты.
## Сторона не зашита: каркас собирается и на восток, и на запад.


const CARD_FRAME: String = "Поставь каркас у лагеря"
const CARD_DOOR: String = "Поставь дверь"
const CARD_BED: String = "Поставь грядку"
const CARD_BEAM: String = "Подведи белый луч"
const CARD_FIBER: String = "Забери волокно"
const CARD_CHEST: String = "Поставь сундук у выхода"
const CARD_ROOM: String = "Закрой комнату дверью"
const PLATE_FRAME: String = "Поставь каркас: ПКМ панелью у лагеря"


func run() -> void:
	player.invuln = 1.0e9
	var hud: HUD = UI.hud
	ok("HUD на месте", hud != null)
	if hud == null:
		finish()
		return
	Game.help_hidden = false
	Game.guide_latch = 0
	# Сценарий не получает стартовые чертежи: этап 1 ждёт пустой список.
	# Крафт цепочки — тот же рецепт, что у новичка с набором.
	for name in ["COLLECTOR", "SPORE_BED"]:
		if not Game.blueprints.has(name):
			Game.blueprints.append(name)
	# Увести прицел от терминала лагеря: иначе плашка показывает его задание.
	player.global_position = World.cell_to_world(Game.base_mark_cell() + Vector2i(8, 1))
	player.vel = Vector2.ZERO
	aim(player.global_position + Vector2(40, 0))
	await _frames(hud, 3)
	ok("старт: карточка «Поставь каркас у лагеря»", hud.card_text == CARD_FRAME, "«%s»" % hud.card_text)
	ok("карточка не длиннее 6 слов", hud.card_text.split(" ", false).size() <= 6, hud.card_text)
	ok("плашка шага равна строке каркаса", hud.plate_text() == PLATE_FRAME, "«%s»" % hud.plate_text())
	var t0: float = Game.game_time
	var east: Vector2i = await _side(1)
	ok("восток: волокно без шахты", east.x >= 0, str(east))
	var elapsed: float = Game.game_time - t0
	ok("первое волокно за ≤ 120 с игрового времени", elapsed <= 120.0 and elapsed > 0.0,
			"%.1f с" % elapsed)
	_clear_side(east)
	Game.guide_latch = 0
	Game.guide_fiber = false
	Game.guide_lit = false
	hud._guide_work = null
	# Набор рассчитан на одну комнату и одно волокно. Запад — вторая сторона
	# того же набора, не вторая выдача: докладываем только то, что восток потратил.
	player.inv.add(IDs.I.COPPER_INGOT, 5)
	player.inv.add(IDs.I.GLASS, 1)
	player.inv.add(IDs.I.LOG, 2)
	await _frames(hud, 2)
	var west: Vector2i = await _side(-1)
	ok("запад: та же цепочка, сторона не зашита", west.x >= 0, str(west))
	_clear_side(west)
	finish()


func _side(sign: int) -> Vector2i:
	var hud: HUD = UI.hud
	var anchor: Vector2i = Game.base_mark_cell()
	var floor_y: int = anchor.y + 1
	var x0: int = anchor.x + sign * 4
	_air(x0 - 2, floor_y - 6, x0 + 6, floor_y + 1)
	# Открытое небо: коллектор молчит под крышей.
	for x in range(x0 - 1, x0 + 5):
		for y in range(0, floor_y):
			if World.in_bounds(x, y):
				World.set_tile(x, y, IDs.T.AIR)
	var frame: Vector2i = Vector2i(x0, floor_y - 2)
	ok("панель в руке", _select(IDs.I.PANEL))
	await _place(frame)
	ok("каркас встал", World.get_tile_v(frame) == IDs.T.ROOM_PANEL, str(frame))
	await _frames(hud, 2)
	ok("после каркаса карточка «Поставь дверь»", hud.card_text == CARD_DOOR, "«%s»" % hud.card_text)
	var door: Vector2i = Vector2i(x0 + sign, floor_y - 2)
	if not _select(IDs.I.DOOR):
		# Запад после востока: в наборе одна дверь, её уже поставили.
		player.inv.add(IDs.I.DOOR, 1)
	ok("дверь в руке", _select(IDs.I.DOOR))
	await _place(door)
	ok("дверь встала", World.get_tile_v(door) == IDs.T.DOOR or World.get_tile_v(door) == IDs.T.DOOR_OPEN,
			str(World.get_tile_v(door)))
	await _frames(hud, 2)
	ok("после двери карточка «Поставь грядку»", hud.card_text == CARD_BED, "«%s»" % hud.card_text)
	var bed_item: int = await _craft(IDs.I.SPORE_BED)
	ok("грядка скрафчена из набора", bed_item > 0)
	var bed_cell: Vector2i = Vector2i(x0 + sign * 2, floor_y - 1)
	World.set_tile(bed_cell.x, bed_cell.y, IDs.T.AIR)
	ok("грядка в руке", _select(IDs.I.SPORE_BED))
	await _place(bed_cell)
	var bed: SporeBed = World.machines.get(bed_cell) as SporeBed
	ok("грядка стоит", bed != null, str(bed_cell))
	if bed == null:
		return Vector2i(-1, -1)
	await _frames(hud, 2)
	ok("без луча карточка «Подведи белый луч»", hud.card_text == CARD_BEAM, "«%s»" % hud.card_text)
	var col_cell: Vector2i = Vector2i(x0 + sign * 2 - 3, floor_y - 1)
	if sign < 0:
		col_cell = Vector2i(bed_cell.x + 3, bed_cell.y)
	World.set_tile(col_cell.x, col_cell.y, IDs.T.AIR)
	var col_item: int = await _craft(IDs.I.COLLECTOR)
	ok("коллектор скрафчен из набора", col_item > 0)
	ok("коллектор в руке", _select(IDs.I.COLLECTOR))
	await _place(col_cell)
	var col: Collector = World.machines.get(col_cell) as Collector
	ok("коллектор стоит", col != null, str(col_cell))
	if col == null:
		return Vector2i(-1, -1)
	col.dir = 0 if sign > 0 else 2
	col._check_sky()
	_flush()
	await _frames(hud, 2)
	var fiber_card: bool = await wait_until(func() -> bool:
		return bed.lit and hud.card_text == "Дождись первого волокна", 1.5)
	ok("белый дошёл — карточка объясняет ожидание", fiber_card,
			"lit %s, «%s»" % [bed.lit, hud.card_text])
	var grew: bool = await wait_until(func() -> bool: return bed.tray >= 1, Balance.SPORE_BED_SECONDS + 2.0)
	ok("волокно вышло само", grew, "лоток %d" % bed.tray)
	ok("карточка ведёт к волокну до отбора", await wait_until(func() -> bool:
		return hud.card_text == CARD_FIBER, 1.5))
	_stand_on(bed_cell + Vector2i(0, 1))
	aim(bed.global_position)
	hold(KEY_E)
	await wait(0.12)
	release(KEY_E)
	await wait(0.2)
	ok("волокно в рюкзаке", player.inv.count_of(IDs.I.SPORE_FIBER) >= 1,
			str(player.inv.count_of(IDs.I.SPORE_FIBER)))
	ok("первый урожай открыл рецепт пресса", DB.recipe_unlocked(DB.find_recipe_for(IDs.I.PRESS), player))
	await _frames(hud, 2)
	ok("после волокна карточка «Поставь сундук у выхода»", hud.card_text == CARD_CHEST,
			"«%s»" % hud.card_text)
	var chest_cell: Vector2i = bed_cell + bed.out_dir()
	World.set_tile(chest_cell.x, chest_cell.y, IDs.T.AIR)
	ok("сундук скрафчен из остатка стартового набора", await _craft(IDs.I.CHEST) == 1)
	ok("сундук в руке", _select(IDs.I.CHEST))
	await _place(chest_cell)
	ok("сундук поставлен у выхода", World.machines.get(chest_cell) is Chest, str(chest_cell))
	await _frames(hud, 2)
	var room_card: bool = await wait_until(func() -> bool: return hud.card_text == CARD_ROOM, 1.5)
	ok("после сундука карточка «Закрой комнату дверью»", room_card, "«%s»" % hud.card_text)
	await _close_room(bed_cell)
	var closed: bool = await wait_until(func() -> bool:
		return hud.card_text != CARD_ROOM and hud.guide_step >= 8, 1.5)
	ok("комната закрыта — шаг цепочки погас", closed,
			"«%s» шаг %d" % [hud.card_text, hud.guide_step])
	return bed_cell


func _close_room(bed: Vector2i) -> void:
	var painted: int = 0
	for dy in range(-3, 1):
		for dx in range(-3, 4):
			if painted >= 6:
				return
			var c: Vector2i = bed + Vector2i(dx, dy)
			if not World.in_bounds(c.x, c.y):
				continue
			if World.get_tile_v(c) != IDs.T.AIR:
				continue
			if World.machines.has(c):
				continue
			World.set_tile(c.x, c.y, IDs.T.ROOM_PANEL)
			painted += 1


func _craft(item: int) -> int:
	var before: int = player.inv.count_of(item)
	var rec: Dictionary = {}
	for r in DB.recipes_for("hand"):
		if int(r["out"]) == item:
			rec = r
			break
	if rec.is_empty():
		return 0
	UI.panel._craft(rec)
	await wait(0.2)
	return player.inv.count_of(item) - before


func _place(c: Vector2i) -> void:
	_stand_on(c + Vector2i(2, 1))
	aim(World.cell_to_world(c))
	press_mouse(MOUSE_BUTTON_RIGHT)
	await wait(0.3)
	release_mouse(MOUSE_BUTTON_RIGHT)
	await wait(0.1)


func _select(item: int) -> bool:
	for i in player.inv.slots.size():
		if player.inv.slots[i].id == item and player.inv.slots[i].count > 0:
			player.inv.selected = i
			return true
	return false


func _stand_on(c: Vector2i) -> void:
	if World.in_bounds(c.x, c.y + 1) and not World.is_solid_cell(c + Vector2i(0, 1)):
		World.set_tile(c.x, c.y + 1, IDs.T.STONE)
	player.global_position = Vector2(float(c.x * World.TILE) + 8.0, float((c.y + 1) * World.TILE) - 11.0)
	player.vel = Vector2.ZERO


func _air(x0: int, y0: int, x1: int, y1: int) -> void:
	for x in range(mini(x0, x1), maxi(x0, x1) + 1):
		for y in range(mini(y0, y1), maxi(y0, y1) + 1):
			if World.in_bounds(x, y):
				World.set_tile(x, y, IDs.T.AIR)


func _clear_side(bed: Vector2i) -> void:
	if bed.x < 0:
		return
	var gone: Array = []
	for m in World.machines.values():
		if m == null or not is_instance_valid(m):
			continue
		var c: Vector2i = m.cell if m.get("cell") != null else World.world_to_cell(m.global_position)
		if absi(c.x - bed.x) <= 8 and absi(c.y - bed.y) <= 6:
			gone.append(m)
	for m in gone:
		if m.has_method("dismantle"):
			m.dismantle()
	for dy in range(-6, 5):
		for dx in range(-8, 9):
			var c: Vector2i = bed + Vector2i(dx, dy)
			if World.in_bounds(c.x, c.y):
				var id: int = World.get_tile_v(c)
				if id == IDs.T.ROOM_PANEL or id == IDs.T.DOOR or id == IDs.T.DOOR_OPEN:
					World.set_tile(c.x, c.y, IDs.T.AIR)


func _flush() -> void:
	if World.beams != null:
		World.beams.note_machines()
		World.beams.rebuild()


func _frames(hud: HUD, n: int) -> void:
	var f0: int = hud.stat_frames
	await wait_until(func() -> bool: return hud.stat_frames >= f0 + n, 5.0)
