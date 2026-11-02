class_name FogLayer
extends Node2D
## Туман войны в мире (#59): неисследованное — чёрное, исследованное вне обзора —
## затемнено на Balance.FOG_DIM, в круге обзора вокруг героя тумана нет.
##
## Как устроено дёшево:
##  * карта тумана — чанки CHUNK×CHUNK клеток, у каждого своя крошечная текстура
##    L8 (клетка = тексель, 255 — исследовано). Текстуры растягиваются на мир
##    с линейной фильтрацией — край тумана мягкий, в клетку шириной. У чанка
##    поле в один тексель с соседями (APRON): фильтрация на стыке чанков берёт
##    тот же тексель, что и сосед, — швов нет;
##  * открытие клеток приходит сигналом World.explored_changed: правим байты
##    только новых клеток (World.explore_new) и заливаем на GPU только задетые
##    чанки (обычно 1–2 по 1,1 КБ). Мир целиком не перебирается никогда, кроме
##    пересборки по сигналу explored_reset (там пустые ряды чанка пропускаются
##    одной нативной проверкой);
##  * круг обзора считает шейдер по расстоянию до героя: позиция героя — uniform,
##    её смена не требует перерисовки узла;
##  * рисуются только чанки в кадре камеры (как отсечение света в WorldFX, #13);
##    узел перерисовывается, только когда сменился набор чанков в кадре.

const CHUNK: int = 32
const APRON: int = 1
const IMG: int = CHUNK + APRON * 2
const IMG_BYTES: int = IMG * IMG
## Скорость, с которой круг обзора догоняет новый радиус (поверхность ↔ шахта), 1/с.
const RADIUS_LERP: float = 6.0

const SHADER_CODE: String = """
shader_type canvas_item;
uniform vec2 hero = vec2(0.0);
uniform float vis_near = 80.0;
uniform float vis_far = 128.0;
uniform float dim = 0.55;
varying vec2 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}
void fragment() {
	float seen = texture(TEXTURE, UV).r;
	float shade = dim * smoothstep(vis_near, vis_far, distance(wpos, hero));
	COLOR = vec4(0.0, 0.0, 0.0, mix(1.0, shade, seen));
}
"""

# ---------------------------------------------- СЧЁТЧИКИ (для замеров)
## Время в _process и _draw, мкс; без учёта открытия (оно в World.explore_us).
var stat_us: int = 0
var stat_frames: int = 0
var stat_redraws: int = 0
## Сколько раз чанк залит на GPU.
var stat_uploads: int = 0
## Сколько чанков нарисовано в последнем кадре.
var chunks_drawn: int = 0

# ------------------------------------------------------------ ВНУТРЕННЕЕ
var _cx: int = 0                       # чанков по ширине
var _cy: int = 0                       # чанков по высоте
var _buf: PackedByteArray = PackedByteArray()   # байты всех чанков подряд
var _texs: Array[ImageTexture] = []
var _dirty: PackedByteArray = PackedByteArray()
var _dirty_list: PackedInt32Array = PackedInt32Array()
var _img: Image = null
var _range: Rect2i = Rect2i(0, 0, -1, -1)       # чанки в кадре при прошлой отрисовке
var _hero: Vector2 = Vector2(INF, INF)
var _radius: float = -1.0
var _target: float = -1.0
var _last_ct: Transform2D = Transform2D(0.0, Vector2(INF, INF))
var _mat: ShaderMaterial = null


func _ready() -> void:
	z_index = 30    # поверх построек, фантомов и WorldFX (20)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var sh: Shader = Shader.new()
	sh.code = SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("dim", Balance.FOG_DIM)
	material = _mat
	_cx = (World.W + CHUNK - 1) / CHUNK
	_cy = (World.H + CHUNK - 1) / CHUNK
	_buf.resize(_cx * _cy * IMG_BYTES)
	_dirty.resize(_cx * _cy)
	_img = Image.create_empty(IMG, IMG, false, Image.FORMAT_L8)
	for i in _cx * _cy:
		_texs.append(ImageTexture.create_from_image(_img))
	World.explored_changed.connect(_on_explored)
	World.explored_reset.connect(_rebuild)
	_rebuild()


