class_name PauseMenu
extends CanvasLayer
## Пауза в забеге (#119): ESC (на телефоне — кнопка «II» TouchControls) открывает панель
## «Продолжить», «Сохранить», «Сохранить и выйти в меню», «Выход из игры». ESC сначала
## закрывает инвентарь или журнал (UI._input) и только потом открывает паузу; в паузе
## ESC — «Продолжить» (из предупреждения — назад к пунктам).
##
## Одиночная игра: дерево на паузе (мир, Game, Threat не тикают — ночь не наступает),
## панель работает в паузе (PROCESS_MODE_ALWAYS). Сетевая (ADR-002): мир не
## останавливается — у товарищей он идёт дальше; панель поверх, ввод у мира забран
## (UI.blocking — у клиента это бит окна в пакете ввода, прокси хоста стоит, как при
## открытом инвентаре). Сетевая схема не меняется.
##
## «Сохранить» — UI.quick_save (то же, что F5: слот Save.slot, те же правила).
## Автосохранение при выходе в меню пишется туда же, куда F5, — «Продолжить» в меню
## берёт его. Нельзя сохраниться (хардкор; Save.save_blocker: клиент, герой погиб, забег
## окончен) — «Сохранить» серая с причиной, а выход — «Выйти в меню» через предупреждение
## «забег не сохранён». Клиент выходит без предупреждения: его героя хранит хост
## (парковка по uid, MP-I) — «Отключиться и выйти в меню».
## Сам выход — main.gd exit_to_menu(): клиент отключается, хост заканчивает сессию.
##
## Слой — над HUD (UI, 10), сенсорными кнопками (15) и экраном финала (20).

const LAYER: int = 25
## Ширина колонки кнопок и высота кнопки, px при 1280×720 (палец попадает, как в меню).
const COL_W: float = 420.0
const BUTTON_H: float = MainMenu.BUTTON_H
const ACCENT: Color = MainMenu.ACCENT
const DIM: Color = Color(0.72, 0.78, 0.88)
const WARN: Color = Color(1.0, 0.72, 0.45)
const OK_COLOR: Color = Color(0.6, 1.0, 0.75)

const T_SAVE_EXIT: String = "Сохранить и выйти в меню"
const T_EXIT: String = "Выйти в меню"
const T_LEAVE: String = "Отключиться и выйти в меню"
const NOT_SAVED: String = "Забег не сохранён"

## Как ведёт себя кнопка выхода в меню (refresh): сохранить и выйти, выйти через
## предупреждение, отключиться (клиент).
enum Exit { SAVE, CONFIRM, LEAVE }

var root: Control
var title_label: Label
var hint_label: Label
var status_label: Label
var continue_button: Button
var save_button: Button
var exit_button: Button
var quit_button: Button
## Предупреждение «забег не сохранён»: подпись и кнопки.
var confirm_box: VBoxContainer
var confirm_label: Label
var confirm_exit_button: Button
var confirm_back_button: Button
var _items: VBoxContainer

var exit_mode: int = Exit.SAVE
## Дерево поставили на паузу мы (одиночная игра) — мы и снимем.
var paused_tree: bool = false

## Открыта / закрыта (тесты, TouchControls).
signal opened
signal closed


func _ready() -> void:
	layer = LAYER
	name = "PauseMenu"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false
	set_process(false)


func is_open() -> bool:
	return visible


## Можно ли сейчас поставить паузу: текущая сцена — забег (main.gd) с героем.
func can_pause() -> bool:
	var sc: Node = get_tree().current_scene
	if sc == null or not sc.has_method("exit_to_menu"):
		return false
	var p = sc.get("player")
	return p != null and is_instance_valid(p)


func open() -> void:
	if visible or not can_pause():
		return
	Save.close_windows()   # инвентарь и журнал — прочь (предмет «в руке» — в инвентарь)
	if not Net.is_online():   # одиночная: мир стоит; в сети он идёт у всех
		paused_tree = not get_tree().paused
		get_tree().paused = true
	status_label.text = ""
	refresh()
	_show_items()
	visible = true
	set_process(true)
	continue_button.grab_focus()
	opened.emit()


## Закрыть панель. unpause = false — сцена уже уходит (меню само решает о паузе дерева).
func close(unpause: bool = true) -> void:
	if not visible:
		return
	visible = false
	set_process(false)
	if paused_tree and unpause:
		get_tree().paused = false
	paused_tree = false
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


