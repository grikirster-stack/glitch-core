extends "res://tools/scenarios/scenario_base.gd"
## Пресс (ADR-006 § 3.2, #314).
##
## Две планировки выпускают панели: грядка → сундук → пресс → сундук
## и грядка лотком прямо в пресс, панели в буфер. Полный выход ждёт.
## Неверная сторона и чужой предмет дают «Не та сторона». Save в середине
## партии восстанавливает волокно, секунды и буфер. Разбор возвращает
## вход и готовое. Минута без игрока копит панели; два световых отрезка
## дают больше панелей, чем стоит ремонт одной машины.


func run() -> void:
	player.invuln = 1.0e9
	stand_in_corridor(3)
	await wait(0.2)
	var origin: Vector2i = Vector2i(40, 8)
	_clear(Vector2i(30, 0), Vector2i(70, 30))
	Game.time_of_day = 0.30
	await await_frame()
	await _line(origin)
	await _direct(origin + Vector2i(0, 6))
	await _wrong_side(origin + Vector2i(12, 0))
	await _full_out(origin + Vector2i(12, 4))
	await _save_mid(_base_air())
	await _dismantle(origin + Vector2i(16, 4))
	await _minute(origin + Vector2i(0, 10))
	await _two_cycles(origin + Vector2i(8, 10))
	finish()


## Планировка 1: грядка смотрит в сундук, пресс берёт с другой грани сундука.
func _line(origin: Vector2i) -> void:
	var bed_c: Vector2i = origin
	var chest_c: Vector2i = origin + Vector2i(1, 0)
	var press_c: Vector2i = origin + Vector2i(2, 0)
	var out_c: Vector2i = origin + Vector2i(3, 0)
	ok("линия: грядка", MachineBase.place_machine("SporeBed", bed_c))
	ok("линия: входной сундук", MachineBase.place_machine("Chest", chest_c))
	ok("линия: пресс", MachineBase.place_machine("Press", press_c))
	ok("линия: выходной сундук", MachineBase.place_machine("Chest", out_c))
	var bed: SporeBed = World.machines.get(bed_c) as SporeBed
	var inn: Chest = World.machines.get(chest_c) as Chest
	var press: Press = World.machines.get(press_c) as Press
	var outc: Chest = World.machines.get(out_c) as Chest
	if bed == null or press == null or inn == null or outc == null:
		return
	bed.dir = 0
	press.dir = 2
	ok("вход пресса смотрит на сундук", press.in_cell() == chest_c, str(press.in_cell()))
	ok("выход пресса смотрит на сундук панелей", press.out_cell() == out_c, str(press.out_cell()))
	var col_c: Vector2i = bed_c + Vector2i(-3, 0)
	ok("линия: коллектор", MachineBase.place_machine("Collector", col_c))
	var col: Collector = World.machines.get(col_c) as Collector
	if col == null:
		return
	col.dir = 0
	col._check_sky()
	_flush()
	ok("белый дошёл до грядки", bed.lit, "lit %s" % bed.lit)
	var need: int = Balance.PRESS_FIBER_IN
	var got: bool = await _wait_proc(func() -> bool:
		return _chest_count(outc, IDs.I.PANEL) >= Balance.PRESS_PANEL_OUT, _line_budget() + 2.0)
	ok("линия выпустила партию панелей", got,
			"панелей %d, волокна в сундуке %d, партия %d, очередь %d" % [
				_chest_count(outc, IDs.I.PANEL), _chest_count(inn, IDs.I.SPORE_FIBER),
				press.batch, press.queued])
	ok("волокно ушло во вход, не в выход", _chest_count(inn, IDs.I.SPORE_FIBER) >= 0
			and _chest_count(outc, IDs.I.SPORE_FIBER) == 0)
	ok("подписи читаются", press.status_text() in [Press.ST_WORK, Press.ST_WAIT, Press.ST_FULL],
			press.status_text())
	var panels: int = _chest_count(outc, IDs.I.PANEL)
	var placed: bool = _spend_panel(outc, origin + Vector2i(0, 2))
	ok("панель из выходного сундука встала стеной", placed and panels == _chest_count(outc, IDs.I.PANEL) + 1,
			"было %d, стало %d, тайл %d" % [panels, _chest_count(outc, IDs.I.PANEL),
			World.get_tile_v(origin + Vector2i(0, 2))])
	_gone(col)
	_gone(bed)
	_gone(inn)
	_gone(press)
	_gone(outc)
	_sweep()


