class_name Floodlight
extends MachineBase
## Прожектор (ADR-001 § 4.4, #31): яркий свет от сети.
##
## Тянет Balance.POWER_DRAW["Floodlight"]. Пока запитан и efficiency не ниже
## Balance.FLOODLIGHT_MIN_EFF — светит силой Balance.FLOODLIGHT_POWER (≈ 10
## клеток) через публичный World.add_light_source. При просадке сети или без
## питания гаснет. Эхо и копатель от такого света убегают; тень идёт его бить.

## Линза, когда светит, — тёплый свет фонаря (`lamp` концепта ADR-003, в DB.PAL его нет).
const LENS_LIT: Color = Color("#FFE7A0")

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
	# Основание с разметкой и стойка
	_draw_body(Rect2(-6.0, 5.0, 12.0, 3.0), powered, false)
	draw_rect(Rect2(-5.0, 6.0, 2.0, 1.0), C_HAZARD)
	draw_rect(Rect2(-1.0, -1.0, 2.0, 6.0), C_METAL_D)
	# Корпус фары — кремовый короб в раме
	_draw_body(Rect2(-7.0, -8.0, 14.0, 8.0), powered, false)
	# Линза: тёплый свет фонаря, когда светит; без света — тёмное стекло
	draw_rect(Rect2(-6.0, -6.0, 12.0, 5.0), C_FRAME)
	draw_rect(Rect2(-5.0, -5.0, 10.0, 3.0), LENS_LIT if lit else C_SCREEN)
	if lit:
		draw_rect(Rect2(-4.0, -5.0, 3.0, 1.0), C_METAL_HI)
		# Ореол — квадратный, полупрозрачный
		draw_rect(Rect2(-9.0, -12.0, 18.0, 16.0), Color(LENS_LIT, 0.12))
	# Лампочка питания: бирюзовая — светит, жёлтая — питания мало, красная — нет
	var lamp: Color = C_LAMP_OFF
	if powered:
		lamp = C_SCREEN_HI if lit else C_HAZARD
	_draw_lamp(Vector2(4.0, 6.0), lamp)


# ------------------------------------------------------------- СОХРАНЕНИЕ (#37)
## Своего состояния сверх базового (hp, наработка) у прожектора нет: lit выводится
## из питания. Save сразу после постановки раскладывает питание и зовёт relight():
## свет возвращается через World.add_light_source в том же кадре, что и загрузка.
func load_state(d: Dictionary) -> void:
	super(d)
	if lit:
		_set_lit(false)


## Зажечь/погасить по текущему питанию (после загрузки — не ждать кадра).
func relight() -> void:
	var want: bool = powered and efficiency >= Balance.FLOODLIGHT_MIN_EFF and not _destroyed
	if want != lit:
		_set_lit(want)
