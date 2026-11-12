extends Mission
## Глава 2 «Огонь» (ADR-005 § 9): горелка даёт луч.
## Горелка у входа, уголь в топку — красный луч через лагерь. Сумерки примерно
## через 40 с: безвредное эхо подходит к лучу и отступает.

## Метка на полу: куда ставить горелку, клеток от центра лагеря.
## +1 занят коридором сценариев, +2 и +5 — панели базы, +3 — лампа.
const MARK_DX: int = 7
## Сколько ждать сумерек после угля в топке, с игрового времени.
const DUSK_WAIT: float = 40.0
## Эхо уже отступило от луча (кадр мог пройти до проверки сценария).
var _retreated: bool = false
## Эхо этой ночи уже выпущено (один раз).
var _echo_out: bool = false
## Живое эхо главы. После деспавна выпускаем ещё раз — цель не должна стать
## недостижимой навсегда (#215).
var _echo: Phantom = null
## Сколько эхо уже шло к лучу, с. Нужно сценарию и кадру.
var echo_walked: float = 0.0
## Ближе этого эхо к лучу метки не подходило, клеток. Сценарий читает:
## в луче эхо живёт один кадр и в группе его уже нет.
var echo_near: float = 999.0
## Этап не ждёт вечно: если эхо не дошло, солнце всё равно отпускаем.
const ECHO_WAIT: float = 25.0
## Сколько эхо идёт к лучу, с. Дальше — обычный ИИ (свет уже должен вспугнуть).
const APPROACH_SEC: float = 20.0


func _init() -> void:
	id = "fire"
	chapter = 2
	title = "Огонь"
	brief = "Уголь есть. Горелка жжёт его и бьёт красным лучом — эхо от луча отступает."
	teaches = "горелка: поставить, положить уголь, красный луч"
	director = false
	start_time = 0.35
	# Солнце стоит, пока горелка не зажжена. Потом — до сумерек около 40 с.
	hold_time = 0.40


func build() -> void:
	CampaignBase.build(CampaignBase.Tier.STATION)
	var m: Vector2i = mark()
	# Метка и воздух над ней: луч идёт вверх через лагерь, не в пол.
	for dy in range(0, 8):
		var c: Vector2i = m + Vector2i(0, -dy)
		if World.get_tile_v(c) != IDs.T.AIR and not World.machines.has(c):
			World.set_tile(c.x, c.y, IDs.T.AIR)
	# Ход от входа до луча. На сиде 31337 воздух над лагерем — только колонка
	# метки: эхо с пола у входа упиралось в потолок и не доходило (#215).
	_clear_lane(m)
	# Горелка станции бьёт вправо по ряду лагеря и стоит в этом ряду стеной.
	# Носик вверх: луч уходит в небо, ход к метке свободен, эхо не пугается
	# чужого света у входа.
	_aim_station_up()



func kit() -> Array:
	return [[IDs.I.BURNER, 1], [IDs.I.COAL, 3]]


func stages() -> Array:
	return [
		{"title": "Горелка",
			"hint": "Горелку ставят у метки на полу",
			"say": ["Горелка — наш свет. Поставь её у метки."],
			"goals": [["Поставь горелку у входа", func() -> Vector2i:
				return Vector2i(1 if _burner() != null else 0, 1),
				IDs.I.BURNER, func() -> Vector2: return World.cell_to_world(mark())]]},
		{"title": "Уголь",
			"hint": "Уголь в руке — и горелка зажигается",
			"say": ["Положи уголь в горелку. Луч пойдёт сам."],
			"goals": [["Положи уголь в горелку", func() -> Vector2i:
				return flag(_burner_lit()),
				IDs.I.COAL, func() -> Vector2: return _burner_at()]],
			"done": _after_coal},
		{"title": "Сумерки",
			"hint": "Эхо подходит к лучу и отступает",
			"say": ["Ждём сумерек. Эхо само подойдёт — и само уйдёт."],
			"goals": [["Дождись сумерек", func() -> Vector2i:
				return flag(_echo_retreated()),
				IDs.I.BURNER, func() -> Vector2: return _burner_at()]]},
	]


func on_tick(delta: float) -> void:
	if stage != 2 or result != Result.RUNNING:
		return
	# Ночь ещё не наступила — ждём. Солнце само дойдёт: hold_time стоит на ночи.
	if not Game.is_night():
		return
	if not _echo_alive():
		# Первое эхо или то, что ушло в глубину, не дойдя. Второе выпускаем
		# у луча, не в пустоту: иначе цель снова недостижима.
		if not _release_echo(not _echo_out):
			return
	echo_walked += delta
	_note_near()
	_steer_echo()
	if _echo_retreated():
		_release_sun_after()
		# Проверка целей — раз в 0.25 с, а эхо у луча живёт кадр. Закрываем сразу.
		evaluate()
		return
	# Эхо не дошло — этап всё равно закрывается, глава не висит.
	if echo_walked >= ECHO_WAIT:
		_retreated = true
		_release_sun_after()