## Планировка 2: лоток грядки прямо во вход пресса, панели остаются в буфере.
func _direct(origin: Vector2i) -> void:
	var bed_c: Vector2i = origin
	var press_c: Vector2i = origin + Vector2i(1, 0)
	ok("прямо: грядка", MachineBase.place_machine("SporeBed", bed_c))
	ok("прямо: пресс", MachineBase.place_machine("Press", press_c))
	var bed: SporeBed = World.machines.get(bed_c) as SporeBed
	var press: Press = World.machines.get(press_c) as Press
	if bed == null or press == null:
		return
	bed.dir = 0
	press.dir = 2
	ok("лоток грядки смотрит во вход пресса", bed.out_dir() == -press.in_dir())
	bed.tray = Balance.PRESS_FIBER_IN
	bed.beam_receive(0)
	var got: bool = await _wait_proc(func() -> bool:
		return press.out_buf >= Balance.PRESS_PANEL_OUT, Balance.PRESS_SECONDS + 1.5)
	ok("прямой лоток дал панели в буфер", got and bed.tray == 0,
			"буфер %d, лоток %d, подпись %s" % [press.out_buf, bed.tray, press.status_text()])
	var before: int = player.inv.count_of(IDs.I.PANEL)
	press.interact(player)
	ok("панели из буфера забираются руками",
			player.inv.count_of(IDs.I.PANEL) == before + Balance.PRESS_PANEL_OUT and press.out_buf == 0,
			"инвентарь %d, буфер %d" % [player.inv.count_of(IDs.I.PANEL), press.out_buf])
	player.inv.remove_id(IDs.I.PANEL, Balance.PRESS_PANEL_OUT)
	_gone(bed)
	_gone(press)
	_sweep()


## Сундук с панелями на входе и волокно с выходной грани — «Не та сторона».
func _wrong_side(origin: Vector2i) -> void:
	var press_c: Vector2i = origin
	ok("сторона: пресс", MachineBase.place_machine("Press", press_c))
	var press: Press = World.machines.get(press_c) as Press
	if press == null:
		return
	press.dir = 0
	var bad_in: Vector2i = press.in_cell()
	var bad_out: Vector2i = press.out_cell()
	ok("сторона: сундук на входе", MachineBase.place_machine("Chest", bad_in))
	ok("сторона: сундук на выходе", MachineBase.place_machine("Chest", bad_out))
	var inn: Chest = World.machines.get(bad_in) as Chest
	var outc: Chest = World.machines.get(bad_out) as Chest
	if inn == null or outc == null:
		return
	inn.receive_item(IDs.I.PANEL, 4)
	outc.receive_item(IDs.I.SPORE_FIBER, Balance.PRESS_FIBER_IN)
	await _proc(0.4)
	ok("чужой предмет на входе не взят", press.batch == 0 and press.queued == 0
			and _chest_count(inn, IDs.I.PANEL) == 4,
			"партия %d, панели %d, подпись %s" % [press.batch, _chest_count(inn, IDs.I.PANEL), press.status_text()])
	ok("подпись «Не та сторона»", press.status_text() == Press.ST_SIDE, press.status_text())
	ok("волокно с выходной грани не взято", _chest_count(outc, IDs.I.SPORE_FIBER) == Balance.PRESS_FIBER_IN
			and press.made == 0)
	var hands: int = press.receive_item(IDs.I.COAL, 2)
	ok("руки с углём не тратят слот", hands == 2 and press.batch == 0, "осталось %d" % hands)
	_gone(press)
	_gone(inn)
	_gone(outc)
	_sweep()


