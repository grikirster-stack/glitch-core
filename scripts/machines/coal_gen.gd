class_name CoalGen
extends Generator
## Угольная ТЭЦ: жжёт уголь и даёт энергию в радиусе.

const BURN: float = 45.0   ## секунд горения одной единицы угля
const FUEL_VALUE: int = 1

var fuel: float = 0.0


func _init() -> void:
	kind = "CoalGen"
	power_radius = 8.0


func _process(delta: float) -> void:
	super(delta)
	if fuel > 0.0:
		fuel = maxf(0.0, fuel - delta)
	power_active = fuel > 0.0
	queue_redraw()


func add_fuel(count: int) -> int:
	var added: int = 0
	for i in count:
		fuel = minf(fuel + BURN, BURN * 12.0)
		added += 1
	return added


func _draw() -> void:
	var hot: bool = fuel > 0.0
	var base: Color = Color(0.30, 0.30, 0.34)
	draw_rect(Rect2(-8.0, -8.0, 16.0, 16.0), base)
	draw_rect(Rect2(-8.0, -8.0, 16.0, 2.0), base.lightened(0.2))
	# Топка
	var glow: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.01)
	var c: Color = Color(0.95, 0.45, 0.12) if hot else Color(0.22, 0.20, 0.20)
	if hot:
		c = c.lerp(Color(1.0, 0.85, 0.4), glow * 0.5)
	draw_rect(Rect2(-5.0, 0.0, 10.0, 6.0), c)
	# Труба
	draw_rect(Rect2(4.0, -8.0, 3.0, 9.0), Color(0.38, 0.40, 0.44))
	if hot:
		draw_circle(Vector2(-5.0, -5.0), 1.8, Color(0.4, 1.0, 0.5))
		# Индикатор топлива
		draw_rect(Rect2(-8.0, -13.0, 16.0, 2.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-8.0, -13.0, 16.0 * clampf(fuel / BURN, 0.0, 1.0), 2.0), Color(1.0, 0.7, 0.2))
