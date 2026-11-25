extends ScenarioBase
## Цепочка на телефоне (C3, #317). Плашка без ЛКМ, ПКМ, [X] и «удерживать».
## Тап по карточке — тот же показ, что клик. Вводные 15 с шаг не прячут.


const CARD: String = "Поставь каркас у лагеря"
const PLATE: String = "Поставь каркас: тап панелью у лагеря"


func run() -> void:
	player.invuln = 1.0e9
	var hud: HUD = UI.hud
	ok("HUD на месте", hud != null)
	if hud == null:
		finish()
		return
	var was: bool = UI.touch_on
	UI.touch_on = true
	Game.help_hidden = false
	Game.guide_latch = 0
	Game.game_time = 1.0
	aim(Vector2(-10000, -10000))
	await _frames(hud, 3)
	ok("телефон: карточка каркаса", hud.card_text == CARD, "«%s»" % hud.card_text)
	ok("телефон: плашка называет тап, не ПКМ", hud.plate_text() == PLATE, "«%s»" % hud.plate_text())
	var plate: String = hud.plate_text()
	ok("плашка без ЛКМ, ПКМ, [X] и «удерживать»",
			not plate.contains("ЛКМ") and not plate.contains("ПКМ")
			and not plate.contains("[X]") and not plate.contains("удерживать"), plate)
	ok("вводные 15 с шаг не спрятали", not plate.begins_with("Джойстик"), plate)
	var touch: InputEventScreenTouch = InputEventScreenTouch.new()
	touch.pressed = true
	touch.index = 0
	hud._card_hit.gui_input.emit(touch)
	ok("тап по карточке увёл камеру", hud._card_looking and hud.card_look_left > 0.0,
			"смотрит %s" % hud._card_looking)
	UI.touch_on = was
	finish()


func _frames(hud: HUD, n: int) -> void:
	var f0: int = hud.stat_frames
	await wait_until(func() -> bool: return hud.stat_frames >= f0 + n, 5.0)
