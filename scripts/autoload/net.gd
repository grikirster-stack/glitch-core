extends Node
## Сеть по локальной сети (ADR-002, § 4.1; D1, D2): роли процесса, транспорт ENet,
## рукопожатие через SceneMultiplayer.auth_callback, четыре канала сообщений.
##
## Роли: OFFLINE (одиночная — всё как раньше), HOST (хост — тоже игрок), CLIENT.
## Системы решают «считать или показывать» одной проверкой Net.is_authority().
##
## Сообщения — кадры NetCodec (тип u8 + полезная нагрузка) через четыре RPC:
##   канал 0 — надёжный упорядоченный, хост → клиенты (мир, события, список игроков);
##   канал 1 — ненадёжный упорядоченный, хост → клиенты (состояние 20 Гц, OWN);
##   канал 2 — надёжный, в обе стороны (личное: инвентарь, команды, барьеры харнесса);
##   канал 3 — ненадёжный упорядоченный, клиент → хост (ввод 30 Гц).
## Обработчики регистрируют системные PR: Net.on(NetCodec.Msg.X, func(sender, payload)).
##
## Сессия (Net.session) — словарь; пустой = игра не задана (main.gd тогда открывает меню):
##   одиночная из меню (MP-B): {mode: "single", seed: N (−1 — случайный), hardcore: bool};
##   хост: {mode: "host", seed, slot: 0, session_name, port, nick};
##   клиент: {mode: "client", seed, slot, session_name, nick, host_ip, port}.
##
## Скрипт не ссылается на другие автозагрузки по имени: его грузит и tools/net_test.gd
## (режим --script, несколько экземпляров Net на поддеревьях со своими SceneMultiplayer).

signal peer_joined(peer_id: int, info: Dictionary)
signal peer_left(peer_id: int, info: Dictionary)
## Сессия началась: хост поднял сервер или клиент прошёл рукопожатие.
signal session_started
## Сессия кончилась (хост вышел, связь потеряна, leave()).
signal session_ended(reason: String)
## Клиент не вошёл: отказ хоста с причиной или хост не отвечает.
signal connection_failed(reason: String)
signal roster_changed

enum Role { OFFLINE, HOST, CLIENT }

# --- транспорт (§ 9.2: не баланс — калибровочный PR их не трогает)
const PROTO: int = 15                ## версия протокола: поднимать при смене кодека, IDs, таблиц DB (2 — MP-D: HIT, звуки, Fx; 3 — MP-H: LOBBY; 4 — MP-E: net_state машин, запись предмета в SPAWN; 5 — MP-G: CHEST, TECH, InvOp; 6 — MP-F: фантомы, Ent; 7 — MP-I: COOP; 8 — MP-J: TEAM; 9 — #139: требование релея в COOP RELAY; 10 — ADR-004: MISSION, глава в приветствии; 11 — #164: предмет горелки и рецепт, байт пламени в net_state; 12 — #167: предмет маяка и рецепт; 13 — #165: зеркало, смеситель, призма; 14 — #171: хвост seen в INV, байт иконки в NOTIFY, ручной список на слитках и оптика по подбору; 15 — #172: сирена, линза, звук сирены)
const GAME_PORT: int = 24642
const DISCOVERY_PORT: int = 24643
const TICK_HZ: int = 20              ## пакет состояния
const INPUT_HZ: int = 30             ## ввод клиента
const MACHINE_HZ: int = 4
const GLOBAL_HZ: int = 1
const INTERP_DELAY: float = 0.10     ## марионетки рисуются в прошлом, с
const EXTRAP_MAX: float = 0.15
const AOI_HALF: Vector2 = Vector2(720, 420)  ## зона интереса, px
const LINK_WARN: float = 0.5         ## «связь прерывается», с
const PEER_TIMEOUT_LIMIT: int = 32
const PEER_TIMEOUT_MIN_MS: int = 3000
const PEER_TIMEOUT_MAX_MS: int = 8000
const SOFT_BUDGET: int = 48 * 1024   ## Б/с на клиента
const DISCOVERY_PERIOD: float = 1.5
const DISCOVERY_EXPIRE: float = 4.0
const WORLD_HASH_PERIOD: float = 30.0
const AUTH_TIMEOUT: float = 3.0      ## рукопожатие, с
const JOIN_TIMEOUT_MS: int = 5000    ## клиент: хост не ответил
## Запас соединений ENet сверх мест: лишний игрок получает внятный отказ
## «мест нет», а не молчаливый обрыв транспорта.
const SPARE_CONNECTIONS: int = 2
## Отказанный пир отключается через столько мс — чтобы ответ с причиной успел уйти.
const REJECT_LINGER_MS: int = 500
const NICK_MIN: int = 2
const NICK_MAX: int = 16
const DEFAULT_NICK: String = "Игрок"