## Полная пересборка из World.explored: новый мир, загрузка, первый кадр.
func _rebuild() -> void:
	_buf.fill(0)
	for i in _cx * _cy:
		_mark(i)
	if World.explore_cells > 0:
		_apply_rect(Rect2i(0, 0, World.W, World.H))


## Открылись клетки: переносим в байты чанков только новые (World.explore_new).
## Новая клетка всегда была закрыта, поэтому пишем без проверки; клетка на краю
## чанка дублируется в поле соседа. Горячий цикл — без вызовов функций.
func _on_explored(_rect: Rect2i) -> void:
	var ww: int = World.W
	var last: int = -1
	for idx in World.explore_new:
		var x: int = idx % ww
		var y: int = idx / ww
		var lx: int = x % CHUNK
		var ly: int = y % CHUNK
		var ci: int = (y / CHUNK) * _cx + x / CHUNK
		_buf[ci * IMG_BYTES + (ly + APRON) * IMG + lx + APRON] = 255
		if ci != last:
			last = ci
			_mark(ci)
		if lx == 0 or lx == CHUNK - 1 or ly == 0 or ly == CHUNK - 1:
			_put_neighbors(x / CHUNK, y / CHUNK, lx, ly)


func _put(cx: int, cy: int, tx: int, ty: int) -> void:
	var ci: int = cy * _cx + cx
	var i: int = ci * IMG_BYTES + ty * IMG + tx
	if _buf[i] == 0:
		_buf[i] = 255
		_mark(ci)


## Клетка на краю чанка (lx, ly — в клетках чанка): копия в поля соседей.
func _put_neighbors(cx: int, cy: int, lx: int, ly: int) -> void:
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var nx: int = cx + dx
			var ny: int = cy + dy
			if nx < 0 or ny < 0 or nx >= _cx or ny >= _cy:
				continue
			# Координата клетки в текстуре соседа: CHUNK + APRON справа от него, -1 + APRON слева.
			var tx: int = lx + APRON - dx * CHUNK
			var ty: int = ly + APRON - dy * CHUNK
			if tx < 0 or ty < 0 or tx >= IMG or ty >= IMG:
				continue
			_put(nx, ny, tx, ty)


func _mark(i: int) -> void:
	if _dirty[i] == 0:
		_dirty[i] = 1
		_dirty_list.append(i)


## Переносит открытые клетки прямоугольника в байты задетых чанков (с полями).
## Клетка x попадает в чанк cx, если cx*CHUNK - APRON <= x <= cx*CHUNK + CHUNK - 1 + APRON.
func _apply_rect(rect: Rect2i) -> void:
	var ww: int = World.W
	var x0: int = maxi(0, rect.position.x)
	var y0: int = maxi(0, rect.position.y)
	var x1: int = mini(World.W - 1, rect.end.x - 1)
	var y1: int = mini(World.H - 1, rect.end.y - 1)
	if x1 < x0 or y1 < y0:
		return
	var ex: PackedByteArray = World.explored
	var cx0: int = maxi(0, (x0 - APRON + CHUNK) / CHUNK - 1)
	var cx1: int = mini(_cx - 1, (x1 + APRON) / CHUNK)
	var cy0: int = maxi(0, (y0 - APRON + CHUNK) / CHUNK - 1)
	var cy1: int = mini(_cy - 1, (y1 + APRON) / CHUNK)
	for cy in range(cy0, cy1 + 1):
		var oy: int = cy * CHUNK - APRON          # клетка мира в ряду 0 текстуры
		var ya: int = maxi(y0, oy)
		var yb: int = mini(y1, oy + IMG - 1)
		for cx in range(cx0, cx1 + 1):
			var ox: int = cx * CHUNK - APRON
			var xa: int = maxi(x0, ox)
			var xb: int = mini(x1, ox + IMG - 1)
			if xb < xa or yb < ya:
				continue
			var ci: int = cy * _cx + cx
			var base: int = ci * IMG_BYTES
			var changed: bool = false
			for y in range(ya, yb + 1):
				var row: int = y * ww
				if not ex.slice(row + xa, row + xb + 1).has(1):
					continue
				var trow: int = base + (y - oy) * IMG - ox
				for x in range(xa, xb + 1):
					if ex[row + x] != 0 and _buf[trow + x] == 0:
						_buf[trow + x] = 255
						changed = true
			if changed:
				_mark(ci)


