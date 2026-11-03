extends SceneTree
class_name MenuTest
## Автотест профиля, параметров вида и главного меню (ADR-002 § 4.6, MP-B, #87).
##
## Проверяет: таблицу ников (валидные/невалидные), профиль туда-обратно во
## временный путь (uid создаётся один раз, битый файл не валит), Look ↔ u16 для
## всех индексов 0..15 каждой части, неизвестный индекс рисуется как 0, «Случайно»
## только из Avatar.VARIANTS, меню строится и реагирует на ник/вид; сетевые экраны
## (MP-H, #93): разбор адреса «По IP», форма «Создать игру», формат и совместимость
## поиска (LanDiscovery), запрос/ответ на 127.0.0.1, кадр LOBBY, «Недавние» в профиле.
## Скафандр «Кербер-9» (V4, MP-L #97): 16 цветов, 4 шлема, 4 аксессуара, 4 ранца,
## неизвестный индекс части рисуется как 0, раскладка каждого варианта полна.
## Отдельный запуск сверх того: «Одиночная игра» из меню запускает мир с сидом,
## хардкором и цветом из профиля; замер Player._draw: рисунок до V4 (прежний
## красный герой) против скафандра.
##
## Отдельный запуск:
##   godot --headless --path . --script res://tools/menu_test.gd
## В составе общего прогона (--test) те же проверки вызывает tools/test_runner.gd
## (секция «== Меню и профиль ==») — общий код, без дублирования; смену сцены
## и замер там не делаем (раннер живёт в сцене игры).
##
## Снимок меню, листы героя и вариантов (нужен настоящий рендер, окно — за
## экраном); каждый вариант рисуется и отличается от соседей по части:
##   godot --path . --windowed --position -10000,-10000 --resolution 1280x720 \
##         --script res://tools/menu_test.gd -- --menu-shot=res://docs/img/menu.png \
##         --sheets=res://docs/img/
## (--sheets= — папка для player_facing.png и avatar_variants.png).
##
## Режим --script: глобальные имена автозагрузок и player.gd (он ссылается на
## World) на этапе компиляции недоступны — их берём через load()/get_node().
## Profile и Avatar от автозагрузок не зависят.

const MENU_SCENE: String = "res://scenes/menu.tscn"
const MENU_SCRIPT: String = "res://scripts/ui/main_menu.gd"
## Скрипт автозагрузки Net (MP-A): правила ника — его static nick_error(). Узел Net
## берём через get_node("/root/Net") — имя автозагрузки в --script недоступно.
const NetScript = preload("res://scripts/autoload/net.gd")
const PLAYER_SCRIPT: String = "res://scripts/entities/player.gd"
## Временный профиль: настоящий user://profile.cfg тест не трогает. Файл — свой у
## процесса (TestEnv.file: profile~t<pid>.cfg), параллельные прогоны не мешают (#132).
const TMP_DIR: String = "user://menu_test"
const TMP_PROFILE: String = "user://menu_test/profile.cfg"
## Синтетические сохранения «Загрузить» (#132): одиночное, сетевое, битое.
const SAVE_SLOTS: Array = ["menu_a", "menu_b", "menu_c"]
## Скафандр концепта A по умолчанию (ADR-003 § 4.1) — вид 0.
const SUIT_DEFAULT: Color = Color("#E8743B")

const NICKS_OK: Array = ["Аня", "Ёжик", "ёж", "Bob", "x1", "Аня 2", "Ann_Lee", "a-b.c",
		"  Пётр  ", "1234567890123456", "Инженер", "Zz", "Юля.К"]
const NICKS_BAD: Array = ["", " ", "a", "  b  ", "12345678901234567", "_Аня", "Аня_",
		"-x", "x.", "Аня  Петя", "Ann!", "Ник@", "日本", "Ølaf", "a\tb", "Ӂук", "😀😀"]

## Прогонов замера (кадров) и рисунков героя за кадр.
const BENCH_FRAMES: int = 120
const BENCH_REPS: int = 200

## Узел-замер: наследник player.gd (из исходника во время выполнения — см. шапку),
## рисует себя BENCH_REPS раз за кадр нынешним _draw или прежним (old).
const BENCH_PLAYER_SRC: String = """extends "res://scripts/entities/player.gd"
var reps: int = 1
var usec: int = 0
var calls: int = 0
var best: float = 1e9
var old: bool = false
func _ready() -> void:
	pass
func _physics_process(_d: float) -> void:
	pass
func _draw() -> void:
	var t0: int = Time.get_ticks_usec()
	for i in reps:
		_breath = float(i) * 0.1
		# После V4 — все варианты частей по кругу (раскладка от них зависит).
		look = (i & 0xF) | (((i >> 1) & 3) << 4) | (((i >> 3) & 3) << 8) | (((i >> 5) & 3) << 12)
		if old:
			_old_draw()
		else:
			super._draw()
	var dt: int = Time.get_ticks_usec() - t0
	usec += dt
	calls += reps
	best = minf(best, float(dt) / float(reps))
## Player._draw до MP-B дословно (коммит c2e8802, scripts/entities/player.gd),
## раскладка — body_layout() до V4 (MenuTest.Legacy.layout).
func _old_draw() -> void:
	var body_col: Color = Color(0.86, 0.22, 0.24)
	if hiding:
		body_col = body_col.darkened(0.45)
	var flash: float = _hit_flash / HIT_FLASH
	if flash > 0.0:
		body_col = body_col.lerp(Color(1.0, 0.74, 0.64), flash * 0.85)
	var lay: Dictionary = MenuTest.Legacy.layout(facing, walk_anim, _breath, vel.x)
	var r: Rect2 = lay["body"]
	draw_set_transform(Vector2(0, SIZE.y * 0.5), 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, SIZE.x * 0.6, Color(0, 0, 0, 0.28))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rect(lay["backpack"], body_col.darkened(0.25))
	draw_rect(r, body_col)
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 3.0), body_col.lightened(0.18))
	draw_rect(Rect2(r.position.x, r.end.y - 3.0, r.size.x, 3.0), body_col.darkened(0.22))
	draw_rect(lay["leg_back"], body_col.darkened(0.35))
	draw_rect(lay["leg_front"], body_col.darkened(0.35))
	draw_rect(lay["visor"], Color(0.72, 0.86, 0.94))
	draw_rect(lay["visor_top"], Color(0.88, 0.96, 1.0))
	draw_rect(lay["visor_glint"], Color(1, 1, 1, 0.85))
	var blink: float = 0.5 + 0.5 * sin(_breath * 6.0)
	draw_circle(lay["light"], 1.6, Color(1.0, 0.35, 0.3, 0.5 + blink * 0.5))
	if flash > 0.0:
		draw_rect(r, Color(1.0, 0.35, 0.32, flash * 0.8), false, 1.5)
	if hiding:
		draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 24, Color(0.4, 0.9, 1.0, 0.5), 1.5)
	_draw_mining_fx(Vector2(0.0, -6.0))
"""


## Прежний герой (до V4) дословно, с параметрами вместо полей героя: эталон
## «до» для замера и листа player_facing.png.
class Legacy:
	## Player.body_layout() до V4 (коммит d87421c).
	static func layout(facing: int, walk_anim: float, breath: float, vx: float) -> Dictionary:
		var size: Vector2 = Vector2(12.0, 22.0)
		var idle_amt: float = clampf(1.0 - absf(vx) / 60.0, 0.0, 1.0)
		var move_amt: float = clampf(absf(vx) / 168.0, 0.0, 1.0)
		var breathe: float = sin(breath * 1.8) * idle_amt
		var bounce: float = -absf(sin(walk_anim)) * 1.4 * move_amt
		var body_h: float = size.y * (1.0 + 0.03 * breathe)
		var r: Rect2 = Rect2(-size.x * 0.5, size.y * 0.5 - body_h + bounce, size.x, body_h)
		var step: float = sin(walk_anim) * 2.0
		var visor: Rect2 = Rect2(-1.0, r.position.y + 2.0, 11.0, 7.0)
		var light: Vector2 = Vector2(visor.position.x + 8.0, visor.position.y)
		var f: int = -1 if facing < 0 else 1
		return {
			"body": r,
			"backpack": Avatar.mirror(Rect2(-r.size.x * 0.5 - 5.0, -r.size.y * 0.5 + 3.0, 5.0, r.size.y - 7.0), f),
			"leg_back": Avatar.mirror(Rect2(-4.0, r.end.y - 3.0, 3.0, 3.0 + step), f),
			"leg_front": Avatar.mirror(Rect2(1.0, r.end.y - 3.0, 3.0, 3.0 - step), f),
			"visor": Avatar.mirror(visor, f),
			"visor_top": Avatar.mirror(Rect2(visor.position.x, visor.position.y, visor.size.x, 2.0), f),
			"visor_glint": Avatar.mirror(Rect2(visor.position.x + 1.0, visor.position.y + 1.0, 3.0, 2.0), f),
			"light": Vector2(light.x * f, light.y),
		}


	## xf — преобразование холста, под которым рисуем (лист с увеличением).
	static func draw(c: CanvasItem, lay: Dictionary, hiding: bool, flash: float, breath: float,
			xf: Transform2D = Transform2D.IDENTITY) -> void:
		var size: Vector2 = Vector2(12.0, 22.0)
		var body_col: Color = Color(0.86, 0.22, 0.24)
		if hiding:
			body_col = body_col.darkened(0.45)
		if flash > 0.0:
			body_col = body_col.lerp(Color(1.0, 0.74, 0.64), flash * 0.85)
		var r: Rect2 = lay["body"]
		c.draw_set_transform_matrix(xf * Transform2D(0.0, Vector2(1.0, 0.35), 0.0, Vector2(0, size.y * 0.5)))
		c.draw_circle(Vector2.ZERO, size.x * 0.6, Color(0, 0, 0, 0.28))
		c.draw_set_transform_matrix(xf)
		c.draw_rect(lay["backpack"], body_col.darkened(0.25))
		c.draw_rect(r, body_col)
		c.draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 3.0), body_col.lightened(0.18))
		c.draw_rect(Rect2(r.position.x, r.end.y - 3.0, r.size.x, 3.0), body_col.darkened(0.22))
		c.draw_rect(lay["leg_back"], body_col.darkened(0.35))
		c.draw_rect(lay["leg_front"], body_col.darkened(0.35))
		c.draw_rect(lay["visor"], Color(0.72, 0.86, 0.94))
		c.draw_rect(lay["visor_top"], Color(0.88, 0.96, 1.0))
		c.draw_rect(lay["visor_glint"], Color(1, 1, 1, 0.85))
		var blink: float = 0.5 + 0.5 * sin(breath * 6.0)
		c.draw_circle(lay["light"], 1.6, Color(1.0, 0.35, 0.3, 0.5 + blink * 0.5))
		if flash > 0.0:
			c.draw_rect(r, Color(1.0, 0.35, 0.32, flash * 0.8), false, 1.5)
		if hiding:
			c.draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 24, Color(0.4, 0.9, 1.0, 0.5), 1.5)


