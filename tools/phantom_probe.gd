extends SceneTree
## Замер зоны «Фантомы»: стоимость 1000 шагов _physics_process фантома в погоне
## и число перестроений пути. Плюс два кейса из issue #5: цель в сплошной
## клетке и реакция на поставленный/снятый свет.
##
## Запуск из корня проекта:
##   godot --headless --path . --script res://tools/phantom_probe.gd -- --seed=31337
##
## Сценарий: в породе выкапывается горизонтальная трасса (две клетки высотой,
## третья — пол). Игрок бежит по ней, четверо фантомов стартуют позади и
## догоняют. Трасса нужна для повторяемости: в естественных пещерах фантом
## (22 px тела против 16 px клетки) застревает в проходах высотой в клетку,
## и замер от старта до финиша теряет смысл.
##
## Шаги фантомов идут в реальном времени (60 Гц): кэши света и обзора
## считают время по стенным часам, и в плотном цикле они не истекали бы —
## замер вышел бы нечестным.
##
## Код фантома не меняется: число перестроений пути считается двумя способами —
## по счётчику `rebuilds` в самом фантоме (если версия его содержит) и по
## тикам таймера `repath`: в старой версии перестроение происходило на каждом
## тике, поэтому тики и есть число перестроений.

const SEED: int = 31337
const PHANTOMS: int = 4
const STEPS: int = 1000
const DT: float = 1.0 / 60.0
const WARMUP: int = 120
const ALERT: float = 5.0
const DARK: float = 0.15				## Свет, ниже которого место считаем тёмным.
const WALK_SPEED: float = 90.0		## Скорость игрока в замере, px/с.
const TUNNEL_X0: int = 120			## Начало трассы по клеткам.
const TUNNEL_LEN: int = 160			## Длина трассы по клеткам.
const PLAYER_OFFSET: int = 30		## Старт игрока от начала трассы.
const ST_CHASE: int = 2
const ST_FLEE: int = 3
const FLEE_STEPS: int = 120			## Сколько шагов ждём реакции на свет.

var scene: Node = null
var player: Node2D = null
var ph: Array = []
var ph_has_age: Array = []			## У фантомов есть счётчик возраста (новая версия).
var held: Node = null
var hold_pos: Vector2 = Vector2.ZERO
var stage: int = 0
var step_idx: int = 0
var next_ms: int = 0
var step_us: Array = []
var step_us2: Array = []			## Вторая фаза: цель стоит на месте.
var rep_prev: Array = []
var ticks: int = 0
var dist_sum: float = 0.0
var dist_n: int = 0
var states: Dictionary = {}
var solid_total: int = 0
var solid_built: int = 0
var light_steps: int = 0
var light_ms: float = 0.0
var unlight_steps: int = 0
var unlight_ms: float = 0.0
var crystal_cell: Vector2i = Vector2i(-1, -1)
var before_light: float = 0.0
var after_light: float = 0.0
var tunnel_row: int = -1			## Верхний ряд выкопанной трассы.
var walk_x: float = 0.0				## Текущая координата игрока по горизонтали.
var walk_dir: float = 1.0			## Направление бега игрока.
var walk_enabled: bool = true		## Бежит ли игрок (вторая фаза — стоит).
var mark_rebuilds: int = 0			## Счётчики на границе фаз.
var mark_ticks: int = 0
var marks: Array = []				## Отметки счётчиков на границах фаз.
var ph1_dist_sum: float = 0.0		## Дистанция в первой фазе (бегущая цель).
var ph1_dist_n: int = 0
var ph1_states: Dictionary = {}
var walk_y: float = 0.0				## Высота игрока (дно трассы).
## Автозагрузки: в режиме --script их нельзя звать по имени, берём из корня.
var W = null
var G = null


func _initialize() -> void:
	seed(SEED)
	W = root.get_node_or_null("World")
	G = root.get_node_or_null("Game")
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene


