class_name Collector
extends MachineBase
## Коллектор (ADR-005 § 4, #166): замена солнечной панели, старый предмет остаётся.
##
## Днём, если над клеткой до y = 0 нет твёрдых тайлов, даёт белый луч длиной 32.
## Ночью и под крышей молчит. Небо проверяется раз в 0,5 с; World.set_tile
## в этом столбце пересчитывает сразу. Луч — тот же beam_emit, что у горелки.


## Как часто смотреть столбец, если set_tile не звал нас сам.
const SKY_PERIOD: float = 0.5

## Последняя проверка: над клеткой пусто до верха мира.
var sky_open: bool = false
var _sky_t: float = 0.0
var _emitting: bool = false
## Бит «светит» от хоста. На хосте не читается.
var _net_on: bool = false


func _init() -> void:
	kind = "Collector"
	z_index = 3
	can_turn = true


func _ready() -> void:
	_check_sky()


func _process(delta: float) -> void:
	super(delta)
	if not Net.is_authority():   # СЕТЬ (ADR-002): небо и день считает хост, клиент рисует по net_state
		queue_redraw()
		return
	_sky_t -= delta
	if _sky_t <= 0.0:
		_sky_t = SKY_PERIOD
		_check_sky()
	var on: bool = emitting()
	if on != _emitting:
		_emitting = on
		_mark_beam()
	_net_on = on
	queue_redraw()


## Светит ли сейчас. Хост смотрит день и столбец. Клиент — байт хоста
## (_net_on): свой daylight может отстать на такт.
func emitting() -> bool:
	if not Net.is_authority():
		return _net_on
	return sky_open and Game.daylight() >= Balance.COLLECTOR_MIN_DAYLIGHT


## Белый луч из носика. Пусто — ночь или крыша.
func beam_emit() -> Array:
	if not emitting():
		return []
	return [[dir, Beams.W, Balance.BEAM_LEN_WHITE]]


## Коллектор луч не пропускает: крышка — источник, не труба.
func beam_pass(_in_dir: int, _color: int) -> Array:
	return []


## World.set_tile в этом столбце. Чужой столбец не трогаем.
func note_column(x: int) -> void:
	if x != cell.x:
		return
	_check_sky()


func _check_sky() -> void:
	var open: bool = true
	if not World.in_bounds(cell.x, cell.y):
		open = false
	else:
		for y in range(0, cell.y):
			if DB.tile_solid(World.get_tile(cell.x, y)):
				open = false
				break
	if open == sky_open:
		return
	sky_open = open
	var on: bool = emitting()
	if on != _emitting:
		_emitting = on
		_mark_beam()
	queue_redraw()


func _on_turned() -> void:
	super()
	queue_redraw()


func _mark_beam() -> void:
	if World.beams != null:
		World.beams.mark_dirty()


func _draw() -> void:
	var on: bool = emitting()
	# Стеклянная крышка на кремовой стойке. Днём — квадратное солнце, как у панели.
	draw_rect(Rect2(-7.0, -6.0, 14.0, 6.0), C_FRAME)
	var glass: Color = Color(0.78, 0.90, 0.96) if on else C_SCREEN
	draw_rect(Rect2(-6.0, -5.0, 12.0, 4.0), glass)
	draw_rect(Rect2(-6.0, -5.0, 3.0, 1.0), glass.lightened(0.25))
	draw_rect(Rect2(-1.0, 0.0, 2.0, 3.0), C_METAL_D)
	_draw_body(Rect2(-6.0, 3.0, 12.0, 5.0), true, false)
	_draw_nozzle()
	if on:
		draw_rect(Rect2(-1.0, -11.0, 3.0, 3.0), C_LAVA_HI)


func _draw_nozzle() -> void:
	var tip: Rect2 = Rect2(6.0, -1.0, 3.0, 3.0)
	match dir & 3:
		1:
			tip = Rect2(-1.0, 7.0, 3.0, 2.0)
		2:
			tip = Rect2(-9.0, -1.0, 3.0, 3.0)
		3:
			tip = Rect2(-1.0, -8.0, 3.0, 2.0)
	draw_rect(tip, C_METAL_D)
	draw_rect(tip.grow(-1.0), Beams.COLOR[Beams.W] if emitting() else C_FRAME)


# ------------------------------------------------------------- СОХРАНЕНИЕ (#37)
## Небо не пишем: после загрузки столбец тот же, _ready пересчитает.
func save_state() -> Dictionary:
	var d: Dictionary = super()
	d["dir"] = dir
	return d


# ------------------------------------------------------------- СЕТЬ (ADR-002)
## Байт: бит 0 — светит. День и небо клиент не пересчитывает: луч детерминирован
## по этому биту, как «горит» у горелки.
func net_state() -> PackedByteArray:
	var b: PackedByteArray = super()
	b.append(1 if emitting() else 0)
	return b


func apply_net_state(b: PackedByteArray) -> int:
	var o: int = super(b)
	if o < 0 or b.size() < o + 1:
		return -1
	var was: bool = emitting()
	_net_on = (int(b[o]) & 1) != 0
	sky_open = _net_on
	_emitting = _net_on
	if emitting() != was:
		_mark_beam()
	queue_redraw()
	return o + 1
