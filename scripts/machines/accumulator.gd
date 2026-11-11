class_name Accumulator
extends MachineBase
## Накопитель (ADR-005 § 4, #166): хранит до 120 с луча одного цвета.
##
## Выход — грань dir, входы — три остальные. Луч сквозь блок не идёт
## (beam_pass → []): иначе непонятно, что он «берёт». Цвет копится по времени,
## не по длине; чужой цвет при ненулевом запасе игнорируется.
## Отдаёт, когда за последние 0,5 с входа не было, или рубильник E стоит
## на «отдавать». При живом входе в режиме «отдавать» накопления нет.
## Шкала на блоке — цвет запаса, высота по stored/CAP.


## Сколько секунд без входа считать вход пустым.
const IDLE: float = 0.5
## Рубильник: копить, пока вход есть; отдавать, даже если вход жив.
const MODE_STORE: int = 0
const MODE_EMIT: int = 1

## Секунд луча в запасе. 0 — пуст, цвет тогда не держим.
var stored: float = 0.0
## Цвет запаса (маска Beams). 0 — пуст.
var color: int = 0
## Рубильник. STORE копит, EMIT отдаёт и при живом входе.
var mode: int = MODE_STORE

## Секунд с последнего принятого входа. Больше IDLE — вход пуст.
var _idle: float = IDLE
## Этот проход уже принял вход. Сбрасывает beam_reset_inputs.
var _fed: bool = false
## Прошлый проход принял вход: между проходами _fed уже чист.
var _fed_pass: bool = false
var _emitting: bool = false
var _interact_frame: int = -10


func _init() -> void:
	kind = "Accumulator"
	z_index = 3
	can_turn = true
	# Passer, чтобы Beams звал beam_pass. Выход пустой — сквозь блок луч не идёт.
	beam_passer = true


func _process(delta: float) -> void:
	super(delta)
	if not Net.is_authority():   # СЕТЬ (ADR-002): запас считает хост, клиент рисует по net_state
		queue_redraw()
		return
	if _fed_pass:
		_idle = 0.0
	else:
		_idle += delta
	var take: bool = _should_store()
	var give: bool = _should_emit()
	if take:
		stored = minf(stored + delta, Balance.ACCUMULATOR_CAP)
	elif give:
		stored = maxf(0.0, stored - delta)
		if stored <= 0.0:
			stored = 0.0
			color = 0
	var on: bool = give and stored > 0.0 and color != 0
	if on != _emitting:
		_emitting = on
		_mark_beam()
	queue_redraw()


## Копит: есть вход того же цвета (или запас пуст) и рубильник не на «отдавать».
func _should_store() -> bool:
	if not _fed_pass or mode == MODE_EMIT:
		return false
	return stored <= 0.0 or color == 0 or _incoming_matches()


## Отдаёт: запас есть и (вход пуст уже IDLE, или рубильник «отдавать»).
## Живой вход того же цвета в режиме «отдавать» не копит — только тратит.
## Чужой цвет в режиме «копить» запас не тратит и не растит.
func _should_emit() -> bool:
	if stored <= 0.0 or color == 0:
		return false
	if mode == MODE_EMIT:
		return true
	return _idle >= IDLE


## Вход этого прохода — того же цвета, что запас. Пустой запас принимает любой.
func _incoming_matches() -> bool:
	return color == 0 or color == _seen


## Цвет, принятый на последнем проходе. 0 — входа не было или цвет чужой.
var _seen: int = 0


## Beams зовёт перед проходом. Признак входа прошлого прохода остаётся на кадр.
func beam_reset_inputs() -> void:
	_fed_pass = _fed
	_fed = false
	_seen = 0


## Луч не проходит наружу. Входная грань запоминается, выходная — нет.
func beam_pass(in_dir: int, in_color: int) -> Array:
	var c: int = in_color & 7
	if c == 0:
		return []
	# Носик dir 0 смотрит вправо, луч туда приходит с направления 2.
	if (in_dir & 3) == ((dir + 2) & 3):
		return []
	# Чужой цвет при живом запасе не принимаем: не смешиваем и не сбрасываем.
	if stored > 0.0 and color != 0 and c != color:
		return []
	if color == 0:
		color = c
	_seen = c
	_fed = true
	return []


## Отдача: тот же луч, что у горелки, пока запас не кончился.
func beam_emit() -> Array:
	if not emitting():
		return []
	var length: int = Balance.BEAM_LEN_WHITE if color == Beams.W else Balance.BEAM_LEN
	return [[dir, color, length]]


## Луч наружу. _emitting ставит _process (и сеть): вход ещё жив — false,
## даже если запас есть. beam_emit зовут из rebuild, не из _process.
func emitting() -> bool:
	return _emitting and stored > 0.0 and color != 0


