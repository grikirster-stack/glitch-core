extends CanvasLayer
## Автозагрузка интерфейса: HUD, окно инвентаря, журнал (J), проброс эффектов в мир.

var hud: HUD
var panel: InventoryPanel
var journal: JournalPanel
var world_fx: WorldFX = null
var player: Player = null


func _ready() -> void:
	layer = 10
	hud = HUD.new()
	add_child(hud)
	panel = InventoryPanel.new()
	add_child(panel)
	journal = JournalPanel.new()
	add_child(journal)
	Game.notification.connect(_on_notification)


func bind(p: Player) -> void:
	player = p
	hud.player = p
	panel.player = p


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event
		if k.keycode == KEY_I or k.keycode == KEY_TAB:
			toggle_inventory()
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_J:
			toggle_journal()
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_ESCAPE and (panel.visible or journal.visible):
			panel.close()
			journal.close()
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_P and world_fx:
			world_fx.show_power = not world_fx.show_power
		elif k.keycode == KEY_F5:
			quick_save()
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_F9:
			quick_load()
			get_viewport().set_input_as_handled()


# ------------------------------------------------------------- СОХРАНЕНИЕ (#37)
## F5 — сохранить забег, F9 — загрузить (Save, слот Save.slot). В --hardcore
## обе клавиши молчат: пермасмерть с загрузкой — уже не пермасмерть.

## Забег сохранён / загружен по клавише (сразу после операции, в том же кадре).
signal run_saved
signal run_loaded


func quick_save() -> bool:
	if _hardcore():
		Game.notify("Хардкор: сохранений нет.", Color(1.0, 0.6, 0.4))
		return false
	var why: String = Save.save_blocker()
	if why != "":
		Game.notify("Сохранить нельзя: %s." % why, Color(1.0, 0.6, 0.4))
		return false
	if not Save.save_game():
		Game.notify("Ошибка сохранения: %s" % Save.last_error, Color(1.0, 0.4, 0.4))
		return false
	Game.notify("Забег сохранён (F9 — загрузить).", Color(0.6, 1.0, 0.75))
	run_saved.emit()
	return true


func quick_load() -> bool:
	if _hardcore():
		Game.notify("Хардкор: сохранений нет.", Color(1.0, 0.6, 0.4))
		return false
	if not Save.load_game():
		Game.notify("Загрузить нельзя: %s." % Save.last_error, Color(1.0, 0.6, 0.4))
		return false
	Game.notify("Забег загружен: смена %d." % Game.day_number, Color(0.6, 1.0, 0.75))
	run_loaded.emit()
	return true


func _hardcore() -> bool:
	var sc: Node = get_tree().current_scene
	return sc != null and sc.get("hardcore") == true


func toggle_inventory() -> void:
	if panel.visible:
		panel.close()
	else:
		if player:
			journal.close()
			panel.open(player)


## J: журнал поверх игры. Окно одно за раз: инвентарь при этом закрывается.
func toggle_journal() -> void:
	if journal.visible:
		journal.close()
	else:
		panel.close()
		journal.open()


func open_chest(c: Chest) -> void:
	if player:
		journal.close()
		panel.open_chest(player, c)


## Открыто окно, которое забирает ввод у мира (инвентарь или журнал).
func blocking() -> bool:
	return panel.visible or journal.visible


func _on_notification(text: String, color: Color) -> void:
	hud.notify(text, color)


func flash_damage() -> void:
	hud.damage_flash = 1.0


func flash_ring(world_pos: Vector2, color: Color) -> void:
	if world_fx:
		world_fx.spawn_ring(world_pos, color)


func spawn_chip(cell: Vector2i, color: Color) -> void:
	if world_fx:
		world_fx.spawn_chip(cell, color)


func spawn_slash(world_pos: Vector2) -> void:
	if world_fx:
		world_fx.spawn_slash(world_pos)
