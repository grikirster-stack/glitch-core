extends ScenarioBase
## Починка с телефона (#316): тап по виртуальной E, камень в руке.
## Клавиатурный hold(KEY_E) здесь не жмём. Плашка — «[E] — починить» или «Тап — починить».


var tc: TouchControls = null
var _down: Dictionary = {}


func run() -> void:
	var origin: Vector2i = World.beacon_cell + Vector2i(4, -2)
	for y in range(-1, 3):
		for x in range(-1, 4):
			var c: Vector2i = origin + Vector2i(x, y)
			if World.in_bounds(c.x, c.y):
				World.set_tile(c.x, c.y, IDs.T.AIR)
	var bed: SporeBed = RaidCommon.place_bed(origin, false)
	ok("грядка без панелей", bed != null)
	player.inv.add(IDs.I.STONE, 4)
	RaidCommon.arm(3)
	Threat.tick(0.05)
	RaidCommon.tick(Game.raid_remain + 0.2)
	RaidCommon.tick(Balance.VENT_TELEGRAPH + 0.2)
	var ph: Node = _one()
	if ph != null:
		ph.global_position = World.cell_to_world(origin)
		ph.approach_at = ph.global_position
		ph.approach_t = 4.0
		ph.state = ph.St.CHASE
	for _i in 8:
		RaidCommon.step_frame(self, 0.05)
	ok("устройство встало", bed.raid_stopped and Game.raid_damage == "device", Game.raid_damage)
	# Строка налёта забивает плашку. Следующая ночь может начать новое предупреждение
	# в том же тике, что сбрасывает фазу 3 — гасим фазу, строку не подменяем руками.
	RaidCommon.tick(Game.raid_remain + 0.3)
	Game.raid_phase = 0
	Game.raid_active = false
	if UI.hud != null:
		UI.hud.raid_line = ""
	tc = get_tree().get_first_node_in_group("touch_controls")
	ok("кнопка E на телефоне есть", tc != null)
	if tc == null:
		finish()
		return
	tc.set_enabled(true)
	await wait(0.05)
	player.inv.slots[0] = ItemStack.new(IDs.I.STONE, 4)
	player.inv.selected = 0
	player.global_position = World.cell_to_world(origin) + Vector2(18.0, 0.0)
	player.vel = Vector2.ZERO
	aim(bed.global_position)
	await wait(0.15)
	var plate: String = RaidCommon.plate()
	ok("плашка зовёт починить тапом или кнопкой E",
			plate == "[E] — починить" or plate == "Тап — починить" \
					or plate.begins_with("[E] — починить") or plate.begins_with("Тап — починить"),
			"«%s»" % plate)
	ok("плашка без ЛКМ, ПКМ и [X]", not plate.contains("ЛКМ") and not plate.contains("ПКМ") and not plate.contains("[X]"),
			"«%s»" % plate)
	var stone0: int = player.inv.count_of(IDs.I.STONE)
	# Тап по виртуальной E держит клавишу, пока палец на кнопке.
	_touch(2, tc.btn_center["e"], true)
	var held_e: bool = false
	for _i in 20:
		await wait(0.05)
		if bool(player.touch_input.get("keys", {}).get(KEY_E, false)):
			held_e = true
		if not bed.raid_stopped:
			break
	_touch(2, tc.btn_center["e"], false)
	tc.set_enabled(false)
	ok("тап по E дошёл до героя", held_e)
	ok("камень запустил устройство", not bed.raid_stopped and player.inv.count_of(IDs.I.STONE) < stone0,
			"стоп %s, камень %d → %d" % [str(bed.raid_stopped), stone0, player.inv.count_of(IDs.I.STONE)])
	finish()


func _one() -> Node:
	var list: Array = RaidCommon.raid_phantoms()
	return list[0] if not list.is_empty() else null


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e: InputEventScreenTouch = InputEventScreenTouch.new()
	e.index = index
	e.position = get_viewport().get_final_transform() * pos
	e.pressed = pressed
	Input.parse_input_event(e)
