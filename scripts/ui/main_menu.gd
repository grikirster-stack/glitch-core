class_name MainMenu
extends Control
## Главный экран (ADR-002 § 4.6; MP-B, #87): название, живое превью героя тем же
## Avatar.draw, что в игре, ник с проверкой, параметры вида, «Одиночная игра»
## (сид, хардкор галочкой), сетевые кнопки (заглушка «Скоро» до MP-H, #93),
## номер версии в углу.
##
## Показ: main.gd открывает scenes/menu.tscn только при запуске без аргументов
## командной строки, не под --script и без сессии (Net.session) — тесты и CI
## (--test, --scenario=, --mp-*, --script) стартуют как раньше.
##
## Профиль (ник, uid, вид) меню держит в Net.local_profile — его шлёт рукопожатие,
## по нему main.gd красит своего героя. «Одиночная игра» кладёт выбор в
## Net.session = {mode: "single", seed (−1 — случайный), hardcore} и меняет сцену
## на main.tscn; main.gd превращает его в --seed= / --hardcore. Перезапуск (R после
## финала) берёт тот же выбор.
##
## Пока меню — текущая сцена, дерево на паузе (Game, Threat и мир не тикают,
## ночь в меню не наступает), а слой UI (HUD) скрыт; сам экран работает в паузе.
## Всё — обычные Control: тап по кнопке приходит кликом (эмуляция мыши из
## касаний включена), поле ввода на телефоне открывает экранную клавиатуру.

const GAME_SCENE: String = "res://scenes/main.tscn"
## Масштаб героя в превью.
const PREVIEW_SCALE: float = 6.0
## Высота площадки превью, px.
const STAGE_H: float = 180.0
## Превью поворачивается раз в столько секунд.
const TURN_EVERY: float = 2.0
## Высота кнопок, px при высоте экрана 720 — палец попадает (≈ 7 мм на телефоне).
const BUTTON_H: float = 52.0
const COL_W: float = 360.0
const ACCENT: Color = Color(0.40, 0.95, 0.80)
const SOON_TEXT: String = "Скоро: сетевая игра ещё в работе"

## Откуда профиль (тесты подставляют временный путь до add_child).
var profile_path: String = Profile.PATH
var profile: Profile = null

var nick_edit: LineEdit
var nick_error_label: Label
var seed_edit: LineEdit
## «Хардкор» — кнопка-переключатель (крупнее галочки под палец).
var hardcore_box: Button
var single_button: Button
var net_buttons: Array[Button] = []
var status_label: Label
var version_label: Label
var preview: AvatarPreview
## Подпись и стрелки каждой части вида (Profile.Look.COLOR..PACK).
var look_labels: Array[Label] = []
var look_arrows: Array[Button] = []
## Образец цвета скафандра рядом с его подписью.
var color_swatch: ColorRect = null
var random_button: Button

## Время до первого кадра меню, мс от запуска процесса (замер ADR § 5.3).
static var first_frame_ms: int = -1
## Когда началась сборка меню (_ready), мс от запуска процесса.
static var ready_ms: int = -1

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _paused_tree: bool = false
var _stars: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	var t_ready: int = Time.get_ticks_msec()
	_rng.randomize()
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	profile = Profile.load_or_create(profile_path)
	theme = _make_theme()
	_build()
	_refresh_look()
	_on_nick_changed(nick_edit.text)
	# Меню — сцена целиком: игровые автозагрузки спят, HUD не виден.
	if get_parent() == get_tree().root:
		_paused_tree = true
		get_tree().paused = true
		_set_game_ui_visible(false)
		single_button.grab_focus()
		if first_frame_ms < 0:
			ready_ms = t_ready
			# Без рендера (--headless) frame_post_draw не приходит — берём первый кадр цикла.
			if DisplayServer.get_name() == "headless":
				get_tree().process_frame.connect(_report_first_frame, CONNECT_ONE_SHOT)
			else:
				RenderingServer.frame_post_draw.connect(_report_first_frame, CONNECT_ONE_SHOT)


func _exit_tree() -> void:
	_leave()


static func _report_first_frame() -> void:
	first_frame_ms = Time.get_ticks_msec()
	print("МЕНЮ: первый кадр через %d мс от запуска процесса (сборка меню и кадр — %d мс)"
			% [first_frame_ms, first_frame_ms - ready_ms])