## Лист картинок: герои (до V4 — Legacy, после — Avatar.draw) и подписи.
## items: {pos, scale, lay, look, state, legacy?, pick? (кирка из точки), cell?}.
## labels: [позиция, текст, кегль, цвет].
class Sheet extends Node2D:
	const BG: Color = Color("#1E1A22")
	const INK: Color = Color(0.82, 0.84, 0.88)
	const DIM: Color = Color(0.62, 0.64, 0.70)
	const BAD: Color = Color(0.95, 0.45, 0.42)
	const GOOD: Color = Color(0.45, 0.88, 0.55)
	var size_px: Vector2 = Vector2(64, 64)
	var items: Array = []
	var labels: Array = []

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size_px), BG)
		var font: Font = ThemeDB.fallback_font
		for l in labels:
			# Пятое поле — ширина: подпись по центру клетки.
			var w: float = l[4] if l.size() > 4 else -1.0
			draw_string(font, l[0], l[1], HORIZONTAL_ALIGNMENT_CENTER if w > 0.0 else HORIZONTAL_ALIGNMENT_LEFT,
					w, l[2], l[3])
		for it in items:
			var xf: Transform2D = Transform2D(0.0, Vector2(it["scale"], it["scale"]), 0.0, it["pos"])
			draw_set_transform_matrix(xf)
			var st: Dictionary = it["state"]
			if it.get("legacy", false):
				Legacy.draw(self, it["lay"], st.get("hiding", false), st.get("flash", 0.0),
						st.get("breath", 0.0), xf)
			else:
				Avatar.draw(self, it["lay"], it["look"], st)
			if it.has("pick"):
				_pick(it["pick"], it["cell"])
		draw_set_transform_matrix(Transform2D.IDENTITY)

	## Кирка как в Player._draw_mining_fx (без контура клетки): из pivot к клетке.
	func _pick(pivot: Vector2, cell: Vector2) -> void:
		var to_cell: Vector2 = cell - pivot
		var ang: float = to_cell.angle()
		var reach: float = clampf(to_cell.length(), 10.0, 30.0)
		var head: Vector2 = pivot + Vector2(cos(ang), sin(ang)) * reach
		draw_line(pivot, head, Color(0.42, 0.32, 0.24), 2.0)
		var perp: Vector2 = Vector2(-sin(ang), cos(ang))
		draw_line(head - perp * 4.5, head + perp * 4.5, Color(0.78, 0.82, 0.88), 2.0)


