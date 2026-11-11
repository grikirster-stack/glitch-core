class_name Beams
extends RefCounted
## Лучи света (ADR-005 § 4–5, #164). Цвет — битовая маска: R=1, G=2, B=4.
## Смешение — побитовое ИЛИ. Источник даёт beam_emit(), постройка на пути —
## beam_pass(); в C1 базовая постройка луч гасит.
##
## Трассировка по клеткам, как копка: воздух и жидкость пропускают, твёрдая
## клетка без постройки останавливает. Длина и плата за постройку — Balance.
## Перестроение не чаще раза в кадр: World ставит dirty, rebuild() — в _process.

## Маски цвета. Смеси: Y = R|G, C = G|B, M = R|B, W = 7.
const R: int = 1
const G: int = 2
const B: int = 4
const Y: int = 3
const C: int = 6
const M: int = 5
const W: int = 7

## Имена на русском — для подсказок и карточек. Индекс — маска цвета.
const NAME: Array[String] = ["", "Красный", "Зелёный", "Жёлтый", "Синий", "Пурпурный", "Голубой", "Белый"]

## Точные цвета палитры (DB.PAL). Красный — lava_hi, зелёный — bio, синий — crystal,
## белый — Color.WHITE; смеси — суммы каналов. Те же цвета в Emission.glow_colors,
## поэтому линия луча светится ночью сама.
const COLOR: Array[Color] = [
	Color(0, 0, 0, 0),
	Color("#FFD86E"),                       ## R — lava_hi
	Color("#7FE6D2"),                       ## G — bio
	Color(1.0, 1.0, 0.4275),                ## Y — R+G
	Color("#6FF5E0"),                       ## B — crystal
	Color(1.0, 0.8471, 1.0),                ## M — R+B
	Color(0.4353, 1.0, 1.0),                ## C — G+B
	Color.WHITE,                            ## W
]

## Защита от петель: кольцо зеркал и смеситель, который кормит сам себя.
const MAX_RAYS: int = 64
const MAX_STEPS: int = 4096
## Полей луча в очереди: x, y, dir, color, left, len, budget.
const RAY: int = 7
## Два прохода мало, если цепочка преобразователей кормит саму себя цветом.
## Повторяем, пока карта клеток не успокоится. Смеситель копит входы между
## проходами и отдаёт смесь только со второго — поэтому одного мало.
const MAX_PASSES: int = 8

## Направления: 0 вправо, 1 вниз, 2 влево, 3 вверх, затем четыре диагонали.
## 4 вправо-вниз, 5 влево-вниз, 6 влево-вверх, 7 вправо-вверх.
## Шаг в соседнюю клетку — и в диагональную — стоит 1 клетку длины.
const DIR: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1), Vector2i(1, -1),
]
const DIR_N: int = 8

## Клетка → маска цвета (битовое ИЛИ всех лучей, прошедших клетку).
## Публичный вид — словарь; внутри прохода маска лежит в плоском массиве мира,
## чтобы 20 горелок укладывались в 1 мс (порог сценария, не 300 мкс CI).
var cells: Dictionary = {}
## Сегменты для отрисовки: {from, to, color, strength}. strength — доля длины
## у начала сегмента (1 у источника, меньше к концу).
var segments: Array = []
## Кто-то изменил мир или источник. World перестроит в ближайшем _process.
var dirty: bool = false
## Вырос на 1 после каждого rebuild(), в котором карта или сегменты сменились.
## WorldFX смотрит на него и не рисует луч заново в покое.
var changed: int = 0
## Последний rebuild(), мкс. Печатает сценарий beam_burner.
var last_rebuild_us: int = 0

var _sig: int = 0
## Плоская карта прохода: индекс клетки мира → маска. 0 — луча нет.
var _flat: PackedByteArray = PackedByteArray()
var _hit: PackedInt32Array = PackedInt32Array()
## Бегущая подпись клеток прохода: без второго обхода массива.
var _run: int = 0
## Кто стоит в клетке, на время прохода: 0 пусто, 1 глушит луч, 2+ пропускает
## (beam_pass). Словарь машин в горячем цикле не трогаем.
var _occ: PackedByteArray = PackedByteArray()
var _occ_nodes: Array = []
## Приёмники луча (есть beam_receive): маяк. Сообщаем им цвет после прохода,
## только если карта реально сменилась.
var _receivers: Array = []
## Источники луча: ищем один раз при постройке, а не по всем машинам мира.
var _emitters: Array = []
## Сколько построек на карте пропускают луч. 0 — одного прохода хватает (C1).
var _passers: int = 0


func _init() -> void:
	dirty = true


