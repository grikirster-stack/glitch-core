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

## Защита от петель: смеситель «всех входов» будет в C2, здесь только потолок.
const MAX_RAYS: int = 64
const MAX_STEPS: int = 4096
## Два прохода мало, если цепочка преобразователей кормит саму себя цветом.
## Повторяем, пока карта клеток не успокоится.
const MAX_PASSES: int = 8

## Направления как у MachineBase.dir: 0 вправо, 1 вниз, 2 влево, 3 вверх.
const DIR: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]

## Клетка → маска цвета (битовое ИЛИ всех лучей, прошедших клетку).
## Публичный вид — словарь; внутри прохода маска лежит в плоском массиве мира,
## чтобы 20 горелок укладывались в 300 мкс.
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
## не больше MAX_PASSES: в C1 преобразователей нет и второй проход совпадает
## с первым; смеситель «всех входов» (C2) допишет сюда же. Возвращает мкс.
## Лишний вызов без изменений карты changed не растит.
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
	var dxs: PackedInt32Array = PackedInt32Array([1, 0, -1, 0])
	var dys: PackedInt32Array = PackedInt32Array([0, 1, 0, -1])
	for s in segs:
		var dir: int = int(s["dir"])
		var x: int = int(s["from"].x) + dxs[dir]
		var y: int = int(s["from"].y) + dys[dir]
		for _i in int(s["air"]):
			_flat[y * w + x] = 0
			x += dxs[dir]
			y += dys[dir]


## Клетки луча — прямые отрезки сегментов, не список индексов из горячего цикла.
func _cells_from_segs(into: Dictionary, segs: Array) -> void:
	into.clear()
	var dxs: PackedInt32Array = PackedInt32Array([1, 0, -1, 0])
	var dys: PackedInt32Array = PackedInt32Array([0, 1, 0, -1])
	for s in segs:
		var dir: int = int(s["dir"])
		var x: int = int(s["from"].x) + dxs[dir]
		var y: int = int(s["from"].y) + dys[dir]
		var col: int = int(s["color"])
		for _i in int(s["air"]):
			var c: Vector2i = Vector2i(x, y)
			into[c] = int(into.get(c, 0)) | col
			x += dxs[dir]
			y += dys[dir]


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
	_passers = 0
	for m in World.machines.values():
		if not is_instance_valid(m) or m.is_queued_for_deletion():
			continue
		if m.has_method("beam_emit"):
			_emitters.append(m)
		# C2: зеркало и смеситель сами объявят beam_pass и поднимут _passers.
	_fill_occ()
	dirty = true


func _fill_occ() -> void:
	var n: int = World.W * World.H
	if _occ.size() != n:
		_occ = PackedByteArray()
		_occ.resize(n)
	_occ_nodes = [null, null]
	for m in World.machines.values():
		if not is_instance_valid(m) or m.is_queued_for_deletion():
			continue
		var c: Vector2i = m.cell
		if not World.in_bounds(c.x, c.y):
			continue
		# C1: любая постройка гасит луч (beam_pass базы возвращает []).
		# C2 запишет сюда код ≥ 2 и узел в _occ_nodes.
		_occ[c.y * World.W + c.x] = 1


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
	# Луч — шесть чисел в одном массиве: x, y, dir, color, left, len.
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
			q.append(int(e[0]) & 3)
			q.append(int(e[1]) & 7)
			q.append(length)
			q.append(length)
			if q.size() >= MAX_RAYS * 6:
				break
		if q.size() >= MAX_RAYS * 6:
			break
	var ri: int = 0
	var dxs: PackedInt32Array = PackedInt32Array([1, 0, -1, 0])
	var dys: PackedInt32Array = PackedInt32Array([0, 1, 0, -1])
	while ri < q.size() and steps < MAX_STEPS:
		var x: int = q[ri]
		var y: int = q[ri + 1]
		var dir: int = q[ri + 2]
		var color: int = q[ri + 3]
		var left: int = q[ri + 4]
		var length: int = maxi(1, q[ri + 5])
		ri += 6
		if color == 0 or left <= 0:
			continue
		var sx: int = dxs[dir]
		var sy: int = dys[dir]
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
			var occ: int = _occ[nidx]
			if occ != 0:
				_close_seg(next_segs, Vector2i(fx, fy), Vector2i(x, y), dir, color, seg_left, length, walked)
				if occ >= 2 and q.size() < MAX_RAYS * 6:
					var outs: Array = _occ_nodes[occ].beam_pass(dir, color)
					for o in outs:
						if q.size() >= MAX_RAYS * 6 or not (o is Array) or o.size() < 2:
							break
						q.append(nx)
						q.append(ny)
						q.append(int(o[0]) & 3)
						q.append(int(o[1]) & 7)
						q.append(left - Balance.BEAM_BLOCK_COST)
						q.append(length)
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
