class_name SkyBackdrop
extends CanvasLayer
## Фон: градиент неба, солнце/луна, звёзды. Живёт в отдельном слое и не смещается камерой.
##
## Оптимизации (issue #7) — небо фон, оно не должно стоить кадра:
##  * три слоя: градиент, звёзды, светило. Каждый перерисовывается сам по себе;
##  * градиент перерисовывается, только когда его цвета сменились хотя бы на
##    1/255 (сверка раз в GRADIENT_CHECK_SEC) или изменился размер экрана;
##  * звёзды мерцают с частотой STAR_HZ и только ночью; днём слой скрыт;
##  * солнце/луна рисуются один раз в начале координат своего слоя, а по дуге
##    ходит позиция слоя — движение плавное каждый кадр без перерисовки.
##    Перерисовка светила — только при смене яркости (шаг 1/64) или день↔ночь.

const GRADIENT_CHECK_SEC: float = 0.25
const STAR_HZ: float = 12.0
const BANDS: int = 48

var _view: Control = null       ## градиент
var _star_view: Control = null  ## звёзды
var _orb: Control = null        ## солнце/луна (рисуется в своих координатах)
var _stars: Array[Vector3] = []      ## x, y, яркость

var _top: Color = Color.BLACK
var _hor: Color = Color.BLACK
var _grad_key: Vector3i = Vector3i(-1, -1, -1)
var _grad_t: float = 0.0
var _star_t: float = 0.0
var _star_a: float = 0.0
var _orb_key: int = -1

# ---------------------------------------------- СЧЁТЧИКИ (для замеров)
## Время в _process и всех _draw слоёв неба, мкс (tools/hud_probe.gd).
var stat_us: int = 0
var stat_frames: int = 0
var stat_redraws: int = 0


func _ready() -> void:
	layer = -100
	_view = _make_layer(_on_draw)
	_star_view = _make_layer(_on_draw_stars)
	_orb = Control.new()
	_orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_orb.draw.connect(_on_draw_orb)
	add_child(_orb)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 777
	for i in 140:
		_stars.append(Vector3(rng.randf(), rng.randf() * 0.72, rng.randf_range(0.25, 1.0)))


func _make_layer(cb: Callable) -> Control:
	var c: Control = Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(cb)
	add_child(c)
	return c


func _process(delta: float) -> void:
	if _view == null:
		return
	var t0: int = Time.get_ticks_usec()
	stat_frames += 1
	var w: float = _view.size.x
	var h: float = _view.size.y
	var t: float = Game.time_of_day
	var dl: float = Game.daylight()

	# Градиент: сверяем цвета в 8-битной точности, перерисовываем при отличии.
	_grad_t -= delta
	if _grad_t <= 0.0:
		_grad_t = GRADIENT_CHECK_SEC
		_sky_colors(dl)
		var k: Vector3i = Vector3i(_top.to_rgba32(), _hor.to_rgba32(), int(w) * 65536 + int(h))
		if k != _grad_key:
			_grad_key = k
			_view.queue_redraw()

	# Звёзды (только ночью), мерцание — STAR_HZ раз в секунду.
	_star_a = clampf(1.0 - dl * 1.6, 0.0, 1.0)
	var stars_on: bool = _star_a > 0.02
	if _star_view.visible != stars_on:
		_star_view.visible = stars_on
		_star_t = 0.0
	if stars_on:
		_star_t -= delta
		if _star_t <= 0.0:
			_star_t = 1.0 / STAR_HZ
			_star_view.queue_redraw()

	# Светило: двигаем слой, а не перерисовываем.
	var ang: float = PI + t * TAU
	_orb.position = Vector2(w * 0.5 + cos(ang) * w * 0.42, h * 0.62 - sin(ang) * h * 0.52)
	var ok: int = int(dl * 64.0) if dl > 0.02 else -2
	if ok != _orb_key:
		_orb_key = ok
		_orb.queue_redraw()
	stat_us += Time.get_ticks_usec() - t0


## Цвета неба по времени суток → _top, _hor.
func _sky_colors(dl: float) -> void:
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

	_top = top_night.lerp(top_day, dl).lerp(top_dusk, dusk * 0.85)
	_hor = hor_night.lerp(hor_day, dl).lerp(hor_dusk, dusk * 0.85)


func _on_draw() -> void:
	var t0: int = Time.get_ticks_usec()
	stat_redraws += 1
	var c: Control = _view
	var w: float = c.size.x
	var h: float = c.size.y
	# Градиент полосами
	for i in BANDS:
		var f: float = float(i) / float(BANDS - 1)
		var col: Color = _top.lerp(_hor, pow(f, 0.75))
		c.draw_rect(Rect2(0.0, h * float(i) / float(BANDS), w, h / float(BANDS) + 1.0), col)
	stat_us += Time.get_ticks_usec() - t0


func _on_draw_stars() -> void:
	var t0: int = Time.get_ticks_usec()
	stat_redraws += 1
	var c: Control = _star_view
	var w: float = c.size.x
	var h: float = c.size.y
	var now: float = Time.get_ticks_msec() * 0.001
	for s in _stars:
		var p: Vector2 = Vector2(s.x * w, s.y * h)
		var tw: float = 0.65 + 0.35 * sin(now * (1.0 + s.z) + s.x * 30.0)
		c.draw_circle(p, 0.8 + s.z * 1.4, Color(1.0, 0.98, 0.92, _star_a * s.z * tw))
	stat_us += Time.get_ticks_usec() - t0


## Солнце и луна — в координатах слоя _orb (центр светила в нуле).
func _on_draw_orb() -> void:
	stat_redraws += 1
	var c: Control = _orb
	var dl: float = Game.daylight()
	if dl > 0.02:
		c.draw_circle(Vector2.ZERO, 26.0, Color(1.0, 0.88, 0.45, 0.20 * dl))
		c.draw_circle(Vector2.ZERO, 15.0, Color(1.0, 0.94, 0.62, 0.9 * dl))
	else:
		c.draw_circle(Vector2.ZERO, 20.0, Color(0.75, 0.82, 1.0, 0.12))
		c.draw_circle(Vector2.ZERO, 11.0, Color(0.88, 0.92, 1.0, 0.9))
		c.draw_circle(Vector2(-3, -3), 3.0, Color(0.75, 0.80, 0.95, 0.8))
