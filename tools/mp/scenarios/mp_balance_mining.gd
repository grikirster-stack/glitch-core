extends "res://tools/mp/scenarios/mp_balance_common.gd"
## mp_balance_mining (ADR-002 § 2 «первая победа 4 игроков 30–45 мин», § 8 вопрос 3; MP-K, #96):
## добыча руками по сети — N героев копают одновременно.
##
## Сетевая часть замера balance_hand (#33): хост ставит каждого героя к своей жиле
## железной руды (самый мягкий тайл с этим дропом, жилы ≥ GAP клеток друг от друга —
## магнит не таскает чужое), каждый процесс копает своим швом (мышь на тайл, ЛКМ) и
## засекает секунды забега от начала копки до «руда в моём инвентаре». У клиента это
## путь человека по сети: ЛКМ → ввод хосту → копает прокси → предмет летит магнитом
## к прокси → INV клиенту. ROUNDS раундов по VEINS жил, с каждой — PER_ROUND единиц:
## при N = 1 хост обходит жилы раунда по очереди, при N = 4 их копают разом.
##
## Итог — с/ед (среднее по героям и худший герой). Зонд делит: M_N = M1 · (с/ед при N ÷
## с/ед при N = 1) ÷ N — минут чистой добычи релея руками командой (M1 — balance_hand).

const ROUNDS: int = 3
const VEINS: int = 4          ## жил в раунде (= MP_MAX_PLAYERS): при любом N — те же
const PER_ROUND: int = 4
const GAP: int = 10
const PICK_PX: float = 60.0

var _steps: Array = []        ## хост: шагов в каждом раунде (для уборки файлов обмена)


# ------------------------------------------------------------------ ХОСТ

func run_host() -> void:
	if not await host_join():
		finish()
		return
	await barrier("in")
	Game.time_of_day = 0.30
	clear_phantoms()
	for h in heroes():
		if h != null:
			(h as Player).invuln = 1.0e9
	var tile: int = ore_tile()
	ok("тайл железной руды", tile >= 0, DB.tile_name(tile) if tile >= 0 else "")
	var placed_all: bool = true
	for r in ROUNDS:
		# Жил в раунде всегда VEINS — при любом N те же жилы: N = 1 копает их по очереди,
		# N = 4 — разом. Сравнение с/ед при N и при N = 1 — на одной и той же руде.
		var stands: Array = pick_stands(tile, VEINS)
		placed_all = placed_all and stands.size() == VEINS
		var steps: int = ceili(float(stands.size()) / float(heroes_n()))
		for st in steps:
			var busy: Array = []
			for k in heroes_n():
				var idx: int = st * heroes_n() + k
				busy.append(idx < stands.size())
				if idx < stands.size():
					await place_hero(k, stand_pos(stands[idx]))
			share_put("busy_%d_%d" % [r, st], busy)
			await wait(0.3)
			await barrier("r%d_%d" % [r, st], -1, 30.0)
			if bool(busy[0]):
				await mine_round(tile)
			await barrier("r%d_%d_done" % [r, st], -1, 60.0)
		_steps.append(steps)
		await barrier("r%d_steps" % r, -1, 30.0)
	ok("жилы для всех героев во всех раундах", placed_all)
	await barrier("shared", -1, 30.0)
	var spu: Array = [_spu()]
	var detail: Array = ["хост %.2f с/ед (%d ед)" % [_spu(), _mined]]
	for i in clients:
		var v = share_get("mine_%d" % i)
		if v is Dictionary and int(v["mined"]) > 0:
			spu.append(float(v["secs"]) / float(v["mined"]))
			detail.append("c%d %.2f с/ед (%d ед)" % [i, spu[spu.size() - 1], int(v["mined"])])
	print("  [добыча, N = %d] %s; %s" % [heroes_n(), DB.tile_name(tile), "; ".join(detail)])
	ok("все %d героя накопали" % heroes_n(), spu.size() == heroes_n() and amin(spu) > 0.0)
	metric("mine_spu", mean(spu), "с на единицу руды, среднее по героям")
	metric("mine_spu_max", vmax_a(spu), "с/ед у самого медленного героя")
	await barrier("done", -1, 30.0)
	var keys: Array = []
	for i in clients:
		keys.append("mine_%d" % i)
	for r in _steps.size():
		for st in int(_steps[r]):
			keys.append("busy_%d_%d" % [r, st])
	share_clear(keys)
	finish()


## Места «стоя у жилы» для k героев: ближние к старту необработанные жилы, где в радиусе
## магнита ≥ PER_ROUND тайлов руды, ≥ GAP клеток друг от друга.
func pick_stands(tile: int, k: int) -> Array:
	var cells: Array = []
	for y in World.H:
		for x in World.W:
			if World.get_tile(x, y) == tile:
				cells.append(Vector2i(x, y))
	var from: Vector2 = World.spawn_point
	cells.sort_custom(func(a, b): return World.cell_to_world(a).distance_squared_to(from) \
			< World.cell_to_world(b).distance_squared_to(from))
	var out: Array = []
	var tries: int = 0
	for target in cells:
		if out.size() >= k or tries > 600:
			break
		tries += 1
		var far: bool = true
		for o in out:
			if (o as Vector2i).distance_to(target) < float(GAP):
				far = false
		if not far:
			continue
		var stand: Vector2i = _stand_cell_for(target)
		if stand.x < 0 or vein_around(tile, stand_pos(stand)).size() < PER_ROUND:
			continue
		out.append(stand)
	return out


