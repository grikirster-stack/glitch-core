extends ScenarioBase
## После налёта плашка несёт итог и один следующий проект (C3, #317).
## Пока фаза не 0, строка налёта не подменяется. Дерево не на паузе.


func run() -> void:
	player.invuln = 1.0e9
	var hud: HUD = UI.hud
	ok("HUD на месте", hud != null)
	if hud == null:
		finish()
		return
	Game.raid_phase = 2
	hud.raid_line = "Налёт с востока, цель — база"
	await _frames(hud, 2)
	ok("во время налёта плашка — строка налёта", hud.plate_text() == "Налёт с востока, цель — база",
			"«%s»" % hud.plate_text())
	UI.touch_on = false
	Game.help_hidden = true
	Game.raid_damage = "device"
	Game.raid_phase = 3
	hud.raid_line = "Налёт с востока: чини камнем или хламом"
	var noted: bool = await wait_until(func() -> bool:
		return Game.raid_note.begins_with("Налёт с востока: чини камнем или хламом"), 1.5)
	ok("итог снят, пока фаза 3", noted, Game.raid_note)
	ok("в итоге один следующий проект и одна альтернатива",
			Game.raid_note.contains("Дальше:") and Game.raid_note.contains("Или "), Game.raid_note)
	# Фаза ещё 3: плашка остаётся строкой налёта, не итогом цепочки.
	ok("фаза 3 не подменяет плашку итогом", hud.plate_text() == hud.raid_line, hud.plate_text())
	Game.raid_phase = 0
	hud.raid_line = ""
	Game.raid_damage = ""
	await _frames(hud, 2)
	ok("после фазы 0 плашка — снятый итог", hud.plate_text() == Game.raid_note, "«%s»" % hud.plate_text())
	ok("дерево не на паузе и UI не блокирует", not get_tree().paused and not UI.blocking())
	Game.raid_note = ""
	finish()


func _frames(hud: HUD, n: int) -> void:
	var f0: int = hud.stat_frames
	await wait_until(func() -> bool: return hud.stat_frames >= f0 + n, 5.0)
