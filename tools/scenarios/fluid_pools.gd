extends ScenarioBase
## Вода (#45): плёнка по ровной земле не расползается, замкнутая яма
## наполняется, одна порция воды невидима, две и больше — видны.
##
## Это независимая перепроверка требований #45: стенды строятся свои, рельеф
## сида на результат не влияет, проверки написаны отдельно от сценария
## fluid.gd — чтобы правило воды нельзя было сломать, не сломав обе проверки.
##
## Площадку сценарий строит сам: ровная полка без стен, ям и настоящей воды.
## Так результат не зависит от того, как выпал рельеф, и проверка «плёнки»
## честная: рядом с водой действительно ровная сухая земля.
##
## Стенды #70 (ширина ямы, площадка без ям, яма с разрывом в полу) стоят в
## расчищенном прямоугольнике в небе справа от базы — им нужно больше места,
## чем есть у ровной полки на земле. Там же стенд #147: малая порция в широкой
## замкнутой впадине стоит видимой лужей, а не плёнкой.
##
## Команда:
##   godot --headless --path . -- --scenario=fluid_pools --seed=31337

const PAD_L: int = 13          # колонок запаса слева от площадки
const PAD_R: int = 13          # колонок запаса справа от площадки
const FILM_X: int = -4         # колонка источника для проверки плёнки
const POCKET_X: int = 8        # колонка источника в замкнутой впадине

# --- Стенды #70: расчищенный прямоугольник в небе справа от базы ---
const SKY_F: int = 14          # ряд пола стендов
const SKY_TOP: int = 4         # верхний ряд расчистки
const SKY_BOTTOM: int = 23     # нижний ряд расчистки (под шахтой разрыва)
const SKY_X1: int = 628        # правый край расчистки (World.W - 12)
const SKY_X0: int = SKY_X1 - 80    # левый край расчистки
const PIT_WIDTHS: Array = [12, 16, 24, 32, 48]
const FLAT_LEN: int = 48       # ширина площадки без ям
const GAP_PIT: int = 32        # ширина ямы с разрывом в полу
const PUDDLE_PIT: int = 27     # ширина впадины для малой лужи (#147)

# Пределы правила воды. Читаем из карты констант, а не World.FLUID_GAP напрямую:
# так этот же сценарий меряет и прежнее правило (замер «до» в PR #70).
var scan_max: int = 16
var gap_max: int = 0


