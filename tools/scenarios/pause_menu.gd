extends ScenarioBase
## Пауза и «Сохранить и выйти в меню» (#119). Клавиши — настоящие события ввода
## (Input.parse_input_event), как в journal_open и save_load: их ловят UI и PauseMenu.
##
##  * ESC сначала закрывает инвентарь и журнал, и только без окон открывает паузу;
##  * пауза: пункты «Продолжить», «Сохранить», «Сохранить и выйти в меню», «Выход из игры»;
##    дерево стоит — Game.game_time не идёт; ESC и «Продолжить» закрывают, мир идёт;
##  * хардкор: «Сохранить» серая, выход — «Выйти в меню» через «Забег не сохранён»;
##  * «Сохранить» пишет слот F5 (Save.slot), панель остаётся;
##  * смена 3, метка в инвентаре, герой отошёл от капсулы → «Сохранить и выйти в меню» —
##    файл в слоте F5, главное меню (дерево на паузе, HUD скрыт), в меню «Продолжить» —
##    тап: мир снова, смена, инвентарь и позиция героя — как в момент сохранения.
##
## Сцена игры сменяется дважды: раннер переезжает через меню (ScenarioRunner.carry_over),
## новая сцена принимает его (main.gd → adopt). Пока дерево на паузе, ждём кадрами
## (часы раннера стоят вместе с миром).

const MARK_ID: int = IDs.I.SCRAP
const MARK_N: int = 11
const DAY: int = 3
## Кадров на смену сцены (меню, мир из сохранения) — с запасом под нагрузку.
const SCENE_FRAMES: int = 600


