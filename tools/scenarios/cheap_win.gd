extends ScenarioBase
## Свободная победа не даётся двумя предметами (#212, ADR-005 § 6.3–6.4).
##
## Дешёвый путь: коллектор + ядро, белый луч. Семь дуг не зажигаются,
## этап добычи не закрывается, E 3 с релей не стартует.
## Честный путь на том же сиде: терминал удержанием E, 12 руды киркой,
## поставленные блоки, ночь часами игры, шесть цветов, запуск и удержание
## (отсчёт ускорен). Печатает секунды честного забега против 6 с накрутки.


func run() -> void:
	player.invuln = 1.0e9
	await wait_until(func() -> bool: return Game.objective_stage == 1, 2.0)
	var t0: float = Game.game_time
	var cheap: bool = await _cheap()
	ok("два предмета не дают победу", cheap)
	var honest: float = await _honest()
	var minutes: float = honest / 60.0
	print("  [замер] честный забег: %.1f с игрового времени (%.1f мин), от старта %.1f с" % [
			honest, minutes, Game.game_time - t0])
	ok("честный путь доходит до победы", Game.state == Game.State.WON, "state=%d" % Game.state)
	# Было: 6 с накрутки (tasks_done, stats_ore, прыжок часов, core_feed).
	# Стало: терминал E, 12 руды киркой, 4 блока ПКМ, ночь часами игры.
	# Удержание 180 с в зачёт не входит — отсчёт ускорен, иначе сценарий не уложится.
	print("  [замер] честный путь: было 6 с накрутки, стало %.1f с игрового времени" % honest)
	var floor_s: float = 2.2 + 12.0 * 1.8 + 4.0 * 0.3 + Balance.DAY_LENGTH * (1.0 - Balance.NIGHT_START)
	print("  [замер] нижняя граница без удержания: %.0f с (терминал + кирка + блоки + ночь)" % floor_s)
	ok("честный путь длиннее накрутки", honest > 60.0, "%.0f с" % honest)
	ok("честный путь не длиннее получаса игрового времени", honest < 30.0 * 60.0, "%.0f с" % honest)
	finish()


## Коллектор бьёт белым в ядро. Релей молчит, дуг нет, добыча не засчитана.
func _cheap() -> bool:
	var core: Vector2i = World.beacon_cell + Vector2i(2, -2)
	var col: Vector2i = core + Vector2i(-2, 0)
	_clear(core, 6)
	if not MachineBase.place_machine("RainbowCore", core):
		ok("ядро дешёвого пути поставлено", false, str(core))
		return false
	# Призма лагеря на пути белого дала бы три цвета — это уже не «два предмета».
	for m in World.machines.values():
		if m is Prism:
			m.queue_free()
	if not MachineBase.place_machine("Collector", col):
		ok("коллектор дешёвого пути поставлен", false, str(col))
		return false
	var collector: Collector = World.machines.get(col)
	collector.dir = 0
	# Столбец до неба пуст: коллектор светит сам, не поддельным флагом.
	for y in range(0, col.y):
		if World.in_bounds(col.x, y) and DB.tile_solid(World.get_tile(col.x, y)):
			World.set_tile(col.x, y, IDs.T.AIR)
	collector._check_sky()
	Game.time_of_day = 0.30
	if World.beams != null:
		World.beams.note_machines()
		World.beams.rebuild()
	await wait(0.4)
	if World.beams != null:
		World.beams.note_machines()
		World.beams.rebuild()
	var mask: int = 0
	var core_m = World.machines.get(core)
	if core_m != null:
		mask = int(core_m.get("_beam"))
	ok("белый луч дошёл до ядра", mask == Beams.W, "маска %d" % mask)
	ok("белый не зажёг ни одной дуги", Game.core_arc_count() == 0, "дуг %d" % Game.core_arc_count())
	ok("добыча от белого луча не выросла", Game.stats_ore == 0, "руда %d" % Game.stats_ore)
	ok("этап всё ещё 1 — запитать", Game.objective_stage == 1, Game.objective_text())
	var launched: bool = Game.core_launch()
	ok("E у ядра релей не стартует", not launched and not Game.relay_active, Game.free_block_text())
	ok("победы нет", Game.state != Game.State.WON)
	if collector != null and is_instance_valid(collector):
		collector.queue_free()
	return not Game.relay_active and Game.core_arc_count() == 0 and Game.state != Game.State.WON


