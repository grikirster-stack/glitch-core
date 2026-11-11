class_name MpRunner
extends ScenarioRunner
## Харнесс сетевых сценариев (ADR-002, § 4.10, уровень 2): настоящая игра, хост и
## клиенты — отдельные headless-процессы на 127.0.0.1.
##
##   godot --headless --path . -- --mp-scenario=<имя|all> --seed=31337 [--mp-clients=N]
##
## Хост-процесс поднимает сервер на 127.0.0.1:(24700 + pid % 200) (занят — следующий
## порт) и запускает клиентов OS.execute_with_pipe с флагами
##   --headless --path <проект> -- --mp-join=127.0.0.1:<порт> --mp-role=<i>
##   --mp-scenario=<имя> --seed=<сид> --mp-uid=<1000+i> [аргументы сценария]
## Вывод клиентов хост перепечатывает с префиксом [cN] (ошибки — [cN!]) и складывает
## их строки «ИТОГ: проверок N, провалов M» в общий итог. Клиент, который не уложился
## в время сценария, убивается (OS.kill) — это провал. Висящих процессов не остаётся:
## у клиента свой сторож времени, хост при выходе добивает всех живых.
##
## Сценарий — наследник MpScenarioBase (tools/mp/mp_scenario_base.gd): run_host() и
## run_client(i), точки синхронизации — await barrier("имя").
## Каждый сетевой PR добавляет свои сценарии строкой в MP_REGISTRY.

const MP_DIR: String = "res://tools/mp/scenarios/"
## Время на сценарий целиком (хост и все клиенты), мс; ключ "timeout_ms" — свой предел.
const MP_TIMEOUT_MS: int = 90000
const PORT_BASE: int = 24700
const PORT_SPREAD: int = 200
const PORT_TRIES: int = 10
## Только петля: на Windows привязка к внешнему интерфейсу вызывает окно брандмауэра.
const LOOPBACK: String = "127.0.0.1"
## Клиент сам выходит, если сценарий завис дольше предела на столько, мс.
const CLIENT_GRACE_MS: int = 5000