func run() -> void:
	await wait(0.3)
	var consts: Dictionary = World.get_script().get_script_constant_map()
	scan_max = int(consts.get("FLUID_SCAN", 16))
	gap_max = int(consts.get("FLUID_GAP", 0))
	# --- #70: широкие ямы, площадка без ям, яма с разрывом в полу ---
	var sky_steps: int = World.fluid_steps
	var sky_scans: int = World.fluid_scan_cells
	World.fluid_tick_us_max = 0
	World.set("fluid_scan_tick_max", 0)
	_clear(SKY_X0, SKY_X1, SKY_TOP, SKY_BOTTOM)
	await _measure_wide_pits()
	await _measure_flat()
	await _measure_gap_pit()
	await _measure_small_puddle()
	_clear(SKY_X0, SKY_X1, SKY_TOP, SKY_BOTTOM)
	print("  ЗАМЕР стенды #70: шагов воды %d, просмотрено клеток %d, больше всего клеток за шаг %d, худший шаг воды %.2f мс" % [
			World.fluid_steps - sky_steps, World.fluid_scan_cells - sky_scans,
			_scan_tick_max(), float(World.fluid_tick_us_max) / 1000.0])
	await wait(0.3)

	# Дальше — стенды #45 на ровной полке у земли; итоговая строка «шагов
	# симуляции» считает только их и озеро (сравнима с замерами #45 и #70).
	var steps0: int = World.fluid_steps
	var scans0: int = World.fluid_scan_cells
	var x: int = _find_spot()
	ok("нашлось ровное сухое место", x >= 0, "колонка %d" % x)
	if x < 0:
		finish()
		return
	var g: int = World.surface[x]
	_build_platform(x, g)
	# Ровная земля — это площадка, у которой пол где-то обрывается (#70). Полка
	# стоит у края мира (колонка 15), а рельеф по обе стороны может подниматься
	# выше её пола (сиды 4242, 12345: стенки в колонках 1 и 29). Тогда вся
	# полка — замкнутая впадина шириной 27, и вода в ней растекается по правилу
	# ям. Поэтому на время проверок (а)–(г) роем по краям полки канавы шире
	# FLUID_GAP: это обрыв, полка становится ровной землёй на любом сиде.
	_set_moats(x, g, true)
	ok("полка — ровная земля, а не замкнутая впадина",
			not bool(World.call("_fluid_bounded", x + FILM_X, g - 1))
			and not bool(World.call("_fluid_bounded", x + 4, g - 1)),
			"колонки %d и %d, ряд %d" % [x + FILM_X, x + 4, g - 1])

	# --- (а) вода не расползается плёнкой по ровной сухой земле ---
	var film_src: Vector2i = Vector2i(x + FILM_X, g - 1)
	World.set_fluid(film_src, World.FLUID_MAX)
	await wait(1.0)
	var film: bool = true
	var where: String = ""
	for dx in [-2, -1, 1, 2]:
		var c: Vector2i = film_src + Vector2i(dx, 0)
		if World.fluid_level(c) != 0 or World.get_tile_v(c) == IDs.T.WATER:
			film = false
			where = "%s уровень %d тайл %d" % [str(c), World.fluid_level(c), World.get_tile_v(c)]
	ok("вода не растеклась плёнкой по ровной земле", film, where)
	ok("вода стоит на месте", World.fluid_level(film_src) == World.FLUID_MAX,
			"уровень %d" % World.fluid_level(film_src))

	# --- (б) вода наполняет замкнутую яму ---
	# Яма в две клетки вглубь, стенки по бокам — земля вокруг.
	var src: Vector2i = Vector2i(x, g - 1)
	var pit_top: Vector2i = Vector2i(x + 1, g)
	var pit_bottom: Vector2i = Vector2i(x + 1, g + 1)
	World.set_tile(pit_top.x, pit_top.y, IDs.T.AIR)
	World.set_tile(pit_bottom.x, pit_bottom.y, IDs.T.AIR)
	World.set_fluid(src, World.FLUID_MAX)
	await wait(2.5)
	ok("вода наполнила яму", World.fluid_level(pit_bottom) > 0,
			"уровень %d" % World.fluid_level(pit_bottom))
	ok("на дне ямы видна вода", World.get_tile_v(pit_bottom) == IDs.T.WATER,
			"тайл %d" % World.get_tile_v(pit_bottom))
	ok("вода не вытекла из ямы",
			World.fluid_level(Vector2i(x + 2, g + 1)) == 0
			and World.fluid_level(Vector2i(x, g + 1)) == 0,
			"слева %d, справа %d" % [World.fluid_level(Vector2i(x, g + 1)),
				World.fluid_level(Vector2i(x + 2, g + 1))])
	# Остаток в одну порцию — плёнка в полклетки, её не видно.
	ok("остаток в одну порцию не виден",
			World.fluid_level(src) <= 1 and World.get_tile_v(src) != IDs.T.WATER,
			"уровень %d тайл %d" % [World.fluid_level(src), World.get_tile_v(src)])

	# --- (в) одна порция невидима, две и больше — видны ---
	var probe: Vector2i = Vector2i(x + 4, g - 1)
	World.set_fluid(probe, 5)
	ok("пять порций видны", World.get_tile_v(probe) == IDs.T.WATER,
			"тайл %d" % World.get_tile_v(probe))
	World.set_fluid(probe, 1)
	ok("одна порция не видна", World.get_tile_v(probe) == IDs.T.AIR,
			"тайл %d" % World.get_tile_v(probe))
	World.set_fluid(probe, 2)
	ok("две порции видны", World.get_tile_v(probe) == IDs.T.WATER,
			"тайл %d" % World.get_tile_v(probe))
	await wait(0.5)
	ok("порции на месте не растекаются", World.fluid_level(probe) == 2,
			"уровень %d" % World.fluid_level(probe))

	# --- (г) вода перетекает в сухую замкнутую впадину ---
	# Стены по бокам, вода между ними: впадина замкнута — вода её заполнит.
	var psrc: Vector2i = Vector2i(x + POCKET_X, g - 1)
	var pdst: Vector2i = Vector2i(x + POCKET_X + 1, g - 1)
	World.set_tile(x + POCKET_X - 1, g - 1, IDs.T.STEEL)
	World.set_tile(x + POCKET_X + 2, g - 1, IDs.T.STEEL)
	World.set_fluid(psrc, World.FLUID_MAX)
	await wait(0.8)
	ok("вода перетекла в замкнутую впадину", World.fluid_level(pdst) > 0,
			"уровень %d" % World.fluid_level(pdst))
	ok("во впадине вода видна", World.get_tile_v(pdst) == IDs.T.WATER,
			"тайл %d" % World.get_tile_v(pdst))

	# --- Замер: тяжёлый случай для симуляции воды ---
	# Льём большое озеро на ровную площадку: вода оседает, по краям её
	# клетки пробуют расползтись вбок и сканируют стены впадины. Это самый
	# тяжёлый случай для сканирования — меряем худший кадр и число
	# просмотренных клеток. Канавы засыпаем: озеро меряем на той же полке,
	# что и в #45, чтобы цифры были сравнимы.
	_set_moats(x, g, false)
	await _stress_water(x, g)

	ok("шагов симуляции воды: %d, просмотрено клеток при поиске стен: %d" % [
		World.fluid_steps - steps0, World.fluid_scan_cells - scans0], true)
	finish()


