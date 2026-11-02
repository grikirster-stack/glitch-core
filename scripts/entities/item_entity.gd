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
## Мешок с хотбаром после смерти (ADR-001 § 4.8, #29): [[item_id, count], ...].
## Пустой — обычный предмет. Мешок ни с чем не сливается и подбирается целиком
## (что не влезло в инвентарь — остаётся в мешке).
var bag: Array = []

var _ground_key: Vector3i = Vector3i(0, 0, -1)
var _registered: bool = false


func _ready() -> void:
	z_index = 4
	vel = Vector2(randf_range(-40.0, 40.0), randf_range(-130.0, -70.0))
	if Net.is_online():   # СЕТЬ (ADR-002): хост рассылает предмет, у клиента — марионетка
		add_to_group(NET_GROUP)


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
	if not Net.is_authority():   # СЕТЬ (ADR-002): подбор и слияние — на хосте
		_net_puppet(delta)
		return
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
	# Погибший герой ничего не подбирает: мешок ждёт его на месте смерти.
	var alive: bool = not bool(player.get("dead"))
	if magnet and not alive:
		magnet = false
		grounded = false
	var d: float = global_position.distance_to(player.global_position)
	if d < MAGNET_DIST and pickup_delay <= 0.0 and not magnet and alive:
		magnet = true
		_unregister()
	if magnet:
		var dir: Vector2 = (player.global_position - global_position).normalized()
		global_position += dir * 340.0 * delta
		if d < PICKUP_DIST and not bag.is_empty():
			_collect_bag(player)
		elif d < PICKUP_DIST:
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


## Мешок: переложить в инвентарь всё, что влезет; остаток ждёт в мешке.
func _collect_bag(player: Node2D) -> void:
	var rest: Array = []
	for e in bag:
		var left: int = player.collect(int(e[0]), int(e[1]))
		if left > 0:
			rest.append([int(e[0]), left])
	bag = rest
	if bag.is_empty():
		queue_free()
		return
	item_id = int(bag[0][0])
	queue_redraw()
	magnet = false
	grounded = false
	vel = Vector2.ZERO
	pickup_delay = FULL_RETRY


## Приземлились: влиться в такой же предмет рядом или занять свою клетку.
func _land() -> void:
	if not bag.is_empty():
		return
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
	if not bag.is_empty():
		_draw_bag()
		return
	var tex: ImageTexture = DB.item_texture(item_id)
	if tex == null:
		return
	draw_texture_rect(tex, Rect2(-7.0, -7.0, 14.0, 14.0), false, Color(1, 1, 1, 0.95))
	if count > 1:
		draw_rect(Rect2(-7.0, -9.0, 14.0, 8.0), Color(0, 0, 0, 0.45))
		draw_string(ThemeDB.fallback_font, Vector2(-7.0, -2.5), str(count),
				HORIZONTAL_ALIGNMENT_CENTER, 14.0, 7, Color(1, 1, 1, 0.95))


## Мешок: тёмный куль с завязкой и иконкой первого предмета.
func _draw_bag() -> void:
	draw_circle(Vector2(0.0, 1.0), 7.0, Color(0.30, 0.24, 0.18))
	draw_rect(Rect2(-3.0, -8.0, 6.0, 4.0), Color(0.30, 0.24, 0.18))
	draw_rect(Rect2(-4.0, -5.0, 8.0, 1.5), Color(0.85, 0.30, 0.28))
	var tex: ImageTexture = DB.item_texture(item_id)
	if tex != null:
		draw_texture_rect(tex, Rect2(-4.0, -2.0, 8.0, 8.0), false, Color(1, 1, 1, 0.9))


# ------------------------------------------------------------- СЕТЬ (ADR-002, MP-E #90)
## Предметы по сети (scripts/net/net_machines.gd, § 4.2.1): физику, подбор и слияние
## считает хост. Клиенту — события: появление/обновление (SPAWN: net_record() + мешок)
## и исчезновение (DESPAWN). У клиента предмет — марионетка: летит той же баллистикой
## до приземления (World.move_body по тем же тайлам), к ближайшему герою тянется
## «на глаз» и прячется у него, пока хост не скажет, подобран ли он.
##
## Запись (NET_RECORD_BYTES): предмет u8 · число u16 · позиция 2×u16 (NetCodec.pos_u16) ·
## скорость 2×s16 (px/с) · флаги u8 (NIF_*) · возраст u16 (×10) · пауза подбора u8 (×100).

