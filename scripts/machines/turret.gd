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
	if not Net.is_authority():   # СЕТЬ (ADR-002): работает хост, клиент рисует по net_state
		return
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
	# Станина — кремовый короб с жёлтой разметкой, на нём поворотная башня.
	_draw_body(Rect2(-8.0, 1.0, 16.0, 7.0), powered)
	draw_rect(Rect2(-5.0, -1.0, 10.0, 2.0), C_FRAME)
	# Ствол-разрядник (поворачивается к цели), срез — бирюзовый разрядник.
	var pivot: Vector2 = Vector2(0.0, -3.0)
	var tip: Vector2 = pivot + Vector2.from_angle(_aim) * MUZZLE
	draw_line(pivot, tip, C_FRAME, 3.0)
	var tp: Vector2 = tip.round()
	draw_rect(Rect2(tp - Vector2(1.0, 1.0), Vector2(3.0, 3.0)), C_BIO if powered else C_METAL_D)
	# Башня — квадратный купол в раме, блик в углу.
	draw_rect(Rect2(-4.0, -7.0, 8.0, 7.0), C_METAL_D)
	draw_rect(Rect2(-3.0, -6.0, 6.0, 5.0), C_METAL if powered else C_METAL_OFF)
	draw_rect(Rect2(-3.0, -6.0, 2.0, 1.0), C_METAL_HI)
	draw_rect(Rect2(-1.0, -4.0, 2.0, 2.0), C_FRAME)
	# Лампочка питания: бирюзовая — норма, жёлтая — браун-аут, красная — нет питания
	var lamp: Color = C_LAMP_OFF
	if powered:
		lamp = C_SCREEN_HI if efficiency >= 0.999 else C_HAZARD
	_draw_lamp(Vector2(5.0, 4.0), lamp)


# ------------------------------------------------------------- СОХРАНЕНИЕ (#37)
## Счётчик выстрелов, перезарядка и угол ствола. Цель (узел фантома) не пишется:
## фантомы после загрузки выходят заново (Threat.save_state), турель найдёт новую.
func save_state() -> Dictionary:
	var d: Dictionary = super()
	d["shots"] = shots
	d["cooldown"] = _cooldown
	d["aim"] = _aim
	return d


func load_state(d: Dictionary) -> void:
	super(d)
	shots = int(d.get("shots", shots))
	_cooldown = float(d.get("cooldown", _cooldown))
	_aim = float(d.get("aim", _aim))
	target = null
	_scan_t = 0.0


# ------------------------------------------------------------- СЕТЬ (ADR-002, MP-E #90)
## + угол ствола u8 · выстрелов u8 (по модулю 256) · точка последнего выстрела 2×u16
## (NetCodec.pos_u16). Выстрел хост шлёт в ближайший сетевой такт, не ждёт 4 Гц
## (NetMachines); клиент, увидев новый счётчик, повторяет дугу (World.turret_fired)
## и звук у себя.
const NET_BYTES: int = 6
var _net_to: Vector2 = Vector2.ZERO


func net_state() -> PackedByteArray:
	if not fired.is_connected(_net_on_fired):
		fired.connect(_net_on_fired)        # хост: запомнить точку выстрела
	var b: PackedByteArray = super()
	b.append(int(roundf(fposmod(_aim, TAU) / TAU * 256.0)) & 0xFF)
	b.append(shots & 0xFF)
	b.resize(b.size() + 4)
	b.encode_u16(b.size() - 4, NetCodec.pos_u16(_net_to.x))
	b.encode_u16(b.size() - 2, NetCodec.pos_u16(_net_to.y))
	return b


func _net_on_fired(_from: Vector2, to: Vector2) -> void:
	_net_to = to


func apply_net_state(b: PackedByteArray) -> int:
	var o: int = super(b)
	if o < 0 or b.size() < o + NET_BYTES:
		return -1
	_aim = float(b[o]) / 256.0 * TAU
	var n: int = b[o + 1]
	var to: Vector2 = Vector2(NetCodec.u16_pos(b.decode_u16(o + 2)), NetCodec.u16_pos(b.decode_u16(o + 4)))
	if n != shots & 0xFF:
		shots += (n - shots) & 0xFF
		_net_to = to
		var from: Vector2 = global_position + Vector2(0.0, -3.0) + Vector2.from_angle(_aim) * MUZZLE
		Sfx.play_at("turret_zap", global_position, -8.0, 1.0)
		fired.emit(from, to)
		World.turret_fired.emit(from, to)
	queue_redraw()
	return o + NET_BYTES