# --- причины отказа (§ 4.1)
const R_FULL: String = "мест нет"
const R_CLOSED: String = "игра закрыта"
const R_BAD_HELLO: String = "неверное рукопожатие"
const R_NO_HOST: String = "хост не отвечает"
const R_HOST_LEFT: String = "хост завершил игру"

## Канал каждого типа сообщения (у EVENT — 0, личное событие — send_on(2, ...)).
const CHANNEL_OF: Dictionary = {
	NetCodec.Msg.ROSTER: 0, NetCodec.Msg.SNAPSHOT: 0, NetCodec.Msg.TILES: 0,
	NetCodec.Msg.FLUID: 0, NetCodec.Msg.MACHINE_ADD: 0, NetCodec.Msg.MACHINE_DEL: 0,
	NetCodec.Msg.MACHINES: 0, NetCodec.Msg.SPAWN: 0, NetCodec.Msg.DESPAWN: 0,
	NetCodec.Msg.GLOBAL: 0, NetCodec.Msg.EVENT: 0,
	NetCodec.Msg.MISSION: 0,   # ADR-004: тем же каналом, что GLOBAL, — итог главы раньше состояния забега
	NetCodec.Msg.STATE: 1, NetCodec.Msg.OWN: 1,
	NetCodec.Msg.INV: 2, NetCodec.Msg.CMD: 2, NetCodec.Msg.CMD_RESULT: 2,
	NetCodec.Msg.BARRIER: 2, NetCodec.Msg.BARRIER_PASS: 2,
	NetCodec.Msg.INPUT: 3,
}

var role: int = Role.OFFLINE
var session: Dictionary = {}
## Игроки сессии: peer_id → {slot, uid, nick, look, peer}. Хост — peer 1, слот 0.
## У клиента — из сообщения ROSTER.
var peers: Dictionary = {}
## Свой профиль для рукопожатия: {uid, nick, look}. Меню (MP-B) кладёт сюда Profile.
var local_profile: Dictionary = {"uid": 0, "nick": DEFAULT_NICK, "look": 0}
## Что клиент шлёт как proto (харнесс подменяет флагом --mp-proto, чтобы проверить отказ).
var hello_proto: int = PROTO
## false — хост больше не принимает игроков («игра закрыта»).
var accepting: bool = true
var max_players: int = Balance.MP_MAX_PLAYERS
## Причина последнего отказа или обрыва.
var last_error: String = ""
## Клиент: подключение + рукопожатие, мс (замер; −1 — не входил).
var join_ms: int = -1
## Байт полезной нагрузки отправлено по типам сообщений (замеры трафика).
var sent_bytes: Dictionary = {}

var _peer: ENetMultiplayerPeer = null
var _handlers: Dictionary = {}       ## Msg → Callable(sender: int, payload: PackedByteArray)
var _accepted: Dictionary = {}       ## хост: принятые, но ещё не вошедшие пиры (держат слот)
var _rejected: Dictionary = {}       ## хост: peer_id → мс отказа (отключим после REJECT_LINGER_MS)
var _join_t0: int = 0
var _welcome: Dictionary = {}
var _signals_wired: bool = false


func _ready() -> void:
	# Без сети автозагрузка ничего не делает: ни случайных чисел, ни кадровой работы.
	set_process(false)


# ------------------------------------------------------------------ РОЛИ

## Считает ли этот процесс мир (одиночная и хост) — или только показывает (клиент).
func is_authority() -> bool:
	return role != Role.CLIENT


func is_online() -> bool:
	return role != Role.OFFLINE


func is_host() -> bool:
	return role == Role.HOST


func is_client() -> bool:
	return role == Role.CLIENT


## Свой id пира (1 у хоста и в одиночной).
func my_id() -> int:
	return multiplayer.get_unique_id() if is_online() else 1


