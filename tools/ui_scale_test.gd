extends Node
class_name UiScaleTest
## «Размер интерфейса» (#159, ADR-005 § 8.1): умолчание от экрана, раскладка HUD без
## наездов при каждом коэффициенте, шрифты не мельче UI.FONT.small, профиль.
##
## Подключается к --test: секция «== Размер интерфейса ==» (test_runner.gd, шаги
## _t_ui_scale_start / _t_ui_scale_wait). Отдельного запуска нет — нужна игровая сцена с
## героем и автозагрузками. Замеры в мм — «эмулированные экраны» (dpi, окно, холст) через
## статические UI.px_per_mm и UI.default_scale: окно настоящего телефона в headless не нужно.

## Экраны: [подпись, dpi, окно в физических px, холст игры].
const PHONE: Array = ["телефон 6,1″", 420, Vector2(2340, 1080), Vector2(1560, 720)]
const MONITOR: Array = ["монитор 24″ 1080p", 92, Vector2(1920, 1080), Vector2(1280, 720)]
## Эталонные холсты для раскладки HUD, px.
const CANVASES: Array = [Vector2(1280, 720), Vector2(1560, 720)]

var checks: int = 0
var fails: int = 0
var done: bool = false


func start(scene: Node) -> void:
	print("== Размер интерфейса ==")
	_t_defaults()
	_t_profile()
	_t_layout(scene)
	_t_panels()
	_t_fonts_grep()
	done = true


func _ok(label: String, cond: bool, extra: String = "") -> void:
	checks += 1
	if cond:
		print("  OK   %s %s" % [label, extra])
	else:
		fails += 1
		print("  FAIL %s %s" % [label, extra])


# --------------------------------------------------------------------------- умолчание

func _t_defaults() -> void:
	var fb: float = float(UI.FONT["body"])
	var phone_ppm: float = UI.px_per_mm(int(PHONE[1]), PHONE[2], PHONE[3])
	var mon_ppm: float = UI.px_per_mm(int(MONITOR[1]), MONITOR[2], MONITOR[3])
	var phone_s: float = UI.default_scale(int(PHONE[1]), PHONE[2], PHONE[3])
	var mon_s: float = UI.default_scale(int(MONITOR[1]), MONITOR[2], MONITOR[3])
	var phone_mm: float = UI.size_mm(fb, phone_s, phone_ppm)
	var mon_mm: float = UI.size_mm(fb, mon_s, mon_ppm)
	print("  ЗАМЕР: %s — %.2f px/мм; строка FONT.body %d px: было (100 %%) %.2f мм, умолчание %s → %.2f мм"
			% [PHONE[0], phone_ppm, int(fb), UI.size_mm(fb, 1.0, phone_ppm), UI.scale_text(phone_s), phone_mm])
	print("  ЗАМЕР: %s — %.2f px/мм; строка FONT.body %d px: умолчание %s → %.2f мм"
			% [MONITOR[0], mon_ppm, int(fb), UI.scale_text(mon_s), mon_mm])
	_ok("телефон 6,1″: строка FONT.body не ниже %.1f мм" % UI.BODY_MM_PHONE, phone_mm >= UI.BODY_MM_PHONE,
			"%.2f мм" % phone_mm)
	var below: float = -1.0
	for s in UI.SCALES:
		if s < phone_s:
			below = s
	_ok("телефон: умолчание — наименьший коэффициент из списка (предыдущий не дотягивает)",
			below < 0.0 or UI.size_mm(fb, below, phone_ppm) < UI.BODY_MM_PHONE,
			"%s → %.2f мм" % [UI.scale_text(below), UI.size_mm(fb, below, phone_ppm)])
	_ok("монитор 24″ 1080p: умолчание 100 %", is_equal_approx(mon_s, 1.0), UI.scale_text(mon_s))
	_ok("монитор: строка FONT.body не ниже %.1f мм" % UI.BODY_MM_PC, mon_mm >= UI.BODY_MM_PC, "%.2f мм" % mon_mm)
	_ok("dpi неизвестен (0) — 100 %", is_equal_approx(UI.default_scale(0, Vector2(1280, 720), Vector2(1280, 720)), 1.0))
	_ok("привязка к списку: 1,3 → 1,5; 9 → 2,5; кнопка идёт по кругу 1 → 1,5 → 2 → 2,5 → 1",
			is_equal_approx(UI.snap_scale(1.3), 1.5) and is_equal_approx(UI.snap_scale(9.0), 2.5)
			and is_equal_approx(UI.next_scale(2.5), 1.0) and is_equal_approx(UI.next_scale(1.0), 1.5))
	_ok("подпись кнопки: «100 %» / «250 %»", UI.scale_text(1.0) == "100 %" and UI.scale_text(2.5) == "250 %")


