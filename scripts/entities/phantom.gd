class_name Phantom
extends Node2D
## Фантом — копия экипажа из глубины. Пять типов (ADR-001, § 4.5):
##   * echo     — эхо: охотится на игрока по шуму и обзору, боится света;
##   * swarm    — рой: мелкая летучая стая, идёт на работающий бур/сборщик;
##   * shade    — тень: свет ей безразличен, дренирует ТЭЦ, гасит солнце;
##   * burrower — копатель: роет природную породу к игроку;
##   * doppel   — двойник: копия игрока, замирает, пока игрок на него смотрит.
## Числа — в Balance.PHANTOMS и разделе «поведение типов» Balance.
## Тип задаётся до добавления в дерево: Phantom.create("swarm").

enum St { DORMANT, ROAM, CHASE, FLEE }

const SIZE: Vector2 = Vector2(12.0, 22.0)
const SWARM_SIZE: Vector2 = Vector2(8.0, 8.0)	## Тело роя: мелкое и летучее.
const MAX_HP: float = 100.0			## hp эха; у остальных типов — из Balance.PHANTOMS.
const KINDS: Array[String] = ["echo", "swarm", "shade", "burrower", "doppel"]

# --- Лимиты и тайминги ------------------------------------------------------
const MAX_PHANTOMS: int = Balance.MAX_PHANTOMS	## Больше стольких копий в сцене не держим.
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
## Узел пути считаем пройденным ближе этого, px. Стоящий на полу пеший фантом
## (тело 22 px) держит центр на 13 px ниже центра клетки над головой: при пороге
## 12 px узел пути, ведущего вверх по диагонали, не засчитывался, и фантом
## замирал под ним до перестроения по застреванию (STUCK_TIME) — на каждом узле.
const NODE_REACH: float = 14.0
const FLIP_T: float = 2.0				## Как часто фантом меняет сторону обхода, с.
const STUN_REDRAW: float = 0.066		## Частота перерисовки оглушённого фантома, с.
const ECHO_SPEED: float = 160.0			## Скорость эха из таблицы: от неё масштабируются остальные.
const SEEK_INTERVAL: float = 0.5		## Как часто рой и тень ищут машину-цель, с.
const MACHINE_REACH: float = 20.0		## С этой дистанции фантом бьёт машину, px.
const DOPPEL_HUNT_PX: float = 1400.0	## Двойник всегда знает, где игрок, ближе этого.
const BUZZ_MIN: float = 1.2				## Пауза между жужжанием роя, с (случайная).
const BUZZ_MAX: float = 2.4

var kind: String = "echo"
var hp: float = MAX_HP
var max_hp: float = MAX_HP
var dmg: float = 24.0				## Урон по игроку за удар.
var light_flee: float = 0.55		## Порог света, от которого фантом убегает (INF — не боится).
var speed_mul: float = 1.0			## Скорость типа относительно эха.
var body: Vector2 = SIZE			## Размер тела для столкновений.
var flying: bool = false			## Рой летает: без гравитации, путь по обеим осям.
var pack_id: int = 0				## Номер стаи (рой): для лимита директора угрозы стая — одна единица.
var vel: Vector2 = Vector2.ZERO
var state: int = St.DORMANT
var on_ground: bool = false
var facing: int = -1
var path: Array[Vector2i] = []
var path_i: int = 0
var repath: float = 0.0
var stun: float = 0.0
var target_pos: Vector2 = Vector2.ZERO
var target_machine: Node2D = null	## Машина-цель роя и тени (null — цель игрок).
var alert: float = 0.0
var wander_t: float = 0.0
var jitter: float = 0.0
var player: Node2D = null
var spawn_point: Vector2 = Vector2.ZERO
var alive: bool = true
var frozen: bool = false			## Двойник замер под взглядом игрока.
var display_name: String = ""		## Имя над головой двойника (Lore.impostor).
var rebuilds: int = 0				## Счётчик перестроений пути — для замеров и отладки.
var machine_hits: int = 0			## Ударов по машинам — для сценариев.
var coal_drained: int = 0			## Сожжено угля у ТЭЦ (тень) — для сценариев.
var tiles_dug: int = 0				## Вырыто клеток (копатель) — для сценариев.

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
var _seek_t: float = 0.0			## Таймер поиска машины-цели.
var _hit_t: float = 0.0				## Таймер удара по машине.
var _drain_t: float = Balance.SHADE_DRAIN_PERIOD	## Таймер дренажа ТЭЦ (тень).
var _dig_t: float = 0.0				## Таймер копания (копатель).
var _buzz_t: float = 0.0			## Таймер жужжания роя.
var _blocked_x: bool = false		## В прошлом кадре упёрлись в стену по горизонтали.

