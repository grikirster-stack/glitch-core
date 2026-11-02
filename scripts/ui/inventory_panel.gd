class_name InventoryPanel
extends Control
## Экран инвентаря: сетка предметов, крафт (ручной / плавильня / сборщик), сундуки
## и вкладка «Исследования» — дерево технологий (ADR-001, § 4.6; issue #28).
##
## Запертые деревом рецепты видны в списке серыми, с подписью узла; клик по ним
## не крафтит, а подсказывает, какой узел открыть.

const SLOT: int = 38
const INV_COLS: int = 9
const CHEST_COLS: int = 6
const RECIPE_H: int = 46
## Сколько строк рецептов влезает в панель (дальше — колесо мыши).
const RECIPE_ROWS: int = 7
## Карточка узла во вкладке «Исследования».
const CARD_H: int = 64
const CARD_GAP: int = 4
## Узлы, у которых есть карточки (T0 открыт с начала, карточки нет).
const CARD_NODES: Array = ["T1", "T2", "T3", "T4", "T5"]

var player = null    ## Игрок (без типа — во избежание цикла зависимостей).
var chest = null     ## Открытый сундук.
var held: ItemStack = ItemStack.new()
var station_tab: int = 0            ## 0 — ручной, 1 — плавильня, 2 — сборщик, 3 — исследования
var scroll: int = 0
var hover: int = -1

const TABS: Array = ["Ручной крафт", "Плавильня", "Сборщик", "Исследования"]
const STATIONS: Array = ["hand", "smelter", "assembler", ""]
const RESEARCH_TAB: int = 3

## Кэш списков рецептов по станциям и подписей узлов: DB.recipes после загрузки
## не меняется, а панель перерисовывается на каждое движение мыши. Ключ сверки —
## размер DB.recipes (вдруг кто-то допишет рецепт на ходу).
var _recipes_cache: Dictionary = {}     ## station -> Array
var _node_desc: Dictionary = {}         ## node -> "Сборщик, Манипулятор, …"
var _cache_size: int = -1


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
			scroll = mini(scroll + 1, _max_scroll())
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


## Верх сетки инвентаря игрока. С открытым сундуком панель выше: сундук
## занимает место сверху, инвентарь игрока уезжает вниз.
## Рисование и клик берут эту координату отсюда, иначе слоты кликаются
## не там, где нарисованы.
func _inv_y() -> float:
	return 268.0 if chest else 92.0


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
		# Есть что открыть — огонёк на вкладке «Исследования».
		if i == RESEARCH_TAB and _any_unlockable():
			draw_circle(r.position + Vector2(r.size.x - 12, r.size.y * 0.5), 4.0, Color(0.4, 0.95, 1.0))

	# ---- Сундук --------------------------------------------------------------
	if chest:
		draw_string(font, origin + Vector2(16, 92), "СУНДУК", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.8, 0.4))
		for i in Chest.CAP:
			var cr: Rect2 = Rect2(origin + Vector2(16 + (i % CHEST_COLS) * SLOT, 100 + int(i / CHEST_COLS) * SLOT), Vector2(SLOT - 4, SLOT - 4))
			_draw_slot(cr, chest.slots[i], font, false)

	# ---- Инвентарь игрока ----------------------------------------------------
	var inv_y: float = _inv_y()
	draw_string(font, origin + Vector2(16, inv_y - 6), "ВЫ", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.9, 1.0))
	for i in player.inv.size:
		var ir: Rect2 = Rect2(origin + Vector2(16 + (i % INV_COLS) * SLOT, inv_y + 6 + int(i / INV_COLS) * SLOT), Vector2(SLOT - 4, SLOT - 4))
		_draw_slot(ir, player.inv.slots[i], font, i < player.inv.hotbar_size)

	# ---- Рецепты или исследования ------------------------------------------
	var rx: float = origin.x + 380
	if station_tab == RESEARCH_TAB:
		_draw_research(rx, origin, font)
	else:
		_draw_recipes(rx, origin, font)

	# ---- Цель: релей ---------------------------------------------------------
	_draw_goal(origin, font)

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


func _draw_recipes(rx: float, origin: Vector2, font: Font) -> void:
	draw_string(font, Vector2(rx, origin.y + 92), "РЕЦЕПТЫ", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.9, 1.0))
	var recipes: Array = _recipes(String(STATIONS[station_tab]))
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

	var first: int = mini(scroll, _max_scroll())
	var last: int = mini(recipes.size(), first + RECIPE_ROWS)
	var y: float = origin.y + 116
	for i in range(first, last):
		_draw_recipe(Rect2(Vector2(rx, y), Vector2(424, RECIPE_H - 6)), recipes[i], font, available, near)
		y += RECIPE_H
	if recipes.size() > RECIPE_ROWS:
		draw_string(font, Vector2(rx, origin.y + 116 + RECIPE_ROWS * RECIPE_H + 8),
				"%d–%d из %d · колесо мыши — листать" % [first + 1, last, recipes.size()],
				HORIZONTAL_ALIGNMENT_LEFT, 424, 11, Color(0.6, 0.66, 0.76))