const MP_REGISTRY: Dictionary = {
	# --- Основа сети (MP-A, #86) ---
	"mp_smoke": {"file": "mp_smoke.gd", "title": "сеть: дым", "clients": 5,
		"desc": "хост + 3 клиента входят: ник («Аня 2»), вид, uid, сид; 5-й — «мест нет»; чужой proto — отказ"},
	# --- Мир по сети (MP-C, #88) ---
	"mp_join_snapshot": {"file": "mp_join_snapshot.gd", "title": "сеть: вход снимком", "clients": 1,
		"desc": "хост копает, строит, льёт воду; клиент входит позже — хэши тайлов, воды, построек равны; у клиента вода, питание, цель, угроза не считаются"},
	"mp_world_deltas": {"file": "mp_world_deltas.gd", "title": "сеть: мир дельтами", "clients": 1,
		"desc": "бот хоста копает и рушит «озеро с полки» (§ 9.1) — у клиента те же тайлы и вода; замер Б/с"},
	# --- Игроки по сети (MP-D, #89) ---
	"mp_move": {"file": "mp_move.gd", "title": "сеть: движение и марионетки", "clients": 2,
		"desc": "клиент ходит и прыгает: хост p95 ≤ 2 px, марионетка у второго ≤ 1 клетки; поправка; «без связи»"},
	"mp_actions": {"file": "mp_actions.gd", "title": "сеть: действия клиента", "clients": 2,
		"desc": "клиент копает, ставит блок, E у терминала — эффект на хосте и у второго клиента, дроп в инвентарь клиента"},
	"mp_feedback": {"file": "mp_feedback.gd", "title": "сеть: обратная связь лично", "clients": 2,
		"desc": "«Рядом нет вентиляции» — только нажавшему; Q в один кадр; удар — вспышка у раненого; обёртки player.gd"},
	# --- Фантомы и угроза на N игроков (MP-F, #92) ---
	"mp_phantoms": {"file": "mp_phantoms.gd", "title": "сеть: фантомы", "clients": 2,
		"desc": "16 фантомов: цель — ближайший доступный герой; у клиента марионетки без ИИ, p95 ≤ 24 px; двойник замирает под взглядом любого"},
	"mp_threat_scale": {"file": "mp_threat_scale.gd", "title": "сеть: угроза на N игроков", "clients": 3,
		"desc": "бюджет, cap, интервал при N = 1…4 (множители ADR-002 § 4.7, T по ADR-005 § 6.2); спавн у наименее занятого; чёрный ящик товарища; шлюз — любому герою"},
	"mp_perf": {"file": "mp_perf.gd", "title": "сеть: кадр хоста", "clients": 3,
		"desc": "4 игрока, 16 фантомов, 130 машин: p95 кадра хоста ≤ 16 мс; замер Б/с фантомов на клиента"},
	# --- Поиск в локалке и лобби (MP-H, #93) ---
	"mp_lobby": {"file": "mp_lobby.gd", "title": "сеть: поиск и лобби", "clients": 0, "timeout_ms": 75000,
		"desc": "меню двух процессов тапами: хост анонсирует, клиент находит ≤ 1.5 с (чужая сборка серая), лобби, «Готов», «Старт» — оба в мире"},
	# mp_factory снят вместе с заводом (#170).
	# --- Инвентари, крафт, сундуки по сети (MP-G, #91) ---
	"mp_inventory": {"file": "mp_inventory.gd", "title": "сеть: инвентари и сундуки", "clients": 2,
		"desc": "E у прокси открывает сундук у владельца; клики панели — команды InvOps (рука — окно); два клиента тянут одну стопку — один получает, второй — отказ, сумма предметов та же; крафт, drop, select с клиента"},
	# --- Кооператив: смерть, укрытие, релей, сохранение (MP-I, #94) ---
	# mp_tech снят (#169): дерево T1–T5 больше не открывается по сети.
	"mp_death": {"file": "mp_death.gd", "title": "сеть: смерть и респаун", "clients": 2,
		"desc": "погибший: мешок только владельцу (120 с — потом любому), экран с отсчётом 15 с, камера за товарищем (A/D), респаун на базе без сдвига часов"},
	"mp_team_wipe": {"file": "mp_team_wipe.gd", "title": "сеть: вайп и хардкор", "clients": 1,
		"desc": "погибли все — через RESPAWN_DELAY все на базе, часы к рассвету, автосохранение; --hardcore — погибший зритель, погибли все — конец для всех"},
	"mp_vent_one": {"file": "mp_vent_one.gd", "title": "сеть: вентиляция и терминал", "clients": 1,
		"desc": "одна вентиляция — один герой («Вентиляция занята: Хост»), ник у занятой; терминал — данные один раз на команду, всем — кто прочёл"},
	"mp_relay_coop": {"file": "mp_relay_coop.gd", "title": "сеть: релей вчетвером", "clients": 2,
		"desc": "вклад деталей двумя клиентами — у всех, второй запускает отсчёт; все дальше 12 клеток — отсчёт стоит, «без присмотра»; вернулся — идёт; клиент видит кота"},
	"mp_save_rejoin": {"file": "mp_save_rejoin.gd", "title": "сеть: сохранение и вход по uid", "clients": 3,
		"desc": "F5 хоста — версия 2 с 4 игроками по uid (замер КБ и мс); у клиента F5/F9 молчат; все вышли, загрузка, вход того же uid — его вещи и место"},
	"mp_disconnect": {"file": "mp_disconnect.gd", "title": "сеть: обрыв и парковка", "clients": 1,
		"desc": "процесс клиента убит — по таймауту ENet герой в Net.parked (хотбар не упал, жив); тот же uid вернулся — позиция, HP, инвентарь"},
	# --- Двойник среди своих, перекличка, команда на HUD (MP-J, #95) ---
	"mp_doppel": {"file": "mp_doppel.gd", "title": "сеть: двойник среди своих", "clients": 3, "timeout_ms": 150000,
		"desc": "4 игрока: двойник в нике и виде товарища (дальше всех от жертвы), охотится на отбившегося; маячки товарищей — 20 клеток или питание, двойника на карте нет; перекличка G — у двойника огонёк красный; удар по своему — «клац», по двойнику — «глюк»"},
	# --- Требование релея от N (#139) ---
	"mp_relay_scale": {"file": "mp_relay_scale.gd", "title": "сеть: требование релея от N", "clients": 1,
		"desc": "N = 2 → 1 → 2 → 1: требование ×(1 + 0.25·(N−1)) одно у хоста и клиента (COOP RELAY, снимок входа); при выходе не ниже сданного, вклад цел, релей запускается"},
	# --- Пауза в сети (#119) ---
	"mp_pause": {"file": "mp_pause.gd", "title": "сеть: пауза не останавливает мир", "clients": 1,
		"desc": "ESC у клиента — панель поверх, «Сохранить» серая, бит окна у прокси, мир хоста идёт; у хоста — «Сохранить и выйти в меню», мир идёт"},
	# --- Кампания по сети (ADR-004) ---
	"mp_campaign": {"file": "mp_campaign.gd", "title": "сеть: глава кампании", "clients": 1,
		"desc": "хост запускает «Копай» до входа: клиенту — id главы в приветствии, жила и марионетка главы в снимке, набор главы; этап и победа хоста — у клиента, экран итога и профиль"},
	# --- Баланс кооператива (MP-K, #96): тяжёлые боты, не в «all» и не в CI ("manual");
	# таблица по N и сидам — tools/mp_balance_probe.gd ---
	"mp_balance_night": {"file": "mp_balance_night.gd", "title": "баланс сети: ночь по шахтам", "clients": 3,
		"timeout_ms": 240000, "manual": true,
		"desc": "N героев в своих тёмных точках с 3 лампами, бьют подошедших; ночь штатным директором с формулами N: смерти, встречи и урон на героя, трафик"},
	# mp_balance_siege снят: база была из ТЭЦ и буров (#170). Ручной прогон больше не зовёт файл.
	"mp_balance_mining": {"file": "mp_balance_mining.gd", "title": "баланс сети: добыча командой", "clients": 3,
		"timeout_ms": 180000, "manual": true,
		"desc": "N героев одновременно копают свои жилы железной руды своим швом (клиент — через прокси): с/ед от ЛКМ до руды в своём инвентаре"},
	"mp_balance_doppel": {"file": "mp_balance_doppel.gd", "title": "баланс сети: двойник до раскрытия", "clients": 3,
		"timeout_ms": 180000, "manual": true,
		"desc": "жертва отбилась, двойник в маске товарища; бот команды: перекличка по кулдауну, ответ через 1.5 с, красный огонёк в поле зрения — бьёт: время до раскрытия, ложный красный у ответивших"},
}

