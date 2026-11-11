class_name Pharos
extends MachineBase
## Маяк (ADR-005 § 5, #167): единственная башня. Что делает — зависит от цвета
## луча, который в него попал. Часть 1: красный жжёт, жёлтый светит, зелёный чинит.
##
## Луч поглощает с любой грани (beam_pass → []). Цвет сообщает Beams.rebuild
## через beam_receive: OR всех входов. Питание не нужно — работает, пока луч
## горит. Синий, голубой, пурпурный и белый — заглушки до C5 (#168).
## Жёлтый приходит смесью; смесителя ещё нет (#165) — цвет можно подать лучом
## напрямую, крафт жёлтого топлива не делаем.

const RANGE_PX: float = Balance.PHAROS_RANGE_TILES * 16.0
## Линза чуть выше центра корпуса: отсюда бьёт дуга.
const MUZZLE: Vector2 = Vector2(0.0, -6.0)

## Цвет луча, который попал на последнем перестроении. 0 — луча нет.
var color: int = 0
## Красный стреляет, жёлтый светит, зелёный чинит. Остальные маски молчат.
var active: bool = false
## Выстрелов за жизнь — для сценариев.
var shots: int = 0
## Сколько раз починил соседа — для сценариев.
var heals: int = 0
var target: Node2D = null

var _cooldown: float = Balance.PHAROS_RED_PERIOD
var _scan_t: float = 0.0
var _heal_t: float = 0.0
var _light: Dictionary = {}
var _lit: bool = false


func _init() -> void:
	kind = "Pharos"
	z_index = 3
	can_turn = false
	hp = Balance.PHAROS_HP
	max_hp = Balance.PHAROS_HP


func _process(delta: float) -> void:
	super(delta)
	if not Net.is_authority():   # СЕТЬ (ADR-002): считает хост, клиент рисует по net_state
		return
	if not active:
		return
	match color:
		Beams.R:
			_tick_red(delta)
		Beams.Y:
			pass
		Beams.G:
			_tick_green(delta)
		_:
			pass   # C5 (#168): синий, голубой, пурпурный, белый


## Луч поглощается: маяк — конец линии, не труба.
func beam_pass(_in_dir: int, _color: int) -> Array:
	return []


## Цвет, который упёрся в маяк (OR всех входов). 0 — луча нет.
func beam_receive(mask: int) -> void:
	var next: int = mask & 7
	if next == color:
		return
	color = next
	active = color != 0
	_cooldown = Balance.PHAROS_RED_PERIOD if color == Beams.R else 0.0
	_heal_t = 0.0
	_scan_t = 0.0
	_sync_light()
	queue_redraw()


## Под зелёным маяк не ломается. Другие цвета — как у обычной машины.
func take_damage(amount: float) -> void:
	if color == Beams.G and active:
		return
	super(amount)


# ---------------------------------------------------------------- КРАСНЫЙ

