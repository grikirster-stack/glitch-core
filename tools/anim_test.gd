extends SceneTree
class_name AnimTest
## Автотест процедурной анимации: игрок, фантом, постройки, эффекты, релей.
##
## Отдельный запуск:
##   godot --headless --path . --script res://tools/anim_test.gd -- --seed=31337
## В составе общего прогона те же самые проверки вызывает tools/test_runner.gd
## (секция «== Анимации ==») — общий код, без дублирования.
##
## AnimationPlayer в проекте нет: вся графика рисуется кодом, а анимация живёт
## в обычных переменных, которые меняются в _process/_physics_process.
## Поэтому проверяем именно значения: растут, затухают, осциллируют, не
## застревают и не превращаются в NaN/бесконечность.
##
## Внимание: файл запускается как главный цикл движка (--script), а в этом
## режиме глобальные имена автозагрузок (World/Game/DB/UI) на этапе компиляции
## ещё недоступны — поэтому все узлы берём через get_node().

const DARK_MAX: float = 0.4        ## максимальный свет в точке, где фантом не убегает
const RING_TTL: float = 0.7        ## TTL кольца импульса, с
const SLASH_TTL: float = 0.22       ## TTL взмаха, с
const CHIP_COUNT: int = 4          ## частиц на один вызов spawn_chip
const PARTICLES_LIMIT: int = 1000  ## предел проверки «лимиты соблюдаются»