func _draw_goal(origin: Vector2, font: Font) -> void:
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
	var locked: bool = not DB.recipe_unlocked(rec)
	var can: bool = available and not locked and _has_ingredients(rec)
	draw_rect(r, Color(0.07, 0.08, 0.10, 0.9) if locked else Color(0.09, 0.11, 0.14, 0.9))
	draw_rect(r, Color(0.4, 0.9, 0.5, 0.7) if can else Color(1, 1, 1, 0.15), false, 1.0)
	# Запертый рецепт — весь серый: иконки притушены, справа — узел, который его открывает.
	var dim: Color = Color(1, 1, 1, 0.35) if locked else Color(1, 1, 1, 1)
	var tex: ImageTexture = DB.item_texture(out_id)
	if tex:
		draw_texture_rect(tex, Rect2(r.position + Vector2(6, 8), Vector2(28, 28)), false, dim)
	var name_col: Color = Color(0.95, 0.97, 1.0) if can else Color(0.65, 0.68, 0.75)
	if locked:
		name_col = Color(0.48, 0.50, 0.55)
		draw_string(font, Vector2(r.end.x - 156, r.position.y + 17), "нужно " + Tech.title(String(rec.get("tech", "T0"))),
				HORIZONTAL_ALIGNMENT_RIGHT, 150, 11, Color(0.95, 0.72, 0.35, 0.85))
	draw_string(font, r.position + Vector2(42, 20), String(rec["name"]), HORIZONTAL_ALIGNMENT_LEFT,
			200 if locked else 240, 14, name_col)
	# Ингредиенты
	var gx: float = r.position.x + 42
	for id in rec["in"].keys():
		var need: int = int(rec["in"][id])
		var have: int = player.inv.count_of(id)
		var col: Color = Color(0.45, 0.95, 0.55) if have >= need else Color(1.0, 0.5, 0.45)
		if locked:
			col = Color(0.5, 0.52, 0.56)
		var itex: ImageTexture = DB.item_texture(id)
		if itex:
			draw_texture_rect(itex, Rect2(Vector2(gx, r.position.y + 22), Vector2(14, 14)), false, dim)
		draw_string(font, Vector2(gx + 15, r.position.y + 34), "%d" % need, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
		gx += 44


# ---------------------------------------------------------------- ИССЛЕДОВАНИЯ

## Вкладка «Исследования»: пять карточек T1…T5, у каждой — что открывает узел
## и кнопка «Открыть (N данных)».
func _draw_research(rx: float, origin: Vector2, font: Font) -> void:
	draw_string(font, Vector2(rx, origin.y + 92), "ИССЛЕДОВАНИЯ", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.9, 1.0))
	draw_string(font, Vector2(rx, origin.y + 92), "Данные: %d" % Game.research, HORIZONTAL_ALIGNMENT_RIGHT, 424, 14,
			Color(0.45, 0.95, 1.0))
	for i in CARD_NODES.size():
		_draw_card(i, font)


func _draw_card(i: int, font: Font) -> void:
	var node: String = String(CARD_NODES[i])
	var r: Rect2 = _card_rect(i)
	var open: bool = Tech.is_unlocked(node)
	var can: bool = Tech.can_unlock(node)
	draw_rect(r, Color(0.07, 0.15, 0.12, 0.92) if open else Color(0.09, 0.11, 0.14, 0.9))
	var edge: Color = Color(1, 1, 1, 0.15)
	if open:
		edge = Color(0.4, 0.9, 0.5, 0.55)
	elif can:
		edge = Color(0.4, 0.85, 1.0, 0.85)
	draw_rect(r, edge, false, 1.0)
	var title_col: Color = Color(0.7, 0.73, 0.8)
	if open:
		title_col = Color(0.55, 0.95, 0.65)
	elif can:
		title_col = Color(0.95, 0.97, 1.0)
	draw_string(font, r.position + Vector2(8, 18), Tech.title(node), HORIZONTAL_ALIGNMENT_LEFT, 250, 14, title_col)
	draw_multiline_string(font, r.position + Vector2(8, 34), _desc(node), HORIZONTAL_ALIGNMENT_LEFT, 252, 11, 2,
			Color(0.62, 0.67, 0.76))
	# Кнопка
	var b: Rect2 = _card_button_rect(i)
	var label: String = "Открыть (%d данных)" % Tech.cost(node)
	var b_bg: Color = Color(0.11, 0.13, 0.17)
	var b_fg: Color = Color(0.5, 0.53, 0.6)
	if open:
		label = "Открыто"
		b_bg = Color(0.08, 0.2, 0.13)
		b_fg = Color(0.55, 0.95, 0.65)
	elif can:
		b_bg = Color(0.12, 0.3, 0.4)
		b_fg = Color(0.9, 0.98, 1.0)
	elif not Tech.is_unlocked(Tech.prerequisite(node)):
		label = "Сначала %s" % Tech.prerequisite(node)
	draw_rect(b, b_bg)
	draw_rect(b, Color(b_fg, 0.5), false, 1.0)
	draw_string(font, b.position + Vector2(0, 19), label, HORIZONTAL_ALIGNMENT_CENTER, b.size.x, 12, b_fg)


