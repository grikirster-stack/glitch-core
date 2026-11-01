class_name ItemStack
extends RefCounted
## Стопка предметов в инвентаре.

var id: int = IDs.I.NONE
var count: int = 0

func _init(p_id: int = IDs.I.NONE, p_count: int = 0) -> void:
	id = p_id
	count = p_count

func is_empty() -> bool:
	return id == IDs.I.NONE or count <= 0

func can_merge(other_id: int) -> bool:
	return id == other_id and id != IDs.I.NONE

func add(amount: int) -> int:
	count += amount
	return 0

func take(amount: int) -> int:
	var taken: int = mini(amount, count)
	count -= taken
	if count <= 0:
		id = IDs.I.NONE
		count = 0
	return taken

func duplicate_stack() -> ItemStack:
	return ItemStack.new(id, count)

func _to_string() -> String:
	return "ItemStack(%d x%d)" % [id, count]
