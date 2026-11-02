class_name SkyBackdrop
extends CanvasLayer
## Фон мира (ADR-003 V3, концепт A «Споровый луг»): небо, светила, дальний и
## средний план, споры в воздухе — и задняя стена пещер вместо неба под рельефом.
## Образец — tools/style_concepts.gd (_sky_spore, paint_far, paint_mid, _backwall).
##
## Всё квадратное: небо считается по сетке пикселей мира на экране (зум камеры),
## газовый гигант «Цербер» — макропикселями 2×2, градиент — ступенями с
## дизерингом Байера, стена — по пикселям мира, ровно в сетке тайлов.
##
## Стоимость (issue #7: небо — фон, оно не должно стоить кадра):
##  * один прямоугольник на весь экран с шейдером; на ЦП в кадре — только сверка
##    камеры (сдвиг → два uniform), раз в GRADIENT_CHECK_SEC — цвета фазы суток;
##  * силуэты дальнего и среднего плана — маски L8, запекаются один раз
##    нативным Image.fill_rect (все силуэты — прямоугольники); цвет — uniform;
##  * рельеф для стены — текстура W×1 (строки поверхности и границ биомов),
##    пересобирается только по World.explored_reset (новый мир, загрузка);
##  * споры и мерцание звёзд анимирует шейдер по TIME — перерисовки нет.
##
## Свет суток — три фазы ADR-003 § 4.1: день, сумерки, ночь. phase_weights(dl)
## даёт их веса, ambient(dl) — цвет CanvasModulate мира (main.gd, секция tint).

const GRADIENT_CHECK_SEC: float = 0.25

## Амбиент мира (CanvasModulate): день, сумерки, ночь — ADR-003 § 7.3, V3.
const AMB_DAY: Color = Color("#FFF6EA")
const AMB_DUSK: Color = Color("#B8889A")
const AMB_NIGHT: Color = Color("#3A3050")

## Небо: верх / горизонт по фазам (PAL.spore).
const SKY_DAY: Array[Color] = [Color("#D8B6A8"), Color("#F3E2C8")]
const SKY_DUSK: Array[Color] = [Color("#5E436A"), Color("#F09A6A")]
const SKY_NIGHT: Array[Color] = [Color("#161220"), Color("#33243C")]
const FAR: Color = Color("#C7A6B6")
const FAR2: Color = Color("#B08CA4")

## Ширина периода силуэтов, px мира: дальний план (мезы) и средний (исполины).
const FAR_W: int = 640
const FAR_H: int = 96
const MID_W: int = 960
const MID_H: int = 128
## Параллакс по горизонтали: доля сдвига камеры (0 — стоит, 1 — как мир).
const PAR_FAR: float = 0.12
const PAR_MID: float = 0.3
const PAR_SPORES: float = 0.5
## Параллакс горизонта по вертикали: горизонт — на уровне моря мира, но ходит
## за камерой в PAR_HORIZON раз медленнее (герой под землёй — горизонт уходит вверх).
const PAR_HORIZON: float = 0.3