# --------------------------------------------------------------------------- профиль

func _t_profile() -> void:
	var path: String = "user://ui_scale_test~%d.cfg" % OS.get_process_id()
	DirAccess.remove_absolute(path)
	_ok("файла нет — read_ui_scale = 0 (первый запуск)", is_zero_approx(Profile.read_ui_scale(path)))
	Profile.write_ui_scale(2.0, path)
	_ok("write → read: 2,0", is_equal_approx(Profile.read_ui_scale(path), 2.0))
	var p: Profile = Profile.load_or_create(path)
	_ok("load_or_create читает ui_scale", is_equal_approx(p.ui_scale, 2.0))
	p.ui_scale = 1.5
	p.save_to(path)
	_ok("save_to пишет ui_scale", is_equal_approx(Profile.read_ui_scale(path), 1.5))
	var fresh: Profile = Profile.new()   # профиль меню, загруженный до первого запуска (ui_scale = 0)
	fresh.save_to(path)
	_ok("save_to не стирает записанный UI размер при ui_scale = 0", is_equal_approx(Profile.read_ui_scale(path), 1.5))
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(path)
	cfg.set_value("access", "ui_scale", "мусор")
	cfg.save(path)
	_ok("битое поле — 0 (умолчание от экрана)", is_zero_approx(Profile.read_ui_scale(path)))
	DirAccess.remove_absolute(path)


# --------------------------------------------------------------------------- раскладка HUD