## Рубильник «отдавать». Пока вход жив, запас не растёт — только тратится.
func set_mode(next: int) -> void:
	var m: int = MODE_EMIT if next == MODE_EMIT else MODE_STORE
	if m == mode:
		return
	mode = m
	_mark_beam()
	queue_redraw()
	Sfx.play("power", -10.0, 1.0 if mode == MODE_EMIT else 0.7)
	Game.notify("Накопитель: %s" % ("отдавать" if mode == MODE_EMIT else "копить"),
			Color(0.6, 1.0, 0.6) if mode == MODE_EMIT else Color(1.0, 0.85, 0.45))


## E пустой рукой — рубильник. Вызов идёт каждый кадр, пока E зажата.
func interact(_p) -> void:
	var f: int = Engine.get_physics_frames()
	var fresh: bool = f - _interact_frame > 1
	_interact_frame = f
	if fresh:
		set_mode(MODE_STORE if mode == MODE_EMIT else MODE_EMIT)


func _on_turned() -> void:
	beam_reset_inputs()
	_idle = IDLE
	super()


func _mark_beam() -> void:
	if World.beams != null:
		World.beams.mark_dirty()


func _draw() -> void:
	_draw_body(BODY, true, false)
	# Шкала цвета запаса: снизу вверх, высота по stored/CAP.
	var gauge: Color = C_SCREEN
	if color > 0 and color < Beams.COLOR.size():
		gauge = Beams.COLOR[color]
	draw_rect(Rect2(-3.0, -5.0, 4.0, 10.0), C_SOOT)
	var h: float = roundf(10.0 * clampf(stored / Balance.ACCUMULATOR_CAP, 0.0, 1.0))
	if h > 0.0:
		draw_rect(Rect2(-3.0, 5.0 - h, 4.0, h), gauge)
	_draw_nozzle()
	# Лампа рубильника: цвет запаса — отдаёт, тёмная — копит.
	var lamp: Color = gauge if mode == MODE_EMIT and stored > 0.0 else C_SCREEN
	if mode == MODE_EMIT and stored <= 0.0:
		lamp = C_LAMP_OFF
	_draw_lamp(Vector2(4.0, -5.0), lamp)


func _draw_nozzle() -> void:
	var tip: Rect2 = Rect2(6.0, -2.0, 3.0, 4.0)
	match dir & 3:
		1:
			tip = Rect2(-2.0, 6.0, 4.0, 3.0)
		2:
			tip = Rect2(-9.0, -2.0, 3.0, 4.0)
		3:
			tip = Rect2(-2.0, -9.0, 4.0, 3.0)
	var tip_col: Color = C_FRAME
	if emitting() and color > 0 and color < Beams.COLOR.size():
		tip_col = Beams.COLOR[color]
	draw_rect(tip, C_METAL_D)
	draw_rect(tip.grow(-1.0), tip_col)


# ------------------------------------------------------------- СОХРАНЕНИЕ (#37)
func save_state() -> Dictionary:
	var d: Dictionary = super()
	d["stored"] = stored
	d["color"] = color
	d["mode"] = mode
	d["dir"] = dir
	return d


func load_state(d: Dictionary) -> void:
	super(d)
	stored = clampf(float(d.get("stored", stored)), 0.0, Balance.ACCUMULATOR_CAP)
	color = int(d.get("color", color)) & 7
	if stored <= 0.0:
		color = 0
		stored = 0.0
	mode = MODE_EMIT if int(d.get("mode", mode)) == MODE_EMIT else MODE_STORE
	# Вход после загрузки неизвестен: «копить» ждёт IDLE, «отдавать» светит сразу.
	_idle = 0.0
	_fed_pass = false
	_emitting = stored > 0.0 and color != 0 and mode == MODE_EMIT
	_mark_beam()
	queue_redraw()


# ------------------------------------------------------------- СЕТЬ (ADR-002)
## Байт запаса — доля CAP. Байт: 3 бита цвета, бит 3 — режим «отдавать»,
## бит 4 — луч сейчас наружу (вход пуст или рубильник). Клиент луч сам не
## решает: вход виден только хосту.
func net_state() -> PackedByteArray:
	var b: PackedByteArray = super()
	b.append(net_u8(stored / Balance.ACCUMULATOR_CAP))
	var pack: int = color & 7
	if mode == MODE_EMIT:
		pack |= 8
	if emitting():
		pack |= 16
	b.append(pack)
	return b


func apply_net_state(b: PackedByteArray) -> int:
	var o: int = super(b)
	if o < 0 or b.size() < o + 2:
		return -1
	var was: bool = emitting()
	var prev: int = color
	stored = float(b[o]) / 255.0 * Balance.ACCUMULATOR_CAP
	color = int(b[o + 1]) & 7
	mode = MODE_EMIT if (int(b[o + 1]) & 8) != 0 else MODE_STORE
	_emitting = (int(b[o + 1]) & 16) != 0
	if stored <= 0.01:
		stored = 0.0
		color = 0
		_emitting = false
	if emitting() != was or color != prev:
		_mark_beam()
	queue_redraw()
	return o + 2
