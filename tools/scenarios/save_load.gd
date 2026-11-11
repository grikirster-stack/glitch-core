extends ScenarioBase
## Сохранение и загрузка (#37): бот ставит маленькую фабрику (сундук → манипулятор
## → лента → плавильня → лента → сундук, ТЭЦ), ждёт первые слитки, жмёт F5,
## ломает плавильню, копает, меняет инвентарь и данные, жмёт F9 — всё вернулось
## как было в момент F5, и фабрика продолжает плавить.
##
## Клавиши идут настоящим событием ввода (Input.parse_input_event) — через UI,
## как у человека. Слот — свой («scenario»): сохранение игрока не трогаем.

const SLOT: String = "scenario"


func run() -> void:
	player.invuln = 1.0e9
	var slot0: String = Save.slot
	Save.slot = SLOT
	Save.remove(SLOT)
	var bx: int = World.beacon_cell.x
	var base: int = World.beacon_cell.y
	var c0: Vector2i = Vector2i(bx - 36, base + 6)
	for x in range(c0.x - 1, c0.x + 8):
		for y in range(c0.y - 1, c0.y + 6):
			World.set_tile(x, y, IDs.T.AIR)
	var ok_place: bool = true
	for e in [["Chest", 0, 0], ["Inserter", 1, 0], ["Belt", 2, 0], ["Smelter", 3, 0],
			["Belt", 4, 0], ["Chest", 5, 0], ["CoalGen", 3, 2], ["Turret", 1, 2]]:
		ok_place = MachineBase.place_machine(String(e[0]), c0 + Vector2i(int(e[1]), int(e[2]))) and ok_place
	ok("фабрика поставлена", ok_place)
	var src: Chest = World.machines.get(c0)
	var dst: Chest = World.machines.get(c0 + Vector2i(5, 0))
	var gen: CoalGen = World.machines.get(c0 + Vector2i(3, 2))
	if not ok_place or src == null or dst == null or gen == null:
		_cleanup(slot0)
		return
	for c in [c0 + Vector2i(2, 0), c0 + Vector2i(4, 0)]:
		(World.belts[c] as Belt).dir = 0
	gen.add_fuel(CoalGen.FUEL_MAX_UNITS)
	src.receive_item(IDs.I.COPPER_ORE, 30)
	Game.give_next_blueprint()   # чертёж в файл: после F9 панель должна показать тот же рецепт
	# Оборона (#31): шлюз у фабрики, решётка на вентиляции. Релей (#32): сигнал держится.
	var lock: Vector2i = c0 + Vector2i(7, 1)
	World.set_tile(lock.x, lock.y, IDs.T.AIRLOCK)
	var grate: Vector2i = Vector2i(-1, -1)
	for v in World.vents:
		if World.get_tile_v(v) == IDs.T.AIR:
			grate = v
			break
	if grate.x >= 0:
		World.set_tile(grate.x, grate.y, IDs.T.VENT_GRATE)
		World.damage_grate(grate, 5.0)
	Game.relay_active = true
	Game.relay_timer = 170.0
	Game.update_objective()
	var got: bool = await wait_until(func() -> bool: return _count(dst, IDs.I.COPPER_INGOT) >= 2, 20.0)
	ok("фабрика дала первые слитки", got, "слитков %d" % _count(dst, IDs.I.COPPER_INGOT))

	# Снимки — в тот же кадр, что и клавиша (сигналы UI): дальше фабрика едет.
	var cap: Dictionary = {}
	var on_saved: Callable = func() -> void:
		cap["saved"] = Save.gather()
		cap["ingots"] = _count(World.machines.get(c0 + Vector2i(5, 0)), IDs.I.COPPER_INGOT)
	var on_loaded: Callable = func() -> void:
		cap["loaded"] = Save.gather()
	UI.run_saved.connect(on_saved)
	UI.run_loaded.connect(on_loaded)

	# --- F5
	await _press(KEY_F5)
	ok("F5 записал файл", Save.exists(SLOT) and cap.has("saved"), Save.path_for(SLOT))
	if not cap.has("saved"):
		_disconnect(on_saved, on_loaded)
		_cleanup(slot0)
		return
	var file_state: Dictionary = Save.decode(FileAccess.get_file_as_bytes(Save.path_for(SLOT)))
	ok("в файле — мир в момент F5", var_to_bytes(file_state) == var_to_bytes(cap["saved"]))
	var snap: Dictionary = cap["saved"]
	var ingots0: int = int(cap["ingots"])
	print("  [замер] F5: %.1f мс, файл %.1f КБ (несжато %.1f КБ)" % [Save.last_save_ms,
			float(Save.last_size) / 1024.0, float(Save.last_raw_size) / 1024.0])

	# --- Меняем мир: ломаем плавильню, копаем, трогаем инвентарь и данные.
	var sm: MachineBase = World.machines.get(c0 + Vector2i(3, 0))
	if sm != null:
		sm.destroy()
	for x in range(bx - 8, bx + 8):
		World.set_tile(x, base + 3, IDs.T.AIR)
	player.inv.add(IDs.I.STONE, 50)
	player.global_position += Vector2(200.0, -40.0)
	Game.blueprints = PackedStringArray()
	var tur: MachineBase = World.machines.get(c0 + Vector2i(1, 2))
	if tur != null:
		tur.destroy()
	World.set_tile(lock.x, lock.y, IDs.T.AIR)
	if grate.x >= 0:
		World.damage_grate(grate, 1.0e6)
	Game.relay_active = false
	Game.objective_stage = 1
	await wait(0.3)
	ok("мир изменился", World.tiles != snap["world"]["tiles"] and not World.machines.has(c0 + Vector2i(3, 0)))

	# --- F9
	await _press(KEY_F9)
	_disconnect(on_saved, on_loaded)
	ok("F9 загрузил файл", cap.has("loaded"), Save.last_error)
	if not cap.has("loaded"):
		_cleanup(slot0)
		return
	print("  [замер] F9: %.1f мс, изменено клеток %d" % [Save.last_load_ms, World.load_changed_cells])
	var after: Dictionary = cap["loaded"]
	ok("плавильня вернулась", World.machines.get(c0 + Vector2i(3, 0)) is Smelter)
	ok("турель вернулась", World.machines.get(c0 + Vector2i(1, 2)) is Turret)
	ok("шлюз вернулся", World.airlocks.has(lock) and (World.get_tile_v(lock) == IDs.T.AIRLOCK
			or World.get_tile_v(lock) == IDs.T.AIRLOCK_OPEN))
	ok("решётка вернулась с прежним HP", grate.x < 0 or (World.is_vent_sealed(grate)
			and World.vents_sealed[grate] == snap["world"]["vents_sealed"][grate]),
			"HP %s" % str(World.vents_sealed.get(grate)))
	ok("этап релея вернулся", Game.relay_active and Game.objective_stage == 3,
			"этап %d, %.1f с" % [Game.objective_stage, Game.relay_timer])
	for sec in ["world", "machines", "items", "player", "game", "tech", "threat"]:
		ok("«%s» как при F5" % sec, var_to_bytes(after[sec]) == var_to_bytes(snap[sec]))
	ok("герой там же, инвентарь тот же", after["player"]["pos"] == snap["player"]["pos"]
			and after["player"]["inv"] == snap["player"]["inv"])
	dst = World.machines.get(c0 + Vector2i(5, 0))
	if dst == null:
		_cleanup(slot0)
		return
	got = await wait_until(func() -> bool: return _count(dst, IDs.I.COPPER_INGOT) > ingots0, 20.0)
	ok("после загрузки фабрика продолжает плавить", got,
			"слитков %d → %d" % [ingots0, _count(dst, IDs.I.COPPER_INGOT)])
	ok("чертёж из сохранения на месте", Game.has_blueprint(IDs.I.STEEL_WALL), str(Game.blueprints))
	var panel: InventoryPanel = UI.panel
	panel.open(player)
	panel.station_tab = 0
	panel._cache_size = -1
	player.inv.mark_seen(IDs.I.IRON_INGOT)
	player.inv.mark_seen(IDs.I.COAL)
	panel._check_cache()
	var shown: bool = false
	for r in panel._recipes("hand"):
		if int(r["out"]) == IDs.I.STEEL_WALL:
			shown = true
	ok("после загрузки панель показывает рецепт чертежа", shown)
	panel.close()
	_cleanup(slot0)


func _disconnect(a: Callable, b: Callable) -> void:
	if UI.run_saved.is_connected(a):
		UI.run_saved.disconnect(a)
	if UI.run_loaded.is_connected(b):
		UI.run_loaded.disconnect(b)


func _cleanup(slot0: String) -> void:
	Game.relay_active = false
	Save.remove(SLOT)
	Save.slot = slot0
	player.invuln = 0.0
	finish()


## Нажать и отпустить клавишу настоящим событием ввода (его ловит UI._input).
func _press(code: int) -> void:
	for pressed in [true, false]:
		var ev: InputEventKey = InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await await_frame()
		await await_frame()


func _count(ch: Chest, id: int) -> int:
	var n: int = 0
	for s in ch.slots:
		if not s.is_empty() and s.id == id:
			n += s.count
	return n

