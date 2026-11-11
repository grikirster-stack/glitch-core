class_name Burner
extends MachineBase
## Горелка (ADR-005 § 4–6, #164): жжёт топливо и бьёт лучом своего цвета.
##
## Уголь — красный, медная руда — зелёный, кристалл — синий. Топка до 12 единиц.
## E с топливом в руке загружает всю стопку; пустой рукой — рубильник, чтобы не
## жечь днём зря (текущая единица не сгорает). Рядом с сундуком сама берёт
## топливо, если в топке меньше двух единиц.

const FUEL_MAX: int = 12
## Как часто смотреть соседние сундуки, с.
const PULL_PERIOD: float = 1.0
## Соседи по стороне — откуда брать топливо.
const NEIGHBORS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]

## Топка: [[item, count], ...] в порядке загрузки. Горит первая единица.
var fuel: Array = []
## Сколько ещё горит текущая единица, с. Выключенный рубильник её не тратит.
var burn_left: float = 0.0
## Цвет текущего пламени (маска Beams). 0 — не горит.
var color: int = 0
## Рубильник. Выключенная горелка топливо не жжёт и луча не даёт.
var enabled: bool = true

var _pull_t: float = 0.0
var _lit: bool = false
var _interact_frame: int = -10


func _init() -> void:
	kind = "Burner"
	z_index = 3
	can_turn = true


func _process(delta: float) -> void:
	super(delta)
	if not Net.is_authority():   # СЕТЬ (ADR-002): топливо считает хост, клиент рисует по net_state
		queue_redraw()
		return
	var was: bool = burning()
	if enabled:
		if burn_left <= 0.0:
			_ignite()
		if burn_left > 0.0:
			burn_left = maxf(0.0, burn_left - delta)
			if burn_left <= 0.0:
				_ignite()
	_pull_t -= delta
	if _pull_t <= 0.0:
		_pull_t = PULL_PERIOD
		_pull_from_chests()
	if burning() != was:
		_mark_beam()
	_lit = burning()
	queue_redraw()


## Горит ли сейчас: рубильник включён и в топке есть пламя.
func burning() -> bool:
	return enabled and burn_left > 0.0 and color != 0


## Луч из носика. Пусто — горелка молчит (нет топлива или выключена).
func beam_emit() -> Array:
	if not burning():
		return []
	var length: int = Balance.BEAM_LEN_WHITE if color == Beams.W else Balance.BEAM_LEN
	return [[dir, color, length]]


## Горелка луч не пропускает: носик — источник, не труба.
func beam_pass(_in_dir: int, _color: int) -> Array:
	return []


## Сколько единиц топлива лежит в топке, не считая той, что уже горит.
func fuel_units() -> int:
	var n: int = 0
	for e in fuel:
		n += int(e[1])
	return n


func has_room() -> bool:
	return fuel_units() < FUEL_MAX


## Принимает только топливо горелки (ключи Balance.FUEL).
func input_accepts(item_id: int) -> bool:
	return Balance.FUEL.has(item_id)


## С конвейера или манипулятора. Возвращает, сколько НЕ принято.
func receive_item(item_id: int, count: int) -> int:
	if not input_accepts(item_id) or count <= 0:
		return count
	var left: int = count - add_fuel(item_id, count)
	return left


## Положить топливо в топку. Возвращает, сколько единиц принято.
func add_fuel(item_id: int, count: int) -> int:
	if not input_accepts(item_id) or count <= 0:
		return 0
	var room: int = FUEL_MAX - fuel_units()
	var take: int = mini(room, count)
	if take <= 0:
		return 0
	var merged: bool = false
	for e in fuel:
		if int(e[0]) == item_id:
			e[1] = int(e[1]) + take
			merged = true
			break
	if not merged:
		fuel.append([item_id, take])
	if burn_left <= 0.0 and enabled:
		_ignite()
	queue_redraw()
	return take


