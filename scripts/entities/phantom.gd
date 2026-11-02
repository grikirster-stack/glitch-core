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
	if tree != null and not net_puppet and tree.get_nodes_in_group("phantom").size() >= MAX_PHANTOMS:
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
	if net_puppet:   # СЕТЬ (ADR-002 § 4.2.5): у клиента ИИ нет — позиция из пакета
		_net_puppet_tick(delta)
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

	if Game.players.size() > 1 or (player != null and not is_instance_valid(player)):   # СЕТЬ: цель — ближайший герой
		_net_pick_target(dt)
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
			if Game.players.size() > 1:   # СЕТЬ: шёпот — в точке двойника
				Sfx.play_at("doppel_whisper", global_position, -10.0)
			else:
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
		if Game.players.size() > 1:   # СЕТЬ: удар по товарищу слышен в его точке
			Sfx.play_at("hit", player.global_position, -4.0, 0.8)
		else:
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
	if Game.players.size() > 1:   # СЕТЬ (ADR-002 § 4.2.5): взгляд любого героя
		return _net_gazed()
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
		if Net.is_host():   # СЕТЬ: крошка и звук копки — клиентам
			_net_dig_fx(cell, t)
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
	if Game.players.size() > 1:   # СЕТЬ: у каждого героя-цели свой свет
		return _net_player_light(ppos)
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
	if net_puppet:   # СЕТЬ: оглушение считает хост
		return
	stun = maxf(stun, t)


func take_damage(amount: float, from: Vector2) -> void:
	if not alive or net_puppet:   # СЕТЬ: урон марионетке считает хост
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
		if Net.is_host():   # СЕТЬ: «рассеян» — всей команде
			_net_killed()
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


# ------------------------------------------------------------------ СЕТЬ (ADR-002, MP-F #92)
# § 4.2.5. Хост с товарищами (Game.players > 1): цель — ближайший живой, не спрятавшийся,
# на связи герой (пересчёт раз в SEEK_INTERVAL), шум, обзор и свет — по нему; двойник
# замирает под взглядом любого героя, «окно открыто» — из пакета ввода (Player._ui_blocking).
# Клиент: марионетка (net_puppet) — ИИ нет, позицию и состояние ставит NetPhantoms.
# Без товарищей (одиночная, хост один) ни одна строка ниже не работает.

## Клиент: марионетка — ИИ, путь, урон не считаются; рисунок прежний.
var net_puppet: bool = false
## Номер в сети (NetPhantoms): у хоста — с объявления, у клиента — из SPAWN; 0 — нет.
var net_id: int = 0
var _net_seek_t: float = 0.0
## Свет героя-цели в сети: instance_id героя → [свет, мс, источников] (кэш общий).
static var _net_light: Dictionary = {}


## Цель — ближайший доступный герой (Player.net_targetable); доступных нет — ближайший
## живой (как в одиночной: спрятавшегося фантом всё равно стережёт). Цель вышла из
## игры (узел освобождён) — выбор заново, и без товарищей.
func _net_pick_target(dt: float) -> void:
	if player != null and not is_instance_valid(player):
		player = null           # товарищ вышел из игры — цель заново
		_net_seek_t = 0.0
	_net_seek_t -= dt
	var cur: Player = player as Player if is_instance_valid(player) else null
	if _net_seek_t > 0.0 and cur != null and cur.net_targetable():
		return
	_net_seek_t = SEEK_INTERVAL
	var best: Player = null
	var best_d: float = INF
	var alive_best: Player = null
	var alive_d: float = INF
	for h in Game.players:
		if not is_instance_valid(h):
			continue
		var hero: Player = h as Player
		if hero == null or hero.dead:
			continue
		var d: float = global_position.distance_squared_to(hero.global_position)
		if d < alive_d:
			alive_d = d
			alive_best = hero
		if d < best_d and hero.net_targetable():
			best_d = d
			best = hero
	if best == null:
		best = alive_best
	if best != null and best != cur:
		player = best
		_los_ms = -1000000      # обзор — уже до нового героя
		repath = 0.0


