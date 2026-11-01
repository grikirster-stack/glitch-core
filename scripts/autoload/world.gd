extends Node2D
## Мир: тайловая сетка, процедурная генерация, физика тайлов, реестр построек.

const W: int = 640
const H: int = 180
const SEA_LEVEL: int = 52
const TILE: int = 16

var world_seed: int = 0
var tiles: PackedByteArray = PackedByteArray()
var surface: PackedInt32Array = PackedInt32Array()
var tilemap: TileMapLayer = null

var terminals: Array[Vector2i] = []
var vents: Array[Vector2i] = []
var beacon_cell: Vector2i = Vector2i.ZERO
var spawn_point: Vector2 = Vector2.ZERO
var lights: Array[Dictionary] = []
var machines: Dictionary = {}       # Vector2i -> Node (машина)
var belts: Dictionary = {}         # Vector2i -> {dir:int, items:Array}
var astar: AStarGrid2D = null


func _ready() -> void:
	_build_tileset()


func _build_tileset() -> void:
	var ts: TileSet = TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	var src: TileSetAtlasSource = TileSetAtlasSource.new()
	src.texture = DB.atlas_texture
	src.texture_region_size = Vector2i(TILE, TILE)
	for id in range(IDs.TILE_COUNT):
		var ac: Vector2i = DB.atlas_of_tile[id]
		src.create_tile(ac)
	ts.add_source(src, 0)
	tilemap = TileMapLayer.new()
	tilemap.name = "Tiles"
	tilemap.tile_set = ts
	add_child(tilemap)


# ------------------------------------------------------------ ГЕНЕРАЦИЯ

func generate(p_seed: int) -> void:
	world_seed = p_seed
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
	vents.clear()
	machines.clear()
	belts.clear()
	lights.clear()

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
	for x in range(2, W - 2):
		var top: int = surface[x]
		if get_tile(x, top) != IDs.T.GRASS:
			continue
		var r: float = rng.randf()
		if r < 0.055:
			_place_tree(x, top - 1, rng)
		elif r < 0.10:
			set_tile_raw(x, top - 1, IDs.T.MOSS)
		elif r < 0.115:
			set_tile_raw(x, top - 1, IDs.T.LIGHT_CRYSTAL)

	# --- 8. Руины станции -----------------------------------------------------
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
	for i in 14:
		var vx: int = rng.randi_range(8, W - 8)
		var vy: int = rng.randi_range(surface[vx] + 6, H - 12)
		if get_tile(vx, vy) == IDs.T.AIR and get_tile(vx, vy + 1) != IDs.T.AIR:
			vents.append(Vector2i(vx, vy))

	_sync_all()
	_rebuild_lights()
	_build_astar()
	spawn_point = Vector2(float((bx - 4) * TILE) + TILE * 0.5, float(surface[bx] * TILE) - 12.0)


## Сетка поиска пути для фантомов. Строится один раз, точечно обновляется при копке.
func _build_astar() -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, W, H)
	astar.cell_size = Vector2(TILE, TILE)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.update()
	for y in range(H):
		for x in range(W):
			if DB.tile_solid(tiles[y * W + x]):
				astar.set_point_solid(Vector2i(x, y), true)


func _update_astar(x: int, y: int) -> void:
	if astar == null:
		return
	if x < 0 or y < 0 or x >= W or y >= H:
		return
	astar.set_point_solid(Vector2i(x, y), DB.tile_solid(tiles[y * W + x]))


func _noise(type: int, freq: float, octaves: int, s: int) -> FastNoiseLite:
	var n: FastNoiseLite = FastNoiseLite.new()
	n.noise_type = type
	n.seed = s
	n.frequency = freq
	n.fractal_octaves = octaves
	n.fractal_lacunarity = 2.0
	n.fractal_gain = 0.5
	return n


func _place_tree(x: int, y: int, rng: RandomNumberGenerator) -> void:
	var hgt: int = rng.randi_range(4, 7)
	for i in hgt:
		set_tile_raw(x, y - i, IDs.T.LOG)
	for ly in range(y - hgt - 2, y - hgt + 3):
		var span: int = 2
		for lx in range(x - span, x + span + 1):
			if absi(lx - x) == span and rng.randf() < 0.5:
				continue
			if get_tile(lx, ly) == IDs.T.AIR:
				set_tile_raw(lx, ly, IDs.T.LEAVES)


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
	# Стены
	for x in range(cx - half, cx + half + 1):
		var hgt: int = rng.randi_range(1, 3)
		for i in hgt:
			if get_tile(x, base - 1 - i) == IDs.T.AIR:
				set_tile_raw(x, base - 1 - i, IDs.T.PANEL)
	# Окна и лампы
	for i in 3:
		var wx: int = cx - half + 1 + i * 2
		if wx > cx - half and wx < cx + half and get_tile(wx, base - 1) == IDs.T.AIR:
			set_tile_raw(wx, base - 1, IDs.T.GLASS)
	if get_tile(cx, base - 1) == IDs.T.AIR:
		set_tile_raw(cx, base - 1, IDs.T.LIGHT_CRYSTAL)
	# Терминал (задание)
	var tx: int = cx + half - 1
	if tx < W - 1 and get_tile(tx, base - 1) == IDs.T.AIR:
		set_tile_raw(tx, base - 1, IDs.T.TERMINAL)
		terminals.append(Vector2i(tx, base - 1))
	# Хлам
	for i in 4:
		var sx: int = clampi(cx + rng.randi_range(-half, half), 1, W - 2)
		var sy: int = base - 1
		if get_tile(sx, sy) == IDs.T.AIR:
			set_tile_raw(sx, sy, IDs.T.SCRAP_ORE)


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
	# Лампы по кругу
	for lx in [cx - 11, cx - 3, cx + 3, cx + 11]:
		set_tile_raw(int(lx), base - 1, IDs.T.LIGHT_CRYSTAL)
	# Декоративные панели между постройками
	for px in [cx - 9, cx - 5, cx - 2, cx + 2, cx + 5, cx + 9]:
		set_tile_raw(int(px), base - 1, IDs.T.PANEL)
	# Вентиляция у базы
	vents.append(Vector2i(cx - 13, base - 1))


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


