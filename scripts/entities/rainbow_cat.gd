class_name RainbowCat
extends Node2D
## Радужный кот (ADR-005 § 7, #176): летающий страж на 90 с.
## Не фантом: группы «phantom» нет, турели и маяки его не бьют.
##
## Выходит из точки ядра (Game.cat_hatch_at). Летит к ближайшему фантому
## по прямой (World.move_body, flying); упёрся в стену — обход по World.astar,
## как рой. Касание < 14 px сносит фантома; рой — всех своей стаи в 24 px.
## Через 90 с или когда фантомов нет 10 с — летит в ядро и садится.
## След — точки раз в 0.05 с; свет и ломаную рисует WorldFX.

const SIZE: Vector2 = Vector2(12.0, 12.0)
const TOUCH: float = 14.0
const PACK_TOUCH: float = 24.0
const ARRIVE: float = 10.0
const PATH_MAX: int = 48
const STUCK_S: float = 0.35

enum St { OUT, HOME }

## Хост: живой кот (один на забег). Клиент смотрит марионетку.
static var live: RainbowCat = null

var state: int = St.OUT
var alive: bool = true
var home: Vector2 = Vector2.ZERO
var vel: Vector2 = Vector2.ZERO
var age: float = 0.0
## Сколько секунд подряд нет живых фантомов.
var quiet: float = 0.0
var target: Node2D = null
## Клиент: марионетка, позицию пишет сеть.
var net_puppet: bool = false
var net_id: int = 0
var facing: int = 1
## Фаза хвоста: растёт, пока кот снаружи. Анимационный тест смотрит её.
var tail_phase: float = 0.0
var kills: int = 0

var _trail_t: float = 0.0
var _path: Array[Vector2i] = []
var _path_i: int = 0
var _stuck: float = 0.0
var _blocked: bool = false
var _flank: float = 1.0
var _meow_t: float = 0.0


## Кот ещё не в дереве: позицию ставит вызывающий, до add_child.
static func create(at: Vector2) -> RainbowCat:
	var cat: RainbowCat = RainbowCat.new()
	cat.home = at
	cat.position = at
	return cat


func _enter_tree() -> void:
	# До _ready: сетевой такт в том же кадре иначе решит, что кота нет, и снимет его.
	if not net_puppet:
		live = self


func _ready() -> void:
	add_to_group("rainbow_cat")
	z_index = 6
	if not net_puppet:
		live = self
		Sfx.play_at("cat_meow", global_position, -4.0, 1.15)
	queue_redraw()


func _exit_tree() -> void:
	if live == self:
		live = null
	if not net_puppet:
		_drop_trail_lights()


func _physics_process(delta: float) -> void:
	if not alive or net_puppet:
		return
	age += delta
	tail_phase += delta
	_meow_t -= delta
	if _meow_t <= 0.0:
		_meow_t = 2.4
		Sfx.play_at("cat_meow", global_position, -10.0, 1.05)
	_drop_point(delta)
	if state == St.HOME:
		_fly_toward(home, delta)
		if global_position.distance_to(home) <= ARRIVE:
			_sit()
		return
	if age >= Balance.CAT_TIME:
		_go_home()
		return
	_pick_target()
	if target == null:
		quiet += delta
		if quiet >= Balance.CAT_QUIET:
			_go_home()
			return
		_fly_toward(home, delta)
		return
	quiet = 0.0
	_touch()
	if not alive or state == St.HOME:
		return
	if target == null or not is_instance_valid(target) or not bool(target.get("alive")):
		return
	_fly_toward(target.global_position, delta)


func _process(delta: float) -> void:
	if net_puppet:
		tail_phase += delta
		_drop_point(delta)
	queue_redraw()


func _pick_target() -> void:
	if target != null and is_instance_valid(target) and bool(target.get("alive")) \
			and target.is_inside_tree():
		return
	target = null
	var best: float = INF
	for n in get_tree().get_nodes_in_group("phantom"):
		if not is_instance_valid(n) or not bool(n.get("alive")):
			continue
		var d: float = global_position.distance_squared_to(n.global_position)
		if d < best:
			best = d
			target = n


func _touch() -> void:
	if target == null or not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) >= TOUCH:
		return
	var pack: int = int(target.get("pack_id"))
	var kind: String = String(target.get("kind"))
	_kill(target)
	if kind == "swarm" and pack != 0:
		for n in get_tree().get_nodes_in_group("phantom"):
			if not is_instance_valid(n) or n == target or not bool(n.get("alive")):
				continue
			if int(n.get("pack_id")) != pack:
				continue
			if global_position.distance_to(n.global_position) > PACK_TOUCH:
				continue
			_kill(n)
	target = null


func _kill(n: Node) -> void:
	if n.has_method("take_damage"):
		n.take_damage(9999.0, global_position)
	kills += 1


func _go_home() -> void:
	if state == St.HOME:
		return
	state = St.HOME
	target = null
	_path.clear()
	_path_i = 0


func _sit() -> void:
	alive = false
	global_position = home
	vel = Vector2.ZERO
	if Game.has_method("cat_returned"):
		Game.cat_returned()
	queue_free()


