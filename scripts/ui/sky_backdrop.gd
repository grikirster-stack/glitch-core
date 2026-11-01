class_name SkyBackdrop
extends CanvasLayer
## Фон: градиент неба, солнце/луна, звёзды. Живёт в отдельном слое и не смещается камерой.

var _view: Control = null
var _stars: Array[Vector3] = []      ## x, y, яркость
var _last_t: float = -1.0


func _ready() -> void:
	layer = -100
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_on_draw)
	add_child(_view)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 777
	for i in 140:
		_stars.append(Vector3(rng.randf(), rng.randf() * 0.72, rng.randf_range(0.25, 1.0)))


func _process(_delta: float) -> void:
	if _view:
		_view.queue_redraw()


func _on_draw() -> void:
	var c: Control = _view
	var w: float = c.size.x
	var h: float = c.size.y
	var t: float = Game.time_of_day
	var dl: float = Game.daylight()

	# Цвета неба по времени суток
	var top_day: Color = Color(0.16, 0.42, 0.78)
	var hor_day: Color = Color(0.56, 0.76, 0.94)
	var top_dusk: Color = Color(0.13, 0.09, 0.26)
	var hor_dusk: Color = Color(0.85, 0.36, 0.20)
	var top_night: Color = Color(0.02, 0.03, 0.08)
	var hor_night: Color = Color(0.06, 0.08, 0.20)

	# Сколько «заката» сейчас: максимум на границах дня и ночи.
	var dusk: float = 1.0 - absf(dl - 0.5) * 2.0
	dusk = clampf(dusk, 0.0, 1.0)
	dusk = pow(dusk, 1.6)

	var top: Color = top_night.lerp(top_day, dl)
	var hor: Color = hor_night.lerp(hor_day, dl)
	top = top.lerp(top_dusk, dusk * 0.85)
	hor = hor.lerp(hor_dusk, dusk * 0.85)

	# Градиент полосами
	var bands: int = 48
	for i in bands:
		var f: float = float(i) / float(bands - 1)
		var col: Color = top.lerp(hor, pow(f, 0.75))
		c.draw_rect(Rect2(0.0, h * float(i) / float(bands), w, h / float(bands) + 1.0), col)

	# Звёзды (только ночью)
	var star_a: float = clampf(1.0 - dl * 1.6, 0.0, 1.0)
	if star_a > 0.02:
		for s in _stars:
			var p: Vector2 = Vector2(s.x * w, s.y * h)
			var tw: float = 0.65 + 0.35 * sin(Time.get_ticks_msec() * 0.001 * (1.0 + s.z) + s.x * 30.0)
			c.draw_circle(p, 0.8 + s.z * 1.4, Color(1.0, 0.98, 0.92, star_a * s.z * tw))

	# Солнце и луна по дуге
	var ang: float = PI + t * TAU
	var orbit: Vector2 = Vector2(w * 0.5 + cos(ang) * w * 0.42, h * 0.62 - sin(ang) * h * 0.52)
	if dl > 0.02:
		c.draw_circle(orbit, 26.0, Color(1.0, 0.88, 0.45, 0.20 * dl))
		c.draw_circle(orbit, 15.0, Color(1.0, 0.94, 0.62, 0.9 * dl))
	else:
		c.draw_circle(orbit, 20.0, Color(0.75, 0.82, 1.0, 0.12))
		c.draw_circle(orbit, 11.0, Color(0.88, 0.92, 1.0, 0.9))
		c.draw_circle(orbit + Vector2(-3, -3), 3.0, Color(0.75, 0.80, 0.95, 0.8))
