extends ScenarioBase
## Сохранение и загрузка (#37, #170): бот ставит лагерь (сундук, горелка, зеркало),
## ждёт, пока горелка горит, жмёт F5, разбирает зеркало, копает, меняет инвентарь
## и данные, жмёт F9 — всё вернулось как при F5, горелка продолжает жечь топливо.
## Фабрики больше нет: бур, лента, плавильня и турель не ставятся.
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
	for e in [["Chest", 0, 0], ["Burner", 2, 0], ["Mirror", 3, 0], ["Chest", 5, 0]]:
		ok_place = MachineBase.place_machine(String(e[0]), c0 + Vector2i(int(e[1]), int(e[2]))) and ok_place
	ok("лагерь поставлен", ok_place)
	ok("фабрика больше не ставится",
			not MachineBase.place_machine("Smelter", c0 + Vector2i(4, 0))
			and not MachineBase.place_machine("Turret", c0 + Vector2i(1, 2))
			and not MachineBase.place_machine("Belt", c0 + Vector2i(6, 0)))
	var src: Chest = World.machines.get(c0)
	var dst: Chest = World.machines.get(c0 + Vector2i(5, 0))
	var burner: Burner = World.machines.get(c0 + Vector2i(2, 0))
	if not ok_place or src == null or dst == null or burner == null:
		_cleanup(slot0)
		return
	burner.add_fuel(IDs.I.COAL, 4)
	src.receive_item(IDs.I.COPPER_ORE, 30)
	# Чертёж в файл: после F9 панель должна показать тот же рецепт.
	# Первый доступный — смеситель (#165).
	Game.give_next_blueprint()
	# Решётка на вентиляции. Шлюз в новом файле остаётся тайлом (конверсия —
	# только если в файле есть фабрика).
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
	Game.set_objective_stage(Game.OBJECTIVE_STAGES)
	var burn0: float = burner.burn_left
	var got: bool = await wait_until(func() -> bool:
		var b: Burner = World.machines.get(c0 + Vector2i(2, 0))
		return b != null and b.burn_left > 0.0 and b.burn_left < burn0, 3.0)
	ok("горелка жжёт уголь", got, "осталось %.1f" % burner.burn_left)

	# Снимки — в тот же кадр, что и клавиша (сигналы UI): дальше фабрика едет.
	var cap: Dictionary = {}
	var on_saved: Callable = func() -> void:
		cap["saved"] = Save.gather()
		var b: Burner = World.machines.get(c0 + Vector2i(2, 0))
		cap["burn"] = b.burn_left if b != null else -1.0
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
	var burn_at_save: float = float(cap["burn"])
	print("  [замер] F5: %.1f мс, файл %.1f КБ (несжато %.1f КБ)" % [Save.last_save_ms,
			float(Save.last_size) / 1024.0, float(Save.last_raw_size) / 1024.0])

	# --- Меняем мир: разбираем зеркало, копаем, трогаем инвентарь и данные.
	var mir: MachineBase = World.machines.get(c0 + Vector2i(3, 0))
	if mir != null:
		mir.destroy()
	for x in range(bx - 8, bx + 8):
		World.set_tile(x, base + 3, IDs.T.AIR)
	player.inv.add(IDs.I.STONE, 50)
	player.global_position += Vector2(200.0, -40.0)
	Game.blueprints = PackedStringArray()
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
	ok("зеркало вернулось", World.machines.get(c0 + Vector2i(3, 0)) is Mirror)
	ok("турель не вернулась", World.machines.get(c0 + Vector2i(1, 2)) == null)
	ok("шлюз свежего файла на месте", World.airlocks.has(lock) and World.get_tile_v(lock) == IDs.T.AIRLOCK)
	ok("решётка вернулась с прежним HP", grate.x < 0 or (World.is_vent_sealed(grate)
			and World.vents_sealed[grate] == snap["world"]["vents_sealed"][grate]),
			"HP %s" % str(World.vents_sealed.get(grate)))
	ok("этап релея вернулся", Game.relay_active and Game.objective_stage == Game.OBJECTIVE_STAGES,
			"этап %d, %.1f с" % [Game.objective_stage, Game.relay_timer])
	for sec in ["world", "machines", "items", "player", "game", "tech", "threat"]:
		ok("«%s» как при F5" % sec, var_to_bytes(after[sec]) == var_to_bytes(snap[sec]))
	ok("герой там же, инвентарь тот же", after["player"]["pos"] == snap["player"]["pos"]
			and after["player"]["inv"] == snap["player"]["inv"])
	var back: Burner = World.machines.get(c0 + Vector2i(2, 0))
	if back == null:
		_cleanup(slot0)
		return
	var left0: float = back.burn_left
	got = await wait_until(func() -> bool:
		var b: Burner = World.machines.get(c0 + Vector2i(2, 0))
		return b != null and b.burn_left < left0 and b.burn_left < burn_at_save, 4.0)
	ok("после загрузки горелка продолжает жечь", got,
			"осталось %.1f → %.1f (в файле %.1f)" % [left0, back.burn_left, burn_at_save])
	ok("чертёж из сохранения на месте", Game.has_blueprint(IDs.I.MIXER), str(Game.blueprints))
	var panel: InventoryPanel = UI.panel
	panel.open(player)
	panel.station_tab = 0
	panel._cache_size = -1
	player.inv.mark_seen(IDs.I.IRON_INGOT)
	player.inv.mark_seen(IDs.I.COAL)
	panel._check_cache()
	var shown: bool = false
	for r in panel._recipes("hand"):
		if int(r["out"]) == IDs.I.MIXER:
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