## Смотрит ли на двойника хоть один герой (те же условия, что _gazed_at в одиночной).
func _net_gazed() -> bool:
	var my_cell: Vector2i = World.world_to_cell(global_position)
	for h in Game.players:
		if not is_instance_valid(h):
			continue
		var hero: Player = h as Player
		if hero == null or hero.dead:
			continue
		if global_position.distance_to(hero.global_position) >= Balance.DOPPEL_GAZE_PX:
			continue
		var dx: float = global_position.x - hero.global_position.x
		if absf(dx) > 4.0 and (1 if dx > 0.0 else -1) != hero.facing:
			continue
		if hero.mining_cell.x >= 0 or hero._ui_blocking():
			continue
		if hero == player:
			if _has_los():
				return true
		elif _compute_los(my_cell, World.world_to_cell(hero.global_position)):
			return true
	return false


func _net_player_light(ppos: Vector2) -> float:
	var key: int = player.get_instance_id() if player != null else 0
	var now: int = Time.get_ticks_msec()
	var sources: int = _light_source_count()
	var e: Array = _net_light.get(key, [])
	if e.is_empty() or int(e[2]) != sources or now - int(e[1]) >= int(PLAYER_LIGHT_INTERVAL * 1000.0):
		e = [World.light_at(World.world_to_cell(ppos)), now, sources]
		_net_light[key] = e
	return float(e[0])


## Хост: строка пакета состояния (NetCodec._put_phantom, 12 Б).
func net_row() -> Dictionary:
	var flags: int = 0
	if on_ground:
		flags |= NetCodec.PHF_ON_GROUND
	if target_machine != null:
		flags |= NetCodec.PHF_MACHINE
	return {"id": net_id, "pos": global_position, "vel": vel,
			"kind": maxi(0, NetCodec.PHANTOM_KINDS.find(kind)), "state": state,
			"facing_left": facing < 0, "frozen": frozen, "stunned": stun > 0.0,
			"hp": hp / maxf(max_hp, 0.001), "stun": stun, "flags": flags}


## Клиент: состояние из строки (NetPhantoms._interp — уже на момент рисования).
func net_apply(pos: Vector2, v: Vector2, row: Dictionary) -> void:
	global_position = pos
	vel = v
	state = int(row["state"])
	facing = -1 if bool(row["facing_left"]) else 1
	var fz: bool = bool(row["frozen"])
	if kind == "doppel" and fz and not frozen:
		Sfx.play_at("doppel_whisper", global_position, -10.0)
	frozen = fz
	stun = float(row["stun"]) if bool(row["stunned"]) else 0.0
	hp = float(row["hp"]) * max_hp
	on_ground = (int(row["flags"]) & NetCodec.PHF_ON_GROUND) != 0


## Клиент: кадр марионетки — анимация и жужжание роя своими часами.
func _net_puppet_tick(dt: float) -> void:
	jitter += dt
	stun = maxf(0.0, stun - dt)
	if not visible:
		return
	if kind == "swarm" and state == St.CHASE:
		_buzz_t -= dt
		if _buzz_t <= 0.0:
			_buzz_t = randf_range(BUZZ_MIN, BUZZ_MAX)
			Sfx.play_at("swarm", global_position, -10.0, randf_range(0.92, 1.08))
	queue_redraw()


## Хост: копатель вырыл клетку — крошка и звук клиентам.
func _net_dig_fx(cell: Vector2i, t: int) -> void:
	NetPlayers.send_fx(NetCodec.Fx.CHIP_TILE, World.cell_to_world(cell), t)
	NetPlayers.send_sound(World.cell_to_world(cell), "mine", -12.0, 0.6)


## Хост: фантом рассеян — уведомление и звук всей команде (канал 0).
func _net_killed() -> void:
	Net.send(NetCodec.Msg.EVENT, NetCodec.encode_notify(global_position, "Фантом рассеян! Хорошая работа.",
			Color(0.5, 0.9, 1.0)))
	NetPlayers.send_sound(global_position, "craft", -6.0, 0.8)


# ------------------------------------------------------------------ ОТРИСОВКА
# Облик — концепт A «Споровый луг» (ADR-003 § 4.1, § 7.3, V5). Всё из
# прямоугольников. Язык опасности общий: глаза/визор цвета DANGER светятся,
# вокруг силуэта — цветовое расслоение на 1 px (красная копия, циановая копия).
# Глитч в мире бывает только у фантомов: это и есть предупреждение.
# Части задаются «лицом вправо» и отражаются по facing одним преобразованием (_face).