## Цвет в клетке (0 — луча нет).
func color_at(cell: Vector2i) -> int:
	return int(cells.get(cell, 0))


## Пометить луч устаревшим. Само перестроение — в World._process, не чаще кадра.
func mark_dirty() -> void:
	dirty = true


## Перестроить карту и сегменты. Повторяет проход, пока карта цветов меняется,
## не больше MAX_PASSES. Без преобразователей хватает одного прохода.
## Смеситель видит все входы только после полного прохода, поэтому перед
## каждым проходом его inputs сбрасывается, а выход стабилен со второго.
## Возвращает мкс. Лишний вызов без изменений карты changed не растит.
func rebuild() -> int:
	var t0: int = Time.get_ticks_usec()
	dirty = false
	var next_cells: Dictionary = {}
	var next_segs: Array = []
	var prev_sig: int = -1
	var n: int = World.W * World.H
	if _flat.size() != n:
		_flat = PackedByteArray()
		_flat.resize(n)
	var passes: int = MAX_PASSES if _passers > 0 else 1
	var kept: Array = []
	for _pass in passes:
		# Карта занятости — на каждый проход: между проходами могли поставить
		# или снять постройку, а note_machines зовут не из каждого кадра.
		_fill_occ()
		_reset_pass_inputs()
		next_segs = []
		_run = 0
		_trace(next_segs)
		var sig: int = _seg_sig(next_segs)
		_clear_flat(next_segs)
		kept = next_segs
		if sig == prev_sig:
			break
		prev_sig = sig
	# Карта не изменилась — словарь клеток и сегменты те же. Горячий путь кадра
	# не собирает 500 ключей Vector2i заново.
	if prev_sig == _sig:
		last_rebuild_us = Time.get_ticks_usec() - t0
		return last_rebuild_us
	_sig = prev_sig
	changed += 1
	_cells_from_segs(next_cells, kept)
	cells = next_cells
	segments = kept
	_deliver(kept)
	last_rebuild_us = Time.get_ticks_usec() - t0
	return last_rebuild_us


func _seg_sig(segs: Array) -> int:
	var h: int = segs.size() * 97
	for s in segs:
		h = (h * 33) ^ (int(s["from"].x) * 73856093) ^ (int(s["from"].y) * 19349663)
		h ^= (int(s["to"].x) * 83492791) ^ int(s["to"].y) ^ (int(s["color"]) << 8) ^ int(s["air"])
	return h


func _clear_flat(segs: Array) -> void:
	var w: int = World.W
	for s in segs:
		var step: Vector2i = DIR[int(s["dir"]) & 7]
		var x: int = int(s["from"].x) + step.x
		var y: int = int(s["from"].y) + step.y
		for _i in int(s["air"]):
			_flat[y * w + x] = 0
			x += step.x
			y += step.y


## Клетки луча — прямые отрезки сегментов, не список индексов из горячего цикла.
func _cells_from_segs(into: Dictionary, segs: Array) -> void:
	into.clear()
	for s in segs:
		var step: Vector2i = DIR[int(s["dir"]) & 7]
		var x: int = int(s["from"].x) + step.x
		var y: int = int(s["from"].y) + step.y
		var col: int = int(s["color"])
		for _i in int(s["air"]):
			var c: Vector2i = Vector2i(x, y)
			into[c] = int(into.get(c, 0)) | col
			x += step.x
			y += step.y


## Подпись плоской карты: без сборки словаря на каждом проходе.
func _signature_flat(next_segs: Array) -> int:
	var h: int = _hit.size() * 16777619
	for idx in _hit:
		h = (h * 31) ^ (idx * 73856093) ^ (int(_flat[idx]) * 83492791)
	h ^= next_segs.size() * 97
	for s in next_segs:
		h = (h * 33) ^ (int(s["from"].x) << 8) ^ int(s["from"].y) ^ (int(s["to"].x) << 4) ^ int(s["to"].y)
		h ^= int(s["color"]) * 17
		h ^= int(round(float(s["strength"]) * 1000.0))
	return h


## Один проход: источники → очередь лучей → клетки и сегменты.
## Постройка появилась или исчезла: обновить список источников.
func note_machines() -> void:
	_emitters.clear()
	_receivers.clear()
	_passers = 0
	for m in World.machines.values():
		if not is_instance_valid(m) or m.is_queued_for_deletion():
			continue
		if m.has_method("beam_emit"):
			_emitters.append(m)
		if m.has_method("beam_receive"):
			_receivers.append(m)
		# Зеркало, смеситель, призма: beam_pass и проход, пока карта не успокоится.
		# Маяк beam_pass имеет, но луч гасит — в _passers его не кладём.
		if m.has_method("beam_pass") and bool(m.get("beam_passer")):
			_passers += 1
	_fill_occ()
	dirty = true


