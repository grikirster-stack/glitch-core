extends ScenarioBase
## Переход «глава 1 → глава 2» по N на экране итога главы (#225).
##
## Клавиша гасится ДО сигнала: сигнал next_requested перезагружает сцену, а
## сцена уходит из дерева внутри сигнала — get_viewport() становится null, и
## падение на set_input_as_handled() уронило кадр на переходе (end_screen.gd:120).
##
## Две проверки:
## 1) порядок — клавиша погашена до сигнала (сигнал уводит узел из дерева);
## 2) переход — настоящая перезагрузка сцены, дальше глава «Огонь».


## Что видел обработчик сигнала: гасили клавишу до сигнала или нет.
var _seen: Array = []
## Обработчик первой проверки (отключаем, чтобы не мешал второй).
var _probe: Callable = Callable()


func run() -> void:
	_ordering()
	await _transition()
	finish()


## Порядок: клавиша гасится до сигнала. Сигнал уводит узел экрана из дерева —
## ровно то, что делает перезагрузка сцены.
func _ordering() -> void:
	var es: Node = scene.get("end_screen")
	if es == null:
		ok("экран итога есть", false)
		return
	es.show_mission("ГЛАВА 1 ПРОЙДЕНА", "проверка порядка", "текст", Color.WHITE, [], true)
	var vp: Viewport = es.get_viewport()
	var parent: Node = es.get_parent()
	_seen.clear()
	_probe = func() -> void:
		if parent != null and es.get_parent() != null:
			parent.remove_child(es)
		_seen.append(vp.is_input_handled())
	es.next_requested.connect(_probe, CONNECT_ONE_SHOT)
	es._input(_key(KEY_N))
	ok("клавиша погашена до сигнала (узел ушёл из дерева — падения нет)",
			_seen.size() == 1 and bool(_seen[0]))
	if es.next_requested.is_connected(_probe):
		es.next_requested.disconnect(_probe)
	# Экран назад в дерево: следующей проверке он нужен.
	if es.get_parent() == null and parent != null:
		parent.add_child(es)
	es.hide_end()


## Настоящий переход: глава 1 → глава 2 (N на экране итога).
func _transition() -> void:
	var seed0: int = int(scene.get("seed_value"))
	var session0: Dictionary = Net.session.duplicate(true)
	var old_id: int = scene.get_instance_id()
	var m: Mission = Campaign.start(scene, "dig")
	if m == null:
		ok("глава «Копай» создана", false)
		return
	ok("глава «Копай» создана", Game.mission == m)
	Game.set_state(Game.State.WON)
	await wait(0.2)
	var es: Node = scene.get("end_screen")
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
			and int(runner.scene.get("seed_value")) == seed0,
			"сид=%d" % (int(runner.scene.get("seed_value")) if runner.scene != null else -1))


## Нажатая клавиша.
func _key(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	return ev
