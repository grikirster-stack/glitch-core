class_name MachineBase
extends Node2D
## Базовый класс построек: питание, приём/выдача предметов, логистика.

var cell: Vector2i = Vector2i.ZERO
var kind: String = ""
var powered: bool = false
var power_radius: float = 0.0
var power_active: bool = false
var progress: float = 0.0
var anim: float = 0.0
var _pt: float = 0.0


static func place_machine(p_kind: String, c: Vector2i) -> bool:
	if World.machines.has(c):
		return false
	if World.belts.has(c):
		return false
	if World.get_tile_v(c) != IDs.T.AIR:
		return false
	var m: MachineBase = null
	match p_kind:
		"Drill":
			m = Drill.new()
		"Smelter":
			m = Smelter.new()
		"Assembler":
			m = Assembler.new()
		"Chest":
			m = Chest.new()
		"CoalGen":
			m = CoalGen.new()
		"Solar":
			m = Solar.new()
		"Belt":
			m = Belt.new()
		_:
			return false
	m.cell = c
	m.kind = p_kind
	m.global_position = World.cell_to_world(c)
	m.position = m.global_position
	World.machines[c] = m
	if m is Belt:
		World.belts[c] = m
	World.add_world_node(m)
	return true


func _process(delta: float) -> void:
	anim = maxf(0.0, anim - delta * 2.0)
	_pt += delta
	if _pt > 0.4:
		_pt = 0.0
		powered = Game.is_powered(global_position)
	queue_redraw()


## Принимает предмет. Возвращает количество, которое НЕ принято (0 — принято всё).
func receive_item(item_id: int, count: int) -> int:
	return count


func input_accepts(item_id: int) -> bool:
	return false


## Отдаёт предмет: сначала соседний конвейер/сундук/станция, иначе — на землю.
func deliver(item_id: int, count: int) -> void:
	for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		var n: Vector2i = cell + d
		if World.belts.has(n):
			var b: Belt = World.belts[n]
			if b.add_item(item_id, count):
				return
		if World.machines.has(n):
			var m: MachineBase = World.machines[n]
			if m.receive_item(item_id, count) == 0:
				return
	spawn_item(item_id, count, global_position + Vector2(0.0, -4.0))


func spawn_item(item_id: int, count: int, pos: Vector2) -> void:
	var e: ItemEntity = ItemEntity.new()
	e.item_id = item_id
	e.count = count
	e.global_position = pos
	e.z_index = 4
	World.add_world_node(e)


func power_label() -> String:
	if power_radius <= 0.0:
		return ""
	return "%d" % int(power_radius)


func _draw_body(base: Color, accent: Color) -> void:
	var r: Rect2 = Rect2(-8.0, -8.0, 16.0, 16.0)
	draw_rect(r, base)
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 2.0), base.lightened(0.2))
	draw_rect(Rect2(r.position.x, r.end.y - 2.0, r.size.x, 2.0), base.darkened(0.25))
	draw_rect(Rect2(r.position.x + 2.0, r.position.y + 2.0, 3.0, 3.0), accent)
