class_name Inventory
extends RefCounted
## Модель инвентаря: hotbar_size слотов хотбара + остальные — рюкзак (всего 36).
## Размер хотбара — 6 или 10 (#161); число 10 вшито только как потолок пакета и ключа HUD.

signal changed

var slots: Array[ItemStack] = []
var size: int = 36
var hotbar_size: int = 10
var selected: int = 0

## Допустимые размеры хотбара (#161): телефон — 6, ПК — 10. Больше 10 пакет ввода не несёт.
const HOTBAR_MIN: int = 6
const HOTBAR_MAX: int = 10

func _init(p_size: int = 36, p_hotbar: int = 10) -> void:
	size = p_size
	hotbar_size = clamp_hotbar(p_hotbar)
	slots.resize(size)
	for i in size:
		slots[i] = ItemStack.new()


## Размер стопки без глобального имени DB: anim_test.gd стартует как --script,
## и на этапе компиляции автозагрузки ещё нет. В игре узел уже есть.
static func _item_max_stack(id: int) -> int:
	var loop: MainLoop = Engine.get_main_loop()
	if loop is SceneTree:
		var db: Node = (loop as SceneTree).root.get_node_or_null("DB")
		if db != null:
			return int(db.call("item_max_stack", id))
	return 99


## 6 или 10; иное — ближайшее из двух (битое поле профиля не оставляет хотбар без ячеек).
static func clamp_hotbar(n: int) -> int:
	return HOTBAR_MIN if n < (HOTBAR_MIN + HOTBAR_MAX) / 2 else HOTBAR_MAX


## Умолчание (#161): сенсорный экран или флаг --touch — 6, иначе 10.
static func default_hotbar(touchscreen: bool, args: PackedStringArray) -> int:
	if touchscreen or args.has("--touch"):
		return HOTBAR_MIN
	return HOTBAR_MAX

func slot_max(id: int) -> int:
	return _item_max_stack(id)

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
	var maxst: int = _item_max_stack(id)
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


## Сменить размер хотбара (#161). Слоты не двигаются: верхний ряд панели рисует
## первые hotbar_size ячеек, остальные 26 — рюкзак рядами по 10. Сужение 10→6
## переносит стопки из ячеек 6…9 в рюкзак; не влезло — в spilled (под ноги, spawn_item).
## Расширение 6→10 только открывает ячейки: они уже в инвентаре, перекладывать нечего.
func set_hotbar_size(n: int) -> Array[ItemStack]:
	var next: int = clamp_hotbar(n)
	var spilled: Array[ItemStack] = []
	if next < hotbar_size:
		for i in range(next, hotbar_size):
			var s: ItemStack = slots[i]
			if s.is_empty():
				continue
			var left: int = stack_into(slots, s.id, s.count, hotbar_size)
			if left > 0:
				spilled.append(ItemStack.new(s.id, left))
			slots[i] = ItemStack.new()
	hotbar_size = next
	if selected >= hotbar_size:
		selected = hotbar_size - 1
	changed.emit()
	return spilled
