extends ScenarioBase
## Помощь скрывается и возвращается (C3, #317). Состояние в сейве.
## Новый забег — помощь видна. Пройденный шаг не возвращается.


func run() -> void:
	player.invuln = 1.0e9
	var hud: HUD = UI.hud
	ok("HUD на месте", hud != null)
	if hud == null:
		finish()
		return
	Game.help_hidden = false
	Game.guide_latch = 0
	await _frames(hud, 3)
	var shown: String = hud.card_text
	ok("помощь видна: карточка шага", shown == "Поставь каркас у лагеря", "«%s»" % shown)
	hud._on_guide_hide()
	await _frames(hud, 2)
	ok("скрыто: карточка цели, не шага", hud.card_text == "Поставь горелку", "«%s»" % hud.card_text)
	ok("флаг скрытия записан", Game.help_hidden)
	var slot: String = Save.slot
	Save.slot = "guide_hide"
	Save.remove("guide_hide")
	ok("сейв помощи", Save.save_game("guide_hide"))
	Game.help_hidden = false
	ok("загрузка вернула скрытие", Save.load_game("guide_hide") and Game.help_hidden)
	Save.remove("guide_hide")
	Save.slot = slot
	# Старый файл поля не знает — помощь снова видна.
	var old: Dictionary = Save.gather()
	var game: Dictionary = old["game"]
	game.erase("guide_latch")
	game.erase("help_hidden")
	old["game"] = game
	Game.help_hidden = true
	Game.guide_latch = 4
	Save.apply(old)
	ok("старый файл: помощь видна и защёлка пуста", not Game.help_hidden and Game.guide_latch == 0,
			"скрыта %s, защёлка %d" % [Game.help_hidden, Game.guide_latch])
	hud._on_guide_help()
	await _frames(hud, 2)
	ok("«?» вернул текущий шаг, не пройденный", hud.card_text == "Поставь каркас у лагеря",
			"«%s»" % hud.card_text)
	finish()


func _frames(hud: HUD, n: int) -> void:
	var f0: int = hud.stat_frames
	await wait_until(func() -> bool: return hud.stat_frames >= f0 + n, 5.0)
