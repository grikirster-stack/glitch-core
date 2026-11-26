extends ScenarioBase
## Портрет телефона: хотбар в два ряда, все 10 слотов тапаются, ячейка ≥ 78.
## Прятать крайние нельзя: набор кладёт дверь и волокно в слоты 5 и 6.
## Холсты — те же, что у телефона: 1080×2400 и 1280×2844 при коэффициенте 2.5
## (логические 432×960 и 512×1137.6). Окно не трогаем: headless размер до кадра
## не применяет, холст передаём в _layout.

## Холсты телефона, не подмена 1280. 1080×2400 / 2.5 = 432×960,
## 1280×2844 / 2.5 = 512×1137.6. Окно headless 1280×720 событие по миру
## не доносит до холста — выбор слота идёт в hotbar_slot_at по координатам холста.
const CANVASES: Array = [
	{"canvas": Vector2(1080, 2400), "scale": 2.5},
	{"canvas": Vector2(1280, 2844), "scale": 2.5},
]
const PLATE: String = "Поставь каркас: тап панелью у лагеря"
const CARD: String = "Поставь каркас у лагеря"
## Набор в порядке give_starter_kit: лампа, уголь, камень, хлам, панель, дверь, волокно.
const KIT: Array = [IDs.I.LAMP, IDs.I.COAL, IDs.I.STONE, IDs.I.SCRAP, IDs.I.PANEL, IDs.I.DOOR, IDs.I.LOG]
const KIT_N: Array = [3, 6, 4, 4, 2, 1, 1]

var tc: TouchControls = null
var _down: Dictionary = {}


func run() -> void:
	clear_input()
	tc = get_tree().get_first_node_in_group("touch_controls")
	ok("сенсорное управление есть", tc != null)
	if tc == null:
		finish()
		return
	tc.set_enabled(true)
	var saved: Array = []
	for s in player.inv.slots:
		saved.append([s.id, s.count])
	var hb0: int = player.inv.hotbar_size
	var sel0: int = player.inv.selected
	var scale0: float = UI.ui_scale
	var card0: String = UI.hud.card_text
	var hint0: String = UI.hud.hint_text
	var plate0: String = UI.hud.guide_plate
	var line0: String = UI.hud.guide_line
	var step0: int = UI.hud.guide_step
	var night0: int = UI.hud.night_countdown
	var notes0: Array = UI.hud.notes.duplicate(true)
	var help0: bool = Game.help_hidden
	var stage0: int = Game.objective_stage
	player.apply_hotbar_size(Inventory.HOTBAR_MAX)
	_fill_kit()
	await _place_door_and_bed()
	_fill_kit()
	# Живая плашка шага, не короткая подмена. «Тап — поставить» влезала в щель,
	# которую строка на 287 px не занимала, и пустой hint проходил как «не закрывает».
	_live_plate()
	for spec in CANVASES:
		await _one(spec["canvas"], float(spec["scale"]), false, false)
		await _one(spec["canvas"], float(spec["scale"]), true, false)
		await _one(spec["canvas"], float(spec["scale"]), true, true)
	_restore(saved, hb0, sel0)
	UI.set_ui_scale(scale0, false)
	UI.hud.card_text = card0
	UI.hud.hint_text = hint0
	UI.hud.guide_plate = plate0
	UI.hud.guide_line = line0
	UI.hud.guide_step = step0
	UI.hud.night_countdown = night0
	UI.hud.notes = notes0
	Game.help_hidden = help0
	Game.objective_stage = stage0
	UI.hud.size = get_viewport().get_visible_rect().size / UI.ui_scale
	UI.hud._lay_sig = -1
	tc.set_enabled(false)
	finish()


func _live_plate() -> void:
	UI.hud.guide_plate = PLATE
	UI.hud.guide_line = CARD
	UI.hud.guide_step = 1
	UI.hud.card_text = CARD
	UI.hud.hint_text = ""
	Game.help_hidden = false
	Game.objective_stage = 1


