extends "res://tools/scenarios/campaign_common.gd"
## #311 (ADR-006 § 1, § 5, § 8): «Огонь» и «Цвета» обычным вводом.
## ПК идёт через шов игрока (test_input → Player._do_place / _do_interact).
## Телефон — через TouchControls (parse_input_event → touch_input → те же
## обработчики). Прямых burner.turn(), machine.interact() и pharos.interact() нет:
## на базе 2cfa4ae команда не названа и E у маяка не гасит прожектор.


func run() -> void:
	await _fire_pc()
	await _fire_touch()
	await _colors_pc()
	await _colors_touch()
	await _colors_lens()
	finish()


func _fire_pc() -> void:
	if not _started("fire"):
		return
	var t0: float = now()
	var mark: Vector2i = mission.call("mark")
	var said: String = await _wait_hint("ПКМ — поставь на метку")
	ok("ПК «Огонь»: команда постановки видна до клика",
			said.find("ПКМ — поставь на метку") >= 0,
			"«%s»" % said)
	stand_at_cell(mark + Vector2i(2, 1))
	player.inv.selected = _slot(IDs.I.BURNER)
	aim(World.cell_to_world(mark))
	await wait(0.3)
	press_mouse(MOUSE_BUTTON_RIGHT)
	await wait(0.35)
	release_mouse(MOUSE_BUTTON_RIGHT)
	var burner: Burner = World.machines.get(mark) as Burner
	ok("ПК «Огонь»: горелка встала на метке", burner != null, str(mark))
	if burner == null:
		return
	var dir0: int = burner.dir
	var taps: int = 0
	while burner.dir != 3 and taps < 8:
		aim(burner.global_position)
		press_mouse(MOUSE_BUTTON_RIGHT)
		await wait(0.2)
		release_mouse(MOUSE_BUTTON_RIGHT)
		await wait(0.2)
		taps += 1
	print("  [замер] ПК «Огонь»: носик %d → %d за %d ПКМ" % [dir0, burner.dir, taps])
	var aim_said: String = await _wait_hint("ПКМ — носик вверх")
	ok("ПК «Огонь»: носик вверх через ПКМ игрока, команда названа",
			burner.dir == 3 and (aim_said.find("ПКМ") >= 0 or aim_said.find("вверх") >= 0),
			"dir %d, «%s»" % [burner.dir, aim_said])
	player.inv.selected = _slot(IDs.I.COAL)
	aim(burner.global_position)
	var fuel_said: String = await _wait_hint("Носик вверх. [E] — уголь")
	ok("ПК «Огонь»: команда угля — [E], не прямой вызов",
			fuel_said.find("[E]") >= 0 or fuel_said.find("E") >= 0, "«%s»" % fuel_said)
	aim(burner.global_position)
	hold(KEY_E)
	await wait(0.4)
	release(KEY_E)
	var lit: bool = await wait_until(func() -> bool:
		return burner.burning() and burner.color == Beams.R, 2.0)
	_rebuild_beams()
	var span: int = _span(mark)
	var above: int = World.beams.color_at(mark + Vector2i(0, -1)) if World.beams != null else -1
	var tile_above: int = World.get_tile_v(mark + Vector2i(0, -1))
	var occ: String = str(World.machines.get(mark + Vector2i(0, -1)))
	print("  [замер] луч: dir %d цвет %d горит %s выше %d плитка %d машина %s сегментов %d" % [
			burner.dir, burner.color, str(burner.burning()), above, tile_above, occ,
			World.beams.segments.size() if World.beams != null else -1])
	ok("ПК «Огонь»: уголь через E дал красный луч на метке", lit and span >= 4,
			"клеток %d, горит %s" % [span, str(burner.burning())])
	ok("ПК «Огонь»: этап «Уголь» закрылся при видимом луче",
			await wait_stage(2, 2.0), "этап %d" % mission.stage)
	await _finish_fire("fire", t0)


