class_name EndScreen
extends Control
## Экран победы/поражения с итогами забега. Он же — экран смерти с эпитафией
## из Lore и отсчётом до респауна (ADR-001 § 4.8, #29): тогда R не перезапускает.

signal restart_requested

var title: String = ""
var subtitle: String = ""
var color: Color = Color.WHITE
var stats: Array = []
var t: float = 0.0
## Экран смерти перед респауном: сколько секунд показывать (< 0 — финальный экран).
var respawn_delay: float = -1.0


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
	visible = true
	t = 0.0
	queue_redraw()


## Экран смерти с эпитафией и отсчётом до респауна в капсуле.
func show_death(p_epitaph: String, delay: float) -> void:
	show_end("ТЕБЯ НАШЛИ", p_epitaph, Color(0.92, 0.28, 0.34), [])
	respawn_delay = delay


func hide_end() -> void:
	visible = false
	respawn_delay = -1.0


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
	var cy: float = size.y * 0.30
	var bob: float = sin(t * 2.0) * 3.0
	draw_string(font, Vector2(0, cy + bob), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 52, Color(color.r, color.g, color.b, a))
	draw_string(font, Vector2(0, cy + 44), subtitle, HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, Color(0.85, 0.9, 1.0, a))
	var y: float = cy + 90
	for s in stats:
		draw_string(font, Vector2(0, y), String(s), HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, Color(0.8, 0.85, 0.95, a))
		y += 26
	var blink: float = 0.55 + 0.45 * sin(t * 4.0)
	if respawn_delay >= 0.0:
		var left: int = ceili(maxf(0.0, respawn_delay - t))
		draw_string(font, Vector2(0, size.y * 0.78), "Капсула на базе через %d с…" % left,
				HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, Color(1.0, 0.95, 0.7, a))
		return
	draw_string(font, Vector2(0, size.y * 0.78), "[R] — новая попытка",
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, Color(1.0, 0.95, 0.7, a * blink))