func _t_layout(scene: Node) -> void:
	var hud: HUD = UI.hud
	var s0: float = UI.ui_scale
	var xf0: Transform2D = get_viewport().get_canvas_transform()
	var zoom0: float = float(scene.get("view_zoom").get_zoom()) if scene.get("view_zoom") != null else -1.0
	var tc: TouchControls = get_tree().get_first_node_in_group("touch_controls") as TouchControls
	var touch0: bool = tc != null and tc.enabled
	var saved: Dictionary = _worst_state(hud)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var bad: Array = []
	var canvases: Array = CANVASES
	var phone_ppm: float = UI.px_per_mm(int(PHONE[1]), PHONE[2], PHONE[3])
	for touch in [false, true]:
		if tc != null:
			tc.set_enabled(touch)
		if touch and tc == null:
			continue
		for canvas in canvases:
			for s in UI.SCALES:
				UI.set_ui_scale(s, false)
				hud.size = canvas / s
				hud._lay_sig = -1
				if tc != null and touch:
					tc.force_k = clampf(TouchControls.MIN_MM * phone_ppm / (TouchControls.BTN_R * 2.0), 1.0, 1.6)
					tc._layout(canvas)   # кнопки телефона 6,1″ на эмулированном холсте (px холста)
				hud._lay_sig = -1
				var keys: Array = []
				var rects: Array = []
				var named: Dictionary = hud.layout_named()
				for k in named:
					if (named[k] as Rect2).has_area():
						keys.append(k)
						rects.append(named[k])
				var tag: String = "%s, %s, тач %s" % [UI.scale_text(s), str(canvas), "да" if touch else "нет"]
				var screen: Rect2 = Rect2(Vector2.ZERO, canvas / s).grow(0.5)
				for i in rects.size():
					if not screen.encloses(rects[i]):
						bad.append("%s: «%s» за краем экрана %s" % [tag, keys[i], str(rects[i])])
					for j in range(i + 1, rects.size()):
						if (rects[i] as Rect2).intersects(rects[j]):
							bad.append("%s: «%s» %s налезает на «%s» %s" % [tag, keys[i], str(rects[i]), keys[j], str(rects[j])])
				if touch and tc != null:
					for id in tc.btn_center:
						if not tc._shown(id, false):
							continue
						var c: Vector2 = tc.btn_center[id]
						var rr: float = float(tc.btn_radius[id])
						var br: Rect2 = Rect2(c - Vector2(rr, rr), Vector2(rr, rr) * 2.0)
						for i in rects.size():
							var hr: Rect2 = Rect2((rects[i] as Rect2).position * s, (rects[i] as Rect2).size * s)
							if br.intersects(hr):
								bad.append("%s: кнопка «%s» налезает на «%s»" % [tag, id, keys[i]])
				var n_shown: int = hud._lay["note_lines"].size() if hud.layout_rect("notes").has_area() else 0
				print("  ЗАМЕР: %s — блоков %d, строк статуса %d, уведомлений %d из 3" % [tag, rects.size(),
						hud._lay["rows"].size(), n_shown])
	_restore_state(hud, saved)
	UI.set_ui_scale(s0, false)
	hud.size = vp / s0
	hud._lay_sig = -1
	if tc != null:
		tc.force_k = 0.0
		tc.set_enabled(touch0)
	_ok("HUD: при 100/150/200/250 % блоки (hp, импульс, статус, сутки, отсчёт, миникарта, хотбар, подсказка, "
			+ "уведомления) не пересекаются и не выходят за экран; кнопки тач-раскладки их не накрывают",
			bad.is_empty(), "\n       ".join(bad.slice(0, 8)))
	_ok("HUD: layout_rects() отдаёт блоки", hud.layout_rects().size() >= 5, str(hud.layout_rects().size()))
	_ok("мир не меняется от коэффициента: камера и зум те же",
			get_viewport().get_canvas_transform().is_equal_approx(xf0)
			and (zoom0 < 0.0 or is_equal_approx(float(scene.get("view_zoom").get_zoom()), zoom0)))
	_ok("слой UI масштабируется, HUD получает логический размер холст / коэффициент",
			is_equal_approx(UI.scale.x, UI.ui_scale) and hud.size.is_equal_approx(vp / UI.ui_scale),
			"scale %.1f, HUD %s" % [UI.scale.x, str(hud.size)])


## Худшее состояние HUD для раскладки: длинные строки трекера, обучение, миссия,
## подсказка и несколько уведомлений. Возвращает прежние значения.
func _worst_state(hud: HUD) -> Dictionary:
	var saved: Dictionary = {
		"tt": hud.tracker_title, "td": hud.tracker_detail, "tut": hud.tutorial_text,
		"ct": hud.card_text, "ch": hud.card_have, "cn": hud.card_need,
		"ml": hud.mission_lines.duplicate(), "hint": hud.hint_text, "hh": hud._hint_hash,
		"notes": hud.notes.duplicate(true), "cd": hud.night_countdown,
	}
	hud.tracker_title = "ЦЕЛЬ 2 · СВЕТ"
	hud.tracker_detail = "Поставь горелку у входа в пещеру и зажги её углём — это длинная строка"
	hud.card_text = "Запитай терминалы базы"
	hud.card_have = 0
	hud.card_need = 2
	hud.tutorial_text = "возьми уголь и положи в топку"
	hud.hint_text = "[E] — загрузить уголь в ТЭЦ · удерживать [E] — разобрать"
	hud._hint_hash = hud.hint_text.hash()
	hud.notes = [
		{"text": "Забег сохранён (F9 — загрузить).", "color": Color.WHITE, "ttl": 5.0},
		{"text": "Подобран уголь × 3", "color": Color.WHITE, "ttl": 5.0},
		{"text": "Ночь наступила: держитесь у света", "color": Color.WHITE, "ttl": 5.0},
	]
	hud._note_serial += 1
	return saved