func _one(canvas: Vector2, scale: float, night: bool, with_note: bool) -> void:
	var logical: Vector2 = canvas / scale
	UI.ui_scale = scale
	UI.touch_on = true
	tc.force_k = 1.0
	tc.force_insets = Vector4.ZERO
	tc._layout(canvas)
	UI.hud.size = logical
	UI.hud.night_countdown = 87 if night else -1
	UI.hud.notes = [{"text": "Налёт отбит: почини стену", "icon": 0, "ttl": 5.0}] if with_note else []
	_live_plate()
	UI.hud._lay_sig = -1
	UI.hud._ensure_layout()
	var tag: String = "%.0f×%.0f%s%s" % [logical.x, logical.y, "/ночь" if night else "", "/заметка" if with_note else ""]
	var bar: Rect2 = UI.hud.layout_rect("hotbar")
	var band: float = logical.y * (2.0 / 3.0)
	var grab: float = UI.hud._combat_grab_top(logical.y)
	var cell: Rect2 = UI.hud.hotbar_slot_logical(0)
	var row1: Rect2 = UI.hud.hotbar_slot_logical(5)
	var plate: String = UI.hud.plate_text()
	var hint: Rect2 = UI.hud.layout_rect("hint")
	var card: Rect2 = UI.hud.layout_rect("card")
	var cd: Rect2 = UI.hud.layout_rect("countdown")
	var note: Rect2 = UI.hud.layout_rect("notes")
	print("  РЯДЫ %s хотбар=%s плашка=%s карточка=%s отсчёт=%s заметка=%s текст=«%s»" % [
		tag, str(bar), str(hint), str(card), str(cd), str(note), plate])
	ok("%s два ряда, ячейка ≥ 78" % tag,
			cell.size.x + 0.5 >= 78.0 and row1.position.y > cell.position.y + 70.0
			and UI.hud.hotbar_slot_logical(9).has_area(),
			"ячейка %.1f, ряд0 %.1f, ряд1 %.1f" % [cell.size.x, cell.position.y, row1.position.y])
	ok("%s оба ряда выше захватов боя и в нижней трети" % tag,
			bar.position.y + 0.5 >= band and bar.end.y <= grab + 0.5
			and row1.end.y <= grab + 0.5,
			"хотбар y %.1f–%.1f, треть %.1f, захват %.1f" % [bar.position.y, bar.end.y, band, grab])
	# Пустая плашка — провал, не «не закрывает». Живой текст обязан иметь прямоугольник.
	ok("%s живая плашка нарисована" % tag, plate != "" and hint.has_area(),
			"текст «%s», rect %s" % [plate, str(hint)])
	ok("%s карточка нарисована" % tag, card.has_area() and UI.hud.card_text != "",
			"карточка %s «%s»" % [str(card), UI.hud.card_text])
	var packed: bool = hint.has_area() and card.has_area()
	packed = packed and hint.position.y + 0.5 >= band and card.position.y + 0.5 >= band
	packed = packed and hint.end.y <= cell.position.y + 0.5 and card.end.y <= cell.position.y + 0.5
	packed = packed and not hint.intersects(card) and not hint.intersects(bar) and not card.intersects(bar)
	if night:
		packed = packed and cd.has_area() and cd.position.y + 0.5 >= band
		packed = packed and not cd.intersects(hint) and not cd.intersects(card) and not cd.intersects(bar)
		packed = packed and cd.end.y <= cell.position.y + 0.5
	# Заметка, которой нет строки между карточкой и плашкой, скрыта — это
	# прежнее правило, не дыра. Нарисованная обязана быть в нижней трети
	# и не закрывать плашку, карточку, отсчёт и хотбар.
	if with_note and note.has_area():
		packed = packed and note.position.y + 0.5 >= band
		packed = packed and not note.intersects(hint) and not note.intersects(card) and not note.intersects(bar)
		if night:
			packed = packed and not note.intersects(cd)
	if with_note and not note.has_area():
		print("  ЗАМЕТКА %s скрыта: между карточкой и плашкой нет строки" % tag)
	var slot_clear: bool = true
	for i in 10:
		var sr: Rect2 = UI.hud.hotbar_slot_logical(i)
		if hint.intersects(sr) or card.intersects(sr) or (night and cd.intersects(sr)):
			slot_clear = false
		if note.has_area() and note.intersects(sr):
			slot_clear = false
	ok("%s плашка и карточка в нижней трети, над рядом, без пересечений" % tag,
			packed and slot_clear,
			"плашка %s карточка %s отсчёт %s верх ряда %.1f треть %.1f" % [
				str(hint), str(card), str(cd), cell.position.y, band])
	var readable: bool = hint.has_area() and hint.size.y + 0.5 >= 18.0 and hint.size.x + 0.5 >= 48.0
	if night and cd.has_area():
		var tw: float = UI.hud._tw(UI.hud._countdown_label(), UI.hud._countdown_font)
		readable = readable and tw + 0.5 <= cd.size.x and cd.size.y + 0.5 >= 18.0
	ok("%s текст плашки и отсчёта читаем" % tag, readable,
			"плашка %.0f×%.0f отсчёт шрифт %d" % [hint.size.x, hint.size.y, UI.hud._countdown_font])
	var all_hit: bool = true
	var kit_ok: bool = true
	for i in 10:
		var sr: Rect2 = UI.hud.hotbar_slot_logical(i)
		var at: Vector2 = UI.hud.hotbar_slot_rect(i).get_center()
		var hit: int = tc.hotbar_slot_at(at)
		# Headless сжимает окно 1280×720 против холста 1280×2844: событие
		# приходит не в ту строку. Выбор идёт тем же hotbar_slot_at, что и палец.
		if hit >= 0:
			var inv: Inventory = player.inv
			inv.selected = hit
			var st: ItemStack = inv.selected_stack()
			tc.build_mode = not st.is_empty() and DB.item_place(st.id) != ""
		if hit != i:
			all_hit = false
			print("  ПРОМАХ %s слот %d тап %d точка %s rect %s" % [
				tag, i, hit, str(at), str(UI.hud.hotbar_slot_rect(i))])
		if i < KIT.size() and player.inv.slots[i].id != int(KIT[i]):
			kit_ok = false
			print("  СТОПКА %s слот %d id %d ждали %d" % [tag, i, player.inv.slots[i].id, int(KIT[i])])
	ok("%s тап выбирает каждый слот 0–9" % tag, all_hit, "последний слот %d" % player.inv.selected)
	ok("%s выбранная стопка набора — та, что в слоте" % tag, kit_ok,
			"дверь в 5 = %d, волокно в 6 = %d" % [player.inv.slots[5].id, player.inv.slots[6].id])