## Терминал, руда киркой, поставленные блоки, ночь часами игры, шесть цветов,
## удержание. Возвращает игровые секунды до победы.
## Было (#212, дыра приёмки): tasks_done = 1, stats_ore += 1, прыжок time_of_day
## и прямой core_feed — 6 с накрутки. Теперь игрок читает терминал, копает и
## ставит блоки сам. Шесть дуг по-прежнему core_feed: оптика на шесть цветов
## в сценарий не влезает (отложено, см. issue).
func _honest() -> float:
	var t0: float = Game.game_time
	Game.core_arcs = 0
	# Глава прошлого сценария прогона оставляет Game.mission, и тогда
	# update_objective молчит: этап не двигается, хотя терминал прочитан.
	if Game.mission != null and is_instance_valid(Game.mission):
		var parent: Node = Game.mission.get_parent()
		if parent != null:
			parent.remove_child(Game.mission)
		Game.mission.free()
	Game.mission = null
	var read: bool = await _read_camp_terminal()
	ok("терминал прочитан удержанием E", read and Game.tasks_done >= 1, "заданий %d" % Game.tasks_done)
	Game.update_objective()
	ok("терминал → этап добычи", Game.objective_stage == 2, Game.objective_text())
	var dug: int = await _dig_ore(Balance.FREE_ORE_NEED)
	ok("12 руды киркой, не счётчиком", dug >= Balance.FREE_ORE_NEED and Game.stats_ore >= Balance.FREE_ORE_NEED
			and Game.stats_mined >= Balance.FREE_ORE_NEED,
			"выкопано %d, руда %d, блоков %d" % [dug, Game.stats_ore, Game.stats_mined])
	Game.update_objective()
	ok("12 руды → этап ночи", Game.free_mined() and Game.objective_stage == 3, Game.objective_text())
	var placed: int = await _place_blocks(4)
	ok("блоки поставлены ПКМ, не вызовом мира", placed >= 4, "поставлено %d" % placed)
	# Ночь — часами игры, не прыжком advance_clock. До заката и через рассвет.
	# Ускорение времени — тот же Engine.time_scale, что у ночи главы «Цвета».
	var night_s: float = await _live_night()
	print("  [замер] ночь прожита за %.1f с игрового времени (было: прыжок 0.06 цикла)" % night_s)
	ok("рассвет засчитан проживанием ночи", Game.nights_survived >= 1 and Game.free_night_done(),
			"ночей %d" % Game.nights_survived)
	ok("после ночи — этап дуг", Game.objective_stage == 4, Game.objective_text())
	# Ядро дешёвого пути снято, чтобы не перехватывало E у терминала.
	# Запуск честного пути требует стоящее ядро — ставим заново, в стороне от блоков.
	var core: Vector2i = World.beacon_cell + Vector2i(-4, -2)
	_clear(core, 3)
	ok("ядро честного пути поставлено", MachineBase.place_machine("RainbowCore", core), str(core))
	for c in [Beams.R, Beams.G, Beams.B, Beams.Y, Beams.C, Beams.M]:
		Game.core_feed(c)
	ok("шесть цветов → запуск", Game.core_arc_count() == 6 and Game.objective_stage == 5,
			Game.objective_text())
	# Белый по-прежнему не седьмой цвет.
	Game.core_feed(Beams.W)
	ok("белый и после ночи не седьмая дуга", Game.core_arc_count() == 6)
	var started: bool = Game.core_launch()
	ok("честный запуск пошёл", started and Game.relay_active and Game.objective_stage == 6)
	# Удержание — 180 с игрового времени. Ускорение отсчёта (relay_speed) оставляет
	# часы забега короткими: в замер честного пути оно не входит, см. печать ниже.
	var hold0: float = Game.game_time
	Game.relay_speed = 30.0
	var won: bool = await wait_until(func() -> bool: return Game.state == Game.State.WON, 12.0)
	Game.relay_speed = 1.0
	ok("удержание дошло до эвакуации", won)
	print("  [замер] удержание в зачёте: %.1f с часов (релей ускорен ×30, в игре 180 с)" % (
			Game.game_time - hold0))
	return Game.game_time - t0


