class_name JournalPanel
extends Control
## Журнал экспедиции (клавиша J; ADR-001, § 4.9): экипаж «Кербер-9», главы
## журнала и обрывки из чёрных ящиков.
##
## Тексты — из `Lore` (детерминированы сидом мира), что прочитано и найдено —
## из `Tech` (`read_chapters`, `fragments`). Неоткрытая глава видна строкой «▒▒▒».
## «Не тот» в списке экипажа ничем не выделен: журнал его не выдаёт.
##
## Открытая панель блокирует ввод в мир так же, как инвентарь (`UI.blocking()`).

const W: float = 820.0
const H: float = 470.0
## Заглушка вместо названия непрочитанной главы.
const LOCKED: String = "▒▒▒"
const CREW_ROW: float = 24.0
const CHAPTER_ROW: float = 20.0
const TEXT_X: float = 296.0
const TEXT_W: float = 508.0

## Выбранная глава (номер 0..8) или -1 — ничего не прочитано.
var selected: int = -1
## Сдвиг списка обрывков (колесо мыши над правым нижним блоком).
var frag_scroll: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


## Открыть журнал на последней прочитанной главе.
func open() -> void:
	selected = -1
	if not Tech.read_chapters.is_empty():
		selected = int(Tech.read_chapters[Tech.read_chapters.size() - 1])
	frag_scroll = 0
	visible = true
	queue_redraw()


func close() -> void:
	visible = false


## Строка главы в списке: название, если глава прочитана, иначе «▒▒▒».
func chapter_label(i: int) -> String:
	if Tech.is_chapter_read(i):
		return "%d. %s" % [i + 1, Lore.chapter_title(i)]
	return "%d. %s" % [i + 1, LOCKED]


func _panel_pos() -> Vector2:
	return Vector2((size.x - W) * 0.5, (size.y - H) * 0.5)


func _chapter_rect(i: int) -> Rect2:
	return Rect2(_panel_pos() + Vector2(16, 258 + i * CHAPTER_ROW), Vector2(260, CHAPTER_ROW - 2))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			frag_scroll = maxi(0, frag_scroll - 1)
			queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			frag_scroll = mini(frag_scroll + 1, maxi(0, Tech.fragments.size() - 1))
			queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_click(mb.position)
	elif event is InputEventMouseMotion:
		queue_redraw()


func _click(pos: Vector2) -> void:
	for i in Lore.chapter_count():
		if _chapter_rect(i).has_point(pos) and Tech.is_chapter_read(i):
			selected = i
			queue_redraw()
			return


func _draw() -> void:
	var o: Vector2 = _panel_pos()
	var font: Font = ThemeDB.fallback_font
	draw_rect(Rect2(o, Vector2(W, H)), Color(0.06, 0.07, 0.09, 0.95))
	draw_rect(Rect2(o, Vector2(W, H)), Color(0.75, 0.68, 0.45, 0.8), false, 2.0)
	draw_string(font, o + Vector2(16, 26), "ЖУРНАЛ ЭКСПЕДИЦИИ «%s»" % Lore.CREW_NAME,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.95, 0.9, 0.72))
	draw_string(font, o + Vector2(16, 26), "глав %d/%d · обрывков %d" % [Tech.read_chapters.size(),
			Lore.chapter_count(), Tech.fragments.size()], HORIZONTAL_ALIGNMENT_RIGHT, W - 32, 12,
			Color(0.65, 0.65, 0.58))
	_draw_crew(o, font)
	_draw_chapters(o, font)
	_draw_text(o, font)
	_draw_fragments(o, font)
	draw_string(font, o + Vector2(16, H - 10),
			"ЛКМ по главе — читать   колесо — листать обрывки   J/ESC — закрыть",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.72, 0.78, 0.9))


