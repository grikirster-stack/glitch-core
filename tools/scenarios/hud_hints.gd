extends ScenarioBase
## Подсказки HUD (issue #7): HUD больше не перебирает все постройки мира, но
## подсказка ТЭЦ (топка / рубильник, #34) / «открыть сундук» по-прежнему появляется
## сразу, как герой подошёл, и пропадает сразу, как отошёл.
##
## В коридоре базы ставим ТЭЦ и сундук, вокруг — ещё 200 построек вдали (как
## большая фабрика). Герой идёт вправо мимо обеих построек и обратно; каждый
## кадр сверяем подсказку HUD с ожидаемой по расстоянию. Допуск — 2 кадра
## (HUD и сценарий обновляются в разном порядке внутри кадра).

const DIST: float = 40.0
const HINT_CHEST: String = HUD.HINT_CHEST
const MAX_LAG_FRAMES: int = 2


func run() -> void:
	var base: int = stand_in_corridor(4)   # bx+5: дальше 56 px от релея
	clear_input()
	var bx: int = World.beacon_cell.x
	var hud: HUD = UI.hud
	var gen_cell: Vector2i = Vector2i(bx + 9, base - 1)
	var chest_cell: Vector2i = Vector2i(bx + 14, base - 1)
	var placed: bool = MachineBase.place_machine("CoalGen", gen_cell) \
			and MachineBase.place_machine("Chest", chest_cell)
	ok("ТЭЦ и сундук поставлены", placed)
	# Большая фабрика вдали: подсказки не должны от неё зависеть.
	var far: int = 0
	for i in 400:
		if far >= 200:
			break
		var c: Vector2i = Vector2i(20 + i % 40, 4 + i / 40)
		World.set_tile(c.x, c.y, IDs.T.AIR)
		if MachineBase.place_machine("Chest" if i % 2 == 0 else "CoalGen", c):
			far += 1
	ok("вдали поставлено 200 построек", far == 200, "%d" % far)
	if not placed:
		finish()
		return
	var gen: Node2D = World.machines[gen_cell]
	var chest: Node2D = World.machines[chest_cell]
	# В сундуке вещь: полный сундук открывается по E (пустой — цель разбора).
	(chest as Chest).receive_item(IDs.I.STONE, 1)
	# Первый кадр после 200 построек бывает длиннее 0.3 с — ждём и кадры HUD,
	# а не только время, иначе проверка успевает раньше первого _process HUD.
	var fr0: int = hud.stat_frames
	await wait(0.3)
	await wait_until(func() -> bool: return hud.stat_frames >= fr0 + 3, 3.0)
	ok("вдали от построек подсказки ТЭЦ/сундука нет", hud.hint_text == _want(gen, chest),
			"«%s»" % hud.hint_text)

	# Туда: вправо до сундука.
	var stats: Dictionary = {"lag": 0, "max_lag": 0, "seen": {}, "mark_ok": 0, "mark_bad": 0}
	hold(KEY_D)
	var right_x: float = chest.global_position.x + DIST + 4.0
	await _walk(stats, gen, chest, func() -> bool: return player.global_position.x > right_x, 6.0)
	release_all()
	# Обратно: влево мимо сундука и ТЭЦ.
	hold(KEY_A)
	var left_x: float = gen.global_position.x - DIST - 4.0
	await _walk(stats, gen, chest, func() -> bool: return player.global_position.x < left_x, 6.0)
	release_all()
	await wait(0.1)

	var seen: Dictionary = stats["seen"]
	var hint_gen: String = hud.generator_hint(gen)
	ok("подсказка ТЭЦ появлялась у ТЭЦ", seen.has(hint_gen), "«%s»" % hint_gen)
	ok("подсказка сундука появлялась у сундука", seen.has(HINT_CHEST))
	ok("подсказка появляется и пропадает сразу", int(stats["max_lag"]) <= MAX_LAG_FRAMES,
			"наибольшее отставание %d кадр(а)" % int(stats["max_lag"]))
	# ADR-003 V6: рамка интерактива — вокруг ТЭЦ/сундука, пока горит их подсказка,
	# и нет рамки, когда подсказки нет.
	ok("рамка интерактива — вокруг ТЭЦ/сундука и только при подсказке",
			int(stats["mark_ok"]) > 0 and int(stats["mark_bad"]) == 0,
			"верно %d кадров, неверно %d" % [int(stats["mark_ok"]), int(stats["mark_bad"])])
	ok("отошёл — подсказки ТЭЦ/сундука нет", hud.hint_text == _want(gen, chest)
			and hud.hint_text != hint_gen and hud.hint_text != HINT_CHEST, "«%s»" % hud.hint_text)
	finish()