## Заливает площадку озером и меряет, сколько стоит кадр.
func _stress_water(x: int, g: int) -> void:
	const LAKE_HALF: int = 12     # половина ширины озера (25 клеток)
	const LAKE_TALL: int = 4      # высота озера в клетках
	for c in range(x - LAKE_HALF, x + LAKE_HALF + 1):
		for y in range(g - LAKE_TALL, g):
			World.set_fluid(Vector2i(c, y), World.FLUID_MAX)
	var worst: float = 0.0
	var sum: float = 0.0
	World.fluid_tick_us_max = 0
	World.set("fluid_scan_tick_max", 0)
	var prev_us: int = Time.get_ticks_usec()
	var scans: int = World.fluid_scan_cells
	var steps: int = World.fluid_steps
	for i in 180:
		await await_frame()
		var now_us: int = Time.get_ticks_usec()
		var ms: float = float(now_us - prev_us) / 1000.0
		worst = maxf(worst, ms)
		sum += ms
		prev_us = now_us
	ok("замер: озеро 25x4 — худший кадр %.1f мс, средний %.1f мс, шагов воды %d, просмотрено клеток %d (за шаг не больше %d), худший шаг воды %.2f мс" % [
			worst, sum / 180.0, World.fluid_steps - steps, World.fluid_scan_cells - scans,
			_scan_tick_max(), float(World.fluid_tick_us_max) / 1000.0], true)


