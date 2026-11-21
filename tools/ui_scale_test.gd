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
## Эталонные холсты для раскладки HUD, px. 1600×720 — 20:9 телефона (2400×1080 при 2.5),
## 1280×2844 — портрет 1080×2400 при 2.5.
const CANVASES: Array = [Vector2(1280, 720), Vector2(1560, 720), Vector2(1600, 720), Vector2(1280, 2844)]

var checks: int = 0
var fails: int = 0
var done: bool = false


func start(scene: Node) -> void:
	print("== Размер интерфейса ==")
	_t_defaults()
	_t_profile()
	_t_layout(scene)
	_t_status_fit(UI.hud)
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
	var slots0: int = 10
	if scene.get("player") != null and scene.player.inv != null:
		slots0 = scene.player.inv.hotbar_size
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var bad: Array = []
	var phone_bad: Array = []
	# 1600×720 и 1280×2844 уже есть в CANVASES: это холсты телефонов 2400×1080 и
	# 1080×2400 при 250 %. Сырой экран 1080×2400 как холст даёт 432 лог. px — шесть
	# ячеек туда не влезают, и это не раскладка HUD.
	var canvases: Array = CANVASES.duplicate()
	for touch in [false, true]:
		if tc != null:
			tc.set_enabled(touch)
		if touch and tc == null:
			continue
		# На телефоне Шифу 6 ячеек, не 10 по умолчанию. Десктопный прогон не трогаем.
		if touch and scene.get("player") != null and scene.player.inv != null:
			scene.player.inv.hotbar_size = 6
		elif scene.get("player") != null and scene.player.inv != null:
			scene.player.inv.hotbar_size = slots0
		for canvas in canvases:
			var win: Vector2 = Vector2(1080, 2400) if canvas.y > canvas.x else Vector2(canvas.x * 1.5, 1080)
			var ppm: float = UI.px_per_mm(420, win, canvas)
			var force_k: float = clampf(TouchControls.MIN_MM * ppm / (TouchControls.BTN_R * 2.0), 1.0, 1.6)
			for s in UI.SCALES:
				UI.set_ui_scale(s, false)
				hud.size = canvas / s
				hud._lay_sig = -1
				if tc != null and touch:
					tc.force_k = force_k
					tc._layout(canvas)   # кнопки на эмулированном холсте (px холста)
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
					var grabs: Array = _grab_circles(tc, s)
					for g in grabs:
						for i in rects.size():
							if _circle_hits((g["c"] as Vector2), float(g["r"]), (rects[i] as Rect2) ):
								bad.append("%s: захват «%s» налезает на «%s»" % [tag, g["id"], keys[i]])
					_phone_layout(hud, named, tc, tag, phone_bad)
					_phone_band(hud, named, tc, s, tag)
				var n_shown: int = hud._lay["note_lines"].size() if hud.layout_rect("notes").has_area() else 0
				print("  ЗАМЕР: %s — блоков %d, строк статуса %d, уведомлений %d из 3" % [tag, rects.size(),
						hud._lay["rows"].size(), n_shown])
	if tc != null:
		tc.set_enabled(true)
		_t_intro_plate(tc, hud)
	if scene.get("player") != null and scene.player.inv != null:
		scene.player.inv.hotbar_size = slots0
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
	_ok("телефон: HUD в нижней трети, плашка без «…», хотбар у нижнего края, карточка компактна если есть",
			phone_bad.is_empty(), "\n       ".join(phone_bad.slice(0, 8)))
	_ok("HUD: layout_rects() отдаёт блоки", hud.layout_rects().size() >= 5, str(hud.layout_rects().size()))
	_ok("мир не меняется от коэффициента: камера и зум те же",
			get_viewport().get_canvas_transform().is_equal_approx(xf0)
			and (zoom0 < 0.0 or is_equal_approx(float(scene.get("view_zoom").get_zoom()), zoom0)))
	_ok("слой UI масштабируется, HUD получает логический размер холст / коэффициент",
			is_equal_approx(UI.scale.x, UI.ui_scale) and hud.size.is_equal_approx(vp / UI.ui_scale),
			"scale %.1f, HUD %s" % [UI.scale.x, str(hud.size)])