func _draw_crew(o: Vector2, font: Font) -> void:
	draw_string(font, o + Vector2(16, 56), "ЭКИПАЖ", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.8, 0.6))
	var y: float = o.y + 64
	for c in Lore.crew:
		draw_string(font, Vector2(o.x + 16, y + 14), String(c["full"]), HORIZONTAL_ALIGNMENT_LEFT, 170, 13,
				Color(0.9, 0.92, 0.95))
		draw_string(font, Vector2(o.x + 16, y + 14), "%s «%s»" % [String(c["role"]), String(c["callsign"])],
				HORIZONTAL_ALIGNMENT_RIGHT, 260, 11, Color(0.6, 0.63, 0.7))
		y += CREW_ROW


func _draw_chapters(o: Vector2, font: Font) -> void:
	draw_string(font, o + Vector2(16, 250), "ГЛАВЫ", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.8, 0.6))
	var mp: Vector2 = get_local_mouse_position()
	for i in Lore.chapter_count():
		var r: Rect2 = _chapter_rect(i)
		var read: bool = Tech.is_chapter_read(i)
		if i == selected:
			draw_rect(r, Color(0.22, 0.2, 0.12, 0.9))
		elif read and r.has_point(mp):
			draw_rect(r, Color(0.14, 0.14, 0.11, 0.9))
		var col: Color = Color(0.92, 0.88, 0.7) if read else Color(0.4, 0.4, 0.42)
		draw_string(font, r.position + Vector2(6, 15), chapter_label(i), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 8, 13, col)


func _draw_text(o: Vector2, font: Font) -> void:
	var x: float = o.x + TEXT_X
	draw_line(Vector2(x - 10, o.y + 44), Vector2(x - 10, o.y + H - 24), Color(1, 1, 1, 0.1), 1.0)
	if selected < 0:
		draw_string(font, Vector2(x, o.y + 56), "ЗАПИСЕЙ НЕТ", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.8, 0.6))
		draw_multiline_string(font, Vector2(x, o.y + 80),
				"Журнал экипажа хранят терминалы станции. Запитайте терминал и прочтите его — глава появится здесь.",
				HORIZONTAL_ALIGNMENT_LEFT, TEXT_W, 13, 4, Color(0.62, 0.65, 0.72))
		return
	draw_string(font, Vector2(x, o.y + 56), "Глава %d. %s" % [selected + 1, Lore.chapter_title(selected)],
			HORIZONTAL_ALIGNMENT_LEFT, TEXT_W, 15, Color(0.95, 0.9, 0.72))
	var author: Dictionary = Lore.chapter_author(selected)
	var meta: String = Lore.chapter_place(selected)
	if not author.is_empty():
		meta = "%s, %s · %s" % [String(author["full"]), String(author["role"]), meta]
	draw_string(font, Vector2(x, o.y + 74), meta, HORIZONTAL_ALIGNMENT_LEFT, TEXT_W, 11, Color(0.6, 0.62, 0.68))
	draw_multiline_string(font, Vector2(x, o.y + 98), Lore.chapter(selected), HORIZONTAL_ALIGNMENT_LEFT,
			TEXT_W, 13, 12, Color(0.85, 0.87, 0.9))


func _draw_fragments(o: Vector2, font: Font) -> void:
	var x: float = o.x + TEXT_X
	var top: float = o.y + 334
	draw_line(Vector2(x, top - 14), Vector2(o.x + W - 16, top - 14), Color(1, 1, 1, 0.1), 1.0)
	draw_string(font, Vector2(x, top), "ОБРЫВКИ", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.8, 0.6))
	if Tech.fragments.is_empty():
		draw_string(font, Vector2(x, top + 22), "Чёрные ящики пока молчат.", HORIZONTAL_ALIGNMENT_LEFT, TEXT_W, 12,
				Color(0.5, 0.52, 0.56))
		return
	# Свежие — сверху; колесо листает вглубь.
	var y: float = top + 20
	var i: int = Tech.fragments.size() - 1 - frag_scroll
	while i >= 0 and y < o.y + H - 34:
		draw_multiline_string(font, Vector2(x, y), "— " + String(Tech.fragments[i]), HORIZONTAL_ALIGNMENT_LEFT,
				TEXT_W, 12, 2, Color(0.75, 0.77, 0.8))
		y += 34
		i -= 1