## Буфер на две партии. Третья ждёт, волокно не сгорает, панели не двоятся.
func _full_out(origin: Vector2i) -> void:
	var press_c: Vector2i = origin
	ok("полный: пресс", MachineBase.place_machine("Press", press_c))
	var press: Press = World.machines.get(press_c) as Press
	if press == null:
		return
	var cap: int = Balance.PRESS_BUFFER * Balance.PRESS_PANEL_OUT
	press.out_buf = cap
	press.batch = Balance.PRESS_FIBER_IN
	press.job = Balance.PRESS_SECONDS - 0.2
	press.queued = 1
	var fiber0: int = press.batch + press.queued * Balance.PRESS_FIBER_IN
	await _proc(0.6)
	ok("полный выход не завершил партию", press.batch == Balance.PRESS_FIBER_IN
			and press.out_buf == cap and press.made == 0,
			"буфер %d, партия %d, работа %.2f, подпись %s" % [
				press.out_buf, press.batch, press.job, press.status_text()])
	ok("подпись «Выход полон»", press.status_text() == Press.ST_FULL, press.status_text())
	press.take_panels(Balance.PRESS_PANEL_OUT)
	var got: bool = await _wait_proc(func() -> bool: return press.made >= 1, 1.5)
	ok("после места партия завершилась один раз", got and press.made == 1
			and press.out_buf == cap,
			"сделано %d, буфер %d, очередь %d" % [press.made, press.out_buf, press.queued])
	var fiber1: int = press.batch + press.queued * Balance.PRESS_FIBER_IN
	ok("волокно сошлось: партия стала панелями, остаток на месте",
			fiber0 == fiber1 + Balance.PRESS_FIBER_IN and press.out_buf == cap,
			"было волокон %d, стало %d, панелей %d" % [fiber0, fiber1, press.out_buf])
	# Выходной сундук забит: пресс не кладёт панель и не списывает буфер.
	press.take_panels(press.out_buf)
	var out_c: Vector2i = press.out_cell()
	ok("полный сундук: выход", MachineBase.place_machine("Chest", out_c))
	var outc: Chest = World.machines.get(out_c) as Chest
	if outc == null:
		_gone(press)
		return
	# Тот же id складывается в одну стопку. Полный сундук — 24 разных предмета.
	var fillers: Array[int] = [
		IDs.I.COAL, IDs.I.COPPER_ORE, IDs.I.IRON_ORE, IDs.I.COPPER_INGOT,
		IDs.I.IRON_INGOT, IDs.I.LOG, IDs.I.STONE, IDs.I.LENS,
		IDs.I.DOOR, IDs.I.SHEATH, IDs.I.PRESS, IDs.I.SPORE_BED,
		IDs.I.COLLECTOR, IDs.I.BURNER, IDs.I.MIRROR, IDs.I.MIXER,
		IDs.I.PRISM, IDs.I.PHAROS, IDs.I.SIREN, IDs.I.ACCUMULATOR,
		IDs.I.RAINBOW_CORE, IDs.I.COPPER_PLATE, IDs.I.GLASS, IDs.I.SCRAP,
	]
	for id in fillers:
		outc.receive_item(id, 1)
	var filled: int = 0
	for s in outc.slots:
		if not s.is_empty():
			filled += 1
	ok("выходной сундук забит", filled == Chest.CAP, "занято %d из %d" % [filled, Chest.CAP])
	press.out_buf = Balance.PRESS_PANEL_OUT
	press.batch = 0
	press.queued = 0
	press.job = 0.0
	await _proc(0.4)
	ok("полный сундук не принял панель", press.out_buf == Balance.PRESS_PANEL_OUT
			and _chest_count(outc, IDs.I.PANEL) == 0
			and press.status_text() == Press.ST_FULL,
			"буфер %d, панели в сундуке %d, подпись %s, занято %d" % [
				press.out_buf, _chest_count(outc, IDs.I.PANEL), press.status_text(), filled])
	_gone(outc)
	_gone(press)
	_sweep()


