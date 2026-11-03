extends ScenarioBase
## Вода (#45): не растекается плёнкой по ровной земле, наполняет ямы,
## одна порция невидима.
##
## Стенды строятся в расчищенном прямоугольнике далеко слева от базы: камень
## кладём сами, поэтому рельеф сида на результат не влияет.
##
##   A — ровная площадка: стенка с одной стороны, ямка в 5 клетках с другой.
##       Вода стоит на месте: ни к стенке, ни к ямке плёнка не ползёт.
##   B — замкнутая яма 5×6: льём 5 порций по 8 в одну колонку — дно
##       заполняется ровно, целиком, а не столбиком.
##   C — широкая яма (WIDE = 16 клеток): вода доходит до дальней стенки,
##       дно ровное, а не лесенкой.
##   D — видимость: 1 порция — тайл AIR, 2 — тайл WATER.
##   E — источник у ямки: вода стекает в ямку целиком, сухо по другую сторону.
##
## В конце — нагрузка (льём в широкую яму сверху) и строка «ЗАМЕР»: шаги
## симуляции, клетки сканирования, время шага и кадра. Команда:
##   godot --headless --path . -- --scenario=fluid --seed=31337

const F: int = 14      # ряд пола стендов
const TOP: int = 5     # верхний ряд расчистки
const X0: int = 12     # левый край расчистки (база — в середине мира)
## Ширина широкой ямы C. Не зависит от FLUID_SCAN: так замер при разных
## FLUID_SCAN идёт на одной и той же нагрузке. Ямы шире — в fluid_pools (#70).
const WIDE: int = 16

## Запас пустых клеток между стендами. Стенды отделены друг от друга
## обрывом (пола между ними нет), так что после #70 «ямой» соседний стенд
## не становится — запас остался от прежнего правила, раскладка та же.
const SPACE: int = 16

var scan: int = 16
var _frame_us_max: int = 0
var _frame_us_sum: int = 0
var _frames: int = 0
var _last_us: int = 0
var _measure: bool = false


func run() -> void:
	await wait(0.2)
	var consts: Dictionary = World.get_script().get_script_constant_map()
	scan = int(consts.get("FLUID_SCAN", 16))
	# Между стендами — SPACE пустых клеток там, где проверяем «ровную землю».
	var d0: int = X0 + SPACE + 2
	var a0: int = d0 + SPACE + 10
	var a_len: int = 2 * SPACE + 9
	var b0: int = a0 + a_len + 4
	var c0: int = b0 + 7 + 4
	var e0: int = c0 + WIDE + 2 + 4
	var x1: int = e0 + 8
	_measure_terrain()
	_clear(X0, x1, TOP, F + 2)
	ok("стенды расчищены", _rect_is(X0, x1, TOP, F + 2, IDs.T.AIR))
	var steps0: int = World.fluid_steps
	var scans0: int = World.fluid_scan_cells
	var ticks0: int = World.fluid_ticks
	var us0: int = World.fluid_tick_us
	_measure = true

	await _stand_flat(a0, a_len)
	_measure_scan(a0 + a_len / 2)
	await _stand_pit(b0)
	await _stand_wide(c0)
	await _stand_visible(d0)
	await _stand_source(e0)
	await _stress(c0)
	var calm: bool = await wait_until(func() -> bool: return _pending() == 0, 10.0)
	ok("вода успокоилась: очередь пересчёта пуста", calm, "в очереди %d" % _pending())

	_measure = false
	var ticks: int = World.fluid_ticks - ticks0
	print("  ЗАМЕР вода: FLUID_SCAN %d, шагов симуляции %d, пересчётов клеток %d, клеток сканирования %d, шаг ср %.1f мкс / макс %d мкс; кадр ср %.2f мс / макс %.2f мс" % [
		scan, ticks, World.fluid_steps - steps0, World.fluid_scan_cells - scans0,
		float(World.fluid_tick_us - us0) / float(maxi(ticks, 1)), World.fluid_tick_us_max,
		float(_frame_us_sum) / float(maxi(_frames, 1)) / 1000.0, float(_frame_us_max) / 1000.0])
	finish()


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	if _measure and _last_us > 0:
		var dt: int = now - _last_us
		_frame_us_max = maxi(_frame_us_max, dt)
		_frame_us_sum += dt
		_frames += 1
	_last_us = now


# ------------------------------------------------------------------ ЗАМЕРЫ

