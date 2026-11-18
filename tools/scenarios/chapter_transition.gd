extends ScenarioBase
## Переход «глава 1 → глава 2» по N на экране итога главы (#225).
##
## Клавиша гасится ДО сигнала: сигнал next_requested перезагружает сцену, а
## сцена уходит из дерева внутри сигнала — get_viewport() становится null, и
## падение на set_input_as_handled() уронило кадр на переходе (end_screen.gd:120).
##
## Четыре проверки (#225, дыра приёмки #229):
## 1) порядок N — клавиша погашена до сигнала;
## 2) порядок R — та же перезагрузка, тот же null, если гасить после сигнала;
## 3) переход N — настоящая перезагрузка, дальше глава «Огонь»;
## 4) R — новая попытка той же главы; тап «дальше» — как N.


## Что видел обработчик сигнала: гасили клавишу до сигнала или нет.
var _seen: Array = []
## Обработчик первой проверки (отключаем, чтобы не мешал второй).
var _probe: Callable = Callable()


func run() -> void:
	_ordering(KEY_N, "next_requested")
	_ordering(KEY_R, "restart_requested")
	await _tap_next()
	await _transition()
	finish()


## Порядок: клавиша гасится до сигнала. Сигнал уводит узел экрана из дерева —
## ровно то, что делает перезагрузка сцены. N и R идут одним путём (#225).
func _live() -> Node:
	return runner.scene if runner.scene != null else scene


func _ordering(code: int, signal_name: String) -> void:
	var es: Node = _live().get("end_screen")
	if es == null:
		ok("экран итога есть", false)
		return
	es.show_mission("ГЛАВА 1 ПРОЙДЕНА", "проверка порядка", "текст", Color.WHITE, [], true)
	var vp: Viewport = es.get_viewport()
	var parent: Node = es.get_parent()
	_seen.clear()
	# Настоящий обработчик R перезагружает сцену всегда, даже без главы.
	# На время проверки его снимаем: увод узла из дерева делает проба,
	# иначе прогон перезапускается и крутится вечно.
	var saved: Array = []
	for c in es.get_signal_connection_list(signal_name):
		saved.append(c["callable"])
		es.disconnect(signal_name, c["callable"])
	_probe = func() -> void:
		if parent != null and es.get_parent() != null:
			parent.remove_child(es)
		_seen.append(vp.is_input_handled())
	es.connect(signal_name, _probe, CONNECT_ONE_SHOT)
	es._input(_key(code))
	var key_name: String = "N" if code == KEY_N else "R"
	ok("клавиша %s погашена до сигнала (узел ушёл из дерева — падения нет)" % key_name,
			_seen.size() == 1 and bool(_seen[0]))
	if es.is_connected(signal_name, _probe):
		es.disconnect(signal_name, _probe)
	for cb in saved:
		if not es.is_connected(signal_name, cb):
			es.connect(signal_name, cb)
	if es.get_parent() == null and parent != null:
		parent.add_child(es)
	es.hide_end()


## Настоящий переход: глава 1 → глава 2 (N на экране итога).
func _transition() -> void:
	var seed0: int = int(_live().get("seed_value"))
	var session0: Dictionary = Net.session.duplicate(true)
	var old_id: int = _live().get_instance_id()
	var m: Mission = Campaign.start(_live(), "dig")
	if m == null:
		ok("глава «Копай» создана", false)
		return
	ok("глава «Копай» создана", Game.mission == m)
	Game.set_state(Game.State.WON)
	await wait(0.2)
	var es: Node = _live().get("end_screen")
	ok("экран итога главы открыт", es != null and es.visible and es.can_next,
			"can_next=%s" % (str(es.can_next) if es != null else "нет экрана"))
	if es == null or not es.can_next:
		return
	# Раннер — под /root: перезагрузка сцены его переживёт (carry_over).
	runner.carry_over()
	es._input(_key(KEY_N))
	# Новая сцена приняла раннера (adopt) — значит, глава перезагрузилась.
	await wait_until(func() -> bool:
		return runner.scene != null and runner.scene.get_instance_id() != old_id, 5.0)
	var m2 = Game.mission
	ok("после перехода глава «Огонь»", m2 != null and is_instance_valid(m2)
			and String(m2.id) == "fire",
			"id=%s" % (String(m2.id) if m2 != null else "нет главы"))
	# Уборка: чужие сценарии прогона идут дальше — мир и глава как до перехода.
	if m2 != null and is_instance_valid(m2):
		var p: Node = m2.get_parent()
		if p != null:
			p.remove_child(m2)
		m2.free()
	Game.mission = null
	if runner.scene != null:
		runner.scene.set("seed_value", seed0)
	Net.session = session0
	ok("сид прогона возвращён", runner.scene != null
			and int(_live().get("seed_value")) == seed0,
			"сид=%d" % (int(_live().get("seed_value")) if runner.scene != null else -1))


## Тап «дальше» — тот же сигнал, что N. В headless вьюпорт тап до контрола
## не доводит: событие идёт в _input, как клик инвентаря (#69).
func _tap_next() -> void:
	var seed0: int = int(_live().get("seed_value"))
	var session0: Dictionary = Net.session.duplicate(true)
	var old_id: int = _live().get_instance_id()
	var m: Mission = Campaign.start(_live(), "dig")
	if m == null:
		ok("глава «Копай» для тапа создана", false)
		return
	Game.set_state(Game.State.WON)
	await wait(0.2)
	var es: Node = _live().get("end_screen")
	if es == null or not es.can_next:
		ok("экран тапа открыт", false)
		return
	# Раньше 1.5 с тап не считается: случайный тап в момент смерти забег не рвёт.
	# Проверяем до перезагрузки: после неё эта сцена уже не жива.
	es.t = 0.5
	es._input(_touch(Vector2(es.size.x * 0.5, es.size.y * 0.5)))
	await runner.get_tree().process_frame
	ok("тап раньше 1.5 с главу не меняет", _live().get_instance_id() == old_id)
	es.t = 2.0
	runner.carry_over()
	es._input(_touch(Vector2(es.size.x * 0.5, es.size.y * 0.5)))
	await wait_until(func() -> bool:
		return runner.scene != null and runner.scene.get_instance_id() != old_id, 5.0)
	var m2 = Game.mission
	ok("тап «дальше» ведёт в главу «Огонь»",
			m2 != null and is_instance_valid(m2) and String(m2.id) == "fire",
			"id=%s" % (String(m2.id) if m2 != null else "нет главы"))
	_restore(m2, seed0, session0)


func _restore(m2, seed0: int, session0: Dictionary) -> void:
	if m2 != null and is_instance_valid(m2):
		var parent: Node = m2.get_parent()
		if parent != null:
			parent.remove_child(m2)
		m2.free()
	Game.mission = null
	if runner.scene != null:
		runner.scene.set("seed_value", seed0)
	Net.session = session0
	ok("сид прогона возвращён", runner.scene != null
			and int(_live().get("seed_value")) == seed0,
			"сид=%d" % (int(_live().get("seed_value")) if runner.scene != null else -1))


func _touch(pos: Vector2) -> InputEventScreenTouch:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = pos
	ev.pressed = true
	return ev


## Нажатая клавиша.
func _key(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	return ev
