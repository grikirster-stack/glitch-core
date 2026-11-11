class_name Mirror
extends MachineBase
## Зеркало (ADR-005 § 4–5, #165): поворачивает луч на 90°, цвет тот же.
##
## Диагональ по dir: 0 и 2 — «/», 1 и 3 — «\». turn() ходит по четырём
## положениям, отражение смотрит на dir % 2. Несколько лучей в одно зеркало
## отражаются независимо: своего состояния у зеркала нет.


func _init() -> void:
	kind = "Mirror"
	z_index = 3
	can_turn = true
	beam_passer = true


## «/»: вправо→вверх, вверх→вправо, влево→вниз, вниз→влево.
## «\»: вправо→вниз, вниз→вправо, влево→вверх, вверх→влево.
## Луч в ребро, а не в зеркало, уходит обратно — иначе он прошёл бы насквозь.
func beam_pass(in_dir: int, color: int) -> Array:
	if color == 0:
		return []
	var slash: bool = (dir % 2) == 0
	var out_dir: int = _reflect(in_dir & 3, slash)

	return [[out_dir, color & 7]]


static func _reflect(in_dir: int, slash: bool) -> int:
	# В игре y растёт вниз, поэтому «вверх» — это направление 3.
	# «/»: вправо→вверх, вверх→вправо, влево→вниз, вниз→влево.
	# «\»: вправо→вниз, вниз→вправо, влево→вверх, вверх→влево.
	if slash:
		return [3, 2, 1, 0][in_dir]
	return [1, 0, 3, 2][in_dir]


func _draw() -> void:
	_draw_body(BODY, true, false)
	var slash: bool = (dir % 2) == 0
	var stripe: Color = Color(0.92, 0.96, 1.0)
	var edge: Color = C_FRAME
	for i in range(-6, 7):
		var x: float = float(i)
		var y: float = -x if slash else x
		draw_rect(Rect2(x, y, 1.0, 1.0), edge)
		draw_rect(Rect2(x, y - 1.0, 1.0, 1.0), stripe)
		draw_rect(Rect2(x + (1.0 if slash else -1.0), y, 1.0, 1.0), stripe.darkened(0.15))
	# Уголок направления: ребёнок видит, какая это диагональ, не читая текст.
	var mark: Vector2 = Vector2(4.0, -5.0) if slash else Vector2(4.0, 4.0)
	draw_rect(Rect2(mark.x, mark.y, 2.0, 2.0), stripe)