## Сколько колонок поверхности мира «в яме» при разной дальности поиска
## стенки: вода на земле в такой колонке растекается по ровному дну.
## Мало — широкие впадины не наполняются; много — вода заливает слоем целые
## долины, то есть та же плёнка. По этому замеру выбран FLUID_SCAN.
func _measure_terrain() -> void:
	var parts: Array = []
	for k in [4, 8, 16, 32, 64]:
		var cols: int = 0
		var pits: int = 0
		for x in range(World.W):
			var r: int = World.surface[x] - 1
			if World.get_tile(x, r) != IDs.T.AIR or not World.is_solid_cell(Vector2i(x, r + 1)):
				continue
			cols += 1
			if _wall_within(x, r, -1, int(k)) and _wall_within(x, r, 1, int(k)):
				pits += 1
		parts.append("%d → %.0f %%" % [int(k), 100.0 * float(pits) / float(maxi(cols, 1))])
	print("  ЗАМЕР рельеф: доля колонок поверхности «в яме» при поиске стенки на N клеток: %s" % ", ".join(parts))
	# #70: стенку ищем по площадке до первого разрыва в полу (шире G клеток
	# без опоры), предел — 64 клетки. Последнее число — правило мира как есть.
	var gparts: Array = []
	for gap in [0, 1, 2, 3, 4]:
		var cols: int = 0
		var pits: int = 0
		for x in range(World.W):
			var r: int = World.surface[x] - 1
			if World.get_tile(x, r) != IDs.T.AIR or not World.is_solid_cell(Vector2i(x, r + 1)):
				continue
			cols += 1
			if _wall_on_floor(x, r, -1, int(gap)) and _wall_on_floor(x, r, 1, int(gap)):
				pits += 1
		gparts.append("%d → %.0f %%" % [int(gap), 100.0 * float(pits) / float(maxi(cols, 1))])
	var wcols: int = 0
	var wpits: int = 0
	if World.has_method("_fluid_bounded"):
		var cells0: int = World.fluid_scan_cells
		for x in range(World.W):
			var r: int = World.surface[x] - 1
			if World.get_tile(x, r) != IDs.T.AIR or not World.is_solid_cell(Vector2i(x, r + 1)):
				continue
			wcols += 1
			if bool(World.call("_fluid_bounded", x, r)):
				wpits += 1
		World.fluid_scan_cells = cells0
	print("  ЗАМЕР рельеф (#70): доля колонок «в яме» по площадке до разрыва шире G клеток: %s; правило мира (FLUID_SCAN %d) → %.0f %%" % [
		", ".join(gparts), scan, 100.0 * float(wpits) / float(maxi(wcols, 1))])


## Стенка в ряду y в сторону d, пока пол под рядом не обрывается шире gap
## клеток подряд (#70); предел — 64 клетки.
func _wall_on_floor(x: int, y: int, d: int, gap: int) -> bool:
	var run: int = 0
	for i in range(1, 65):
		var cx: int = x + d * i
		if cx < 0 or cx >= World.W:
			return true
		var t: int = World.get_tile(cx, y)
		if t != IDs.T.AIR and t != IDs.T.WATER:
			return true
		var b: int = World.get_tile(cx, y + 1)
		if (b == IDs.T.AIR or b == IDs.T.WATER) and World.fluid_level(Vector2i(cx, y + 1)) < World.FLUID_MAX:
			run += 1
			if run > gap:
				return false
		else:
			run = 0
	return false


func _wall_within(x: int, y: int, d: int, k: int) -> bool:
	for i in range(1, k + 1):
		var t: int = World.get_tile(x + d * i, y)
		if t != IDs.T.AIR and t != IDs.T.WATER:
			return true
	return false


## Цена одного сканирования вбок (если оно есть в World): 2000 вызовов на
## ровной площадке A, где справа стенки нет — ряд просматривается целиком.
func _measure_scan(x: int) -> void:
	if not World.has_method("_fluid_bounded"):
		return
	_measure = false   # пачка вызовов — не кадр игры, в замер кадра не берём
	var cells0: int = World.fluid_scan_cells
	var t0: int = Time.get_ticks_usec()
	for i in 2000:
		World.call("_fluid_bounded", x, F - 1)
	var us: int = Time.get_ticks_usec() - t0
	var cells: int = World.fluid_scan_cells - cells0
	World.fluid_scan_cells = cells0
	_last_us = 0
	_measure = true
	print("  ЗАМЕР сканирование: %.2f мкс на вызов, %.0f нс на клетку (%d клеток за вызов)" % [
		float(us) / 2000.0, 1000.0 * float(us) / float(maxi(cells, 1)), cells / 2000])


# ------------------------------------------------------------------ СТЕНДЫ

