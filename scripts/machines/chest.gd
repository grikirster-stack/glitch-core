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
	draw_rect(Rect2(-8.0, -8.0, 16.0, 16.0), Color(0.45, 0.30, 0.17))
	draw_rect(Rect2(-8.0, -8.0, 16.0, 3.0), Color(0.55, 0.38, 0.22))
	draw_rect(Rect2(-8.0, -1.0, 16.0, 2.0), Color(0.28, 0.18, 0.10))
	draw_rect(Rect2(-1.5, -1.0, 3.0, 3.0), Color(0.85, 0.72, 0.30))
