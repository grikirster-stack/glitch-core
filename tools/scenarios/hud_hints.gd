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
	# Первый кадр после 200 построек бывает длиннее 0.3 с — ждём и кадры HUD,
	# а не только время, иначе проверка успевает раньше первого _process HUD.
	var fr0: int = hud.stat_frames
	await wait(0.3)
	await wait_until(func() -> bool: return hud.stat_frames >= fr0 + 3, 3.0)
	ok("вдали от построек подсказки ТЭЦ/сундука нет", hud.hint_text == _want(gen, chest),
			"«%s»" % hud.hint_text)

	# Туда: вправо до сундука.
	var stats: Dictionary = {"lag": 0, "max_lag": 0, "seen": {}}
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
		else:
			stats["lag"] = int(stats["lag"]) + 1
			stats["max_lag"] = maxi(int(stats["max_lag"]), int(stats["lag"]))


## Какая подсказка должна быть сейчас — по расстояниям, в том же порядке
## важности, что у HUD: терминал, релей, ТЭЦ, сундук. Коридор базы может
## задевать терминал — тогда ждём подсказку терминала (с учётом питания, #34).
func _want(gen: Node2D, chest: Node2D) -> String:
	var p: Vector2 = player.global_position
	for t in World.terminals:
		if World.cell_to_world(t).distance_to(p) < 42.0:
			return UI.hud.terminal_hint(t)
	if World.cell_to_world(World.beacon_cell).distance_to(p) < 56.0:
		return HUD.HINT_BEACON
	if gen.global_position.distance_to(p) < DIST:
		return UI.hud.generator_hint(gen)
	if chest.global_position.distance_to(p) < DIST:
		return HINT_CHEST
	return ""