# Свет игрока общий для всех фантомов: пересчитывать его на каждого — расточительно.
static var _shared_player_light: float = 0.0
static var _shared_player_light_ms: int = -1000000
static var _shared_light_sources: int = -1


## Фантом нужного типа (ещё не в дереве). Неизвестный тип — эхо.
static func create(p_kind: String) -> Phantom:
	var p: Phantom = Phantom.new()
	p.kind = p_kind if Balance.PHANTOMS.has(p_kind) else "echo"
	return p


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
	_apply_kind()


## Параметры типа из Balance.PHANTOMS.
func _apply_kind() -> void:
	if not Balance.PHANTOMS.has(kind):
		kind = "echo"
	var spec: Dictionary = Balance.PHANTOMS[kind]
	max_hp = float(spec["hp"])
	hp = max_hp
	dmg = float(spec["dmg"])
	light_flee = float(spec["light_flee"])
	speed_mul = float(spec["speed"]) / ECHO_SPEED
	flying = kind == "swarm"
	body = SWARM_SIZE if flying else SIZE
	_buzz_t = randf_range(0.0, BUZZ_MAX)
	if kind == "doppel":
		display_name = String(Lore.impostor.get("full", ""))


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
	# Тем, кто света не боится (рой, тень, двойник), он не нужен вовсе.
	var fears_light: bool = light_flee < INF
	var light: float = _light_value() if fears_light else 0.0
	var player_light: float = _player_light_value(player.global_position) if fears_light else 0.0

	# --- Решения -------------------------------------------------------------
	if stun > 0.0:
		state = St.DORMANT
	else:
		_decide(dt, dist, light)

	# --- Куда идём ------------------------------------------------------------
	# Цель в погоне — позиция игрока (или машины): путь строим именно к ней,
	# и перестроение пути срабатывает по сдвигу этой цели.
	if state == St.CHASE:
		target_pos = _chase_goal()
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

	# --- Двойник под взглядом -------------------------------------------------
	if kind == "doppel":
		var was: bool = frozen
		frozen = stun <= 0.0 and _gazed_at(dist)
		if frozen and not was:
			Sfx.play("doppel_whisper", -10.0)

	# --- Движение ------------------------------------------------------------
	var speed: float = _move_speed(player_light)
	if stun > 0.0 or frozen:
		speed = 0.0

	repath -= dt
	var dir: Vector2 = Vector2.ZERO
	if state == St.CHASE and repath <= 0.0 and not frozen:
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
		if dnode < NODE_REACH:
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
			if state == St.CHASE and _path_failed and not _has_los() and kind != "burrower":
				# Пути нет — обходим препятствие вбок, а не упираемся лбом в стену.
				# Копатель не обходит: он роет напрямую (см. _burrow).
				dir = _flank_dir(to_target)
			else:
				# Цель могла оказаться в сплошной клетке: тогда идём к ближайшей
				# проходимой точке, а не в стену.
				var aim: Vector2 = _aim_pos if state == St.CHASE else target_pos
				if kind == "burrower" and state == St.CHASE:
					aim = target_pos
				var to_aim: Vector2 = aim - global_position
				if to_aim.length() > 1.0:
					dir = to_aim.normalized()

	if dir.length() > 0.01 and absf(dir.x) > 0.05:
		facing = 1 if dir.x > 0.0 else -1

	if flying:
		_move_flying(dir, speed, dt)
	else:
		_move_walking(dir, speed, dt)

	# --- Работа по типу -----------------------------------------------------
	if stun <= 0.0:
		match kind:
			"swarm":
				_swarm_tick(dt)
			"shade":
				_shade_tick(dt)
			"burrower":
				if state == St.CHASE:
					_burrow(dt)

	# --- Атака ---------------------------------------------------------------
	# Бьём игрока, только если цель — он сам (у роя и тени цель бывает машиной).
	if state == St.CHASE and target_machine == null and not frozen and dist < 22.0 \
			and stun <= 0.0 and player.has_method("damage"):
		var knock: Vector2 = (player.global_position - global_position).normalized() * 190.0
		player.damage(dmg, knock)
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


