extends ScenarioBase
## Бесконечная игра (ADR-005 § 6.4, #174).
##
## 1. Руда. В радиусе 30 клеток от лагеря копаем весь уголь (explored вокруг шахты
##    открыт — это «разведанная зона»). Пять рассветов: в разведанной зоне новых
##    клеток угля нет, в тумане уголь отрос.
## 2. Фантомы. Тень при смерти роняет SHADE_DROP_COAL угля, мотылёк роя —
##    SWARM_DROP_COPPER меди. Чёрный ящик не мешает: предметы лежат отдельно.
## 3. После сигнала. Победа → экран с кнопкой «Остаться на планете». Клик мышью
##    по stay_rect — то же, что C: PLAYING, signal_sent, ядро на месте, карточка
##    «Смена N · Сигнал отправлен». Пока экран открыт, ЛКМ не копает мир под ним,
##    а клик мимо кнопки игру не продолжает. Повторный запуск ядра доходит до
##    второй победы, в эпилоге — «вторая передача». Хардкор кнопки не даёт.


func run() -> void:
	player.invuln = 1.0e9
	await _regrow()
	await _drops()
	await _stay()
	finish()


# ------------------------------------------------------------------ РУДА

func _regrow() -> void:
	var camp: Vector2i = World.beacon_cell
	var mined: int = 0
	var mined_cells: Array[Vector2i] = []
	for y in range(camp.y - 30, camp.y + 31):
		for x in range(camp.x - 30, camp.x + 31):
			if not World.in_bounds(x, y):
				continue
			if World.get_tile(x, y) != IDs.T.COAL_ORE:
				continue
			World.reveal_around(Vector2i(x, y), 2)
			World.set_tile(x, y, IDs.T.AIR)
			mined_cells.append(Vector2i(x, y))
			mined += 1
	ok("в радиусе 30 от лагеря был уголь", mined > 0, "%d клеток" % mined)
	var fog_before: int = _coal_in_fog()
	var explored_coal: int = _coal_explored()
	for d in range(1, 6):
		World.regrow_ores(d)
	var back: int = 0
	for c in mined_cells:
		if World.get_tile_v(c) == IDs.T.COAL_ORE:
			back += 1
	var fog_after: int = _coal_in_fog()
	ok("за 5 рассветов в разведанной зоне уголь не отрос", back == 0 and _coal_explored() == explored_coal,
			"новых на месте %d, угля в тумане разведки %d → %d" % [back, explored_coal, _coal_explored()])
	ok("в тумане уголь отрос", fog_after > fog_before,
			"%d → %d (+%d)" % [fog_before, fog_after, fog_after - fog_before])
	var initial: int = int(World.ore_initial.get(str(IDs.T.COAL_ORE), 0))
	ok("перепись угля записана", initial > 0, str(initial))


func _coal_in_fog() -> int:
	var n: int = 0
	for i in World.tiles.size():
		if World.tiles[i] == IDs.T.COAL_ORE and World.explored[i] == 0:
			n += 1
	return n


func _coal_explored() -> int:
	var n: int = 0
	for i in World.tiles.size():
		if World.tiles[i] == IDs.T.COAL_ORE and World.explored[i] != 0:
			n += 1
	return n


# ------------------------------------------------------------------ ДРОП

func _drops() -> void:
	var coal0: int = _ground(IDs.I.COAL)
	var shade: Node = spawn_phantom_at(player.global_position + Vector2(48, 0), "shade")
	ok("тень на месте", shade != null)
	if shade != null:
		shade.take_damage(10000.0, player.global_position)
	await await_frame()
	var coal1: int = _ground(IDs.I.COAL)
	ok("тень отдала %d угля" % Balance.SHADE_DROP_COAL, coal1 - coal0 == Balance.SHADE_DROP_COAL,
			"%d → %d" % [coal0, coal1])

	var copper0: int = _ground(IDs.I.COPPER_ORE)
	var pack: Array = spawn_pack_at(player.global_position + Vector2(-48, 0), "swarm")
	ok("рой на месте", pack.size() >= 1, "%d мотыльков" % pack.size())
	var moths: int = 0
	for p in pack:
		if p != null and is_instance_valid(p):
			p.take_damage(10000.0, player.global_position)
			moths += 1
	await await_frame()
	var copper1: int = _ground(IDs.I.COPPER_ORE)
	var want: int = moths * Balance.SWARM_DROP_COPPER
	ok("рой отдал по %d меди за мотылька" % Balance.SWARM_DROP_COPPER, copper1 - copper0 == want,
			"%d мотыльков, меди %d → %d" % [moths, copper0, copper1])


func _ground(item_id: int) -> int:
	var n: int = 0
	for c in scene.get_children():
		if c is ItemEntity and c.item_id == item_id:
			n += c.count
	return n


# ------------------------------------------------------------------ ОСТАТЬСЯ

