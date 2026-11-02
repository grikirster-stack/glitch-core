extends SceneTree
## Процесс сценария mp_lobby (ADR-002 § 4.5, § 4.6; MP-H, #93): настоящее меню —
## текущая сцена, как при запуске без аргументов, — и тапы по нему.
##
##   хост:   --lobby-role=host --lobby-port=G --lobby-disc=D --lobby-other=D2 --lobby-seed=S
##           «Создать игру» (имя, сид, 3 места, порт G) → лобби; на D2 — ответчик чужой
##           сборки; ждёт гостя, «Старт» активен только когда гость готов → мир;
##           гость получил снимок → ждёт, пока гость выйдет сам.
##   клиент: --lobby-role=client --lobby-port=G --lobby-disc=D,D2 --lobby-seed=S
##           «Найти игру» → игра хоста в списке ≤ 1.5 с (версия, протокол, 1/3), чужая
##           сборка — серая с причиной → тап по игре → лобби (ники и вид обоих) →
##           «Готов» → мир хоста (сид, снимок) → выход.
##
## Всё на 127.0.0.1 (сервер, поиск и цели запроса) — окна брандмауэра Windows нет.
## Профили — временные (user://mp_lobby/), настоящий user://profile.cfg не трогается.
## Свой сторож времени: процесс выходит сам не позже WATCHDOG_MS.
##
## Режим --script: имена автозагрузок и классов, которые на них ссылаются (NetLobby),
## на этапе компиляции недоступны — берём узлы через root.get_node().
##
## Снимки сетевых экранов (окно за экраном, настоящий рендер):
##   godot --path . --windowed --position -10000,-10000 --resolution 1280x720 \
##         --script res://tools/mp/lobby_driver.gd -- --lobby-shot=res://docs/img
## Хост-лобби и поиск — в одном процессе; гость лобби — отдельный headless-процесс
## (этот же скрипт, --lobby-role=guest: входит по IP, «Готов», ждёт конца сессии).

const MENU_SCENE: String = "res://scenes/menu.tscn"
const GAME_SCENE: String = "res://scenes/main.tscn"
const NetScript = preload("res://scripts/autoload/net.gd")
const TMP_DIR: String = "user://mp_lobby"
const WATCHDOG_MS: int = 70000
## Приёмка § 5.3: хост в списке клиента не позже, мс.
const FIND_LIMIT_MS: int = 1500
const HOST_LOOK: int = 3      ## цвет скафандра хоста (индекс)
const GUEST_LOOK: int = 5

var role: String = ""
var game_port: int = 0
var disc_ports: PackedInt32Array = PackedInt32Array()
var other_port: int = 0
var seed_value: int = 0
var shot_dir: String = ""
var checks: int = 0
var fails: int = 0
var menu = null
var _t0: int = 0
var _other: LanDiscovery = null
var _guest_pid: int = 0


func _initialize() -> void:
	_t0 = Time.get_ticks_msec()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lobby-role="):
			role = a.substr(13)
		elif a.begins_with("--lobby-port="):
			game_port = int(a.substr(13))
		elif a.begins_with("--lobby-disc="):
			for p in a.substr(13).split(",", false):
				disc_ports.append(int(p))
		elif a.begins_with("--lobby-other="):
			other_port = int(a.substr(14))
		elif a.begins_with("--lobby-seed="):
			seed_value = int(a.substr(13))
		elif a.begins_with("--lobby-shot="):
			shot_dir = a.substr(13)
			role = "shot"
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	_run.call_deferred()


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _t0 > WATCHDOG_MS:
		ok("процесс уложился в %d с" % (WATCHDOG_MS / 1000), false)
		_summary()
		quit(3)
		return true
	return false


func _run() -> void:
	match role:
		"host":
			await _host()
		"client":
			await _client()
		"guest":
			await _guest()
		"shot":
			await _shots()
		_:
			ok("роль задана (--lobby-role=host|client|guest)", false, role)
	_finish()


# ------------------------------------------------------------------ ХОСТ

