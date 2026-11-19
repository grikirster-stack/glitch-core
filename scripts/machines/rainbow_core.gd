class_name RainbowCore
extends MachineBase
## Радужное ядро (ADR-005 § 6.3, #175): ставится где угодно. Семь дуг живут
## в Game, не в блоке: снял и перенёс — дуги не гаснут. Луч чистого цвета,
## попавший в клетку, зажигает свою дугу навсегда. Белый — не дуга (#212):
## маска 7 равна R|G|B, но сама по себе красный, зелёный и синий не зажигает.
##
## Активное ядро одно — последнее поставленное (Game.core_cell). Возрождение
## и удержание сигнала считают от него. Питание не нужно.

## Чистые цвета, которые ядро предлагает Game. Белый входит: свободная игра
## откажется в core_feed, глава «Радуга» примет.
const PURE: Array[int] = [Beams.R, Beams.G, Beams.B, Beams.Y, Beams.C, Beams.M, Beams.W]
## Маска луча, упёршегося в клетку на последнем перестроении. 0 — луча нет.
var _beam: int = 0
## Дуги по верху корпуса, слева направо. Белый в свободной игре не рисуется
## (#212): его не зажигает ни коллектор, ни смесь.
const ARC_COLORS: Array[int] = [Beams.R, Beams.Y, Beams.G, Beams.C, Beams.B, Beams.M, Beams.W]
## Серая дуга, которую ещё не зажгли.
const ARC_DIM: Color = Color(0.42, 0.44, 0.48, 0.85)


func _init() -> void:
	kind = "RainbowCore"
	z_index = 3
	can_turn = false
	hp = Balance.CORE_HP
	max_hp = Balance.CORE_HP


func _ready() -> void:
	Game.core_note_placed(cell)


## Луч поглощается: ядро — конец линии, не труба.
func beam_pass(_in_dir: int, _color: int) -> Array:
	return []


## Маска луча, упёршегося в клетку. Дугу зажигает только точное совпадение
## с чистым цветом. Белый (7 = R|G|B) не содержит «в себе» три дуги (#212):
## иначе коллектор закрывает добычу без призмы. Призма сама режет белый на три.
func beam_receive(mask: int) -> void:
	var m: int = mask & 7
	_beam = m
	if not Net.is_authority() or m == 0:
		return
	for c in PURE:
		if m == int(c):
			Game.core_feed(int(c))
	Game.cat_beam(m, get_process_delta_time())
	queue_redraw()


## Кот выходит из ядра в первую ночь удержания (#176).
## Game зовёт cat_hatch_at сам: прямой вызов отсюда замыкает класс на класс.
func cat_hatch() -> void:
	pass


func _on_destroyed() -> void:
	Game.core_note_removed(cell)


func _exit_tree() -> void:
	Game.core_note_removed(cell)


func _draw() -> void:
	# Тёмный куб: это предмет в мире, не тайл базы.
	var body: Rect2 = Rect2(-7.0, -3.0, 14.0, 11.0)
	draw_rect(body, C_FRAME)
	draw_rect(body.grow(-1.0), C_SCREEN)
	draw_rect(Rect2(-6.0, -2.0, 12.0, 1.0), C_METAL_D)
	var marks: Array = _arc_picture()
	var full: bool = true
	for m in marks:
		if not m["lit"]:
			full = false
			break
	if marks.is_empty():
		full = false
	var pulse: float = 0.55 + 0.45 * sin(float(Time.get_ticks_msec()) * 0.006) if full else 1.0
	# Столбики и дуги — из одного массива. Белый в свободной игре не рисуется (#212).
	for m in marks:
		var col: Color = _arc_paint(m, full, pulse)
		var bx: float = m["bx"]
		draw_rect(Rect2(bx, -14.0, 2.0, 6.0), col)
		if m["lit"]:
			_draw_arc(bx, -15.0, _arc_ink(col))
	if full:
		draw_rect(Rect2(-2.0, 1.0, 4.0, 3.0), Color(1.0, 1.0, 1.0, 0.35 + 0.4 * pulse))
	if Game.relay_active and cell == Game.core_cell:
		# Белая искра: сигнал уже идёт, столб рисует WorldFX.
		draw_rect(Rect2(-1.0, -8.0, 2.0, 2.0), Color.WHITE)


## Дуга над зажжённым столбиком: три квадрата, цвет луча. Пульс — в цвете.
func _draw_arc(x: float, top: float, col: Color) -> void:
	for r in _arc_rects(x, top):
		draw_rect(r, col)


## Три квадрата дуги. Тот же набор, что рисует _draw_arc.
func _arc_rects(x: float, top: float) -> Array:
	return [
		Rect2(x, top - 2.0, 2.0, 2.0),
		Rect2(x - 1.0, top - 4.0, 2.0, 2.0),
		Rect2(x + 1.0, top - 4.0, 2.0, 2.0),
	]


## Столбики дуг: позиция, цвет и зажжён ли. Единственный расчёт —
## _draw рисует из этого массива, picture() отдаёт дугу из него же.
## Серая дуга (ARC_DIM) — не зажжена: проверка цвета это видит.
func _arc_picture() -> Array:
	var need: int = Game.arc_need()
	var lit_mask: int = Game.core_arcs & need
	var n_show: int = 0
	for c in ARC_COLORS:
		if (need & (1 << Game.CORE_ARC_COLOR.find(c))) != 0:
			n_show += 1
	var x0: float = -float(n_show) * 1.5
	var drawn: int = 0
	var out: Array = []
	for c in ARC_COLORS:
		var bit: int = 1 << Game.CORE_ARC_COLOR.find(c)
		if (need & bit) == 0:
			continue
		var on: bool = (lit_mask & bit) != 0
		var col: Color = Beams.COLOR[c] if on else ARC_DIM
		out.append({"bx": x0 + float(drawn) * 3.0, "col": col, "lit": on})
		drawn += 1
	return out


## Цвет, которым _draw красит дугу. picture() читает его же:
## серая заливка в _draw роняет проверку, а не только столбик.
func _arc_ink(col: Color) -> Color:
	return col


## Цвет столбика. Пульс полного ядра — только прозрачность, не оттенок.
func _arc_paint(m: Dictionary, full: bool, pulse: float) -> Color:
	var col: Color = m["col"]
	if m["lit"] and full:
		col = Color(col.r, col.g, col.b, pulse)
	return col


## Картинка зажжённой дуги: те же квадраты и тот же цвет, что рисует _draw.
func picture() -> Dictionary:
	for m in _arc_picture():
		if m["lit"]:
			return {"arc": _arc_rects(m["bx"], -15.0), "arc_color": _arc_ink(_arc_paint(m, false, 1.0))}
	return {"arc": [], "arc_color": ARC_DIM}