func outro() -> String:
	return "Красный луч через весь лагерь. Эхо подошло — и отступило."


## Метка на полу лагеря: пустая клетка справа от центра.
func mark() -> Vector2i:
	return Vector2i(World.beacon_cell.x + MARK_DX, World.beacon_cell.y)


## Два ряда воздуха от входа до колонки луча, на уровне пола лагеря.
## Постройки и релей не трогаем: горелка станции стоит левее метки.
func _clear_lane(m: Vector2i) -> void:
	var door: Vector2i = CampaignBase.camp_door()
	var x0: int = mini(door.x, m.x)
	var x1: int = maxi(door.x, m.x)
	# Три ряда: тело эха 22 px, коридор в одну клетку его не пускает.
	var y0: int = mini(door.y, m.y) - 3
	var y1: int = maxi(door.y, m.y)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var c: Vector2i = Vector2i(x, y)
			if World.machines.has(c):
				continue
			if World.get_tile_v(c) == IDs.T.RELAY_CORE:
				continue
			if World.get_tile_v(c) != IDs.T.AIR:
				World.set_tile(c.x, c.y, IDs.T.AIR)
	# Пол под ходом. Без него эхо падает на ряд ниже и не достаёт цель.
	for x in range(x0, x1 + 1):
		var floor_c: Vector2i = Vector2i(x, y1 + 1)
		if World.machines.has(floor_c):
			continue
		if World.get_tile_v(floor_c) == IDs.T.AIR:
			World.set_tile(floor_c.x, floor_c.y, IDs.T.STONE)


## Носик горелки станции — вверх. Иначе её луч перекрывает ряд лагеря.
func _aim_station_up() -> void:
	var station: Vector2i = Vector2i(World.beacon_cell.x - 1, World.beacon_cell.y)
	var b: Burner = World.machines.get(station) as Burner
	if b == null:
		return
	var guard: int = 0
	while b.dir != 3 and guard < 8:
		b.turn()
		guard += 1


func _burner() -> Burner:
	# Станция (#170) уже ставит свою горелку у релея. Глава ждёт ту, что на метке:
	# первая в словаре машин — не она, и этап «Уголь» иначе не закрывается.
	var at: Burner = World.machines.get(mark()) as Burner
	if at != null and is_instance_valid(at):
		return at
	return null


func _burner_at() -> Vector2:
	var b: Burner = _burner()
	if b == null:
		return World.cell_to_world(mark())
	return b.global_position


## Уголь в топке и луч красный. Эхо планируем здесь же: done и enter
## зовутся из того же _process, и волна с нулевой задержкой сгорает сразу.
func _burner_lit() -> bool:
	var b: Burner = _burner()
	if b == null or not b.burning() or b.color != Beams.R:
		return false
	if World.beams == null or World.beams.color_at(b.cell + Vector2i(0, -1)) != Beams.R:
		return false
	return true


## Уголь в топке: солнце идёт к сумеркам. Эхо выйдет в on_tick, с сумерками.
func _after_coal() -> void:
	_release_sun()


## Солнце больше не стоит: до сумерек около 40 с игрового времени.
func _release_sun() -> void:
	var dusk_in: float = Balance.DUSK_START - Game.time_of_day
	if dusk_in < 0.0:
		dusk_in += 1.0
	var want: float = DUSK_WAIT / Balance.DAY_LENGTH
	if dusk_in > want + 0.002:
		Game.time_of_day = Balance.DUSK_START - want
	# Ночь короче 60 с: солнце дойдёт до NIGHT_START и встанет, пока эхо не уйдёт.
	hold_time = Balance.NIGHT_START + 50.0 / Balance.DAY_LENGTH


## Эхо отступило (или ждать больше нечего): солнце идёт к рассвету.
func _release_sun_after() -> void:
	if hold_time < 0.0:
		return
	hold_time = -1.0