## Идти, пока не выполнится условие, сверяя подсказку каждый кадр.
func _walk(stats: Dictionary, gen: Node2D, chest: Node2D, done_cond: Callable, timeout: float) -> void:
	var hud: HUD = UI.hud
	var t0: float = now()
	while now() - t0 < timeout and not done_cond.call():
		await get_tree().process_frame
		var want: String = _want(gen, chest)
		if hud.hint_text == want:
			stats["lag"] = 0
			if want != "":
				stats["seen"][want] = true
			_check_mark(stats, want, gen, chest)
		else:
			stats["lag"] = int(stats["lag"]) + 1
			stats["max_lag"] = maxi(int(stats["max_lag"]), int(stats["lag"]))


## Рамка интерактива (V6): при подсказке ТЭЦ/сундука — вокруг этой постройки на
## экране (допуск 8 px: камера и HUD обновляются в разном порядке внутри кадра),
## без подсказки — рамки нет. Подсказку терминала не проверяем (рамка — от питания).
func _check_mark(stats: Dictionary, want: String, gen: Node2D, chest: Node2D) -> void:
	var hud: HUD = UI.hud
	var tgt: Node2D = null
	if want == hud.generator_hint(gen):
		tgt = gen
	elif want == HINT_CHEST:
		tgt = chest
	if tgt != null:
		var sp: Vector2 = hud.get_viewport().get_canvas_transform() * tgt.global_position
		var good: bool = Rect2(hud.mark_rect).grow(8.0).has_point(sp)
		stats["mark_ok" if good else "mark_bad"] = int(stats["mark_ok" if good else "mark_bad"]) + 1
	elif want == "" and hud.mark_rect.size != Vector2i.ZERO:
		stats["mark_bad"] = int(stats["mark_bad"]) + 1


## Какая подсказка должна быть сейчас — по расстояниям, по правилу цели E
## (#116): ближайший к герою объект в своём радиусе (терминал 42, релей 56,
## ТЭЦ и сундук 40); терминал без питания — только если строго ближе всего
## остального. Курсор сценарий не наводит. Коридор базы может задевать терминал —
## тогда ждём подсказку терминала (с учётом питания, #34).
func _want(gen: Node2D, chest: Node2D) -> String:
	var p: Vector2 = player.global_position
	var best: String = ""
	var best_d: float = INF
	var off: String = ""
	var off_d: float = INF
	for t in World.terminals:
		var td: float = World.cell_to_world(t).distance_to(p)
		if td >= 42.0:
			continue
		var th: String = UI.hud.terminal_hint(t)
		if th == HUD.HINT_TERMINAL_NO_POWER:
			if td < off_d:
				off_d = td
				off = th
		elif td < best_d:
			best_d = td
			best = th
	var bd: float = World.cell_to_world(World.beacon_cell).distance_to(p)
	if bd < 56.0 and bd < best_d:
		best_d = bd
		best = HUD.HINT_BEACON
	var gd: float = gen.global_position.distance_to(p)
	if gd < DIST and gd < best_d:
		best_d = gd
		best = UI.hud.generator_hint(gen)
	var cd: float = chest.global_position.distance_to(p)
	if cd < DIST and cd < best_d:
		best_d = cd
		best = HINT_CHEST
	return off if off_d < best_d else best
