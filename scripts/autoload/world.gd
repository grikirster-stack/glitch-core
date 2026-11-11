extends Node2D
## Мир: тайловая сетка, процедурная генерация, физика тайлов, реестр построек.

const W: int = 640
const H: int = 180
const SEA_LEVEL: int = 52
const TILE: int = 16

const TREE_CHANCE: float = 0.10      # шанс дерева на колонку (до учёта зазора)
const TREE_MIN_GAP: int = 6          # минимум колонок между соседними стволами

const FLUID_MAX: int = 8             # сколько порций воды помещается в клетке
const FLUID_STEP: float = 0.05       # период шага симуляции воды, сек
const FLUID_VISIBLE: int = 2         # с какого уровня вода видна: 1 порция — плёнка, тайл AIR
## Замкнутая яма (#45, #70): вода растекается по ровному дну, только если
## ряд над этим дном упирается в стенки с обеих сторон, а пол под рядом
## не обрывается. Стенку ищем вдоль всей площадки до первого разрыва в полу —
## шире FLUID_GAP клеток без опоры подряд. Разрыв значит «площадка кончилась»:
## это ровная земля у обрыва, а не яма, и вода стоит на месте. Ямка уже или
## равная FLUID_GAP — это ямка в дне: яму она не открывает, вода стекает в неё.
## Замер (сценарии fluid и fluid_pools, #70): ямы 12–48 клеток наполняются
## целиком, на ровной площадке без ям плёнки нет (0 клеток), вода из ямы
## уходит в шахту шириной 2. Доля колонок поверхности «в яме» при FLUID_GAP
## 0 / 1 / 2 / 3 / 4 — 41–46 / 47–50 / 54–57 / 60–61 / 66–67 % (у прежнего
## ряда с лимитом 16 было 85–91 %). 2 — шахта, которую копает игрок
## (1–2 клетки), ещё ямка в дне; шире — уже обрыв.
const FLUID_GAP: int = 2
## Жёсткий предел поиска стенки, клеток в каждую сторону: дальше — «не яма»,
## даже если пол не обрывается. Яма шире предела наполняется не целиком.
## Замер (fluid_pools): в яме 48 клеток за шаг воды просматривается не больше
## ~2300 клеток (~0.7 мс при 300 нс на клетку), на озере 25×4 — не больше
## ~230, как и при прежнем ряде в 16 клеток: разрыв в полу обрывает поиск
## раньше предела. 64 — вчетверо больше прежнего ряда в 16 клеток.
const FLUID_SCAN: int = 64

const LIGHT_CHUNK: int = 8            # размер чанка пространственного хэша света (клетки)
const LIGHT_MIN: float = 0.05         # минимальный свет тайла, дающий источник
const LIGHT_BASE_RADIUS: float = 46.0 # базовый радиус свечения тайла
const LIGHT_RADIUS_PER_POWER: float = 60.0
const LIGHT_CHUNKS_X: int = (W + LIGHT_CHUNK - 1) / LIGHT_CHUNK  # чанков по ширине
const LIGHT_CHUNKS_Y: int = (H + LIGHT_CHUNK - 1) / LIGHT_CHUNK  # чанков по высоте

var world_seed: int = 0
var tiles: PackedByteArray = PackedByteArray()
var surface: PackedInt32Array = PackedInt32Array()
var tilemap: TileMapLayer = null
## Декор-слой флоры (ADR-003 V2): только картинка, из сида и тайлов (scripts/world/decor.gd).
var decor: TileMapLayer = null

var terminals: Array[Vector2i] = []
## Какую главу журнала выдаёт терминал: клетка -> номер главы (0..8). Терминалы
## базы — главы 0–1, терминал i-й руины — глава Lore.BASE_TERMINALS + i (#29).
var terminal_chapters: Dictionary = {}
var vents: Array[Vector2i] = []
var beacon_cell: Vector2i = Vector2i.ZERO
var spawn_point: Vector2 = Vector2.ZERO
var lights: Array[Dictionary] = []
var machines: Dictionary = {}       # Vector2i -> Node (машина)
var belts: Dictionary = {}         # Vector2i -> {dir:int, items:Array}
## Лучи света (ADR-005, #164). Перестраиваются в _process, не чаще раза в кадр.
var beams: Beams = Beams.new()
## Ручки света луча: клетка → источник World.add_light_source. Снимаются целиком
## при перестроении, чтобы погасшие клетки не продолжали светить.
var _beam_lights: Dictionary = {}
var astar: AStarGrid2D = null
var gen_stats: Dictionary = {}     # замеры последней генерации мира

# --- Реестр источников света -------------------------------------------------
# _light_cells: Vector2i клетка -> источник света, даваемый тайлом.
# _light_chunks: индекс чанка -> Array источников света внутри чанка.
# _light_flat: индекс чанка -> PackedFloat32Array (x, y, r², power) — зеркало
# чанка для быстрого light_at: в горячем цикле словари не трогаем.
# Чанки хранятся в обычных массивах, а не в словаре: индекс считается
# арифметикой, без хеширования Vector2i.
# Реестр нужен, чтобы обновлять свет точечно, а не пересобирать весь мир.
var _light_cells: Dictionary = {}
var _light_chunks: Array = []
var _light_flat: Array = []
var _light_max_radius: float = 0.0  # максимальный радиус источника в мире
var _light_reach: int = 1           # на сколько чанков в сторону достаёт этот радиус
var _tile_light_pow: PackedFloat32Array = PackedFloat32Array()  # свет тайла по id
var _atlas_cache: Array = []          # id тайла -> координаты в атласе
var _trees: int = 0

# --- Вода ---------------------------------------------------------------------
# fluid: уровень воды в клетке, 0..FLUID_MAX. Ноль — клетка сухая.
# Уровень нужен, чтобы отличать «в клетке стоит вода» от «в клетке её полно»:
# без уровней вода не умеет растекаться ровным слоем и не может заполнить
# яму снизу вверх.
var fluid: PackedByteArray = PackedByteArray()
var _fluid_queue: PackedInt32Array = PackedInt32Array()  # клетки на пересчёт
var _fluid_queued: PackedByteArray = PackedByteArray()   # флаг «уже в очереди»
var _fluid_timer: float = 0.0
# Замеры воды (сценарий fluid, замеры в PR): сколько стоит симуляция.
var fluid_ticks: int = 0        # шагов симуляции с непустой очередью
var fluid_steps: int = 0        # пересчётов клеток (вызовов _fluid_step_cell)
var fluid_scan_cells: int = 0   # клеток, просмотренных сканированием вбок
var fluid_tick_us: int = 0      # суммарное время шагов, мкс
var fluid_tick_us_max: int = 0  # самый дорогой шаг, мкс
var fluid_scan_tick_max: int = 0  # больше всего клеток сканирования за один шаг (#70)


func _ready() -> void:
	_build_tileset()
	_build_tile_light_table()
	_build_atlas_cache()
	_build_defense_tables()
	_reset_light_chunks()
	_reset_fluid()


## Кэш света тайлов по id — чтобы не лезть в словарь DB в горячих циклах.
func _build_tile_light_table() -> void:
	_tile_light_pow.resize(IDs.TILE_COUNT)
	for id in range(IDs.TILE_COUNT):
		_tile_light_pow[id] = DB.tile_light(id)


## Кэш координат атласа по id тайла: поиск в словаре на каждой клетке дорогой.
## _atlas_cache — «лицо» тайла, _atlas_var — все варианты (ADR-003 V1).
func _build_atlas_cache() -> void:
	_atlas_cache.clear()
	for id in range(IDs.TILE_COUNT):
		_atlas_cache.append(DB.atlas_of_tile.get(id, Vector2i(-1, -1)))
	_atlas_var = DB.atlas_var
	_open_tbl.resize(IDs.TILE_COUNT)
	for id in range(IDs.TILE_COUNT):
		_open_tbl[id] = 0 if DB.tile_solid(id) else 1


func _build_tileset() -> void:
	var ts: TileSet = TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	var src: TileSetAtlasSource = TileSetAtlasSource.new()
	src.texture = DB.atlas_texture
	src.texture_region_size = Vector2i(TILE, TILE)
	for ac in DB.atlas_cells:
		src.create_tile(ac)
	ts.add_source(src, 0)
	tilemap = TileMapLayer.new()
	tilemap.name = "Tiles"
	tilemap.tile_set = ts
	add_child(tilemap)
	decor = preload("res://scripts/world/decor.gd").new()   # ADR-003 V2: декор-слой флоры
	add_child(decor)


# ------------------------------------------------------------ ГЕНЕРАЦИЯ

func generate(p_seed: int) -> void:
	var t_start: int = Time.get_ticks_usec()
	world_seed = p_seed
	if _tile_light_pow.size() < IDs.TILE_COUNT:
		_build_tile_light_table()
	if _atlas_cache.size() < IDs.TILE_COUNT:
		_build_atlas_cache()
	if _psolid_tbl.size() < IDs.TILE_COUNT:
		_build_defense_tables()
	for m in machines.values():
		if is_instance_valid(m):
			m.queue_free()
	machines.clear()
	belts.clear()
	tiles = PackedByteArray()
	tiles.resize(W * H)
	tiles.fill(0)
	surface = PackedInt32Array()
	surface.resize(W)
	terminals.clear()
	terminal_chapters.clear()
	vents.clear()
	machines.clear()
	belts.clear()
	lights.clear()
	_light_cells.clear()
	_beam_lights.clear()
	if beams != null:
		beams.cells.clear()
		beams.segments.clear()
		# Словарь машин уже пуст, а плоская карта занятости — нет: иначе луч
		# нового забега упирается в клетки построек прошлого мира.
		beams.note_machines()
		beams.mark_dirty()
	_reset_light_chunks()
	_light_max_radius = 0.0
	_light_reach = 1
	_trees = 0
	_defense_reset()

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = world_seed

	var n_height: FastNoiseLite = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0065, 4, world_seed)
	var n_hill: FastNoiseLite = _noise(FastNoiseLite.TYPE_SIMPLEX, 0.021, 2, world_seed + 11)
	var n_c1: FastNoiseLite = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.042, 3, world_seed + 23)
	var n_c2: FastNoiseLite = _noise(FastNoiseLite.TYPE_SIMPLEX, 0.075, 2, world_seed + 37)
	var n_crystal: FastNoiseLite = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0085, 2, world_seed + 51)

	# --- 1. Высота поверхности -------------------------------------------------
	for x in range(W):
		var h: float = 44.0 + n_height.get_noise_1d(float(x)) * 15.0
		h += n_hill.get_noise_1d(float(x)) * 5.0
		surface[x] = clampi(int(round(h)), 16, H - 20)

	# --- 2. Заливка породы -----------------------------------------------------
	for x in range(W):
		var top: int = surface[x]
		var crystal_biome: bool = n_crystal.get_noise_1d(float(x)) > 0.34
		for y in range(top, H):
			var t: int = IDs.T.STONE
			if y == top:
				t = IDs.T.GRASS
			elif y <= top + 3:
				t = IDs.T.DIRT
			elif y >= H - 3:
				t = IDs.T.BEDROCK
			elif y == H - 4:
				t = IDs.T.SCRAP_ORE
			if crystal_biome and y > top + 2 and rng.randf() < 0.05:
				t = IDs.T.CRYSTAL_ORE
			tiles[y * W + x] = t
		# Песок у воды
		if top > SEA_LEVEL - 1:
			for y in range(maxi(top - 1, SEA_LEVEL - 3), mini(top + 4, H)):
				if tiles[y * W + x] == IDs.T.STONE or tiles[y * W + x] == IDs.T.DIRT:
					tiles[y * W + x] = IDs.T.SAND

	# --- 3. Пещеры ------------------------------------------------------------
	for x in range(W):
		var top: int = surface[x]
		for y in range(top + 4, H - 3):
			var fy: float = float(y) * 1.55
			var v1: float = n_c1.get_noise_2d(float(x), fy)
			var v2: float = n_c2.get_noise_2d(float(x) * 1.3, fy * 1.1)
			if v1 > 0.40 or v2 > 0.55:
				tiles[y * W + x] = IDs.T.AIR

	# --- 4. Норизонтальные тоннели (удобно строить базу) ----------------------
	var tunnels: int = 4
	for t in tunnels:
		var base_y: float = 92.0 + float(t) * 16.0 + rng.randf_range(-6.0, 6.0)
		var freq: float = rng.randf_range(0.018, 0.032)
		var phase: float = rng.randf_range(0.0, 10.0)
		for x in range(W):
			var ty: int = int(base_y + sin(float(x) * freq + phase) * 9.0)
			for dy in range(-2, 3):
				var y: int = ty + dy
				if y > surface[x] + 5 and y < H - 4:
					tiles[y * W + x] = IDs.T.AIR

	# --- 5. Жилы руд ----------------------------------------------------------
	var n_coal: FastNoiseLite = _noise(FastNoiseLite.TYPE_SIMPLEX, 0.13, 2, world_seed + 71)
	var n_copper: FastNoiseLite = _noise(FastNoiseLite.TYPE_SIMPLEX, 0.15, 2, world_seed + 83)
	var n_iron: FastNoiseLite = _noise(FastNoiseLite.TYPE_SIMPLEX, 0.16, 2, world_seed + 97)
	var n_crys: FastNoiseLite = _noise(FastNoiseLite.TYPE_SIMPLEX, 0.14, 2, world_seed + 109)
	var n_scrap: FastNoiseLite = _noise(FastNoiseLite.TYPE_SIMPLEX, 0.11, 2, world_seed + 131)

	for x in range(W):
		var top: int = surface[x]
		for y in range(top + 2, H - 3):
			var idx: int = y * W + x
			if tiles[idx] != IDs.T.STONE and tiles[idx] != IDs.T.DIRT and tiles[idx] != IDs.T.SAND:
				continue
			var depth: float = float(y - top) / float(H - top)
			var v: float = n_coal.get_noise_2d(float(x), float(y))
			if v > 0.60 and depth > 0.03:
				tiles[idx] = IDs.T.COAL_ORE
				continue
			v = n_scrap.get_noise_2d(float(x), float(y))
			if v > 0.66 and depth < 0.35:
				tiles[idx] = IDs.T.SCRAP_ORE
				continue
			v = n_copper.get_noise_2d(float(x), float(y))
			if v > 0.63 and depth > 0.06:
				tiles[idx] = IDs.T.COPPER_ORE
				continue
			v = n_iron.get_noise_2d(float(x), float(y))
			if v > 0.66 and depth > 0.22:
				tiles[idx] = IDs.T.IRON_ORE
				continue
			v = n_crys.get_noise_2d(float(x), float(y))
			if v > 0.70 and depth > 0.45:
				tiles[idx] = IDs.T.CRYSTAL_ORE

	# --- 6. Вода и лава -------------------------------------------------------
	for x in range(W):
		var top: int = surface[x]
		if top > SEA_LEVEL:
			for y in range(SEA_LEVEL, top):
				if tiles[y * W + x] == IDs.T.AIR:
					tiles[y * W + x] = IDs.T.WATER
	var n_lava: FastNoiseLite = _noise(FastNoiseLite.TYPE_SIMPLEX, 0.06, 2, world_seed + 149)
	for x in range(W):
		for y in range(126, H - 3):
			var idx: int = y * W + x
			if tiles[idx] == IDs.T.AIR and n_lava.get_noise_2d(float(x), float(y)) > 0.55:
				tiles[idx] = IDs.T.LAVA

	# --- 7. Деревья, трава, камни --------------------------------------------
	# Сначала деревья: крона занимает место над поверхностью, иначе мох и кристаллы
	# выросли бы сквозь неё.
	# Деревья не жмутся друг к другу: между соседними стволами держим
	# минимальный зазор, иначе лес превращается в сплошную стену.
	var last_tree_x: int = -TREE_MIN_GAP
	for x in range(2, W - 2):
		# Вокруг базы деревьев нет: площадку всё равно выровняют и вычистят.
		if absi(x - W / 2) <= 18:
			continue
		var top: int = surface[x]
		if get_tile(x, top) != IDs.T.GRASS:
			continue
		if x - last_tree_x < TREE_MIN_GAP:
			continue
		if rng.randf() < TREE_CHANCE:
			_place_tree(x, top, rng)
			last_tree_x = x
	# Трава и светящиеся кристаллы — только в пустые клетки над поверхностью.
	for x in range(2, W - 2):
		var top: int = surface[x]
		if get_tile(x, top) != IDs.T.GRASS:
			continue
		if get_tile(x, top - 1) != IDs.T.AIR:
			continue
		var r: float = rng.randf()
		if r < 0.045:
			set_tile_raw(x, top - 1, IDs.T.MOSS)
		elif r < 0.060:
			set_tile_raw(x, top - 1, IDs.T.LIGHT_CRYSTAL)

	# --- 8. Руины станции -----------------------------------------------------
	_clear_ruin_caches()
	var ruins: int = 7
	for i in ruins:
		var rx: int = int((float(i) + 0.5) / float(ruins) * float(W)) + rng.randi_range(-18, 18)
		rx = clampi(rx, 12, W - 20)
		if absi(rx - W / 2) < 34:
			rx = clampi(rx + 44, 12, W - 20)
		_place_ruin(rx, rng)

	# --- 9. База (релей) ------------------------------------------------------
	var bx: int = W / 2
	_flatten(bx, 17)
	_place_base(bx)

	# --- 10. Вентиляция -------------------------------------------------------
	_place_vents(rng)

	# --- 11. Страховка: ничего не должно висеть в воздухе --------------------
	_fix_floating_trees()

	# --- 11. Небесный тайник (#60): после деревьев, на своём ГСЧ -----------
	_place_sky_cache()

	# --- 11a. Вода: уровни по готовому миру ----------------------------------
	_init_fluid_from_tiles()

	# --- 12. Визуализация, свет, поиск пути ----------------------------------
	var t_sync: int = Time.get_ticks_usec()
	_build_biome_rows()
	_sync_all()
	var t_lights: int = Time.get_ticks_usec()
	_rebuild_lights()
	var t_astar: int = Time.get_ticks_usec()
	_build_astar()
	var t_end: int = Time.get_ticks_usec()
	spawn_point = Vector2(float((bx - 4) * TILE) + TILE * 0.5, float(surface[bx] * TILE) - 12.0)
	_reset_explored()   # туман войны (#59): закрыто всё, кроме старта
	_census_ores()      # бесконечная игра (#174): цель отрастания — эта перепись

	gen_stats = {
		"gen_ms": float(t_end - t_start) / 1000.0,
		"astar_ms": float(t_end - t_astar) / 1000.0,
		"sync_ms": float(t_lights - t_sync) / 1000.0,
		"lights_ms": float(t_astar - t_lights) / 1000.0,
		"lights_count": lights.size(),
		"trees": _trees,
	}
	print("[Мир] генерация: gen=%.0f мс astar=%.0f мс sync=%.0f мс свет=%.0f мс источников=%d деревьев=%d"
			% [gen_stats["gen_ms"], gen_stats["astar_ms"], gen_stats["sync_ms"],
			gen_stats["lights_ms"], gen_stats["lights_count"], gen_stats["trees"]])