## Эхо вышло, подошло к лучу и отступило. Флаг копится: в луче эхо живёт
## один кадр, сценарий может не застать его в группе.
func _echo_retreated() -> bool:
	if _retreated:
		return true
	if not Game.is_night():
		return false
	for n in get_tree().get_nodes_in_group("phantom"):
		if not is_instance_valid(n) or not (n is Phantom):
			continue
		var p: Phantom = n
		if not bool(p.get("harmless")):
			continue
		# Лампы лагеря тоже ярче порога. Отступление — только у луча метки,
		# иначе эхо пугается у входа и глава закрывается без демонстрации.
		if _by_beam(p):
			_retreated = true
			return true
	return false


## Клетка хода над полом, ближе к лучу. Центр тела — на ряд выше ног:
## клетка пола для спавна слишком низко, эхо оказывается в камне (#215).
func _echo_spot() -> Vector2i:
	var door: Vector2i = CampaignBase.camp_door()
	var beam: Vector2i = _nearest_beam(door)
	var toward: int = door.x if beam.x < 0 else beam.x
	var best: Vector2i = door + Vector2i(0, -1)
	var bd: int = 1 << 30
	var y: int = door.y - 1
	for x in range(door.x - 8, door.x + 6):
		var c: Vector2i = Vector2i(x, y)
		if not _open(c) or _lit(c):
			continue
		var d: int = absi(c.x - toward)
		if d < bd:
			bd = d
			best = c
	return best


func _echo_alive() -> bool:
	return _echo != null and is_instance_valid(_echo) and _echo.alive and not _echo.is_queued_for_deletion()


## Выпустить безвредное эхо. Оба раза — у входа, на полу лагеря: оттуда
## прямой ход к лучу. Тёмная клетка хода в глубине эхо уводит от луча.
func _release_echo(_first: bool) -> bool:
	var spot: Vector2i = _echo_spot()
	var made: Array = Threat.spawn_phantom("echo", World.cell_to_world(spot), {"harmless": true})
	if made.is_empty():
		return false
	_echo = made[0]
	_echo_out = true
	Threat.chapter_echo = true
	_steer_echo()
	return true


## Эхо у луча метки: в его свете или уже бежит от него.
## Горизонтальный луч станции тоже красный и ярче порога. Его не считаем:
## эхо пугается у входа, и демонстрация у метки не случается.
func _by_beam(p: Phantom) -> bool:
	if World.beams == null:
		return false
	var here: Vector2i = World.world_to_cell(p.global_position)
	var best: float = 999.0
	for c in World.beams.cells.keys():
		if not _mark_beam_cell(c):
			continue
		var d: float = Vector2(here - c).length()
		if d < best:
			best = d
	# Тело не входит в клетку луча: центр на ряд выше ног. Свет луча (радиус
	# 20 px) достаёт соседнюю клетку — этого хватает, чтобы отступить на глазах.
	if best > 1.5:
		return false
	return p.state == Phantom.St.FLEE or _lit(here)


## Запомнить, насколько близко эхо подходило к лучу метки.
func _note_near() -> void:
	if not _echo_alive() or World.beams == null:
		return
	var here: Vector2i = World.world_to_cell(_echo.global_position)
	var best: float = echo_near
	for c in World.beams.cells.keys():
		if not _mark_beam_cell(c):
			continue
		var d: float = Vector2(here - c).length()
		if d < best:
			best = d
	echo_near = best


## Вести живое эхо к ближайшей клетке луча, пока свет не вспугнет.
func _steer_echo() -> void:
	if not _echo_alive():
		return
	if _echo.state == Phantom.St.FLEE:
		return
	var at: Vector2 = _approach_at()
	if at == Vector2.ZERO:
		return
	# Цель на месте — не сбрасываем путь каждый кадр.
	if _echo.approach_t > 1.0 and _echo.approach_at.distance_to(at) < 8.0:
		return
	_echo.approach(APPROACH_SEC, at)


## Куда идти: тёмная клетка на ряду тела, рядом с лучом метки.
## Ряд ног — на один ниже: путь туда упирается в пол, и эхо топчется.
## Луч станции (влево от маяка) не цель: его свет гасит эхо раньше метки.
func _approach_at() -> Vector2:
	var from: Vector2i = World.world_to_cell(_echo.global_position) if _echo_alive() else _echo_spot()
	var beam: Vector2i = _nearest_beam(from)
	if beam.x < 0:
		var b: Burner = _burner()
		if b == null:
			return Vector2.ZERO
		beam = b.cell + Vector2i(0, -1)
	var goal: Vector2i = _walkable_near(beam, from)
	if goal.x < 0:
		return Vector2.ZERO
	return World.cell_to_world(goal)


