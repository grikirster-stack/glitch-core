class_name WorldFX
extends Node2D
## Мировые эффекты: частицы, кольца импульса, вентиляция, оверлей питания, свечение.
##
## Оптимизации (issue #3):
##  * источники света отсекаются по прямоугольнику камеры и ограничены MAX_GLOWS;
##  * перерисовка ленивая: каждый кадр — только при живых эффектах или движении
##    камеры, в покое — не чаще REDRAW_HZ (пульс релея не «встаёт колом»);
##  * частицы/кольца/взмахи имеют жёсткие лимиты, самые старые вытесняются.

# ------------------------------------------------------------ ЛИМИТЫ
## Максимум источников света, нарисованных за один кадр. В мире их тысячи,
## но в кадре камеры (с запасом GLOW_MARGIN радиуса) их десятки. Если в камере
## больше — рисуем ближайшие к центру камеры.
const MAX_GLOWS: int = 48
## Максимум живых частиц. При переполнении вытесняются самые старые.
const MAX_CHIPS: int = 160
## Максимум живых колец импульса.
const MAX_RINGS: int = 48
## Максимум живых взмахов.
const MAX_SLASHES: int = 32
## Максимум кругов оверлея питания за кадр.
const MAX_POWER_RINGS: int = 32

# ------------------------------------------------- ПАРАМЕТРЫ ОТСЕЧЕНИЯ
## Запас вокруг видимой области камеры в долях радиуса источника света.
const GLOW_MARGIN: float = 1.5
## Консервативная верхняя граница радиуса источника света — для прямоугольника
## запроса (нужен, когда World.get_lights_near ещё не появился).
const MAX_LIGHT_RADIUS: float = 128.0
## Частота перерисовки в покое, Гц. Нужна только для анимации пульса релея:
## период пульса ~2.1 с, шаг радиуса при 25 Гц — доли пикселя, «колом» не стоит.
const REDRAW_HZ: float = 25.0
const REDRAW_INTERVAL: float = 1.0 / REDRAW_HZ
## Ключ запуска для замеров: godot --path . -- --fx-stats
## Печатает раз в 2 с счётчики света и живых эффектов.
const STATS_FLAG: String = "--fx-stats"
const STATS_INTERVAL: float = 2.0

# ------------------------------------------------------------ СОСТОЯНИЕ
var chips: Array = []
var rings: Array = []
var slashes: Array = []

var show_power: bool = false:
	set(value):
		if show_power == value:
			return
		show_power = value
		_dirty = true

var light_overlay: bool = true:
	set(value):
		if light_overlay == value:
			return
		light_overlay = value
		_dirty = true

# ---------------------------------------------- СЧЁТЧИКИ (для замеров)
## Сколько источников света нарисовано в последнем кадре.
var glows_drawn: int = 0
## Пиковые значения за сессию — для отчёта о лимитах.
var peak_glows: int = 0
var peak_chips: int = 0
var peak_rings: int = 0
var peak_slashes: int = 0

# ------------------------------------------------------------ ВНУТРЕННЕЕ
var _dirty: bool = true
var _pulse_clock: float = 0.0
var _have_cam: bool = false
var _last_cam_center: Vector2 = Vector2.ZERO
var _last_cam_zoom: Vector2 = Vector2.ONE
var _last_light_count: int = -1
var _stats_on: bool = false
var _stats_t: float = 0.0
var _redraws: int = 0


func _ready() -> void:
	z_index = 20
	queue_redraw()
	_stats_on = OS.get_cmdline_user_args().has(STATS_FLAG)


func _process(delta: float) -> void:
	# Живые эффекты требуют покадровой перерисовки — иначе движение дёргается.
	var animating: bool = _advance_effects(delta)
	var cam: Camera2D = get_viewport().get_camera_2d()
	if _camera_changed(cam):
		_dirty = true
	if World.lights.size() != _last_light_count:
		_last_light_count = World.lights.size()
		_dirty = true
	if animating:
		_dirty = true
	else:
		# ПОКОЙ: перерисовываем не чаще REDRAW_HZ и только если пульс релея
		# реально виден в кадре.
		_pulse_clock += delta
		if _pulse_clock >= REDRAW_INTERVAL:
			_pulse_clock = 0.0
			if _beacon_visible(cam):
				_dirty = true
	if _dirty:
		_dirty = false
		queue_redraw()
	if _stats_on:
		_stats_t += delta
		if _stats_t >= STATS_INTERVAL:
			_stats_t = 0.0
			print("FXSTATS: свет_в_мире=%d нарисовано_за_кадр=%d/%d частиц=%d/%d колец=%d/%d взмахов=%d/%d перерисовок_в_сек=%.1f" % [
				World.lights.size(), glows_drawn, MAX_GLOWS,
				chips.size(), MAX_CHIPS, rings.size(), MAX_RINGS,
				slashes.size(), MAX_SLASHES, float(_redraws) / STATS_INTERVAL])
			_redraws = 0