## Сколько клеток дна наполнено в яме разной ширины (#70). Яма глубиной 2,
## льём у левой стенки по две порции на клетку дна: вода должна дойти до
## правой стенки. Ямы не шире предела FLUID_SCAN наполняются целиком.
func _measure_wide_pits() -> void:
	var parts: Array = []
	for w in PIT_WIDTHS:
		var width: int = int(w)
		var x0: int = SKY_X0 + 2
		_build_pit(x0, width, 2)
		var pour: Vector2i = Vector2i(x0 + 1, SKY_F - 2)
		var pours: int = (2 * width) / World.FLUID_MAX
		for i in pours:
			await wait_until(func() -> bool: return World.fluid_level(pour) == 0, 3.0)
			World.set_fluid(pour, World.FLUID_MAX)
		await wait_until(func() -> bool:
				return _wet(x0 + 1, x0 + width, SKY_F - 1) == width, 4.0 + 0.4 * float(width))
		await wait(0.5)
		var wet: int = _wet(x0 + 1, x0 + width, SKY_F - 1)
		parts.append("%d клеток → %d из %d" % [width, wet, width])
		if width <= scan_max:
			ok("яма %d клеток наполнилась целиком" % width, wet == width,
					"мокрых клеток дна %d из %d, дно %s" % [wet, width,
						str(_row_levels(x0 + 1, x0 + width, SKY_F - 1))])
		_clear(x0, x0 + width + 1, SKY_TOP, SKY_F)
	print("  ЗАМЕР ширина ямы (мокрых клеток дна): %s" % ", ".join(parts))


## Площадка без ям (#70): ровный пол FLAT_LEN клеток, по краям обрыв, а за
## обрывом в 4 клетках — стенки. Ряд над полом упирается в стенки, но пол до
## них обрывается: это ровная земля, а не яма. Льём воду в несколько мест —
## ни одна соседняя клетка не должна намокнуть даже плёнкой.
func _measure_flat() -> void:
	var x0: int = SKY_X0 + 6
	var x1: int = x0 + FLAT_LEN - 1
	for x in range(x0, x1 + 1):
		World.set_tile(x, SKY_F, IDs.T.STONE)
	for y in range(SKY_F - 3, SKY_F + 1):
		World.set_tile(x0 - 5, y, IDs.T.STONE)   # стенка за обрывом слева
		World.set_tile(x1 + 5, y, IDs.T.STONE)   # и справа
	var srcs: Array = []
	for k in 5:
		srcs.append(x0 + 4 + k * (FLAT_LEN - 9) / 4)
	for sx in srcs:
		World.set_fluid(Vector2i(int(sx), SKY_F - 1), World.FLUID_MAX)
	await wait(2.0)
	var film: int = 0
	var where: Array = []
	for x in range(x0, x1 + 1):
		if srcs.has(x):
			continue
		if World.fluid_level(Vector2i(x, SKY_F - 1)) > 0:
			film += 1
			where.append(x - x0)
	var cells: int = FLAT_LEN - srcs.size()
	print("  ЗАМЕР площадка без ям %d клеток: с плёнкой %d из %d клеток (%.0f %%)" % [
			FLAT_LEN, film, cells, 100.0 * float(film) / float(cells)])
	ok("площадка без ям: плёнки нет (доля 0)", film == 0, "мокрые клетки %s" % str(where))
	var stay: bool = true
	for sx in srcs:
		if World.fluid_level(Vector2i(int(sx), SKY_F - 1)) != World.FLUID_MAX:
			stay = false
	ok("площадка без ям: вода стоит, где налили", stay)
	_clear(x0 - 5, x1 + 5, SKY_TOP, SKY_F)


