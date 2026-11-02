class_name Emission
extends Node
## Слой эмиссии (ADR-003 V3): светящиеся пиксели мира не темнеют ночью.
##
## Гифы и нити мицелия, жар трещин, кристаллы, лава, экраны терминалов и машин,
## светокристалл, ядро релея — пиксели этих цветов палитры (DB.PAL) светятся сами,
## на них не действует CanvasModulate мира. Ночью на шляпках свечников
## загораются споры (угол кремового пятна на розовой шляпке → бирюза).
##
## Как устроено (рендерер gl_compatibility, постобработки нет):
##  * не второй TileMapLayer, а материал на тех же слоях: World.tilemap, декор-слой
##    флоры (World.decor, V2) и машины. Шейдер узнаёт светящийся пиксель по его
##    цвету в атласе (точное совпадение с цветом свечения палитры) и делит его на
##    текущий амбиент — CanvasModulate умножает обратно, и пиксель выходит в своём
##    цвете при любом времени суток. Ни второго набора клеток, ни синхронизации
##    правок мира: копнул — эмиссия ушла вместе с тайлом;
##  * порядок отрисовки прежний: эмиссия лежит в мировом канвасе на месте своего
##    тайла — под героем, фантомами и туманом войны (FogLayer, z 30): сквозь туман
##    не светит, в полутени исследованного притушена, как всё под туманом;
##  * ореолы — прежние glow_texture WorldFX (MAX_GLOWS), их слой получает
##    glow_material: ореол — свет, ночью он тоже не тускнеет.
## В кадре на ЦП — только сверка цвета CanvasModulate (смена → два uniform).

## Как часто проверять, у всех ли машин материал эмиссии, с (новые постройки).
const MACHINE_CHECK_SEC: float = 1.0
## Допуск совпадения цвета с цветом свечения (8-битный атлас — с запасом).
const MATCH_EPS: float = 0.012

## Материал тайлов, декора и машин: светятся только пиксели цветов свечения.
var tile_material: ShaderMaterial = null
## Материал ореолов WorldFX: светится всё, что нарисовано.
var glow_material: ShaderMaterial = null

var _tint: CanvasModulate = null
var _last: Color = Color(-1, -1, -1)
var _night: float = -1.0
var _mach_t: float = 0.0
var _mach_n: int = -1

# ---------------------------------------------- СЧЁТЧИКИ (для замеров)
var stat_us: int = 0
var stat_frames: int = 0


func _ready() -> void:
	var sh: Shader = Shader.new()
	sh.code = shader_code()
	tile_material = ShaderMaterial.new()
	tile_material.shader = sh
	glow_material = ShaderMaterial.new()
	glow_material.shader = sh
	glow_material.set_shader_parameter("all_emit", true)
	for n in get_parent().get_children():
		if n is CanvasModulate:
			_tint = n
	World.tilemap.material = tile_material
	var decor: Variant = World.get("decor")
	if decor is CanvasItem:
		(decor as CanvasItem).material = tile_material
	if UI.world_fx != null and UI.world_fx.has_method("set_glow_material"):
		UI.world_fx.set_glow_material(glow_material)
	_apply()


func _process(delta: float) -> void:
	var t0: int = Time.get_ticks_usec()
	stat_frames += 1
	_apply()
	_mach_t -= delta
	if _mach_t <= 0.0 or World.machines.size() != _mach_n:
		_mach_t = MACHINE_CHECK_SEC
		_mach_n = World.machines.size()
		for m in World.machines.values():
			if m is CanvasItem and is_instance_valid(m) and (m as CanvasItem).material == null:
				(m as CanvasItem).material = tile_material
	stat_us += Time.get_ticks_usec() - t0


## Амбиент сменился → обратный амбиент в оба материала; ночь → споры на флоре.
func _apply() -> void:
	var c: Color = _tint.color if _tint != null else SkyBackdrop.ambient(Game.daylight())
	if c != _last:
		_last = c
		var inv: Vector3 = Vector3(1.0 / maxf(c.r, 0.01), 1.0 / maxf(c.g, 0.01), 1.0 / maxf(c.b, 0.01))
		tile_material.set_shader_parameter("inv_amb", inv)
		glow_material.set_shader_parameter("inv_amb", inv)
	var n: float = snappedf(SkyBackdrop.phase_weights(Game.daylight()).z, 1.0 / 64.0)
	if n != _night:
		_night = n
		tile_material.set_shader_parameter("night", n)


## Цвета свечения палитры: точное совпадение пикселя — эмиссия.
static func glow_colors() -> Array[Color]:
	var cr: Color = DB.pal("crystal")
	return [DB.pal("m_glow"), DB.pal("d_glow"), cr, cr.lightened(0.4),
			DB.pal("lava"), DB.pal("lava_hi"), DB.pal("lava").darkened(0.25),
			DB.pal("screen_hi"), DB.pal("bio"), DB.pal("bio_core"), Color.WHITE]


## Шейдер: цвета свечения вписываются константами (сравнение без массивов uniform).
static func shader_code() -> String:
	var checks: PackedStringArray = PackedStringArray()
	for g in glow_colors():
		checks.append("e = max(e, step(max3(abs(c - vec3(%.4f, %.4f, %.4f))), EPS));" % [g.r, g.g, g.b])
	var spore: Color = DB.pal("fl3")
	var cap: Color = DB.pal("fl1")
	var bio: Color = DB.pal("bio")
	return """
shader_type canvas_item;
uniform vec3 inv_amb = vec3(1.0);   // 1 / цвет CanvasModulate
uniform float night = 0.0;          // вес ночи: споры на шляпках свечников
uniform bool all_emit = false;      // ореолы: светится всё

const float EPS = %.4f;

float max3(vec3 v) {
	return max(v.r, max(v.g, v.b));
}

void fragment() {
	if (all_emit) {
		COLOR.rgb *= inv_amb;
	} else if (COLOR.a > 0.98) {
		vec3 c = COLOR.rgb;
		float e = 0.0;
		%s
		if (e > 0.5) {
			COLOR.rgb *= inv_amb;
		} else if (night > 0.0 && max3(abs(c - vec3(%.4f, %.4f, %.4f))) < EPS) {
			// Спора: угол кремового пятна на шляпке — и слева, и сверху розовая шляпка
			// (у кольца роста на стебле розовое только сверху).
			vec3 cap = vec3(%.4f, %.4f, %.4f);
			vec3 l = texture(TEXTURE, UV - vec2(TEXTURE_PIXEL_SIZE.x, 0.0)).rgb;
			vec3 u = texture(TEXTURE, UV - vec2(0.0, TEXTURE_PIXEL_SIZE.y)).rgb;
			if (max3(abs(l - cap)) < EPS && max3(abs(u - cap)) < EPS) {
				COLOR.rgb = mix(c, vec3(%.4f, %.4f, %.4f) * inv_amb, night);
			}
		}
	}
}
""" % [MATCH_EPS, "\n\t\t".join(checks), spore.r, spore.g, spore.b, cap.r, cap.g, cap.b, bio.r, bio.g, bio.b]
