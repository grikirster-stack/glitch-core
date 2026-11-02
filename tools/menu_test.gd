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
## Отдельный запуск сверх того: «Одиночная игра» из меню запускает мир с сидом,
## хардкором и цветом из профиля; замер Avatar.draw против прежнего Player._draw.
##
## Отдельный запуск:
##   godot --headless --path . --script res://tools/menu_test.gd
## В составе общего прогона (--test) те же проверки вызывает tools/test_runner.gd
## (секция «== Меню и профиль ==») — общий код, без дублирования; смену сцены
## и замер там не делаем (раннер живёт в сцене игры).
##
## Снимок меню и попиксельная сверка Avatar.draw с прежним рисунком (нужен
## настоящий рендер, окно — за экраном):
##   godot --path . --windowed --position -10000,-10000 --resolution 1280x720 \
##         --script res://tools/menu_test.gd -- --menu-shot=res://docs/img/menu.png
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
## Временный профиль: настоящий user://profile.cfg тест не трогает.
const TMP_DIR: String = "user://menu_test"
const TMP_PROFILE: String = "user://menu_test/profile.cfg"
## Цвет героя до ADR-002 (Player._draw).
const OLD_RED: Color = Color(0.86, 0.22, 0.24)

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
		if old:
			_old_draw()
		else:
			super._draw()
	var dt: int = Time.get_ticks_usec() - t0
	usec += dt
	calls += reps
	best = minf(best, float(dt) / float(reps))
## Player._draw до MP-B дословно (коммит c2e8802, scripts/entities/player.gd).
func _old_draw() -> void:
	var body_col: Color = Color(0.86, 0.22, 0.24)
	if hiding:
		body_col = body_col.darkened(0.45)
	var flash: float = _hit_flash / HIT_FLASH
	if flash > 0.0:
		body_col = body_col.lerp(Color(1.0, 0.74, 0.64), flash * 0.85)
	var lay: Dictionary = body_layout()
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
	_draw_mining_fx()
