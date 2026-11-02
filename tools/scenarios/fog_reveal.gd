extends ScenarioBase
## Туман войны (#59): в начале открыта только область вокруг старта; бот идёт
## по коридору базы — клетки по пути и в радиусе обзора открываются (в мире,
## в текстуре тумана и на миникарте); стоя на месте, открытие не вызывается;
## под землёй обзор уже; дальние пещеры так и остаются закрытыми.
##
## Заодно меряет стоимость: открытие круга при шаге (World.explore_us — вместе
## с обработчиками сигнала у слоя тумана и миникарты) и мкс/кадр слоя тумана.

## Дальняя пещера — не ближе стольких клеток от релея по горизонтали.
const FAR_CAVE_DX: int = 110
## Пещера считается пещерой, если она глубже стольких клеток под рельефом.
const CAVE_DEPTH: int = 12


func run() -> void:
	await await_frame()
	var fog: FogLayer = null
	for c in scene.get_children():
		if c is FogLayer:
			fog = c
	ok("слой тумана на месте", fog != null and fog.chunk_count() > 0,
			"чанков %d" % (fog.chunk_count() if fog != null else 0))
	if fog == null:
		finish()
		return
	var hud: HUD = UI.hud
	var rs: int = Balance.FOG_RADIUS_SURFACE
	var bx: int = World.beacon_cell.x

	# --- 1. Старт: открыт только круг у точки старта -------------------------
	var spawn: Vector2i = World.world_to_cell(World.spawn_point)
	var disk: float = PI * (float(rs) + 0.5) * (float(rs) + 0.5)
	ok("в начале открыта только область вокруг старта",
			World.explore_cells > 0 and float(World.explore_cells) <= disk * 1.5,
			"%d клеток из %d (круг ≈ %.0f)" % [World.explore_cells, World.W * World.H, disk])
	ok("клетка старта открыта (мир, текстура, миникарта)",
			World.is_explored(spawn) and fog.fog_byte(spawn) == 255 and hud.map_explored_at(spawn))
	var far_l: Vector2i = spawn + Vector2i(-(rs + 3), 0)
	ok("за радиусом обзора закрыто", not World.is_explored(far_l) and fog.fog_byte(far_l) == 0)
	var caves_l: Array = _caves(0, bx - FAR_CAVE_DX)
	var caves_r: Array = _caves(bx + FAR_CAVE_DX, World.W)
	ok("дальние пещеры найдены", caves_l.size() > 10 and caves_r.size() > 10,
			"слева %d, справа %d клеток" % [caves_l.size(), caves_r.size()])
	ok("дальние пещеры закрыты в начале", _open_count(caves_l) == 0 and _open_count(caves_r) == 0)
	ok("дальняя пещера черна на миникарте", caves_r.size() > 0 and not hud.map_explored_at(caves_r[0]))

	# --- 2. Проход по коридору базы ------------------------------------------
	var base: int = stand_in_corridor()
	await wait(0.3)
	var probe: Vector2i = Vector2i(bx + 28, base - 2)
	ok("клетка впереди закрыта до прохода", not World.is_explored(probe) and not hud.map_explored_at(probe))
	var calls0: int = World.explore_calls
	var us0: int = World.explore_us
	World.explore_us_max = 0
	var fog_us0: int = fog.stat_us
	var fog_fr0: int = fog.stat_frames
	var path: Array = []
	hold(KEY_D)
	var t0: float = now()
	while now() - t0 < 1.6:
		await await_frame()
		var pc: Vector2i = World.world_to_cell(player.global_position)
		if path.is_empty() or path[path.size() - 1] != pc:
			path.append(pc)
	release(KEY_D)
	await await_frame()
	var unexplored_path: int = 0
	for c in path:
		if not World.is_explored(c) or fog.fog_byte(c) != 255:
			unexplored_path += 1
	ok("бот прошёл по коридору", path.size() >= 8, "клеток пути %d" % path.size())
	ok("клетки по пути открыты", unexplored_path == 0, "закрытых %d из %d" % [unexplored_path, path.size()])
	ok("клетка впереди открылась (мир, текстура, миникарта)",
			World.is_explored(probe) and fog.fog_byte(probe) == 255 and hud.map_explored_at(probe))
	var calls: int = World.explore_calls - calls0
	var avg_us: float = float(World.explore_us - us0) / float(maxi(1, calls))
	ok("открытие — только при смене клетки", calls > 0 and calls <= path.size() + 1,
			"вызовов %d на %d клеток пути" % [calls, path.size()])
	ok("стоимость открытия при шаге", calls > 0,
			"в среднем %.0f мкс, худший %d мкс (R=%d, вместе со слоем тумана и миникартой)"
			% [avg_us, World.explore_us_max, rs])
	var fog_walk: float = float(fog.stat_us - fog_us0) / float(maxi(1, fog.stat_frames - fog_fr0))

	# --- 3. Стоя на месте туман не работает ----------------------------------
	await wait(0.3)
	var calls_idle0: int = World.explore_calls
	var up0: int = fog.stat_uploads
	var rd0: int = fog.stat_redraws
	var fog_idle: float = await _fog_median_us(fog, 1.0)
	ok("стоя на месте: 0 открытий, 0 заливок, 0 перерисовок",
			World.explore_calls == calls_idle0 and fog.stat_uploads == up0 and fog.stat_redraws == rd0,
			"открытий %d, заливок %d, перерисовок %d" % [World.explore_calls - calls_idle0,
			fog.stat_uploads - up0, fog.stat_redraws - rd0])
	ok("слой тумана, мкс/кадр", fog_idle < 100.0,
			"среднее в ходьбе %.1f, медиана стоя %.1f (чанков в кадре %d из %d)"
			% [fog_walk, fog_idle, fog.chunks_drawn, fog.chunk_count()])

	# --- 4. Под землёй обзор уже ---------------------------------------------
	var cave: Vector2i = _standable(caves_r)
	ok("нашлась пещера, где можно встать", cave.x >= 0, str(cave))
	if cave.x >= 0:
		var r: int = Balance.FOG_RADIUS
		ok("в пещере радиус обзора подземный", World.explore_radius_at(cave) == r,
				"%d клеток" % World.explore_radius_at(cave))
		stand_at_cell(cave)
		await await_frame()
		await await_frame()
		var pc2: Vector2i = World.world_to_cell(player.global_position)
		ok("пещера под героем открылась", World.is_explored(pc2) and hud.map_explored_at(pc2))
		var inside: Vector2i = pc2 + Vector2i(0, -(r - 1))
		var outside: Vector2i = pc2 + Vector2i(0, -(r + 3))
		ok("под землёй открыт круг R=%d, дальше — нет" % r,
				World.is_explored(inside) and not World.is_explored(outside),
				"%s открыта, %s закрыта" % [str(inside), str(outside)])
	clear_input()
	stand_in_corridor()
	await wait(0.2)

	# --- 5. Дальние пещеры на той стороне так и закрыты ----------------------
	ok("дальние пещеры слева закрыты после прохода", _open_count(caves_l) == 0,
			"открыто %d из %d" % [_open_count(caves_l), caves_l.size()])
	print("  FOGSTATS: открыто клеток %d из %d, заливок чанков %d, перерисовок слоя %d"
			% [World.explore_cells, World.W * World.H, fog.stat_uploads, fog.stat_redraws])

	# --- 5a. Пересборка по готовой карте (так будет после загрузки, #37) -----
	var tr: int = Time.get_ticks_usec()
	World.explored_reset.emit()
	var rebuild_us: int = Time.get_ticks_usec() - tr
	ok("пересборка по карте: открытое открыто, закрытое закрыто",
			fog.fog_byte(probe) == 255 and hud.map_explored_at(probe) and fog.fog_byte(spawn) == 255
			and fog.fog_byte(far_l) == 0 and not hud.map_explored_at(caves_l[0]),
			"%.1f мс на слой тумана и миникарту" % (float(rebuild_us) / 1000.0))

	# --- 6. Замер: шаг в неисследованное, R подземный и наземный -------------
	# Шагаем по клетке вдоль закрытого ряда у дна мира слева: каждый шаг
	# открывает край круга. Медиана по шагам (машина под нагрузкой — среднее
	# портят вытеснения процесса); отдельно — само открытие без слушателей.
	var y8: int = World.H - 1 - Balance.FOG_RADIUS
	var y16: int = y8 - 2 * Balance.FOG_RADIUS - 2 - Balance.FOG_RADIUS_SURFACE
	for pair in [[Balance.FOG_RADIUS, y8], [Balance.FOG_RADIUS_SURFACE, y16]]:
		var r: int = pair[0]
		var full: Vector3 = _bench_steps(r, pair[1], 4, true)
		var bare: Vector3 = _bench_steps(r, pair[1], 4 + 60, false)
		ok("замер шага в новое, R=%d" % r, full.x > 0.0,
				"медиана %.0f мкс на шаг (худший %.0f, новых клеток %.0f), из них само открытие %.0f мкс"
				% [full.x, full.y, full.z, bare.x])
	finish()