func _fire_touch() -> void:
	if not _started("fire"):
		return
	var tc: TouchControls = _touch_on()
	if tc == null:
		ok("сенсорный слой есть", false)
		return
	var t0: float = now()
	var mark: Vector2i = mission.call("mark")
	stand_at_cell(mark + Vector2i(2, 1))
	_settle_camera()
	await wait(0.3)
	_tap(3, UI.hud.hotbar_slot_rect(_slot(IDs.I.BURNER)).get_center())
	await wait(0.15)
	ok("тач «Огонь»: горелка в хотбаре включает стройку", tc.build_mode, "слот %d" % player.inv.selected)
	var said: String = await _wait_hint("Тапни клетку — поставить")
	ok("тач «Огонь»: команда постановки — тап, не ПКМ",
			said.find("Тапни клетку — поставить") >= 0 and said.find("ПКМ") < 0,
			"«%s»" % said)
	_touch(1, _screen(World.cell_to_world(mark)), true)
	await wait(0.25)
	_touch(1, _screen(World.cell_to_world(mark)), false)
	var placed: bool = await wait_until(func() -> bool:
		return World.machines.get(mark) is Burner, 1.5)
	var burner: Burner = World.machines.get(mark) as Burner
	ok("тач «Огонь»: отпускание пальца ставит горелку", placed and burner != null)
	if burner == null:
		_touch_off(tc)
		return
	var dir0: int = burner.dir
	var taps: int = 0
	var aim_said: String = ""
	while burner.dir != 3 and taps < 8:
		var seen: String = _hint_or_card()
		if seen.find("Тап — носик вверх") >= 0:
			aim_said = seen
		_touch(1, _screen(burner.global_position), true)
		await wait(0.2)
		_touch(1, _screen(burner.global_position), false)
		await wait(0.35)
		taps += 1
	if aim_said == "":
		aim_said = await _wait_hint("Тап — носик вверх")
	print("  [замер] тач «Огонь»: носик %d → %d за %d тап(ов)" % [dir0, burner.dir, taps])
	ok("тач «Огонь»: носик вверх через тап игрока, команда — тап",
			burner.dir == 3 and _cmd_ok(aim_said, "Тап — носик вверх"),
			"dir %d, «%s»" % [burner.dir, aim_said])
	player.inv.selected = _slot(IDs.I.COAL)
	_tap(3, UI.hud.hotbar_slot_rect(player.inv.selected).get_center())
	await wait(0.15)
	var fuel_said: String = await _wait_hint("Тап — топка")
	ok("тач «Огонь»: команда топки — тап, не [E]",
			_cmd_ok(fuel_said, "Тап — топка"), "«%s»" % fuel_said)
	_touch(1, _screen(burner.global_position), true)
	_touch(2, tc.btn_center["e"], true)
	await wait(0.45)
	_touch(2, tc.btn_center["e"], false)
	_touch(1, _screen(burner.global_position), false)
	var lit: bool = await wait_until(func() -> bool:
		return burner.burning() and burner.color == Beams.R, 2.0)
	_rebuild_beams()
	ok("тач «Огонь»: [E] сенсорного слоя кладёт уголь, луч красный",
			lit and _span(mark) >= 4, "клеток %d" % _span(mark))
	ok("тач «Огонь»: этап закрылся при видимом луче", await wait_stage(2, 2.0),
			"этап %d" % mission.stage)
	_touch_off(tc)
	await _finish_fire("fire", t0)


