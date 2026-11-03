class_name Belt
extends MachineBase
## Конвейер: переносит предметы в направлении dir (0 — вправо, 1 — вниз, 2 — влево, 3 — вверх).

const SPEED: float = 1.5   ## тайлов в секунду
const GAP: float = 0.34

var dir: int = 0
var items: Array = []      ## [{id:int, count:int, pos:float}]


func _init() -> void:
	kind = "Belt"
	z_index = 2


func dir_vector() -> Vector2:
	match dir:
		0: return Vector2.RIGHT
		1: return Vector2.DOWN
		2: return Vector2.LEFT
		_: return Vector2.UP


func turn() -> void:
	dir = (dir + 1) % 4
	queue_redraw()


## Ставит предмет на ленту, если есть место. Возвращает true при успехе.
func add_item(item_id: int, count: int) -> bool:
	if items.is_empty():
		items.append({"id": item_id, "count": count, "pos": 0.0})
		return true
	var last: Dictionary = items[items.size() - 1]
	if last["pos"] > GAP:
		items.append({"id": item_id, "count": count, "pos": 0.0})
		return true
	# Слишком плотно — попробуем объединить с последним.
	if int(last["id"]) == item_id:
		last["count"] = int(last["count"]) + count
		return true
	return false


## Приём «как у станка» (для манипулятора, #30): 0 — принято всё.
func receive_item(item_id: int, count: int) -> int:
	return 0 if add_item(item_id, count) else count


## Снять с ленты один предмет для манипулятора (#30): ближайший к концу ленты,
## подходящий под filter (NONE — любой) и accepts (пустой Callable — любой).
## Возвращает id снятого предмета или IDs.I.NONE.
func take_front(filter: int = IDs.I.NONE, accepts: Callable = Callable()) -> int:
	for i in items.size():
		var it: Dictionary = items[i]
		var id: int = int(it["id"])
		if filter != IDs.I.NONE and id != filter:
			continue
		if accepts.is_valid() and not bool(accepts.call(id)):
			continue
		var left: int = int(it["count"]) - 1
		if left <= 0:
			items.remove_at(i)
		else:
			it["count"] = left
		queue_redraw()
		return id
	return IDs.I.NONE


func _process(delta: float) -> void:
	super(delta)
	if not Net.is_authority():   # СЕТЬ (ADR-002): у клиента предметы едут без передачи соседу
		_net_glide(delta)
		return
	if items.is_empty():
		return
	# Двигаем: передний (с большим pos) идёт первым и не обгоняет следующий.
	var ordered: Array = items.duplicate()
	ordered.sort_custom(func(a, b): return float(a["pos"]) > float(b["pos"]))
	var limit: float = 2.0
	for it in ordered:
		var p: float = float(it["pos"])
		if p < limit:
			p = minf(p + SPEED * delta, limit)
		it["pos"] = p
		limit = p - GAP
	# Передача на следующий участок
	while items.size() > 0:
		var front: Dictionary = items[0]
		if float(front["pos"]) < 1.0:
			break
		var next_cell: Vector2i = cell + _dir_cell()
		var moved: bool = false
		if World.belts.has(next_cell):
			var nb: Belt = World.belts[next_cell]
			if nb.add_item(int(front["id"]), int(front["count"])):
				moved = true
		elif World.machines.has(next_cell):
			var m: MachineBase = World.machines[next_cell]
			if m.receive_item(int(front["id"]), int(front["count"])) == 0:
				moved = true
		if moved:
			items.pop_front()
		else:
			break
	queue_redraw()


func _dir_cell() -> Vector2i:
	match dir:
		0: return Vector2i(1, 0)
		1: return Vector2i(0, 1)
		2: return Vector2i(-1, 0)
		_: return Vector2i(0, -1)


