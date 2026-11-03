extends SceneTree
## Иконка игры (#141): шлем «Кербер-9» на ночном небе Кобальта-9 со спорами,
## одна строка сдвинута глитчем (красный и кобальтовый каналы).
##
## Единственный источник рисунка — карта 16×16 ниже (сетка тайла, 1 символ = 1 пиксель
## иконки). Скрипт пишет из неё icon.svg (только <rect> по сетке), а все PNG рендерит
## из SVG через Image.load_svg_from_string — то есть из того же рисунка:
##   godot --headless --path . --script res://tools/icon_dump.gd
## Выход:
##   res://icon.svg                                 — иконка проекта, 128×128 (8 px на клетку);
##   res://assets/icon/icon_192.png                 — Android launcher_icons/main_192x192;
##   res://assets/icon/adaptive_foreground_432.png  — Android adaptive: шлем, плечи, глитч;
##   res://assets/icon/adaptive_background_432.png  — Android adaptive: небо, споры, гигант;
##   res://assets/icon/adaptive_monochrome_432.png  — Android 13+ (тематические иконки);
##   res://assets/icon/icon.ico                     — Windows: 16…256 px, PNG внутри;
##   res://docs/img/app_icon.png                    — лист для README: 192/96/48/32 px
##                                                    на тёмном и светлом фоне + adaptive в круге.
## Все размеры — целое число пикселей на клетку, поэтому края чёткие без nearest-хаков;
## скрипт сам проверяет, что в PNG нет цветов вне палитры (нет размытых краёв).

const OUT_ICON: String = "res://assets/icon/"
const OUT_SHEET: String = "res://docs/img/app_icon.png"

## Палитра — только цвета ADR-003: концепт A «Споровый луг» (§ 4.1) + кобальтовое железо из B.
const PAL: Dictionary = {
	".": "#161220",   # небо ночь, верх
	",": "#33243C",   # небо ночь, низ
	"p": "#5D4A68",   # газовый гигант в тени (порода средних пещер)
	"q": "#3D3049",   # его тёмная сторона (тень пещер)
	"*": "#7FE6D2",   # светящиеся споры / свечение мицелия
	"k": "#1E1719",   # контур (уголь)
	"W": "#EFE8D8",   # ткань шлема
	"e": "#E3DDCD",   # тень ткани (металл базы, эмаль)
	"g": "#9A9E94",   # ворот шлема (хлам)
	"v": "#2F4C5A",   # визор
	"h": "#7FE6D2",   # блик визора — в нём отражаются споры
	"L": "#FFE7A0",   # фонарь
	"o": "#E8743B",   # скафандр по умолчанию
	"c": "#8CF0C8",   # огонёк на нагруднике (экран терминала)
	"m": "#F0306A",   # глитч: красный канал (опасность)
	"b": "#4A7DF0",   # глитч: синий канал (кобальтовое железо)
}

## Передний план: шлем 10×9 с визором на передней половине и фонарём на углу,
## ворот, плечи. Пробел — прозрачно (там видно небо).
const FG: Array[String] = [
	"           kk   ",
	"          kLLk  ",
	"          kLLk  ",
	"  kkkkkkkkkkkk  ",
	"  keWWWWWWWWWk  ",
	"  keWWWWWWWWWk  ",
	"  keWWWvvvvvvk  ",
	"  keWWWvvvhhvk  ",
	"  keWWWvvvvhvk  ",
	"  keWWWvvvvvvk  ",
	"  keWWWWWWWWWk  ",
	"  keWWWWWWWWWk  ",
	"  kggggggggggk  ",
	" kooooooooooook ",
	" kooooWcWoooook ",
	" kooooWWWoooook ",
]

## Глитч — ровно одна полоса: [строка, первая клетка, последняя клетка, сдвиг].
## Нижняя строка визора съезжает на 2 клетки назад, в ткань шлема: передний край
## сдвинутого куска — красный канал, дыра на старом месте — синий (кобальт). Всё внутри
## силуэта шлема, поэтому снаружи иконка остаётся чистым квадратом.
const GLITCH: Array = [[8, 7, 12, -2]]

## Споры в небе (клетки сетки; за пределами 0..15 — только для фона adaptive-иконки).
const SPORES: Array[Vector2i] = [
	Vector2i(1, 7), Vector2i(14, 5), Vector2i(15, 10), Vector2i(0, 12),
	Vector2i(-2, 3), Vector2i(17, 2), Vector2i(-3, 14), Vector2i(18, 15), Vector2i(7, -3),
]