func _process(_delta: float) -> bool:
	match stage:
		0:
			player = get_first_node_in_group("player")
			if player == null or W == null or W.tiles.size() == 0:
				return false
			_prepare()
			stage = 1
			return false
		1:
			if not _tick(false):
				return false
			step_idx += 1
			if step_idx >= WARMUP:
				step_idx = 0
				stage = 2
				_mark()
			return false
		2:
			if not _tick(true):
				return false
			step_idx += 1
			if step_idx >= STEPS:
				step_idx = 0
				stage = 21
				walk_enabled = false
				_mark()
				ph1_dist_sum = dist_sum
				ph1_dist_n = dist_n
				ph1_states = states.duplicate()
				dist_sum = 0.0
				dist_n = 0
				states.clear()
			return false
		21:
			# Вторая фаза: цель стоит на месте — считаем перестроения пути.
			if not _tick(true):
				return false
			step_idx += 1
			if step_idx >= STEPS:
				step_idx = 0
				stage = 3
				_mark()
			return false
		3:
			_report()
			stage = 4
			return false
		4:
			_solid_test()
			_light_setup()
			stage = 5
			return false
		5:
			# Ждём, когда фантом заметит поставленный свет.
			if not _tick(false):
				return false
			light_steps += 1
			if int(held.state) == ST_FLEE or light_steps >= FLEE_STEPS:
				light_ms = float(light_steps) * DT * 1000.0
				W.set_tile(crystal_cell.x, crystal_cell.y, IDs.T.AIR)
				stage = 6
			return false
		6:
			# Ждём, когда фантом перестанет бояться снятого света.
			if not _tick(false):
				return false
			unlight_steps += 1
			if int(held.state) != ST_FLEE or unlight_steps >= FLEE_STEPS:
				unlight_ms = float(unlight_steps) * DT * 1000.0
				stage = 7
			return false
		7:
			_report2()
			stage = 8
			return false
		8:
			quit()
			return true
	return false


## Один шаг фантомов, привязанный к реальному времени (60 Гц).
func _tick(timed: bool) -> bool:
	var now: int = Time.get_ticks_msec()
	if now < next_ms:
		return false
	next_ms = now + int(DT * 1000.0)
	var t0: int = Time.get_ticks_usec()
	_walk_player()
	for i in ph.size():
		var p: Node = ph[i]
		if not is_instance_valid(p):
			continue
		# Фантом держим в погоне: иначе он растворяется и замер обрывается.
		if i < ph_has_age.size() and ph_has_age[i]:
			p.set("_age", 0.0)
		p.alert = ALERT
		p._physics_process(DT)
	if held != null and is_instance_valid(held):
		held.global_position = hold_pos
		held._physics_process(DT)
	_count_ticks()
	if timed:
		if stage == 21:
			step_us2.append(Time.get_ticks_usec() - t0)
		else:
			step_us.append(Time.get_ticks_usec() - t0)
		if ph.size() > 0 and player != null and is_instance_valid(ph[0]):
			dist_sum += float(ph[0].global_position.distance_to(player.global_position))
			dist_n += 1
			var st: int = int(ph[0].state)
			states[st] = int(states.get(st, 0)) + 1
	return true


## Отметка счётчиков на границе фаз замера.
func _mark() -> void:
	marks.append([_rebuilds_total(), ticks])


## Суммарное число перестроений пути (в старой версии счётчика нет).
func _rebuilds_total() -> int:
	var total: int = 0
	for p in ph:
		if not is_instance_valid(p) or not _has_prop(p, "rebuilds"):
			return -1
		total += int(p.get("rebuilds"))
	return total


## Тик таймера перестроения пути виден как скачок `repath` вверх.
func _count_ticks() -> void:
	var cur: Array = []
	for p in ph:
		if not is_instance_valid(p):
			cur.append(-1.0)
			continue
		cur.append(float(p.repath))
	for i in cur.size():
		if i < rep_prev.size() and cur[i] > rep_prev[i] + 0.001:
			ticks += 1
	rep_prev = cur


func _prepare() -> void:
	# День и живой игрок: состояние одинаково для всех вариантов замера.
	G.time_of_day = 0.30
	player.invuln = 1.0e9
	tunnel_row = _dig_tunnel()
	if tunnel_row < 0:
		print("диагностика: трассу выкопать не удалось")
		return
	# Игрок на полу трассы, фантомы — позади него.
	var floor_y: float = float((tunnel_row + 2) * 16) - 11.0
	walk_y = floor_y
	walk_x = float((TUNNEL_X0 + PLAYER_OFFSET) * 16) + 8.0
	walk_dir = 1.0
	player.global_position = Vector2(walk_x, walk_y)
	for i in PHANTOMS:
		var c: Vector2i = Vector2i(TUNNEL_X0 + 6 + i * 2, tunnel_row + 1)
		var p: Node = load("res://scripts/entities/phantom.gd").new()
		p.player = player
		scene.add_child(p)
		p.global_position = Vector2(float(c.x * 16) + 8.0, floor_y)
		p.set_physics_process(false)
		p.alert = ALERT
		p.state = ST_CHASE
		ph.append(p)
		ph_has_age.append(_has_prop(p, "_age"))
	print("диагностика: трасса=%d дистанция_фантома_1=%.0f свет=%.2f"
			% [tunnel_row, 24.0 * 16.0, W.light_at(Vector2i(TUNNEL_X0 + 30, tunnel_row + 1))])