const DANGER: Color = Color(0.94, 0.19, 0.42)		## #F0306A — опасность (ADR-003).
const BIO: Color = Color(0.50, 0.90, 0.82)			## #7FE6D2 — свечение спор и мицелия.
const PH_DARK: Color = Color(0.17, 0.13, 0.22)		## #2C2238 — ткань тени, ранец эха.
const MOTH_WING: Color = Color(0.86, 0.80, 0.92, 0.85)	## #DCCDEA — крылья споровых мотыльков.
const SPLIT_RED: Color = Color(1.0, 0.2, 0.35, 0.40)	## Красная копия силуэта.
const SPLIT_CYAN: Color = Color(0.2, 0.95, 1.0, 0.35)	## Циановая копия силуэта.
const STUN_TINT: Color = Color(0.6, 0.85, 1.0)		## Оглушённый фантом бледнеет.
const DANGER_HALO: Color = Color(0.94, 0.19, 0.42, 0.22)	## Ореол вокруг светящегося визора.
const DANGER_DIM: Color = Color(0.94, 0.19, 0.42, 0.6)	## Дальний глаз тени.
const BIO_TIP: Color = Color(0.50, 0.90, 0.82, 0.75)	## Светящиеся кончики гиф и бугорки спор.
const SHADE_RED: Color = Color(1.0, 0.2, 0.35, 0.22)	## Расслоение тени — слабее, чем у эха.
const SHADE_CYAN: Color = Color(0.2, 0.95, 1.0, 0.18)
const SHADE_FACE: Color = Color(0.05, 0.03, 0.07)	## Провал лица под капюшоном.
const GLINT: Color = Color(1.0, 0.85, 0.9, 0.75)		## Блик на визоре.
const GROUND_SHADOW: Color = Color(0, 0, 0, 0.3)
const DRILL: Color = Color(0.72, 0.75, 0.80)		## Сталь бура копателя и её грани.
const DRILL_DARK: Color = Color(0.50, 0.53, 0.56)
const DRILL_HI: Color = Color(0.78, 0.80, 0.84)
const ECHO_SPORE_X: Array[float] = [-4.0, -1.0, 2.0, 4.0]	## Где споры отрываются от шлема эха.
const BURROWER_SEG_H: Array[float] = [6.0, 9.0, 10.0, 8.0]	## Высоты сегментов копателя, хвост → голова.

var _name_w: float = 0.0			## Ширина имени двойника, px: меряется, когда имя сменилось.
var _name_w_of: String = ""			## Для какого имени измерена _name_w.


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


## Отражение рисунка относительно вертикальной оси фантома (flip) или сброс.
## Один вызов на кадр дешевле, чем отражать каждый прямоугольник.
func _face(flip: bool) -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1.0 if flip else 1.0, 1.0))


## Сдвиг расслоения: ±1 px, знак мигает с частотой rate.
func _split_d(t: float, rate: float) -> float:
	return 1.0 if sin(t * rate) > 0.0 else -1.0


