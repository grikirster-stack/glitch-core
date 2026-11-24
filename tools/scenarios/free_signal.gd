extends ScenarioBase
## Свободная игра — постоянная база (ADR-006 § 2, § 4, § 6, #315).
##
## Новый мир строится сразу: ядро запускается без горелки, руды и ночи.
## Успех пишет signal_sent и signal_sends, часы и ввод не встают, экран победы
## не открывается. Второй сигнал доходит до второй передачи.
## Метка базы рождается у капсулы и переносится на свой сундук. Чужой сундук
## и перенос посреди налёта точку этой волны не двигают.
## Старый файл: идущий сигнал продолжает свой таймер, дуги и история на месте.
## Кампания и хардкор по-прежнему заканчивают забег экраном.
##
## На dbcfeb8 красный: запуск без этапов 1–3 отказывает, успех ставит WON
## и глушит часы, метки базы нет. Методы новой ветки спрашиваем через has_method,
## чтобы на базе это была проверка, а не ошибка скрипта.


const SLOT: String = "free_signal"


func run() -> void:
	player.invuln = 1.0e9
	await _free_launch()
	await _second_signal()
	await _base_mark()
	await _old_save()
	await _campaign_and_hardcore()
	finish()


# ------------------------------------------------------------------ ЗАПУСК

## Новый мир: ядро и шесть дуг достаточны. Горелка, руда и ночь не нужны.
func _free_launch() -> void:
	var cell: Vector2i = _place_core(World.beacon_cell + Vector2i(2, 0))
	ok("ядро поставлено в новом мире", cell.x >= 0 and Game.core_placed(), str(cell))
	if cell.x < 0:
		return
	_feed_six()
	ok("шесть дуг горят", Game.core_arcs == Game.CORE_ARCS_FREE, str(Game.core_arcs))
	ok("этапы 1–3 не сданы", Game.tasks_done == 0 and Game.stats_ore == 0
			and Game.nights_survived == 0 and not Game.free_ready(),
			"руда %d, ночей %d" % [Game.stats_ore, Game.nights_survived])
	var launched: bool = Game.core_launch()
	ok("запуск без этапов 1–3", launched and Game.relay_active, Game.core_block_text())
	ok("удержание — 90 с", is_equal_approx(Game.relay_timer, Balance.RELAY_TIME),
			"%.1f" % Game.relay_timer)
	var t0: float = Game.game_time
	var day0: int = Game.day_number
	var clock0: float = Game.time_of_day
	Game.relay_timer = 0.05
	var done: bool = await wait_until(func() -> bool: return Game.signal_sends >= 1, 2.0)
	await await_frame()
	var es: EndScreen = scene.get("end_screen")
	ok("сигнал записан, мир не встал", done and Game.signal_sent and Game.signal_sends == 1
			and Game.state == Game.State.PLAYING and not Game.relay_active,
			"state=%d sends=%d" % [Game.state, Game.signal_sends])
	ok("экран победы не открылся", es == null or not es.visible,
			es.title if es != null and es.visible else "")
	ok("сутки идут после сигнала", Game.game_time > t0 + 0.02 and Game.time_of_day != clock0,
			"время %.2f → %.2f, сутки %.3f → %.3f" % [t0, Game.game_time, clock0, Game.time_of_day])
	# Ввод жив: клик копает клетку. На старом пути экран победы его съедает.
	var dig: Vector2i = find_mineable()
	ok("есть клетка под клик", dig.x >= 0, str(dig))
	if dig.x >= 0:
		var before: int = World.get_tile_v(dig)
		aim(World.cell_to_world(dig))
		press_mouse(MOUSE_BUTTON_LEFT)
		await wait(0.6)
		release_mouse(MOUSE_BUTTON_LEFT)
		ok("клик после сигнала копает", World.get_tile_v(dig) != before,
				"тайл %d → %d" % [before, World.get_tile_v(dig)])
	ok("смена не сброшена сигналом", Game.day_number == day0, "%d → %d" % [day0, Game.day_number])
	# Старый путь оставил WON: дальше сценарий не имеет смысла, но проверки метки
	# должны отчитаться. Возвращаем PLAYING, чтобы загрузка и глава не упирались в экран.
	if Game.state != Game.State.PLAYING:
		Game.set_state(Game.State.PLAYING)
		if es != null and es.has_method("hide_end"):
			es.hide_end()


## Второй сигнал в том же мире: ещё 90 с, счётчик 2, снова без экрана.
func _second_signal() -> void:
	Game.signal_sent = true
	var again: bool = Game.core_launch()
	ok("второй запуск ядра", again and Game.relay_active, Game.core_block_text())
	if not Game.relay_active:
		return
	Game.relay_timer = 0.05
	var want: int = Game.signal_sends + 1
	var done: bool = await wait_until(func() -> bool: return Game.signal_sends >= want, 2.0)
	await await_frame()
	var es: EndScreen = scene.get("end_screen")
	ok("вторая передача в том же мире", done and Game.signal_sends >= 2
			and Game.state == Game.State.PLAYING and Game.signal_sent,
			"state=%d sends=%d" % [Game.state, Game.signal_sends])
	ok("второй сигнал тоже без экрана", es == null or not es.visible)
	if Game.state != Game.State.PLAYING:
		Game.set_state(Game.State.PLAYING)
		if es != null and es.has_method("hide_end"):
			es.hide_end()