## Газовый гигант — пиксельный диск в левом верхнем углу (центр и радиус в клетках).
const GIANT_C: Vector2 = Vector2(-0.5, -0.5)
const GIANT_R: float = 4.6

## Adaptive-иконка Android: 432 px, видимая область 288, безопасная зона — круг 264.
## Шлем — 16 px на клетку: сетка 16×16 занимает 256 px с отступом 88 (88..344),
## то есть целиком внутри центральных 264 px (84..348).
const AD_SIZE: int = 432
const AD_CELL: int = 16
const AD_ORIGIN: int = 88
## Размеры Windows .ico (все кратны 16 — целое число пикселей на клетку).
const ICO_SIZES: Array[int] = [16, 32, 48, 64, 128, 256]

var _fg: Array = []   # [y][x] -> символ палитры или "" (прозрачно), после глитча


func _init() -> void:
	_fg = _apply_glitch()
	var ok: bool = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_ICON))

	# 1) icon.svg — полная иконка 16×16 клеток, 128×128 px.
	var svg_full: String = _svg(Rect2i(0, 0, 16, 16), 128, true, true, false)
	_write_text("res://icon.svg", svg_full)

	# 2) Android: обычная 192 и слои adaptive 432.
	var icon192: Image = _render(svg_full, 192)
	ok = _save(icon192, OUT_ICON + "icon_192.png") and ok
	var ad_view: Rect2i = _adaptive_view()
	var fg: Image = _render(_svg(ad_view, AD_SIZE, false, true, false), AD_SIZE)
	var bg: Image = _render(_svg(ad_view, AD_SIZE, true, false, false), AD_SIZE)
	var mono: Image = _render(_svg(ad_view, AD_SIZE, false, true, true), AD_SIZE)
	ok = _save(fg, OUT_ICON + "adaptive_foreground_432.png") and ok
	ok = _save(bg, OUT_ICON + "adaptive_background_432.png") and ok
	ok = _save(mono, OUT_ICON + "adaptive_monochrome_432.png") and ok
	ok = _check_safe_zone(fg) and ok

	# 3) Windows .ico — PNG внутри (так умеет и Windows Vista+, и экспорт Godot).
	var ico_imgs: Array[Image] = []
	for s in ICO_SIZES:
		ico_imgs.append(_render(svg_full, s))
	ok = _write_ico(ico_imgs, OUT_ICON + "icon.ico") and ok

	# 4) Лист предпросмотра для README.
	ok = _save(_sheet(svg_full, fg, bg), OUT_SHEET) and ok

	# Проверка: в каждом PNG только цвета палитры (края не размыты).
	var checks: Dictionary = {"icon_192": icon192, "fg": fg, "bg": bg, "mono": mono}
	for s in [16, 32, 48, 96]:
		checks["icon_%d" % s] = _render(svg_full, s)
	for key in checks:
		var bad: int = _off_palette(checks[key])
		print("ПАЛИТРА %s: %s" % [key, "ok" if bad == 0 else "%d пикселей вне палитры" % bad])
		ok = ok and bad == 0
	print("ИТОГ icon_dump: %s" % ("ok" if ok else "ОШИБКИ"))
	quit(0 if ok else 1)


# ------------------------------------------------------------------ РИСУНОК

## Карта переднего плана [y][x] после глитч-полосы; пробел карты → "" (прозрачно).
func _apply_glitch() -> Array:
	var rows: Array = []
	for y in FG.size():
		var row: Array = []
		for x in 16:
			var ch: String = FG[y][x]
			row.append("" if ch == " " else ch)
		rows.append(row)
	for gl in GLITCH:
		var y: int = gl[0]
		var x0: int = gl[1]
		var x1: int = gl[2]
		var dx: int = gl[3]
		var src: Array = rows[y].duplicate()
		var row: Array = src.duplicate()
		for x in range(x0, x1 + 1):
			row[x] = "b"                      # старое место — синий канал
		for x in range(x0, x1 + 1):
			if x + dx >= 0 and x + dx < 16:
				row[x + dx] = src[x]
		var lead: int = x0 + dx if dx < 0 else x1 + dx
		row[clampi(lead, 0, 15)] = "m"        # передний край — красный канал
		rows[y] = row
	return rows


## Символ переднего плана в клетке (x, y); ниже сетки плечи продолжаются гладкой
## строкой 13 (без нагрудника) — для adaptive-иконки, где видно больше вниз.
func _fg_at(x: int, y: int) -> String:
	if x < 0 or x >= 16 or y < 0:
		return ""
	return _fg[y if y < 16 else 13][x]