## A: ровная площадка. Слева в трёх клетках стенка, справа в пяти — ямка.
## Вода с обеих сторон «не заперта» — значит, стоит где стоит.
func _stand_flat(a0: int, a_len: int) -> void:
	for x in range(a0, a0 + a_len):
		World.set_tile(x, F, IDs.T.STONE)
	var c: int = a0 + a_len / 2
	World.set_tile(c - 3, F - 1, IDs.T.STONE)       # стенка слева
	World.set_tile(c + 5, F, IDs.T.AIR)             # ямка справа
	World.set_tile(c + 5, F + 1, IDs.T.STONE)
	World.set_fluid(Vector2i(c, F - 1), World.FLUID_MAX)
	await wait(1.5)
	var wet: Array = []
	for x in range(c - 2, c + 5):
		if x != c and World.fluid_level(Vector2i(x, F - 1)) > 0:
			wet.append(x - c)
	ok("ровная земля: вода не расползлась плёнкой", wet.is_empty(),
			"мокрые клетки (смещение от источника): %s" % str(wet))
	ok("ровная земля: до ямки в 5 клетках вода не доползла",
			World.fluid_level(Vector2i(c + 5, F)) == 0,
			"уровень в ямке %d" % World.fluid_level(Vector2i(c + 5, F)))
	ok("ровная земля: источник на месте и виден",
			World.fluid_level(Vector2i(c, F - 1)) == World.FLUID_MAX
			and World.get_tile(c, F - 1) == IDs.T.WATER,
			"уровень %d" % World.fluid_level(Vector2i(c, F - 1)))


## B: замкнутая яма 5 клеток шириной, 6 глубиной. Льём в среднюю колонку
## пять раз по полной клетке — 40 порций ровно на один ряд дна.
func _stand_pit(b0: int) -> void:
	_build_pit(b0, 5, 6)
	var pour: Vector2i = Vector2i(b0 + 3, F - 6)
	for i in 5:
		await wait_until(func() -> bool: return World.fluid_level(pour) == 0, 3.0)
		World.set_fluid(pour, World.FLUID_MAX)
	var full: bool = await wait_until(func() -> bool:
			return _row_min(b0 + 1, b0 + 5, F - 1) == World.FLUID_MAX, 12.0)
	var levels: Array = _row_levels(b0 + 1, b0 + 5, F - 1)
	ok("яма: дно заполнилось целиком, а не столбиком", full, "дно %s" % str(levels))
	ok("яма: всё дно — видимая вода",
			_row_tiles_are(b0 + 1, b0 + 5, F - 1, IDs.T.WATER), "дно %s" % str(levels))
	var total: int = _sum(b0 + 1, b0 + 5, F - 6, F - 1)
	ok("яма: вода не потерялась и не размножилась", total == 5 * World.FLUID_MAX,
			"порций %d" % total)
	ok("яма: выше дна сухо", _sum(b0 + 1, b0 + 5, F - 6, F - 2) == 0,
			"порций выше дна %d" % _sum(b0 + 1, b0 + 5, F - 6, F - 2))


## C: широкая яма — WIDE клеток, глубиной 2. Льём у левой стенки две порции
## на клетку дна: вода должна дойти до правой стенки и лечь ровно.
func _stand_wide(c0: int) -> void:
	_build_pit(c0, WIDE, 2)
	var pour: Vector2i = Vector2i(c0 + 1, F - 2)
	var cells: int = (2 * WIDE) / World.FLUID_MAX
	for i in cells:
		await wait_until(func() -> bool: return World.fluid_level(pour) == 0, 3.0)
		World.set_fluid(pour, World.FLUID_MAX)
	var far: Vector2i = Vector2i(c0 + WIDE, F - 1)
	await wait_until(func() -> bool: return World.fluid_level(far) > 0, 12.0)
	await wait(1.0)
	var levels: Array = _row_levels(c0 + 1, c0 + WIDE, F - 1)
	ok("широкая яма (%d клеток): вода дошла до дальней стенки" % WIDE,
			World.fluid_level(far) > 0, "дно %s" % str(levels))
	ok("широкая яма: мокро всё дно", _row_min(c0 + 1, c0 + WIDE, F - 1) > 0,
			"дно %s" % str(levels))
	var lv_min: int = _row_min(c0 + 1, c0 + WIDE, F - 1)
	var lv_max: int = 0
	for v in levels:
		lv_max = maxi(lv_max, int(v))
	ok("широкая яма: дно ровное, а не лесенкой (разброс ≤ 1 порции)", lv_max - lv_min <= 1,
			"дно %s" % str(levels))
	ok("широкая яма: вода не потерялась", _sum(c0 + 1, c0 + WIDE, F - 2, F - 1) == cells * World.FLUID_MAX,
			"порций %d" % _sum(c0 + 1, c0 + WIDE, F - 2, F - 1))


