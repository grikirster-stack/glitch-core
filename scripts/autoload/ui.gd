extends CanvasLayer
## Автозагрузка интерфейса: HUD, окно инвентаря, проброс эффектов в мир.

var hud: HUD
var panel: InventoryPanel
var world_fx: WorldFX = null
var player: Player = null


func _ready() -> void:
	layer = 10
	hud = HUD.new()
	add_child(hud)
	panel = InventoryPanel.new()
	add_child(panel)
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
		elif k.keycode == KEY_ESCAPE and panel.visible:
			panel.close()
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_P and world_fx:
			world_fx.show_power = not world_fx.show_power


func toggle_inventory() -> void:
	if panel.visible:
		panel.close()
	else:
		if player:
			panel.open(player)


func open_chest(c: Chest) -> void:
	if player:
		panel.open_chest(player, c)


func blocking() -> bool:
	return panel.visible


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