func _host() -> void:
	print("== mp_lobby: хост ==")
	await _open_menu("host", "Хост", HOST_LOOK)
	menu.net_bind = "127.0.0.1"
	menu.discovery_port = disc_ports[0] if not disc_ports.is_empty() else NetScript.DISCOVERY_PORT
	tap(menu.net_buttons[0])
	await frames(2)
	ok("тап «Создать игру» — форма хоста", menu.current_screen == "host")
	menu.host_name_edit.text = "Тест-лобби"
	menu.host_seed_edit.text = str(seed_value)
	menu.host_port_edit.text = str(game_port)
	tap(menu.slot_buttons[1])
	ok("тап «3» — мест 3", menu.host_slots == 3)
	tap(menu.host_create_button)
	await frames(2)
	var net: Node = root.get_node("Net")
	ok("тап «Создать» — лобби хоста: сервер, сид, 3 места", menu.current_screen == "lobby" and net.is_host()
			and net.max_players == 3 and int(net.session.get("seed", -1)) == seed_value
			and String(net.session.get("session_name", "")) == "Тест-лобби",
			"экран %s, сессия %s" % [menu.current_screen, str(net.session)])
	var lobby: Node = root.get_node_or_null("NetLobby")
	ok("ответчик поиска поднят на 127.0.0.1", lobby != null and lobby.discovery != null
			and lobby.discovery.is_running() and lobby.discovery_error == "")
	ok("экран хоста показывает адрес для «По IP»", String(menu.lobby_info.text).contains("127.0.0.1:%d" % game_port),
			menu.lobby_info.text)
	if other_port > 0:
		_other = LanDiscovery.new()
		root.add_child(_other)
		_other.start_host(other_port, "127.0.0.1", func() -> Dictionary:
				return {"proto": NetScript.PROTO, "build": "9.9.9", "name": "Чужая сборка", "host": "Ник",
						"n": 1, "max": 4, "port": game_port + 1000, "day": 0, "st": "lobby"})
	print("ЛОББИ: хост готов")
	var got: bool = await until(func() -> bool: return net.peers.size() >= 2, 40.0)
	ok("гость вошёл в лобби", got, "игроков %d" % net.peers.size())
	if not got:
		return
	var guest: int = -1
	for id in net.peers:
		if int(id) != 1:
			guest = int(id)
	await frames(3)
	var nicks: Array = []
	for r in menu.lobby_rows:
		nicks.append(String(r["nick"]))
	ok("в лобби хоста оба: ники и вид", menu.lobby_rows.size() == 2 and nicks == ["Хост", "Гость"]
			and int(menu.lobby_rows[1]["look"]) == GUEST_LOOK, str(menu.lobby_rows))
	ok("«Старт» неактивен, пока гость не готов", menu.start_button.visible and menu.start_button.disabled
			and not menu.ready_button.visible)
	got = await until(func() -> bool: return lobby.is_ready(guest), 20.0)
	await frames(2)
	ok("гость нажал «Готов» — «Старт» активен", got and not menu.start_button.disabled
			and bool(menu.lobby_rows[1]["ready"]))
	var t_start: int = Time.get_ticks_msec()
	tap(menu.start_button)
	got = await until(_in_world, 30.0)
	ok("тап «Старт» — хост в мире по своему сиду", got and root.get_node("World").world_seed == seed_value
			and net.is_host(), "%d мс" % (Time.get_ticks_msec() - t_start))
	var nw = root.get_node("Game").net_world
	got = await until(func() -> bool: return nw.synced.has(guest), 30.0)
	ok("гость в мире хоста: снимок отдан", got, "%d мс от «Старт»" % (Time.get_ticks_msec() - t_start))
	print("  ЗАМЕР: «Старт» → снимок гостю %d мс" % (Time.get_ticks_msec() - t_start))
	if current_scene.get("net_players") != null:
		var game: Node = root.get_node("Game")
		ok("в мире хоста два героя (свой и гость)", game.players.size() == 2, str(game.players.size()))
	var ann: Dictionary = lobby.announce()
	ok("поиск видит игру и после старта: «смена», 2/3", lobby.discovery.is_running()
			and String(ann["st"]) == "game" and int(ann["n"]) == 2 and int(ann["max"]) == 3, str(ann))
	got = await until(func() -> bool: return net.peers.size() == 1, 40.0)
	ok("гость вышел сам — хост остался в мире", got and _in_world())


# ------------------------------------------------------------------ КЛИЕНТ