# ------------------------------------------------------------------ ДЕЙСТВИЯ

## «Одиночная игра»: выбор — в Net.session, дальше старт старым путём main.gd.
func start_single() -> void:
	if Net.nick_error(nick_edit.text) != "":
		return
	profile.save_to(profile_path)
	Net.local_profile = profile.to_net()
	Net.session = session_for(seed_edit.text, hardcore_box.button_pressed)
	_leave()
	get_tree().change_scene_to_file(GAME_SCENE)


## Сессия одиночной игры для main.gd (формат Net.session, MP-A).
## Сид: пусто — случайный (−1); целое ≥ 0 — как есть; другой текст — hash().
static func session_for(seed_text: String, hardcore: bool) -> Dictionary:
	var s: String = seed_text.strip_edges()
	var sd: int = -1
	if s != "":
		sd = int(s) if s.is_valid_int() and int(s) >= 0 else hash(s)
	return {"mode": "single", "seed": sd, "hardcore": hardcore}


func set_part(i: int, idx: int) -> void:
	var n: int = Avatar.VARIANTS[i]
	profile.look = Profile.Look.with_part(profile.look, i, posmod(idx, n))
	profile.save_to(profile_path)
	_refresh_look()


func step_part(i: int, d: int) -> void:
	set_part(i, Avatar.resolve(profile.look, i) + d)


func randomize_look() -> void:
	profile.look = Avatar.random_look(_rng)
	profile.save_to(profile_path)
	_refresh_look()


func _on_nick_changed(text: String) -> void:
	var err: String = Net.nick_error(text)
	nick_error_label.text = ("Ник: " + err) if err != "" else ""
	single_button.disabled = err != ""
	for b in net_buttons:
		b.disabled = err != ""
	if err == "" and text.strip_edges() != profile.nick:
		profile.nick = text.strip_edges()
		profile.save_to(profile_path)
		Net.local_profile = profile.to_net()


func _on_soon() -> void:
	status_label.text = SOON_TEXT


func _leave() -> void:
	if not _paused_tree:
		return
	_paused_tree = false
	get_tree().paused = false
	_set_game_ui_visible(true)


## Слой UI (HUD, инвентарь, журнал) — автозагрузка; в меню его не видно.
func _set_game_ui_visible(v: bool) -> void:
	var ui: Node = get_tree().root.get_node_or_null("UI")
	if ui is CanvasLayer:
		(ui as CanvasLayer).visible = v


func _refresh_look() -> void:
	for i in Profile.Look.PARTS:
		var idx: int = Avatar.resolve(profile.look, i)
		var n: int = Avatar.VARIANTS[i]
		look_labels[i].text = Avatar.variant_name(i, idx) if n <= 1 \
				else "%s  %d/%d" % [Avatar.variant_name(i, idx), idx + 1, n]
		look_arrows[i * 2].disabled = n <= 1
		look_arrows[i * 2 + 1].disabled = n <= 1
	if color_swatch != null:
		color_swatch.color = Avatar.suit_color(profile.look)
	preview.look = profile.look
	Net.local_profile = profile.to_net()


# ------------------------------------------------------------------ ВЁРСТКА


