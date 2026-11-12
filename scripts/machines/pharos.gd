class_name Pharos
extends MachineBase
## Маяк (ADR-005 § 5, #167, #168): единственная башня. Что делает — зависит
## от цвета луча, который в него попал.
##
## Луч поглощает с любой грани (beam_pass → []). Цвет сообщает Beams.rebuild
## через beam_receive: OR всех входов. Питание не нужно — работает, пока луч
## горит. Смеси (жёлтый, голубой, пурпурный, белый) приходят смесителем,
## не отдельным топливом.
##
## Красный жжёт, зелёный чинит, жёлтый светит. Синий морозит, голубой держит
## купол, пурпурный зовёт рой и тень, белый показывает руду сквозь породу.

## Линза чуть выше центра корпуса: отсюда бьёт дуга.
const MUZZLE: Vector2 = Vector2(0.0, -6.0)
## Руда, которую белый показывает сквозь породу. Камень и земля — нет.
const ORES: Array[int] = [
	IDs.T.COAL_ORE, IDs.T.COPPER_ORE, IDs.T.IRON_ORE,
	IDs.T.CRYSTAL_ORE, IDs.T.SCRAP_ORE, IDs.T.LIGHT_CRYSTAL,
]

## Цвет луча, который попал на последнем перестроении. 0 — луча нет.
var color: int = 0
## Линза вставлена навсегда (#172). Разбор возвращает её отдельно от маяка.
var lens: bool = false
## Есть луч — маяк работает. Какой эффект — решает match по цвету.
var active: bool = false
## Выстрелов за жизнь — для сценариев.
var shots: int = 0
## Сколько раз починил соседа — для сценариев.
var heals: int = 0
## Клеток руды, открытых белым — для сценариев.
var revealed: int = 0
## Купол голубого: сколько урона ещё примет, прежде чем погаснуть.
var dome_hp: float = Balance.PHAROS_DOME_HP
## Купол сейчас держит. false — погашен, ждёт PHAROS_DOME_DOWN.
var dome_up: bool = false
var target: Node2D = null

var _cooldown: float = Balance.PHAROS_RED_PERIOD
var _scan_t: float = 0.0
var _heal_t: float = 0.0
var _frost_t: float = 0.0
var _white_t: float = 0.0
var _dome_down: float = 0.0
var _light: Dictionary = {}
var _lit: bool = false
## В каком списке мира стоим: 0 нет, Beams.B / C / M.
var _listed: int = 0
## Глава «Цвета» (#217): прожектор можно погасить тапом, не снимая жёлтый луч.
## Иначе эхо ночи не доходит — маяк светит раньше, чем игрок успел встать.
var lamp_off: bool = false


func _init() -> void:
	kind = "Pharos"
	z_index = 3
	can_turn = false
	hp = Balance.PHAROS_HP
	max_hp = Balance.PHAROS_HP


func interact(_p) -> void:
	# Тап по жёлтому маяку гасит и зажигает прожектор. Луч при этом остаётся:
	# цвет башни не меняется, меняется только свет. Другие цвета тап не трогает.
	if color != Beams.Y or not active or _destroyed:
		return
	var f: int = Engine.get_physics_frames()
	if f - _lamp_frame <= 1:
		return
	_lamp_frame = f
	lamp_off = not lamp_off
	_sync_light()
	Game.notify("Прожектор: %s" % ("погашен" if lamp_off else "горит"),
			Color(1.0, 0.85, 0.4) if lamp_off else Color(1.0, 0.95, 0.55), IDs.I.PHAROS)


var _lamp_frame: int = -10


func _process(delta: float) -> void:
	super(delta)
	# Клиент не считает урон, стан и туман: explored уже в снимке входа,
	# а дельт тумана нет — свой reveal_cells разошёлся бы с хостом (#180).
	if not Net.is_authority():
		return
	if not active:
		return
	match color:
		Beams.R:
			_tick_red(delta)
		Beams.G:
			_tick_green(delta)
		Beams.B:
			_tick_blue(delta)
		Beams.C:
			_tick_dome(delta)
		Beams.W:
			_tick_white(delta)
		Beams.Y, Beams.M:
			pass


## Луч поглощается: маяк — конец линии, не труба.
func beam_pass(_in_dir: int, _color: int) -> Array:
	return []


## Цвет, который упёрся в маяк (OR всех входов). 0 — луча нет.
## Клиент цвет не решает: его трассировка ещё не видит пламени хоста и затёрла бы
## стекло, пришедшее net_state (#180).
func beam_receive(mask: int) -> void:
	if not Net.is_authority():
		return
	var next: int = mask & 7
	if next == color:
		return
	color = next
	active = color != 0
	_cooldown = Balance.PHAROS_RED_PERIOD if color == Beams.R else 0.0
	_heal_t = 0.0
	_frost_t = 0.0
	_white_t = 0.0
	_scan_t = 0.0
	_apply_color()
	_sync_light()
	queue_redraw()


