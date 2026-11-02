class_name Avatar
extends RefCounted
## Шов рисования героя (ADR-002 § 4.6, D8; MP-B, #87): Avatar.draw(canvas,
## layout, look, state). Его зовут Player._draw, превью главного меню, товарищи по
## сети (их Player с чужим look) и двойник (Phantom._draw_doppel).
##
## Облик — скафандр «Кербер-9», тип A концепта «Споровый луг» (ADR-003 § 4.1,
## V4; MP-L, #97): большой квадратный шлем 10×9 из светлой ткани с визором на
## передней половине, тканевый корпус цвета игрока, ранец-фильтр спор с жёлтым
## патроном, отдельная рука, массивные боты, контур 1 px. Всё из прямоугольников.
##
## Раскладку частей считает layout() (шов #58: части «лицом вправо», при
## facing = -1 каждая отражается относительно оси героя x = 0). Её зовёт
## Player.body_layout() — героя, превью меню и двойника рисует одна раскладка.
## Раскладка зависит от look: шлем, аксессуар и ранец меняют геометрию.
## state — {"hiding": bool, "flash": 0..1 (покраснение после урона),
##          "breath": фаза (мерцание фонаря/антенны),
##          "impostor": bool (двойник: визор цвета опасности, фонарь погашен),
##          "lit": bool (визор двойника вспыхнул), "tint": Color, "tint_k": 0..1
##          (подмешать цвет — оглушение)}; нет ключа — значение покоя.

## Размер корпуса героя — Player.SIZE (равенство проверяет menu_test). Своя
## константа, чтобы шов не тянул за собой player.gd и автозагрузки мира: превью
## меню и тесты в режиме --script грузят Avatar без них.
const SIZE: Vector2 = Vector2(12.0, 22.0)
## Рамка, в которой лежат все части при любом варианте и позе (антенна, ранец и
## вытянутая рука выступают за SIZE; коллизия — SIZE). Проверяют anim_test и menu_test.
const BOUNDS: Rect2 = Rect2(-12.0, -21.0, 24.0, 33.0)

## Сколько вариантов у каждой части Look (Profile.Look.COLOR..PACK) в этой сборке.
## «Случайно» в меню выбирает только из них; индекс вне — рисуется как 0.
const VARIANTS: PackedInt32Array = [16, 4, 4, 4]

## 16 цветов скафандра — из палитры и листа концепта A (ADR-003 § 4.1, решение
## владельца в #102). Индекс 0 — цвет концепта по умолчанию. Тёмные и светлые
## остаются читаемыми: шлем светлый, контур тёмный, визор — цвет концепта.
const SUIT_COLORS: Array[Color] = [
	Color("#E8743B"),   # оранжевый — скафандр концепта по умолчанию
	Color("#D84A5A"),   # красный (лист концепта)
	Color("#E0C040"),   # горчичный (лист концепта)
	Color("#2FA39A"),   # бирюзовый (лист концепта)
	Color("#8A5AC8"),   # фиолетовый (лист концепта)
	Color("#4A70C8"),   # синий
	Color("#6E9A3A"),   # мох
	Color("#E07AA8"),   # розовый
	Color("#5CC8B0"),   # мятный (тон свечения мицелия)
	Color("#94685A"),   # глина (тень поверхности)
	Color("#B08CA4"),   # сирень (дальние горы)
	Color("#5E6B78"),   # графит (рамы базы)
	Color("#E3DDCD"),   # эмаль (металл базы)
	Color("#94474A"),   # «плоть» глубины
	Color("#F2B8A0"),   # персик (флора)
	Color("#5D4A68"),   # слива (порода пещер)
]
## Подписи вариантов для меню, по частям.
const VARIANT_NAMES: Array = [
	["Оранжевый", "Красный", "Горчичный", "Бирюзовый", "Фиолетовый", "Синий", "Мох", "Розовый",
			"Мятный", "Глина", "Сирень", "Графит", "Эмаль", "Бордо", "Персик", "Слива"],
	["Квадратный", "Высокий", "Панорамный", "Щиток"],
	["Фонарь", "Антенна", "Нет", "Два фонаря"],
	["Ранец-фильтр", "Удлинённый", "Два баллона", "Компактный"],
]