const SHADER_CODE: String = """
shader_type canvas_item;
render_mode blend_disabled;

// Камера: мир в px левого верхнего угла экрана, единиц экрана на px мира.
uniform vec2 cam = vec2(0.0);
uniform float zoom = 2.2;
uniform vec2 view = vec2(582.0, 327.0); // экран в пикселях мира
uniform float sea = 832.0;           // уровень моря в px мира: якорь горизонта
uniform float par_hor = 0.3;
uniform vec3 par = vec3(0.12, 0.3, 0.5);   // параллакс: мезы, исполины, споры

// Фаза суток: веса день / сумерки / ночь.
uniform vec3 phase = vec3(1.0, 0.0, 0.0);
uniform vec3 sky_top = vec3(0.85, 0.71, 0.66);
uniform vec3 sky_hor = vec3(0.95, 0.89, 0.78);
uniform vec3 far1;
uniform vec3 far_alt;
uniform vec3 far2;
uniform vec3 mid1;
uniform vec3 mid2;
uniform vec3 bio = vec3(0.5, 0.9, 0.82);
uniform vec2 sun = vec2(-100.0);     // центр солнца, px экрана в пикселях мира
uniform float sun_a = 1.0;

// Задняя стена пещер: рельеф (r — поверхность, g — средние пещеры, b — глубина;
// номера строк тайлов), цвета биомов, амбиент мира (стена — под ним, как тайлы).
uniform sampler2D relief : filter_nearest, repeat_disable;
uniform int world_w = 640;
uniform vec3 amb = vec3(1.0);
uniform vec3 wall0;
uniform vec3 wall0d;
uniform vec3 wall1;
uniform vec3 wall1d;
uniform vec3 wall2;
uniform vec3 wall2d;
uniform vec3 glow1;
uniform vec3 glow2;

uniform sampler2D far_mask : filter_nearest, repeat_enable;
uniform sampler2D mid_mask : filter_nearest, repeat_enable;

varying vec2 bpos;

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
		3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

float hsh(int x, int y, int s) {
	uint n = uint(x) * 374761393u + uint(y) * 668265263u + uint(s) * 982451653u + 1013904223u;
	n = (n ^ (n >> 13u)) * 1274126177u;
	n = n ^ (n >> 16u);
	return float(n & 65535u) / 65535.0;
}

// Остаток для неотрицательного a (сдвиг 1 << 20 держит параллакс в плюсе).
int imod(int a, int m) {
	return (a + (1 << 20) / m * m) % m;
}

void vertex() {
	bpos = VERTEX;
}

vec3 wall(ivec2 w) {
	ivec2 c = ivec2(floor(vec2(w) / 16.0));
	vec3 rr = texelFetch(relief, ivec2(clamp(c.x, 0, world_w - 1), 0), 0).rgb * 255.0;
	int bio_i = c.y >= int(rr.b + 0.5) ? 2 : (c.y >= int(rr.g + 0.5) ? 1 : 0);
	vec3 base = bio_i == 2 ? wall2 : (bio_i == 1 ? wall1 : wall0);
	vec3 dark = bio_i == 2 ? wall2d : (bio_i == 1 ? wall1d : wall0d);
	vec3 col = mix(base, dark, hsh(w.x >> 2, w.y >> 2, 241) * 0.8);
	if (hsh(w.x >> 1, w.y >> 1, 242) < 0.08) {
		col *= 0.7;
	}
	col *= amb;
	// Нити мицелия в стене светятся сами (под амбиент не попадают).
	if (bio_i > 0 && hsh(w.x, w.y, 243) < 0.003) {
		col = bio_i == 1 ? glow1 : glow2;
	}
	return col;
}

void fragment() {
	// Пиксель мира под фрагментом: под рельефом — задняя стена.
	vec2 wp = cam + bpos / zoom;
	ivec2 wi = ivec2(floor(wp));
	ivec2 wc = ivec2(floor(wp / 16.0));
	float srow = texelFetch(relief, ivec2(clamp(wc.x, 0, world_w - 1), 0), 0).r * 255.0;
	if (float(wc.y) > srow + 0.5) {
		COLOR = vec4(wall(wi), 1.0);
	} else {
		// Небо — в сетке пикселей мира, привязанной к экрану.
		vec2 pf = floor(bpos / zoom);
		ivec2 p = ivec2(pf);
		float hz = floor(view.y * 0.5 + (sea - (cam.y + view.y * 0.5)) * par_hor);
		// 1. Градиент: 7 ступеней с дизерингом Байера 4×4.
		float t = pow(clamp(pf.y / max(hz, 1.0), 0.0, 1.0), 1.25);
		float d = BAYER[(p.y & 3) * 4 + (p.x & 3)] / 16.0;
		float q = clamp(floor(t * 7.0 + d - 0.5) / 7.0, 0.0, 1.0);
		vec3 col = mix(sky_top, sky_hor, q);
		// 2. Звёзды (ночью), мерцают по TIME.
		if (phase.z > 0.01) {
			float hs = hsh(p.x, p.y, 5);
			if (hs < 0.0009) {
				float k = 0.35 + hsh(p.x, p.y, 6) * 0.65;
				float tw = 0.65 + 0.35 * sin(TIME * (1.0 + k) + float(p.x) * 0.3);
				col = mix(col, vec3(0.96, 0.9, 0.81), phase.z * k * tw);
			}
		}
		// 3. Солнце: маленькое белое, квадрат с крестом и ступенчатым ореолом.
		vec2 ds = abs(pf - sun);
		float ch = max(ds.x, ds.y);
		if (sun_a > 0.0 && ch < 16.0) {
			if (ds.x <= 2.0 && ds.y <= 2.0) {
				col = mix(col, vec3(1.0, 0.973, 0.91), sun_a);
			} else if ((ds.x <= 3.0 && ds.y <= 1.0) || (ds.x <= 1.0 && ds.y <= 3.0)) {
				col = mix(col, vec3(1.0, 0.94, 0.816), sun_a);
			} else {
				float hb = floor(ch / 2.0) * 2.0;
				col = mix(col, vec3(1.0, 0.95, 0.85), sun_a * 0.32 * (1.0 - hb / 16.0));
			}
		}
		// 4. Газовый гигант «Цербер» в полнеба: полосы, тень слева, макропиксели 2×2.
		vec2 gc = vec2(view.x * 0.78, view.y * 0.28);
		float gr = view.y * 0.36;
		vec2 m = floor(pf / 2.0) * 2.0 + 1.0;
		vec2 uv = (m - gc) / gr;
		if (dot(uv, uv) <= 1.0) {
			int b = int(floor((uv.y + 1.0) * 5.0 + sin(uv.x * 3.0) * 0.6));
			vec3 g = (b % 2 == 0) ? vec3(0.851, 0.765, 0.863) : vec3(0.765, 0.651, 0.788);
			if (b == 6) {
				g = vec3(0.91, 0.725, 0.659);
			}
			g = mix(g, sky_top, clamp((-uv.x - 0.15) * 1.4, 0.0, 0.8));
			if (uv.x > 0.55) {
				g = mix(g, vec3(1.0, 0.69, 0.478), 0.5 * phase.y);
			}
			float lit = phase.x + phase.y * 0.75 + phase.z * 0.35;
			col = mix(g, sky_top, 1.0 - lit);
		}
		// 5. Дальний план: грибные столовые горы и холмы в дымке.
		int fy = int(hz) - p.y;          // сколько px над горизонтом
		if (fy <= 0) {
			col = far2;
		} else if (fy <= FAR_H) {
			int fx = imod(p.x + int(floor(cam.x * par.x)), FAR_W);
			float fm = texelFetch(far_mask, ivec2(fx, FAR_H - fy), 0).r * 255.0 / 40.0;
			if (fm > 0.5) {
				col = fm < 1.5 ? far2 : (fm < 2.5 ? far1 : far_alt);
			}
		}
		// 6. Средний план: исполинские свечники; ночью светятся кончики пластинок.
		int my = int(hz) + 6 - p.y;
		if (my > 0 && my <= MID_H) {
			int mx = imod(p.x + int(floor(cam.x * par.y)), MID_W);
			float mm = texelFetch(mid_mask, ivec2(mx, MID_H - my), 0).r * 255.0 / 40.0;
			if (mm > 0.5) {
				col = mm < 1.5 ? mid1 : (mm < 2.5 ? mid2 : mix(mid1, bio, phase.y + phase.z));
			}
		}
		// 7. Споры в воздухе: медленные квадратики, ночью светятся бирюзой.
		vec2 sq = pf + floor(cam * par.z) + floor(vec2(-TIME * 3.0, TIME * 1.6));
		ivec2 sc = ivec2(floor(sq / 22.0));
		float h0 = hsh(sc.x, sc.y, 31);
		if (h0 < 0.3) {
			ivec2 o = ivec2(floor(vec2(hsh(sc.x, sc.y, 32), hsh(sc.x, sc.y, 33)) * 20.0)) + 1;
			o.x += int(floor(sin(TIME * 0.7 + h0 * 40.0) * 1.5));
			if (all(equal(ivec2(floor(sq)) - sc * 22, o))) {
				col = mix(col, vec3(1.0, 0.97, 0.9), 0.55 * (phase.x + phase.y * 0.5));
				col = mix(col, bio, (0.55 + h0 * 1.3) * (phase.z + phase.y * 0.5));
			}
		}
		COLOR = vec4(col, 1.0);
	}
}
"""