## Эхо: тёмно-фиолетовая копия скафандра, верх распадается светящимися спорами,
## визор цвета опасности, расслоение каналов 1 px.
func _draw_echo() -> void:
	var t: float = jitter
	var base: Color = Color(0.29, 0.23, 0.36)
	if state == St.CHASE:
		base = Color(0.46, 0.20, 0.42)
	if stun > 0.0:
		base = base.lerp(STUN_TINT, 0.55)
	_face(facing < 0)
	# Тень на земле — плоская полоса.
	draw_rect(Rect2(-7.0, SIZE.y * 0.5, 14.0, 1.0), GROUND_SHADOW)
	# Расслоение: красная копия шлема и корпуса влево, циановая вправо.
	var d: float = _split_d(t, 9.0)
	draw_rect(Rect2(-5.0 - d, -9.0, 10.0, 8.0), SPLIT_RED)
	draw_rect(Rect2(-6.0 - d, -1.0, 12.0, 12.0), SPLIT_RED)
	draw_rect(Rect2(-5.0 + d, -9.0, 10.0, 8.0), SPLIT_CYAN)
	draw_rect(Rect2(-6.0 + d, -1.0, 12.0, 12.0), SPLIT_CYAN)
	# Ранец, корпус, ноги (на ходу одна нога приподнята).
	draw_rect(Rect2(-9.0, -2.0, 3.0, 8.0), PH_DARK)
	draw_rect(Rect2(-6.0, -1.0, 12.0, 8.0), base)
	var walking: bool = absf(vel.x) > 10.0
	var step: bool = sin(t * 12.0) > 0.0
	draw_rect(Rect2(-5.0, 7.0, 4.0, 3.0 if walking and step else 4.0), base.darkened(0.3))
	draw_rect(Rect2(1.0, 7.0, 4.0, 3.0 if walking and not step else 4.0), base.darkened(0.3))
	# Квадратный шлем; верхняя кромка уже распалась — от неё остались обрывки.
	var helm: Color = base.lightened(0.12)
	draw_rect(Rect2(-5.0, -8.0, 10.0, 7.0), helm)
	draw_rect(Rect2(-5.0, -9.0, 2.0, 1.0), helm)
	draw_rect(Rect2(-1.0, -9.0, 3.0, 1.0), helm)
	draw_rect(Rect2(4.0, -9.0, 1.0, 1.0), helm)
	# Визор на передней половине шлема: светится цветом опасности и мерцает.
	var lit: bool = sin(t * 17.0) > -0.2
	if lit:
		draw_rect(Rect2(-1.0, -8.0, 7.0, 6.0), DANGER_HALO)
	draw_rect(Rect2(0.0, -7.0, 5.0, 4.0), DANGER if lit else DANGER.darkened(0.55))
	draw_rect(Rect2(1.0, -6.0, 1.0, 1.0), GLINT)
	# Споры отрываются от шлема и тают, поднимаясь.
	for i in ECHO_SPORE_X.size():
		var life: float = fmod(t * 0.9 + float(i) * 0.27, 1.0)
		var sx: float = ECHO_SPORE_X[i] + (1.0 if life > 0.5 and i % 2 == 0 else 0.0)
		var sz: float = 2.0 if i == 1 and life < 0.3 else 1.0
		draw_rect(Rect2(sx, -10.0 - floorf(life * 7.0), sz, sz), Color(BIO, 0.9 * (1.0 - life)))
	_face(false)
	_draw_status(t, -19.0)


## Индикатор погони, полоса hp и искры оглушения — общие для всех типов.
func _draw_status(t: float, top: float) -> void:
	if state == St.CHASE:
		draw_rect(Rect2(-1.5, top - 1.5, 3.0, 3.0), Color(DANGER, 0.6 + 0.4 * sin(t * 12.0)))
	if hp < max_hp:
		var bw: float = 16.0
		draw_rect(Rect2(-bw * 0.5, top - 5.0, bw, 2.5), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-bw * 0.5, top - 5.0, bw * (hp / max_hp), 2.5), Color(0.85, 0.25, 0.35))
	if stun > 0.0:
		for i in 3:
			var a: float = t * 6.0 + i * TAU / 3.0
			draw_rect(Rect2(roundf(cos(a) * 11.0) - 1.0, roundf(top + 2.0 + sin(a) * 4.0) - 1.0, 2.0, 2.0),
					Color(STUN_TINT, 0.8))


## Рой: пара споровых мотыльков — тельце, крылья-пиксели, глаз цвета опасности.
func _draw_swarm() -> void:
	var t: float = jitter
	var col: Color = Color(0.62, 0.30, 0.56) if state == St.CHASE else Color(0.42, 0.32, 0.50)
	if stun > 0.0:
		col = col.lerp(STUN_TINT, 0.55)
	_face(facing < 0)
	var d: float = _split_d(t, 13.0)
	draw_rect(Rect2(-2.0 - d, -2.0, 4.0, 3.0), SPLIT_RED)
	draw_rect(Rect2(-2.0 + d, -2.0, 4.0, 3.0), SPLIT_CYAN)
	# Ведущий мотылёк: крылья взмахивают — то над тельцем, то вровень с ним.
	var up: bool = sin(t * 28.0) > 0.0
	var wy: float = -4.0 if up else -2.0
	draw_rect(Rect2(-5.0, wy, 3.0, 2.0), MOTH_WING)
	draw_rect(Rect2(2.0, wy, 3.0, 2.0), MOTH_WING)
	draw_rect(Rect2(-2.0, -2.0, 4.0, 3.0), col)
	draw_rect(Rect2(1.0, -2.0, 1.0, 1.0), DANGER)
	# Ведомый: мельче, кружит рядом, машет в противофазе.
	var ox: float = roundf(cos(t * 4.0 + 1.7) * 3.0) - 1.0
	var oy: float = roundf(sin(t * 4.0 + 1.7) * 2.0) - 6.0
	var wy2: float = oy if up else oy - 1.0
	draw_rect(Rect2(ox - 2.0, wy2, 2.0, 1.0), MOTH_WING)
	draw_rect(Rect2(ox + 2.0, wy2, 2.0, 1.0), MOTH_WING)
	draw_rect(Rect2(ox, oy, 2.0, 2.0), col)
	draw_rect(Rect2(ox + 1.0, oy, 1.0, 1.0), DANGER)
	_face(false)