## Символ фона в клетке: небо ступенями, газовый гигант, споры. Определён на любой клетке.
func _bg_at(x: int, y: int) -> String:
	if SPORES.has(Vector2i(x, y)):
		return "*"
	var d: Vector2 = Vector2(x + 0.5, y + 0.5) - GIANT_C
	if d.length() < GIANT_R:
		# Освещённый край — снизу справа, остальное в тени.
		return "p" if (Vector2(x + 0.5, y + 0.5) - GIANT_C + Vector2(1.6, 1.6)).length() >= GIANT_R else "q"
	return "." if y < 8 else ","


## SVG из <rect> на сетке клеток: view — какие клетки, size — сторона в px.
## mono — силуэт для монохромной иконки: всё белым, визор (с глитчем) и ворот вырезаны.
func _svg(view: Rect2i, size: int, with_bg: bool, with_fg: bool, mono: bool) -> String:
	var lines: PackedStringArray = []
	lines.append('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="%d %d %d %d" shape-rendering="crispEdges">' % [
		size, size, view.position.x, view.position.y, view.size.x, view.size.y])
	lines.append("<!-- ГЛИТЧ-КОРЕ: шлем «Кербер-9» (ADR-003). Сгенерировано tools/icon_dump.gd — правьте карту там. -->")
	for y in range(view.position.y, view.end.y):
		var x: int = view.position.x
		while x < view.end.x:
			var ch: String = _cell(x, y, with_bg, with_fg, mono)
			var run: int = 1
			while x + run < view.end.x and _cell(x + run, y, with_bg, with_fg, mono) == ch:
				run += 1
			if ch != "":
				var col: String = "#FFFFFF" if mono else PAL[ch]
				lines.append('<rect x="%d" y="%d" width="%d" height="1" fill="%s"/>' % [x, y, run, col])
			x += run
	lines.append("</svg>")
	return "\n".join(lines) + "\n"


func _cell(x: int, y: int, with_bg: bool, with_fg: bool, mono: bool) -> String:
	if with_fg:
		var f: String = _fg_at(x, y)
		if mono and f in ["v", "h", "g", "m", "b"]:
			f = ""
		if f != "":
			return f
	return _bg_at(x, y) if with_bg else ""


## Вид adaptive-иконки в клетках: 432 px при 16 px на клетку, клетка (0,0) — на 88 px.
## Начало вида дробное (−5.5), поэтому берём целые клетки с запасом (28 клеток = 448 px),
## а _render обрезает по 8 px с каждой стороны.
func _adaptive_view() -> Rect2i:
	return Rect2i(-6, -6, 28, 28)


## Рендер SVG в PNG стороной size. Полная иконка (128 px, 16 клеток) масштабируется
## в size/128 — при size, кратном 16, это целое число пикселей на клетку.
## Adaptive-слой (вид 28 клеток) рендерится в 448 px и обрезается до 432: клетка 0 → 88 px.
func _render(svg: String, size: int) -> Image:
	var img: Image = Image.new()
	if size == AD_SIZE:
		var big: String = svg.replace('width="%d" height="%d"' % [AD_SIZE, AD_SIZE], 'width="448" height="448"')
		img.load_svg_from_string(big, 1.0)
		img.convert(Image.FORMAT_RGBA8)
		var off: int = (448 - AD_SIZE) / 2
		return img.get_region(Rect2i(off, off, AD_SIZE, AD_SIZE))
	img.load_svg_from_string(svg, float(size) / 128.0)
	img.convert(Image.FORMAT_RGBA8)
	return img


# ------------------------------------------------------------------ ЛИСТ ПРЕДПРОСМОТРА

## Две полосы (тёмная #1E1719 и светлая #F3E2C8): иконка 192, 96, 48, 32 px и
## adaptive-иконка Android под круглой маской (видимая область 288 px → 192).
func _sheet(svg_full: String, fg: Image, bg: Image) -> Image:
	var sizes: Array[int] = [192, 96, 48, 32]
	var pad: int = 32
	var w: int = pad
	for s in sizes:
		w += s + pad
	w += 192 + pad
	var band: int = 192 + pad * 2
	var sheet: Image = Image.create_empty(w, band * 2, false, Image.FORMAT_RGBA8)
	var round_icon: Image = _adaptive_preview(fg, bg, 192)
	for i in 2:
		var back: Color = Color(PAL["k"]) if i == 0 else Color("#F3E2C8")   # уголь / горизонт дня
		sheet.fill_rect(Rect2i(0, band * i, w, band), back)
		var x: int = pad
		for s in sizes:
			var icon: Image = _render(svg_full, s)
			sheet.blend_rect(icon, Rect2i(0, 0, s, s), Vector2i(x, band * i + pad + 192 - s))
			x += s + pad
		sheet.blend_rect(round_icon, Rect2i(0, 0, 192, 192), Vector2i(x, band * i + pad))
	return sheet


