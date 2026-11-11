extends ScenarioBase
## Небесный тайник (#60): высоко над рельефом висит обломок «Кербер-9» с сундуком
## и самописцем. С земли он — тёмный силуэт, допрыгнуть нельзя. Бот берёт камень
## (как добытый), ставит блоки ПКМ прямо в воздух лесенкой 1:1, прыгает по ним,
## выходит на пол обломка, открывает сундук по E — обрывок журнала уходит в Tech.
## Потом мир пересоздаётся: тот же сид — тот же тайник, другой — другой.
##
## Сценарий только расчищает коридор под лестницу (рельеф и деревья над её линией,
## как stand_in_corridor у базы) — строит и лезет бот сам, через шов ввода.

const STEP_SECS: float = 2.5           # на один шаг лестницы


func run() -> void:
	var sc: Dictionary = World.sky_cache
	ok("в мире есть небесный тайник", not sc.is_empty(), "«%s»" % String(sc.get("name", "")))
	if sc.is_empty():
		finish()
		return
	var x0: int = int(sc["x0"])
	var fy: int = int(sc["floor_y"])
	var wreck = sc["wreck"]
	var chest = sc["chest"]

	# Начало лестницы: колонка слева от носа, откуда лесенка 1:1 доходит до пола.
	var xs: int = -1
	var b0: int = 0
	for d in range(3, x0 - 1):
		var g: int = _ground_row(x0 - 1 - d, fy + 3)
		if g - fy <= d:
			xs = x0 - 1 - d
			b0 = g
			break
	ok("слева от обломка есть место под лестницу", xs >= 1, "старт x=%d, земля y=%d, пол y=%d" % [xs, b0, fy])
	if xs < 1:
		finish()
		return
	var cleared: int = _clear_corridor(xs, b0, x0, fy)
	stand_at_cell(Vector2i(xs, b0 - 1))
	await wait(0.5)
	ok("герой стоит на земле под обломком", player.on_ground, "расчищено клеток: %d" % cleared)
	ok("с земли обломок — тёмный силуэт", wreck.haze > Balance.SKY_HAZE_ALPHA * 0.9 and not wreck.announced,
			"затемнение %.2f" % wreck.haze)

	# Прыжок с земли: голова не достаёт даже до днища.
	var y0: float = player.global_position.y
	var min_y: float = y0
	hold(KEY_SPACE)
	var t0: float = now()   # игровые часы: под нагрузкой физика отстаёт от стены (#71)
	while now() - t0 < 0.9:
		min_y = minf(min_y, player.global_position.y)
		await wait(0.02)
	release(KEY_SPACE)
	await wait_until(func() -> bool: return player.on_ground, 2.0)
	var head: float = min_y - Player.SIZE.y * 0.5
	var bottom_px: float = float((int(sc["bottom"]) + 1) * World.TILE)
	ok("с земли не допрыгнуть", head > bottom_px + float(World.TILE),
			"прыжок %.0f px, до днища осталось %.0f px" % [y0 - min_y, head - bottom_px])

	# Блоки — камень, как добытый киркой; выбрать его в хотбаре клавишей.
	player.inv.add(IDs.I.STONE, 40)
	var slot: int = -1
	for i in 9:
		var s: ItemStack = player.inv.slots[i]
		if not s.is_empty() and s.id == IDs.I.STONE:
			slot = i
			break
	ok("камень в хотбаре", slot >= 0)
	slot = maxi(slot, 0)
	hold(KEY_1 + slot)
	await wait(0.1)
	release(KEY_1 + slot)
	ok("камень выбран", player.inv.selected == slot)

	# Лестница: блок справа на уровень выше ног, прыжок на него; на высоте пола — мостик.
	var placed: int = 0
	var steps: int = 0
	var why: String = ""
	var t_build: int = Time.get_ticks_msec()
	for _guard in 80:
		var px: int = floori(player.global_position.x / World.TILE)
		var b: int = _feet_row()
		if px >= x0 and b == fy:
			break
		var up: bool = b > fy
		var target: Vector2i = Vector2i(px + 1, b - 1 if up else b)
		if World.get_tile_v(target) == IDs.T.AIR:
			if not await _place(target):
				why = "блок не встал в %s (герой x=%.1f)" % [str(target), player.global_position.x]
				break
			placed += 1
		if not await _step_to(px + 1, up):
			why = "шаг на колонку %d не удался (герой %s)" % [px + 1, str(player.global_position)]
			break
		steps += 1
	var on_wreck: bool = player.on_ground and _feet_row() == fy \
			and floori(player.global_position.x / World.TILE) >= x0
	ok("бот достроился до обломка лестницей из блоков", on_wreck and placed >= int(sc["clearance"]),
			"блоков %d, шагов %d, %.1f с %s" % [placed, steps,
			float(Time.get_ticks_msec() - t_build) / 1000.0, why])
	if not on_wreck:
		release_all()
		finish()
		return

	# По полу — к сундуку, E — открыть.
	var cx: float = World.cell_to_world(sc["cell"]).x
	hold(KEY_D)
	await wait_until(func() -> bool: return player.global_position.x >= cx - 20.0, 3.0)
	release(KEY_D)
	await wait(0.3)
	ok("вблизи обломок проступает из силуэта", wreck.haze < 0.1 and wreck.announced,
			"затемнение %.2f" % wreck.haze)
	hold(KEY_E)
	var opened: bool = await wait_until(func() -> bool:
		return UI.panel.visible and UI.panel.chest == chest, 3.0)
	release(KEY_E)
	ok("небесный тайник открывается по E", opened)
	var loot: Array = _loot(chest)
	ok("в тайнике 3–6 предметов", loot.size() >= Balance.SKY_CACHE_MIN and loot.size() <= Balance.SKY_CACHE_MAX,
			str(loot))
	ok("линза лежит в тайнике", _count(chest, IDs.I.LENS) >= 1, "линз %d" % _count(chest, IDs.I.LENS))
	await wait(0.2)
	ok("при первом открытии обрывок журнала — в Tech", wreck.opened and Tech.fragments.has(sc["fragment"]),
			"«%s»" % String(sc["fragment"]))
	if UI.panel.visible:
		UI.panel.close()

	# Детерминизм: тот же сид — тот же тайник, другой сид — другой.
	var seed0: int = World.world_seed
	var snap0: Array = _snapshot()
	_regen(seed0)
	ok("тот же сид — тот же небесный тайник", _snapshot() == snap0, str(snap0.slice(0, 3)))
	_regen(seed0 + 7)
	var snap1: Array = _snapshot()
	ok("другой сид — другой небесный тайник", not snap1.is_empty() and snap1 != snap0,
			str(snap1.slice(0, 3)))
	_regen(seed0)
	release_all()
	player.global_position = World.spawn_point
	player.vel = Vector2.ZERO
	finish()


