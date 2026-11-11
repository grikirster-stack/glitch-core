class_name MainMenu
extends Control
## Главный экран (ADR-002 § 4.6; MP-B, #87): название, живое превью героя тем же
## Avatar.draw, что в игре, ник с проверкой, параметры вида, «Одиночная игра»
## (сид, хардкор галочкой), «Продолжить» (#119: последний забег одним тапом) и
## «Загрузить» (#132: список сохранений — секция «ЗАГРУЗКА» в конце), сетевые экраны (MP-H, #93: «Создать игру», «Найти игру»,
## «Подключиться по IP», подключение, лобби — секция «СЕТЕВЫЕ ЭКРАНЫ» в конце),
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

## Откуда профиль (тесты подставляют временный путь до add_child).
var profile_path: String = Profile.default_path()
var profile: Profile = null

var nick_edit: LineEdit
var nick_error_label: Label
var seed_edit: LineEdit
## «Хардкор» — кнопка-переключатель (крупнее галочки под палец).
var hardcore_box: Button
## «100 %» (#159): размер интерфейса игры, в одной строке с «Глитч» и «Хотбар».
var ui_scale_button: Button
## «Хотбар: 6 / 10» (#161): в той же строке, что «Интерфейс».
var hotbar_button: Button
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
	theme = make_theme()
	_build()
	_build_net_screens()   # MP-H (#93)
	refresh_continue()     # #119
	_refresh_look()
	_on_nick_changed(nick_edit.text)
	# Меню — сцена целиком: игровые автозагрузки спят, HUD не виден.
	if get_parent() == get_tree().root:
		_paused_tree = true
		get_tree().paused = true
		_set_game_ui_visible(false)
		(continue_button if continue_button.visible else single_button).grab_focus()
		if first_frame_ms < 0:
			ready_ms = t_ready
			# Без рендера (--headless) frame_post_draw не приходит — берём первый кадр цикла.
			if DisplayServer.get_name() == "headless":
				get_tree().process_frame.connect(_report_first_frame, CONNECT_ONE_SHOT)
			else:
				RenderingServer.frame_post_draw.connect(_report_first_frame, CONNECT_ONE_SHOT)


func _exit_tree() -> void:
	_unwire_net()   # MP-H (#93)
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
	campaign_button.disabled = err != ""   # ADR-004
	for b in net_buttons:
		b.disabled = err != ""
	_refresh_load_buttons()   # #132
	if err == "" and text.strip_edges() != profile.nick:
		profile.nick = text.strip_edges()
		profile.save_to(profile_path)
		Net.local_profile = profile.to_net()


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
	_center = center
	main_page = page

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

	# --- Правая колонка: ник, одиночная игра, сеть.
	var right: VBoxContainer = VBoxContainer.new()
	right.custom_minimum_size = Vector2(COL_W, 0)
	right.add_theme_constant_override("separation", 6)   # #119: с «Продолжить» колонка влезает в 720
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
	seed_row.add_theme_constant_override("separation", 8)
	seed_row.custom_minimum_size = Vector2(COL_W, 0)
	right.add_child(seed_row)
	seed_edit = LineEdit.new()
	seed_edit.placeholder_text = "сид: случайный"
	seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_edit.custom_minimum_size = Vector2(0, BUTTON_H)
	seed_edit.add_theme_constant_override("minimum_character_width", 4)
	seed_row.add_child(seed_edit)
	hardcore_box = _button("Хардкор: нет")
	hardcore_box.toggle_mode = true
	hardcore_box.custom_minimum_size = Vector2(0, BUTTON_H)
	# Шрифт мельче основного: в строке ещё поле сида и «Ячеек» (#161), колонка 360 px.
	hardcore_box.add_theme_font_size_override("font_size", UI.FONT["small"])
	hardcore_box.toggled.connect(func(on: bool) -> void:
			hardcore_box.text = "Хардкор: да" if on else "Хардкор: нет")
	hardcore_box.tooltip_text = "Одна жизнь, без сохранений"
	seed_row.add_child(hardcore_box)
	# «Хотбар» (#161) — здесь, а не в строке «Глитч»: та и так 360 px на две кнопки A1.
	hotbar_button = _button("")
	hotbar_button.add_theme_font_size_override("font_size", UI.FONT["small"])
	hotbar_button.custom_minimum_size = Vector2(0, BUTTON_H)
	hotbar_button.tooltip_text = "Сколько ячеек в хотбаре: 6 крупнее на телефоне, 10 — на клавиатуре. Лишние вещи уходят в рюкзак"
	hotbar_button.pressed.connect(_on_hotbar_pressed)
	_refresh_hotbar_button()
	seed_row.add_child(hotbar_button)
	# Доступность: «Глитч» (ADR-003 V7, #108) и размер интерфейса (#159) — одна строка,
	# чтобы колонка с «Продолжить» по-прежнему влезала в 720 по высоте.
	var access_row: HBoxContainer = HBoxContainer.new()
	access_row.add_theme_constant_override("separation", 10)
	right.add_child(access_row)
	var calm_button: Button = GlitchFx.menu_toggle(_button(""), profile, profile_path)
	calm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	calm_button.add_theme_font_size_override("font_size", UI.FONT["body"])
	access_row.add_child(calm_button)
	ui_scale_button = _button("")
	ui_scale_button.add_theme_font_size_override("font_size", UI.FONT["body"])
	ui_scale_button.custom_minimum_size = Vector2(96, BUTTON_H)
	ui_scale_button.tooltip_text = "Размер интерфейса игры: 100–250 %. Подпись и кнопки в забеге крупнее"
	ui_scale_button.pressed.connect(_on_ui_scale_pressed)
	_refresh_ui_scale_button()
	access_row.add_child(ui_scale_button)
	continue_button = _button("Продолжить")   # #119: последний забег; нечего продолжать — кнопки нет
	continue_button.pressed.connect(continue_run)
	continue_button.visible = false
	right.add_child(continue_button)

	campaign_button = _button("Кампания")   # ADR-004: главы на готовой базе
	campaign_button.pressed.connect(show_campaign)
	right.add_child(campaign_button)
	var single_row: HBoxContainer = HBoxContainer.new()
	single_row.add_theme_constant_override("separation", 10)
	right.add_child(single_row)
	single_button = _button("Одиночная игра")
	single_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	single_button.pressed.connect(start_single)
	single_row.add_child(single_button)
	load_button = _button("Загрузить")   # #132: экран «load» со списком сохранений
	load_button.custom_minimum_size = Vector2(150, BUTTON_H)
	load_button.pressed.connect(show_load.bind(LOAD_SINGLE))
	single_row.add_child(load_button)
	var net_actions: Array[Callable] = [show_host_form, show_browser, show_ip]
	# «Создать» и «Найти» — в один ряд (ADR-004): с «Кампанией» колонка влезает в 720.
	var net_row: HBoxContainer = HBoxContainer.new()
	net_row.add_theme_constant_override("separation", 10)
	right.add_child(net_row)
	for k in 3:
		var b: Button = _button(["Создать игру", "Найти игру", "Подключиться по IP"][k])
		b.pressed.connect(net_actions[k])
		net_buttons.append(b)
		if k < 2:
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			net_row.add_child(b)
		else:
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