func _build() -> void:
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var page: VBoxContainer = VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	center.add_child(page)

	var title: Label = _label("ГЛИТЧ-КОРЕ", 48, ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(title)
	var sub: Label = _label("Экспедиция «Кербер-9». Связь с орбитой потеряна.", 18,
			Color(0.75, 0.82, 0.92))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(sub)

	var cols: HBoxContainer = HBoxContainer.new()
	cols.add_theme_constant_override("separation", 64)
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_child(cols)

	# --- Левая колонка: превью и вид.
	var left: VBoxContainer = VBoxContainer.new()
	left.custom_minimum_size = Vector2(COL_W, 0)
	left.add_theme_constant_override("separation", 8)
	cols.add_child(left)
	var stage: Control = Control.new()
	stage.custom_minimum_size = Vector2(COL_W, STAGE_H)
	left.add_child(stage)
	preview = AvatarPreview.new()
	preview.scale = Vector2(PREVIEW_SCALE, PREVIEW_SCALE)
	preview.position = Vector2(COL_W * 0.5, STAGE_H - Avatar.SIZE.y * 0.5 * PREVIEW_SCALE - 12.0)
	stage.add_child(preview)
	var head: HBoxContainer = HBoxContainer.new()
	var head_l: Label = _label("Вид персонажа", 20, ACCENT)
	head_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(head_l)
	random_button = _button("Случайно")
	random_button.custom_minimum_size = Vector2(150, BUTTON_H)
	random_button.pressed.connect(randomize_look)
	head.add_child(random_button)
	left.add_child(head)
	for i in Profile.Look.PARTS:
		left.add_child(_look_row(i))
	var note: Label = _label("Шлем, аксессуар и рюкзак — с новым скафандром", 14,
			Color(0.6, 0.66, 0.76))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(note)

	# --- Правая колонка: ник, одиночная игра, сеть.
	var right: VBoxContainer = VBoxContainer.new()
	right.custom_minimum_size = Vector2(COL_W, 0)
	right.add_theme_constant_override("separation", 8)
	cols.add_child(right)
	right.add_child(_label("Ник", 20, ACCENT))
	nick_edit = LineEdit.new()
	nick_edit.text = profile.nick
	nick_edit.max_length = Net.NICK_MAX + 8
	nick_edit.placeholder_text = "2–16 символов"
	nick_edit.custom_minimum_size = Vector2(0, BUTTON_H)
	nick_edit.text_changed.connect(_on_nick_changed)
	right.add_child(nick_edit)
	nick_error_label = _label("", 14, Color(1.0, 0.55, 0.45))
	nick_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nick_error_label.custom_minimum_size = Vector2(COL_W, 20)
	right.add_child(nick_error_label)

	var seed_row: HBoxContainer = HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 10)
	right.add_child(seed_row)
	seed_edit = LineEdit.new()
	seed_edit.placeholder_text = "сид: случайный"
	seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_edit.custom_minimum_size = Vector2(0, BUTTON_H)
	seed_row.add_child(seed_edit)
	hardcore_box = _button("Хардкор: нет")
	hardcore_box.toggle_mode = true
	hardcore_box.custom_minimum_size = Vector2(150, BUTTON_H)
	hardcore_box.toggled.connect(func(on: bool) -> void:
			hardcore_box.text = "Хардкор: да" if on else "Хардкор: нет")
	hardcore_box.tooltip_text = "Одна жизнь, без сохранений"
	hardcore_box.custom_minimum_size = Vector2(0, BUTTON_H)
	seed_row.add_child(hardcore_box)

	single_button = _button("Одиночная игра")
	single_button.pressed.connect(start_single)
	right.add_child(single_button)
	for t in ["Создать игру", "Найти игру", "Подключиться по IP"]:
		var b: Button = _button(t)
		b.pressed.connect(_on_soon)
		net_buttons.append(b)
		right.add_child(b)
	var quit_b: Button = _button("Выход")
	quit_b.pressed.connect(func() -> void: get_tree().quit())
	right.add_child(quit_b)
	status_label = _label("", 15, Color(1.0, 0.85, 0.5))
	status_label.custom_minimum_size = Vector2(COL_W, 22)
	right.add_child(status_label)

	version_label = _label("версия %s" % Profile.build_version(), 14, Color(0.55, 0.6, 0.7))
	version_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	version_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version_label.offset_right = -16
	version_label.offset_bottom = -10
	add_child(version_label)


func _look_row(i: int) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var prev_b: Button = _button("◀")
	prev_b.custom_minimum_size = Vector2(BUTTON_H, BUTTON_H)
	prev_b.pressed.connect(step_part.bind(i, -1))
	row.add_child(prev_b)
	var lbl: Label = _label("", 17, Color(0.9, 0.93, 1.0))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.tooltip_text = Profile.Look.NAMES[i]
	lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(lbl)
	var next_b: Button = _button("▶")
	next_b.custom_minimum_size = Vector2(BUTTON_H, BUTTON_H)
	next_b.pressed.connect(step_part.bind(i, 1))
	row.add_child(next_b)
	if i == Profile.Look.COLOR:
		color_swatch = ColorRect.new()
		color_swatch.custom_minimum_size = Vector2(20, 20)
		color_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(color_swatch)
		row.move_child(color_swatch, 1)
	look_labels.append(lbl)
	look_arrows.append(prev_b)
	look_arrows.append(next_b)
	return row