## Пункты по режиму: можно ли сохраниться, хардкор, сеть.
func refresh() -> void:
	var why: String = save_blocked()
	save_button.disabled = why != ""
	save_button.tooltip_text = why
	if Net.is_client():
		exit_mode = Exit.LEAVE
		exit_button.text = T_LEAVE
	elif why != "":
		exit_mode = Exit.CONFIRM
		exit_button.text = T_EXIT
	else:
		exit_mode = Exit.SAVE
		exit_button.text = T_SAVE_EXIT
	var lines: PackedStringArray = PackedStringArray()
	if Net.is_online():
		lines.append("Сетевая игра: мир не остановлен — товарищи играют дальше.")
		if Net.is_host():
			lines.append("Выход в меню закончит игру для всех.")
	if why != "":
		lines.append("Сохранить нельзя: %s." % why)
	hint_label.text = "\n".join(lines)
	title_label.text = "ПАУЗА" if not Net.is_online() else "МЕНЮ"


## Почему нельзя сохраниться ("" — можно): хардкор и Save.save_blocker.
func save_blocked() -> String:
	if UI.hardcore():
		return "хардкор — сохранений нет"
	return Save.save_blocker()


# ------------------------------------------------------------------ ДЕЙСТВИЯ

## «Сохранить»: как F5. Панель остаётся открытой.
func save_run() -> bool:
	if save_blocked() != "":
		return false
	var ok: bool = UI.quick_save()
	if ok:
		status_label.text = "Забег сохранён."
		status_label.add_theme_color_override("font_color", OK_COLOR)
	else:
		status_label.text = "Не сохранено: %s" % (Save.last_error if Save.last_error != "" else save_blocked())
		status_label.add_theme_color_override("font_color", WARN)
	return ok


## Кнопка выхода в меню: сохранить и выйти, предупредить или отключиться.
func exit_pressed() -> void:
	refresh()
	match exit_mode:
		Exit.SAVE:
			if save_run():
				exit_to_menu()
		Exit.CONFIRM:
			_show_confirm()
		Exit.LEAVE:
			exit_to_menu()


## Выйти в меню без сохранения (после предупреждения или у клиента).
func exit_to_menu() -> void:
	var sc: Node = get_tree().current_scene
	close(false)
	if sc != null and sc.has_method("exit_to_menu"):
		sc.exit_to_menu()


func quit_game() -> void:
	get_tree().quit()


# ------------------------------------------------------------------ ВВОД

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		if confirm_box.visible:
			_show_items()
		else:
			close()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	# Сцена ушла без нас (хост закрыл игру, финал → R): панель — прочь, паузу дерева
	# решает новая сцена.
	if visible and not can_pause():
		close(false)


# ------------------------------------------------------------------ ВЁРСТКА

func _build() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP   # клики мимо кнопок — не в мир
	root.theme = MainMenu.make_theme()
	add_child(root)
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var page: VBoxContainer = VBoxContainer.new()
	page.custom_minimum_size = Vector2(COL_W, 0)
	page.add_theme_constant_override("separation", 10)
	center.add_child(page)

	title_label = _label("ПАУЗА", 40, ACCENT)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(title_label)
	hint_label = _label("", 16, DIM)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.custom_minimum_size = Vector2(COL_W, 0)
	page.add_child(hint_label)

	_items = VBoxContainer.new()
	_items.add_theme_constant_override("separation", 8)
	page.add_child(_items)
	continue_button = _button("Продолжить")
	continue_button.pressed.connect(close.bind(true))
	_items.add_child(continue_button)
	save_button = _button("Сохранить")
	save_button.pressed.connect(func() -> void: save_run())
	_items.add_child(save_button)
	exit_button = _button(T_SAVE_EXIT)
	exit_button.pressed.connect(exit_pressed)
	_items.add_child(exit_button)
	quit_button = _button("Выход из игры")
	quit_button.pressed.connect(quit_game)
	_items.add_child(quit_button)

	confirm_box = VBoxContainer.new()
	confirm_box.add_theme_constant_override("separation", 8)
	page.add_child(confirm_box)
	confirm_label = _label("", 18, WARN)
	confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_label.custom_minimum_size = Vector2(COL_W, 0)
	confirm_box.add_child(confirm_label)
	confirm_exit_button = _button("Выйти без сохранения")
	confirm_exit_button.pressed.connect(exit_to_menu)
	confirm_box.add_child(confirm_exit_button)
	confirm_back_button = _button("Назад")
	confirm_back_button.pressed.connect(_show_items)
	confirm_box.add_child(confirm_back_button)

	status_label = _label("", 16, OK_COLOR)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(COL_W, 22)
	page.add_child(status_label)


func _show_items() -> void:
	_items.visible = true
	confirm_box.visible = false
	if visible:
		continue_button.grab_focus()


func _show_confirm() -> void:
	var why: String = save_blocked()
	confirm_label.text = "%s%s. Выйти в меню?" % [NOT_SAVED, (" (%s)" % why) if why != "" else ""]
	_items.visible = false
	confirm_box.visible = true
	confirm_back_button.grab_focus()


func _label(text: String, font_size: int, col: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	return l


func _button(text: String) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(COL_W, BUTTON_H)
	b.focus_mode = Control.FOCUS_ALL
	return b
