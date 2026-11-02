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
## Команда:
##   godot --headless --path . -- --scenario=fluid_pools --seed=31337

const PAD_L: int = 13          # колонок запаса слева от площадки
const PAD_R: int = 13          # колонок запаса справа от площадки
const FILM_X: int = -4         # колонка источника для проверки плёнки
const POCKET_X: int = 8        # колонка источника в замкнутой впадине


func run() -> void:
	await wait(0.3)
	var steps0: int = World.fluid_steps
	var scans0: int = World.fluid_scan_cells
	var x: int = _find_spot()
	ok("нашлось ровное сухое место", x >= 0, "колонка %d" % x)
	if x < 0:
		finish()
		return
	var g: int = World.surface[x]
	_build_platform(x, g)

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
	# просмотренных клеток.
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
	ok("замер: озеро 25x4 — худший кадр %.1f мс, средний %.1f мс, шагов воды %d, просмотрено клеток %d" % [
			worst, sum / 180.0, World.fluid_steps - steps,
			World.fluid_scan_cells - scans], true)


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


## Строим площадку: ровный пол в три ряда (чтобы яма была с настоящим дном)
## и чистое пространство над ним (ни стен, ни мха, ни деревьев).
func _build_platform(x: int, g: int) -> void:
	for c in range(x - PAD_L, x + PAD_R + 1):
		World.set_tile(c, g, IDs.T.GRASS)
		World.set_tile(c, g + 1, IDs.T.DIRT)
		World.set_tile(c, g + 2, IDs.T.DIRT)
		for y in range(g - 13, g):
			World.set_tile(c, y, IDs.T.AIR)