## Клетка, на которой стоят ноги. Центр тела — на ряд выше пола.
func _echo_feet() -> Vector2i:
	if not _echo_alive():
		return _echo_spot()
	var head: Vector2i = World.world_to_cell(_echo.global_position)
	var below: Vector2i = head + Vector2i(0, 1)
	if not _open(below):
		return below
	return head


## Красный луч горелки на метке, не луч станции.
## Станция стоит на beacon.x − 1 и бьёт вправо по ряду лагеря: её свет
## перекрывает подход, если считать любую красную клетку.
func _mark_beam_cell(c: Vector2i) -> bool:
	if World.beams == null or int(World.beams.cells.get(c, 0)) & Beams.R == 0:
		return false
	var m: Vector2i = mark()
	if c.x == m.x:
		return true
	# Горизонталь метки: носик вверх, но соседние машины гнут луч в ряд лагеря.
	if c.y == m.y and c.x > World.beacon_cell.x + 1 and c.x < m.x + 6:
		return true
	return false


## Ближайшая клетка красного луча метки. Нет луча — (−1, −1).
func _nearest_beam(from: Vector2i) -> Vector2i:
	if World.beams == null:
		return Vector2i(-1, -1)
	var best: Vector2i = Vector2i(-1, -1)
	var bd: int = 1 << 30
	for c in World.beams.cells.keys():
		if not _mark_beam_cell(c):
			continue
		var d: int = absi(c.x - from.x) + absi(c.y - from.y)
		if d < bd:
			bd = d
			best = c
	return best


## Проходимая клетка у луча, до которой от from есть путь по полу.
## Свет соседа не отсекаем: эхо должно войти в луч и отступить, а не встать
## в трёх клетках, где свет уже погас. Ряд — тот же, что у тела: путь вверх
## по диагонали пеший фантом не проходит.
func _walkable_near(beam: Vector2i, from: Vector2i) -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var bd: int = 1 << 30
	for r in range(1, 8):
		for dx in [-r, r]:
			var s: Vector2i = Vector2i(beam.x + dx, from.y)
			if not _open(s):
				continue
			if not _floor_path(from, s):
				continue
			var d: int = absi(s.x - from.x)
			if d < bd:
				bd = d
				best = s
		if best.x >= 0:
			return best
	return best


## Путь по одному ряду: каждая клетка между from и to проходима.
## A* режет угол вверх, и пеший фантом на этом узле замирает.
func _floor_path(from: Vector2i, to: Vector2i) -> bool:
	if from.y != to.y:
		return false
	var step: int = 1 if to.x >= from.x else -1
	var x: int = from.x
	while x != to.x:
		x += step
		if not _open(Vector2i(x, from.y)):
			return false
	return true


func _open(c: Vector2i) -> bool:
	if not World.in_bounds(c.x, c.y):
		return false
	# Машина для A* — воздух, для тела эха — стена. В такую клетку путь не ведём.
	if World.machines.has(c):
		return false
	if World.astar != null:
		return World.astar.is_in_boundsv(c) and not World.astar.is_point_solid(c)
	return not World.is_solid_cell(c)


func _path_exists(from: Vector2i, to: Vector2i) -> bool:
	if from == to:
		return true
	if World.astar == null:
		return false
	var a: Vector2i = from if _open(from) else _nearest_open(from)
	if a.x < 0 or not _open(to):
		return false
	return World.astar.get_id_path(a, to).size() > 0


func _nearest_open(c: Vector2i) -> Vector2i:
	if _open(c):
		return c
	for r in range(1, 5):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var t: Vector2i = c + Vector2i(dx, dy)
				if _open(t):
					return t
	return Vector2i(-1, -1)


## Повторный выход: тёмная клетка у лагеря, откуда до луча есть путь.
## Ход в глубину не берём — оттуда эхо снова уйдёт, не показав луч.
func _echo_retry_spot() -> Vector2i:
	var door: Vector2i = CampaignBase.camp_door()
	var beam: Vector2i = _nearest_beam(door)
	if beam.x < 0:
		beam = mark() + Vector2i(0, -2)
	var best: Vector2i = door
	var bd: int = 1 << 30
	for y in range(door.y - 3, door.y + 4):
		for x in range(door.x - 4, beam.x + 2):
			var c: Vector2i = Vector2i(x, y)
			if not _open(c) or _lit(c):
				continue
			if not _path_exists(c, beam) and not _path_exists(c, _walkable_near(beam, c)):
				continue
			var d: int = absi(c.x - beam.x) + absi(c.y - beam.y)
			if d < bd:
				bd = d
				best = c
	return best


func _lit(c: Vector2i) -> bool:
	return World.light_at(c) > float(Balance.PHANTOMS["echo"]["light_flee"])



