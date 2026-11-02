extends "res://tools/mp/scenarios/mp_players_base.gd"
## mp_actions (ADR-002 § 4.2.3, D3; MP-D, #89): действия клиента выполняет хост.
##
## Клиент 0 своим героем (шов ввода) копает тайл, ставит его обратно и держит E у
## терминала под питанием. Хост выполняет это обычным кодом Player у прокси
## (test_input ← пакет ввода). Проверки:
##  * хост: тайл сломан, дроп подобрал прокси клиента 0, блок поставлен из его
##    инвентаря, задание терминала засчитано, терминал отработал;
##  * клиент 0: дроп в своём инвентаре (INV с хоста), индикатор копки своего героя
##    (своя строка STATE);
##  * клиент 1: марионетка клиента 0 копает ту же клетку; звуки копки, постройки и
##    терминала дошли в точке действия, крошки — эффектом. Тайлы у второго клиента —
##    дельты мира MP-C (#88): проверяются, если они есть в сборке.
## Замер: ввод → эффект на хосте (ЛКМ у клиента → копка у прокси, общие часы
## машины), мс; петля ввод → своя копка в STATE у клиента, мс.

## Твёрдость тайла для копки: копка ≤ 2.5 с (дроп должен ставиться тайлом — камень).
const MAX_HARD: float = 2.5
const MAX_DIST: float = 52.0

var _plan: Dictionary = {}
## c0: момент нажатия ЛКМ и первый кадр, когда своя строка STATE показала копку, мкс.
var _press_us: int = 0
var _seen_us: int = 0


func _physics_process(_delta: float) -> void:
	if role == 0 and _press_us > 0 and _seen_us == 0 and _plan.has("dig") 			and player.mining_cell == _plan["dig"] and player.mining_progress > 0.0:
		_seen_us = Time.get_ticks_usec()


# ------------------------------------------------------------------ ХОСТ

func run_host() -> void:
	ok("хост + %d клиента вошли" % clients, await wait_players(1 + clients, 45.0))
	ok("прокси обоих клиентов с вводом", await wait_proxies(clients, 10.0))
	await barrier("in")
	var p0: Player = hero_of(0)
	var p1: Player = hero_of(1)
	if p0 == null or p1 == null:
		finish()
		return
	# Свой герой хоста и клиент 1 — подальше: дроп подбирает ближайший живой герой.
	var sx: int = World.world_to_cell(World.spawn_point).x
	player.global_position = surface_stand(sx - 40)
	player.vel = Vector2.ZERO
	ok("клиент 1 переставлен поправкой", await teleport_proxy(p1, surface_stand(sx + 70)))
	# Клиент 0 — за пределы базы (там сталь), к рыхлому грунту и камню.
	var dig: Vector2i = Vector2i(-1, -1)
	for k in 12:
		var spot0: Vector2 = surface_stand(sx + 24 + k * 3)
		dig = _mineable_near(spot0)
		if dig.x >= 0:
			ok("клиент 0 переставлен поправкой к месту копки", await teleport_proxy(p0, spot0))
			await wait(0.5)
			dig = _mineable_near(p0.global_position)
			break

	# План: клетка копки рядом с клиентом 0 (дроп ставится тайлом), терминал базы.
	ok("найден тайл для копки (дроп ставится тайлом)", dig.x >= 0, str(dig))
	var term: Vector2i = _terminal()
	ok("есть терминал базы", term.x >= 0, str(term))
	if dig.x < 0 or term.x < 0:
		share_put("plan", {})
		await barrier("plan")
		await barrier("done")
		finish()
		return
	var tid: int = World.get_tile_v(dig)
	var drop: int = DB.tile_drop(tid)
	var put: int = int(DB.item_place(drop).substr(5))
	_plan = {"dig": dig, "drop": drop, "tid": tid, "put": put, "term": term}
	share_put("plan", _plan)
	await barrier("plan")

	# --- Копка: ЛКМ у клиента → копка у прокси на хосте.
	var drop0: int = p0.inv.count_of(drop)
	var started: bool = await wait_until(func() -> bool: return p0.mining_progress > 0.0, 5.0)
	var t_eff: float = wall_clock()
	ok("копка клиента идёт на хосте (прокси)", started and p0.mining_cell == dig, str(p0.mining_cell))
	var broke: bool = await wait_until(func() -> bool: return World.get_tile_v(dig) == IDs.T.AIR, 8.0)
	ok("хост: тайл сломан", broke, "%s → воздух" % DB.tile_name(tid))
	var got: bool = await wait_until(func() -> bool: return p0.inv.count_of(drop) > drop0, 5.0)
	ok("хост: дроп подобрал прокси клиента 0 (ближайший живой герой)", got,
			"%s %d → %d" % [DB.item_name(drop), drop0, p0.inv.count_of(drop)])
	ok("хост: свой герой и клиент 1 ничего не подобрали",
			player.inv.count_of(drop) == 0 and p1.inv.count_of(drop) == 0)
	await barrier("dug")
	var t_press = share_get("press")
	if t_press is float:
		print("  ЗАМЕР ввод → эффект на хосте (ЛКМ клиента → копка прокси, общие часы машины): %.0f мс" % [
				(t_eff - float(t_press)) * 1000.0])

	# --- Постройка: ПКМ у клиента → тайл из инвентаря прокси.
	var placed: bool = await wait_until(func() -> bool: return World.get_tile_v(dig) == put, 8.0)
	ok("хост: блок поставлен клиентом", placed, "%s в %s" % [DB.tile_name(World.get_tile_v(dig)), str(dig)])
	ok("хост: блок списан из инвентаря прокси", p0.inv.count_of(drop) == drop0,
			"%d" % p0.inv.count_of(drop))
	await barrier("placed")

	# --- Терминал: E у клиента → задание у хоста. ТЭЦ с углём рядом — питание.
	var spot: Vector2 = World.cell_to_world(term)
	var gen: CoalGen = _place_gen_near(term)
	ok("ТЭЦ у терминала", gen != null)
	if gen != null:
		gen.add_fuel(4)
	ok("терминал под питанием", await wait_until(func() -> bool: return Game.is_powered(spot), 3.0))
	var stand: Vector2 = _stand_near(spot)
	ok("клиент 0 переставлен к терминалу", await teleport_proxy(p0, stand))
	await wait(0.5)
	ok("прокси у терминала", p0.global_position.distance_to(spot) < 42.0,
			"%.1f px" % p0.global_position.distance_to(spot))
	var done0: int = Game.tasks_done
	await barrier("term")
	var read: bool = await wait_until(func() -> bool: return Game.tasks_done > done0, 8.0)
	ok("хост: задание терминала засчитано по E клиента", read, "%d → %d" % [done0, Game.tasks_done])
	ok("хост: терминал отработал", World.get_tile_v(term) == IDs.T.PANEL and not World.terminals.has(term))
	await barrier("read")
	await barrier("done")
	share_clear(["plan", "press"])
	finish()