## --------------------------------------------------------------------- исполнитель
class Runner extends Node:
	var host: Node = null
	var checks: int = 0
	var fails: int = 0
	var done: bool = false
	## Отдельный запуск: ещё замер (в общем прогоне — нет).
	var bench: bool = false

	var _menu = null
	var _bench_nodes: Array = []
	var _frames: int = 0
	var _phase: int = 0

	func _init(p_host: Node = null, p_bench: bool = false) -> void:
		host = p_host
		bench = p_bench

	func start(_main_scene: Node) -> void:
		print("== Меню и профиль ==")
		_check_nicks()
		_check_look()
		_check_avatar()
		_check_profile()
		_check_menu()
		_check_saves()         # «Загрузить» (#132)
		_check_net_forms()     # MP-H (#93)
		_check_discovery()     # MP-H (#93)
		if bench:
			_bench_start()
			_phase = 1
		else:
			done = true

	func _process(_delta: float) -> void:
		if _phase != 1:
			return
		_frames += 1
		for n in _bench_nodes:
			n.queue_redraw()
		if _frames < BENCH_FRAMES:
			return
		_phase = 2
		_bench_report()
		done = true

	func _ok(label: String, cond: bool, extra: String = "") -> void:
		checks += 1
		if cond:
			print("  OK   %s %s" % [label, extra])
		else:
			fails += 1
			print("  FAIL %s %s" % [label, extra])

	# --- Ник
	func _check_nicks() -> void:
		var bad_ok: Array = []
		for n in NICKS_OK:
			if not Profile.is_valid_nick(n):
				bad_ok.append("%s: %s" % [n, NetScript.nick_error(n)])
		_ok("валидные ники приняты (%d)" % NICKS_OK.size(), bad_ok.is_empty(), str(bad_ok))
		var passed: Array = []
		var no_reason: Array = []
		for n in NICKS_BAD:
			if Profile.is_valid_nick(n):
				passed.append(n)
			elif NetScript.nick_error(n) == "":
				no_reason.append(n)
		_ok("невалидные ники отклонены (%d)" % NICKS_BAD.size(), passed.is_empty(), str(passed))
		_ok("у отказа есть причина", no_reason.is_empty(), str(no_reason))
		_ok("ник по умолчанию валиден", Profile.is_valid_nick(Profile.DEFAULT_NICK))
		_ok("Profile.is_valid_nick — те же правила, что Net.nick_error",
				Profile.is_valid_nick("Аня 2") and not Profile.is_valid_nick("Аня  2"))

	# --- Look ↔ u16
	func _check_look() -> void:
		var bad: Array = []
		for i in Profile.Look.PARTS:
			for idx in Profile.Look.SIZE:
				var parts: PackedInt32Array = PackedInt32Array([3, 7, 11, 15])
				parts[i] = idx
				var v: int = Profile.Look.pack(parts)
				if v < 0 or v > 0xFFFF or Profile.Look.unpack(v) != parts \
						or Profile.Look.part(v, i) != idx \
						or Profile.Look.with_part(Profile.Look.pack(PackedInt32Array([3, 7, 11, 15])), i, idx) != v:
					bad.append("часть %d индекс %d" % [i, idx])
		_ok("Look ↔ u16: все индексы 0..15 каждой части", bad.is_empty(), str(bad.slice(0, 4)))
		var miss: int = 0
		for v in 0x10000:
			if Profile.Look.pack(Profile.Look.unpack(v)) != v:
				miss += 1
		_ok("u16 → Look → u16 без потерь (65536 значений)", miss == 0, "расхождений %d" % miss)
		_ok("биты частей: цвет 0–3, шлем 4–7, аксессуар 8–11, рюкзак 12–15",
				Profile.Look.pack(PackedInt32Array([1, 2, 3, 4])) == 0x4321)

	# --- Avatar: варианты, неизвестный индекс, «Случайно»
	func _check_avatar() -> void:
		var player_size: Vector2 = load(PLAYER_SCRIPT).SIZE
		_ok("Avatar.SIZE = Player.SIZE", Avatar.SIZE == player_size, str(player_size))
		var counts_ok: bool = Avatar.VARIANTS.size() == Profile.Look.PARTS
		for i in Avatar.VARIANTS.size():
			counts_ok = counts_ok and Avatar.VARIANTS[i] >= 1 and Avatar.VARIANTS[i] <= Profile.Look.SIZE \
					and (Avatar.VARIANT_NAMES[i] as Array).size() == Avatar.VARIANTS[i]
		_ok("VARIANTS: 4 части, 1..16 вариантов, подписи есть", counts_ok, str(Avatar.VARIANTS))
		_ok("V4: 16 цветов, 4 шлема, 4 аксессуара, 4 ранца",
				Avatar.VARIANTS == PackedInt32Array([16, 4, 4, 4]) and Avatar.SUIT_COLORS.size() == 16)
		_ok("вид 0 — скафандр концепта A (#E8743B)", Avatar.suit_color(0).is_equal_approx(SUIT_DEFAULT))
		var distinct: Dictionary = {}
		for c in Avatar.SUIT_COLORS:
			distinct[c.to_html(false)] = true
		_ok("16 цветов скафандра различны", distinct.size() == 16, "%d" % distinct.size())
		var wrong: Array = []
		for i in Profile.Look.PARTS:
			for idx in Profile.Look.SIZE:
				var v: int = Profile.Look.with_part(0, i, idx)
				var want: int = idx if idx < Avatar.VARIANTS[i] else 0
				if Avatar.resolve(v, i) != want:
					wrong.append("часть %d индекс %d" % [i, idx])
		_ok("неизвестный индекс рисуется как 0", wrong.is_empty(), str(wrong.slice(0, 4)))
		# Индексы шлема/аксессуара/ранца ≥ 4 (из будущих сборок) — вариант 0.
		var unk: int = Profile.Look.pack(PackedInt32Array([0, 9, 15, 7]))
		_ok("неизвестные шлем/аксессуар/ранец — раскладка варианта 0",
				Avatar.layout(unk, -1, 1.3, 0.4, 1.0, false, true) == Avatar.layout(0, -1, 1.3, 0.4, 1.0, false, true))
		# Раскладка каждого варианта: обязательные ключи, части разные у вариантов.
		var need: Array = ["body", "torso", "helmet", "visor", "visor_top", "visor_glint", "arm", "glove",
				"backpack", "tank", "leg_back", "leg_front", "boot_back", "boot_front", "light"]
		var lacking: Array = []
		var shapes: Array = [{}, {}, {}, {}]
		for i in range(1, Profile.Look.PARTS):
			for idx in Avatar.VARIANTS[i]:
				var lay: Dictionary = Avatar.layout(Profile.Look.with_part(0, i, idx), 1, 0.0, 0.0, 0.0, false, false)
				for k in need:
					if not lay.has(k):
						lacking.append("часть %d вариант %d: %s" % [i, idx, k])
				shapes[i][str(lay)] = true
		_ok("каждый вариант шлема/аксессуара/ранца даёт полную раскладку", lacking.is_empty(),
				str(lacking.slice(0, 3)))
		_ok("варианты частей различаются формой", shapes[1].size() == Avatar.VARIANTS[1]
				and shapes[2].size() == Avatar.VARIANTS[2] and shapes[3].size() == Avatar.VARIANTS[3],
				"шлемов %d, аксессуаров %d, ранцев %d" % [shapes[1].size(), shapes[2].size(), shapes[3].size()])
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = 87
		var out_of: int = 0
		var colors: Dictionary = {}
		for k in 400:
			var v: int = Avatar.random_look(rng)
			colors[Profile.Look.part(v, Profile.Look.COLOR)] = true
			for i in Profile.Look.PARTS:
				if Profile.Look.part(v, i) >= Avatar.VARIANTS[i]:
					out_of += 1
		_ok("«Случайно» — только из Avatar.VARIANTS", out_of == 0 and colors.size() == Avatar.VARIANTS[0],
				"вне вариантов %d, цветов %d" % [out_of, colors.size()])

	# --- Профиль туда-обратно
	func _check_profile() -> void:
		DirAccess.make_dir_recursive_absolute(TMP_DIR)
		DirAccess.remove_absolute(TestEnv.file(TMP_PROFILE))
		var p1: Profile = Profile.load_or_create(TestEnv.file(TMP_PROFILE))
		_ok("нет файла — профиль создан и записан", FileAccess.file_exists(TestEnv.file(TMP_PROFILE)) and p1.uid != 0
				and p1.nick == Profile.DEFAULT_NICK and p1.look == 0 and p1.port == Profile.DEFAULT_PORT)
		var p2: Profile = Profile.load_or_create(TestEnv.file(TMP_PROFILE))
		_ok("uid создаётся один раз", p2.uid == p1.uid, "%d / %d" % [p1.uid, p2.uid])
		p2.nick = "Аня-2"
		p2.look = Profile.Look.pack(PackedInt32Array([5, 0, 0, 0]))
		p2.recent_ips = PackedStringArray(["192.168.1.20", "10.0.0.5"])
		p2.port = 25000
		_ok("профиль записан", p2.save_to(TestEnv.file(TMP_PROFILE)) == OK)
		var p3: Profile = Profile.load_or_create(TestEnv.file(TMP_PROFILE))
		_ok("профиль туда-обратно: uid, ник, вид, адреса, порт", p3.uid == p1.uid and p3.nick == "Аня-2"
				and p3.look == p2.look and p3.recent_ips == p2.recent_ips and p3.port == 25000,
				"%s look=%d ips=%s port=%d" % [p3.nick, p3.look, str(p3.recent_ips), p3.port])
		var cfg: ConfigFile = ConfigFile.new()
		cfg.load(TestEnv.file(TMP_PROFILE))
		_ok("в файле [profile] uid/nick/look и [net] recent_ips/port",
				cfg.has_section_key("profile", "uid") and cfg.has_section_key("profile", "nick")
				and cfg.has_section_key("profile", "look") and cfg.has_section_key("net", "recent_ips")
				and cfg.has_section_key("net", "port"))
		# Чужой/битый профиль: неверные поля — по умолчанию, uid сохраняется.
		cfg.set_value("profile", "nick", "!!")
		cfg.set_value("profile", "look", "красный")
		cfg.set_value("net", "port", 99999)
		cfg.save(TestEnv.file(TMP_PROFILE))
		var p4: Profile = Profile.load_or_create(TestEnv.file(TMP_PROFILE))
		_ok("битые поля — значения по умолчанию, uid тот же", p4.nick == Profile.DEFAULT_NICK
				and p4.look == 0 and p4.port == Profile.DEFAULT_PORT and p4.uid == p1.uid)
		var f: FileAccess = FileAccess.open(TestEnv.file(TMP_PROFILE), FileAccess.WRITE)
		f.store_string("это не ConfigFile [[[")
		f.close()
		var p5: Profile = Profile.load_or_create(TestEnv.file(TMP_PROFILE))
		_ok("мусор вместо файла — новый профиль", p5.uid != 0 and p5.nick == Profile.DEFAULT_NICK)
		var unk: int = Profile.Look.pack(PackedInt32Array([12, 9, 15, 3]))
		p5.look = unk
		p5.save_to(TestEnv.file(TMP_PROFILE))
		_ok("неизвестные индексы вида хранятся как есть",
				Profile.load_or_create(TestEnv.file(TMP_PROFILE)).look == unk)
		_ok("uid — 64 бита, разные", Profile.new_uid() != Profile.new_uid())
		DirAccess.remove_absolute(TestEnv.file(TMP_PROFILE))

	# --- Меню: сборка, ник, вид, заглушки (узлом-ребёнком, без смены сцены)
	func _check_menu() -> void:
		var net: Node = get_tree().root.get_node("Net")
		var net_profile0: Dictionary = net.local_profile.duplicate()
		DirAccess.remove_absolute(TestEnv.file(TMP_PROFILE))
		var menu = load(MENU_SCENE).instantiate()
		var mm = load(MENU_SCRIPT)
		menu.set("profile_path", TestEnv.file(TMP_PROFILE))
		add_child(menu)
		_menu = menu
		_ok("меню построено: ник, сид, хардкор, 5 кнопок, «Случайно», версия",
				menu.nick_edit != null and menu.seed_edit != null and menu.hardcore_box != null
				and menu.single_button != null and menu.net_buttons.size() == 3
				and menu.random_button != null
				and String(menu.version_label.text).contains(Profile.build_version()))
		_ok("ребёнком меню не ставит паузу и не прячет HUD", not get_tree().paused)
		_ok("ник из профиля, игра доступна", menu.nick_edit.text == Profile.DEFAULT_NICK
				and not menu.single_button.disabled)
		menu.nick_edit.text = "a"
		menu._on_nick_changed("a")
		_ok("невалидный ник: подпись и кнопки игры неактивны", menu.nick_error_label.text != ""
				and menu.single_button.disabled and menu.net_buttons[0].disabled)
		menu.nick_edit.text = " Аня "
		menu._on_nick_changed(" Аня ")
		_ok("валидный ник сохранён в профиль (без краевых пробелов)", not menu.single_button.disabled
				and menu.nick_error_label.text == ""
				and Profile.load_or_create(TestEnv.file(TMP_PROFILE)).nick == "Аня")
		var arrows_on: bool = true
		for b in menu.look_arrows:
			arrows_on = arrows_on and not (b as Button).disabled
		_ok("стрелки всех четырёх частей активны (у каждой ≥ 2 вариантов)",
				arrows_on and menu.look_arrows.size() == Profile.Look.PARTS * 2)
		menu.step_part(Profile.Look.COLOR, 1)
		menu.step_part(Profile.Look.HELMET, 1)
		menu.step_part(Profile.Look.PACK, -1)
		var saved: int = Profile.load_or_create(TestEnv.file(TMP_PROFILE)).look
		_ok("стрелки: цвет 1, шлем 1, ранец по кругу 3, сохранено",
				Profile.Look.part(saved, Profile.Look.COLOR) == 1
				and Profile.Look.part(saved, Profile.Look.HELMET) == 1
				and Profile.Look.part(saved, Profile.Look.PACK) == Avatar.VARIANTS[3] - 1
				and menu.preview.look == saved, "look=%04x" % saved)
		_ok("подпись части — имя варианта и номер", String(menu.look_labels[1].text).begins_with(
				Avatar.variant_name(1, 1)) and String(menu.look_labels[1].text).ends_with("2/4"),
				String(menu.look_labels[1].text))
		menu.step_part(Profile.Look.COLOR, -2)
		_ok("стрелка влево по кругу: цвет 15",
				Profile.Look.part(menu.profile.look, Profile.Look.COLOR) == Avatar.VARIANTS[0] - 1)
		menu.randomize_look()
		var rl: int = menu.profile.look
		var in_range: bool = true
		for i in Profile.Look.PARTS:
			in_range = in_range and Profile.Look.part(rl, i) < Avatar.VARIANTS[i]
		_ok("«Случайно» в пределах вариантов", in_range
				and menu.color_swatch.color == Avatar.suit_color(rl), "look=%04x" % rl)
		_check_net_screens(menu)   # MP-H (#93)
		_ok("профиль меню — в Net.local_profile (uid, ник, вид)",
				int(net.local_profile.get("uid", 0)) == menu.profile.uid
				and String(net.local_profile.get("nick", "")) == "Аня"
				and int(net.local_profile.get("look", -1)) == rl)
		var s0: Dictionary = mm.session_for("", false)
		var s1: Dictionary = mm.session_for(" 4242 ", true)
		var s2: Dictionary = mm.session_for("Кербер", false)
		var s3: Dictionary = mm.session_for("-5", false)
		_ok("Net.session: single; сид пусто — −1, число — как есть, текст — hash(); хардкор",
				s0 == {"mode": "single", "seed": -1, "hardcore": false}
				and s1 == {"mode": "single", "seed": 4242, "hardcore": true}
				and int(s2["seed"]) == hash("Кербер") and int(s3["seed"]) == hash("-5"))
		net.local_profile = net_profile0
		menu.queue_free()
		_menu = null
		DirAccess.remove_absolute(TestEnv.file(TMP_PROFILE))

	# --- Сетевые экраны меню (MP-H, #93): переходы, поля по умолчанию, «Недавние»
	func _check_net_screens(menu) -> void:
		var net: Node = get_tree().root.get_node("Net")
		_ok("экраны построены: создать, найти, по IP, подключение, лобби, загрузка, кампания",
				menu.screens.size() == 8 and menu.screens.has("campaign") and menu.current_screen == "main"
				and not menu.screens["host"].visible and menu.screens["main"].visible)
		menu.net_buttons[0].pressed.emit()
		_ok("«Создать игру» — форма: имя «Экспедиция <ник>», сид пусто, мест 4, порт из профиля",
				menu.current_screen == "host" and menu.host_name_edit.text == "Экспедиция Аня"
				and menu.host_seed_edit.text == "" and menu.host_slots == 4
				and menu.slot_buttons[2].button_pressed and menu.host_port_edit.text == str(menu.profile.port)
				and not menu.screens["main"].visible)
		menu.slot_buttons[0].pressed.emit()
		_ok("мест: кнопка «2»", menu.host_slots == 2 and menu.slot_buttons[0].button_pressed
				and not menu.slot_buttons[2].button_pressed)
		menu.host_port_edit.text = "80"
		menu.create_game()
		_ok("неверный порт — ошибка под формой, сессии нет", menu.host_error_label.text.contains("Порт")
				and not net.is_online() and menu.current_screen == "host", menu.host_error_label.text)
		menu.show_screen("main")
		menu.profile.recent_ips = PackedStringArray(["10.0.0.1", "10.0.0.2:25000", "a", "b", "c", "d", "e"])
		menu.net_buttons[2].pressed.emit()
		_ok("«По IP»: последние 5 адресов кнопками, поле — последний адрес",
				menu.current_screen == "ip" and menu.recent_buttons.size() == 5
				and menu.recent_buttons[1].text == "10.0.0.2:25000" and menu.ip_edit.text == "10.0.0.1")
		menu.ip_edit.text = "300.1.1.1"
		menu.connect_by_ip()
		_ok("«По IP»: неверный адрес — ошибка, подключения нет", menu.ip_error_label.text.contains("IPv4")
				and not net.is_online() and menu.current_screen == "ip", menu.ip_error_label.text)
		menu.show_screen("main")
		menu.profile.recent_ips = PackedStringArray()
		var out: Array = []
		for k in menu.screens:
			menu.show_screen(k)
			for c in menu.find_children("*", "Control", true, false):
				var cc: Control = c
				if cc.is_visible_in_tree() and cc.size.x > menu.size.x + 1.0:
					out.append("%s: %s" % [k, cc.get_class()])
		menu.show_screen("main")
		_ok("сетевые экраны не шире окна %d px" % int(menu.size.x), out.is_empty(), str(out.slice(0, 3)))

	# --- «Загрузить» (#132): список сохранений, серые кнопки, выбор для одиночной и хоста.
	# Файлы — синтетические (заголовок и словарь Save.encode), слоты — тестовые этого
	# процесса (TestEnv): сохранения игрока не видны и не трогаются.
	func _check_saves() -> void:
		print("== Меню: «Загрузить» (#132) ==")
		var save_s: GDScript = load("res://scripts/core/save.gd")
		var mm = load(MENU_SCRIPT)
		var pid: String = "%s%d" % [TestEnv.MARK, OS.get_process_id()]
		_ok("тестовый прогон: слот и профиль — файлы процесса", TestEnv.active()
				and save_s.path_for("1") == "user://save_1%s.sav" % pid
				and Profile.default_path() == "user://profile%s.cfg" % pid and Profile.PATH == "user://profile.cfg",
				"%s, %s" % [save_s.path_for("1"), Profile.default_path()])
		for s in SAVE_SLOTS:
			save_s.remove(s)
		var had: PackedStringArray = save_s.slots()
		DirAccess.remove_absolute(TestEnv.file(TMP_PROFILE))
		var menu = load(MENU_SCENE).instantiate()
		menu.set("profile_path", TestEnv.file(TMP_PROFILE))
		add_child(menu)
		if had.is_empty():
			_ok("сохранений нет — «Загрузить» и «Из сохранения…» серые", menu.load_button.disabled
					and menu.host_load_button.disabled and menu.load_button.tooltip_text == "Сохранений нет")
		else:
			print("  ПРОПУСК «нет сохранений»: у процесса уже есть слоты %s" % str(had))
		# Одиночное (сид 4242, смена 3), сетевое (двое, сид 777, смена 5), мусор.
		_write_save(save_s, SAVE_SLOTS[0], {"version": save_s.VERSION, "seed": 4242, "game": {"day_number": 3},
				"world": {}, "player": {}})
		_write_save(save_s, SAVE_SLOTS[1], {"version": save_s.VERSION, "seed": 777, "game": {"day_number": 5},
				"session": {"name": "Экспедиция Аня", "max": 4},
				"players": {101: {"nick": "Аня"}, 102: {"nick": "Борис"}}, "player": {}})
		var f: FileAccess = FileAccess.open(save_s.path_for(SAVE_SLOTS[2]), FileAccess.WRITE)
		f.store_string("не сохранение")
		f.close()
		var mine: PackedStringArray = save_s.slots()
		var mine_ok: bool = true
		for s in SAVE_SLOTS:
			mine_ok = mine_ok and mine.has(s)
		TestEnv._active = 0          # как у игрока: тестовых файлов не видно
		var player_view: PackedStringArray = save_s.slots()
		TestEnv._active = 1
		var leaked: bool = false
		for s in player_view:
			leaked = leaked or String(s).contains(TestEnv.MARK) or SAVE_SLOTS.has(s)
		_ok("слоты: тестовые видны только своему процессу, у игрока их нет", mine_ok and not leaked,
				"свои %s, у игрока %d" % [str(mine), player_view.size()])
		var t0: int = Time.get_ticks_usec()
		menu._refresh_load_buttons()
		var t1: int = Time.get_ticks_usec()
		save_s.list_saves()
		print("  ЗАМЕР: серая ли «Загрузить» (Save.slots, без чтения) — %.2f мс; список из %d файлов — %.2f мс"
				% [float(t1 - t0) / 1000.0, mine.size(), float(Time.get_ticks_usec() - t1) / 1000.0])
		_ok("есть сохранения — «Загрузить» активна", not menu.load_button.disabled)
		menu.load_button.pressed.emit()
		var rows: Array = []
		for k in menu.save_buttons.size():
			if SAVE_SLOTS.has(String(menu.saves[k]["slot"])):
				rows.append(k)
		var by_slot: Dictionary = {}
		for k in rows:
			by_slot[String(menu.saves[k]["slot"])] = k
		_ok("экран «Загрузить»: строка на каждое сохранение", menu.current_screen == "load"
				and rows.size() == 3 and menu.save_buttons.size() == menu.saves.size()
				and menu.load_title.text == "Загрузить" and menu.load_go_button.text == "Загрузить")
		var t_single: String = menu.save_buttons[by_slot.get(SAVE_SLOTS[0], 0)].text
		var t_net: String = menu.save_buttons[by_slot.get(SAVE_SLOTS[1], 0)].text
		var b_bad: Button = menu.save_buttons[by_slot.get(SAVE_SLOTS[2], 0)]
		_ok("строка одиночного: дата, сид, смена, игроки", t_single.begins_with("Одиночная · ")
				and t_single.contains("сид 4242 · смена 3 · игрок 1") and t_single.contains("\n"),
				t_single.replace("\n", " | "))
		_ok("строка сетевого: имя игры, сид, смена, ники", t_net.begins_with("Сетевая «Экспедиция Аня» · ")
				and t_net.contains("сид 777 · смена 5 · игроков 2: Аня, Борис"), t_net.replace("\n", " | "))
		_ok("битый файл — серая строка с причиной", b_bad.disabled and b_bad.text.contains("не читается"),
				b_bad.text.replace("\n", " | "))
		var ts: String = mm.format_time(int(menu.saves[by_slot.get(SAVE_SLOTS[0], 0)]["time"]))
		_ok("дата файла — дд.мм.гггг чч:мм, сегодня", ts.length() == 16 and ts.substr(6, 4)
				== str(Time.get_datetime_dict_from_system()["year"]) and mm.format_time(0) == "дата неизвестна", ts)
		_ok("выбрана первая читаемая строка, «Загрузить» активна", menu.selected_save >= 0
				and bool(menu.saves[menu.selected_save]["ok"]) and not menu.load_go_button.disabled
				and menu.save_buttons[menu.selected_save].button_pressed)
		var k_net: int = by_slot.get(SAVE_SLOTS[1], 0)
		menu.save_buttons[k_net].pressed.emit()
		b_bad.pressed.emit()
		_ok("тап по строке — выбор (битая не выбирается)", menu.selected_save == k_net
				and menu.save_buttons[k_net].button_pressed)
		var ses: Dictionary = mm.load_session(menu.saves[by_slot.get(SAVE_SLOTS[0], 0)])
		_ok("одиночная из сохранения: сид файла, без хардкора, слот в Net.session[load]",
				ses == {"mode": "single", "seed": 4242, "hardcore": false, "load": SAVE_SLOTS[0]}, str(ses))
		for b in menu.screens["load"].find_children("*", "Button", true, false):
			if (b as Button).text == "Назад":
				(b as Button).pressed.emit()
		_ok("«Назад» — главный экран", menu.current_screen == "main")
		# «Создать игру» из сохранения.
		menu.net_buttons[0].pressed.emit()
		_ok("«Создать игру»: мир новый, «Из сохранения…» активна", menu.current_screen == "host"
				and menu.host_load_label.text == "новый" and not menu.host_load_button.disabled
				and menu.host_load_slot == "")
		menu.host_load_button.pressed.emit()
		_ok("«Из сохранения…» — тот же список, кнопка «Выбрать»", menu.current_screen == "load"
				and menu.load_for == "host" and menu.load_go_button.text == "Выбрать"
				and menu.load_title.text == "Сохранение для сетевой игры")
		k_net = -1
		for k in menu.saves.size():
			if String(menu.saves[k]["slot"]) == SAVE_SLOTS[1]:
				k_net = k
		menu.save_buttons[k_net].pressed.emit()
		menu.load_go_button.pressed.emit()
		var form: Dictionary = mm.host_form(menu.host_name_edit.text, menu.host_seed_edit.text, menu.host_slots,
				menu.host_port_edit.text)
		_ok("«Выбрать» — форма хоста: слот, сид из файла (поле закрыто), «Новый мир»",
				menu.current_screen == "host" and menu.host_load_slot == SAVE_SLOTS[1]
				and menu.host_seed_edit.text == "777" and not menu.host_seed_edit.editable
				and menu.host_load_button.text == "Новый мир" and menu.host_load_label.text.contains("Экспедиция Аня")
				and bool(form["ok"]) and int(form["seed"]) == 777, menu.host_load_label.text)
		menu.host_load_button.pressed.emit()
		_ok("«Новый мир» — без сохранения, сид снова свободный", menu.host_load_slot == ""
				and menu.host_seed_edit.text == "" and menu.host_seed_edit.editable
				and menu.host_load_button.text == "Из сохранения…")
		menu.show_screen("main")
		for s in SAVE_SLOTS:
			save_s.remove(s)
		_ok("тест убрал за собой свои слоты", not save_s.exists(SAVE_SLOTS[0]) and not save_s.exists(SAVE_SLOTS[1])
				and not save_s.exists(SAVE_SLOTS[2]))
		menu._refresh_load_buttons()
		if had.is_empty():
			_ok("файлы убраны — «Загрузить» снова серая", menu.load_button.disabled)
		# Хвосты упавших прогонов (процесса уже нет) убирает TestEnv.sweep(), свои — не трогает.
		var dead: String = "user://save_menu_dead%s999999999.sav" % TestEnv.MARK
		_write_save(save_s, SAVE_SLOTS[0], {"version": save_s.VERSION, "seed": 1})
		var fd: FileAccess = FileAccess.open(dead, FileAccess.WRITE)
		fd.store_string("x")
		fd.close()
		var swept: int = TestEnv.sweep()
		_ok("TestEnv.sweep: файл мёртвого процесса убран, свой остался", not FileAccess.file_exists(dead)
				and save_s.exists(SAVE_SLOTS[0]) and swept >= 1, "убрано %d" % swept)
		save_s.remove(SAVE_SLOTS[0])
		DirAccess.remove_absolute(dead)
		menu.queue_free()
		DirAccess.remove_absolute(TestEnv.file(TMP_PROFILE))

	func _write_save(save_s: GDScript, slot: String, d: Dictionary) -> void:
		var f: FileAccess = FileAccess.open(save_s.path_for(slot), FileAccess.WRITE)
		f.store_buffer(save_s.encode(d))
		f.close()

	# --- Формы: адрес «По IP», «Создать игру», «Недавние», кадр LOBBY
	func _check_net_forms() -> void:
		print("== Сеть: адрес, форма хоста, поиск (MP-H) ==")
		var mm = load(MENU_SCRIPT)
		var addr_ok: Array = [
			["192.168.1.20", "192.168.1.20", NetScript.GAME_PORT],
			[" 10.0.0.5:25000 ", "10.0.0.5", 25000],
			["127.0.0.1:1", "127.0.0.1", 1],
			["255.255.255.255:65535", "255.255.255.255", 65535],
			["Kerber-PC", "kerber-pc", NetScript.GAME_PORT],
			["localhost:24650", "localhost", 24650],
			["pc.local", "pc.local", NetScript.GAME_PORT],
		]
		var bad: Array = []
		for row in addr_ok:
			var r: Dictionary = mm.parse_address(row[0])
			if not bool(r["ok"]) or r["host"] != row[1] or int(r["port"]) != int(row[2]):
				bad.append("%s → %s" % [row[0], str(r)])
		_ok("адрес: IPv4[:порт] и имя хоста приняты (%d)" % addr_ok.size(), bad.is_empty(), str(bad))
		var addr_bad: Array = ["", "  ", "256.1.1.1", "1.2.3", "1.2.3.4.5", "01.2.3.4", "1.2.3.4:0",
				"1.2.3.4:65536", "1.2.3.4:", "1.2.3.4:abc", "1.2.3.4:-5", ":24642", "::1", "[::1]:24642",
				"-pc", "pc-", "пк.дом", "a b", "a..b", "1.2.3.4:+80"]
		var passed: Array = []
		var no_reason: Array = []
		for a in addr_bad:
			var r: Dictionary = mm.parse_address(a)
			if bool(r["ok"]):
				passed.append(a)
			elif String(r["error"]) == "":
				no_reason.append(a)
		_ok("адрес: неверные отклонены с причиной (%d)" % addr_bad.size(), passed.is_empty()
				and no_reason.is_empty(), "прошли %s, без причины %s" % [str(passed), str(no_reason)])
		# Форма хоста.
		var f0: Dictionary = mm.host_form("Экспедиция Аня", "", 4, "")
		var f1: Dictionary = mm.host_form("  Тест  ", "4242", 2, "25000")
		var f2: Dictionary = mm.host_form("Тест", "Кербер", 3, "24642")
		_ok("форма хоста: по умолчанию — порт 24642, сид случайный (−1)", bool(f0["ok"])
				and int(f0["port"]) == NetScript.GAME_PORT and int(f0["seed"]) == -1 and int(f0["slots"]) == 4)
		_ok("форма хоста: имя без краевых пробелов, сид числом, порт", bool(f1["ok"]) and f1["name"] == "Тест"
				and int(f1["seed"]) == 4242 and int(f1["port"]) == 25000 and int(f1["slots"]) == 2)
		_ok("форма хоста: сид-текст — hash() ≥ 0 (клиентам нужен --seed= ≥ 0)", bool(f2["ok"])
				and int(f2["seed"]) == (hash("Кербер") if hash("Кербер") >= 0 else hash("Кербер") & 0x7FFFFFFF)
				and int(f2["seed"]) >= 0)
		var form_bad: Array = [["", "", 4, ""], ["   ", "", 4, ""], ["x".repeat(25), "", 4, ""],
				["Тест", "", 1, ""], ["Тест", "", 5, ""], ["Тест", "", 4, "abc"], ["Тест", "", 4, "80"],
				["Тест", "", 4, "70000"], ["Тест", "", 4, str(NetScript.DISCOVERY_PORT)], ["a\tb", "", 4, ""]]
		var fb: Array = []
		for row in form_bad:
			var r: Dictionary = mm.host_form(row[0], row[1], row[2], row[3])
			if bool(r["ok"]) or String(r["error"]) == "":
				fb.append(str(row))
		_ok("форма хоста: имя 1–24, мест 2–4, порт 1024–65535 и не %d — отказ с причиной (%d)"
				% [NetScript.DISCOVERY_PORT, form_bad.size()], fb.is_empty(), str(fb))
		_ok("длина имени — ровно 24 можно", bool(mm.host_form("x".repeat(24), "", 4, "")["ok"]))
		# «Недавние» в профиле.
		var p: Profile = Profile.new()
		for a in ["1.1.1.1", "2.2.2.2", "1.1.1.1", "3.3.3.3:25000"]:
			p.remember_ip(a)
		_ok("«Недавние»: новые сверху, без повторов", p.recent_ips == PackedStringArray(["3.3.3.3:25000",
				"1.1.1.1", "2.2.2.2"]), str(p.recent_ips))
		for k in 20:
			p.remember_ip("10.0.0.%d" % k)
		_ok("«Недавние»: не больше %d" % Profile.RECENT_IPS_MAX, p.recent_ips.size() == Profile.RECENT_IPS_MAX
				and p.recent_ips[0] == "10.0.0.19")
		# Кадр LOBBY.
		var st: Dictionary = NetCodec.decode_lobby(NetCodec.encode_lobby_state(true, [2, 7, 0xFFFFFFFF]))
		var rd: Dictionary = NetCodec.decode_lobby(NetCodec.encode_lobby_ready(true))
		_ok("кадр LOBBY: состояние и «Готов» туда-обратно", st.get("started") == true
				and st.get("ready") == [2, 7, 0xFFFFFFFF] and rd.get("on") == true
				and int(rd.get("kind", -1)) == NetCodec.LOBBY_READY)
		_ok("кадр LOBBY: битый — {}", NetCodec.decode_lobby(PackedByteArray([0, 1, 2, 0])).is_empty()
				and NetCodec.decode_lobby(PackedByteArray([9, 1])).is_empty()
				and NetCodec.decode_lobby(PackedByteArray()).is_empty())

	# --- Поиск: формат, совместимость, адреса, запрос/ответ на 127.0.0.1
	func _check_discovery() -> void:
		var q: PackedByteArray = LanDiscovery.encode_query(NetScript.PROTO)
		_ok("запрос GCQ1 + proto u16 — 6 Б", q.size() == 6 and LanDiscovery.decode_query(q) == NetScript.PROTO
				and q.slice(0, 4).get_string_from_ascii() == "GCQ1")
		_ok("не запрос — −1", LanDiscovery.decode_query("GCQ2xx".to_ascii_buffer()) == -1
				and LanDiscovery.decode_query(PackedByteArray([1, 2, 3])) == -1)
		var full: Dictionary = {"proto": NetScript.PROTO, "build": "dev", "name": "Экспедиция Аня",
				"host": "Аня", "n": 2, "max": 4, "port": 24642, "day": 3, "st": "game", "pw": false}
		var ans: PackedByteArray = LanDiscovery.encode_answer(full)
		var back: Dictionary = LanDiscovery.decode_answer(ans)
		var same: bool = not back.is_empty()
		for k in full:
			same = same and back.get(k) == full[k]
		print("  ЗАМЕР: запрос %d Б, ответ %d Б (имя «%s», ник «%s»)" % [q.size(), ans.size(), full["name"],
				full["host"]])
		_ok("ответ GCA1 + JSON туда-обратно, ≤ 200 Б", same and int(back["v"]) == LanDiscovery.ANSWER_V
				and ans.size() <= 200, "%d Б %s" % [ans.size(), str(back)])
		var junk: Array = [PackedByteArray(), "GCA1".to_ascii_buffer(), "GCA1{".to_utf8_buffer(),
				"GCA1[1,2]".to_utf8_buffer(), "GCQ1{}".to_utf8_buffer(),
				("GCA1" + JSON.stringify({"v": 1})).to_utf8_buffer(),
				("GCA1" + JSON.stringify(full).replace("24642", "70000")).to_utf8_buffer(),
				("GCA1" + JSON.stringify(full).replace("\"dev\"", "5")).to_utf8_buffer()]
		var took: int = 0
		for j in junk:
			if not LanDiscovery.decode_answer(j).is_empty():
				took += 1
		_ok("битый ответ — {} (%d случаев)" % junk.size(), took == 0, "принято %d" % took)
		var me: Array = [NetScript.PROTO, "0.5.0"]
		var cases: Array = [
			[{"proto": NetScript.PROTO, "build": "0.5.0", "n": 1, "max": 4}, ""],
			[{"proto": NetScript.PROTO + 1, "build": "0.5.0", "n": 1, "max": 4}, "другой протокол"],
			[{"proto": NetScript.PROTO, "build": "0.4.2", "n": 1, "max": 4}, "другая версия: у хоста 0.4.2, у вас 0.5.0"],
			[{"proto": NetScript.PROTO, "build": "0.5.0", "n": 4, "max": 4}, NetScript.R_FULL],
			[{"proto": NetScript.PROTO, "build": "0.5.0", "n": 1, "max": 4, "pw": true}, "парол"],
		]
		var wrong: Array = []
		for c in cases:
			var r: String = LanDiscovery.incompat_reason(c[0], me[0], me[1])
			if (c[1] == "" and r != "") or (c[1] != "" and not r.contains(c[1])):
				wrong.append("%s → «%s»" % [str(c[0]), r])
		_ok("совместимость: протокол, сборка, места, пароль — причина словами", wrong.is_empty(), str(wrong))
		_ok("две сборки dev совместимы", LanDiscovery.incompat_reason({"proto": NetScript.PROTO,
				"build": "dev", "n": 1, "max": 2}, NetScript.PROTO, "dev") == "")
		var v4_ok: bool = LanDiscovery.is_ipv4("0.0.0.0") and LanDiscovery.is_ipv4("192.168.1.255") \
				and not LanDiscovery.is_ipv4("192.168.1") and not LanDiscovery.is_ipv4("192.168.01.1") \
				and not LanDiscovery.is_ipv4("1.2.3.256") and not LanDiscovery.is_ipv4("a.b.c.d")
		_ok("строгий IPv4", v4_ok)
		_ok("частные диапазоны 10/8, 172.16/12, 192.168/16", LanDiscovery.is_private("10.1.2.3")
				and LanDiscovery.is_private("172.16.0.1") and LanDiscovery.is_private("172.31.255.1")
				and not LanDiscovery.is_private("172.32.0.1") and LanDiscovery.is_private("192.168.0.7")
				and not LanDiscovery.is_private("8.8.8.8") and not LanDiscovery.is_private("127.0.0.1"))
		var bt: PackedStringArray = LanDiscovery.broadcast_targets()
		var bt_ok: bool = bt.size() >= 1 and bt[0] == "255.255.255.255"
		for t in bt:
			bt_ok = bt_ok and LanDiscovery.is_ipv4(t) and t.ends_with(".255") and not t.begins_with("127.")
		_ok("цели broadcast: 255.255.255.255 и x.y.z.255 своих IPv4", bt_ok, str(bt))
		# Запрос/ответ на петле (без окна брандмауэра): хост-ответчик и поиск в одном процессе.
		var host_d: LanDiscovery = LanDiscovery.new()
		var cli_d: LanDiscovery = LanDiscovery.new()
		add_child(host_d)
		add_child(cli_d)
		var port: int = 0
		var base: int = 26100 + OS.get_process_id() % 400
		for k in 10:
			if host_d.start_host(base + k, "127.0.0.1", func() -> Dictionary: return full) == OK:
				port = base + k
				break
		_ok("ответчик поиска на 127.0.0.1", port > 0, str(port))
		if port == 0:
			host_d.queue_free()
			cli_d.queue_free()
			return
		var t0: int = Time.get_ticks_usec()
		var err: Error = cli_d.start_search(port, "127.0.0.1", PackedStringArray(["127.0.0.1"]))
		var guard: int = 0
		while cli_d.hosts.is_empty() and guard < 500:
			host_d._poll()
			cli_d._poll()
			OS.delay_usec(500)
			guard += 1
		var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
		var key: String = "127.0.0.1:24642"
		var e: Dictionary = cli_d.hosts.get(key, {})
		_ok("поиск на петле: игра в списке, поля и причина пустая", err == OK and not e.is_empty()
				and e.get("name") == "Экспедиция Аня" and int(e.get("n", 0)) == 2 and String(e.get("reason", "?")) == ""
				and cli_d.queries_sent == 1 and host_d.answers_sent >= 1,
				"%.2f мс, запросов %d, ответов %d" % [ms, cli_d.queries_sent, host_d.answers_sent])
		print("  ЗАМЕР: круг запрос → ответ на 127.0.0.1 — %.2f мс" % ms)
		cli_d.my_build = "0.0.1-другая"
		cli_d.refresh()
		guard = 0
		while cli_d.hosts.is_empty() and guard < 500:
			host_d._poll()
			cli_d._poll()
			OS.delay_usec(500)
			guard += 1
		var row: String = ServerBrowser.row_text(cli_d.hosts.get(key, {}))
		_ok("«Обновить» — список заново; другая сборка — с причиной", String(cli_d.hosts.get(key, {}).get("reason",
				"")).begins_with("другая версия") and row.contains("версия dev") and row.contains("протокол %d"
				% NetScript.PROTO) and row.contains("2/4") and row.contains("смена 3"), row.replace("\n", " | "))
		host_d.stop()
		cli_d.stop()
		host_d.queue_free()
		cli_d.queue_free()

	# --- Замер: Player._draw до V4 против скафандра
	func _bench_start() -> void:
		var s: GDScript = GDScript.new()
		s.source_code = BENCH_PLAYER_SRC
		s.reload()
		for old in [true, false]:
			var bp = s.new()
			bp.reps = BENCH_REPS
			bp.old = old
			add_child(bp)
			_bench_nodes.append(bp)

	func _bench_report() -> void:
		var names: Array = ["Player._draw до V4 (прежний красный герой)", "Player._draw после (скафандр «Кербер-9»)"]
		var line: String = ""
		var five: String = ""
		for k in _bench_nodes.size():
			var n = _bench_nodes[k]
			var avg: float = float(n.usec) / maxf(1.0, float(n.calls))
			line += "%s: лучший кадр %.2f, среднее %.2f; " % [names[k], float(n.best), avg]
			five += "%s %.1f; " % ["до" if k == 0 else "после", avg * 5.0]
		print("  ЗАМЕР (мкс на одного героя, %d кадров × %d рисунков): %s"
				% [BENCH_FRAMES, BENCH_REPS, line])
		print("  ЗАМЕР 4 героя + двойник, мкс/кадр (×5 среднего): %s" % five)
		_ok("замер шёл (рисунки были)", int(_bench_nodes[0].calls) > 0 and int(_bench_nodes[1].calls) > 0)
		for n in _bench_nodes:
			n.queue_free()
		_bench_nodes.clear()


