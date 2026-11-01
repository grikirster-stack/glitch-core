class_name InventoryPanel
extends Control
## Экран инвентаря: сетка предметов, крафт (ручной / плавильня / сборщик) и сундуки.

const SLOT: int = 38
const INV_COLS: int = 9
const CHEST_COLS: int = 6
const RECIPE_H: int = 46

var player = null    ## Игрок (без типа — во избежание цикла зависимостей).
var chest = null     ## Открытый сундук.
var held: ItemStack = ItemStack.new()
var station_tab: int = 0            ## 0 — ручной, 1 — плавильня, 2 — сборщик
var scroll: int = 0
var hover: int = -1

const TABS: Array = ["Ручной крафт", "Плавильня", "Сборщик"]
const STATIONS: Array = ["hand", "smelter", "assembler"]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func open(p: Player) -> void:
	player = p
	chest = null
	visible = true
	held = ItemStack.new()
	queue_redraw()


func open_chest(p: Player, c: Chest) -> void:
	player = p
	chest = c
	visible = true
	held = ItemStack.new()
	queue_redraw()


func close() -> void:
	visible = false
	chest = null
	if not held.is_empty():
		if player:
			player.inv.add(held.id, held.count)
		held = ItemStack.new()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			scroll = maxi(0, scroll - 1)
			queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			scroll += 1
			queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_click(_local(mb.position), false)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_click(_local(mb.position), true)
	elif event is InputEventMouseMotion:
		queue_redraw()


func _local(p: Vector2) -> Vector2:
	return p - Vector2((size.x - 820.0) * 0.5, (size.y - 470.0) * 0.5)


func _panel_pos() -> Vector2:
	return Vector2((size.x - 820.0) * 0.5, (size.y - 470.0) * 0.5)


func _draw() -> void:
	if player == null:
		return
	var origin: Vector2 = _panel_pos()
	draw_rect(Rect2(origin, Vector2(820, 470)), Color(0.06, 0.07, 0.10, 0.94))
	draw_rect(Rect2(origin, Vector2(820, 470)), Color(0.35, 0.55, 0.75, 0.8), false, 2.0)
	var font: Font = ThemeDB.fallback_font

	draw_string(font, origin + Vector2(16, 26), "ИНВЕНТАРЬ И КРАФТ", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.85, 0.93, 1.0))

	# ---- Вкладки -------------------------------------------------------------
	for i in TABS.size():
		var r: Rect2 = Rect2(origin + Vector2(16 + i * 170, 38), Vector2(164, 30))
		var active: bool = (station_tab == i)
		draw_rect(r, Color(0.16, 0.24, 0.34) if active else Color(0.10, 0.12, 0.16))
		draw_rect(r, Color(0.4, 0.8, 1.0, 0.9) if active else Color(1, 1, 1, 0.2), false, 1.0)
		draw_string(font, r.position + Vector2(10, 20), String(TABS[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
				Color(1, 1, 1) if active else Color(0.7, 0.75, 0.85))

	# ---- Сундук --------------------------------------------------------------
	if chest:
		draw_string(font, origin + Vector2(16, 92), "СУНДУК", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.8, 0.4))
		for i in Chest.CAP:
			var cr: Rect2 = Rect2(origin + Vector2(16 + (i % CHEST_COLS) * SLOT, 100 + int(i / CHEST_COLS) * SLOT), Vector2(SLOT - 4, SLOT - 4))
			_draw_slot(cr, chest.slots[i], font, false)

	# ---- Инвентарь игрока ----------------------------------------------------
	var inv_y: float = 100.0 if chest else 92.0
	if chest:
		inv_y = 268.0
	draw_string(font, origin + Vector2(16, inv_y - 6), "ВЫ", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.9, 1.0))
	for i in player.inv.size:
		var ir: Rect2 = Rect2(origin + Vector2(16 + (i % INV_COLS) * SLOT, inv_y + 6 + int(i / INV_COLS) * SLOT), Vector2(SLOT - 4, SLOT - 4))
		_draw_slot(ir, player.inv.slots[i], font, i < player.inv.hotbar_size)

	# ---- Рецепты -------------------------------------------------------------
	var rx: float = origin.x + 380
	draw_string(font, Vector2(rx, origin.y + 92), "РЕЦЕПТЫ", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.9, 1.0))
	var recipes: Array = DB.recipes_for(String(STATIONS[station_tab]))
	var available: bool = true
	var near: MachineBase = null
	if station_tab == 1:
		near = _near_machine("Smelter")
	elif station_tab == 2:
		near = _near_machine("Assembler")
	available = (station_tab == 0) or (near != null)
	if not available:
		draw_string(font, Vector2(rx, origin.y + 116), "Подойдите ближе к «%s»" % String(TABS[station_tab]),
				HORIZONTAL_ALIGNMENT_LEFT, 380, 13, Color(1.0, 0.6, 0.4))

	var y: float = origin.y + 116
	var shown: int = 0
	for r in recipes:
		if shown < scroll:
			shown += 1
			continue
		if y > origin.y + 440:
			break
		_draw_recipe(Rect2(Vector2(rx, y), Vector2(424, RECIPE_H - 6)), r, font, available, near)
		y += RECIPE_H
		shown += 1

	# ---- Цель: релей ---------------------------------------------------------
	var goal: Rect2 = Rect2(origin + Vector2(16, 396), Vector2(350, 60))
	if chest:
		goal = Rect2(origin + Vector2(16, 396), Vector2(350, 60))
	draw_rect(goal, Color(0.08, 0.14, 0.18, 0.9))
	draw_rect(goal, Color(0.3, 0.8, 0.95, 0.5), false, 1.0)
	draw_string(font, goal.position + Vector2(8, 16), "ЦЕЛЬ: РЕЛЕЙ-ЯДРО", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.4, 0.9, 1.0))
	var gx: float = goal.position.x + 8
	for id in Game.relay_req.keys():
		var need: int = int(Game.relay_req[id])
		var have: int = player.inv.count_of(id)
		var col: Color = Color(0.4, 0.95, 0.5) if have >= need else Color(1.0, 0.55, 0.4)
		draw_string(font, Vector2(gx, goal.position.y + 34), "%s %d/%d" % [DB.item_name(id), have, need],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
		gx += 108

	# ---- Курсор/подсказка ----------------------------------------------------
	if not held.is_empty():
		var tex: ImageTexture = DB.item_texture(held.id)
		var mp: Vector2 = get_local_mouse_position()
		if tex:
			draw_texture_rect(tex, Rect2(mp - Vector2(14, 14), Vector2(28, 28)), false)
		draw_string(font, mp + Vector2(14, -6), "x%d" % held.count, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1))

	draw_string(font, origin + Vector2(16, 458),
			"ЛКМ — взять/положить   ПКМ — половина   I/TAB — закрыть",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.75, 0.85, 0.9))