func _refresh_ui_scale_button() -> void:
	# Короче, чем «Интерфейс:»: в строке ещё «Хотбар» (#161), колонка — 360 px.
	ui_scale_button.text = UI.scale_text(UI.ui_scale)


func _refresh_hotbar_button() -> void:
	hotbar_button.text = "Ячеек: %d" % _hotbar_now()


## Размер хотбара для подписи: из профиля, иначе умолчание экрана (ещё не записано).
func _hotbar_now() -> int:
	if profile.hotbar > 0:
		return Inventory.clamp_hotbar(profile.hotbar)
	return Inventory.default_hotbar(DisplayServer.is_touchscreen_available(), OS.get_cmdline_user_args())


## Тап по «Хотбар»: 6 ↔ 10, пишется в профиль. Уже идущий забег подхватывает размер сразу:
## ячейки 7–10 уходят в рюкзак, не влезло — под ноги.
func _on_hotbar_pressed() -> void:
	var n: int = Inventory.HOTBAR_MAX if _hotbar_now() <= Inventory.HOTBAR_MIN else Inventory.HOTBAR_MIN
	profile.hotbar = n
	profile.save_to(profile_path)
	var p: Player = get_tree().get_first_node_in_group("player") as Player
	if p != null:
		p.apply_hotbar_size(n)
	_refresh_hotbar_button()


## Тап по «Интерфейс»: следующий коэффициент по кругу, применяется сразу и пишется в профиль.
func _on_ui_scale_pressed() -> void:
	var v: float = UI.next_scale(UI.ui_scale)
	UI.set_ui_scale(v, false)
	profile.ui_scale = v
	profile.save_to(profile_path)
	_refresh_ui_scale_button()


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


## Тема меню (кнопки, поля); ею же оформлена пауза в забеге (PauseMenu, #119).
static func make_theme() -> Theme:
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


static func _box(bg: Color, border: Color) -> StyleBoxFlat:
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
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		go_back()


## «Назад» Android (#149; application/config/quit_on_go_back = false): с сетевых экранов —
## как их кнопка «Назад» / «Отмена» / «Выйти», с главного — выход из игры.
func go_back() -> void:
	match current_screen:
		"main":
			get_tree().quit()
		"connecting":
			connect_back_button.pressed.emit()
		"lobby":
			lobby_leave_button.pressed.emit()
		_:
			show_screen("main")


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
## шов раскладки один (#58); от вида (look) зависит и раскладка (шлем, ранец).
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
		_pose.look = look
		Avatar.draw(self, _pose.body_layout(), look, {"breath": t})

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE and is_instance_valid(_pose):
			_pose.free()


# ------------------------------------------------- СЕТЕВЫЕ ЭКРАНЫ (ADR-002 § 4.5, § 4.6; MP-H, #93)
## «Создать игру» (имя, сид, места, порт) → лобби хоста; «Найти игру» (ServerBrowser:
## поиск по локалке, несовместимые — серые с причиной) и «Подключиться по IP» (последние
## адреса из профиля) → «Подключение…» → лобби клиента; лобби: игроки с ником и видом,
## «Готов», «Старт» у хоста (когда готовы все). Сессию, готовность и старт ведёт NetLobby
## (scripts/net/net_lobby.gd, узел под /root — переживает смену сцены). Всё — кнопки
## и поля: тап по кнопке приходит кликом, поле открывает экранную клавиатуру.

## Имя игры: 1–NAME_MAX символов.
const NAME_MAX: int = 24
## Сколько последних адресов показывает «Подключиться по IP».
const RECENT_SHOWN: int = 5
## Ширина сетевых экранов, px при 1280×720.
const NET_W: float = 760.0
const LOBBY_PREVIEW_SCALE: float = 2.5
const ERR_COLOR: Color = Color(1.0, 0.55, 0.45)
const DIM_COLOR: Color = Color(0.6, 0.66, 0.76)
const READY_COLOR: Color = Color(0.45, 0.95, 0.6)

## Тесты (петля, без окна брандмауэра Windows): адрес привязки сервера и поиска,
## порт поиска хоста и цели запроса клиента ("ip:порт"; пусто — широковещательно).
var net_bind: String = "*"
var discovery_port: int = Net.DISCOVERY_PORT
var discovery_targets: PackedStringArray = PackedStringArray()

## Экраны: "main", "host", "browser", "ip", "connecting", "lobby".
var screens: Dictionary = {}
var current_screen: String = "main"
var main_page: Control = null
var lobby: NetLobby = null

# --- «Создать игру»
var host_name_edit: LineEdit
var host_seed_edit: LineEdit
var host_port_edit: LineEdit
var slot_buttons: Array[Button] = []
var host_slots: int = 4
var host_error_label: Label
var host_ips_label: Label
var host_create_button: Button
# --- «Найти игру»
var browser: ServerBrowser
# --- «Подключиться по IP»
var ip_edit: LineEdit
var ip_error_label: Label
var ip_connect_button: Button
var recent_buttons: Array[Button] = []
var _recent_box: VBoxContainer
# --- «Подключение…»
var connect_label: Label
var connect_back_button: Button
# --- лобби
var lobby_title: Label
var lobby_info: Label
var lobby_status: Label
var lobby_list: VBoxContainer
var ready_button: Button
var start_button: Button
var lobby_leave_button: Button
## Строки игроков лобби по порядку слотов: {peer, nick, ready, look} (тесты сверяют).
var lobby_rows: Array = []