## Версия сборки: application/config/version (пишет релиз, #80) или "dev".
static func build_id() -> String:
	var v: String = String(ProjectSettings.get_setting("application/config/version", "")).strip_edges()
	return v if v != "" else "dev"


# ------------------------------------------------------------------ ХОСТ

## Поднять сервер. bind_ip "*" — все интерфейсы (LAN), "127.0.0.1" — только петля
## (тесты: окна брандмауэра Windows нет).
func host(port: int, bind_ip: String, p_seed: int, session_name: String,
		p_max_players: int = Balance.MP_MAX_PLAYERS) -> int:
	if is_online():
		leave()
	max_players = clampi(p_max_players, 1, Balance.MP_MAX_PLAYERS)
	var p: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	p.set_bind_ip(bind_ip)
	var err: int = p.create_server(port, max_players - 1 + SPARE_CONNECTIONS)
	if err != OK:
		last_error = "порт %d занят или недоступен (%s)" % [port, error_string(err)]
		return err
	_peer = p
	_wire()
	multiplayer.multiplayer_peer = p
	role = Role.HOST
	accepting = true
	_ensure_uid()
	var nick: String = String(local_profile.get("nick", DEFAULT_NICK))
	session = {"mode": "host", "seed": p_seed, "slot": 0, "session_name": session_name,
			"port": port, "nick": nick}
	peers.clear()
	peers[1] = {"peer": 1, "slot": 0, "uid": int(local_profile.get("uid", 0)), "nick": nick,
			"look": int(local_profile.get("look", 0)) & 0xFFFF}
	set_process(true)
	session_started.emit()
	return OK


# ------------------------------------------------------------------ КЛИЕНТ

## Подключиться. Итог — сигнал session_started или connection_failed(причина).
func join(ip: String, port: int) -> int:
	if is_online():
		leave()
	var p: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: int = p.create_client(ip, port)
	if err != OK:
		last_error = "не удалось подключиться к %s:%d (%s)" % [ip, port, error_string(err)]
		return err
	_peer = p
	_wire()
	multiplayer.multiplayer_peer = p
	var server: ENetPacketPeer = p.get_peer(1)
	if server != null:
		server.set_timeout(PEER_TIMEOUT_LIMIT, PEER_TIMEOUT_MIN_MS, PEER_TIMEOUT_MAX_MS)
	role = Role.CLIENT
	_ensure_uid()
	session = {}
	peers.clear()
	_welcome = {}
	last_error = ""
	join_ms = -1
	_join_t0 = Time.get_ticks_msec()
	session["host_ip"] = ip
	session["port"] = port
	set_process(true)
	return OK


## Закончить сессию (хост закрывает сервер, клиент отключается).
func leave(reason: String = "") -> void:
	if _peer != null:
		_peer.close()
	_peer = null
	var was_online: bool = is_online() and session.has("mode")
	var api: SceneMultiplayer = multiplayer as SceneMultiplayer
	if api != null:
		api.auth_callback = Callable()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	role = Role.OFFLINE
	session = {}
	peers.clear()
	_accepted.clear()
	_rejected.clear()
	set_process(false)
	if reason != "":
		last_error = reason
	if was_online:
		session_ended.emit(reason)


func _ensure_uid() -> void:
	if int(local_profile.get("uid", 0)) != 0:
		return
	# Свой генератор: глобальный randi() не трогаем — от него зависит сид одиночной игры.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = Time.get_ticks_usec() ^ (OS.get_process_id() << 20)
	local_profile["uid"] = (rng.randi() << 31) ^ rng.randi() | 1


# ------------------------------------------------------------------ РУКОПОЖАТИЕ

