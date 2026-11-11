extends ScenarioBase
## Глитч по событию и «меньше глитча» (ADR-003 V7, #108).
##
## Проверяет: в простое GlitchFx не работает и не плодит узлов; по событию —
## старт релея, отметка отсчёта удержания, браун-аут, телеграф вентиляции рядом,
## раскрытие и удар двойника — шейдер включается и гаснет не позже GlitchFx.MAX_SEC;
## вентиляция вне экрана и слабое событие поверх сильного эффекта не дают; при
## «меньше глитча» шейдер не включается (важные события — спокойная вспышка),
## расслоение фантома не мигает; настройка — одно поле профиля туда-обратно.
##
## Рендер кадров эффекта (нужно окно — ЗА ЭКРАНОМ):
##   godot --path . --audio-driver Dummy --windowed --position -10000,-10000 \
##         --resolution 1280x720 -- --scenario=glitch_fx --seed=31337 --glitch-shot
## → docs/img/glitch_<вид>.png: слева кадр до события, справа — во время эффекта.

## Временный профиль теста — свой у процесса (TestEnv.file, #132): параллельные прогоны не мешают.
const TMP_PROFILE: String = "user://glitch_fx_test/profile.cfg"
const SHOT_DIR: String = "res://docs/img/"

var fx: GlitchFx = null
var _shots: bool = false


