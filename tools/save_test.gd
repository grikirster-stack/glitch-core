extends SceneTree
class_name SaveTest
## Сохранение и загрузка забега (issue #37, ADR-001 PR-N).
##
## На каждом сиде: лагерь света (сундук, горелка, зеркало, маяк, коллектор),
## вода течёт в выкопанную яму, открыт кусок тумана, у героя инвентарь
## и кулдауны, на земле предмет и мешок, Game/Tech с прогрессом. Дальше:
##   снимок → файл → мир меняется (тайлы, вода, туман, машины, инвентарь,
##   Game/Tech; во втором раунде — вообще другой сид) → загрузка → снимок.
## Снимки должны совпасть побайтно (var_to_bytes) — целиком и по разделам, а
## файл — с кодировкой снимка после загрузки. После загрузки горелка жжёт уголь.
## Плюс: битый файл не загружается и не трогает мир.
##
## Отдельный запуск (три сида CI в одном процессе):
##   godot --headless --path . --script res://tools/save_test.gd
##   godot --headless --path . --script res://tools/save_test.gd -- --seed=4242   (один сид)
## В составе --test те же проверки идут на сиде прогона (секция «== Сохранение ==»).
##
## Как и в power_test.gd: в режиме --script имена автозагрузок на этапе
## компиляции недоступны — узлы берём через get_node(), Save — через load().

const SEEDS: Array = [31337, 4242, 12345]
const SLOT: String = "selftest"
## Разделы снимка, которые сверяем по отдельности (чтобы провал говорил, где).
const SECTIONS: Array = ["world", "machines", "items", "player", "game", "tech", "threat"]