## Решение хоста по hello (чистая функция — её таблицу проверяет net_test).
## host_state: {proto, build, open, free_slot (−1 — нет), nicks: Array}.
## Итог: {ok, reason, nick, slot}. Порядок проверок: формат, закрыта, протокол,
## сборка, места, ник.
static func check_hello(hello: Dictionary, host_state: Dictionary) -> Dictionary:
	var res: Dictionary = {"ok": false, "reason": "", "nick": "", "slot": -1}
	if hello.is_empty():
		res["reason"] = R_BAD_HELLO
		return res
	if not bool(host_state.get("open", true)):
		res["reason"] = R_CLOSED
		return res
	var hp: int = int(host_state.get("proto", PROTO))
	if int(hello["proto"]) != hp:
		res["reason"] = "версии разные: протокол хоста %d, у вас %d" % [hp, int(hello["proto"])]
		return res
	var hb: String = String(host_state.get("build", "dev"))
	if String(hello["build"]) != hb:
		res["reason"] = "версии разные: хост %s, у вас %s" % [hb, String(hello["build"])]
		return res
	var slot: int = int(host_state.get("free_slot", -1))
	if slot < 0:
		res["reason"] = R_FULL
		return res
	var nick: String = String(hello["nick"]).strip_edges()
	var nerr: String = nick_error(nick)
	if nerr != "":
		res["reason"] = "недопустимый ник: " + nerr
		return res
	res["ok"] = true
	res["slot"] = slot
	res["nick"] = unique_nick(nick, host_state.get("nicks", []))
	return res


## Ошибка ника словами или "" (§ 4.6): после strip_edges 2–16 символов; буквы A–Z a–z
## А–Я а–я Ё ё, цифры, пробел, _ - .; первый и последний — буква или цифра; без двух
## пробелов подряд.
static func nick_error(nick: String) -> String:
	var n: String = nick.strip_edges()
	if n.length() < NICK_MIN:
		return "короче %d символов" % NICK_MIN
	if n.length() > NICK_MAX:
		return "длиннее %d символов" % NICK_MAX
	if n.contains("  "):
		return "два пробела подряд"
	for i in n.length():
		var c: String = n[i]
		if not (_nick_alnum(c) or c == " " or c == "_" or c == "-" or c == "."):
			return "недопустимый символ «%s»" % c
	if not _nick_alnum(n[0]) or not _nick_alnum(n[n.length() - 1]):
		return "начинаться и кончаться должен буквой или цифрой"
	return ""


static func _nick_alnum(c: String) -> bool:
	var u: int = c.unicode_at(0)
	return (u >= 0x30 and u <= 0x39) or (u >= 0x41 and u <= 0x5A) or (u >= 0x61 and u <= 0x7A) \
			or (u >= 0x410 and u <= 0x44F) or u == 0x401 or u == 0x451


## Повтор ника в сессии: «Аня» → «Аня 2», «Аня 3»… (сравнение без регистра; длина ≤ NICK_MAX).
static func unique_nick(nick: String, taken: Array) -> String:
	var low: Array = []
	for t in taken:
		low.append(String(t).to_lower())
	if not low.has(nick.to_lower()):
		return nick
	for k in range(2, 100):
		var suffix: String = " %d" % k
		var cand: String = nick.substr(0, NICK_MAX - suffix.length()).strip_edges() + suffix
		if not low.has(cand.to_lower()):
			return cand
	return nick


func _host_state() -> Dictionary:
	var used: Dictionary = {}
	var nicks: Array = []
	for id in peers:
		used[int(peers[id]["slot"])] = true
		nicks.append(String(peers[id]["nick"]))
	for id in _accepted:
		used[int(_accepted[id]["slot"])] = true
		nicks.append(String(_accepted[id]["nick"]))
	var free: int = -1
	for s in max_players:
		if not used.has(s):
			free = s
			break
	return {"proto": PROTO, "build": build_id(), "open": accepting, "free_slot": free, "nicks": nicks}


func _on_auth(id: int, data: PackedByteArray) -> void:
	var api: SceneMultiplayer = multiplayer as SceneMultiplayer
	if is_host():
		if _accepted.has(id) or _rejected.has(id):
			return
		var hello: Dictionary = NetCodec.decode_hello(data)
		var res: Dictionary = check_hello(hello, _host_state())
		var welcome: Dictionary = {"ok": res["ok"], "reason": res["reason"],
				"seed": int(session.get("seed", 0)) if res["ok"] else 0,
				"slot": int(res["slot"]), "session_name": String(session.get("session_name", "")),
				"nick": String(res["nick"]), "mission": String(session.get("mission", ""))}
		api.send_auth(id, NetCodec.encode_welcome(welcome))
		if bool(res["ok"]):
			_accepted[id] = {"peer": id, "slot": int(res["slot"]), "uid": int(hello["uid"]),
					"nick": String(res["nick"]), "look": int(hello["look"]) & 0xFFFF,
					"build": String(hello["build"])}
			api.complete_auth(id)
		else:
			_rejected[id] = Time.get_ticks_msec()
		return
	# Клиент: ответ хоста.
	if id != 1 or not _welcome.is_empty():
		return
	var w: Dictionary = NetCodec.decode_welcome(data)
	if w.is_empty():
		_fail(R_BAD_HELLO)
		return
	_welcome = w
	if not bool(w["ok"]):
		_fail(String(w["reason"]))
		return
	session["mode"] = "client"
	session["seed"] = int(w["seed"])
	session["slot"] = int(w["slot"])
	session["session_name"] = String(w["session_name"])
	session["nick"] = String(w["nick"])
	if String(w["mission"]) != "":   # ADR-004: глава кампании хоста
		session["mission"] = String(w["mission"])
	api.complete_auth(1)


