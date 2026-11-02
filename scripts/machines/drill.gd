class_name Drill
extends MachineBase
## Буровая станция: достаёт руду со дна своей шахты и выдаёт её наружу.

const CYCLE: float = 2.0
const REACH: int = 16

var _timer: float = 0.0
var _spin: float = 0.0


func _init() -> void:
	kind = "Drill"
	z_index = 3


func _process(delta: float) -> void:
	super(delta)
	_spin += delta * (6.0 if powered else 0.6)
	if not powered:
		return
	_timer -= work(delta)
	if _timer <= 0.0:
		_timer = CYCLE
		_harvest()


func _harvest() -> void:
	var target: Vector2i = Vector2i(-1, -1)
	for y in range(cell.y + 1, cell.y + REACH):
		if y >= World.H:
			break
		var t: int = World.get_tile(cell.x, y)
		if t == IDs.T.AIR or DB.is_liquid(t):
			continue
		if DB.tile_hard(t) > 100.0:
			break
		target = Vector2i(cell.x, y)
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
	var base: Color = Color(0.34, 0.36, 0.40) if powered else Color(0.24, 0.25, 0.28)
	draw_rect(Rect2(-8.0, -8.0, 16.0, 16.0), base)
	draw_rect(Rect2(-8.0, -8.0, 16.0, 3.0), base.lightened(0.22))
	# Сверло
	var a: float = _spin
	for i in 3:
		var ang: float = a + i * TAU / 3.0
		draw_line(Vector2.ZERO, Vector2(cos(ang), sin(ang)) * 5.0, Color(0.78, 0.80, 0.85), 2.0)
	draw_circle(Vector2.ZERO, 2.4, Color(0.55, 0.58, 0.62))
	# Стержень вниз
	draw_line(Vector2(0, 6), Vector2(0, 14), Color(0.62, 0.64, 0.68), 3.0)
	if powered:
		draw_circle(Vector2(5.0, -5.0), 1.8, Color(0.4, 1.0, 0.5))
	else:
		draw_circle(Vector2(5.0, -5.0), 1.8, Color(0.9, 0.25, 0.2))