## Яма с разрывом в полу (#70): яма GAP_PIT клеток, посередине пола шахта
## шириной 2 и глубиной 6. Льём у левой стенки по две порции на клетку дна —
## вода должна уйти в шахту, а не стоять в яме. Шире FLUID_GAP разрыв делит
## яму на две ровные площадки: это граница правила, её только меряем.
func _measure_gap_pit() -> void:
	for hole in [2, 4]:
		var hw: int = int(hole)
		var x0: int = SKY_X0 + 2
		_build_pit(x0, GAP_PIT, 2)
		var h0: int = x0 + 1 + GAP_PIT / 2 - hw / 2   # левая клетка шахты
		for y in range(SKY_F, SKY_F + 7):
			World.set_tile(h0 - 1, y, IDs.T.STONE)
			World.set_tile(h0 + hw, y, IDs.T.STONE)
			for x in range(h0, h0 + hw):
				World.set_tile(x, y, IDs.T.STONE if y == SKY_F + 6 else IDs.T.AIR)
		var pour: Vector2i = Vector2i(x0 + 1, SKY_F - 2)
		var poured: int = 0   # сколько порций реально добавили (клетка могла быть не пуста)
		# Широкий разрыв воду не принимает: вода стоит у стенки, ждём недолго.
		var drains: bool = hw <= gap_max
		for i in (2 * GAP_PIT) / World.FLUID_MAX:
			await wait_until(func() -> bool: return World.fluid_level(pour) == 0, 3.0 if drains else 1.0)
			poured += World.FLUID_MAX - World.fluid_level(pour)
			World.set_fluid(pour, World.FLUID_MAX)
		await wait_until(func() -> bool:
				return _sum(x0 + 1, x0 + GAP_PIT, SKY_F - 2, SKY_F - 1) == 0, 20.0 if drains else 3.0)
		await wait(0.5)
		var left: int = _sum(x0 + 1, x0 + GAP_PIT, SKY_F - 2, SKY_F - 1)
		var shaft: int = _sum(h0, h0 + hw - 1, SKY_F, SKY_F + 5)
		print("  ЗАМЕР яма %d клеток, разрыв в полу %d клетки: налито %d порций, в шахте %d, осталось в яме %d (видимой воды клеток дна %d)" % [
				GAP_PIT, hw, poured, shaft, left, _wet(x0 + 1, x0 + GAP_PIT, SKY_F - 1)])
		if drains:
			ok("яма с разрывом в полу: вода ушла в разрыв", shaft == poured,
					"в шахте %d из %d" % [shaft, poured])
			ok("яма с разрывом в полу: в яме вода не стоит", left == 0,
					"в яме %d порций, дно %s" % [left,
						str(_row_levels(x0 + 1, x0 + GAP_PIT, SKY_F - 1))])
		_clear(x0, x0 + GAP_PIT + 1, SKY_TOP, SKY_F + 6)


## Малая порция в широкой замкнутой впадине (#147): впадина PUDDLE_PIT клеток
## с ровным дном, посередине льём сначала 2 порции, потом 8. Воды мало на всё
## дно — она должна стоять видимой компактной лужей (каждая мокрая клетка не
## меньше FLUID_VISIBLE), а не растечься невидимой плёнкой по 1 порции.
func _measure_small_puddle() -> void:
	var parts: Array = []
	for amount in [2, 8]:
		var v: int = int(amount)
		var x0: int = SKY_X0 + 2
		_build_pit(x0, PUDDLE_PIT, 2)
		var src: Vector2i = Vector2i(x0 + 1 + PUDDLE_PIT / 2, SKY_F - 1)
		World.set_fluid(src, v)
		await wait(2.5)
		var levels: Array = _row_levels(x0 + 1, x0 + PUDDLE_PIT, SKY_F - 1)
		var wet: int = 0      # клеток с водой (любой уровень)
		var film: int = 0     # из них невидимых (1 порция)
		var first: int = -1
		var last: int = -1
		for i in levels.size():
			var lv: int = int(levels[i])
			if lv <= 0:
				continue
			wet += 1
			if lv < World.FLUID_VISIBLE:
				film += 1
			if first < 0:
				first = i
			last = i
		var total: int = _sum(x0 + 1, x0 + PUDDLE_PIT, SKY_F - 1, SKY_F - 1)
		var visible: int = _wet(x0 + 1, x0 + PUDDLE_PIT, SKY_F - 1)
		parts.append("%d порций → мокрых клеток %d, видимых %d, плёнки %d" % [v, wet, visible, film])
		var dump: String = "дно %s" % str(levels)
		ok("впадина %d, %d порций: вода не потерялась" % [PUDDLE_PIT, v], total == v,
				"порций %d, %s" % [total, dump])
		ok("впадина %d, %d порций: видимая лужа, а не плёнка" % [PUDDLE_PIT, v],
				visible >= 1 and film == 0, dump)
		ok("впадина %d, %d порций: лужа компактная (одним куском, не шире %d клеток)" % [
				PUDDLE_PIT, v, v / World.FLUID_VISIBLE],
				wet <= v / World.FLUID_VISIBLE and last - first + 1 == wet, dump)
		_clear(x0, x0 + PUDDLE_PIT + 1, SKY_TOP, SKY_F)
	print("  ЗАМЕР малая лужа во впадине %d клеток: %s" % [PUDDLE_PIT, "; ".join(parts)])