## Save в середине партии. Старый сейв без ключей пресса читается нулями.
func _save_mid(origin: Vector2i) -> void:
	var press_c: Vector2i = origin
	ok("сейв: пресс", MachineBase.place_machine("Press", press_c))
	var press: Press = World.machines.get(press_c) as Press
	if press == null:
		return
	press.dir = 1
	press.batch = Balance.PRESS_FIBER_IN
	press.queued = 1
	press.job = Balance.PRESS_SECONDS * 0.5
	press.out_buf = 3
	press.made = 4
	press.pushed = 2
	press._sync_progress()
	var slot0: String = Save.slot
	Save.slot = "press"
	Save.remove("press")
	var packed_d: Dictionary = Save.gather()
	var found: bool = false
	for rec in packed_d.get("machines", []):
		if str(rec.get("kind", "")) == "Press":
			found = true
			ok("в файле партия, очередь, секунды и буфер",
					int(rec.get("batch", -1)) == Balance.PRESS_FIBER_IN
					and int(rec.get("queued", -1)) == 1
					and absf(float(rec.get("job", -1.0)) - Balance.PRESS_SECONDS * 0.5) < 0.05
					and int(rec.get("out_buf", -1)) == 3,
					str(rec))
	ok("пресс попал в сохранение", found)
	var packed: PackedByteArray = Save.encode(packed_d)
	var decoded: Dictionary = Save.decode(packed)
	var wd = decoded.get("world", {})
	var tiles = wd.get("tiles") if wd is Dictionary else null
	var grid_ok: bool = tiles is PackedByteArray and tiles.size() == World.W * World.H
	ok("файл сейва читается", not decoded.is_empty() and grid_ok,
			"пусто %s, сетка %s, ошибка %s" % [decoded.is_empty(), grid_ok, Save.last_error])
	if decoded.is_empty() or not grid_ok:
		_gone(press)
		Save.remove("press")
		Save.slot = slot0
		return
	# Источник жив до apply: иначе загрузка не доказывает, что машина встала из файла.
	_gone(press)
	_sweep()
	await await_frame()
	ok("сейв применился", Save.apply(decoded), Save.last_error)
	var back: Press = World.machines.get(press_c) as Press
	ok("пресс загрузился", back != null)
	if back == null:
		Save.remove("press")
		Save.slot = slot0
		return
	ok("середина партии та же",
			back.dir == 1 and back.batch == Balance.PRESS_FIBER_IN and back.queued == 1
			and absf(back.job - Balance.PRESS_SECONDS * 0.5) < 0.05
			and back.out_buf == 3 and back.made == 4 and back.pushed == 2,
			"dir %d, партия %d, очередь %d, работа %.3f, буфер %d" % [
				back.dir, back.batch, back.queued, back.job, back.out_buf])
	var work0: float = back.job
	await _proc(0.3)
	ok("после загрузки партия продолжается", back.job > work0 + 0.15,
			"%.3f → %.3f" % [work0, back.job])
	# Старый сейв без полей пресса: машина как новая, волокно не появляется из воздуха.
	# Сетка берётся из только что прочитанного файла — apply без мира отвергает сейв.
	var bare: Dictionary = back.save_state()
	for k in ["batch", "queued", "job", "work", "out_buf", "made", "pushed"]:
		bare.erase(k)
	var old_world: Dictionary = packed_d.get("world", {})
	_gone(back)
	_sweep()
	await await_frame()
	await await_frame()
	ok("старый сейв применился", Save.apply(Save.decode(Save.encode({
			"version": Save.VERSION, "machines": [bare], "player": {}, "world": old_world,
			"seed": packed_d.get("seed", World.world_seed)}))), Save.last_error)
	var old: Press = World.machines.get(press_c) as Press
	ok("старый сейв без полей пресса — нули", old != null and old.batch == 0 and old.queued == 0
			and old.job == 0.0 and old.out_buf == 0,
			"партия %s" % (old.batch if old != null else -1))
	if old != null:
		_gone(old)
	Save.remove("press")
	Save.slot = slot0
	_sweep()


## Разбор в середине партии кладёт волокно и панели на землю, не теряя и не двоя.
func _dismantle(origin: Vector2i) -> void:
	var press_c: Vector2i = origin
	ok("разбор: пресс", MachineBase.place_machine("Press", press_c))
	var press: Press = World.machines.get(press_c) as Press
	if press == null:
		return
	press.batch = Balance.PRESS_FIBER_IN
	press.queued = 1
	press.job = 3.0
	press.out_buf = 5
	var fiber: int = press.batch + press.queued * Balance.PRESS_FIBER_IN
	var panels: int = press.out_buf
	_gone(press)
	await wait(0.1)
	ok("разбор вернул волокно партии", _ground(IDs.I.SPORE_FIBER) == fiber, str(_ground(IDs.I.SPORE_FIBER)))
	ok("разбор вернул панели буфера", _ground(IDs.I.PANEL) == panels, str(_ground(IDs.I.PANEL)))
	ok("пресса в мире нет", World.machines.get(press_c) == null)
	_sweep()