## Сетка поиска пути для фантомов. Строится один раз, точечно обновляется при копке.
func _build_astar() -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, W, H)
	astar.cell_size = Vector2(TILE, TILE)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.update()
	# Локальная таблица твёрдости: раз в клетку вместо обращения к словарю DB.
	# Прямой вызов метода быстрее, чем вызов через Callable.
	# Для фантомов шлюз — стена всегда, даже открытый (#31): таблица phantom_solid.
	var solid_tbl: PackedByteArray = _psolid_tbl
	var grid: AStarGrid2D = astar
	for y in range(H):
		var row: int = y * W
		for x in range(W):
			if solid_tbl[tiles[row + x]] != 0:
				grid.set_point_solid(Vector2i(x, y), true)


func _update_astar(x: int, y: int) -> void:
	if astar == null:
		return
	if x < 0 or y < 0 or x >= W or y >= H:
		return
	astar.set_point_solid(Vector2i(x, y), _psolid_tbl[tiles[y * W + x]] != 0)


## Кэшированная таблица свойств тайлов — быстрее словарных запросов в DB.
func _tile_flag_table(want_solid: bool) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(IDs.TILE_COUNT)
	for id in range(IDs.TILE_COUNT):
		if want_solid:
			out[id] = 1 if DB.tile_solid(id) else 0
		else:
			out[id] = 1 if DB.tile_light(id) > LIGHT_MIN else 0
	return out


func _noise(type: int, freq: float, octaves: int, s: int) -> FastNoiseLite:
	var n: FastNoiseLite = FastNoiseLite.new()
	n.noise_type = type
	n.seed = s
	n.frequency = freq
	n.fractal_octaves = octaves
	n.fractal_lacunarity = 2.0
	n.fractal_gain = 0.5
	return n


# ------------------------------------------------------------ ДЕРЕВЬЯ

## Ставит дерево: высокий узкий ствол и круглая крона.
##
## Форма: ствол в одну клетку шириной и высотой 5–8 брёвен, сверху крона из
## листвы шириной 3 или 5 клеток. Ствол узкий — мимо дерева можно пройти;
## крона начинается высоко — под ней тоже можно пройти.
##
## Листва нависает над землёй: для дерева это нормально. Связана она всегда:
## каждый лист стоит на бревне, на другом листе или рядом с ними, а по цепочке —
## со стволом, стоящим на земле (см. _fix_floating_trees и floating_tree_cells).
##
## ADR-003 V2: это «Свечник» — ствол рисуется стеблем, каждый ряд кроны — шляпкой
## с просветом (DB._flora_tile), стебель в просветах — декор-слой. Расстановка
## клеток и расход ГСЧ не меняются: мир того же сида не сдвигается.
func _place_tree(x: int, ground: int, rng: RandomNumberGenerator) -> void:
	# Опора: под стволом сплошной грунт, сверху пусто.
	if not DB.tile_solid(get_tile(x, ground)):
		return
	if get_tile(x, ground - 1) != IDs.T.AIR:
		return
	# Ширина кроны: 3 (1) или 5 (2) клеток в сторону.
	var crown_w: int = rng.randi_range(1, 2)
	# Земля вокруг ствола не должна обваливаться: иначе крона повиснет над
	# обрывом и дерево будет выглядеть криво.
	for c in range(x - crown_w, x + crown_w + 1):
		if c < 1 or c >= W - 1:
			return
		if absi(surface[c] - ground) > 1:
			return
	# Высота ствола: чем выше, тем дальше от земли крона.
	var trunk_h: int = rng.randi_range(5, 8)
	var top: int = ground - trunk_h
	# Место под ствол должно быть свободно — иначе ствол вырастет из воздуха.
	for y in range(ground - 1, top - 1, -1):
		if get_tile(x, y) != IDs.T.AIR:
			return
	# Слои кроны снизу вверх: широкие посередине, узкие сверху и снизу — крона
	# получается круглой, а не прямоугольной.
	var layers: Array[int] = [crown_w - 1, crown_w, crown_w, crown_w - 1, crown_w - 2]
	# Проверяем, что место под крону свободно: иначе крона выйдет рваной.
	for i in range(layers.size()):
		var w: int = layers[i]
		if w < 0:
			break
		var row: int = top - i
		for c in range(x - w, x + w + 1):
			if c == x and row == top:
				continue # место верхнего бревна
			if get_tile(c, row) != IDs.T.AIR:
				return
	# Ствол: сплошной столб брёвен от земли до верха.
	# Ствол — тайл TREE: он не твёрдый, сквозь него можно пройти.
	for y in range(ground - 1, top - 1, -1):
		set_tile_raw(x, y, IDs.T.TREE)
	# Крона: слои листвы снизу вверх.
	for i in range(layers.size()):
		var w2: int = layers[i]
		if w2 < 0:
			break
		var row2: int = top - i
		for c in range(x - w2, x + w2 + 1):
			if c == x and row2 == top:
				continue
			set_tile_raw(c, row2, IDs.T.LEAVES)
	_trees += 1


## Клетки, которые висят в воздухе: стволы без грунта под ними и листва, не
## связанная с землёй. Пусто — значит всё дерево держится на земле.
##
## Связность, а не «под каждой клеткой что-то твёрдое»: ствол TREE не твёрдый
## (сквозь него проходят), и клетка ствола опирается на клетку ствола ниже,
## а не на землю напрямую.
func floating_tree_cells() -> Array:
	var bad: Array = []
	var attached: Dictionary = {}
	var roots: Array[Vector2i] = []
	# Деревья растут над поверхностью: глубже смотреть незачем.
	var max_top: int = 0
	for x in range(W):
		max_top = maxi(max_top, surface[x])
	var limit: int = mini(max_top + 14, H - 1)
	for x in range(W):
		for y in range(limit):
			if get_tile(x, y) != IDs.T.TREE:
				continue
			if not DB.tile_solid(get_tile(x, y + 1)):
				continue # ствол не стоит на грунте — это не корень
			attached[Vector2i(x, y)] = true
			roots.append(Vector2i(x, y))
	# Обход в ширину: от стволов по стволам и листве.
	var queue: Array[Vector2i] = roots.duplicate()
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if attached.has(n):
				continue
			var t: int = get_tile(n.x, n.y)
			if t != IDs.T.TREE and t != IDs.T.LEAVES:
				continue
			attached[n] = true
			queue.append(n)
	# Всё, что осталось непривязанным, — висящие стволы и листва.
	for x in range(W):
		for y in range(limit):
			var t: int = get_tile(x, y)
			if t != IDs.T.TREE and t != IDs.T.LEAVES:
				continue
			if not attached.has(Vector2i(x, y)):
				bad.append(Vector2i(x, y))
	return bad


## Страховка после расстановки построек: убирает стволы и листву, не связанные
## с землёй. Крона, нависающая над землёй, остаётся на месте.
func _fix_floating_trees() -> void:
	for c in floating_tree_cells():
		set_tile_raw(c.x, c.y, IDs.T.AIR)


## Убирает то, что повисло после того, как игрок сломал часть дерева.
##
## Считает связность в окрестности скола: ствол и крона, которые больше не
## связаны с землёй, исчезают. Смотрим только рядом с местом раскола —
## перебирать весь мир на каждый скол слишком дорого.
func fix_floating_near(cell: Vector2i) -> void:
	var x0: int = maxi(cell.x - 10, 0)
	var x1: int = mini(cell.x + 10, W - 1)
	var y0: int = maxi(cell.y - 18, 0)
	var y1: int = mini(cell.y + 2, H - 1)
	var attached: Dictionary = {}
	var roots: Array[Vector2i] = []
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			var t: int = get_tile(x, y)
			if t != IDs.T.TREE and t != IDs.T.LEAVES:
				continue
			if DB.tile_solid(get_tile(x, y + 1)):
				attached[Vector2i(x, y)] = true
				roots.append(Vector2i(x, y))
	var queue: Array[Vector2i] = roots.duplicate()
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.x < x0 or n.x > x1 or n.y < y0 or n.y > y1:
				continue
			if attached.has(n):
				continue
			var t: int = get_tile(n.x, n.y)
			if t != IDs.T.TREE and t != IDs.T.LEAVES:
				continue
			attached[n] = true
			queue.append(n)
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			var t: int = get_tile(x, y)
			if t != IDs.T.TREE and t != IDs.T.LEAVES:
				continue
			if not attached.has(Vector2i(x, y)):
				set_tile(x, y, IDs.T.AIR)


func _flatten(cx: int, half: int) -> void:
	## Расчищает площадку под базу: ровный грунт и открытое небо над ней.
	var base: int = H
	for x in range(cx - half, cx + half + 1):
		if x < 0 or x >= W:
			continue
		base = mini(base, surface[x])
	for x in range(cx - half, cx + half + 1):
		if x < 0 or x >= W:
			continue
		surface[x] = base
		for y in range(0, base):
			set_tile_raw(x, y, IDs.T.AIR)
		for y in range(base, mini(H, base + 16)):
			if y == base:
				set_tile_raw(x, y, IDs.T.GRASS)
			elif y <= base + 3:
				set_tile_raw(x, y, IDs.T.DIRT)
			else:
				set_tile_raw(x, y, IDs.T.STONE)


func _place_ruin(cx: int, rng: RandomNumberGenerator) -> void:
	var half: int = rng.randi_range(3, 6)
	var base: int = surface[clampi(cx, 0, W - 1)]
	for x in range(cx - half, cx + half + 1):
		if x < 1 or x >= W - 1:
			continue
		if base > 0 and base < H - 1:
			set_tile_raw(x, base, IDs.T.STEEL)
	# Нижний ряд (base - 1): терминал у правого края, лампа в центре, окна.
	# Их колонки стены обходят: раньше стены заполняли весь ряд, и окна, лампа
	# и терминал руины не ставились ни на одном сиде (#29).
	var tx: int = mini(cx + half - 1, W - 2)
	var low: Dictionary = {tx: IDs.T.TERMINAL}
	if not low.has(cx):
		low[cx] = IDs.T.LIGHT_CRYSTAL
	for i in 3:
		var wx: int = cx - half + 1 + i * 2
		if wx > cx - half and wx < cx + half and not low.has(wx):
			low[wx] = IDs.T.GLASS
	# Стены (ГСЧ зовётся на каждую колонку, как раньше: остальной мир не сдвигается)
	for x in range(cx - half, cx + half + 1):
		var hgt: int = rng.randi_range(1, 3)
		if low.has(x):
			continue
		for i in hgt:
			if get_tile(x, base - 1 - i) == IDs.T.AIR:
				set_tile_raw(x, base - 1 - i, IDs.T.PANEL)
	for x in low.keys():
		if int(low[x]) != IDs.T.TERMINAL and get_tile(int(x), base - 1) == IDs.T.AIR:
			set_tile_raw(int(x), base - 1, int(low[x]))
	# Терминал (задание, глава журнала руины) ставится всегда; над ним — проход.
	set_tile_raw(tx, base - 1, IDs.T.TERMINAL)
	for y in range(base - 3, base - 1):
		if DB.tile_solid(get_tile(tx, y)):
			set_tile_raw(tx, y, IDs.T.AIR)
	terminals.append(Vector2i(tx, base - 1))
	terminal_chapters[Vector2i(tx, base - 1)] = Lore.BASE_TERMINALS + ruin_caches.size()
	# Хлам
	for i in 4:
		var sx: int = clampi(cx + rng.randi_range(-half, half), 1, W - 2)
		var sy: int = base - 1
		if get_tile(sx, sy) == IDs.T.AIR:
			set_tile_raw(sx, sy, IDs.T.SCRAP_ORE)
	# Тайник и табличка (ADR-001 § 4.9, #35)
	_place_ruin_cache(ruin_caches.size(), cx, base, half)


# ------------------------------------------------------------ ТАЙНИКИ РУИН
# В каждой руине — сундук хозяина руины (Lore.ruin_owner) с 3–6 предметами
# по его роли и табличка с именем места (Lore.place_name("ruin", i)).
# Содержимое считается своим ГСЧ от сида мира и номера руины: поток случайных
# чисел генерации мира не сдвигается, остальной мир остаётся прежним.

