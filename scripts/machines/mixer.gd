class_name Mixer
extends MachineBase
## Смеситель (ADR-005 § 4–5, #165): складывает цвета входящих лучей.
##
## Выход — грань dir, входы — три остальные. Луч в выходную грань гаснет.
## Цвет входа копится в inputs за проход; Beams перед каждым проходом
## вызывает beam_reset_inputs(). Выход — один луч [[dir, inputs]].
## Длину выхода считает beam_out_length: max(остаток входов) − 2,
## белый — полные BEAM_LEN_WHITE.


## Маска цветов, вошедших с входных граней за текущий проход.
var inputs: int = 0
## Смесь прошлого прохода: её и отдаём. Текущий проход ещё не видел всех входов.
var _held: int = 0
## Самый длинный бюджет входов текущего прохода и прошлого (для длины выхода).
var _best_budget: int = 0
var _held_budget: int = 0
## Последний beam_pass принял луч (не выходная грань). Бюджет пишем только тогда.
var _accepted: bool = false


func _init() -> void:
	kind = "Mixer"
	z_index = 3
	can_turn = true
	beam_passer = true


## Beams зовёт перед каждым проходом. Накопленное становится выходом,
## лист входов — чистый: все входы видны только со следующего прохода.
func beam_reset_inputs() -> void:
	_held = inputs
	_held_budget = _best_budget
	inputs = 0
	_best_budget = 0
	_accepted = false


## Вход с выходной грани гасится. Иначе цвет копится, а наружу идёт смесь
## прошлого прохода — в этом проходе ещё не все входы пришли.
func beam_pass(in_dir: int, color: int) -> Array:
	_accepted = false
	if color == 0:
		return []
	# Пришёл с грани, куда смотрит выход, — это выход, не вход.
	# Носик dir 0 рисуется вправо, а луч туда приходит с направления 2:
	# «откуда пришёл» и «куда смотрит грань» — противоположны.
	if (in_dir & 3) == ((dir + 2) & 3):
		return []
	inputs |= color & 7
	_accepted = true

	if _held == 0:
		return []
	return [[dir & 3, _held]]


## Бюджет выхода — от смеси, которую отдаём (прошлый проход), минус плата.
## Белый стартует с 32, не с бюджета входа. Текущий луч запоминаем на следующий проход.
func beam_out_budget(budget: int) -> int:
	if _accepted:
		_best_budget = maxi(_best_budget, budget)
	var base: int = Balance.BEAM_LEN_WHITE if _held == Beams.W else _held_budget
	return maxi(0, base - Balance.BEAM_BLOCK_COST)


func _on_turned() -> void:
	beam_reset_inputs()
	super()


func _draw() -> void:
	_draw_body(BODY, true, false)
	var shown: int = inputs | _held
	var mix: Color = C_SCREEN
	if shown > 0 and shown < Beams.COLOR.size():
		mix = Beams.COLOR[shown]
	# Три тёмных входа и один яркий выход цвета смеси.
	for d in 4:
		var at: Vector2 = _face(d)
		var col: Color = mix if d == (dir & 3) else C_SCREEN
		draw_rect(Rect2(at.x, at.y, 3.0, 3.0), C_FRAME)
		draw_rect(Rect2(at.x + 1.0, at.y + 1.0, 1.0, 1.0), col)
	# Сердцевина: тот же цвет, чтобы смесь читалась и сбоку.
	draw_rect(Rect2(-2.0, -2.0, 4.0, 4.0), C_FRAME)
	draw_rect(Rect2(-1.0, -1.0, 2.0, 2.0), mix)


func _face(d: int) -> Vector2:
	match d:
		0:
			return Vector2(4.0, -2.0)
		1:
			return Vector2(-2.0, 4.0)
		2:
			return Vector2(-7.0, -2.0)
		_:
			return Vector2(-2.0, -7.0)