# ------------------------------------------------------------------ МЕТКА

## Метка рождается у капсулы. Свой сундук её принимает, чужой — нет.
## Посреди налёта перенос не двигает точку этой волны.
## На базе методов нет: это и есть красная проверка, не ошибка скрипта.
func _base_mark() -> void:
	var has_mark: bool = Game.has_method("base_mark_cell")
	var born: Vector2i = Game.base_mark_cell() if has_mark else Vector2i(-99, -99)
	ok("метка родилась у капсулы", has_mark and born == World.beacon_cell,
			"%s, капсула %s" % [born, World.beacon_cell])
	var chest: Vector2i = _place_chest(World.beacon_cell + Vector2i(4, 0))
	ok("свой сундук поставлен", chest.x >= 0, str(chest))
	if chest.x < 0:
		return
	var moved: bool = Game.has_method("base_mark_move") and Game.base_mark_move(chest, player)
	var at: Vector2i = Game.base_mark_cell() if has_mark else Vector2i(-99, -99)
	ok("метка перенесена на свой сундук", moved and at == chest, str(at))
	# Чужой сундук: другой uid. Одиночный герой — uid 0, чужой — 7.
	var foreign: Vector2i = _place_chest(World.beacon_cell + Vector2i(6, 0))
	var box = World.machines.get(foreign)
	if box != null:
		box.set("owner_uid", 7)
	var denied: bool = Game.has_method("base_mark_move") and not Game.base_mark_move(foreign, player)
	at = Game.base_mark_cell() if Game.has_method("base_mark_cell") else Vector2i(-99, -99)
	ok("чужой сундук метку не берёт", denied and at == chest, str(at))
	# Налёт: перенос влияет на следующую волну, не на текущую.
	Game.set("raid_active", true)
	var later: Vector2i = _place_chest(World.beacon_cell + Vector2i(8, 0))
	var during: bool = Game.has_method("base_mark_move") and Game.base_mark_move(later, player)
	var now_mark: Vector2i = Game.base_mark_cell() if Game.has_method("base_mark_cell") else Vector2i(-99, -99)
	var anchor: Vector2i = Game.base_mark_anchor() if Game.has_method("base_mark_anchor") else Vector2i(-99, -99)
	ok("перенос посреди налёта принят", during and now_mark == later, str(now_mark))
	ok("волна держит прежнюю точку", Game.has_method("base_mark_anchor") and anchor == chest,
			"якорь %s, метка %s" % [anchor, now_mark])
	Game.set("raid_active", false)
	anchor = Game.base_mark_anchor() if Game.has_method("base_mark_anchor") else Vector2i(-99, -99)
	ok("после налёта точка — новая", Game.has_method("base_mark_anchor") and anchor == later,
			str(anchor))
	# Разрушенный сундук: волна держит последнюю точку, метка возвращается к капсуле.
	Game.set("raid_active", true)
	var gone = World.machines.get(later)
	if gone != null and gone.has_method("dismantle"):
		gone.dismantle()
	await await_frame()
	anchor = Game.base_mark_anchor() if Game.has_method("base_mark_anchor") else Vector2i(-99, -99)
	now_mark = Game.base_mark_cell() if Game.has_method("base_mark_cell") else Vector2i(-99, -99)
	ok("сундук снесён — волна держит точку", Game.has_method("base_mark_anchor")
			and anchor == later and now_mark == World.beacon_cell,
			"якорь %s, метка %s" % [anchor, now_mark])
	Game.set("raid_active", false)


# ------------------------------------------------------------------ СТАРЫЙ ФАЙЛ