# ------------------------------------------------------------------ КЛИЕНТЫ

func run_client(i: int) -> void:
	await barrier("in", -1, 60.0)
	var tile: int = ore_tile()
	for r in ROUNDS:
		var st: int = 0
		while true:
			# Шаг раунда: хост расставил героев; занят ли я — из файла обмена.
			var passed: bool = await barrier_or("r%d_%d" % [r, st], "r%d_steps" % r)
			if not passed:
				break
			var busy = share_get("busy_%d_%d" % [r, st])
			if busy is Array and int(i) + 1 < (busy as Array).size() and bool(busy[i + 1]):
				await mine_round(tile)
			await barrier("r%d_%d_done" % [r, st], -1, 60.0)
			st += 1
	share_put("mine_%d" % i, {"secs": _secs, "mined": _mined})
	ok("c%d: накопал %d ед за %.1f с" % [i, _mined, _secs], _mined > 0)
	await barrier("shared", -1, 30.0)
	await barrier("done", -1, 30.0)
	finish()


## Клиент: дойти до барьера a; если хост вместо него объявил барьер b (шаги раунда
## кончились) — false. Хост отпускает a только тем, кто до него дошёл, поэтому клиент
## шлёт оба и ждёт, какой отпустят первым.
func barrier_or(a: String, b: String) -> bool:
	Net.send(NetCodec.Msg.BARRIER, NetCodec.encode_str8(a))
	Net.send(NetCodec.Msg.BARRIER, NetCodec.encode_str8(b))
	var ok_a: bool = await wait_until(func() -> bool: return mp()._passed.has(a) or mp()._passed.has(b), 90.0)
	return ok_a and mp()._passed.has(a)


# ------------------------------------------------------------------ КОПКА (свой герой процесса)

var _secs: float = 0.0
var _mined: int = 0


## Накопать до PER_ROUND тайлов жилы вокруг своего героя; засечь с от первой копки до
## последнего подобранного в свой инвентарь.
func mine_round(tile: int) -> void:
	var item: int = DB.tile_drop(tile)
	var vein: Array = vein_around(tile, player.global_position)
	if vein.is_empty():
		return
	var inv0: int = player.inv.count_of(item)
	var t0: float = Game.game_time
	var got: int = 0
	for c in vein:
		if got >= PER_ROUND:
			break
		aim(World.cell_to_world(c))
		press_mouse(MOUSE_BUTTON_LEFT)
		var limit: float = DB.tile_hard(tile) * 2.0 + 2.0
		if await wait_until(func() -> bool: return World.get_tile_v(c) != tile, limit):
			got += 1
	release_mouse(MOUSE_BUTTON_LEFT)
	await wait_until(func() -> bool: return player.inv.count_of(item) - inv0 >= got, 4.0)
	_secs += Game.game_time - t0
	_mined += mini(got, player.inv.count_of(item) - inv0)


func _spu() -> float:
	return _secs / float(_mined) if _mined > 0 else 0.0


## Самый мягкий тайл, из которого падает железная руда (как balance_hand._tiles_for).
static func ore_tile() -> int:
	var best: int = -1
	for tid in DB.tile_defs.keys():
		if DB.tile_drop(int(tid)) != IDs.I.IRON_ORE or DB.tile_hard(int(tid)) > 100.0:
			continue
		if best < 0 or DB.tile_hard(int(tid)) < DB.tile_hard(best):
			best = int(tid)
	return best


## Клетка, где герой стоит (два воздуха, пол) в радиусе PICK_PX от цели (balance_hand).
func _stand_cell_for(target: Vector2i) -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: float = INF
	var tw: Vector2 = World.cell_to_world(target)
	for dy in range(-5, 6):
		for dx in range(-5, 6):
			var c: Vector2i = target + Vector2i(dx, dy)
			if World.get_tile_v(c) != IDs.T.AIR or World.get_tile_v(c + Vector2i(0, -1)) != IDs.T.AIR:
				continue
			if not World.is_solid_cell(c + Vector2i(0, 1)):
				continue
			var d: float = stand_pos(c).distance_to(tw)
			if d <= PICK_PX and d < best_d:
				best_d = d
				best = c
	return best


## Тайлы tile в радиусе магнита от точки, ближние первыми.
static func vein_around(tile: int, at: Vector2) -> Array:
	var out: Array = []
	var pc: Vector2i = World.world_to_cell(at)
	for dy in range(-5, 6):
		for dx in range(-5, 6):
			var c: Vector2i = pc + Vector2i(dx, dy)
			if World.get_tile_v(c) == tile and World.cell_to_world(c).distance_to(at) <= PICK_PX:
				out.append(c)
	out.sort_custom(func(a, b): return World.cell_to_world(a).distance_squared_to(at) \
			< World.cell_to_world(b).distance_squared_to(at))
	return out


static func vmax_a(a: Array) -> float:
	var m: float = 0.0
	for v in a:
		m = maxf(m, float(v))
	return m
