class_name Turret
extends MachineBase
## Турель-разрядник (ADR-001 § 4.4, #31): бьёт фантомов разрядом.
##
## Радиус Balance.TURRET_RANGE_TILES, нужна прямая видимость (клетки между
## турелью и целью не твёрдые). Урон Balance.TURRET_DAMAGE раз в
## Balance.TURRET_PERIOD секунд полезной работы: перезарядка идёт через
## work(delta), поэтому при efficiency 0.5 турель стреляет вдвое реже.
## Цель — по приоритету Balance.TURRET_PRIORITY (тень > копатель > двойник >
## эхо > рой), при равном — ближайшая.
##
## Дугу выстрела рисует только WorldFX (#34) по World.turret_fired — сама
## турель её не рисует (иначе дуга двойная). Точка from — срез ствола.

## Выстрел: из точки from в точку to (мировые координаты).
signal fired(from: Vector2, to: Vector2)

const RANGE_PX: float = Balance.TURRET_RANGE_TILES * 16.0
const MUZZLE: float = 7.0           ## длина ствола от центра купола, px

var shots: int = 0                  ## выстрелов за жизнь — для сценариев
var target: Node2D = null           ## последняя цель
var _cooldown: float = 0.0          ## секунды полезной работы до выстрела
var _scan_t: float = 0.0
var _aim: float = -PI * 0.5         ## угол ствола


func _init() -> void:
	kind = "Turret"
	z_index = 3
	hp = Balance.TURRET_HP
	max_hp = Balance.TURRET_HP


func _process(delta: float) -> void:
	super(delta)
	if not powered:
		return
	if _cooldown > 0.0:
		_cooldown -= work(delta)
		if _cooldown > 0.0:
			return
	# Заряжена: ищем цель не чаще TURRET_SCAN_PERIOD, пока её нет.
	_scan_t -= delta
	if _scan_t > 0.0:
		return
	var t: Node2D = pick_target()
	if t == null:
		_scan_t = Balance.TURRET_SCAN_PERIOD
		return
	_fire(t)


## Лучшая цель в радиусе с прямой видимостью (null — стрелять не в кого).
func pick_target() -> Node2D:
	var best: Node2D = null
	var best_rank: int = 1 << 30
	var best_d2: float = INF
	var r2: float = RANGE_PX * RANGE_PX
	var me: Vector2 = global_position
	for p in get_tree().get_nodes_in_group("phantom"):
		if not is_instance_valid(p) or not bool(p.get("alive")):
			continue
		var d2: float = me.distance_squared_to(p.global_position)
		if d2 > r2:
			continue
		var rank: int = Balance.TURRET_PRIORITY.find(String(p.get("kind")))
		if rank < 0:
			rank = Balance.TURRET_PRIORITY.size()
		if rank > best_rank or (rank == best_rank and d2 >= best_d2):
			continue
		if not _los(p.global_position):
			continue
		best = p
		best_rank = rank
		best_d2 = d2
	return best


## Прямая видимость по клеткам (как у фантома): твёрдое между — не видно.
func _los(to: Vector2) -> bool:
	var a: Vector2i = cell
	var b: Vector2i = World.world_to_cell(to)
	var steps: int = maxi(absi(b.x - a.x), absi(b.y - a.y))
	for i in range(1, steps):
		var k: float = float(i) / float(steps)
		var c: Vector2i = Vector2i(int(round(lerpf(a.x, b.x, k))), int(round(lerpf(a.y, b.y, k))))
		if World.is_solid_cell(c):
			return false
	return true


func _fire(t: Node2D) -> void:
	target = t
	_cooldown = Balance.TURRET_PERIOD
	shots += 1
	var to: Vector2 = t.global_position
	var pivot: Vector2 = global_position + Vector2(0.0, -3.0)
	_aim = (to - pivot).angle()
	var from: Vector2 = pivot + Vector2.from_angle(_aim) * MUZZLE
	queue_redraw()                  # ствол повернулся
	t.take_damage(Balance.TURRET_DAMAGE, global_position)
	Sfx.play_at("turret_zap", global_position, -8.0, randf_range(0.92, 1.08))
	fired.emit(from, to)
	World.turret_fired.emit(from, to)


func _draw() -> void:
	var base: Color = Color(0.36, 0.40, 0.48) if powered else Color(0.25, 0.27, 0.31)
	# Станина
	draw_rect(Rect2(-8.0, 2.0, 16.0, 6.0), base.darkened(0.15))
	draw_rect(Rect2(-8.0, 2.0, 16.0, 1.5), base.lightened(0.2))
	draw_rect(Rect2(-5.0, -1.0, 10.0, 4.0), base)
	# Ствол-разрядник
	var pivot: Vector2 = Vector2(0.0, -3.0)
	var tip: Vector2 = pivot + Vector2.from_angle(_aim) * MUZZLE
	draw_line(pivot, tip, Color(0.70, 0.74, 0.80), 3.0)
	draw_circle(tip, 1.6, Color(0.55, 0.9, 1.0) if powered else Color(0.35, 0.4, 0.45))
	# Купол
	draw_circle(pivot, 4.5, base.lightened(0.1))
	draw_circle(pivot + Vector2(-1.2, -1.2), 1.4, base.lightened(0.35))
	# Лампочка питания: зелёная — норма, жёлтая — браун-аут, красная — нет питания
	var lamp: Color = Color(0.9, 0.25, 0.2)
	if powered:
		lamp = Color(0.4, 1.0, 0.5) if efficiency >= 0.999 else Color(1.0, 0.8, 0.2)
	draw_circle(Vector2(6.0, 5.0), 1.5, lamp)
