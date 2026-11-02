extends SceneTree
## ADR-003 (#84): концепт-рендеры трёх визуальных стилей «ГЛИТЧ-КОРЕ».
##
## Прототип ТОЛЬКО для картинок ADR: к игре не подключён, игровые скрипты и
## автозагрузки не читает. Всё рисуется попиксельно в Image (как DB рисует тайлы),
## поэтому окно не нужно:
##   godot --headless --path . --script res://tools/style_concepts.gd
##   godot --headless --path . --script res://tools/style_concepts.gd -- --only=spore
## Выход — docs/adr/img/0003/:
##   <концепт>_surface_day.png  — поверхность днём: база, релей, ТЭЦ, солнечная панель, герой;
##   <концепт>_cave_night.png   — пещера ночью: руды, пять фантомов, фонарь героя;
##   <концепт>_biomes.png       — разрез по глубине: поверхность → средние пещеры → глубина у лавы;
##   <концепт>_sheet.png        — лист: тайлы/руды ×4, флора, герой ×6, кастомизация ×4,
##                                фантомы ×4, небо день/сумерки/ночь, палитра;
##   compare_scenes.png, compare_cvd.png — три концепта рядом; то же с симуляцией дейтеранопии.
##
## Правило владельца (#84): сетка 16×16 и квадратные силуэты сохраняются — никаких
## скосов и кривых. Рисуем только прямоугольниками и пикселями; своеобразие —
## палитрой, фактурой внутри квадрата, флорой из блоков, светом и дозированным глитчем.
## Сцена рисуется в «родном» разрешении (1 px = 1 пиксель мира) и увеличивается nearest.

