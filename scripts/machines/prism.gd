class_name Prism
extends MachineBase
## Призма (ADR-005 § 4–5, #165): белый луч делится на три основных.
##
## Вход — любая грань. Белый: красный продолжает направление, зелёный
## уходит налево, синий — направо. Любой другой цвет проходит прямо.
## Своего состояния нет: каждый луч делится независимо.


func _init() -> void:
	kind = "Prism"
	z_index = 3
	can_turn = true
	beam_passer = true


## in_dir — направление пришедшего луча. «Прямо» — то же направление.
func beam_pass(in_dir: int, color: int) -> Array:
	var c: int = color & 7
	if c == 0:
		return []
	var d: int = in_dir & 3
	if c != Beams.W:
		return [[d, c]]
	# Налево от направления — dir+3, направо — dir+1 (по часовой: 0→1).
	return [[d, Beams.R], [(d + 3) & 3, Beams.G], [(d + 1) & 3, Beams.B]]


func _draw() -> void:
	_draw_body(BODY, true, false)
	# Треугольник в корпусе. Остриё смотрит по dir — туда уйдёт красный.
	var tip: Vector2 = _tip(dir)
	var left: Vector2 = _tip((dir + 3) & 3)
	var right: Vector2 = _tip((dir + 1) & 3)
	_tri(tip, left, right)
	# Три цветные точки на гранях: R прямо, G налево, B направо.
	draw_rect(Rect2(tip.x - 1.0, tip.y - 1.0, 2.0, 2.0), Beams.COLOR[Beams.R])
	draw_rect(Rect2(left.x - 1.0, left.y - 1.0, 2.0, 2.0), Beams.COLOR[Beams.G])
	draw_rect(Rect2(right.x - 1.0, right.y - 1.0, 2.0, 2.0), Beams.COLOR[Beams.B])


func _tip(d: int) -> Vector2:
	match d & 3:
		0:
			return Vector2(4.0, 0.0)
		1:
			return Vector2(0.0, 4.0)
		2:
			return Vector2(-4.0, 0.0)
		_:
			return Vector2(0.0, -4.0)


## Треугольник из прямоугольников: пиксельная сетка, без линий наискосок.
func _tri(tip: Vector2, a: Vector2, b: Vector2) -> void:
	var glass: Color = Color(0.78, 0.90, 0.96)
	var edge: Color = C_FRAME
	for i in 5:
		var t: float = float(i) / 4.0
		var p: Vector2 = a.lerp(b, t)
		var q: Vector2 = p.lerp(tip, 1.0 - t * 0.15)
		draw_rect(Rect2(q.x - 1.0, q.y - 1.0, 2.0, 2.0), glass if i % 2 == 0 else edge)
	draw_rect(Rect2(tip.x - 1.0, tip.y - 1.0, 3.0, 3.0), glass)
	draw_rect(Rect2(a.x, a.y, 2.0, 2.0), edge)
	draw_rect(Rect2(b.x, b.y, 2.0, 2.0), edge)