## Выкапывает трассу: два ряда воздуха, третий — каменный пол. Глубину
## подбираем так, чтобы в трассе было темно (иначе фантомы убегут).
func _dig_tunnel() -> int:
	var top: int = int(W.surface[TUNNEL_X0])
	for depth in [12, 20, 28, 36, 44, 52]:
		var r: int = top + depth
		if r + 3 >= W.H:
			continue
		for x in range(TUNNEL_X0, TUNNEL_X0 + TUNNEL_LEN):
			W.set_tile(x, r, IDs.T.AIR)
			W.set_tile(x, r + 1, IDs.T.AIR)
			W.set_tile(x, r + 2, IDs.T.STONE)
		var dark: bool = true
		for x in range(TUNNEL_X0, TUNNEL_X0 + TUNNEL_LEN, 7):
			if W.light_at(Vector2i(x, r + 1)) > DARK:
				dark = false
				break
		if dark:
			return r
	return -1


## Игрок бежит по трассе: цель движется, фантомы её догоняют.
func _walk_player() -> void:
	if not walk_enabled:
		return
	walk_x += walk_dir * WALK_SPEED * DT
	var x0: float = float(TUNNEL_X0 * 16) + 8.0
	var x1: float = float((TUNNEL_X0 + TUNNEL_LEN - 2) * 16) + 8.0
	if walk_x < x0 or walk_x > x1:
		walk_dir = -walk_dir
		walk_x = clampf(walk_x, x0, x1)
	player.global_position = Vector2(walk_x, walk_y)


## Есть ли у объекта такое свойство (у старой версии фантома счётчика нет).
func _has_prop(o: Object, pname: String) -> bool:
	for pd in o.get_property_list():
		if String(pd["name"]) == pname:
			return true
	return false


func _median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s: Array = a.duplicate()
	s.sort()
	return float(s[s.size() / 2])


func _report() -> void:
	var total_ms: float = 0.0
	for v in step_us:
		total_ms += float(v) / 1000.0
	var rebuilds: int = 0
	var counted: bool = false
	for p in ph:
		if not is_instance_valid(p) or not _has_prop(p, "rebuilds"):
			continue
		rebuilds += int(p.get("rebuilds"))
		counted = true
	var chase_pct: float = 0.0
	if dist_n > 0:
		chase_pct = 100.0 * float(states.get(ST_CHASE, 0)) / float(dist_n)
	print("=== ЗАМЕР: 1000 шагов _physics_process, фантомов в погоне ===")
	print("фантомов=%d" % ph.size())
	print("всего=%.1f мс" % total_ms)
	print("на_шаг=%.4f мс" % (total_ms / float(maxi(1, step_us.size()))))
	print("медиана_шага=%.1f мкс" % _median(step_us))
	print("на_фантома_шаг=%.4f мс" % (total_ms / float(maxi(1, step_us.size() * ph.size()))))
	print("тиков_таймера_пути=%d" % ticks)
	if counted:
		print("перестроений_пути=%d" % rebuilds)
		print("перестроений_на_фантома=%.2f" % (float(rebuilds) / float(maxi(1, ph.size()))))
	else:
		## В старой версии перестроение шло на каждом тике таймера.
		print("перестроений_пути=%d (по тикам таймера)" % ticks)
		print("перестроений_на_фантома=%.2f" % (float(ticks) / float(maxi(1, ph.size()))))
	print("шагов_в_погоне=%.0f%%" % chase_pct)
	print("средняя_дистанция_до_игрока=%.0f px" % (dist_sum / float(maxi(1, dist_n))))
	if ph1_dist_n > 0:
		print("фаза1_дистанция=%.0f px" % (ph1_dist_sum / float(ph1_dist_n)))
		print("фаза1_шагов_в_погоне=%.0f%%"
				% (100.0 * float(ph1_states.get(ST_CHASE, 0)) / float(ph1_dist_n)))
	if marks.size() >= 3:
		var rb1: int = int(marks[1][0])
		var rb2: int = int(marks[2][0])
		if rb1 >= 0 and rb2 >= 0:
			print("перестроений_пути_бегущая_цель=%d" % (rb1 - int(marks[0][0])))
			print("перестроений_пути_стоящая_цель=%d" % (rb2 - rb1))
		print("тиков_таймера_пути_бегущая_цель=%d" % (int(marks[1][1]) - int(marks[0][1])))
		print("тиков_таймера_пути_стоящая_цель=%d" % (int(marks[2][1]) - int(marks[1][1])))
	if step_us2.size() > 0:
		var total2: float = 0.0
		for v in step_us2:
			total2 += float(v) / 1000.0
		print("=== ФАЗА 2: цель стоит на месте, ещё 1000 шагов ===")
		print("всего=%.1f мс" % total2)
		print("медиана_шага=%.1f мкс" % _median(step_us2))
		print("на_фантома_шаг=%.4f мс" % (total2 / float(maxi(1, step_us2.size() * ph.size()))))
		print("фаза2_дистанция=%.0f px" % (dist_sum / float(maxi(1, dist_n))))
	if ph.size() > 0 and is_instance_valid(ph[0]):
		var p0: Node = ph[0]
		print("диагностика: дистанция=%.0f путь=%d узел=%d цель=(%.0f,%.0f) фантом=(%.0f,%.0f) repath=%.2f"
				% [p0.global_position.distance_to(player.global_position),
				p0.path.size(), p0.path_i,
				p0.target_pos.x, p0.target_pos.y,
				p0.global_position.x, p0.global_position.y,
				float(p0.repath)])
		if _has_prop(p0, "_path_failed"):
			print("диагностика: путь_не_найден=%s" % str(p0.get("_path_failed")))
		if _has_prop(p0, "dbg_rebuild_us"):
			print("диагностика: A*_всего=%.1f мс путь_длина=%d" % [float(p0.get("dbg_rebuild_us")) / 1000.0, int(p0.get("dbg_path_len"))])
		if _has_prop(p0, "dbg_light_calls"):
			print("диагностика: light_calls=%d los_calls=%d move=%.1f мс"
					% [int(p0.get("dbg_light_calls")), int(p0.get("dbg_los_calls")), float(p0.get("dbg_move_us")) / 1000.0])
			if _has_prop(p0, "dbg_los_cells"):
				print("диагностика: los_клеток=%d" % int(p0.get("dbg_los_cells")))
			if _has_prop(p0, "dbg_t_total"):
				print("диагностика: всего_шаг=%.1f мс свет=%.1f мс"
						% [float(p0.get("dbg_t_total")) / 1000.0, float(p0.get("dbg_t_light")) / 1000.0])
			var tt: float = 0.0
			var tl: float = 0.0
			var tm: float = 0.0
			var lc: int = 0
			var ll: int = 0
			var la: int = 0
			for p in ph:
				if not is_instance_valid(p) or not _has_prop(p, "dbg_t_total"):
					continue
				tt += float(p.get("dbg_t_total")) / 1000.0
				tl += float(p.get("dbg_t_light")) / 1000.0
				tm += float(p.get("dbg_move_us")) / 1000.0
				lc += int(p.get("dbg_light_calls"))
				ll += int(p.get("dbg_los_calls"))
				la += int(p.get("dbg_light_at_calls"))
			print("диагностика: все_фантомы: шаг=%.1f мс свет=%.1f мс move=%.1f мс light_calls=%d los_calls=%d light_at=%d"
					% [tt, tl, tm, lc, ll, la])
		if _has_prop(p0, "dbg_stuck"):
			var st: Array = p0.get("dbg_stuck")
			print("диагностика: застреваний=%d" % st.size())