func _fill_occ() -> void:
	var n: int = World.W * World.H
	# Новый массив, не fill поверх старого: generate() и смена сцены сносят
	# машины через queue_free, а note_machines() видит уже пустой словарь.
	# fill оставил бы клетки снятых построек — и луч обрывался на воздухе.
	_occ = PackedByteArray()
	_occ.resize(n)
	_occ_nodes = [null, null]
	for m in World.machines.values():
		if not is_instance_valid(m) or m.is_queued_for_deletion():
			continue
		var c: Vector2i = m.cell
		if not World.in_bounds(c.x, c.y):
			continue
		# Постройка без beam_passer гасит луч (код 1). Маяк — тоже: башня конец линии.
		# Пропускающая — код ≥ 2 и узел в _occ_nodes: горячий цикл не ищет машину в словаре.
		var passer: bool = m.get("beam_passer") == true
		if m.has_method("beam_pass") and passer:
			_occ_nodes.append(m)
			_occ[c.y * World.W + c.x] = _occ_nodes.size() - 1
		else:
			_occ[c.y * World.W + c.x] = 1


## Смеситель копит входы за проход. Перед следующим — чистый лист,
## иначе цвет прошлого прохода останется в смеси навсегда.
func _reset_pass_inputs() -> void:
	for i in range(2, _occ_nodes.size()):
		var m = _occ_nodes[i]
		if is_instance_valid(m) and m.has_method("beam_reset_inputs"):
			m.beam_reset_inputs()


func _clear_occ() -> void:
	var w: int = World.W
	for m in World.machines.values():
		if not is_instance_valid(m):
			continue
		var c: Vector2i = m.cell
		if World.in_bounds(c.x, c.y):
			_occ[c.y * w + c.x] = 0
	_occ_nodes = [null, null]


func _trace(next_segs: Array) -> void:
	# Луч — семь чисел: x, y, dir, color, left, len, budget.
	# budget — длина у источника этого луча (24 или 32). После зеркала и призмы
	# left падает на BEAM_BLOCK_COST, len (для яркости) остаётся прежним.
	# Смеситель смотрит на budget, не на left: белый выход — всегда 32.
	var q: PackedInt32Array = PackedInt32Array()
	var steps: int = 0
	var solid: PackedByteArray = World._solid_tbl
	var tiles: PackedByteArray = World.tiles
	var w: int = World.W
	var h: int = World.H
	if _emitters.is_empty() and not World.machines.is_empty():
		note_machines()
		dirty = false
	for m in _emitters:
		if not is_instance_valid(m) or m.is_queued_for_deletion():
			continue
		var emitted: Array = m.beam_emit()
		for e in emitted:
			if not (e is Array) or e.size() < 3:
				continue
			var length: int = int(e[2])
			if length <= 0:
				continue
			q.append(m.cell.x)
			q.append(m.cell.y)
			q.append(int(e[0]) & 7)
			q.append(int(e[1]) & 7)
			q.append(length)
			q.append(length)
			q.append(length)
			if q.size() >= MAX_RAYS * RAY:
				break
		if q.size() >= MAX_RAYS * RAY:
			break
	var ri: int = 0
	while ri < q.size() and steps < MAX_STEPS:
		var x: int = q[ri]
		var y: int = q[ri + 1]
		var dir: int = q[ri + 2]
		var color: int = q[ri + 3]
		var left: int = q[ri + 4]
		var length: int = maxi(1, q[ri + 5])
		var budget: int = q[ri + 6]
		ri += RAY
		if color == 0 or left <= 0:
			continue

		var step: Vector2i = DIR[dir & 7]
		var sx: int = step.x
		var sy: int = step.y


		var fx: int = x
		var fy: int = y
		var seg_left: int = left
		var walked: int = 0
		while left > 0 and steps < MAX_STEPS:
			steps += 1
			var nx: int = x + sx
			var ny: int = y + sy
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				break
			var nidx: int = ny * w + nx
			# Наискосок сквозь угол двух стен не идём: обе боковые клетки
			# должны быть воздухом. Одна стена на углу — луч ещё проходит.
			if sx != 0 and sy != 0 and _corner_blocked(x, y, sx, sy, w, h, solid, tiles):
				_close_seg(next_segs, Vector2i(fx, fy), Vector2i(x, y), dir, color, seg_left, length, walked)
				break
			var occ: int = _occ[nidx]
			if occ != 0:
				_close_seg(next_segs, Vector2i(fx, fy), Vector2i(x, y), dir, color, seg_left, length, walked)
				if occ >= 2 and q.size() < MAX_RAYS * RAY:
					var node = _occ_nodes[occ]
					if is_instance_valid(node):
						var outs: Array = node.beam_pass(dir, color)

						var out_left: int = left - Balance.BEAM_BLOCK_COST
						var out_budget: int = budget
						# Смеситель: длина — max(бюджет входов) − 2, белый — 32.
						# Зеркало и призма бюджет не меняют, только платят 2.
						if node.has_method("beam_out_budget"):
							out_budget = int(node.beam_out_budget(budget))
							out_left = out_budget

						for o in outs:
							if q.size() >= MAX_RAYS * RAY or not (o is Array) or o.size() < 2:
								break

							var span: int = maxi(1, out_left)
							q.append(nx)
							q.append(ny)
							q.append(int(o[0]) & 7)
							q.append(int(o[1]) & 7)
							q.append(out_left)
							q.append(span)
							q.append(out_budget)
				break
			if solid[tiles[nidx]] != 0:
				# Упирается в породу: линия доходит до стены, сквозь неё не идёт.
				_close_seg(next_segs, Vector2i(fx, fy), Vector2i(nx, ny), dir, color, seg_left, length, walked)
				break
			# Воздух и жидкость. Клетка источника в карту не пишется — луч из носика.
			x = nx
			y = ny
			left -= 1
			walked += 1
			_flat[nidx] = _flat[nidx] | color
		if walked > 0 and left <= 0:
			next_segs.append(_seg(fx, fy, x, y, dir, color, seg_left, length, walked))


