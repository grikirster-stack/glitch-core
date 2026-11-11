class_name Mirror
extends MachineBase
## Зеркало (ADR-005 § 4–5): поворот на 90° и на 45°.
##
## dir 0 и 2 — «/», 1 и 3 — «\». Прямой луч уходит под 90°, как в старом сейве.
## dir 4 и 6 — наклон 22,5° («пологая /»): прямой уходит по диагонали,
## диагональный — на прямую. dir 5 и 7 — «пологая \», то же в другую сторону.
## turn() шагает на 45°: 0 → 4 → 1 → 5 → 2 → 6 → 3 → 7 → 0.
## Несколько лучей в одно зеркало отражаются независимо.
##
## Направления 0..7: вправо, вниз, влево, вверх, вправо-вниз, влево-вниз,
## влево-вверх, вправо-вверх. «Вверх» — меньший y.


func _init() -> void:
	kind = "Mirror"
	z_index = 3
	can_turn = true
	turn_steps = 8
	beam_passer = true


## Луч в ребро, а не в зеркало, уходит обратно — иначе он прошёл бы насквозь.
func beam_pass(in_dir: int, color: int) -> Array:
	if color == 0:
		return []
	return [[_reflect(in_dir & 7, dir & 7), color & 7]]


## Таблица 8×8: строка — dir зеркала, столбец — откуда пришёл луч.
## 0..3 совпадают со старым «/» и «\». 4..7 — наклон 22,5°: прямой ↔ диагональ.
static func _reflect(in_dir: int, mirror_dir: int) -> int:
	return _TABLE[(mirror_dir & 7) * 8 + (in_dir & 7)]


const _TABLE: PackedByteArray = [
	3, 2, 1, 0, 6, 5, 4, 7,   ## 0 «/» 45°: вправо→вверх
	1, 0, 3, 2, 4, 7, 6, 5,   ## 1 «\» 45°: вправо→вниз
	3, 2, 1, 0, 6, 5, 4, 7,   ## 2 «/»
	1, 0, 3, 2, 4, 7, 6, 5,   ## 3 «\»
	7, 6, 5, 4, 3, 2, 1, 0,   ## 4 пологая «/»: вправо→вправо-вверх, диагональ→прямая
	4, 7, 6, 5, 0, 3, 2, 1,   ## 5 пологая «\»: вправо→вправо-вниз
	7, 6, 5, 4, 3, 2, 1, 0,   ## 6 пологая «/»
	4, 7, 6, 5, 0, 3, 2, 1,   ## 7 пологая «\»
]


func net_state() -> PackedByteArray:
	var b: PackedByteArray = super()
	# База кладёт только 0..3. Наклон 22,5° — свой байт, только у зеркала:
	# у него своего хвоста не было, разбор остальных машин не съезжает.
	b.append(dir & 7)
	return b


func apply_net_state(b: PackedByteArray) -> int:
	var o: int = super(b)
	if o < 0:
		return -1
	# Старый пакет без байта: dir 0..3 лежит в флагах базы. База его для
	# turn_steps = 8 не пишет — читаем здесь.
	if b.size() < o + 1:
		var old: int = (int(b[1]) >> NF_DIR_SHIFT) & 3
		if old != dir:
			dir = old
			queue_redraw()
		return o
	var d: int = int(b[o]) & 7
	if d != dir:
		dir = d
		queue_redraw()
	return o + 1


func _draw() -> void:
	_draw_body(BODY, true, false)
	var stripe: Color = Color(0.92, 0.96, 1.0)
	var edge: Color = C_FRAME
	var d: int = dir & 7
	if d < 4:
		var slash: bool = (d % 2) == 0
		for i in range(-6, 7):
			var x: float = float(i)
			var y: float = -x if slash else x
			draw_rect(Rect2(x, y, 1.0, 1.0), edge)
			draw_rect(Rect2(x, y - 1.0, 1.0, 1.0), stripe)
			draw_rect(Rect2(x + (1.0 if slash else -1.0), y, 1.0, 1.0), stripe.darkened(0.15))
		var mark: Vector2 = Vector2(4.0, -5.0) if slash else Vector2(4.0, 4.0)
		draw_rect(Rect2(mark.x, mark.y, 2.0, 2.0), stripe)
	else:
		# Пологая полоска: два пикселя по горизонтали на один по вертикали.
		# Ребёнок отличает 22,5° от крутой «/» без текста.
		var shallow_slash: bool = (d % 2) == 0
		for i in range(-3, 4):
			var x0: float = float(i * 2)
			var y: float = float(-i if shallow_slash else i)
			for k in 2:
				var x: float = x0 + float(k) - 0.5
				draw_rect(Rect2(x, y, 1.0, 1.0), edge)
				draw_rect(Rect2(x, y - 1.0, 1.0, 1.0), stripe)
		var mark: Vector2 = Vector2(5.0, -3.0) if shallow_slash else Vector2(5.0, 2.0)
		draw_rect(Rect2(mark.x, mark.y, 2.0, 2.0), stripe)