## Кейс из issue #5: цель в сплошной клетке — строится ли путь.
func _solid_test() -> void:
	var probe: Node = load("res://scripts/entities/phantom.gd").new()
	probe.player = player
	scene.add_child(probe)
	probe.global_position = player.global_position
	probe.set_physics_process(false)
	var pcell: Vector2i = W.world_to_cell(player.global_position)
	var walls: Array = []
	for r in range(1, 26):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c: Vector2i = pcell + Vector2i(dx, dy)
				if W.astar.is_in_boundsv(c) and W.astar.is_point_solid(c):
					walls.append(c)
		if walls.size() >= 300:
			break
	var built: int = 0
	for c in walls:
		probe.target_pos = W.cell_to_world(c)
		probe._rebuild_path()
		if probe.path.size() > 0:
			built += 1
	solid_total = walls.size()
	solid_built = built


## Подготовка светового кейса: тёмный фантом и светокристалл рядом.
func _light_setup() -> void:
	var spot: Vector2i = Vector2i(TUNNEL_X0 + 6, tunnel_row + 1)
	var p: Node = load("res://scripts/entities/phantom.gd").new()
	p.player = player
	scene.add_child(p)
	p.global_position = Vector2(float(spot.x * 16) + 8.0, walk_y)
	p.set_physics_process(false)
	held = p
	hold_pos = p.global_position
	before_light = W.light_at(spot)
	# Ставим светокристалл в паре клеток от фантома.
	var target: Vector2i = spot + Vector2i(3, 0)
	crystal_cell = target
	W.set_tile(target.x, target.y, IDs.T.LIGHT_CRYSTAL)
	after_light = W.light_at(spot)


func _report2() -> void:
	print("=== ЦЕЛЬ В СПЛОШНОЙ КЛЕТКЕ ===")
	print("целей_в_стенах=%d" % solid_total)
	print("путь_построен=%d" % solid_built)
	print("=== РЕАКЦИЯ НА СВЕТ ===")
	print("свет_до_кристалла=%.2f" % before_light)
	print("свет_после_кристалла=%.2f" % after_light)
	print("реакция_на_свет=%d шагов (%.0f мс)" % [light_steps, light_ms])
	print("реакция_на_снятие_света=%d шагов (%.0f мс)" % [unlight_steps, unlight_ms])