func _card_rect(i: int) -> Rect2:
	var o: Vector2 = _panel_pos()
	return Rect2(Vector2(o.x + 380, o.y + 104 + i * (CARD_H + CARD_GAP)), Vector2(424, CARD_H))


## Кнопка «Открыть» карточки i: рисование и клик берут её отсюда.
func _card_button_rect(i: int) -> Rect2:
	var r: Rect2 = _card_rect(i)
	return Rect2(Vector2(r.end.x - 152, r.position.y + 30), Vector2(144, 28))


## Есть ли узел, который можно открыть прямо сейчас (огонёк на вкладке).
func _any_unlockable() -> bool:
	for n in CARD_NODES:
		if Tech.can_unlock(String(n)):
			return true
	return false


## Нажата кнопка карточки: открыть узел или сказать, почему нельзя.
func _unlock_card(i: int) -> void:
	var node: String = String(CARD_NODES[i])
	if Tech.is_unlocked(node):
		return
	if Tech.unlock(node):
		Sfx.play("craft", -4.0, 0.8)
	else:
		Game.notify(Tech.lock_reason(node) + ".", Color(1.0, 0.6, 0.4))


# ---------------------------------------------------------------- КЭШ РЕЦЕПТОВ

func _check_cache() -> void:
	if _cache_size == DB.recipes.size():
		return
	_cache_size = DB.recipes.size()
	_recipes_cache = {}
	_node_desc = {}


## Рецепты станции (кэш поверх DB.recipes_for).
func _recipes(station: String) -> Array:
	_check_cache()
	if not _recipes_cache.has(station):
		_recipes_cache[station] = DB.recipes_for(station)
	return _recipes_cache[station]


## Что открывает узел: названия его рецептов через запятую.
func _desc(node: String) -> String:
	_check_cache()
	if not _node_desc.has(node):
		var names: PackedStringArray = PackedStringArray()
		for r in Tech.recipes_of(node):
			names.append(String(r["name"]))
		_node_desc[node] = ", ".join(names) if not names.is_empty() else "—"
	return String(_node_desc[node])


func _max_scroll() -> int:
	if station_tab == RESEARCH_TAB:
		return 0
	return maxi(0, _recipes(String(STATIONS[station_tab])).size() - RECIPE_ROWS)


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
		var ir: Rect2 = Rect2(_panel_pos() + Vector2(16 + (i % INV_COLS) * SLOT, _inv_y() + 6 + int(i / INV_COLS) * SLOT),
				Vector2(SLOT - 4, SLOT - 4))
		if ir.has_point(pos):
			_click_inv(i, right)
			queue_redraw()
			return
	if station_tab == RESEARCH_TAB:
		# Карточки исследований
		for i in CARD_NODES.size():
			if _card_button_rect(i).has_point(pos):
				_unlock_card(i)
				queue_redraw()
				return
	else:
		# Рецепты: те же строки, что нарисованы (не больше RECIPE_ROWS).
		var recipes: Array = _recipes(String(STATIONS[station_tab]))
		var first: int = mini(scroll, _max_scroll())
		var y: float = _panel_pos().y + 116
		for i in range(first, mini(recipes.size(), first + RECIPE_ROWS)):
			var rr: Rect2 = Rect2(Vector2(_panel_pos().x + 380, y), Vector2(424, RECIPE_H - 6))
			if rr.has_point(pos):
				_craft(recipes[i])
				queue_redraw()
				return
			y += RECIPE_H
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
	if not DB.recipe_unlocked(rec):
		Game.notify("Рецепт заперт: откройте %s во вкладке «Исследования»." % Tech.title(String(rec.get("tech", "T0"))),
				Color(1.0, 0.72, 0.35))
		return
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