## D: видимость. Отдельная ровная площадка: стенок рядом нет, по краям обрыв.
func _stand_visible(d0: int) -> void:
	for x in range(d0 - 1, d0 + 10):
		World.set_tile(x, F, IDs.T.STONE)
	var one: Vector2i = Vector2i(d0 + 2, F - 1)
	var two: Vector2i = Vector2i(d0 + 6, F - 1)
	World.set_fluid(one, 1)
	World.set_fluid(two, 2)
	ok("1 порция — плёнка, тайл AIR", World.get_tile_v(one) == IDs.T.AIR
			and World.fluid_level(one) == 1, "тайл %d уровень %d" % [World.get_tile_v(one), World.fluid_level(one)])
	ok("2 порции — тайл WATER", World.get_tile_v(two) == IDs.T.WATER
			and World.fluid_level(two) == 2, "тайл %d уровень %d" % [World.get_tile_v(two), World.fluid_level(two)])
	await wait(1.0)
	ok("плёнка лежит на месте и не пропадает", World.fluid_level(one) == 1
			and World.get_tile_v(one) == IDs.T.AIR, "уровень %d" % World.fluid_level(one))
	ok("2 порции на ровном месте не растеклись", World.fluid_level(two) == 2
			and World.get_tile_v(two) == IDs.T.WATER, "уровень %d" % World.fluid_level(two))


## E: как в основном автотесте — источник на ровном, рядом ямка в клетку.
## Вода стекает в ямку (последняя порция тоже — с края она капает вниз).
func _stand_source(e0: int) -> void:
	for x in range(e0, e0 + 6):
		World.set_tile(x, F, IDs.T.STONE)
	var src: Vector2i = Vector2i(e0 + 2, F - 1)
	var hole: Vector2i = Vector2i(e0 + 3, F)
	World.set_tile(hole.x, hole.y, IDs.T.AIR)
	World.set_tile(hole.x, hole.y + 1, IDs.T.STONE)
	World.set_fluid(src, World.FLUID_MAX)
	await wait_until(func() -> bool: return World.fluid_level(src) <= 1, 6.0)
	await wait(0.5)
	ok("источник у ямки: вода стекла в ямку", World.get_tile_v(hole) == IDs.T.WATER
			and World.fluid_level(hole) >= 2, "уровень в ямке %d" % World.fluid_level(hole))
	ok("источник у ямки: на месте источника нет видимой лужи", World.get_tile_v(src) == IDs.T.AIR,
			"тайл %d уровень %d" % [World.get_tile_v(src), World.fluid_level(src)])
	ok("источник у ямки: по другую сторону сухо",
			World.fluid_level(Vector2i(src.x - 1, src.y)) == 0,
			"уровень %d" % World.fluid_level(Vector2i(src.x - 1, src.y)))


## Нагрузка: льём сверху в широкую яму сразу в три места — вода выравнивается
## по всему дну, каждая движущаяся клетка сканирует ряд. Только замер.
func _stress(c0: int) -> void:
	for i in 8:
		for x in [c0 + 1, c0 + WIDE / 2, c0 + WIDE]:
			World.set_fluid(Vector2i(int(x), F - 2), World.FLUID_MAX)
		await wait(0.15)
	await wait(2.0)


# ------------------------------------------------------------------ ПОСТРОЙКА

func _pending() -> int:
	if World.has_method("fluid_pending"):
		return int(World.call("fluid_pending"))
	return 0


## Расчистить прямоугольник (включительно).
func _clear(x0: int, x1: int, y0: int, y1: int) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if World.get_tile(x, y) != IDs.T.AIR or World.fluid_level(Vector2i(x, y)) > 0:
				World.set_tile(x, y, IDs.T.AIR)


## Яма: пол на ряду F, стенки по краям, внутри inner клеток ширины и depth глубины.
func _build_pit(x0: int, inner: int, depth: int) -> void:
	for x in range(x0, x0 + inner + 2):
		World.set_tile(x, F, IDs.T.STONE)
	for y in range(F - depth, F):
		World.set_tile(x0, y, IDs.T.STONE)
		World.set_tile(x0 + inner + 1, y, IDs.T.STONE)


func _rect_is(x0: int, x1: int, y0: int, y1: int, id: int) -> bool:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if World.get_tile(x, y) != id:
				return false
	return true


func _sum(x0: int, x1: int, y0: int, y1: int) -> int:
	var s: int = 0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			s += World.fluid_level(Vector2i(x, y))
	return s


func _row_levels(x0: int, x1: int, y: int) -> Array:
	var a: Array = []
	for x in range(x0, x1 + 1):
		a.append(World.fluid_level(Vector2i(x, y)))
	return a


func _row_min(x0: int, x1: int, y: int) -> int:
	var m: int = World.FLUID_MAX
	for x in range(x0, x1 + 1):
		m = mini(m, World.fluid_level(Vector2i(x, y)))
	return m


func _row_tiles_are(x0: int, x1: int, y: int, id: int) -> bool:
	for x in range(x0, x1 + 1):
		if World.get_tile(x, y) != id:
			return false
	return true