## Взять единицу из топки и зажечь её. Текущее пламя не трогает.
func _ignite() -> void:
	if burn_left > 0.0 or fuel.is_empty():
		if fuel.is_empty() and burn_left <= 0.0 and color != 0:
			color = 0
		return
	var e: Array = fuel[0]
	e[1] = int(e[1]) - 1
	var item: int = int(e[0])
	if int(e[1]) <= 0:
		fuel.pop_front()
	burn_left = float(Balance.FUEL[item])
	color = _color_of(item)


func _color_of(item: int) -> int:
	if item == IDs.I.COAL:
		return Beams.R
	if item == IDs.I.COPPER_ORE:
		return Beams.G
	if item == IDs.I.CRYSTAL:
		return Beams.B
	return 0


## Раз в секунду: если в топке меньше двух единиц — взять одну из соседнего сундука.
func _pull_from_chests() -> void:
	if fuel_units() >= 2:
		return
	for d in NEIGHBORS:
		var n = World.machines.get(cell + d)
		if not (n is Chest):
			continue
		var id: int = n.take_any(IDs.I.NONE, input_accepts)
		if id == IDs.I.NONE:
			continue
		add_fuel(id, 1)
		return


func _mark_beam() -> void:
	if World.beams != null:
		World.beams.mark_dirty()


## E: топливо в руке — загрузить всю стопку, пустая рука — рубильник.
## Вызов идёт каждый кадр, пока E зажата; срабатывает один раз на нажатие.
func interact(p) -> void:
	var f: int = Engine.get_physics_frames()
	var fresh: bool = f - _interact_frame > 1
	_interact_frame = f
	if fresh:
		_on_interact(p)


func _on_interact(p) -> void:
	var st: ItemStack = p.inv.selected_stack()
	if not st.is_empty() and input_accepts(st.id):
		var added: int = add_fuel(st.id, st.count)
		if added > 0:
			p.inv.remove_at(p.inv.selected, added)
			Sfx.play("craft", -12.0)
			Game.notify("Топливо загружено в горелку.", Beams.COLOR[color] if color != 0 else Color(1.0, 0.8, 0.4))
		else:
			Game.notify("Топка горелки полна.", Color(1.0, 0.7, 0.4))
		return
	if not st.is_empty():
		return
	set_enabled(not enabled)


## Рубильник. Выключение не сжигает текущую единицу — burn_left стоит на паузе.
func set_enabled(on: bool) -> void:
	if on == enabled:
		return
	enabled = on
	_mark_beam()
	queue_redraw()
	Sfx.play("power", -10.0, 1.0 if on else 0.7)
	Game.notify("Горелка: %s" % ("ВКЛ" if on else "ВЫКЛ"),
			Color(0.6, 1.0, 0.6) if on else Color(1.0, 0.7, 0.4))


func _draw() -> void:
	var hot: bool = burning()
	var t: float = Time.get_ticks_msec() * 0.001
	_draw_body(BODY, true)
	# Окно топки: точный цвет луча (он в Emission.glow_colors — ночью не тускнеет).
	var flame: Color = C_SOOT
	if hot and color > 0 and color < Beams.COLOR.size():
		flame = Beams.COLOR[color]
	draw_rect(Rect2(-5.0, -3.0, 8.0, 7.0), C_FRAME)
	draw_rect(Rect2(-4.0, -2.0, 6.0, 5.0), flame)
	if hot:
		draw_rect(Rect2(-3.0, 0.0, 4.0, 2.0), flame.lightened(0.3))
	# Носик по направлению: из него бьёт луч.
	_draw_nozzle()
	# Шкала топлива справа, как у ТЭЦ: доля текущей единицы снизу вверх
	# и короткие деления запаса над ней.
	var gauge: Color = flame if hot else C_LAVA_HI
	if burn_left > 0.0 and color != 0:
		var burn: float = float(Balance.FUEL.get(_burning_item(), Balance.COAL_BURN))
		var f: float = roundf(5.0 * clampf(burn_left / burn, 0.0, 1.0))
		draw_rect(Rect2(5.0, -1.0, 2.0, 5.0), C_SOOT)
		draw_rect(Rect2(5.0, 4.0 - f, 2.0, f), gauge)
	var stock: int = mini(4, fuel_units())
	for i in stock:
		draw_rect(Rect2(5.0, -4.0 - float(i) * 2.0, 2.0, 1.0), gauge)
	# Лампа рубильника: красная — выключена, цвет пламени — горит, тёмная — ждёт топлива.
	var lamp: Color = C_SCREEN
	if not enabled:
		lamp = C_LAMP_OFF
	elif hot:
		lamp = flame
	_draw_lamp(Vector2(-5.0, -5.0), lamp)