# ------------------------------------------------------------- отдельный запуск

var _runner: Runner = null
var _step: int = 0
var _menu = null
var _frames: int = 0
var _shot_path: String = ""
var _checks: int = 0
var _fails: int = 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--menu-shot="):
			_shot_path = a.substr(12)
		elif a.begins_with("--sheets="):
			_sheets_dir = a.substr(9)


func _process(_delta: float) -> bool:
	if _shot_path != "":
		return _shot_step()
	match _step:
		0:
			_runner = Runner.new(null, true)
			root.add_child(_runner)
			_runner.start(null)
			_step = 1
		1:
			if _runner.done:
				_checks += _runner.checks
				_fails += _runner.fails
				_runner.queue_free()
				_step = 2
		2:
			_start_single()
			_frames = 0
			_step = 3
		3:
			# Пара кадров на вёрстку контейнеров — и дальше всё тапами.
			_frames += 1
			if _frames >= 3:
				_tap_menu()
				_frames = 0
				_step = 6
		6:
			_frames += 1          # экран поиска свёрстан — второй заход тапов (MP-H)
			if _frames >= 3:
				_tap_menu2()
				_frames = 0
				_step = 5
		5:
			_frames += 1
			var sc: Node = current_scene
			if sc != null and sc != _menu and sc.get("player") != null:
				_check_single(sc)
				_step = 7
			elif _frames > 600:
				_ok("мир из меню запустился", false, "нет сцены игры за 600 кадров")
				_step = 4
		# --- «Загрузить» (#132): сохранили → в меню видно → загрузили → мир тот же.
		7:
			_save_run(current_scene)
			_open_menu()
			_frames = 0
			_step = 8
		8:
			_frames += 1
			if _frames >= 3:
				_tap_load()
				_frames = 0
				_step = 9
		9:
			_frames += 1
			if not is_instance_valid(_menu):
				_ok("список сохранений открыт", false, "меню закрылось раньше «Загрузить»")
				_step = 4
			elif _frames >= 3:
				_tap_load_row()
				_frames = 0
				_step = 18
		18:
			_frames += 1
			if _frames >= 3:
				_tap(_menu.load_go_button)
				_frames = 0
				_step = 10
		10, 17:
			_frames += 1
			var sc: Node = current_scene
			if sc != null and sc != _menu and sc.get("player") != null and _frames >= 3:
				_check_loaded(sc, _step == 17)
				_step = 11 if _step == 10 else 4
			elif _frames > 600:
				_ok("мир из сохранения запустился", false, "нет сцены игры за 600 кадров")
				_step = 4
		11:
			_open_menu()
			_frames = 0
			_step = 12
		12, 13, 14, 15, 16:
			_frames += 1
			if _frames >= 3:
				_tap_host(_step)
				_frames = 0
				_step += 1
		4:
			var net: Node = root.get_node("Net")
			if net.is_online():
				net.leave()
			net.session = {}
			load("res://scripts/core/save.gd").remove("1")
			DirAccess.remove_absolute(TestEnv.file(TMP_PROFILE))
			DirAccess.remove_absolute(Profile.default_path())
			print("")
			print("ИТОГ: проверок %d, провалов %d" % [_checks, _fails])
			quit(1 if _fails > 0 else 0)
			return true
	return false