# ------------------------------------------------------------------ РЕШЕНИЯ

## Состояние на этот кадр — по типу фантома.
func _decide(dt: float, dist: float, light: float) -> void:
	if light > light_flee:
		state = St.FLEE
		target_machine = null
		return
	match kind:
		"swarm":
			_seek_machine(dt, Balance.SWARM_SEEK_PX)
			if target_machine != null:
				state = St.CHASE
			elif dist < 420.0:
				state = St.CHASE
				alert = 2.0
			else:
				state = St.ROAM
		"shade":
			_seek_machine(dt, Balance.SHADE_SEEK_PX)
			if target_machine != null:
				state = St.CHASE
			else:
				_decide_hunter(dist)
		"burrower":
			# Копатель чует игрока сквозь породу и роет к нему напрямую.
			if dist < Balance.BURROWER_HUNT_PX:
				state = St.CHASE
				alert = 2.0
			else:
				state = St.ROAM
		"doppel":
			state = St.CHASE if dist < DOPPEL_HUNT_PX else St.ROAM
		_:
			_decide_hunter(dist)


## Охота эха: обзор, шум, память о недавней погоне.
func _decide_hunter(dist: float) -> void:
	if dist < (170.0 if Game.is_night() else 120.0) and _has_los():
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


## Куда идём в погоне: к машине-цели или к игроку.
func _chase_goal() -> Vector2:
	if target_machine != null and is_instance_valid(target_machine):
		return target_machine.global_position
	target_machine = null
	return player.global_position


## Скорость по состоянию. Эхо и копатель медленнее на свету игрока
## (как было у эха), остальным свет безразличен.
func _move_speed(player_light: float) -> float:
	if light_flee < INF:
		var s: float = 150.0
		if state == St.CHASE:
			s = 172.0 if player_light < 0.3 else 138.0
		elif state == St.FLEE:
			s = 175.0
		return s * speed_mul
	var base_speed: float = ECHO_SPEED * speed_mul
	return base_speed if state == St.CHASE else base_speed * 0.6


## Смотрит ли игрок на двойника: лицом к нему, ближе DOPPEL_GAZE_PX, прямая
## видимость. Копает или крафтит — значит, не смотрит (§ 4.5).
func _gazed_at(dist: float) -> bool:
	if dist >= Balance.DOPPEL_GAZE_PX:
		return false
	var dx: float = global_position.x - player.global_position.x
	var pf = player.get("facing")
	if absf(dx) > 4.0 and pf is int and (1 if dx > 0.0 else -1) != int(pf):
		return false
	var mc = player.get("mining_cell")
	if mc is Vector2i and mc.x >= 0:
		return false
	if UI.blocking():
		return false
	return _has_los()


# ------------------------------------------------------------------ ДВИЖЕНИЕ

