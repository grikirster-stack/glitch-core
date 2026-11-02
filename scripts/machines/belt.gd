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
	var c: Color = Color(0.22, 0.22, 0.25)
	draw_line(side * 8.0 - d * 8.0, side * 8.0 + d * 8.0, c, 5.0)
	draw_line(-side * 8.0 - d * 8.0, -side * 8.0 + d * 8.0, c, 5.0)
	# Стрелки движения
	var t: float = fmod(anim * 3.0 + float(cell.x + cell.y) * 0.25, 1.0)
	var p: Vector2 = -d * 6.0 + d * t * 12.0
	draw_line(p - d * 3.0, p, Color(0.85, 0.72, 0.3), 2.0)
	draw_line(p, p - d * 2.0 + side * 2.0, Color(0.85, 0.72, 0.3), 2.0)
	draw_line(p, p - d * 2.0 - side * 2.0, Color(0.85, 0.72, 0.3), 2.0)
	# Предметы
	for it in items:
		var tex: ImageTexture = DB.item_texture(int(it["id"]))
		if tex:
			var pos: Vector2 = -d * 6.0 + d * float(it["pos"]) * 12.0
			draw_texture_rect(tex, Rect2(pos - Vector2(6, 6), Vector2(12, 12)), false)