const NET_GROUP: StringName = &"net_item"
const NET_RECORD_BYTES: int = 15
const NIF_GROUNDED: int = 1
const NIF_DESPAWN: int = 2
const NIF_MAGNET: int = 4

## Номер предмета в сессии (хост выдаёт 1..65535; 0 — не разослан / не от хоста).
var net_id: int = 0

static var _net_heroes: Array = []
static var _net_heroes_frame: int = -1


func net_record() -> PackedByteArray:
	var b: PackedByteArray = PackedByteArray()
	b.resize(NET_RECORD_BYTES)
	b[0] = item_id & 0xFF
	b.encode_u16(1, clampi(count, 0, 0xFFFF))
	b.encode_u16(3, NetCodec.pos_u16(global_position.x))
	b.encode_u16(5, NetCodec.pos_u16(global_position.y))
	b.encode_s16(7, clampi(roundi(vel.x), -32768, 32767))
	b.encode_s16(9, clampi(roundi(vel.y), -32768, 32767))
	b[11] = (NIF_GROUNDED if grounded else 0) | (NIF_DESPAWN if despawn else 0) \
			| (NIF_MAGNET if magnet else 0)
	b.encode_u16(12, clampi(roundi(age * 10.0), 0, 0xFFFF))
	b[14] = clampi(roundi(pickup_delay * 100.0), 0, 255)
	return b


## Клиент: запись хоста (появление или обновление). false — запись битая.
func net_apply(b: PackedByteArray, p_bag: Array) -> bool:
	if b.size() != NET_RECORD_BYTES:
		return false
	item_id = b[0]
	count = b.decode_u16(1)
	global_position = Vector2(NetCodec.u16_pos(b.decode_u16(3)), NetCodec.u16_pos(b.decode_u16(5)))
	vel = Vector2(b.decode_s16(7), b.decode_s16(9))
	grounded = (b[11] & NIF_GROUNDED) != 0
	despawn = (b[11] & NIF_DESPAWN) != 0
	magnet = false
	age = b.decode_u16(12) / 10.0
	pickup_delay = b[14] / 100.0
	bag = p_bag
	visible = true
	queue_redraw()
	return true


## Клиент: кадр марионетки (вместо подбора и слияния — только вид).
func _net_puppet(delta: float) -> void:
	age += delta
	pickup_delay = maxf(0.0, pickup_delay - delta)
	if is_warning():
		modulate.a = 0.35 + 0.65 * absf(cos(age * PI * 4.0))
	elif modulate.a != 1.0:
		modulate.a = 1.0
	var hero: Node2D = _net_nearest_hero()
	var d: float = global_position.distance_to(hero.global_position) if hero != null else INF
	if not magnet and d < MAGNET_DIST and pickup_delay <= 0.0:
		magnet = true
	if magnet:
		if hero == null:
			magnet = false
			return
		if d < PICKUP_DIST:
			visible = false              # «подобран» — до ответа хоста (DESPAWN или обновление)
			return
		global_position += (hero.global_position - global_position).normalized() * 340.0 * delta
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
	if res["hit_x"]:
		vel.x = 0.0


## Ближайший живой герой (список героев — раз в физический кадр на все предметы).
func _net_nearest_hero() -> Node2D:
	var f: int = Engine.get_physics_frames()
	if f != _net_heroes_frame:
		_net_heroes_frame = f
		_net_heroes = get_tree().get_nodes_in_group("player")
	var best: Node2D = null
	var best_d: float = INF
	for h in _net_heroes:
		if not is_instance_valid(h) or bool(h.get("dead")):
			continue
		var dd: float = global_position.distance_squared_to(h.global_position)
		if dd < best_d:
			best_d = dd
			best = h
	return best