## Тень: капюшон, из подола свисают гифы со светящимися кончиками, две щели глаз.
func _draw_shade() -> void:
	var t: float = jitter
	var col: Color = Color(PH_DARK, 0.94)
	if stun > 0.0:
		col = col.lerp(STUN_TINT, 0.45)
	_face(facing < 0)
	var d: float = _split_d(t, 5.0)
	draw_rect(Rect2(-6.0 - d, -4.0, 12.0, 10.0), SHADE_RED)
	draw_rect(Rect2(-4.0 - d, -10.0, 8.0, 6.0), SHADE_RED)
	draw_rect(Rect2(-6.0 + d, -4.0, 12.0, 10.0), SHADE_CYAN)
	draw_rect(Rect2(-4.0 + d, -10.0, 8.0, 6.0), SHADE_CYAN)
	# Капюшон (верхушка, голова), покатые плечи и балахон до подола.
	draw_rect(Rect2(-2.0, -11.0, 4.0, 1.0), col)
	draw_rect(Rect2(-4.0, -10.0, 8.0, 3.0), col)
	draw_rect(Rect2(-5.0, -7.0, 10.0, 3.0), col)
	draw_rect(Rect2(-6.0, -4.0, 12.0, 10.0), col)
	# Провал лица под капюшоном и две щели глаз (изредка моргают).
	draw_rect(Rect2(-2.0, -8.0, 6.0, 4.0), SHADE_FACE)
	if fmod(t, 3.1) < 2.98:
		draw_rect(Rect2(2.0, -7.0, 2.0, 1.0), DANGER)
		draw_rect(Rect2(-1.0, -7.0, 2.0, 1.0), DANGER_DIM)
	# Гифы из подола: длина 2..5 px, покачиваются, кончик светится спорой.
	for k in 6:
		var x: float = -6.0 + float(k) * 2.0
		var hl: float = 2.0 + float((k * 7 + 3) % 3) + (1.0 if sin(t * 3.0 + k * 1.3) > 0.3 else 0.0)
		draw_rect(Rect2(x, 6.0, 1.0, hl), col)
		draw_rect(Rect2(x, 6.0 + hl, 1.0, 1.0), BIO_TIP)
	_face(false)
	_draw_status(t, -16.0)