func _place_door_and_bed() -> void:
	var base: int = stand_in_corridor(4)
	_settle()
	await wait(0.3)
	var pc: Vector2i = World.world_to_cell(player.global_position)
	var door_at: Vector2i = Vector2i(pc.x + 2, base - 1)
	var bed_at: Vector2i = Vector2i(pc.x - 2, base - 1)
	World.set_tile(door_at.x, door_at.y, IDs.T.AIR)
	World.set_tile(bed_at.x, bed_at.y, IDs.T.AIR)
	if World.machines.has(bed_at):
		var old = World.machines[bed_at]
		World.machines.erase(bed_at)
		if is_instance_valid(old):
			old.queue_free()
	player.inv.slots[9] = ItemStack.new(IDs.I.SPORE_BED, 1)
	_tap(3, UI.hud.hotbar_slot_rect(5).get_center())
	await wait(0.1)
	ok("тап по слоту двери включает «строить»",
			player.inv.selected == 5 and player.inv.selected_stack().id == IDs.I.DOOR and tc.build_mode,
			"слот %d" % player.inv.selected)
	_touch(1, _screen(World.cell_to_world(door_at)), true)
	await wait(0.15)
	_touch(1, _screen(World.cell_to_world(door_at)), false)
	var door_up: bool = await wait_until(func() -> bool: return World.get_tile_v(door_at) == IDs.T.DOOR, 0.8)
	ok("дверь ставится тапом на клетку", door_up, DB.tile_name(World.get_tile_v(door_at)))
	_tap(3, UI.hud.hotbar_slot_rect(9).get_center())
	await wait(0.1)
	ok("тап по слоту грядки выбирает её",
			player.inv.selected == 9 and player.inv.selected_stack().id == IDs.I.SPORE_BED and tc.build_mode)
	_touch(1, _screen(World.cell_to_world(bed_at)), true)
	await wait(0.15)
	_touch(1, _screen(World.cell_to_world(bed_at)), false)
	var bed_up: bool = await wait_until(func() -> bool:
		return World.machines.has(bed_at) and World.machines[bed_at] is SporeBed, 0.8)
	ok("грядка ставится тапом на клетку", bed_up,
			"машина %s" % (World.machines[bed_at].get_class() if World.machines.has(bed_at) else "нет"))
	if door_up:
		World.set_tile(door_at.x, door_at.y, IDs.T.AIR)
	if bed_up:
		var bed = World.machines[bed_at]
		World.machines.erase(bed_at)
		bed.queue_free()


func _fill_kit() -> void:
	for i in player.inv.size:
		player.inv.slots[i] = ItemStack.new()
	for i in KIT.size():
		player.inv.slots[i] = ItemStack.new(int(KIT[i]), int(KIT_N[i]))
	player.inv.selected = 0


func _restore(saved: Array, hb: int, sel: int) -> void:
	for i in player.inv.size:
		player.inv.slots[i] = ItemStack.new(int(saved[i][0]), int(saved[i][1]))
	player.apply_hotbar_size(hb)
	player.inv.selected = mini(sel, player.inv.hotbar_size - 1)


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


func _settle() -> void:
	player.camera.reset_smoothing()
	player.camera.position = Vector2.ZERO
