class_name Phantom
extends Node2D
## Фантом — копия экипажа из глубины. Охотится на игрока, боится света.

enum St { DORMANT, ROAM, CHASE, FLEE }

const SIZE: Vector2 = Vector2(12.0, 22.0)
const MAX_HP: float = 100.0

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


func _ready() -> void:
	add_to_group("phantom")
	z_index = 5
	jitter = randf() * 10.0


func _physics_process(delta: float) -> void:
	if not alive:
		return
	jitter += delta
	var dt: float = delta
	stun = maxf(0.0, stun - dt)
	alert = maxf(0.0, alert - dt * 0.5)

	if player == null:
		player = get_tree().get_first_node_in_group("player")
	if player == null:
		return

	var dist: float = global_position.distance_to(player.global_position)
	var light: float = World.light_at(World.world_to_cell(global_position))
	var player_light: float = World.light_at(World.world_to_cell(player.global_position))

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

	if state == St.CHASE:
		target_pos = player.global_position
	elif state == St.FLEE:
		target_pos = global_position + (global_position - World.cell_to_world(World.world_to_cell(global_position))).normalized() * 90.0
	elif state == St.ROAM:
		wander_t -= dt
		if wander_t <= 0.0:
			wander_t = randf_range(1.5, 3.5)
			target_pos = global_position + Vector2(randf_range(-110.0, 110.0), randf_range(-40.0, 40.0))

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
		repath = 0.45
		_rebuild_path()
	if path_i < path.size():
		var node: Vector2i = path[path_i]
		var np: Vector2 = World.cell_to_world(node)
		if global_position.distance_to(np) < 12.0:
			path_i += 1
		else:
			dir = (np - global_position).normalized()
	elif state != St.DORMANT:
		dir = (target_pos - global_position).normalized()

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

	queue_redraw()


func _blocked_ahead() -> bool:
	var ahead: Vector2 = global_position + Vector2(facing * 14.0, 0.0)
	return World.is_solid_at(ahead)


func _has_los() -> bool:
	if player == null:
		return false
	var from: Vector2i = World.world_to_cell(global_position)
	var to: Vector2i = World.world_to_cell(player.global_position)
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


func _rebuild_path() -> void:
	path.clear()
	path_i = 0
	if World.astar == null:
		return
	var from: Vector2i = World.world_to_cell(global_position)
	var to: Vector2i = World.world_to_cell(target_pos)
	if not World.astar.is_in_boundsv(from) or not World.astar.is_in_boundsv(to):
		return
	if World.astar.is_point_solid(to):
		# Ищем ближайшую проходимую клетку рядом с целью.
		for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1)]:
			var alt: Vector2i = to + off
			if World.astar.is_in_boundsv(alt) and not World.astar.is_point_solid(alt):
				to = alt
				break
			return
	var p: Array[Vector2i] = World.astar.get_id_path(from, to)
	if p.size() > 1:
		path = p.slice(1, min(p.size(), 70))
		path_i = 0


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