func _stay() -> void:
	# Game.player сценарий не ставит: try_finish берёт героя из аргумента.
	var core: Vector2i = World.beacon_cell + Vector2i(2, 0)
	World.set_tile(core.x, core.y, IDs.T.AIR)
	MachineBase.place_machine("RainbowCore", core)
	for c in [Beams.R, Beams.G, Beams.B, Beams.Y, Beams.C, Beams.M]:
		Game.core_feed(c)
	Game.tasks_done = 1
	Game.stats_ore = Balance.FREE_ORE_NEED
	Game.nights_survived = Balance.FREE_NIGHTS_NEED
	Game.try_finish(player)
	ok("ядро запущено для проверки финала", Game.relay_active)
	Game.relay_timer = 0.05
	var won: bool = await wait_until(func() -> bool: return Game.state == Game.State.WON, 2.0)
	ok("сигнал ушёл — победа", won and Game.signal_sent and Game.signal_sends == 1,
			"state=%d sends=%d" % [Game.state, Game.signal_sends])
	var es: EndScreen = scene.get("end_screen")
	await await_frame()
	ok("на финале есть «Остаться на планете»", es != null and es.visible and es.can_stay
			and es.stay_rect.size.x > 0.0 and es.stay_rect.size.y >= EndScreen.STAY_MIN_HIT,
			es.title if es != null else "нет экрана")
	var beacon: Vector2i = World.beacon_cell
	# Пока экран открыт, зажатая ЛКМ не должна копать клетку под курсором (#214).
	var dig: Vector2i = find_mineable()
	ok("есть клетка, которую клик мог бы выкопать", dig.x >= 0, str(dig))
	var dig_before: int = World.get_tile_v(dig) if dig.x >= 0 else -1
	if dig.x >= 0:
		aim(World.cell_to_world(dig))
		press_mouse(MOUSE_BUTTON_LEFT)
		await wait(0.6)
		ok("клик сквозь экран победы не копает", World.get_tile_v(dig) == dig_before
				and player.mining_progress <= 0.0,
				"тайл %d → %d, прогресс %.2f" % [dig_before, World.get_tile_v(dig), player.mining_progress])
		release_mouse(MOUSE_BUTTON_LEFT)
	# Клик мимо кнопки игру не продолжает: только прямоугольник stay_rect.
	_click_screen(es.stay_rect.position + Vector2(-8.0, es.stay_rect.size.y * 0.5))
	await await_frame()
	ok("клик мимо кнопки не оставляет на планете", Game.state == Game.State.WON and es.visible,
			"state=%d" % Game.state)
	# Клик мышью по кнопке — тот же путь, что C: событие в EndScreen._gui_input.
	_click_screen(es.stay_rect.get_center())
	var stayed: bool = await wait_until(func() -> bool: return Game.state == Game.State.PLAYING, 2.0)
	ok("клик по кнопке — остались, состояние PLAYING", stayed and Game.signal_sent,
			"state=%d" % Game.state)
	ok("экран финала закрыт", es != null and not es.visible)
	ok("ядро на месте", World.beacon_cell == beacon, str(World.beacon_cell))
	var hud: HUD = UI.hud
	if hud != null:
		hud._compute_tracker()
	ok("карточка: «Смена %d · Сигнал отправлен»" % Game.day_number,
			hud != null and hud.tracker_title == "Смена %d · Сигнал отправлен" % Game.day_number,
			hud.tracker_title if hud != null else "нет HUD")
	var again: bool = Game.try_finish(player)
	ok("повторный запуск ядра возможен", again and Game.relay_active,
			"relay_active=%s" % str(Game.relay_active))
	Game.relay_timer = 0.05
	var won2: bool = await wait_until(func() -> bool: return Game.state == Game.State.WON, 2.0)
	ok("вторая передача — снова победа", won2 and Game.signal_sends == 2, "sends=%d" % Game.signal_sends)
	await await_frame()
	ok("эпилог второй передачи", es != null and es.visible and es.epilogue.contains("Вторая передача"),
			es.epilogue.right(60) if es != null else "")
	# Хардкор: победа завершает забег, кнопки нет и C ничего не делает.
	# Флаг сцены, не аргумент — следующий сценарий его не унаследует.
	scene.set("hardcore", true)
	Game.set_state(Game.State.PLAYING)
	Game.set_state(Game.State.WON)
	await await_frame()
	ok("хардкор: кнопки «Остаться» нет", es.visible and not es.can_stay and es.stay_rect.size.x == 0.0)
	es.stay_requested.emit()
	await await_frame()
	ok("хардкор: C не возвращает в игру", Game.state == Game.State.WON and es.visible)
	scene.set("hardcore", false)


## Клик ЛКМ в экранной точке. В headless вьюпорт мышь до контрола не доводит
## (как у панели инвентаря, #69): событие идёт в _gui_input — тот же обработчик,
## что ловит клик по кнопке на десктопе (Control на весь экран, MOUSE_FILTER_STOP).
func _click_screen(pos: Vector2) -> void:
	var screen: EndScreen = scene.get("end_screen")
	for pressed in [true, false]:
		var ev: InputEventMouseButton = InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		if screen != null:
			screen._gui_input(ev)
		await get_tree().process_frame