## Обновляет частицы/кольца/взмахи. Возвращает true, если что-то ещё живо.
func _advance_effects(delta: float) -> bool:
	# Обход с конца: remove_at(i) не сдвигает элементы с меньшими индексами,
	# поэтому индексы ниже i остаются валидными.
	var i: int = chips.size() - 1
	while i >= 0:
		var c: Dictionary = chips[i]
		c["vel"] = Vector2(c["vel"]) + Vector2(0.0, 520.0) * delta
		c["pos"] = Vector2(c["pos"]) + Vector2(c["vel"]) * delta
		c["life"] = float(c["life"]) - delta
		if float(c["life"]) <= 0.0:
			chips.remove_at(i)
		i -= 1
	i = rings.size() - 1
	while i >= 0:
		var r: Dictionary = rings[i]
		r["t"] = float(r["t"]) + delta
		if float(r["t"]) > 0.7:
			rings.remove_at(i)
		i -= 1
	i = slashes.size() - 1
	while i >= 0:
		var s: Dictionary = slashes[i]
		s["t"] = float(s["t"]) + delta
		if float(s["t"]) > 0.22:
			slashes.remove_at(i)
		i -= 1
	return not chips.is_empty() or not rings.is_empty() or not slashes.is_empty()


## Следит за камерой: сдвиг/зум/появление и исчезновение камеры — повод перерисовать.
func _camera_changed(cam: Camera2D) -> bool:
	if cam == null:
		var had: bool = _have_cam
		_have_cam = false
		return had
	var center: Vector2 = cam.get_screen_center_position()
	var zoom: Vector2 = cam.zoom
	if not _have_cam:
		_have_cam = true
		_last_cam_center = center
		_last_cam_zoom = zoom
		return true
	if center.distance_squared_to(_last_cam_center) > 0.25 or zoom != _last_cam_zoom:
		_last_cam_center = center
		_last_cam_zoom = zoom
		return true
	return false


## Виден ли релей (пульс которого анимируется по времени) в кадре.
func _beacon_visible(cam: Camera2D) -> bool:
	if cam == null:
		return false
	return _view_rect(cam).has_point(World.cell_to_world(World.beacon_cell))


## Прямоугольник мира, видимый камерой. Пустой Rect2 — камеры нет.
func _view_rect(cam: Camera2D) -> Rect2:
	if cam == null:
		return Rect2()
	var vp: Viewport = get_viewport()
	# Канвас-трансформ вьюпорта несёт и зум камеры, и он же задаёт систему
	# координат, в которой живёт get_visible_rect() — отменяем только его.
	var to_world: Transform2D = vp.get_canvas_transform().affine_inverse()
	var vr: Rect2 = vp.get_visible_rect()
	var tl: Vector2 = to_world * vr.position
	var br: Vector2 = to_world * (vr.position + vr.size)
	return Rect2(tl, br - tl).abs()


# ------------------------------------------------------------ ЭФФЕКТЫ

func spawn_chip(cell: Vector2i, color: Color) -> void:
	var base: Vector2 = World.cell_to_world(cell)
	# Вытесняем самые старые частицы, если лимит превышен.
	var overflow: int = chips.size() + 4 - MAX_CHIPS
	for i in maxi(0, overflow):
		if chips.is_empty():
			break
		chips.remove_at(0)
	for i in 4:
		chips.append({
			"pos": base + Vector2(randf_range(-5.0, 5.0), randf_range(-5.0, 5.0)),
			"vel": Vector2(randf_range(-70.0, 70.0), randf_range(-140.0, -50.0)),
			"life": randf_range(0.25, 0.55),
			"color": color,
			"size": randf_range(1.5, 3.0),
		})
	peak_chips = maxi(peak_chips, chips.size())


func spawn_ring(pos: Vector2, color: Color) -> void:
	if rings.size() >= MAX_RINGS:
		rings.remove_at(0)
	rings.append({"pos": pos, "t": 0.0, "color": color})
	peak_rings = maxi(peak_rings, rings.size())


func spawn_slash(pos: Vector2) -> void:
	if slashes.size() >= MAX_SLASHES:
		slashes.remove_at(0)
	slashes.append({"pos": pos, "t": 0.0})
	peak_slashes = maxi(peak_slashes, slashes.size())


# ------------------------------------------------------------ ОТРИСОВКА