func _tick_red(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta
		if _cooldown > 0.0:
			return
	_scan_t -= delta
	if _scan_t > 0.0:
		return
	var t: Node2D = pick_target()
	if t == null:
		_scan_t = Balance.TURRET_SCAN_PERIOD
		return
	_fire(t)


## Ближайший фантом в радиусе с прямой видимостью. Приоритет — как у турели.
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


## Прямая видимость: твёрдое между маяком и целью — не бьём (B1).
func _los(to: Vector2) -> bool:
	var b: Vector2i = World.world_to_cell(to)
	var hit: Vector2i = World.first_solid_on_ray(World.cell_to_world(cell), World.cell_to_world(b), false)
	return hit == Vector2i(-1, -1) or hit == b


func _fire(t: Node2D) -> void:
	target = t
	_cooldown = Balance.PHAROS_RED_PERIOD
	shots += 1
	var to: Vector2 = t.global_position
	var from: Vector2 = global_position + MUZZLE
	t.take_damage(Balance.PHAROS_RED_DAMAGE, global_position)
	Sfx.play_at("turret_zap", global_position, -8.0, randf_range(0.92, 1.08))
	var arc: Color = Beams.COLOR[Beams.R]
	World.pharos_fired.emit(from, to, arc)
	queue_redraw()


# ---------------------------------------------------------------- ЖЁЛТЫЙ

## Радиус света — та же формула, что у прожектора: 46 + 2·60 px.
static func light_radius() -> float:
	return World.LIGHT_BASE_RADIUS + Balance.PHAROS_YELLOW_POWER * World.LIGHT_RADIUS_PER_POWER


func _sync_light() -> void:
	var want: bool = color == Beams.Y and active and not _destroyed
	if want == _lit:
		return
	_lit = want
	if want:
		_light = World.add_light_source(global_position, light_radius(), Balance.PHAROS_YELLOW_POWER)
	else:
		World.remove_light_source(_light)
		_light = {}
	queue_redraw()


func relight() -> void:
	if _lit:
		World.remove_light_source(_light)
		_light = {}
		_lit = false
	_sync_light()


# ---------------------------------------------------------------- ЗЕЛЁНЫЙ

func _tick_green(delta: float) -> void:
	_heal_t -= delta
	if _heal_t > 0.0:
		return
	_heal_t = Balance.PHAROS_GREEN_PERIOD
	var r: int = Balance.PHAROS_GREEN_RADIUS
	var bio: Color = MachineBase.C_BIO
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if absi(dx) + absi(dy) > r:
				continue
			var n = World.machines.get(cell + Vector2i(dx, dy))
			if n == null or n == self or not is_instance_valid(n):
				continue
			if float(n.hp) >= float(n.max_hp) - 0.01:
				continue
			n.hp = minf(float(n.max_hp), float(n.hp) + Balance.PHAROS_GREEN_HEAL)
			n.anim = 1.0
			n.queue_redraw()
			UI.spawn_chip(n.cell, bio)
			heals += 1


func _on_destroyed() -> void:
	_drop_light()


func _exit_tree() -> void:
	_drop_light()


func _drop_light() -> void:
	if _lit:
		World.remove_light_source(_light)
		_light = {}
		_lit = false


func _draw() -> void:
	# Корпус-башня: кремовый короб, линза сверху — цвет луча или тёмное стекло.
	_draw_body(Rect2(-7.0, -1.0, 14.0, 9.0), active)
	draw_rect(Rect2(-2.0, -6.0, 4.0, 4.0), C_FRAME)
	var lens: Color = C_SCREEN
	if color > 0 and color < Beams.COLOR.size() and active:
		lens = Beams.COLOR[color]
	draw_rect(Rect2(-5.0, -8.0, 10.0, 4.0), C_FRAME)
	draw_rect(Rect2(-4.0, -7.0, 8.0, 2.0), lens)
	if active and color == Beams.R and _cooldown > Balance.PHAROS_RED_PERIOD - 0.12:
		# Вспышка линзы в такт выстрелу: ребёнок видит, что башня жжёт.
		draw_rect(Rect2(-3.0, -10.0, 6.0, 2.0), Color(lens.r, lens.g, lens.b, 1.0))
	elif active and color == Beams.Y:
		draw_rect(Rect2(-8.0, -12.0, 16.0, 6.0), Color(lens.r, lens.g, lens.b, 0.18))
	elif active and color == Beams.G:
		draw_rect(Rect2(-3.0, -7.0, 2.0, 1.0), lens.lightened(0.3))


# ------------------------------------------------------------- СОХРАНЕНИЕ (#37)
func save_state() -> Dictionary:
	var d: Dictionary = super()
	d["color"] = color
	d["shots"] = shots
	d["heals"] = heals
	d["cooldown"] = _cooldown
	d["heal_t"] = _heal_t
	return d


func load_state(d: Dictionary) -> void:
	super(d)
	color = int(d.get("color", color)) & 7
	active = color != 0
	shots = int(d.get("shots", shots))
	heals = int(d.get("heals", heals))
	_cooldown = float(d.get("cooldown", _cooldown))
	_heal_t = float(d.get("heal_t", _heal_t))
	target = null
	_scan_t = 0.0
	relight()
	queue_redraw()


# ------------------------------------------------------------- СЕТЬ (ADR-002)
## Байт цвета: 3 бита маски. Выстрелы клиенту не нужны — дугу рисует хост,
## а видимый признак «жжёт» — цвет линзы. Длина net_state базы не меняется.
func net_state() -> PackedByteArray:
	var b: PackedByteArray = super()
	b.append(color & 7)
	return b


func apply_net_state(b: PackedByteArray) -> int:
	var o: int = super(b)
	if o < 0 or b.size() < o + 1:
		return -1
	var next: int = int(b[o]) & 7
	if next != color:
		color = next
		active = color != 0
		_sync_light()
		queue_redraw()
	return o + 1
