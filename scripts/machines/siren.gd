class_name Siren
extends MachineBase
## Сирена (ADR-005 § 7.2, #172): кнопка паники. Рой и тень света не боятся,
## а от сирены бегут все пять видов.
##
## Заряд копится только под лучом любого цвета. Без луча стоит. E при полном
## заряде гонит фантомов в SIREN_RADIUS_TILES на SIREN_TIME секунд и обнуляет
## заряд. Питание не нужно: работает луч, не сеть.


## Заряд 0…SIREN_RECHARGE. Полный — можно жать E.
var charge: float = 0.0
## Луч упёрся в сирену на последнем перестроении. Без него заряд не растёт.
var charging: bool = false
## Сколько раз сработала — для сценариев.
var blasts: int = 0
## Кольцо после срабатывания: клиент рисует его по флагу сети.
var _ring: float = 0.0
var _was_charging: bool = false


func _init() -> void:
	kind = "Siren"
	z_index = 3
	can_turn = false


func _process(delta: float) -> void:
	super(delta)
	if _ring > 0.0:
		_ring = maxf(0.0, _ring - delta)
	if not Net.is_authority():
		queue_redraw()
		return
	var before: float = charge
	if charging:
		charge = minf(Balance.SIREN_RECHARGE, charge + delta)
	if charge != before or charging != _was_charging:
		_was_charging = charging
		queue_redraw()


## Луч гасится: сирена — конец линии, не труба.
func beam_pass(_in_dir: int, _color: int) -> Array:
	return []


## Любой цвет заряжает. 0 — луча нет, заряд стоит.
func beam_receive(mask: int) -> void:
	var next: bool = mask != 0
	if next == charging:
		return
	charging = next
	queue_redraw()


func ready() -> bool:
	return charge >= Balance.SIREN_RECHARGE - 0.01


## E при полном заряде. Возвращает false, если жать ещё рано.
func trigger() -> bool:
	if not Net.is_authority() or not ready():
		return false
	var n: int = blast()
	charge = 0.0
	blasts += 1
	_ring = 0.7
	Sfx.play_at("siren", global_position, -4.0, 1.0)
	UI.flash_ring(global_position, Color(1.0, 0.55, 0.15))
	Game.notify("Сирена: %d бегут." % n, Color(1.0, 0.7, 0.35))
	queue_redraw()
	return true


## Все живые фантомы в радиусе — в FLEE от этой клетки. Возвращает, сколько ушло.
func blast() -> int:
	var n: int = 0
	var r: float = Balance.SIREN_RADIUS_TILES * 16.0
	var r2: float = r * r
	var from: Vector2 = global_position
	for p in get_tree().get_nodes_in_group("phantom"):
		if not is_instance_valid(p) or not bool(p.get("alive")):
			continue
		if from.distance_squared_to(p.global_position) > r2:
			continue
		if p.has_method("force_flee"):
			p.force_flee(Balance.SIREN_TIME, from)
			n += 1
	return n


## E: один раз на нажатие, как у горелки. Неполный заряд — только подсказка.
func interact(p) -> void:
	var f: int = Engine.get_physics_frames()
	var fresh: bool = f - _interact_frame > 1
	_interact_frame = f
	if not fresh:
		return
	if trigger():
		return
	var left: int = ceili(Balance.SIREN_RECHARGE - charge)
	if charging:
		Game.notify("Сирена заряжается: %d с." % left, Color(1.0, 0.85, 0.4))
	else:
		Game.notify("Сирене нужен луч.", Color(1.0, 0.55, 0.35))


var _interact_frame: int = -10


func _draw() -> void:
	_draw_body(Rect2(-7.0, -6.0, 14.0, 14.0), charging or ready())
	# Рупор сверху: ребёнок отличает сирену от маяка — у маяка стекло, здесь воронка.
	draw_rect(Rect2(-5.0, -10.0, 10.0, 4.0), C_FRAME)
	draw_rect(Rect2(-3.0, -12.0, 6.0, 3.0), C_METAL_D)
	draw_rect(Rect2(-1.0, -14.0, 2.0, 3.0), C_HAZARD)
	var lamp: Color = C_LAMP_OFF
	if ready():
		lamp = C_BIO
	elif charging:
		lamp = C_HAZARD
	_draw_lamp(Vector2(4.0, -3.0), lamp)
	# Шкала заряда снизу вверх, как топливо у горелки.
	var f: float = clampf(charge / Balance.SIREN_RECHARGE, 0.0, 1.0)
	draw_rect(Rect2(-5.0, 2.0, 8.0, 3.0), C_SOOT)
	draw_rect(Rect2(-5.0, 2.0, 8.0 * f, 3.0), lamp if charging or ready() else C_METAL_HI)
	if _ring > 0.0:
		var a: float = _ring / 0.7
		draw_arc(Vector2.ZERO, 8.0 + (1.0 - a) * 10.0, 0.0, TAU, 16,
				Color(1.0, 0.55, 0.15, a), 1.0)


# ------------------------------------------------------------- СОХРАНЕНИЕ (#37)
func save_state() -> Dictionary:
	var d: Dictionary = super()
	d["charge"] = charge
	d["charging"] = charging
	d["blasts"] = blasts
	return d


func load_state(d: Dictionary) -> void:
	super(d)
	charge = clampf(float(d.get("charge", charge)), 0.0, Balance.SIREN_RECHARGE)
	charging = bool(d.get("charging", charging))
	blasts = int(d.get("blasts", blasts))
	_was_charging = charging
	queue_redraw()


# ------------------------------------------------------------- СЕТЬ (ADR-002)
## Байт заряда (0…255) и байт флагов: бит 0 — луч есть, бит 1 — только что
## сработала (клиент рисует кольцо). Срабатывание ещё едет Fx.RING_EMP.
func net_state() -> PackedByteArray:
	var b: PackedByteArray = super()
	b.append(MachineBase.net_u8(charge / Balance.SIREN_RECHARGE))
	var flags: int = 1 if charging else 0
	if _ring > 0.35:
		flags |= 2
	b.append(flags)
	return b


func apply_net_state(b: PackedByteArray) -> int:
	var o: int = super(b)
	if o < 0 or b.size() < o + 2:
		return -1
	charge = float(b[o]) / 255.0 * Balance.SIREN_RECHARGE
	charging = (int(b[o + 1]) & 1) != 0
	if (int(b[o + 1]) & 2) != 0 and _ring <= 0.0:
		_ring = 0.7
		UI.flash_ring(global_position, Color(1.0, 0.55, 0.15))
	queue_redraw()
	return o + 2
