extends ScenarioBase
## Стиль V2 (ADR-003, #104): флора концепта «Споровый луг».
##
## Свечник — те же TREE/LEAVES (проходимость и форма дерева прежние), декор-слой —
## отдельный TileMapLayer без коллизий:
##  * слой на месте, без физики, над тайлами и под туманом войны;
##  * под туманом декора нет: чанк заводится, когда в нём открылась клетка;
##  * декор выводится из сида и тайлов: пересборка даёт то же самое, собранное
##    совпадает с правилами везде, в сохранение не идёт, тайлы мира не трогает;
##  * каждому биому — своя флора; над стволом в просвете шляпок — стебель;
##  * правка клетки пересчитывает декор столбца (сломал пол — растение исчезло,
##    вернул — выросло то же самое);
##  * замер: сборка чанка, пересчёт при правке, полная сборка мира.

const Decor = preload("res://scripts/world/decor.gd")


func run() -> void:
	await await_frame()
	var d = World.decor
	ok("декор-слой на месте", d != null and d.get_parent() == World and d.tile_set != null)
	if d == null:
		finish()
		return
	ok("декор без коллизий и навигации",
			not d.collision_enabled and not d.navigation_enabled
			and d.tile_set.get_physics_layers_count() == 0)
	ok("декор над тайлами, под постройками и туманом войны (z 30)",
			d.z_index > World.tilemap.z_index and d.z_index < 3 and not d.is_processing(),
			"z %d, _process %s" % [d.z_index, str(d.is_processing())])

	# --- 1. Туман: декор только в исследованном ------------------------------
	var far: Vector2i = _far_unexplored()
	ok("нашлась неисследованная пещера", far.x >= 0, str(far))
	var lazy_cells: int = d.cells
	ok("в начале собраны только чанки у старта", d.chunks_built > 0 and d.chunks_built < 40,
			"чанков %d, клеток декора %d" % [d.chunks_built, lazy_cells])
	if far.x >= 0:
		ok("под туманом декора нет", not d.is_built(far) and d.decor_at(far.x, far.y) == 0
				and not World.is_explored(far))
		World.reveal_around(far, Balance.FOG_RADIUS)
		ok("открыли пещеру — чанк собран", d.is_built(far))
		ok("собранный чанк — по правилам", _mismatch(d, far.x - 8, far.y - 8, 16, 16) == 0)

	# --- 2. Весь мир: детерминизм, сохранение, тайлы -------------------------
	var tiles0: PackedByteArray = World.tiles.duplicate()
	var t0: int = Time.get_ticks_usec()
	d.build_all()
	var all_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	var snap: PackedByteArray = _snapshot(d)
	ok("собранный декор совпадает с правилами по всему миру", _mismatch(d, 0, 0, World.W, World.H) == 0)
	d.reset()
	d.build_all()
	ok("пересборка с нуля даёт то же самое", _snapshot(d) == snap)
	ok("декор тайлы мира не трогает", World.tiles == tiles0)
	var save: Dictionary = World.save_state()
	var leak: Array = []
	for k in save.keys():
		if String(k).to_lower().contains("decor"):
			leak.append(k)
	ok("декор в сохранение не идёт", leak.is_empty(), str(leak))

	# --- 3. Флора по биомам; стебель свечника --------------------------------
	var by_kind: Array = []
	by_kind.resize(Decor.KINDS)
	by_kind.fill(0)
	var wrong_bio: Array = []
	var bad_stem: int = 0
	for y in World.H:
		for x in World.W:
			var k: int = Decor.kind_of(d.decor_at(x, y))
			if k < 0:
				continue
			by_kind[k] += 1
			# Низ завесы — в биоме своего верха (граница биомов неровная).
			var bio: int = World.biome_at(x, y - 1 if k == Decor.K.HYPHAE_LO else y)
			var need: int = _biome_of_kind(k)
			if need >= 0 and need != bio and wrong_bio.size() < 5:
				wrong_bio.append("%s %d@%d" % [str(Vector2i(x, y)), k, bio])
			if k == Decor.K.STEM and not _above_trunk(x, y):
				bad_stem += 1
	ok("каждому биому — своя флора", wrong_bio.is_empty(), str(wrong_bio))
	var trees: int = int(World.gen_stats.get("trees", 0))
	ok("в просвете шляпок над стволом — стебель", by_kind[Decor.K.STEM] >= trees and bad_stem == 0,
			"стеблей %d на %d свечников, не над стволом %d" % [by_kind[Decor.K.STEM], trees, bad_stem])
	ok("флора есть во всех трёх биомах",
			by_kind[Decor.K.BUBBLE_LO] + by_kind[Decor.K.SHELF] + by_kind[Decor.K.PUFF] > 30
			and by_kind[Decor.K.HYPHAE_TOP] + by_kind[Decor.K.HYPHAE_SHORT] > 30
			and by_kind[Decor.K.POLYPORE] > 5 and by_kind[Decor.K.SACS] + by_kind[Decor.K.TUBES] > 5,
			str(by_kind))

	# --- 4. Правка клетки: пересчёт столбца ----------------------------------
	var plant: Vector2i = _find_kind(d, [Decor.K.POLYPORE, Decor.K.SHELF, Decor.K.SACS])
	ok("нашлось растение на полу", plant.x >= 0, str(plant))
	if plant.x >= 0:
		var code: int = d.decor_at(plant.x, plant.y)
		var floor_id: int = World.get_tile(plant.x, plant.y + 1)
		d.update_us_max = 0
		World.set_tile(plant.x, plant.y + 1, IDs.T.AIR)
		var gone: bool = d.decor_at(plant.x, plant.y) == 0
		World.set_tile(plant.x, plant.y + 1, floor_id)
		ok("сломал пол — растение исчезло, вернул — выросло то же",
				gone and d.decor_at(plant.x, plant.y) == code
				and _mismatch(d, plant.x, plant.y - 8, 1, 16) == 0)
	var stem: Vector2i = _find_kind(d, [Decor.K.STEM])
	if stem.x >= 0:
		var trunk: int = stem.y + 1
		while World.get_tile(stem.x, trunk) == IDs.T.LEAVES:
			trunk += 1
		World.set_tile(stem.x, trunk, IDs.T.AIR)
		ok("срубил верх ствола — стебля в шляпках нет", d.decor_at(stem.x, stem.y) == 0
				and _mismatch(d, stem.x, trunk - 8, 1, 12) == 0)
		World.set_tile(stem.x, trunk, IDs.T.TREE)

	# --- 5. Замер ------------------------------------------------------------
	var calls: int = maxi(1, d.update_calls)
	var avg_us: float = float(d.update_us) / float(calls)
	ok("пересчёт столбца при правке клетки дешёвый", avg_us < 200.0,
			"в среднем %.1f мкс, худший %d мкс на %d правок" % [avg_us, d.update_us_max, d.update_calls])
	var chunks: int = maxi(1, d.chunks_built)
	print("  DECORSTATS: клеток декора %d (до прохода %d), по видам %s; чанк %.0f мкс в среднем, худший %d мкс; весь мир %.1f мс"
			% [d.cells, lazy_cells, str(by_kind), float(d.build_us) / float(chunks), d.build_us_max, all_ms])
	finish()