func _restore_state(hud: HUD, saved: Dictionary) -> void:
	hud.tracker_title = saved["tt"]
	hud.tracker_detail = saved["td"]
	hud.card_text = saved["ct"]
	hud.card_have = saved["ch"]
	hud.card_need = saved["cn"]
	hud.tutorial_text = saved["tut"]
	var ml: Array[String] = []
	ml.assign(saved["ml"])
	hud.mission_lines = ml
	hud.hint_text = saved["hint"]
	hud._hint_hash = saved["hh"]
	hud.notes = saved["notes"]
	hud.night_countdown = saved["cd"]
	hud._note_serial += 1
	hud._lay_sig = -1


# --------------------------------------------------------------------------- панели

func _t_panels() -> void:
	var s0: float = UI.ui_scale
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var bad: Array = []
	var worst: float = 99.0
	for s in UI.SCALES:
		UI.set_ui_scale(s, false)
		for pair in [["инвентарь", UI.panel, InventoryPanel.PANEL],
				["журнал", UI.journal, Vector2(JournalPanel.W, JournalPanel.H)]]:
			var c: Control = pair[1]
			var d: Vector2 = pair[2]
			var shown: Vector2 = d * c.scale.x * UI.ui_scale   # px холста на экране
			worst = minf(worst, c.scale.x * UI.ui_scale)
			if shown.x > vp.x - 2.0 * UI.PANEL_MARGIN + 0.5 or shown.y > vp.y + 0.5:
				bad.append("%s при %s: панель %s на холсте %s" % [pair[0], UI.scale_text(s), str(shown), str(vp)])
			if c.size.x * c.scale.x * UI.ui_scale < vp.x - 1.0:
				bad.append("%s при %s: Control не закрывает холст" % [pair[0], UI.scale_text(s)])
		var pause_w: float = (PauseMenu.COL_W + 40.0) * UI.pause.scale.x
		if pause_w > vp.x or PauseMenu.DESIGN_H * UI.pause.scale.x > vp.y:
			bad.append("пауза при %s: %.0f × %.0f на холсте %s" % [UI.scale_text(s), pause_w,
					PauseMenu.DESIGN_H * UI.pause.scale.x, str(vp)])
	# Достигнутый коэффициент панелей на эмулированных холстах при 250 % (воспроизводимо:
	# окно headless 64×64, холст у него свой).
	UI.set_ui_scale(2.5, false)
	var narrow: bool = true
	for canvas in CANVASES:
		var f_inv: float = UI.panel_scale(InventoryPanel.PANEL, canvas)
		var f_jrn: float = UI.panel_scale(Vector2(JournalPanel.W, JournalPanel.H), canvas)
		var ppm: float = UI.px_per_mm(int(PHONE[1]), PHONE[2], canvas)
		print("  ЗАМЕР: холст %s, 250 %%: панель инвентаря ×%.2f (%.0f × %.0f px), журнал ×%.2f; "
				% [str(canvas), f_inv, InventoryPanel.PANEL.x * f_inv, InventoryPanel.PANEL.y * f_inv, f_jrn]
				+ "на 6,1″ шрифты панели: FONT.small %.2f мм, FONT.body %.2f мм" % [
				UI.size_mm(float(UI.FONT["small"]), f_inv, ppm), UI.size_mm(float(UI.FONT["body"]), f_inv, ppm)])
		narrow = narrow and f_inv <= 2.5 + 0.001 \
				and InventoryPanel.PANEL.x * f_inv <= canvas.x - 2.0 * UI.PANEL_MARGIN + 0.5 \
				and InventoryPanel.PANEL.y * f_inv <= canvas.y + 0.5
	UI.set_ui_scale(s0, false)
	_ok("панели (инвентарь, журнал, пауза) при каждом коэффициенте влезают в экран целиком",
			bad.is_empty(), "\n       ".join(bad.slice(0, 6)))
	_ok("панель инвентаря при 250 % на холстах 1280×720 и 1560×720 — не больше коэффициента интерфейса, "
			+ "в экране целиком", narrow)

