extends ScenarioBase
## Сенсорное управление (#81): касания InputEventScreenTouch/ScreenDrag идут
## настоящим путём — Input.parse_input_event, вместе с эмуляцией мыши из касаний
## (как на телефоне), — и доходят до TouchControls, а оттуда через шов
## Player.touch_input до героя. Шов сценария (test_input) здесь пуст.
##
## Проверяем: без сенсорного экрана и --touch управление выключено; джойстик
## двигает героя, а эмулированный «клик» под джойстиком не копает; тап по кнопке
## прыжка (нажатие и отпускание в одном кадре) прыгает; второй палец копает тайл,
## пока первый держит джойстик (мультитач); тап по хотбару выбирает слот и режим
## (блок — «строить», пустая ячейка — «копать»); умный прицел (#149): тап по свободной
## клетке ставит один блок, тап за препятствием — блок со своей стороны, тап за радиусом
## копает ближнюю стену по лучу, тап на полклетки мимо камня копает камень; тап из ямы
## по тайлу слева-сверху (герой на тайл ниже) начинает копку; кнопки I и J
## открывают и закрывают окна, тап по миру при этом не копает; кнопка «меню» открывает
## паузу (#119); «Назад» Android закрывает окно, открывает и закрывает паузу, свернули
## приложение — пауза и сохранение (#149). Щипок двумя пальцами по миру ведёт зум
## (ViewZoom) и ничего не копает и не ставит; короткий тап быстрее ожидания щипка
## всё равно ставит блок. Тап по фантому на 21–26 px от тела бьёт его: прицел
## берёт дальше, чем порог взмаха мыши.
## В одиночной игре кнопки переклички G нет (#135; в сети её проверяет mp_doppel).
## Тап по центру карточки «Сейчас» не копает и не ставит; тап мимо UI копает.
## Раскладка: ландшафт 1280×720 и портрет 1280×2844 (как tools/ui_scale_test.gd).
## Кнопки и стик внутри safe-rect, стик и действия не на полосе хотбара; зоны
## захвата стика и «строить» не пересекаются и в ландшафте (кнопка в ряду боя),
## и в портрете. Меню и Q/V/G не на карточке задания. Меню и пауза внутри
## safe-rect. Холст — аргумент _layout, окно не трогаем: headless размер до кадра
## не применяет. Колонку I/J/паузы ландшафта не двигаем.

var tc: TouchControls = null
## Холсты как в ui_scale_test: ландшафт 1280×720 и портрет 1280×2844
## (1080×2400 при коэффициенте 2.5).
const LANDSCAPE: Vector2 = Vector2(1280, 720)
const PORTRAIT: Vector2 = Vector2(1280, 2844)


func run() -> void:
	clear_input()
	tc = get_tree().get_first_node_in_group("touch_controls")
	ok("сенсорное управление создано", tc != null)
	if tc == null:
		finish()
		return
	ok("без сенсорного экрана и --touch выключено (ПК не меняется)",
			not tc.enabled and not tc.visible and player.touch_input.is_empty())
	tc.set_enabled(true)
	ok("включается по запросу: шов игрока получил клавиши", tc.enabled and player.touch_input.has("keys"))
	await wait(0.1)
	ok("в одиночной игре кнопки G (перекличка) нет: не жмётся, колонка под миникартой на месте",
			not tc.rollcall_shown() and tc.control_at(tc.btn_center["g"]) != "g"
			and not bool(player.touch_input["keys"].get(KEY_G, false))
			and is_equal_approx(tc.btn_center["inv"].y, 126.0 + float(tc.btn_radius["inv"])),
			"под пальцем «%s», I на y=%.0f" % [tc.control_at(tc.btn_center["g"]), tc.btn_center["inv"].y])

	_layout_checks()
	await _mining_with_stick_held()
	await _walk_and_jump()
	await _card_tap_does_not_dig()
	await _smart_aim()
	await _pit_step_dig()
	await _pinch_zoom()
	await _windows_by_buttons()
	await _back_and_app_pause()

	_lift_all()
	await wait(0.1)
	tc.set_enabled(false)
	ok("после сценария мышь отпущена и шов пуст",
			not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and player.touch_input.is_empty())
	finish()


# ------------------------------------------------------------------ РАСКЛАДКА

## Раскладка на двух канвасах. Холст — аргумент _layout, не окно: headless
## root.size до кадра не применяет, а смена окна сдвинула бы следующие шаги.
## Касаний нет. Safe-area подставляем сами: headless её не отдаёт.
func _layout_checks() -> void:
	var saved_k: float = tc.force_k
	var saved_insets: Vector4 = tc.force_insets
	var saved_team: int = tc.force_team_rows
	var saved_scale: float = UI.ui_scale
	tc.force_insets = Vector4.ZERO
	tc.force_team_rows = 0
	_layout_on(LANDSCAPE, false, "ландшафт")
	_layout_on(PORTRAIT, true, "портрет")
	# Вырез: краевые элементы уходят внутрь. На desktop отступы нулевые — ветка выше.
	tc.force_insets = Vector4(40, 80, 24, 60)
	_layout_on(PORTRAIT, true, "портрет с вырезом")
	tc.force_insets = Vector4.ZERO
	# Плашка команды: headless сети не поднимает, строки задаём крючком.
	for n in [1, 4]:
		tc.force_team_rows = n
		_layout_on(PORTRAIT, true, "портрет, товарищей %d" % n)
		_team_plate_clear(PORTRAIT, n)
	tc.force_k = saved_k
	tc.force_insets = saved_insets
	tc.force_team_rows = saved_team
	# Прямое поле, не set_ui_scale: тот двигает панели, а следующие шаги бьют по ячейкам.
	UI.ui_scale = saved_scale
	tc._relayout()


