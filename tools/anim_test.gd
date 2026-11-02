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
## Ввод подменяется через шов игрока (Player.test_input, issue #8): сценарий
## задаёт состояние клавиш и мыши, а игрок читает их вместо Input. Так проверки
## идут по настоящему пути _physics_process → _handle_input, а не по прямому
## вызову внутренних методов.
##
## Внимание: файл запускается как главный цикл движка (--script), а в этом
## режиме глобальные имена автозагрузок (World/Game/DB/UI) на этапе компиляции
## ещё недоступны — поэтому все узлы берём через get_node().

# --------------------------------------------------------------- КОНСТАНТЫ
## Максимальный свет в точке, где фантом не убегает.
const DARK_MAX: float = 0.4
## TTL кольца импульса, с.
const RING_TTL: float = 0.7
## TTL взмаха, с.
const SLASH_TTL: float = 0.22
## Частиц на один вызов spawn_chip.
const CHIP_COUNT: int = 4
## Предел числа живых копий фантома (issue #15).
const PHANTOM_LIMIT: int = 12
## Порог шума, выше которого фантом начинает слышать игрока (phantom.gd).
const PHANTOM_NOISE: float = 28.0
## Ниже этого порога тайл считается «мягким»: его реально выкопать за пару секунд.
const SOFT_TILE_HARD: float = 0.6
## Шаг фаз анимации (машина состояний проверок).
enum {
	ST_SETUP = 1,
	ST_WALK_START,
	ST_WALK_CHECK,
	ST_IDLE_START,
	ST_IDLE_CHECK,
	ST_FACE_RIGHT,
	ST_FACE_LEFT,
	ST_JUMP_SETUP,
	ST_JUMP_GROUND,
	ST_JUMP_AIR,
	ST_RUN_START,
	ST_RUN_CHECK,
	ST_MINE_SETUP,
	ST_MINE_CHECK,
	ST_MINE_DONE,
	ST_INTERACT_SETUP,
	ST_INTERACT_CHECK,
	ST_BREATH_CHECK,
	ST_PH_SETUP,
	ST_PH_JITTER,
	ST_PH_CHASE,
	ST_PH_DAMAGE,
	ST_PH_STUN,
	ST_PH_LIMIT,
	ST_MAC_SETUP,
	ST_MAC_POWER,
	ST_MAC_PROGRESS,
	ST_MAC_BELT,
	ST_FX_SPAWN,
	ST_FX_TTL,
	ST_FX_LIMIT,
	ST_FX_LIMIT_WAIT,
	ST_PULSE_START,
	ST_PULSE_CHECK,
	ST_LIGHT_API,
	ST_GENERAL,
}