func _move_walking(dir: Vector2, speed: float, dt: float) -> void:
	# Прыжки через препятствия
	if on_ground and absf(dir.x) > 0.2 and _blocked_ahead():
		vel.y = -280.0
		on_ground = false

	vel.x = move_toward(vel.x, dir.x * speed, 900.0 * dt)
	if stun > 0.0 or frozen:
		vel.x = move_toward(vel.x, 0.0, 900.0 * dt)
	vel.y = minf(vel.y + 900.0 * dt, 520.0)

	# phantom = true: шлюз для фантома стена и открытым (#31).
	var res: Dictionary = World.move_body(global_position, vel * dt, body, true)
	global_position = res["position"]
	if res["hit_y"]:
		vel.y = 0.0
		if res["on_ground"]:
			on_ground = true
	_blocked_x = bool(res["hit_x"])
	if res["hit_x"]:
		vel.x = 0.0
	if not res["hit_y"]:
		on_ground = false


## Полёт роя: без гравитации, по обеим осям, лёгкое покачивание.
func _move_flying(dir: Vector2, speed: float, dt: float) -> void:
	var want: Vector2 = dir * speed
	if speed > 0.0:
		want.y += sin(jitter * 7.0) * 18.0
	vel = vel.move_toward(want, 1100.0 * dt)
	var res: Dictionary = World.move_body(global_position, vel * dt, body, true)
	global_position = res["position"]
	_blocked_x = bool(res["hit_x"])
	if res["hit_x"]:
		vel.x = 0.0
	if res["hit_y"]:
		vel.y = 0.0
	on_ground = bool(res["on_ground"])


# ------------------------------------------------------------------ ТИПЫ

## Ищем машину-цель не чаще раза в SEEK_INTERVAL: машин бывает сотни.
## Рой — работающий бур/сборщик, тень — работающий генератор или прожектор.
func _seek_machine(dt: float, radius: float) -> void:
	if target_machine != null and not is_instance_valid(target_machine):
		target_machine = null
	_seek_t -= dt
	if _seek_t > 0.0:
		return
	_seek_t = SEEK_INTERVAL
	var best: Node2D = null
	var best_d: float = radius
	for m in World.machines.values():
		if not is_instance_valid(m) or not _is_prey(m):
			continue
		var d: float = global_position.distance_to(m.global_position)
		if d < best_d:
			best_d = d
			best = m
	target_machine = best


## Подходит ли машина в цели этому типу. Рой — работающий бур/сборщик
## (есть питание), тень — работающий генератор или прожектор.
func _is_prey(m: Node) -> bool:
	if not (m is MachineBase):
		return false
	var mb: MachineBase = m
	if kind == "swarm":
		return (mb.kind == "Drill" or mb.kind == "Assembler") and mb.powered
	if kind == "shade":
		if mb is Generator:
			return mb.power_active
		return mb.kind == "Floodlight"
	return false


## Рой у машины грызёт её; жужжание стаи — позиционным звуком.
func _swarm_tick(dt: float) -> void:
	_buzz_t -= dt
	if _buzz_t <= 0.0 and state == St.CHASE:
		_buzz_t = randf_range(BUZZ_MIN, BUZZ_MAX)
		Sfx.play_at("swarm", global_position, -10.0, randf_range(0.92, 1.08))
	_machine_attack(dt)


## Тень: у ТЭЦ сжигает уголь (генератор она не ломает — она им питается),
## касание гасит солнечную панель, прожектор бьёт.
func _shade_tick(dt: float) -> void:
	var m: Node2D = target_machine
	if m == null or not is_instance_valid(m):
		return
	if global_position.distance_to(m.global_position) > MACHINE_REACH + 8.0:
		_drain_t = Balance.SHADE_DRAIN_PERIOD
		return
	if m is CoalGen:
		var gen: CoalGen = m
		_drain_t -= dt
		if _drain_t <= 0.0:
			_drain_t = Balance.SHADE_DRAIN_PERIOD
			if gen.fuel > 0.0:
				gen.fuel = maxf(0.0, gen.fuel - Balance.COAL_BURN)
				coal_drained += 1
	elif m is Solar:
		# Касание гасит панель рубильником (#25): игрок включит её обратно по E.
		var sol: Solar = m
		if sol.enabled:
			sol.set_enabled(false)
	else:
		# Прожектор (#31) не выключить и не осушить — его тень бьёт.
		_machine_attack(dt)