## −1 — хост-процесс; 0.. — номер клиента (--mp-role).
var mp_role: int = -1
var mp_name: String = ""
var port: int = 0
## Хост: процессы клиентов текущего сценария.
var children: Array = []

var _opts: Dictionary = {}
var _sc: MpScenarioBase = null
var _sc_done: bool = false
var _deadline: int = 0
var _ran_any: bool = false
var _arrived: Dictionary = {}     ## хост: барьер → {peer_id: true}
var _passed: Dictionary = {}      ## клиент: барьер → true
var _joined_ms: Dictionary = {}   ## хост: uid → мс от запуска клиента до входа
var _launch_ms: Dictionary = {}   ## хост: uid → мс запуска процесса
var _total_re: RegEx = RegEx.create_from_string("^ИТОГ: проверок (\\d+), провалов (\\d+)")


## Имена сетевых сценариев для «all» (без "manual": боты баланса MP-K запускают по имени).
static func mp_names() -> Array:
	return MP_REGISTRY.keys().filter(func(k) -> bool: return not bool(MP_REGISTRY[k].get("manual", false)))


## Точка входа из main.gd (_net_runner): opts — Net.parse_args().
func start_mp(main_scene: Node, opts: Dictionary) -> void:
	scene = main_scene
	_opts = opts
	mp_role = int(opts.get("role", -1)) if opts.has("join_ip") else -1
	Net.on(NetCodec.Msg.BARRIER, _on_barrier)
	Net.on(NetCodec.Msg.BARRIER_PASS, _on_barrier_pass)
	if mp_role >= 0:
		_client_flow(String(opts.get("scenario", "")))
		return
	if not opts.has("nick"):
		Net.local_profile["nick"] = "Хост"
	Net.peer_joined.connect(_on_peer_joined)
	var names: Array = []
	for part in String(opts.get("scenario", "")).split(",", false):
		var n: String = String(part).strip_edges()
		if n == "all":
			names.append_array(mp_names())
		elif n != "":
			names.append(n)
	scenarios_total = names.size()
	_host_flow(names)