func run() -> void:
	player.invuln = 1.0e9
	Save.remove(Save.slot)
	var pm: PauseMenu = UI.pause
	ok("пауза создана и закрыта", pm != null and not pm.visible and not get_tree().paused)
	if pm == null:
		_cleanup()
		return

	# --- ESC: сначала окна, потом пауза.
	await _press(KEY_I)
	ok("I — инвентарь открыт", UI.panel.visible)
	await _press(KEY_ESCAPE)
	ok("ESC закрыл инвентарь, пауза не открылась", not UI.panel.visible and not pm.visible)
	await _press(KEY_J)
	await _press(KEY_ESCAPE)
	ok("ESC закрыл журнал, пауза не открылась", not UI.journal.visible and not pm.visible)
	await _press(KEY_ESCAPE)
	ok("ESC без окон — пауза; дерево стоит, ввод у мира забран", pm.visible and get_tree().paused
			and UI.blocking())
	var texts: Array = []
	for b in [pm.continue_button, pm.save_button, pm.exit_button, pm.quit_button]:
		texts.append((b as Button).text)
	ok("пункты паузы", texts == ["Продолжить", "Сохранить", "Сохранить и выйти в меню", "Выход из игры"]
			and not pm.save_button.disabled and not pm.quit_button.disabled, str(texts))
	var t0: float = Game.game_time
	var tod0: float = Game.time_of_day
	await _frames(20)
	ok("в паузе мир стоит: время забега не идёт", Game.game_time == t0 and Game.time_of_day == tod0,
			"%.3f → %.3f" % [t0, Game.game_time])
	await _press(KEY_I)
	ok("в паузе I не открывает инвентарь", not UI.panel.visible and pm.visible)
	await _press(KEY_ESCAPE)
	ok("ESC в паузе — «Продолжить»: панель закрыта, дерево идёт", not pm.visible and not get_tree().paused)
	await wait(0.2)
	ok("после паузы время снова идёт", Game.game_time > t0)
	pm.open()
	pm.continue_button.pressed.emit()
	ok("кнопка «Продолжить» закрывает паузу", not pm.visible and not get_tree().paused)

	# --- Хардкор: сохранить нельзя, выход — через предупреждение.
	scene.hardcore = true
	pm.open()
	ok("хардкор: «Сохранить» серая, выход — «Выйти в меню»", pm.save_button.disabled
			and pm.exit_button.text == PauseMenu.T_EXIT and pm.hint_label.text.contains("хардкор"),
			"%s | %s" % [pm.exit_button.text, pm.hint_label.text])
	pm.exit_button.pressed.emit()
	ok("хардкор: выход — предупреждение «забег не сохранён», сцена та же",
			pm.confirm_box.visible and pm.confirm_label.text.begins_with(PauseMenu.NOT_SAVED)
			and get_tree().current_scene == scene and not Save.exists(Save.slot), pm.confirm_label.text)
	await _press(KEY_ESCAPE)
	ok("ESC в предупреждении — назад к пунктам", pm.visible and not pm.confirm_box.visible)
	pm.close()
	scene.hardcore = false

	# --- «Сохранить»: слот F5, панель остаётся.
	pm.open()
	pm.save_button.pressed.emit()
	ok("«Сохранить» — файл в слоте F5, панель открыта", Save.exists(Save.slot) and pm.visible
			and pm.status_label.text.contains("сохранён"), "%s %s" % [Save.path_for(Save.slot), pm.status_label.text])
	pm.close()
	Save.remove(Save.slot)

	# --- Забег, который сохраним: смена, метка в инвентаре, герой вдали от капсулы.
	Game.day_number = DAY
	player.inv.add(MARK_ID, MARK_N)
	var x: int = clampi(World.beacon_cell.x + 24, 4, World.W - 5)
	stand_at_cell(Vector2i(x, int(World.surface[x]) - 1))
	await wait(0.6)
	await _press(KEY_ESCAPE)
	ok("пауза перед выходом", pm.visible and get_tree().paused)
	var snap: Dictionary = player.save_state()
	var pos0: Vector2 = player.global_position
	var marks0: int = player.inv.count_of(MARK_ID)
	ok("герой отошёл от капсулы", pos0.distance_to(World.spawn_point) > 100.0,
			"%.0f px" % pos0.distance_to(World.spawn_point))

	# --- «Сохранить и выйти в меню».
	runner.carry_over()
	var old_scene: Node = scene
	pm.exit_button.pressed.emit()
	ok("«Сохранить и выйти в меню» — файл в слоте F5 (автосохранение поверх F5)", Save.exists(Save.slot),
			Save.path_for(Save.slot))
	var menu: MainMenu = await _scene_of(func(sc: Node) -> bool: return sc is MainMenu)
	ok("главное меню: сцена игры ушла, дерево на паузе, HUD скрыт", menu != null and not is_instance_valid(old_scene)
			and get_tree().paused and not UI.visible and not pm.visible)
	if menu == null:
		_cleanup()
		return
	await _frames(3)
	ok("в меню «Продолжить» — этот забег (смена %d)" % DAY, menu.continue_button.visible
			and not menu.continue_button.disabled and menu.continue_button.text.contains("смена %d" % DAY)
			and String(menu.continue_info.get("slot", "")) == Save.slot, menu.continue_button.text)
	ok("«Загрузить» рядом — список, не вторая «Продолжить»", menu.load_button.visible
			and menu.load_button.text == "Загрузить")
	var focus: Control = menu.get_viewport().gui_get_focus_owner()
	ok("фокус на «Продолжить»", focus == menu.continue_button)

	# --- «Продолжить».
	menu.continue_button.pressed.emit()
	var sc2: Node = await _scene_of(func(sc: Node) -> bool:
			return sc != null and sc != menu and sc.has_method("exit_to_menu") and sc.get("player") != null)
	ok("«Продолжить» — снова забег, раннер принят новой сценой", sc2 != null and runner.scene == sc2
			and not get_tree().paused and UI.visible)
	if sc2 == null:
		_cleanup()
		return
	scene = sc2
	player = sc2.get("player")
	player.invuln = 1.0e9
	await _frames(2)
	ok("смена — как при сохранении", Game.day_number == DAY, "смена %d" % Game.day_number)
	ok("инвентарь — как при сохранении", player.save_state()["inv"] == snap["inv"]
			and player.inv.count_of(MARK_ID) == marks0, "метка %d из %d" % [player.inv.count_of(MARK_ID), marks0])
	ok("герой там же, где сохранился", player.global_position.distance_to(pos0) < 4.0,
			"%s → %s" % [str(pos0), str(player.global_position)])
	_cleanup()


func _cleanup() -> void:
	if UI.pause != null:
		UI.pause.close()
	get_tree().paused = false
	if scene != null and is_instance_valid(scene):
		scene.hardcore = false
	Save.remove(Save.slot)
	DirAccess.remove_absolute(Profile.default_path())   # профиль, созданный меню
	Net.session = {}
	if player != null and is_instance_valid(player):
		player.invuln = 0.0
	finish()


## Ждать сцену, для которой cond истинно (кадрами: дерево может стоять). null — не дождались.
func _scene_of(cond: Callable) -> Node:
	for _i in SCENE_FRAMES:
		await get_tree().process_frame
		var sc: Node = get_tree().current_scene
		if sc != null and cond.call(sc):
			return sc
	return null


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


## Нажать и отпустить клавишу настоящим событием ввода (ловят UI._input и PauseMenu._input).
func _press(code: int) -> void:
	for pressed in [true, false]:
		var ev: InputEventKey = InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await get_tree().process_frame
		await get_tree().process_frame