## Удар по машине-цели раз в MACHINE_HIT_PERIOD: MachineBase.take_damage (#25),
## при hp <= 0 машина разрушается сама.
func _machine_attack(dt: float) -> void:
	var m: Node2D = target_machine
	if m == null or not is_instance_valid(m):
		return
	if global_position.distance_to(m.global_position) > MACHINE_REACH:
		return
	_hit_t -= dt
	if _hit_t > 0.0:
		return
	_hit_t = Balance.MACHINE_HIT_PERIOD
	machine_hits += 1
	if m is MachineBase:
		(m as MachineBase).take_damage(dmg)


## Копатель: если путь упёрся в породу, роет клетку перед собой (или под/над
## собой, если цель ниже/выше). Роет только природную породу: флаг "dig"
## в DB.tile_defs и твёрдость не выше BURROWER_DIG_MAX_HARD (§ 4.4).
func _burrow(dt: float) -> void:
	_dig_t -= dt
	if _dig_t > 0.0:
		return
	var to: Vector2 = target_pos - global_position
	if to.length() < 18.0:
		return
	# Роем, только когда идти некуда: пути нет, застряли или упёрлись в стену.
	if not (_path_failed or _blocked_x or _stuck_t > STUCK_TIME * 0.5 or path_i >= path.size()):
		return
	var c: Vector2i = World.world_to_cell(global_position)
	var foot: Vector2i = World.world_to_cell(global_position + Vector2(0.0, body.y * 0.5 - 2.0))
	var head: Vector2i = World.world_to_cell(global_position - Vector2(0.0, body.y * 0.5 - 2.0))
	var cands: Array[Vector2i] = []
	if absf(to.x) >= absf(to.y) * 0.7:
		var sx: int = 1 if to.x > 0.0 else -1
		cands.append(Vector2i(c.x + sx, foot.y))
		cands.append(Vector2i(c.x + sx, head.y))
	if to.y > 8.0:
		cands.append(Vector2i(c.x, foot.y + 1))
	elif to.y < -8.0:
		cands.append(Vector2i(c.x, head.y - 1))
	for cell in cands:
		var t: int = World.get_tile_v(cell)
		if not DB.tile_solid(t):
			continue
		if not can_dig(t):
			continue
		World.set_tile(cell.x, cell.y, IDs.T.AIR)
		tiles_dug += 1
		_dig_t = Balance.BURROWER_DIG_PERIOD
		_path_failed = false
		repath = 0.0
		UI.spawn_chip(cell, DB.tile_color(t))
		Sfx.play_at("mine", World.cell_to_world(cell), -12.0, 0.6)
		return
	# Рыть нечего (или порода не по зубам) — пробуем снова чуть позже.
	_dig_t = Balance.BURROWER_DIG_PERIOD * 0.5


## Роет ли копатель этот тайл.
static func can_dig(t: int) -> bool:
	return DB.tile_diggable(t) and DB.tile_hard(t) <= Balance.BURROWER_DIG_MAX_HARD


# ------------------------------------------------------------------ СВЕТ, ОБЗОР

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


# ------------------------------------------------------------------ ПУТЬ

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


# ------------------------------------------------------------------ УРОН

func apply_stun(t: float) -> void:
	stun = maxf(stun, t)


func take_damage(amount: float, from: Vector2) -> void:
	if not alive:
		return
	hp -= amount
	# Рой рассыпается с одного удара — и от взмаха, и от импульса (§ 4.5).
	if kind == "swarm":
		hp = 0.0
	alert = 4.0
	state = St.CHASE
	target_pos = from
	vel += (global_position - from).normalized() * 90.0
	if hp <= 0.0:
		alive = false
		Game.stats_kills += 1
		Game.notify("Фантом рассеян! Хорошая работа.", Color(0.5, 0.9, 1.0))
		Sfx.play("craft", -6.0, 0.8)
		_drop_black_box()
		queue_free()