func _colors_pc() -> void:
	if not _started("colors"):
		return
	var t0: float = now()
	var green_c: Vector2i = LightLayout.at(LightLayout.BURNER_G)
	var green: Burner = World.machines.get(green_c) as Burner
	ok("ПК «Цвета»: вторая горелка пустая", green != null and not green.burning())
	if green == null:
		return
	stand_at_cell(_stand_near(green_c))
	player.inv.selected = _slot(IDs.I.COPPER_ORE)
	aim(green.global_position)
	hold(KEY_E)
	await wait(0.4)
	release(KEY_E)
	var got: bool = await wait_until(func() -> bool:
		return green.burning() and green.color == Beams.G, 2.0)
	ok("ПК «Цвета»: медь через E дала зелёный", got, "цвет %d" % green.color)
	ok("ПК «Цвета»: этап смеси", await wait_stage(1, 2.0), str(mission.stage))
	var bend_c: Vector2i = LightLayout.at(LightLayout.MIRROR4)
	var bend: Mirror = World.machines.get(bend_c) as Mirror
	stand_at_cell(_stand_near(bend_c))
	player.inv.selected = 0
	var taps: int = 0
	if bend != null:
		for i in 8:
			aim(bend.global_position)
			press_mouse(MOUSE_BUTTON_RIGHT)
			await wait(0.2)
			release_mouse(MOUSE_BUTTON_RIGHT)
			await wait(0.25)
			taps += 1
			if World.beams != null and World.beams.color_at(LightLayout.at(LightLayout.MIX_OUT)) == Beams.Y:
				break
	print("  [замер] ПК «Цвета»: смесь за %d ПКМ по зеркалу" % taps)
	ok("ПК «Цвета»: зеркало свело лучи через ПКМ",
			World.beams != null and World.beams.color_at(LightLayout.at(LightLayout.MIX_OUT)) == Beams.Y,
			"тапов %d" % taps)
	ok("ПК «Цвета»: этап маяка", await wait_stage(2, 3.0), str(mission.stage))
	var pharos: Pharos = World.machines.get(LightLayout.at(LightLayout.PHAROS)) as Pharos
	var yellow: bool = await wait_until(func() -> bool:
		return pharos != null and pharos.color == Beams.Y and pharos.active, 3.0)
	ok("ПК «Цвета»: маяк жёлтый и луч жив", yellow and pharos != null and pharos._lit,
			"цвет %d" % (pharos.color if pharos != null else -1))
	await _stand_at_pharos()
	player.inv.selected = 0
	var lamp_said: String = await _wait_hint("[E] у маяка гасит прожектор")
	ok("ПК «Цвета»: команда прожектора названа и это [E]",
			lamp_said.find("[E]") >= 0 or lamp_said.find("прожектор") >= 0 or lamp_said.find("Погаси") >= 0,
			"«%s»" % lamp_said)
	var kind: String = String(player.interact_target().get("kind", ""))
	ok("ПК «Цвета»: E у маяка — рубильник, не разбор",
			kind == player.ET_PHAROS, "цель «%s»" % kind)
	hold(KEY_E)
	await wait(0.35)
	release(KEY_E)
	var doused: bool = await wait_until(func() -> bool:
		return pharos.lamp_off and not pharos._lit and pharos.color == Beams.Y, 1.5)
	ok("ПК «Цвета»: E погасил прожектор, луч остался", doused,
			"погашен %s, цвет %d" % [str(pharos.lamp_off), pharos.color])
	ok("ПК «Цвета»: глава перешла к ночи", await wait_stage(3, 2.0), str(mission.stage))
	var spot: Vector2i = mission.call("_echo_spot")
	stand_at_cell(_dark_stand(spot))
	player.invuln = 0.0
	player.hp = Player.MAX_HP
	var spawned: bool = await wait_until(func() -> bool: return _first_echo() != null, 8.0)
	ok("ПК «Цвета»: эхо вышло при погашенном прожекторе", spawned)
	var hurt: bool = await wait_until(func() -> bool: return player.hp < Player.MAX_HP - 0.5, 16.0)
	ok("ПК «Цвета»: эхо бьёт, пока прожектор погашен", hurt, "hp %.0f" % player.hp)
	player.hp = Player.MAX_HP
	player.invuln = 1.0e9
	await _stand_at_pharos()
	hold(KEY_E)
	await wait(0.35)
	release(KEY_E)
	var back: bool = await wait_until(func() -> bool:
		return not pharos.lamp_off and pharos._lit, 1.5)
	ok("ПК «Цвета»: E зажёг прожектор при угрозе", back and bool(mission.get("lamp_lit")),
			"горит %s" % str(not pharos.lamp_off))
	Engine.time_scale = 8.0
	var done: bool = await wait_until(func() -> bool:
		return mission.result != Mission.Result.RUNNING, 40.0)
	Engine.time_scale = 1.0
	ok("ПК «Цвета»: ночь закрылась после включения света",
			done and mission.result == Mission.Result.WON, "итог %d" % mission.result)
	await _won("colors", now() - t0)