func _ok(label: String, cond: bool, extra: String = "") -> void:
	_checks += 1
	if cond:
		print("  OK   %s %s" % [label, extra])
	else:
		_fails += 1
		print("  FAIL %s %s" % [label, extra])


## «Одиночная игра»: меню — текущая сцена, как при запуске без аргументов.
func _start_single() -> void:
	print("== Одиночная игра из меню ==")
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	DirAccess.remove_absolute(TestEnv.file(TMP_PROFILE))
	var p: Profile = Profile.load_or_create(TestEnv.file(TMP_PROFILE))
	p.look = Profile.Look.pack(PackedInt32Array([5, 0, 0, 0]))
	p.save_to(TestEnv.file(TMP_PROFILE))
	root.get_node("Net").session = {}
	_menu = load(MENU_SCENE).instantiate()
	_menu.set("profile_path", TestEnv.file(TMP_PROFILE))
	root.add_child(_menu)
	current_scene = _menu
	var ui: CanvasLayer = root.get_node("UI")
	_ok("меню-сцена: дерево на паузе, HUD скрыт", paused and not ui.visible)
	_ok("превью в цвете профиля", _menu.preview.look == p.look)



## Тапы (InputEventScreenTouch; мышь эмулируется из касаний, как на телефоне):
## цвет ▶ (5 → 6), «Найти игру» — «Скоро», галочка хардкора, «Одиночная игра».
func _tap_menu() -> void:
	var out: Array = []
	var screen: Rect2 = Rect2(Vector2.ZERO, _menu.size).grow(1.0)
	for c in _menu.find_children("*", "Control", true, false):
		if (c as Control).is_visible_in_tree() and not screen.encloses((c as Control).get_global_rect()):
			out.append("%s %s" % [c.get_class(), str((c as Control).get_global_rect())])
	_ok("меню целиком помещается в %dx%d" % [int(_menu.size.x), int(_menu.size.y)], out.is_empty(),
			str(out.slice(0, 3)))
	print("  (тапы по меню)")
	_tap(_menu.look_arrows[1])
	_ok("тап по ▶ цвета: цвет 6", Profile.Look.part(_menu.profile.look, Profile.Look.COLOR) == 6
			and _menu.preview.look == _menu.profile.look, "look=%d" % _menu.profile.look)
	_menu.net_bind = "127.0.0.1"           # MP-H: поиск только на петле — без окна брандмауэра
	_menu.discovery_targets = PackedStringArray(["127.0.0.1:9"])
	_tap(_menu.net_buttons[1])
	_ok("тап по «Найти игру» — экран поиска, поиск идёт", _menu.current_screen == "browser"
			and _menu.browser.discovery.is_running())


