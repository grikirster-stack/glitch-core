class_name DeepDrill
extends Drill
## Глубинный бур (ADR-001 § 4.2, #30): та же буровая, но быстрее и глубже —
## такт Balance.DEEP_DRILL_CYCLE, достаёт на Balance.DEEP_DRILL_REACH клеток вниз.
## Тянет 4 мощности (Balance.POWER_DRAW["DeepDrill"]).


func _init() -> void:
	kind = "DeepDrill"
	z_index = 3


func cycle() -> float:
	return Balance.DEEP_DRILL_CYCLE


func reach() -> int:
	return Balance.DEEP_DRILL_REACH


func _draw() -> void:
	_draw_body(BODY, powered, false)
	# Усиленная рама: стальные косынки-квадраты по углам и жёлтая полоса
	# во всю ширину внизу — «тяжёлая» машина.
	draw_rect(Rect2(-8.0, -8.0, 3.0, 3.0), C_FRAME)
	draw_rect(Rect2(5.0, -8.0, 3.0, 3.0), C_FRAME)
	draw_rect(Rect2(-7.0, 5.0, 14.0, 2.0), C_HAZARD)
	for k in 4:
		draw_rect(Rect2(-6.0 + k * 4.0, 5.0, 2.0, 2.0), C_FRAME)
	# Окно шире, шнек толще.
	draw_rect(Rect2(-5.0, -4.0, 10.0, 9.0), C_FRAME)
	draw_rect(Rect2(-4.0, -3.0, 8.0, 7.0), C_SCREEN)
	_draw_auger(Rect2(-3.0, -3.0, 6.0, 7.0), C_BIO.lerp(C_METAL_HI, 0.5))
	# Двойная штанга: шахта идёт глубже.
	_draw_auger(Rect2(-3.0, 8.0, 2.0, 7.0), C_METAL_D)
	_draw_auger(Rect2(1.0, 8.0, 2.0, 7.0), C_METAL_D)
	_draw_power_lamp(Vector2(6.0, -6.0))