func _colors_touch() -> void:
	if not _started("colors"):
		return
	var tc: TouchControls = _touch_on()
	if tc == null:
		ok("сенсорный слой есть", false)
		return
	var green_c: Vector2i = LightLayout.at(LightLayout.BURNER_G)
	stand_at_cell(_stand_near(green_c))
	_settle_camera()
	await wait(0.3)
	_tap(3, UI.hud.hotbar_slot_rect(_slot(IDs.I.COPPER_ORE)).get_center())
	await wait(0.15)
	var green: Burner = World.machines.get(green_c) as Burner
	_touch(1, _screen(green.global_position), true)
	_touch(2, tc.btn_center["e"], true)
	await wait(0.45)
	_touch(2, tc.btn_center["e"], false)
	_touch(1, _screen(green.global_position), false)
	var got: bool = await wait_until(func() -> bool:
		return green != null and green.burning() and green.color == Beams.G, 2.0)
	ok("тач «Цвета»: [E] сенсорного слоя кладёт медь", got)
	var bend_c: Vector2i = LightLayout.at(LightLayout.MIRROR4)
	stand_at_cell(_stand_near(bend_c))
	_settle_camera()
	await wait(0.2)
	# Пустая рука не включает стройку. Кнопка «строить» — иначе тап копает.
	player.inv.selected = _empty_slot()
	_tap(3, UI.hud.hotbar_slot_rect(player.inv.selected).get_center())
	await wait(0.15)
	if not tc.build_mode:
		_tap(2, tc.btn_center["build"])
		await wait(0.15)
	var bend: Mirror = World.machines.get(bend_c) as Mirror
	var taps: int = 0
	if bend != null:
		for i in 8:
			_touch(1, _screen(bend.global_position), true)
			await wait(0.2)
			_touch(1, _screen(bend.global_position), false)
			await wait(0.35)
			taps += 1
			if World.beams != null and World.beams.color_at(LightLayout.at(LightLayout.MIX_OUT)) == Beams.Y:
				break
	print("  [замер] тач «Цвета»: смесь за %d тап(ов) по зеркалу" % taps)
	ok("тач «Цвета»: тап по зеркалу свёл лучи",
			World.beams != null and World.beams.color_at(LightLayout.at(LightLayout.MIX_OUT)) == Beams.Y,
			"тапов %d" % taps)
	var pharos_c: Vector2i = LightLayout.at(LightLayout.PHAROS)
	await _stand_at_pharos()
	_settle_camera()
	var pharos: Pharos = World.machines.get(pharos_c) as Pharos
	await wait_until(func() -> bool:
		return pharos != null and pharos.color == Beams.Y and pharos.active, 3.0)
	var said: String = await _wait_hint("Тап по маяку гасит прожектор")
	ok("тач «Цвета»: команда прожектора — тап, не [E]",
			_cmd_ok(said, "Тап по маяку гасит прожектор"), "«%s»" % said)
	_touch(2, tc.btn_center["e"], true)
	await wait(0.4)
	_touch(2, tc.btn_center["e"], false)
	var doused: bool = await wait_until(func() -> bool:
		return pharos != null and pharos.lamp_off and not pharos._lit, 1.5)
	ok("тач «Цвета»: [E] сенсорного слоя гасит прожектор при живом луче",
			doused and pharos.color == Beams.Y, "погашен %s" % str(pharos.lamp_off if pharos != null else false))
	ok("тач «Цвета»: глава перешла к ночи", await wait_stage(3, 2.0), str(mission.stage))
	var night_said: String = await _wait_hint("Зажги прожектор — тап по маяку")
	ok("тач «Цвета»: ночная команда — тап, не [E]",
			_cmd_ok(night_said, "Зажги прожектор — тап по маяку"), "«%s»" % night_said)
	var heard: bool = false
	for n in UI.hud.notes:
		if String(n.get("text", "")).find("тап по маяку") >= 0 \
				and String(n.get("text", "")).find("[E]") < 0:
			heard = true
	ok("тач «Цвета»: ночная реплика назвала тап", heard)
	_touch_off(tc)