func _on_peer_authenticating(id: int) -> void:
	var api: SceneMultiplayer = multiplayer as SceneMultiplayer
	if is_host():
		var pp: ENetPacketPeer = _peer.get_peer(id) if _peer != null else null
		if pp != null:
			pp.set_timeout(PEER_TIMEOUT_LIMIT, PEER_TIMEOUT_MIN_MS, PEER_TIMEOUT_MAX_MS)
			_no_throttle(pp)   # MP-D (#89)
		return
	if id == 1:
		var hello: Dictionary = {"proto": hello_proto, "build": build_id(),
				"uid": int(local_profile.get("uid", 0)),
				"nick": String(local_profile.get("nick", DEFAULT_NICK)),
				"look": int(local_profile.get("look", 0)) & 0xFFFF}
		api.send_auth(1, NetCodec.encode_hello(hello))


func _on_auth_failed(id: int) -> void:
	if is_host():
		_accepted.erase(id)
		_rejected.erase(id)
	elif id == 1 and last_error == "":
		_fail(R_NO_HOST)


func _on_peer_connected(id: int) -> void:
	if not is_host():
		return
	var info: Dictionary = _accepted.get(id, {})
	_accepted.erase(id)
	if info.is_empty():
		return
	peers[id] = info
	_broadcast_roster()
	peer_joined.emit(id, info)
	roster_changed.emit()


func _on_peer_disconnected(id: int) -> void:
	_accepted.erase(id)
	_rejected.erase(id)
	if not is_host() or not peers.has(id):
		return
	var info: Dictionary = peers[id]
	peers.erase(id)
	_broadcast_roster()
	peer_left.emit(id, info)
	roster_changed.emit()


func _on_connected_to_server() -> void:
	join_ms = Time.get_ticks_msec() - _join_t0
	if _peer != null and _peer.get_peer(1) != null:
		_no_throttle(_peer.get_peer(1))   # MP-D (#89)
	session_started.emit()


func _on_connection_failed() -> void:
	_fail(R_NO_HOST)


func _on_server_disconnected() -> void:
	leave(R_HOST_LEFT)


func _fail(reason: String) -> void:
	var was_joined: bool = join_ms >= 0
	last_error = reason
	if _peer != null:
		_peer.close()
	_peer = null
	var api: SceneMultiplayer = multiplayer as SceneMultiplayer
	if api != null:
		api.auth_callback = Callable()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	role = Role.OFFLINE
	session = {}
	peers.clear()
	set_process(false)
	if was_joined:
		session_ended.emit(reason)
	else:
		connection_failed.emit(reason)


func _wire() -> void:
	var api: SceneMultiplayer = multiplayer as SceneMultiplayer
	api.auth_callback = _on_auth
	api.auth_timeout = AUTH_TIMEOUT
	api.server_relay = false        # клиенты друг другу не шлют: всё через хост
	if _signals_wired:
		return
	_signals_wired = true
	api.peer_authenticating.connect(_on_peer_authenticating)
	api.peer_authentication_failed.connect(_on_auth_failed)
	api.peer_connected.connect(_on_peer_connected)
	api.peer_disconnected.connect(_on_peer_disconnected)
	api.connected_to_server.connect(_on_connected_to_server)
	api.connection_failed.connect(_on_connection_failed)
	api.server_disconnected.connect(_on_server_disconnected)


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	if is_host() and not _rejected.is_empty():
		for id in _rejected.keys():
			if now - int(_rejected[id]) >= REJECT_LINGER_MS:
				_rejected.erase(id)
				if _peer != null:
					_peer.disconnect_peer(id)
	elif is_client() and join_ms < 0 and now - _join_t0 > JOIN_TIMEOUT_MS:
		_fail(R_NO_HOST)


