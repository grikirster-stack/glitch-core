class_name ItemEntity
extends Node2D
## Лежащий на земле предмет: притягивается к игроку, может попасть на конвейер.
##
## Уборка и стоимость (issue #7):
##  * ссылка на игрока одна на все предметы (static) и ищется по группе, только
##    когда протухла, — а не 200 поисков по группе в каждом физическом кадре;
##  * слияние: упавший предмет вливается в такой же предмет, уже лежащий в
##    соседних клетках (MERGE_CELLS), — кучка из 50 камней = один узел со
##    счётчиком. Добыча не теряется: счётчик складывается, «возраст» берётся
##    у младшего — подбрасывая в кучку, игрок продлевает ей жизнь;
##  * срок жизни: несобранный предмет живёт LIFETIME (5 минут). За WARN_TIME
##    до конца он мигает, затем рассыпается облачком частиц. Предмет с
##    despawn = false (например, мешок с хотбаром после смерти) живёт вечно.
##  * перерисовка — только при смене счётчика (раньше — каждый кадр полёта).

## Срок жизни несобранного предмета, с.
const LIFETIME: float = 300.0
## За сколько секунд до исчезновения предмет начинает мигать.
const WARN_TIME: float = 30.0
## Радиус слияния в клетках (квадрат (2r+1)x(2r+1) вокруг клетки падения).
const MERGE_CELLS: int = 2
const MAGNET_DIST: float = 70.0
const PICKUP_DIST: float = 14.0
## Пауза перед повторным притягиванием, если инвентарь полон, с.
const FULL_RETRY: float = 1.0

## Общая ссылка на игрока (см. _get_player).
static var _player: Node2D = null
## Лежащие предметы: Vector3i(клетка.x, клетка.y, item_id) -> ItemEntity.
static var _ground: Dictionary = {}

var item_id: int = IDs.I.NONE
var count: int = 1
var vel: Vector2 = Vector2.ZERO
var grounded: bool = false
var age: float = 0.0
var magnet: bool = false
var pickup_delay: float = 0.45
## false — предмет не исчезает по сроку жизни.
var despawn: bool = true

var _ground_key: Vector3i = Vector3i(0, 0, -1)
var _registered: bool = false


func _ready() -> void:
	z_index = 4
	vel = Vector2(randf_range(-40.0, 40.0), randf_range(-130.0, -70.0))


func _exit_tree() -> void:
	_unregister()


## Игрок — один на сцену; ищем его по группе, только если ссылки ещё нет
## или узел уже удалён (перезапуск сцены).
func _get_player() -> Node2D:
	if not is_instance_valid(_player) or not _player.is_inside_tree():
		_player = get_tree().get_first_node_in_group("player") as Node2D
	return _player


## Сколько секунд осталось до исчезновения (INF — не исчезает).
func time_left() -> float:
	return LIFETIME - age if despawn else INF


## Предмет мигает: скоро исчезнет.
func is_warning() -> bool:
	return despawn and time_left() <= WARN_TIME


## Сколько предметов лежит на земле (зарегистрированных для слияния).
static func ground_count() -> int:
	return _ground.size()


func _physics_process(delta: float) -> void:
	age += delta
	pickup_delay = maxf(0.0, pickup_delay - delta)
	if despawn:
		if age >= LIFETIME:
			_expire()
			return
		if age >= LIFETIME - WARN_TIME:
			# Мигание ускоряется к концу: от 2 до 6 Гц.
			var f: float = lerpf(2.0, 6.0, (age - (LIFETIME - WARN_TIME)) / WARN_TIME)
			modulate.a = 0.35 + 0.65 * absf(cos(age * PI * f))
		elif modulate.a != 1.0:
			modulate.a = 1.0
	var player: Node2D = _get_player()
	if player == null:
		return
	var d: float = global_position.distance_to(player.global_position)
	if d < MAGNET_DIST and pickup_delay <= 0.0 and not magnet:
		magnet = true
		_unregister()
	if magnet:
		var dir: Vector2 = (player.global_position - global_position).normalized()
		global_position += dir * 340.0 * delta
		if d < PICKUP_DIST:
			var left: int = player.collect(item_id, count)
			if left <= 0:
				queue_free()
			else:
				# Инвентарь полон: падаем обратно и ждём, а не дёргаем collect каждый кадр.
				_set_count(left)
				magnet = false
				grounded = false
				vel = Vector2.ZERO
				pickup_delay = FULL_RETRY
		return
	if grounded:
		return
	vel.y += 900.0 * delta
	var res: Dictionary = World.move_body(global_position, vel * delta, Vector2(10.0, 10.0))
	global_position = res["position"]
	if res["hit_y"]:
		vel.y = 0.0
		vel.x *= 0.7
		grounded = true
		_land()
	if res["hit_x"]:
		vel.x = 0.0


## Приземлились: влиться в такой же предмет рядом или занять свою клетку.
func _land() -> void:
	var c: Vector2i = World.world_to_cell(global_position)
	for dy in range(-MERGE_CELLS, MERGE_CELLS + 1):
		for dx in range(-MERGE_CELLS, MERGE_CELLS + 1):
			var k: Vector3i = Vector3i(c.x + dx, c.y + dy, item_id)
			var other = _ground.get(k)
			if other == null or other == self:
				continue
			if not is_instance_valid(other) or other.is_queued_for_deletion():
				_ground.erase(k)
				continue
			other.absorb(self)
			return
	_ground_key = Vector3i(c.x, c.y, item_id)
	_ground[_ground_key] = self
	_registered = true


## Забрать предмет other в свою кучку (other удаляется).
func absorb(other: ItemEntity) -> void:
	_set_count(count + other.count)
	age = minf(age, other.age)
	despawn = despawn and other.despawn
	other.count = 0
	other._unregister()
	other.queue_free()


func _unregister() -> void:
	if _registered and _ground.get(_ground_key) == self:
		_ground.erase(_ground_key)
	_registered = false


func _set_count(n: int) -> void:
	if n != count:
		count = n
		queue_redraw()


## Срок вышел: рассыпаемся облачком частиц.
func _expire() -> void:
	UI.spawn_chip(World.world_to_cell(global_position), Color(0.8, 0.8, 0.85))
	_unregister()
	queue_free()


func _draw() -> void:
	var tex: ImageTexture = DB.item_texture(item_id)
	if tex == null:
		return
	draw_texture_rect(tex, Rect2(-7.0, -7.0, 14.0, 14.0), false, Color(1, 1, 1, 0.95))
	if count > 1:
		draw_rect(Rect2(-7.0, -9.0, 14.0, 8.0), Color(0, 0, 0, 0.45))
		draw_string(ThemeDB.fallback_font, Vector2(-7.0, -2.5), str(count),
				HORIZONTAL_ALIGNMENT_CENTER, 14.0, 7, Color(1, 1, 1, 0.95))