## Цвета концепта (ADR-003 § 4.1, PAL.spore): игрок их не меняет.
const FABRIC: Color = Color("#EFE8D8")		## ткань шлема, ранца, нагрудника
const FABRIC_D: Color = Color("#B5AC9A")	## тень ткани: пояс, перчатки, ворот шлема
const VISOR: Color = Color("#2F4C5A")
const VISOR_TOP: Color = Color("#3D6474")	## верхняя строка визора
const VISOR_HI: Color = Color("#A8E6E0")	## блик визора
const LAMP: Color = Color("#FFE7A0")
const LAMP_OFF: Color = Color(0.22, 0.18, 0.20)	## погашенный фонарь двойника
const HAZARD: Color = Color("#E3B341")		## жёлтый патрон фильтра, полосы баллонов
const LED: Color = Color("#8CF0C8")			## огонёк на нагруднике
const ANT_TIP: Color = Color("#FF9A5C")		## мигающий кончик антенны
const OUTLINE: Color = Color("#2A1E24")
const DANGER: Color = Color("#F0306A")		## визор двойника — цвет опасности
const HURT: Color = Color(1.0, 0.74, 0.64)	## покраснение после урона
const HURT_LINE: Color = Color(1.0, 0.35, 0.32)
const SHADOW: Color = Color(0, 0, 0, 0.28)

## Кэш раскладок: ключ — вариант шлема/аксессуара/ранца, facing и целочисленная
## поза (шаг, подъём, прыжок, работа). Цвет на раскладку не влияет.
static var _cache: Dictionary = {}
const CACHE_MAX: int = 2048

## Части силуэта, обводимые контуром (порядок не важен: контур — первым проходом).
const OUTLINED: Array[StringName] = [&"backpack", &"tank", &"leg_back", &"boot_back", &"torso",
		&"helmet", &"crown", &"brim", &"leg_front", &"boot_front", &"arm", &"glove",
		&"antenna", &"antenna_tip", &"lamp", &"lamp2"]
const LAMPS: Array[StringName] = [&"lamp", &"lamp2"]


## Индекс части i для рисования: неизвестный этой сборке (≥ VARIANTS[i]) — 0.
static func resolve(look: int, i: int) -> int:
	var idx: int = Profile.Look.part(look, i)
	return idx if idx < VARIANTS[i] else 0


## Цвет скафандра по look (неизвестный индекс — цвет 0).
static func suit_color(look: int) -> Color:
	return SUIT_COLORS[resolve(look, Profile.Look.COLOR)]


static func variant_name(i: int, idx: int) -> String:
	var names: Array = VARIANT_NAMES[i]
	return String(names[idx]) if idx >= 0 and idx < names.size() else String(names[0])


## Случайный вид из вариантов VARIANTS. rng — свой генератор вызывающего.
static func random_look(rng: RandomNumberGenerator) -> int:
	var parts: PackedInt32Array = PackedInt32Array()
	for i in Profile.Look.PARTS:
		parts.append(rng.randi_range(0, VARIANTS[i] - 1))
	return Profile.Look.pack(parts)


# ------------------------------------------------------------------ РАСКЛАДКА