# --------------------------------------------------------------------------- шрифты

## Ни один размер шрифта в scripts/ui/ не меньше UI.FONT.small: разбираем вызовы draw_string,
## draw_string_outline, draw_multiline_string, _text, _str и add_theme_font_size_override
## и смотрим числовые литералы в позиции размера.
func _t_fonts_grep() -> void:
	var small: int = int(UI.FONT["small"])
	var bad: Array = []
	var calls: int = 0
	# (имя вызова, позиция аргумента-размера, сколько аргументов до него — для проверки).
	var spec: Dictionary = {
		"draw_string(": 5, "draw_string_outline(": 5, "draw_multiline_string(": 5,
		"_text(": 3, "_str(": 2, "add_theme_font_size_override(": 1,
		"_text_on_plate(": 3, "_text_outlined(": 3,
	}
	var dir: DirAccess = DirAccess.open("res://scripts/ui")
	if dir == null:
		_ok("скрипты интерфейса читаются", false)
		return
	for fn in dir.get_files():
		if not fn.ends_with(".gd"):
			continue
		var src: String = FileAccess.get_file_as_string("res://scripts/ui/" + fn)
		for name in spec:
			var at: int = 0
			while true:
				at = src.find(name, at)
				if at < 0:
					break
				var pre: String = src.substr(at - 1, 1) if at > 0 else ""
				var is_def: bool = src.substr(maxi(0, at - 5), 5) == "func "
				at += name.length()
				# «func _text(» и «draw_text(» — не вызовы; «.draw_string(» и «	_text(» — они.
				if is_def or pre == "_" or pre.is_valid_identifier():
					continue
				var args: PackedStringArray = _split_args(src, at)
				var idx: int = int(spec[name])
				if idx >= args.size():
					continue
				calls += 1
				var a: String = args[idx].strip_edges()
				if a.is_valid_int() and int(a) < small:
					bad.append("%s: %s…%s" % [fn, name, a])
	_ok("шрифты: ни один размер в scripts/ui/ не меньше UI.FONT.small (%d px); разобрано вызовов: %d" % [small, calls],
			bad.is_empty() and calls > 40, "\n       ".join(bad.slice(0, 8)))
	var literals: int = 0
	for fn in ["hud.gd", "inventory_panel.gd", "journal_panel.gd", "pause_menu.gd"]:
		var src2: String = FileAccess.get_file_as_string("res://scripts/ui/" + fn)
		for name in ["draw_string(", "_text(", "_str("]:
			var at2: int = 0
			while true:
				at2 = src2.find(name, at2)
				if at2 < 0:
					break
				at2 += name.length()
				var args2: PackedStringArray = _split_args(src2, at2)
				var i2: int = int(spec[name])
				if i2 < args2.size() and args2[i2].strip_edges().is_valid_int():
					literals += 1
	_ok("шрифты: в HUD, инвентаре, журнале и паузе размеры — только UI.FONT, без вшитых чисел", literals == 0,
			"вшитых: %d" % literals)


## Аргументы вызова верхнего уровня: from — сразу после «(». Скобки и кавычки учитываются.
static func _split_args(src: String, from: int) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var depth: int = 1
	var cur: String = ""
	var quote: String = ""
	var i: int = from
	while i < src.length() and i < from + 600:
		var ch: String = src[i]
		if quote != "":
			cur += ch
			if ch == "\\":
				i += 1
				if i < src.length():
					cur += src[i]
			elif ch == quote:
				quote = ""
		elif ch == "\"":
			quote = ch
			cur += ch
		elif ch == "(" or ch == "[" or ch == "{":
			depth += 1
			cur += ch
		elif ch == ")" or ch == "]" or ch == "}":
			depth -= 1
			if depth == 0:
				out.append(cur)
				return out
			cur += ch
		elif ch == "," and depth == 1:
			out.append(cur)
			cur = ""
		else:
			cur += ch
		i += 1
	return out
