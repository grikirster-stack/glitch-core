extends ScenarioBase
## «Показать» не меняет мир (C3, #317). Камера уезжает на 2 с и возвращается.
## Хэши мира, машин, позиция героя и сейв до и после совпадают.


func run() -> void:
	player.invuln = 1.0e9
	var hud: HUD = UI.hud
	ok("HUD на месте", hud != null)
	if hud == null or player.camera == null:
		finish()
		return
	Game.help_hidden = false
	await _frames(hud, 3)
	ok("цель показа — не пусто", hud.card_at != Vector2.INF, str(hud.card_at))
	var world0: int = NetWorld.world_hash()
	var mach0: int = NetWorld.machines_hash()
	var pos0: Vector2 = player.global_position
	var save0: int = hash(Save.gather())
	var cam0: Vector2 = player.camera.position
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	hud._card_hit.gui_input.emit(click)
	var aimed: Vector2 = hud.card_at - player.global_position
	ok("камера уехала к цели", player.camera.position.distance_to(aimed) < 1.0,
			"%s, ждали %s" % [player.camera.position, aimed])
	ok("герой на месте", player.global_position == pos0, str(player.global_position))
	ok("мир не изменился", NetWorld.world_hash() == world0, "%d → %d" % [world0, NetWorld.world_hash()])
	ok("машины не изменились", NetWorld.machines_hash() == mach0, "%d → %d" % [mach0, NetWorld.machines_hash()])
	ok("сейв не изменился", hash(Save.gather()) == save0)
	# 2 с показа. Ждём, пока HUD сам вернёт камеру: фиксированные 2.2 с
	# не дожидаются, если кадр длинный и таймер ещё не дотикал.
	var back: bool = await wait_until(func() -> bool:
		return not hud._card_looking and player.camera.position == cam0, 3.0)
	ok("камера вернулась", back, "%s → %s, показ %s" % [cam0, player.camera.position, str(hud._card_looking)])
	ok("после возврата мир тот же", NetWorld.world_hash() == world0 and player.global_position == pos0)
	ok("дерево не на паузе", not get_tree().paused and not UI.blocking())
	finish()


func _frames(hud: HUD, n: int) -> void:
	var f0: int = hud.stat_frames
	await wait_until(func() -> bool: return hud.stat_frames >= f0 + n, 5.0)