func _client() -> void:
	print("== mp_lobby: клиент ==")
	await _open_menu("client", "Гость", GUEST_LOOK)
	menu.net_bind = "127.0.0.1"
	var targets: PackedStringArray = PackedStringArray()
	for p in disc_ports:
		targets.append("127.0.0.1:%d" % p)
	menu.discovery_targets = targets
	var t0: int = Time.get_ticks_msec()
	tap(menu.net_buttons[1])
	var key: String = "127.0.0.1:%d" % game_port
	var got: bool = await until(func() -> bool: return menu.browser.rows.has(key), 10.0)
	var ms: int = Time.get_ticks_msec() - t0
	print("  ЗАМЕР: хост в списке через %d мс от тапа «Найти игру» (запросов %d)" % [ms,
			menu.browser.discovery.queries_sent])
	ok("тап «Найти игру» — игра хоста в списке ≤ %d мс" % FIND_LIMIT_MS, got and ms <= FIND_LIMIT_MS,
			"%d мс" % ms)
	if not got:
		return
	var key2: String = "127.0.0.1:%d" % (game_port + 1000)
	if disc_ports.size() > 1:
		await until(func() -> bool: return menu.browser.rows.has(key2), 5.0)
	await frames(2)
	var row: Button = menu.browser.rows[key]
	var txt: String = row.text
	ok("строка игры: имя, ник хоста, 1/3, лобби, версия и протокол, активна", not row.disabled
			and txt.contains("Тест-лобби") and txt.contains("Хост") and txt.contains("1/3")
			and txt.contains("лобби") and txt.contains("версия " + NetScript.build_id())
			and txt.contains("протокол %d" % NetScript.PROTO), txt.replace("\n", " | "))
	if disc_ports.size() > 1:
		var grey: Button = menu.browser.rows.get(key2, null)
		ok("чужая сборка — серая, с причиной, ниже совместимой", grey != null and grey.disabled
				and grey.text.contains("другая версия: у хоста 9.9.9")
				and grey.get_index() > row.get_index(), grey.text.replace("\n", " | ") if grey != null else "нет")
		tap(grey)
		ok("тап по серой — ничего", menu.current_screen == "browser")
	var t_join: int = Time.get_ticks_msec()
	tap(row)
	var net: Node = root.get_node("Net")
	got = await until(func() -> bool: return menu.current_screen == "lobby" and net.is_client(), 10.0)
	ok("тап по игре — лобби гостя", got, "%d мс" % (Time.get_ticks_msec() - t_join))
	await until(func() -> bool: return menu.lobby_rows.size() == 2, 5.0)
	await frames(2)
	var nicks: Array = []
	for r in menu.lobby_rows:
		nicks.append(String(r["nick"]))
	ok("в лобби гостя оба: ники, вид хоста, хост готов", nicks == ["Хост", "Гость"]
			and int(menu.lobby_rows[0]["look"]) == HOST_LOOK and bool(menu.lobby_rows[0]["ready"])
			and not bool(menu.lobby_rows[1]["ready"]), str(menu.lobby_rows))
	ok("у гостя «Готов», без «Старт»", menu.ready_button.visible and not menu.start_button.visible
			and menu.ready_button.text == "Готов")
	ok("адрес в «Недавних» профиля", menu.profile.recent_ips.size() > 0
			and menu.profile.recent_ips[0] == "127.0.0.1:%d" % game_port, str(menu.profile.recent_ips))
	tap(menu.ready_button)
	got = await until(func() -> bool: return bool(menu.lobby_rows[1]["ready"]), 5.0)
	ok("тап «Готов» — хост подтвердил", got and menu.ready_button.text == "Не готов")
	var t_ready: int = Time.get_ticks_msec()
	got = await until(_in_world, 40.0)
	ok("хост начал — гость в мире по сиду хоста", got and root.get_node("World").world_seed == seed_value,
			"%d мс" % (Time.get_ticks_msec() - t_ready))
	var nw = root.get_node("Game").net_world
	got = await until(func() -> bool: return nw.is_joined, 30.0)
	ok("снимок мира хоста применён", got, "вход %d мс" % int(nw.join_total_ms))
	if current_scene.get("net_players") != null:
		await until(func() -> bool: return root.get_node("Game").players.size() == 2, 5.0)
		ok("в мире гостя два героя (свой и хост)", root.get_node("Game").players.size() == 2)


# ------------------------------------------------------------------ ГОСТЬ ДЛЯ СНИМКОВ

## Входит по IP, «Готов», ждёт конца сессии (хост-процесс снимков закрывает игру).
func _guest() -> void:
	await _open_menu("guest", "Гость", GUEST_LOOK)
	menu.ip_edit.text = "127.0.0.1:%d" % game_port
	menu.connect_by_ip()
	var net: Node = root.get_node("Net")
	if not await until(func() -> bool: return menu.current_screen == "lobby", 10.0):
		ok("гость вошёл", false)
		return
	await frames(10)
	menu.toggle_ready()
	await until(func() -> bool: return not net.is_online(), 40.0)


# ------------------------------------------------------------------ СНИМКИ