## Под зелёным маяк не ломается. Другие цвета — как у обычной машины.
## Свой купол маяк не накрывает: удар по башне идёт в её HP.
func take_damage(amount: float) -> void:
	if color == Beams.G and active:
		return
	super(amount)


## Списки мира и прочность под цвет. Пурпурный временно 200 HP; смена цвета
## возвращает 100, текущее HP не выше нового максимума.
func _apply_color() -> void:
	_unlist()
	if not active:
		dome_up = false
		_cap_hp(Balance.PHAROS_HP)
		return
	match color:
		Beams.B:
			_list_as(Beams.B)
		Beams.C:
			_list_as(Beams.C)
			dome_hp = Balance.PHAROS_DOME_HP
			dome_up = true
			_dome_down = 0.0
		Beams.M:
			_list_as(Beams.M)
			max_hp = Balance.PHAROS_LURE_HP
			if hp <= Balance.PHAROS_HP + 0.01:
				hp = Balance.PHAROS_LURE_HP
			return
	_cap_hp(Balance.PHAROS_HP)


func _cap_hp(cap: float) -> void:
	max_hp = cap
	hp = minf(hp, max_hp)


func _list_as(which: int) -> void:
	var bag: Array = _bag(which)
	if bag == null:
		return
	if not bag.has(self):
		bag.append(self)
	_listed = which


func _unlist() -> void:
	if _listed == 0:
		return
	var bag: Array = _bag(_listed)
	if bag != null:
		bag.erase(self)
	_listed = 0
	dome_up = false


func _bag(which: int) -> Array:
	if which == Beams.B:
		return World.pharos_blue
	if which == Beams.C:
		return World.pharos_dome
	if which == Beams.M:
		return World.pharos_lure
	return []


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
	var reach: float = red_range_px()
	var r2: float = reach * reach
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
	t.take_damage(red_damage(), global_position)
	Sfx.play_at("turret_zap", global_position, -8.0, randf_range(0.92, 1.08))
	var arc: Color = Beams.COLOR[Beams.R]
	World.pharos_fired.emit(from, to, arc)
	queue_redraw()


# ---------------------------------------------------------------- ЖЁЛТЫЙ

## Радиус света — та же формула, что у прожектора: 46 + 2·60 px.
## Линза множит силу, радиус растёт вместе с ней.
func light_radius() -> float:
	return World.LIGHT_BASE_RADIUS + yellow_power() * World.LIGHT_RADIUS_PER_POWER


func _sync_light() -> void:
	var want: bool = color == Beams.Y and active and not _destroyed and not lamp_off
	if want == _lit:
		return
	_lit = want
	if want:
		_light = World.add_light_source(global_position, light_radius(), yellow_power())
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


# ---------------------------------------------------------------- СИНИЙ

## Раз в 3 с фантомы в радиусе не бьют 1 с. Скорость режет World.slow_factor_at.
## Осада главы «Солнце» в радиусе стоит, пока синий горит: импульса раз в 3 с
## не хватает, копатель доходит между станами (#218).
func _tick_blue(delta: float) -> void:
	_hold_siege()
	_frost_t -= delta
	if _frost_t > 0.0:
		return
	_frost_t = Balance.PHAROS_BLUE_STUN_PERIOD
	var r: int = blue_radius()
	var frost: Color = Beams.COLOR[Beams.B]
	for p in get_tree().get_nodes_in_group("phantom"):
		if not is_instance_valid(p) or not bool(p.get("alive")):
			continue
		var pc: Vector2i = World.world_to_cell(p.global_position)
		if maxi(absi(pc.x - cell.x), absi(pc.y - cell.y)) > r:
			continue
		if p.has_method("apply_stun"):
			p.apply_stun(Balance.PHAROS_BLUE_STUN)
		UI.spawn_chip(pc, frost)


## Копатель на осаде в радиусе мороза не шагает, пока луч синий.
func _hold_siege() -> void:
	var r: int = blue_radius()
	for p in get_tree().get_nodes_in_group("phantom"):
		if not is_instance_valid(p) or String(p.get("kind")) != "burrower":
			continue
		if p.get("siege_target") == null:
			continue
		var pc: Vector2i = World.world_to_cell(p.global_position)
		if maxi(absi(pc.x - cell.x), absi(pc.y - cell.y)) > r:
			continue
		if p.has_method("apply_stun"):
			p.apply_stun(0.2)