## Минута при работающей цепочке. Игрок стоит в стороне — это и есть «в шахте».
func _minute(origin: Vector2i) -> void:
	var bed_c: Vector2i = origin
	var chest_c: Vector2i = origin + Vector2i(1, 0)
	var press_c: Vector2i = origin + Vector2i(2, 0)
	var out_c: Vector2i = origin + Vector2i(3, 0)
	MachineBase.place_machine("SporeBed", bed_c)
	MachineBase.place_machine("Chest", chest_c)
	MachineBase.place_machine("Press", press_c)
	MachineBase.place_machine("Chest", out_c)
	var bed: SporeBed = World.machines.get(bed_c) as SporeBed
	var press: Press = World.machines.get(press_c) as Press
	var outc: Chest = World.machines.get(out_c) as Chest
	if bed == null or press == null or outc == null:
		ok("минута: цепочка встала", false)
		return
	bed.dir = 0
	press.dir = 2
	var col_c: Vector2i = bed_c + Vector2i(-3, 0)
	MachineBase.place_machine("Collector", col_c)
	var col: Collector = World.machines.get(col_c) as Collector
	if col == null:
		ok("минута: коллектор", false)
		return
	col.dir = 0
	col._check_sky()
	_flush()
	ok("минута: грядка под белым", bed.lit, "lit %s" % bed.lit)
	await _proc(60.0)
	var panels: int = _chest_count(outc, IDs.I.PANEL) + press.out_buf
	var batches: int = int(60.0 / (Balance.SPORE_BED_SECONDS * Balance.PRESS_FIBER_IN))
	ok("за минуту накопились панели", panels >= Balance.PRESS_PANEL_OUT,
			"панелей %d (в сундуке %d, в буфере %d), партий пресса %d, ожидаем ≥ %d" % [
				panels, _chest_count(outc, IDs.I.PANEL), press.out_buf, press.made, batches])
	ok("минута не потеряла волокно", _fiber_books(bed, World.machines.get(chest_c), press, outc),
			"лоток %d, выпущено %d, партия %d, очередь %d, сделано %d" % [
				bed.tray, bed.made, press.batch, press.queued, press.made])
	var wall: Vector2i = origin + Vector2i(0, 2)
	var spent: int = 0
	while _chest_count(outc, IDs.I.PANEL) > 0 and spent < 6:
		if not _spend_panel(outc, wall + Vector2i(spent, 0)):
			break
		spent += 1
	ok("из накопленного достроен участок", spent >= 1
			and World.get_tile_v(wall) == IDs.T.ROOM_PANEL, "поставлено %d" % spent)
	_gone(col)
	_gone(bed)
	_gone(World.machines.get(chest_c))
	_gone(press)
	_gone(outc)
	_sweep()


## Два световых отрезка по 48 с. Выпуск больше, чем один ремонт машины.
func _two_cycles(origin: Vector2i) -> void:
	var bed_c: Vector2i = origin
	var chest_c: Vector2i = origin + Vector2i(1, 0)
	var press_c: Vector2i = origin + Vector2i(2, 0)
	var out_c: Vector2i = origin + Vector2i(3, 0)
	MachineBase.place_machine("SporeBed", bed_c)
	MachineBase.place_machine("Chest", chest_c)
	MachineBase.place_machine("Press", press_c)
	MachineBase.place_machine("Chest", out_c)
	var bed: SporeBed = World.machines.get(bed_c) as SporeBed
	var press: Press = World.machines.get(press_c) as Press
	var outc: Chest = World.machines.get(out_c) as Chest
	if bed == null or press == null or outc == null:
		ok("циклы: цепочка встала", false)
		return
	bed.dir = 0
	press.dir = 2
	var col_c: Vector2i = bed_c + Vector2i(-3, 0)
	# Минутный участок мог положить камень в y=0 соседнего столба.
	for y in range(0, col_c.y):
		if World.in_bounds(col_c.x, y) and World.get_tile_v(Vector2i(col_c.x, y)) != IDs.T.AIR:
			World.set_tile(col_c.x, y, IDs.T.AIR)
	MachineBase.place_machine("Collector", col_c)
	var col: Collector = World.machines.get(col_c) as Collector
	if col == null:
		ok("циклы: коллектор", false)
		return
	col.dir = 0
	col._check_sky()
	_flush()
	ok("циклы: грядка под белым", bed.lit,
			"lit %s, небо %s, светит %s, цвет %d" % [
				bed.lit, col.sky_open, col.emitting(),
				World.beams.color_at(bed_c + Vector2i(-1, 0)) if World.beams != null else -1])
	await _proc(48.0)
	var day1: int = _chest_count(outc, IDs.I.PANEL) + press.out_buf
	await _proc(48.0)
	var day2: int = _chest_count(outc, IDs.I.PANEL) + press.out_buf
	var repair: int = 1
	ok("два цикла дали больше панелей, чем ремонт", day2 > repair and day2 >= day1,
			"после 48 с %d, после 96 с %d, ремонт %d" % [day1, day2, repair])
	print("[замер] пресс: партия %.0f с, %d→%d, буфер %d партий; 48 с → %d панелей, 96 с → %d; ремонт одной машины %d" % [
		Balance.PRESS_SECONDS, Balance.PRESS_FIBER_IN, Balance.PRESS_PANEL_OUT,
		Balance.PRESS_BUFFER, day1, day2, repair])
	_gone(col)
	_gone(bed)
	_gone(World.machines.get(chest_c))
	_gone(press)
	_gone(outc)
	_sweep()