func _shots() -> void:
	print("== mp_lobby: снимки сетевых экранов ==")
	var port: int = 26700 + OS.get_process_id() % 200 * 3
	await _open_menu("shot", "Аня", HOST_LOOK)
	menu.net_bind = "127.0.0.1"
	menu.discovery_port = port + 1
	menu.discovery_targets = PackedStringArray(["127.0.0.1:%d" % (port + 1), "127.0.0.1:%d" % (port + 2)])
	# «Создать игру»
	tap(menu.net_buttons[0])
	await frames(2)
	menu.host_seed_edit.text = "Кербер"
	tap(menu.slot_buttons[1])
	# Свои адреса машины в снимок для репозитория не кладём — пример домашней сети.
	menu.host_ips_label.text = "Ваши адреса в локальной сети: 192.168.1.20"
	await _shot("lobby_create.png")
	# «Подключиться по IP» с недавними адресами
	menu.show_screen("main")
	menu.profile.recent_ips = PackedStringArray(["192.168.1.20", "192.168.1.31:25000", "kerber-pc"])
	tap(menu.net_buttons[2])
	await frames(2)
	await _shot("lobby_ip.png")
	menu.profile.recent_ips = PackedStringArray()
	# Лобби хоста + гость отдельным процессом.
	menu.show_screen("host")
	menu.host_port_edit.text = str(port)
	tap(menu.host_create_button)
	await frames(2)
	var args: PackedStringArray = PackedStringArray(["--headless", "--path",
			ProjectSettings.globalize_path("res://"), "--script", "res://tools/mp/lobby_driver.gd", "--",
			"--lobby-role=guest", "--lobby-port=%d" % port])
	_guest_pid = OS.create_process(OS.get_executable_path(), args)
	var net: Node = root.get_node("Net")
	await until(func() -> bool: return net.peers.size() >= 2, 15.0)
	var lobby: Node = root.get_node("NetLobby")
	await until(func() -> bool: return lobby.ready_peers.size() >= 1, 10.0)
	await frames(3)
	await _shot("lobby_host.png")
	# «Найти игру»: своя игра и чужая сборка (второй ответчик).
	_other = LanDiscovery.new()
	root.add_child(_other)
	_other.start_host(port + 2, "127.0.0.1", func() -> Dictionary:
			return {"proto": NetScript.PROTO, "build": "0.9.1", "name": "Экспедиция Борис", "host": "Борис",
					"n": 2, "max": 4, "port": 24642, "day": 3, "st": "game"})
	menu.screens["lobby"].visible = false
	menu.current_screen = "lobby_hidden"
	menu.screens["browser"].visible = true
	menu.browser.start(port + 1, "127.0.0.1", menu.discovery_targets)
	await until(func() -> bool: return menu.browser.rows.size() >= 2, 5.0)
	await frames(3)
	await _shot("lobby_browser.png")
	menu.browser.stop()
	net.leave()
	await frames(5)
	if _guest_pid > 0 and OS.is_process_running(_guest_pid):
		await until(func() -> bool: return not OS.is_process_running(_guest_pid), 5.0)
		if OS.is_process_running(_guest_pid):
			OS.kill(_guest_pid)


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path(shot_dir.path_join(file))
	var err: Error = img.save_png(path)
	print("СНИМОК: %s (%dx%d) %s" % [path, img.get_width(), img.get_height(), error_string(err)])
	ok("снимок %s" % file, err == OK and not img.is_invisible())


# ------------------------------------------------------------------ ОБЩЕЕ

func _open_menu(tag: String, nick: String, color: int) -> void:
	var path: String = TMP_DIR.path_join("%s_%d.cfg" % [tag, OS.get_process_id()])
	DirAccess.remove_absolute(path)
	var p: Profile = Profile.load_or_create(path)
	p.nick = nick
	p.look = Profile.Look.pack(PackedInt32Array([color, 0, 0, 0]))
	p.save_to(path)
	root.get_node("Net").session = {}
	menu = load(MENU_SCENE).instantiate()
	menu.set("profile_path", path)
	root.add_child(menu)
	current_scene = menu
	set_meta("profile_path", path)
	await frames(3)
	ok("меню — сцена, ник «%s», вид %d" % [nick, color], menu.nick_edit.text == nick
			and menu.profile.look == color and paused)


func _in_world() -> bool:
	var sc: Node = current_scene
	if sc == null or sc.scene_file_path != GAME_SCENE:
		return false
	var p = sc.get("player")
	return p != null and is_instance_valid(p) and p.is_inside_tree() and not paused


func frames(n: int) -> void:
	for i in n:
		await process_frame


## Ждать условия не дольше timeout с (кадрами).
func until(cond: Callable, timeout: float) -> bool:
	var t0: int = Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > int(timeout * 1000.0):
			return false
		await process_frame
	return true


## Тап: касание (мышь эмулируется из касаний, как на телефоне) по центру кнопки.
func tap(ctrl: Control) -> void:
	if ctrl == null:
		ok("есть кнопка для тапа", false)
		return
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


func ok(label: String, cond: bool, extra: String = "") -> void:
	checks += 1
	if cond:
		print("  OK   %s %s" % [label, extra])
	else:
		fails += 1
		print("  FAIL %s %s" % [label, extra])


func _summary() -> void:
	print("ИТОГ: проверок %d, провалов %d" % [checks, fails])


func _finish() -> void:
	if _other != null:
		_other.stop()
	var net: Node = root.get_node("Net")
	if net.is_online():
		net.leave()
	await frames(3)
	if has_meta("profile_path"):
		DirAccess.remove_absolute(String(get_meta("profile_path")))
	_summary()
	quit(1 if fails > 0 else 0)
