class_name Phantom
extends Node2D
## Фантом — копия экипажа из глубины. Охотится на игрока, боится света.

enum St { DORMANT, ROAM, CHASE, FLEE }

const SIZE: Vector2 = Vector2(12.0, 22.0)
const MAX_HP: float = 100.0

# --- Лимиты и тайминги ------------------------------------------------------
const MAX_PHANTOMS: int = 12			## Больше стольких копий в сцене не держим.
const DESPAWN_DIST: float = 900.0		## Дальше этой дистанции фантом растворяется.
const DESPAWN_DIST_NIGHT: float = 2000.0	## Ночью порог выше — ночь должна пугать.
const SPAWN_GRACE: float = 5.0			## Свежий фантом первые секунды не растворяется.
const LIGHT_INTERVAL: float = 0.25		## Как часто пересчитываем свет фантома, с.
const PLAYER_LIGHT_INTERVAL: float = 0.2	## Как часто пересчитываем свет игрока, с.
const LOS_INTERVAL: float = 0.2			## Кэш линии видимости, с.
const LOS_PLAYER_SHIFT: float = 24.0	## Сдвиг игрока, при котором обзор пересчитывается.
const REPATH_NEAR: float = 0.45			## Интервал перестроения пути вблизи цели, с.
const REPATH_FAR: float = 0.9			## Интервал перестроения пути вдали от цели, с.
const REPATH_FAR_DIST: float = 300.0	## Дистанция, с которой путь строится реже.
const PATH_TARGET_MOVE: float = 32.0	## Минимальный сдвиг цели для перестроения пути, px.
const PATH_GOAL_EPS: float = 16.0	## На этом расстоянии до цели путь считаем доведённым.
const PATH_MAX_NODES: int = 70			## Максимум узлов в одном куске пути.
const STUCK_TIME: float = 0.8			## Сколько секунд без прогресса считать застреванием.
const STUCK_PROGRESS: float = 6.0		## Минимальный прогресс к узлу пути за это время, px.
const FLIP_T: float = 2.0				## Как часто фантом меняет сторону обхода, с.
const STUN_REDRAW: float = 0.066		## Частота перерисовки оглушённого фантома, с.

var hp: float = MAX_HP
var vel: Vector2 = Vector2.ZERO
var state: int = St.DORMANT
var on_ground: bool = false
var facing: int = -1
var path: Array[Vector2i] = []
var path_i: int = 0
var repath: float = 0.0
var stun: float = 0.0
var target_pos: Vector2 = Vector2.ZERO
var alert: float = 0.0
var wander_t: float = 0.0
var jitter: float = 0.0
var player: Node2D = null
var spawn_point: Vector2 = Vector2.ZERO
var alive: bool = true
var rebuilds: int = 0				## Счётчик перестроений пути — для замеров и отладки.

# --- Кэши и служебное состояние ----------------------------------------------
var _light: float = 0.0				## Кэш света в точке фантома.
var _light_ms: int = -1000000		## Метка времени последнего пересчёта света фантома.
var _light_sources: int = -1		## Число источников света на момент последнего пересчёта.
var _los: bool = false				## Кэш линии видимости до игрока.
var _los_ms: int = -1000000			## Метка времени последнего пересчёта обзора.
var _los_player_pos: Vector2 = Vector2.ZERO
var _los_cell: Vector2i = Vector2i(-9999, -9999)
var _path_target: Vector2 = Vector2.ZERO	## Цель на момент последнего расчёта пути.
var _aim_pos: Vector2 = Vector2.ZERO		## Куда идти, если путь кончился (цель могла быть в стене).
var _path_failed: bool = false		## Путь не найден — идём вбок, а не в стену.
var _stuck_t: float = 0.0			## Время без прогресса по пути.
var _stuck_best: float = INF		## Лучшая дистанция до узла пути с последнего прогресса.
var _flank_side: float = 1.0		## Сторона обхода препятствия.
var _flank_t: float = 0.0
var _age: float = 0.0				## Возраст фантома, с.
var _prev_state: int = St.DORMANT	## Состояние в прошлом кадре — для смены режима.
var _redraw_t: float = 0.0			## Таймер редкой перерисовки оглушённого фантома.

# Свет игрока общий для всех фантомов: пересчитывать его на каждого — расточительно.
static var _shared_player_light: float = 0.0
static var _shared_player_light_ms: int = -1000000
static var _shared_light_sources: int = -1