## Копатель: личинка из сегментов разной высоты со споровыми бугорками
## и ступенчатым буром спереди; бур «вращается» чередованием граней.
func _draw_burrower() -> void:
	var t: float = jitter
	var col: Color = Color(0.54, 0.50, 0.58)
	if state == St.CHASE:
		col = Color(0.66, 0.46, 0.60)
	if stun > 0.0:
		col = col.lerp(STUN_TINT, 0.55)
	var floor_y: float = SIZE.y * 0.5
	_face(facing < 0)
	var d: float = _split_d(t, 9.0)
	draw_rect(Rect2(-9.0 - d, floor_y - 6.0, 16.0, 6.0), SPLIT_RED)
	draw_rect(Rect2(-9.0 + d, floor_y - 6.0, 16.0, 6.0), SPLIT_CYAN)
	# Сегменты от хвоста к голове; в погоне по телу бежит волна.
	var wave: int = int(t * 6.0) if state == St.CHASE else 0
	var col_dark: Color = col.darkened(0.18)
	var col_hi: Color = col.lightened(0.2)
	for k in BURROWER_SEG_H.size():
		var h: float = BURROWER_SEG_H[k] + (1.0 if (k + wave) % 2 == 0 and wave != 0 else 0.0)
		var x: float = -9.0 + float(k) * 4.0
		draw_rect(Rect2(x, floor_y - h, 4.0, h), col if k % 2 == 0 else col_dark)
		draw_rect(Rect2(x, floor_y - h, 4.0, 1.0), col_hi)
		draw_rect(Rect2(x + 1.0, floor_y - h - 1.0, 2.0, 1.0), BIO_TIP)
	draw_rect(Rect2(-9.0, floor_y - 1.0, 16.0, 1.0), col.darkened(0.4))
	# Глаз на головном сегменте.
	draw_rect(Rect2(4.0, floor_y - 6.0, 2.0, 1.0), DANGER)
	# Бур: ступени сужаются к острию, грани меняют цвет — вращение.
	var spin: int = int(t * 14.0) % 2
	for k in 4:
		draw_rect(Rect2(7.0 + k, floor_y - 8.0 + k, 1.0, 8.0 - 2.0 * k), DRILL if (k + spin) % 2 == 0 else DRILL_DARK)
	draw_rect(Rect2(11.0, floor_y - 5.0, 1.0, 2.0), DRILL_HI)
	_face(false)
	_draw_status(t, floor_y - 14.0)


## Двойник: облик героя — тем же Avatar, с видом (look) и раскладкой самого героя
## (Player.body_layout, шов #58): сменит герой скафандр — двойник сменит его вместе
## с ним. Выдаёт подделку визор цвета опасности и погашенный фонарь
## (state.impostor). Под взглядом визор мерцает чаще и проступает расслоение.
func _draw_doppel() -> void:
	var t: float = jitter
	var lay: Dictionary = _hero_layout()
	var r: Rect2 = lay["body"]
	# Раскладка уже повёрнута по facing героя; смотрит двойник в другую сторону — отражаем.
	_face((int(lay["facing"]) < 0) != (facing < 0))
	var rate: float = 31.0 if frozen else 11.0
	if frozen and sin(t * 7.0) > 0.3:
		draw_rect(Rect2(r.position - Vector2(1.0, 0.0), r.size), SPLIT_RED)
		draw_rect(Rect2(r.position + Vector2(1.0, 0.0), r.size), SPLIT_CYAN)
	Avatar.draw(self, lay, int(lay["look"]), {"breath": t, "impostor": true,
			"lit": sin(t * rate) > 0.1, "tint": STUN_TINT, "tint_k": 0.55 if stun > 0.0 else 0.0})
	_face(false)
	if display_name != "":
		var font: Font = ThemeDB.fallback_font
		var fs: int = 8
		# Меряем строку только при смене имени, а не каждый кадр.
		if _name_w_of != display_name:
			_name_w_of = display_name
			_name_w = font.get_string_size(display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(-_name_w * 0.5, -SIZE.y * 0.5 - 6.0), display_name,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.85, 0.92, 1.0, 0.85))
	_draw_status(t, -SIZE.y * 0.5 - 16.0)


## Раскладка фигуры героя для двойника (Player.body_layout), ключ "facing" —
## куда смотрит герой, под которого она повёрнута, и "look" — вид героя. Героя нет
## (пустая сцена) — скафандр по умолчанию в покое «лицом вправо».
func _hero_layout() -> Dictionary:
	var hero: Node = player
	if (hero == null or not is_instance_valid(hero)) and is_inside_tree():
		hero = get_tree().get_first_node_in_group("player")
	var lay: Dictionary = {}
	var look: int = 0
	if hero != null and is_instance_valid(hero) and hero.has_method("body_layout"):
		lay = hero.body_layout().duplicate()
		var hf = hero.get("facing")
		lay["facing"] = -1 if hf is int and int(hf) < 0 else 1
		var hl = hero.get("look")
		look = int(hl) if hl is int else 0
	if not (lay.has("helmet") and lay.has("arm") and lay.has("tank")):
		lay = Avatar.layout(look, 1, 0.0, jitter, 0.0, false, false).duplicate()
	lay["look"] = look
	return lay
