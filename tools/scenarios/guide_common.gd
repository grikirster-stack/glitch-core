class_name GuideCommon
extends RefCounted
## Общие проверки цепочки новичка (C3, #317). Сценарий зовёт их сам.
## Строки сравниваются целиком, не по одному слову.


static func card_is(hud: HUD, want: String) -> bool:
	return hud.card_text == want


static func plate_is(hud: HUD, want: String) -> bool:
	return hud.plate_text() == want


## Плашка телефона не называет мышь и удержание.
static func touch_clean(plate: String) -> bool:
	if plate.contains("ЛКМ") or plate.contains("ПКМ") or plate.contains("[X]"):
		return false
	if plate.contains("удерживать"):
		return false
	return true


static func words_ok(text: String) -> bool:
	return text.split(" ", false).size() <= 6