func _ready() -> void:
	# Лимит живых копий: лишний фантом растворяется, не успев толпиться в мире.
	var tree: SceneTree = get_tree()
	if tree != null and tree.get_nodes_in_group("phantom").size() >= MAX_PHANTOMS:
		alive = false
		queue_free()
		return
	add_to_group("phantom")
	z_index = 5
	jitter = randf() * 10.0
	_flank_side = 1.0 if randf() < 0.5 else -1.0


func _physics_process(delta: float) -> void:
	if not alive:
		return
	jitter += delta
	var dt: float = delta
	_age += dt
	stun = maxf(0.0, stun - dt)
	alert = maxf(0.0, alert - dt * 0.5)
	_flank_t -= dt
	if _flank_t <= 0.0:
		_flank_t = FLIP_T
		_flank_side = -_flank_side

	if player == null:
		player = get_tree().get_first_node_in_group("player")
	if player == null:
		return

	var dist: float = global_position.distance_to(player.global_position)

	# --- Растворение в глубине ------------------------------------------------
	# Забывший про игрока фантом (не в погоне) уходит за пределы досягаемости.
	if state != St.CHASE and _age > SPAWN_GRACE and dist > _despawn_limit():
		alive = false
		queue_free()
		return

	# --- Свет (кэш) ----------------------------------------------------------
	# Источники света статичны, суммировать их каждый кадр слишком дорого.
	var light: float = _light_value()
	var player_light: float = _player_light_value(player.global_position)

	# --- Решения -------------------------------------------------------------
	if stun > 0.0:
		state = St.DORMANT
	else:
		if light > 0.55:
			state = St.FLEE
		elif dist < (170.0 if Game.is_night() else 120.0) and _has_los():
			state = St.CHASE
			alert = 3.0
		elif player.noise > 28.0 and dist < 260.0:
			state = St.CHASE
			alert = 2.0
			target_pos = player.global_position
		elif alert > 0.0 and dist < 420.0:
			state = St.CHASE
		else:
			state = St.ROAM if dist > 260.0 else St.DORMANT

	# --- Куда идём ------------------------------------------------------------
	# Цель в погоне — позиция игрока: путь строим именно к ней, и перестроение
	# пути срабатывает по сдвигу этой цели.
	if state == St.CHASE:
		target_pos = player.global_position
	elif state == St.FLEE:
		target_pos = global_position + (global_position - World.cell_to_world(World.world_to_cell(global_position))).normalized() * 90.0
	elif state == St.ROAM:
		wander_t -= dt
		if wander_t <= 0.0:
			wander_t = randf_range(1.5, 3.5)
			target_pos = _wander_target()

	# Путь ведёт только в погоне: в других состояниях фантом идёт по своей воле.
	if state != St.CHASE and path.size() > 0:
		path.clear()
		path_i = 0
		_stuck_t = 0.0
		_stuck_best = INF
	# Смена режима на погоню — перестраиваем путь сразу, а не через остаток таймера.
	if state == St.CHASE and _prev_state != St.CHASE:
		repath = 0.0
	_prev_state = state

	# --- Движение ------------------------------------------------------------
	var speed: float = 150.0
	if state == St.CHASE:
		speed = 172.0 if player_light < 0.3 else 138.0
	elif state == St.FLEE:
		speed = 175.0

	if stun > 0.0:
		speed = 0.0

	repath -= dt
	var dir: Vector2 = Vector2.ZERO
	if state == St.CHASE and repath <= 0.0:
		# Вдали от цели путь перестраиваем реже — цели похуже, а поиск дорог.
		repath = REPATH_FAR if dist > REPATH_FAR_DIST else REPATH_NEAR
		# Пересчитываем путь, только если цель заметно сдвинулась
		# либо прежний путь кончился/не найден/завёл в тупик.
		# Пустой путь при уже достигнутой цели — не повод для перестроения.
		var need_path: bool = path_i >= path.size() \
				and global_position.distance_to(target_pos) > PATH_GOAL_EPS
		if _path_target.distance_to(target_pos) > PATH_TARGET_MOVE \
				or need_path or _path_failed or _stuck_t > STUCK_TIME:
			_rebuild_path()
	if path_i < path.size():
		var node: Vector2i = path[path_i]
		var np: Vector2 = World.cell_to_world(node)
		var dnode: float = global_position.distance_to(np)
		if dnode < 12.0:
			path_i += 1
			_stuck_t = 0.0
			_stuck_best = INF
		else:
			dir = (np - global_position).normalized()
			_track_progress(dnode, dt)
	elif state != St.DORMANT:
		_stuck_t = 0.0
		_stuck_best = INF
		var to_target: Vector2 = target_pos - global_position
		if to_target.length() > 1.0:
			if state == St.CHASE and _path_failed and not _has_los():
				# Пути нет — обходим препятствие вбок, а не упираемся лбом в стену.
				dir = _flank_dir(to_target)
			else:
				# Цель могла оказаться в сплошной клетке: тогда идём к ближайшей
				# проходимой точке, а не в стену.
				var aim: Vector2 = _aim_pos if state == St.CHASE else target_pos
				var to_aim: Vector2 = aim - global_position
				if to_aim.length() > 1.0:
					dir = to_aim.normalized()

	if dir.length() > 0.01:
		facing = 1 if dir.x > 0.0 else -1

	# Прыжки через препятствия
	if on_ground and absf(dir.x) > 0.2 and _blocked_ahead():
		vel.y = -280.0
		on_ground = false

	vel.x = move_toward(vel.x, dir.x * speed, 900.0 * dt)
	if stun > 0.0:
		vel.x = move_toward(vel.x, 0.0, 900.0 * dt)
	vel.y = minf(vel.y + 900.0 * dt, 520.0)

	var res: Dictionary = World.move_body(global_position, vel * dt, SIZE)
	global_position = res["position"]
	if res["hit_y"]:
		vel.y = 0.0
		if res["on_ground"]:
			on_ground = true
	if res["hit_x"]:
		vel.x = 0.0
	if not res["hit_y"]:
		on_ground = false

	# --- Атака ---------------------------------------------------------------
	if state == St.CHASE and dist < 22.0 and stun <= 0.0 and player.has_method("damage"):
		var knock: Vector2 = (player.global_position - global_position).normalized() * 190.0
		player.damage(24.0, knock)
		Sfx.play("hit", -4.0, 0.8)
		alert = 3.0

	# Перерисовка: канальный сдвиг, мерцание визора и индикатор состояния
	# анимируются каждый кадр. Оглушённый фантом неподвижен и рисуется реже,
	# мёртвый не перерисовывается вовсе (выход по alive выше).
	_redraw_t -= dt
	if stun > 0.0:
		if _redraw_t <= 0.0:
			_redraw_t = STUN_REDRAW
			queue_redraw()
	else:
		_redraw_t = STUN_REDRAW
		queue_redraw()