## Второй заход тапов (экран поиска уже свёрстан): «Назад», хардкор, «Одиночная игра».
func _tap_menu2() -> void:
	_tap(_button_in(_menu.screens["browser"], "Назад"))
	_ok("тап по «Назад» — главный экран, поиск остановлен", _menu.current_screen == "main"
			and not _menu.browser.discovery.is_running())
	_tap(_menu.hardcore_box)
	_ok("тап по «Хардкор»: включён", _menu.hardcore_box.button_pressed
			and String(_menu.hardcore_box.text).ends_with("да"))
	_menu.seed_edit.text = "4242"
	_tap(_menu.single_button)


## Кнопка с таким текстом внутри узла (первая).
func _button_in(node: Node, text: String) -> Button:
	for b in node.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			return b
	return null


func _tap(ctrl: Control) -> void:
	var p: Vector2 = ctrl.get_viewport().get_final_transform() \
			* (ctrl.get_global_transform_with_canvas() * (ctrl.size * 0.5))
	var down: InputEventScreenTouch = InputEventScreenTouch.new()
	down.index = 0
	down.position = p
	down.pressed = true
	Input.parse_input_event(down)
	var up: InputEventScreenTouch = down.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()


func _check_single(sc: Node) -> void:
	var pl = sc.get("player")
	var lv: Variant = pl.get("look")
	var look: int = int(lv) if lv is int else -1
	_ok("мир запущен с сидом из меню", int(sc.get("seed_value")) == 4242, str(sc.get("seed_value")))
	_ok("хардкор галочкой", sc.get("hardcore") == true)
	_ok("герой в цвете из профиля", Avatar.resolve(look, Profile.Look.COLOR) == 6
			and Avatar.suit_color(look) == Avatar.SUIT_COLORS[6], "look=%d" % look)
	_ok("после меню пауза снята, HUD виден", not paused and (root.get_node("UI") as CanvasLayer).visible)