func _draw() -> void:
	_redraws += 1
	var cam: Camera2D = get_viewport().get_camera_2d()
	var view: Rect2 = _view_rect(cam)

	# --- Свечение источников света ------------------------------------------
	if light_overlay and DB.glow_texture:
		_draw_glows(cam, view)

	# --- Вентиляция -----------------------------------------------------------
	for v in World.vents:
		var p: Vector2 = World.cell_to_world(v)
		if view.size != Vector2.ZERO and not view.grow(8.0).has_point(p):
			continue
		draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), Color(0.18, 0.20, 0.24, 0.9))
		draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), Color(0.45, 0.55, 0.65, 0.8), false, 1.0)
		for i in 3:
			draw_line(Vector2(p.x - 4 + i * 4, p.y - 4), Vector2(p.x - 4 + i * 4, p.y + 4), Color(0.35, 0.42, 0.5), 1.0)

	# --- Оверлей питания ------------------------------------------------------
	if show_power:
		_draw_power(view)

	# --- Релей ----------------------------------------------------------------
	var bp: Vector2 = World.cell_to_world(World.beacon_cell)
	var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.003)
	draw_arc(bp, 10.0 + pulse * 3.0, 0.0, TAU, 28, Color(0.3, 0.95, 1.0, 0.5), 2.0)

	# --- Частицы --------------------------------------------------------------
	for c in chips:
		var life: float = float(c["life"]) / 0.55
		draw_rect(Rect2(Vector2(c["pos"]), Vector2(c["size"], c["size"])),
				Color(c["color"].r, c["color"].g, c["color"].b, clampf(life, 0.0, 1.0)))

	# --- Кольца ---------------------------------------------------------------
	for r in rings:
		var t: float = float(r["t"]) / 0.7
		draw_arc(Vector2(r["pos"]), 10.0 + t * 120.0, 0.0, TAU, 40,
				Color(r["color"].r, r["color"].g, r["color"].b, (1.0 - t) * 0.8), 3.0)

	# --- Взмах ---------------------------------------------------------------
	for s in slashes:
		var t2: float = float(s["t"]) / 0.22
		var col2: Color = Color(1, 1, 1, 1.0 - t2)
		draw_arc(Vector2(s["pos"]), 14.0 + t2 * 8.0, -0.9 + t2 * 1.8, 0.9 + t2 * 1.8, 12, col2, 3.0)


## Рисует не больше MAX_GLOWS источников света, попадающих в кадр камеры.
## Если камеры нет — свет не рисуем вовсе.
func _draw_glows(cam: Camera2D, view: Rect2) -> void:
	glows_drawn = 0
	if cam == null or view.size == Vector2.ZERO:
		return
	# Запрос с запасом, чтобы поймать источники, чьё свечение заходит в кадр.
	var query: Rect2 = view.grow(GLOW_MARGIN * MAX_LIGHT_RADIUS)
	var lights: Array = World.get_lights_near(query) if World.has_method("get_lights_near") else World.lights
	var center: Vector2 = cam.get_screen_center_position()
	var cands: Array = []
	for l in lights:
		if not (l is Dictionary):
			continue
		var lp: Vector2 = l["pos"]
		var lr: float = float(l["radius"])
		# Источник считается видимым, если его свечение (с запасом) касается кадра.
		if not view.grow(GLOW_MARGIN * lr).has_point(lp):
			continue
		cands.append(l)
	if cands.size() > MAX_GLOWS:
		cands.sort_custom(func(a, b): return _light_dist2(a, center) < _light_dist2(b, center))
		cands = cands.slice(0, MAX_GLOWS)
	for l in cands:
		var lp: Vector2 = l["pos"]
		var lr: float = float(l["radius"])
		var col: Color = Color(1.0, 0.92, 0.70, float(l["power"]) * 0.55)
		draw_texture_rect(DB.glow_texture, Rect2(lp - Vector2(lr, lr) * 0.9,
				Vector2(lr, lr) * 1.8), false, col)
	glows_drawn = cands.size()
	peak_glows = maxi(peak_glows, glows_drawn)


## Квадратичное расстояние от источника света до центра камеры (для отбора).
func _light_dist2(l: Dictionary, center: Vector2) -> float:
	return (Vector2(l["pos"]) - center).length_squared()


## Оверлей питания: только генераторы, попадающие в кадр камеры.
func _draw_power(view: Rect2) -> void:
	var drawn: int = 0
	for m in World.machines.values():
		if not (m is Generator):
			continue
		if drawn >= MAX_POWER_RINGS:
			break
		var pos: Vector2 = m.global_position
		var r: float = m.power_radius * World.TILE
		if r <= 0.0:
			continue
		if view.size != Vector2.ZERO and not view.grow(r).has_point(pos):
			continue
		drawn += 1
		var col: Color = Color(1.0, 0.85, 0.25, 0.16) if m.power_active else Color(0.5, 0.5, 0.55, 0.10)
		draw_circle(pos, r, col)
		draw_arc(pos, r, 0.0, TAU, 48, Color(col.r, col.g, col.b, 0.6), 1.5)