## Клетка рядом с героем: дроп ставится тайлом, не твёрже MAX_HARD; из таких —
## самая твёрдая (копка длится, её видно в нескольких пакетах), потом ближайшая.
## Не дальше MAX_DIST: дроп падает у клетки и должен притянуться к герою (70 px).
func _mineable_near(pos: Vector2) -> Vector2i:
	var pc: Vector2i = World.world_to_cell(pos)
	var best: Vector2i = Vector2i(-1, -1)
	var best_score: float = -INF
	for dy in range(-2, 4):
		for dx in range(-5, 6):
			var c: Vector2i = pc + Vector2i(dx, dy)
			var t: int = World.get_tile_v(c)
			if t == IDs.T.AIR or DB.tile_hard(t) > MAX_HARD or DB.tile_drop(t) == IDs.I.NONE:
				continue
			if not DB.item_place(DB.tile_drop(t)).begins_with("tile:"):
				continue
			var d: float = World.cell_to_world(c).distance_to(pos)
			if d > MAX_DIST or d < 14.0:
				continue
			var score: float = DB.tile_hard(t) * 100.0 - d
			if score > best_score:
				best_score = score
				best = c
	return best


func _terminal() -> Vector2i:
	for t in World.terminals:
		if int(World.terminal_chapters.get(t, -1)) == 0:
			return t
	return World.terminals[0] if not World.terminals.is_empty() else Vector2i(-1, -1)


func _stand_near(spot: Vector2) -> Vector2:
	for o in [Vector2(0, -24), Vector2(24, 0), Vector2(-24, 0), Vector2(24, -24), Vector2(-24, -24)]:
		var p: Vector2 = spot + o
		if not World.rect_solid(Rect2(p - Player.SIZE * 0.5, Player.SIZE)):
			return p
	return spot + Vector2(0, -24)


## Как в terminal_powered: ТЭЦ на свободной клетке с полом рядом с терминалом.
func _place_gen_near(t: Vector2i) -> CoalGen:
	for r in range(2, 7):
		for dy in range(-3, 2):
			for dx in [-r, r]:
				var c: Vector2i = t + Vector2i(int(dx), dy)
				if World.get_tile_v(c) != IDs.T.AIR or not World.is_solid_cell(c + Vector2i(0, 1)):
					continue
				if MachineBase.place_machine("CoalGen", c):
					return World.machines.get(c) as CoalGen
	return null


# ------------------------------------------------------------------ КЛИЕНТЫ

func run_client(i: int) -> void:
	await barrier("in")
	if i == 1:
		ok("c1: марионетка клиента 0 есть", await wait_puppets([0], 10.0))
	await barrier("plan")
	var plan = share_get("plan")
	if not (plan is Dictionary) or (plan as Dictionary).is_empty():
		ok("c%d: план сценария получен" % i, false)
		await barrier("done")
		finish()
		return
	_plan = plan
	if i == 0:
		await _actor()
	else:
		await _watcher()
	await barrier("done")
	finish()