const RUIN_CACHE_MIN: int = 3          # минимум разных предметов в тайнике
const RUIN_CACHE_MAX: int = 6          # максимум разных предметов в тайнике
const RUIN_CACHE_SALT: int = 0x52554E53  # «RUNS»: свой поток случайных чисел
## Что хозяин руины хранил у себя: роль → [[предмет, мин, макс], ...]. В пуле
## не меньше RUIN_CACHE_MAX позиций, чтобы тайник набирался без повторов.
const RUIN_LOOT: Dictionary = {
	"капитан": [[IDs.I.POWER_CELL, 1, 2], [IDs.I.CIRCUIT, 2, 4], [IDs.I.STEEL_PLATE, 2, 4],
			[IDs.I.IRON_PLATE, 3, 6], [IDs.I.LAMP, 1, 3], [IDs.I.SOLAR, 1, 1]],
	"инженер": [[IDs.I.COPPER_PLATE, 4, 8], [IDs.I.IRON_PLATE, 4, 8], [IDs.I.STEEL_PLATE, 2, 4],
			[IDs.I.BELT, 4, 10], [IDs.I.DRILL, 1, 1], [IDs.I.ASSEMBLER, 1, 1]],
	"медик": [[IDs.I.SCRAP, 4, 10], [IDs.I.GLASS, 3, 6], [IDs.I.SAND, 4, 8],
			[IDs.I.LAMP, 1, 2], [IDs.I.POWER_CELL, 1, 1], [IDs.I.CRYSTAL, 1, 3]],
	"геолог": [[IDs.I.COPPER_ORE, 6, 12], [IDs.I.IRON_ORE, 6, 12], [IDs.I.CRYSTAL, 2, 5],
			[IDs.I.COAL, 6, 12], [IDs.I.STONE, 6, 12], [IDs.I.DRILL, 1, 1]],
	"связист": [[IDs.I.CIRCUIT, 2, 5], [IDs.I.COPPER_PLATE, 3, 6], [IDs.I.COPPER_INGOT, 3, 6],
			[IDs.I.CRYSTAL, 2, 4], [IDs.I.GLASS, 2, 4], [IDs.I.SOLAR, 1, 1]],
	"пилот": [[IDs.I.COAL, 8, 16], [IDs.I.POWER_CELL, 1, 2], [IDs.I.IRON_INGOT, 3, 6],
			[IDs.I.STEEL_PLATE, 2, 4], [IDs.I.COAL_GEN, 1, 1], [IDs.I.LAMP, 1, 3]],
	"техник": [[IDs.I.IRON_INGOT, 3, 6], [IDs.I.COPPER_INGOT, 3, 6], [IDs.I.BELT, 6, 12],
			[IDs.I.CHEST, 1, 2], [IDs.I.IRON_PLATE, 3, 6], [IDs.I.SMELTER, 1, 1]],
}

## Тайники текущего мира, по одному на руину, в порядке генерации:
## {index, cell, chest, sign, sign_cell, name, role, owner}.
var ruin_caches: Array = []
var ruin_cache_ms: float = 0.0         # сколько генерация тайников добавила к gen_ms