var _center: CenterContainer = null
var _pending_addr: String = ""
var _net_wired: bool = false


func _build_net_screens() -> void:
	screens["main"] = main_page
	_build_host_screen()
	_build_browser_screen()
	_build_ip_screen()
	_build_connecting_screen()
	_build_lobby_screen()
	_build_load_screen()   # #132
	_build_campaign_screen()   # ADR-004
	for k in screens:
		(screens[k] as Control).visible = k == "main"
	Net.session_started.connect(_on_net_started)
	Net.connection_failed.connect(_on_net_failed)
	Net.session_ended.connect(_on_net_ended)
	Net.roster_changed.connect(_refresh_lobby)
	_net_wired = true
	if NetLobby.last_reason != "":
		status_label.text = "Сеть: " + NetLobby.last_reason
		NetLobby.last_reason = ""


func _unwire_net() -> void:
	if browser != null:
		browser.stop()
	if not _net_wired:
		return
	_net_wired = false
	Net.session_started.disconnect(_on_net_started)
	Net.connection_failed.disconnect(_on_net_failed)
	Net.session_ended.disconnect(_on_net_ended)
	Net.roster_changed.disconnect(_refresh_lobby)
	if lobby != null and is_instance_valid(lobby) and lobby.changed.is_connected(_refresh_lobby):
		lobby.changed.disconnect(_refresh_lobby)


func show_screen(screen: String) -> void:
	if not screens.has(screen):
		return
	if current_screen == "browser" and screen != "browser" and browser != null:
		browser.stop()
	current_screen = screen
	for k in screens:
		(screens[k] as Control).visible = k == screen
	if screen != "main":
		status_label.text = ""


func _net_page(title: String) -> VBoxContainer:
	var page: VBoxContainer = VBoxContainer.new()
	page.custom_minimum_size = Vector2(NET_W, 0)
	page.add_theme_constant_override("separation", 10)
	var t: Label = _label(title, 34, ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(t)
	_center.add_child(page)
	return page


func _field_row(page: VBoxContainer, caption: String, ctrl: Control) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l: Label = _label(caption, 19, Color(0.9, 0.93, 1.0))
	l.custom_minimum_size = Vector2(150, 0)
	row.add_child(l)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ctrl)
	page.add_child(row)


func _edit(placeholder: String) -> LineEdit:
	var e: LineEdit = LineEdit.new()
	e.placeholder_text = placeholder
	e.custom_minimum_size = Vector2(0, BUTTON_H)
	return e