## Раскладка частей героя в его локальных координатах (центр корпуса 12×22 —
## начало координат, ступни на y = 11). Все части задаются «лицом вправо» и
## при facing < 0 отражаются относительно x = 0.
##   walk   — фаза шага (Player.walk_anim), breath — фаза дыхания;
##   move   — доля скорости бега 0..1 (|vel.x| / Player.SPEED);
##   air    — в прыжке/падении (ноги врозь, рука назад);
##   work   — копает/чинит перед собой (рука вытянута вперёд).
## Ключи — Rect2: body (габарит фигуры), torso, helmet, visor, visor_top,
## visor_glint, arm, glove, backpack, tank (патрон/второй баллон), leg_back,
## leg_front, boot_back, boot_front, chest, chest_led; по варианту ещё crown
## (высокий шлем), brim (щиток), lamp, lamp2, antenna, antenna_tip.
## light — Vector2, место фонаря на шлеме (есть всегда); facing — ±1.
## Словарь общий (кэш) и только для чтения: дополнять — через duplicate().
static func layout(look: int, facing: int, walk: float, breath: float, move: float,
		air: bool, work: bool) -> Dictionary:
	var helm: int = (look >> 4) & 0xF
	var acc: int = (look >> 8) & 0xF
	var pack: int = (look >> 12) & 0xF
	if helm >= VARIANTS[1]:
		helm = 0
	if acc >= VARIANTS[2]:
		acc = 0
	if pack >= VARIANTS[3]:
		pack = 0
	move = clampf(move, 0.0, 1.0)
	var idle: float = clampf(1.0 - move * 2.8, 0.0, 1.0)
	var sw: float = sin(walk)
	# Шаг — целыми пикселями: ведущая нога на 1 px вперёд и приподнята.
	var stride: int = 0
	if move > 0.05:
		var s: float = sw * move
		stride = 1 if s > 0.35 else (-1 if s < -0.35 else 0)
	# Подъём корпуса на 1 px: на шаге — когда ноги проходят друг мимо друга,
	# в покое — на вдохе.
	var up: float = 0.0
	if not air:
		if move > 0.3:
			up = -1.0 if absf(sw) < 0.5 else 0.0
		elif sin(breath * 1.8) * idle > 0.5:
			up = -1.0
	var feet: float = SIZE.y * 0.5
	var yt: float = -2.0 + up		# верх корпуса
	var yh: float = yt - 9.0		# верх шлема
	var leg_top: float = yt + 8.0
	var fx: float = float(stride)
	var bx: float = -float(stride)
	var f_lift: float = 1.0 if stride > 0 else 0.0
	var b_lift: float = 1.0 if stride < 0 else 0.0
	if air:
		fx = 1.0
		bx = -1.0
		f_lift = 2.0
		b_lift = 1.0
	var f: int = -1 if facing < 0 else 1
	# Раскладка целочисленная: поз немного, их раскладки кэшируются.
	var key: int = (helm << 4) | (acc << 8) | (pack << 12) | ((f + 1) << 16) 			| ((0 if air else stride + 1) << 18) | (int(up < 0.0) << 20) | (int(air) << 21) | (int(work) << 22)
	var hit: Variant = _cache.get(key)
	if hit != null:
		return hit
	var lay: Dictionary = {}
	lay["facing"] = f
	lay["body"] = Rect2(-SIZE.x * 0.5, yh, SIZE.x, feet - yh)
	lay["torso"] = mirror(Rect2(-5.0, yt, 10.0, 8.0), f)
	lay["helmet"] = mirror(Rect2(-5.0, yh, 10.0, 9.0), f)
	lay["chest"] = mirror(Rect2(2.0, yt + 2.0, 3.0, 3.0), f)
	lay["chest_led"] = mirror(Rect2(3.0, yt + 3.0, 1.0, 1.0), f)
	# Ноги и боты: задняя — с пяткой назад, передняя — носком вперёд.
	lay["leg_back"] = mirror(Rect2(-4.0 + bx, leg_top, 4.0, feet - 2.0 - b_lift - leg_top), f)
	lay["boot_back"] = mirror(Rect2(-5.0 + bx, feet - 2.0 - b_lift, 4.0, 2.0), f)
	lay["leg_front"] = mirror(Rect2(1.0 + fx, leg_top, 4.0, feet - 2.0 - f_lift - leg_top), f)
	lay["boot_front"] = mirror(Rect2(1.0 + fx, feet - 2.0 - f_lift, 5.0, 2.0), f)
	# Рука: вытянута вперёд в работе, отведена назад в прыжке, на шаге — против ноги.
	if work:
		lay["arm"] = mirror(Rect2(1.0, yt + 2.0, 6.0, 3.0), f)
		lay["glove"] = mirror(Rect2(7.0, yt + 2.0, 2.0, 3.0), f)
	else:
		var ax: float = -3.0 if air else -2.0 * float(stride)
		lay["arm"] = mirror(Rect2(-1.0 + ax, yt + 1.0, 3.0, 5.0), f)
		lay["glove"] = mirror(Rect2(-1.0 + ax, yt + 6.0, 3.0, 2.0), f)
	# Шлем и визор по варианту.
	var visor: Rect2
	var top: float = yh
	match helm:
		1:	# высокий шлем с большим визором
			lay["crown"] = mirror(Rect2(-4.0, yh - 2.0, 8.0, 2.0), f)
			top = yh - 2.0
			visor = Rect2(-2.0, yh, 7.0, 6.0)
		2:	# панорамный визор во всю ширину
			visor = Rect2(-4.0, yh + 3.0, 9.0, 3.0)
		3:	# щиток над узкой щелью
			lay["brim"] = mirror(Rect2(-1.0, yh + 2.0, 8.0, 1.0), f)
			visor = Rect2(0.0, yh + 3.0, 5.0, 2.0)
		_:	# квадратный шлем, визор на передней половине
			visor = Rect2(-1.0, yh + 2.0, 6.0, 4.0)
	lay["visor"] = mirror(visor, f)
	lay["visor_top"] = mirror(Rect2(visor.position.x, visor.position.y, visor.size.x, 1.0), f)
	lay["visor_glint"] = mirror(Rect2(visor.position.x + 1.0, visor.position.y, 2.0, 1.0), f)
	# Аксессуар: фонарь на переднем углу шлема, антенна на заднем.
	lay["light"] = Vector2(5.0 * f, yh)
	match acc:
		0:
			lay["lamp"] = mirror(Rect2(4.0, yh - 1.0, 2.0, 2.0), f)
		1:
			lay["antenna"] = mirror(Rect2(-4.0, top - 4.0, 1.0, 4.0), f)
			lay["antenna_tip"] = mirror(Rect2(-5.0, top - 6.0, 2.0, 2.0), f)
		3:
			lay["lamp"] = mirror(Rect2(4.0, yh - 1.0, 2.0, 2.0), f)
			lay["lamp2"] = mirror(Rect2(1.0, top - 1.0, 2.0, 2.0), f)
	# Ранец за спиной; tank — жёлтый патрон фильтра или второй баллон.
	match pack:
		1:	# удлинённый ранец
			lay["backpack"] = mirror(Rect2(-9.0, yt - 1.0, 4.0, 11.0), f)
			lay["tank"] = mirror(Rect2(-10.0, yt + 2.0, 1.0, 6.0), f)
		2:	# два баллона
			lay["backpack"] = mirror(Rect2(-7.0, yt - 1.0, 2.0, 9.0), f)
			lay["tank"] = mirror(Rect2(-10.0, yt, 2.0, 8.0), f)
		3:	# компактный ранец, патрон сверху
			lay["backpack"] = mirror(Rect2(-8.0, yt + 1.0, 3.0, 5.0), f)
			lay["tank"] = mirror(Rect2(-8.0, yt, 3.0, 1.0), f)
		_:	# ранец-фильтр спор
			lay["backpack"] = mirror(Rect2(-9.0, yt, 4.0, 7.0), f)
			lay["tank"] = mirror(Rect2(-10.0, yt + 2.0, 1.0, 4.0), f)
	lay.make_read_only()
	if _cache.size() >= CACHE_MAX:
		_cache.clear()
	_cache[key] = lay
	return lay