## Больше всего клеток сканирования за один шаг воды (0, если счётчика нет).
func _scan_tick_max() -> int:
	var v = World.get("fluid_scan_tick_max")
	return int(v) if v != null else 0


## Яма в небе: пол на ряду SKY_F, стенки по краям, inner клеток внутри.
func _build_pit(x0: int, inner: int, depth: int) -> void:
	for x in range(x0, x0 + inner + 2):
		World.set_tile(x, SKY_F, IDs.T.STONE)
	for y in range(SKY_F - depth, SKY_F):
		World.set_tile(x0, y, IDs.T.STONE)
		World.set_tile(x0 + inner + 1, y, IDs.T.STONE)


## Расчистить прямоугольник (включительно): воздух и ни капли воды.
func _clear(x0: int, x1: int, y0: int, y1: int) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if World.get_tile(x, y) != IDs.T.AIR:
				World.set_tile(x, y, IDs.T.AIR)
			World.set_fluid(Vector2i(x, y), 0)


## Сколько клеток ряда держат видимую воду (2 порции и больше).
func _wet(x0: int, x1: int, y: int) -> int:
	var n: int = 0
	for x in range(x0, x1 + 1):
		if World.fluid_level(Vector2i(x, y)) >= World.FLUID_VISIBLE:
			n += 1
	return n


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


## Ищем сухое ровное место подальше от базы: рядом не должно быть ни
## настоящей воды, ни построек — иначе замеры «плёнки» зависели бы от рельефа.
func _find_spot() -> int:
	var bx: int = World.beacon_cell.x
	for x in range(PAD_L + 2, World.W - PAD_R - 2):
		if x > bx - 46 and x < bx + 50:
			continue
		if World.surface[x] > World.SEA_LEVEL:
			continue
		var dry: bool = true
		for c in range(x - PAD_L, x + PAD_R + 1):
			if c < 0 or c >= World.W:
				dry = false
				break
			if World.surface[c] > World.SEA_LEVEL:
				dry = false
				break
		if dry:
			return x
	return -1


## Канавы по краям полки: MOAT клеток без пола в ряду g (на дне — земля).
## Слева — между краем полки и источником (а), справа — за пробой (в) и
## впадиной (г). dig = false засыпает их обратно.
func _set_moats(x: int, g: int, dig: bool) -> void:
	const MOAT: int = 3
	for c in range(x - 10, x - 10 + MOAT) + range(x + PAD_R - MOAT + 1, x + PAD_R + 1):
		World.set_fluid(Vector2i(c, g), 0)
		World.set_tile(c, g, IDs.T.AIR if dig else IDs.T.GRASS)


## Строим площадку: ровный пол в три ряда (чтобы яма была с настоящим дном)
## и чистое пространство над ним (ни стен, ни мха, ни деревьев).
func _build_platform(x: int, g: int) -> void:
	for c in range(x - PAD_L, x + PAD_R + 1):
		World.set_tile(c, g, IDs.T.GRASS)
		World.set_tile(c, g + 1, IDs.T.DIRT)
		World.set_tile(c, g + 2, IDs.T.DIRT)
		for y in range(g - 13, g):
			World.set_tile(c, y, IDs.T.AIR)