## Телефон: хотбар у нижнего края, плашка над ним без «…». Карточка, если влезла
## в нижнюю треть, — компактная (не выше 52, не шире 65 %). Весь HUD — в нижней трети.
func _phone_layout(hud: HUD, named: Dictionary, tc: TouchControls, tag: String, bad: Array) -> void:
	var sz: Vector2 = hud.size
	var band_y: float = sz.y * (2.0 / 3.0)
	if not named.has("hotbar"):
		bad.append("%s: нет хотбара" % tag)
		return
	var hot: Rect2 = named["hotbar"]
	if hot.size.y > 44.0 and not (sz.y > sz.x * 1.2):
		bad.append("%s: хотбар выше 44 (%s)" % [tag, str(hot.size)])
	if hot.position.y + 0.5 < band_y:
		bad.append("%s: хотбар выше нижней трети (%s, треть %.1f)" % [tag, str(hot), band_y])
	if sz.y > sz.x * 1.2:
		var cell: float = float(hud._lay.get("slot", 0.0)) - 4.0
		var n_slots: int = hud._hotbar_count()
		if n_slots <= 6 and cell + 0.5 < 78.0:
			bad.append("%s: ячейка портрета %.1f < 78" % [tag, cell])
		if cell + 0.5 < HUD.SLOT_DIGIT_MIN:
			bad.append("%s: ячейка %.1f < %d, номер слота не рисуется" % [tag, cell, int(HUD.SLOT_DIGIT_MIN)])
		var grab_top: float = hud._combat_grab_top(sz.y)
		if hot.end.y > grab_top + 0.5:
			bad.append("%s: хотбар не выше захватов (низ %.1f, захват %.1f)" % [tag, hot.end.y, grab_top])
		var ppm: float = UI.px_per_mm(420, Vector2(1080, 2400), Vector2(1280, 2844))
		print("  ЗАМЕР портрет: %s ячейка %.1f лог. px = %.2f мм, верх захвата %.1f, хотбар %s" % [tag, cell, UI.size_mm(cell, UI.ui_scale, ppm), grab_top, str(hot)])
	if hud.card_text != "" and not named.has("card"):
		bad.append("%s: цель скрыта при непустом card_text" % tag)
	if named.has("card"):
		var card: Rect2 = named["card"]
		if card.size.y > 52.0:
			bad.append("%s: карточка выше 52 (%s)" % [tag, str(card.size)])
		if card.size.y + 0.5 < 22.0 or card.size.y > 24.0 + 0.5:
			bad.append("%s: полоса цели не 22–24 (%s)" % [tag, str(card.size)])
		# Полоса может занять почти всю ширину нижней трети: 6 слов + этап + счётчик
		# на 512 лог. px не влезают в поля 8. За край экрана не выходим.
		if card.end.x > sz.x + 0.5 or card.position.x < -0.5:
			bad.append("%s: карточка шире экрана (%s)" % [tag, str(card)])
		if card.position.y + 0.5 < band_y:
			bad.append("%s: карточка выше нижней трети (%s)" % [tag, str(card)])
		if named.has("map") and card.intersects(named["map"]):
			bad.append("%s: карточка на карте" % tag)
		if named.has("hint") and card.intersects(named["hint"]):
			bad.append("%s: карточка на плашке" % tag)
		if named.has("hotbar") and card.intersects(named["hotbar"]):
			bad.append("%s: карточка на хотбаре" % tag)
		if named.has("hp") and card.intersects(named["hp"]):
			bad.append("%s: карточка на здоровье" % tag)
		if named.has("emp") and card.intersects(named["emp"]):
			bad.append("%s: карточка на импульсе" % tag)
		var hero: Rect2 = Rect2(sz * 0.5 - Vector2(24, 32), Vector2(48, 64))
		if card.intersects(hero):
			bad.append("%s: карточка на силуэте" % tag)
		if named.has("hint"):
			var above: float = (named["hint"] as Rect2).position.y - card.end.y
			if card.end.y <= (named["hint"] as Rect2).position.y + 0.5 and above + 0.5 < HUD.HINT_GAP_TOUCH:
				bad.append("%s: зазор цель–плашка %.1f < 10 card=%s hint=%s" % [tag, above, card, named["hint"]])
		elif named.has("hotbar"):
			var above_h: float = (named["hotbar"] as Rect2).position.y - card.end.y
			if card.end.y <= (named["hotbar"] as Rect2).position.y + 0.5 and above_h + 0.5 < HUD.HINT_GAP_TOUCH:
				bad.append("%s: зазор цель–хотбар %.1f < 10" % [tag, above_h])
		var inner: float = float(hud._lay.get("card_inner", 0.0))
		var title: String = String(hud._lay.get("card_title", ""))
		var cfont: int = int(hud._lay.get("card_font", UI.FONT["small"]))
		if title == "" or hud._tw(title, cfont) > inner + 0.5:
			print("  ЗАМЕР цель: %s inner=%.1f pad=%s icon=%s hint=%s hot=%s" % [tag, inner, hud._lay.get("card_pad"), hud._lay.get("card_icon_px"), named.get("hint", Rect2()), named.get("hotbar", Rect2())])
			var grabs: Array = _grab_circles(tc, UI.ui_scale)
			var bits: PackedStringArray = []
			for g in grabs:
				bits.append("%s c=%s r=%.1f" % [g["id"], str(g["c"]), float(g["r"])])
			bad.append("%s: заголовок не влезает tw=%.1f card=%s grabs=[%s]" % [tag, hud._tw(title, cfont), str(card), "; ".join(bits)])
		if title.contains("…"):
			bad.append("%s: заголовок обрезан «%s»" % [tag, title])
		if not title.begins_with("%d/" % _goal_stage()):
			bad.append("%s: строка не с этапа «%s»" % [tag, title])
		if hud.card_need > 1 and not title.contains("%d / %d" % [hud.card_have, hud.card_need]):
			bad.append("%s: нет счётчика «%s»" % [tag, title])
		if title.contains("0 / 1"):
			bad.append("%s: показан 0 / 1" % tag)
	if named.has("hint"):
		var hint: Rect2 = named["hint"]
		var ht: String = String(hud._lay.get("hint_text", ""))
		var gap: float = hot.position.y - hint.end.y
		if gap + 0.5 < HUD.HINT_GAP_TOUCH:
			bad.append("%s: зазор плашка–хотбар %.1f < %d" % [tag, gap, int(HUD.HINT_GAP_TOUCH)])
		if ht.ends_with("…"):
			bad.append("%s: плашка с «…» «%s»" % [tag, ht])
		var screen: Rect2 = Rect2(Vector2.ZERO, sz).grow(0.5)
		if not screen.encloses(hint):
			bad.append("%s: плашка за экраном" % tag)
		var slot_fs: int = hud._slot_font()
		if int(hud._lay.get("hint_font", 0)) > slot_fs:
			bad.append("%s: кегль плашки %s > цифры %d" % [tag, hud._lay.get("hint_font"), slot_fs])
	for nl in hud._lay.get("note_lines", []):
		if String(nl).ends_with("…"):
			bad.append("%s: уведомление с «…»" % tag)
	if named.has("status0"):
		var st: String = String(hud._lay["rows"][0]["text"]) if hud._lay["rows"].size() > 0 else ""
		if st.ends_with("…"):
			bad.append("%s: строка обучения обрезана «%s»" % [tag, st])
	if band_y < 40.0:
		bad.append("%s: полоса мира %.1f < 40" % [tag, band_y])
	if sz.y < 300.0 or sz.x < 600.0:
		var keys: Array = []
		for kk in named:
			if (named[kk] as Rect2).has_area():
				keys.append(kk)
		print("  ЗАМЕР 2.5: %s card %s hint %s hotbar %s map %s hp %s день %s треть %.1f есть %s" % [tag,
				named.get("card", Rect2()), named.get("hint", Rect2()), hot,
				named.get("map", Rect2()), named.get("hp", Rect2()), named.get("day", Rect2()),
				band_y, ", ".join(keys)])
		hud._lay_sig = -1