# ------------------------------------------------------------------ ХОСТ

func _host_flow(names: Array) -> void:
	for name in names:
		await _host_one(String(name))
	_summary()


func _host_one(name: String) -> void:
	if not MP_REGISTRY.has(name):
		print("== Сетевой сценарий: %s ==" % name)
		ok("сценарий есть в реестре", false)
		return
	var reg: Dictionary = MP_REGISTRY[name]
	print("== Сетевой сценарий: %s ==" % String(reg["title"]))
	if _ran_any:
		_reset_world()
	_ran_any = true
	mp_name = name
	_arrived.clear()
	_joined_ms.clear()
	_launch_ms.clear()
	children.clear()
	if not _open_server(name):
		ok("сервер поднят на %s" % LOOPBACK, false, Net.last_error)
		return
	var n: int = int(_opts.get("clients", reg.get("clients", 2)))
	_sc = load(MP_DIR + String(reg["file"])).new()
	_sc.setup(self, scene)
	_sc.mp_setup(-1, n, name)
	add_child(_sc)
	_sc_done = false
	_sc.done.connect(func(): _sc_done = true)
	_deadline = Time.get_ticks_msec() + int(reg.get("timeout_ms", MP_TIMEOUT_MS))
	if _sc.auto_launch:
		for i in n:
			launch(i)
	_sc.run_host()
	while not _sc_done and Time.get_ticks_msec() < _deadline:
		await get_tree().process_frame
	if not _sc_done:
		ok("сценарий уложился в отведённое время", false,
				"%.0f с" % (float(int(reg.get("timeout_ms", MP_TIMEOUT_MS))) / 1000.0))
	# Клиенты доигрывают и выходят сами; кто не успел к сроку — убиваем.
	while _running() > 0 and Time.get_ticks_msec() < _deadline:
		await get_tree().process_frame
	_reap(true)
	for c in children:
		ok("[c%d] закончил сам, есть ИТОГ, код 0" % int(c["i"]),
				bool(c["summary"]) and int(c["code"]) == 0 and not bool(c["killed"]),
				"код %d%s" % [int(c["code"]), ", убит по таймауту" if bool(c["killed"]) else ""])
	Net.leave()
	_sc.queue_free()
	_sc = null
	await wait(0.2)


func _open_server(name: String) -> bool:
	var base: int = PORT_BASE + OS.get_process_id() % PORT_SPREAD
	for k in PORT_TRIES:
		if Net.host(base + k, LOOPBACK, int(scene.get("seed_value")), "Тест " + name) == OK:
			port = base + k
			return true
	return false