## Табличка у руины: столбик с дощечкой. Имя места проступает при подходе героя,
## при первом подходе оно же приходит подсказкой в HUD (Game.notify).
class RuinSign extends Node2D:
	const SHOW_DIST: float = 160.0     # 10 клеток: руина шире 13 клеток, тайник — у середины
	var title: String = ""
	var alpha: float = 0.0
	var announced: bool = false

	func _process(delta: float) -> void:
		var p = UI.player
		var near: bool = p != null and is_instance_valid(p) \
				and p.global_position.distance_to(global_position) < SHOW_DIST
		var a: float = move_toward(alpha, 1.0 if near else 0.0, delta * 3.0)
		if a != alpha:
			alpha = a
			queue_redraw()
		if near and not announced:
			announced = true
			Game.notify("Руина: «%s»" % title, Color(1.0, 0.92, 0.7))

	func _draw() -> void:
		draw_rect(Rect2(-1.0, -3.0, 2.0, 11.0), Color(0.35, 0.33, 0.30))
		draw_rect(Rect2(-7.0, -9.0, 14.0, 7.0), Color(0.55, 0.52, 0.45))
		draw_rect(Rect2(-6.0, -8.0, 12.0, 1.0), Color(0.25, 0.24, 0.22))
		draw_rect(Rect2(-6.0, -5.0, 9.0, 1.0), Color(0.25, 0.24, 0.22))
		if alpha <= 0.01:
			return
		var font: Font = ThemeDB.fallback_font
		var w: float = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		draw_string(font, Vector2(-w * 0.5, -12.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 8,
				Color(1.0, 0.95, 0.75, alpha))


## Убирает тайники и таблички прошлого мира (сундуки уходят вместе с machines).
func _clear_ruin_caches() -> void:
	for c in ruin_caches:
		if is_instance_valid(c["sign"]):
			c["sign"].queue_free()
	ruin_caches.clear()
	ruin_cache_ms = 0.0


## Подарок терминала главы chapter: [[предмет, число], ...], 2–3 вида из
## Balance.TERMINAL_GIFT_POOL. Роль места (капитан, инженер, … — как у тайника
## руины) выбирает, какие виды; на базе роли нет — берётся «капитан» и «инженер».
## Зависит только от сида мира и номера главы: тот же терминал — тот же подарок.
func terminal_gift(chapter: int) -> Array:
	var role: String = _terminal_gift_role(chapter)
	var pool: Array = Balance.TERMINAL_GIFT_POOL.duplicate()
	var r: RandomNumberGenerator = RandomNumberGenerator.new()
	r.seed = int(world_seed) ^ 0x47494654 ^ (chapter * 7919) ^ (role.hash() & 0xFFFF)
	var n: int = mini(r.randi_range(Balance.TERMINAL_GIFT_MIN, Balance.TERMINAL_GIFT_MAX), pool.size())
	# Роль сдвигает пул: у каждой — свой «любимый» первый предмет, дальше по кругу.
	var shift: int = posmod(role.hash(), pool.size())
	var rotated: Array = []
	for k in pool.size():
		rotated.append(pool[(k + shift) % pool.size()])
	# Фишер — Йейтс на своём ГСЧ, но первые два места роли трогаем реже: мешаем хвост.
	for k in range(rotated.size() - 1, 1, -1):
		var j: int = r.randi_range(1, k)
		var tmp = rotated[k]
		rotated[k] = rotated[j]
		rotated[j] = tmp
	var out: Array = []
	for k in n:
		var e: Array = rotated[k]
		out.append([int(e[0]), r.randi_range(int(e[1]), int(e[2]))])
	return out


## Роль места терминала главы: руина — роль хозяина, база — по номеру главы.
func _terminal_gift_role(chapter: int) -> String:
	if chapter >= Lore.BASE_TERMINALS:
		var owner: Dictionary = Lore.ruin_owner(chapter - Lore.BASE_TERMINALS)
		var role: String = String(owner.get("role", ""))
		if role != "":
			return role
	return "капитан" if posmod(chapter, 2) == 0 else "инженер"


## Содержимое тайника i-й руины: [[предмет, число], ...], 3–6 разных предметов
## из пула роли хозяина. Зависит только от сида мира, номера руины и роли.
func ruin_cache_loot(i: int, role: String) -> Array:
	var pool: Array = (RUIN_LOOT[role] if RUIN_LOOT.has(role) else RUIN_LOOT["техник"]).duplicate()
	var r: RandomNumberGenerator = RandomNumberGenerator.new()
	r.seed = (world_seed ^ RUIN_CACHE_SALT) + i * 7919
	var n: int = mini(r.randi_range(RUIN_CACHE_MIN, RUIN_CACHE_MAX), pool.size())
	# Фишер — Йейтс на своём ГСЧ: Array.shuffle() берёт глобальный.
	for k in range(pool.size() - 1, 0, -1):
		var j: int = r.randi_range(0, k)
		var tmp = pool[k]
		pool[k] = pool[j]
		pool[j] = tmp
	var out: Array = []
	for k in n:
		var e: Array = pool[k]
		out.append([int(e[0]), r.randi_range(int(e[1]), int(e[2]))])
	return out


## Первая пустая клетка над руиной в колонке x, стоящая на твёрдом; (-1, -1) — нет.
func _ruin_top_cell(x: int, base: int) -> Vector2i:
	for y in range(base - 1, maxi(base - 7, 0), -1):
		if get_tile(x, y) == IDs.T.AIR and DB.tile_solid(get_tile(x, y + 1)):
			return Vector2i(x, y)
	return Vector2i(-1, -1)


## Сундук с добром хозяина — на крыше руины у середины, табличка — у левого края.
func _place_ruin_cache(i: int, cx: int, base: int, half: int) -> void:
	var t0: int = Time.get_ticks_usec()
	var owner: Dictionary = Lore.ruin_owner(i)
	var role: String = String(owner.get("role", ""))
	var cell: Vector2i = Vector2i(-1, -1)
	for dx in [0, -1, 1, -2, 2]:
		cell = _ruin_top_cell(cx + int(dx), base)
		if cell.x >= 0:
			break
	if cell.x < 0:
		# Над руиной вода или деревья — вырезаем нишу в стене над стальным полом.
		cell = Vector2i(cx, base - 1)
		set_tile_raw(cell.x, cell.y, IDs.T.AIR)
	var chest: Chest = null
	if MachineBase.place_machine("Chest", cell):
		chest = machines[cell]
		chest.permanent = true   # тайник руины: разобрать нельзя
		for e in ruin_cache_loot(i, role):
			chest.receive_item(int(e[0]), int(e[1]))
	var sign_cell: Vector2i = _ruin_top_cell(cx - half, base)
	if sign_cell.x < 0:
		sign_cell = cell + Vector2i(-1, 0)
	var sign: RuinSign = RuinSign.new()
	sign.title = Lore.place_name("ruin", i)
	sign.z_index = 2
	sign.position = cell_to_world(sign_cell)
	add_world_node(sign)
	ruin_caches.append({
		"index": i, "cell": cell, "chest": chest, "sign": sign, "sign_cell": sign_cell,
		"name": sign.title, "role": role, "owner": String(owner.get("full", "")),
	})
	ruin_cache_ms += float(Time.get_ticks_usec() - t0) / 1000.0


# ------------------------------------------------------------ НЕБЕСНЫЙ ТАЙНИК
# Высоко над рельефом висит обломок корабля «Кербер-9» (#60): стальной пол,
# днище и корма из панелей, иллюминатор, сундук с редким грузом (Balance.SKY_LOOT)
# и бортовой самописец с обрывком журнала (Lore.fragment). Допрыгнуть нельзя —
# только достроиться лестницей из блоков (блоки ставятся прямо в воздух).
# Всё считается своим ГСЧ от сида мира: поток случайных чисел генерации мира не
# сдвигается, остальной мир остаётся прежним. Издалека обломок — тёмный силуэт
# на фоне неба; на миникарте его нет (она рисует только рельеф World.surface).
#
# Форма (x0 — нос, открыт: туда приходит лестница; x1 — корма):
#        . . . . . . . P P P P      fy-3  обрывок крыши и корма
#        . . . . . . . . . . G      fy-2  G — иллюминатор
#        . . . r . . . . c . P      fy-1  r — самописец, c — сундук
#        S S S S S S S S S S S      fy    пол
#        . . P P P P P P P . .      fy+1  днище
#        . . . . P P P . . . .      fy+2
# и, с шансом SKY_DEBRIS_CHANCE, малый обломок обшивки справа, выше пола.

const SKY_SALT: int = 0x534B5946       # «SKYF»: свой поток случайных чисел
const SKY_PLACES: Array = ["Грузовой отсек", "Кормовой отсек", "Шлюзовой отсек", "Рубка"]

## Тайник текущего мира (пусто — обломок не поместился): {cell, chest, wreck,
## x0, x1, floor_y, bottom, ground, clearance, debris, name, fragment}.
var sky_cache: Dictionary = {}
## Клетки обломков (тайлы и сундук): проверки «мир вне тайника не сдвинулся».
var sky_cells: Array[Vector2i] = []
var sky_cache_ms: float = 0.0          # сколько тайник добавил к gen_ms


## Обломок: тёмный силуэт издалека, при подходе проступает; самописец с именем
## отсека; при первом открытии сундука обрывок журнала уходит в Tech.fragments.
class SkyWreck extends Node2D:
	var cells: Array[Vector2i] = []
	var bounds: Rect2 = Rect2()        # мировые координаты обломков
	var recorder: Vector2 = Vector2.ZERO
	var chest = null
	var title: String = ""
	var fragment: String = ""
	var haze: float = Balance.SKY_HAZE_ALPHA
	var announced: bool = false
	var opened: bool = false

	func _process(delta: float) -> void:
		var p = UI.player
		var near: bool = false
		if p != null and is_instance_valid(p):
			var q: Vector2 = p.global_position.clamp(bounds.position, bounds.end)
			near = q.distance_to(p.global_position) < Balance.SKY_REVEAL_TILES * World.TILE
		var a: float = move_toward(haze, 0.0 if near else Balance.SKY_HAZE_ALPHA, delta * 2.0)
		if a != haze:
			haze = a
			queue_redraw()
		if near and not announced:
			announced = true
			Game.notify("Обломок в небе: «%s»" % title, Color(0.8, 0.9, 1.0))
		if not opened and chest != null and is_instance_valid(chest) \
				and UI.panel != null and UI.panel.visible and UI.panel.chest == chest:
			opened = true
			if Tech.add_fragment(fragment):
				Game.notify("Самописец: найден обрывок журнала (J).", Color(1.0, 0.85, 0.5))

	func _draw() -> void:
		var t: float = float(World.TILE)
		var lit: float = 1.0 - haze / Balance.SKY_HAZE_ALPHA
		var dark: Color = Color(0.04, 0.05, 0.09)
		draw_rect(Rect2(recorder + Vector2(-5.0, 2.0), Vector2(10.0, 6.0)),
				Color(0.85, 0.42, 0.12).lerp(dark, 1.0 - lit))
		draw_rect(Rect2(recorder + Vector2(-5.0, 4.0), Vector2(10.0, 1.0)), Color(0.20, 0.10, 0.05))
		for c in cells:
			draw_rect(Rect2(Vector2(c) * t - position, Vector2(t, t)), Color(dark, haze))
		if lit <= 0.01:
			return
		var font: Font = ThemeDB.fallback_font
		var w: float = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		draw_string(font, recorder + Vector2(-w * 0.5, -6.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 8,
				Color(0.8, 0.9, 1.0, lit))


func _clear_sky_cache() -> void:
	var wreck = sky_cache.get("wreck")
	if wreck != null and is_instance_valid(wreck):
		wreck.queue_free()
	sky_cache = {}
	sky_cells.clear()
	sky_cache_ms = 0.0


## Верх рельефа в колонках x0..x1: самая высокая непустая клетка (с деревьями
## и руинами). Клетки обломков не считаются — функция годится и после постройки.
func sky_ground(x0: int, x1: int) -> int:
	var top: int = H - 1
	for x in range(maxi(x0, 0), mini(x1, W - 1) + 1):
		for y in range(0, top):
			if tiles[y * W + x] != IDs.T.AIR and not sky_cells.has(Vector2i(x, y)):
				top = y
				break
	return top


## Где и какой обломок висит: зависит только от сида мира и рельефа под ним.
## {} — нигде не поместился (на трёх сидах CI такого нет — проверяет автотест).
func sky_plan() -> Dictionary:
	var r: RandomNumberGenerator = _sky_rng(0)
	var debris: bool = r.randf() < Balance.SKY_DEBRIS_CHANCE
	var w: int = r.randi_range(9, 11)
	var span: int = w + (6 if debris else 1)    # колонок от носа до края обломков
	var want: int = r.randi_range(Balance.SKY_CLEARANCE_MIN, Balance.SKY_CLEARANCE_MAX)
	var title: String = "%s «%s»" % [SKY_PLACES[r.randi() % SKY_PLACES.size()], Lore.CREW_NAME]
	var dx: int = r.randi_range(3, 4)
	var dy: int = r.randi_range(1, 3)
	for _k in Balance.SKY_TRIES:
		var x0: int = r.randi_range(Balance.SKY_EDGE_GAP, W - 9 - span)
		if absi(x0 + w / 2 - W / 2) < Balance.SKY_BASE_GAP:
			continue
		var ground: int = sky_ground(x0 - 2, x0 + span + 1)
		# Днище — ground - clearance - 1, пол — на 2 выше, верх обломков — на 4 выше пола.
		var fit: int = ground - 7 - Balance.SKY_TOP_MARGIN
		if fit < Balance.SKY_CLEARANCE_MIN:
			continue
		var clearance: int = mini(want, fit)
		var bottom: int = ground - clearance - 1
		return {"x0": x0, "x1": x0 + w - 1, "floor_y": bottom - 2, "bottom": bottom,
				"ground": ground, "clearance": clearance, "debris": debris,
				"debris_x": x0 + w - 1 + dx, "debris_y": bottom - 2 - dy, "name": title}
	return {}


## Груз тайника: [[предмет, число], ...], SKY_CACHE_MIN..MAX разных предметов
## из Balance.SKY_LOOT. Свой поток (1): раскладка обломка на груз не влияет.
func sky_cache_loot() -> Array:
	var pool: Array = Balance.SKY_LOOT.keys()
	var r: RandomNumberGenerator = _sky_rng(1)
	var n: int = mini(r.randi_range(Balance.SKY_CACHE_MIN, Balance.SKY_CACHE_MAX), pool.size())
	for k in range(pool.size() - 1, 0, -1):
		var j: int = r.randi_range(0, k)
		var tmp = pool[k]
		pool[k] = pool[j]
		pool[j] = tmp
	var out: Array = []
	for k in n:
		var span: Array = Balance.SKY_LOOT[pool[k]]
		out.append([int(pool[k]), r.randi_range(int(span[0]), int(span[1]))])
	return out


## Обрывок журнала в самописце: свой поток (2), тот же сид — тот же текст.
func sky_fragment() -> String:
	return Lore.fragment(_sky_rng(2))


## ГСЧ тайника: сид мира, соль и номер потока перемешаны через hash() — у соседних
## сидов первые числа PCG почти одинаковы (на трёх сидах CI малый обломок
## не выпадал ни разу при шансе 50 %).
func _sky_rng(stream: int) -> RandomNumberGenerator:
	var r: RandomNumberGenerator = RandomNumberGenerator.new()
	r.seed = hash([world_seed, SKY_SALT, stream])
	return r


func _sky_set(x: int, y: int, id: int) -> void:
	if get_tile(x, y) == IDs.T.AIR:
		set_tile_raw(x, y, id)
		sky_cells.append(Vector2i(x, y))


func _place_sky_cache() -> void:
	var t0: int = Time.get_ticks_usec()
	_clear_sky_cache()
	var plan: Dictionary = sky_plan()
	if plan.is_empty():
		push_warning("[Мир] небесный тайник не поместился (сид %d)" % world_seed)
		return
	var x0: int = int(plan["x0"])
	var x1: int = int(plan["x1"])
	var fy: int = int(plan["floor_y"])
	for x in range(x0, x1 + 1):
		_sky_set(x, fy, IDs.T.STEEL)
	for x in range(x0 + 2, x1 - 1):
		_sky_set(x, fy + 1, IDs.T.PANEL)
	for x in range(x0 + 4, x1 - 3):
		_sky_set(x, fy + 2, IDs.T.PANEL)
	_sky_set(x1, fy - 1, IDs.T.PANEL)
	_sky_set(x1, fy - 2, IDs.T.GLASS)
	for x in range(x1 - 3, x1 + 1):
		_sky_set(x, fy - 3, IDs.T.PANEL)
	if plan["debris"]:
		var ddx: int = int(plan["debris_x"])
		var ddy: int = int(plan["debris_y"])
		for x in range(ddx, ddx + 3):
			_sky_set(x, ddy, IDs.T.PANEL)
		_sky_set(ddx + 1, ddy - 1, IDs.T.GLASS)
	var cell: Vector2i = Vector2i(x1 - 2, fy - 1)
	var chest: Chest = null
	if MachineBase.place_machine("Chest", cell):
		chest = machines[cell]
		chest.permanent = true   # тайник обломков: разобрать нельзя
		sky_cells.append(cell)
		for e in sky_cache_loot():
			chest.receive_item(int(e[0]), int(e[1]))
	var wreck: SkyWreck = SkyWreck.new()
	var lo: Vector2i = Vector2i(x0, fy - 3)
	var hi: Vector2i = Vector2i(x0, fy + 2)
	for c in sky_cells:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	wreck.position = Vector2(lo * TILE)
	wreck.bounds = Rect2(Vector2(lo * TILE), Vector2((hi - lo + Vector2i.ONE) * TILE))
	wreck.cells = sky_cells.duplicate()
	wreck.recorder = cell_to_world(Vector2i(x0 + 3, fy - 1)) - wreck.position
	wreck.chest = chest
	wreck.title = String(plan["name"])
	wreck.fragment = sky_fragment()
	wreck.z_index = 4                  # над тайлами и сундуком, под героем
	add_world_node(wreck)
	sky_cache = plan.duplicate()
	sky_cache["cell"] = cell
	sky_cache["chest"] = chest
	sky_cache["wreck"] = wreck
	sky_cache["fragment"] = wreck.fragment
	sky_cache_ms = float(Time.get_ticks_usec() - t0) / 1000.0


func _place_base(cx: int) -> void:
	## Открытая станция на расчищенной площадке: стальной пол, панели, лампы, терминалы, релей.
	var base: int = surface[cx]
	# Пол платформы
	for x in range(cx - 12, cx + 13):
		set_tile_raw(x, base, IDs.T.STEEL)
		set_tile_raw(x, base + 1, IDs.T.STEEL)
	# Ряд построек (по одному тайлу, игрок ходит между ними)
	# Релей-ядро в центре
	beacon_cell = Vector2i(cx, base - 1)
	set_tile_raw(cx, base - 1, IDs.T.RELAY_CORE)
	# Терминалы
	for i in 2:
		var tx: int = cx - 6 + i * 12
		set_tile_raw(tx, base - 1, IDs.T.TERMINAL)
		terminals.append(Vector2i(tx, base - 1))
		terminal_chapters[Vector2i(tx, base - 1)] = i
	# Лампы по кругу
	for lx in [cx - 11, cx - 3, cx + 3, cx + 11]:
		set_tile_raw(int(lx), base - 1, IDs.T.LIGHT_CRYSTAL)
	# Декоративные панели между постройками
	for px in [cx - 9, cx - 5, cx - 2, cx + 2, cx + 5, cx + 9]:
		set_tile_raw(int(px), base - 1, IDs.T.PANEL)
	# Вентиляция у базы
	vents.append(Vector2i(cx - 13, base - 1))


# ------------------------------------------------------------ ВОДА

## Обнуляет состояние воды: мир сухой, очередь пересчёта пуста.
func _reset_fluid() -> void:
	fluid = PackedByteArray()
	fluid.resize(W * H)
	fluid.fill(0)
	_fluid_queued = PackedByteArray()
	_fluid_queued.resize(W * H)
	_fluid_queued.fill(0)
	_fluid_queue = PackedInt32Array()
	_fluid_timer = 0.0
	fluid_ticks = 0
	fluid_steps = 0
	fluid_scan_cells = 0
	fluid_tick_us = 0
	fluid_tick_us_max = 0
	fluid_scan_tick_max = 0


## Заливает уровни воды по готовому миру: каждая клетка с водой полная.
## Клетки, под которыми пустота (вода висит в воздухе), помечаем на пересчёт —
## они должны стечь вниз.
func _init_fluid_from_tiles() -> void:
	_reset_fluid()
	for y in range(H):
		var row: int = y * W
		for x in range(W):
			if tiles[row + x] != IDs.T.WATER:
				continue
			fluid[row + x] = FLUID_MAX
			var below: int = get_tile(x, y + 1)
			if below != IDs.T.WATER and not DB.tile_solid(below):
				_fluid_mark(row + x)


## Уровень воды в клетке (0 — сухо).
func fluid_level(c: Vector2i) -> int:
	if c.x < 0 or c.x >= W or c.y < 0 or c.y >= H:
		return 0
	return int(fluid[c.y * W + c.x])


## Наливает в клетку ровно lvl порций воды (0 — осушить). Клетка должна быть
## проходимой для воды (воздух или вода). Для сценариев и будущих вёдер/насосов.
func set_fluid(c: Vector2i, lvl: int) -> void:
	if c.x < 0 or c.x >= W or c.y < 0 or c.y >= H:
		return
	var idx: int = c.y * W + c.x
	var t: int = tiles[idx]
	if t != IDs.T.AIR and t != IDs.T.WATER:
		return
	fluid[idx] = clampi(lvl, 0, FLUID_MAX)
	_set_fluid_cell(c.x, c.y)
	_fluid_mark(idx)
	_fluid_mark_cell(c.x - 1, c.y)
	_fluid_mark_cell(c.x + 1, c.y)
	_fluid_mark_cell(c.x, c.y - 1)
	_fluid_mark_cell(c.x, c.y + 1)


## Ставит клетку в очередь на пересчёт воды.
func _fluid_mark(idx: int) -> void:
	if idx < 0 or idx >= fluid.size():
		return
	if _fluid_queued[idx] != 0:
		return
	_fluid_queued[idx] = 1
	_fluid_queue.append(idx)


## Ставит клетку в очередь на пересчёт воды (по координатам).
func _fluid_mark_cell(x: int, y: int) -> void:
	if x < 0 or x >= W or y < 0 or y >= H:
		return
	_fluid_mark(y * W + x)


func _process(delta: float) -> void:
	_explore_tick()   # туман войны (#59): работа только при смене клетки героя
	_defense_tick(delta)   # оборона (#31): шлюзы и решётки, раз в 0.1 с
	_beams_tick()     # луч (#164): не чаще раза в кадр, только если мир изменился
	_fluid_timer += delta
	if _fluid_timer < FLUID_STEP:
		return
	_fluid_timer = 0.0
	_fluid_tick()


## Шаг симуляции воды: пересчитывает клетки, которые изменились или рядом с
## которыми что-то изменилось. Очередь обычно пуста — вода стоит смирно,
## пока игрок не выкопает яму.
func _fluid_tick() -> void:
	if not Net.is_authority():   # СЕТЬ (ADR-002, D5): вода считается только на хосте
		return
	if _fluid_queue.is_empty():
		return
	var t0: int = Time.get_ticks_usec()
	var scan0: int = fluid_scan_cells
	var batch: PackedInt32Array = _fluid_queue
	_fluid_queue = PackedInt32Array()
	var moved: PackedInt32Array = PackedInt32Array()
	for i in batch.size():
		var idx: int = batch[i]
		_fluid_queued[idx] = 0
		if _fluid_step_cell(idx):
			moved.append(idx)
	fluid_steps += batch.size()
	# Изменилась клетка — пересчитать и её, и соседей: вода могла прийти
	# или уйти, и их уровни теперь другие.
	for i in moved.size():
		var idx: int = moved[i]
		_fluid_mark(idx)
		var x: int = idx % W
		var y: int = int(idx / W)
		_fluid_mark_cell(x - 1, y)
		_fluid_mark_cell(x + 1, y)
		_fluid_mark_cell(x, y - 1)
		_fluid_mark_cell(x, y + 1)
	var dt: int = Time.get_ticks_usec() - t0
	fluid_ticks += 1
	fluid_tick_us += dt
	fluid_tick_us_max = maxi(fluid_tick_us_max, dt)
	fluid_scan_tick_max = maxi(fluid_scan_tick_max, fluid_scan_cells - scan0)


## Один шаг воды в клетке: сначала вниз, потом в стороны.
## Возвращает true, если уровень в клетке изменился.
##
## Вниз вода падает целиком, если под ней место. В стороны — по одной порции:
##   * к обрыву: под соседом есть куда стечь (пусто или неполная вода), а сам
##     сосед ниже нас. Сосед тут же стечёт вниз — туда-обратно не бывает;
##   * по ровному — только внутри ямы: в этом ряду слева и справа стоят
##     стенки, а пол до них не обрывается (см. _fluid_scan_side). Иначе озеро
##     растечётся тонкой плёнкой по всей ровной земле вокруг себя. В яме вода отдаёт соседу, который
##     ниже на две порции, или ниже на одну, если за ним есть клетка ещё
##     ниже: так дно заливается ровно (разброс не больше порции), а не лесенкой.
## Одна порция — плёнка, её не видно; по ровному она стоит на месте и
## сползает, только если в той же яме есть куда стечь вниз.
## На сухую клетку твёрдого дна лужа шагает, только если её воды хватит на
## видимый слой и после шага (см. _fluid_may_spread, #147): малая порция в
## широкой яме стоит компактной видимой лужей, а не плёнкой по всему дну.
func _fluid_step_cell(idx: int) -> bool:
	var lvl: int = fluid[idx]
	if lvl <= 0:
		return false
	var x: int = idx % W
	var y: int = int(idx / W)
	# --- вниз ---
	if y + 1 < H:
		var below: int = idx + W
		if _fluid_open(tiles[below]):
			var space: int = FLUID_MAX - fluid[below]
			if space > 0:
				var give: int = mini(lvl, space)
				fluid[idx] = lvl - give
				fluid[below] = fluid[below] + give
				_set_fluid_cell(x, y)
				_set_fluid_cell(x, y + 1)
				return true
	# --- вбок ---
	# Растекается только вода, стоящая на опоре (твёрдое или полная вода):
	# та, под которой есть место, утекает вниз (см. выше).
	if y + 1 >= H or not _fluid_supported(idx + W):
		return false
	# Уровни соседей; -1 — туда вода не течёт (стенка, постройка, край мира).
	var nl: int = fluid[idx - 1] if x > 0 and _fluid_open(tiles[idx - 1]) else -1
	var nr: int = fluid[idx + 1] if x + 1 < W and _fluid_open(tiles[idx + 1]) else -1
	var lower_l: bool = nl >= 0 and lvl > nl
	var lower_r: bool = nr >= 0 and lvl > nr
	# К обрыву.
	if lower_l and not _fluid_supported(idx - 1 + W):
		_fluid_move_side(idx, idx - 1, x, x - 1, y)
		return true
	if lower_r and not _fluid_supported(idx + 1 + W):
		_fluid_move_side(idx, idx + 1, x, x + 1, y)
		return true
	# По ровному: сосед ниже, и мы в яме. Плёнка (1 порция) по ровному
	# течёт, только если в этой яме дальше есть ямка в дне — стечь туда.
	if not (lower_l or lower_r):
		return false
	var sl: int = _fluid_scan_side(x, y, -1, nl, lvl - 2)
	if sl < 0:
		return false
	var sr: int = _fluid_scan_side(x, y, 1, nr, lvl - 2)
	if sr < 0:
		return false
	var go_l: bool = lower_l and (lvl >= nl + 2 or sl >= 1) and _fluid_may_spread(idx, idx - 1, nl, sl)
	var go_r: bool = lower_r and (lvl >= nr + 2 or sr >= 1) and _fluid_may_spread(idx, idx + 1, nr, sr)
	if go_l and not (go_r and lvl >= nr + 2 and lvl < nl + 2):
		_fluid_move_side(idx, idx - 1, x, x - 1, y)
		return true
	if go_r:
		_fluid_move_side(idx, idx + 1, x, x + 1, y)
		return true
	return false


## Можно ли луже по ровному дну ямы шагнуть из клетки idx в соседнюю n
## (уровень nlvl, итог сканирования в ту сторону — s). Ограничивает растекание
## количество воды, а не ширина ямы (#147):
##   * в мокрую клетку и к ямке в дне (s == 2) — всегда: внутри лужи вода
##     выравнивается, а к самой низкой точке впадины стекает даже плёнка;
##   * на сухую клетку над водой (полная вода — пол) — всегда: тонкий слой на
##     поверхности озера сливается с ним и выглядит ровной гладью;
##   * на сухую клетку твёрдого дна — только если воды в луже (связный ряд
##     мокрых клеток вокруг idx) хватит на видимый слой и после шага:
##     объём ≥ FLUID_VISIBLE × (длина + 1). Иначе лужа стоит компактно, а не
##     растекается плёнкой по 1 порции. Воды достаточно — лужа шагает дальше
##     и наполняет яму любой ширины до FLUID_SCAN.
func _fluid_may_spread(idx: int, n: int, nlvl: int, s: int) -> bool:
	if nlvl > 0 or s == 2:
		return true
	if _fluid_open(tiles[n + W]):
		return true
	var vol: int = fluid[idx]
	var cells: int = 1
	for d in [-1, 1]:
		var i: int = idx
		var cx: int = idx % W
		for k in FLUID_SCAN:
			i += d
			cx += d
			if cx < 0 or cx >= W:
				break
			fluid_scan_cells += 1
			if fluid[i] == 0 or not _fluid_open(tiles[i]):
				break
			vol += fluid[i]
			cells += 1
	return vol >= FLUID_VISIBLE * (cells + 1)


## Перелить одну порцию вбок: из клетки idx в соседнюю n.
func _fluid_move_side(idx: int, n: int, x: int, nx: int, y: int) -> void:
	fluid[idx] = fluid[idx] - 1
	fluid[n] = fluid[n] + 1
	_set_fluid_cell(x, y)
	_set_fluid_cell(nx, y)


## Может ли вода стоять в клетке с таким тайлом (воздух или вода).
func _fluid_open(t: int) -> bool:
	return t == IDs.T.AIR or t == IDs.T.WATER


## Держит ли клетка воду над собой: твёрдое, постройка или полная вода.
func _fluid_supported(i: int) -> bool:
	return not _fluid_open(tiles[i]) or fluid[i] >= FLUID_MAX


## Просматривает ряд y от клетки x в сторону d — ищет стенку ямы.
## Стенка — любая клетка, куда вода не течёт, или край мира. Под рядом смотрим
## пол: клетка без опоры (пусто или неполная вода) — дыра в полу. Узкая дыра
## (не шире FLUID_GAP) — ямка в дне: яму она не открывает, вода стечёт в неё.
## Широкая — разрыв: площадка кончилась, это не яма (#70).
## Возвращает:
##   -1 — до стенки разрыв в полу или стенки нет ближе FLUID_SCAN клеток:
##        это ровная земля, а не яма;
##    2 — стенка есть, и за соседом (уровень nlvl) по ровному или под горку
##        лежит ямка в дне — самая низкая точка, вода стекает туда (#147);
##    1 — стенка есть, и за соседом по ровному или под горку лежит клетка
##        не выше low — воде есть куда «скатиться»;
##    0 — стенка есть, а ниже ничего нет.
func _fluid_scan_side(x: int, y: int, d: int, nlvl: int, low: int) -> int:
	if y + 1 >= H:
		return 0   # нижний ряд мира: под ним бедрок, пол сплошной
	var row: int = y * W
	var cx: int = x
	var state: int = 0  # 0 — ищем низину, 1 — нашли клетку не выше low, 2 — путь закрыт горкой, 3 — нашли ямку
	var gap: int = 0    # клеток подряд без опоры под рядом
	for k in FLUID_SCAN:
		cx += d
		if cx < 0 or cx >= W:
			return _fluid_scan_result(state)
		fluid_scan_cells += 1
		var i: int = row + cx
		var t: int = tiles[i]
		if t != IDs.T.AIR and t != IDs.T.WATER:
			return _fluid_scan_result(state)
		var bt: int = tiles[i + W]
		var hole: bool = (bt == IDs.T.AIR or bt == IDs.T.WATER) and fluid[i + W] < FLUID_MAX
		if hole:
			gap += 1
			if gap > FLUID_GAP:
				return -1
		else:
			gap = 0
		if k > 0 and (state == 0 or state == 1):
			# Низину нашли — смотрим дальше, нет ли за ней ямки (пока не горка).
			var f: int = fluid[i]
			if hole:
				state = 3
			elif f <= low:
				state = 1
			elif f > nlvl:
				state = 2 if state == 0 else 4   # 4 — низина есть, к ямке не пройти
	return -1


## Итог _fluid_scan_side по состоянию поиска низины.
func _fluid_scan_result(state: int) -> int:
	match state:
		3:
			return 2
		1, 4:
			return 1
	return 0


## Заперт ли ряд y вокруг клетки x стенками с обеих сторон — стоит ли вода
## в яме, а не на ровной земле (см. _fluid_scan_side).
func _fluid_bounded(x: int, y: int) -> bool:
	return _fluid_scan_side(x, y, -1, 0, -1) >= 0 and _fluid_scan_side(x, y, 1, 0, -1) >= 0


## Сколько клеток ждут пересчёта воды (0 — вода успокоилась).
func fluid_pending() -> int:
	return _fluid_queue.size()


## Обновляет тайл и картинку клетки по текущему уровню воды.
func _set_fluid_cell(x: int, y: int) -> void:
	var idx: int = y * W + x
	if _net_track:   # СЕТЬ (ADR-002): уровень клетки — в батч хоста
		_net_mark_fluid(idx)
	# Одна порция — плёнка в полклетки: её не видно, клетка остаётся воздухом.
	var id: int = IDs.T.WATER if fluid[idx] >= FLUID_VISIBLE else IDs.T.AIR
	var old: int = tiles[idx]
	if old == id:
		return
	tiles[idx] = id
	if tilemap:
		_set_cell_visual(x, y, id, old)


# ------------------------------------------------------------ ДОСТУП К ТАЙЛАМ

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < W and y < H


func get_tile(x: int, y: int) -> int:
	if x < 0 or x >= W:
		return IDs.T.BEDROCK
	if y < 0:
		return IDs.T.AIR
	if y >= H:
		return IDs.T.BEDROCK
	return tiles[y * W + x]


func get_tile_v(c: Vector2i) -> int:
	return get_tile(c.x, c.y)


func set_tile_raw(x: int, y: int, id: int) -> void:
	if x < 0 or x >= W or y < 0 or y >= H:
		return
	tiles[y * W + x] = id


# ------------------------------------------------------------ ОТРАСТАНИЕ РУДЫ (#174, ADR-005 § 6.4)
## Планета живая: каждый рассвет в неразведанной породе (explored == 0, глубже
## ORE_REGROW_MIN_DEPTH) камень рядом с жилой становится той же рудой — пока клеток
## не станет столько, сколько было после генерации (ore_initial). Хлам не растёт.
## Выбор клеток детерминирован от world_seed + день: тот же сид и та же перепись —
## те же клетки. На глазах у игрока ничего не прорастает.

## Начальная перепись: id тайла руды → клеток после генерации. Хлам не входит.
var ore_initial: Dictionary = {}
## Сколько клеток руды приросло за последний рассвет (замер ore-census и сценарий).
var ore_regrow_last: Dictionary = {}
## Сколько рассветов отрастание уже отработало (load не вызывает его повторно).
var ore_regrow_dawns: int = 0

const REGROW_ORES: Array[int] = [IDs.T.COAL_ORE, IDs.T.COPPER_ORE, IDs.T.IRON_ORE, IDs.T.CRYSTAL_ORE]
const _REGROW_DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


## Перепись руды по готовому миру. Зовётся в конце generate(); load_state её не трогает.
func _census_ores() -> void:
	ore_initial.clear()
	ore_regrow_last.clear()
	ore_regrow_dawns = 0
	for tid in REGROW_ORES:
		ore_initial[str(tid)] = 0
	if tiles.size() != W * H:
		return
	for i in tiles.size():
		var key: String = str(tiles[i])
		if ore_initial.has(key):
			ore_initial[key] = int(ore_initial[key]) + 1


## Клеток руды tid сейчас.
func ore_count(tid: int) -> int:
	if tiles.size() != W * H:
		return 0
	return tiles.count(tid)


## Рассвет: вернуть до 1 % начальной переписи каждой руды. Нет кандидатов — пропуск.
## Возвращает, сколько клеток добавлено по каждой руде (id → n).
func regrow_ores(day: int) -> Dictionary:
	var added: Dictionary = {}
	ore_regrow_last = added
	if tiles.size() != W * H or explored.size() != W * H or surface.size() != W:
		return added
	if ore_initial.is_empty():
		_census_ores()
	ore_regrow_dawns += 1
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(world_seed) + day * 100003
	for tid in REGROW_ORES:
		var initial: int = int(ore_initial.get(str(tid), 0))
		var have: int = ore_count(tid)
		var want: int = ceili(Balance.ORE_REGROW_RATE * float(initial))
		var deficit: int = initial - have
		var n: int = mini(want, maxi(0, deficit))
		added[tid] = 0
		if n <= 0:
			continue
		var pool: Array[int] = _regrow_candidates(tid)
		if pool.is_empty():
			continue
		_regrow_shuffle(pool, rng)
		var take: int = mini(n, pool.size())
		for k in take:
			var idx: int = pool[k]
			var x: int = idx % W
			var y: int = int(idx / W)
			# set_tile, не raw: клиенты получают клетку обычной синхронизацией тайлов.
			set_tile(x, y, tid)
		added[tid] = take
	return added


## Камень в тумане, глубже порога, соседний по 4 сторонам с этой рудой.
func _regrow_candidates(tid: int) -> Array[int]:
	var out: Array[int] = []
	var min_d: int = Balance.ORE_REGROW_MIN_DEPTH
	for y in range(H - 3):
		var row: int = y * W
		for x in range(W):
			var idx: int = row + x
			if tiles[idx] != IDs.T.STONE or explored[idx] != 0:
				continue
			if y - surface[x] <= min_d:
				continue
			var touch: bool = false
			for d in _REGROW_DIRS:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx < 0 or ny < 0 or nx >= W or ny >= H:
					continue
				if tiles[ny * W + nx] == tid:
					touch = true
					break
			if touch:
				out.append(idx)
	return out


## Фишер–Йейтс от ГСЧ рассветa: тот же сид и день — тот же порядок.
func _regrow_shuffle(pool: Array[int], rng: RandomNumberGenerator) -> void:
	for i in range(pool.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: int = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp


## Ставит тайл и обновляет визуализацию.
func set_tile(x: int, y: int, id: int) -> void:
	if x < 0 or x >= W or y < 0 or y >= H:
		return
	var idx: int = y * W + x
	var old: int = tiles[idx]
	tiles[idx] = id
	if fluid.size() == W * H:
		if id == IDs.T.WATER:
			if fluid[idx] < FLUID_VISIBLE:
				fluid[idx] = FLUID_MAX
		else:
			fluid[idx] = 0
	# Вода рядом с изменившейся клеткой могла потечь или притечь.
	_fluid_mark_cell(x, y)
	_fluid_mark_cell(x - 1, y)
	_fluid_mark_cell(x + 1, y)
	_fluid_mark_cell(x, y - 1)
	_fluid_mark_cell(x, y + 1)
	if tilemap:
		_set_cell_visual(x, y, id, old)
	_update_astar(x, y)
	_update_lights_around(x, y)
	_defense_on_set_tile(Vector2i(x, y), id)
	if beams != null and old != id:
		beams.mark_dirty()
	if _net_track:   # СЕТЬ (ADR-002): клетка — в батч хоста
		_net_mark_tile(idx)


func is_solid_cell(c: Vector2i) -> bool:
	return DB.tile_solid(get_tile_v(c))


func is_solid_at(p: Vector2) -> bool:
	return is_solid_cell(world_to_cell(p))


## Первая твёрдая клетка на отрезке from → to (мировые px), считая конечную; стартовая
## клетка не проверяется — луч выходит из неё. Обход по клеткам (DDA): ни один угол не
## пропускается. Касание только угла — не попадание: сквозь щель между двумя твёрдыми
## клетками луч не проходит (оба соседа по стороне перекрывают угол), но клетка, которую
## отрезок лишь задевает углом, луч не останавливает. Жидкости и воздух — пусто.
## machines_block — машины тоже твёрдые (копка; трассировка видимости фантомов и турели
## их не считает). diggable — для копки: проходимый, но ломаемый тайл (ствол, ветка)
## тоже преграда; видимости он не мешает. Нет такой — (-1, -1). Единая трассировка:
## копка мышью, тач, турель, фантомы, дальше — луч света.
func first_solid_on_ray(from: Vector2, to: Vector2, machines_block: bool = true, diggable: bool = false) -> Vector2i:
	var a: Vector2i = world_to_cell(from)
	var b: Vector2i = world_to_cell(to)
	if a == b:
		return Vector2i(-1, -1)
	var d: Vector2 = (to - from) / float(TILE)
	var fx: float = from.x / float(TILE)
	var fy: float = from.y / float(TILE)
	var sx: int = 1 if d.x > 0.0 else -1
	var sy: int = 1 if d.y > 0.0 else -1
	var inf: float = 1.0e30
	var dtx: float = absf(1.0 / d.x) if d.x != 0.0 else inf
	var dty: float = absf(1.0 / d.y) if d.y != 0.0 else inf
	var tx: float = inf
	var ty: float = inf
	if d.x != 0.0:
		tx = (float(a.x + (1 if sx > 0 else 0)) - fx) / d.x
	if d.y != 0.0:
		ty = (float(a.y + (1 if sy > 0 else 0)) - fy) / d.y
	var cx: int = a.x
	var cy: int = a.y
	var steps: int = absi(b.x - a.x) + absi(b.y - a.y)
	for _i in range(steps):
		# Равенство границ — отрезок проходит ровно через угол сетки. Обычный DDA в этот
		# шаг заходит в одну клетку и пропускает соседа; проверяем обоих. Касание только
		# угла — не попадание, вход в обе клетки — стена, если хотя бы одна твёрдая.
		var corner: bool = is_equal_approx(tx, ty)
		var ox: int = cx
		var oy: int = cy
		if corner or tx < ty:
			cx += sx
			tx += dtx
		if corner or ty < tx:
			cy += sy
			ty += dty
		var cell: Vector2i = Vector2i(cx, cy)
		if corner:
			# Соседи по сторонам от угла, не диагональная клетка шага. Внутрь ни одной —
			# касание угла, не попадание. Внутрь обеих — щель закрыта, если хотя бы одна
			# твёрдая. Иначе — та, куда луч вошёл.
			var side_x: Vector2i = Vector2i(ox + sx, oy)
			var side_y: Vector2i = Vector2i(ox, oy + sy)
			var into_x: bool = _segment_enters_cell(from, to, side_x)
			var into_y: bool = _segment_enters_cell(from, to, side_y)
			if not into_x and not into_y:
				continue
			if into_x and into_y:
				var cx_hit: Vector2i = _solid_hit(side_x, machines_block, diggable)
				if cx_hit.x >= 0:
					return cx_hit
				cell = side_y
			else:
				cell = side_x if into_x else side_y
		var hit: Vector2i = _solid_hit(cell, machines_block, diggable)
		if hit.x >= 0:
			return hit
	return Vector2i(-1, -1)


func _solid_hit(c: Vector2i, machines_block: bool, diggable: bool = false) -> Vector2i:
	var tid: int = tiles[c.y * W + c.x] if c.x >= 0 and c.x < W and c.y >= 0 and c.y < H else get_tile(c.x, c.y)
	if _solid_tbl[tid] != 0 or (machines_block and machines.has(c)):
		return c
	# Копка: проходимый, но ломаемый тайл (ствол, ветка) тоже преграда на луче.
	if diggable and tid != IDs.T.AIR and not DB.is_liquid(tid) and DB.tile_hard(tid) <= 100.0:
		return c
	return Vector2i(-1, -1)


## Отрезок заходит внутрь клетки, а не только касается угла. Граница клетки — часть клетки:
## конец луча на грани считается попаданием.
func _segment_enters_cell(from: Vector2, to: Vector2, c: Vector2i) -> bool:
	var x0: float = float(c.x * TILE)
	var y0: float = float(c.y * TILE)
	var x1: float = x0 + float(TILE)
	var y1: float = y0 + float(TILE)
	var dx: float = to.x - from.x
	var dy: float = to.y - from.y
	var t0: float = 0.0
	var t1: float = 1.0
	if absf(dx) < 0.000001:
		if from.x < x0 or from.x > x1:
			return false
	else:
		var inv: float = 1.0 / dx
		var ta: float = (x0 - from.x) * inv
		var tb: float = (x1 - from.x) * inv
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	if absf(dy) < 0.000001:
		if from.y < y0 or from.y > y1:
			return false
	else:
		var invy: float = 1.0 / dy
		var ta2: float = (y0 - from.y) * invy
		var tb2: float = (y1 - from.y) * invy
		t0 = maxf(t0, minf(ta2, tb2))
		t1 = minf(t1, maxf(ta2, tb2))
	# Строгое неравенство: касание только угла (t0 == t1) — не вход внутрь.
	# Допуск — погрешность float на границе клетки, не ширина клетки.
	return t0 < t1 + 0.000001 and t1 >= -0.000001 and t0 <= 1.000001


func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / TILE)), int(floor(p.y / TILE)))


