extends ScenarioBase
## Свободная победа не даётся двумя предметами (#212, ADR-005 § 6.3–6.4).
##
## Дешёвый путь: коллектор + ядро, белый луч. Семь дуг не зажигаются,
## этап добычи не закрывается, E 3 с релей не стартует.
## Честный путь на том же сиде: терминал, 12 руды, одна ночь, шесть цветов,
## запуск и удержание (отсчёт ускорен). Печатает минуты честного забега.


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
	# Часы забега: терминал, 12 руды, ночь до рассвета и 180 с сигнала.
	# Сценарий ночь сжимает до границы рассвета, сигнал ускоряет — в логе секунды.
	var floor_s: float = 150.0 + 12.0 * 2.0 + 90.0 + Balance.RELAY_TIME
	print("  [замер] нижняя граница честного забега: %.0f с (%.1f мин)" % [floor_s, floor_s / 60.0])
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


## Терминал, руда, ночь, шесть цветов, удержание. Возвращает игровые секунды до победы.
func _honest() -> float:
	var t0: float = Game.game_time
	# Дешёвый луч мог зажечь дуги, если рядом стояла чужая призма. Честный путь
	# зажигает шесть цветов сам.
	Game.core_arcs = 0
	Game.tasks_done = 1
	Game.update_objective()
	ok("терминал → этап добычи", Game.objective_stage == 2, Game.objective_text())
	for _i in Balance.FREE_ORE_NEED:
		Game.stats_ore += 1
	Game.update_objective()
	ok("12 руды → этап ночи", Game.free_mined() and Game.objective_stage == 3, Game.objective_text())
	# Старт забега — уже рассвет. В ночь, потом короткий шаг через рассвет:
	# так считает Game.advance_clock, прыжок длиннее цикла ночь не даёт.
	Game.time_of_day = 0.99
	Game.advance_clock(0.06)
	var dawn: bool = Game.nights_survived >= 1
	ok("рассвет засчитан", dawn and Game.free_night_done(), "ночей %d" % Game.nights_survived)
	ok("после ночи — этап дуг", Game.objective_stage == 4, Game.objective_text())
	for c in [Beams.R, Beams.G, Beams.B, Beams.Y, Beams.C, Beams.M]:
		Game.core_feed(c)
	ok("шесть цветов → запуск", Game.core_arc_count() == 6 and Game.objective_stage == 5,
			Game.objective_text())
	# Белый по-прежнему не седьмой цвет.
	Game.core_feed(Beams.W)
	ok("белый и после ночи не седьмая дуга", Game.core_arc_count() == 6)
	var started: bool = Game.core_launch()
	ok("честный запуск пошёл", started and Game.relay_active and Game.objective_stage == 6)
	Game.relay_speed = 30.0
	var won: bool = await wait_until(func() -> bool: return Game.state == Game.State.WON, 12.0)
	Game.relay_speed = 1.0
	ok("удержание дошло до эвакуации", won)
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