func _actor() -> void:
	var dig: Vector2i = _plan["dig"]
	var drop: int = int(_plan["drop"])
	var have0: int = player.inv.count_of(drop)
	# Копка: навести и держать ЛКМ, пока хост не сломает тайл и не отдаст дроп.
	aim(World.cell_to_world(dig))
	share_put("press", wall_clock())
	_press_us = Time.get_ticks_usec()
	press_mouse(MOUSE_BUTTON_LEFT)
	var seen: bool = await wait_until(func() -> bool: return _seen_us > 0, 5.0)
	ok("c0: индикатор копки своего героя (своя строка STATE)", seen)
	if seen:
		print("  ЗАМЕР c0: петля ЛКМ → копка на хосте → своя строка STATE: %.0f мс" % [
				float(_seen_us - _press_us) / 1000.0])
	var got: bool = await wait_until(func() -> bool: return player.inv.count_of(drop) > have0, 10.0)
	release_mouse(MOUSE_BUTTON_LEFT)
	ok("c0: дроп в своём инвентаре (INV с хоста)", got,
			"%s %d → %d" % [DB.item_name(drop), have0, player.inv.count_of(drop)])
	await barrier("dug")
	# Постройка: выбрать слот с дропом цифрой (шов ввода), навести, ПКМ.
	var slot: int = -1
	for k in player.inv.hotbar_size:
		if player.inv.slots[k].id == drop:
			slot = k
			break
	ok("c0: дроп в хотбаре", slot >= 0, "слот %d" % slot)
	if slot >= 0:
		var key: int = KEY_1 + slot if slot < 9 else KEY_0
		hold(key)
		await wait(0.1)
		release(key)
		ok("c0: слот выбран", player.inv.selected == slot)
		await wait(0.15)
		press_mouse(MOUSE_BUTTON_RIGHT)
		await wait(0.3)
		release_mouse(MOUSE_BUTTON_RIGHT)
		var spent: bool = await wait_until(func() -> bool: return player.inv.count_of(drop) == have0, 4.0)
		ok("c0: блок списан из своего инвентаря (INV)", spent, "%d" % player.inv.count_of(drop))
	await barrier("placed")
	# Терминал: хост переставил героя к терминалу; держать E.
	await barrier("term")
	hold(KEY_E)
	await barrier("read", -1, 15.0)
	release(KEY_E)


func _watcher() -> void:
	var dig: Vector2i = _plan["dig"]
	var at: Vector2 = World.cell_to_world(dig)
	var pup: Player = hero_of(0)
	var mined: bool = false
	var t_end: float = now() + 15.0
	# До барьера «dug»: марионетка копает ту же клетку.
	while now() < t_end and not mined:
		if pup != null and pup.mining_cell == dig and pup.mining_progress > 0.0:
			mined = true
		await wait(0.02)
	ok("c1: марионетка клиента 0 копает ту же клетку (STATE)", mined)
	await barrier("dug")
	# Звук — в точке героя (копает он), крошки — в клетке.
	var r: float = Player.REACH + 16.0
	ok("c1: звук копки дошёл в точке героя", events_near(NetCodec.Ev.SOUND, "sound", "mine", at, r) > 0)
	ok("c1: звук разрушения дошёл в точке героя", events_near(NetCodec.Ev.SOUND, "sound", "break", at, r) > 0)
	ok("c1: крошки — эффектом", events_near(NetCodec.Ev.FX, "kind", NetCodec.Fx.CHIP_TILE, at, 24.0) > 0)
	if has_world_deltas():
		ok("c1: тайл сломан и у второго клиента (MP-C)", await wait_until(func() -> bool:
			return World.get_tile_v(dig) == IDs.T.AIR or World.get_tile_v(dig) == int(_plan["put"]), 3.0))
	else:
		print("  ПРОПУСК c1: тайлы у второго клиента — дельты мира MP-C (#88), их нет в этой сборке")
	await barrier("placed")
	var p: Vector2 = pup.global_position if pup != null else at
	ok("c1: звук постройки дошёл", events_near(NetCodec.Ev.SOUND, "sound", "place", p, Player.REACH + 24.0) > 0)
	if has_world_deltas():
		ok("c1: блок стоит и у второго клиента (MP-C)", await wait_until(func() -> bool:
			return World.get_tile_v(dig) == int(_plan["put"]), 3.0))
	await barrier("term")
	await barrier("read", -1, 15.0)
	var term: Vector2 = World.cell_to_world(_plan["term"])
	ok("c1: звук прочитанного терминала дошёл в точке", await wait_until(func() -> bool:
		return events_near(NetCodec.Ev.SOUND, "sound", "craft", term, 64.0) > 0, 2.0))
	if has_world_deltas():
		var tc: Vector2i = _plan["term"]
		ok("c1: терминал отработал и у второго клиента (MP-C)", await wait_until(func() -> bool:
			return World.get_tile_v(tc) == IDs.T.PANEL, 3.0))
