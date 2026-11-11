extends "res://tools/scenarios/balance_common.gd"
## Бот баланса «релей руками» (#33, ADR-001 § 2: руками ≥ 25 мин добычи).
##
## 1. Бюджет: детали релея (Balance.RELAY_REQ) + станки, без которых деталь
##    не сделать (сборщик, плавильня, ТЭЦ), раскладываются до сырья по ручным
##    рецептам (2 руды → 1 слиток); что руками не делается (сталь, микросхемы,
##    ячейки, антенна) — по рецепту станка, но его вход — снова руками.
##    Минус стартовый набор, плюс уголь на работу станков.
## 2. Замер: бот копает каждое сырьё через шов ввода — наводит «мышь» на тайл,
##    держит ЛКМ, ждёт, пока предмет долетит до него (магнит), — и засекает
##    игровые секунды на единицу. Берёт самый мягкий тайл, из которого это
##    сырьё падает (хлам — из земли, камень — из песчаника, если он есть).
## 3. Итог: Σ бюджет × секунд на единицу = минут чистой добычи до релея.
##
## Честно: переходы между жилами не засчитаны — бот ставится к ближайшей
## необработанной жиле (телепорт), засекается только копка и подбор.
## Ручной крафт в игре мгновенный, поэтому в итог не входит.

const TARGET_MIN: float = 25.0      ## ADR-001 § 2
const SAMPLE_MAIN: int = 10         ## проб на сырьё, которого в бюджете ≥ 20
const SAMPLE_MINOR: int = 4
const PICK_PX: float = 60.0         ## копаем не дальше магнита предметов (70 px)
const SPEED: float = 3.0


func run() -> void:
	player.invuln = 1.0e9
	Game.time_of_day = 0.30
	speed_up(SPEED)
	await wait_game(0.3)

	# ---- 1. бюджет
	var need: Dictionary = {}
	var st_time: Dictionary = {}
	var basket: Dictionary = Balance.RELAY_REQ.duplicate()
	for m in [IDs.I.ASSEMBLER, IDs.I.SMELTER, IDs.I.COAL_GEN]:
		basket[m] = int(basket.get(m, 0)) + 1
	for id in basket.keys():
		expand(int(id), int(basket[id]), ["hand"], need, [], st_time)
	# Уголь на работу станков (сталь, микросхемы, ячейки, антенна — не руками).
	var machine_secs: float = float(st_time.get("smelter", 0.0)) + float(st_time.get("assembler", 0.0))
	need[IDs.I.COAL] = int(need.get(IDs.I.COAL, 0)) + int(ceil(machine_secs / Balance.COAL_BURN))
	# Стартовый набор (как в ScenarioRunner._reset_world и в обычной игре).
	# Медной руды в наборе нет (#171): слиток открывается первым подбором.
	var kit: Dictionary = {}
	for id in [IDs.I.COAL, IDs.I.STONE, IDs.I.SCRAP]:
		expand(int(id), _start_count(int(id)), ["hand"], kit)
	for id in kit.keys():
		need[id] = maxi(0, int(need.get(id, 0)) - int(kit[id]))
	print("  [бюджет руками] %s" % items_str(need))
	print("  [станки] плавильня %.0f с, сборщик %.0f с работы" % [
			float(st_time.get("smelter", 0.0)), float(st_time.get("assembler", 0.0))])
	ok("бюджет релея разложен до сырья", not need.is_empty())

	# ---- 2. замер секунд на единицу
	var total: float = 0.0
	var all_measured: bool = true
	for id in need.keys():
		var n: int = int(need[id])
		if n <= 0:
			continue
		var sample: int = SAMPLE_MAIN if n >= 20 else SAMPLE_MINOR
		# Самый мягкий тайл с этим сырьём, у которого нашлась доступная жила.
		var tile: int = -1
		var res: Dictionary = {}
		for t in _tiles_for(int(id)):
			res = await _measure(int(t), sample)
			if int(res["mined"]) > 0:
				tile = int(t)
				break
		if tile < 0:
			print("  не нашлось жилы для %s" % DB.item_name(int(id)))
			all_measured = false
			continue
		var spu: float = float(res["secs"]) / float(res["mined"])
		total += spu * float(n)
		print("  [добыча] %-16s ×%3d: %.2f с/ед (твёрдость %.1f; %d проб, подобрано %d) → %.1f мин" % [
				DB.item_name(int(id)), n, spu, DB.tile_hard(tile), int(res["mined"]),
				int(res["picked"]), spu * float(n) / 60.0])
	ok("каждое сырьё измерено ботом", all_measured)
	var minutes: float = total / 60.0
	metric("hand_relay_min", minutes, "минут чистой добычи руками до релея")
	ok("релей руками ≥ %.0f мин добычи" % TARGET_MIN, minutes >= TARGET_MIN, "%.1f мин" % minutes)
	finish()


