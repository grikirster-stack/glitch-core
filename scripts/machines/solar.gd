class_name Solar
extends Generator
## Солнечная панель: работает только днём, зато бесплатно.
## Даёт Balance.POWER_OUT["Solar"], пока daylight() > SOLAR_MIN_DAYLIGHT; ночью 0.

func _init() -> void:
	kind = "Solar"
	power_radius = 6.0
	power_output = float(Balance.POWER_OUT["Solar"])


func _process(delta: float) -> void:
	super(delta)
	power_active = enabled and Game.daylight() > Balance.SOLAR_MIN_DAYLIGHT
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(-8.0, -8.0, 16.0, 16.0), Color(0.18, 0.26, 0.42))
	for i in 4:
		draw_line(Vector2(-7.0 + i * 4.0, -7.0), Vector2(-7.0 + i * 4.0, 7.0), Color(0.35, 0.48, 0.70), 1.0)
	draw_line(Vector2(-8.0, 0.0), Vector2(8.0, 0.0), Color(0.35, 0.48, 0.70), 1.0)
	draw_rect(Rect2(-8.0, 8.0, 16.0, 2.0), Color(0.55, 0.58, 0.62))
	if power_active:
		draw_circle(Vector2(0.0, -12.0), 2.0, Color(1.0, 0.85, 0.35))
	if not enabled or overloaded():
		_draw_status_lamp(Vector2(5.0, -5.0))
