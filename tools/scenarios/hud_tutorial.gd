extends ScenarioBase
## Обучение первых минут (#34): цепочка подсказок HUD копай → крафт → ТЭЦ →
## питание терминала → терминал и подсказки у машин. Проверяется по
## состоянию HUD (tutorial_step / tutorial_text / hint_text):
##  * шаг двигается вперёд от состояния игры (хлам, ТЭЦ в инвентаре, работающий
##    генератор, терминал под питанием, выполненное задание) и назад не идёт;
##  * у генератора: уголь в руке — «загрузить», иначе — «рубильник»; E с углём
##    действительно топит ТЭЦ;
##  * у терминала без питания — «нет питания», с питанием — «[E] — выполнить»;
##  * у манипулятора — ПКМ поворот / E фильтр;
##  * задание выполнено — цепочка пройдена, строка обучения пуста.


func run() -> void:
	var base: int = stand_in_corridor(14)    # герой на bx+15
	clear_input()
	var hud: HUD = UI.hud
	var bx: int = World.beacon_cell.x
	await _frames(hud, 3)
	ok("старт: шаг «копай»", hud.tutorial_step == HUD.Tut.DIG and hud.tutorial_text.contains("Копай")
			and hud.tutorial_text.contains("0/%d" % HUD.TUT_SCRAP), "«%s»" % hud.tutorial_text)

	# Хлам на ТЭЦ накопан → крафт.
	player.inv.add(IDs.I.SCRAP, HUD.TUT_SCRAP)
	await _step(hud, HUD.Tut.CRAFT)
	ok("хлам 6/6 → шаг «крафт»", hud.tutorial_step == HUD.Tut.CRAFT and hud.tutorial_text.contains("Крафт"),
			"«%s»" % hud.tutorial_text)
	# Скрафтили ТЭЦ → поставить.
	player.inv.remove_id(IDs.I.SCRAP, HUD.TUT_SCRAP)
	player.inv.remove_id(IDs.I.IRON_PLATE, 2)
	player.inv.add(IDs.I.COAL_GEN, 1)
	await _step(hud, HUD.Tut.PLACE)
	ok("ТЭЦ в инвентаре → шаг «ТЭЦ»", hud.tutorial_step == HUD.Tut.PLACE and hud.tutorial_text.contains("ТЭЦ"),
			"«%s»" % hud.tutorial_text)
	player.inv.remove_id(IDs.I.COAL_GEN, 1)
	await _frames(hud, 3)
	ok("ТЭЦ ушла из инвентаря — шаг назад не идёт", hud.tutorial_step == HUD.Tut.PLACE, str(hud.tutorial_step))

	# ТЭЦ далеко от терминалов (bx+17, терминал базы — bx+6, радиус 8).
	var far_cell: Vector2i = Vector2i(bx + 17, base - 1)
	ok("ТЭЦ поставлена вдали от терминала", MachineBase.place_machine("CoalGen", far_cell))
	var far = World.machines.get(far_cell)
	if far == null:
		finish()
		return
	await wait(0.4)
	ok("у ТЭЦ без угля в руке — подсказка «рубильник»",
			hud.hint_text == HUD.HINT_GEN_SWITCH + HUD.HINT_DISMANTLE_TAIL,
			"«%s»" % hud.hint_text)
	hold(KEY_2)                               # слот 2 — уголь из стартового набора
	await wait(0.4)
	release(KEY_2)
	ok("уголь в руке — подсказка «загрузить уголь»", hud.hint_text == HUD.HINT_GEN_COAL,
			"«%s»" % hud.hint_text)
	hold(KEY_E)
	await wait(0.3)
	release(KEY_E)
	ok("E с углём растопил ТЭЦ", float(far.fuel) > 0.0, "топливо %.1f" % float(far.fuel))
	await _step(hud, HUD.Tut.POWER)
	ok("генератор работает, терминал вне зоны → шаг «питание»", hud.tutorial_step == HUD.Tut.POWER
			and hud.tutorial_text.contains("Питание"), "«%s»" % hud.tutorial_text)

	# Терминал базы: без питания — «нет питания».
	stand_in_corridor(4)                      # герой на bx+5, терминал — bx+6
	await wait(0.4)
	ok("у терминала без питания — «нет питания»", hud.hint_text == HUD.HINT_TERMINAL_NO_POWER,
			"«%s»" % hud.hint_text)
	var near_cell: Vector2i = Vector2i(bx + 9, base - 1)
	ok("ТЭЦ поставлена у терминала", MachineBase.place_machine("CoalGen", near_cell))
	var near = World.machines.get(near_cell)
	if near == null:
		finish()
		return
	near.add_fuel(2)
	await _step(hud, HUD.Tut.TERMINAL)
	ok("терминал под питанием → шаг «терминал»", hud.tutorial_step == HUD.Tut.TERMINAL
			and hud.tutorial_text.contains("Терминал"), "«%s»" % hud.tutorial_text)
	await wait(0.3)
	ok("у терминала с питанием — «[E] — выполнить задание»", hud.hint_text == HUD.HINT_TERMINAL,
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

	# Манипулятор: ПКМ — поворот, E — фильтр.
	var ins_cell: Vector2i = Vector2i(bx + 13, base - 1)
	ok("манипулятор поставлен", MachineBase.place_machine("Inserter", ins_cell))
	stand_in_corridor(11)                     # герой на bx+12: манипулятор в 16 px
	await wait(0.4)
	ok("у манипулятора — ПКМ поворот / E фильтр",
			hud.hint_text == HUD.HINT_INSERTER + HUD.HINT_DISMANTLE_TAIL,
			"«%s»" % hud.hint_text)
	finish()


## Подождать n кадров HUD (а не секунд: первый кадр бывает длинным).
func _frames(hud: HUD, n: int) -> void:
	var f0: int = hud.stat_frames
	await wait_until(func() -> bool: return hud.stat_frames >= f0 + n, 5.0)


## Подождать, пока обучение не дойдёт до шага (пересчёт — раз в 0.25 с).
func _step(hud: HUD, step: int) -> void:
	await wait_until(func() -> bool: return hud.tutorial_step >= step, 2.0)