func cell_to_world(c: Vector2i) -> Vector2:
	return Vector2(float(c.x * TILE) + TILE * 0.5, float(c.y * TILE) + TILE * 0.5)


func cell_rect(c: Vector2i) -> Rect2:
	return Rect2(Vector2(c.x * TILE, c.y * TILE), Vector2(TILE, TILE))


# ------------------------------------------------------------ ФИЗИКА ТАЙЛОВ

## phantom — проверка для фантома: открытый шлюз для него тоже стена (#31).
func rect_solid(r: Rect2, phantom: bool = false) -> bool:
	var x0: int = int(floor(r.position.x / TILE))
	var x1: int = int(floor((r.position.x + r.size.x - 0.01) / TILE))
	var y0: int = int(floor(r.position.y / TILE))
	var y1: int = int(floor((r.position.y + r.size.y - 0.01) / TILE))
	var tbl: PackedByteArray = _psolid_tbl if phantom else _solid_tbl
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if tbl[get_tile(x, y)] != 0:
				return true
	return false


## Перемещение AABB по сетке с раздельным разрешением по осям.
## phantom — тело фантома: шлюз для него непроходим и открытым (#31).
func move_body(pos: Vector2, motion: Vector2, size: Vector2, phantom: bool = false) -> Dictionary:
	var half: Vector2 = size * 0.5
	var p: Vector2 = pos
	var hit_x: bool = false
	var hit_y: bool = false
	var on_ground: bool = false

	if motion.x != 0.0:
		p.x += motion.x
		var test: Rect2 = Rect2(p - half, size)
		if rect_solid(test, phantom):
			hit_x = true
			if motion.x > 0.0:
				p.x = floor((p.x + half.x) / TILE) * TILE - half.x - 0.01
			else:
				p.x = (floor((p.x - half.x) / TILE) + 1) * TILE + half.x + 0.01
	if motion.y != 0.0:
		p.y += motion.y
		var test2: Rect2 = Rect2(p - half, size)
		if rect_solid(test2, phantom):
			hit_y = true
			if motion.y > 0.0:
				p.y = floor((p.y + half.y) / TILE) * TILE - half.y - 0.01
				on_ground = true
			else:
				p.y = (floor((p.y - half.y) / TILE) + 1) * TILE + half.y + 0.01
	return {"position": p, "hit_x": hit_x, "hit_y": hit_y, "on_ground": on_ground}