func _fly_toward(aim: Vector2, delta: float) -> void:
	# Тело уже в породе: move_body из стены не выпускает, кот крутит хвост на месте.
	# Так сценарий «радужный кот» ставит стену в клетку кота на обратном пути.
	if World.rect_solid(Rect2(global_position - SIZE * 0.5, SIZE), true):
		_unstick()
	var dir: Vector2 = _steer(aim)
	if dir.length_squared() < 0.0001:
		dir = Vector2.RIGHT
	var want: Vector2 = dir * Balance.CAT_SPEED
	want.y += sin(tail_phase * 7.0) * 12.0
	vel = vel.move_toward(want, 1400.0 * delta)
	var res: Dictionary = World.move_body(global_position, vel * delta, SIZE, true)
	global_position = res["position"]
	_blocked = bool(res["hit_x"]) or bool(res["hit_y"])
	if res["hit_x"]:
		vel.x = 0.0
	if res["hit_y"]:
		vel.y = 0.0
	if vel.x < -8.0:
		facing = -1
	elif vel.x > 8.0:
		facing = 1


## Ближайшая свободная клетка. Стена, выросшая в клетке кота, не должна его хоронить.
func _unstick() -> void:
	var free: Vector2i = _free_near(World.world_to_cell(global_position))
	if free.x < 0:
		return
	global_position = World.cell_to_world(free)
	vel = Vector2.ZERO
	_path.clear()
	_path_i = 0


## Прямая, пока клетка впереди свободна. Упор — путь A* или шаг вбок.
func _steer(aim: Vector2) -> Vector2:
	var to: Vector2 = aim - global_position
	if to.length() < ARRIVE:
		_path.clear()
		return to.normalized() if to.length() > 0.5 else Vector2.ZERO
	var ahead: Vector2i = World.world_to_cell(global_position + to.normalized() * 12.0)
	var free: bool = World.in_bounds(ahead.x, ahead.y) and not World.is_solid_cell(ahead)
	if free and not _blocked and _path.is_empty():
		_stuck = 0.0
		return to.normalized()
	_stuck += get_physics_process_delta_time()
	if _path.is_empty() or _stuck > STUCK_S or _path_i >= _path.size():
		_rebuild(aim)
		_stuck = 0.0
	if _path_i < _path.size():
		var node: Vector2 = World.cell_to_world(_path[_path_i])
		if global_position.distance_to(node) < 8.0:
			_path_i += 1
			if _path_i >= _path.size():
				return to.normalized()
			node = World.cell_to_world(_path[_path_i])
		return (node - global_position).normalized()
	var perp: Vector2 = Vector2(-to.y, to.x).normalized() * _flank
	_flank = -_flank
	return (perp + to.normalized() * 0.35).normalized()


func _rebuild(aim: Vector2) -> void:
	_path.clear()
	_path_i = 0
	if World.astar == null:
		return
	var from: Vector2i = _free_near(World.world_to_cell(global_position))
	var to: Vector2i = _free_near(World.world_to_cell(aim))
	if from.x < 0 or to.x < 0:
		return
	var p: Array[Vector2i] = World.astar.get_id_path(from, to)
	var end_i: int = mini(p.size(), PATH_MAX)
	for i in range(1, end_i):
		_path.append(p[i])


func _free_near(c: Vector2i) -> Vector2i:
	if World.astar != null and World.astar.is_in_boundsv(c) and not World.astar.is_point_solid(c):
		return c
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var t: Vector2i = c + Vector2i(dx, dy)
				if World.astar != null and World.astar.is_in_boundsv(t) and not World.astar.is_point_solid(t):
					return t
	return Vector2i(-1, -1)


func _drop_point(delta: float) -> void:
	_trail_t -= delta
	if _trail_t > 0.0:
		return
	_trail_t = Balance.CAT_TRAIL_STEP
	var fx: Node = get_tree().current_scene.get("world_fx") if get_tree().current_scene != null else null
	if fx != null and fx.has_method("cat_trail"):
		fx.cat_trail(global_position)


func _drop_trail_lights() -> void:
	var fx: Node = get_tree().current_scene.get("world_fx") if get_tree() != null and get_tree().current_scene != null else null
	if fx != null and fx.has_method("cat_trail_clear"):
		fx.cat_trail_clear()


## Строка пакета CAT (8 Б): позиция и состояние.
func net_row() -> Dictionary:
	return {"id": net_id, "pos": global_position, "state": state, "facing_left": facing < 0}


func net_apply(pos: Vector2, row: Dictionary) -> void:
	global_position = pos
	state = int(row.get("state", St.OUT))
	facing = -1 if bool(row.get("facing_left", false)) else 1
	alive = true


## Цвет квадрата хвоста. Фаза растёт — цвет по кругу семи, смена чаще раза в секунду.
func tail_color() -> Color:
	return Beams.COLOR[1 + (int(tail_phase * 14.0) % 7)]


func _draw() -> void:
	var flip: float = -1.0 if facing < 0 else 1.0
	# Локальный ноль узла. Сдвиг на global_position удваивает позицию сцены.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(flip, 1.0))
	var bob: float = roundf(sin(tail_phase * 8.0))
	# Серый кот 12×12: уши, корпус, лапы. Хвост — квадрат цвета фазы.
	var body: Color = Color(0.93, 0.94, 0.96)
	draw_rect(Rect2(-6.0, 6.0, 12.0, 2.0), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(-6.0, -4.0 + bob, 12.0, 10.0), body)
	draw_rect(Rect2(-6.0, -8.0 + bob, 4.0, 4.0), body)
	draw_rect(Rect2(2.0, -8.0 + bob, 4.0, 4.0), body)
	draw_rect(Rect2(-2.0, -1.0 + bob, 2.0, 2.0), Color(0.12, 0.13, 0.16))
	draw_rect(Rect2(3.0, -2.0 + bob, 2.0, 2.0), Color(0.95, 0.8, 0.25))
	var wag: float = 2.0 if sin(tail_phase * 14.0) > 0.0 else 0.0
	draw_rect(Rect2(-14.0, -3.0 + wag + bob, 8.0, 4.0), tail_color())
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
