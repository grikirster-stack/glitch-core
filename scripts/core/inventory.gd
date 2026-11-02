class_name Inventory
extends RefCounted
## Модель инвентаря: 10 слотов хотбара + 26 основных.

signal changed

var slots: Array[ItemStack] = []
var size: int = 36
var hotbar_size: int = 10
var selected: int = 0

func _init(p_size: int = 36, p_hotbar: int = 10) -> void:
	size = p_size
	hotbar_size = p_hotbar
	slots.resize(size)
	for i in size:
		slots[i] = ItemStack.new()

func slot_max(id: int) -> int:
	return DB.item_max_stack(id)

func can_add(id: int, amount: int = 1) -> bool:
	if id == IDs.I.NONE or amount <= 0:
		return false
	var space: int = 0
	for s in slots:
		if s.is_empty():
			space += slot_max(id)
		elif s.id == id:
			space += slot_max(id) - s.count
		if space >= amount:
			return true
	return false

## Возвращает количество, которое НЕ удалось положить.
func add(id: int, amount: int = 1) -> int:
	if id == IDs.I.NONE or amount <= 0:
		return amount
	var left: int = stack_into(slots, id, amount)
	if left != amount:
		changed.emit()
	return left


## Разложить amount предметов id по массиву стопок: сначала докладываем
## в неполные стопки, потом — в пустые слоты; только слоты [from, to)
## (to < 0 — до конца). Годится и для инвентаря, и для сундука (Chest.slots):
## так панель перекладывает Shift+кликом и «Забрать всё» (#69).
## Возвращает количество, которое НЕ поместилось.
static func stack_into(arr: Array[ItemStack], id: int, amount: int, from: int = 0, to: int = -1) -> int:
	if id == IDs.I.NONE or amount <= 0:
		return amount
	var end: int = arr.size() if to < 0 else mini(to, arr.size())
	var maxst: int = DB.item_max_stack(id)
	var left: int = amount
	for i in range(from, end):
		if left <= 0:
			break
		var s: ItemStack = arr[i]
		if s.id == id and s.count < maxst:
			var take: int = mini(maxst - s.count, left)
			s.count += take
			left -= take
	for i in range(from, end):
		if left <= 0:
			break
		if arr[i].is_empty():
			var take2: int = mini(maxst, left)
			arr[i] = ItemStack.new(id, take2)
			left -= take2
	return left

func count_of(id: int) -> int:
	var total: int = 0
	for s in slots:
		if s.id == id:
			total += s.count
	return total

func remove_id(id: int, amount: int = 1) -> bool:
	if count_of(id) < amount:
		return false
	var left: int = amount
	for i in size:
		if left <= 0:
			break
		var s: ItemStack = slots[i]
		if s.id == id:
			var taken: int = s.take(left)
			left -= taken
	changed.emit()
	return true

func remove_at(index: int, amount: int = 1) -> int:
	if index < 0 or index >= size:
		return 0
	var s: ItemStack = slots[index]
	if s.is_empty():
		return 0
	return s.take(amount)

func swap(a: int, b: int) -> void:
	if a == b:
		return
	if a < 0 or b < 0 or a >= size or b >= size:
		return
	var tmp: ItemStack = slots[a]
	slots[a] = slots[b]
	slots[b] = tmp
	changed.emit()

## Раскладывает часть стопки a в свободный слот (или в существующую того же типа).
func split_into(a: int, b: int) -> void:
	if a < 0 or b < 0 or a >= size or b >= size or a == b:
		return
	var sa: ItemStack = slots[a]
	var sb: ItemStack = slots[b]
	if sa.is_empty():
		return
	if sb.is_empty():
		var maxst: int = slot_max(sa.id)
		var move: int = int(ceil(float(sa.count) * 0.5))
		move = mini(move, maxst)
		slots[b] = ItemStack.new(sa.id, move)
		sa.take(move)
	elif sb.id == sa.id:
		var maxst2: int = slot_max(sb.id)
		var room: int = maxst2 - sb.count
		var move2: int = mini(room, sa.count)
		sb.count += move2
		sa.take(move2)
	changed.emit()

func get_slot(index: int) -> ItemStack:
	if index < 0 or index >= size:
		return ItemStack.new()
	return slots[index]

func selected_stack() -> ItemStack:
	return get_slot(selected)

func is_full() -> bool:
	for s in slots:
		if s.is_empty():
			return false
	return true

func first_empty() -> int:
	for i in size:
		if slots[i].is_empty():
			return i
	return -1