func _layout_on(canvas: Vector2, portrait: bool, tag: String) -> void:
	# Портрет: dpi 420, окно 1080×2400 под холст 1280×2844 — пол MIN_MM (10 мм),
	# k упирается в 1.6 (как ui_scale_test): диаметр там около 7,8 мм, потолок
	# не поднимаем. Ландшафт 1280×720 — desktop/headless: dpi не раздувает
	# кнопки, k = 1. Иначе колонка I уехала бы.
	var win: Vector2 = Vector2(1080, 2400) if portrait else canvas
	var ppm: float = UI.px_per_mm(420, win, canvas) if portrait else 0.0
	tc.force_k = clampf(TouchControls.MIN_MM * ppm / (TouchControls.BTN_R * 2.0), 1.0, 1.6) if ppm > 0.0 else 1.0
	UI.ui_scale = 2.5 if portrait else 1.0
	tc.set_enabled(true)
	# _layout читает _layout_team, не _team_rows(): крючок надо положить до вызова.
	tc._layout_team = tc._team_rows()
	tc._layout(canvas)
	var insets: Vector4 = tc.safe_insets(canvas)
	var safe: Rect2 = Rect2(insets.x, insets.y, canvas.x - insets.x - insets.z,
			canvas.y - insets.y - insets.w)
	ok("%s: портрет определён как у HUD (h > w·1.2)" % tag, tc._portrait(canvas) == portrait,
			"%.0f×%.0f" % [canvas.x, canvas.y])
	ok("%s: safe-rect внутри канваса" % tag, safe.size.x > 0.0 and safe.size.y > 0.0
			and Rect2(Vector2.ZERO, canvas).encloses(safe), str(safe))
	var hotbar: Rect2 = _hotbar_band(canvas)
	var outside: Array = []
	var on_bar: Array = []
	for id in tc.btn_center:
		if not tc._shown(id, false):
			continue
		var rr: float = float(tc.btn_radius[id])
		var br: Rect2 = Rect2(tc.btn_center[id] - Vector2(rr, rr), Vector2(rr, rr) * 2.0)
		if not safe.encloses(br):
			outside.append("%s %s" % [id, str(br)])
		# Хотбар сидит над стиком и действиями. Верхние кнопки проверяем отдельно
		# против карточки — на полосу хотбара они не претендуют.
		if id in ["pause", "journal", "inv", "q", "v", "g"]:
			pass
		elif br.intersects(hotbar):
			on_bar.append("%s %s" % [id, str(br)])
	var sr: float = tc.stick_radius
	var stick: Rect2 = Rect2(tc.stick_center - Vector2(sr, sr), Vector2(sr, sr) * 2.0)
	if not safe.encloses(stick):
		outside.append("stick %s" % str(stick))
	if stick.intersects(hotbar):
		on_bar.append("stick %s" % str(stick))
	ok("%s: кнопки и стик внутри safe-rect" % tag, outside.is_empty(), ", ".join(outside))
	ok("%s: стик и кнопки действий не на полосе хотбара" % tag, on_bar.is_empty(),
			"%s; полоса %s" % [", ".join(on_bar), str(hotbar)])
	var pause_r: float = float(tc.btn_radius["pause"])
	var pause_br: Rect2 = Rect2(tc.btn_center["pause"] - Vector2(pause_r, pause_r),
			Vector2(pause_r, pause_r) * 2.0)
	ok("%s: меню/пауза внутри safe-rect" % tag, safe.encloses(pause_br), str(pause_br))
	if portrait:
		var card: Rect2 = _portrait_card(canvas)
		var on_card: Array = []
		for id in ["pause", "journal", "inv", "q", "v", "g"]:
			if not tc._shown(id, false):
				continue
			var cr: float = float(tc.btn_radius[id])
			var cbr: Rect2 = Rect2(tc.btn_center[id] - Vector2(cr, cr), Vector2(cr, cr) * 2.0)
			if cbr.intersects(card):
				on_card.append("%s %s" % [id, str(cbr)])
		ok("%s: меню и Q/V/G не на карточке задания" % tag, on_card.is_empty(),
				"%s; карточка %s" % [", ".join(on_card), str(card)])
	var build_r: float = float(tc.btn_radius["build"])
	var gap: float = tc.stick_center.distance_to(tc.btn_center["build"]) \
			- tc.stick_radius * TouchControls.STICK_GRAB - build_r * TouchControls.BTN_GRAB
	# «строить» в ряду боя справа, не над стиком: зазор >= 0 и в ландшафте, и в портрете.
	ok("%s: зоны захвата стика и «строить» не пересекаются (зазор ≥ 0)" % tag, gap >= 0.0,
			"зазор %.1f, центры %.0f" % [gap, tc.stick_center.distance_to(tc.btn_center["build"])])
	if portrait:
		ok("%s: стик слева внизу, действия справа внизу, меню сверху справа" % tag,
				tc.stick_center.x < canvas.x * 0.4 and tc.stick_center.y > canvas.y * 0.7
				and tc.btn_center["jump"].x > canvas.x * 0.6 and tc.btn_center["jump"].y > canvas.y * 0.7
				and tc.btn_center["pause"].x > canvas.x * 0.5 and tc.btn_center["pause"].y < canvas.y * 0.35
				and tc.btn_center["pause"].y < tc.btn_center["jump"].y * 0.5,
				"стик %s, прыжок %s, меню %s" % [str(tc.stick_center), str(tc.btn_center["jump"]),
				str(tc.btn_center["pause"])])
	else:
		# Прежняя ландшафтная формула: I на max(126, низ миникарты) + радиус, у правого края.
		var r: float = float(tc.btn_radius["inv"])
		var m: float = 24.0 * tc._k
		var expect_y: float = maxf(126.0, HUD.right_column_bottom(canvas.x / UI.ui_scale, 0) * UI.ui_scale + 8.0) + r
		var expect_x: float = canvas.x - m - r
		ok("%s: колонка I на прежнем месте (ландшафт не сдвинут)" % tag,
				is_equal_approx(tc.btn_center["inv"].y, expect_y)
				and is_equal_approx(tc.btn_center["inv"].x, expect_x),
				"I %s, ждали (%.0f, %.0f)" % [str(tc.btn_center["inv"]), expect_x, expect_y])