const OUT: String = "res://docs/adr/img/0003/"
const W: int = 320
const H: int = 180
const SCALE: int = 4
const T: int = 16
const BAYER: Array[int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
const IDS: Array[String] = ["spore", "reef", "static"]

enum K { AIR, GROUND, BED, COPPER, IRON, COAL, CRYSTAL, SCRAP, LAVA, WATER, PANEL, WALL, GLASS, TERM, RELAY, LAMP }

## Палитры концептов. Роли цветов описаны в docs/adr/0003-visual-style.md.
const PAL: Dictionary = {
	"spore": {
		"sky_day_top": "#D8B6A8", "sky_day_hor": "#F3E2C8", "sky_dusk_top": "#5E436A", "sky_dusk_hor": "#F09A6A",
		"sky_night_top": "#161220", "sky_night_hor": "#33243C", "far": "#C7A6B6", "far2": "#B08CA4",
		"s_top": "#C9A445", "s_top2": "#F2D27A", "s_base": "#B58A72", "s_dark": "#94685A", "s_hi": "#CDA48A",
		"m_base": "#5D4A68", "m_dark": "#3D3049", "m_hi": "#7B6786", "m_glow": "#7FE6D2",
		"d_base": "#6B3035", "d_dark": "#461D25", "d_hi": "#94474A", "d_glow": "#FF9A5C",
		"bed": "#241A22",
		"copper": "#F08C3C", "copper_d": "#8E4220", "iron": "#EEE8DA", "iron_d": "#7E7668",
		"coal": "#1E1719", "coal_hi": "#F4E6CF", "crystal": "#6FF5E0", "crystal_d": "#21807E",
		"scrap": "#9A9E94", "scrap_d": "#4E423C",
		"lava": "#FF7A2E", "lava_hi": "#FFD86E", "water": "#6FA7B0", "water_hi": "#C4E6E0",
		"metal": "#E3DDCD", "metal_d": "#A39E92", "metal_hi": "#FFF8EA", "frame": "#5E6B78",
		"hazard": "#E3B341", "screen": "#23353A", "screen_hi": "#8CF0C8",
		"suit": "#E8743B", "suit2": "#EFE8D8", "suit2_d": "#B5AC9A", "visor": "#2F4C5A", "visor_hi": "#A8E6E0",
		"lamp": "#FFE7A0", "outline": "#2A1E24",
		"interact": "#FFF1A8", "danger": "#F0306A", "bio": "#7FE6D2",
		"ph": "#4B3A5C", "ph2": "#2C2238",
		"fl1": "#F2B8A0", "fl1_d": "#C47E78", "fl2": "#DCCDEA", "fl2_d": "#A68FBC", "fl3": "#F4EBCF",
		"ui_bg": "#221A20", "ui_panel": "#3A2E34", "ui_line": "#EFE8D8", "ui_hp": "#E8743B",
		"amb_day": "#FFF6EA", "amb_dusk": "#B8889A", "amb_night": "#3A3050", "amb_cave": "#3A3046",
	},
	"reef": {
		"sky_day_top": "#7EAFAE", "sky_day_hor": "#DCE6D3", "sky_dusk_top": "#2A4562", "sky_dusk_hor": "#E2957C",
		"sky_night_top": "#07111A", "sky_night_hor": "#163036", "far": "#A6C2BA", "far2": "#8AABA4",
		"s_top": "#86BBA2", "s_top2": "#D2EAC6", "s_base": "#DAD0BA", "s_dark": "#AFA288", "s_hi": "#F0E8D6",
		"m_base": "#34565B", "m_dark": "#20393F", "m_hi": "#4D7373", "m_glow": "#D6F27A",
		"d_base": "#27242F", "d_dark": "#15131B", "d_hi": "#3C3846", "d_glow": "#FF7B3A",
		"bed": "#0E0D12",
		"copper": "#F28A3A", "copper_d": "#8A4020", "iron": "#4A7DF0", "iron_d": "#1C3478",
		"coal": "#121318", "coal_hi": "#E8F0F0", "crystal": "#F25ACB", "crystal_d": "#7E2068",
		"scrap": "#8C9298", "scrap_d": "#4A4038",
		"lava": "#FF6A2A", "lava_hi": "#FFD25A", "water": "#3E8A9A", "water_hi": "#A8EAE6",
		"metal": "#4C5764", "metal_d": "#2E3640", "metal_hi": "#7E8A98", "frame": "#1D232A",
		"hazard": "#F2C14E", "screen": "#0F2228", "screen_hi": "#7FF0E6",
		"suit": "#F2C14E", "suit2": "#5C6773", "suit2_d": "#39414A", "visor": "#123040", "visor_hi": "#9FE6F0",
		"lamp": "#FFF6C8", "outline": "#10161C",
		"interact": "#7FF0FF", "danger": "#FF3D6E", "bio": "#D6F27A",
		"ph": "#1E3A4A", "ph2": "#0E1C26",
		"fl1": "#E88E7C", "fl1_d": "#AE5C58", "fl2": "#E8D98A", "fl2_d": "#AE9C52", "fl3": "#F4ECDE",
		"ui_bg": "#0F171C", "ui_panel": "#1D2A30", "ui_line": "#DCE6D3", "ui_hp": "#F2C14E",
		"amb_day": "#F2FAF4", "amb_dusk": "#8C8CA4", "amb_night": "#22384A", "amb_cave": "#22363C",
	},
	"static": {
		"sky_day_top": "#B4A3C6", "sky_day_hor": "#E6D2C2", "sky_dusk_top": "#3A2C5A", "sky_dusk_hor": "#E8784E",
		"sky_night_top": "#07070E", "sky_night_hor": "#191530", "far": "#9C8FB0", "far2": "#7C6F96",
		"s_top": "#7FA0A0", "s_top2": "#E4F25A", "s_base": "#5E4E58", "s_dark": "#3E323C", "s_hi": "#7A6874",
		"m_base": "#302E3C", "m_dark": "#1D1C26", "m_hi": "#4A4760", "m_glow": "#B6E64A",
		"d_base": "#2E1522", "d_dark": "#180A12", "d_hi": "#4A2034", "d_glow": "#FF2E88",
		"bed": "#0B0609",
		"copper": "#F08A36", "copper_d": "#8E4418", "iron": "#C4D0DE", "iron_d": "#5E6A7A",
		"coal": "#100E12", "coal_hi": "#FFFFFF", "crystal": "#46F0FF", "crystal_d": "#167090",
		"scrap": "#8A8C90", "scrap_d": "#50443C",
		"lava": "#FF7A2A", "lava_hi": "#FFE07A", "water": "#3A5A8A", "water_hi": "#A8CCFF",
		"metal": "#C9CDD4", "metal_d": "#868B95", "metal_hi": "#F2F4F8", "frame": "#1C1E24",
		"hazard": "#FF8A2A", "screen": "#0E1416", "screen_hi": "#E4F25A",
		"suit": "#3F78F0", "suit2": "#E2E4E8", "suit2_d": "#9CA1AC", "visor": "#E4F25A", "visor_hi": "#FFFFFF",
		"lamp": "#F4FFE0", "outline": "#0C0B10",
		"interact": "#F4F4F4", "danger": "#FF2E88", "bio": "#46F0FF",
		"ph": "#2A2238", "ph2": "#120E1A",
		"fl1": "#C9D45A", "fl1_d": "#7E8650", "fl2": "#8E9A7A", "fl2_d": "#4E5642", "fl3": "#7A6A9E",
		"ui_bg": "#0D0C12", "ui_panel": "#1C1A26", "ui_line": "#E2E4E8", "ui_hp": "#FF8A2A",
		"amb_day": "#F4EEF6", "amb_dusk": "#9A7C9C", "amb_night": "#262040", "amb_cave": "#2E2640",
	},
}

var cid: String = ""
var P: Dictionary = {}


# ================================================================ КАНВА

## Канва: альбедо + излучение + накопленный свет. finish() собирает кадр:
## альбедо × (амбиент + свет), поверх — излучение и мягкое «свечение» вокруг него.
class Cv:
	var w: int
	var h: int
	var col: Image
	var emi: Image
	var lit: PackedFloat32Array
	var amb: Color = Color(1, 1, 1)
	var amb_rows: Array = []		## Амбиент по строкам (разрез биомов), иначе amb.

	func _init(pw: int, ph: int) -> void:
		w = pw
		h = ph
		col = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
		col.fill(Color(0, 0, 0, 1))
		emi = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
		emi.fill(Color(0, 0, 0, 0))
		lit = PackedFloat32Array()
		lit.resize(w * h * 3)
		lit.fill(0.0)

	func inb(x: int, y: int) -> bool:
		return x >= 0 and y >= 0 and x < w and y < h

	func px(x: int, y: int, c: Color) -> void:
		if not inb(x, y) or c.a <= 0.0:
			return
		if c.a < 1.0:
			var b: Color = col.get_pixel(x, y)
			col.set_pixel(x, y, b.lerp(Color(c.r, c.g, c.b, 1.0), c.a))
		else:
			col.set_pixel(x, y, c)

	func rect(x: int, y: int, rw: int, rh: int, c: Color) -> void:
		var x0: int = maxi(x, 0)
		var y0: int = maxi(y, 0)
		var x1: int = mini(x + rw, w)
		var y1: int = mini(y + rh, h)
		if x1 <= x0 or y1 <= y0:
			return
		if c.a >= 1.0:
			col.fill_rect(Rect2i(x0, y0, x1 - x0, y1 - y0), c)
			return
		for yy in range(y0, y1):
			for xx in range(x0, x1):
				px(xx, yy, c)

	## Светящийся пиксель: виден в темноте, k — сила (0..1).
	func glow(x: int, y: int, c: Color, k: float = 1.0) -> void:
		if not inb(x, y):
			return
		col.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
		var e: Color = emi.get_pixel(x, y)
		if k >= e.a:
			emi.set_pixel(x, y, Color(c.r, c.g, c.b, k))

	func glow_rect(x: int, y: int, rw: int, rh: int, c: Color, k: float = 1.0) -> void:
		for yy in range(y, y + rh):
			for xx in range(x, x + rw):
				glow(xx, yy, c, k)

	## Точечный свет с квадратичным спадом.
	func light(cx: float, cy: float, r: float, c: Color, k: float) -> void:
		cone(cx, cy, Vector2.ZERO, PI, r, c, k)

	## Конус света (фонарь): dir — направление, half — полуугол, рад.
	func cone(cx: float, cy: float, dir: Vector2, half: float, r: float, c: Color, k: float) -> void:
		var x0: int = maxi(int(cx - r), 0)
		var x1: int = mini(int(cx + r) + 1, w)
		var y0: int = maxi(int(cy - r), 0)
		var y1: int = mini(int(cy + r) + 1, h)
		var nd: Vector2 = dir.normalized() if dir != Vector2.ZERO else Vector2.ZERO
		for y in range(y0, y1):
			for x in range(x0, x1):
				var d: Vector2 = Vector2(x + 0.5 - cx, y + 0.5 - cy)
				var l: float = d.length()
				if l >= r:
					continue
				var f: float = pow(1.0 - l / r, 1.4)
				if nd != Vector2.ZERO and l > 2.0:
					var a: float = absf(nd.angle_to(d))
					if a > half:
						continue
					f *= clampf((half - a) / (half * 0.35), 0.0, 1.0)
				var i: int = (y * w + x) * 3
				lit[i] += c.r * f * k
				lit[i + 1] += c.g * f * k
				lit[i + 2] += c.b * f * k

	func finish(bloom: float) -> Image:
		var out: Image = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
		var gl: Image = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			var a: Color = amb
			if amb_rows.size() > y:
				a = amb_rows[y]
			for x in w:
				var i: int = (y * w + x) * 3
				var c: Color = col.get_pixel(x, y)
				var r: float = c.r * (a.r + lit[i])
				var g: float = c.g * (a.g + lit[i + 1])
				var b: float = c.b * (a.b + lit[i + 2])
				var e: Color = emi.get_pixel(x, y)
				if e.a > 0.0:
					r = maxf(r, e.r * e.a)
					g = maxf(g, e.g * e.a)
					b = maxf(b, e.b * e.a)
					gl.set_pixel(x, y, Color(e.r * e.a, e.g * e.a, e.b * e.a, 1.0))
				out.set_pixel(x, y, Color(minf(r, 1.0), minf(g, 1.0), minf(b, 1.0), 1.0))
		if bloom <= 0.0:
			return out
		# Свечение: усреднение уменьшением в 2, 4, 8 раз и обратное растяжение.
		var halo: Array[Image] = []
		var cur: Image = gl
		for step in 3:
			var nxt: Image = cur.duplicate()
			nxt.resize(maxi(cur.get_width() / 2, 1), maxi(cur.get_height() / 2, 1), Image.INTERPOLATE_BILINEAR)
			var up: Image = nxt.duplicate()
			up.resize(w, h, Image.INTERPOLATE_BILINEAR)
			halo.append(up)
			cur = nxt
		for y in h:
			for x in w:
				var c: Color = out.get_pixel(x, y)
				var add: Color = halo[0].get_pixel(x, y) * 0.35 + halo[1].get_pixel(x, y) * 0.45 + halo[2].get_pixel(x, y) * 0.5
				out.set_pixel(x, y, Color(minf(c.r + add.r * bloom, 1.0), minf(c.g + add.g * bloom, 1.0),
						minf(c.b + add.b * bloom, 1.0), 1.0))
		return out


## Спрайт 48×48 с началом координат в точке «ноги по центру» (24, 44).
class Spr:
	const SZ: int = 48
	var img: Image
	var emi: Image
	var ox: int = 24
	var oy: int = 44

	func _init() -> void:
		img = Image.create_empty(SZ, SZ, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		emi = Image.create_empty(SZ, SZ, false, Image.FORMAT_RGBA8)
		emi.fill(Color(0, 0, 0, 0))

	func p(x: int, y: int, c: Color) -> void:
		var xx: int = ox + x
		var yy: int = oy + y
		if xx < 0 or yy < 0 or xx >= SZ or yy >= SZ:
			return
		img.set_pixel(xx, yy, c)
		emi.set_pixel(xx, yy, Color(0, 0, 0, 0))

	func r(x: int, y: int, w: int, h: int, c: Color) -> void:
		for yy in range(y, y + h):
			for xx in range(x, x + w):
				p(xx, yy, c)

	## Светящийся прямоугольник.
	func e(x: int, y: int, w: int, h: int, c: Color, k: float = 1.0) -> void:
		for yy in range(y, y + h):
			for xx in range(x, x + w):
				p(xx, yy, c)
				var ax: int = ox + xx
				var ay: int = oy + yy
				if ax >= 0 and ay >= 0 and ax < SZ and ay < SZ:
					emi.set_pixel(ax, ay, Color(c.r, c.g, c.b, k))

	## Ступенчатая линия (Брезенхем) — квадратными пикселями.
	func line(x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
		var dx: int = absi(x1 - x0)
		var dy: int = -absi(y1 - y0)
		var sx: int = 1 if x0 < x1 else -1
		var sy: int = 1 if y0 < y1 else -1
		var err: int = dx + dy
		while true:
			p(x0, y0, c)
			if x0 == x1 and y0 == y1:
				break
			var e2: int = 2 * err
			if e2 >= dy:
				err += dy
				x0 += sx
			if e2 <= dx:
				err += dx
				y0 += sy

	## Однопиксельный контур вокруг непрозрачного силуэта (4 соседа).
	func outline(c: Color) -> void:
		var src: Image = img.duplicate()
		for y in SZ:
			for x in SZ:
				if src.get_pixel(x, y).a > 0.0:
					continue
				var hit: bool = false
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q: Vector2i = Vector2i(x, y) + d
					if q.x >= 0 and q.y >= 0 and q.x < SZ and q.y < SZ and src.get_pixel(q.x, q.y).a > 0.5:
						hit = true
						break
				if hit:
					img.set_pixel(x, y, c)

	func flip() -> void:
		img.flip_x()
		emi.flip_x()
		ox = SZ - 1 - ox


# ================================================================ ЗАПУСК

func _initialize() -> void:
	var only: String = ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var surf: Dictionary = {}
	var cave: Dictionary = {}
	var t0: int = Time.get_ticks_msec()
	for id in IDS:
		if only != "" and id != only:
			continue
		_select(id)
		surf[id] = _scene_surface()
		_save(surf[id], id + "_surface_day", SCALE)
		cave[id] = _scene_cave()
		_save(cave[id], id + "_cave_night", SCALE)
		_save(_scene_biomes(), id + "_biomes", 3)
		_save(_sheet(), id + "_sheet", 1)
		print("style_concepts: %s готов, %d мс" % [id, Time.get_ticks_msec() - t0])
	if only == "":
		_save(_compare(surf, cave, false), "compare_scenes", 1)
		_save(_compare(surf, cave, true), "compare_cvd", 1)
	print("style_concepts: всё за %d мс" % (Time.get_ticks_msec() - t0))
	quit()


func _select(id: String) -> void:
	cid = id
	P = {}
	var src: Dictionary = PAL[id]
	for k in src:
		P[k] = Color(src[k])


func _save(img: Image, name: String, scale: int) -> void:
	var out: Image = img
	if scale != 1:
		out = img.duplicate()
		out.resize(img.get_width() * scale, img.get_height() * scale, Image.INTERPOLATE_NEAREST)
	var path: String = ProjectSettings.globalize_path(OUT + name + ".png")
	var err: int = out.save_png(path)
	if err != OK:
		push_error("не удалось сохранить %s: %d" % [path, err])


# ================================================================ УТИЛИТЫ

func hsh(x: int, y: int, s: int = 0) -> float:
	var n: int = x * 374761393 + y * 668265263 + s * 982451653 + 1013904223
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return float(n & 0xFFFF) / 65535.0


func c(k: String) -> Color:
	return P[k]


func dith(x: int, y: int) -> float:
	return float(BAYER[(y % 4) * 4 + (x % 4)]) / 16.0


# ================================================================ НЕБО

## Небо: ступенчатый градиент с дизерингом Байера, светила, дальние силуэты.
func paint_sky(cv: Cv, tod: String, x0: int, y0: int, w: int, h: int, hor: int) -> void:
	var top: Color = c("sky_%s_top" % tod)
	var bot: Color = c("sky_%s_hor" % tod)
	var steps: float = 7.0
	for y in range(y0, y0 + h):
		var t: float = clampf(float(y - y0) / float(maxi(hor, 1)), 0.0, 1.0)
		t = pow(t, 1.25)
		for x in range(x0, x0 + w):
			var q: float = floor(t * steps + dith(x, y) - 0.5) / steps
			cv.px(x, y, top.lerp(bot, clampf(q, 0.0, 1.0)))
	match cid:
		"spore":
			_sky_spore(cv, tod, x0, y0, w, hor)
		"reef":
			_sky_reef(cv, tod, x0, y0, w, hor)
		"static":
			_sky_static(cv, tod, x0, y0, w, hor)


## Круг макропикселями mp×mp: светило остаётся «квадратным».
func _block_disc(cv: Cv, cx: float, cy: float, r: float, mp: int, col_fn: Callable) -> void:
	var n: int = int(ceil(r / mp)) + 1
	for j in range(-n, n + 1):
		for i in range(-n, n + 1):
			var px0: float = cx + i * mp
			var py0: float = cy + j * mp
			var d: float = Vector2(px0 + mp * 0.5 - cx, py0 + mp * 0.5 - cy).length()
			if d > r:
				continue
			var col: Color = col_fn.call((px0 + mp * 0.5 - cx) / r, (py0 + mp * 0.5 - cy) / r)
			cv.rect(int(px0), int(py0), mp, mp, col)


func _stars(cv: Cv, x0: int, y0: int, w: int, hor: int, n: int, col: Color, sd: int) -> void:
	for i in n:
		var x: int = x0 + int(hsh(i, 1, sd) * w)
		var y: int = y0 + int(hsh(i, 2, sd) * hor * 0.8)
		var k: float = 0.35 + hsh(i, 3, sd) * 0.65
		cv.glow(x, y, col, k)


func _sky_spore(cv: Cv, tod: String, x0: int, y0: int, w: int, hor: int) -> void:
	# Газовый гигант «Цербер» в полнеба: полосы, тень слева. Солнце — маленькое и белое.
	var cx: float = x0 + w * 0.78
	var cy: float = y0 + hor * 0.42
	var r: float = hor * 0.55
	var band_a: Color = Color("#D9C3DC")
	var band_b: Color = Color("#C3A6C9")
	var shade: Color = c("sky_%s_top" % tod)
	var lit_k: float = 1.0 if tod == "day" else (0.75 if tod == "dusk" else 0.35)
	_block_disc(cv, cx, cy, r, 2, func(u: float, v: float) -> Color:
		var b: int = int(floor((v + 1.0) * 5.0 + sin(u * 3.0) * 0.6))
		var col: Color = band_a if b % 2 == 0 else band_b
		if b == 6:
			col = Color("#E8B9A8")
		var sh: float = clampf((-u - 0.15) * 1.4, 0.0, 0.8)
		col = col.lerp(shade, sh)
		if tod == "dusk" and u > 0.55:
			col = col.lerp(Color("#FFB07A"), 0.5)
		return col.lerp(shade, 1.0 - lit_k))
	if tod != "night":
		var sx: int = x0 + int(w * 0.22)
		var sy: int = y0 + int(hor * (0.25 if tod == "day" else 0.85))
		cv.glow_rect(sx - 2, sy - 2, 5, 5, Color("#FFF8E8"), 1.0)
		cv.glow_rect(sx - 3, sy - 1, 7, 3, Color("#FFF0D0"), 0.8)
		cv.glow_rect(sx - 1, sy - 3, 3, 7, Color("#FFF0D0"), 0.8)
	else:
		_stars(cv, x0, y0, w, hor, 26, Color("#F4E6CF"), 5)
	# Споры в воздухе: медленные квадратики.
	for i in 22:
		var x: int = x0 + int(hsh(i, 9, 31) * w)
		var y: int = y0 + int(hsh(i, 8, 31) * hor * 1.1)
		if tod == "night":
			cv.glow(x, y, c("bio"), 0.55 + hsh(i, 7, 31) * 0.4)
		else:
			cv.px(x, y, Color(1, 0.97, 0.9, 0.55))


func _sky_reef(cv: Cv, tod: String, x0: int, y0: int, w: int, hor: int) -> void:
	# Окольцованная планета низко над горизонтом + две луны-квадрата.
	var cx: float = x0 + w * 0.27
	var cy: float = y0 + hor * 0.55
	var r: float = hor * 0.32
	var shade: Color = c("sky_%s_top" % tod)
	var k: float = 1.0 if tod == "day" else (0.8 if tod == "dusk" else 0.4)
	var ring: Color = Color("#F4EAD6").lerp(shade, 1.0 - k)
	# Кольцо — эллипс из макропикселей 2×1, задняя половина (над планетой) — до диска.
	for pass_i in 2:
		if pass_i == 1:
			_block_disc(cv, cx, cy, r, 2, func(u: float, v: float) -> Color:
				var col: Color = Color("#E9D7C0") if int(floor((v + 1.0) * 4.0)) % 2 == 0 else Color("#D8C2A6")
				col = col.lerp(shade, clampf((u + 0.2) * 0.9, 0.0, 0.7))
				return col.lerp(shade, 1.0 - k))
			continue
		for i in 160:
			var a: float = TAU * float(i) / 160.0
			var rx: float = cx + cos(a) * r * 2.1
			var ry: float = cy + sin(a) * r * 0.42 - cos(a) * r * 0.18
			cv.rect(int(rx), int(ry), 2, 1, ring)
	# Передняя половина кольца поверх диска.
	for i in 80:
		var a2: float = PI * float(i) / 80.0
		var rx2: float = cx + cos(a2) * r * 2.1
		var ry2: float = cy + sin(a2) * r * 0.42 - cos(a2) * r * 0.18
		cv.rect(int(rx2), int(ry2), 2, 1, ring)
	cv.rect(x0 + int(w * 0.62), y0 + int(hor * 0.18), 4, 4, Color("#E8F0EC").lerp(shade, 1.0 - k))
	cv.rect(x0 + int(w * 0.70), y0 + int(hor * 0.30), 2, 2, Color("#E8F0EC").lerp(shade, 1.0 - k))
	if tod == "night":
		_stars(cv, x0, y0, w, hor, 30, Color("#E8F6F2"), 6)
	if tod != "day":
		# Глитч-сияние: горизонтальные полосы, порванные сдвигами строк.
		var ac: Color = Color("#8CF2B4")
		for band in 3:
			var by: int = y0 + int(hor * (0.18 + band * 0.11))
			for y in range(by, by + 3):
				var shift: int = int((hsh(y, band, 41) - 0.5) * 14.0)
				for x in range(x0, x0 + w):
					var f: float = 0.5 + 0.5 * sin(float(x + shift) * 0.045 + band * 1.7)
					if f > 0.55 and (x + y) % 2 == 0:
						if tod == "night":
							cv.glow(x, y, ac, (f - 0.55) * 1.2)
						else:
							cv.px(x, y, Color(ac.r, ac.g, ac.b, (f - 0.55) * 0.8))


func _sky_static(cv: Cv, tod: String, x0: int, y0: int, w: int, hor: int) -> void:
	# Солнце, нарезанное на строки со сдвигом (глитч светила), и обломки кольца.
	var shade: Color = c("sky_%s_top" % tod)
	if tod != "night":
		var cx: float = x0 + w * 0.74
		var cy: float = y0 + hor * (0.33 if tod == "day" else 0.82)
		var r: float = hor * 0.12
		for yy in range(int(cy - r), int(cy + r) + 1):
			var shift: int = 0
			if (yy / 2) % 3 == 1:
				shift = int((hsh(yy, 0, 51) - 0.5) * 8.0)
			var hw: float = sqrt(maxf(r * r - pow(yy + 0.5 - cy, 2.0), 0.0))
			for xx in range(int(cx - hw), int(cx + hw) + 1):
				var sc: Color = Color("#FFF4DE") if tod == "day" else Color("#FFB070")
				cv.glow(xx + shift, yy, sc, 0.75)
	else:
		# Звёзды — R, G или B пиксели (битая матрица).
		for i in 34:
			var x: int = x0 + int(hsh(i, 1, 52) * w)
			var y: int = y0 + int(hsh(i, 2, 52) * hor * 0.85)
			var pick: int = int(hsh(i, 3, 52) * 3.0)
			var sc2: Color = [Color("#FF5A7A"), Color("#7AFF9A"), Color("#7AA8FF")][pick]
			cv.glow(x, y, sc2, 0.6 + hsh(i, 4, 52) * 0.4)
	# Обломки кольца: штриховая наклонная полоса через всё небо.
	var dc: Color = Color("#E8E0F0").lerp(shade, 0.35 if tod == "day" else 0.7)
	for i in 70:
		var t: float = float(i) / 70.0
		var x2: int = x0 + int(t * w)
		var y2: int = y0 + int(hor * (0.12 + t * 0.28))
		if hsh(i, 5, 53) > 0.35:
			var lw: int = 2 + int(hsh(i, 6, 53) * 4.0)
			cv.rect(x2, y2, lw, 1, dc)


## Средний план: исполинская флора — масштаб «мы здесь гости».
func paint_mid(cv: Cv, tod: String, x0: int, w: int, base_y: int) -> void:
	var col: Color = c("far2").lerp(c("s_dark"), 0.35).lerp(c("sky_%s_hor" % tod), 0.25)
	var col2: Color = col.lightened(0.08)
	if tod == "night":
		col = c("sky_night_hor").darkened(0.35)
		col2 = col.lightened(0.05)
	elif tod == "dusk":
		col = c("sky_dusk_top").darkened(0.3)
		col2 = col.lightened(0.06)
	var hk: float = clampf(float(base_y) / 118.0, 0.5, 1.0)	## Ниже горизонт — ниже исполины.
	match cid:
		"spore":
			for i in 3:
				var mx: int = x0 + [40, 150, 262][i]
				var mh: int = int([86, 70, 96][i] * hk)
				cv.rect(mx, base_y - mh, 8, mh, col)
				cv.rect(mx + 6, base_y - mh, 2, mh, col2)
				cv.rect(mx - 22, base_y - mh - 8, 52, 8, col)
				cv.rect(mx - 18, base_y - mh - 12, 44, 4, col2)
				cv.rect(mx - 12, base_y - mh + 22, 32, 5, col)
				for k in 6:
					cv.rect(mx - 20 + k * 9, base_y - mh, 1, 4 + (k % 3) * 3, col)
					if tod != "day":
						cv.glow(mx - 20 + k * 9, base_y - mh + 4 + (k % 3) * 3, c("bio"), 0.6)
		"reef":
			for i in 3:
				var mx2: int = x0 + [30, 160, 250][i]
				var mh2: int = int([80, 64, 92][i] * hk)
				cv.rect(mx2, base_y - mh2, 8, mh2, col)
				cv.rect(mx2 + 8, base_y - mh2 + 20, 18, 6, col)
				cv.rect(mx2 + 20, base_y - mh2 - 4, 6, 24, col)
				cv.rect(mx2 - 16, base_y - mh2 + 36, 16, 6, col)
				cv.rect(mx2 - 16, base_y - mh2 + 14, 6, 22, col)
				cv.rect(mx2 + 20, base_y - mh2 - 6, 6, 2, col2)
				cv.rect(mx2 - 16, base_y - mh2 + 12, 6, 2, col2)
		"static":
			for i in 3:
				var mx3: int = x0 + [56, 170, 280][i]
				var mh3: int = int([72, 58, 66][i] * hk)
				cv.rect(mx3, base_y - mh3, 4, mh3, col)
				var cw: int = 40
				for xx in cw:
					var run: int = 12 + int(hsh(xx, i, 251) * 26.0)
					cv.rect(mx3 - cw / 2 + xx, base_y - mh3 - 6 + int(hsh(xx, i, 252) * 4.0), 1, run, col if xx % 3 != 0 else col2)


## Дальние силуэты: макропиксели, дымка к цвету горизонта.
func paint_far(cv: Cv, tod: String, x0: int, w: int, base_y: int) -> void:
	var hz: Color = c("sky_%s_hor" % tod)
	var f1: Color = c("far").lerp(hz, 0.45)
	var f2: Color = c("far2").lerp(hz, 0.2)
	if tod == "night":
		f1 = c("sky_night_hor").lightened(0.06)
		f2 = c("sky_night_hor").darkened(0.25)
	elif tod == "dusk":
		f1 = c("far2").lerp(c("sky_dusk_top"), 0.5)
		f2 = c("sky_dusk_top").darkened(0.2)
	match cid:
		"spore":
			# Гигантские грибные столовые горы: ножка + плоская шляпка.
			for i in 7:
				var mx: int = x0 + int(hsh(i, 1, 61) * w)
				var mh: int = 26 + int(hsh(i, 2, 61) * 40)
				var stalk_w: int = 6 + int(hsh(i, 3, 61) * 6) * 2
				var cap_w: int = stalk_w * 3 + int(hsh(i, 4, 61) * 16)
				var col: Color = f1 if i % 2 == 0 else f2.lerp(f1, 0.4)
				cv.rect(mx, base_y - mh, stalk_w, mh, col)
				cv.rect(mx - (cap_w - stalk_w) / 2, base_y - mh - 6, cap_w, 6, col)
				cv.rect(mx - (cap_w - stalk_w) / 2 + 4, base_y - mh - 10, cap_w - 8, 4, col)
			for x in range(x0, x0 + w, 4):
				var hh: int = 6 + int((sin(x * 0.03) * 0.5 + 0.5) * 8 + hsh(x / 4, 0, 62) * 4)
				cv.rect(x, base_y - hh, 4, hh + 40, f2)
		"reef":
			# Окаменевший исполин: позвоночник и рёбра-арки П-образными сегментами.
			var spine_y: int = base_y - 58
			cv.rect(x0 + 20, spine_y, w - 40, 4, f1)
			for i in 9:
				var rx: int = x0 + 28 + i * 30
				var rh: int = 58 - absi(i - 4) * 5
				cv.rect(rx, spine_y, 4, rh, f1)
				cv.rect(rx + 4, spine_y + rh - 4, 6, 4, f1)
				cv.rect(rx - 6, spine_y + 4, 6, 3, f1)
				cv.rect(rx - 8, spine_y + 7, 3, 8, f1)
			for i in 3:
				cv.rect(x0 + w - 40 + i * 6, spine_y - 6 + i * 4, 6, 4, f1)
			for x in range(x0, x0 + w, 4):
				var hh2: int = 8 + int(hsh(x / 16, 0, 63) * 3) * 4
				cv.rect(x, base_y - hh2, 4, hh2 + 40, f2)
				if (x / 4) % 5 == 0:
					cv.rect(x, base_y - hh2 + 3, 4, 1, f2.lightened(0.08))
		"static":
			# Сигнальные шпили: тонкие мачты с поперечинами и квадратными капсулами.
			for i in 6:
				var sx: int = x0 + 18 + int(hsh(i, 1, 64) * (w - 30))
				var sh: int = 40 + int(hsh(i, 2, 64) * 46)
				cv.rect(sx, base_y - sh, 2, sh, f1)
				for k in 4:
					var yy: int = base_y - sh + 6 + k * 10
					cv.rect(sx - 4, yy, 10, 1, f1)
				cv.rect(sx - 3, base_y - sh - 6, 8, 6, f1)
				if tod == "night":
					cv.glow(sx, base_y - sh - 8, c("danger"), 0.9)
			for x in range(x0, x0 + w, 4):
				var hh3: int = 6 + int(hsh(x / 8, 0, 65) * 4) * 3
				cv.rect(x, base_y - hh3, 4, hh3 + 40, f2)


# ================================================================ ТАЙЛЫ

func _bio_cols(bio: int) -> Array:
	match bio:
		1:
			return [c("m_base"), c("m_dark"), c("m_hi"), c("m_glow")]
		2:
			return [c("d_base"), c("d_dark"), c("d_hi"), c("d_glow")]
	return [c("s_base"), c("s_dark"), c("s_hi"), c("s_top")]


## Тайл kind в пикселях (x0, y0). bio: 0 поверхность, 1 средние пещеры, 2 глубина.
## m — открытые стороны (сосед не твёрдый): 1 верх, 2 право, 4 низ, 8 лево.
## Края остаются прямыми: «автотайлинг» меняет только кайму внутри квадрата
## и наросты, которые торчат в соседнюю пустую клетку.
func tile(cv: Cv, kind: int, bio: int, x0: int, y0: int, m: int) -> void:
	match kind:
		K.AIR:
			return
		K.GROUND:
			_ground(cv, bio, x0, y0, m)
		K.BED:
			_bedrock(cv, x0, y0)
		K.COPPER, K.IRON, K.COAL, K.CRYSTAL, K.SCRAP:
			_ground(cv, bio, x0, y0, m)
			_ore(cv, kind, x0, y0)
		K.LAVA:
			_lava(cv, x0, y0, m)
		K.WATER:
			_water(cv, x0, y0, m)
		_:
			_metal_tile(cv, kind, x0, y0, m)


func _ground(cv: Cv, bio: int, x0: int, y0: int, m: int) -> void:
	var bc: Array = _bio_cols(bio)
	var base: Color = bc[0]
	var dark: Color = bc[1]
	var hi: Color = bc[2]
	for y in 16:
		for x in 16:
			var gx: int = x0 + x
			var gy: int = y0 + y
			var col: Color = base
			match cid:
				"spore":
					# Мягкая «войлочная» фактура: пятна 2×2 и нити мицелия.
					var n: float = hsh(gx >> 2, gy >> 2, 3 + bio)
					col = base.lerp(dark if n < 0.5 else hi, absf(n - 0.5) * 0.7)
					var n2: float = hsh(gx >> 1, gy >> 1, 4 + bio)
					if n2 < 0.06:
						col = dark
					elif n2 > 0.96:
						col = hi
					var th: float = sin(gx * 0.55 + sin(gy * 0.35 + bio) * 2.2)
					if absf(th) < 0.07 and hsh(gx >> 3, gy >> 3, 9) > 0.45:
						col = hi.lerp(base, 0.3) if bio != 1 else c("m_glow").lerp(base, 0.55)
				"reef":
					# Слоистые осадки: горизонтальные полосы, поры, обломки раковин.
					var off: int = int(hsh(gx >> 3, 0, 5 + bio) * 3.0)
					var band: int = ((gy + off) / 3) % 4
					if band == 2:
						col = hi.lerp(base, 0.55)
					elif band == 3:
						col = dark.lerp(base, 0.45)
					if hsh(gx, gy, 7) < 0.035:
						col = dark
					if hsh(gx >> 2, gy >> 2, 8 + bio) < 0.05 and (gx % 4) < 3 and (gy % 4) == 1:
						col = hi
				"static":
					# «Отсортированная» порода: в каждом столбце пиксели идут отрезками
					# 4–10 px от светлого к тёмному — как пиксель-сортировка в глитч-арте.
					var seg: int = 4 + int(hsh(gx, 0, 11 + bio) * 7.0)
					var ph: int = int(hsh(gx, 1, 11 + bio) * seg)
					var pos: int = (gy + ph) % seg
					var blk: int = (gy + ph) / seg
					var t: float = float(pos) / float(seg - 1)
					var amp: float = 0.35 + hsh(gx, blk, 12 + bio) * 0.65
					col = hi.lerp(dark, t * amp + (1.0 - amp) * 0.5)
					if hsh(gx, gy, 13 + bio) < 0.004 and bio != 0:
						col = c("m_glow") if bio == 1 else c("d_glow")
			cv.px(gx, gy, col)
	# Глубина: светящиеся трещины (жар снизу).
	if bio == 2 and hsh(x0 >> 4, y0 >> 4, 23) < 0.55:
		var cx: int = 3 + int(hsh(x0, y0, 24) * 10)
		for y in 16:
			if hsh(x0 + y, y0, 25) < 0.35:
				cx += 1 if hsh(x0, y0 + y, 26) > 0.5 else -1
			cx = clampi(cx, 1, 14)
			cv.glow(x0 + cx, y0 + y, bc[3], 0.55)
	# Кайма открытых сторон.
	if m & 2:
		cv.rect(x0 + 15, y0, 1, 16, dark)
	if m & 8:
		cv.rect(x0, y0, 1, 16, dark)
	if m & 4:
		_ceiling_edge(cv, bio, x0, y0, bc)
	if m & 1:
		_top_edge(cv, bio, x0, y0, bc)


## Верхняя кромка: лишайник/водоросли/антенная трава и наросты над клеткой.
func _top_edge(cv: Cv, bio: int, x0: int, y0: int, bc: Array) -> void:
	for x in 16:
		var gx: int = x0 + x
		var h1: float = hsh(gx, y0, 31)
		match cid:
			"spore":
				if bio == 0:
					var d: int = 2 + int(hsh(gx >> 1, y0, 32) * 3.0)
					cv.rect(gx, y0, 1, d, c("s_top"))
					cv.px(gx, y0, c("s_top2") if h1 > 0.6 else c("s_top"))
					if h1 < 0.3:
						var th: int = 1 + int(hsh(gx, y0, 33) * 3.0)
						cv.rect(gx, y0 - th, 1, th, c("s_top"))
						cv.px(gx, y0 - th, c("s_top2"))
				elif bio == 1:
					cv.px(gx, y0, c("m_hi"))
					if h1 < 0.12:
						cv.glow(gx, y0 - 1, c("m_glow"), 0.8)
				else:
					cv.px(gx, y0, c("d_hi"))
					if h1 < 0.15:
						cv.glow(gx, y0, c("d_glow"), 0.6)
			"reef":
				if bio == 0:
					var d2: int = 1 + int(hsh(gx >> 2, y0, 34) * 2.0)
					cv.rect(gx, y0, 1, d2, c("s_top"))
					if h1 < 0.18:
						cv.px(gx, y0 - 1, c("s_top2"))
				elif bio == 1:
					cv.px(gx, y0, c("m_hi"))
					if h1 < 0.1:
						cv.px(gx, y0 - 1, c("fl3"))
				else:
					if h1 < 0.7:
						cv.glow(gx, y0, c("d_glow"), 0.45 + h1 * 0.4)
					if h1 < 0.15:
						cv.glow(gx, y0 - 1, c("d_glow"), 0.6)
			"static":
				if bio == 0:
					cv.px(gx, y0, c("s_top"))
					if h1 < 0.55:
						var th2: int = 1 + int(hsh(gx, y0, 35) * 5.0)
						cv.rect(gx, y0 - th2, 1, th2, c("s_top"))
						if hsh(gx, y0, 36) < 0.4:
							cv.px(gx, y0 - th2, c("s_top2"))
				elif bio == 1:
					cv.px(gx, y0, c("m_hi"))
					if (gx % 2) == 0 and h1 < 0.5:
						cv.glow(gx, y0 + 1, c("m_glow"), 0.4)
				else:
					cv.px(gx, y0, c("d_hi"))
					if h1 < 0.25:
						cv.glow(gx, y0, c("d_glow"), 0.7)


## Нижняя кромка (потолок пещеры): гифы, ракушки, капли пиксель-сортировки.
func _ceiling_edge(cv: Cv, bio: int, x0: int, y0: int, bc: Array) -> void:
	var yb: int = y0 + 15
	cv.rect(x0, yb, 16, 1, bc[1])
	for x in 16:
		var gx: int = x0 + x
		var h1: float = hsh(gx, y0, 41)
		match cid:
			"spore":
				if bio == 1 and h1 < 0.3:
					var l: int = 2 + int(hsh(gx, y0, 42) * 7.0)
					cv.rect(gx, yb + 1, 1, l - 1, c("m_hi"))
					cv.glow(gx, yb + l, c("m_glow"), 0.9)
				elif bio == 0 and h1 < 0.25:
					cv.rect(gx, yb + 1, 1, 1 + int(hsh(gx, y0, 43) * 3.0), bc[1])
				elif bio == 2 and h1 < 0.15:
					cv.glow(gx, yb + 1, c("d_glow"), 0.5)
			"reef":
				if h1 < 0.2:
					cv.px(gx, yb + 1, c("fl3") if bio != 2 else c("d_hi"))
				if bio == 1 and h1 > 0.92:
					cv.glow(gx, yb, c("m_glow"), 0.7)
			"static":
				if bio == 1 and (gx + y0) % 2 == 0:
					cv.glow(gx, yb - 1, c("m_glow"), 0.35)
				if bio == 2 and h1 < 0.25:
					var l2: int = 3 + int(hsh(gx, y0, 44) * 9.0)
					for k in l2:
						var t: float = float(k) / float(l2)
						cv.glow(gx, yb + 1 + k, c("d_glow").lerp(c("lava"), t), 0.9 - t * 0.6)


## Задняя стенка пещеры: та же порода, сильно темнее, крупные блоки 4×4.
func _backwall(cv: Cv, bio: int, x0: int, y0: int) -> void:
	var bc: Array = _bio_cols(bio)
	var base: Color = (bc[0] as Color).darkened(0.42)
	for y in 16:
		for x in 16:
			var gx: int = x0 + x
			var gy: int = y0 + y
			var col: Color = base.lerp((bc[1] as Color).darkened(0.6), hsh(gx >> 2, gy >> 2, 241) * 0.8)
			match cid:
				"reef":
					if gy % 6 == 0:
						col = col.darkened(0.25)
				"static":
					if gx % 8 == 0 or gy % 8 == 0:
						col = col.darkened(0.3)
				_:
					if hsh(gx >> 1, gy >> 1, 242) < 0.08:
						col = col.darkened(0.3)
			cv.px(gx, gy, col)


func _bedrock(cv: Cv, x0: int, y0: int) -> void:
	var b: Color = c("bed")
	for y in 16:
		for x in 16:
			var n: float = hsh((x0 + x) >> 2, (y0 + y) >> 2, 71)
			cv.px(x0 + x, y0 + y, b.lightened(0.06) if n > 0.7 else b)
	cv.rect(x0, y0, 16, 1, b.lightened(0.1))


## Руды: у каждой свой УЗОР (не только цвет) — так их различают и при дальтонизме.
## Медь — диагональные жилы, железо — квадратные самородки, уголь — чёрные блоки
## с бликом, кристалл — вертикальные призмы со свечением, хлам — пластина с заклёпками.
func _ore(cv: Cv, kind: int, x0: int, y0: int) -> void:
	var t: Image = Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	t.fill(Color(0, 0, 0, 0))
	var sd: int = x0 * 7 + y0 * 13
	var dk: Color = Color.BLACK
	var glowing: bool = false
	var glints: Array[Vector2i] = []		## Блики: слабо светятся — руду видно издалека.
	match kind:
		K.COPPER:
			dk = c("copper_d")
			for v in 3:
				var vx: int = 1 + int(hsh(v, sd, 81) * 8.0)
				var vy: int = 1 + v * 5
				for k in 6:
					var xx: int = vx + k
					var yy: int = vy + k / 2
					if xx < 15 and yy < 15:
						t.set_pixel(xx, yy, c("copper"))
						t.set_pixel(xx, yy + 1, c("copper").darkened(0.15))
				t.set_pixel(vx, vy, c("copper").lightened(0.35))
				glints.append(Vector2i(vx, vy))
		K.IRON:
			dk = c("iron_d")
			for v in 3:
				var nx: int = [2, 9, 5][v] + int(hsh(v, sd, 82) * 2.0)
				var ny: int = [3, 4, 10][v]
				var nw: int = 4 if v != 2 else 5
				for yy in 3:
					for xx in nw:
						t.set_pixel(nx + xx, ny + yy, c("iron"))
				t.set_pixel(nx, ny, c("iron").lightened(0.4))
				glints.append(Vector2i(nx, ny))
				t.set_pixel(nx + nw - 1, ny + 2, c("iron").darkened(0.25))
		K.COAL:
			dk = c("coal").lightened(0.25)
			for v in 5:
				var cx: int = [2, 8, 11, 4, 9][v]
				var cy: int = [2, 3, 8, 9, 12][v]
				for yy in 2:
					for xx in 3:
						t.set_pixel(cx + xx, cy + yy, c("coal"))
				t.set_pixel(cx, cy, c("coal_hi"))
				glints.append(Vector2i(cx, cy))
		K.CRYSTAL:
			dk = c("crystal_d")
			glowing = true
			for v in 3:
				var px0: int = [3, 7, 11][v]
				var ph: int = [7, 11, 6][v]
				for yy in ph:
					for xx in 2:
						t.set_pixel(px0 + xx, 14 - yy, c("crystal") if xx == 1 else c("crystal").lightened(0.4))
				t.set_pixel(px0, 14 - ph, Color.WHITE)
		K.SCRAP:
			dk = c("scrap_d")
			for yy in 4:
				for xx in 7:
					t.set_pixel(3 + xx, 5 + yy, c("scrap"))
			t.set_pixel(3, 5, c("scrap_d"))
			t.set_pixel(9, 5, c("scrap_d"))
			t.set_pixel(3, 8, c("scrap_d"))
			t.set_pixel(9, 8, c("scrap_d"))
			for yy in 5:
				t.set_pixel(11, 8 + yy - 2, c("scrap").darkened(0.2))
			t.set_pixel(6, 11, c("hazard").darkened(0.2))
			glints.append(Vector2i(6, 11))
			t.set_pixel(5, 12, c("scrap_d"))
	# Тёмный контур вокруг узора — руда читается на любой породе.
	var src: Image = t.duplicate()
	for y in 16:
		for x in 16:
			if src.get_pixel(x, y).a > 0.0:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + d
				if q.x >= 0 and q.y >= 0 and q.x < 16 and q.y < 16 and src.get_pixel(q.x, q.y).a > 0.0:
					t.set_pixel(x, y, dk)
					break
	for y in 16:
		for x in 16:
			var p: Color = t.get_pixel(x, y)
			if p.a <= 0.0:
				continue
			if glowing and src.get_pixel(x, y).a > 0.0:
				cv.glow(x0 + x, y0 + y, p, 0.9)
			elif glints.has(Vector2i(x, y)):
				cv.glow(x0 + x, y0 + y, p, 0.55)
			else:
				cv.px(x0 + x, y0 + y, p)
	if glowing:
		cv.light(x0 + 8, y0 + 8, 34.0, c("crystal"), 0.55)


func _lava(cv: Cv, x0: int, y0: int, m: int) -> void:
	for y in 16:
		for x in 16:
			var gx: int = x0 + x
			var gy: int = y0 + y
			var col: Color = c("lava")
			var n: float = hsh(gx >> 1, gy >> 1, 91)
			if n > 0.82:
				col = c("lava_hi")
			elif n < 0.18:
				col = c("lava").darkened(0.25)
			if m & 1 and y < 2:
				col = c("lava_hi")
			cv.glow(gx, gy, col, 1.0)
	if m & 1:
		for x in 16:
			if hsh(x0 + x, y0, 92) < 0.25:
				cv.glow(x0 + x, y0 - 1, c("lava_hi"), 0.8)
	cv.light(x0 + 8, y0 + 4, 70.0, c("lava"), 0.5)


func _water(cv: Cv, x0: int, y0: int, m: int) -> void:
	for y in 16:
		for x in 16:
			var col: Color = c("water")
			if (m & 1) and y == 0:
				col = c("water_hi")
			elif cid == "reef" and (y0 + y) % 4 == 0 and hsh(x0 + x >> 2, y0 + y, 93) > 0.5:
				col = c("water").lightened(0.15)
			col.a = 0.82
			cv.px(x0 + x, y0 + y, col)


func _metal_tile(cv: Cv, kind: int, x0: int, y0: int, m: int) -> void:
	var mt: Color = c("metal")
	var md: Color = c("metal_d")
	var mh: Color = c("metal_hi")
	var fr: Color = c("frame")
	match kind:
		K.PANEL:
			cv.rect(x0, y0, 16, 16, mt)
			cv.rect(x0, y0, 16, 1, mh)
			cv.rect(x0, y0 + 15, 16, 1, md)
			cv.rect(x0 + 15, y0, 1, 16, md)
			for p in [Vector2i(2, 3), Vector2i(13, 3), Vector2i(2, 12), Vector2i(13, 12)]:
				cv.px(x0 + p.x, y0 + p.y, fr)
			match cid:
				"spore":
					cv.rect(x0, y0 + 6, 16, 2, c("hazard").lerp(mt, 0.25))
					for x in 16:
						if hsh(x0 + x, y0, 101) < 0.35:
							cv.rect(x0 + x, y0, 1, 1 + int(hsh(x0 + x, y0, 102) * 3.0), c("s_top"))
				"reef":
					for x in 16:
						if ((x + (y0 >> 4)) / 2) % 2 == 0:
							cv.px(x0 + x, y0 + 1, c("hazard"))
							cv.px(x0 + x, y0 + 2, c("hazard"))
					for x in 16:
						if hsh(x0 + x, y0, 103) < 0.3:
							cv.px(x0 + x, y0 + 14 - int(hsh(x0 + x, y0, 104) * 2.0), c("fl3"))
				"static":
					cv.rect(x0, y0, 16, 16, mt)
					cv.rect(x0, y0, 16, 1, fr)
					cv.rect(x0, y0 + 15, 16, 1, fr)
					cv.rect(x0 + 15, y0, 1, 16, fr)
					cv.rect(x0, y0 + 2, 16, 1, mh)
					cv.rect(x0 + 1, y0 + 6, 14, 2, c("hazard"))
					cv.glow(x0 + 12, y0 + 11, c("screen_hi"), 0.9)
		K.WALL:
			cv.rect(x0, y0, 16, 16, md)
			for x in range(1, 16, 4):
				cv.rect(x0 + x, y0, 2, 16, mt)
			cv.rect(x0, y0, 16, 1, mh)
			cv.rect(x0, y0 + 15, 16, 1, fr)
			if cid != "spore":
				for y in 3:
					for x in 16:
						if ((x + y) / 2) % 2 == 0:
							cv.px(x0 + x, y0 + 1 + y, c("hazard"))
						else:
							cv.px(x0 + x, y0 + 1 + y, fr)
		K.GLASS:
			cv.rect(x0, y0, 16, 16, Color(c("water_hi").r, c("water_hi").g, c("water_hi").b, 0.3))
			cv.rect(x0, y0, 16, 1, fr)
			cv.rect(x0, y0 + 15, 16, 1, fr)
			cv.rect(x0, y0, 1, 16, fr)
			cv.rect(x0 + 15, y0, 1, 16, fr)
			for k in 4:
				cv.px(x0 + 3 + k, y0 + 9 - k, Color(1, 1, 1, 0.7))
				cv.px(x0 + 4 + k, y0 + 12 - k, Color(1, 1, 1, 0.45))
		K.TERM:
			cv.rect(x0, y0, 16, 16, md)
			cv.rect(x0, y0, 16, 1, mh)
			cv.rect(x0 + 2, y0 + 2, 12, 8, c("screen"))
			for l in 3:
				var lw: int = 3 + int(hsh(x0, y0 + l, 105) * 7.0)
				cv.glow_rect(x0 + 3, y0 + 3 + l * 2, lw, 1, c("screen_hi"), 0.9)
			cv.rect(x0 + 3, y0 + 12, 2, 2, c("hazard"))
			cv.rect(x0 + 7, y0 + 12, 2, 2, fr)
			cv.rect(x0 + 11, y0 + 12, 2, 2, fr)
			cv.light(x0 + 8, y0 + 6, 26.0, c("screen_hi"), 0.35)
		K.RELAY:
			cv.rect(x0, y0, 16, 16, fr)
			cv.rect(x0 + 1, y0 + 1, 14, 14, md)
			cv.glow_rect(x0 + 4, y0 + 4, 8, 8, c("bio"), 1.0)
			cv.glow_rect(x0 + 6, y0 + 6, 4, 4, Color.WHITE, 1.0)
			cv.light(x0 + 8, y0 + 8, 44.0, c("bio"), 0.4)
		K.LAMP:
			_lamp_block(cv, x0, y0)


## Светоблок (светокристалл): у каждого концепта свой источник света.
func _lamp_block(cv: Cv, x0: int, y0: int) -> void:
	var fr: Color = c("frame")
	match cid:
		"spore":
			# Клетка с живой светящейся колонией.
			cv.rect(x0 + 2, y0, 12, 16, Color(0, 0, 0, 0))
			cv.rect(x0 + 2, y0, 12, 2, fr)
			cv.rect(x0 + 2, y0 + 14, 12, 2, fr)
			cv.glow_rect(x0 + 4, y0 + 3, 8, 10, c("bio"), 0.9)
			cv.glow_rect(x0 + 6, y0 + 5, 4, 6, Color("#E8FFF8"), 1.0)
			for x in [2, 6, 10, 13]:
				cv.rect(x0 + x, y0 + 2, 1, 12, fr)
			cv.light(x0 + 8, y0 + 8, 64.0, c("bio"), 0.9)
		"reef":
			# Банка с планктоном.
			cv.rect(x0 + 3, y0 + 1, 10, 2, fr)
			cv.glow_rect(x0 + 3, y0 + 3, 10, 12, c("bio").darkened(0.3), 0.8)
			for k in 8:
				cv.glow(x0 + 4 + int(hsh(k, y0, 106) * 8.0), y0 + 4 + int(hsh(k, x0, 107) * 10.0), Color("#F8FFD0"), 1.0)
			cv.rect(x0 + 3, y0 + 15, 10, 1, fr)
			cv.light(x0 + 8, y0 + 8, 64.0, c("bio"), 0.9)
		_:
			# Кристалл в рамке.
			cv.rect(x0 + 1, y0 + 1, 14, 14, fr)
			for yy in 12:
				var hw: int = 1 + (mini(yy, 11 - yy) / 2)
				cv.glow_rect(x0 + 8 - hw, y0 + 2 + yy, hw * 2, 1, c("crystal"), 1.0)
			cv.glow_rect(x0 + 7, y0 + 4, 1, 6, Color.WHITE, 1.0)
			cv.light(x0 + 8, y0 + 8, 64.0, c("crystal"), 0.9)


# ================================================================ ФЛОРА (только прямоугольники)

## Поверхностная флора: вид 0 — крупная, 1 — средняя, 2 — мелкая.
## x — левый край клетки, gy — верх грунта (растение стоит на нём).
func flora_surface(cv: Cv, kind: int, x: int, gy: int, sz: int, night: bool) -> void:
	match cid:
		"spore":
			_fl_spore_surface(cv, kind, x, gy, sz, night)
		"reef":
			_fl_reef_surface(cv, kind, x, gy, sz, night)
		"static":
			_fl_static_surface(cv, kind, x, gy, sz, night)


func _fl_spore_surface(cv: Cv, kind: int, x: int, gy: int, sz: int, night: bool) -> void:
	var st: Color = c("fl3")
	var cap: Color = c("fl1")
	var capd: Color = c("fl1_d")
	match kind:
		0:
			# «Свечник»: высокий стебель со стопкой квадратных шляпок-дождевиков.
			var hgt: int = 30 + sz * 10
			cv.rect(x + 6, gy - hgt, 3, hgt, st)
			cv.rect(x + 8, gy - hgt, 1, hgt, st.darkened(0.18))
			var caps: Array = [[-4, 15, 6], [10, 10, 4], [19, 7, 3]]
			for i in caps.size():
				var cw: int = caps[i][1] + sz * 2
				var ch: int = caps[i][2]
				var cx: int = x + 7 - cw / 2
				var cy: int = gy - hgt + caps[i][0]
				cv.rect(cx, cy, cw, ch, cap)
				cv.rect(cx, cy + ch - 1, cw, 1, capd)
				cv.rect(cx, cy, cw, 1, cap.lightened(0.2))
				for sp in cw / 3:
					var sx: int = cx + 1 + int(hsh(sp, cy, 111) * (cw - 2))
					var sy: int = cy + 1 + int(hsh(sp, cx, 112) * maxf(ch - 2, 1.0))
					if night:
						cv.glow(sx, sy, c("bio"), 0.85)
					else:
						cv.px(sx, sy, c("fl3"))
				if night:
					cv.light(cx + cw * 0.5, cy + ch * 0.5, 28.0, c("bio"), 0.35)
		1:
			# «Пузырник»: связка квадратных пузырей на нитях.
			for b in 4:
				var bx: int = x + 1 + b * 4 + int(hsh(b, x, 113) * 2.0)
				var by: int = gy - 18 - int(hsh(b, x, 114) * 16.0) - sz * 4
				cv.rect(bx + 1, by + 5, 1, gy - by - 5, c("fl2_d"))
				cv.rect(bx - 1, by, 5, 5, Color(c("fl2").r, c("fl2").g, c("fl2").b, 0.85))
				cv.rect(bx - 1, by, 5, 1, c("fl2").lightened(0.25))
				cv.px(bx, by + 1, Color(1, 1, 1, 0.8))
				if night:
					cv.glow(bx + 1, by + 2, c("fl2"), 0.5)
		_:
			# Низкая «полка»: плоские пластины одна над другой.
			cv.rect(x + 2, gy - 4, 12, 2, capd)
			cv.rect(x + 4, gy - 7, 8, 2, cap)
			cv.rect(x + 7, gy - 7, 2, 7, st)
			if night:
				cv.glow(x + 5, gy - 7, c("bio"), 0.7)


func _fl_reef_surface(cv: Cv, kind: int, x: int, gy: int, sz: int, night: bool) -> void:
	var cr: Color = c("fl1")
	var crd: Color = c("fl1_d")
	var tip: Color = c("fl3")
	match kind:
		0:
			# «Ветвянка»: коралл с ветвями под прямым углом, кончики выбелены.
			var hgt: int = 34 + sz * 10
			cv.rect(x + 6, gy - hgt, 4, hgt, cr)
			cv.rect(x + 9, gy - hgt, 1, hgt, crd)
			var arms: Array = [[-12, 1, 8], [-20, -1, 7], [-28, 1, 6], [-34, -1, 5]]
			for a in arms:
				var ay: int = gy + a[0] - sz * 4
				var dir: int = a[1]
				var ln: int = a[2]
				var ax: int = x + 10 if dir > 0 else x + 6 - ln
				cv.rect(ax, ay, ln, 3, cr)
				var ux: int = ax + ln - 3 if dir > 0 else ax
				cv.rect(ux, ay - 8, 3, 8, cr)
				cv.rect(ux, ay - 10, 3, 2, tip)
			cv.rect(x + 6, gy - hgt - 2, 4, 2, tip)
			if night:
				for k in 6:
					cv.glow(x + 2 + int(hsh(k, x, 121) * 14.0), gy - 6 - int(hsh(k, x, 122) * hgt), c("bio"), 0.7)
		1:
			# «Губка»: широкая колонна с решёткой пор.
			var hh: int = 20 + sz * 8
			cv.rect(x + 2, gy - hh, 12, hh, c("fl2"))
			cv.rect(x + 2, gy - hh, 12, 1, c("fl2").lightened(0.25))
			cv.rect(x + 13, gy - hh, 1, hh, c("fl2_d"))
			for yy in range(gy - hh + 3, gy - 2, 4):
				for xx in range(x + 4, x + 12, 3):
					cv.rect(xx, yy, 2, 2, c("fl2_d"))
			cv.rect(x + 5, gy - hh - 3, 6, 3, c("fl2_d"))
		_:
			# «Актиния»: квадратное основание и бахрома через пиксель.
			cv.rect(x + 4, gy - 5, 8, 5, c("s_top"))
			for k in 8:
				if k % 2 == 0:
					cv.rect(x + 4 + k, gy - 8, 1, 3, tip)
				else:
					cv.rect(x + 4 + k, gy - 7, 1, 2, c("s_top2"))
			if night:
				cv.glow(x + 7, gy - 6, c("bio"), 0.8)


func _fl_static_surface(cv: Cv, kind: int, x: int, gy: int, sz: int, night: bool) -> void:
	match kind:
		0:
			# «Сортировщик»: ствол и крона, где пиксели «отсортированы» в столбцы-градиенты.
			var hgt: int = 40 + sz * 8
			cv.rect(x + 6, gy - hgt + 14, 3, hgt - 14, c("fl2_d"))
			var cw: int = 22 + sz * 4
			var cx: int = x + 7 - cw / 2
			var ctop: int = gy - hgt
			for xx in cw:
				var run: int = 10 + int(hsh(xx + x, gy, 131) * 12.0)
				for k in run:
					var t: float = float(k) / float(run)
					var col: Color = c("s_top2").lerp(Color("#46C8B8"), clampf(t * 1.6, 0.0, 1.0))
					if t > 0.6:
						col = Color("#46C8B8").lerp(c("fl3"), (t - 0.6) * 2.5)
					if night and k < 2:
						cv.glow(cx + xx, ctop + k + int(hsh(xx, x, 132) * 3.0), col, 0.6)
					else:
						cv.px(cx + xx, ctop + k + int(hsh(xx, x, 132) * 3.0), col)
		1:
			# «Антенник»: тонкий стебель с квадратными приёмниками; мигают.
			var hh: int = 44 + sz * 8
			cv.rect(x + 7, gy - hh, 1, hh, c("fl1_d"))
			for k in 4:
				var py: int = gy - hh + k * 11
				var px0: int = x + 5 if k % 2 == 0 else x + 7
				cv.rect(px0, py, 3, 3, c("fl1"))
				cv.rect(px0, py + 2, 3, 1, c("fl1_d"))
				if night or k == 0:
					cv.glow(px0 + 1, py + 1, c("bio") if k == 0 else c("s_top2"), 0.9)
			cv.light(x + 8, gy - hh, 24.0, c("bio"), 0.3 if night else 0.0)
		_:
			# «Шумоцвет»: квадратные листья, заполненные телевизионным шумом.
			for lf in 4:
				var lx: int = x + [1, 7, 3, 9][lf]
				var ly: int = gy - [6, 9, 13, 16][lf]
				var shift: int = 2 if lf == 2 else 0
				for yy in 5:
					for xx in 5:
						var n: float = hsh(lx + xx, ly + yy, 133 + lf)
						var col2: Color = c("fl2") if n > 0.5 else c("fl2_d")
						if n > 0.92:
							col2 = c("s_top2")
						cv.px(lx + xx + (shift if yy < 2 else 0), ly + yy, col2)
			cv.rect(x + 7, gy - 4, 1, 4, c("fl2_d"))


## Флора пещер: висячая (с потолка cy вниз) и напольная (на gy вверх).
func flora_cave(cv: Cv, hanging: bool, x: int, y: int, sz: int) -> void:
	match cid:
		"spore":
			if hanging:
				# Завеса мицелия: нити разной длины со светящимися кончиками.
				for k in 7:
					var l: int = 10 + int(hsh(k, x, 141) * (18 + sz * 8))
					var xx: int = x + 1 + k * 2
					cv.rect(xx, y, 1, l, c("m_hi").lerp(c("m_glow"), 0.25))
					cv.glow(xx, y + l, c("m_glow"), 1.0)
					cv.glow(xx, y + l - 1, c("m_glow"), 0.6)
				cv.light(x + 8, y + 16, 34.0, c("m_glow"), 0.45)
			else:
				# Трутовики-полки на ножке.
				cv.rect(x + 7, y - 14, 2, 14, c("m_hi"))
				cv.rect(x + 2, y - 10, 12, 2, c("fl2_d"))
				cv.rect(x + 4, y - 15, 9, 2, c("fl2"))
				cv.glow_rect(x + 4, y - 9, 8, 1, c("m_glow"), 0.6)
				cv.glow_rect(x + 5, y - 14, 7, 1, c("m_glow"), 0.6)
				cv.light(x + 8, y - 10, 24.0, c("m_glow"), 0.3)
		"reef":
			if hanging:
				# Ламинария: длинные ленты с поплавками-квадратами.
				for k in 2:
					var l2: int = 26 + sz * 10 + k * 8
					var xx2: int = x + 4 + k * 6
					cv.rect(xx2, y, 2, l2, Color("#4F7A4E"))
					for b in range(4, l2, 7):
						var side: int = 2 if (b / 7) % 2 == 0 else -3
						cv.rect(xx2 + side, y + b, 3, 2, Color("#6E9A5E"))
					cv.rect(xx2, y + l2, 2, 2, Color("#9ABA6A"))
				for k in 6:
					cv.glow(x + int(hsh(k, x, 142) * 18.0), y + 6 + int(hsh(k, x, 143) * 30.0), c("m_glow"), 0.9)
				cv.light(x + 8, y + 20, 30.0, c("m_glow"), 0.3)
			else:
				var l3: int = 20 + sz * 8
				cv.rect(x + 7, y - l3, 2, l3, Color("#4F7A4E"))
				for b2 in range(4, l3, 6):
					cv.rect(x + (9 if (b2 / 6) % 2 == 0 else 4), y - b2, 3, 2, Color("#6E9A5E"))
				cv.glow(x + 8, y - l3 - 1, c("m_glow"), 1.0)
				cv.light(x + 8, y - l3, 20.0, c("m_glow"), 0.35)
		"static":
			if hanging:
				# Сталактиты пиксель-сортировки: вертикальные градиенты.
				for k in 5:
					var l4: int = 8 + int(hsh(k, x, 144) * (14 + sz * 6))
					for j in l4:
						var t: float = float(j) / float(l4)
						cv.glow(x + 2 + k * 3, y + j, c("m_glow").lerp(c("fl3"), t), 0.75 - t * 0.5)
						cv.px(x + 3 + k * 3, y + j, c("m_hi"))
				cv.light(x + 8, y + 10, 26.0, c("m_glow"), 0.3)
			else:
				# Решётчатый кристалл: прямоугольные призмы.
				for k in 3:
					var ph: int = [10, 16, 8][k] + sz * 3
					var pxk: int = x + 3 + k * 4
					cv.glow_rect(pxk, y - ph, 3, ph, c("crystal"), 0.85)
					cv.glow_rect(pxk, y - ph, 1, ph, Color.WHITE, 0.6)
				cv.light(x + 8, y - 8, 36.0, c("crystal"), 0.5)


## Флора глубины у лавы.
func flora_deep(cv: Cv, x: int, gy: int, sz: int) -> void:
	match cid:
		"spore":
			# Мембранные мешки на общем корне: квадрат в квадрате, светящееся ядро,
			# сверху — трубки, из которых сочатся споры.
			var sizes: Array = [6, 11, 8]
			var offs: Array = [0, 5, 14]
			cv.rect(x, gy - 2, 22, 2, c("d_hi"))
			for k in 3:
				var sq: int = sizes[k] + sz * 2
				var bx: int = x + offs[k]
				var by: int = gy - 2 - sq - (4 if k == 1 else 0)
				cv.rect(bx + sq / 2, by + sq, 1, gy - by - sq, c("d_hi"))
				cv.rect(bx, by, sq, sq, c("d_hi"))
				cv.rect(bx + 1, by + 1, sq - 2, sq - 2, Color("#C8786A"))
				cv.rect(bx + 1, by + 1, sq - 2, 1, Color("#E8A090"))
				var core: int = maxi(sq / 3, 2)
				cv.glow_rect(bx + (sq - core) / 2, by + (sq - core) / 2, core, core, c("d_glow"), 0.95)
				if k == 1:
					cv.rect(bx + 2, by - 5, 2, 5, c("d_hi"))
					cv.rect(bx + 7, by - 3, 2, 3, c("d_hi"))
					cv.glow(bx + 2, by - 7, c("d_glow"), 0.7)
					cv.glow(bx + 8, by - 6, c("d_glow"), 0.5)
			cv.light(x + 10, gy - 10, 34.0, c("d_glow"), 0.45)
		"reef":
			# Трубочники: белые трубки с алыми кончиками + чёрный курильщик.
			for k in 4:
				var th: int = 8 + int(hsh(k, x, 151) * 12.0) + sz * 3
				var tx: int = x + 1 + k * 4
				cv.rect(tx, gy - th, 2, th, c("fl3"))
				cv.glow_rect(tx, gy - th - 2, 2, 2, Color("#FF4A3A"), 0.8)
			cv.light(x + 8, gy - 12, 24.0, Color("#FF4A3A"), 0.3)
		"static":
			# Битые цветы: блок с RGB-расслоением.
			for k in 2:
				var bx2: int = x + 2 + k * 7
				var by2: int = gy - 10 - k * 6 - sz * 2
				cv.rect(bx2, by2 + 4, 1, gy - by2 - 4, c("d_hi"))
				cv.glow_rect(bx2 - 3, by2, 6, 5, Color("#FF3A3A"), 0.5)
				cv.glow_rect(bx2 - 1, by2, 6, 5, Color("#3A7AFF"), 0.5)
				cv.glow_rect(bx2 - 2, by2, 6, 5, c("d_glow"), 0.95)
			cv.light(x + 8, gy - 12, 30.0, c("d_glow"), 0.45)


# ================================================================ ГЕРОЙ «КЕРБЕР-9»

## Скафандр. pose: stand | run | dig. cust: col (основной цвет — кастомизация),
## helm (0/1 — вариант шлема), acc (lamp | antenna | tank | none), ph (фантом-палитра).
## Цветовые слоты одинаковы у всех концептов: основной (игрок), вторичный (концепт),
## визор и фонарь (концепт), контур. Габарит 12×22 = нынешний SIZE игрока.
func hero(pose: String, cust: Dictionary = {}) -> Spr:
	var s: Spr = Spr.new()
	var pal: Dictionary = {
		"pc": cust.get("col", c("suit")), "c2": c("suit2"), "c2d": c("suit2_d"),
		"vis": c("visor"), "vhi": c("visor_hi"), "lamp": c("lamp"), "out": c("outline"),
		"helm": cust.get("helm", 0), "acc": cust.get("acc", "lamp"), "ph": cust.get("ph", false),
		"mirror": cust.get("mirror", false),
	}
	if pal["ph"]:
		pal["c2"] = c("ph").lightened(0.1)
		pal["c2d"] = c("ph2")
		pal["vis"] = c("danger")
		pal["vhi"] = c("danger").lightened(0.4)
	match cid:
		"spore":
			_hero_spore(s, pose, pal)
		"reef":
			_hero_reef(s, pose, pal)
		"static":
			_hero_static(s, pose, pal)
	return s


func _legs(s: Spr, pose: String, pc: Color, pd: Color, boot: Color, lw: int, lh: int, bw: int) -> void:
	match pose:
		"run":
			s.r(-5, -lh - 2, lw, lh - 1, pd)
			s.r(-7, -4, bw, 2, boot)
			s.r(1, -lh - 2, lw, lh, pc)
			s.r(2, -2, bw + 1, 2, boot)
		"dig":
			s.r(-6, -lh - 2, lw, lh, pd)
			s.r(-7, -2, bw, 2, boot)
			s.r(2, -lh - 2, lw, lh, pc)
			s.r(2, -2, bw + 1, 2, boot)
		_:
			s.r(-4, -lh - 2, lw, lh, pd)
			s.r(-5, -2, bw, 2, boot)
			s.r(1, -lh - 2, lw, lh, pc)
			s.r(1, -2, bw + 1, 2, boot)


func _tool(s: Spr, hx: int, hy: int) -> void:
	# Резак-кирка: рукоять ступенчатой линией и квадратная головка.
	s.line(hx, hy, hx + 5, hy - 5, Color("#6A5A4A"))
	s.r(hx + 4, hy - 8, 4, 2, Color("#C8CED6"))
	s.r(hx + 7, hy - 7, 2, 4, Color("#C8CED6"))


func _hero_spore(s: Spr, pose: String, pal: Dictionary) -> void:
	# Тип A: мягкий «надувной» костюм из ткани, большой квадратный шлем,
	# ранец-фильтр спор (жёлтый патрон), массивные боты.
	var pc: Color = pal["pc"]
	var pd: Color = pc.darkened(0.28)
	var c2: Color = pal["c2"]
	var c2d: Color = pal["c2d"]
	var b: int = -1 if pose == "run" else 0
	_legs(s, pose, pc, pd, c2d.darkened(0.35), 4, 6, 4)
	var tank_h: int = 12 if pal["acc"] == "tank" else 9
	s.r(-9, -17 + b, 4, tank_h, c2d)
	s.r(-9, -17 + b, 4, 1, c2)
	s.r(-10, -15 + b, 1, 5, c("hazard"))
	# Корпус
	s.r(-5, -17 + b, 10, 10, pc)
	s.r(-5, -17 + b, 10, 1, pc.lightened(0.2))
	s.r(-5, -9 + b, 10, 2, c2d)
	s.r(1, -15 + b, 3, 3, c2)
	s.p(2, -14 + b, c("screen_hi"))
	# Шлем
	if pal["helm"] == 0:
		s.r(-5, -26 + b, 10, 9, c2)
		s.r(-5, -26 + b, 10, 1, c2.lightened(0.1))
		s.r(-5, -18 + b, 10, 1, c2d)
		s.r(-1, -24 + b, 6, 4, pal["vis"])
		s.r(0, -24 + b, 2, 1, pal["vhi"])
	else:
		s.r(-4, -28 + b, 8, 2, c2)
		s.r(-5, -26 + b, 10, 9, c2)
		s.r(-5, -18 + b, 10, 1, c2d)
		s.r(-2, -26 + b, 7, 6, pal["vis"])
		s.r(-1, -26 + b, 2, 2, pal["vhi"])
	if pal["acc"] == "antenna":
		s.r(-4, -31 + b, 1, 5, c2d)
		s.e(-4, -32 + b, 1, 1, c("danger"))
	elif pal["acc"] != "none" and not pal["ph"]:
		s.e(4, -27 + b, 2, 2, pal["lamp"])
	# Рука
	match pose:
		"dig":
			s.r(1, -15 + b, 7, 3, pd)
			s.r(8, -15 + b, 2, 3, c2d)
		"run":
			s.r(-3, -15 + b, 3, 6, pd)
			s.r(-3, -9 + b, 3, 2, c2d)
		_:
			s.r(-1, -16 + b, 3, 7, pd)
			s.r(-1, -9 + b, 3, 2, c2d)
	s.outline(pal["out"])
	if pose == "dig":
		_tool(s, 9, -14 + b)


func _hero_reef(s: Spr, pose: String, pal: Dictionary) -> void:
	# Тип B: водолазный: шлем шире плеч с квадратным иллюминатором в толстой раме,
	# узкий корпус, два баллона, шланг, грузовые боты, фонарь на груди.
	var pc: Color = pal["pc"]
	var pd: Color = pc.darkened(0.3)
	var c2: Color = pal["c2"]
	var c2d: Color = pal["c2d"]
	var b: int = -1 if pose == "run" else 0
	_legs(s, pose, pc, pd, c2d.darkened(0.2), 3, 7, 5)
	var tank_h: int = 12 if pal["acc"] == "tank" else 10
	s.r(-8, -17 + b, 2, tank_h, c2)
	s.r(-6, -17 + b, 2, tank_h, c2d)
	s.r(-8, -18 + b, 4, 1, c2d)
	# Корпус
	s.r(-4, -16 + b, 8, 9, pc)
	s.r(-4, -16 + b, 8, 1, pc.lightened(0.2))
	s.r(-4, -9 + b, 8, 2, c2d)
	if pal["acc"] != "none" and not pal["ph"]:
		s.e(2, -14 + b, 2, 2, pal["lamp"])
	# Шлем-короб шире плеч
	s.r(-6, -27 + b, 12, 11, c2)
	s.r(-6, -27 + b, 12, 1, c2.lightened(0.2))
	s.r(-6, -17 + b, 12, 1, c2d)
	s.r(-5, -29 + b, 4, 2, c2d)
	if pal["helm"] == 0:
		var px0: int = 0 if not pal.get("mirror", false) else -6
		s.r(px0, -25 + b, 6, 6, c2d)
		s.r(px0 + 1, -24 + b, 4, 4, pal["vis"])
		s.r(px0 + 1, -24 + b, 1, 1, pal["vhi"])
		s.r(px0 + 2, -23 + b, 1, 1, pal["vhi"].darkened(0.3))
	else:
		s.r(-2, -23 + b, 8, 2, pal["vis"])
		s.r(-1, -23 + b, 2, 1, pal["vhi"])
	# Шланг от баллона к шлему
	s.line(-7, -18 + b, -7, -21 + b, c2d.darkened(0.3))
	if pal["acc"] == "antenna":
		s.r(-4, -33 + b, 1, 4, c2d)
		s.e(-4, -34 + b, 1, 1, c("danger"))
	match pose:
		"dig":
			s.r(1, -14 + b, 7, 2, pd)
			s.r(8, -15 + b, 2, 3, c2d)
		"run":
			s.r(-3, -14 + b, 2, 6, pd)
			s.r(-3, -8 + b, 2, 2, c2d)
		_:
			s.r(0, -15 + b, 2, 7, pd)
			s.r(0, -8 + b, 2, 2, c2d)
	s.outline(pal["out"])
	if pose == "dig":
		_tool(s, 9, -14 + b)


func _hero_static(s: Spr, pose: String, pal: Dictionary) -> void:
	# Тип C: угловатый экзокостюм: узкий высокий шлем со светящейся щелью-визором,
	# широкие наплечники, тонкие ноги с наколенниками, мачта антенны над ранцем.
	var pc: Color = pal["pc"]
	var pd: Color = pc.darkened(0.3)
	var c2: Color = pal["c2"]
	var c2d: Color = pal["c2d"]
	var b: int = -1 if pose == "run" else 0
	_legs(s, pose, c2, c2d, pal["out"].lightened(0.25), 3, 8, 4)
	# наколенники
	match pose:
		"run":
			s.r(1, -7, 3, 2, pc)
		"dig":
			s.r(2, -7, 3, 2, pc)
		_:
			s.r(1, -7, 3, 2, pc)
	# Ранец + мачта
	s.r(-7, -17 + b, 3, 8 if pal["acc"] != "tank" else 11, c2d)
	if pal["acc"] != "none":
		s.r(-6, -29 + b, 1, 12, c2d)
		s.r(-7, -31 + b, 3, 2, c2d)
		s.e(-6, -32 + b, 1, 1, c("danger") if pal["acc"] == "antenna" else pal["vis"])
	# Корпус: широкие плечи, узкая талия
	s.r(-5, -17 + b, 10, 3, pc)
	s.r(-4, -14 + b, 8, 3, c2)
	s.r(-3, -11 + b, 6, 3, pc)
	s.r(-5, -17 + b, 10, 1, pc.lightened(0.25))
	# Шлем
	if pal["helm"] == 0:
		s.r(-3, -25 + b, 7, 8, c2)
		s.r(-3, -25 + b, 7, 1, c2.lightened(0.1))
		s.e(-1, -22 + b, 6, 2, pal["vis"])
	else:
		s.r(-4, -25 + b, 8, 8, c2)
		s.e(-2, -24 + b, 7, 5, pal["vis"], 0.8)
		s.e(-1, -24 + b, 2, 1, pal["vhi"])
	if pal["acc"] == "lamp" and not pal["ph"]:
		s.e(4, -18 + b, 2, 2, pal["lamp"])
	match pose:
		"dig":
			s.r(1, -15 + b, 7, 2, pd)
			s.r(8, -15 + b, 2, 3, c2d)
		"run":
			s.r(-3, -15 + b, 2, 6, pd)
		_:
			s.r(0, -15 + b, 2, 7, pd)
			s.r(0, -8 + b, 2, 1, c2d)
	s.outline(pal["out"])
	if pose == "dig":
		_tool(s, 9, -14 + b)


# ================================================================ ФАНТОМЫ

## Пять типов (ADR-001 § 4.5). Общий язык опасности во всех концептах:
## визор/глаза цвета danger (светятся) + цветовое расслоение. Тело — по концепту.
func phantom(kind: String, hero_col: Color = Color(-1, 0, 0)) -> Spr:
	var s: Spr = Spr.new()
	match kind:
		"echo":
			s = hero("stand", {"ph": true, "col": c("ph"), "acc": "none"})
			_ph_effect(s)
		"doppel":
			var hc: Color = hero_col if hero_col.r >= 0.0 else c("suit")
			s = hero("stand", {"col": hc, "acc": "lamp", "mirror": true})
			# Подмена выдаёт одна деталь: визор/иллюминатор цвета опасности.
			_doppel_tell(s)
		"swarm":
			_swarm(s)
		"shade":
			_shade(s)
		"burrower":
			_burrower(s)
	return s


func _ph_effect(s: Spr) -> void:
	var src: Image = s.img.duplicate()
	match cid:
		"spore":
			# Распад на споры: верхние пиксели разлетаются вверх квадратиками.
			for y in Spr.SZ:
				for x in Spr.SZ:
					var p: Color = src.get_pixel(x, y)
					if p.a <= 0.0:
						continue
					if hsh(x, y, 161) < 0.12 and y < s.oy - 12:
						s.img.set_pixel(x, y, Color(0, 0, 0, 0))
						var ny: int = y - 2 - int(hsh(x, y, 162) * 6.0)
						if ny >= 0:
							s.img.set_pixel(x, ny, Color(c("bio").r, c("bio").g, c("bio").b, 0.8))
							s.emi.set_pixel(x, ny, Color(c("bio").r, c("bio").g, c("bio").b, 0.6))
		"reef":
			# Помеха: каждая третья строка выпадает, соседние сдвинуты.
			s.img.fill(Color(0, 0, 0, 0))
			for y in Spr.SZ:
				if y % 3 == 0:
					continue
				var sh: int = 0 if y % 3 == 1 else (1 if (y / 3) % 2 == 0 else -1)
				for x in Spr.SZ:
					var p2: Color = src.get_pixel(x, y)
					if p2.a > 0.0 and x + sh >= 0 and x + sh < Spr.SZ:
						s.img.set_pixel(x + sh, y, p2)
		"static":
			# Капли сортировки вниз от силуэта.
			for x in Spr.SZ:
				var last: int = -1
				for y in Spr.SZ:
					if src.get_pixel(x, y).a > 0.0:
						last = y
				if last < 0 or hsh(x, 0, 163) > 0.6:
					continue
				var run: int = 2 + int(hsh(x, 1, 163) * 6.0)
				var pc: Color = src.get_pixel(x, last)
				for k in run:
					var yy: int = last + 1 + k
					if yy < Spr.SZ:
						s.img.set_pixel(x, yy, Color(pc.r, pc.g, pc.b, 0.8 - float(k) / float(run) * 0.7))
	_rgb_split(s, 1 if cid != "static" else 2)


## Цветовое расслоение: красная копия влево, циановая вправо, за силуэтом.
func _rgb_split(s: Spr, d: int) -> void:
	var src: Image = s.img.duplicate()
	var out: Image = Image.create_empty(Spr.SZ, Spr.SZ, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	for y in Spr.SZ:
		for x in Spr.SZ:
			if src.get_pixel(x, y).a <= 0.0:
				continue
			if x - d >= 0:
				out.set_pixel(x - d, y, Color(1.0, 0.2, 0.35, 0.4))
			if x + d < Spr.SZ and out.get_pixel(x + d, y).a == 0.0:
				out.set_pixel(x + d, y, Color(0.2, 0.95, 1.0, 0.35))
	for y in Spr.SZ:
		for x in Spr.SZ:
			var p: Color = src.get_pixel(x, y)
			if p.a > 0.0:
				out.set_pixel(x, y, p)
	s.img = out


func _doppel_tell(s: Spr) -> void:
	var vis: Color = c("visor")
	for y in Spr.SZ:
		for x in Spr.SZ:
			var p: Color = s.img.get_pixel(x, y)
			if p.a > 0.0 and absf(p.r - vis.r) + absf(p.g - vis.g) + absf(p.b - vis.b) < 0.05:
				s.img.set_pixel(x, y, c("danger"))
				s.emi.set_pixel(x, y, Color(c("danger").r, c("danger").g, c("danger").b, 0.7))
	# Фонарь двойника не светит (s.emi лампы гасим).
	var lamp: Color = c("lamp")
	for y in Spr.SZ:
		for x in Spr.SZ:
			var e: Color = s.emi.get_pixel(x, y)
			if e.a > 0.0 and absf(e.r - lamp.r) + absf(e.g - lamp.g) + absf(e.b - lamp.b) < 0.05:
				s.emi.set_pixel(x, y, Color(0, 0, 0, 0))
				s.img.set_pixel(x, y, c("outline").lightened(0.2))


func _swarm(s: Spr) -> void:
	var dc: Color = c("danger")
	for i in 9:
		var x: int = -10 + int(hsh(i, 1, 171) * 20.0)
		var y: int = -22 + int(hsh(i, 2, 171) * 14.0)
		match cid:
			"spore":
				# Споровые мотыльки: тельце 2×2 и крылья-пиксели.
				s.r(x, y, 2, 2, c("ph"))
				s.r(x - 2, y - 1, 2, 1, c("fl2"))
				s.r(x + 2, y - 1, 2, 1, c("fl2"))
				s.e(x + 1, y, 1, 1, dc)
			"reef":
				# Косяк: тело 3×1, хвост, светящийся глаз.
				s.r(x, y, 4, 2, c("ph").lightened(0.2))
				s.r(x - 2, y, 1, 2, c("ph"))
				s.e(x + 3, y, 1, 1, dc)
			"static":
				# Пакеты: квадраты 2×2 трёх каналов.
				var pick: int = i % 3
				var col: Color = [Color("#FF3A5A"), Color("#5AFF8A"), Color("#5A8AFF")][pick]
				s.e(x, y, 2, 2, col, 0.8)
				if i % 2 == 0:
					s.e(x + 3, y, 1, 1, dc)
	if cid != "static":
		s.outline(c("ph2"))


func _shade(s: Spr) -> void:
	var dc: Color = c("danger")
	match cid:
		"spore":
			# Тень-капюшон, из подола свисают гифы.
			s.r(-5, -26, 10, 22, c("ph2"))
			s.r(-6, -22, 12, 14, c("ph2"))
			s.r(-3, -28, 6, 2, c("ph2"))
			for k in 6:
				s.r(-5 + k * 2, -4, 1, 2 + int(hsh(k, 0, 181) * 4.0), c("ph2"))
			s.e(1, -21, 2, 1, dc)
			s.e(-2, -21, 2, 1, dc, 0.6)
		"reef":
			# Бездонная тень с приманкой на стебле.
			s.r(-6, -24, 12, 22, c("ph2"))
			s.r(-4, -27, 8, 3, c("ph2"))
			s.line(2, -27, 6, -33, c("ph2"))
			s.e(6, -35, 2, 2, Color("#FFF0A0"))
			s.e(-2, -20, 1, 1, dc)
			s.e(2, -20, 1, 1, dc)
		"static":
			# Чёрная дыра в кадре с шумной кромкой.
			s.r(-6, -27, 12, 25, Color("#000000"))
			for y in range(-27, -2):
				for x in [-7, 6]:
					if hsh(x, y, 182) > 0.4:
						var n: float = hsh(x, y, 183)
						s.r(x, y, 1, 1, Color(n, n, n))
			s.e(-3, -22, 6, 1, dc)
	s.outline(c("outline"))


func _burrower(s: Spr) -> void:
	var dc: Color = c("danger")
	var body: Color = c("ph").lightened(0.35)
	var drill: Color = Color("#B8BEC8")
	match cid:
		"spore":
			# Личинка: сегменты разной высоты, ножки-пиксели, споровые бугорки.
			var hs: Array = [6, 9, 10, 9]
			for k in 4:
				var hh: int = hs[k]
				s.r(-14 + k * 5, -2 - hh, 5, hh, body if k % 2 == 0 else body.darkened(0.18))
				s.r(-14 + k * 5, -2 - hh, 5, 1, body.lightened(0.2))
				s.r(-13 + k * 5, -2, 1, 2, body.darkened(0.35))
				s.r(-11 + k * 5, -2, 1, 2, body.darkened(0.35))
				s.e(-12 + k * 5, -3 - hh, 1, 1, c("bio"), 0.6)
			s.e(3, -8, 2, 1, dc)
		"reef":
			# Краб: панцирь, ноги-штрихи.
			s.r(-9, -10, 14, 6, body)
			s.r(-7, -12, 10, 2, body.lightened(0.15))
			for k in 4:
				s.r(-9 + k * 4, -4, 1, 3, body.darkened(0.25))
			s.e(2, -11, 1, 1, dc)
			s.e(4, -11, 1, 1, dc)
		"static":
			# Блок-бур с отсортированным шлейфом позади.
			s.r(-6, -10, 11, 9, c("ph"))
			for k in 8:
				s.r(-7 - k, -9 + (k % 3), 1, 7 - (k % 3) * 2, Color(c("danger").r, c("danger").g, c("danger").b, 0.8 - k * 0.09))
			s.e(1, -8, 3, 1, dc)
	# Бур: ступенчатый треугольник.
	for k in 6:
		s.r(6 + k, -9 + k / 2, 1, 8 - k, drill if k % 2 == 0 else drill.darkened(0.25))
	s.outline(c("outline"))


# ================================================================ МАШИНЫ

## Релей: ферма-мачта с излучателем. x — левый край, fy — пол.
func machine_relay(cv: Cv, x: int, fy: int, hgt: int) -> void:
	var md: Color = c("metal_d")
	var mt: Color = c("metal")
	cv.rect(x, fy - hgt, 2, hgt, md)
	cv.rect(x + 8, fy - hgt, 2, hgt, md)
	for y in range(fy - hgt + 2, fy, 6):
		for k in 6:
			cv.px(x + 2 + k, y + k, mt)
			cv.px(x + 7 - k, y + k, mt)
	cv.rect(x - 3, fy - hgt - 3, 16, 3, mt)
	cv.rect(x - 3, fy - hgt - 3, 16, 1, c("metal_hi"))
	cv.rect(x + 2, fy - hgt - 9, 6, 6, c("frame"))
	cv.glow_rect(x + 3, fy - hgt - 8, 4, 4, c("bio"), 1.0)
	cv.glow(x + 4, fy - hgt - 14, c("danger"), 1.0)
	cv.rect(x + 4, fy - hgt - 13, 1, 4, md)
	cv.light(x + 5, fy - hgt - 6, 40.0, c("bio"), 0.35)
	match cid:
		"spore":
			for k in 12:
				var yy: int = fy - int(hsh(k, x, 191) * hgt * 0.5)
				cv.rect(x + (0 if k % 2 == 0 else 8), yy, 2, 2, c("s_top"))
		"reef":
			for k in 5:
				var ax: int = x - 2 + k * 3
				var l: int = 4 + int(hsh(k, x, 192) * 8.0)
				cv.rect(ax, fy - hgt, 1, l, Color("#6E9A5E"))
			for k in 10:
				cv.px(x + (1 if k % 2 == 0 else 9), fy - int(hsh(k, x, 193) * hgt * 0.4), c("fl3"))
		"static":
			for k in range(0, 24):
				var sag: int = int(sin(float(k) / 23.0 * PI) * 6.0)
				cv.px(x + 10 + k, fy - hgt + 10 + sag, c("frame"))
			for k in 4:
				cv.glow(x + 1, fy - hgt + 8 + k * 12, c("screen_hi"), 0.9)


## ТЭЦ: короб, топка, труба с дымом квадратами.
func machine_tec(cv: Cv, x: int, fy: int, on: bool) -> void:
	var mt: Color = c("metal")
	var md: Color = c("metal_d")
	cv.rect(x, fy - 20, 28, 20, md)
	cv.rect(x + 1, fy - 19, 26, 18, mt)
	cv.rect(x + 1, fy - 19, 26, 1, c("metal_hi"))
	for k in 26:
		if (k / 2) % 2 == 0:
			cv.px(x + 1 + k, fy - 3, c("hazard"))
	cv.rect(x + 13, fy - 15, 10, 8, c("frame"))
	if on:
		cv.glow_rect(x + 14, fy - 14, 8, 6, c("lava"), 1.0)
		cv.glow_rect(x + 15, fy - 11, 6, 2, c("lava_hi"), 1.0)
		cv.light(x + 18, fy - 10, 40.0, c("lava"), 0.5)
	cv.rect(x + 3, fy - 34, 6, 15, md)
	cv.rect(x + 3, fy - 34, 6, 1, c("metal_hi"))
	cv.rect(x + 3, fy - 15, 6, 2, c("frame"))
	cv.glow(x + 5, fy - 9, c("screen_hi"), 0.9)
	if on:
		for k in 5:
			var sz: int = 3 + k
			var col: Color = Color(0.92, 0.9, 0.86, 0.55 - k * 0.08)
			if cid == "spore":
				col = Color(c("fl2").r, c("fl2").g, c("fl2").b, 0.6 - k * 0.09)
			cv.rect(x + 4 + k * 2 - sz / 2 + int(hsh(k, x, 201) * 3.0), fy - 38 - k * 6, sz, sz, col)
	if cid == "reef":
		for k in 9:
			cv.px(x + int(hsh(k, x, 202) * 28.0), fy - 1 - int(hsh(k, x, 203) * 3.0), c("fl3"))
	elif cid == "spore":
		cv.rect(x, fy - 20, 6, 2, c("s_top"))
		cv.rect(x, fy - 18, 2, 5, c("s_top"))


func machine_solar(cv: Cv, x: int, fy: int) -> void:
	cv.rect(x + 10, fy - 10, 2, 10, c("metal_d"))
	cv.rect(x, fy - 15, 22, 6, c("frame"))
	for k in 5:
		cv.rect(x + 1 + k * 4, fy - 14, 3, 4, c("screen").lerp(c("bio"), 0.25))
		cv.px(x + 1 + k * 4, fy - 14, c("bio").lerp(Color.WHITE, 0.4))


func lamp_post(cv: Cv, x: int, fy: int) -> void:
	cv.rect(x + 1, fy - 18, 2, 18, c("metal_d"))
	cv.rect(x - 1, fy - 21, 6, 3, c("frame"))
	cv.glow_rect(x, fy - 20, 4, 2, c("lamp"), 1.0)
	cv.light(x + 2, fy - 18, 56.0, c("lamp"), 0.55)


## Обводка «можно взаимодействовать» + клавиша E.
func interact_mark(cv: Cv, x: int, y: int, w: int, h: int) -> void:
	var ic: Color = c("interact")
	cv.glow_rect(x - 1, y - 1, w + 2, 1, ic, 0.9)
	cv.glow_rect(x - 1, y + h, w + 2, 1, ic, 0.9)
	cv.glow_rect(x - 1, y, 1, h, ic, 0.9)
	cv.glow_rect(x + w, y, 1, h, ic, 0.9)
	var kx: int = x + w / 2 - 3
	var ky: int = y - 10
	cv.rect(kx, ky, 7, 7, c("ui_bg"))
	cv.glow_rect(kx, ky, 7, 1, ic, 0.9)
	# буква E 3×5
	cv.glow_rect(kx + 2, ky + 1, 1, 5, ic, 1.0)
	cv.glow_rect(kx + 3, ky + 1, 2, 1, ic, 1.0)
	cv.glow_rect(kx + 3, ky + 3, 1, 1, ic, 1.0)
	cv.glow_rect(kx + 3, ky + 5, 2, 1, ic, 1.0)


## HUD-акценты поверх кадра (без освещения): здоровье, импульс, хотбар.
func hud(img: Image, night: bool) -> void:
	var bg: Color = c("ui_bg")
	var ln: Color = c("ui_line")
	img.fill_rect(Rect2i(6, 6, 62, 6), bg)
	img.fill_rect(Rect2i(7, 7, 44, 4), c("ui_hp"))
	img.fill_rect(Rect2i(7, 7, 44, 1), c("ui_hp").lightened(0.3))
	img.fill_rect(Rect2i(6, 13, 42, 3), bg)
	img.fill_rect(Rect2i(7, 14, 28, 1), c("bio"))
	# хотбар 8 слотов
	var x0: int = W / 2 - 8 * 13 / 2
	var y0: int = H - 16
	var icons: Array = ["copper", "iron", "coal", "crystal", "scrap", "metal", "lamp", "fl1"]
	for i in 8:
		var sx: int = x0 + i * 13
		img.fill_rect(Rect2i(sx, y0, 12, 12), bg)
		img.fill_rect(Rect2i(sx + 1, y0 + 1, 10, 10), c("ui_panel"))
		img.fill_rect(Rect2i(sx + 3, y0 + 4, 4, 4), c(icons[i]))
		img.fill_rect(Rect2i(sx + 6, y0 + 6, 3, 3), c(icons[i]).darkened(0.2))
		if i == 2:
			for k in 12:
				img.set_pixel(sx + k, y0, c("interact"))
				img.set_pixel(sx + k, y0 + 11, c("interact"))
				img.set_pixel(sx, y0 + k, c("interact"))
				img.set_pixel(sx + 11, y0 + k, c("interact"))
	# Метка суток в правом верхнем углу: квадрат-солнце/луна на полоске.
	img.fill_rect(Rect2i(W - 46, 7, 40, 3), bg)
	img.fill_rect(Rect2i(W - 46 + (30 if night else 12), 5, 5, 7), c("danger") if night else c("hazard"))
	if night:
		# Сигнал опасности: угол-рамка мигает цветом danger.
		for k in 10:
			img.set_pixel(1 + k, 1, c("danger"))
			img.set_pixel(1, 1 + k, c("danger"))
			img.set_pixel(W - 2 - k, 1, c("danger"))
			img.set_pixel(W - 2, 1 + k, c("danger"))


# ================================================================ ГЛИТЧ-ПОСТОБРАБОТКА

## Сдвиг каналов в прямоугольнике: R влево, B вправо.
func fx_chroma(img: Image, r: Rect2i, d: int) -> void:
	var src: Image = img.duplicate()
	for y in range(maxi(r.position.y, 0), mini(r.end.y, img.get_height())):
		for x in range(maxi(r.position.x, 0), mini(r.end.x, img.get_width())):
			var p: Color = src.get_pixel(x, y)
			var pr: Color = src.get_pixel(clampi(x + d, 0, img.get_width() - 1), y)
			var pb: Color = src.get_pixel(clampi(x - d, 0, img.get_width() - 1), y)
			img.set_pixel(x, y, Color(pr.r, p.g, pb.b, 1.0))


## Разрыв строки: полоса строк сдвинута на dx.
func fx_tear(img: Image, x0: int, x1: int, y0: int, y1: int, dx: int) -> void:
	var src: Image = img.duplicate()
	for y in range(maxi(y0, 0), mini(y1, img.get_height())):
		for x in range(maxi(x0, 0), mini(x1, img.get_width())):
			img.set_pixel(x, y, src.get_pixel(clampi(x - dx, 0, img.get_width() - 1), y))


## Битые блоки: квадраты 2×2 одного цвета (артефакт сжатия).
func fx_blocks(img: Image, r: Rect2i, n: int, sd: int) -> void:
	for i in n:
		var x: int = r.position.x + int(hsh(i, 1, sd) * r.size.x)
		var y: int = r.position.y + int(hsh(i, 2, sd) * r.size.y)
		var src: Color = img.get_pixel(clampi(x + 3, 0, img.get_width() - 1), clampi(y - 2, 0, img.get_height() - 1))
		var sz: int = 2 if hsh(i, 3, sd) > 0.3 else 4
		img.fill_rect(Rect2i(x - x % 2, y - y % 2, sz, sz), src)


func put(cv: Cv, s: Spr, wx: int, wy: int, alpha: float = 1.0) -> void:
	for y in Spr.SZ:
		for x in Spr.SZ:
			var p: Color = s.img.get_pixel(x, y)
			if p.a <= 0.0:
				continue
			var tx: int = wx - s.ox + x
			var ty: int = wy - s.oy + y
			var e: Color = s.emi.get_pixel(x, y)
			if e.a > 0.0:
				cv.glow(tx, ty, Color(e.r, e.g, e.b), e.a * alpha)
			else:
				cv.px(tx, ty, Color(p.r, p.g, p.b, p.a * alpha))


func shadow(cv: Cv, x: int, fy: int, w: int) -> void:
	cv.rect(x - w / 2, fy, w, 1, Color(0, 0, 0, 0.35))


# ================================================================ СЕТКА И СЦЕНЫ

## Простая сетка тайлов сцены: kind и биом каждой клетки.
class Grid:
	var cols: int
	var rows: int
	var kind: PackedInt32Array
	var bio: PackedInt32Array
	var wall: PackedInt32Array		## 1 — за воздухом задняя стенка (пещера).

	func _init(pc: int, pr: int) -> void:
		cols = pc
		rows = pr
		kind = PackedInt32Array()
		kind.resize(pc * pr)
		kind.fill(0)
		bio = PackedInt32Array()
		bio.resize(pc * pr)
		bio.fill(0)
		wall = PackedInt32Array()
		wall.resize(pc * pr)
		wall.fill(0)

	func k(x: int, y: int) -> int:
		if x < 0 or y < 0 or x >= cols or y >= rows:
			return 1
		return kind[y * cols + x]

	func setk(x: int, y: int, v: int, b: int = -1) -> void:
		if x < 0 or y < 0 or x >= cols or y >= rows:
			return
		kind[y * cols + x] = v
		if b >= 0:
			bio[y * cols + x] = b

	func solid(x: int, y: int) -> bool:
		var v: int = k(x, y)
		return v != 0 and v != 8 and v != 9	# AIR, LAVA, WATER

	func mask(x: int, y: int) -> int:
		var m: int = 0
		if not solid(x, y - 1):
			m |= 1
		if not solid(x + 1, y):
			m |= 2
		if not solid(x, y + 1):
			m |= 4
		if not solid(x - 1, y):
			m |= 8
		return m


func draw_grid(cv: Cv, g: Grid, ox: int, oy: int) -> void:
	# Сначала порода, потом металл (наросты породы не должны лезть на панели).
	for pass_i in 2:
		for y in g.rows:
			for x in g.cols:
				var kd: int = g.k(x, y)
				if pass_i == 0 and g.wall[y * g.cols + x] == 1 and not g.solid(x, y):
					_backwall(cv, g.bio[y * g.cols + x], ox + x * T, oy + y * T)
				if kd == K.AIR:
					continue
				var is_metal: bool = kd >= K.PANEL
				if (pass_i == 0) == is_metal:
					continue
				tile(cv, kd, g.bio[y * g.cols + x], ox + x * T, oy + y * T, g.mask(x, y))


## (а) Поверхность днём: база с релеем, ТЭЦ, солнечной панелью, терминалом; герой.
func _scene_surface() -> Image:
	var cv: Cv = Cv.new(W, H)
	cv.amb = c("amb_day")
	var oy: int = -12
	var hor: int = 120
	paint_sky(cv, "day", 0, 0, W, H, hor)
	paint_far(cv, "day", 0, W, 112)
	paint_mid(cv, "day", 0, W, 118)
	var g: Grid = Grid.new(20, 13)
	var tops: Array = [7, 7, 6, 6, 7, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 7, 7, 6, 6]
	for x in 20:
		for y in range(tops[x], 13):
			var b: int = 0 if y < 11 else 1
			g.setk(x, y, K.GROUND, b)
	# база: пол из панелей и стена-шлюз справа
	for x in range(5, 16):
		g.setk(x, 8, K.PANEL)
	g.setk(15, 7, K.WALL)
	g.setk(15, 6, K.WALL)
	g.setk(5, 7, K.GLASS)
	g.setk(11, 7, K.TERM)
	g.setk(12, 7, K.RELAY)
	# руды у поверхности
	g.setk(2, 9, K.COPPER, 0)
	g.setk(3, 10, K.COAL, 0)
	g.setk(17, 10, K.SCRAP, 0)
	g.setk(8, 11, K.IRON, 1)
	g.setk(9, 12, K.CRYSTAL, 1)
	draw_grid(cv, g, 0, oy)
	var fy: int = 8 * T + oy
	# флора по краям
	flora_surface(cv, 0, 1 * T, 6 * T + oy, 1, false)
	flora_surface(cv, 2, 3 * T, 6 * T + oy, 0, false)
	flora_surface(cv, 1, 0, 7 * T + oy, 0, false)
	flora_surface(cv, 1, 16 * T + 2, 7 * T + oy, 1, false)
	flora_surface(cv, 0, 18 * T, 6 * T + oy, 2, false)
	flora_surface(cv, 2, 17 * T + 4, 7 * T + oy, 0, false)
	flora_surface(cv, 2, 4 * T + 2, 7 * T + oy, 1, false)
	flora_surface(cv, 1, 2 * T + 4, 6 * T + oy, 1, false)
	flora_surface(cv, 0, 19 * T + 4, 6 * T + oy, 0, false)
	# машины
	machine_tec(cv, 6 * T + 2, fy, true)
	machine_solar(cv, 9 * T, fy)
	machine_relay(cv, 13 * T + 3, fy, 64)
	lamp_post(cv, 14 * T + 10, fy)
	interact_mark(cv, 11 * T, 7 * T + oy, 16, 16)
	# герой
	var hs: Spr = hero("stand")
	shadow(cv, int(9.6 * T), fy, 10)
	put(cv, hs, int(9.6 * T), fy)
	cv.light(9.6 * T + 5, fy - 24, 30.0, c("lamp"), 0.25)
	var img: Image = cv.finish(0.35)
	match cid:
		"spore":
			fx_blocks(img, Rect2i(13 * T, fy - 84, 24, 20), 6, 211)
		"reef":
			fx_tear(img, 0, W, 92, 94, 3)
		"static":
			fx_tear(img, 13 * T - 4, 13 * T + 20, fy - 80, fy - 74, 2)
	hud(img, false)
	return img


## (б) Пещера ночью: средние пещеры → глубина у лавы, руды, пять фантомов, фонарь героя.
func _scene_cave() -> Image:
	var cv: Cv = Cv.new(W, H)
	cv.amb = c("amb_cave")
	var oy: int = -8
	var g: Grid = Grid.new(20, 13)
	var ceil_y: Array = [2, 2, 3, 3, 3, 2, 2, 3, 3, 4, 4, 3, 3, 3, 4, 4, 4, 3, 3, 3]
	var floor_y: Array = [8, 8, 9, 9, 9, 9, 8, 8, 9, 9, 9, 9, 9, 10, 10, 10, 10, 9, 9, 9]
	for x in 20:
		for y in 13:
			var open: bool = y >= ceil_y[x] and y < floor_y[x]
			if x == 0 and y < 7:
				open = false
			var deep: bool = float(x - 9) + float(y - 5) * 1.4 + hsh(x, y, 221) * 1.5 > 3.0
			var b: int = 2 if deep else 1
			g.setk(x, y, K.AIR if open else K.GROUND, b)
	# лава в провале
	for x in range(13, 17):
		g.setk(x, 10, K.LAVA, 2)
		g.setk(x, 9, K.AIR, 2)
	# руды
	g.setk(2, 1, K.COPPER)
	g.setk(3, 1, K.COPPER)
	g.setk(6, 9, K.IRON)
	g.setk(7, 9, K.IRON)
	g.setk(10, 2, K.COAL)
	g.setk(11, 2, K.COAL)
	g.setk(17, 2, K.CRYSTAL)
	g.setk(18, 2, K.CRYSTAL)
	g.setk(4, 10, K.SCRAP)
	g.setk(19, 6, K.CRYSTAL)
	g.setk(1, 6, K.LAMP)
	g.wall.fill(1)
	draw_grid(cv, g, 0, oy)
	# флора
	flora_cave(cv, true, 5 * T, 2 * T + oy + 0, 1)
	flora_cave(cv, true, 8 * T, 3 * T + oy, 0)
	flora_cave(cv, false, 2 * T, 9 * T + oy, 0)
	flora_cave(cv, false, 11 * T, 9 * T + oy, 1)
	flora_deep(cv, 17 * T, 9 * T + oy, 0)
	flora_cave(cv, true, 15 * T, 4 * T + oy, 0)
	# герой с фонарём
	var hx: int = 5 * T + 4
	var hfy: int = 9 * T + oy
	var hs: Spr = hero("run")
	shadow(cv, hx, hfy, 10)
	put(cv, hs, hx, hfy)
	var lamp_at: Vector2 = Vector2(hx + 5, hfy - 25)
	if cid == "reef":
		lamp_at = Vector2(hx + 3, hfy - 13)
	elif cid == "static":
		lamp_at = Vector2(hx + 5, hfy - 17)
	cv.cone(lamp_at.x, lamp_at.y, Vector2(1.0, 0.12), 0.42, 200.0, c("lamp"), 1.9)
	cv.light(hx, hfy - 12, 30.0, c("lamp"), 0.45)
	# фантомы
	var echo: Spr = phantom("echo")
	put(cv, echo, 12 * T + 2, 9 * T + oy, 0.92)
	var dop: Spr = phantom("doppel")
	put(cv, dop, 2 * T + 6, 8 * T + oy, 0.95)
	var sw: Spr = phantom("swarm")
	put(cv, sw, 9 * T + 6, 6 * T + oy, 1.0)
	var sh: Spr = phantom("shade")
	put(cv, sh, 17 * T + 10, 9 * T + oy, 1.0)
	var bu: Spr = phantom("burrower")
	bu.flip()
	put(cv, bu, 19 * T + 6, 9 * T + oy - 0, 1.0)
	# Фантомы чуть подсвечены цветом опасности — силуэт читается и в темноте.
	for p in [Vector2(12 * T + 2, 9 * T + oy), Vector2(2 * T + 6, 8 * T + oy), Vector2(9 * T + 6, 6 * T + oy),
			Vector2(17 * T + 10, 9 * T + oy), Vector2(19 * T, 9 * T + oy)]:
		cv.light(p.x, p.y - 12, 26.0, c("danger"), 0.35)
	var img: Image = cv.finish(0.85)
	# глитч только вокруг фантомов — сигнал опасности
	var er: Rect2i = Rect2i(12 * T - 12, 9 * T + oy - 34, 28, 36)
	match cid:
		"spore":
			fx_chroma(img, er, 1)
			fx_blocks(img, Rect2i(17 * T, 2 * T + oy, 32, 16), 5, 222)
		"reef":
			fx_tear(img, er.position.x, er.end.x + 10, er.position.y + 8, er.position.y + 10, 3)
			fx_tear(img, er.position.x - 6, er.end.x, er.position.y + 20, er.position.y + 21, -2)
			fx_chroma(img, er, 1)
		"static":
			fx_chroma(img, er, 2)
			fx_chroma(img, Rect2i(17 * T, 2 * T + oy, 32, 16), 1)
			fx_tear(img, 2 * T - 6, 2 * T + 20, 8 * T + oy - 24, 8 * T + oy - 21, 2)
	hud(img, true)
	return img


## (г) Разрез биомов: поверхность → средние пещеры → глубина у лавы.
func _scene_biomes() -> Image:
	var rows: int = 18
	var cv: Cv = Cv.new(W, rows * T)
	var g: Grid = Grid.new(20, rows)
	for x in 20:
		var top: int = 4 if x < 6 or x > 14 else 5
		for y in range(top, rows):
			var b: int = 0
			var d1: int = 8 + int(round(sin(x * 0.9) * 0.8 + (hsh(x, 0, 232) - 0.5) * 1.2))
			var d2: int = 13 + int(round(sin(x * 0.7 + 2.0) * 0.8 + (hsh(x, 0, 231) - 0.5) * 1.2))
			if y >= d2:
				b = 2
			elif y >= d1:
				b = 1
			g.setk(x, y, K.GROUND, b)
	# пещера средних глубин
	for x in range(3, 16):
		var c0: int = 9 if x % 5 != 0 else 10
		for y in range(c0, 12):
			g.setk(x, y, K.AIR)
	# пещера глубины с лавой
	for x in range(1, 19):
		var c1: int = 14 if x % 4 != 1 else 15
		for y in range(c1, 17):
			g.setk(x, y, K.AIR)
	for x in range(7, 13):
		g.setk(x, 16, K.LAVA, 2)
	for x in 20:
		g.setk(x, 17, K.BED)
	g.setk(1, 6, K.COPPER)
	g.setk(17, 6, K.COAL)
	g.setk(2, 9, K.IRON)
	g.setk(17, 10, K.IRON)
	g.setk(16, 12, K.CRYSTAL)
	g.setk(0, 15, K.CRYSTAL)
	g.setk(19, 13, K.SCRAP)
	for y in range(7, rows):
		for x in 20:
			g.wall[y * 20 + x] = 1
	paint_sky(cv, "day", 0, 0, W, 5 * T, 4 * T)
	paint_far(cv, "day", 0, W, 4 * T + 6)
	paint_mid(cv, "day", 0, W, 4 * T + 10)
	draw_grid(cv, g, 0, 0)
	flora_surface(cv, 0, 1 * T, 4 * T, 0, false)
	flora_surface(cv, 1, 7 * T, 5 * T, 0, false)
	flora_surface(cv, 2, 11 * T, 5 * T, 0, false)
	flora_surface(cv, 0, 16 * T, 4 * T, 1, false)
	flora_cave(cv, true, 4 * T, 9 * T, 0)
	flora_cave(cv, true, 11 * T, 9 * T, 1)
	flora_cave(cv, false, 7 * T, 12 * T, 0)
	flora_cave(cv, false, 14 * T, 12 * T, 1)
	flora_deep(cv, 2 * T, 17 * T, 0)
	flora_deep(cv, 15 * T, 17 * T, 1)
	flora_cave(cv, true, 16 * T, 14 * T, 0)
	var day: Color = c("amb_day")
	var cave: Color = c("amb_cave")
	for y in rows * T:
		var t: float = clampf((float(y) - 6.0 * T) / (3.0 * T), 0.0, 1.0)
		cv.amb_rows.append(day.lerp(cave.lightened(0.15), t))
	var hs: Spr = hero("dig")
	put(cv, hs, 6 * T, 12 * T)
	cv.cone(6 * T + 5, 12 * T - 25, Vector2(1, 0.2), 0.5, 110.0, c("lamp"), 1.0)
	var e: Spr = phantom("echo")
	e.flip()
	put(cv, e, 14 * T, 17 * T - T)
	return cv.finish(0.75)


# ================================================================ ЛИСТ

func _sheet() -> Image:
	var sw: int = 1280
	var sh: int = 1040
	var img: Image = Image.create_empty(sw, sh, false, Image.FORMAT_RGBA8)
	img.fill(c("ui_bg"))
	# 1. Тайлы ×4
	var kinds: Array = [
		[K.GROUND, 0, 1], [K.GROUND, 0, 0], [K.GROUND, 1, 4], [K.GROUND, 1, 1], [K.GROUND, 2, 1], [K.BED, 2, 0],
		[K.COPPER, 0, 0], [K.IRON, 1, 0], [K.COAL, 0, 0], [K.CRYSTAL, 1, 0], [K.SCRAP, 0, 0],
		[K.LAVA, 2, 1], [K.WATER, 0, 1], [K.PANEL, 0, 0], [K.WALL, 0, 0], [K.TERM, 0, 0],
	]
	var tv: Cv = Cv.new(16 * 18, 26)
	tv.col.fill(c("ui_bg"))
	tv.amb = Color(1, 1, 1)
	for i in kinds.size():
		tile(tv, kinds[i][0], kinds[i][1], i * 18 + 1, 5, kinds[i][2])
	var ti: Image = tv.finish(0.4)
	_blit_scaled(img, ti, 64, 16, 4)
	# 2. Флора: поверхность | средние пещеры | глубина
	var fv: Cv = Cv.new(320, 86)
	fv.amb = Color(0.95, 0.95, 0.95)
	fv.col.fill(c("ui_bg"))
	var g: Grid = Grid.new(20, 5)
	for x in 20:
		var b: int = 0 if x < 9 else (1 if x < 15 else 2)
		g.setk(x, 4, K.GROUND, b)
		if x >= 9 and x < 15:
			g.setk(x, 0, K.GROUND, 1)
	draw_grid(fv, g, 0, 4)
	var gy: int = 4 * T + 4
	flora_surface(fv, 0, 0, gy, 1, false)
	flora_surface(fv, 1, 2 * T, gy, 1, false)
	flora_surface(fv, 2, 3 * T + 8, gy, 0, false)
	flora_surface(fv, 0, 5 * T, gy, 0, true)
	flora_surface(fv, 1, 6 * T + 8, gy, 0, true)
	flora_surface(fv, 2, 7 * T + 8, gy, 1, true)
	flora_cave(fv, true, 9 * T + 4, T + 4, 0)
	flora_cave(fv, false, 11 * T, gy, 1)
	flora_cave(fv, true, 12 * T + 8, T + 4, 1)
	flora_cave(fv, false, 13 * T + 8, gy, 0)
	flora_deep(fv, 15 * T + 4, gy, 0)
	flora_deep(fv, 17 * T + 6, gy, 1)
	_blit_scaled(img, fv.finish(0.6), 0, 112, 4)
	# 3. Герой: 3 позы ×6 и 5 вариантов кастомизации ×4
	var poses: Array = ["stand", "run", "dig"]
	for i in 3:
		_blit_sprite(img, hero(poses[i]), 24 + i * 150, 438, 6, 22, 36)
	var custs: Array = [
		{"col": Color("#E8743B")}, {"col": Color("#2FA39A"), "helm": 1},
		{"col": Color("#8A5AC8"), "acc": "antenna"}, {"col": Color("#E0C040"), "acc": "tank"},
		{"col": Color("#D84A5A"), "helm": 1, "acc": "none"},
	]
	for i in custs.size():
		_blit_sprite(img, hero("stand", custs[i]), 500 + i * 110, 470, 4, 26, 40)
	# 4. Фантомы ×4
	var kinds_ph: Array = ["echo", "swarm", "shade", "burrower", "doppel"]
	for i in kinds_ph.size():
		_blit_sprite(img, phantom(kinds_ph[i]), 40 + i * 172, 680, 4, 40, 40)
	# 4б. Машины базы ×2: ТЭЦ, солнечная панель, релей, фонарь — с «одеждой» концепта.
	var mv: Cv = Cv.new(140, 92)
	mv.col.fill(c("ui_bg"))
	mv.amb = Color(1, 1, 1)
	var mg: Grid = Grid.new(9, 6)
	for x in 9:
		mg.setk(x, 5, K.PANEL)
	draw_grid(mv, mg, 0, -4)
	machine_tec(mv, 4, 76, true)
	machine_solar(mv, 36, 76)
	machine_relay(mv, 74, 76, 44)
	lamp_post(mv, 100, 76)
	tile(mv, K.TERM, 0, 114, 60, 0)
	_blit_scaled(img, mv.finish(0.4), 980, 664, 2)
	# 5. Небо: день / сумерки / ночь
	var tods: Array = ["day", "dusk", "night"]
	for i in 3:
		var sv: Cv = Cv.new(100, 56)
		sv.amb = c("amb_" + tods[i])
		paint_sky(sv, tods[i], 0, 0, 100, 56, 44)
		paint_far(sv, tods[i], 0, 100, 46)
		var gg: Grid = Grid.new(7, 4)
		for x in 7:
			gg.setk(x, 3, K.GROUND, 0)
		draw_grid(sv, gg, 0, 0)
		flora_surface(sv, 0, 70, 48, 0, tods[i] != "day")
		flora_surface(sv, 1, 10, 48, 0, tods[i] != "day")
		_blit_scaled(img, sv.finish(0.8), 40 + i * 316, 856, 3)
	# 6. Палитра
	var keys: Array = ["sky_day_top", "sky_day_hor", "s_top", "s_base", "m_base", "m_glow", "d_base", "d_glow",
		"copper", "iron", "coal", "crystal", "scrap", "lava", "metal", "frame", "hazard", "suit", "suit2", "visor",
		"lamp", "interact", "danger", "bio"]
	for i in keys.size():
		img.fill_rect(Rect2i(16 + i * 52, 1026 - 12, 48, 12), c(keys[i]))
	return img


func _blit_scaled(dst: Image, src: Image, x: int, y: int, s: int) -> void:
	var big: Image = src.duplicate()
	big.resize(src.get_width() * s, src.get_height() * s, Image.INTERPOLATE_NEAREST)
	dst.blit_rect(big, Rect2i(0, 0, mini(big.get_width(), dst.get_width() - x), mini(big.get_height(), dst.get_height() - y)), Vector2i(x, y))


## Спрайт на фоне листа, вырез cw×ch вокруг ног, увеличение s.
func _blit_sprite(dst: Image, sp: Spr, x: int, y: int, s: int, cw: int, ch: int) -> void:
	var cv: Cv = Cv.new(cw, ch)
	cv.col.fill(c("ui_panel"))
	cv.amb = Color(1, 1, 1)
	put(cv, sp, cw / 2, ch - 3)
	_blit_scaled(dst, cv.finish(0.5), x, y, s)


# ================================================================ СРАВНЕНИЕ

## Три концепта рядом: слева поверхность, справа пещера (×2). cvd — симуляция дейтеранопии.
func _compare(surf: Dictionary, cave: Dictionary, cvd: bool) -> Image:
	var out: Image = Image.create_empty(1280, 1080, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.05, 0.05, 0.06))
	for i in IDS.size():
		var id: String = IDS[i]
		var a: Image = cave[id] if cvd else surf[id]
		var b: Image = cave[id]
		if cvd:
			b = _deutan(cave[id])
			a = cave[id]
		var a2: Image = a.duplicate()
		a2.resize(640, 360, Image.INTERPOLATE_NEAREST)
		var b2: Image = b.duplicate()
		b2.resize(640, 360, Image.INTERPOLATE_NEAREST)
		out.blit_rect(a2, Rect2i(0, 0, 640, 360), Vector2i(0, i * 360))
		out.blit_rect(b2, Rect2i(0, 0, 640, 360), Vector2i(640, i * 360))
	return out


## Дейтеранопия, матрица Machado et al. 2009 (тяжесть 1.0), приближение в sRGB.
func _deutan(src: Image) -> Image:
	var img: Image = src.duplicate()
	for y in img.get_height():
		for x in img.get_width():
			var p: Color = img.get_pixel(x, y)
			var r: float = 0.367322 * p.r + 0.860646 * p.g - 0.227968 * p.b
			var g: float = 0.280085 * p.r + 0.672501 * p.g + 0.047413 * p.b
			var b: float = -0.011820 * p.r + 0.042940 * p.g + 0.968881 * p.b
			img.set_pixel(x, y, Color(clampf(r, 0, 1), clampf(g, 0, 1), clampf(b, 0, 1), 1.0))
	return img
