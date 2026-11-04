extends CanvasLayer
## Автозагрузка интерфейса: HUD, окно инвентаря, журнал (J), пауза (ESC, #119),
## проброс эффектов в мир. Телефон (#149): системная «Назад» Android — как ESC
## (go_back; само приложение не закрывается: application/config/quit_on_go_back = false),
## свернули приложение — пауза и автосохранение (app_paused).

var hud: HUD
var panel: InventoryPanel
var journal: JournalPanel
var pause: PauseMenu
var world_fx: WorldFX = null
var player: Player = null
## Включено сенсорное управление (TouchControls.set_enabled): подсказки — про тапы.
var touch_on: bool = false

# ------------------------------------------------------------- РАЗМЕР ИНТЕРФЕЙСА (#159)
## Размеры шрифтов интерфейса, логические px слоя UI. Меньше FONT.small в игре нет:
## вшитые числа в draw_string и _text запрещены (tools/ui_scale_test.gd).
const FONT: Dictionary = {"small": 14, "body": 18, "title": 28}
## Доступные коэффициенты «Размера интерфейса» (ADR-005 § 8.1).
const SCALES: Array[float] = [1.0, 1.5, 2.0, 2.5]
## Основной текст (кегль FONT.body) не мельче столько мм: телефон и монитор.
const BODY_MM_PHONE: float = 4.0
const BODY_MM_PC: float = 3.0
## Экран с dpi не выше — монитор: умолчание 100 %.
const PC_DPI: int = 110
## Запас по краям панели при подгонке под экран, px.
const PANEL_MARGIN: float = 20.0

## Коэффициент интерфейса. Это scale слоёв UI; мир (камера, ViewZoom) от него не зависит.
var ui_scale: float = 1.0
## Коэффициент сменили (меню, профиль): раскладка пересчитана.
signal ui_scale_changed


## Логических px в миллиметре: dpi экрана, окно в физических px, холст (viewport) — как
## в TouchControls._scale.
static func px_per_mm(dpi: int, win: Vector2, vp: Vector2) -> float:
	if dpi <= 0 or win.y <= 0.0 or vp.y <= 0.0:
		return 0.0
	return float(dpi) / 25.4 * vp.y / win.y


## Кегль font_px при коэффициенте s на экране с px_per_mm, мм.
static func size_mm(font_px: float, s: float, ppm: float) -> float:
	return font_px * s / ppm if ppm > 0.0 else 0.0


## Умолчание от экрана (первый запуск): наименьший коэффициент, при котором FONT.body не
## мельче BODY_MM_PHONE; монитор (dpi ≤ PC_DPI) и неизвестный dpi — 1.0.
static func default_scale(dpi: int, win: Vector2, vp: Vector2) -> float:
	var ppm: float = px_per_mm(dpi, win, vp)
	if ppm <= 0.0 or dpi <= PC_DPI:
		return 1.0
	for s in SCALES:
		if size_mm(float(FONT["body"]), s, ppm) >= BODY_MM_PHONE:
			return s
	return SCALES[SCALES.size() - 1]


## Ближайший доступный коэффициент (битое значение из профиля → 1.0).
static func snap_scale(v: float) -> float:
	var best: float = 1.0
	var bd: float = INF
	for s in SCALES:
		if absf(s - v) < bd:
			bd = absf(s - v)
			best = s
	return best


## Следующий коэффициент по кругу (кнопка в меню).
static func next_scale(v: float) -> float:
	var i: int = SCALES.find(snap_scale(v))
	return SCALES[(i + 1) % SCALES.size()]


static func scale_text(v: float) -> String:
	return "%d %%" % int(roundf(v * 100.0))


## Логический размер холста слоя UI: холст игры, поделённый на коэффициент.
func logical_size() -> Vector2:
	return get_viewport().get_visible_rect().size / ui_scale


## Коэффициент панели: не больше ui_scale и так, чтобы панель размера design целиком
## влезала в экран. vp — холст (по умолчанию холст игры; тест подставляет эмулированный).
func panel_scale(design: Vector2, vp: Vector2 = Vector2.ZERO) -> float:
	if vp == Vector2.ZERO:
		vp = get_viewport().get_visible_rect().size
	return maxf(0.1, minf(ui_scale, minf((vp.x - 2.0 * PANEL_MARGIN) / design.x,
			(vp.y - PANEL_MARGIN) / design.y)))