class Runner extends Node:
	var host: Node = null
	var scene: Node = null
	var world = null
	var game = null
	var tech = null
	var save_s: GDScript = null

	var checks: int = 0
	var fails: int = 0
	var done: bool = false

	var _seeds: Array = []
	var _step: int = 0
	var _wait_until_ms: int = 0
	var _round: int = 0          ## 0 — меняем мир на месте, 1 — грузим поверх другого сида
	var _seed: int = 0
	var _snap: Dictionary = {}
	var _c0: Vector2i = Vector2i.ZERO
	var _state0: int = 0
	var _slot0: String = "1"
	var _grate: Vector2i = Vector2i(-1, -1)
	var _lit_at_save: bool = false
	var _fuel_at_load: float = 0.0
	var _work_at_load: float = 0.0
	var _ms_save: Array = []
	var _ms_load: Array = []
	var _sizes: Array = []
	var _raw_sizes: Array = []


	func _init(p_host: Node = null) -> void:
		host = p_host


	func start(main_scene: Node, seeds: Array) -> void:
		scene = main_scene
		world = scene.get_node("/root/World")
		game = scene.get_node("/root/Game")
		tech = scene.get_node("/root/Tech")
		save_s = load("res://scripts/core/save.gd")
		_seeds = seeds.duplicate()
		_state0 = int(game.state)
		_slot0 = String(save_s.slot)
		save_s.slot = SLOT
		print("== Сохранение ==")
		_next(1, 0.1)


	func _ok(label: String, cond: bool, extra: String = "") -> void:
		checks += 1
		if cond:
			print("  OK   %s %s" % [label, extra])
		else:
			fails += 1
			print("  FAIL %s %s" % [label, extra])


	func _next(s: int, secs: float = 0.0) -> void:
		_step = s
		_wait_until_ms = Time.get_ticks_msec() + int(secs * 1000.0)


	func _process(_delta: float) -> void:
		if done or Time.get_ticks_msec() < _wait_until_ms:
			return
		match _step:
			1: _s_setup()
			2: _s_save_and_load()
			3: _s_running()
			_: _finish()


	# ------------------------------------------------------------------ шаги

	## Новый мир по сиду (или следующий раунд на том же) и фабрика на нём.
	func _s_setup() -> void:
		if _round == 0:
			if _seeds.is_empty():
				_next(99)
				return
			_seed = int(_seeds.pop_front())
		print("  -- сид %d, раунд %d (%s)" % [_seed, _round + 1,
				"мир меняется на месте" if _round == 0 else "загрузка поверх другого сида"])
		save_s._clear_world_nodes()
		if world.tilemap:
			world.tilemap.clear()
		world.generate(_seed)
		game.reset_run()
		game.tasks_total = world.terminals.size()
		_build_factory()
		_next(2, 1.5)   # горелка погорела, вода потекла


	func _s_save_and_load() -> void:
		var p = game.player
		var fl0 = world.machines.get(_c0 + Vector2i(8, 3))
		_lit_at_save = fl0 != null and bool(fl0.lit)
		_snap = save_s.gather()
		var saved: bool = save_s.save_game(SLOT)
		_ok("файл записан", saved, "%s %s" % [save_s.path_for(SLOT), save_s.last_error])
		_ok("файл — свой у процесса (#132: параллельные прогоны не делят слот)", TestEnv.suffix() != ""
				and save_s.path_for(SLOT).ends_with("%s.sav" % TestEnv.suffix()))
		if not saved:
			_after_round()
			return
		_ms_save.append(save_s.last_save_ms)
		_sizes.append(save_s.last_size)
		_raw_sizes.append(save_s.last_raw_size)
		var file_bytes: PackedByteArray = FileAccess.get_file_as_bytes(save_s.path_for(SLOT))

		_mutate()
		var mutated: Dictionary = save_s.gather()
		var differs: Array = []
		for s in SECTIONS:
			if var_to_bytes(mutated.get(s)) != var_to_bytes(_snap.get(s)):
				differs.append(s)
		_ok("мир после правок отличается от сохранённого (тест не пустой)",
				differs.size() == SECTIONS.size(), "разделы: %s" % ", ".join(differs))

		var loaded: bool = save_s.load_game(SLOT)
		_ok("файл загружен", loaded, save_s.last_error)
		if not loaded:
			_after_round()
			return
		_ms_load.append(save_s.last_load_ms)
		var after: Dictionary = save_s.gather()
		_ok("сид мира вернулся", int(world.world_seed) == _seed, "сид %d" % int(world.world_seed))
		for s in SECTIONS:
			var a: PackedByteArray = var_to_bytes(_snap.get(s))
			var b: PackedByteArray = var_to_bytes(after.get(s))
			_ok("раздел «%s» побайтно равен" % s, a == b, "%d байт" % a.size() if a == b
					else _diff_hint(s, _snap.get(s), after.get(s)))
		var w0: Dictionary = _snap["world"]
		_ok("тайлы равны", world.tiles == w0["tiles"])
		_ok("вода равна (уровни и очередь)", world.fluid == w0["fluid"]
				and world.fluid_pending() == PackedInt32Array(w0["fluid_queue"]).size())
		_ok("туман равен, счётчик открытых клеток пересчитан", world.explored == w0["explored"]
				and int(world.explore_cells) == PackedByteArray(w0["explored"]).count(1),
				"открыто %d" % int(world.explore_cells))
		_ok("картинка и сетка пути совпадают с тайлами", _grid_synced(), _grid_hint)
		_ok("машин столько же",world.machines.size() == Array(_snap["machines"]).size(),
				"%d" % world.machines.size())
		_ok("весь снимок побайтно равен", var_to_bytes(_snap) == var_to_bytes(after))
		_ok("файл = кодировка мира после загрузки", save_s.encode(after) == file_bytes,
				"%d байт" % file_bytes.size())
		var mir = world.machines.get(_c0 + Vector2i(3, 0))
		_ok("зеркало вернулось", mir != null and String(mir.kind) == "Mirror")
		var bag_ok: bool = false
		for it in Array(after["items"]):
			if not Array(it["bag"]).is_empty():
				bag_ok = true
		_ok("мешок после смерти вернулся", bag_ok)
		_ok("тайники руин снова ссылаются на сундуки", _ruin_links_ok())
		# Оборона (#31), релей (#32), небесный тайник (#60).
		var ph = world.machines.get(_c0 + Vector2i(2, 2))
		_ok("маяк вернулся с hp", ph != null and String(ph.kind) == "Pharos"
				and is_equal_approx(float(ph.hp), float(_snap_machine("Pharos").get("hp", -1.0))),
				"hp %.1f" % (float(ph.hp) if ph != null else -1.0))
		var col = world.machines.get(_c0 + Vector2i(0, 3))
		_ok("коллектор вернулся", col != null and String(col.kind) == "Collector"
				and int(col.dir) == int(_snap_machine("Collector").get("dir", -1)))
		_ok("шлюз в реестре", world.airlocks.has(_c0 + Vector2i(8, 0)))
		_ok("решётка запечатала вентиляцию с прежним HP", _grate.x < 0 or (world.is_vent_sealed(_grate)
				and float(world.vents_sealed[_grate]) < float(Balance.GRATE_HP)),
				"HP %s" % str(world.vents_sealed.get(_grate)))
		_ok("этап релея вернулся", int(game.objective_stage) == 3 and bool(game.relay_active)
				and is_equal_approx(float(game.relay_timer), float(_snap["game"]["relay_timer"])))
		var wreck = world.sky_cache.get("wreck")
		_ok("небесный тайник: открыт, ссылка на сундук", wreck == null or (bool(wreck.opened)
				and wreck.chest != null and wreck.chest == world.machines.get(world.sky_cache["cell"])
				and world.sky_cache["chest"] == wreck.chest))
		var gen = world.machines.get(_c0 + Vector2i(2, 0))
		_fuel_at_load = float(gen.burn_left) if gen != null else 0.0
		_work_at_load = _total_work()
		if p != null:
			p.invuln = 1.0e9
		_next(3, 1.5)


	## Горелка после загрузки продолжает жечь уголь.
	func _s_running() -> void:
		var gen = world.machines.get(_c0 + Vector2i(2, 0))
		_ok("горелка жжёт уголь после загрузки", gen != null and float(gen.burn_left) < _fuel_at_load,
				"пламя %.2f → %.2f" % [_fuel_at_load, float(gen.burn_left) if gen != null else -1.0])
		_ok("машины работают после загрузки", _total_work() > _work_at_load + 0.5,
				"наработка %.2f → %.2f с" % [_work_at_load, _total_work()])
		if _round == 0:
			_corrupt_case()
			_versions_case()   # MP-I (#94): версия 1 читается, версия 2 с игроками — в одиночной
		_after_round()


	func _after_round() -> void:
		_round += 1
		if _round > 1:
			_round = 0
		_next(1, 0.1)


	func _finish() -> void:
		save_s.remove(SLOT)
		save_s.slot = _slot0
		if not _ms_save.is_empty():
			print("  [замер] сохранение: %s мс; загрузка: %s мс; файл: %s КБ (несжато %s КБ)"
					% [_fmt(_ms_save), _fmt(_ms_load), _fmt_kb(_sizes), _fmt_kb(_raw_sizes)])
		var p = game.player
		if p != null:
			p.invuln = 0.0
		game.relay_active = false
		game.state = _state0
		done = true
		_step = 0


	# ------------------------------------------------------------------ мир

	## Лагерь света у базы и остальное состояние забега. Фабрика не ставится (#170).
	func _build_factory() -> void:
		var bx: int = world.beacon_cell.x
		var base: int = world.beacon_cell.y
		_c0 = Vector2i(bx - 36, base + 6)
		for x in range(_c0.x - 1, _c0.x + 9):
			for y in range(_c0.y - 1, _c0.y + 6):
				world.set_tile(x, y, IDs.T.AIR)
		var mb: GDScript = load("res://scripts/machines/machine_base.gd")
		var plan: Array = [
			["Chest", Vector2i(0, 0)], ["Burner", Vector2i(2, 0)], ["Mirror", Vector2i(3, 0)],
			["Chest", Vector2i(5, 0)], ["Pharos", Vector2i(2, 2)], ["Collector", Vector2i(0, 3)],
			["Accumulator", Vector2i(5, 2)], ["Prism", Vector2i(6, 3)], ["Mixer", Vector2i(7, 3)],
		]
		var placed: int = 0
		for e in plan:
			if mb.place_machine(String(e[0]), _c0 + Vector2i(e[1])):
				placed += 1
		_ok("лагерь поставлен", placed == plan.size(), "%d из %d" % [placed, plan.size()])
		_ok("бур больше не ставится", not mb.place_machine("Drill", _c0 + Vector2i(8, 4)))
		var src = world.machines.get(_c0)
		if src != null:
			src.receive_item(IDs.I.SAND, 6)
			src.receive_item(IDs.I.COPPER_ORE, 30)
		var burner = world.machines.get(_c0 + Vector2i(2, 0))
		if burner != null:
			burner.add_fuel(IDs.I.COAL, 4)
		var mir = world.machines.get(_c0 + Vector2i(3, 0))
		if mir != null:
			mir.hp = 61.0
		var col = world.machines.get(_c0 + Vector2i(0, 3))
		if col != null:
			col.turn()
		var ph = world.machines.get(_c0 + Vector2i(2, 2))
		if ph != null:
			ph.hp = 61.0
		# Оборона (#31): шлюз в площадке и решётка на вентиляции с надкусанным HP.
		world.set_tile(_c0.x + 8, _c0.y, IDs.T.AIRLOCK)
		_grate = Vector2i(-1, -1)
		for v in world.vents:
			if world.get_tile_v(v) == IDs.T.AIR:
				_grate = v
				break
		if _grate.x >= 0:
			world.set_tile(_grate.x, _grate.y, IDs.T.VENT_GRATE)
			world.damage_grate(_grate, 7.5)
		# Небесный тайник (#60): сундук уже открывали, обрывок выдан.
		var wreck = world.sky_cache.get("wreck")
		if wreck != null:
			wreck.opened = true
			wreck.announced = true
		# Вода: яма у первой лужи на поверхности — вода потечёт и встанет в очередь.
		_dig_near_water()
		# Туман: кусок пещер открыт.
		world.reveal_around(_c0 + Vector2i(0, 20), 9)
		# Герой: инвентарь, хотбар, кулдауны укрытия.
		var p = game.player
		if p != null:
			p.invuln = 1.0e9
			p.global_position = world.spawn_point
			p.inv.add(IDs.I.SCRAP, 17)
			p.inv.add(IDs.I.IRON_INGOT, 9)
			p.inv.selected = 3
			p.hide_cd = 4.25
			p.hp = 73.0
		# Game и Tech с прогрессом, терминал прочитан.
		game.blueprints = PackedStringArray(["STEEL_WALL"])
		game.day_number = 3
		game.time_of_day = 0.31
		game.stats_mined = 41
		game.tasks_done = 1
		game.objective_stage = 3
		game.relay_active = true          # этап релея (#32): сигнал держится
		game.relay_timer = 151.5
		if not world.terminals.is_empty():
			world.terminals.remove_at(0)
		tech.read_chapters = [0, 3]
		tech.fragments = ["обрывок для теста"]
		# Предмет на земле и мешок с хотбаром.
		var ie: GDScript = load("res://scripts/entities/item_entity.gd")
		var item = ie.new()
		item.item_id = IDs.I.IRON_ORE
		item.count = 5
		item.global_position = world.cell_to_world(_c0 + Vector2i(-6, 0))
		world.add_world_node(item)
		var bag = ie.new()
		bag.bag = [[IDs.I.COAL, 4], [IDs.I.LAMP, 1]]
		bag.item_id = IDs.I.COAL
		bag.despawn = false
		bag.global_position = world.cell_to_world(_c0 + Vector2i(-12, 0))
		world.add_world_node(bag)


	## Правки после сохранения: всё, что потом должно вернуться.
	func _mutate() -> void:
		if _round == 1:
			# Другой мир целиком: загрузка обязана пересоздать мир по сиду из файла.
			save_s._clear_world_nodes()
			if world.tilemap:
				world.tilemap.clear()
			world.generate(_seed + 1)
		for x in range(_c0.x - 4, _c0.x + 12):
			world.set_tile(x, _c0.y + 8, IDs.T.STONE)
		# Шлюз снят, решётка сломана, релей «отыграл».
		world.set_tile(_c0.x + 8, _c0.y, IDs.T.AIR)
		if _grate.x >= 0:
			world.damage_grate(_grate, 1.0e6)
		game.relay_active = false
		game.relay_timer = 0.0
		world.reveal_around(world.beacon_cell + Vector2i(0, 60), 12)
		var mb: GDScript = load("res://scripts/machines/machine_base.gd")
		var victim = world.machines.get(_c0 + Vector2i(6, 3))
		if victim != null:
			victim.destroy()
		mb.place_machine("Chest", _c0 + Vector2i(8, 4))
		var p = game.player
		if p != null:
			p.inv.add(IDs.I.STONE, 40)
			p.inv.selected = 0
			p.hp = 12.0
			p.global_position += Vector2(160.0, 0.0)
		game.blueprints = PackedStringArray(["STEEL_WALL", "VENT_GRATE"])
		game.day_number += 4
		game.time_of_day = 0.8
		game.objective_stage = 0
		tech.read_chapters.append(5)
		var threat = scene.get_node("/root/Threat")
		threat.roster.append("echo")
		threat.budget += 9.0
		var ie: GDScript = load("res://scripts/entities/item_entity.gd")
		var junk = ie.new()
		junk.item_id = IDs.I.STONE
		junk.count = 3
		junk.global_position = world.cell_to_world(_c0 + Vector2i(-20, 0))
		world.add_world_node(junk)


	## Битый файл: загрузка отказывается и мир не трогает.
	func _corrupt_case() -> void:
		var path: String = save_s.path_for(SLOT + "_bad")
		var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		f.store_buffer("GCSV".to_ascii_buffer() + PackedByteArray([1, 0, 0, 0, 255, 255, 0, 0, 1, 2, 3]))
		f.close()
		var before: PackedByteArray = var_to_bytes(save_s.gather())
		var loaded: bool = save_s.load_game(SLOT + "_bad")
		_ok("битый файл не загружается", not loaded, save_s.last_error)
		_ok("битый файл не трогает мир", var_to_bytes(save_s.gather()) == before)
		save_s.remove(SLOT + "_bad")


	## Версии формата (ADR-002 § 4.9, MP-I #94): файл версии 1 (до сети, без вклада в
	## релей) грузится как одиночный; версия 2 с разделами session и players (сетевая
	## игра хоста) в одиночной берёт только player — чужие герои ни на что не влияют.
	func _versions_case() -> void:
		var p = game.player
		var d: Dictionary = save_s.gather()
		_ok("одиночное сохранение: версия %d, разделов сети нет" % int(save_s.VERSION),
				int(d["version"]) == int(save_s.VERSION) and not d.has("players") and not d.has("session"))
		var v1: Dictionary = d.duplicate(true)
		v1["version"] = 1
		(v1["game"] as Dictionary).erase("relay_have")
		var b1: PackedByteArray = save_s.encode(v1)
		b1.encode_u32(4, 1)
		_write(SLOT + "_v1", b1)
		var pos0: Vector2 = p.global_position
		p.global_position += Vector2(64, 0)
		game.relay_have = {IDs.I.IRON_PLATE: 5}
		var ok1: bool = save_s.load_game(SLOT + "_v1")
		_ok("файл версии 1 загружается", ok1, save_s.last_error)
		_ok("версия 1: герой на месте, вклада в релей нет", ok1 and p.global_position.distance_to(pos0) < 0.5
				and game.relay_have.is_empty(), str(game.relay_have))
		var v2: Dictionary = d.duplicate(true)
		v2["session"] = {"name": "Экспедиция", "max": 4}
		var other: Dictionary = (d["player"] as Dictionary).duplicate(true)
		other["pos"] = pos0 + Vector2(320, 0)
		v2["players"] = {777: {"nick": "Аня", "look": 3, "state": other, "stats": {"deaths": 1}, "dead": false}}
		_write(SLOT + "_v2", save_s.encode(v2))
		p.global_position += Vector2(64, 0)
		var ok2: bool = save_s.load_game(SLOT + "_v2")
		_ok("версия 2 с игроками сети в одиночной: только раздел player", ok2
				and p.global_position.distance_to(pos0) < 0.5 and scene.get_node("/root/Net").parked.is_empty(), save_s.last_error)
		save_s.remove(SLOT + "_v1")
		save_s.remove(SLOT + "_v2")
		_legacy_research_case()


	## Сохранение с main: поля research и tech.unlocked игнорируются, журнал
	## (read_chapters) восстанавливается, чертежей в старом файле нет (#169).
	func _legacy_research_case() -> void:
		var d: Dictionary = save_s.gather()
		(d["game"] as Dictionary)["research"] = 23
		(d["game"] as Dictionary).erase("blueprints")
		(d["game"] as Dictionary)["objective_stage"] = 4
		(d["tech"] as Dictionary)["unlocked"] = ["T0", "T1", "T2"]
		(d["tech"] as Dictionary)["read_chapters"] = [0, 2]
		_write(SLOT + "_legacy", save_s.encode(d))
		game.blueprints = PackedStringArray(["STEEL_WALL"])
		tech.read_chapters = []
		var ok_l: bool = save_s.load_game(SLOT + "_legacy")
		_ok("старый файл с research/tech грузится", ok_l, save_s.last_error)
		_ok("research проигнорирован, чертежей нет", ok_l and game.blueprints.is_empty(), str(game.blueprints))
		_ok("журнал из старого файла восстановлен", ok_l and tech.read_chapters == [0, 2], str(tech.read_chapters))
		_ok("старый этап 4 сжат в 3", ok_l and game.objective_stage == 3, str(game.objective_stage))
		save_s.remove(SLOT + "_legacy")
		_legacy_factory_case()


	## Старый мир фабрики: машины не ставятся, предметы ложатся в сундук лагеря.
	## Классов бура и ТЭЦ уже нет — файл собираем словарём, как его писал бы v2.
	func _legacy_factory_case() -> void:
		var d: Dictionary = save_s.gather()
		var chest_cell: Vector2i = _c0
		var machines: Array = []
		for md in d.get("machines", []):
			if md is Dictionary and md.get("cell") == chest_cell:
				machines.append(md)
		machines.append({"kind": "CoalGen", "cell": _c0 + Vector2i(4, 2), "hp": 40.0})
		machines.append({"kind": "Turret", "cell": _c0 + Vector2i(4, 3), "hp": 40.0})
		machines.append({"kind": "Belt", "cell": _c0 + Vector2i(4, 4), "hp": 20.0})
		machines.append({"kind": "Belt", "cell": _c0 + Vector2i(5, 4), "hp": 20.0})
		machines.append({"kind": "Belt", "cell": _c0 + Vector2i(6, 4), "hp": 20.0})
		d["machines"] = machines
		var pd: Dictionary = d["player"]
		var slots: Array = Array(pd.get("inv", [])).duplicate(true)
		var placed_plate: bool = false
		for i in slots.size():
			var e = slots[i]
			if e is Array and int(e[1]) == 0:
				slots[i] = [IDs.I.IRON_PLATE, 1]
				placed_plate = true
				break
		if not placed_plate:
			slots.append([IDs.I.IRON_PLATE, 1])
		pd["inv"] = slots
		_write(SLOT + "_factory", save_s.encode(d))
		var ok_f: bool = save_s.load_game(SLOT + "_factory")
		var chest = world.machines.get(chest_cell)
		var got_burner: bool = false
		var got_pharos: bool = false
		var got_ingot: bool = false
		if chest != null:
			for s in chest.slots:
				if s.is_empty():
					continue
				if s.id == IDs.I.BURNER:
					got_burner = true
				if s.id == IDs.I.PHAROS:
					got_pharos = true
				if s.id == IDs.I.IRON_INGOT and s.count >= 2:
					got_ingot = true
		_ok("старая фабрика грузится без падения", ok_f, save_s.last_error)
		_ok("ТЭЦ стала горелкой в сундуке", ok_f and got_burner)
		_ok("турель стала маяком в сундуке", ok_f and got_pharos)
		_ok("три ленты — два слитка (вверх на весь файл)", ok_f and got_ingot)
		_ok("пластина в инвентаре стала двумя слитками", ok_f
				and game.player.inv.count_of(IDs.I.IRON_PLATE) == 0
				and game.player.inv.count_of(IDs.I.IRON_INGOT) >= 2)
		save_s.remove(SLOT + "_factory")


	func _write(s: String, bytes: PackedByteArray) -> void:
		var f: FileAccess = FileAccess.open(save_s.path_for(s), FileAccess.WRITE)
		f.store_buffer(bytes)
		f.close()


	func _dig_near_water() -> void:
		for x in range(4, world.W - 4):
			var top: int = int(world.surface[x])
			for y in range(maxi(0, top - 12), top + 2):
				if world.get_tile(x, y) == IDs.T.WATER and world.get_tile(x + 1, y) != IDs.T.WATER \
						and world.get_tile(x + 1, y) != IDs.T.AIR:
					for dy in range(0, 3):
						world.set_tile(x + 1, y + dy, IDs.T.AIR)
					return


	var _grid_hint: String = ""

	## Тайлмап и сетка поиска пути после загрузки — те же, что у тайлов в памяти
	## (загрузка правит их только в изменённых клетках — проверяем весь мир).
	func _grid_synced() -> bool:
		for y in world.H:
			for x in world.W:
				var id: int = world.tiles[y * world.W + x]
				var c: Vector2i = Vector2i(x, y)
				# Вариант клетки (биом, маска соседей — ADR-003 V1) считает сам мир.
				var want: Vector2i = Vector2i(-1, -1) if id == IDs.T.AIR else world.cell_atlas(x, y)
				if world.tilemap.get_cell_atlas_coords(c) != want:
					_grid_hint = "тайлмап в %s" % str(c)
					return false
				if world.astar.is_point_solid(c) != bool(world.is_phantom_solid_cell(c)):
					_grid_hint = "сетка пути в %s" % str(c)
					return false
		_grid_hint = "изменено клеток при загрузке: %d" % int(world.load_changed_cells)
		return true


	func _total_work() -> float:
		var t: float = 0.0
		for m in world.machines.values():
			if is_instance_valid(m):
				t += float(m.work_time)
		return t


	## Запись машины вида kind из сохранённого снимка ({} — нет такой).
	func _snap_machine(kind: String) -> Dictionary:
		for md in Array(_snap.get("machines", [])):
			if String(md.get("kind", "")) == kind:
				return md
		return {}


	func _ruin_links_ok() -> bool:
		for rc in world.ruin_caches:
			var ch = world.machines.get(rc["cell"])
			if ch == null or rc["chest"] != ch:
				return false
		return true


	## Подсказка, где расходятся разделы (первое различие).
	func _diff_hint(name: String, a, b) -> String:
		if a is Dictionary and b is Dictionary:
			for k in a.keys():
				if not b.has(k) or var_to_bytes(a[k]) != var_to_bytes(b[k]):
					return "%s.%s: %s ≠ %s" % [name, str(k), str(a[k]).left(80), str(b.get(k)).left(80)]
		if a is Array and b is Array:
			if a.size() != b.size():
				return "%s: %d ≠ %d записей" % [name, a.size(), b.size()]
			for i in a.size():
				if var_to_bytes(a[i]) != var_to_bytes(b[i]):
					return "%s[%d]: %s ≠ %s" % [name, i, str(a[i]).left(120), str(b[i]).left(120)]
		return "%s различается" % name


	func _fmt(a: Array) -> String:
		var parts: PackedStringArray = PackedStringArray()
		for v in a:
			parts.append("%.1f" % float(v))
		return "/".join(parts)


	func _fmt_kb(a: Array) -> String:
		var parts: PackedStringArray = PackedStringArray()
		for v in a:
			parts.append("%.1f" % (float(v) / 1024.0))
		return "/".join(parts)


# ------------------------------------------------------------- отдельный запуск

var _runner: Node = null
var _scene: Node = null
var _started: bool = false
var _seeds: Array = SEEDS.duplicate()


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			_seeds = [int(a.substr(7))]


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		seed(int(_seeds[0]))
		_scene = load("res://scenes/main.tscn").instantiate()
		root.add_child(_scene)
		current_scene = _scene
		_runner = Runner.new(null)
		root.add_child(_runner)
		_runner.start(_scene, _seeds)
		return false
	if _runner == null:
		return false
	if _runner.done:
		print("")
		print("ИТОГ: проверок %d, провалов %d" % [_runner.checks, _runner.fails])
		quit(1 if _runner.fails > 0 else 0)
		return true
	return false