func _draw_nozzle() -> void:
	var tip: Rect2 = Rect2(6.0, -2.0, 3.0, 4.0)
	match dir:
		1:
			tip = Rect2(-2.0, 6.0, 4.0, 3.0)
		2:
			tip = Rect2(-9.0, -2.0, 3.0, 4.0)
		3:
			tip = Rect2(-2.0, -9.0, 4.0, 3.0)
	draw_rect(tip, C_METAL_D)
	draw_rect(tip.grow(-1.0), C_FRAME)


## Предмет, который сейчас горит (для шкалы). 0 — не знаем, берём уголь.
func _burning_item() -> int:
	if color == Beams.G:
		return IDs.I.COPPER_ORE
	if color == Beams.B:
		return IDs.I.CRYSTAL
	return IDs.I.COAL


func dismantle() -> int:
	_spill_fuel()
	return super()


func _on_destroyed() -> void:
	_spill_fuel()


func _spill_fuel() -> void:
	for e in fuel:
		if int(e[1]) > 0:
			spawn_item(int(e[0]), int(e[1]), global_position + Vector2(0.0, -4.0))
	fuel.clear()


# ------------------------------------------------------------- СОХРАНЕНИЕ (#37)
func save_state() -> Dictionary:
	var d: Dictionary = super()
	d["fuel"] = fuel.duplicate(true)
	d["burn_left"] = burn_left
	d["color"] = color
	d["enabled"] = enabled
	return d


func load_state(d: Dictionary) -> void:
	super(d)
	fuel.clear()
	var src = d.get("fuel", [])
	if src is Array:
		for e in src:
			if e is Array and e.size() >= 2 and int(e[1]) > 0 and input_accepts(int(e[0])):
				fuel.append([int(e[0]), int(e[1])])
	burn_left = float(d.get("burn_left", burn_left))
	color = int(d.get("color", color)) & 7
	enabled = bool(d.get("enabled", enabled))
	_lit = burning()
	_mark_beam()
	queue_redraw()


# ------------------------------------------------------------- СЕТЬ (ADR-002)
## Байт пламени: цвет — 3 бита, горит — бит 3. Байт запаса — единицы в топке.
## burn_left клиенту для луча не нужен: луч детерминирован по «горит/цвет».
func net_state() -> PackedByteArray:
	var b: PackedByteArray = super()
	var flame: int = color & 7
	if burning():
		flame |= 8
	if not enabled:
		flame |= 16
	b.append(flame)
	b.append(mini(255, fuel_units()))
	return b


func apply_net_state(b: PackedByteArray) -> int:
	var o: int = super(b)
	if o < 0 or b.size() < o + 2:
		return -1
	var was: bool = burning()
	var prev: int = color
	color = int(b[o]) & 7
	var lit: bool = (int(b[o]) & 8) != 0
	enabled = (int(b[o]) & 16) == 0
	# Запас клиент не жжёт: одна фиктивная единица, чтобы шкала и «горит» совпали.
	var stock: int = int(b[o + 1])
	fuel.clear()
	if stock > 0:
		fuel.append([_burning_item(), stock])
	burn_left = 1.0 if lit else 0.0
	if burning() != was or color != prev:
		_mark_beam()
	queue_redraw()
	return o + 2