func run() -> void:
	_shots = OS.get_cmdline_user_args().has("--glitch-shot") and DisplayServer.get_name() != "headless"
	stand_in_corridor(3)
	clear_input()
	player.invuln = 1.0e9
	for c in scene.get_children():
		if c is GlitchFx:
			fx = c
	ok("GlitchFx в сцене (main.gd)", fx != null)
	if fx == null:
		finish()
		return
	var calm0: bool = GlitchFx.calm
	GlitchFx.set_calm(false)
	fx.reset()   # паузы событий от прошлых сценариев (релей, питание) — долой
	await wait(0.6)

	# --- 1. Простой: эффект не идёт, _process выключен, новых узлов нет.
	var n0: int = get_tree().get_node_count()
	var n_max: int = n0
	var f0: int = fx.stat_fired + fx.stat_calm
	var t0: float = now_proc()
	while now_proc() - t0 < (0.5 if _shots else 2.0):
		await get_tree().process_frame
		n_max = maxi(n_max, get_tree().get_node_count())
	ok("простой: эффекта нет, _process выключен", not fx.active() and not fx.is_processing()
			and fx.stat_fired + fx.stat_calm == f0)
	ok("простой: 0 новых узлов", n_max == n0 and get_tree().get_node_count() == n0,
			"%d → %d (макс %d)" % [n0, get_tree().get_node_count(), n_max])

	var bp: Vector2 = World.cell_to_world(World.beacon_cell)
	# --- 2. Старт релея (этап 3) — блоки у излучателя.
	await _shot_before()
	Game.objective_changed.emit(3)
	ok("релей запущен → блоки у релея", fx.glitch_active() and fx.active_name() == "relay_start",
			fx.active_name())
	await _shot_after("glitch_relay", bp)
	await _expect_off("relay_start")

	# Отметка отсчёта удержания — «приём сигнала». Этап 3 ставим заранее: иначе
	# Game сам перейдёт на него (relay_active) и «релей запущен» перебьёт сигнал.
	var stage0: int = Game.objective_stage
	Game.objective_stage = 3
	Game.relay_active = true
	Game.relay_timer = 30.5
	fx._wake()
	await wait(0.1)
	Game.relay_timer = 29.9
	var got: bool = await wait_until(func(): return fx.active_name() == "relay_signal", 0.5)
	ok("отметка отсчёта релея → приём сигнала", got)
	Game.relay_active = false
	Game.relay_timer = 0.0
	Game.objective_stage = stage0
	await _expect_off("relay_signal")

	# --- 3. Браун-аут — разрыв строк по всему экрану.
	await _shot_before()
	Game.brownout_changed.emit(true)
	ok("браун-аут → разрыв строк", fx.glitch_active() and fx.active_name() == "brownout")
	await _shot_after("glitch_brownout", player.global_position)
	Game.brownout_changed.emit(false)
	ok("конец браун-аута эффекта не даёт", fx.active_name() == "brownout")
	await _expect_off("brownout")

	# --- 4. Вентиляция: рядом — блоки, далеко (вне экрана) — ничего.
	var near: Vector2i = World.world_to_cell(player.global_position) + Vector2i(4, -2)
	var skipped0: int = fx.stat_skipped
	Threat.vent_warning.emit(near + Vector2i(400, 0))
	ok("вентиляция вне экрана — без эффекта", not fx.active() and fx.stat_skipped == skipped0 + 1)
	Threat.vent_warning.emit(near)
	ok("вентиляция рядом → блоки у решётки", fx.active_name() == "vent")
	# Слабое событие поверх сильного не перебивает его; сильное перебивает слабое.
	Game.objective_changed.emit(4)
	ok("сильное событие перебивает слабое", fx.active_name() == "relay_start")
	Threat.vent_warning.emit(near)
	ok("слабое событие не перебивает сильное", fx.active_name() == "relay_start")
	await _expect_off("relay_start")
	Threat.vent_warning.emit(near)
	ok("пауза события: вентиляция подряд — без эффекта", not fx.active())

	# --- 5. Двойник: удар (за спиной героя) и раскрытие (под взглядом).
	hold(KEY_D)
	await wait(0.06)
	release(KEY_D)
	await wait(0.3)
	var strikes0: int = fx.stat_by_kind[GlitchFx.Kind.DOPPEL_STRIKE]
	player.invuln = 0.0
	player.hp = 1000.0
	var back: Node = spawn_phantom_at(player.global_position + Vector2(-26.0, 0.0), "doppel")
	ok("двойник за спиной появился", back != null)
	got = await wait_until(func(): return fx.stat_by_kind[GlitchFx.Kind.DOPPEL_STRIKE] > strikes0, 3.0)
	player.invuln = 1.0e9
	player.hp = Player.MAX_HP
	ok("удар двойника → разрыв строк", got, "hp-удар засчитан: %s" % str(got))
	if back != null and is_instance_valid(back):
		back.take_damage(1000.0, player.global_position)
	await _expect_off("doppel_strike")
	await wait(0.2)
	ok("двойник рассеян — слежки нет, _process выключен", not fx.is_processing())

	var reveal0: int = fx.stat_by_kind[GlitchFx.Kind.DOPPEL_REVEAL]
	await _shot_before()
	var ph: Node = spawn_phantom_at(player.global_position + Vector2(150.0, 0.0), "doppel")
	got = await wait_until(func(): return fx.stat_by_kind[GlitchFx.Kind.DOPPEL_REVEAL] > reveal0, 1.5)
	ok("двойник раскрыт (замер под взглядом) → разрыв строк", got and ph != null and bool(ph.frozen))
	if got:
		await _shot_after("glitch_doppel", ph.global_position)
	await _expect_off("doppel_reveal")
	# Повторный взгляд на того же двойника — уже не раскрытие.
	hold(KEY_A)
	await wait(0.06)
	release(KEY_A)
	await wait(0.3)
	hold(KEY_D)
	await wait(0.06)
	release(KEY_D)
	await wait(0.4)
	ok("второй взгляд на того же двойника — без эффекта",
			fx.stat_by_kind[GlitchFx.Kind.DOPPEL_REVEAL] == reveal0 + 1)

	# Расслоение фантома мигает (знак сдвига меняется)...
	var flips: bool = ph != null and ph._split_d(0.1, 9.0) != ph._split_d(0.4, 9.0)
	ok("расслоение фантома мигает в обычном режиме", flips)

	# --- 6. «Меньше глитча»: шейдер не включается, важное — спокойная вспышка.
	GlitchFx.set_calm(true)
	ok("меньше мерцания: расслоение фантома стоит", ph != null
			and ph._split_d(0.1, 9.0) == ph._split_d(0.4, 9.0))
	if ph != null and is_instance_valid(ph):
		ph.take_damage(1000.0, player.global_position)
	await wait(0.2)
	fx.reset()   # пауза события «релей запущен» — проверена выше
	var fired0: int = fx.stat_fired
	var calm0n: int = fx.stat_calm
	await _shot_before()
	Game.objective_changed.emit(4)
	ok("меньше глитча: релей — без шейдера, спокойная вспышка", not fx.glitch_active()
			and fx.active() and fx.stat_calm == calm0n + 1 and fx.stat_fired == fired0
			and fx.get_child(0).material == null)
	await _shot_after("glitch_calm", bp)
	await _expect_off("relay_start (спокойная вспышка)")
	Game.brownout_changed.emit(true)
	Threat.vent_warning.emit(near + Vector2i(1, 0))
	ok("меньше глитча: браун-аут и вентиляция — ничего", not fx.active() and fx.stat_fired == fired0)
	Game.brownout_changed.emit(false)
	GlitchFx.set_calm(false)

	# --- 7. Настройка в профиле: одно поле, туда-обратно.
	var tmp_profile: String = TestEnv.file(TMP_PROFILE)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://glitch_fx_test"))
	var p: Profile = Profile.load_or_create(tmp_profile)
	ok("профиль: по умолчанию глитч полный", not p.less_glitch and not Profile.read_less_glitch(tmp_profile))
	p.less_glitch = true
	p.save_to(tmp_profile)
	ok("профиль: «меньше глитча» сохраняется", Profile.load_or_create(tmp_profile).less_glitch
			and Profile.read_less_glitch(tmp_profile))
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(tmp_profile)
	cfg.set_value("access", "less_glitch", "да")
	cfg.save(tmp_profile)
	ok("профиль: битое поле — по умолчанию", not Profile.load_or_create(tmp_profile).less_glitch
			and not Profile.read_less_glitch(tmp_profile))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_profile))
	ok("нет профиля — глитч полный", not Profile.read_less_glitch(tmp_profile))
	var btn: Button = GlitchFx.menu_toggle(Button.new(), p, tmp_profile)
	btn.button_pressed = false
	ok("переключатель меню пишет флаг и профиль", not GlitchFx.calm and not p.less_glitch
			and btn.text.ends_with("нет"))
	btn.button_pressed = true
	ok("переключатель меню: включён", GlitchFx.calm and Profile.read_less_glitch(tmp_profile))
	btn.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_profile))

	GlitchFx.set_calm(calm0)
	release_all()
	print("  (сценарий: %.1f с игрового времени)" % now_proc())
	finish()


