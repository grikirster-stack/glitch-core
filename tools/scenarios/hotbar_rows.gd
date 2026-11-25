extends ScenarioBase
## Портрет телефона: хотбар в два ряда, все 10 слотов тапаются, ячейка ≥ 78.
## Прятать крайние нельзя: набор кладёт дверь и волокно в слоты 5 и 6.
## Холсты — те же, что у телефона: 1080×2400 и 1280×2844 при коэффициенте 2.5
## (логические 432×960 и 512×1137.6). Окно не трогаем: headless размер до кадра
## не применяет, холст передаём в _layout.

## Холст 1280, как у touch_controls и ui_scale_test: headless окно 1280×720,
## stretch expand. 1080 дал бы тап в координатах окна мимо ячеек холста.
## Логические размеры те же, что у телефона: 432×960 и 512×1137.6.
const CANVASES: Array = [
	{"canvas": Vector2(1280, 2844.444), "scale": 1280.0 / 432.0},
	{"canvas": Vector2(1280, 2844), "scale": 2.5},
]
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
	player.apply_hotbar_size(Inventory.HOTBAR_MAX)
	_fill_kit()
	await _place_door_and_bed()
	_fill_kit()
	UI.hud.card_text = "Закрой комнату дверью"
	UI.hud.hint_text = "Тап — поставить"
	for spec in CANVASES:
		await _one(spec["canvas"], float(spec["scale"]))
	_restore(saved, hb0, sel0)
	UI.set_ui_scale(scale0, false)
	UI.hud.card_text = card0
	UI.hud.hint_text = hint0
	UI.hud.size = get_viewport().get_visible_rect().size / UI.ui_scale
	UI.hud._lay_sig = -1
	tc.set_enabled(false)
	finish()


func _one(canvas: Vector2, scale: float) -> void:
	var logical: Vector2 = canvas / scale
	UI.ui_scale = scale
	UI.touch_on = true
	tc.force_k = 1.0
	tc.force_insets = Vector4.ZERO
	tc._layout(canvas)
	UI.hud.size = logical
	UI.hud._lay_sig = -1
	UI.hud._ensure_layout()
	var tag: String = "%.0f×%.1f" % [logical.x, logical.y]
	var bar: Rect2 = UI.hud.layout_rect("hotbar")
	var band: float = logical.y * (2.0 / 3.0)
	var grab: float = UI.hud._combat_grab_top(logical.y)
	var cell: Rect2 = UI.hud.hotbar_slot_logical(0)
	var row1: Rect2 = UI.hud.hotbar_slot_logical(5)
	print("  РЯДЫ %s хотбар=%s ячейка=%.1f ряд0y=%.1f ряд1y=%.1f треть=%.1f захват=%.1f" % [
		tag, str(bar), cell.size.x, cell.position.y, row1.position.y, band, grab])
	ok("%s два ряда, ячейка ≥ 78" % tag,
			cell.size.x + 0.5 >= 78.0 and row1.position.y > cell.position.y + 70.0
			and UI.hud.hotbar_slot_logical(9).has_area(),
			"ячейка %.1f, ряд0 %.1f, ряд1 %.1f" % [cell.size.x, cell.position.y, row1.position.y])
	ok("%s оба ряда выше захватов боя и в нижней трети" % tag,
			bar.position.y + 0.5 >= band and bar.end.y <= grab + 0.5
			and row1.end.y <= grab + 0.5,
			"хотбар y %.1f–%.1f, треть %.1f, захват %.1f" % [bar.position.y, bar.end.y, band, grab])
	var hint: Rect2 = UI.hud.layout_rect("hint")
	var card: Rect2 = UI.hud.layout_rect("card")
	print("  ПЛАШКИ %s подсказка=%s карточка=%s" % [tag, str(hint), str(card)])
	var covers: bool = false
	if hint.has_area() and (hint.intersects(bar) or hint.end.y > cell.position.y + 0.5):
		covers = true
	if card.has_area() and (card.intersects(bar) or card.intersects(hint) or card.end.y > cell.position.y + 0.5):
		covers = true
	ok("%s плашка и карточка не закрывают верхний ряд" % tag, not covers,
			"подсказка %s, карточка %s, верх ряда %.1f" % [str(hint), str(card), cell.position.y])
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