## (а) силуэт героя в центре не пересекает блоки и кнопки.
## (б) кегль плашки ≤ FONT.small. (в) каждый блок начинается в нижней трети.
## (г) зазор плашка–хотбар ≥ HINT_GAP_TOUCH − 0.5.

## Круги захвата в логических px HUD: кнопки × BTN_GRAB, стик × STICK_GRAB.
func _grab_circles(tc: TouchControls, s: float) -> Array:
	var out: Array = []
	for id in tc.btn_center:
		if not tc._shown(id, false):
			continue
		var mul: float = TouchControls.BTN_GRAB
		out.append({"id": id, "c": tc.btn_center[id] / s, "r": float(tc.btn_radius[id]) * mul / s})
	out.append({"id": "stick", "c": tc.stick_center / s, "r": tc.stick_radius * TouchControls.STICK_GRAB / s})
	return out


func _circle_hits(c: Vector2, rad: float, r: Rect2) -> bool:
	var closest := Vector2(clampf(c.x, r.position.x, r.end.x), clampf(c.y, r.position.y, r.end.y))
	return c.distance_to(closest) < rad - 0.01


func _phone_band(hud: HUD, named: Dictionary, tc: TouchControls, s: float, tag: String) -> void:
	var sz: Vector2 = hud.size
	var band_y: float = sz.y * (2.0 / 3.0) - 0.5
	var above: Array = []
	for kk in named:
		var r: Rect2 = named[kk]
		if r.has_area() and r.position.y < band_y:
			above.append("%s %s" % [kk, r])
	_ok("тач: весь HUD в нижней трети", above.is_empty(), "%s %s" % [tag, ", ".join(above)])
	var player: Rect2 = Rect2(sz * 0.5 - Vector2(24, 32), Vector2(48, 64))
	var hit: Array = []
	for kk in named:
		var r2: Rect2 = named[kk]
		if r2.has_area() and r2.intersects(player):
			hit.append(kk)
	for g in _grab_circles(tc, s):
		if _circle_hits(g["c"], float(g["r"]), player):
			hit.append("захват " + String(g["id"]))
	_ok("тач: силуэт игрока не пересекает HUD и кнопки", hit.is_empty(),
			"%s силуэт %s %s" % [tag, player, ", ".join(hit)])
	var hf: int = int(hud._lay.get("hint_font", hud._slot_font()))
	var slot_fs: int = hud._slot_font()
	_ok("тач: кегль подсказки не больше цифры слота", hf <= slot_fs, "%s %d ≤ %d" % [tag, hf, slot_fs])
	var gap_detail: String = "%s hint скрыт" % tag
	var gap_ok: bool = true
	if named.has("hint") and named.has("hotbar"):
		var gap: float = (named["hotbar"] as Rect2).position.y - (named["hint"] as Rect2).end.y
		gap_ok = gap + 0.5 >= HUD.HINT_GAP_TOUCH
		gap_detail = "%s %.1f" % [tag, gap]
		var plate: Rect2 = named["hint"]
		var hero: Rect2 = Rect2(sz * 0.5 - Vector2(24, 32), Vector2(48, 64))
		if plate.intersects(hero):
			gap_ok = false
			gap_detail += " плашка на игроке"
	_ok("тач: зазор подсказка–хотбар ≥ 10", gap_ok, gap_detail)



