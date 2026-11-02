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
	# Панель в раме на стойке: ячейки — тёмное стекло с бирюзовым отливом,
	# днём (в работе) отлив ярче. Кремовое основание с жёлтой разметкой.
	draw_rect(Rect2(-8.0, -8.0, 16.0, 10.0), C_FRAME)
	var cellc: Color = C_SCREEN.lerp(C_BIO, 0.35 if power_active else 0.15)
	var glint: Color = C_BIO.lerp(C_METAL_HI, 0.4) if power_active else C_SCREEN.lerp(C_BIO, 0.3)
	for i in 3:
		for j in 2:
			var x: float = -7.0 + i * 5.0
			var y: float = -7.0 + j * 5.0
			draw_rect(Rect2(x, y, 4.0, 4.0 if j == 0 else 3.0), cellc)
			draw_rect(Rect2(x, y, 1.0, 1.0), glint)
	draw_rect(Rect2(-1.0, 2.0, 2.0, 4.0), C_METAL_D)
	_draw_body(Rect2(-6.0, 5.0, 12.0, 3.0), true, false)
	draw_rect(Rect2(-5.0, 6.0, 2.0, 1.0), C_HAZARD)
	draw_rect(Rect2(-1.0, 6.0, 2.0, 1.0), C_HAZARD)
	draw_rect(Rect2(3.0, 6.0, 2.0, 1.0), C_HAZARD)
	if power_active:
		# Солнце-квадрат над панелью: «работает от света».
		draw_rect(Rect2(-1.0, -13.0, 3.0, 3.0), C_LAVA_HI)
	if not enabled or overloaded():
		_draw_status_lamp(Vector2(5.0, -5.0))