## Чёрный ящик: шанс BLACK_BOX_CHANCE, у двойника — всегда. Стая роя делит
## шанс на всех, иначе рой оказался бы самым щедрым на данные.
func _drop_black_box() -> void:
	var chance: float = Balance.BLACK_BOX_CHANCE
	if kind == "doppel":
		chance = 1.0
	elif kind == "swarm":
		chance /= float(maxi(1, int(Balance.PHANTOMS["swarm"].get("pack", 1))))
	if randf() >= chance:
		return
	var e: ItemEntity = ItemEntity.new()
	e.item_id = IDs.I.BLACK_BOX
	e.count = 1
	e.global_position = global_position
	World.add_world_node(e)


# ------------------------------------------------------------------ ОТРИСОВКА

func _draw() -> void:
	match kind:
		"swarm":
			_draw_swarm()
		"shade":
			_draw_shade()
		"burrower":
			_draw_burrower()
		"doppel":
			_draw_doppel()
		_:
			_draw_echo()


func _draw_echo() -> void:
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

	_draw_status(t, -16.0)


## Индикатор погони, полоса hp и звёздочки оглушения — общие для всех типов.
func _draw_status(t: float, top: float) -> void:
	if state == St.CHASE:
		draw_circle(Vector2(0, top), 2.2, Color(1.0, 0.25, 0.3, 0.6 + 0.4 * sin(t * 12.0)))
	if hp < max_hp:
		var bw: float = 16.0
		draw_rect(Rect2(-bw * 0.5, top - 5.0, bw, 2.5), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-bw * 0.5, top - 5.0, bw * (hp / max_hp), 2.5), Color(0.85, 0.25, 0.35))
	if stun > 0.0:
		for i in 3:
			var a: float = t * 6.0 + i * TAU / 3.0
			draw_circle(Vector2(cos(a) * 11.0, top + 2.0 + sin(a) * 4.0), 1.6, Color(0.5, 0.9, 1.0, 0.8))


## Рой: мелкий мерцающий сгусток с крылышками.
func _draw_swarm() -> void:
	var t: float = jitter
	var col: Color = Color(0.85, 0.30, 0.55) if state == St.CHASE else Color(0.55, 0.22, 0.48)
	if stun > 0.0:
		col = col.lerp(Color(0.6, 0.85, 1.0), 0.55)
	var flap: float = absf(sin(t * 28.0)) * 3.0
	draw_line(Vector2(-1.0, -1.0), Vector2(-5.0, -2.0 - flap), Color(0.9, 0.9, 1.0, 0.5), 1.0)
	draw_line(Vector2(1.0, -1.0), Vector2(5.0, -2.0 - flap), Color(0.9, 0.9, 1.0, 0.5), 1.0)
	var shift: float = sin(t * 13.0) * 1.0
	draw_circle(Vector2(shift, 0.0), 3.6, Color(0.2, 0.9, 0.9, 0.30))
	draw_circle(Vector2.ZERO, 3.0, col)
	draw_circle(Vector2(float(facing) * 1.4, -0.6), 1.0, Color(1.0, 0.9, 0.5))


## Тень: тёмный размытый силуэт без визора.
func _draw_shade() -> void:
	var t: float = jitter
	var col: Color = Color(0.06, 0.05, 0.10, 0.92)
	if stun > 0.0:
		col = col.lerp(Color(0.6, 0.85, 1.0), 0.45)
	var r: Rect2 = Rect2(-SIZE.x * 0.5, -SIZE.y * 0.5, SIZE.x, SIZE.y)
	for i in 3:
		var w: float = sin(t * 3.0 + i * 2.1) * 2.0
		draw_rect(Rect2(r.position + Vector2(w - 1.5, -1.0), r.size + Vector2(3.0, 2.0)),
				Color(0.15, 0.05, 0.25, 0.18))
	draw_rect(r, col)
	# Рваный подол
	for i in 4:
		var x: float = r.position.x + 1.5 + i * 3.0
		var h: float = 3.0 + sin(t * 6.0 + i) * 1.5
		draw_rect(Rect2(x, r.end.y, 2.0, h), Color(0.06, 0.05, 0.10, 0.7))
	_draw_status(t, -16.0)