# --------------------------------------------------------------- ГОЛУБОЙ

func _tick_dome(delta: float) -> void:
	if dome_up:
		return
	_dome_down -= delta
	if _dome_down > 0.0:
		return
	dome_hp = Balance.PHAROS_DOME_HP
	dome_up = true
	queue_redraw()


## Удар по постройке под куполом. 100 урона гасит купол на 10 с.
func absorb_dome(amount: float) -> void:
	if not dome_up or amount <= 0.0:
		return
	dome_hp = maxf(0.0, dome_hp - amount)
	UI.spawn_chip(cell, Beams.COLOR[Beams.C])
	if dome_hp <= 0.0:
		dome_up = false
		_dome_down = Balance.PHAROS_DOME_DOWN
	queue_redraw()


# ---------------------------------------------------------------- БЕЛЫЙ

## Раз в секунду открывает неразведанную руду в радиусе 8. Камень не трогает.
func _tick_white(delta: float) -> void:
	_white_t -= delta
	if _white_t > 0.0:
		return
	_white_t = Balance.PHAROS_WHITE_PERIOD
	var cells: Array = _ore_hidden()
	if cells.is_empty():
		return
	var n: int = World.reveal_cells(cells)
	revealed += n
	if n > 0:
		UI.spawn_chip(cell, Beams.COLOR[Beams.W])


func _ore_hidden() -> Array:
	var out: Array = []
	var r: int = white_radius()
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if maxi(absi(dx), absi(dy)) > r:
				continue
			var c: Vector2i = cell + Vector2i(dx, dy)
			if not World.in_bounds(c.x, c.y):
				continue
			if World.is_explored(c):
				continue
			if not ORES.has(World.get_tile_v(c)):
				continue
			out.append(c)
	return out


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
	_unlist()
	_drop_light()
	# Разбор героем гасит флаг сам и кладёт линзу в рюкзак. Разрушение и
	# сетевой снос — роняют её на землю, чтобы не пропала.
	if lens:
		lens = false
		spawn_item(IDs.I.LENS, 1, global_position + Vector2(0.0, -6.0))


func _exit_tree() -> void:
	_unlist()
	_drop_light()


func _drop_light() -> void:
	if _lit:
		World.remove_light_source(_light)
		_light = {}
		_lit = false


func _draw() -> void:
	# Корпус-башня: кремовый короб, стекло сверху — цвет луча или тёмное стекло.
	_draw_body(Rect2(-7.0, -1.0, 14.0, 9.0), active)
	draw_rect(Rect2(-2.0, -6.0, 4.0, 4.0), C_FRAME)
	var glass: Color = C_SCREEN
	if color > 0 and color < Beams.COLOR.size() and active:
		glass = Beams.COLOR[color]
	draw_rect(Rect2(-5.0, -8.0, 10.0, 4.0), C_FRAME)
	draw_rect(Rect2(-4.0, -7.0, 8.0, 2.0), glass)
	if lens:
		# Вставленная линза: белый ободок и искра. Без неё башня — тёмное стекло.
		draw_rect(Rect2(-6.0, -9.0, 12.0, 1.0), Color(0.95, 0.97, 1.0))
		draw_rect(Rect2(-1.0, -10.0, 2.0, 2.0), Color(1.0, 0.98, 0.85))
	if active and color == Beams.R and _cooldown > Balance.PHAROS_RED_PERIOD - 0.12:
		# Вспышка стекла в такт выстрелу: ребёнок видит, что башня жжёт.
		draw_rect(Rect2(-3.0, -10.0, 6.0, 2.0), Color(glass.r, glass.g, glass.b, 1.0))
	elif active and color == Beams.Y:
		draw_rect(Rect2(-8.0, -12.0, 16.0, 6.0), Color(glass.r, glass.g, glass.b, 0.18))
	elif active and color == Beams.G:
		draw_rect(Rect2(-3.0, -7.0, 2.0, 1.0), glass.lightened(0.3))
	elif active and color == Beams.B:
		draw_rect(Rect2(-6.0, -11.0, 2.0, 2.0), glass)
		draw_rect(Rect2(4.0, -11.0, 2.0, 2.0), glass)
	elif active and color == Beams.W:
		# Белая искра над стеклом: руда рядом уже видна.
		draw_rect(Rect2(-1.0, -11.0, 2.0, 2.0), Color.WHITE)