func _near_machine(kind: String) -> MachineBase:
	if player == null:
		return null
	for m in World.machines.values():
		if m.kind == kind and m.global_position.distance_to(player.global_position) < 90.0:
			return m
	return null


func _draw_slot(r: Rect2, stack: ItemStack, font: Font, hotbar: bool) -> void:
	draw_rect(r, Color(0.13, 0.15, 0.19, 0.95))
	draw_rect(r, Color(1, 1, 1, 0.18), false, 1.0)
	if hotbar:
		draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), Color(0.5, 0.8, 1.0, 0.4))
	if stack.is_empty():
		return
	var tex: ImageTexture = DB.item_texture(stack.id)
	if tex:
		draw_texture_rect(tex, Rect2(r.position + Vector2(5, 5), Vector2(SLOT - 14, SLOT - 14)), false)
	if stack.count > 1:
		draw_string(font, r.position + Vector2(2, r.size.y - 4), str(stack.count),
				HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 6, 12, Color(1, 1, 1, 0.95))


func _draw_recipe(r: Rect2, rec: Dictionary, font: Font, available: bool, near: MachineBase) -> void:
	var out_id: int = int(rec["out"])
	var can: bool = available and _has_ingredients(rec)
	draw_rect(r, Color(0.09, 0.11, 0.14, 0.9))
	draw_rect(r, Color(0.4, 0.9, 0.5, 0.7) if can else Color(1, 1, 1, 0.15), false, 1.0)
	var tex: ImageTexture = DB.item_texture(out_id)
	if tex:
		draw_texture_rect(tex, Rect2(r.position + Vector2(6, 8), Vector2(28, 28)), false)
	draw_string(font, r.position + Vector2(42, 20), String(rec["name"]), HORIZONTAL_ALIGNMENT_LEFT, 240, 14,
			Color(0.95, 0.97, 1.0) if can else Color(0.65, 0.68, 0.75))
	# Ингредиенты
	var gx: float = r.position.x + 42
	for id in rec["in"].keys():
		var need: int = int(rec["in"][id])
		var have: int = player.inv.count_of(id)
		var col: Color = Color(0.45, 0.95, 0.55) if have >= need else Color(1.0, 0.5, 0.45)
		var itex: ImageTexture = DB.item_texture(id)
		if itex:
			draw_texture_rect(itex, Rect2(Vector2(gx, r.position.y + 22), Vector2(14, 14)), false)
		draw_string(font, Vector2(gx + 15, r.position.y + 34), "%d" % need, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
		gx += 44


func _has_ingredients(rec: Dictionary) -> bool:
	for id in rec["in"].keys():
		if player.inv.count_of(id) < int(rec["in"][id]):
			return false
	return true


func _click(pos: Vector2, right: bool) -> void:
	# Сундук
	if chest:
		for i in Chest.CAP:
			var cr: Rect2 = Rect2(_panel_pos() + Vector2(16 + (i % CHEST_COLS) * SLOT, 100 + int(i / CHEST_COLS) * SLOT), Vector2(SLOT - 4, SLOT - 4))
			if cr.has_point(pos):
				_click_chest(i, right)
				queue_redraw()
				return
	# Инвентарь
	for i in player.inv.size:
		var ir: Rect2 = Rect2(_panel_pos() + Vector2(16 + (i % INV_COLS) * SLOT, 268 + int(i / INV_COLS) * SLOT) if chest
				else Rect2(_panel_pos() + Vector2(16 + (i % INV_COLS) * SLOT, 98 + int(i / INV_COLS) * SLOT), Vector2(SLOT - 4, SLOT - 4)),
				Vector2(SLOT - 4, SLOT - 4))
		if ir.has_point(pos):
			_click_inv(i, right)
			queue_redraw()
			return
	# Рецепты
	var recipes: Array = DB.recipes_for(String(STATIONS[station_tab]))
	var y: float = _panel_pos().y + 116
	var shown: int = 0
	for rec in recipes:
		if shown < scroll:
			shown += 1
			continue
		var rr: Rect2 = Rect2(Vector2(_panel_pos().x + 380, y), Vector2(424, RECIPE_H - 6))
		if rr.has_point(pos):
			_craft(rec)
			queue_redraw()
			return
		y += RECIPE_H
		shown += 1
	# Вкладки
	for i in TABS.size():
		var tr: Rect2 = Rect2(_panel_pos() + Vector2(16 + i * 170, 38), Vector2(164, 30))
		if tr.has_point(pos):
			station_tab = i
			scroll = 0
			queue_redraw()
			return


func _click_inv(index: int, right: bool) -> void:
	var slot: ItemStack = player.inv.slots[index]
	if held.is_empty():
		if slot.is_empty():
			return
		if right:
			var half: int = int(ceil(float(slot.count) * 0.5))
			held = ItemStack.new(slot.id, half)
			slot.take(half)
		else:
			held = slot.duplicate_stack()
			player.inv.slots[index] = ItemStack.new()
		return
	if slot.is_empty():
		if right:
			player.inv.slots[index] = ItemStack.new(held.id, 1)
			held.take(1)
		else:
			player.inv.slots[index] = held.duplicate_stack()
			held = ItemStack.new()
		return
	if slot.id == held.id:
		var room: int = DB.item_max_stack(slot.id) - slot.count
		var move: int = mini(room, held.count)
		if right:
			move = mini(move, 1)
		slot.count += move
		held.take(move)
	elif not right:
		var tmp: ItemStack = held
		held = slot.duplicate_stack()
		player.inv.slots[index] = tmp


func _click_chest(index: int, right: bool) -> void:
	var slot: ItemStack = chest.slots[index]
	if held.is_empty():
		if slot.is_empty():
			return
		if right:
			var half: int = int(ceil(float(slot.count) * 0.5))
			held = ItemStack.new(slot.id, half)
			slot.take(half)
		else:
			held = slot.duplicate_stack()
			chest.slots[index] = ItemStack.new()
		return
	if slot.is_empty():
		if right:
			chest.slots[index] = ItemStack.new(held.id, 1)
			held.take(1)
		else:
			chest.slots[index] = held.duplicate_stack()
			held = ItemStack.new()
		return
	if slot.id == held.id:
		var room: int = DB.item_max_stack(slot.id) - slot.count
		var move: int = mini(room, held.count)
		if right:
			move = mini(move, 1)
		slot.count += move
		held.take(move)
	else:
		var tmp: ItemStack = held
		held = slot.duplicate_stack()
		chest.slots[index] = tmp


func _craft(rec: Dictionary) -> void:
	if not _has_ingredients(rec):
		Game.notify("Не хватает материалов.", Color(1.0, 0.6, 0.4))
		return
	var station: String = String(rec["station"])
	var near: MachineBase = null
	if station == "smelter":
		near = _near_machine("Smelter")
	elif station == "assembler":
		near = _near_machine("Assembler")
	if station != "hand" and near == null:
		Game.notify("Рядом нет нужной станции.", Color(1.0, 0.6, 0.4))
		return
	for id in rec["in"].keys():
		player.inv.remove_id(id, int(rec["in"][id]))
	if station == "hand":
		player.inv.add(int(rec["out"]), int(rec["amount"]))
	else:
		for id in rec["in"].keys():
			near.receive_item(id, int(rec["in"][id]))
	Game.notify("Готово: %s" % DB.item_name(int(rec["out"])), Color(0.5, 0.95, 0.6))
	Sfx.play("craft", -6.0)
	Game.stats_crafted += 1