## Первая твёрдая клетка в колонке x начиная с ряда from (земля под лестницей).
func _ground_row(x: int, from: int) -> int:
	for y in range(from, World.H):
		if World.is_solid_cell(Vector2i(x, y)):
			return y
	return World.H - 1


## Ряд клетки, на которой стоят ноги героя.
func _feet_row() -> int:
	return int(floor((player.global_position.y + Player.SIZE.y * 0.5 + 0.5) / float(World.TILE)))


## Над линией лестницы (xs..x0-1) не должно быть ни рельефа, ни деревьев.
func _clear_corridor(xs: int, b0: int, x0: int, fy: int) -> int:
	var n: int = 0
	for x in range(xs, x0):
		var row: int = maxi(b0 - (x - xs), fy)
		for y in range(fy - 4, row + 1):
			var t: int = World.get_tile_v(Vector2i(x, y))
			if t == IDs.T.AIR or (y == row and World.is_solid_cell(Vector2i(x, y))):
				continue
			World.set_tile(x, y, IDs.T.AIR)
			n += 1
	return n


## Навести мышь на клетку и держать ПКМ, пока там не встанет камень.
func _place(cell: Vector2i) -> bool:
	aim(World.cell_to_world(cell))
	press_mouse(MOUSE_BUTTON_RIGHT)
	var done_ok: bool = await wait_until(func() -> bool:
		return World.get_tile_v(cell) == IDs.T.STONE, 1.5)
	release_mouse(MOUSE_BUTTON_RIGHT)
	return done_ok


## Шагнуть (или запрыгнуть, up) на колонку col и встать в её середине.
func _step_to(col: int, up: bool) -> bool:
	var cx: float = float(col * World.TILE) + World.TILE * 0.5
	if up:
		hold(KEY_SPACE)
	hold(KEY_D)
	var reached: bool = await wait_until(func() -> bool:
		return player.global_position.x >= cx - 6.0, STEP_SECS)
	release(KEY_D)
	release(KEY_SPACE)
	var landed: bool = await wait_until(func() -> bool:
		return player.on_ground and absf(player.vel.x) < 1.0, STEP_SECS)
	# Подровняться: следующий блок не должен задевать героя.
	for i in 20:
		var dx: float = player.global_position.x - cx
		if absf(dx) <= 1.5:
			break
		var key: int = KEY_A if dx > 0.0 else KEY_D
		hold(key)
		await wait(0.03)
		release(key)
		await wait_until(func() -> bool: return absf(player.vel.x) < 1.0, 0.5)
	return reached and landed and floori(player.global_position.x / World.TILE) == col


## Случайный груз без линзы: [[id, число], ...]. Линза кладётся отдельно (#172).
func _loot(chest) -> Array:
	var out: Array = []
	if chest == null or not is_instance_valid(chest):
		return out
	for s in chest.slots:
		if s.is_empty() or s.id == IDs.I.LENS:
			continue
		out.append([s.id, s.count])
	return out


func _count(chest, id: int) -> int:
	var n: int = 0
	if chest == null or not is_instance_valid(chest):
		return 0
	for s in chest.slots:
		if not s.is_empty() and s.id == id:
			n += s.count
	return n


## Слепок тайника: место, имя, обрывок, груз (линза — своим числом).
func _snapshot() -> Array:
	var sc: Dictionary = World.sky_cache
	if sc.is_empty():
		return []
	return [sc["x0"], sc["floor_y"], sc["name"], sc["fragment"], _loot(sc["chest"]),
			_count(sc["chest"], IDs.I.LENS)]


func _regen(s: int) -> void:
	if World.tilemap:
		World.tilemap.clear()
	World.generate(s)
	Game.tasks_total = World.terminals.size()