func _colors_lens() -> void:
	if not _started("colors"):
		return
	var green: Burner = World.machines.get(LightLayout.at(LightLayout.BURNER_G)) as Burner
	stand_at_cell(_stand_near(LightLayout.at(LightLayout.BURNER_G)))
	player.inv.selected = _slot(IDs.I.COPPER_ORE)
	aim(green.global_position)
	hold(KEY_E)
	await wait(0.35)
	release(KEY_E)
	await wait_until(func() -> bool: return green != null and green.color == Beams.G, 2.0)
	var bend: Mirror = World.machines.get(LightLayout.at(LightLayout.MIRROR4)) as Mirror
	stand_at_cell(_stand_near(LightLayout.at(LightLayout.MIRROR4)))
	if bend != null:
		for i in 8:
			aim(bend.global_position)
			press_mouse(MOUSE_BUTTON_RIGHT)
			await wait(0.2)
			release_mouse(MOUSE_BUTTON_RIGHT)
			await wait(0.2)
			if World.beams != null and World.beams.color_at(LightLayout.at(LightLayout.MIX_OUT)) == Beams.Y:
				break
	var pharos: Pharos = World.machines.get(LightLayout.at(LightLayout.PHAROS)) as Pharos
	await wait_until(func() -> bool:
		return pharos != null and pharos.color == Beams.Y and pharos.active, 3.0)
	player.inv.add(IDs.I.LENS, 1)
	player.inv.selected = _slot(IDs.I.LENS)
	await _stand_at_pharos()
	var kind: String = String(player.interact_target().get("kind", ""))
	ok("линза в руке у маяка — отдельное действие, не рубильник",
			kind == player.ET_LENS, "цель «%s»" % kind)
	var off0: bool = pharos.lamp_off
	hold(KEY_E)
	await wait(0.35)
	release(KEY_E)
	await wait(0.3)
	ok("E с линзой вставил её и не переключил прожектор",
			pharos.lens and player.inv.count_of(IDs.I.LENS) == 0 and pharos.lamp_off == off0
			and pharos.color == Beams.Y,
			"линза %s, погашен %s → %s" % [str(pharos.lens), str(off0), str(pharos.lamp_off)])
	player.inv.selected = _empty_slot()
	await _stand_at_pharos()
	var kind2: String = String(player.interact_target().get("kind", ""))
	ok("пустая рука после линзы снова целится в рубильник", kind2 == player.ET_PHAROS,
			"цель «%s»" % kind2)
	hold(KEY_E)
	await wait(0.35)
	release(KEY_E)
	var toggled: bool = await wait_until(func() -> bool: return pharos.lamp_off != off0, 1.5)
	ok("после линзы E переключает прожектор, линза на месте",
			toggled and pharos.lens and pharos.color == Beams.Y,
			"погашен %s" % str(pharos.lamp_off))


# ------------------------------------------------------------------ ОБЩЕЕ

func _started(id: String) -> bool:
	var m: Mission = start_chapter(id)
	ok("глава «%s» создана" % id, m != null and Game.mission == m)
	return m != null


func _won(id: String, secs: float) -> void:
	await wait_until(func() -> bool: return mission.result != Mission.Result.RUNNING, 8.0)
	ok("%s: победа за %.0f с (лимит 120)" % [id, secs],
			mission.result == Mission.Result.WON and secs <= 120.0,
			"итог %d, %.1f с" % [mission.result, secs])


## Сумерки 6 с и подход эха до 25 с. На x8 глава укладывается в лимит сценария.
func _finish_fire(id: String, t0: float) -> void:
	Engine.time_scale = 8.0
	var done: bool = await wait_until(func() -> bool:
		return mission.result != Mission.Result.RUNNING, 40.0)
	Engine.time_scale = 1.0
	var secs: float = now() - t0
	ok("%s: победа за %.0f с (лимит 120)" % [id, secs],
			done and mission.result == Mission.Result.WON and secs <= 120.0,
			"итог %d, %.1f с" % [mission.result, secs])


func _rebuild_beams() -> void:
	if World.beams == null:
		return
	World.beams.mark_dirty()
	World.beams.rebuild()


## Плашка копирует Mission.hint не чаще чем раз в STATE_RECHECK_SEC.
## Ждём конкретную команду этой главы. Любой «[E]» или «метк» не годится:
## в шарде 3/3 предыдущий сценарий оставляет «[E] — открыть сундук» и хвост
## обучения «на горелку», и общий фильтр возвращался на чужой строке.
## Если нужная строка уже висит — это она, ждать смены не нужно.
## Если висит чужая — ждём, пока плашка сменится на нужную, а не на ту же чужую.
## Команда главы — часть после « | ». Контекстная плашка слева может звать
## другую кнопку; невыполнимая команда — это [E] или ПКМ в самой команде главы.
func _cmd_ok(said: String, need: String) -> bool:
	var cmd: String = said
	var bar: int = said.find(" | ")
	if bar >= 0:
		cmd = said.substr(bar + 3)
	return cmd.find(need) >= 0 and cmd.find("[E]") < 0 and cmd.find("ПКМ") < 0