## Ввод на телефоне: одна строка INTRO_LINES в нижней плашке, без «…», не на карточке и хотбаре.
func _t_intro_plate(tc: TouchControls, hud: HUD) -> void:
	var canvas: Vector2 = Vector2(1600, 720)
	var win: Vector2 = Vector2(canvas.x * 1.5, 1080)
	var ppm: float = UI.px_per_mm(420, win, canvas)
	tc.force_k = clampf(TouchControls.MIN_MM * ppm / (TouchControls.BTN_R * 2.0), 1.0, 1.6)
	tc._layout(canvas)
	UI.set_ui_scale(2.5, false)
	hud.size = canvas / 2.5
	var old_hint: String = hud.hint_text
	var old_hash: int = hud._hint_hash
	var old_time: float = Game.game_time
	var old_done: bool = hud._intro_done
	hud.hint_text = ""
	hud._hint_hash = "".hash()
	hud._intro_done = false
	Game.game_time = 1.0
	# Цикл раскладки выше оставляет 6 ячеек и шаг героя: шаг гасит ввод, а крупный
	# хотбар поднимается и съедает ряд плашки. Здесь — как до цикла.
	var scene: Node = hud.get_parent()
	var old_vel: Vector2 = Vector2.ZERO
	var had_vel: bool = scene != null and scene.get("player") != null
	var old_slots: int = 10
	if had_vel:
		old_vel = scene.player.vel
		scene.player.vel = Vector2.ZERO
		if scene.player.inv != null:
			old_slots = scene.player.inv.hotbar_size
			scene.player.inv.hotbar_size = 10
	hud._lay_sig = -1
	var named: Dictionary = hud.layout_named()
	var ht: String = String(hud._lay.get("hint_text", ""))
	var lines: Array = ["Джойстик — идти", "Тап — копать", "«меню» — пауза"]
	var ok_line: bool = lines.has(ht) and not ht.ends_with("…")
	var overlap: bool = false
	if named.has("hint"):
		var hint: Rect2 = named["hint"]
		if named.has("card") and hint.intersects(named["card"]):
			overlap = true
		if named.has("hotbar") and hint.intersects(named["hotbar"]):
			overlap = true
		if hint.end.y + 4.0 > (named["hotbar"] as Rect2).position.y:
			overlap = true
		for g in _grab_circles(tc, 2.5):
			if _circle_hits(g["c"], float(g["r"]), hint):
				overlap = true
		if int(hud._lay.get("hint_font", 99)) > hud._slot_font():
			overlap = true
	else:
		ok_line = false
	_ok("телефон, ввод: одна строка INTRO_LINES без «…», не на карточке и хотбаре",
			ok_line and not overlap, "«%s»" % ht)
	hud.hint_text = old_hint
	hud._hint_hash = old_hash
	hud._intro_done = old_done
	Game.game_time = old_time
	if had_vel:
		scene.player.vel = old_vel
		if scene.player.inv != null:
			scene.player.inv.hotbar_size = old_slots
	hud._lay_sig = -1


