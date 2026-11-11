class_name Inserter
extends MachineBase
## Манипулятор (ADR-001 § 4.2, #30): раз в Balance.INSERTER_PERIOD переносит
## один предмет из клетки сзади в клетку спереди.
##
## Источник сзади: сундук (take_any), конвейер (take_front), станок или бур
## (take_output — готовое, которое машина придержала для манипулятора).
## Приёмник спереди: всё, что принимает receive_item (конвейер, сундук,
## станок, ТЭЦ, анализатор). dir — как у конвейера: 0 — вправо, 1 — вниз,
## 2 — влево, 3 — вверх; ПКМ поворачивает. Фильтр (E с предметом в руке) —
## переносить только этот предмет; E с пустой рукой — сбросить фильтр.
##
## Предмет, который приёмник не возьмёт, манипулятор не берёт вовсе: иначе
## он навсегда застрял бы в захвате.

const PERIOD: float = Balance.INSERTER_PERIOD
## Как часто пустой манипулятор заново смотрит, есть ли что взять, с.
## Без паузы 100 простаивающих манипуляторов опрашивали бы соседей каждый кадр.
const IDLE_RETRY: float = 0.1

## Переносить только этот предмет (IDs.I.NONE — любой).
var filter: int = IDs.I.NONE
## Предмет в захвате (IDs.I.NONE — пусто).
var held: int = IDs.I.NONE
## Сколько предметов перенесено (для замеров и сценариев).
var moved: int = 0

var _swing: float = 0.0      ## наработка текущего переноса, с
var _idle_t: float = 0.0
var _accepts_cb: Callable
var _interact_frame: int = -10


func _init() -> void:
	kind = "Inserter"
	z_index = 3
	can_turn = true
	_accepts_cb = _front_accepts


## Клетка, откуда манипулятор берёт (сзади).
func source_cell() -> Vector2i:
	return cell - _dir_cell()


## Клетка, куда манипулятор кладёт (спереди).
func target_cell() -> Vector2i:
	return cell + _dir_cell()


func set_filter(item_id: int) -> void:
	if filter == item_id:
		return
	filter = item_id
	queue_redraw()


## E по манипулятору: предмет в руке — фильтр, пустая рука — сброс.
## Срабатывает один раз на нажатие (E держат, вызов идёт каждый кадр).
func interact(p) -> void:
	var f: int = Engine.get_physics_frames()
	var fresh: bool = f - _interact_frame > 1
	_interact_frame = f
	if not fresh:
		return
	var sel: ItemStack = p.inv.selected_stack()
	if sel.is_empty():
		set_filter(IDs.I.NONE)
		Game.notify("Манипулятор: фильтр снят", Color(0.8, 0.85, 0.9))
	else:
		set_filter(sel.id)
		Game.notify("Манипулятор: только %s" % DB.item_name(sel.id), Color(0.7, 0.9, 1.0))
	Sfx.play("place", -14.0, 1.2)


func _process(delta: float) -> void:
	super(delta)
	if not Net.is_authority():   # СЕТЬ (ADR-002): работает хост, клиент рисует по net_state
		return
	if not powered:
		return
	if held == IDs.I.NONE:
		_idle_t -= delta
		if _idle_t > 0.0:
			return
		held = _grab()
		if held == IDs.I.NONE:
			_idle_t = IDLE_RETRY
			return
		_swing = 0.0
		queue_redraw()
	if _swing < PERIOD:
		_swing += work(delta)
		progress = clampf(_swing / PERIOD, 0.0, 1.0)
		if _swing < PERIOD:
			return
	# Перенос закончен — кладём; не берут — ждём с предметом в захвате.
	if _put(held):
		held = IDs.I.NONE
		moved += 1
		_swing = 0.0
		progress = 0.0
		queue_redraw()


func _grab() -> int:
	var src: Vector2i = source_cell()
	var b: Belt = World.belts.get(src)
	if b != null:
		return b.take_front(filter, _accepts_cb)
	var m = World.machines.get(src)
	if m == null or m is Inserter:
		return IDs.I.NONE
	if m is Chest:
		return m.take_any(filter, _accepts_cb)
	return m.take_output(filter, _accepts_cb)


func _put(item_id: int) -> bool:
	var dst: Vector2i = target_cell()
	var b: Belt = World.belts.get(dst)
	if b != null:
		return b.add_item(item_id, 1)
	var m = World.machines.get(dst)
	if m == null or m is Inserter:
		return false
	return m.receive_item(item_id, 1) == 0