func _despawn_limit() -> float:
	## Днём фантомы уходят глубже, ночью запас больше — ночь должна пугать.
	return DESPAWN_DIST_NIGHT if Game.is_night() else DESPAWN_DIST


func _light_value() -> float:
	## Свет в точке фантома. Источники света статичны, суммировать их каждый
	## кадр — дорого: пересчитываем не чаще раза в LIGHT_INTERVAL.
	## Но если набор источников изменился (поставили или сняли светящийся
	## кристалл, пересобрался мир) — пересчитываем сразу: иначе фантом до
	## LIGHT_INTERVAL секунд не увидит, что стало светлее или темнее.
	var now: int = Time.get_ticks_msec()
	var sources: int = _light_source_count()
	if sources != _light_sources or now - _light_ms >= int(LIGHT_INTERVAL * 1000.0):
		_light_ms = now
		_light_sources = sources
		_light = World.light_at(World.world_to_cell(global_position))
	return _light


func _player_light_value(ppos: Vector2) -> float:
	## Свет в точке игрока. Кэш общий для всех фантомов сцены: считать его
	## отдельно на каждого фантома — та же самая дорогая сумма по всем
	## источникам света, только раз за другим.
	var now: int = Time.get_ticks_msec()
	var sources: int = _light_source_count()
	if sources != _shared_light_sources or now - _shared_player_light_ms >= int(PLAYER_LIGHT_INTERVAL * 1000.0):
		_shared_player_light_ms = now
		_shared_light_sources = sources
		_shared_player_light = World.light_at(World.world_to_cell(ppos))
	return _shared_player_light