## Запустить клиента i (отдельный headless-процесс).
func launch(i: int) -> void:
	var uid: int = _sc.client_uid(i)
	var args: PackedStringArray = PackedStringArray(["--headless", "--path",
			ProjectSettings.globalize_path("res://"), "--",
			"--mp-join=%s:%d" % [LOOPBACK, port], "--mp-role=%d" % i,
			"--mp-scenario=%s" % mp_name, "--seed=%d" % int(scene.get("seed_value")),
			"--mp-uid=%d" % uid])
	args.append_array(_sc.client_args(i))
	var r: Dictionary = OS.execute_with_pipe(OS.get_executable_path(), args, false)
	if r.is_empty():
		ok("[c%d] процесс запущен" % i, false)
		return
	_launch_ms[uid] = Time.get_ticks_msec()
	children.append({"i": i, "pid": int(r["pid"]), "out": r["stdio"], "err": r["stderr"],
			"buf": PackedByteArray(), "ebuf": PackedByteArray(), "summary": false,
			"code": -1, "done": false, "killed": false, "t0": Time.get_ticks_msec(), "ms": -1})


## Сколько клиентов ещё работает.
func _running() -> int:
	var n: int = 0
	for c in children:
		if not bool(c["done"]):
			n += 1
	return n


## Клиент i вышел?
func child_done(i: int) -> bool:
	for c in children:
		if int(c["i"]) == i:
			return bool(c["done"])
	return false


## Мс от запуска процесса клиента i до его выхода (−1 — ещё работает).
func exit_ms_of(i: int) -> int:
	for c in children:
		if int(c["i"]) == i:
			return int(c["ms"])
	return -1


## Мс от запуска процесса клиента до его входа в сессию (−1 — не вошёл).
func join_ms_of_uid(uid: int) -> int:
	return int(_joined_ms.get(uid, -1))


func _on_peer_joined(_id: int, info: Dictionary) -> void:
	var uid: int = int(info.get("uid", 0))
	if _launch_ms.has(uid):
		_joined_ms[uid] = Time.get_ticks_msec() - int(_launch_ms[uid])


func _process(_delta: float) -> void:
	if mp_role >= 0:
		# Сторож клиента: сценарий завис — выходим сами, хост не должен нас ждать.
		if _deadline > 0 and Time.get_ticks_msec() > _deadline + CLIENT_GRACE_MS:
			print("  FAIL клиент завис: выход по сторожу времени")
			get_tree().quit(3)
		return
	_reap(false)


## Читать вывод клиентов; отметить вышедших; kill — добить живых.
func _reap(kill: bool) -> void:
	for c in children:
		if bool(c["done"]):
			continue
		_drain(c)
		if kill and OS.is_process_running(int(c["pid"])):
			OS.kill(int(c["pid"]))
			c["killed"] = true
			print("[c%d!] убит по таймауту сценария" % int(c["i"]))
		if not OS.is_process_running(int(c["pid"])):
			_drain(c)
			_flush(c)
			c["done"] = true
			c["code"] = OS.get_process_exit_code(int(c["pid"]))
			c["ms"] = Time.get_ticks_msec() - int(c["t0"])


func _drain(c: Dictionary) -> void:
	for pair in [["out", "buf", false], ["err", "ebuf", true]]:
		var f: FileAccess = c[pair[0]]
		if f == null:
			continue
		var buf: PackedByteArray = c[pair[1]]
		for _guard in 64:
			var chunk: PackedByteArray = f.get_buffer(4096)
			if chunk.is_empty():
				break
			buf.append_array(chunk)
			if chunk.size() < 4096:
				break
		var nl: int = buf.find(10)
		while nl >= 0:
			_child_line(c, buf.slice(0, nl).get_string_from_utf8().strip_edges(false, true), bool(pair[2]))
			buf = buf.slice(nl + 1)
			nl = buf.find(10)
		c[pair[1]] = buf