## Шагает 40 клеток вправо от x0 по ряду y, открывая круг R на каждом шаге.
## Возвращает (медиана мкс на шаг, худший шаг, новых клеток на шаг).
## listeners=false — без слушателей (слой тумана и миникарта отключены).
func _bench_steps(r: int, y: int, x0: int, listeners: bool) -> Vector3:
	var conns: Array = World.explored_changed.get_connections()
	if not listeners:
		for cn in conns:
			World.explored_changed.disconnect(cn["callable"])
	World.reveal_around(Vector2i(x0 - 1, y), r)   # прогрев: первый круг целиком
	var cells0: int = World.explore_cells
	var times: Array = []
	for i in 40:
		var t0: int = Time.get_ticks_usec()
		World.reveal_around(Vector2i(x0 + i, y), r)
		times.append(Time.get_ticks_usec() - t0)
	if not listeners:
		for cn in conns:
			World.explored_changed.connect(cn["callable"])
	times.sort()
	return Vector3(float(times[20]), float(times[39]), float(World.explore_cells - cells0) / 40.0)


## Медиана мкс/кадр слоя тумана за secs секунд.
func _fog_median_us(fog: FogLayer, secs: float) -> float:
	var times: Array = []
	var t0: int = Time.get_ticks_msec()
	var last: int = fog.stat_us
	while Time.get_ticks_msec() - t0 < int(secs * 1000.0):
		await await_frame()
		times.append(fog.stat_us - last)
		last = fog.stat_us
	if times.is_empty():
		return 0.0
	times.sort()
	return float(times[times.size() / 2])


## Клетки воздуха глубоко под рельефом в колонках [xa, xb).
func _caves(xa: int, xb: int) -> Array:
	var out: Array = []
	for x in range(maxi(2, xa), mini(World.W - 2, xb), 3):
		for y in range(World.surface[x] + CAVE_DEPTH, World.H - 3, 3):
			if World.get_tile(x, y) == IDs.T.AIR:
				out.append(Vector2i(x, y))
	return out


func _open_count(cells: Array) -> int:
	var n: int = 0
	for c in cells:
		if World.is_explored(c):
			n += 1
	return n


## Пещерная клетка, где герой встанет: два воздуха над твёрдым полом.
func _standable(cells: Array) -> Vector2i:
	for c in cells:
		var cell: Vector2i = c
		if World.get_tile(cell.x, cell.y - 1) != IDs.T.AIR:
			continue
		for d in 8:
			var f: Vector2i = cell + Vector2i(0, d)
			if World.is_solid_cell(f + Vector2i(0, 1)) and World.get_tile(f.x, f.y) == IDs.T.AIR \
					and World.get_tile(f.x, f.y - 1) == IDs.T.AIR:
				return f
	return Vector2i(-1, -1)