func _label(text: String, font_size: int, col: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	return l


func _button(text: String) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, BUTTON_H)
	b.focus_mode = Control.FOCUS_ALL
	return b


func _make_theme() -> Theme:
	var th: Theme = Theme.new()
	th.default_font_size = 20
	var normal: StyleBoxFlat = _box(Color(0.10, 0.13, 0.20, 0.92), Color(0.25, 0.32, 0.45))
	var hover: StyleBoxFlat = _box(Color(0.15, 0.20, 0.30, 0.95), ACCENT.darkened(0.2))
	var pressed: StyleBoxFlat = _box(Color(0.08, 0.28, 0.26, 0.95), ACCENT)
	var disabled: StyleBoxFlat = _box(Color(0.08, 0.09, 0.12, 0.8), Color(0.18, 0.2, 0.26))
	var focus: StyleBoxFlat = _box(Color(0, 0, 0, 0), ACCENT)
	focus.draw_center = false
	for cls in ["Button"]:
		th.set_stylebox("normal", cls, normal)
		th.set_stylebox("hover", cls, hover)
		th.set_stylebox("pressed", cls, pressed)
		th.set_stylebox("hover_pressed", cls, pressed)
		th.set_stylebox("disabled", cls, disabled)
		th.set_stylebox("focus", cls, focus)
		th.set_color("font_color", cls, Color(0.92, 0.95, 1.0))
		th.set_color("font_hover_color", cls, Color(1, 1, 1))
		th.set_color("font_disabled_color", cls, Color(0.45, 0.48, 0.55))
	th.set_stylebox("normal", "LineEdit", _box(Color(0.05, 0.07, 0.11, 0.95), Color(0.25, 0.32, 0.45)))
	th.set_stylebox("focus", "LineEdit", focus)
	th.set_color("font_color", "LineEdit", Color(0.95, 0.97, 1.0))
	th.set_color("font_placeholder_color", "LineEdit", Color(0.5, 0.55, 0.65))
	return th


func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(6)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


# ------------------------------------------------------------------ ФОН

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_stars = PackedVector2Array()
		queue_redraw()


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	# Небо: сверху ночь, к горизонту — сине-зелёная дымка.
	var top: Color = Color(0.03, 0.04, 0.08)
	var low: Color = Color(0.07, 0.13, 0.18)
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]),
			PackedColorArray([top, top, low, low]))
	if _stars.is_empty():
		var srng: RandomNumberGenerator = RandomNumberGenerator.new()
		srng.seed = 9
		for i in 140:
			_stars.append(Vector2(srng.randf() * w, srng.randf() * h * 0.8))
	for i in _stars.size():
		var a: float = 0.25 + 0.5 * float((i * 37) % 11) / 10.0
		draw_rect(Rect2(_stars[i], Vector2(2, 2)), Color(0.8, 0.9, 1.0, a))
	# Рельеф у горизонта.
	var ground: PackedVector2Array = PackedVector2Array([Vector2(0, h)])
	for i in 33:
		var x: float = w * float(i) / 32.0
		ground.append(Vector2(x, h - 46.0 - 18.0 * sin(float(i) * 0.9) - 10.0 * sin(float(i) * 2.3)))
	ground.append(Vector2(w, h))
	draw_colored_polygon(ground, Color(0.06, 0.08, 0.10))


## Живое превью: тот же Avatar.draw, что у героя в игре. Позу (дыхание, поворот)
## считает Player.body_layout() отдельного, не добавленного в дерево героя —
## шов раскладки один (#58), его меняет только MP-L.
class AvatarPreview extends Node2D:
	var look: int = 0
	var t: float = 0.0
	var _pose: Player = Player.new()

	func _process(delta: float) -> void:
		t += delta
		_pose._breath = t
		_pose.facing = 1 if int(t / TURN_EVERY) % 2 == 0 else -1
		queue_redraw()

	func _draw() -> void:
		Avatar.draw(self, _pose.body_layout(), look, {"breath": t})

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE and is_instance_valid(_pose):
			_pose.free()