## Круги меню и Q/V/G не садятся на плашку команды. Прямоугольник — HUD.team_plate_rect
## в логических px, умноженный на ui_scale (как HUD._touch_rects переводит кнопки).
func _team_plate_clear(canvas: Vector2, n: int) -> void:
	var s: float = UI.ui_scale
	var logical: Rect2 = HUD.team_plate_rect(canvas.x / s, n)
	var plate: Rect2 = Rect2(logical.position * s, logical.size * s)
	var hit: Array = []
	var outside: Array = []
	for id in ["pause", "journal", "inv", "q", "v", "g"]:
		var rr: float = float(tc.btn_radius[id])
		var br: Rect2 = Rect2(tc.btn_center[id] - Vector2(rr, rr), Vector2(rr, rr) * 2.0)
		if br.intersects(plate):
			hit.append("%s %s" % [id, str(br)])
		if not Rect2(Vector2.ZERO, canvas).encloses(br):
			outside.append("%s %s" % [id, str(br)])
	ok("портрет, товарищей %d: меню и Q/V/G не на плашке команды" % n, hit.is_empty(),
			"%s; плашка %s" % [", ".join(hit), str(plate)])
	ok("портрет, товарищей %d: круги меню и Q/V/G внутри канваса" % n, outside.is_empty(),
			", ".join(outside))


## Карточка «Сейчас» в портрете, px канваса. HUD опускает её под ряд
## pause/journal/inv (низ круга + 4 лог. px), не ниже полосы мира. Ширина —
## до миникарты, не шире 65 % экрана (как HUD._compute_layout на таче).
func _portrait_card(canvas: Vector2) -> Rect2:
	var s: float = UI.ui_scale
	var w: float = canvas.x / s
	var row_bottom: float = HUD.CARD_Y
	for id in ["pause", "journal", "inv"]:
		var rr: float = float(tc.btn_radius[id])
		row_bottom = maxf(row_bottom, (tc.btn_center[id].y + rr) / s + 4.0)
	var card_y: float = row_bottom
	var cap: float = (w - HUD.MAP_OFFSET.x) - HUD.CARD_X - 8.0
	cap = minf(cap, w * 0.65)
	var cw: float = maxf(96.0, cap)
	return Rect2(Vector2(HUD.CARD_X, card_y) * s, Vector2(cw, HUD.CARD_H_TOUCH) * s)


## Полоса хотбара в px канваса — та же формула, что HUD._compute_layout на таче.
## Логические px × ui_scale. И в портрете, и в ландшафте полоса сидит над верхом
## стика и ряда боя: у края холста ряд боя её накрывал.
func _hotbar_band(canvas: Vector2) -> Rect2:
	var s: float = UI.ui_scale
	var w: float = canvas.x / s
	var n_slots: int = 6
	var bottom_top: float = (tc.stick_center.y - tc.stick_radius) / s
	for id in ["build", "e", "run", "jump"]:
		bottom_top = minf(bottom_top, (tc.btn_center[id].y - float(tc.btn_radius[id])) / s)
	var slot: float = clampf(floorf((w - 16.0) / float(n_slots)), 16.0, 42.0)
	var hy: float = bottom_top - 10.0 - (slot - 4.0)
	var hb_w: float = slot * float(n_slots) - 4.0
	var hx: float = (w - hb_w) * 0.5
	return Rect2(Vector2(hx, hy) * s, Vector2(hb_w, slot - 4.0) * s)


# ------------------------------------------------------------------ ШАГИ

## Палец 0 — джойстик в центре (он же эмулирует мышь), палец 1 копает тайл.
func _mining_with_stick_held() -> void:
	await wait(0.4)
	_settle_camera()
	await wait(0.2)
	var cell: Vector2i = find_mineable()
	ok("найден тайл для копки тапом", cell.x >= 0, str(cell))
	if cell.x < 0:
		return
	var before: int = World.get_tile_v(cell)
	var x0: float = player.global_position.x
	_touch(0, tc.stick_center, true)
	await wait(0.3)
	ok("эмулированный клик под джойстиком не копает мир",
			Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and player.mining_progress <= 0.0,
			"ЛКМ эмулирована: %s, прогресс %.2f" % [Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),
			player.mining_progress])
	_touch(1, _screen(World.cell_to_world(cell)), true)
	await wait(0.35)
	ok("второй палец копает, пока первый на джойстике", player.mining_cell == cell
			and player.mining_progress > 0.0, "%s, прогресс %.2f" % [str(player.mining_cell), player.mining_progress])
	var broke: bool = await wait_until(func() -> bool: return World.get_tile_v(cell) != before, 6.0)
	ok("удержание тапа докапывает тайл", broke, DB.tile_name(before))
	ok("герой при этом стоял (джойстик в мёртвой зоне)", absf(player.global_position.x - x0) < 4.0,
			"%.1f px" % (player.global_position.x - x0))
	await wait(0.6)
	ok("докопал и держит палец — на месте тайла ничего не ставится",
			World.get_tile_v(cell) == IDs.T.AIR, DB.tile_name(World.get_tile_v(cell)))
	# Оба пальца сразу: джойстик вправо и палец на мире — шов видит и то и другое.
	# Пустую клетку умный прицел (#149) не копает — возвращаем тайл под палец.
	World.set_tile(cell.x, cell.y, before)
	_drag(0, tc.stick_center + Vector2(tc.stick_radius * 0.9, 0.0))
	await wait(0.1)
	var keys: Dictionary = player.touch_input.get("keys", {})
	var mb: Dictionary = player.touch_input.get("mouse_buttons", {})
	ok("мультитач: идти и копать одновременно", bool(keys.get(KEY_D, false))
			and bool(mb.get(MOUSE_BUTTON_LEFT, false)))
	# Джойстик и палец по миру — не щипок: палец на джойстике в зум не идёт, как его ни веди.
	var z0: float = player.view_zoom.current
	_drag(0, tc.stick_center + Vector2(-tc.stick_radius * 0.9, -tc.stick_radius * 0.5))
	_drag(1, _screen(World.cell_to_world(cell)) + Vector2(4.0, 0.0))
	await wait(0.1)
	ok("джойстик + палец по миру не зумят и копка не сбрасывается",
			is_equal_approx(player.view_zoom.current, z0) and tc.aim_cell == cell
			and bool(player.touch_input.get("mouse_buttons", {}).get(MOUSE_BUTTON_LEFT, false)),
			"зум %.2f → %.2f, цель %s" % [z0, player.view_zoom.current, str(tc.aim_cell)])
	# Кнопка (бег, прыжок) и палец по миру — тоже не щипок.
	_touch(2, tc.btn_center["e"], true)
	await wait(0.1)
	ok("кнопка + палец по миру не зумят", is_equal_approx(player.view_zoom.current, z0)
			and tc.aim_cell == cell)
	_touch(2, tc.btn_center["e"], false)
	_touch(1, _screen(World.cell_to_world(cell)), false)
	_touch(0, tc.stick_center, false)
	await wait(0.2)
	ok("пальцы сняты — мышь снова своя", not player.touch_input.has("mouse_buttons"))