## Поставить Control слоя UI на весь экран, сжав его в f раз относительно слоя
## (панель, которой не хватает места при большом коэффициенте): size — логический,
## чтобы Control, уменьшенный на f, всё равно заполнял холст.
func place_full(c: Control, f: float = 1.0) -> void:
	c.set_anchors_preset(Control.PRESET_TOP_LEFT)
	c.scale = Vector2.ONE * f
	c.position = Vector2.ZERO
	c.size = logical_size() / f


## Задать коэффициент (меню, профиль) и сразу применить. save — записать в профиль.
func set_ui_scale(v: float, save: bool = true) -> void:
	ui_scale = snap_scale(v)
	if save:
		Profile.write_ui_scale(ui_scale)
	_apply_scale()
	ui_scale_changed.emit()


## Применить коэффициент: scale слоя, размер HUD и подгонка панелей и паузы.
func _apply_scale() -> void:
	if hud == null:
		return
	scale = Vector2.ONE * ui_scale
	place_full(hud)
	place_full(panel, panel_scale(InventoryPanel.PANEL) / ui_scale)
	place_full(journal, panel_scale(Vector2(JournalPanel.W, JournalPanel.H)) / ui_scale)
	pause.apply_scale(panel_scale(Vector2(PauseMenu.COL_W + 40.0, PauseMenu.DESIGN_H)))


## Коэффициент при запуске: из профиля; поля нет (первый запуск) — от экрана, и записать.
func _initial_scale() -> float:
	var saved: float = Profile.read_ui_scale()
	if saved > 0.0:
		return snap_scale(saved)
	var s: float = default_scale(DisplayServer.screen_get_dpi(), Vector2(get_window().size),
			get_viewport().get_visible_rect().size)
	Profile.write_ui_scale(s)
	return s


func _ready() -> void:
	layer = 10
	ui_scale = _initial_scale()
	hud = HUD.new()
	add_child(hud)
	panel = InventoryPanel.new()
	add_child(panel)
	journal = JournalPanel.new()
	add_child(journal)
	pause = PauseMenu.new()   # #119: свой CanvasLayer, работает и при паузе дерева
	add_child(pause)
	Game.notification.connect(_on_notification)
	get_viewport().size_changed.connect(_apply_scale)
	_apply_scale()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		go_back()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		app_paused()


## «Назад» Android в забеге (#149) — как ESC: открытое окно закрыть, иначе пауза; в паузе —
## назад из предупреждения или «Продолжить». В меню «Назад» ведёт MainMenu.go_back.
func go_back() -> void:
	if pause.visible:
		pause.back()
	elif panel.visible or journal.visible:
		panel.close()
		journal.close()
	elif pause.can_pause():
		pause.open()


## Приложение свернули (#149): Android может выгрузить его из памяти, и забег пропал бы.
## Пауза (одиночная игра — мир стоит) и сохранение в слот F5, если сейчас можно.
func app_paused() -> void:
	if not pause.can_pause():
		return
	pause.open()
	if pause.save_blocked() == "":
		pause.save_run()


func bind(p: Player) -> void:
	player = p
	hud.player = p
	panel.player = p


func _input(event: InputEvent) -> void:
	if pause.visible:
		return   # пауза (#119) забирает клавиши; ESC в ней ловит сама панель
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event
		if k.keycode == KEY_I or k.keycode == KEY_TAB:
			toggle_inventory()
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_J:
			toggle_journal()
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_ESCAPE and (panel.visible or journal.visible):
			panel.close()
			journal.close()
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_ESCAPE and pause.can_pause():   # окон нет — пауза (#119)
			pause.open()
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_P and world_fx:
			world_fx.show_power = not world_fx.show_power
		elif k.keycode == KEY_F5:
			quick_save()
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_F9:
			quick_load()
			get_viewport().set_input_as_handled()


# ------------------------------------------------------------- СОХРАНЕНИЕ (#37)
## F5 — сохранить забег, F9 — загрузить (Save, слот Save.slot). В --hardcore
## обе клавиши молчат: пермасмерть с загрузкой — уже не пермасмерть.

## Забег сохранён / загружен по клавише (сразу после операции, в том же кадре).
signal run_saved
signal run_loaded