# ------------------------------------------------------------------ СПИСОК ИГРОКОВ

func roster() -> Array:
	var list: Array = []
	for id in peers:
		list.append(peers[id])
	list.sort_custom(func(a, b): return int(a["slot"]) < int(b["slot"]))
	return list


## Каждому, кто на связи: соседи, которые сами в этот момент отключаются, пропускаются
## (ENet не шлёт в закрывающийся канал).
func _broadcast_roster() -> void:
	if _peer == null:
		return
	var payload: PackedByteArray = NetCodec.encode_roster(roster())
	for id in peers:
		if int(id) == 1:
			continue
		var pp: ENetPacketPeer = _peer.get_peer(int(id))
		if pp != null and pp.get_state() == ENetPacketPeer.STATE_CONNECTED:
			send(NetCodec.Msg.ROSTER, payload, int(id))


func _on_roster(sender: int, payload: PackedByteArray) -> void:
	if sender != 1:
		return
	var list = NetCodec.decode_roster(payload)
	if list == null:
		return
	var old: Dictionary = peers
	peers = {}
	for e in list:
		peers[int(e["peer"])] = e
	for id in peers:
		if not old.has(id):
			peer_joined.emit(id, peers[id])
	for id in old:
		if not peers.has(id):
			peer_left.emit(id, old[id])
	roster_changed.emit()


# ------------------------------------------------------------------ СООБЩЕНИЯ

## Обработчик сообщения: fn(sender: int, payload: PackedByteArray). Один на тип.
func on(msg: int, fn: Callable) -> void:
	_handlers[msg] = fn


## Отправить кадр по каналу его типа. peer 0 — всем (хост) / хосту (клиент).
func send(msg: int, payload: PackedByteArray, peer: int = 0) -> void:
	send_on(int(CHANNEL_OF.get(msg, 2)), msg, payload, peer)


## Отправить кадр по явному каналу 0–3 (например, личное событие — по каналу 2).
func send_on(channel: int, msg: int, payload: PackedByteArray, peer: int = 0) -> void:
	if not is_online() or _peer == null:
		return
	if is_client():
		peer = 1
		if channel < 2:
			return           # каналы 0–1 — только от хоста
	var data: PackedByteArray = NetCodec.frame(msg, payload)
	sent_bytes[msg] = int(sent_bytes.get(msg, 0)) + data.size()
	match channel:
		0:
			if peer == 0:
				_rx0.rpc(data)
			else:
				_rx0.rpc_id(peer, data)
		1:
			if peer == 0:
				_rx1.rpc(data)
			else:
				_rx1.rpc_id(peer, data)
		2:
			if peer == 0:
				_rx2.rpc(data)
			else:
				_rx2.rpc_id(peer, data)
		_:
			if peer == 0:
				_rx3.rpc(data)
			else:
				_rx3.rpc_id(peer, data)


@rpc("authority", "call_remote", "reliable", 0)
func _rx0(data: PackedByteArray) -> void:
	_dispatch(data)


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _rx1(data: PackedByteArray) -> void:
	_dispatch(data)


@rpc("any_peer", "call_remote", "reliable", 2)
func _rx2(data: PackedByteArray) -> void:
	_dispatch(data)


@rpc("any_peer", "call_remote", "unreliable_ordered", 3)
func _rx3(data: PackedByteArray) -> void:
	if is_host():            # ввод — только хосту
		_dispatch(data)


func _dispatch(data: PackedByteArray) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	# Клиент слушает только хост; хост — только вошедших игроков.
	if is_client() and sender != 1:
		return
	if is_host() and not peers.has(sender):
		return
	var msg: int = NetCodec.frame_type(data)
	if msg == NetCodec.Msg.ROSTER:
		_on_roster(sender, NetCodec.frame_payload(data))
		return
	var fn: Callable = _handlers.get(msg, Callable())
	if fn.is_valid():
		fn.call(sender, NetCodec.frame_payload(data))


# ------------------------------------------------------------------ КОМАНДНАЯ СТРОКА