## Джойстик вправо — идёт; тап по кнопке прыжка — прыгает; джойстик вверх — прыгает.
func _walk_and_jump() -> void:
	stand_in_corridor(2)
	_settle_camera()
	await wait(0.6)
	var x0: float = player.global_position.x
	_touch(0, tc.stick_center, true)
	_drag(0, tc.stick_center + Vector2(tc.stick_radius * 0.9, 0.0))
	await wait(0.6)
	_touch(0, tc.stick_center, false)
	var dx: float = player.global_position.x - x0
	ok("джойстик вправо двигает героя", dx > 24.0, "%.1f px" % dx)
	await wait(0.4)

	await wait_until(func() -> bool: return player.on_ground, 1.5)
	var y0: float = player.global_position.y
	# Нажатие и отпускание в одном кадре — короткий тап не теряется.
	_touch(2, tc.btn_center["jump"], true)
	_touch(2, tc.btn_center["jump"], false)
	var rose: bool = await wait_until(func() -> bool: return player.global_position.y < y0 - 8.0, 0.6)
	ok("короткий тап по кнопке прыжка — прыжок", rose, "%.1f px" % (y0 - player.global_position.y))
	await wait_until(func() -> bool: return player.on_ground, 2.0)
	await wait(0.2)
	y0 = player.global_position.y
	_touch(0, tc.stick_center, true)
	_drag(0, tc.stick_center + Vector2(0.0, -tc.stick_radius))
	rose = await wait_until(func() -> bool: return player.global_position.y < y0 - 8.0, 0.6)
	_touch(0, tc.stick_center, false)
	ok("джойстик вверх — прыжок", rose, "%.1f px" % (y0 - player.global_position.y))
	await wait_until(func() -> bool: return player.on_ground, 2.0)


## Тап по центру карточки «Сейчас» не копает и не ставит — ни клетку под пальцем,
## ни клетку по лучу к ней. Тап по тайлу мимо UI копает.
func _card_tap_does_not_dig() -> void:
	var base: int = stand_in_corridor(8)
	# Зум 1 и без сглаживания: центр карточки — известная мировая точка рядом с героем.
	# Иначе камера (зум 2.2, сглаживание) не догоняет, и тап целится мимо радиуса.
	player.view_zoom.set_now(1.0)
	player.camera.position_smoothing_enabled = false
	_settle_camera()
	await wait(0.3)
	var logical: Rect2 = UI.hud.layout_rect("card")
	ok("карточка «Сейчас» на экране", logical.size != Vector2.ZERO and UI.hud.card_text != "",
			UI.hud.card_text)
	var card: Rect2 = Rect2(logical.position * UI.ui_scale, logical.size * UI.ui_scale)
	var center: Vector2 = card.get_center()
	var screen_of_feet: Vector2 = _screen(player.global_position)
	var under_world: Vector2 = player.global_position + (center - screen_of_feet) / player.camera.zoom.x
	var under: Vector2i = World.world_to_cell(under_world)
	var pc: Vector2i = World.world_to_cell(player.global_position)
	# Воздух на луче от героя к центру карточки и рядом: проскочивший тап поставит камень.
	for y in range(under.y, pc.y):
		for x in range(mini(under.x, pc.x) - 1, maxi(under.x, pc.x) + 2):
			if World.get_tile_v(Vector2i(x, y)) != IDs.T.AIR:
				World.set_tile(x, y, IDs.T.AIR)
	player.inv.slots[0] = ItemStack.new(IDs.I.STONE, 8)
	player.inv.selected = 0
	tc.build_mode = true
	var stones: int = player.inv.slots[0].count
	var snap: Dictionary = {}
	for y in range(under.y - 1, pc.y + 1):
		for x in range(pc.x - 8, pc.x + 8):
			snap[Vector2i(x, y)] = World.get_tile_v(Vector2i(x, y))
	_touch(1, center, true)
	await wait(0.6)
	var changed: Array = []
	for c in snap:
		if World.get_tile_v(c) != int(snap[c]):
			changed.append(c)
	var finger: String = String(tc._fingers.get(1, {}).get("kind", ""))
	ok("тап по центру карточки не копает и не ставит", changed.is_empty()
			and player.inv.slots[0].count == stones and player.mining_progress <= 0.0
			and tc.aim_cell == TouchControls.NO_CELL and finger != "world",
			"изменено %s, камней %d → %d, копка %.2f, цель %s, палец %s" % [str(changed),
			stones, player.inv.slots[0].count, player.mining_progress, str(tc.aim_cell),
			String(tc._fingers.get(1, {}).get("kind", ""))])
	_touch(1, center, false)
	await wait(0.2)
	for c in changed:
		World.set_tile(c.x, c.y, int(snap[c]))
	# Тап мимо UI по камню рядом с героем — копает. Точка не на карточке и не на кнопке.
	tc.build_mode = false
	player.inv.selected = 0
	player.inv.slots[0] = ItemStack.new()
	pc = World.world_to_cell(player.global_position)
	var free: Vector2i = Vector2i(pc.x + 2, base - 1)
	World.set_tile(free.x, free.y, IDs.T.STONE)
	var free_screen: Vector2 = _screen(World.cell_to_world(free))
	ok("свободный тайл не под карточкой и не на кнопке",
			not card.has_point(free_screen) and tc.control_at(free_screen) == "",
			"%s экран %s карточка %s кнопка «%s»" % [str(free), str(free_screen), str(card),
			tc.control_at(free_screen)])
	_touch(1, free_screen, true)
	await wait(0.35)
	ok("тап по свободному тайлу мимо UI копает", player.mining_cell == free and player.mining_progress > 0.0,
			"копается %s, прогресс %.2f, цель %s" % [str(player.mining_cell), player.mining_progress,
			str(tc.aim_cell)])
	_touch(1, free_screen, false)
	await wait(0.15)
	World.set_tile(free.x, free.y, IDs.T.AIR)
	# Герой стоял под карточкой — возвращаем его в коридор, иначе следующие шаги
	# целятся мимо экрана.
	player.view_zoom.set_now(ViewZoom.DEFAULT)
	player.camera.position_smoothing_enabled = true
	stand_in_corridor(3)
	_settle_camera()
	await wait(0.3)