## Копатель: приземистый, с вращающимся буром спереди.
func _draw_burrower() -> void:
	var t: float = jitter
	var col: Color = Color(0.42, 0.26, 0.16)
	if state == St.CHASE:
		col = Color(0.60, 0.30, 0.14)
	if stun > 0.0:
		col = col.lerp(Color(0.6, 0.85, 1.0), 0.55)
	var r: Rect2 = Rect2(-SIZE.x * 0.5, -SIZE.y * 0.5, SIZE.x, SIZE.y)
	var shift: float = sin(t * 9.0) * 1.2
	draw_rect(Rect2(r.position + Vector2(shift, 0), r.size), Color(0.9, 0.5, 0.2, 0.25))
	draw_rect(r, col)
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 3.0), col.lightened(0.2))
	# Бур: треугольник с вращающимися гранями.
	var fx: float = float(facing)
	var tip: Vector2 = Vector2(fx * (SIZE.x * 0.5 + 9.0), 2.0)
	var a: Vector2 = Vector2(fx * SIZE.x * 0.5, -4.0)
	var b: Vector2 = Vector2(fx * SIZE.x * 0.5, 8.0)
	draw_colored_polygon(PackedVector2Array([a, b, tip]), Color(0.70, 0.72, 0.78))
	var s: float = fmod(t * 14.0, 1.0)
	draw_line(a.lerp(tip, s), b.lerp(tip, s), Color(0.35, 0.36, 0.40), 1.0)
	# Узкая щель визора
	var visor_x: float = 0.0 if facing > 0 else -8.0
	draw_rect(Rect2(visor_x, -8.0, 8.0, 3.0), Color(1.0, 0.65, 0.25))
	_draw_status(t, -16.0)


## Двойник: копия скафандра игрока, визор мерцает, над головой — имя.
func _draw_doppel() -> void:
	var t: float = jitter
	var col: Color = Color(0.86, 0.22, 0.24)
	if stun > 0.0:
		col = col.lerp(Color(0.6, 0.85, 1.0), 0.55)
	var r: Rect2 = Rect2(-SIZE.x * 0.5, -SIZE.y * 0.5, SIZE.x, SIZE.y)
	draw_set_transform(Vector2(0, SIZE.y * 0.5), 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, SIZE.x * 0.6, Color(0, 0, 0, 0.28))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rect(Rect2(-r.size.x * 0.5 - 5.0, -r.size.y * 0.5 + 3.0, 5.0, r.size.y - 7.0), col.darkened(0.25))
	draw_rect(r, col)
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 3.0), col.lightened(0.18))
	draw_rect(Rect2(r.position.x, r.end.y - 3.0, r.size.x, 3.0), col.darkened(0.22))
	# Визор мерцает: под взглядом — чаще, и выдаёт подделку.
	var visor_x: float = -1.0 if facing > 0 else -11.0
	var rate: float = 31.0 if frozen else 11.0
	var flick: bool = sin(t * rate) > 0.1
	var vcol: Color = Color(0.72, 0.86, 0.94) if flick else Color(0.95, 0.15, 0.25)
	draw_rect(Rect2(visor_x, r.position.y + 2.0, 11.0, 7.0), vcol)
	if display_name != "":
		var font: Font = ThemeDB.fallback_font
		var fs: int = 8
		var w: float = font.get_string_size(display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(-w * 0.5, -SIZE.y * 0.5 - 6.0), display_name,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.85, 0.92, 1.0, 0.85))
	_draw_status(t, -SIZE.y * 0.5 - 16.0)