## Как лаунчер покажет adaptive-иконку: фон + передний план, видимые 288 px из 432,
## уменьшение до size (nearest, только для предпросмотра) и круглая маска.
func _adaptive_preview(fg: Image, bg: Image, size: int) -> Image:
	var comp: Image = bg.duplicate()
	comp.blend_rect(fg, Rect2i(0, 0, AD_SIZE, AD_SIZE), Vector2i.ZERO)
	var vis: int = 288
	var o: int = (AD_SIZE - vis) / 2
	var crop: Image = comp.get_region(Rect2i(o, o, vis, vis))
	crop.resize(size, size, Image.INTERPOLATE_NEAREST)
	var r: float = size * 0.5
	for y in size:
		for x in size:
			if Vector2(x + 0.5 - r, y + 0.5 - r).length() > r:
				crop.set_pixel(x, y, Color(0, 0, 0, 0))
	return crop


# ------------------------------------------------------------------ ПРОВЕРКИ И ЗАПИСЬ

## Сколько пикселей не совпадают ни с одним цветом палитры (или полупрозрачны).
func _off_palette(img: Image) -> int:
	var allowed: Dictionary = {}
	for ch in PAL:
		allowed[Color(PAL[ch]).to_rgba32() | 0xFF] = true
	allowed[Color.WHITE.to_rgba32()] = true
	var bad: int = 0
	for y in img.get_height():
		for x in img.get_width():
			var c: Color = img.get_pixel(x, y)
			if c.a8 == 0:
				continue
			if c.a8 != 255 or not allowed.has(c.to_rgba32()):
				bad += 1
	return bad


## Передний план adaptive-иконки весь внутри центральных 264 px, кроме плеч,
## которые нарочно уходят вниз за край (их может срезать маска — так и задумано).
func _check_safe_zone(fg: Image) -> bool:
	var lo: int = (AD_SIZE - 264) / 2
	var hi: int = lo + 264
	var shoulders_y: int = AD_ORIGIN + 13 * AD_CELL
	var bad: int = 0
	for y in shoulders_y:
		for x in AD_SIZE:
			if fg.get_pixel(x, y).a8 > 0 and (x < lo or x >= hi or y < lo):
				bad += 1
	print("БЕЗОПАСНАЯ ЗОНА adaptive (шлем и фонарь в %d..%d px): %s" % [lo, hi, "ok" if bad == 0 else "%d px снаружи" % bad])
	return bad == 0


func _save(img: Image, path: String) -> bool:
	var err: Error = img.save_png(path)
	print("%s %s (%d×%d)" % ["записан" if err == OK else "ОШИБКА %d" % err, path, img.get_width(), img.get_height()])
	return err == OK


func _write_text(path: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("записан %s" % path)


## ICO с PNG-кадрами: ICONDIR + ICONDIRENTRY на каждый размер + данные PNG.
func _write_ico(imgs: Array[Image], path: String) -> bool:
	var datas: Array[PackedByteArray] = []
	for img in imgs:
		datas.append(img.save_png_to_buffer())
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("ОШИБКА записи %s" % path)
		return false
	f.store_16(0)               # зарезервировано
	f.store_16(1)               # тип: иконка
	f.store_16(imgs.size())
	var offset: int = 6 + 16 * imgs.size()
	for i in imgs.size():
		var s: int = imgs[i].get_width()
		f.store_8(0 if s >= 256 else s)   # ширина (0 = 256)
		f.store_8(0 if s >= 256 else s)   # высота
		f.store_8(0)            # цветов в палитре
		f.store_8(0)            # зарезервировано
		f.store_16(1)           # плоскостей
		f.store_16(32)          # бит на пиксель
		f.store_32(datas[i].size())
		f.store_32(offset)
		offset += datas[i].size()
	for d in datas:
		f.store_buffer(d)
	f.close()
	print("записан %s (%s px)" % [path, ", ".join(ICO_SIZES.map(func(v: int) -> String: return str(v)))])
	return true