func _start_count(id: int) -> int:
	match id:
		IDs.I.COAL: return 6
		IDs.I.STONE: return 4
		IDs.I.SCRAP: return 4
	return 0


## Тайлы, из которых падает это сырьё, — от мягкого к твёрдому.
func _tiles_for(item: int) -> Array:
	var out: Array = []
	for tid in DB.tile_defs.keys():
		if DB.tile_drop(int(tid)) != item:
			continue
		if DB.tile_hard(int(tid)) > 100.0:
			continue
		out.append(int(tid))
	out.sort_custom(func(a, b): return DB.tile_hard(a) < DB.tile_hard(b))
	return out


## Накопать sample тайлов вида tile у ближайших к старту жил. Возвращает
## {secs, mined, picked}: игровые секунды копки+подбора, тайлов, подобрано.
func _measure(tile: int, sample: int) -> Dictionary:
	var item: int = DB.tile_drop(tile)
	var cells: Array = []
	for y in World.H:
		for x in World.W:
			if World.get_tile(x, y) == tile:
				cells.append(Vector2i(x, y))
	var from: Vector2 = World.spawn_point
	cells.sort_custom(func(a, b): return World.cell_to_world(a).distance_squared_to(from) \
			< World.cell_to_world(b).distance_squared_to(from))
	var secs: float = 0.0
	var mined: int = 0
	var picked: int = 0
	var tries: int = 0
	for target in cells:
		if mined >= sample or tries > 300:
			break
		if World.get_tile_v(target) != tile:
			continue
		tries += 1
		var stand: Vector2i = _stand_cell_for(target)
		if stand.x < 0:
			continue
		release_all()
		release_mouse(MOUSE_BUTTON_LEFT)
		stand_at_cell(stand)
		await wait_game(0.25)
		# Жила вокруг: все тайлы этого вида в досягаемости магнита, ближние первыми.
		var vein: Array = _vein_around(tile)
		if vein.is_empty():
			continue
		var inv0: int = player.inv.count_of(item)
		var t0: float = clock
		var got: int = 0
		for c in vein:
			if mined + got >= sample:
				break
			aim(World.cell_to_world(c))
			press_mouse(MOUSE_BUTTON_LEFT)
			var limit: float = DB.tile_hard(tile) * 2.0 + 1.0
			if await wait_game_until(func() -> bool: return World.get_tile_v(c) != tile, limit):
				got += 1
		release_mouse(MOUSE_BUTTON_LEFT)
		# Подбор: предметы летят к герою магнитом.
		await wait_game_until(func() -> bool: return player.inv.count_of(item) - inv0 >= got, 2.0)
		secs += clock - t0
		mined += got
		picked += player.inv.count_of(item) - inv0
	release_mouse(MOUSE_BUTTON_LEFT)
	return {"secs": secs, "mined": mined, "picked": picked}


## Клетка, где герой стоит (два воздуха, пол снизу) в радиусе PICK_PX от цели.
func _stand_cell_for(target: Vector2i) -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: float = INF
	var tw: Vector2 = World.cell_to_world(target)
	for dy in range(-5, 6):
		for dx in range(-5, 6):
			var c: Vector2i = target + Vector2i(dx, dy)
			if not _free(c) or not _free(c + Vector2i(0, -1)):
				continue
			if not World.is_solid_cell(c + Vector2i(0, 1)):
				continue
			var pos: Vector2 = Vector2(float(c.x * World.TILE) + 8.0, float((c.y + 1) * World.TILE) - 11.0)
			var d: float = pos.distance_to(tw)
			if d <= PICK_PX and d < best_d:
				best_d = d
				best = c
	return best


func _free(c: Vector2i) -> bool:
	var t: int = World.get_tile_v(c)
	return t == IDs.T.AIR


func _vein_around(tile: int) -> Array:
	var out: Array = []
	var pc: Vector2i = World.world_to_cell(player.global_position)
	for dy in range(-5, 6):
		for dx in range(-5, 6):
			var c: Vector2i = pc + Vector2i(dx, dy)
			if World.get_tile_v(c) != tile:
				continue
			if World.cell_to_world(c).distance_to(player.global_position) > PICK_PX:
				continue
			out.append(c)
	var p: Vector2 = player.global_position
	out.sort_custom(func(a, b): return World.cell_to_world(a).distance_squared_to(p) \
			< World.cell_to_world(b).distance_squared_to(p))
	return out