func _buttons_row(page: VBoxContainer, list: Array) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	for b in list:
		(b as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	page.add_child(row)


func _back_button() -> Button:
	var b: Button = _button("Назад")
	b.pressed.connect(show_screen.bind("main"))
	return b


# ------------------------------------------------------------------ «СОЗДАТЬ ИГРУ»

func _build_host_screen() -> void:
	var page: VBoxContainer = _net_page("Создать игру")
	screens["host"] = page
	host_name_edit = _edit("Экспедиция <ник>")
	host_name_edit.max_length = NAME_MAX + 8
	_field_row(page, "Имя игры", host_name_edit)
	host_seed_edit = _edit("сид: случайный")
	_field_row(page, "Сид", host_seed_edit)
	var slots_row: HBoxContainer = HBoxContainer.new()
	slots_row.add_theme_constant_override("separation", 10)
	var group: ButtonGroup = ButtonGroup.new()
	for n in range(2, Balance.MP_MAX_PLAYERS + 1):
		var b: Button = _button(str(n))
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(set_slots.bind(n))
		slots_row.add_child(b)
		slot_buttons.append(b)
	_field_row(page, "Мест", slots_row)
	host_port_edit = _edit(str(Net.GAME_PORT))
	host_port_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_field_row(page, "Порт", host_port_edit)
	_build_host_load_row(page)   # #132: мир — новый или из сохранения
	host_mode_button = _button("")   # ADR-004: свободная игра или глава кампании
	host_mode_button.pressed.connect(cycle_host_mode)
	_field_row(page, "Режим", host_mode_button)
	host_error_label = _label("", 15, ERR_COLOR)
	host_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	host_error_label.custom_minimum_size = Vector2(NET_W, 22)
	page.add_child(host_error_label)
	host_ips_label = _label("", 16, DIM_COLOR)
	host_ips_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	host_ips_label.custom_minimum_size = Vector2(NET_W, 0)
	page.add_child(host_ips_label)
	host_create_button = _button("Создать")
	host_create_button.pressed.connect(create_game)
	_buttons_row(page, [_back_button(), host_create_button])


func show_host_form() -> void:
	if Net.nick_error(nick_edit.text) != "":
		return
	host_name_edit.text = ("Экспедиция " + profile.nick).substr(0, NAME_MAX)
	host_seed_edit.text = ""
	clear_host_load()   # #132
	set_host_mission("")   # ADR-004
	host_port_edit.text = str(profile.port)
	set_slots(Balance.MP_MAX_PLAYERS)
	host_error_label.text = ""
	var ips: PackedStringArray = LanDiscovery.private_ipv4()
	host_ips_label.text = ("Ваши адреса в локальной сети: " + ", ".join(ips)) if not ips.is_empty() \
			else "Адресов в локальной сети не видно — подключиться смогут только с этого компьютера"
	show_screen("host")


func set_slots(n: int) -> void:
	host_slots = clampi(n, 2, Balance.MP_MAX_PLAYERS)
	for b in slot_buttons:
		b.set_pressed_no_signal(int(b.text) == host_slots)


## Проверка формы хоста (чистая функция — её таблицу проверяет menu_test).
## Итог: {ok, error, name, seed (−1 — случайный), slots, port}.
static func host_form(name_text: String, seed_text: String, slots: int, port_text: String) -> Dictionary:
	var res: Dictionary = {"ok": false, "error": "", "name": "", "seed": -1, "slots": slots, "port": 0}
	var nm: String = name_text.strip_edges()
	if nm.is_empty():
		res["error"] = "Имя игры: пусто"
		return res
	if nm.length() > NAME_MAX:
		res["error"] = "Имя игры: длиннее %d символов" % NAME_MAX
		return res
	for i in nm.length():
		if nm.unicode_at(i) < 0x20:
			res["error"] = "Имя игры: недопустимый символ"
			return res
	if slots < 2 or slots > Balance.MP_MAX_PLAYERS:
		res["error"] = "Мест: от 2 до %d" % Balance.MP_MAX_PLAYERS
		return res
	var pt: String = port_text.strip_edges()
	var port: int = Net.GAME_PORT
	if pt != "":
		if not pt.is_valid_int():
			res["error"] = "Порт: нужно число"
			return res
		port = int(pt)
	if port < 1024 or port > 65535:
		res["error"] = "Порт: от 1024 до 65535"
		return res
	if port == Net.DISCOVERY_PORT:
		res["error"] = "Порт %d занят поиском игр — выберите другой" % Net.DISCOVERY_PORT
		return res
	var sd: int = int(session_for(seed_text, false)["seed"])
	if sd < -1 or (sd == -1 and seed_text.strip_edges() != ""):
		sd = sd & 0x7FFFFFFF        # клиентам нужен сид ≥ 0 (main.gd: --seed=)
	res["ok"] = true
	res["name"] = nm
	res["seed"] = sd
	res["port"] = port
	return res


## «Создать»: сервер, ответчик поиска и лобби хоста.
func create_game() -> void:
	if Net.nick_error(nick_edit.text) != "":
		return
	var f: Dictionary = host_form(host_name_edit.text, host_seed_edit.text, host_slots, host_port_edit.text)
	if not bool(f["ok"]):
		host_error_label.text = String(f["error"])
		return
	var sd: int = int(f["seed"]) if int(f["seed"]) >= 0 else int(_rng.randi() & 0x7FFFFFFF)
	if host_mission != "":
		sd = Campaign.SEED   # ADR-004: глава — на мире кампании
	profile.port = int(f["port"])
	profile.save_to(profile_path)
	Net.local_profile = profile.to_net()
	_use_lobby()
	if lobby.host(int(f["port"]), net_bind, sd, String(f["name"]), int(f["slots"]), discovery_port) != OK:
		host_error_label.text = "Не удалось создать игру: " + NetLobby.last_reason
		lobby.queue_free()
		lobby = null
		return
	if host_mission != "":   # ADR-004: глава кампании — main.gd строит её базу, клиентам — в приветствии
		Net.session["mission"] = host_mission
	elif host_load_slot != "":   # #132: при «Старт» хост грузит слот (main.gd → Save.load_net, MP-I)
		Net.session["load"] = host_load_slot
	show_screen("lobby")
	_refresh_lobby()


func _use_lobby() -> void:
	lobby = NetLobby.ensure(get_tree())
	if not lobby.changed.is_connected(_refresh_lobby):
		lobby.changed.connect(_refresh_lobby)


# ------------------------------------------------------------------ «НАЙТИ ИГРУ»

func _build_browser_screen() -> void:
	var page: VBoxContainer = _net_page("Найти игру")
	screens["browser"] = page
	var note: Label = _label("Игры в этой локальной сети (Wi-Fi). Серые — другая версия или нет мест.",
			16, DIM_COLOR)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(NET_W, 0)
	page.add_child(note)
	browser = ServerBrowser.new(NET_W)
	browser.join_requested.connect(func(ip: String, port: int) -> void:
			connect_to(ip, port, ip if port == Net.GAME_PORT else "%s:%d" % [ip, port]))
	page.add_child(browser)
	var refresh_b: Button = _button("Обновить")
	refresh_b.pressed.connect(func() -> void: browser.refresh())
	var by_ip: Button = _button("По IP")
	by_ip.pressed.connect(show_ip)
	_buttons_row(page, [_back_button(), refresh_b, by_ip])


func show_browser() -> void:
	if Net.nick_error(nick_edit.text) != "":
		return
	show_screen("browser")
	var err: Error = browser.start(discovery_port, net_bind, discovery_targets)
	if err != OK:
		status_label.text = "Поиск недоступен (%s) — подключитесь по IP" % error_string(err)


# ------------------------------------------------------------------ «ПОДКЛЮЧИТЬСЯ ПО IP»

func _build_ip_screen() -> void:
	var page: VBoxContainer = _net_page("Подключиться по IP")
	screens["ip"] = page
	ip_edit = _edit("192.168.1.20, 192.168.1.20:24642 или имя компьютера")
	ip_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
	ip_edit.text_submitted.connect(func(_t: String) -> void: connect_by_ip())
	page.add_child(ip_edit)
	ip_error_label = _label("", 15, ERR_COLOR)
	ip_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ip_error_label.custom_minimum_size = Vector2(NET_W, 22)
	page.add_child(ip_error_label)
	page.add_child(_label("Недавние адреса", 18, ACCENT))
	_recent_box = VBoxContainer.new()
	_recent_box.add_theme_constant_override("separation", 6)
	page.add_child(_recent_box)
	var hint: Label = _label("Адрес хоста виден на его экране лобби. Порт по умолчанию — %d." % Net.GAME_PORT,
			15, DIM_COLOR)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(NET_W, 0)
	page.add_child(hint)
	ip_connect_button = _button("Подключиться")
	ip_connect_button.pressed.connect(connect_by_ip)
	_buttons_row(page, [_back_button(), ip_connect_button])


func show_ip() -> void:
	if Net.nick_error(nick_edit.text) != "":
		return
	ip_error_label.text = ""
	if ip_edit.text.strip_edges() == "" and not profile.recent_ips.is_empty():
		ip_edit.text = profile.recent_ips[0]
	for b in recent_buttons:
		b.queue_free()
	recent_buttons.clear()
	for k in mini(RECENT_SHOWN, profile.recent_ips.size()):
		var addr: String = profile.recent_ips[k]
		var b: Button = _button(addr)
		b.pressed.connect(func() -> void:
				ip_edit.text = addr
				connect_by_ip())
		_recent_box.add_child(b)
		recent_buttons.append(b)
	if recent_buttons.is_empty():
		var none: Button = _button("пока нет")
		none.disabled = true
		_recent_box.add_child(none)
		recent_buttons.append(none)
	show_screen("ip")


## Разбор адреса «Подключиться по IP» (чистая функция — таблица в menu_test):
## IPv4[:порт] или имя хоста[:порт]. Итог: {ok, host, port, error}.
static func parse_address(text: String, default_port: int = Net.GAME_PORT) -> Dictionary:
	var res: Dictionary = {"ok": false, "host": "", "port": default_port, "error": ""}
	var s: String = text.strip_edges()
	if s.is_empty():
		res["error"] = "введите адрес"
		return res
	if s.count(":") > 1 or s.begins_with("["):
		res["error"] = "IPv6 не поддерживается — введите IPv4"
		return res
	var h: String = s
	var colon: int = s.find(":")
	if colon >= 0:
		h = s.substr(0, colon)
		var ps: String = s.substr(colon + 1)
		if not ps.is_valid_int() or ps.begins_with("+") or ps.begins_with("-") \
				or int(ps) < 1 or int(ps) > 65535:
			res["error"] = "порт — число от 1 до 65535"
			return res
		res["port"] = int(ps)
	if h.is_empty():
		res["error"] = "нет адреса перед «:»"
		return res
	if LanDiscovery.is_ipv4(h):
		res["ok"] = true
		res["host"] = h
		return res
	var numeric: bool = true
	for i in h.length():
		if not (h[i] == "." or h[i].is_valid_int()):
			numeric = false
			break
	if numeric:
		res["error"] = "неверный IPv4: нужно четыре числа 0–255 через точку"
		return res
	if not _valid_hostname(h):
		res["error"] = "недопустимый адрес «%s»" % h
		return res
	res["ok"] = true
	res["host"] = h.to_lower()
	return res


static func _valid_hostname(h: String) -> bool:
	if h.length() > 253:
		return false
	for label in h.split("."):
		if label.is_empty() or label.length() > 63 or label.begins_with("-") or label.ends_with("-"):
			return false
		for i in label.length():
			var u: int = label.unicode_at(i)
			if not ((u >= 0x30 and u <= 0x39) or (u >= 0x41 and u <= 0x5A) or (u >= 0x61 and u <= 0x7A)
					or u == 0x2D):
				return false
	return true


func connect_by_ip() -> void:
	var a: Dictionary = parse_address(ip_edit.text)
	if not bool(a["ok"]):
		ip_error_label.text = "Адрес: " + String(a["error"])
		return
	var host: String = String(a["host"])
	var ip: String = host
	if not LanDiscovery.is_ipv4(host):
		ip = IP.resolve_hostname(host, IP.TYPE_IPV4)
		if ip == "":
			ip_error_label.text = "Адрес: компьютер «%s» не найден" % host
			return
	var port: int = int(a["port"])
	connect_to(ip, port, host if port == Net.GAME_PORT else "%s:%d" % [host, port])


# ------------------------------------------------------------------ ПОДКЛЮЧЕНИЕ

func _build_connecting_screen() -> void:
	var page: VBoxContainer = _net_page("Подключение")
	screens["connecting"] = page
	connect_label = _label("", 20, Color(0.9, 0.93, 1.0))
	connect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	connect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	connect_label.custom_minimum_size = Vector2(NET_W, 80)
	page.add_child(connect_label)
	connect_back_button = _button("Отмена")
	connect_back_button.pressed.connect(leave_session)
	_buttons_row(page, [connect_back_button])


## Войти в игру ip:port; remember — что записать в «Недавние» при успехе.
func connect_to(ip: String, port: int, remember: String = "") -> void:
	if Net.nick_error(nick_edit.text) != "":
		return
	profile.save_to(profile_path)
	Net.local_profile = profile.to_net()
	_pending_addr = remember
	connect_label.add_theme_color_override("font_color", Color(0.9, 0.93, 1.0))
	connect_label.text = "Подключение к %s:%d…" % [ip, port]
	connect_back_button.text = "Отмена"
	show_screen("connecting")
	_use_lobby()
	if lobby.join(ip, port) != OK:
		_on_net_failed(NetLobby.last_reason)


func _on_net_started() -> void:
	if not Net.is_client():
		return
	if _pending_addr != "":
		profile.remember_ip(_pending_addr)
		profile.save_to(profile_path)
		_pending_addr = ""
	show_screen("lobby")
	_refresh_lobby()


func _on_net_failed(reason: String) -> void:
	_pending_addr = ""
	lobby = null
	connect_label.add_theme_color_override("font_color", ERR_COLOR)
	connect_label.text = "Ошибка: " + reason
	connect_back_button.text = "Назад"
	show_screen("connecting")


func _on_net_ended(reason: String) -> void:
	lobby = null
	show_screen("main")
	if reason != "":
		status_label.text = "Сеть: " + reason


## «Отмена» / «Выйти» / «Закрыть игру»: конец сессии, главный экран.
func leave_session() -> void:
	if Net.is_online():
		Net.leave()
	elif lobby != null and is_instance_valid(lobby):
		lobby.queue_free()
	lobby = null
	show_screen("main")


# ------------------------------------------------------------------ ЛОББИ

func _build_lobby_screen() -> void:
	var page: VBoxContainer = _net_page("Лобби")
	screens["lobby"] = page
	lobby_title = page.get_child(0) as Label
	lobby_info = _label("", 18, Color(1.0, 0.88, 0.55))
	lobby_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lobby_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_info.custom_minimum_size = Vector2(NET_W, 0)
	page.add_child(lobby_info)
	lobby_list = VBoxContainer.new()
	lobby_list.add_theme_constant_override("separation", 4)
	lobby_list.custom_minimum_size = Vector2(NET_W, 4 * 66.0)
	page.add_child(lobby_list)
	lobby_status = _label("", 16, DIM_COLOR)
	lobby_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lobby_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_status.custom_minimum_size = Vector2(NET_W, 22)
	page.add_child(lobby_status)
	lobby_leave_button = _button("Выйти")
	lobby_leave_button.pressed.connect(leave_session)
	ready_button = _button("Готов")
	ready_button.pressed.connect(toggle_ready)
	start_button = _button("Старт")
	start_button.pressed.connect(start_game)
	_buttons_row(page, [lobby_leave_button, ready_button, start_button])


func toggle_ready() -> void:
	if lobby != null and is_instance_valid(lobby):
		lobby.set_ready(not lobby.my_ready)


func start_game() -> void:
	if lobby != null and is_instance_valid(lobby) and lobby.start_game():
		_refresh_lobby()


func _refresh_lobby() -> void:
	if lobby == null or not is_instance_valid(lobby) or not Net.is_online():
		return
	var host: bool = Net.is_host()
	lobby_title.text = String(Net.session.get("session_name", "Лобби"))
	var port: int = int(Net.session.get("port", Net.GAME_PORT))
	if host:
		var ips: PackedStringArray = LanDiscovery.private_ipv4() if net_bind == "*" \
				else PackedStringArray([net_bind])
		var addrs: PackedStringArray = PackedStringArray()
		for ip in ips:
			addrs.append("%s:%d" % [ip, port] if port != Net.GAME_PORT else ip)
		lobby_info.text = ("Адрес для «По IP»: " + ", ".join(addrs)) if not addrs.is_empty() \
				else "Адресов в локальной сети нет — войти можно только с этого компьютера"
		if lobby.discovery_error != "":
			lobby_info.text += "\n" + lobby.discovery_error
	else:
		lobby_info.text = "Хост: %s:%d" % [String(Net.session.get("host_ip", "?")), port]
	# Игроки: превью вида, ник, готовность.
	for c in lobby_list.get_children():
		c.queue_free()
	lobby_rows.clear()
	var waiting: Array = []
	for e in Net.roster():
		var peer: int = int(e["peer"])
		var rdy: bool = lobby.is_ready(peer)
		lobby_rows.append({"peer": peer, "nick": String(e["nick"]), "ready": rdy, "look": int(e["look"])})
		lobby_list.add_child(_lobby_row(e, rdy))
		if not rdy:
			waiting.append(String(e["nick"]))
	var n: int = Net.peers.size()
	var cap: String = "%d/%d" % [n, Net.max_players] if host else "%d" % n
	lobby_leave_button.text = "Закрыть игру" if host else "Выйти"
	ready_button.visible = not host
	start_button.visible = host
	if host:
		start_button.disabled = not lobby.can_start()
		if lobby.is_entering():
			lobby_status.text = "Мир строится…"
		elif waiting.is_empty():
			lobby_status.text = "Игроков %s. Все готовы — можно начинать (войти можно и после старта)" % cap
		else:
			lobby_status.text = "Игроков %s. Ждём готовности: %s" % [cap, ", ".join(waiting)]
	else:
		ready_button.text = "Не готов" if lobby.my_ready else "Готов"
		lobby_status.text = "Игроков %s. %s" % [cap, "Ждём, когда хост начнёт" if lobby.my_ready
				else "Нажмите «Готов», когда будете готовы"]


func _lobby_row(e: Dictionary, rdy: bool) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.custom_minimum_size = Vector2(NET_W, 62)
	var stage: Control = Control.new()
	stage.custom_minimum_size = Vector2(56, 62)
	var pv: AvatarPreview = AvatarPreview.new()
	pv.look = int(e["look"]) & 0xFFFF
	pv.scale = Vector2(LOBBY_PREVIEW_SCALE, LOBBY_PREVIEW_SCALE)
	pv.position = Vector2(28, 62 - Avatar.SIZE.y * 0.5 * LOBBY_PREVIEW_SCALE - 4.0)
	stage.add_child(pv)
	row.add_child(stage)
	var peer: int = int(e["peer"])
	var tag: String = ""
	if peer == 1:
		tag = "  (хост)"
	elif peer == Net.my_id():
		tag = "  (вы)"
	var nl: Label = _label(String(e["nick"]) + tag, 22, Color(0.92, 0.95, 1.0))
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(nl)
	var rl: Label = _label("готов" if rdy else "ждём", 20, READY_COLOR if rdy else DIM_COLOR)
	rl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(rl)
	return row


# ------------------------------------------------------------------ ЗАГРУЗКА (#132)
## «Загрузить» рядом с «Одиночной игрой» и «Мир: Из сохранения…» в «Создать игру» ведут
## на один экран «load»: сохранения (Save.list_saves — новые сверху) кнопками в две
## строки — тип и дата; сид, смена, игроки. Тап выбирает, «Загрузить» / «Выбрать» —
## внизу. Нет сохранений — обе кнопки серые; битый файл — серая строка с причиной.
##   Одиночная: Net.session = {mode: single, seed: сид файла, hardcore: false,
##     load: слот} → main.gd строит мир по сиду и грузит слот (Save.load_game);
##     ключ load снимается — перезапуск после финала начинает заново.
##   «Создать игру»: сид формы — из файла (поле закрыто), после создания лобби
##     Net.session["load"] = слот (крюк MP-I) — при «Старт» хост грузит его
##     (Save.load_net); «Новый мир» — отказаться.

const LOAD_SINGLE: String = "single"
const LOAD_HOST: String = "host"
## Высота строки сохранения (две строки текста), px.
const SAVE_ROW_H: float = 66.0
## Строк сохранений без прокрутки.
const SAVE_ROWS_SHOWN: int = 5

var load_button: Button
var host_load_button: Button
var host_load_label: Label
## Слот, выбранный для «Создать игру» ("" — новый мир).
var host_load_slot: String = ""
## Для кого экран «load»: LOAD_SINGLE или LOAD_HOST.
var load_for: String = LOAD_SINGLE
## Последний список (Save.slot_info по порядку строк) и выбранная строка (−1 — нет).
var saves: Array = []
var save_buttons: Array[Button] = []
var selected_save: int = -1
var load_title: Label
var load_list: VBoxContainer
var load_hint_label: Label
var load_go_button: Button


func _build_load_screen() -> void:
	var page: VBoxContainer = _net_page("Загрузить")
	screens["load"] = page
	load_title = page.get_child(0) as Label
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(NET_W, SAVE_ROWS_SHOWN * (SAVE_ROW_H + 6.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	load_list = VBoxContainer.new()
	load_list.add_theme_constant_override("separation", 6)
	load_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(load_list)
	load_hint_label = _label("", 16, DIM_COLOR)
	load_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	load_hint_label.custom_minimum_size = Vector2(NET_W, 22)
	page.add_child(load_hint_label)
	var back: Button = _button("Назад")
	back.pressed.connect(func() -> void: show_screen("host" if load_for == LOAD_HOST else "main"))
	load_go_button = _button("Загрузить")
	load_go_button.pressed.connect(load_selected)
	_buttons_row(page, [back, load_go_button])


## «Создать игру»: строка «Мир» — подпись и кнопка «Из сохранения…» / «Новый мир».
func _build_host_load_row(page: VBoxContainer) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	host_load_label = _label("новый", 17, Color(0.9, 0.93, 1.0))
	host_load_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_load_label.clip_text = true
	host_load_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(host_load_label)
	host_load_button = _button("Из сохранения…")
	host_load_button.custom_minimum_size = Vector2(220, BUTTON_H)
	host_load_button.pressed.connect(func() -> void:
			if host_load_slot != "":
				clear_host_load()
			else:
				show_load(LOAD_HOST))
	row.add_child(host_load_button)
	_field_row(page, "Мир", row)


## Серые ли «Загрузить» и «Из сохранения…»: есть ли файлы (без чтения) и ник.
func _refresh_load_buttons() -> void:
	var has_saves: bool = not Save.slots().is_empty()
	var nick_bad: bool = nick_edit != null and Net.nick_error(nick_edit.text) != ""
	if continue_button != null:
		continue_button.disabled = nick_bad   # #119
	if load_button != null:
		load_button.disabled = nick_bad or not has_saves
		load_button.tooltip_text = "Загрузить сохранение" if has_saves else "Сохранений нет"
	if host_load_button != null:
		host_load_button.disabled = not has_saves and host_load_slot == ""


## Экран «load» для одиночной игры (LOAD_SINGLE) или формы хоста (LOAD_HOST).
func show_load(mode: String) -> void:
	if Net.nick_error(nick_edit.text) != "":
		return
	load_for = mode
	load_title.text = "Загрузить" if mode == LOAD_SINGLE else "Сохранение для сетевой игры"
	load_go_button.text = "Загрузить" if mode == LOAD_SINGLE else "Выбрать"
	refresh_saves()
	show_screen("load")


## Перечитать сохранения и построить строки; выбрана первая читаемая.
func refresh_saves() -> void:
	saves = Save.list_saves()
	for b in save_buttons:
		b.queue_free()
	save_buttons.clear()
	var group: ButtonGroup = ButtonGroup.new()
	selected_save = -1
	for i in saves.size():
		var info: Dictionary = saves[i]
		var b: Button = _button(save_row_text(info))
		b.custom_minimum_size = Vector2(0, SAVE_ROW_H)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 17)
		b.toggle_mode = true
		b.button_group = group
		b.disabled = not bool(info["ok"])
		b.pressed.connect(select_save.bind(i))
		load_list.add_child(b)
		save_buttons.append(b)
		if selected_save < 0 and bool(info["ok"]):
			selected_save = i
	if selected_save >= 0:
		save_buttons[selected_save].set_pressed_no_signal(true)
	_refresh_load_buttons()
	load_go_button.disabled = selected_save < 0
	if saves.is_empty():
		load_hint_label.text = "Сохранений нет. В игре F5 — сохранить."
	elif selected_save < 0:
		load_hint_label.text = "Ни одно сохранение не читается."
	else:
		load_hint_label.text = "Тап по строке — выбрать."


func select_save(i: int) -> void:
	if i < 0 or i >= saves.size() or not bool(saves[i]["ok"]):
		return
	selected_save = i
	save_buttons[i].set_pressed_no_signal(true)
	load_go_button.disabled = false


## «Загрузить» / «Выбрать» внизу экрана.
func load_selected() -> void:
	if selected_save < 0 or selected_save >= saves.size():
		return
	var info: Dictionary = saves[selected_save]
	if load_for == LOAD_HOST:
		pick_host_load(info)
		show_screen("host")
		return
	_start_from_save(info)


## Одиночная игра из сохранения: «Загрузить» → «Загрузить» и «Продолжить» (#119).
func _start_from_save(info: Dictionary) -> void:
	if Net.nick_error(nick_edit.text) != "":
		return
	profile.save_to(profile_path)
	Net.local_profile = profile.to_net()
	Net.session = load_session(info)
	_leave()
	get_tree().change_scene_to_file(GAME_SCENE)


## «Создать игру» из сохранения: сид — из файла (поле закрыто), слот — в create_game.
func pick_host_load(info: Dictionary) -> void:
	set_host_mission("")   # ADR-004: из сохранения — свободная игра
	host_load_slot = String(info["slot"])
	host_seed_edit.text = str(int(info["seed"]))
	host_seed_edit.editable = false
	host_load_label.text = save_row_text(info).get_slice("\n", 0)
	host_load_label.tooltip_text = save_row_text(info)
	host_load_button.text = "Новый мир"
	host_load_button.disabled = false


func clear_host_load() -> void:
	host_load_slot = ""
	if host_seed_edit != null and not host_seed_edit.editable:
		host_seed_edit.text = ""
		host_seed_edit.editable = true
	if host_load_label != null:
		host_load_label.text = "новый"
		host_load_label.tooltip_text = ""
		host_load_button.text = "Из сохранения…"
	_refresh_load_buttons()


## Сессия одиночной игры из сохранения (формат Net.session; main.gd → _menu_load).
static func load_session(info: Dictionary) -> Dictionary:
	return {"mode": "single", "seed": int(info["seed"]), "hardcore": false, "load": String(info["slot"])}


## Строка списка: тип и дата; сид, смена, игроки (битый файл — причина).
static func save_row_text(info: Dictionary) -> String:
	var kind: String = "Одиночная"
	if bool(info.get("net", false)):
		kind = "Сетевая «%s»" % String(info["name"]) if String(info.get("name", "")) != "" else "Сетевая"
	var head: String = "%s · %s" % [kind, format_time(int(info.get("time", 0)))]
	if not bool(info.get("ok", false)):
		return "%s\nне читается: %s" % [head, String(info.get("error", ""))]
	var who: String = "игрок 1"
	if bool(info.get("net", false)):
		var nicks: PackedStringArray = info.get("nicks", PackedStringArray())
		who = "игроков %d: %s" % [int(info["players"]), ", ".join(nicks)]
	return "%s\nсид %d · смена %d · %s" % [head, int(info["seed"]), int(info["day"]), who]


## Время файла (unix, UTC) по местным часам: «дд.мм.гггг чч:мм».
static func format_time(unix: int) -> String:
	if unix <= 0:
		return "дата неизвестна"
	var bias: int = int(Time.get_time_zone_from_system().get("bias", 0))
	var t: Dictionary = Time.get_datetime_dict_from_unix_time(unix + bias * 60)
	return "%02d.%02d.%04d %02d:%02d" % [int(t["day"]), int(t["month"]), int(t["year"]),
			int(t["hour"]), int(t["minute"])]


# ------------------------------------------------------------------ «ПРОДОЛЖИТЬ» (#119)
## Последний одиночный забег одним тапом — без списка: Save.latest_single (самый новый по
## времени файла читаемый не сетевой слот; автосохранение «Сохранить и выйти в меню»
## пишется в слот F5 — его и берём). Путь тот же, что у «Загрузить» → строка →
## «Загрузить» (load_session → main.gd _menu_load). Продолжать нечего — кнопки нет.
## «Загрузить» остаётся для выбора слота; сетевые сохранения — «Создать игру» →
## «Из сохранения…».

var continue_button: Button
## Что продолжит кнопка (Save.slot_info; {} — нечего).
var continue_info: Dictionary = {}


func refresh_continue() -> void:
	continue_info = Save.latest_single()
	continue_button.visible = not continue_info.is_empty()
	if not continue_info.is_empty():
		continue_button.text = "Продолжить · смена %d" % int(continue_info["day"])
		continue_button.tooltip_text = save_row_text(continue_info)
	continue_button.disabled = nick_edit != null and Net.nick_error(nick_edit.text) != ""


func continue_run() -> void:
	if not continue_info.is_empty():
		_start_from_save(continue_info)


# ------------------------------------------------------------------ КАМПАНИЯ (ADR-004)
## «Кампания» — экран глав: строка на главу (номер, название, пройдена / закрыта),
## под списком — завязка и чему учит выбранная, «Начать главу». Глава открыта, когда
## пройдена предыдущая (Profile.campaign_done, Campaign.unlocked). Старт —
## Net.session = {mode: single, seed: Campaign.SEED, hardcore: false, mission: id}.
## В «Создать игру» строка «Режим» листает «Свободная игра» и открытые главы: глава
## кладётся в Net.session["mission"], сид — Campaign.SEED (сид из формы не нужен).

var campaign_button: Button
var campaign_rows: Array[Button] = []
var campaign_info: Label
var campaign_go: Button
## Выбранная глава на экране «Кампания» ("" — нет открытых).
var campaign_pick: String = ""
var host_mode_button: Button
## Глава сетевой игры ("" — свободная игра).
var host_mission: String = ""


func _build_campaign_screen() -> void:
	var page: VBoxContainer = _net_page("Кампания")
	screens["campaign"] = page
	var sub: Label = _label("Пять глав на одном мире: готовая база, цель и короткая история. "
			+ "Каждая знакомит с частью механик. Играть можно и по сети: «Создать игру» → «Режим».",
			16, DIM_COLOR)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(NET_W, 0)
	page.add_child(sub)
	var group: ButtonGroup = ButtonGroup.new()
	for id in Campaign.CHAPTERS:
		var b: Button = _button("")
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(pick_chapter.bind(id))
		campaign_rows.append(b)
		page.add_child(b)
	campaign_info = _label("", 16, Color(0.9, 0.93, 1.0))
	campaign_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	campaign_info.custom_minimum_size = Vector2(NET_W, 64)
	page.add_child(campaign_info)
	campaign_go = _button("Начать главу")
	campaign_go.pressed.connect(start_campaign)
	_buttons_row(page, [_back_button(), campaign_go])


func show_campaign() -> void:
	if Net.nick_error(nick_edit.text) != "":
		return
	refresh_campaign()
	show_screen("campaign")


## Строки глав по профилю; выбрана первая непройденная открытая (всё пройдено — последняя).
func refresh_campaign() -> void:
	var done: PackedStringArray = Profile.load_or_create(profile_path).campaign_done
	profile.campaign_done = done
	var pick: String = ""
	for i in Campaign.CHAPTERS.size():
		var id: String = Campaign.CHAPTERS[i]
		var info: Dictionary = Campaign.info(id)
		var open: bool = Campaign.unlocked(id, done)
		var mark: String = " — пройдена" if done.has(id) else ("" if open else " — закрыта")
		campaign_rows[i].text = "%d. %s%s" % [int(info["chapter"]), String(info["title"]), mark]
		campaign_rows[i].disabled = not open
		if open and (pick == "" or not done.has(id) and done.has(pick)):
			pick = id
	pick_chapter(pick)


func pick_chapter(id: String) -> void:
	campaign_pick = id
	var i: int = Campaign.CHAPTERS.find(id)
	for k in campaign_rows.size():
		campaign_rows[k].set_pressed_no_signal(k == i)
	if i < 0:
		campaign_info.text = ""
		campaign_go.disabled = true
		return
	var info: Dictionary = Campaign.info(id)
	campaign_info.text = "%s
Чему учит: %s." % [String(info["brief"]), String(info["teaches"])]
	campaign_go.disabled = false


func start_campaign() -> void:
	if campaign_pick == "" or Net.nick_error(nick_edit.text) != "":
		return
	profile.save_to(profile_path)
	Net.local_profile = profile.to_net()
	Net.session = campaign_session(campaign_pick)
	_leave()
	get_tree().change_scene_to_file(GAME_SCENE)


## Сессия главы кампании для main.gd (формат Net.session).
static func campaign_session(id: String) -> Dictionary:
	return {"mode": "single", "seed": Campaign.SEED, "hardcore": false, "mission": id}


## «Режим» в «Создать игру»: свободная игра → открытые главы по кругу.
func cycle_host_mode() -> void:
	var done: PackedStringArray = Profile.load_or_create(profile_path).campaign_done
	var list: Array[String] = [""]
	for id in Campaign.CHAPTERS:
		if Campaign.unlocked(id, done):
			list.append(id)
	set_host_mission(list[(list.find(host_mission) + 1) % list.size()])


func set_host_mission(id: String) -> void:
	host_mission = id if Campaign.has(id) else ""
	if host_mission == "":
		host_mode_button.text = "Свободная игра"
	else:
		var info: Dictionary = Campaign.info(host_mission)
		host_mode_button.text = "Кампания: %d. %s" % [int(info["chapter"]), String(info["title"])]
	if host_mission != "":
		clear_host_load()   # глава начинается с готовой базы — сохранение не нужно
		host_seed_edit.text = str(Campaign.SEED)
		host_seed_edit.editable = false
	elif not host_seed_edit.editable and host_load_slot == "":
		host_seed_edit.text = ""
		host_seed_edit.editable = true