## Отражение прямоугольника относительно оси героя, если он смотрит влево.
static func mirror(r: Rect2, f: int) -> Rect2:
	if f >= 0:
		return r
	return Rect2(-r.end.x, r.position.y, r.size.x, r.size.y)


# ------------------------------------------------------------------ РИСУНОК

## Рисует героя на canvas (внутри его _draw) в локальных координатах героя.
## Преобразование холста не трогает: двойник отражает рисунок своим.
static func draw(canvas: CanvasItem, lay: Dictionary, look: int, state: Dictionary) -> void:
	var hiding: bool = state.get("hiding", false)
	var flash: float = state.get("flash", 0.0)
	var breath: float = state.get("breath", 0.0)
	var impostor: bool = state.get("impostor", false)
	var tint_k: float = state.get("tint_k", 0.0)
	var ci: int = look & 0xF
	var pack: int = (look >> 12) & 0xF
	var pc: Color = SUIT_COLORS[ci if ci < VARIANTS[0] else 0]
	var c2: Color = FABRIC
	var c2d: Color = FABRIC_D
	var vis: Color = VISOR
	var out: Color = OUTLINE
	if tint_k > 0.0:
		var tint: Color = state.get("tint", Color.WHITE)
		pc = pc.lerp(tint, tint_k)
		c2 = c2.lerp(tint, tint_k * 0.6)
		c2d = c2d.lerp(tint, tint_k * 0.6)
	if hiding:
		pc = pc.darkened(0.45)
		c2 = c2.darkened(0.45)
		c2d = c2d.darkened(0.45)
		vis = vis.darkened(0.45)
	# Покраснение после урона: ткань теплеет, контур краснеет.
	if flash > 0.0:
		pc = pc.lerp(HURT, flash * 0.85)
		c2 = c2.lerp(HURT, flash * 0.6)
		out = out.lerp(HURT_LINE, flash)
	var pd: Color = pc.darkened(0.28)
	var boot: Color = c2d.darkened(0.35)

	# Тень — плоская, ступенькой.
	var feet: float = SIZE.y * 0.5
	canvas.draw_rect(Rect2(-7.0, feet, 14.0, 1.0), SHADOW)
	canvas.draw_rect(Rect2(-5.0, feet + 1.0, 10.0, 1.0), SHADOW)
	# Контур 1 px вокруг всего силуэта — первым проходом, под заливкой.
	for k in OUTLINED:
		var o: Variant = lay.get(k)
		if o != null:
			canvas.draw_rect((o as Rect2).grow(1.0), out)

	# Ранец и патрон / баллоны.
	var bp: Rect2 = lay["backpack"]
	var tk: Rect2 = lay["tank"]
	if pack == 2:
		for r: Rect2 in [bp, tk]:
			canvas.draw_rect(r, c2)
			canvas.draw_rect(Rect2(r.position.x, r.end.y - 2.0, r.size.x, 2.0), c2d)
			canvas.draw_rect(Rect2(r.position.x, r.position.y + 2.0, r.size.x, 1.0), HAZARD)
	else:
		canvas.draw_rect(bp, c2d)
		canvas.draw_rect(Rect2(bp.position.x, bp.position.y, bp.size.x, 1.0), c2)
		canvas.draw_rect(tk, HAZARD)
	# Задняя нога — темнее.
	canvas.draw_rect(lay["leg_back"], pd)
	canvas.draw_rect(lay["boot_back"], boot)
	# Корпус: светлая строка сверху, пояс, нагрудник с огоньком.
	var t: Rect2 = lay["torso"]
	canvas.draw_rect(t, pc)
	canvas.draw_rect(Rect2(t.position.x, t.position.y, t.size.x, 1.0), pc.lightened(0.2))
	canvas.draw_rect(Rect2(t.position.x, t.end.y - 2.0, t.size.x, 2.0), c2d)
	canvas.draw_rect(lay["chest"], c2)
	canvas.draw_rect(lay["chest_led"], LED if not hiding else LED.darkened(0.5))
	# Передняя нога.
	canvas.draw_rect(lay["leg_front"], pc)
	canvas.draw_rect(lay["boot_front"], boot)
	# Шлем: светлая ткань, ворот снизу.
	var h: Rect2 = lay["helmet"]
	var crown: Variant = lay.get(&"crown")
	if crown != null:
		canvas.draw_rect(crown, c2)
	canvas.draw_rect(h, c2)
	if crown == null:
		canvas.draw_rect(Rect2(h.position.x, h.position.y, h.size.x, 1.0), c2.lightened(0.1))
	canvas.draw_rect(Rect2(h.position.x, h.end.y - 1.0, h.size.x, 1.0), c2d)
	var brim: Variant = lay.get(&"brim")
	if brim != null:
		canvas.draw_rect(brim, c2d)
	# Визор. У двойника — цвет опасности, вспыхивает (state.lit).
	var vtop: Color = VISOR_TOP
	if impostor:
		var lit: bool = state.get("lit", true)
		vis = DANGER.lightened(0.15) if lit else DANGER.darkened(0.45)
		vtop = DANGER.lightened(0.45) if lit else DANGER.darkened(0.3)
	elif hiding:
		vtop = vtop.darkened(0.45)
	canvas.draw_rect(lay["visor"], vis)
	canvas.draw_rect(lay["visor_top"], vtop)
	canvas.draw_rect(lay["visor_glint"], VISOR_HI if not hiding else VISOR_HI.darkened(0.45))
	# Рука поверх корпуса, перчатка — тканью.
	canvas.draw_rect(lay["arm"], pd)
	canvas.draw_rect(lay["glove"], c2d)
	# Аксессуар: фонарь светит ровно с лёгким ореолом, кончик антенны мигает.
	var pulse: float = 0.5 + 0.5 * sin(breath * 6.0)
	var ant: Variant = lay.get(&"antenna")
	if ant != null:
		canvas.draw_rect(ant, c2d)
		var tip: Rect2 = lay["antenna_tip"]
		canvas.draw_rect(tip, LAMP_OFF if impostor or hiding else ANT_TIP.lerp(Color.WHITE, pulse * 0.3))
		if not impostor and not hiding:
			canvas.draw_rect(tip.grow(1.0), Color(ANT_TIP, 0.18 + 0.22 * pulse))
	for k in LAMPS:
		var l: Variant = lay.get(k)
		if l == null:
			continue
		if impostor or hiding:
			canvas.draw_rect(l, LAMP_OFF)
		else:
			canvas.draw_rect(l, LAMP)
			canvas.draw_rect((l as Rect2).grow(1.0), Color(LAMP, 0.16 + 0.12 * pulse))

	if hiding:
		# Укрытие: квадратная рамка вокруг героя.
		canvas.draw_rect(Rect2(-13.0, -15.0, 26.0, 28.0), Color(0.4, 0.9, 1.0, 0.5), false, 1.0)