# ------------------------------------------------------------ ОБОРОНА (#31)
# ADR-001 § 4.4: стальная стена, шлюз, решётка вентиляции, свет прожекторов.
#   * Флаги тайлов — упакованные таблицы по id: _solid_tbl (стена для тел),
#     _psolid_tbl (phantom_solid: стена для фантомов и A*, плюс шлюз в любом
#     состоянии), _dig_tbl (dig: копатель роет — флаг dig в DB и твёрдость
#     не выше BURROWER_DIG_MAX_HARD).
#   * Шлюз — тайлы AIRLOCK/AIRLOCK_OPEN. Открыт, если игрок ближе
#     AIRLOCK_OPEN_DIST_TILES и ни одного фантома ближе AIRLOCK_SAFE_DIST_TILES
#     (и всегда, пока игрок стоит в проёме — иначе дверь его зажмёт; фантому
#     открытый шлюз всё равно стена). Пересчёт раз в AIRLOCK_CHECK_PERIOD
#     только по реестру airlocks.
#   * Решётка — тайл VENT_GRATE на клетке вентиляции; vents_sealed: клетка → HP.
#     Threat не спавнит из запечатанных. Копатель рядом грызёт решётку:
#     GRATE_HP за GRATE_BREAK_TIME секунд (damage_grate — для любого урона).
#   * Свет машин — публичные add_light_source/remove_light_source (прожектор).

## Выстрел турели (для FX/HUD, #34): откуда и куда. Имя не менять — на него
## подписаны сеть и сценарии. Цвет дуги — отдельный сигнал маяка (#167).
signal turret_fired(from: Vector2, to: Vector2)
## Выстрел маяка под красным: дуга цвета луча. Турель этот сигнал не шлёт.
signal pharos_fired(from: Vector2, to: Vector2, color: Color)
## Решётку сломали — вентиляция снова открыта.
signal grate_broken(cell: Vector2i)

## Шлюзы мира: клетка → true. Заполняется в set_tile.
var airlocks: Dictionary = {}
## Запечатанные вентиляции: клетка решётки → её HP.
var vents_sealed: Dictionary = {}
## Замер: время последнего пересчёта шлюзов, мкс (tools/defense_bench.gd).
var airlock_tick_us: int = 0

var _solid_tbl: PackedByteArray = PackedByteArray()
var _psolid_tbl: PackedByteArray = PackedByteArray()
var _dig_tbl: PackedByteArray = PackedByteArray()
var _defense_t: float = 0.0
## Плоское зеркало реестра шлюзов для горячего цикла (пересобирается по флагу).
var _airlock_dirty: bool = true
var _airlock_cells: Array = []
var _airlock_pos: PackedVector2Array = PackedVector2Array()
var _airlock_idx: PackedInt32Array = PackedInt32Array()
## Источники света от машин (переживают _rebuild_lights).
var _extra_lights: Array = []
## Дальнобойные источники (радиус больше чанка): отдельно от чанков.
var _big_lights: Array = []
var _big_flat: PackedFloat32Array = PackedFloat32Array()
var _big_rect: Rect2 = Rect2()      ## рамка кругов дальнобойных источников


func _build_defense_tables() -> void:
	_solid_tbl.resize(IDs.TILE_COUNT)
	_psolid_tbl.resize(IDs.TILE_COUNT)
	_dig_tbl.resize(IDs.TILE_COUNT)
	for id in range(IDs.TILE_COUNT):
		var solid: bool = DB.tile_solid(id)
		_solid_tbl[id] = 1 if solid else 0
		_psolid_tbl[id] = 1 if solid or id == IDs.T.AIRLOCK or id == IDs.T.AIRLOCK_OPEN else 0
		_dig_tbl[id] = 1 if DB.tile_diggable(id) and DB.tile_hard(id) <= Balance.BURROWER_DIG_MAX_HARD else 0


func _defense_reset() -> void:
	airlocks.clear()
	_airlock_dirty = true
	vents_sealed.clear()
	_extra_lights.clear()
	_big_lights.clear()
	_big_flat = PackedFloat32Array()
	_defense_t = 0.0


## Стена ли клетка для фантома (шлюз — всегда).
func is_phantom_solid_cell(c: Vector2i) -> bool:
	return _psolid_tbl[get_tile_v(c)] != 0


## Роет ли копатель тайл с таким id.
func is_diggable(id: int) -> bool:
	return id >= 0 and id < _dig_tbl.size() and _dig_tbl[id] != 0


func is_vent_sealed(c: Vector2i) -> bool:
	return vents_sealed.has(c)


## Можно ли поставить тайл id в клетку: решётка — только на вентиляцию.
func tile_place_ok(c: Vector2i, id: int) -> bool:
	if id == IDs.T.VENT_GRATE:
		return vents.has(c)
	return true


## Вентиляции в пещерах: VENTS_RANDOM штук на полу пещер (воздух над твёрдым),
## не ближе VENT_MIN_GAP клеток друг к другу и к вентиляции базы. Раньше
## бралась случайная клетка без поиска пола — она попадала в «воздух над полом»
## редко, и на сиде 31337 выходила одна вентиляция на весь мир.
func _place_vents(rng: RandomNumberGenerator) -> void:
	var placed: int = 0
	for attempt in Balance.VENTS_RANDOM * 40:
		if placed >= Balance.VENTS_RANDOM:
			break
		var vx: int = rng.randi_range(8, W - 8)
		var vy: int = rng.randi_range(surface[vx] + 6, H - 12)
		if get_tile(vx, vy) != IDs.T.AIR:
			continue
		# Опускаемся на пол пещеры.
		while vy < H - 5 and get_tile(vx, vy + 1) == IDs.T.AIR:
			vy += 1
		if get_tile(vx, vy) != IDs.T.AIR or not DB.tile_solid(get_tile(vx, vy + 1)):
			continue
		var c: Vector2i = Vector2i(vx, vy)
		var crowded: bool = false
		for v in vents:
			if absi(v.x - c.x) < Balance.VENT_MIN_GAP and absi(v.y - c.y) < Balance.VENT_MIN_GAP:
				crowded = true
				break
		if crowded:
			continue
		vents.append(c)
		placed += 1


## Крюк set_tile: реестры шлюзов и решёток.
func _defense_on_set_tile(c: Vector2i, id: int) -> void:
	if id == IDs.T.AIRLOCK or id == IDs.T.AIRLOCK_OPEN:
		if not airlocks.has(c):
			airlocks[c] = true
			_airlock_dirty = true
	elif not airlocks.is_empty() and airlocks.erase(c):
		_airlock_dirty = true
	if id == IDs.T.VENT_GRATE:
		if not vents_sealed.has(c):
			vents_sealed[c] = Balance.GRATE_HP
	elif not vents_sealed.is_empty():
		vents_sealed.erase(c)


func _defense_tick(delta: float) -> void:
	if not Net.is_authority():   # СЕТЬ (ADR-002): шлюзы и решётки — на хосте, тайлы приходят батчем
		return
	if airlocks.is_empty() and vents_sealed.is_empty():
		_defense_t = 0.0
		return
	_defense_t += delta
	if _defense_t < Balance.AIRLOCK_CHECK_PERIOD:
		return
	var dt: float = _defense_t
	_defense_t = 0.0
	var ph: PackedVector2Array = PackedVector2Array()
	var burrowers: PackedVector2Array = PackedVector2Array()
	for p in get_tree().get_nodes_in_group("phantom"):
		if not is_instance_valid(p) or not bool(p.get("alive")):
			continue
		ph.append(p.global_position)
		if String(p.get("kind")) == "burrower":
			burrowers.append(p.global_position)
	if not airlocks.is_empty() and Game.players.size() > 1:   # СЕТЬ (ADR-002, MP-F): шлюз — любому герою
		update_airlocks_heroes(net_hero_positions(), ph)
	elif not airlocks.is_empty():
		var pl = Game.player
		var has_pl: bool = pl != null and is_instance_valid(pl) \
				and not bool(pl.get("dead")) and not bool(pl.get("hiding"))
		update_airlocks(pl.global_position if has_pl else Vector2.ZERO, has_pl, ph)
	if not vents_sealed.is_empty() and not burrowers.is_empty():
		_gnaw_grates(burrowers, dt)


## Пересчёт всех шлюзов по положению игрока и фантомов. Публичная — для замера.
func update_airlocks(ppos: Vector2, has_player: bool, phantoms: PackedVector2Array) -> void:
	var t0: int = Time.get_ticks_usec()
	if _airlock_dirty:
		_airlock_dirty = false
		_airlock_cells = airlocks.keys()
		_airlock_pos = PackedVector2Array()
		_airlock_idx = PackedInt32Array()
		for c in _airlock_cells:
			_airlock_pos.append(cell_to_world(c))
			_airlock_idx.append(c.y * W + c.x)
	var open_r: float = Balance.AIRLOCK_OPEN_DIST_TILES * TILE
	var open_r2: float = open_r * open_r
	var safe_r: float = Balance.AIRLOCK_SAFE_DIST_TILES * TILE
	var safe_r2: float = safe_r * safe_r
	# Перекрытие тела героя (12×22) с клеткой: |dx| < 8 + 6, |dy| < 8 + 11.
	var ox: float = TILE * 0.5 + 6.0
	var oy: float = TILE * 0.5 + 11.0
	var np: int = phantoms.size()
	for i in _airlock_pos.size():
		var cp: Vector2 = _airlock_pos[i]
		var want: bool = false
		if has_player:
			if absf(cp.x - ppos.x) < ox and absf(cp.y - ppos.y) < oy:
				want = true   # игрок в проёме — не зажимаем
			elif cp.distance_squared_to(ppos) <= open_r2:
				want = true
				for k in np:
					if cp.distance_squared_to(phantoms[k]) < safe_r2:
						want = false
						break
		if tiles[_airlock_idx[i]] != (IDs.T.AIRLOCK_OPEN if want else IDs.T.AIRLOCK):
			_set_airlock(_airlock_cells[i], want)
	airlock_tick_us = Time.get_ticks_usec() - t0


## Открыть/закрыть шлюз: только тайл и картинка. A* не трогаем — для фантомов
## шлюз стена в любом состоянии; вода в шлюз не течёт ни так, ни так.
func _set_airlock(c: Vector2i, open: bool) -> void:
	var idx: int = c.y * W + c.x
	var id: int = IDs.T.AIRLOCK_OPEN if open else IDs.T.AIRLOCK
	if tiles[idx] == id:
		return
	tiles[idx] = id
	if _net_track:   # СЕТЬ (ADR-002): клетка — в батч хоста
		_net_mark_tile(idx)
	if tilemap:
		_set_cell_visual(c.x, c.y, id)
	Sfx.play_at("place", cell_to_world(c), -18.0, 0.7 if open else 0.55)


## Копатели рядом с решётками грызут их.
func _gnaw_grates(burrowers: PackedVector2Array, dt: float) -> void:
	var r2: float = Balance.GRATE_REACH_PX * Balance.GRATE_REACH_PX
	var dps: float = Balance.GRATE_HP / Balance.GRATE_BREAK_TIME
	for c in vents_sealed.keys():
		var cp: Vector2 = cell_to_world(c)
		for q in burrowers:
			if cp.distance_squared_to(q) <= r2:
				damage_grate(c, dps * dt)
				break


## Урон решётке. true — решётка сломана (вентиляция снова открыта).
func damage_grate(c: Vector2i, amount: float) -> bool:
	if not vents_sealed.has(c):
		return false
	var hp: float = float(vents_sealed[c]) - amount
	if hp > 0.0:
		vents_sealed[c] = hp
		return false
	set_tile(c.x, c.y, IDs.T.AIR)
	UI.spawn_chip(c, DB.tile_color(IDs.T.VENT_GRATE))
	Sfx.play_at("break", cell_to_world(c), -8.0, 0.7)
	grate_broken.emit(c)
	return true


## Луч (#164): перестроить карту, если мир или горелка изменились, и зажечь
## клетки луча. Не чаще раза в кадр. Клиент считает сам — состояния машин
## уже пришли от хоста, трассировка детерминирована.
func _beams_tick() -> void:
	if beams == null or not beams.dirty:
		return
	var before: int = beams.changed
	beams.rebuild()
	if beams.changed != before:
		_apply_beam_lights()


## Свет луча: на каждую клетку — источник 20 px. Белый ярче. Старые ручки
## снимаются целиком: погасшая клетка не должна продолжать светить.
func _apply_beam_lights() -> void:
	for c in _beam_lights.keys():
		remove_light_source(_beam_lights[c])
	_beam_lights.clear()
	for c in beams.cells.keys():
		var mask: int = int(beams.cells[c])
		if mask == 0:
			continue
		var power: float = Balance.BEAM_LIGHT_WHITE if mask == Beams.W else Balance.BEAM_LIGHT
		_beam_lights[c] = add_light_source(cell_to_world(c), 20.0, power)


## Источник света от машины (прожектор). Возвращает ручку для remove_light_source.
## Радиус больше чанка — в отдельный короткий список, чтобы light_at во всём
## мире не начал просматривать 5×5 чанков вместо 3×3.
func add_light_source(pos: Vector2, radius: float, power: float) -> Dictionary:
	var entry: Dictionary = {"pos": pos, "radius": radius, "power": power}
	_extra_lights.append(entry)
	_light_attach(entry)
	return entry


## Убрать источник, выданный add_light_source. Чужая/старая ручка — без ошибок.
func remove_light_source(entry: Dictionary) -> void:
	if entry.is_empty():
		return
	var known: bool = false
	for i in range(_extra_lights.size()):
		if is_same(_extra_lights[i], entry):
			_extra_lights.remove_at(i)
			known = true
			break
	if not known:
		return   # ручка прошлого мира: generate() уже всё сбросил
	for i in range(lights.size()):
		if is_same(lights[i], entry):
			lights.remove_at(i)
			break
	for i in range(_big_lights.size()):
		if is_same(_big_lights[i], entry):
			_big_lights.remove_at(i)
			_rebuild_big_flat()
			return
	_light_unregister(entry, world_to_cell(entry["pos"]))


func _light_attach(entry: Dictionary) -> void:
	lights.append(entry)
	if float(entry["radius"]) > float(TILE * LIGHT_CHUNK):
		_big_lights.append(entry)
		_rebuild_big_flat()
	else:
		_light_register(entry, world_to_cell(entry["pos"]))