var _view: ColorRect = null
var _mat: ShaderMaterial = null
var _grad_t: float = 0.0
var _key: PackedInt32Array = PackedInt32Array()
var _cam: Vector2 = Vector2(INF, INF)
var _zoom: float = -1.0
var _size: Vector2 = Vector2.ZERO
var _relief: ImageTexture = null
## Палитры фаз: день, сумерки, ночь — {имя uniform: Color}.
var _pal: Array[Dictionary] = []

# ---------------------------------------------- СЧЁТЧИКИ (для замеров)
## Время в _process и отрисовке неба, мкс (tools/hud_probe.gd).
var stat_us: int = 0
var stat_frames: int = 0
var stat_redraws: int = 0


func _ready() -> void:
	layer = -100
	var sh: Shader = Shader.new()
	sh.code = SHADER_CODE.replace("FAR_W", str(FAR_W)).replace("FAR_H", str(FAR_H)) \
			.replace("MID_W", str(MID_W)).replace("MID_H", str(MID_H))
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_view = ColorRect.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.material = _mat
	_view.draw.connect(func() -> void: stat_redraws += 1)
	add_child(_view)
	_build_palettes()
	_mat.set_shader_parameter("far_mask", ImageTexture.create_from_image(_bake_far()))
	_mat.set_shader_parameter("mid_mask", ImageTexture.create_from_image(_bake_mid()))
	_mat.set_shader_parameter("sea", float(World.SEA_LEVEL * World.TILE))
	_mat.set_shader_parameter("par_hor", PAR_HORIZON)
	_mat.set_shader_parameter("par", Vector3(PAR_FAR, PAR_MID, PAR_SPORES))
	_mat.set_shader_parameter("bio", _v3(DB.pal("bio")))
	_mat.set_shader_parameter("glow1", _v3(DB.pal("m_glow")))
	_mat.set_shader_parameter("glow2", _v3(DB.pal("d_glow")))
	# Стена: основа биома в тени, к его тени ещё темнее (style_concepts._backwall).
	var bios: Array = [["s_base", "s_dark"], ["m_base", "m_dark"], ["d_base", "d_dark"]]
	for i in 3:
		_mat.set_shader_parameter("wall%d" % i, _v3(DB.pal(bios[i][0]).darkened(0.42)))
		_mat.set_shader_parameter("wall%dd" % i, _v3(DB.pal(bios[i][1]).darkened(0.6)))
	_rebuild_relief()
	World.explored_reset.connect(_rebuild_relief)