func _light_source_count() -> int:
	## Число источников света в мире. Меняется, когда игрок ставит или снимает
	## светящийся кристалл, а также когда мир перегенерируется. Реестр света
	## публичный — сверяемся с ним, чтобы вовремя сбросить кэш света.
	if World.lights == null:
		return -1
	return World.lights.size()


func _wander_target() -> Vector2:
	## Точка блуждания. Днём фантомы уходят в глубину прочь от игрока,
	## ночью просто кружат рядом.
	if player == null:
		return global_position + Vector2(randf_range(-110.0, 110.0), randf_range(-40.0, 40.0))
	var away: Vector2 = global_position - player.global_position
	if not Game.is_night() and away.length() > 1.0:
		var deep: Vector2 = global_position + away.normalized() * randf_range(120.0, 200.0)
		return deep + Vector2(randf_range(-30.0, 30.0), randf_range(-20.0, 20.0))
	return global_position + Vector2(randf_range(-110.0, 110.0), randf_range(-40.0, 40.0))


func _blocked_ahead() -> bool:
	var ahead: Vector2 = global_position + Vector2(facing * 14.0, 0.0)
	return World.is_solid_at(ahead)


func _has_los() -> bool:
	## Кэшированная линия видимости: луч по клеткам стоит слишком дорого,
	## чтобы считать его каждый кадр. Пересчитываем по таймеру,
	## при заметном сдвиге игрока или при смене клетки фантома.
	if player == null:
		return false
	var ppos: Vector2 = player.global_position
	var my_cell: Vector2i = World.world_to_cell(global_position)
	var now: int = Time.get_ticks_msec()
	if now - _los_ms >= int(LOS_INTERVAL * 1000.0) \
			or ppos.distance_to(_los_player_pos) > LOS_PLAYER_SHIFT \
			or my_cell != _los_cell:
		_los_ms = now
		_los_player_pos = ppos
		_los_cell = my_cell
		_los = _compute_los(my_cell, World.world_to_cell(ppos))
	return _los


func _compute_los(from: Vector2i, to: Vector2i) -> bool:
	var steps: int = maxi(absi(to.x - from.x), absi(to.y - from.y))
	if steps <= 0:
		return true
	for i in range(1, steps):
		var t: float = float(i) / float(steps)
		var cx: int = int(round(lerpf(from.x, to.x, t)))
		var cy: int = int(round(lerpf(from.y, to.y, t)))
		if World.is_solid_cell(Vector2i(cx, cy)):
			return false
	return true


func _track_progress(dnode: float, dt: float) -> void:
	## Следим, продвигается ли фантом по пути: если к очередному узлу
	## подобраться не удаётся, фантом застрял — прежний путь больше не годится
	## и его надо перестроить.
	_stuck_t += dt
	if dnode < _stuck_best - STUCK_PROGRESS:
		_stuck_best = dnode
		_stuck_t = 0.0


func _flank_dir(to_target: Vector2) -> Vector2:
	## Обход препятствия: шаг вбок от цели, направление обхода меняем со временем.
	var perp: Vector2 = Vector2(-to_target.y, to_target.x)
	if perp.length() < 0.001:
		return Vector2.ZERO
	perp = perp.normalized() * _flank_side
	# Немного вперёд по направлению цели, чтобы не уползать назад.
	return (perp + to_target.normalized() * 0.35).normalized()


func _nearest_free_cell(c: Vector2i) -> Vector2i:
	## Ближайшая свободная клетка вокруг c (спираль по радиусу).
	for r in range(1, 7):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var t: Vector2i = c + Vector2i(dx, dy)
				if World.astar.is_in_boundsv(t) and not World.astar.is_point_solid(t):
					return t
	return Vector2i(-1, -1)


