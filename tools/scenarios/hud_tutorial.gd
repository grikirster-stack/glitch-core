extends ScenarioBase
## Обучение первых минут (#170): копай → крафт горелки → поставить → терминал.
## Питания нет: терминал читается всегда, шаг «питание» не наступает.


func run() -> void:
	var base: int = stand_in_corridor(14)    # герой на bx+15
	clear_input()
	var hud: HUD = UI.hud
	var bx: int = World.beacon_cell.x
	await _frames(hud, 3)
	# Стартовый набор уже несёт хлам: шаг «копай» считает его, не ноль.
	var scrap0: int = player.inv.count_of(IDs.I.SCRAP)
	ok("старт: шаг «копай»", hud.tutorial_step == HUD.Tut.DIG and hud.tutorial_text.contains("Копай")
			and hud.tutorial_text.contains("%d/%d" % [mini(scrap0, HUD.TUT_SCRAP), HUD.TUT_SCRAP]),
			"«%s»" % hud.tutorial_text)

	player.inv.add(IDs.I.SCRAP, HUD.TUT_SCRAP)
	await _step(hud, HUD.Tut.CRAFT)
	ok("хлам 6/6 → шаг «крафт»", hud.tutorial_step == HUD.Tut.CRAFT and hud.tutorial_text.contains("Крафт"),
			"«%s»" % hud.tutorial_text)
	player.inv.remove_id(IDs.I.SCRAP, HUD.TUT_SCRAP)
	player.inv.add(IDs.I.BURNER, 1)
	await _step(hud, HUD.Tut.PLACE)
	ok("горелка в инвентаре → шаг «поставить»", hud.tutorial_step == HUD.Tut.PLACE
			and hud.tutorial_text.contains("Горелка"), "«%s»" % hud.tutorial_text)
	player.inv.remove_id(IDs.I.BURNER, 1)
	await _frames(hud, 3)
	ok("горелка ушла из инвентаря — шаг назад не идёт", hud.tutorial_step == HUD.Tut.PLACE, str(hud.tutorial_step))

	var far_cell: Vector2i = Vector2i(bx + 17, base - 1)
	ok("горелка поставлена", MachineBase.place_machine("Burner", far_cell))
	var far = World.machines.get(far_cell)
	if far == null:
		finish()
		return
	await wait(0.4)
	ok("у горелки без топлива в руке — подсказка «рубильник»",
			hud.hint_text == HUD.HINT_BURNER_SWITCH + HUD.HINT_DISMANTLE_TAIL,
			"«%s»" % hud.hint_text)
	hold(KEY_2)
	await wait(0.4)
	release(KEY_2)
	ok("уголь в руке — подсказка «загрузить топливо»", hud.hint_text == HUD.HINT_BURNER_FUEL,
			"«%s»" % hud.hint_text)
	hold(KEY_E)
	await wait(0.3)
	release(KEY_E)
	ok("E с углём затопил горелку", float(far.burn_left) > 0.0, "пламя %.1f" % float(far.burn_left))
	await _step(hud, HUD.Tut.TERMINAL)
	ok("горелка рядом → шаг «терминал»", hud.tutorial_step == HUD.Tut.TERMINAL
			and hud.tutorial_text.contains("Терминал"), "«%s»" % hud.tutorial_text)

	stand_in_corridor(4)
	await wait(0.4)
	ok("у терминала без ТЭЦ — «выполнить задание»", hud.hint_text == HUD.HINT_TERMINAL,
			"«%s»" % hud.hint_text)
	var r0: int = hud.stat_redraws
	hold(KEY_E)
	await wait_until(func() -> bool: return Game.tasks_done > 0, 5.0)
	release(KEY_E)
	ok("задание выполнено", Game.tasks_done > 0)
	await _step(hud, HUD.Tut.DONE)
	ok("цепочка пройдена — строка обучения пуста", hud.tutorial_step == HUD.Tut.DONE
			and hud.tutorial_text == "", "«%s»" % hud.tutorial_text)
	ok("HUD перерисован после смены шага", hud.stat_redraws > r0)
	finish()


## Подождать n кадров HUD (а не секунд: первый кадр бывает длинным).
func _frames(hud: HUD, n: int) -> void:
	var f0: int = hud.stat_frames
	await wait_until(func() -> bool: return hud.stat_frames >= f0 + n, 5.0)


## Подождать, пока обучение не дойдёт до шага (пересчёт — раз в 0.25 с).
func _step(hud: HUD, step: int) -> void:
	await wait_until(func() -> bool: return hud.tutorial_step >= step, 2.0)