# ------------------------------------------------------------- «Загрузить» (#132)
## Мир из меню меняется (смена 3, метка в инвентаре, выкопанный столбик у героя) и
## сохраняется в слот F5 — «1» (в тестовом прогоне — файл процесса, TestEnv). Дальше —
## меню, тап «Загрузить» → строка → «Загрузить»: мир тот же; затем «Создать игру» →
## «Из сохранения…» → «Выбрать» → «Создать» → «Старт»: хост грузит тот же слот.

## Что сверяем после загрузки: {seed, tiles, day, mark}.
var _saved: Dictionary = {}
## Метка в инвентаре: id и сколько.
var _mark_id: int = 0
const MARK_N: int = 11


func _save_run(sc: Node) -> void:
	print("== «Загрузить» из меню (#132) ==")
	var save_s: GDScript = load("res://scripts/core/save.gd")
	var ids: GDScript = load("res://scripts/core/ids.gd")
	var world: Node = root.get_node("World")
	var game: Node = root.get_node("Game")
	var pl = sc.get("player")
	_mark_id = int(ids.I.SCRAP)
	game.day_number = 3
	pl.inv.add(_mark_id, MARK_N)
	var c: Vector2i = world.world_to_cell(pl.global_position)
	for dy in 3:
		world.set_tile_raw(c.x + 4, c.y + 2 + dy, int(ids.T.AIR))
	save_s.remove("1")
	var ok: bool = save_s.save_game("1")
	_ok("F5-слот «1» записан — файл процесса", ok and save_s.exists("1")
			and save_s.path_for("1").contains(TestEnv.MARK), "%s %s" % [save_s.path_for("1"), save_s.last_error])
	_saved = {"seed": int(world.world_seed), "tiles": (world.tiles as PackedByteArray).duplicate(), "day": 3,
			"mark": int(pl.inv.count_of(_mark_id))}


## Меню — снова текущая сцена (как после выхода из игры): сцена игры уходит.
func _open_menu() -> void:
	var old: Node = current_scene
	root.get_node("Net").session = {}
	_menu = load(MENU_SCENE).instantiate()
	_menu.set("profile_path", TestEnv.file(TMP_PROFILE))
	root.add_child(_menu)
	current_scene = _menu
	if old != null and old != _menu:
		old.queue_free()


func _tap_load() -> void:
	_ok("сохранение есть — «Загрузить» активна", not _menu.load_button.disabled)
	# #119: «Продолжить» — последний одиночный забег, кнопка одна, меню по-прежнему влезает.
	var out: Array = []
	var screen: Rect2 = Rect2(Vector2.ZERO, _menu.size).grow(1.0)
	for c in _menu.find_children("*", "Control", true, false):
		if (c as Control).is_visible_in_tree() and not screen.encloses((c as Control).get_global_rect()):
			out.append("%s %s" % [c.get_class(), str((c as Control).get_global_rect())])
	var n_cont: int = 0
	for b in _menu.find_children("*", "Button", true, false):
		if (b as Button).is_visible_in_tree() and String((b as Button).text).begins_with("Продолжить"):
			n_cont += 1
	_ok("«Продолжить» — этот забег (смена 3), одна кнопка, фокус на ней", _menu.continue_button.visible
			and not _menu.continue_button.disabled and _menu.continue_button.text == "Продолжить · смена 3"
			and String(_menu.continue_info.get("slot", "")) == "1" and n_cont == 1
			and _menu.get_viewport().gui_get_focus_owner() == _menu.continue_button, _menu.continue_button.text)
	var page_h: float = (_menu.main_page as Control).get_combined_minimum_size().y
	_ok("с «Продолжить» меню помещается в %dx%d и по высоте в 720" % [int(_menu.size.x), int(_menu.size.y)],
			out.is_empty() and page_h <= 720.0, "страница %.0f px %s" % [page_h, str(out.slice(0, 3))])
	var t0: int = Time.get_ticks_usec()
	_tap(_menu.load_button)
	print("  ЗАМЕР: тап «Загрузить» → список (настоящий файл %.1f КБ) — %.2f мс" % [
			float(FileAccess.get_file_as_bytes(load("res://scripts/core/save.gd").path_for("1")).size()) / 1024.0,
			float(Time.get_ticks_usec() - t0) / 1000.0])


## Экран «load» свёрстан: строка сохранения и тап по ней.
func _tap_load_row() -> void:
	var row: String = _menu.save_buttons[0].text if not _menu.save_buttons.is_empty() else ""
	_ok("тап «Загрузить» — список, строка сохранения: сид 4242, смена 3", _menu.current_screen == "load"
			and _menu.saves.size() == 1 and row.contains("сид 4242 · смена 3"), row.replace("\n", " | "))
	_tap(_menu.save_buttons[0])
	_ok("тап по строке — выбрана", _menu.selected_save == 0 and _menu.save_buttons[0].button_pressed)


## Мир после загрузки — тот же, что в момент сохранения.
func _check_loaded(sc: Node, host: bool) -> void:
	var world: Node = root.get_node("World")
	var game: Node = root.get_node("Game")
	var net: Node = root.get_node("Net")
	var pl = sc.get("player")
	var tiles: PackedByteArray = world.tiles
	var diff: int = 0
	if tiles.size() == (_saved["tiles"] as PackedByteArray).size():
		for i in tiles.size():
			if tiles[i] != _saved["tiles"][i]:
				diff += 1
	else:
		diff = -1
	var who: String = "хост" if host else "одиночная"
	_ok("%s: мир того же сида, клетки совпали" % who, int(world.world_seed) == int(_saved["seed"]) and diff == 0,
			"сид %d, разных клеток %d" % [int(world.world_seed), diff])
	_ok("%s: смена и инвентарь из сохранения" % who, int(game.day_number) == int(_saved["day"])
			and int(pl.inv.count_of(_mark_id)) == int(_saved["mark"]),
			"смена %d, метка %d" % [int(game.day_number), int(pl.inv.count_of(_mark_id))])
	if host:
		_ok("хост: сетевая игра, слот из меню в Net.session[load]", net.is_host()
				and String(net.session.get("load", "")) == "1")
	else:
		_ok("одиночная: без хардкора, ключ load снят (перезапуск — новый забег)", sc.get("hardcore") == false
				and not net.session.has("load") and String(net.session.get("mode", "")) == "single")


## «Создать игру» тапами: 12 — форма, 13 — «Из сохранения…», 14 — «Выбрать»,
## 15 — «Создать» (лобби), 16 — «Старт».
func _tap_host(step: int) -> void:
	var net: Node = root.get_node("Net")
	match step:
		12:
			var port: int = 27300 + OS.get_process_id() % 200 * 2
			_menu.net_bind = "127.0.0.1"   # петля — без окна брандмауэра
			_menu.discovery_port = port + 1
			_menu.discovery_targets = PackedStringArray(["127.0.0.1:%d" % (port + 1)])
			_tap(_menu.net_buttons[0])
			_menu.host_port_edit.text = str(port)
			_ok("тап «Создать игру» — форма, «Из сохранения…» активна", _menu.current_screen == "host"
					and not _menu.host_load_button.disabled)
		13:
			_tap(_menu.host_load_button)
			_ok("тап «Из сохранения…» — список", _menu.current_screen == "load" and _menu.saves.size() == 1
					and _menu.load_go_button.text == "Выбрать")
		14:
			_tap(_menu.save_buttons[0])
			_tap(_menu.load_go_button)
			_ok("тап «Выбрать» — форма: сид 4242 из файла, поле закрыто", _menu.current_screen == "host"
					and _menu.host_load_slot == "1" and _menu.host_seed_edit.text == "4242"
					and not _menu.host_seed_edit.editable)
		15:
			_tap(_menu.host_create_button)
			_ok("тап «Создать» — лобби хоста, Net.session[load] = слот, сид файла", _menu.current_screen == "lobby"
					and net.is_host() and String(net.session.get("load", "")) == "1"
					and int(net.session.get("seed", -1)) == 4242, _menu.host_error_label.text)
		16:
			_tap(_menu.start_button)


# ------------------------------------------------------------- снимок и листы

## Листы (--sheets=): {"vp": SubViewport, "sheet": Sheet, "file": имя, "groups": клетки}.
var _sheets: Array = []
var _sheets_dir: String = ""