func _rebuild_big_flat() -> void:
	var f: PackedFloat32Array = PackedFloat32Array()
	for i in range(_big_lights.size()):
		var e: Dictionary = _big_lights[i]
		var p: Vector2 = e["pos"]
		var r: float = float(e["radius"])
		var box: Rect2 = Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0)
		_big_rect = box if i == 0 else _big_rect.merge(box)
		f.push_back(p.x)
		f.push_back(p.y)
		f.push_back(r * r)
		f.push_back(float(e["power"]))
	_big_flat = f


## После полной пересборки света — вернуть источники машин.
func _relight_sources() -> void:
	_big_lights.clear()
	_big_flat = PackedFloat32Array()
	for e in _extra_lights:
		_light_attach(e)


# ------------------------------------------------------------ СВЕТ

## Индекс чанка в массивах реестра. LIGHT_CHUNK == 8, поэтому деление — сдвиг на 3.
static func _chunk_index(cell: Vector2i) -> int:
	return (cell.y >> 3) * LIGHT_CHUNKS_X + (cell.x >> 3)


## Пересоздаёт пустые чанки реестра света.
func _reset_light_chunks() -> void:
	_light_chunks.clear()
	_light_flat.clear()
	for i in range(LIGHT_CHUNKS_X * LIGHT_CHUNKS_Y):
		_light_chunks.append([] as Array[Dictionary])
		_light_flat.append(PackedFloat32Array())


## Кладёт источник в чанк хэша.
func _light_register(entry: Dictionary, cell: Vector2i) -> void:
	var idx: int = _chunk_index(cell)
	var bucket: Array = _light_chunks[idx]
	bucket.append(entry)
	# Числовое зеркало чанка: x, y, r², power. В light_at словари не трогаем.
	var flat: PackedFloat32Array = _light_flat[idx]
	var pos: Vector2 = entry["pos"]
	var r: float = float(entry["radius"])
	flat.push_back(pos.x)
	flat.push_back(pos.y)
	flat.push_back(r * r)
	flat.push_back(float(entry["power"]))
	_light_flat[idx] = flat
	if r > _light_max_radius:
		_light_max_radius = r
		_light_reach = maxi(1, int(ceil(r / float(TILE * LIGHT_CHUNK))))


## Убирает источник из чанка хэша.
func _light_unregister(entry: Dictionary, cell: Vector2i) -> void:
	var idx: int = _chunk_index(cell)
	var bucket: Array = _light_chunks[idx]
	var at: int = -1
	for i in range(bucket.size()):
		if is_same(bucket[i], entry):
			at = i
			break
	if at < 0:
		return
	bucket.remove_at(at)
	var flat: PackedFloat32Array = _light_flat[idx]
	if flat.size() >= (at + 1) * 4:
		for k in range(4):
			flat.remove_at(at * 4)
		_light_flat[idx] = flat


## Добавляет источник света от тайла (светящиеся руды, кристаллы, лава).
func _light_add_tile(cell: Vector2i, power: float) -> void:
	var entry: Dictionary = {
		"pos": cell_to_world(cell),
		"radius": LIGHT_BASE_RADIUS + power * LIGHT_RADIUS_PER_POWER,
		"power": power,
	}
	lights.append(entry)
	_light_cells[cell] = entry
	_light_register(entry, cell)


## Убирает источник света от тайла.
func _light_remove_tile(cell: Vector2i) -> void:
	if not _light_cells.has(cell):
		return
	var entry: Dictionary = _light_cells[cell]
	# Ищем по ссылке, а не по значению: сравнение словарей по содержимому дорогое.
	for i in range(lights.size()):
		if is_same(lights[i], entry):
			lights.remove_at(i)
			break
	_light_unregister(entry, cell)
	_light_cells.erase(cell)


## Статический источник (вентиляция, терминал, релей) — не привязан к тайлу.
func _light_add_static(cell: Vector2i, radius: float, power: float) -> void:
	var entry: Dictionary = {
		"pos": cell_to_world(cell),
		"radius": radius,
		"power": power,
	}
	lights.append(entry)
	_light_register(entry, cell)


## Полная пересборка реестра света. Дёргается только при генерации мира и sync_all().
func _rebuild_lights() -> void:
	lights.clear()
	_light_cells.clear()
	_reset_light_chunks()
	_light_max_radius = 0.0
	_light_reach = 1
	var light_tbl: PackedByteArray = _tile_flag_table(false)
	for y in range(H):
		var row: int = y * W
		for x in range(W):
			var id: int = tiles[row + x]
			if light_tbl[id] != 0:
				_light_add_tile(Vector2i(x, y), _tile_light_pow[id])
	for v in vents:
		_light_add_static(v, 26.0, 0.35)
	for c in terminals:
		_light_add_static(c, 40.0, 0.4)
	_light_add_static(beacon_cell, 70.0, 0.6)
	_relight_sources()


## Точечное обновление света вокруг изменённой клетки.
## Меняется только источник в самой клетке — никакого перебора всего мира.
func _update_lights_around(x: int, y: int) -> void:
	var cell: Vector2i = Vector2i(x, y)
	var old_power: float = 0.0
	if _light_cells.has(cell):
		old_power = float(_light_cells[cell]["power"])
	var new_power: float = _tile_light_pow[tiles[y * W + x]]
	if old_power == new_power:
		return
	_light_remove_tile(cell)
	if new_power > LIGHT_MIN:
		_light_add_tile(cell, new_power)


## Суммарный свет в клетке: складываем источники из соседних чанков хэша.
## Ходим по числовому зеркалу чанка — без словарей в горячем цикле.
func light_at(c: Vector2i) -> float:
	var total: float = 0.0
	var cp: Vector2 = cell_to_world(c)
	var cx: int = c.x >> 3
	var cy: int = c.y >> 3
	var reach: int = _light_reach
	for y in range(cy - reach, cy + reach + 1):
		if y < 0 or y >= LIGHT_CHUNKS_Y:
			continue
		var row: int = y * LIGHT_CHUNKS_X
		for x in range(cx - reach, cx + reach + 1):
			if x < 0 or x >= LIGHT_CHUNKS_X:
				continue
			var flat: PackedFloat32Array = _light_flat[row + x]
			var n: int = flat.size() / 4
			for i in range(n):
				var o: int = i * 4
				var ddx: float = cp.x - flat[o]
				var ddy: float = cp.y - flat[o + 1]
				if ddx * ddx + ddy * ddy < flat[o + 2]:
					total += flat[o + 3]
	# Дальнобойные источники (прожекторы, #31) — отдельным коротким списком:
	# в чанки их не кладём, чтобы не раздувать _light_reach для всего мира.
	# Рамка всех дальнобойных источников: вдали от прожекторов список не смотрим.
	if _big_flat.is_empty() or not _big_rect.has_point(cp):
		return total
	var big: PackedFloat32Array = _big_flat
	for i in range(big.size() / 4):
		var o: int = i * 4
		var ddx: float = cp.x - big[o]
		var ddy: float = cp.y - big[o + 1]
		if ddx * ddx + ddy * ddy < big[o + 2]:
			total += big[o + 3]
	return total


## Источники света, чей радиус пересекает прямоугольник (в мировых координатах).
## Нужен для отсечения света вне камеры.
func get_lights_near(rect: Rect2) -> Array:
	var out: Array = []
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return out
	var reach: float = _light_max_radius
	var span: float = float(TILE * LIGHT_CHUNK)
	var x0: int = maxi(int(floor((rect.position.x - reach) / span)), 0)
	var x1: int = mini(int(floor((rect.end.x + reach) / span)), LIGHT_CHUNKS_X - 1)
	var y0: int = maxi(int(floor((rect.position.y - reach) / span)), 0)
	var y1: int = mini(int(floor((rect.end.y + reach) / span)), LIGHT_CHUNKS_Y - 1)
	for cy in range(y0, y1 + 1):
		var row: int = cy * LIGHT_CHUNKS_X
		for cx in range(x0, x1 + 1):
			var bucket: Array = _light_chunks[row + cx]
			for l in bucket:
				var p: Vector2 = l["pos"]
				var r: float = float(l["radius"])
				var dx: float = maxf(maxf(rect.position.x - p.x, p.x - rect.end.x), 0.0)
				var dy: float = maxf(maxf(rect.position.y - p.y, p.y - rect.end.y), 0.0)
				if dx * dx + dy * dy <= r * r:
					out.append(l)
	for l in _big_lights:
		var p: Vector2 = l["pos"]
		var r: float = float(l["radius"])
		var dx: float = maxf(maxf(rect.position.x - p.x, p.x - rect.end.x), 0.0)
		var dy: float = maxf(maxf(rect.position.y - p.y, p.y - rect.end.y), 0.0)
		if dx * dx + dy * dy <= r * r:
			out.append(l)
	return out


# ------------------------------------------------------------ СИНХРОНИЗАЦИЯ

## old — что стояло в клетке до правки (-1 — неизвестно): соседей, чья маска
## от правки не меняется (вода сменила воздух у стены), не перерисовываем.
func _set_cell_visual(x: int, y: int, id: int, old: int = -1) -> void:
	## Воздух не рисуем вовсе — пустая клетка дешевле прозрачного тайла.
	if id == IDs.T.AIR:
		tilemap.set_cell(Vector2i(x, y), 0, Vector2i(-1, -1))
	else:
		tilemap.set_cell(Vector2i(x, y), 0, _atlas_var[id * DB.VARIANTS + _cell_variant(x, y, id)])
	# ADR-003 V1: у четырёх соседей могла смениться маска открытых сторон.
	_refresh_cell(x, y - 1, old, id)
	_refresh_cell(x + 1, y, old, id)
	_refresh_cell(x, y + 1, old, id)
	_refresh_cell(x - 1, y, old, id)
	if decor:
		decor.on_cell(x, y)   # ADR-003 V2: декор столбца зависит от этой клетки


func _sync_all() -> void:
	if not tilemap:
		return
	if _bio_mid.size() != W:
		_build_biome_rows()
	# Пустые клетки пропускаем: тайлмап после очистки и так пуст.
	# Вариант клетки (ADR-003 V1) считается здесь же, без вызовов на клетку:
	# маска открытых сторон, биом по глубине колонки, фактура по хэшу.
	var nv: int = DB.VARIANTS
	var av: Array = _atlas_var
	var op: PackedByteArray = _open_tbl
	var ta: int = DB.TEX_ALTS
	var am: int = DB.TEX_ALTS - 1      # фактур — степень двойки
	var mid: PackedInt32Array = _bio_mid
	var deep: PackedInt32Array = _bio_deep
	for y in range(H):
		var row: int = y * W
		# Края мира — общим путём (соседи за краем), середина — без проверок границ.
		var inner: bool = y > 0 and y < H - 1
		for x in range(W):
			var i: int = row + x
			var id: int = tiles[i]
			if id == IDs.T.AIR:
				continue
			if not inner or x == 0 or x == W - 1:
				tilemap.set_cell(Vector2i(x, y), 0, av[id * nv + _cell_variant(x, y, id)])
				continue
			var m: int = 0
			var n: int = tiles[i - W]
			if n != id and op[n] != 0:
				m = 1
			n = tiles[i + 1]
			if n != id and op[n] != 0:
				m |= 2
			n = tiles[i + W]
			if n != id and op[n] != 0:
				m |= 4
			n = tiles[i - 1]
			if n != id and op[n] != 0:
				m |= 8
			var bio: int = 2 if y >= deep[x] else (1 if y >= mid[x] else 0)
			var alt: int = ((x * 374761393 + y * 668265263) >> 15) & am
			tilemap.set_cell(Vector2i(x, y), 0, av[id * nv + (((bio * ta + alt) << 4) | m)])
	if decor:
		decor.reset()   # ADR-003 V2: декор флоры соберётся по тем же тайлам


# --- ADR-003 V1 (#103): вариант тайла в атласе -------------------------------
# Клетка атласа = тайл × биом по глубине × фактура (одна из DB.TEX_ALTS, по хэшу клетки) ×
# маска открытых сторон (1 верх, 2 право, 4 низ, 8 лево; сторона открыта, если
# сосед не твёрдый и не тот же тайл). Всё считается локально из тайлов и рельефа:
# в сохранение и в сеть по-прежнему идёт только id тайла (ADR-003 § 8).
# Глубины смены биомов — ADR-003 § 10 п. 3: средние пещеры с 25 % глубины
# колонки (как железо), глубина у лавы — с 55 % (кристаллы, лава).

const BIO_MID_DEPTH: float = 0.25
const BIO_DEEP_DEPTH: float = 0.55

var _atlas_var: Array = []                              # id * DB.VARIANTS + вариант -> клетка атласа
var _open_tbl: PackedByteArray = PackedByteArray()      # 1 — тайл не твёрдый: сторона к нему открыта
var _bio_mid: PackedInt32Array = PackedInt32Array()     # с какой строки колонки начинаются средние пещеры
var _bio_deep: PackedInt32Array = PackedInt32Array()    # с какой строки — глубина у лавы


## Границы биомов по колонкам: от рельефа, с неровной «ступенькой» ±1–2 клетки
## (пары колонок), чтобы граница не была линейкой. Зовётся после генерации и загрузки.
func _build_biome_rows() -> void:
	_bio_mid.resize(W)
	_bio_deep.resize(W)
	for x in W:
		var top: int = surface[x] if surface.size() == W else SEA_LEVEL
		var span: float = float(H - top)
		var h: int = ((x >> 1) * 2654435761) >> 13
		_bio_mid[x] = top + int(span * BIO_MID_DEPTH) + (h & 3) - 1
		_bio_deep[x] = top + int(span * BIO_DEEP_DEPTH) + ((h >> 3) & 3) - 1


## Биом клетки: 0 поверхность, 1 средние пещеры, 2 глубина у лавы.
func biome_at(x: int, y: int) -> int:
	if _bio_mid.size() != W or x < 0 or x >= W:
		return 0
	return 2 if y >= _bio_deep[x] else (1 if y >= _bio_mid[x] else 0)


func _cell_variant(x: int, y: int, id: int) -> int:
	var m: int = 0
	var n: int = get_tile(x, y - 1)
	if n != id and _open_tbl[n] != 0:
		m = 1
	n = get_tile(x + 1, y)
	if n != id and _open_tbl[n] != 0:
		m |= 2
	n = get_tile(x, y + 1)
	if n != id and _open_tbl[n] != 0:
		m |= 4
	n = get_tile(x - 1, y)
	if n != id and _open_tbl[n] != 0:
		m |= 8
	var alt: int = ((x * 374761393 + y * 668265263) >> 15) & (DB.TEX_ALTS - 1)
	return DB.variant_index(biome_at(x, y), alt, m)


## Клетка атласа, которая должна стоять в (x, y) при текущих тайлах (тесты сверяют тайлмап).
func cell_atlas(x: int, y: int) -> Vector2i:
	var id: int = get_tile(x, y)
	if id == IDs.T.AIR or not in_bounds(x, y):
		return Vector2i(-1, -1)
	return _atlas_var[id * DB.VARIANTS + _cell_variant(x, y, id)]


## Пересчёт варианта соседней клетки после правки рядом (воздух не трогаем — он пуст).
## was/now — тайл правленой клетки до и после: если сторона к ней у соседа как была
## открыта (или закрыта), так и осталась, перерисовывать нечего.
func _refresh_cell(x: int, y: int, was: int = -1, now: int = -1) -> void:
	if not in_bounds(x, y):
		return
	var id: int = tiles[y * W + x]
	if id == IDs.T.AIR:
		return
	if was >= 0 and now >= 0 \
			and (was != id and _open_tbl[was] != 0) == (now != id and _open_tbl[now] != 0):
		return
	tilemap.set_cell(Vector2i(x, y), 0, _atlas_var[id * DB.VARIANTS + _cell_variant(x, y, id)])


func sync_all() -> void:
	_sync_all()
	_rebuild_lights()


## Добавляет объект в мир (текущая сцена, иначе — сам World).
func add_world_node(n: Node) -> void:
	var host: Node = get_tree().current_scene
	if host == null:
		host = self
	host.add_child(n)