func _process(delta: float) -> void:
	if _view == null:
		return
	var t0: int = Time.get_ticks_usec()
	stat_frames += 1
	# Камера: левый верхний угол экрана в мире и зум — сдвиг стены и параллакса.
	var ct: Transform2D = get_viewport().get_canvas_transform()
	var z: float = ct.x.x
	if z > 0.0:
		var c: Vector2 = -ct.origin / z
		if z != _zoom or _view.size != _size:
			_zoom = z
			_size = _view.size
			_mat.set_shader_parameter("zoom", z)
			_mat.set_shader_parameter("view", _size / z)
			_grad_t = 0.0   # солнце считается в долях экрана
		if c.distance_squared_to(_cam) > 0.0001:
			_cam = c
			_mat.set_shader_parameter("cam", c)
	# Цвета фазы суток и солнце: сверка раз в GRADIENT_CHECK_SEC, в 8-битной точности.
	_grad_t -= delta
	if _grad_t <= 0.0:
		_grad_t = GRADIENT_CHECK_SEC
		_update_phase()
	stat_us += Time.get_ticks_usec() - t0


## Веса фаз суток по Game.daylight(): x — день, y — сумерки, z — ночь (сумма 1).
## Рассвет проходит те же сумерки в обратную сторону.
static func phase_weights(dl: float) -> Vector3:
	if dl >= 0.75:
		return Vector3(1.0, 0.0, 0.0)
	if dl >= 0.45:
		var f: float = smoothstep(0.45, 0.75, dl)
		return Vector3(f, 1.0 - f, 0.0)
	if dl >= 0.2:
		var g: float = smoothstep(0.2, 0.45, dl)
		return Vector3(0.0, g, 1.0 - g)
	return Vector3(0.0, 0.0, 1.0)