## Клетка коридора базы: apply пересобирает мир по сиду и возвращает
## этот воздух. Расчищенная шахта после загрузки снова камень.
func _base_air() -> Vector2i:
	return Vector2i(World.beacon_cell.x + 8, World.beacon_cell.y)


func _line_budget() -> float:
	return Balance.SPORE_BED_SECONDS * float(Balance.PRESS_FIBER_IN) + Balance.PRESS_SECONDS + 1.0


## Машины тикают в _process. wait() считает физику — в headless она отстаёт.
func _proc(secs: float) -> void:
	var until: float = now_proc() + secs
	while now_proc() < until:
		# День 240 с. Минута цепочки иначе уводит полдень в ночь, коллектор гаснет.
		Game.time_of_day = 0.30
		await runner.get_tree().process_frame


func _wait_proc(cond: Callable, timeout: float) -> bool:
	var t0: float = now_proc()
	while now_proc() - t0 < timeout:
		if cond.call():
			return true
		await _proc(0.05)
	return bool(cond.call())


func _spend_panel(chest: Chest, at: Vector2i) -> bool:
	if _chest_count(chest, IDs.I.PANEL) <= 0:
		return false
	if not _chest_take(chest, IDs.I.PANEL, 1):
		return false
	if not World.in_bounds(at.x, at.y):
		return false
	World.set_tile(at.x, at.y, IDs.T.ROOM_PANEL)
	return World.get_tile_v(at) == IDs.T.ROOM_PANEL


func _fiber_books(bed: SporeBed, chest, press: Press, outc: Chest) -> bool:
	var fiber: int = bed.tray + press.batch + press.queued * Balance.PRESS_FIBER_IN
	if chest is Chest:
		fiber += _chest_count(chest, IDs.I.SPORE_FIBER)
	var panels: int = press.out_buf
	if outc != null:
		panels += _chest_count(outc, IDs.I.PANEL)
	return bed.made == fiber + (panels / Balance.PRESS_PANEL_OUT) * Balance.PRESS_FIBER_IN


func _chest_count(chest: Chest, id: int) -> int:
	var n: int = 0
	for s in chest.slots:
		if s.id == id:
			n += s.count
	return n


func _chest_take(chest: Chest, id: int, n: int) -> bool:
	var left: int = n
	for s in chest.slots:
		if s.id != id:
			continue
		var take: int = mini(left, s.count)
		s.take(take)
		left -= take
		if left <= 0:
			chest.queue_redraw()
			return true
	return false


func _saw(text: String) -> bool:
	var hud = UI.hud if UI != null else null
	if hud == null:
		return false
	for n in hud.notes:
		if str(n.get("text", "")) == text:
			return true
	return false


func _note_dump() -> String:
	var hud = UI.hud if UI != null else null
	if hud == null:
		return "hud нет"
	var out: PackedStringArray = PackedStringArray()
	for n in hud.notes:
		out.append(str(n.get("text", "")))
	return ", ".join(out)


func _ground(id: int) -> int:
	var n: int = 0
	for c in get_tree().get_nodes_in_group("items"):
		if c is ItemEntity and c.item_id == id:
			n += c.count
	if n == 0:
		for c in get_tree().root.find_children("*", "ItemEntity", true, false):
			if c is ItemEntity and c.item_id == id and not c.is_queued_for_deletion():
				n += c.count
	return n


func _flush() -> void:
	if World.beams != null:
		World.beams.note_machines()
		World.beams.rebuild()


func _clear(a: Vector2i, b: Vector2i) -> void:
	for x in range(a.x, b.x + 1):
		for y in range(a.y, b.y + 1):
			if World.in_bounds(x, y):
				World.set_tile(x, y, IDs.T.AIR)


func _gone(m) -> void:
	if m != null and is_instance_valid(m) and not m.is_queued_for_deletion():
		m.dismantle()


func _sweep() -> void:
	for c in get_tree().root.find_children("*", "ItemEntity", true, false):
		if c is ItemEntity and not c.is_queued_for_deletion():
			c.queue_free()