func _wait_hint(need: String) -> String:
	var before: String = _hint_or_card()
	if before.find(need) >= 0:
		return before
	await wait_until(func() -> bool:
		var s: String = _hint_or_card()
		return s.find(need) >= 0 and s != before, 2.0)
	return _hint_or_card()


func _slot(id: int) -> int:
	for i in player.inv.slots.size():
		if player.inv.slots[i].id == id and player.inv.slots[i].count > 0:
			return i
	return 0


func _empty_slot() -> int:
	for i in player.inv.hotbar_size:
		if player.inv.slots[i].is_empty():
			return i
	return 0


func _span(mark: Vector2i) -> int:
	var n: int = 0
	if World.beams == null:
		return 0
	for k in range(1, 13):
		if World.beams.color_at(mark + Vector2i(0, -k)) == Beams.R:
			n += 1
	return n


func _hint_or_card() -> String:
	var hud = UI.hud
	if hud == null:
		return ""
	var h: String = String(hud.hint_text)
	var tut: String = String(hud.tutorial_text)
	if h == "":
		return tut
	if tut == "":
		return h
	return h + " | " + tut


## Под маяком: ~20 px до башни, терминалы далеко. Курсор должен успеть
## попасть в building_cell — иначе ближайший терминал забирает E.
func _stand_at_pharos() -> void:
	var c: Vector2i = LightLayout.at(LightLayout.PHAROS)
	stand_at_cell(c + Vector2i(0, 1))
	aim(World.cell_to_world(c))
	await wait(0.35)


func _stand_near(c: Vector2i) -> Vector2i:
	for o in [Vector2i(2, 1), Vector2i(-2, 1), Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(1, 2)]:
		var s: Vector2i = c + o
		if not World.in_bounds(s.x, s.y):
			continue
		if World.machines.has(s):
			continue
		if World.is_solid_cell(s):
			continue
		var feet: Vector2i = s + Vector2i(0, 1)
		if World.is_solid_cell(feet) or World.machines.has(feet):
			return s
	return c + Vector2i(2, 1)


func _dark_stand(spot: Vector2i) -> Vector2i:
	var flee: float = float(Balance.PHANTOMS["echo"]["light_flee"])
	var best: Vector2i = spot + Vector2i(2, 0)
	var bd: int = 1 << 30
	for y in range(spot.y - 2, spot.y + 3):
		for x in range(spot.x + 1, spot.x + 6):
			var c: Vector2i = Vector2i(x, y)
			if World.machines.has(c) or World.is_solid_cell(c):
				continue
			if World.light_at(c) > flee:
				continue
			var d: int = absi(c.x - spot.x) + absi(c.y - spot.y)
			if d < bd and d > 0:
				bd = d
				best = c
	return best


func _first_echo() -> Node:
	for n in get_tree().get_nodes_in_group("phantom"):
		if is_instance_valid(n) and n is Phantom and (n as Phantom).alive:
			return n
	return null


func _touch_on() -> TouchControls:
	var tc: TouchControls = get_tree().get_first_node_in_group("touch_controls")
	if tc == null:
		return null
	clear_input()
	tc.set_enabled(true)
	return tc


func _touch_off(tc: TouchControls) -> void:
	_lift_all()
	tc.set_enabled(false)
	clear_input()


func _screen(world: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world


func _win(pos: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * pos


var _down: Dictionary = {}


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e: InputEventScreenTouch = InputEventScreenTouch.new()
	e.index = index
	e.position = _win(pos)
	e.pressed = pressed
	Input.parse_input_event(e)
	if pressed:
		_down[index] = pos
	else:
		_down.erase(index)


func _tap(index: int, pos: Vector2) -> void:
	_touch(index, pos, true)
	_touch(index, pos, false)


func _lift_all() -> void:
	for i in _down.keys():
		_touch(int(i), Vector2(_down[i]), false)


func _settle_camera() -> void:
	player.camera.reset_smoothing()
	player.camera.position_smoothing_enabled = false
	player.camera.global_position = player.global_position
	player.camera.position_smoothing_enabled = true