## Цвет, который упёрся в постройку: OR всех входов. Сообщаем только если карта
## реально сменилась — иначе маяк сбрасывал бы перезарядку на каждом кадре.
## Диагональный шаг сквозь угол: обе боковые клетки твёрдые — щели нет.
## Одна стена на углу луч не закрывает (как копка: касание угла — не стена).
func _corner_blocked(x: int, y: int, sx: int, sy: int, w: int, h: int, solid: PackedByteArray, tiles: PackedByteArray) -> bool:
	var ax: int = x + sx
	var ay: int = y
	var bx: int = x
	var by: int = y + sy
	if ax < 0 or ay < 0 or ax >= w or ay >= h:
		return true
	if bx < 0 or by < 0 or bx >= w or by >= h:
		return true
	return solid[tiles[ay * w + ax]] != 0 and solid[tiles[by * w + bx]] != 0


func _deliver(segs: Array) -> void:
	if _receivers.is_empty():
		return
	var hit: Dictionary = {}
	var w: int = World.W
	var hgt: int = World.H
	for s in segs:
		var step: Vector2i = DIR[int(s["dir"]) & 7]
		var x: int = int(s["to"].x) + step.x
		var y: int = int(s["to"].y) + step.y
		if x < 0 or y < 0 or x >= w or y >= hgt:
			continue
		var key: int = y * w + x
		hit[key] = int(hit.get(key, 0)) | int(s["color"])
	for m in _receivers:
		if not is_instance_valid(m) or m.is_queued_for_deletion():
			continue
		var c: Vector2i = m.cell
		if not World.in_bounds(c.x, c.y):
			continue
		m.beam_receive(int(hit.get(c.y * w + c.x, 0)))


func _close_seg(segs: Array, from: Vector2i, to: Vector2i, dir: int, color: int, seg_left: int, length: int, air: int) -> void:
	if air <= 0 and from == to:
		return
	segs.append(_seg(from.x, from.y, to.x, to.y, dir, color, seg_left, length, air))


func _seg(fx: int, fy: int, tx: int, ty: int, dir: int, color: int, seg_left: int, length: int, air: int) -> Dictionary:
	return {
		"from": Vector2i(fx, fy),
		"to": Vector2i(tx, ty),
		"dir": dir,
		"color": color,
		"air": air,
		"strength": clampf(float(seg_left) / float(maxi(1, length)), 0.0, 1.0),
	}


## Подпись карты и сегментов: смена — повод перерисовать и зажечь свет заново.
func _signature(next_cells: Dictionary, next_segs: Array) -> int:
	var h: int = next_cells.size() * 16777619
	for c in next_cells.keys():
		h = (h * 31) ^ (int(c.x) * 73856093) ^ (int(c.y) * 19349663) ^ (int(next_cells[c]) * 83492791)
	h ^= next_segs.size() * 97
	for s in next_segs:
		h = (h * 33) ^ (int(s["from"].x) << 8) ^ int(s["from"].y) ^ (int(s["to"].x) << 4) ^ int(s["to"].y)
		h ^= int(s["color"]) * 17
		h ^= int(round(float(s["strength"]) * 1000.0))
	return h