## Возьмёт ли приёмник спереди этот предмет. Конвейер и сундук берут всё;
## станки и ТЭЦ — только то, что есть у них во входе.
func _front_accepts(item_id: int) -> bool:
	var dst: Vector2i = target_cell()
	if World.belts.has(dst):
		return true
	var m = World.machines.get(dst)
	if m == null or m is Inserter:
		return false
	if m is Chest:
		return true
	return m.input_accepts(item_id)


func _dir_cell() -> Vector2i:
	match dir:
		0: return Vector2i(1, 0)
		1: return Vector2i(0, 1)
		2: return Vector2i(-1, 0)
		_: return Vector2i(0, -1)


func _draw() -> void:
	var d: Vector2 = Vector2(_dir_cell())
	var side: Vector2 = Vector2(-d.y, d.x)
	# Основание: кремовая плита с полосой «откуда» (рама) и «куда» (жёлтая).
	_draw_body(Rect2(-6.0, -6.0, 12.0, 12.0), powered, false)
	var p0: Vector2 = -d * 4.0 - side * 5.0
	var p1: Vector2 = -d * 6.0 + side * 5.0
	draw_rect(Rect2(p0.min(p1), (p1 - p0).abs()), C_FRAME)
	p0 = d * 4.0 - side * 5.0
	p1 = d * 6.0 + side * 5.0
	draw_rect(Rect2(p0.min(p1), (p1 - p0).abs()), C_HAZARD)
	# Рука: поворачивается от источника (сзади) через верх к приёмнику (спереди).
	var a0: float = (-d).angle()
	var swing: float = progress if held != IDs.I.NONE else 0.0
	var turn_sign: float = 1.0 if side.y > 0.0 else -1.0   ## переносим «над» основанием
	var ang: float = a0 + turn_sign * PI * swing
	var hand: Vector2 = Vector2(cos(ang), sin(ang)) * 7.0
	# Рука — механизм, она поворачивается; шарнир и захват — квадраты по сетке.
	var arm: Color = C_FRAME if powered else C_FRAME.darkened(0.2)
	draw_line(Vector2.ZERO, hand, arm, 2.0)
	draw_rect(Rect2(-2.0, -2.0, 4.0, 4.0), C_METAL_D)
	draw_rect(Rect2(-1.0, -1.0, 2.0, 2.0), C_FRAME)
	# Захват: квадрат 3×3 на конце руки (жёлтый — видно, где он).
	var hp: Vector2 = hand.round()
	draw_rect(Rect2(hp - Vector2(1.0, 1.0), Vector2(3.0, 3.0)), C_HAZARD)
	if held != IDs.I.NONE:
		var tex: ImageTexture = DB.item_texture(held)
		if tex:
			draw_texture_rect(tex, Rect2(hp - Vector2(4, 4), Vector2(8, 8)), false)
	# Фильтр — квадратик цвета предмета в углу.
	if filter != IDs.I.NONE:
		draw_rect(Rect2(-8.0, -8.0, 4.0, 4.0), DB.item_color(filter))
		draw_rect(Rect2(-8.0, -8.0, 4.0, 4.0), C_FRAME, false, 1.0)
	_draw_lamp(Vector2(6.0, -6.0), C_SCREEN_HI if powered else C_LAMP_OFF)


# ------------------------------------------------------------- СОХРАНЕНИЕ (#37)
## Направление, фильтр, предмет в захвате и ход переноса.
func save_state() -> Dictionary:
	var d: Dictionary = super()
	d["dir"] = dir
	d["filter"] = filter
	d["held"] = held
	d["moved"] = moved
	d["swing"] = _swing
	d["idle"] = _idle_t
	return d


func load_state(d: Dictionary) -> void:
	super(d)
	dir = int(d.get("dir", dir)) % 4
	filter = int(d.get("filter", filter))
	held = int(d.get("held", held))
	moved = int(d.get("moved", moved))
	_swing = float(d.get("swing", _swing))
	_idle_t = float(d.get("idle", _idle_t))


# ------------------------------------------------------------- СЕТЬ (ADR-002, MP-E #90)
## + dir u8 · предмет в захвате u8 · фильтр u8 (ход руки — progress базы).
func net_state() -> PackedByteArray:
	var b: PackedByteArray = super()
	b.append(dir & 3)
	b.append(held & 0xFF)
	b.append(filter & 0xFF)
	return b


func apply_net_state(b: PackedByteArray) -> int:
	var o: int = super(b)
	if o < 0 or b.size() < o + 3:
		return -1
	dir = b[o] & 3
	held = b[o + 1]
	filter = b[o + 2]
	queue_redraw()
	return o + 3
