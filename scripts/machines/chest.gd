class_name Chest
extends MachineBase
## Сундук для хранения. Вмещает 24 слота, конвейеры кладут и забирают предметы.

const CAP: int = 24

var slots: Array[ItemStack] = []


func _init() -> void:
	kind = "Chest"
	z_index = 3
	slots.resize(CAP)
	for i in CAP:
		slots[i] = ItemStack.new()


func receive_item(item_id: int, count: int) -> int:
	for s in slots:
		if s.is_empty():
			s.id = item_id
			s.count = count
			queue_redraw()
			return 0
		if s.id == item_id and s.count < DB.item_max_stack(item_id):
			var room: int = DB.item_max_stack(item_id) - s.count
			var take: int = mini(room, count)
			s.count += take
			queue_redraw()
			return count - take
	return count


func take_at(index: int, amount: int) -> int:
	if index < 0 or index >= CAP:
		return 0
	return slots[index].take(amount)


## Выдать один предмет манипулятору (#30). filter — только этот id (NONE — любой);
## accepts — дополнительная проверка «возьмёт ли приёмник» (пустой Callable — да).
## Возвращает id выданного предмета или IDs.I.NONE.
func take_any(filter: int = IDs.I.NONE, accepts: Callable = Callable()) -> int:
	for s in slots:
		if s.is_empty():
			continue
		if filter != IDs.I.NONE and s.id != filter:
			continue
		if accepts.is_valid() and not bool(accepts.call(s.id)):
			continue
		var id: int = s.id
		s.take(1)
		queue_redraw()
		return id
	return IDs.I.NONE


func _draw() -> void:
	# Кремовый ящик-контейнер: крышка отделена рамой, жёлтый замок по центру,
	# рёбра жёсткости по бокам.
	_draw_body(BODY, true, false)
	draw_rect(Rect2(-7.0, -3.0, 14.0, 2.0), C_FRAME)
	draw_rect(Rect2(-5.0, 0.0, 1.0, 6.0), C_METAL_D)
	draw_rect(Rect2(4.0, 0.0, 1.0, 6.0), C_METAL_D)
	draw_rect(Rect2(-2.0, -3.0, 4.0, 4.0), C_HAZARD)
	draw_rect(Rect2(-1.0, -2.0, 2.0, 1.0), C_FRAME)


# ------------------------------------------------------------- СОХРАНЕНИЕ (#37)
## Слоты по порядку: [[id, число], ...] — и сундуки игрока, и тайники руин.
func save_state() -> Dictionary:
	var d: Dictionary = super()
	var out: Array = []
	for s in slots:
		out.append([s.id, s.count])
	d["slots"] = out
	return d


func load_state(d: Dictionary) -> void:
	super(d)
	var src = d.get("slots", [])
	if not (src is Array):
		return
	for i in CAP:
		var e = src[i] if i < src.size() else null
		if e is Array and e.size() >= 2 and int(e[1]) > 0:
			slots[i] = ItemStack.new(int(e[0]), int(e[1]))
		else:
			slots[i] = ItemStack.new()
	queue_redraw()