func _rebuild_path() -> void:
	rebuilds += 1
	path.clear()
	path_i = 0
	_path_failed = false
	_aim_pos = target_pos
	_stuck_t = 0.0
	_stuck_best = INF
	if World.astar == null:
		_path_failed = true
		return
	var from: Vector2i = World.world_to_cell(global_position)
	var to: Vector2i = World.world_to_cell(target_pos)
	if not World.astar.is_in_boundsv(from) or not World.astar.is_in_boundsv(to):
		_path_failed = true
		return
	# Стартовая клетка может оказаться в стене — ищем свободную рядом.
	if World.astar.is_point_solid(from):
		var alt_from: Vector2i = _nearest_free_cell(from)
		if alt_from.x < 0:
			_path_failed = true
			return
		from = alt_from
	if World.astar.is_point_solid(to):
		# Цель в сплошной клетке: ищем ближайшую проходимую клетку рядом с ней.
		# Раньше здесь стоял `return` внутри цикла по смещениям — из-за этого
		# ни один вариант не проверялся и путь не строился вовсе.
		var alt: Vector2i = _nearest_free_cell(to)
		if alt.x < 0:
			# Проходимых клеток рядом нет — путь не строим вовсе.
			_path_failed = true
			return
		to = alt
		# И идём к этой клетке, а не в стену.
		_aim_pos = World.cell_to_world(alt)
	var p: Array[Vector2i] = World.astar.get_id_path(from, to)
	if p.size() > 1:
		var sliced: Array[Vector2i] = []
		var end_i: int = mini(p.size(), PATH_MAX_NODES)
		for i in range(1, end_i):
			sliced.append(p[i])
		path = sliced
		path_i = 0
		_path_target = target_pos
	elif p.size() == 1:
		# Мы уже в целевой клетке — путь пуст, но это не провал.
		_path_target = target_pos
	else:
		# Пути нет вовсе — фантом не должен тут застрять.
		_path_failed = true


func apply_stun(t: float) -> void:
	stun = maxf(stun, t)


func take_damage(amount: float, from: Vector2) -> void:
	if not alive:
		return
	hp -= amount
	alert = 4.0
	state = St.CHASE
	target_pos = from
	vel += (global_position - from).normalized() * 90.0
	if hp <= 0.0:
		alive = false
		Game.stats_kills += 1
		Game.notify("Фантом рассеян! Хорошая работа.", Color(0.5, 0.9, 1.0))
		Sfx.play("craft", -6.0, 0.8)
		queue_free()


func _draw() -> void:
	var t: float = jitter
	var base: Color = Color(0.30, 0.16, 0.34)
	if state == St.CHASE:
		base = Color(0.62, 0.12, 0.42)
	if stun > 0.0:
		base = base.lerp(Color(0.6, 0.85, 1.0), 0.55)
	var r: Rect2 = Rect2(-SIZE.x * 0.5, -SIZE.y * 0.5, SIZE.x, SIZE.y)

	# Фантомные «призрачные» копии со смещением каналов.
	var shift: float = sin(t * 9.0) * 1.6
	draw_rect(Rect2(r.position + Vector2(shift, 0), r.size), Color(0.9, 0.2, 0.4, 0.35))
	draw_rect(Rect2(r.position - Vector2(shift, 0), r.size), Color(0.2, 0.9, 0.9, 0.30))

	draw_set_transform(Vector2(0, SIZE.y * 0.5), 0.0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, SIZE.x * 0.55, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	draw_rect(Rect2(-r.size.x * 0.5 - 4.0, -r.size.y * 0.5 + 3.0, 4.0, r.size.y - 6.0), base.darkened(0.3))
	draw_rect(r, base)
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 3.0), base.lightened(0.2))

	var visor_x: float = -1.0 if facing > 0 else -11.0
	var flick: bool = sin(t * 17.0) > -0.2
	var vcol: Color = Color(0.75, 0.95, 1.0) if flick else Color(0.2, 0.1, 0.15)
	draw_rect(Rect2(visor_x, -9.0, 11.0, 7.0), vcol)
	draw_rect(Rect2(visor_x + 1.0, -8.0, 3.0, 2.0), Color(1, 1, 1, 0.7))

	# Индикатор состояния
	if state == St.CHASE:
		draw_circle(Vector2(0, -16.0), 2.2, Color(1.0, 0.25, 0.3, 0.6 + 0.4 * sin(t * 12.0)))
	if hp < MAX_HP:
		var bw: float = 16.0
		draw_rect(Rect2(-bw * 0.5, -21.0, bw, 2.5), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-bw * 0.5, -21.0, bw * (hp / MAX_HP), 2.5), Color(0.85, 0.25, 0.35))
	if stun > 0.0:
		for i in 3:
			var a: float = t * 6.0 + i * TAU / 3.0
			draw_circle(Vector2(cos(a) * 11.0, -14.0 + sin(a) * 4.0), 1.6, Color(0.5, 0.9, 1.0, 0.8))
