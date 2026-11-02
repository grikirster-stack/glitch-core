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
	var base: Color = Color(0.30, 0.33, 0.42) if powered else Color(0.21, 0.23, 0.28)
	draw_rect(Rect2(-8.0, -8.0, 16.0, 16.0), base)
	draw_rect(Rect2(-8.0, -8.0, 16.0, 3.0), base.lightened(0.22))
	# Усиленная рама: стальные косынки по углам.
	var brace: Color = base.lightened(0.35)
	draw_line(Vector2(-8.0, -5.0), Vector2(-5.0, -8.0), brace, 1.0)
	draw_line(Vector2(8.0, -5.0), Vector2(5.0, -8.0), brace, 1.0)
	draw_rect(Rect2(-8.0, 6.0, 16.0, 2.0), base.darkened(0.3))
	# Сверло крупнее и светлее обычного.
	_draw_bit(Color(0.70, 0.86, 0.98), 6.0)
	# Двойной стержень: шахта идёт глубже.
	var rod: Color = Color(0.58, 0.62, 0.70)
	draw_line(Vector2(-2.0, 6.0), Vector2(-2.0, 15.0), rod, 2.0)
	draw_line(Vector2(2.0, 6.0), Vector2(2.0, 15.0), rod, 2.0)
	_draw_power_lamp(Vector2(5.0, -5.0))
