extends ScenarioBase
## Переход «глава 1 → глава 2» по N на экране итога главы (#225).
##
## Клавиша гасится ДО сигнала: сигнал next_requested перезагружает сцену, а
## сцена уходит из дерева внутри сигнала — get_viewport() становится null, и
## падение на set_input_as_handled() уронило кадр на переходе.


func run() -> void:
	# Мир главы — тот же сид, что и в настоящей главе 1.
	scene.set("seed_value", Campaign.SEED)
	runner.reset_world()
	var m: Mission = Campaign.start(scene, "dig")
	if m == null:
		ok("глава «Копай» создана", false)
		finish()
		return
	ok("глава «Копай» создана", Game.mission == m)
	Game.set_state(Game.State.WON)
	await wait(0.2)
	var es: Node = scene.get("end_screen")
	ok("экран итога главы открыт", es != null and es.visible and es.can_next,
			"can_next=%s" % (str(es.can_next) if es != null else "нет экрана"))
	if es == null or not es.can_next:
		finish()
		return
	# Раннер — под /root: перезагрузка сцены его переживёт (carry_over).
	runner.carry_over()
	var vp: Viewport = es.get_viewport()
	var ev := InputEventKey.new()
	ev.keycode = KEY_N
	ev.pressed = true
	es._input(ev)
	ok("клавиша N погашена (вьюпорт пережил перезагрузку сцены)",
			vp != null and vp.is_input_handled())
	# Сцена перезагрузилась — новая глава.
	await wait(0.5)
	var m2 = Game.mission
	ok("после перехода глава «Огонь»", m2 != null and is_instance_valid(m2)
			and String(m2.id) == "fire",
			"id=%s" % (String(m2.id) if m2 != null else "нет главы"))
	finish()
