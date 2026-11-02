class_name Floodlight
extends MachineBase
## Прожектор (ADR-001 § 4.4, #31): яркий свет от сети.
##
## Тянет Balance.POWER_DRAW["Floodlight"]. Пока запитан и efficiency не ниже
## Balance.FLOODLIGHT_MIN_EFF — светит силой Balance.FLOODLIGHT_POWER (≈ 10
## клеток) через публичный World.add_light_source. При просадке сети или без
## питания гаснет. Эхо и копатель от такого света убегают; тень идёт его бить.

var lit: bool = false
var _light: Dictionary = {}


func _init() -> void:
	kind = "Floodlight"
	z_index = 3


## Радиус света — по той же формуле, что у светящихся тайлов.
static func light_radius() -> float:
	return World.LIGHT_BASE_RADIUS + Balance.FLOODLIGHT_POWER * World.LIGHT_RADIUS_PER_POWER


func _process(delta: float) -> void:
	super(delta)
	var want: bool = powered and efficiency >= Balance.FLOODLIGHT_MIN_EFF and not _destroyed
	if want != lit:
		_set_lit(want)


func _set_lit(on: bool) -> void:
	lit = on
	if on:
		_light = World.add_light_source(global_position, light_radius(), Balance.FLOODLIGHT_POWER)
	else:
		World.remove_light_source(_light)
		_light = {}
	queue_redraw()


func _on_destroyed() -> void:
	if lit:
		_set_lit(false)


func _exit_tree() -> void:
	if lit:
		_set_lit(false)


func _draw() -> void:
	var base: Color = Color(0.36, 0.38, 0.42) if powered else Color(0.25, 0.26, 0.29)
	# Стойка и основание
	draw_rect(Rect2(-6.0, 5.0, 12.0, 3.0), base.darkened(0.2))
	draw_rect(Rect2(-1.5, -1.0, 3.0, 6.0), base)
	# Корпус фары
	draw_rect(Rect2(-7.0, -8.0, 14.0, 8.0), base)
	draw_rect(Rect2(-7.0, -8.0, 14.0, 1.5), base.lightened(0.22))
	# Линза: тёплая, когда светит
	var lens: Color = Color(1.0, 0.94, 0.62) if lit else Color(0.30, 0.31, 0.30)
	draw_rect(Rect2(-5.5, -6.5, 11.0, 5.0), lens)
	if lit:
		draw_rect(Rect2(-4.5, -5.5, 3.0, 2.0), Color(1.0, 1.0, 0.9))
		draw_circle(Vector2(0.0, -4.0), 9.0, Color(1.0, 0.9, 0.55, 0.12))
	# Лампочка питания
	var lamp: Color = Color(0.9, 0.25, 0.2)
	if powered:
		lamp = Color(0.4, 1.0, 0.5) if lit else Color(1.0, 0.8, 0.2)
	draw_circle(Vector2(5.0, 6.5), 1.3, lamp)