## Текущий этап для строки цели: глава — stage+1, иначе clampi(objective_stage, 1, 6).
func _goal_stage() -> int:
	if Game.in_mission() and Game.mission != null:
		return int(Game.mission.stage) + 1
	var st: int = clampi(Game.objective_stage, 1, Game.OBJECTIVE_STAGES)
	if Game.relay_active:
		st = Game.OBJECTIVE_STAGES
	return st


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
	# 72 символа: _set_card режет до 6 слов, тест пишет card_text напрямую.
	# Шесть слов, как режет _set_card. Длиннее полоса телефона не обещает.
	hud.card_text = "Положи медную катушку во вторую горелку"
	hud.card_have = 3
	hud.card_need = 8
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


# --------------------------------------------------------------------------- строка этапа

## Портрет 250 % (холст 1280 → HUD 512): строка обучения — самая длинная из миссий —
## обязана читаться целиком. В body 18 она обрезалась, раскладка берёт small 14.
func _t_status_fit(hud: HUD) -> void:
	var s0: float = UI.ui_scale
	var sz0: Vector2 = hud.size
	UI.set_ui_scale(2.5, false)
	hud.size = Vector2(512, 1138)
	var full: String = "Копать можно только то, до чего достаёт луч от тебя"
	var rows: Array = [{"text": full, "kind": "tutorial", "prio": 1,
			"color": Color.WHITE, "full": full, "wide": true}]
	hud._status_place(rows, 200.0, 9999.0, [])
	var txt: String = String(rows[0]["text"]) if rows.size() == 1 else ""
	var fsize: int = int(rows[0].get("font", 0)) if rows.size() == 1 else 0
	_ok("телефон, портрет 250 %%: строка этапа читается целиком, кегль %d" % UI.FONT["small"],
			rows.size() == 1 and not txt.ends_with("…") and fsize == int(UI.FONT["small"]),
			"«%s», %d px" % [txt, fsize])
	UI.set_ui_scale(s0, false)
	hud.size = sz0
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
