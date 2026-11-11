class_name LightLate
extends RefCounted
## Площадка глав «Свет» 5–6 (ADR-005 § 9, #179).
##
## Смещения от релея. На сиде 31337 релей — (320, 43), пол — ряд 44.
## Коллектор на открытом небе справа. Белый идёт влево по ряду y−2,
## зеркало над маяком гнёт его вниз. Маяк у кромки ствола: радиус белого
## (8) достаёт до кристаллов в левой стене. Подвал глав 3–4 — справа, не здесь.


## Коллектор под небом, носик влево. На сиде 31337 колонка пуста до y = 0.
const COLLECTOR: Vector2i = Vector2i(14, -2)
## Зеркало на линии коллектора, над маяком. dir 0 «/»: влево (вход 2) → вниз.
## Ряд y−2 и x−8: сундук лагеря (cx−10) и горелка станции (cx−1) луч не режут.
const BEND: Vector2i = Vector2i(-8, -2)
## Маяк на полу, прямо под зеркалом. Белый показывает руду, синий морозит.
const PHAROS: Vector2i = Vector2i(-8, 0)
## Призма на пути белого: игрок видит, как луч делится. Синий в запас даёт горелка.
const PRISM: Vector2i = Vector2i(6, -2)
## Накопитель на полу, справа от маяка. Носик влево: ночной синий бьёт в маяк.
## Вход справа — горелка с кристаллом.
const ACCUM: Vector2i = Vector2i(-6, 0)
## Горелка синего, справа от накопителя, носик влево. На пути белого не стоит.
const BURNER: Vector2i = Vector2i(-5, 0)
## Второе зеркало набора — на полке над полом, пока не понадобится.
const MIRROR_SPARE: Vector2i = Vector2i(12, -4)
## Сундук топлива главы 6. Сундук лагеря (cx−10) и вентиляцию не перекрываем.
const CHEST: Vector2i = Vector2i(3, 0)
## Ядро ставим сюда, если игрок ещё не выбрал место.
## Левее ствола: коридор сценариев справа главу не сносит.
const CORE: Vector2i = Vector2i(-22, 0)
## Кристаллы в левой стене ствола, ряды от пола. Маяк в Chebyshev ≤ 8,
## герой у релея — дальше поверхностного тумана (16): белому есть что открыть.
const CRYSTAL_ROWS: Array[int] = [1, 2, 3, 4, 5, 6]
## Ночь главы 5, с. До главы 6 ночь не длиннее 60.
const NIGHT_SEC: float = 60.0
## Сколько синего копить на ночь, с.
const STORE_NEED: float = 30.0


static func at(off: Vector2i) -> Vector2i:
	return World.beacon_cell + off


static func world_at(off: Vector2i) -> Vector2:
	return World.cell_to_world(at(off))


## Левая стена ствола: клетка кристалла на ряду row (от пола базы).
static func crystal_cell(row: int) -> Vector2i:
	return Vector2i(World.beacon_cell.x + CampaignBase.SHAFT_X0 - 1, CampaignBase.floor_row() + row)


## Ближайший ещё не накопанный кристалл. Нет — верхний.
static func nearest_crystal() -> Vector2i:
	var best: Vector2i = crystal_cell(int(CRYSTAL_ROWS[0]))
	var best_d: int = 1 << 30
	var hero: Vector2i = World.beacon_cell
	if Game.player != null and is_instance_valid(Game.player):
		hero = World.world_to_cell(Game.player.global_position)
	for row in CRYSTAL_ROWS:
		var c: Vector2i = crystal_cell(int(row))
		if World.get_tile_v(c) != IDs.T.CRYSTAL_ORE:
			continue
		var d: int = absi(c.x - hero.x) + absi(c.y - hero.y)
		if d < best_d:
			best_d = d
			best = c
	return best


## Ствол слева от базы: проём SHAFT_*, стальные стены, кристаллы в левой.
## Пол штольни не роем — главам 5–6 хватает верхней части.
static func dig_shaft() -> void:
	var bx: int = World.beacon_cell.x
	var fl: int = CampaignBase.floor_row()
	var x0: int = bx + CampaignBase.SHAFT_X0
	var x1: int = bx + CampaignBase.SHAFT_X1
	var deep: int = int(CRYSTAL_ROWS[CRYSTAL_ROWS.size() - 1]) + 2
	# Проём и воздух над ним: зеркало у кромки не упирается в лишайник.
	CampaignBase.fill(x0, fl - 2, x1, fl + deep, IDs.T.AIR)
	# Стены ствола.
	CampaignBase.fill(x0 - 1, fl, x0 - 1, fl + deep, IDs.T.STEEL)
	CampaignBase.fill(x1 + 1, fl, x1 + 1, fl + deep, IDs.T.STEEL)
	CampaignBase.fill(x0 - 1, fl + deep + 1, x1 + 1, fl + deep + 1, IDs.T.STEEL)
	for row in CRYSTAL_ROWS:
		var c: Vector2i = crystal_cell(int(row))
		World.set_tile(c.x, c.y, IDs.T.CRYSTAL_ORE)
		# Туман: белый маяк открывает только неразведанную руду.
		if not World.explored.is_empty() and World.in_bounds(c.x, c.y):
			World.explored[c.y * World.W + c.x] = 0


## Воздух на линии белого и под зеркалом. Панели и лампы луч не пропускают.
static func clear_lane() -> void:
	var b: Vector2i = World.beacon_cell
	var y: int = b.y + COLLECTOR.y
	var x_from: int = b.x + BEND.x
	var x_to: int = b.x + COLLECTOR.x
	for x in range(x_from, x_to + 1):
		_air_cell(Vector2i(x, y))
	# Колонка от зеркала до маяка: луч идёт вниз сквозь воздух.
	var mx: int = b.x + BEND.x
	for yy in range(b.y + BEND.y, b.y + PHAROS.y + 1):
		_air_cell(Vector2i(mx, yy))
	# Колонка коллектора до неба: лист дерева — не твёрдый, но крышу не оставляем.
	var col: int = b.x + COLLECTOR.x
	for yy in range(0, b.y + COLLECTOR.y):
		var id: int = World.get_tile(col, yy)
		if id != IDs.T.AIR:
			World.set_tile(col, yy, IDs.T.AIR)
	# Пол между горелкой и маяком: синий идёт влево, в башню.
	for x in range(b.x + PHAROS.x + 1, b.x + BURNER.x):
		_air_cell(Vector2i(x, b.y))


## Воздух в клетке. Постройку лагеря не сносим — линию луча ведём мимо неё.
static func _air_cell(c: Vector2i) -> void:
	if World.machines.has(c):
		return
	if World.get_tile_v(c) != IDs.T.AIR:
		World.set_tile(c.x, c.y, IDs.T.AIR)


## Ближайшая вентиляция к базе. Нет — клетка у края площадки.
static func base_vent() -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var bd: int = 1 << 30
	var b: Vector2i = World.beacon_cell
	for v in World.vents:
		var d: int = absi(v.x - b.x) + absi(v.y - b.y)
		if d < bd:
			bd = d
			best = v
	if best.x < 0:
		best = b + Vector2i(-13, 0)
	return best