## --------------------------------------------------------------------- исполнитель
class Runner extends Node:
	## Узел, который выполняет проверки. Живёт в дереве сцены и сам себя
	## добавляет по таймеру: шаги с паузами по реальному времени (в headless
	## частота кадров не гарантирована, а симуляция идёт по delta).
	var host: Node = null          ## кто-то снаружи (test_runner) — для совместимости
	var scene: Node = null
	var player: Node = null
	var world_fx: Node = null
	var world = null                ## узел автозагрузки World
	var db = null                   ## узел автозагрузки DB
	var game = null                 ## узел автозагрузки Game

	var checks: int = 0
	var fails: int = 0
	var step: int = 0
	var done: bool = false

	var _wait_until_ms: int = 0
	var _sky_y: float = 0.0
	var _walk0: float = 0.0
	var _walk1: float = 0.0
	var _walk_samples: Array = []
	var _mine_cell: Vector2i = Vector2i(-1, -1)
	var _dark_cell: Vector2i = Vector2i(-1, -1)
	var _phantom: Node = null
	var _hp0: float = 0.0
	var _jitter0: float = 0.0
	var _jitter1: float = 0.0
	var _task0: float = 0.0
	var _breath0: float = 0.0
	var _pulse_min: float = 2.0
	var _pulse_max: float = -1.0
	var _placed: Array = []
	var _gen: Node = null
	var _smelter: Node = null
	var _belt: Node = null
	var _belt_pos0: float = 0.0
	var _fx_base: int = 0
	var _rings_base: int = 0
	var _slashes_base: int = 0
	var _light_grid: PackedFloat32Array = PackedFloat32Array()
	var _phantom_script: GDScript = null
	var _ph_enum: Dictionary = {}


	func _init(p_host: Node = null) -> void:
		host = p_host


	## Запуск: main_scene — корень сцены игры (у него есть player и world_fx).
	func start(main_scene: Node) -> void:
		scene = main_scene
		print("== Анимации ==")
		_next(1, 0.2)


	func _ok(label: String, cond: bool, extra: String = "") -> void:
		checks += 1
		if cond:
			print("  OK   %s %s" % [label, extra])
		else:
			fails += 1
			print("  FAIL %s %s" % [label, extra])


	func _next(s: int, secs: float = 0.1) -> void:
		step = s
		_wait_until_ms = Time.get_ticks_msec() + int(secs * 1000.0)


	func _process(_delta: float) -> void:
		if done:
			return
		# Пока идёт замер шага — подвешиваем игрока в воздухе, чтобы гравитация
		# не сбивала замер (ходьба по воздуху, а не по поверхности).
		if step == 3 and player:
			player.global_position.y = _sky_y
			player.vel.y = 0.0
			_walk_samples.append(sin(float(player.walk_anim)) * 2.0)
		# Пульс релея — величина от Time.get_ticks_msec(), снимаем её пока идёт замер.
		if step == 26:
			var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.003)
			_pulse_min = minf(_pulse_min, pulse)
			_pulse_max = maxf(_pulse_max, pulse)
		if Time.get_ticks_msec() < _wait_until_ms:
			return
		match step:
			1: _s_setup()
			2: _s_walk_start()
			3: _s_walk_check()
			4: _s_idle_start()
			5: _s_idle_check()
			6: _s_face_right()
			7: _s_face_left()
			8: _s_mining()
			9: _s_interact()
			10: _s_breath_start()
			11: _s_breath_check()
			12: _s_phantom_setup()
			13: _s_phantom_jitter()
			14: _s_phantom_chase()
			15: _s_phantom_damage()
			16: _s_phantom_stun()
			17: _s_machines_setup()
			18: _s_machines_power()
			19: _s_machines_progress()
			20: _s_machines_belt()
			21: _s_fx_spawn()
			22: _s_fx_ttl()
			23: _s_fx_limit()
			24: _s_fx_limit_wait()
			25: _s_pulse_start()
			26: _s_pulse_check()
			27: _s_general()
			_: _finish()


	# ------------------------------------------------------------------ игрок

	func _s_setup() -> void:
		world = get_tree().root.get_node("World")
		db = get_tree().root.get_node("DB")
		game = get_tree().root.get_node("Game")
		player = scene.get("player")
		world_fx = scene.get("world_fx")
		_ok("игрок доступен", player != null)
		_ok("эффекты мира доступны", world_fx != null)
		_ok("мир сгенерирован", world != null and world.tiles.size() == world.W * world.H)
		if player == null or world_fx == null or world == null:
			_finish()
			return
		# Фантомы не должны убить игрока посреди замеров.
		player.invuln = 99999.0
		player.hp = player.MAX_HP
		_sky_y = float(world.cell_to_world(Vector2i(300, 6)).y)
		_build_light_grid()
		_find_dark_cell()
		_find_mine_cell()
		_ok("найдено тёмное место для фантома", _dark_cell.x >= 0, str(_dark_cell))
		_ok("найден тайл для добычи", _mine_cell.x >= 0, str(_mine_cell))
		_next(2)


	func _s_walk_start() -> void:
		player.global_position = world.cell_to_world(Vector2i(300, 6))
		player.vel = Vector2.ZERO
		_walk0 = float(player.walk_anim)
		_walk_samples.clear()
		_press(KEY_D)
		_next(3, 0.7)


	func _s_walk_check() -> void:
		var w: float = float(player.walk_anim)
		_ok("фаза шага растёт при ходьбе", w > _walk0 + 0.5,
				"walk_anim %.2f -> %.2f" % [_walk0, w])
		var has_up: bool = false
		var has_down: bool = false
		for s in _walk_samples:
			if float(s) > 0.5:
				has_up = true
			elif float(s) < -0.5:
				has_down = true
		_ok("фаза шага осциллирует", has_up and has_down,
				"замеров %d, вверх %s, вниз %s" % [_walk_samples.size(), has_up, has_down])
		_ok("фаза шага конечна", is_finite(w), "walk_anim=%.3f" % w)
		_release(KEY_D)
		_next(4, 0.5)


	func _s_idle_start() -> void:
		_walk1 = float(player.walk_anim)
		_next(5, 0.3)


	func _s_idle_check() -> void:
		var d: float = float(player.walk_anim) - _walk1
		_ok("фаза шага не растёт без движения", absf(d) < 0.001,
				"прирост %.5f за 0.3 с, скорость %.2f" % [d, player.vel.x])
		_next(6)


	func _s_face_right() -> void:
		_press(KEY_D)
		_next(7, 0.25)


	func _s_face_left() -> void:
		_ok("взгляд вправо при движении вправо", int(player.facing) == 1, "facing=%d" % int(player.facing))
		_release(KEY_D)
		_press(KEY_A)
		_next(8, 0.25)


	func _s_mining() -> void:
		_ok("взгляд влево при движении влево", int(player.facing) == -1, "facing=%d" % int(player.facing))
		_release(KEY_A)
		if _mine_cell.x < 0:
			_next(9)
			return
		player.mining_cell = Vector2i(-1, -1)
		player.mining_progress = 0.0
		player._do_mining(_mine_cell, 0.25)
		_ok("прогресс копания растёт", float(player.mining_progress) > 0.0,
				"progress=%.3f" % float(player.mining_progress))
		var guard: int = 0
		while world.get_tile_v(_mine_cell) != IDs.T.AIR and guard < 40:
			player._do_mining(_mine_cell, 0.25)
			guard += 1
		_ok("тайл пробит", world.get_tile_v(_mine_cell) == IDs.T.AIR, "вызовов %d" % guard)
		_ok("прогресс копания сброшен", float(player.mining_progress) <= 0.0001,
				"progress=%.4f" % float(player.mining_progress))
		_next(9)


	func _s_interact() -> void:
		player.task_progress = 0.0
		_task0 = float(player.task_progress)
		# Ставим игрока к терминалу (или к релею, если терминалов нет).
		var target: Vector2 = Vector2.ZERO
		var terminals: Array = world.terminals
		if terminals.size() > 0:
			target = world.cell_to_world(terminals[0])
		else:
			target = world.cell_to_world(world.beacon_cell)
		player.global_position = target
		player.vel = Vector2.ZERO
		player._do_interact(0.5)
		_ok("прогресс задачи растёт при взаимодействии", float(player.task_progress) > _task0,
				"progress=%.3f" % float(player.task_progress))
		_next(10)


	func _s_breath_start() -> void:
		_breath0 = float(player._breath)
		_next(11, 0.3)


	func _s_breath_check() -> void:
		var b: float = float(player._breath)
		_ok("дыхание растёт", b > _breath0, "breath %.2f -> %.2f" % [_breath0, b])
		_next(12)


	# ----------------------------------------------------------------- фантом

	func _s_phantom_setup() -> void:
		if _dark_cell.x < 0:
			_next(13)
			return
		player.global_position = world.cell_to_world(_dark_cell)
		player.vel = Vector2.ZERO
		# Скрипт фантома грузим в рантайме: в режиме --script глобальные имена
		# автозагрузок на этапе компиляции ещё недоступны (см. шапку файла).
		if _phantom_script == null:
			_phantom_script = load("res://scripts/entities/phantom.gd")
			_ph_enum = _phantom_script.get_script_constant_map().get("St", {})
		_phantom = _phantom_script.new()
		_phantom.player = player
		scene.add_child(_phantom)
		# Ищем позицию рядом с игроком: пол под ногами, нет света и прямая видимость.
		var offsets: Array = [Vector2(48, 0), Vector2(-48, 0), Vector2(64, 0),
				Vector2(-64, 0), Vector2(32, 0), Vector2(-32, 0), Vector2(16, 0)]
		for off in offsets:
			var p: Vector2 = player.global_position + off
			var c: Vector2i = world.world_to_cell(p)
			if world.get_tile_v(c) != IDs.T.AIR:
				continue
			if world.get_tile_v(c + Vector2i(0, 1)) == IDs.T.AIR:
				continue
			if float(world.light_at(c)) > 0.55:
				continue
			_phantom.global_position = p
			if bool(_phantom._has_los()):
				break
		_jitter0 = float(_phantom.jitter)
		_next(13, 0.3)


	func _s_phantom_jitter() -> void:
		if _phantom == null:
			_next(14)
			return
		_jitter1 = float(_phantom.jitter)
		_ok("джиттер фантома растёт", _jitter1 > _jitter0,
				"jitter %.3f -> %.3f" % [_jitter0, _jitter1])
		_ok("джиттер фантома конечен", is_finite(_jitter1), "jitter=%.3f" % _jitter1)
		_next(14, 1.2)


	func _s_phantom_chase() -> void:
		if _phantom == null:
			_next(15)
			return
		var st: int = int(_phantom.state)
		_ok("фантом переходит в погоню", st == int(_ph_enum.get("CHASE", 2)),
				"state=%d (DORMANT=%d ROAM=%d CHASE=%d FLEE=%d)"
				% [st, int(_ph_enum.get("DORMANT", 0)), int(_ph_enum.get("ROAM", 1)),
				int(_ph_enum.get("CHASE", 2)), int(_ph_enum.get("FLEE", 3))])
		# Цвет фантома в погоне должен отличаться от базового: сверяем константы
		# из исходника (сам draw недоступен из теста).
		var colors: Array = _phantom_colors()
		_ok("цвет фантома различается в погоне", colors.size() >= 2 and colors[0] != colors[1],
				"базовый %s, погоня %s" % [str(colors[0]) if colors.size() > 0 else "?",
				str(colors[1]) if colors.size() > 1 else "?"])
		_next(15)


	func _s_phantom_damage() -> void:
		if _phantom == null:
			_next(16)
			return
		_hp0 = float(_phantom.hp)
		_phantom.take_damage(50.0, Vector2.ZERO)
		_ok("урон снижает hp фантома", float(_phantom.hp) < _hp0,
				"hp %.0f -> %.0f" % [_hp0, float(_phantom.hp)])
		_phantom.apply_stun(0.4)
		_ok("стаун применяется", float(_phantom.stun) > 0.0, "stun=%.2f" % float(_phantom.stun))
		_next(16, 0.9)


	func _s_phantom_stun() -> void:
		if _phantom == null:
			_next(17)
			return
		_ok("стаун истекает", float(_phantom.stun) <= 0.0, "stun=%.3f" % float(_phantom.stun))
		_next(17)


	# --------------------------------------------------------------- постройки

	func _s_machines_setup() -> void:
		# Расчищаем площадку и ставим: ТЭЦ, плавильня, конвейер.
		var base: Vector2i = Vector2i(560, 70)
		for x in range(base.x - 1, base.x + 6):
			for y in range(base.y - 1, base.y + 3):
				world.set_tile(x, y, IDs.T.AIR)
		var gen_cell: Vector2i = base
		var smelt_cell: Vector2i = base + Vector2i(2, 0)
		var belt_cell: Vector2i = base + Vector2i(4, 0)
		# Статику постройки тоже берём из рантайма (см. шапку файла).
		var mb: GDScript = load("res://scripts/machines/machine_base.gd")
		mb.place_machine("CoalGen", gen_cell)
		mb.place_machine("Smelter", smelt_cell)
		mb.place_machine("Belt", belt_cell)
		_gen = world.machines.get(gen_cell)
		_smelter = world.machines.get(smelt_cell)
		_belt = world.belts.get(belt_cell)
		_placed = [{"cell": gen_cell, "node": _gen}, {"cell": smelt_cell, "node": _smelter},
				{"cell": belt_cell, "node": _belt}]
		_ok("ТЭЦ поставлена", _gen != null)
		_ok("плавильня поставлена", _smelter != null)
		_ok("конвейер поставлен", _belt != null)
		if _gen:
			_gen.add_fuel(3)
		_next(18, 1.2)


	func _s_machines_power() -> void:
		if _gen == null or _smelter == null:
			_next(19)
			return
		_ok("ТЭЦ запитана", bool(_gen.power_active), "fuel=%.1f" % float(_gen.fuel))
		_ok("постройка под питанием", bool(_gen.powered))
		_ok("станция под питанием", bool(_smelter.powered))
		if _smelter:
			_smelter.receive_item(IDs.I.COPPER_ORE, 2)
		_next(19, 0.9)


	func _s_machines_progress() -> void:
		if _smelter == null:
			_next(20)
			return
		_ok("прогресс станции растёт", float(_smelter.progress) > 0.0,
				"progress=%.3f" % float(_smelter.progress))
		if _belt:
			_belt.add_item(IDs.I.COPPER_ORE, 1)
			_belt_pos0 = 0.0
		_next(20, 0.5)


	func _s_machines_belt() -> void:
		if _belt == null:
			_next(21)
			return
		var pos: float = -1.0
		if _belt.items.size() > 0:
			pos = float(_belt.items[0]["pos"])
		_ok("предмет едет по конвейеру", pos > _belt_pos0 + 0.05,
				"pos=%.3f, предметов %d" % [pos, _belt.items.size()])
		if _gen:
			_gen.anim = 1.0
		_next(21, 0.8)


	# --------------------------------------------------------------- эффекты

	func _s_fx_spawn() -> void:
		_fx_base = world_fx.chips.size()
		_rings_base = world_fx.rings.size()
		_slashes_base = world_fx.slashes.size()
		world_fx.spawn_chip(world.world_to_cell(player.global_position), Color(0.9, 0.6, 0.2))
		_ok("частицы создаются", world_fx.chips.size() == _fx_base + CHIP_COUNT,
				"чипов %d -> %d" % [_fx_base, world_fx.chips.size()])
		world_fx.spawn_ring(player.global_position, Color(0.4, 0.9, 1.0))
		_ok("кольцо создаётся", world_fx.rings.size() == _rings_base + 1,
				"колец %d -> %d" % [_rings_base, world_fx.rings.size()])
		world_fx.spawn_slash(player.global_position)
		_ok("взмах создаётся", world_fx.slashes.size() == _slashes_base + 1,
				"взмахов %d -> %d" % [_slashes_base, world_fx.slashes.size()])
		if _gen:
			_ok("анимация постройки затухает", float(_gen.anim) <= 0.0001,
					"anim=%.4f" % float(_gen.anim))
		_next(22, 1.2)


	func _s_fx_ttl() -> void:
		_ok("частицы исчезают по TTL", world_fx.chips.size() == _fx_base,
				"чипов %d (было %d)" % [world_fx.chips.size(), _fx_base])
		_ok("кольцо исчезает за 0.7 с", world_fx.rings.size() == _rings_base,
				"колец %d (было %d)" % [world_fx.rings.size(), _rings_base])
		_ok("взмах исчезает за 0.22 с", world_fx.slashes.size() == _slashes_base,
				"взмахов %d (было %d)" % [world_fx.slashes.size(), _slashes_base])
		# Проверка лимита: 1000 частиц за один залп.
		for i in PARTICLES_LIMIT / CHIP_COUNT:
			world_fx.spawn_chip(world.world_to_cell(player.global_position), Color(0.9, 0.3, 0.2))
		_ok("лимит частиц соблюдён", world_fx.chips.size() == _fx_base + PARTICLES_LIMIT,
				"чипов %d" % world_fx.chips.size())
		_next(23, 1.2)


	func _s_fx_limit() -> void:
		_next(24, 0.1)


	func _s_fx_limit_wait() -> void:
		_ok("после TTL эффектов не остаётся", world_fx.chips.size() == _fx_base,
				"чипов %d (было %d)" % [world_fx.chips.size(), _fx_base])
		_next(25)


	# ------------------------------------------------------------------ релей

	func _s_pulse_start() -> void:
		_pulse_min = 2.0
		_pulse_max = -1.0
		var t0: int = Time.get_ticks_msec()
		_next(26, 0.6)


	func _s_pulse_check() -> void:
		# Пульс релея рисуется в world_fx как 0.5 + 0.5*sin(Time.get_ticks_msec()*0.003).
		# Проверяем, что эта величина (и сам источник времени) не «замёрзли».
		var t1: int = Time.get_ticks_msec()
		_ok("пульс релея меняется", _pulse_max - _pulse_min > 0.005,
				"min=%.3f max=%.3f" % [_pulse_min, _pulse_max])
		_ok("источник времени жив", t1 > 0, "ticks=%d" % t1)
		_next(27, 0.6)


	# ------------------------------------------------------------------ общее

	func _s_general() -> void:
		var values: Dictionary = {
			"walk_anim": float(player.walk_anim),
			"breath": float(player._breath),
			"mining_progress": float(player.mining_progress),
			"task_progress": float(player.task_progress),
			"facing": float(player.facing),
			"hp": float(player.hp),
		}
		if _phantom != null and is_instance_valid(_phantom):
			values["jitter"] = float(_phantom.jitter)
			values["phantom_hp"] = float(_phantom.hp)
			values["stun"] = float(_phantom.stun)
		if _gen != null and is_instance_valid(_gen):
			values["machine_anim"] = float(_gen.anim)
		if _smelter != null and is_instance_valid(_smelter):
			values["machine_progress"] = float(_smelter.progress)
		if _belt != null and is_instance_valid(_belt) and _belt.items.size() > 0:
			values["belt_pos"] = float(_belt.items[0]["pos"])
		var bad: Array = []
		var huge: Array = []
		for k in values.keys():
			var v: float = float(values[k])
			if is_nan(v) or not is_finite(v):
				bad.append(k)
			elif absf(v) > 1.0e6:
				huge.append(k)
		_ok("значения анимации конечны", bad.is_empty(), "проблемные: %s" % str(bad))
		_ok("значения в разумных пределах", huge.is_empty(), "запредельные: %s" % str(huge))
		_finish()


	func _finish() -> void:
		_cleanup()
		done = true


	func _cleanup() -> void:
		_release(KEY_A)
		_release(KEY_D)
		if _phantom != null and is_instance_valid(_phantom):
			_phantom.queue_free()
			_phantom = null
		for p in _placed:
			var cell: Vector2i = p["cell"]
			var node: Node = p["node"]
			if node != null and is_instance_valid(node):
				if world.belts.has(cell):
					world.belts.erase(cell)
				world.machines.erase(cell)
				node.queue_free()
		_placed.clear()
		_gen = null
		_smelter = null
		_belt = null
		if player != null and is_instance_valid(player):
			player.invuln = 0.0
			player.hp = player.MAX_HP


	# --------------------------------------------------------------- помощники

	func _press(key: int) -> void:
		var ev: InputEventKey = InputEventKey.new()
		ev.keycode = key
		ev.physical_keycode = key
		ev.pressed = true
		Input.parse_input_event(ev)


	func _release(key: int) -> void:
		var ev: InputEventKey = InputEventKey.new()
		ev.keycode = key
		ev.physical_keycode = key
		ev.pressed = false
		Input.parse_input_event(ev)


	## Карта освещённости мира (сумма мощностей источников в радиусе).
	## Считается один раз, чтобы не платить за world.light_at() в каждой клетке.
	func _build_light_grid() -> void:
		_light_grid.resize(world.W * world.H)
		_light_grid.fill(0.0)
		for l in world.lights:
			var lp: Vector2 = l["pos"]
			var rad: float = float(l["radius"])
			var pw: float = float(l["power"])
			var x0: int = maxi(0, int(floor((lp.x - rad) / world.TILE)))
			var x1: int = mini(world.W - 1, int(floor((lp.x + rad) / world.TILE)))
			var y0: int = maxi(0, int(floor((lp.y - rad) / world.TILE)))
			var y1: int = mini(world.H - 1, int(floor((lp.y + rad) / world.TILE)))
			for y in range(y0, y1 + 1):
				for x in range(x0, x1 + 1):
					var d: float = (world.cell_to_world(Vector2i(x, y)) - lp).length()
					if d < rad:
						_light_grid[y * world.W + x] += pw


	func _light_at_grid(c: Vector2i) -> float:
		if c.x < 0 or c.y < 0 or c.x >= world.W or c.y >= world.H:
			return 9.0
		return _light_grid[c.y * world.W + c.x]


	## Тёмная подземная клетка: нет света, есть пол, и по бокам тоже пол.
	func _find_dark_cell() -> void:
		for y in range(56, world.H - 6):
			for x in range(6, world.W - 6):
				var c: Vector2i = Vector2i(x, y)
				if world.get_tile_v(c) != IDs.T.AIR:
					continue
				if world.get_tile_v(c + Vector2i(0, 1)) == IDs.T.AIR:
					continue
				if _light_at_grid(c) > DARK_MAX:
					continue
				var ok: bool = true
				for dx in [-3, 3]:
					var c2: Vector2i = c + Vector2i(dx, 0)
					if world.get_tile_v(c2) != IDs.T.AIR:
						ok = false
						break
					if world.get_tile_v(c2 + Vector2i(0, 1)) == IDs.T.AIR:
						ok = false
						break
					if _light_at_grid(c2) > DARK_MAX:
						ok = false
						break
				if not ok:
					continue
				_dark_cell = c
				return


	## Минерируемый тайл рядом с игроком (как в test_runner).
	func _find_mine_cell() -> void:
		var pc: Vector2i = world.world_to_cell(player.global_position)
		for dy in range(0, 26):
			for dx in range(-14, 15):
				var c: Vector2i = pc + Vector2i(dx, dy)
				var t: int = world.get_tile_v(c)
				if t == IDs.T.AIR:
					continue
				if float(db.tile_hard(t)) > 100.0:
					continue
				if int(db.tile_drop(t)) == IDs.I.NONE:
					continue
				_mine_cell = c
				return


	## Базовый цвет фантома и цвет в состоянии CHASE — из исходника.
	func _phantom_colors() -> Array:
		var out: Array = []
		var src: String = FileAccess.get_file_as_string("res://scripts/entities/phantom.gd")
		if src.is_empty():
			return out
		var lines: PackedStringArray = src.split("\n")
		for i in lines.size():
			var t: String = lines[i].strip_edges()
			if t.begins_with("var base: Color = Color("):
				out.append(_parse_color(t))
			elif t == "if state == St.CHASE:" and i + 1 < lines.size():
				var nxt: String = lines[i + 1].strip_edges()
				if nxt.begins_with("base = Color("):
					out.append(_parse_color(nxt))
		return out


	## Разбор литерала вида Color(0.30, 0.16, 0.34) из исходника.
	func _parse_color(line: String) -> Color:
		var a: int = line.find("Color(")
		if a < 0:
			return Color(0, 0, 0, 0)
		var b: int = line.find(")", a)
		if b < 0:
			return Color(0, 0, 0, 0)
		var parts: PackedStringArray = line.substr(a + 6, b - a - 6).split(",")
		if parts.size() < 3:
			return Color(0, 0, 0, 0)
		var c: Color = Color(float(parts[0]), float(parts[1]), float(parts[2]))
		if parts.size() >= 4:
			c.a = float(parts[3])
		return c


# ------------------------------------------------------------- отдельный запуск

var _runner: Node = null
var _scene: Node = null
var _started: bool = false
var _seed_value: int = 31337


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			_seed_value = int(a.substr(7))


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_scene = load("res://scenes/main.tscn").instantiate()
		root.add_child(_scene)
		current_scene = _scene
		_runner = Runner.new(null)
		root.add_child(_runner)
		_runner.start(_scene)
		return false
	if _runner == null:
		return false
	if _runner.done:
		print("")
		print("ИТОГ: проверок %d, провалов %d" % [_runner.checks, _runner.fails])
		quit(1 if _runner.fails > 0 else 0)
		return true
	return false