## Ждём, пока эффект погаснет: на экране не дольше MAX_SEC (GlitchFx.stat_last_sec).
func _expect_off(what: String) -> void:
	var t0: float = now_proc()
	while fx.active() and now_proc() - t0 < 2.0:
		await get_tree().process_frame
	ok("%s гаснет ≤ %.1f с" % [what, GlitchFx.MAX_SEC],
			not fx.active() and fx.stat_last_sec > 0.0 and fx.stat_last_sec <= GlitchFx.MAX_SEC,
			"%.3f с" % fx.stat_last_sec)


# ------------------------------------------------------------------ РЕНДЕР

var _before: Image = null


func _shot_before() -> void:
	if not _shots:
		return
	await RenderingServer.frame_post_draw
	_before = get_viewport().get_texture().get_image()


## Кадр эффекта рядом с кадром «до»: кадрируем вокруг точки события.
func _shot_after(name: String, at: Vector2) -> void:
	if not _shots or _before == null:
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var after: Image = get_viewport().get_texture().get_image()
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var k: float = float(after.get_width()) / vp.x
	var c: Vector2 = get_viewport().get_canvas_transform() * at * k
	var cw: int = after.get_width() / 2
	var ch: int = after.get_height() / 2
	var x: int = clampi(int(c.x) - cw / 2, 0, after.get_width() - cw)
	var y: int = clampi(int(c.y) - ch / 2, 0, after.get_height() - ch)
	var out: Image = Image.create(cw * 2 + 4, ch, false, after.get_format())
	out.fill(Color(0.1, 0.08, 0.12))
	out.blit_rect(_before, Rect2i(x, y, cw, ch), Vector2i(0, 0))
	out.blit_rect(after, Rect2i(x, y, cw, ch), Vector2i(cw + 4, 0))
	var path: String = ProjectSettings.globalize_path(SHOT_DIR + name + ".png")
	out.save_png(path)
	print("ГЛИТЧ-КАДР: ", path)
	_before = null