## Тап по хотбару выбирает слот и режим; умный прицел (#149) ставит и копает, даже
## когда палец не попал в клетку.
func _smart_aim() -> void:
	var base: int = stand_in_corridor(3)
	_settle_camera()
	await wait(0.6)
	# Хотбар на телефоне — 6 ячеек (#161): 6-я выбирается, пустое место за ней — нет.
	player.apply_hotbar_size(Inventory.HOTBAR_MIN)
	player.inv.slots[5] = ItemStack.new(IDs.I.STONE, 10)
	_tap(3, UI.hud.hotbar_slot_rect(5).get_center())
	await wait(0.1)
	ok("тап по хотбару выбирает слот, блок в руке включает «строить»",
			player.inv.selected == 5 and tc.build_mode, "слот %d, строить %s" % [player.inv.selected, tc.build_mode])

	var pc: Vector2i = World.world_to_cell(player.global_position)
	var near: Vector2i = Vector2i(pc.x + 1, base - 1)
	var a: Vector2i = Vector2i(pc.x + 2, base - 1)
	var far: Vector2i = Vector2i(pc.x + 9, base - 1)
	ok("рядом пустые клетки под постройку", World.get_tile_v(near) == IDs.T.AIR
			and World.get_tile_v(a) == IDs.T.AIR, "%s %s" % [str(near), str(a)])

	# Короткий тап по свободной клетке — блок; палец держится — второй не ставится.
	var stones: int = player.inv.slots[5].count
	_touch(1, _screen(World.cell_to_world(a)), true)
	var placed: bool = await wait_until(func() -> bool: return World.get_tile_v(a) == IDs.T.STONE, 0.6)
	await wait(0.5)
	_touch(1, _screen(World.cell_to_world(a)), false)
	ok("тап по свободной клетке ставит один блок (палец держится — второй не встаёт)",
			placed and player.inv.slots[5].count == stones - 1 and World.get_tile_v(near) == IDs.T.AIR,
			"камней %d → %d" % [stones, player.inv.slots[5].count])

	# Тап далеко за камнем (за радиусом): блок встаёт перед камнем, со своей стороны.
	_touch(1, _screen(World.cell_to_world(far)), true)
	placed = await wait_until(func() -> bool: return World.get_tile_v(near) == IDs.T.STONE, 0.6)
	_touch(1, _screen(World.cell_to_world(far)), false)
	ok("тап за препятствием и радиусом ставит блок со своей стороны", placed,
			DB.tile_name(World.get_tile_v(near)))

	# Пустое место за 6-й ячейкой — не хотбар: слот и режим не меняются.
	var past: Rect2 = UI.hud.hotbar_slot_rect(5)
	_tap(3, past.get_center() + Vector2(past.size.x + 8.0, 0.0))
	await wait(0.1)
	ok("тап за 6-й ячейкой хотбара ничего не выбирает", player.inv.selected == 5 and tc.build_mode,
			"слот %d" % player.inv.selected)
	# Пустая ячейка хотбара — «копать»; тап за радиусом копает ближнюю стену по лучу.
	player.inv.slots[4] = ItemStack.new()
	_tap(3, UI.hud.hotbar_slot_rect(4).get_center())
	await wait(0.1)
	ok("пустая ячейка хотбара включает «копать»", player.inv.selected == 4 and not tc.build_mode)
	_touch(1, _screen(World.cell_to_world(far)), true)
	await wait(0.1)
	ok("тап за радиусом целит в ближнюю стену по лучу", tc.aim_cell == near, str(tc.aim_cell))
	var dug: bool = await wait_until(func() -> bool: return World.get_tile_v(near) == IDs.T.AIR, 6.0)
	_touch(1, _screen(World.cell_to_world(far)), false)
	ok("удержание выкапывает её", dug, DB.tile_name(World.get_tile_v(near)))
	await wait(0.1)
	ok("палец снят — цели нет", tc.aim_cell == TouchControls.NO_CELL)

	# Палец на полклетки мимо камня (над ним, в воздухе) — копаем камень.
	World.set_tile(a.x, a.y, IDs.T.AIR)
	var rock: Vector2i = Vector2i(pc.x + 3, base - 1)
	World.set_tile(rock.x, rock.y, IDs.T.STONE)
	var miss: Vector2 = World.cell_to_world(rock + Vector2i(0, -1)) + Vector2(0.0, 5.0)
	_touch(1, _screen(miss), true)
	await wait(0.15)
	ok("тап на полклетки мимо камня целит в камень", tc.aim_cell == rock and player.mining_cell == rock,
			"%s, копается %s" % [str(tc.aim_cell), str(player.mining_cell)])
	_touch(1, _screen(miss), false)
	await wait(0.1)
	World.set_tile(rock.x, rock.y, IDs.T.AIR)
	await _phantom_off_finger()