# ------------------------------------------------------------- СОХРАНЕНИЕ (#37)
func save_state() -> Dictionary:
	var d: Dictionary = super()
	d["color"] = color
	d["lens"] = lens
	d["shots"] = shots
	d["heals"] = heals
	d["revealed"] = revealed
	d["dome_hp"] = dome_hp
	d["dome_up"] = dome_up
	d["cooldown"] = _cooldown
	d["heal_t"] = _heal_t
	d["frost_t"] = _frost_t
	d["white_t"] = _white_t
	d["dome_down"] = _dome_down
	d["lamp_off"] = lamp_off
	return d


func load_state(d: Dictionary) -> void:
	super(d)
	color = int(d.get("color", color)) & 7
	lens = bool(d.get("lens", lens))
	active = color != 0
	shots = int(d.get("shots", shots))
	heals = int(d.get("heals", heals))
	revealed = int(d.get("revealed", revealed))
	dome_hp = float(d.get("dome_hp", dome_hp))
	_cooldown = float(d.get("cooldown", _cooldown))
	_heal_t = float(d.get("heal_t", _heal_t))
	_frost_t = float(d.get("frost_t", _frost_t))
	_white_t = float(d.get("white_t", _white_t))
	_dome_down = float(d.get("dome_down", _dome_down))
	lamp_off = bool(d.get("lamp_off", lamp_off))
	target = null
	_scan_t = 0.0
	_apply_color()
	if color == Beams.C and active:
		dome_up = bool(d.get("dome_up", true))
	relight()
	queue_redraw()


# ------------------------------------------------------------- СЕТЬ (ADR-002)
## Байт цвета: 3 бита маски, бит 3 — линза вставлена (#172). Выстрелы клиенту
## не нужны — дугу рисует хост, а видимый признак «жжёт» — цвет стекла.
## Длина байта та же: старый пакет с нулём в бите 3 читается как маяк без линзы.
func net_state() -> PackedByteArray:
	var b: PackedByteArray = super()
	var bits: int = color & 7
	if lens:
		bits |= 8
	# Бит 4 — прожектор погашен тапом (#217). Старый пакет его не ставит.
	if lamp_off:
		bits |= 16
	b.append(bits)
	return b


func apply_net_state(b: PackedByteArray) -> int:
	var o: int = super(b)
	if o < 0 or b.size() < o + 1:
		return -1
	var bits: int = int(b[o])
	var next: int = bits & 7
	var has_lens: bool = (bits & 8) != 0
	var off: bool = (bits & 16) != 0
	if next != color or has_lens != lens or off != lamp_off:
		color = next
		lens = has_lens
		lamp_off = off
		active = color != 0
		# Клиент собирает свои списки из цвета: купол рисуется здесь,
		# белый открывает руду без пакета explored.
		_apply_color()
		_sync_light()
		queue_redraw()
	return o + 1


# --------------------------------------------------------------- линза (#172)

## Красный бьёт дальше и больнее, только если линза вставлена.
func red_range_px() -> float:
	var tiles: float = Balance.LENS_RANGE_TILES if lens else Balance.PHAROS_RANGE_TILES
	return tiles * 16.0


func red_damage() -> float:
	var d: float = Balance.PHAROS_RED_DAMAGE
	return d * Balance.LENS_MUL if lens else d


func yellow_power() -> float:
	var p: float = Balance.PHAROS_YELLOW_POWER
	return p * Balance.LENS_MUL if lens else p


func blue_radius() -> int:
	return Balance.PHAROS_BLUE_RADIUS + (Balance.LENS_RADIUS_BONUS if lens else 0)


func dome_radius() -> int:
	return Balance.PHAROS_DOME_RADIUS + (Balance.LENS_RADIUS_BONUS if lens else 0)


func lure_px() -> float:
	return Balance.PHAROS_LURE_PX + (Balance.LENS_LURE_BONUS_PX if lens else 0.0)


func white_radius() -> int:
	return Balance.LENS_WHITE_RADIUS if lens else Balance.PHAROS_WHITE_RADIUS


## E с линзой в руке. false — линзы нет или она уже стоит.
func insert_lens(p) -> bool:
	if lens or p == null:
		return false
	var st: ItemStack = p.inv.selected_stack()
	if st.is_empty() or st.id != IDs.I.LENS:
		return false
	p.inv.remove_at(p.inv.selected, 1)
	lens = true
	if _lit:
		relight()
	queue_redraw()
	Sfx.play("craft", -8.0, 1.2)
	Game.notify("Линза вставлена в маяк.", Color(0.85, 0.95, 1.0))
	return true


## Линзу в рюкзак кладёт герой: он читает lens до вызова. Флаг гасим здесь,
## чтобы _on_destroyed не выронил вторую.
func dismantle() -> int:
	lens = false
	return super()