## Дальняя неисследованная пещера (воздух под рельефом).
func _far_unexplored() -> Vector2i:
	for x in range(8, World.W - 8, 5):
		if absi(x - World.beacon_cell.x) < 120:
			continue
		for y in range(World.surface[x] + 20, World.H - 10, 3):
			var c: Vector2i = Vector2i(x, y)
			if World.get_tile_v(c) == IDs.T.AIR and not World.is_explored(c) and not World.decor.is_built(c):
				return c
	return Vector2i(-1, -1)


## Сколько клеток прямоугольника расходятся с правилами (собранные чанки).
func _mismatch(d, x0: int, y0: int, w: int, h: int) -> int:
	var n: int = 0
	for y in range(maxi(y0, 0), mini(y0 + h, World.H)):
		for x in range(maxi(x0, 0), mini(x0 + w, World.W)):
			if d.is_built(Vector2i(x, y)) and d.decor_at(x, y) != d.expected_at(x, y):
				n += 1
	return n


func _snapshot(d) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(World.W * World.H)
	for y in World.H:
		for x in World.W:
			out[y * World.W + x] = d.decor_at(x, y)
	return out


## В каком биоме растёт вид (-1 — где угодно: стебель свечника, полка).
func _biome_of_kind(k: int) -> int:
	match k:
		Decor.K.BUBBLE_LO, Decor.K.BUBBLE_HI, Decor.K.PUFF:
			return 0
		Decor.K.HYPHAE_TOP, Decor.K.HYPHAE_LO, Decor.K.HYPHAE_SHORT, Decor.K.POLYPORE:
			return 1
		Decor.K.SACS, Decor.K.TUBES:
			return 2
	return -1


## Шляпка (x, y) стоит на столбе шляпок над стволом.
func _above_trunk(x: int, y: int) -> bool:
	if World.get_tile(x, y) != IDs.T.LEAVES:
		return false
	var yy: int = y + 1
	while World.get_tile(x, yy) == IDs.T.LEAVES:
		yy += 1
	return World.get_tile(x, yy) == IDs.T.TREE


func _find_kind(d, kinds: Array) -> Vector2i:
	for y in World.H:
		for x in World.W:
			if kinds.has(Decor.kind_of(d.decor_at(x, y))):
				return Vector2i(x, y)
	return Vector2i(-1, -1)