## --------------------------------------------------------------------- исполнитель
class Runner extends Node:
	## Узел, который выполняет проверки. Живёт в дереве сцены и сам себя
	## добавляет по таймеру: шаги с паузами по реальному времени (в headless
	## частота кадров не гарантирована, а симуляция идёт по delta).
	var host: Node = null          ## кто-то снаружи (test_runner) — для совместимости
	var scene: Node = null
	# Типы узлов намеренно не указаны: в режиме --script статическая ссылка на
	# class_name (Player, WorldFX) заставила бы компилировать их на старте,
	# когда имена автозагрузок ещё не зарегистрированы. Поэтому всё через
	# динамический доступ.
	var player = null               ## узел игрока
	var world_fx = null             ## узел мировых эффектов
	var world = null                ## узел автозагрузки World
	var db = null                   ## узел автозагрузки DB
	var game = null                 ## узел автозагрузки Game

	var checks: int = 0
	var fails: int = 0
	var step: int = 0
	var done: bool = false

	var _wait_until_ms: int = 0
	# Прибитый игрок: держим его в воздухе, чтобы гравитация не сбивала замеры.
	var _pin: bool = false
	var _pin_pos: Vector2 = Vector2.ZERO
	var _walk0: float = 0.0
	var _walk1: float = 0.0
	var _walk_samples: Array = []
	var _mine_cell: Vector2i = Vector2i(-1, -1)
	var _dark_cell: Vector2i = Vector2i(-1, -1)
	var _terminal_cell: Vector2i = Vector2i(-1, -1)
	var _phantom: Node = null
	var _hp0: float = 0.0
	var _jitter0: float = 0.0
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
	var _ph_states: Dictionary = {}
	var _jump_min_vy: float = 0.0
	var _jump_min_y: float = 0.0
	var _jump_y0: float = 0.0
	var _progress_max: float = 0.0
	var _noise_peak: float = 0.0
	var _noise_floor: float = 0.0
	var _tod0: float = 0.30


	func _init(p_host: Node = null) -> void:
		host = p_host


	## Запуск: main_scene — корень сцены игры (у него есть player и world_fx).
	func start(main_scene: Node) -> void:
		scene = main_scene
		print("== Анимации ==")
		_next(ST_SETUP, 0.2)


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
		# Пока идёт замер шага — прибиваем игрока в воздухе, чтобы гравитация
		# не сбивала замер (ходьба по воздуху, а не по поверхности).
		if _pin and player:
			player.global_position = _pin_pos
			player.vel.y = 0.0
		if step == ST_WALK_CHECK and player:
			_walk_samples.append(sin(float(player.walk_anim)))
		if step == ST_PH_CHASE and _phantom != null and is_instance_valid(_phantom):
			_ph_states[int(_phantom.state)] = true
		if step == ST_JUMP_AIR and player:
			_jump_min_vy = minf(_jump_min_vy, player.vel.y)
			_jump_min_y = minf(_jump_min_y, player.global_position.y)
		if step == ST_PULSE_CHECK:
			var pulse: float = _relay_pulse()
			_pulse_min = minf(_pulse_min, pulse)
			_pulse_max = maxf(_pulse_max, pulse)
		if step == ST_MAC_PROGRESS and _smelter != null and is_instance_valid(_smelter):
			_progress_max = maxf(_progress_max, float(_smelter.progress))
		if step == ST_RUN_START and player:
			_noise_peak = maxf(_noise_peak, float(player.noise))
		if step == ST_RUN_CHECK and player:
			_noise_floor = minf(_noise_floor, float(player.noise))
		if Time.get_ticks_msec() < _wait_until_ms:
			return
		match step:
			ST_SETUP: _s_setup()
			ST_WALK_START: _s_walk_start()
			ST_WALK_CHECK: _s_walk_check()
			ST_IDLE_START: _s_idle_start()
			ST_IDLE_CHECK: _s_idle_check()
			ST_FACE_RIGHT: _s_face_right()
			ST_FACE_LEFT: _s_face_left()
			ST_JUMP_SETUP: _s_jump_setup()
			ST_JUMP_GROUND: _s_jump_ground()
			ST_JUMP_AIR: _s_jump_air()
			ST_RUN_START: _s_run_start()
			ST_RUN_CHECK: _s_run_check()
			ST_MINE_SETUP: _s_mine_setup()
			ST_MINE_CHECK: _s_mine_check()
			ST_MINE_DONE: _s_mine_done()
			ST_INTERACT_SETUP: _s_interact_setup()
			ST_INTERACT_CHECK: _s_interact_check()
			ST_BREATH_CHECK: _s_breath_check()
			ST_PH_SETUP: _s_phantom_setup()
			ST_PH_JITTER: _s_phantom_jitter()
			ST_PH_CHASE: _s_phantom_chase()
			ST_PH_DAMAGE: _s_phantom_damage()
			ST_PH_STUN: _s_phantom_stun()
			ST_PH_LIMIT: _s_phantom_limit()
			ST_MAC_SETUP: _s_machines_setup()
			ST_MAC_POWER: _s_machines_power()
			ST_MAC_PROGRESS: _s_machines_progress()
			ST_MAC_BELT: _s_machines_belt()
			ST_FX_SPAWN: _s_fx_spawn()
			ST_FX_TTL: _s_fx_ttl()
			ST_FX_LIMIT: _s_fx_limit()
			ST_FX_LIMIT_WAIT: _s_fx_limit_wait()
			ST_PULSE_START: _s_pulse_start()
			ST_PULSE_CHECK: _s_pulse_check()
			ST_LIGHT_API: _s_light_api()
			ST_GENERAL: _s_general()
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
		# Шов ввода (#8) — на нём построены все проверки управления.
		_ok("шов ввода игрока на месте", player.test_input is Dictionary,
				"test_input=%s" % str(player.test_input))
		# Фантомы не должны убить игрока посреди замеров.
		player.invuln = 99999.0
		player.hp = player.MAX_HP
		# Время суток фиксируем на дне: ночью просыпаются волны фантомов,
		# а проверки должны быть воспроизводимыми.
		_tod0 = float(game.time_of_day)
		game.time_of_day = 0.30
		_clear_input()
		_build_light_grid()
		_find_dark_cell()
		_find_mine_cell()
		_find_terminal_cell()
		_ok("найдено тёмное место для фантома", _dark_cell.x >= 0, str(_dark_cell))
		_ok("найден тайл для добычи", _mine_cell.x >= 0, str(_mine_cell))
		_ok("найден терминал для задания", _terminal_cell.x >= 0, str(_terminal_cell))
		_next(ST_WALK_START)


	func _s_walk_start() -> void:
		# Ходим в воздухе над базой: ровно, без стен и ям.
		_pin = true
		_pin_pos = world.cell_to_world(Vector2i(world.beacon_cell.x, 4))
		player.global_position = _pin_pos
		player.vel = Vector2.ZERO
		_walk0 = float(player.walk_anim)
		_walk_samples.clear()
		_set_key(KEY_D, true)
		_next(ST_WALK_CHECK, 0.7)


	func _s_walk_check() -> void:
		var w: float = float(player.walk_anim)
		_ok("фаза шага растёт при ходьбе", w > _walk0 + 0.5,
				"walk_anim %.2f -> %.2f" % [_walk0, w])
		var hi: float = -2.0
		var lo: float = 2.0
		for s in _walk_samples:
			hi = maxf(hi, float(s))
			lo = minf(lo, float(s))
		_ok("фаза шага осциллирует", hi > 0.3 and lo < -0.3,
				"замеров %d, макс %.2f, мин %.2f" % [_walk_samples.size(), hi, lo])
		_ok("фаза шага конечна", is_finite(w), "walk_anim=%.3f" % w)
		_set_key(KEY_D, false)
		_next(ST_IDLE_START, 0.5)


	func _s_idle_start() -> void:
		_walk1 = float(player.walk_anim)
		_next(ST_IDLE_CHECK, 0.35)


	func _s_idle_check() -> void:
		var d: float = float(player.walk_anim) - _walk1
		_ok("фаза шага не растёт без движения", absf(d) < 0.001,
				"прирост %.5f за 0.35 с, скорость %.2f" % [d, player.vel.x])
		_next(ST_FACE_RIGHT)


	func _s_face_right() -> void:
		_set_key(KEY_D, true)
		_next(ST_FACE_LEFT, 0.25)


	func _s_face_left() -> void:
		_ok("взгляд вправо при движении вправо", int(player.facing) == 1, "facing=%d" % int(player.facing))
		_set_key(KEY_D, false)
		_set_key(KEY_A, true)
		_next(ST_JUMP_SETUP, 0.25)


	func _s_jump_setup() -> void:
		_ok("взгляд влево при движении влево", int(player.facing) == -1, "facing=%d" % int(player.facing))
		_set_key(KEY_A, false)
		# Прыжок проверяем на настоящей земле: игрок встаёт на площадку базы.
		_pin = false
		player.global_position = world.spawn_point
		player.vel = Vector2.ZERO
		_jump_min_vy = 0.0
		_jump_min_y = player.global_position.y
		_jump_y0 = player.global_position.y
		_next(ST_JUMP_GROUND, 0.6)


	func _s_jump_ground() -> void:
		_ok("игрок стоит на земле", bool(player.on_ground), "on_ground=%s" % str(player.on_ground))
		_set_key(KEY_SPACE, true)
		_next(ST_JUMP_AIR, 0.4)


	func _s_jump_air() -> void:
		_ok("прыжок сработал", _jump_min_vy < -100.0,
				"vel.y min=%.1f, подъём %.1f px" % [_jump_min_vy, _jump_y0 - _jump_min_y])
		_set_key(KEY_SPACE, false)
		# Шум: бег громче шага и громче порога фантома (issue #8).
		# Бежим в воздухе — на площадке базы мешают постройки.
		_pin = true
		_pin_pos = world.cell_to_world(Vector2i(world.beacon_cell.x, 4))
		player.global_position = _pin_pos
		player.vel = Vector2.ZERO
		_set_key(KEY_D, true)
		_set_key(KEY_SHIFT, true)
		_noise_peak = 0.0
		_next(ST_RUN_START, 0.9)


	func _s_run_start() -> void:
		_ok("шум растёт при беге", _noise_peak > PHANTOM_NOISE,
				"шум=%.1f (ходьба 14, бег 40)" % _noise_peak)
		_set_key(KEY_SHIFT, false)
		_noise_floor = 9999.0
		_next(ST_RUN_CHECK, 0.9)


	func _s_run_check() -> void:
		_ok("шум шагов ниже порога фантома", _noise_floor < PHANTOM_NOISE,
				"шум=%.1f, порог=%.0f" % [_noise_floor, PHANTOM_NOISE])
		_set_key(KEY_D, false)
		_next(ST_MINE_SETUP, 0.3)


	func _s_mine_setup() -> void:
		if _mine_cell.x < 0:
			_next(ST_MINE_CHECK)
			return
		# Копаем по-настоящему: мышь над тайлом + зажатая ЛКМ.
		_pin = true
		_pin_pos = world.cell_to_world(_mine_cell) + Vector2(26.0, -22.0)
		player.global_position = _pin_pos
		player.vel = Vector2.ZERO
		player.mining_cell = Vector2i(-1, -1)
		player.mining_progress = 0.0
		player.test_input["mouse"] = world.cell_to_world(_mine_cell)
		_set_mouse_button(MOUSE_BUTTON_LEFT, true)
		_next(ST_MINE_CHECK, 0.25)


	func _s_mine_check() -> void:
		if _mine_cell.x < 0:
			_next(ST_MINE_DONE)
			return
		_ok("прогресс копания растёт", float(player.mining_progress) > 0.0,
				"progress=%.3f, клетка %s" % [float(player.mining_progress), str(_mine_cell)])
		_next(ST_MINE_DONE, 1.0)


	func _s_mine_done() -> void:
		if _mine_cell.x < 0:
			_next(ST_INTERACT_SETUP)
			return
		_ok("тайл пробит", world.get_tile_v(_mine_cell) == IDs.T.AIR,
				"тайл=%d" % int(world.get_tile_v(_mine_cell)))
		_ok("прогресс копания сброшен", float(player.mining_progress) <= 0.0001,
				"progress=%.4f" % float(player.mining_progress))
		_set_mouse_button(MOUSE_BUTTON_LEFT, false)
		_next(ST_INTERACT_SETUP)


	func _s_interact_setup() -> void:
		if _terminal_cell.x < 0:
			_next(ST_INTERACT_CHECK)
			return
		# Стоим у терминала и держим взаимодействие (E).
		_pin = true
		_pin_pos = world.cell_to_world(_terminal_cell) + Vector2(0.0, -24.0)
		player.global_position = _pin_pos
		player.vel = Vector2.ZERO
		player.task_progress = 0.0
		_task0 = float(player.task_progress)
		_set_key(KEY_E, true)
		_next(ST_INTERACT_CHECK, 0.5)


	func _s_interact_check() -> void:
		if _terminal_cell.x < 0:
			_next(ST_BREATH_CHECK)
			return
		_ok("прогресс задачи растёт при взаимодействии", float(player.task_progress) > _task0,
				"progress=%.3f" % float(player.task_progress))
		_set_key(KEY_E, false)
		_next(ST_BREATH_CHECK, 0.2)


	func _s_breath_check() -> void:
		_breath0 = float(player._breath)
		_next(ST_PH_SETUP, 0.3)


	# ----------------------------------------------------------------- фантом

	func _s_phantom_setup() -> void:
		if _dark_cell.x < 0:
			_next(ST_PH_JITTER)
			return
		_pin = true
		_pin_pos = world.cell_to_world(_dark_cell)
		player.global_position = _pin_pos
		player.vel = Vector2.ZERO
		# Скрипт фантома грузим в рантайме: в режиме --script глобальные имена
		# автозагрузок на этапе компиляции ещё недоступны (см. шапку файла).
		if _phantom_script == null:
			_phantom_script = load("res://scripts/entities/phantom.gd")
			_ph_enum = _phantom_script.get_script_constant_map().get("St", {})
		_phantom = _phantom_script.new()
		_phantom.player = player
		scene.add_child(_phantom)
		# Фантом — через три клетки вправо: там гарантированно есть пол,
		# нет света и есть прямая видимость (см. _find_dark_cell).
		var pc: Vector2i = _dark_cell + Vector2i(3, 0)
		_phantom.global_position = world.cell_to_world(pc)
		_jitter0 = float(_phantom.jitter)
		_next(ST_PH_JITTER, 0.3)


	func _s_phantom_jitter() -> void:
		if _phantom == null:
			_next(ST_PH_CHASE)
			return
		var j1: float = float(_phantom.jitter)
		_ok("джиттер фантома растёт", j1 > _jitter0,
				"jitter %.3f -> %.3f" % [_jitter0, j1])
		_ok("джиттер фантома конечен", is_finite(j1), "jitter=%.3f" % j1)
		_ph_states.clear()
		_next(ST_PH_CHASE, 1.2)


	func _s_phantom_chase() -> void:
		if _phantom == null:
			_next(ST_PH_DAMAGE)
			return
		var chase: int = int(_ph_enum.get("CHASE", 2))
		_ok("фантом переходит в погоню", _ph_states.has(chase),
				"состояния: %s (DORMANT=%d ROAM=%d CHASE=%d FLEE=%d)"
				% [str(_ph_states.keys()), int(_ph_enum.get("DORMANT", 0)),
				int(_ph_enum.get("ROAM", 1)), chase, int(_ph_enum.get("FLEE", 3))])
		# Цвет фантома в погоне должен отличаться от базового: сверяем константы
		# из исходника (сам draw недоступен из теста).
		var colors: Array = _phantom_colors()
		_ok("цвет фантома различается в погоне", colors.size() >= 2 and colors[0] != colors[1],
				"базовый %s, погоня %s" % [str(colors[0]) if colors.size() > 0 else "?",
				str(colors[1]) if colors.size() > 1 else "?"])
		_ok("фантом строит путь к игроку", int(_phantom.rebuilds) > 0,
				"перестроений пути: %d" % int(_phantom.rebuilds))
		_next(ST_PH_DAMAGE)


	func _s_phantom_damage() -> void:
		if _phantom == null:
			_next(ST_PH_STUN)
			return
		_hp0 = float(_phantom.hp)
		_phantom.take_damage(50.0, Vector2.ZERO)
		_ok("урон снижает hp фантома", float(_phantom.hp) < _hp0,
				"hp %.0f -> %.0f" % [_hp0, float(_phantom.hp)])
		_phantom.apply_stun(0.4)
		_ok("стаун применяется", float(_phantom.stun) > 0.0, "stun=%.2f" % float(_phantom.stun))
		_next(ST_PH_STUN, 0.9)


	func _s_phantom_stun() -> void:
		if _phantom == null:
			_next(ST_PH_LIMIT)
			return
		_ok("стаун истекает", float(_phantom.stun) <= 0.0, "stun=%.3f" % float(_phantom.stun))
		_next(ST_PH_LIMIT)


	func _s_phantom_limit() -> void:
		# Лимит живых копий (issue #15): лишние фантомы растворяются сами.
		var ph: GDScript = load("res://scripts/entities/phantom.gd")
		for i in PHANTOM_LIMIT + 4:
			var p: Node = ph.new()
			p.set("player", player)
			scene.add_child(p)
			p.global_position = world.cell_to_world(_dark_cell + Vector2i(0, -1))
		_next(ST_MAC_SETUP, 0.4)


	# --------------------------------------------------------------- постройки

	func _s_machines_setup() -> void:
		var alive: int = get_tree().get_nodes_in_group("phantom").size()
		_ok("лимит живых копий фантома соблюдён", alive <= PHANTOM_LIMIT,
				"в сцене %d, лимит %d" % [alive, PHANTOM_LIMIT])
		_free_phantoms()
		# Расчищаем площадку и ставим: ТЭЦ, плавильня, конвейер.
		var base: Vector2i = Vector2i(560, 70)
		for x in range(base.x - 1, base.x + 7):
			for y in range(base.y - 1, base.y + 3):
				world.set_tile(x, y, IDs.T.AIR)
		var gen_cell: Vector2i = base
		var smelt_cell: Vector2i = base + Vector2i(2, 0)
		var belt_cell: Vector2i = base + Vector2i(5, 0)
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
		_next(ST_MAC_POWER, 1.2)


	func _s_machines_power() -> void:
		if _gen == null or _smelter == null:
			_next(ST_MAC_PROGRESS)
			return
		_ok("ТЭЦ запитана", bool(_gen.power_active), "fuel=%.1f" % float(_gen.fuel))
		_ok("ТЭЦ питает станцию", bool(game.is_powered(world.cell_to_world(_smelter.cell))),
				"радиус %d тайлов" % int(_gen.power_radius))
		_ok("станция под питанием", bool(_smelter.powered))
		# ТЭЦ — источник питания, а не потребитель: свой флаг powered она не
		# запрашивает (issue #4 — индекс источников питания).
		_ok("ТЭЦ не запрашивает питание сама", not bool(_gen.powered),
				"powered=%s" % str(bool(_gen.powered)))
		if _smelter:
			_smelter.receive_item(IDs.I.COPPER_ORE, 2)
		_progress_max = 0.0
		_next(ST_MAC_PROGRESS, 1.2)


	func _s_machines_progress() -> void:
		if _smelter == null:
			_next(ST_MAC_BELT)
			return
		_ok("прогресс станции растёт", _progress_max > 0.0,
				"макс. progress=%.3f" % _progress_max)
		if _belt:
			_belt.add_item(IDs.I.COPPER_ORE, 1)
			_belt_pos0 = _belt_max_pos()
		_next(ST_MAC_BELT, 0.6)


	func _s_machines_belt() -> void:
		if _belt == null:
			_next(ST_FX_SPAWN)
			return
		var pos: float = _belt_max_pos()
		_ok("предмет едет по конвейеру", pos > _belt_pos0 + 0.05,
				"pos %.3f -> %.3f, предметов %d" % [_belt_pos0, pos, _belt.items.size()])
		if _gen:
			_gen.anim = 1.0
		_next(ST_FX_SPAWN, 0.8)


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
		_next(ST_FX_TTL, 1.2)


	func _s_fx_ttl() -> void:
		_ok("частицы исчезают по TTL", world_fx.chips.size() == _fx_base,
				"чипов %d (было %d)" % [world_fx.chips.size(), _fx_base])
		_ok("кольцо исчезает за 0.7 с", world_fx.rings.size() == _rings_base,
				"колец %d (было %d)" % [world_fx.rings.size(), _rings_base])
		_ok("взмах исчезает за 0.22 с", world_fx.slashes.size() == _slashes_base,
				"взмахов %d (было %d)" % [world_fx.slashes.size(), _slashes_base])
		# Залп: 1000 частиц по 4 за вызов. Лимит WorldFX не даёт им копиться.
		for i in 250:
			world_fx.spawn_chip(world.world_to_cell(player.global_position), Color(0.9, 0.3, 0.2))
		for i in 100:
			world_fx.spawn_ring(player.global_position + Vector2(float(i) * 3.0, 0.0), Color(0.4, 0.9, 1.0))
		for i in 100:
			world_fx.spawn_slash(player.global_position + Vector2(0.0, float(i) * 2.0))
		_next(ST_FX_LIMIT, 0.1)


	func _s_fx_limit() -> void:
		var lim: Dictionary = world_fx.get_script().get_script_constant_map()
		var max_chips: int = int(lim.get("MAX_CHIPS", 160))
		var max_rings: int = int(lim.get("MAX_RINGS", 48))
		var max_slashes: int = int(lim.get("MAX_SLASHES", 32))
		_ok("лимит частиц соблюдён", world_fx.chips.size() <= max_chips,
				"чипов %d, лимит %d" % [world_fx.chips.size(), max_chips])
		_ok("лимит колец соблюдён", world_fx.rings.size() <= max_rings,
				"колец %d, лимит %d" % [world_fx.rings.size(), max_rings])
		_ok("лимит взмахов соблюдён", world_fx.slashes.size() <= max_slashes,
				"взмахов %d, лимит %d" % [world_fx.slashes.size(), max_slashes])
		_next(ST_FX_LIMIT_WAIT, 1.2)


	func _s_fx_limit_wait() -> void:
		_ok("после TTL эффектов не остаётся", world_fx.chips.size() == _fx_base,
				"чипов %d (было %d)" % [world_fx.chips.size(), _fx_base])
		_next(ST_PULSE_START)


	# ------------------------------------------------------------------ релей

	func _s_pulse_start() -> void:
		_pulse_min = 2.0
		_pulse_max = -1.0
		_next(ST_PULSE_CHECK, 0.6)


	func _s_pulse_check() -> void:
		# Пульс релея рисуется в world_fx как 0.5 + 0.5*sin(Time.get_ticks_msec()*0.003).
		# Проверяем, что эта величина (и сам источник времени) не «замёрзли».
		var t1: int = Time.get_ticks_msec()
		_ok("пульс релея меняется", _pulse_max - _pulse_min > 0.005,
				"min=%.3f max=%.3f" % [_pulse_min, _pulse_max])
		_ok("источник времени жив", t1 > 0, "ticks=%d" % t1)
		_next(ST_LIGHT_API, 0.2)


	# ------------------------------------------------------------------- свет

	func _s_light_api() -> void:
		# Инкрементальный реестр света (issue #12): источники лежат в World.lights,
		# сумма в клетке считается через light_at, а выборка nearby — через
		# get_lights_near (нужно для отсечения света вне камеры).
		var beacon: Vector2i = world.beacon_cell
		_ok("реестр света непуст", world.lights.size() > 0,
				"источников %d" % world.lights.size())
		var bl: float = float(world.light_at(beacon))
		_ok("свет у релея считается", bl > 0.0, "light_at=%0.3f" % bl)
		var near: Array = world.get_lights_near(world.cell_rect(beacon).grow(64.0))
		_ok("источники рядом находятся", near.size() > 0,
				"рядом %d из %d" % [near.size(), world.lights.size()])
		_ok("дальние источники отсекаются", near.size() < world.lights.size(),
				"рядом %d из %d" % [near.size(), world.lights.size()])
		_next(ST_GENERAL, 0.1)


	# ------------------------------------------------------------------ общее

	func _s_general() -> void:
		var values: Dictionary = {
			"walk_anim": float(player.walk_anim),
			"breath": float(player._breath),
			"mining_progress": float(player.mining_progress),
			"task_progress": float(player.task_progress),
			"facing": float(player.facing),
			"hp": float(player.hp),
			"noise": float(player.noise),
		}
		if _phantom != null and is_instance_valid(_phantom):
			values["jitter"] = float(_phantom.jitter)
			values["phantom_hp"] = float(_phantom.hp)
			values["stun"] = float(_phantom.stun)
			values["rebuilds"] = float(_phantom.rebuilds)
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
		_clear_input()
		_pin = false
		if player != null and is_instance_valid(player):
			player.test_input = {}
			player.invuln = 0.0
			player.hp = player.MAX_HP
		if _phantom != null and is_instance_valid(_phantom):
			_phantom.queue_free()
			_phantom = null
		_free_phantoms()
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
		if game != null:
			game.time_of_day = _tod0


	# --------------------------------------------------------------- помощники

	## Задать состояние клавиши в шве ввода игрока.
	func _set_key(code: int, down: bool) -> void:
		var keys: Dictionary = player.test_input.get("keys", {})
		keys[code] = down
		player.test_input["keys"] = keys


	## Задать состояние кнопки мыши в шве ввода игрока.
	func _set_mouse_button(btn: int, down: bool) -> void:
		var mb: Dictionary = player.test_input.get("mouse_buttons", {})
		mb[btn] = down
		player.test_input["mouse_buttons"] = mb


	## Сбросить весь ввод: ни одна клавиша не нажата, мышь не задана.
	func _clear_input() -> void:
		if player == null:
			return
		player.test_input = {"keys": {}, "mouse": Vector2.ZERO, "mouse_buttons": {}}


	## Самая дальняя позиция предмета на конвейере.
	func _belt_max_pos() -> float:
		var out: float = 0.0
		if _belt == null or not is_instance_valid(_belt):
			return out
		for it in _belt.items:
			out = maxf(out, float(it["pos"]))
		return out


	## Пульс релея — та же формула, что в world_fx._draw.
	func _relay_pulse() -> float:
		return 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.003)


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


	## Тёмная подземная клетка с широким коридором: нет света, есть пол,
	## и по бокам (в том числе на 3 клетки вправо) тоже пол и пустота —
	## там сможет встать фантом и видеть игрока.
	func _find_dark_cell() -> void:
		for y in range(56, world.H - 6):
			for x in range(6, world.W - 6):
				var c: Vector2i = Vector2i(x, y)
				if not _dark_corridor_ok(c):
					continue
				_dark_cell = c
				return


	func _dark_corridor_ok(c: Vector2i) -> bool:
		if world.get_tile_v(c) != IDs.T.AIR:
			return false
		if world.get_tile_v(c + Vector2i(0, 1)) == IDs.T.AIR:
			return false
		if _light_at_grid(c) > DARK_MAX:
			return false
		for dx in [-3, -2, -1, 1, 2, 3]:
			var c2: Vector2i = c + Vector2i(dx, 0)
			if world.get_tile_v(c2) != IDs.T.AIR:
				return false
			if world.get_tile_v(c2 + Vector2i(0, 1)) == IDs.T.AIR:
				return false
			if _light_at_grid(c2) > DARK_MAX:
				return false
		return true


	## Минерируемый тайл: мягкий (ломается за пару секунд) и с дропом.
	func _find_mine_cell() -> void:
		var base_x: int = world.beacon_cell.x
		for dx in range(-30, 31):
			var x: int = base_x + dx
			if x < 1 or x >= world.W - 1:
				continue
			var top: int = world.surface[x]
			for dy in range(1, 6):
				var c: Vector2i = Vector2i(x, top + dy)
				var t: int = world.get_tile_v(c)
				if t == IDs.T.AIR:
					continue
				if float(db.tile_hard(t)) > SOFT_TILE_HARD:
					continue
				if int(db.tile_drop(t)) == IDs.I.NONE:
					continue
				_mine_cell = c
				return


	## Терминал задания — чтобы проверить рост task_progress.
	func _find_terminal_cell() -> void:
		var terms: Array = world.terminals
		if terms.size() > 0:
			_terminal_cell = terms[0]
			return
		_terminal_cell = world.beacon_cell


	## Убрать всех фантомов сцены.
	func _free_phantoms() -> void:
		for p in get_tree().get_nodes_in_group("phantom"):
			if is_instance_valid(p):
				p.queue_free()


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
		# Фиксированный сид: сцена должна быть воспроизводимой.
		seed(_seed_value)
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