"""


## Прежний Player._draw (до MP-B) дословно, с параметрами вместо полей героя:
## эталон для попиксельной сверки.
class Legacy:
	static func draw(c: CanvasItem, lay: Dictionary, hiding: bool, flash: float, breath: float) -> void:
		var size: Vector2 = Vector2(12.0, 22.0)
		var body_col: Color = Color(0.86, 0.22, 0.24)
		if hiding:
			body_col = body_col.darkened(0.45)
		if flash > 0.0:
			body_col = body_col.lerp(Color(1.0, 0.74, 0.64), flash * 0.85)
		var r: Rect2 = lay["body"]
		c.draw_set_transform(Vector2(0, size.y * 0.5), 0.0, Vector2(1.0, 0.35))
		c.draw_circle(Vector2.ZERO, size.x * 0.6, Color(0, 0, 0, 0.28))
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
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


## Холст попиксельной сверки: mode 0 — Legacy, 1 — Avatar.draw.
class Canvas extends Node2D:
	var mode: int = 0
	var lay: Dictionary = {}
	var look: int = 0
	var hiding: bool = false
	var flash: float = 0.0
	var breath: float = 0.0

	func _draw() -> void:
		if mode == 0:
			Legacy.draw(self, lay, hiding, flash, breath)
		else:
			Avatar.draw(self, lay, look, {"hiding": hiding, "flash": flash, "breath": breath})


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
		_ok("до ADR-003: 8 цветов, остальные части — только 0",
				Avatar.VARIANTS == PackedInt32Array([8, 1, 1, 1]) and Avatar.SUIT_COLORS.size() == 8)
		_ok("вид 0 — прежний красный герой", Avatar.suit_color(0) == OLD_RED)
		var wrong: Array = []
		for i in Profile.Look.PARTS:
			for idx in Profile.Look.SIZE:
				var v: int = Profile.Look.with_part(0, i, idx)
				var want: int = idx if idx < Avatar.VARIANTS[i] else 0
				if Avatar.resolve(v, i) != want:
					wrong.append("часть %d индекс %d" % [i, idx])
		_ok("неизвестный индекс рисуется как 0", wrong.is_empty(), str(wrong.slice(0, 4)))
		var unk: int = Profile.Look.pack(PackedInt32Array([12, 9, 15, 3]))
		_ok("неизвестный цвет — цвет 0", Avatar.suit_color(unk) == Avatar.suit_color(0))
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
		DirAccess.remove_absolute(TMP_PROFILE)
		var p1: Profile = Profile.load_or_create(TMP_PROFILE)
		_ok("нет файла — профиль создан и записан", FileAccess.file_exists(TMP_PROFILE) and p1.uid != 0
				and p1.nick == Profile.DEFAULT_NICK and p1.look == 0 and p1.port == Profile.DEFAULT_PORT)
		var p2: Profile = Profile.load_or_create(TMP_PROFILE)
		_ok("uid создаётся один раз", p2.uid == p1.uid, "%d / %d" % [p1.uid, p2.uid])
		p2.nick = "Аня-2"
		p2.look = Profile.Look.pack(PackedInt32Array([5, 0, 0, 0]))
		p2.recent_ips = PackedStringArray(["192.168.1.20", "10.0.0.5"])
		p2.port = 25000
		_ok("профиль записан", p2.save_to(TMP_PROFILE) == OK)
		var p3: Profile = Profile.load_or_create(TMP_PROFILE)
		_ok("профиль туда-обратно: uid, ник, вид, адреса, порт", p3.uid == p1.uid and p3.nick == "Аня-2"
				and p3.look == p2.look and p3.recent_ips == p2.recent_ips and p3.port == 25000,
				"%s look=%d ips=%s port=%d" % [p3.nick, p3.look, str(p3.recent_ips), p3.port])
		var cfg: ConfigFile = ConfigFile.new()
		cfg.load(TMP_PROFILE)
		_ok("в файле [profile] uid/nick/look и [net] recent_ips/port",
				cfg.has_section_key("profile", "uid") and cfg.has_section_key("profile", "nick")
				and cfg.has_section_key("profile", "look") and cfg.has_section_key("net", "recent_ips")
				and cfg.has_section_key("net", "port"))
		# Чужой/битый профиль: неверные поля — по умолчанию, uid сохраняется.
		cfg.set_value("profile", "nick", "!!")
		cfg.set_value("profile", "look", "красный")
		cfg.set_value("net", "port", 99999)
		cfg.save(TMP_PROFILE)
		var p4: Profile = Profile.load_or_create(TMP_PROFILE)
		_ok("битые поля — значения по умолчанию, uid тот же", p4.nick == Profile.DEFAULT_NICK
				and p4.look == 0 and p4.port == Profile.DEFAULT_PORT and p4.uid == p1.uid)
		var f: FileAccess = FileAccess.open(TMP_PROFILE, FileAccess.WRITE)
		f.store_string("это не ConfigFile [[[")
		f.close()
		var p5: Profile = Profile.load_or_create(TMP_PROFILE)
		_ok("мусор вместо файла — новый профиль", p5.uid != 0 and p5.nick == Profile.DEFAULT_NICK)
		var unk: int = Profile.Look.pack(PackedInt32Array([12, 9, 15, 3]))
		p5.look = unk
		p5.save_to(TMP_PROFILE)
		_ok("неизвестные индексы вида хранятся как есть",
				Profile.load_or_create(TMP_PROFILE).look == unk)
		_ok("uid — 64 бита, разные", Profile.new_uid() != Profile.new_uid())
		DirAccess.remove_absolute(TMP_PROFILE)

	# --- Меню: сборка, ник, вид, заглушки (узлом-ребёнком, без смены сцены)
	func _check_menu() -> void:
		var net: Node = get_tree().root.get_node("Net")
		var net_profile0: Dictionary = net.local_profile.duplicate()
		DirAccess.remove_absolute(TMP_PROFILE)
		var menu = load(MENU_SCENE).instantiate()
		var mm = load(MENU_SCRIPT)
		menu.set("profile_path", TMP_PROFILE)
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
				and Profile.load_or_create(TMP_PROFILE).nick == "Аня")
		menu.step_part(Profile.Look.COLOR, 1)
		menu.step_part(Profile.Look.HELMET, 1)
		var saved: int = Profile.load_or_create(TMP_PROFILE).look
		_ok("стрелки: цвет 1, шлем остался 0 (один вариант), сохранено",
				Profile.Look.part(saved, Profile.Look.COLOR) == 1
				and Profile.Look.part(saved, Profile.Look.HELMET) == 0
				and menu.preview.look == saved and menu.look_arrows[2].disabled)
		menu.step_part(Profile.Look.COLOR, -2)
		_ok("стрелка влево по кругу: цвет 7",
				Profile.Look.part(menu.profile.look, Profile.Look.COLOR) == Avatar.VARIANTS[0] - 1)
		menu.randomize_look()
		var rl: int = menu.profile.look
		_ok("«Случайно» в пределах вариантов", Profile.Look.part(rl, 0) < Avatar.VARIANTS[0]
				and (rl >> 4) == 0 and menu.color_swatch.color == Avatar.suit_color(rl))
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
		DirAccess.remove_absolute(TMP_PROFILE)

	# --- Сетевые экраны меню (MP-H, #93): переходы, поля по умолчанию, «Недавние»
	func _check_net_screens(menu) -> void:
		var net: Node = get_tree().root.get_node("Net")
		_ok("сетевые экраны построены: создать, найти, по IP, подключение, лобби",
				menu.screens.size() == 6 and menu.current_screen == "main"
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

	# --- Замер: Avatar.draw против прежнего _draw
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
		var names: Array = ["Player._draw до (прежний код)", "Player._draw после (Avatar.draw)"]
		var line: String = ""
		for k in _bench_nodes.size():
			var n = _bench_nodes[k]
			line += "%s: лучший кадр %.2f, среднее %.2f; " % [names[k], float(n.best),
					float(n.usec) / maxf(1.0, float(n.calls))]
		print("  ЗАМЕР (мкс на одного героя, %d кадров × %d рисунков): %s"
				% [BENCH_FRAMES, BENCH_REPS, line])
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
				_step = 4
			elif _frames > 600:
				_ok("мир из меню запустился", false, "нет сцены игры за 600 кадров")
				_step = 4
		4:
			root.get_node("Net").session = {}
			DirAccess.remove_absolute(TMP_PROFILE)
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
	DirAccess.remove_absolute(TMP_PROFILE)
	var p: Profile = Profile.load_or_create(TMP_PROFILE)
	p.look = Profile.Look.pack(PackedInt32Array([5, 0, 0, 0]))
	p.save_to(TMP_PROFILE)
	root.get_node("Net").session = {}
	_menu = load(MENU_SCENE).instantiate()
	_menu.set("profile_path", TMP_PROFILE)
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


# ------------------------------------------------------------- снимок и сверка

var _cmp: Array = []


func _shot_step() -> bool:
	_frames += 1
	match _step:
		0:
			DirAccess.make_dir_recursive_absolute(TMP_DIR)
			DirAccess.remove_absolute(TMP_PROFILE)
			var p: Profile = Profile.load_or_create(TMP_PROFILE)
			p.save_to(TMP_PROFILE)
			_menu = load(MENU_SCENE).instantiate()
			_menu.set("profile_path", TMP_PROFILE)
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
			_cmp_start()
			_frames = 0
			_step = 4
		4:
			if _frames >= 4:
				_step = 5
				_cmp_finish()
		6:
			DirAccess.remove_absolute(TMP_PROFILE)
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


## Попиксельная сверка: прежний рисунок и Avatar.draw (look 0) в одинаковых
## позах — должны совпасть до бита. Плюс неизвестный цвет = цвет 0.
func _cmp_start() -> void:
	var s: GDScript = GDScript.new()
	s.source_code = BENCH_PLAYER_SRC
	s.reload()
	var poses: Array = []
	for facing in [1, -1]:
		for st in [[false, 0.0, 0.3], [true, 0.0, 1.1], [false, 0.7, 2.0]]:
			poses.append([facing, st])
	for pose in poses:
		var bp = s.new()
		bp.facing = pose[0]
		bp._breath = float(pose[1][2])
		var lay: Dictionary = bp.body_layout()
		bp.free()
		var pair: Array = []
		for k in 3:
			var vp: SubViewport = SubViewport.new()
			vp.size = Vector2i(48, 48)
			vp.transparent_bg = true
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			var c: Canvas = Canvas.new()
			c.mode = 0 if k == 0 else 1
			c.look = Profile.Look.pack(PackedInt32Array([13, 7, 9, 15])) if k == 2 else 0
			c.lay = lay
			c.hiding = pose[1][0]
			c.flash = pose[1][1]
			c.breath = pose[1][2]
			c.position = Vector2(24, 24)
			vp.add_child(c)
			root.add_child(vp)
			pair.append(vp)
		_cmp.append(pair)


func _cmp_finish() -> void:
	await RenderingServer.frame_post_draw
	var same: int = 0
	var same_unk: int = 0
	var opaque: int = 0
	for pair in _cmp:
		var a: Image = (pair[0] as SubViewport).get_texture().get_image()
		var b: Image = (pair[1] as SubViewport).get_texture().get_image()
		var u: Image = (pair[2] as SubViewport).get_texture().get_image()
		if a.get_data() == b.get_data():
			same += 1
		if a.get_data() == u.get_data():
			same_unk += 1
		if not a.is_invisible():
			opaque += 1
		for vp in pair:
			vp.queue_free()
	_ok("Avatar.draw (вид 0) попиксельно равен прежнему _draw", same == _cmp.size() and opaque == _cmp.size(),
			"совпало %d из %d поз" % [same, _cmp.size()])
	_ok("неизвестные индексы рисуются как вид 0", same_unk == _cmp.size(),
			"совпало %d из %d поз" % [same_unk, _cmp.size()])
	_step = 6