## Флаги сети (§ 4.6): --mp-host[=порт], --mp-join=ip[:порт], --nick=, --look=,
## --mp-bind=ip, --mp-scenario=<имя|all>, --mp-clients=N, --mp-role=i,
## --mp-uid=N, --mp-proto=N (два последних — для тестов). Неизвестное игнорируется.
static func parse_args(args: PackedStringArray) -> Dictionary:
	var o: Dictionary = {}
	for a in args:
		if a == "--mp-host":
			o["host_port"] = GAME_PORT
		elif a.begins_with("--mp-host="):
			o["host_port"] = _port_or(a.substr(10), GAME_PORT)
		elif a.begins_with("--mp-join="):
			var addr: String = a.substr(10).strip_edges()
			var port: int = GAME_PORT
			var colon: int = addr.rfind(":")
			if colon > 0:
				port = _port_or(addr.substr(colon + 1), GAME_PORT)
				addr = addr.substr(0, colon)
			if addr != "":
				o["join_ip"] = addr
				o["join_port"] = port
		elif a.begins_with("--nick="):
			o["nick"] = a.substr(7).strip_edges()
		elif a.begins_with("--look="):
			var s: String = a.substr(7).strip_edges()
			if s.is_valid_int():
				o["look"] = clampi(int(s), 0, 0xFFFF)
			elif s.begins_with("0x") and s.substr(2).is_valid_hex_number():
				o["look"] = clampi(s.substr(2).hex_to_int(), 0, 0xFFFF)
		elif a.begins_with("--mp-bind="):
			o["bind"] = a.substr(10).strip_edges()
		elif a.begins_with("--mp-scenario="):
			o["scenario"] = a.substr(14).strip_edges()
		elif a.begins_with("--mp-clients="):
			o["clients"] = maxi(0, int(a.substr(13)))
		elif a.begins_with("--mp-role="):
			o["role"] = int(a.substr(10))
		elif a.begins_with("--mp-uid="):
			o["uid"] = int(a.substr(9))
		elif a.begins_with("--mp-proto="):
			o["proto"] = int(a.substr(11))
	return o


static func _port_or(s: String, fallback: int) -> int:
	s = s.strip_edges()
	if not s.is_valid_int():
		return fallback
	var p: int = int(s)
	return p if p > 0 and p < 65536 else fallback


## Профиль из разобранных флагов (--nick, --look, --mp-uid, --mp-proto).
func apply_args(o: Dictionary) -> void:
	if o.has("nick") and String(o["nick"]) != "":
		local_profile["nick"] = String(o["nick"])
	if o.has("look"):
		local_profile["look"] = int(o["look"])
	if o.has("uid"):
		local_profile["uid"] = int(o["uid"])
	if o.has("proto"):
		hello_proto = int(o["proto"])


# ------------------------------------------------------------------ MP-D (#89): ДРОССЕЛЬ ENet
## ENet по умолчанию «дросселирует» ненадёжные пакеты: стоит RTT подскочить (клиент
## секунду строит мир после входа, машина занята), он выбрасывает до 100 % пакетов
## состояния и ввода и возвращает их по 2/32 за интервал — замер mp_move: после входа
## RTT 420 мс, дроссель 0/32, до нормы ≈ 5 с, ввод доходил через раз. Состоянию и вводу
## (новое затирает старое) дроссель не нужен: снижение запрещаем (deceleration 0),
## возврат — сразу (acceleration = PACKET_THROTTLE_SCALE). Команда уходит и второй
## стороне соединения.
const THROTTLE_INTERVAL_MS: int = 1000
const THROTTLE_SCALE: int = 32       ## ENET_PEER_PACKET_THROTTLE_SCALE


func _no_throttle(pp: ENetPacketPeer) -> void:
	pp.throttle_configure(THROTTLE_INTERVAL_MS, THROTTLE_SCALE, 0)


# ------------------------------------------------------------------ MP-I (#94): ПАРКОВКА
## Хост: игроки, которых сейчас нет в сессии, по uid профиля (§ 4.4, § 4.9):
## uid → {nick, look, state = Player.save_state(), stats, dead}. Обрыв или выход кладёт
## сюда героя, загрузка сетевого сохранения — всех из файла; вернувшийся uid получает
## своё (scripts/net/net_coop.gd).
var parked: Dictionary = {}