func quick_save() -> bool:
	if hardcore():
		Game.notify("Хардкор: сохранений нет.", Color(1.0, 0.6, 0.4))
		return false
	var why: String = Save.save_blocker()
	if why != "":
		Game.notify("Сохранить нельзя: %s." % why, Color(1.0, 0.6, 0.4))
		return false
	if not Save.save_game():
		Game.notify("Ошибка сохранения: %s" % Save.last_error, Color(1.0, 0.4, 0.4))
		return false
	Game.notify("Забег сохранён (F9 — загрузить).", Color(0.6, 1.0, 0.75))
	run_saved.emit()
	return true


func quick_load() -> bool:
	if hardcore():
		Game.notify("Хардкор: сохранений нет.", Color(1.0, 0.6, 0.4))
		return false
	if Game.in_mission():   # ADR-004: поверх главы чужой забег не кладём
		Game.notify("Загрузить нельзя: %s." % Save.MISSION_NO_SAVE, Color(1.0, 0.6, 0.4))
		return false
	if not Save.load_game():
		Game.notify("Загрузить нельзя: %s." % Save.last_error, Color(1.0, 0.6, 0.4))
		return false
	Game.notify("Забег загружен: смена %d." % Game.day_number, Color(0.6, 1.0, 0.75))
	run_loaded.emit()
	return true


func hardcore() -> bool:
	var sc: Node = get_tree().current_scene
	return sc != null and sc.get("hardcore") == true


func toggle_inventory() -> void:
	if panel.visible:
		panel.close()
	else:
		if player:
			journal.close()
			panel.open(player)


## J: журнал поверх игры. Окно одно за раз: инвентарь при этом закрывается.
func toggle_journal() -> void:
	if journal.visible:
		journal.close()
	else:
		panel.close()
		journal.open()


func open_chest(c: Chest) -> void:
	if player:
		journal.close()
		panel.open_chest(player, c)


## Открыто окно, которое забирает ввод у мира (инвентарь, журнал или пауза).
func blocking() -> bool:
	return panel.visible or journal.visible or pause.visible


## Пауза (#119): ESC и кнопка «II» на телефоне. Открыт инвентарь или журнал — сначала их.
func toggle_pause() -> void:
	if pause.visible:
		pause.close()
	elif panel.visible or journal.visible:
		panel.close()
		journal.close()
	else:
		pause.open()


func _on_notification(text: String, color: Color) -> void:
	hud.notify(text, color)


func flash_damage() -> void:
	hud.damage_flash = 1.0


func flash_ring(world_pos: Vector2, color: Color) -> void:
	if world_fx:
		world_fx.spawn_ring(world_pos, color)


func spawn_chip(cell: Vector2i, color: Color) -> void:
	if world_fx:
		world_fx.spawn_chip(cell, color)


func spawn_slash(world_pos: Vector2) -> void:
	if world_fx:
		world_fx.spawn_slash(world_pos)


# ------------------------------------------------- СЕТЬ (ADR-002 § 4.2.3, MP-D #89)
## События обратной связи с хоста (NetCodec.Msg.EVENT; канал 0 — всем, 2 — лично):
## звук в точке (Sfx.play_at — тише с расстоянием), уведомление, эффект в мире, удар
## по своему герою. Обработчик ставит NetPlayers; свой герой — player (bind).
const NET_EVENT_LOG: int = 64
## Последние принятые события {type, pos, sound | text | kind} — для сценариев mp_*.
var net_events: Array = []


func net_event(_sender: int, payload: PackedByteArray) -> void:
	var e: Dictionary = NetCodec.decode_event(payload)
	if e.is_empty():
		return
	var rec: Dictionary = {"type": int(e["type"]), "pos": e["pos"]}
	match int(e["type"]):
		NetCodec.Ev.SOUND:
			var id: String = NetCodec.sound_name(int(e["sound"]))
			rec["sound"] = id
			if id != "":
				Sfx.play_at(id, e["pos"], float(e["volume_db"]), float(e["pitch"]))
		NetCodec.Ev.NOTIFY:
			rec["text"] = String(e["text"])
			Game.notify(String(e["text"]), e["color"])
		NetCodec.Ev.FX:
			rec["kind"] = int(e["kind"])
			NetPlayers.play_fx(int(e["kind"]), e["pos"], int(e["arg"]))
		NetCodec.Ev.HIT:
			if player != null:
				player.net_on_hit(e["knock"], float(e["stun"]))
	net_events.append(rec)
	if net_events.size() > NET_EVENT_LOG:
		net_events.pop_front()