## Герой на дне ямы, на тайл ниже цели; цель слева вплотную. Тап по центру
## подсвеченной клетки (путь TouchControls → шов → Player._do_mining) начинает
## копку. На старом коде луч из центра клетки героя в центр цели касается только
## угла и отбрасывается: aim пуст, прогресса нет.
func _pit_step_dig() -> void:
	clear_input()
	tc.build_mode = false
	var floor_y: int = stand_in_corridor(5)
	await wait(0.3)
	var hx: int = int(floor(player.global_position.x / float(World.TILE)))
	var feet: Vector2i = Vector2i(hx, floor_y)
	var target: Vector2i = Vector2i(hx - 1, floor_y - 1)
	for dx in range(-1, 3):
		World.set_tile(hx + dx, floor_y - 1, IDs.T.AIR)
		World.set_tile(hx + dx, floor_y - 2, IDs.T.AIR)
	World.set_tile(feet.x, feet.y, IDs.T.AIR)
	World.set_tile(target.x, target.y, IDs.T.STONE)
	World.set_tile(feet.x, feet.y + 1, IDs.T.STONE)
	World.set_tile(target.x, target.y + 1, IDs.T.STONE)
	player.global_position = Vector2(float(feet.x * World.TILE) + 8.0,
			float((feet.y + 1) * World.TILE) - 12.0)
	player.vel = Vector2.ZERO
	player.facing = -1
	player.mining_progress = 0.0
	player.mining_cell = Vector2i(-1, -1)
	player.camera.position_smoothing_enabled = false
	_settle_camera()
	await wait(0.3)
	var stood: Vector2i = World.world_to_cell(player.global_position)
	ok("яма: герой на тайл ниже цели, цель слева вплотную",
			stood == feet and target == feet + Vector2i(-1, -1)
			and World.get_tile_v(target) == IDs.T.STONE and player.facing < 0,
			"ноги %s цель %s" % [str(stood), str(target)])
	# Палец в центр подсвеченного тайла. Луч из центра клетки героя идёт в этот
	# центр через общий угол: пол под целью только касается угла и не должен
	# перехватывать копку.
	var tap: Vector2 = World.cell_to_world(target)
	var origin: Vector2 = World.cell_to_world(stood)
	var ray: Vector2i = World.first_solid_on_ray(origin, tap, true, true)
	ok("луч в центр тайла ямы бьёт в него, а не в пол под ним",
			ray == target, "луч %s, пол %s" % [str(ray), str(Vector2i(target.x, feet.y))])
	_touch(1, _screen(tap), true)
	await wait(0.35)
	ok("тап по подсвеченному тайлу ямы начинает копку",
			tc.aim_cell == target and player.mining_cell == target and player.mining_progress > 0.0,
			"aim %s, копается %s, прогресс %.3f, луч %s" % [str(tc.aim_cell),
			str(player.mining_cell), player.mining_progress, str(ray)])
	var broke: bool = await wait_until(func() -> bool: return World.get_tile_v(target) == IDs.T.AIR, 6.0)
	_touch(1, _screen(tap), false)
	ok("удержание тапа выкапывает тайл ямы", broke, DB.tile_name(World.get_tile_v(target)))
	await wait(0.15)
	# ЛКМ в ту же точку не расходится с тапом: восстанавливаем тайл и целимся мышью.
	World.set_tile(target.x, target.y, IDs.T.STONE)
	player.mining_progress = 0.0
	player.mining_cell = Vector2i(-1, -1)
	aim(tap)
	press_mouse(MOUSE_BUTTON_LEFT)
	await wait(0.3)
	ok("ЛКМ в ту же точку ямы тоже копает этот тайл",
			player.mining_cell == target and player.mining_progress > 0.0,
			"копается %s, прогресс %.3f" % [str(player.mining_cell), player.mining_progress])
	release_mouse(MOUSE_BUTTON_LEFT)
	clear_input()
	player.camera.position_smoothing_enabled = true
	stand_in_corridor(3)
	_settle_camera()
	await wait(0.2)


