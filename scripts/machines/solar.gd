class_name Solar
extends Generator
## Солнечная панель: работает только днём, зато бесплатно.

func _init() -> void:
	kind = "Solar"
	power_radius = 6.0


func _process(delta: float) -> void:
	super(delta)
	power_active = Game.daylight() > 0.35
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(-8.0, -8.0, 16.0, 16.0), Color(0.18, 0.26, 0.42))
	for i in 4:
		draw_line(Vector2(-7.0 + i * 4.0, -7.0), Vector2(-7.0 + i * 4.0, 7.0), Color(0.35, 0.48, 0.70), 1.0)
	draw_line(Vector2(-8.0, 0.0), Vector2(8.0, 0.0), Color(0.35, 0.48, 0.70), 1.0)
	draw_rect(Rect2(-8.0, 8.0, 16.0, 2.0), Color(0.55, 0.58, 0.62))
	if power_active:
		draw_circle(Vector2(0.0, -12.0), 2.0, Color(1.0, 0.85, 0.35))