func _draw() -> void:
	var d: Vector2 = dir_vector()
	var side: Vector2 = Vector2(-d.y, d.x)
	# Борта — голубовато-серые рамы с кремовой кромкой, полотно между ними
	# тёмное; всё по сетке (d и side — единичные по осям).
	_belt_rect(-5.0, 5.0, -8.0, 8.0, d, side, Color(C_SOOT, 0.55))
	_belt_rect(5.0, 8.0, -8.0, 8.0, d, side, C_FRAME)
	_belt_rect(-8.0, -5.0, -8.0, 8.0, d, side, C_FRAME)
	_belt_rect(5.0, 6.0, -8.0, 8.0, d, side, C_METAL_D)
	_belt_rect(-6.0, -5.0, -8.0, 8.0, d, side, C_METAL_D)
	# Стрелка движения — жёлтый уголок из квадратов.
	var t: float = fmod(anim * 3.0 + float(cell.x + cell.y) * 0.25, 1.0)
	var a: float = roundf(-6.0 + t * 12.0)
	_belt_rect(-1.0, 1.0, a - 1.0, a + 1.0, d, side, C_HAZARD)
	_belt_rect(-3.0, -1.0, a - 3.0, a - 1.0, d, side, C_HAZARD)
	_belt_rect(1.0, 3.0, a - 3.0, a - 1.0, d, side, C_HAZARD)
	# Предметы
	for it in items:
		var tex: ImageTexture = DB.item_texture(int(it["id"]))
		if tex:
			var pos: Vector2 = -d * 6.0 + d * float(it["pos"]) * 12.0
			draw_texture_rect(tex, Rect2(pos - Vector2(6, 6), Vector2(12, 12)), false)


## Прямоугольник в координатах ленты: s — поперёк (side), a — вдоль (d).
func _belt_rect(s0: float, s1: float, a0: float, a1: float, d: Vector2, side: Vector2, col: Color) -> void:
	var p0: Vector2 = side * s0 + d * a0
	var p1: Vector2 = side * s1 + d * a1
	draw_rect(Rect2(Vector2(minf(p0.x, p1.x), minf(p0.y, p1.y)), (p1 - p0).abs()), col)


## Конвейер сняли или снесли — груз с него на землю, ничего не пропадает.
func _on_destroyed() -> void:
	for it in items:
		spawn_item(int(it["id"]), int(it["count"]), global_position + Vector2(0.0, -4.0))
	items.clear()


# ------------------------------------------------------------- СОХРАНЕНИЕ (#37)
## Направление и предметы на ленте с их положением.
func save_state() -> Dictionary:
	var d: Dictionary = super()
	d["dir"] = dir
	d["items"] = items.duplicate(true)
	return d


func load_state(d: Dictionary) -> void:
	super(d)
	dir = int(d.get("dir", dir)) % 4
	items = []
	var src = d.get("items", [])
	if src is Array:
		for it in src:
			if it is Dictionary:
				items.append({"id": int(it.get("id", IDs.I.NONE)), "count": int(it.get("count", 1)),
						"pos": float(it.get("pos", 0.0))})


# ------------------------------------------------------------- СЕТЬ (ADR-002, MP-E #90)
## net_state ленты — своя раскладка (без станочной базы): hp u8 · dir u8 · n u8 +
## n × (id u8, count u8, pos u8 — pos·255, конец ленты — 255). 3 + 3·n Б.
## Между пакетами (4 Гц) клиент сам двигает предметы: pos += SPEED·dt, передний — не
## дальше конца ленты, следующие — не ближе GAP; соседу не передаёт — это делает хост.

const NET_MAX_ITEMS: int = 84    ## 3 + 3·84 = 255 — предел длины net_state


func net_state() -> PackedByteArray:
	var n: int = mini(items.size(), NET_MAX_ITEMS)
	var b: PackedByteArray = PackedByteArray()
	b.resize(3 + 3 * n)
	b[0] = net_u8(hp / maxf(max_hp, 0.001))
	b[1] = dir & 3
	b[2] = n
	for i in n:
		var it: Dictionary = items[i]
		b[3 + 3 * i] = int(it["id"]) & 0xFF
		b[4 + 3 * i] = clampi(int(it["count"]), 1, 255)
		b[5 + 3 * i] = net_u8(float(it["pos"]))
	return b


func apply_net_state(b: PackedByteArray) -> int:
	if b.size() < 3 or b.size() < 3 + 3 * int(b[2]):
		return -1
	hp = float(b[0]) / 255.0 * max_hp
	if dir != int(b[1]) & 3:
		dir = int(b[1]) & 3
	var n: int = b[2]
	items = []
	for i in n:
		items.append({"id": int(b[3 + 3 * i]), "count": int(b[4 + 3 * i]),
				"pos": float(b[5 + 3 * i]) / 255.0})
	queue_redraw()
	return 3 + 3 * n


## Клиент: экстраполяция между пакетами хоста (items[0] — передний, как у хоста).
func _net_glide(delta: float) -> void:
	if items.is_empty():
		return
	var limit: float = 1.0
	for it in items:
		var p: float = float(it["pos"])
		if p < limit:
			p = minf(p + SPEED * delta, limit)
		it["pos"] = p
		limit = p - GAP
	queue_redraw()