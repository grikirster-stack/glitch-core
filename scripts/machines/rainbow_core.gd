class_name RainbowCore
extends MachineBase
## Радужное ядро (ADR-005 § 6.3, #175): ставится где угодно. Семь дуг живут
## в Game, не в блоке: снял и перенёс — дуги не гаснут. Луч любого чистого
## цвета, попавший в клетку, зажигает свою дугу навсегда.
##
## Активное ядро одно — последнее поставленное (Game.core_cell). Возрождение
## и удержание сигнала считают от него. Питание не нужно.

## Чистые цвета луча: R, G, B, Y, C, M, W — ровно семь. Смесь из нескольких
## битов сразу (маска не из этого списка) дугу не зажигает.
const PURE: Array[int] = [Beams.R, Beams.G, Beams.B, Beams.Y, Beams.C, Beams.M, Beams.W]
## Маска луча, упёршегося в клетку на последнем перестроении. 0 — луча нет.
var _beam: int = 0
## Дуги по верху корпуса, слева направо. Бит — индекс цвета в Game.CORE_ARC_COLOR.
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


## Маска луча, упёршегося в клетку. Каждый чистый цвет в маске — своя дуга.
func beam_receive(mask: int) -> void:
	var m: int = mask & 7
	_beam = m
	if not Net.is_authority() or m == 0:
		return
	for c in PURE:
		if (m & int(c)) == int(c):
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
	var lit: int = Game.core_arcs & 0x7F
	var full: bool = lit == 0x7F
	var pulse: float = 0.55 + 0.45 * sin(float(Time.get_ticks_msec()) * 0.006) if full else 1.0
	# Семь столбиков над корпусом, выше кольца пульса: на кадре это дуги, не пиксель.
	for i in ARC_COLORS.size():
		var col: Color = ARC_DIM
		var bit: int = 1 << Game.CORE_ARC_COLOR.find(ARC_COLORS[i])
		if (lit & bit) != 0:
			col = Beams.COLOR[ARC_COLORS[i]]
			if full:
				col = Color(col.r, col.g, col.b, pulse)
		var x: float = -10.5 + float(i) * 3.0
		draw_rect(Rect2(x, -14.0, 2.0, 6.0), col)
	if full:
		draw_rect(Rect2(-2.0, 1.0, 4.0, 3.0), Color(1.0, 1.0, 1.0, 0.35 + 0.4 * pulse))
	if Game.relay_active and cell == Game.core_cell:
		# Белая искра: сигнал уже идёт, столб рисует WorldFX.
		draw_rect(Rect2(-1.0, -8.0, 2.0, 2.0), Color.WHITE)
