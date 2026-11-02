class_name Drill
extends MachineBase
## Буровая станция: достаёт руду со дна своей шахты и выдаёт её наружу.
##
## Такт и глубина — виртуальные cycle()/reach(): глубинный бур (DeepDrill, #30)
## наследует всю логику и меняет только их и отрисовку.

const CYCLE: float = Balance.DRILL_CYCLE
const REACH: int = Balance.DRILL_REACH

var _timer: float = 0.0
var _spin: float = 0.0


func _init() -> void:
	kind = "Drill"
	z_index = 3


## Секунд полезной работы на одну единицу руды.
func cycle() -> float:
	return CYCLE


## На сколько клеток вниз достаёт бур (включительно).
func reach() -> int:
	return REACH


func _process(delta: float) -> void:
	super(delta)
	_spin += delta * (6.0 if powered else 0.6)
	if not Net.is_authority():   # СЕТЬ (ADR-002): копает хост, клиент только крутит шнек
		return
	if not powered:
		return
	_timer -= work(delta)
	if _timer <= 0.0:
		_timer = cycle()
		_harvest()


## Нижний добываемый тайл шахты в пределах reach() (до непробиваемой породы).
## Vector2i(-1, -1) — копать нечего.
func harvest_target() -> Vector2i:
	var target: Vector2i = Vector2i(-1, -1)
	for y in range(cell.y + 1, cell.y + reach() + 1):
		if y >= World.H:
			break
		var t: int = World.get_tile(cell.x, y)
		if t == IDs.T.AIR or DB.is_liquid(t):
			continue
		if DB.tile_hard(t) > 100.0:
			break
		target = Vector2i(cell.x, y)
	return target


func _harvest() -> void:
	var target: Vector2i = harvest_target()
	if target.x < 0:
		return
	var tid: int = World.get_tile_v(target)
	var drop: int = DB.tile_drop(tid)
	World.set_tile(target.x, target.y, IDs.T.AIR)
	anim = 1.0
	Sfx.play("mine", -18.0, 0.7)
	if drop != IDs.I.NONE:
		deliver(drop, 1)


func _draw() -> void:
	_draw_body(BODY, powered)
	# Окно шахты: рама, тёмный проём и шнек в нём.
	draw_rect(Rect2(-4.0, -5.0, 8.0, 9.0), C_FRAME)
	draw_rect(Rect2(-3.0, -4.0, 6.0, 7.0), C_SCREEN)
	_draw_auger(Rect2(-2.0, -4.0, 4.0, 7.0), C_METAL_HI)
	# Штанга вниз, в шахту
	_draw_auger(Rect2(-1.0, 8.0, 3.0, 6.0), C_METAL_D)
	_draw_power_lamp(Vector2(6.0, -5.0))


## Шнек: косые витки бегут вниз, пока бур крутится (_spin) — квадратами,
## без поворота спрайта.
func _draw_auger(r: Rect2, col: Color) -> void:
	draw_rect(r, C_FRAME)
	var half: float = floorf(r.size.x * 0.5)
	var ph: int = int(_spin * 2.0) % 3
	var y: float = r.position.y + float(ph)
	while y < r.end.y:
		draw_rect(Rect2(r.position.x, y, half, 1.0), col)
		if y + 1.0 < r.end.y:
			draw_rect(Rect2(r.position.x + half, y + 1.0, r.size.x - half, 1.0), col)
		y += 3.0


## Лампочка питания: бирюзовая — есть, красная — нет.
func _draw_power_lamp(at: Vector2) -> void:
	_draw_lamp(at, C_SCREEN_HI if powered else C_LAMP_OFF)


# ------------------------------------------------------------- СОХРАНЕНИЕ (#37)
## Таймер такта (глубинный бур наследует как есть).
func save_state() -> Dictionary:
	var d: Dictionary = super()
	d["timer"] = _timer
	return d


func load_state(d: Dictionary) -> void:
	super(d)
	_timer = float(d.get("timer", _timer))


# ------------------------------------------------------------- СЕТЬ (ADR-002, MP-E #90)
## Прогресс базы у бура — доля такта (1 − _timer / cycle()): сам бур поле progress не
## ведёт, клиент видит, как идёт добыча (cycle_fraction()).
func net_state() -> PackedByteArray:
	var b: PackedByteArray = super()
	b[3] = net_u8(cycle_fraction())
	return b


func apply_net_state(b: PackedByteArray) -> int:
	var o: int = super(b)
	if o < 0:
		return o
	_timer = (1.0 - progress) * cycle()
	progress = 0.0
	return o


## Доля текущего такта добычи: 0 — только начал, 1 — сейчас выдаст руду.
func cycle_fraction() -> float:
	return clampf(1.0 - _timer / maxf(cycle(), 0.001), 0.0, 1.0)