## Амбиент мира (цвет CanvasModulate) по Game.daylight().
static func ambient(dl: float) -> Color:
	var w: Vector3 = phase_weights(dl)
	return AMB_DAY * w.x + AMB_DUSK * w.y + AMB_NIGHT * w.z


func _update_phase() -> void:
	var w: Vector3 = phase_weights(Game.daylight())
	# Солнце: восходит справа (из-за гиганта), садится слева у горизонта.
	var vs: Vector2 = _view.size / maxf(_zoom, 0.01)
	var p: float = clampf((Game.time_of_day - Balance.NIGHT_END) / (Balance.NIGHT_START - Balance.NIGHT_END), 0.0, 1.0)
	var sun: Vector2 = Vector2(floorf(vs.x * lerpf(0.70, 0.12, p)), floorf(vs.y * 0.5 - sin(p * PI) * vs.y * 0.42))
	var amb: Color = ambient(Game.daylight())
	var key: PackedInt32Array = PackedInt32Array([int(w.x * 255.0), int(w.y * 255.0), int(w.z * 255.0),
			int(sun.x), int(sun.y), amb.to_rgba32()])
	if key == _key:
		return
	_key = key
	_mat.set_shader_parameter("phase", w)
	_mat.set_shader_parameter("sun", sun)
	_mat.set_shader_parameter("sun_a", 1.0 - w.z)
	_mat.set_shader_parameter("amb", _v3(amb))
	for k in _pal[0].keys():
		_mat.set_shader_parameter(k, _v3(_pal[0][k] * w.x + _pal[1][k] * w.y + _pal[2][k] * w.z))


## Цвета неба и силуэтов по фазам — формулы концепта (style_concepts.gd).
func _build_palettes() -> void:
	_pal.clear()
	var s_dark: Color = DB.pal("s_dark")
	for i in 3:
		var sk: Array[Color] = [SKY_DAY, SKY_DUSK, SKY_NIGHT][i]
		var top: Color = sk[0]
		var hor: Color = sk[1]
		var f1: Color = FAR.lerp(hor, 0.45)
		var f2: Color = FAR2.lerp(hor, 0.2)
		var m1: Color = FAR2.lerp(s_dark, 0.35).lerp(hor, 0.25)
		var m2: Color = m1.lightened(0.08)
		if i == 1:
			f1 = FAR2.lerp(top, 0.5)
			f2 = top.darkened(0.2)
			m1 = top.darkened(0.3)
			m2 = m1.lightened(0.06)
		elif i == 2:
			f1 = hor.lightened(0.06)
			f2 = hor.darkened(0.25)
			m1 = hor.darkened(0.35)
			m2 = m1.lightened(0.05)
		_pal.append({"sky_top": top, "sky_hor": hor, "far1": f1, "far_alt": f2.lerp(f1, 0.4),
				"far2": f2, "mid1": m1, "mid2": m2})