func _process(delta: float) -> void:
	var t0: int = Time.get_ticks_usec()
	stat_frames += 1
	# Заливка изменённых чанков: обычно пусто, при шаге в новое — 1–2 чанка.
	if not _dirty_list.is_empty():
		for i in _dirty_list:
			_img.set_data(IMG, IMG, false, Image.FORMAT_L8, _buf.slice(i * IMG_BYTES, (i + 1) * IMG_BYTES))
			_texs[i].update(_img)
			_dirty[i] = 0
			stat_uploads += 1
		_dirty_list.clear()
	# Круг обзора: позиция героя и радиус — параметры шейдера, без перерисовки.
	# Стоя на месте и при устоявшемся радиусе здесь только два сравнения.
	var p = Game.player
	if p != null and is_instance_valid(p):
		var hp: Vector2 = p.global_position
		if hp != _hero:
			_hero = hp
			_mat.set_shader_parameter("hero", hp)
			_target = float(World.explore_radius_at(World.world_to_cell(hp)) * World.TILE)
		if _radius != _target:
			if _radius < 0.0 or absf(_radius - _target) < 0.5:
				_radius = _target
			else:
				_radius = lerpf(_radius, _target, minf(1.0, delta * RADIUS_LERP))
			_mat.set_shader_parameter("vis_far", _radius)
			_mat.set_shader_parameter("vis_near", maxf(0.0, _radius - float(Balance.FOG_EDGE * World.TILE)))
	# Перерисовка — только если сменился набор чанков в кадре; набор пересчитываем,
	# только когда сдвинулась камера (канвас-трансформ вьюпорта).
	var ct: Transform2D = get_viewport().get_canvas_transform()
	if ct != _last_ct:
		_last_ct = ct
		var r: Rect2i = _view_chunks()
		if r != _range:
			_range = r
			queue_redraw()
	stat_us += Time.get_ticks_usec() - t0


## Чанки, задевающие кадр камеры (с запасом в клетку). Без камеры — все.
func _view_chunks() -> Rect2i:
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam == null:
		return Rect2i(0, 0, _cx, _cy)
	var vp: Viewport = get_viewport()
	var to_world: Transform2D = vp.get_canvas_transform().affine_inverse()
	var vr: Rect2 = vp.get_visible_rect()
	var a: Vector2 = to_world * vr.position
	var b: Vector2 = to_world * (vr.position + vr.size)
	var view: Rect2 = Rect2(a, b - a).abs().grow(float(World.TILE))
	var cs: float = float(CHUNK * World.TILE)
	var c0x: int = clampi(int(floor(view.position.x / cs)), 0, _cx - 1)
	var c0y: int = clampi(int(floor(view.position.y / cs)), 0, _cy - 1)
	var c1x: int = clampi(int(floor(view.end.x / cs)), 0, _cx - 1)
	var c1y: int = clampi(int(floor(view.end.y / cs)), 0, _cy - 1)
	return Rect2i(c0x, c0y, c1x - c0x + 1, c1y - c0y + 1)


func _draw() -> void:
	var t0: int = Time.get_ticks_usec()
	stat_redraws += 1
	chunks_drawn = 0
	var cs: float = float(CHUNK * World.TILE)
	var src: Rect2 = Rect2(APRON, APRON, CHUNK, CHUNK)
	for cy in range(_range.position.y, _range.end.y):
		for cx in range(_range.position.x, _range.end.x):
			draw_texture_rect_region(_texs[cy * _cx + cx], Rect2(cx * cs, cy * cs, cs, cs), src)
			chunks_drawn += 1
	stat_us += Time.get_ticks_usec() - t0


## Сколько чанков всего (для сценария и замеров).
func chunk_count() -> int:
	return _cx * _cy


## Байт тумана клетки так, как он лежит в текстуре (255 — исследовано). Для сценария.
func fog_byte(c: Vector2i) -> int:
	if c.x < 0 or c.y < 0 or c.x >= World.W or c.y >= World.H:
		return 0
	var cx: int = c.x / CHUNK
	var cy: int = c.y / CHUNK
	var base: int = (cy * _cx + cx) * IMG_BYTES
	return _buf[base + (c.y - cy * CHUNK + APRON) * IMG + (c.x - cx * CHUNK + APRON)]