## Ставит тайл и обновляет визуализацию.
func set_tile(x: int, y: int, id: int) -> void:
	if x < 0 or x >= W or y < 0 or y >= H:
		return
	tiles[y * W + x] = id
	if tilemap:
		_set_cell_visual(x, y, id)
	_update_astar(x, y)
	_update_lights_around(x, y)


func is_solid_cell(c: Vector2i) -> bool:
	return DB.tile_solid(get_tile_v(c))


func is_solid_at(p: Vector2) -> bool:
	return is_solid_cell(world_to_cell(p))


func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / TILE)), int(floor(p.y / TILE)))


func cell_to_world(c: Vector2i) -> Vector2:
	return Vector2(float(c.x * TILE) + TILE * 0.5, float(c.y * TILE) + TILE * 0.5)


func cell_rect(c: Vector2i) -> Rect2:
	return Rect2(Vector2(c.x * TILE, c.y * TILE), Vector2(TILE, TILE))


# ------------------------------------------------------------ ФИЗИКА ТАЙЛОВ

func rect_solid(r: Rect2) -> bool:
	var x0: int = int(floor(r.position.x / TILE))
	var x1: int = int(floor((r.position.x + r.size.x - 0.01) / TILE))
	var y0: int = int(floor(r.position.y / TILE))
	var y1: int = int(floor((r.position.y + r.size.y - 0.01) / TILE))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if is_solid_cell(Vector2i(x, y)):
				return true
	return false


## Перемещение AABB по сетке с раздельным разрешением по осям.
func move_body(pos: Vector2, motion: Vector2, size: Vector2) -> Dictionary:
	var half: Vector2 = size * 0.5
	var p: Vector2 = pos
	var hit_x: bool = false
	var hit_y: bool = false
	var on_ground: bool = false

	if motion.x != 0.0:
		p.x += motion.x
		var test: Rect2 = Rect2(p - half, size)
		if rect_solid(test):
			hit_x = true
			if motion.x > 0.0:
				p.x = floor((p.x + half.x) / TILE) * TILE - half.x - 0.01
			else:
				p.x = (floor((p.x - half.x) / TILE) + 1) * TILE + half.x + 0.01
	if motion.y != 0.0:
		p.y += motion.y
		var test2: Rect2 = Rect2(p - half, size)
		if rect_solid(test2):
			hit_y = true
			if motion.y > 0.0:
				p.y = floor((p.y + half.y) / TILE) * TILE - half.y - 0.01
				on_ground = true
			else:
				p.y = (floor((p.y - half.y) / TILE) + 1) * TILE + half.y + 0.01
	return {"position": p, "hit_x": hit_x, "hit_y": hit_y, "on_ground": on_ground}


# ------------------------------------------------------------ СВЕТ

func _rebuild_lights() -> void:
	lights.clear()
	for y in range(H):
		for x in range(W):
			var l: float = DB.tile_light(get_tile(x, y))
			if l > 0.05:
				lights.append({"pos": cell_to_world(Vector2i(x, y)), "radius": 46.0 + l * 60.0, "power": l})
	for v in vents:
		lights.append({"pos": cell_to_world(v), "radius": 26.0, "power": 0.35})
	for c in terminals:
		lights.append({"pos": cell_to_world(c), "radius": 40.0, "power": 0.4})
	lights.append({"pos": cell_to_world(beacon_cell), "radius": 70.0, "power": 0.6})


func _update_lights_around(x: int, y: int) -> void:
	_rebuild_lights()


func light_at(c: Vector2i) -> float:
	var total: float = 0.0
	for l in lights:
		if (cell_to_world(c) - l["pos"]).length() < l["radius"]:
			total += l["power"]
	return total


# ------------------------------------------------------------ СИНХРОНИЗАЦИЯ

func _set_cell_visual(x: int, y: int, id: int) -> void:
	## Воздух не рисуем вовсе — пустая клетка дешевле прозрачного тайла.
	if id == IDs.T.AIR:
		tilemap.set_cell(Vector2i(x, y), 0, Vector2i(-1, -1))
	else:
		tilemap.set_cell(Vector2i(x, y), 0, DB.atlas_of_tile[id])


func _sync_all() -> void:
	if not tilemap:
		return
	for y in range(H):
		for x in range(W):
			_set_cell_visual(x, y, tiles[y * W + x])


func sync_all() -> void:
	_sync_all()
	_rebuild_lights()


## Добавляет объект в мир (текущая сцена, иначе — сам World).
func add_world_node(n: Node) -> void:
	var host: Node = get_tree().current_scene
	if host == null:
		host = self
	host.add_child(n)