## Маска дальнего плана FAR_W×FAR_H (низ — горизонт): 1 холмы, 2 и 3 — мезы двух тонов.
func _bake_far() -> Image:
	var img: Image = Image.create_empty(FAR_W, FAR_H, false, Image.FORMAT_L8)
	img.fill(Color(0, 0, 0))
	var by: int = FAR_H
	for i in 14:
		var mx: int = int(_h(i, 1, 61) * FAR_W)
		var mh: int = 26 + int(_h(i, 2, 61) * 40)
		var sw: int = 6 + int(_h(i, 3, 61) * 6) * 2
		var cw: int = sw * 3 + int(_h(i, 4, 61) * 16)
		var v: Color = Color8(80, 80, 80) if i % 2 == 0 else Color8(120, 120, 120)
		for dx in [0, -FAR_W, FAR_W]:   # шов периода: края мезы переносим на другую сторону
			img.fill_rect(Rect2i(mx + dx, by - mh, sw, mh), v)
			img.fill_rect(Rect2i(mx + dx - (cw - sw) / 2, by - mh - 6, cw, 6), v)
			img.fill_rect(Rect2i(mx + dx - (cw - sw) / 2 + 4, by - mh - 10, cw - 8, 4), v)
	for x in range(0, FAR_W, 4):
		var hh: int = 6 + int((sin(TAU * float(x) / float(FAR_W) * 3.0) * 0.5 + 0.5) * 8.0 + _h(x / 4, 0, 62) * 4.0)
		img.fill_rect(Rect2i(x, by - hh, 4, hh), Color8(40, 40, 40))
	return img


## Маска среднего плана MID_W×MID_H (низ — основание): 1 исполин, 2 блик, 3 кончик пластинки.
func _bake_mid() -> Image:
	var img: Image = Image.create_empty(MID_W, MID_H, false, Image.FORMAT_L8)
	img.fill(Color(0, 0, 0))
	var c1: Color = Color8(40, 40, 40)
	var c2: Color = Color8(80, 80, 80)
	var c3: Color = Color8(120, 120, 120)
	var by: int = MID_H
	for i in 6:
		var mx: int = 60 + i * 160 + int(_h(i, 1, 71) * 60.0)
		var mh: int = 64 + int(_h(i, 2, 71) * 40.0)
		img.fill_rect(Rect2i(mx, by - mh, 8, mh), c1)
		img.fill_rect(Rect2i(mx + 6, by - mh, 2, mh), c2)
		img.fill_rect(Rect2i(mx - 22, by - mh - 8, 52, 8), c1)
		img.fill_rect(Rect2i(mx - 18, by - mh - 12, 44, 4), c2)
		img.fill_rect(Rect2i(mx - 12, by - mh + 22, 32, 5), c1)
		for k in 6:
			var gl: int = 4 + (k % 3) * 3
			img.fill_rect(Rect2i(mx - 20 + k * 9, by - mh, 1, gl), c1)
			img.fill_rect(Rect2i(mx - 20 + k * 9, by - mh + gl, 1, 1), c3)
	return img


## Рельеф для стены: W×1, r — строка поверхности, g — начало средних пещер, b — глубины.
func _rebuild_relief() -> void:
	var w: int = World.W
	var img: Image = Image.create_empty(w, 1, false, Image.FORMAT_RGBA8)
	var surf: PackedInt32Array = World.surface
	for x in w:
		var top: int = surf[x] if surf.size() == w else World.SEA_LEVEL
		img.set_pixel(x, 0, Color8(top, _biome_row(x, top, 1), _biome_row(x, top, 2)))
	if _relief == null:
		_relief = ImageTexture.create_from_image(img)
		_mat.set_shader_parameter("relief", _relief)
	else:
		_relief.update(img)
	_mat.set_shader_parameter("world_w", w)


## Первая строка колонки x, где биом не меньше bio (двоичный поиск по World.biome_at).
func _biome_row(x: int, top: int, bio: int) -> int:
	var lo: int = top
	var hi: int = World.H
	while lo < hi:
		var mid: int = (lo + hi) >> 1
		if World.biome_at(x, mid) >= bio:
			hi = mid
		else:
			lo = mid + 1
	return mini(lo, 255)


static func _v3(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


static func _h(x: int, y: int, s: int) -> float:
	var n: int = (x * 374761393 + y * 668265263 + s * 982451653 + 1013904223) & 0xFFFFFFFF
	n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
	n = n ^ (n >> 16)
	return float(n & 0xFFFF) / 65535.0