## Тап по фантому на 21–26 px от тела: прицел берёт его (PHANTOM_GRAB 26), взмах
## мыши — только ближе 20. Удар обязан пройти. Шов test_input пуст: иначе ветка
## мыши порог 20 не проверяет. Эхо за PINCH_WAIT (~67 мс) уходит на ~10 px и
## выпадает из захвата — стоим на месте, пока ждём кадр удара.
func _phantom_off_finger() -> void:
	stand_in_corridor(6)
	player.invuln = 1.0e9
	player.slash_cd = 0.0
	_settle_camera()
	await wait(0.3)
	ok("перед ударом шов сценария пуст", player.test_input.is_empty())
	var foe_pos: Vector2 = player.global_position + Vector2(48.0, -20.0)
	var ph: Node = spawn_phantom_at(foe_pos, "echo")
	ok("эхо для удара с промахом пальца появилось", ph != null and is_instance_valid(ph))
	if ph == null:
		return
	var off: Vector2 = Vector2(24.0, 0.0)
	var tap: Vector2 = ph.global_position + off
	ok("палец дальше порога мыши и внутри захвата прицела",
			tap.distance_to(ph.global_position) > 20.0
			and tap.distance_to(ph.global_position) <= TouchControls.PHANTOM_GRAB
			and ph.global_position.distance_to(player.global_position) <= Player.REACH,
			"до пальца %.1f, до героя %.1f" % [tap.distance_to(ph.global_position),
			ph.global_position.distance_to(player.global_position)])
	var hp0: float = ph.hp
	# Эхо само ходит (160 px/с) и за PINCH_WAIT выходит из захвата 26 px.
	# Держим точку, пока палец не дойдёт до удара: проверяем порог, не погоню.
	ph.set_physics_process(false)
	ph.global_position = foe_pos
	ph.vel = Vector2.ZERO
	_touch(1, _screen(tap), true)
	var hit: bool = await wait_until(func() -> bool:
		if is_instance_valid(ph):
			ph.global_position = foe_pos
			ph.vel = Vector2.ZERO
		return is_instance_valid(ph) and ph.hp < hp0, 0.4)
	if is_instance_valid(ph):
		ph.set_physics_process(true)
	_touch(1, _screen(tap), false)
	ok("тап по фантому на 21–26 px — удар проходит", hit and player.slash_cd > 0.0,
			"hp %.0f → %.0f, slash_cd %.2f, прицел %s" % [hp0,
			ph.hp if is_instance_valid(ph) else -1.0, player.slash_cd, tc.aim_foe])
	if is_instance_valid(ph):
		ph.queue_free()
	await wait(0.15)


