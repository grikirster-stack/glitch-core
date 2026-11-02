class_name EndScreen
extends Control
## Экран победы/поражения с итогами забега. Он же — экран смерти с эпитафией
## из Lore и отсчётом до респауна (ADR-001 § 4.8, #29): тогда R не перезапускает.
## Победа (§ 4.7, #32) — эпилог из Lore.epilogue() абзацами и итоги в две колонки.
##
## Живёт в своём CanvasLayer (LAYER, main.gd): в экранных координатах, поверх
## мира, тумана войны и HUD.

signal restart_requested

## Слой CanvasLayer экрана: выше UI (HUD, инвентарь, журнал — слой 10).
const LAYER: int = 20
## Эпилог не шире этого, px — строки длиннее читать трудно.
const EPILOGUE_MAX_W: float = 760.0
const EPILOGUE_FONT: int = 15
const STATS_FONT: int = 15
const STATS_ROW: float = 21.0

var title: String = ""
var subtitle: String = ""
var color: Color = Color.WHITE
var stats: Array = []
var t: float = 0.0
## Экран смерти перед респауном: сколько секунд показывать (< 0 — финальный экран).
var respawn_delay: float = -1.0
## Эпилог победы (абзацы через «\n»); пусто — обычный экран.
var epilogue: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func show_end(p_title: String, p_subtitle: String, p_color: Color, p_stats: Array) -> void:
	title = p_title
	subtitle = p_subtitle
	color = p_color
	stats = p_stats
	respawn_delay = -1.0
	epilogue = ""
	visible = true
	t = 0.0
	queue_redraw()


## Победа: сигнал ушёл на орбиту — эпилог экспедиции и итоги.
func show_victory(p_epilogue: String, p_stats: Array) -> void:
	show_end("ЭВАКУАЦИЯ", "Сигнал принят на орбите. Капсула уходит вверх.",
			Color(0.40, 1.0, 0.78), p_stats)
	epilogue = p_epilogue


## Экран смерти с эпитафией и отсчётом до респауна в капсуле.
func show_death(p_epitaph: String, delay: float) -> void:
	show_end("ТЕБЯ НАШЛИ", p_epitaph, Color(0.92, 0.28, 0.34), [])
	respawn_delay = delay


func hide_end() -> void:
	visible = false
	respawn_delay = -1.0
	epilogue = ""


func _process(delta: float) -> void:
	if visible:
		t += delta
		queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible or respawn_delay >= 0.0:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event
		if k.keycode == KEY_R or k.keycode == KEY_ENTER or k.keycode == KEY_SPACE:
			restart_requested.emit()


func _draw() -> void:
	var a: float = clampf(t * 1.6, 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.05, 0.86 * a))
	var font: Font = ThemeDB.fallback_font
	if epilogue != "":
		_draw_victory(font, a)
		return
	var cy: float = size.y * 0.30
	var bob: float = sin(t * 2.0) * 3.0
	draw_string(font, Vector2(0, cy + bob), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 52, Color(color.r, color.g, color.b, a))
	draw_string(font, Vector2(0, cy + 44), subtitle, HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, Color(0.85, 0.9, 1.0, a))
	var y: float = cy + 90
	for s in stats:
		draw_string(font, Vector2(0, y), String(s), HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, Color(0.8, 0.85, 0.95, a))
		y += 26
	if respawn_delay >= 0.0:
		var left: int = ceili(maxf(0.0, respawn_delay - t))
		draw_string(font, Vector2(0, size.y * 0.78), "Капсула на базе через %d с…" % left,
				HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, Color(1.0, 0.95, 0.7, a))
		return
	_draw_prompt(font, a, size.y * 0.78)


## Победа: заголовок выше, эпилог абзацами по ширине, итоги в две колонки.
## Раскладка от высоты экрана — влезает и в 960×540.
func _draw_victory(font: Font, a: float) -> void:
	var w: float = size.x
	var bob: float = sin(t * 2.0) * 3.0
	var y: float = maxf(56.0, size.y * 0.13)
	draw_string(font, Vector2(0, y + bob), title, HORIZONTAL_ALIGNMENT_CENTER, w, 44, Color(color.r, color.g, color.b, a))
	y += 34
	draw_string(font, Vector2(0, y), subtitle, HORIZONTAL_ALIGNMENT_CENTER, w, 18, Color(0.85, 0.9, 1.0, a))
	y += 30
	# Эпилог: абзацы — по «\n», перенос по словам внутри колонки.
	var ew: float = minf(EPILOGUE_MAX_W, w - 64.0)
	var ex: float = (w - ew) * 0.5
	var line_h: float = font.get_height(EPILOGUE_FONT) + 2.0
	for para in epilogue.split("\n", false):
		var ps: Vector2 = font.get_multiline_string_size(para, HORIZONTAL_ALIGNMENT_CENTER, ew, EPILOGUE_FONT)
		draw_multiline_string(font, Vector2(ex, y + font.get_ascent(EPILOGUE_FONT)), para,
				HORIZONTAL_ALIGNMENT_CENTER, ew, EPILOGUE_FONT, -1, Color(0.92, 0.94, 1.0, a))
		y += maxf(ps.y, line_h) + 6.0
	# Итоги — две колонки по центру.
	y += 10.0
	var col_w: float = minf(320.0, (w - 64.0) * 0.5)
	var half: int = ceili(float(stats.size()) / 2.0)
	for i in stats.size():
		var cx: float = w * 0.5 - col_w + (col_w if i >= half else 0.0)
		var sy: float = y + float(i % half) * STATS_ROW
		draw_string(font, Vector2(cx, sy), String(stats[i]), HORIZONTAL_ALIGNMENT_CENTER, col_w,
				STATS_FONT, Color(0.75, 0.82, 0.95, a))
	y += float(half) * STATS_ROW + 14.0
	_draw_prompt(font, a, maxf(y + 8.0, size.y - 34.0))


func _draw_prompt(font: Font, a: float, y: float) -> void:
	var blink: float = 0.55 + 0.45 * sin(t * 4.0)
	draw_string(font, Vector2(0, y), "[R] — новая попытка",
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, Color(1.0, 0.95, 0.7, a * blink))