func _shot_step() -> bool:
	_frames += 1
	match _step:
		0:
			DirAccess.make_dir_recursive_absolute(TMP_DIR)
			DirAccess.remove_absolute(TestEnv.file(TMP_PROFILE))
			var p: Profile = Profile.load_or_create(TestEnv.file(TMP_PROFILE))
			p.save_to(TestEnv.file(TMP_PROFILE))
			# Есть сохранение (#132) — «Загрузить» на снимке активна, как у играющего.
			var save_s: GDScript = load("res://scripts/core/save.gd")
			var f: FileAccess = FileAccess.open(save_s.path_for(SAVE_SLOTS[0]), FileAccess.WRITE)
			f.store_buffer(save_s.encode({"version": save_s.VERSION, "seed": 31337, "game": {"day_number": 4}}))
			f.close()
			_menu = load(MENU_SCENE).instantiate()
			_menu.set("profile_path", TestEnv.file(TMP_PROFILE))
			root.add_child(_menu)
			current_scene = _menu
			_frames = 0
			_step = 1
		1:
			# Превью дышит; снимаем, когда герой стоит лицом вправо.
			if _frames >= 45:
				_step = 2
				_save_shot()
		3:
			_menu.queue_free()
			_menu = null
			if _sheets_dir == "":
				_step = 6
			else:
				_sheets_start()
				_frames = 0
				_step = 4
		4:
			if _frames >= 4:
				_step = 5
				_sheets_finish()
		6:
			load("res://scripts/core/save.gd").remove(SAVE_SLOTS[0])
			DirAccess.remove_absolute(TestEnv.file(TMP_PROFILE))
			print("ИТОГ: проверок %d, провалов %d" % [_checks, _fails])
			quit(1 if _fails > 0 else 0)
			return true
	return false


func _save_shot() -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path(_shot_path)
	var err: Error = img.save_png(path)
	print("СНИМОК МЕНЮ: %s (%dx%d) %s" % [path, img.get_width(), img.get_height(), error_string(err)])
	_ok("снимок меню сохранён", err == OK)
	_step = 3


## Позы листа героя: подпись, фаза шага, доля скорости, дыхание, прыжок, работа,
## укрытие, урон.
const SHEET_POSES: Array = [
	["стоит", 0.0, 0.0, 0.3, false, false, false, 0.0],
	["шаг 1", 1.3, 1.0, 0.0, false, false, false, 0.0],
	["шаг 2", 2.9, 1.0, 0.0, false, false, false, 0.0],
	["шаг 3", 4.4, 1.0, 0.0, false, false, false, 0.0],
	["прыжок", 0.0, 0.6, 0.0, true, false, false, 0.0],
	["копка", 0.0, 0.0, 0.0, false, true, false, 0.0],
	["укрытие", 0.0, 0.0, 0.3, false, false, true, 0.0],
	["урон", 0.0, 0.0, 0.3, false, false, false, 0.8],
]


func _sheets_start() -> void:
	_sheets.append(_sheet_facing())
	_sheets.append(_sheet_variants())
	for s in _sheets:
		var vp: SubViewport = SubViewport.new()
		vp.size = Vector2i(s["sheet"].size_px)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.add_child(s["sheet"])
		root.add_child(vp)
		s["vp"] = vp


## Лист героя: позы × направления, до V4 и после.
func _sheet_facing() -> Dictionary:
	var sh: Sheet = Sheet.new()
	var cw: float = 150.0
	var x0: float = 230.0
	var sc: float = 6.0
	sh.size_px = Vector2(x0 + cw * SHEET_POSES.size() + 10.0, 1040.0)
	for c in SHEET_POSES.size():
		sh.labels.append([Vector2(x0 + cw * c + 40.0, 40.0), SHEET_POSES[c][0], 22, Sheet.INK])
	var y: float = 60.0
	for legacy in [true, false]:
		sh.labels.append([Vector2(16.0, y + 34.0), "ДО (main): красный герой" if legacy
				else "ПОСЛЕ: скафандр «Кербер-9» (V4)", 26, Sheet.BAD if legacy else Sheet.GOOD])
		y += 50.0
		for facing in [1, -1]:
			sh.labels.append([Vector2(16.0, y + 110.0), "вправо" if facing > 0 else "влево", 22, Sheet.INK])
			for c in SHEET_POSES.size():
				var p: Array = SHEET_POSES[c]
				var lay: Dictionary
				if legacy:
					lay = Legacy.layout(facing, p[1], p[3], float(p[2]) * 168.0)
				else:
					lay = Avatar.layout(0, facing, p[1], p[3], p[2], p[4], p[5])
				var it: Dictionary = {"pos": Vector2(x0 + cw * c + cw * 0.5, y + 130.0), "scale": sc,
						"lay": lay, "look": 0, "legacy": legacy,
						"state": {"breath": p[3], "hiding": p[6], "flash": p[7]}}
				if p[5]:
					it["pick"] = Vector2(0.0, -6.0) if legacy else (lay["glove"] as Rect2).get_center()
					it["cell"] = Vector2(22.0 * facing, 8.0)
				sh.items.append(it)
			y += 210.0
	return {"sheet": sh, "file": "player_facing.png", "groups": {}}


## Лист вариантов: 16 цветов, 4 шлема, 4 аксессуара, 4 ранца, двойник, «Случайно».
func _sheet_variants() -> Dictionary:
	var sh: Sheet = Sheet.new()
	var cw: float = 100.0
	var ch: float = 150.0
	var sc: float = 4.0
	var x0: float = 20.0
	sh.size_px = Vector2(x0 * 2.0 + cw * 16.0, 40.0 + (ch + 40.0) * 4.0)
	var groups: Dictionary = {"цвет": [], "шлем": [], "аксессуар": [], "ранец": [], "случайные": []}
	var rows: Array = []
	var row0: Array = []
	for i in 16:
		row0.append(["цвет", Profile.Look.pack(PackedInt32Array([i, 0, 0, 0])), 1, {},
				Avatar.variant_name(0, i)])
	rows.append([["Цвет скафандра — 16 (палитра концепта A)"], row0])
	var row1: Array = []
	var hc: Array = [0, 3, 4, 1]
	for h in 4:
		row1.append(["шлем", Profile.Look.pack(PackedInt32Array([hc[h], h, 0, 0])), 1, {},
				Avatar.variant_name(1, h)])
	var ac: Array = [5, 2, 7, 8]
	for a in 4:
		row1.append(["аксессуар", Profile.Look.pack(PackedInt32Array([ac[a], 0, a, 0])), 1, {},
				Avatar.variant_name(2, a)])
	rows.append([["Шлем / визор — 4", "Аксессуар — 4"], row1])
	var row2: Array = []
	var pc: Array = [9, 6, 10, 13]
	for k in 4:
		row2.append(["ранец", Profile.Look.pack(PackedInt32Array([pc[k], 0, 0, k])), 1, {},
				Avatar.variant_name(3, k)])
	var dl: int = Profile.Look.pack(PackedInt32Array([3, 1, 3, 2]))
	row2.append(["", dl, 1, {}, "герой"])
	row2.append(["", dl, -1, {"impostor": true, "lit": true}, "двойник"])
	row2.append(["", dl, -1, {"impostor": true, "lit": false, "tint": Color(0.6, 0.85, 1.0),
			"tint_k": 0.55}, "оглушён"])
	row2.append(["", dl, 1, {"hiding": true}, "в укрытии"])
	rows.append([["Рюкзак / баллоны — 4", "Двойник — тем же Avatar с видом героя"], row2])
	var row3: Array = []
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 97
	for i in 16:
		row3.append(["случайные", Avatar.random_look(rng), -1 if i % 2 == 1 else 1, {}, ""])
	rows.append([["«Случайно» — 16 видов"], row3])
	var y: float = 10.0
	for row in rows:
		for t in (row[0] as Array).size():
			sh.labels.append([Vector2(x0 + cw * 4.0 * t, y + 26.0), row[0][t], 22, Sheet.INK])
		y += 40.0
		for c in (row[1] as Array).size():
			var cell: Array = row[1][c]
			var pos: Vector2 = Vector2(x0 + cw * c + cw * 0.5, y + 86.0)
			var st: Dictionary = (cell[3] as Dictionary).duplicate()
			st["breath"] = 0.0
			sh.items.append({"pos": pos, "scale": sc, "look": cell[1], "state": st,
					"lay": Avatar.layout(cell[1], cell[2], 0.0, 0.0, 0.0, false, false)})
			sh.labels.append([Vector2(pos.x - cw * 0.5, y + ch - 2.0), cell[4], 13, Sheet.DIM, cw])
			if String(cell[0]) != "":
				(groups[cell[0]] as Array).append(Rect2i(Vector2i(pos) - Vector2i(48, 84), Vector2i(96, 132)))
		y += ch
	return {"sheet": sh, "file": "avatar_variants.png", "groups": groups}


func _sheets_finish() -> void:
	await RenderingServer.frame_post_draw
	for s in _sheets:
		var img: Image = (s["vp"] as SubViewport).get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		var path: String = ProjectSettings.globalize_path(_sheets_dir.path_join(s["file"]))
		var err: Error = img.save_png(path)
		print("ЛИСТ: %s (%dx%d) %s" % [path, img.get_width(), img.get_height(), error_string(err)])
		_ok("лист %s сохранён" % s["file"], err == OK)
		# Каждый вариант рисуется (в клетке есть фигура) и отличается от соседей по части.
		var groups: Dictionary = s["groups"]
		for g in groups:
			var empty: int = 0
			var seen: Dictionary = {}
			for r: Rect2i in groups[g]:
				var crop: Image = img.get_region(r)
				if _ink(crop) < 150:
					empty += 1
				seen[crop.get_data()] = true
			var n: int = (groups[g] as Array).size()
			# «Случайно» может выпасть дважды — там только «рисуется».
			var differ: bool = g == "случайные" or seen.size() == n
			_ok("варианты «%s» рисуются%s" % [g, "" if g == "случайные" else " и различаются"],
					empty == 0 and differ, "клеток %d, пустых %d, разных %d" % [n, empty, seen.size()])
		(s["vp"] as SubViewport).queue_free()
	_sheets.clear()
	_step = 6


## Сколько пикселей клетки (через один) отличаются от фона листа.
func _ink(img: Image) -> int:
	var n: int = 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c: Color = img.get_pixel(x, y)
			if absf(c.r - Sheet.BG.r) + absf(c.g - Sheet.BG.g) + absf(c.b - Sheet.BG.b) > 0.06:
				n += 1
	return n