## Щипок: второй палец лёг на мир чуть позже первого (как у человека) — оба ведут зум,
## прицела нет, в режиме «строить» ни один блок не встаёт. Короткий тап ставит блок.
func _pinch_zoom() -> void:
	var base: int = stand_in_corridor(4)
	var vz: ViewZoom = player.view_zoom
	vz.set_now(ViewZoom.DEFAULT)
	_settle_camera()
	await wait(0.6)
	player.apply_hotbar_size(Inventory.HOTBAR_MIN)
	player.inv.slots[5] = ItemStack.new(IDs.I.STONE, 10)
	_tap(3, UI.hud.hotbar_slot_rect(5).get_center())
	await wait(0.1)
	ok("щипок проверяем в режиме «строить»", tc.build_mode)
	var stones: int = player.inv.slots[5].count
	var c: Vector2 = _screen(player.global_position) + Vector2(0.0, -30.0)
	_touch(4, c + Vector2(-50.0, 0.0), true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_touch(5, c + Vector2(50.0, 0.0), true)
	await wait(0.1)
	ok("второй палец на мире — щипок, прицела нет", tc.aim_cell == TouchControls.NO_CELL
			and not bool(player.touch_input.get("mouse_buttons", {}).get(MOUSE_BUTTON_RIGHT, false)))
	_drag(4, c + Vector2(-100.0, 0.0))
	_drag(5, c + Vector2(100.0, 0.0))
	await wait(0.1)
	ok("пальцы разошлись вдвое — зум вдвое ближе (до MAX)",
			is_equal_approx(vz.current, minf(ViewZoom.DEFAULT * 2.0, ViewZoom.MAX))
			and is_equal_approx(player.camera.zoom.x, vz.current), "%.3f" % vz.current)
	_drag(4, c + Vector2(-25.0, 0.0))
	_drag(5, c + Vector2(25.0, 0.0))
	await wait(0.1)
	ok("свели — зум дальше, не дальше MIN",
			is_equal_approx(vz.current, maxf(ViewZoom.DEFAULT * 0.5, ViewZoom.MIN)), "%.3f" % vz.current)
	_touch(4, c + Vector2(-25.0, 0.0), false)
	await wait(0.3)
	ok("один палец щипка отпущен — второй не строит", tc.aim_cell == TouchControls.NO_CELL
			and player.inv.slots[5].count == stones)
	_touch(5, c + Vector2(25.0, 0.0), false)
	await wait(0.2)
	ok("щипок не поставил ни блока", player.inv.slots[5].count == stones,
			"камней %d → %d" % [stones, player.inv.slots[5].count])

	vz.set_now(ViewZoom.DEFAULT)
	_settle_camera()
	await wait(0.2)
	var pc: Vector2i = World.world_to_cell(player.global_position)
	var cell: Vector2i = Vector2i(pc.x + 2, base - 1)
	_tap(4, _screen(World.cell_to_world(cell)))
	var placed: bool = await wait_until(func() -> bool: return World.get_tile_v(cell) == IDs.T.STONE, 0.6)
	ok("короткий тап (быстрее ожидания щипка) ставит блок", placed and player.inv.slots[5].count == stones - 1,
			DB.tile_name(World.get_tile_v(cell)))
	World.set_tile(cell.x, cell.y, IDs.T.AIR)
	player.inv.slots[4] = ItemStack.new()
	_tap(3, UI.hud.hotbar_slot_rect(4).get_center())
	await wait(0.1)


## I и J открывают и закрывают окна; при открытом окне тап по миру не копает.
func _windows_by_buttons() -> void:
	_tap(2, tc.btn_center["inv"])
	await wait(0.2)
	ok("кнопка I открывает инвентарь", UI.panel.visible)
	# Палец листает рецепты. Событие — прямо в _gui_input панели: в headless
	# вьюпорт касания до контролов не доводит (как и мышь, см. inventory_transfer).
	var panel: InventoryPanel = UI.panel
	# Тап по ячейке — эмулированный из касания клик ЛКМ: стопка в руку и обратно.
	var slot_pos: Vector2 = panel._inv_slot_rect(0).get_center()
	var id0: int = player.inv.slots[0].id
	_panel_tap(panel, slot_pos)
	var took: bool = panel.held.id == id0 and player.inv.slots[0].is_empty()
	_panel_tap(panel, slot_pos)
	ok("тап по ячейке инвентаря: стопка в руку и обратно", took and panel.held.is_empty()
			and player.inv.slots[0].id == id0, DB.item_name(id0))
	if panel._max_scroll() >= 2:
		# Прокрутка панели живёт между сценариями (предыдущий мог оставить её
		# внизу) — проверка листания должна начинаться с нуля.
		panel.scroll = 0
		var s0: int = panel.scroll
		_panel_drag(panel, -InventoryPanel.RECIPE_H * 2.2)
		var s1: int = panel.scroll
		_panel_drag(panel, InventoryPanel.RECIPE_H * 2.2)
		ok("палец листает рецепты вниз и обратно", s1 == s0 + 2 and panel.scroll == s0,
				"%d → %d → %d" % [s0, s1, panel.scroll])
	var cell: Vector2i = find_mineable()
	if cell.x >= 0:
		_touch(1, _screen(World.cell_to_world(cell)), true)
		await wait(0.4)
		ok("при открытом инвентаре тап по миру не копает", player.mining_progress <= 0.0,
				"прогресс %.2f" % player.mining_progress)
		_touch(1, _screen(World.cell_to_world(cell)), false)
	ok("при открытом окне кнопка I на месте, джойстик спрятан",
			tc.control_at(tc.btn_center["inv"]) == "inv" and tc.control_at(tc.stick_center) == "")
	_tap(2, tc.btn_center["inv"])
	await wait(0.2)
	ok("повторный тап по I закрывает инвентарь", not UI.panel.visible)
	_tap(2, tc.btn_center["journal"])
	await wait(0.2)
	ok("кнопка J открывает журнал", UI.journal.visible)
	_tap(2, tc.btn_center["journal"])
	await wait(0.2)
	ok("повторный тап по J закрывает журнал", not UI.journal.visible and not UI.blocking())
	# Пауза (#119): ESC на телефоне нет — кнопка «меню» рядом с J; в паузе кнопок нет.
	_tap(2, tc.btn_center["pause"])
	await get_tree().process_frame
	await get_tree().process_frame
	ok("кнопка «меню» открывает паузу (дерево стоит), кнопок и джойстика нет", UI.pause.visible
			and get_tree().paused and tc.control_at(tc.btn_center["inv"]) == ""
			and tc.control_at(tc.btn_center["pause"]) == "" and tc.control_at(tc.stick_center) == "")
	UI.pause.continue_button.pressed.emit()
	ok("«Продолжить» — пауза закрыта, кнопка «меню» снова жмётся", not UI.pause.visible
			and not get_tree().paused and tc.control_at(tc.btn_center["pause"]) == "pause")


## «Назад» Android (#149): окно — закрыть, иначе пауза; в паузе — продолжить. Свернули
## приложение — пауза и сохранение в слот F5.
func _back_and_app_pause() -> void:
	ok("приложение не закрывается само по «Назад»",
			not bool(ProjectSettings.get_setting("application/config/quit_on_go_back", true)))
	_tap(2, tc.btn_center["inv"])
	await wait(0.2)
	get_tree().root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await get_tree().process_frame
	ok("«Назад» закрывает инвентарь, паузы нет", not UI.panel.visible and not UI.pause.visible)
	get_tree().root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await get_tree().process_frame
	ok("«Назад» открывает паузу", UI.pause.visible and get_tree().paused)
	get_tree().root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await get_tree().process_frame
	ok("ещё раз «Назад» — пауза закрыта", not UI.pause.visible and not get_tree().paused)
	Save.remove(Save.slot)
	UI.app_paused()
	ok("свернули приложение — пауза и сохранение в слот F5", UI.pause.visible and get_tree().paused
			and Save.exists(Save.slot), Save.path_for(Save.slot))
	# close() молчит, если «Назад» уже закрыл панель, а дерево всё ещё стоит:
	# следующий сценарий в том же процессе тогда не двигается.
	UI.pause.close()
	get_tree().paused = false
	Save.remove(Save.slot)
	await get_tree().process_frame


# ------------------------------------------------------------------ КАСАНИЯ

var _down: Dictionary = {}   ## индекс пальца -> последняя точка


## Экранная точка (координаты вьюпорта) мировой позиции.
func _screen(world: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world


## Вьюпорт → окно: события Input.parse_input_event приходят в координатах окна.
func _win(pos: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * pos


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e: InputEventScreenTouch = InputEventScreenTouch.new()
	e.index = index
	e.position = _win(pos)
	e.pressed = pressed
	Input.parse_input_event(e)
	if pressed:
		_down[index] = pos
	else:
		_down.erase(index)


func _drag(index: int, pos: Vector2) -> void:
	var e: InputEventScreenDrag = InputEventScreenDrag.new()
	e.index = index
	e.position = _win(pos)
	e.relative = _win(pos) - _win(Vector2(_down.get(index, pos)))
	Input.parse_input_event(e)
	_down[index] = pos


## Тап по панели так, как его видит панель на телефоне: ЛКМ с device эмуляции.
func _panel_tap(panel: InventoryPanel, pos: Vector2) -> void:
	for pressed in [true, false]:
		var e: InputEventMouseButton = InputEventMouseButton.new()
		e.device = InputEvent.DEVICE_ID_EMULATION
		e.button_index = MOUSE_BUTTON_LEFT
		e.position = pos
		e.pressed = pressed
		panel._gui_input(e)


func _panel_drag(panel: InventoryPanel, dy: float) -> void:
	var e: InputEventScreenDrag = InputEventScreenDrag.new()
	e.position = panel._list_rect().get_center()
	e.relative = Vector2(0.0, dy)
	panel._gui_input(e)


## Короткий тап: нажатие и отпускание подряд.
func _tap(index: int, pos: Vector2) -> void:
	_touch(index, pos, true)
	_touch(index, pos, false)


func _lift_all() -> void:
	for i in _down.keys():
		_touch(int(i), Vector2(_down[i]), false)


## Камера догоняет героя плавно; для тапов по миру ставим её сразу на место.
func _settle_camera() -> void:
	player.camera.reset_smoothing()