# ------------------------------------------------------------ ТУМАН ВОЙНЫ (#59)
## Битовая карта исследования: байт на клетку (0 — не видели, 1 — видели),
## одно поле для сохранения (#37). Открывается кругом вокруг героя (радиусы —
## Balance.FOG_*) и только при смене его клетки: стоя на месте, туман не стоит
## ничего. Слои тумана (мир — FogLayer, миникарта — HUD) карту не перебирают:
## они слушают explored_changed и пересчитывают только открытый прямоугольник.

## Открылись новые клетки; rect — их охватывающий прямоугольник, сами клетки
## (индексы y * W + x) — в explore_new, пока идёт рассылка сигнала.
signal explored_changed(rect: Rect2i)
## Карта заменена (новый мир или загрузка #37) — слоям пора пересобраться по ней.
signal explored_reset

var explored: PackedByteArray = PackedByteArray()
var explore_new: PackedInt32Array = PackedInt32Array()
var explore_cells: int = 0          ## сколько клеток открыто всего
# Замеры (сценарий fog_reveal): вызовы открытия, время на них, самый дорогой.
var explore_calls: int = 0
var explore_us: int = 0
var explore_us_max: int = 0
var _explore_cell: Vector2i = Vector2i(-9999, -9999)


## Новая карта: всё закрыто, кроме круга вокруг точки старта.
func _reset_explored() -> void:
	explored.resize(W * H)
	explored.fill(0)
	explore_cells = 0
	_explore_cell = Vector2i(-9999, -9999)
	explored_reset.emit()
	var c: Vector2i = world_to_cell(spawn_point)
	reveal_around(c, explore_radius_at(c))


## Радиус обзора в клетке: на поверхности (и над ней) шире, под землёй уже.
func explore_radius_at(c: Vector2i) -> int:
	var x: int = clampi(c.x, 0, W - 1)
	if surface.is_empty() or c.y <= surface[x] + Balance.FOG_SURFACE_DEPTH:
		return Balance.FOG_RADIUS_SURFACE
	return Balance.FOG_RADIUS


func is_explored(c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= W or c.y >= H or explored.is_empty():
		return false
	return explored[c.y * W + c.x] != 0


## Открывает круг радиусом r клеток вокруг c. Возвращает число новых клеток.
## Закрытые клетки ряда ищет нативный find по срезу ряда, поэтому цикл скрипта
## идёт только по новым клеткам: ходьба по исследованному почти бесплатна,
## шаг в новое — пропорционален краю круга, а не его площади.
func reveal_around(c: Vector2i, r: int) -> int:
	if explored.is_empty():
		return 0
	var t0: int = Time.get_ticks_usec()
	explore_new.clear()
	var x_lo: int = W
	var x_hi: int = -1
	var y_lo: int = H
	var y_hi: int = -1
	var rr: float = (float(r) + 0.5) * (float(r) + 0.5)
	for y in range(maxi(0, c.y - r), mini(H - 1, c.y + r) + 1):
		var dy: int = y - c.y
		var hw: int = int(sqrt(rr - float(dy * dy)))
		var x0: int = maxi(0, c.x - hw)
		var x1: int = mini(W - 1, c.x + hw)
		if x1 < x0:
			continue
		var row: int = y * W + x0
		var seg: PackedByteArray = explored.slice(row, row + x1 - x0 + 1)
		var i: int = seg.find(0)
		if i < 0:
			continue
		y_lo = mini(y_lo, y)
		y_hi = y
		x_lo = mini(x_lo, x0 + i)
		while i >= 0:
			explored[row + i] = 1
			explore_new.append(row + i)
			x_hi = maxi(x_hi, x0 + i)
			i = seg.find(0, i + 1)
	var opened: int = explore_new.size()
	explore_calls += 1
	if opened > 0:
		explore_cells += opened
		explored_changed.emit(Rect2i(x_lo, y_lo, x_hi - x_lo + 1, y_hi - y_lo + 1))
	var us: int = Time.get_ticks_usec() - t0
	explore_us += us
	explore_us_max = maxi(explore_us_max, us)
	return opened


## Каждый кадр — одно сравнение клетки героя; круг открываем только при смене клетки.
func _explore_tick() -> void:
	var p = Game.player
	if p == null or not is_instance_valid(p) or explored.is_empty():
		return
	var c: Vector2i = world_to_cell(p.global_position)
	if c == _explore_cell:
		return
	_explore_cell = c
	reveal_around(c, explore_radius_at(c))


# ------------------------------------------------------------ СОХРАНЕНИЕ (#37)
## Сетка мира для Save (scripts/core/save.gd): тайлы, уровни воды с очередью
## пересчёта, карта исследования и списки, которые меняются по ходу забега
## (прочитанные терминалы уходят из terminals). Постройки пишет Save сам —
## через MachineBase.save_state(). Сжимает файл целиком Save.

## Сколько клеток поменяла последняя загрузка (замер).
var load_changed_cells: int = 0

func save_state() -> Dictionary:
	var signs: Array = []
	for c in ruin_caches:
		signs.append(is_instance_valid(c["sign"]) and bool(c["sign"].announced))
	return {
		"w": W, "h": H,
		"tiles": tiles.duplicate(),
		"fluid": fluid.duplicate(),
		"fluid_queue": _fluid_queue.duplicate(),
		"fluid_timer": _fluid_timer,
		"explored": explored.duplicate(),
		"surface": surface.duplicate(),
		"terminals": Array(terminals),
		"terminal_chapters": terminal_chapters.duplicate(),
		"vents": Array(vents),
		"beacon_cell": beacon_cell,
		"spawn_point": spawn_point,
		"ruin_signs": signs,
		# Оборона (#31): шлюзы и решётки с их HP (реестры, которые ведёт set_tile).
		"airlocks": airlocks.keys(),
		"vents_sealed": vents_sealed.duplicate(),
		# Небесный тайник (#60): подходили ли к обломку, открыт ли сундук (обрывок выдан).
		"sky": _sky_save(),
		# Отрастание (#174): цель — перепись этого мира, а не пересчёт по уже изменённым тайлам.
		"ore_initial": ore_initial.duplicate(),
		"ore_regrow_dawns": ore_regrow_dawns,
	}


func _sky_save() -> Dictionary:
	var wreck = sky_cache.get("wreck")
	if wreck == null or not is_instance_valid(wreck):
		return {}
	return {"announced": bool(wreck.announced), "opened": bool(wreck.opened)}


## Положить сетку из файла поверх мира того же сида: тайлмап, свет и сетка пути
## правятся в отличающихся клетках, слои тумана пересобираются по explored_reset.
## false — размеры не сходятся.
func load_state(d: Dictionary) -> bool:
	var n: int = W * H
	var t: PackedByteArray = d.get("tiles", PackedByteArray())
	var f: PackedByteArray = d.get("fluid", PackedByteArray())
	var e: PackedByteArray = d.get("explored", PackedByteArray())
	if int(d.get("w", 0)) != W or int(d.get("h", 0)) != H or t.size() != n or f.size() != n \
			or e.size() != n:
		return false
	# Тайлмап, сетка пути и свет уже соответствуют текущим тайлам (мир того же
	# сида или только что сгенерирован) — правим только отличающиеся клетки.
	# Ряды сравниваются нативно: цикл скрипта идёт лишь по изменённым рядам.
	var old: PackedByteArray = tiles
	tiles = t.duplicate()
	load_changed_cells = 0
	for y in H:
		var row: int = y * W
		if old.slice(row, row + W) == tiles.slice(row, row + W):
			continue
		for x in W:
			if old[row + x] == tiles[row + x]:
				continue
			load_changed_cells += 1
			if tilemap:
				_set_cell_visual(x, y, tiles[row + x])
			_update_astar(x, y)
			_update_lights_around(x, y)
	fluid = f.duplicate()
	explored = e.duplicate()
	var s: PackedInt32Array = d.get("surface", PackedInt32Array())
	if s.size() == W and s != surface:
		surface = s.duplicate()
		# ADR-003 V1: границы биомов идут от рельефа — пересчитать и перерисовать.
		_build_biome_rows()
		if tilemap:
			_sync_all()
	# Очередь воды — как была: вода продолжит течь с того же шага.
	_fluid_queued.resize(n)
	_fluid_queued.fill(0)
	_fluid_queue = PackedInt32Array()
	for idx in PackedInt32Array(d.get("fluid_queue", PackedInt32Array())):
		_fluid_mark(idx)
	_fluid_timer = float(d.get("fluid_timer", 0.0))
	terminals.clear()
	for c in d.get("terminals", []):
		terminals.append(c)
	terminal_chapters = Dictionary(d.get("terminal_chapters", terminal_chapters)).duplicate()
	vents.clear()
	for v in d.get("vents", []):
		vents.append(v)
	beacon_cell = d.get("beacon_cell", beacon_cell)
	spawn_point = d.get("spawn_point", spawn_point)
	var signs: Array = d.get("ruin_signs", [])
	for i in mini(signs.size(), ruin_caches.size()):
		if is_instance_valid(ruin_caches[i]["sign"]):
			ruin_caches[i]["sign"].announced = bool(signs[i])
	airlocks.clear()
	for c in d.get("airlocks", []):
		airlocks[c] = true
	_airlock_dirty = true
	vents_sealed.clear()
	var vs = d.get("vents_sealed", {})
	if vs is Dictionary:
		for c in vs.keys():
			vents_sealed[c] = vs[c]
	var sky = d.get("sky", {})
	var wreck = sky_cache.get("wreck")
	if sky is Dictionary and not sky.is_empty() and wreck != null and is_instance_valid(wreck):
		wreck.announced = bool(sky.get("announced", false))
		wreck.opened = bool(sky.get("opened", false))
	explore_cells = explored.count(1)
	_explore_cell = Vector2i(-9999, -9999)
	explored_reset.emit()
	var oi: Dictionary = d.get("ore_initial", {})
	if oi is Dictionary and not oi.is_empty():
		ore_initial.clear()
		for k in oi.keys():
			ore_initial[str(k)] = int(oi[k])
	elif ore_initial.is_empty():
		_census_ores()
	ore_regrow_dawns = int(d.get("ore_regrow_dawns", ore_regrow_dawns))
	return true


# ------------------------------------------------------------ СЕТЬ (ADR-002, MP-C #88)
## Мир по сети (scripts/net/net_world.gd, § 4.2.1, D5). На хосте крюки set_tile,
## _set_airlock и _set_fluid_cell отмечают клетку «грязной» (флаг + список, без
## повторов); NetWorld раз в сетевой такт забирает списки и шлёт текущие значения
## батчем. Уровень воды отмечается и правкой тайла: set_tile сам меняет fluid.
## У клиента клетки ставятся net_apply_* — вода и оборона у него не считаются
## (Net.is_authority() в _fluid_tick и _defense_tick). В одиночной игре и у клиента
## _net_track = false: крюк — одно сравнение, поведение прежнее.

var _net_track: bool = false
var _net_tile_flag: PackedByteArray = PackedByteArray()
var _net_fluid_flag: PackedByteArray = PackedByteArray()
var _net_tiles: PackedInt32Array = PackedInt32Array()
var _net_fluid: PackedInt32Array = PackedInt32Array()


## Хост: включить/выключить учёт изменённых клеток (списки очищаются).
func net_track(on: bool) -> void:
	_net_track = on
	_net_tile_flag.resize(W * H)
	_net_tile_flag.fill(0)
	_net_fluid_flag.resize(W * H)
	_net_fluid_flag.fill(0)
	_net_tiles = PackedInt32Array()
	_net_fluid = PackedInt32Array()


func _net_mark_tile(idx: int) -> void:
	if _net_tile_flag[idx] == 0:
		_net_tile_flag[idx] = 1
		_net_tiles.append(idx)
	_net_mark_fluid(idx)


func _net_mark_fluid(idx: int) -> void:
	if _net_fluid_flag[idx] == 0:
		_net_fluid_flag[idx] = 1
		_net_fluid.append(idx)


## Хост: забрать изменённые с прошлого раза клетки {tiles, fluid} (индексы y·W + x).
func net_take_dirty() -> Dictionary:
	var t: PackedInt32Array = _net_tiles
	var f: PackedInt32Array = _net_fluid
	_net_tiles = PackedInt32Array()
	_net_fluid = PackedInt32Array()
	for i in t:
		_net_tile_flag[i] = 0
	for i in f:
		_net_fluid_flag[i] = 0
	return {"tiles": t, "fluid": f}


## Клиент: тайлы из батча хоста. Шлюз открывается/закрывается своим путём (картинка
## и звук, без пересчёта пути и света) — как у хоста.
func net_apply_tiles(idx: PackedInt32Array, val: PackedByteArray) -> void:
	var n: int = W * H
	for k in idx.size():
		var i: int = idx[k]
		if i < 0 or i >= n:
			continue
		var id: int = val[k]
		var old: int = tiles[i]
		if old == id or id >= IDs.TILE_COUNT:
			continue
		var x: int = i % W
		var y: int = int(i / W)
		var lock_old: bool = old == IDs.T.AIRLOCK or old == IDs.T.AIRLOCK_OPEN
		var lock_new: bool = id == IDs.T.AIRLOCK or id == IDs.T.AIRLOCK_OPEN
		if lock_old and lock_new:
			_set_airlock(Vector2i(x, y), id == IDs.T.AIRLOCK_OPEN)
		else:
			set_tile(x, y, id)


## Клиент: уровни воды из батча хоста. Тайл воды/воздуха выводится из уровня тем же
## правилом, что у хоста (_set_fluid_cell), и только в клетке, куда вода течёт.
func net_apply_fluid(idx: PackedInt32Array, val: PackedByteArray) -> void:
	var n: int = W * H
	for k in idx.size():
		var i: int = idx[k]
		if i < 0 or i >= n:
			continue
		fluid[i] = mini(int(val[k]), FLUID_MAX)
		if _fluid_open(tiles[i]):
			_set_fluid_cell(i % W, int(i / W))


# ------------------------------------------------------------ СЕТЬ: ШЛЮЗЫ (ADR-002, MP-F #92)
## С товарищами шлюз открывается любому герою (живому, не в укрытии) — по тому же
## правилу, что update_airlocks: герой в проёме — открыт; герой ближе
## AIRLOCK_OPEN_DIST_TILES и фантомов у шлюза нет — открыт. Один герой — прежний путь.

## Позиции героев, которым открываются шлюзы.
func net_hero_positions() -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for h in Game.players:
		if is_instance_valid(h) and not bool(h.get("dead")) and not bool(h.get("hiding")):
			out.append((h as Node2D).global_position)
	return out


## Пересчёт всех шлюзов по нескольким героям (публичная — для сценариев).
func update_airlocks_heroes(heroes: PackedVector2Array, phantoms: PackedVector2Array) -> void:
	if heroes.size() <= 1:
		update_airlocks(heroes[0] if heroes.size() == 1 else Vector2.ZERO, heroes.size() == 1, phantoms)
		return
	var t0: int = Time.get_ticks_usec()
	if _airlock_dirty:
		_airlock_dirty = false
		_airlock_cells = airlocks.keys()
		_airlock_pos = PackedVector2Array()
		_airlock_idx = PackedInt32Array()
		for c in _airlock_cells:
			_airlock_pos.append(cell_to_world(c))
			_airlock_idx.append(c.y * W + c.x)
	var open_r: float = Balance.AIRLOCK_OPEN_DIST_TILES * TILE
	var open_r2: float = open_r * open_r
	var safe_r: float = Balance.AIRLOCK_SAFE_DIST_TILES * TILE
	var safe_r2: float = safe_r * safe_r
	var ox: float = TILE * 0.5 + 6.0
	var oy: float = TILE * 0.5 + 11.0
	for i in _airlock_pos.size():
		var cp: Vector2 = _airlock_pos[i]
		var want: bool = false
		var near: bool = false
		for hp in heroes:
			if absf(cp.x - hp.x) < ox and absf(cp.y - hp.y) < oy:
				want = true   # герой в проёме — не зажимаем
				break
			if cp.distance_squared_to(hp) <= open_r2:
				near = true
		if not want and near:
			want = true
			for ph in phantoms:
				if cp.distance_squared_to(ph) < safe_r2:
					want = false
					break
		if tiles[_airlock_idx[i]] != (IDs.T.AIRLOCK_OPEN if want else IDs.T.AIRLOCK):
			_set_airlock(_airlock_cells[i], want)
	airlock_tick_us = Time.get_ticks_usec() - t0