## Активный сигнал старого файла продолжает таймер. Дуги, счётчик и история
## не теряются. Файл без метки читается: метка рождается у капсулы.
func _old_save() -> void:
	var slot0: String = Save.slot
	Save.slot = SLOT
	Save.remove(SLOT)
	Game.core_arcs = Game.CORE_ARCS_FREE
	Game.signal_sent = true
	Game.signal_sends = 3
	Game.relay_active = true
	Game.relay_timer = 42.0
	Game.stats_ore = 17
	Game.nights_survived = 2
	Game.set_objective_stage(Game.OBJECTIVE_STAGES)
	var cell: Vector2i = Game.core_cell
	var d: Dictionary = Save.gather()
	# Старый файл метки не знает: поле вырезаем, как будто его не писали.
	var game_d: Dictionary = d.get("game", {})
	game_d.erase("base_mark")
	game_d.erase("base_mark_set")
	game_d.erase("base_mark_pending")
	d["game"] = game_d
	var blob: PackedByteArray = Save.encode(d)
	var f: FileAccess = FileAccess.open(Save.path_for(SLOT), FileAccess.WRITE)
	if f != null:
		f.store_buffer(blob)
		f.close()
	# Мир «портим», как перед F9: отсчёт сброшен, дуги погашены.
	Game.relay_active = false
	Game.relay_timer = 0.0
	Game.core_arcs = 0
	Game.signal_sent = false
	Game.signal_sends = 0
	if Game.has_method("base_mark_cell"):
		Game.set("base_mark", Vector2i(3, 3))
		Game.set("base_mark_set", true)
	var loaded: bool = Save.load_game(SLOT)
	ok("старый файл прочитан", loaded, Save.last_error)
	ok("идущий сигнал продолжает таймер", Game.relay_active and absf(Game.relay_timer - 42.0) < 0.6,
			"%.1f с, active=%s" % [Game.relay_timer, str(Game.relay_active)])
	ok("дуги и история на месте", Game.core_arcs == Game.CORE_ARCS_FREE
			and Game.signal_sent and Game.signal_sends == 3 and Game.stats_ore == 17
			and Game.nights_survived == 2 and Game.core_cell == cell,
			"дуги %d, передач %d, руда %d" % [Game.core_arcs, Game.signal_sends, Game.stats_ore])
	var mark_absent: bool = Game.get("base_mark_set") != true
	var mark_at: Vector2i = Game.base_mark_cell() if Game.has_method("base_mark_cell") else Vector2i(-99, -99)
	ok("файл без метки — метка у капсулы", Game.has_method("base_mark_cell")
			and mark_absent and mark_at == World.beacon_cell, str(mark_at))
	# Свежий файл метку пишет — на свой сундук, не на ядро.
	var wrote: bool = false
	var chest: Vector2i = _place_chest(World.beacon_cell + Vector2i(-4, 0))
	if Game.has_method("base_mark_move") and chest.x >= 0:
		Game.base_mark_move(chest, player)
		var written: Dictionary = Save.gather()
		var wg: Dictionary = written.get("game", {})
		wrote = wg.has("base_mark") and wg.get("base_mark") == chest
	ok("свежий файл пишет метку", wrote, str(chest))
	Save.remove(SLOT)
	Save.slot = slot0
	Game.relay_active = false
	Game.relay_timer = 0.0


# ------------------------------------------------------------------ КАМПАНИЯ И ХАРДКОР

## Кампания по-прежнему заканчивает главу экраном. Хардкор — забег экраном,
## без возврата в мир. Свободный успех хардкор не завершает: одна жизнь — про смерть.
func _campaign_and_hardcore() -> void:
	var es: EndScreen = scene.get("end_screen")
	var m = Campaign.start(scene, "dig")
	ok("глава «Сигнал» начата", m != null and Game.in_mission(), str(m))
	if m != null and m.has_method("win"):
		m.win()
		await await_frame()
		ok("кампания заканчивается экраном", Game.state == Game.State.WON
				and es != null and es.visible and not es.can_stay,
				es.title if es != null else "нет экрана")
		Game.mission = null
		Game.set_state(Game.State.PLAYING)
		if es != null and es.has_method("hide_end"):
			es.hide_end()
	# Хардкор: смерть по-прежнему кончает забег. Сигнал — нет: мир продолжается,
	# но принудительная победа (set_state WON) экраном остаётся и C не возвращает.
	scene.set("hardcore", true)
	Game.signal_sent = false
	Game.signal_sends = 0
	Game.relay_active = true
	Game.relay_timer = 0.05
	var continued: bool = await wait_until(func() -> bool:
		return Game.signal_sends >= 1 and Game.state == Game.State.PLAYING, 2.0)
	await await_frame()
	ok("хардкор: сигнал не кончает забег", continued and Game.state == Game.State.PLAYING
			and (es == null or not es.visible),
			"state=%d sends=%d" % [Game.state, Game.signal_sends])
	Game.set_state(Game.State.WON)
	await await_frame()
	ok("хардкор: экран победы, кнопки нет", Game.state == Game.State.WON
			and es != null and es.visible and not es.can_stay,
			es.title if es != null else "")
	if es != null:
		es.stay_requested.emit()
	await await_frame()
	ok("хардкор: остаться нельзя", Game.state == Game.State.WON and es != null and es.visible)
	scene.set("hardcore", false)
	Game.set_state(Game.State.PLAYING)
	if es != null and es.has_method("hide_end"):
		es.hide_end()


# ------------------------------------------------------------------ УТИЛИТЫ

func _place_core(cell: Vector2i) -> Vector2i:
	if World.get_tile_v(cell) != IDs.T.AIR:
		World.set_tile(cell.x, cell.y, IDs.T.AIR)
	if not MachineBase.place_machine("RainbowCore", cell):
		return Vector2i(-1, -1)
	return cell


func _place_chest(cell: Vector2i) -> Vector2i:
	if World.get_tile_v(cell) != IDs.T.AIR:
		World.set_tile(cell.x, cell.y, IDs.T.AIR)
	if World.machines.has(cell):
		return Vector2i(-1, -1)
	if not MachineBase.place_machine("Chest", cell):
		return Vector2i(-1, -1)
	return cell


func _feed_six() -> void:
	for c in [Beams.R, Beams.G, Beams.B, Beams.Y, Beams.C, Beams.M]:
		Game.core_feed(c)