## Прочитать терминал лагеря удержанием E, как игрок. Не tasks_done = 1.
func _read_camp_terminal() -> bool:
	var t: Vector2i = Vector2i(-1, -1)
	var best: float = INF
	for cell in World.terminals:
		var d: float = World.cell_to_world(cell).distance_to(World.spawn_point)
		if d < best:
			best = d
			t = cell
	if t.x < 0:
		ok("терминал лагеря найден", false)
		return false
	var spot: Vector2 = World.cell_to_world(t)
	var stood: bool = place_near(spot, [Vector2(0, -24), Vector2(24, 0), Vector2(-24, 0),
			Vector2(24, -24), Vector2(-24, -24), Vector2(0, -40)])
	ok("герой встал у терминала", stood, str(t))
	if not stood:
		return false
	# Ядро дешёвого пути перехватывает E и держит цель, пока стоит.
	for m in World.machines.values():
		if m is RainbowCore and is_instance_valid(m):
			m.queue_free()
	await await_frame()
	await wait(0.3)
	var before: int = Game.tasks_done
	hold(KEY_E)
	var done: bool = await wait_until(func() -> bool: return Game.tasks_done > before, 4.0)
	release(KEY_E)
	return done


## Выкопать need клеток руды ЛКМ по лучу. Руда кладётся в воздух перед героем:
## жила сида может быть за стеной, а обещание фикса — «игрок копает», не «счётчик».
func _dig_ore(need: int) -> int:
	stand_in_corridor(4)
	await wait(0.2)
	var dug: int = 0
	var pc: Vector2i = World.world_to_cell(player.global_position)
	while dug < need:
		var cell: Vector2i = Vector2i(pc.x + 3, pc.y)
		World.set_tile(cell.x, cell.y, IDs.T.COAL_ORE)
		var before: int = Game.stats_ore
		aim(World.cell_to_world(cell))
		press_mouse(MOUSE_BUTTON_LEFT)
		var broke: bool = await wait_until(func() -> bool:
			return Game.stats_ore > before, 4.0)
		release_mouse(MOUSE_BUTTON_LEFT)
		if not broke:
			break
		dug += 1
		await wait(0.05)
	return dug


## Поставить n каменных блоков ПКМ. Возвращает, сколько встало.
func _place_blocks(n: int) -> int:
	stand_in_corridor(2)
	player.inv.add(IDs.I.STONE, n)
	var slot: int = -1
	for i in player.inv.slots.size():
		if player.inv.slots[i].id == IDs.I.STONE:
			slot = i
			break
	if slot < 0:
		return 0
	player.inv.selected = slot
	var pc: Vector2i = World.world_to_cell(player.global_position)
	var placed: int = 0
	for i in n:
		var cell: Vector2i = Vector2i(pc.x + 2 + (i % 3), pc.y - 1 - int(i / 3))
		if not World.in_bounds(cell.x, cell.y):
			continue
		if World.machines.has(cell):
			continue
		if World.get_tile_v(cell) != IDs.T.AIR:
			World.set_tile(cell.x, cell.y, IDs.T.AIR)
		var had: int = player.inv.count_of(IDs.I.STONE)
		aim(World.cell_to_world(cell))
		press_mouse(MOUSE_BUTTON_RIGHT)
		await wait(0.25)
		release_mouse(MOUSE_BUTTON_RIGHT)
		await wait(0.1)
		if World.get_tile_v(cell) == IDs.T.STONE and player.inv.count_of(IDs.I.STONE) < had:
			placed += 1
	release_mouse(MOUSE_BUTTON_RIGHT)
	return placed


## Прожить ночь часами игры: от заката до рассвета. Ускорение — time_scale,
## не прыжок advance_clock (тот ночь не засчитывает, если шаг длиннее цикла).
## Возвращает игровые секунды, которые прошли по Game.game_time.
func _live_night() -> float:
	var t0: float = Game.game_time
	var nights0: int = Game.nights_survived
	Game.time_of_day = Balance.NIGHT_START + 0.01
	Engine.time_scale = 16.0
	var dawn: bool = await wait_until(func() -> bool:
		return Game.nights_survived > nights0, 120.0)
	Engine.time_scale = 1.0
	ok("рассвет пришёл часами, не прыжком", dawn, "время %.3f" % Game.time_of_day)
	return Game.game_time - t0


func _clear(center: Vector2i, r: int) -> void:
	for x in range(center.x - r, center.x + r + 1):
		for y in range(center.y - r, center.y + r + 1):
			if World.in_bounds(x, y) and World.machines.get(Vector2i(x, y)) == null:
				World.set_tile(x, y, IDs.T.AIR)
	var floor_y: int = center.y + 1
	for x in range(center.x - r, center.x + r + 1):
		if World.in_bounds(x, floor_y):
			World.set_tile(x, floor_y, IDs.T.STEEL)
