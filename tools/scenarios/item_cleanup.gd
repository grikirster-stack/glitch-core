extends ScenarioBase
## Уборка предметов на земле (issue #7): одинаковые предметы рядом сливаются
## в одну кучку, несобранный предмет мигает перед исчезновением и исчезает по
## сроку жизни, а подобранная кучка отдаёт в инвентарь всё до единицы.
##
## Предметы роняем штатным путём (player.spawn_item — так падает добыча) в
## коридоре базы, дальше радиуса притягивания. Чтобы не ждать 5 минут, срок
## жизни проверяем, «состарив» предмет (поле age).

const DROPS: int = 12


func run() -> void:
	var base: int = stand_in_corridor(0)
	clear_input()
	await wait(0.3)
	var bx: int = World.beacon_cell.x
	var floor_y: float = float(base * World.TILE) - 12.0
	var stone: int = IDs.I.STONE
	var sand: int = IDs.I.SAND
	var inv0: int = player.inv.count_of(stone)

	# 12 камней — как добыча под ногами. Роняем в одну клетку со сдвигом ±4 px:
	# предмет при падении случайно уходит вбок до ~13 px, поэтому ложатся они
	# в 2–3 соседние клетки, но всегда в радиусе слияния (MERGE_CELLS = 2).
	# Раньше роняли в три клетки подряд: разлёт доходил до 5 клеток, крайние
	# кучки оказывались в 4 клетках друг от друга и по правилу не сливались —
	# сценарий зависел от состояния ГСЧ, то есть от сценариев перед ним.
	var nodes0: int = get_tree().get_node_count()
	var cx: int = bx + 12
	for i in DROPS:
		var dx: float = float(i % 3 - 1) * 4.0
		player.spawn_item(stone, 1, Vector2(float(cx * World.TILE) + 8.0 + dx, floor_y))
	# Песок в той же клетке — другой предмет, с камнями не сливается.
	player.spawn_item(sand, 1, Vector2(float((bx + 12) * World.TILE) + 8.0, floor_y))
	await wait(1.5)

	var stones: Array = _items(stone)
	var sands: Array = _items(sand)
	ok("одинаковые предметы рядом слились в одну кучку", stones.size() == 1,
			"узлов камня: %d из %d выпавших %s" % [stones.size(), DROPS, _describe(stones)])
	var total: int = 0
	for e in stones:
		total += int(e.count)
	ok("при слиянии ничего не потерялось", total == DROPS, "в кучке %d" % total)
	ok("другой предмет не слился", sands.size() == 1, "узлов песка: %d" % sands.size())
	ok("узлов прибавилось не больше двух", get_tree().get_node_count() - nodes0 <= 2,
			"+%d узлов на %d выпавших" % [get_tree().get_node_count() - nodes0, DROPS + 1])
	if stones.is_empty() or sands.is_empty():
		finish()
		return

	# Срок жизни: состарим песок до предупреждения — он мигает.
	var s: ItemEntity = sands[0]
	ok("срок жизни — не меньше нескольких минут", ItemEntity.LIFETIME >= 180.0,
			"%.0f с, предупреждение за %.0f с" % [ItemEntity.LIFETIME, ItemEntity.WARN_TIME])
	ok("свежий предмет не мигает", not s.is_warning() and s.modulate.a >= 0.99)
	s.age = ItemEntity.LIFETIME - ItemEntity.WARN_TIME + 1.0
	var min_a: float = 1.0
	var t0: float = now_proc()   # мигание идёт по кадрам отрисовки
	while now_proc() - t0 < 0.8:
		await get_tree().process_frame
		min_a = minf(min_a, s.modulate.a)
	ok("перед исчезновением предмет мигает", s.is_warning() and min_a < 0.8,
			"прозрачность до %.2f" % min_a)
	# Срок вышел — предмет исчезает.
	s.age = ItemEntity.LIFETIME - 0.2
	var gone: bool = await wait_until(func() -> bool: return _items(sand).is_empty(), 2.0)
	ok("по сроку жизни предмет исчез", gone)

	# Кучка камней: подходим — в инвентарь попадает всё.
	hold(KEY_D)
	var got: bool = await wait_until(func() -> bool: return player.inv.count_of(stone) >= inv0 + DROPS, 6.0)
	release_all()
	ok("подобранная кучка отдала всё", got,
			"камней %d → %d" % [inv0, player.inv.count_of(stone)])
	await wait(0.2)
	ok("кучка исчезла с земли", _items(stone).is_empty())
	finish()


## Клетки и счётчики кучек — для разбора провала.
func _describe(list: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for e in list:
		parts.append("%s×%d%s" % [str(World.world_to_cell(e.global_position)), int(e.count),
				"" if e.grounded else " (летит)" if not e.magnet else " (магнит)"])
	return "[" + ", ".join(parts) + "]"


func _items(id: int) -> Array:
	var out: Array = []
	for n in scene.get_children():
		if n is ItemEntity and n.item_id == id and not n.is_queued_for_deletion():
			out.append(n)
	return out