func _flush(c: Dictionary) -> void:
	for pair in [["buf", false], ["ebuf", true]]:
		var buf: PackedByteArray = c[pair[0]]
		if not buf.is_empty():
			_child_line(c, buf.get_string_from_utf8().strip_edges(false, true), bool(pair[1]))
			c[pair[0]] = PackedByteArray()


func _child_line(c: Dictionary, line: String, is_err: bool) -> void:
	if line == "":
		return
	print("[c%d%s] %s" % [int(c["i"]), "!" if is_err else "", line])
	var m: RegExMatch = _total_re.search(line)
	if m != null:
		c["summary"] = true
		checks += int(m.get_string(1))
		fails += int(m.get_string(2))
	elif line.contains("SCRIPT ERROR"):
		ok("[c%d] без ошибок скрипта" % int(c["i"]), false)


func _exit_tree() -> void:
	# Хост уходит — ни одного клиента за собой не оставляем.
	for c in children:
		if not bool(c["done"]) and OS.is_process_running(int(c["pid"])):
			OS.kill(int(c["pid"]))


# ------------------------------------------------------------------ КЛИЕНТ

func _client_flow(name: String) -> void:
	mp_name = name
	if not MP_REGISTRY.has(name):
		ok("сценарий есть в реестре", false, name)
		_client_end()
		return
	var reg: Dictionary = MP_REGISTRY[name]
	_sc = load(MP_DIR + String(reg["file"])).new()
	_sc.setup(self, scene)
	_sc.mp_setup(mp_role, int(_opts.get("clients", reg.get("clients", 2))), name)
	add_child(_sc)
	_sc_done = false
	_sc.done.connect(func(): _sc_done = true)
	_deadline = Time.get_ticks_msec() + int(reg.get("timeout_ms", MP_TIMEOUT_MS))
	_sc.run_client(mp_role)
	while not _sc_done and Time.get_ticks_msec() < _deadline:
		await get_tree().process_frame
	if not _sc_done:
		ok("сценарий клиента уложился в отведённое время", false)
	_client_end()


func _client_end() -> void:
	print("ИТОГ: проверок %d, провалов %d" % [checks, fails])
	await wait(0.2)          # последние сообщения уходят хосту
	Net.leave()
	await wait(0.1)
	get_tree().quit(1 if fails > 0 else 0)


# ------------------------------------------------------------------ БАРЬЕРЫ

## Хост: ждать, пока до барьера дойдут count клиентов (−1 — все вошедшие), затем
## отпустить их. Клиент: сообщить хосту и ждать отпускания.
func barrier(name: String, count: int = -1, timeout: float = 30.0) -> bool:
	var t0: int = Time.get_ticks_msec()
	var limit: int = int(timeout * 1000.0)
	if mp_role >= 0:
		Net.send(NetCodec.Msg.BARRIER, NetCodec.encode_str8(name))
		while not _passed.has(name) and Net.is_client() and Time.get_ticks_msec() - t0 < limit:
			await get_tree().process_frame
		return _passed.has(name)
	var reached: bool = false
	while Time.get_ticks_msec() - t0 < limit:
		var got: Dictionary = _arrived.get(name, {})
		var need: int = count if count >= 0 else Net.peers.size() - 1
		var have: int = 0
		for id in got:
			if Net.peers.has(id):
				have += 1
		if have >= need and need >= 0:
			reached = true
			break
		await get_tree().process_frame
	for id in _arrived.get(name, {}):
		if Net.peers.has(id):
			Net.send(NetCodec.Msg.BARRIER_PASS, NetCodec.encode_str8(name), int(id))
	return reached


func _on_barrier(sender: int, payload: PackedByteArray) -> void:
	var name = NetCodec.decode_str8(payload)
	if name == null:
		return
	if not _arrived.has(name):
		_arrived[name] = {}
	_arrived[name][sender] = true


func _on_barrier_pass(_sender: int, payload: PackedByteArray) -> void:
	var name = NetCodec.decode_str8(payload)
	if name != null:
		_passed[name] = true
