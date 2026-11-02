class_name LanDiscovery
extends Node
## Поиск игр в локальной сети (ADR-002 § 3 D7, § 4.5; MP-H, #93): запрос/ответ по UDP.
##
## Клиент («Найти игру») шлёт запрос QUERY_MAGIC + proto u16 (6 Б) на 255.255.255.255 и
## на направленный broadcast /24 каждого своего IPv4 (маску Godot не отдаёт — домашний
## случай), порт Net.DISCOVERY_PORT (24643): сразу, через QUERY_SECOND и дальше каждые
## Net.DISCOVERY_PERIOD. Хост отвечает ЮНИКАСТОМ на адрес и порт запроса:
## ANSWER_MAGIC + JSON {v, proto, build, name, host, n, max, port, day, st, pw} — клиенту
## (в том числе Android) принимать broadcast не нужно, MulticastLock ему не требуется.
## Хосту на Android он может понадобиться (§ 4.5) — проверка руками, IP на экране хоста
## и «Подключиться по IP» работают всегда.
##
## Список: ключ ip:порт игры; пинг — от последнего запроса до ответа; запись без ответа
## дольше Net.DISCOVERY_EXPIRE живёт не больше этого. Совместимость — incompat_reason():
## другой протокол, другая сборка, мест нет, пароль (поле pw зарезервировано, в первой
## версии всегда false) — такая игра в списке серая с причиной.
##
## Тесты (окна брандмауэра Windows нет): хост bind_ip = "127.0.0.1", поиск —
## bind_ip = "127.0.0.1" и targets ["127.0.0.1:порт"] вместо широковещательных адресов.
##
## По имени автозагрузки не обращаемся: скрипт грузят и инструменты в режиме --script.

signal hosts_changed

const NetScript = preload("res://scripts/autoload/net.gd")

const QUERY_MAGIC: String = "GCQ1"
const ANSWER_MAGIC: String = "GCA1"
## Версия формата ответа (поле v).
const ANSWER_V: int = 1
## Второй запрос — через столько секунд после первого (дальше — Net.DISCOVERY_PERIOD).
const QUERY_SECOND: float = 0.5
## Ответ длиннее — мусор.
const ANSWER_MAX: int = 1024
## Сколько пакетов разбирать за кадр (защита от потока мусора).
const PACKETS_PER_FRAME: int = 32
const BROADCAST: String = "255.255.255.255"

enum Mode { NONE, HOST, SEARCH }

var mode: int = Mode.NONE
## Порт поиска: хост слушает его, клиент шлёт на него (если в цели не указан свой).
var port: int = NetScript.DISCOVERY_PORT
var bind_ip: String = "*"
## Клиент: цели запроса — "ip" или "ip:порт"; пусто — broadcast_targets().
var targets: PackedStringArray = PackedStringArray()
## Хост: func() -> Dictionary — поля ответа (name, host, n, max, port, day, st, pw).
var announce: Callable = Callable()
## Клиент: найденные игры, "ip:порт" → запись (decode_answer + ip, ping_ms, seen_ms,
## first_ms, reason).
var hosts: Dictionary = {}
## Своя версия для совместимости (тесты подменяют).
var my_proto: int = NetScript.PROTO
var my_build: String = NetScript.build_id()

# --- замеры
var queries_sent: int = 0
var answers_sent: int = 0
var answers_got: int = 0
var last_query_bytes: int = 0
var last_answer_bytes: int = 0
## Клиент: мс от start_search() до первой записи в списке (−1 — пусто).
var first_host_ms: int = -1

var _udp: PacketPeerUDP = null
var _t: float = 0.0
var _next_query: float = 0.0
var _queries_in_round: int = 0
var _last_send_ms: int = 0
var _start_ms: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # меню держит дерево на паузе
	set_process(mode != Mode.NONE)


func _exit_tree() -> void:
	stop()


# ------------------------------------------------------------------ ЗАПУСК

## Хост: слушать запросы на p_port (bind "*" — все интерфейсы, "127.0.0.1" — петля).
func start_host(p_port: int, p_bind: String, p_announce: Callable) -> Error:
	stop()
	port = p_port
	bind_ip = p_bind
	announce = p_announce
	_udp = PacketPeerUDP.new()
	var err: Error = _udp.bind(port, bind_ip)
	if err != OK:
		_udp = null
		return err
	mode = Mode.HOST
	set_process(true)
	return OK


## Клиент: слать запросы и собирать ответы. p_targets пусто — широковещательно.
func start_search(p_port: int = NetScript.DISCOVERY_PORT, p_bind: String = "*",
		p_targets: PackedStringArray = PackedStringArray()) -> Error:
	stop()
	port = p_port
	bind_ip = p_bind
	targets = p_targets
	_udp = PacketPeerUDP.new()
	var err: Error = _udp.bind(0, bind_ip)
	if err != OK:
		_udp = null
		return err
	_udp.set_broadcast_enabled(true)
	mode = Mode.SEARCH
	hosts.clear()
	first_host_ms = -1
	_start_ms = Time.get_ticks_msec()
	_t = 0.0
	_next_query = 0.0
	_queries_in_round = 0
	set_process(true)
	_poll()             # первый запрос — сразу, не через кадр
	return OK


## «Обновить»: список заново, запрос сразу.
func refresh() -> void:
	if mode != Mode.SEARCH:
		return
	hosts.clear()
	first_host_ms = -1
	_start_ms = Time.get_ticks_msec()
	_t = 0.0
	_next_query = 0.0
	_queries_in_round = 0
	hosts_changed.emit()
	_poll()


func stop() -> void:
	if _udp != null:
		_udp.close()
	_udp = null
	mode = Mode.NONE
	set_process(false)


func is_running() -> bool:
	return mode != Mode.NONE and _udp != null


# ------------------------------------------------------------------ ЦИКЛ

func _process(delta: float) -> void:
	_t += delta
	_poll()


func _poll() -> void:
	if _udp == null:
		return
	if mode == Mode.HOST:
		_host_poll()
	elif mode == Mode.SEARCH:
		_search_poll()


func _host_poll() -> void:
	for _k in PACKETS_PER_FRAME:
		if _udp.get_available_packet_count() <= 0:
			return
		var pkt: PackedByteArray = _udp.get_packet()
		var ip: String = _udp.get_packet_ip()
		var from_port: int = _udp.get_packet_port()
		if decode_query(pkt) < 0 or ip == "" or from_port <= 0:
			continue
		var d: Dictionary = announce.call() if announce.is_valid() else {}
		var ans: PackedByteArray = encode_answer(d)
		_udp.set_dest_address(ip, from_port)
		if _udp.put_packet(ans) == OK:
			answers_sent += 1
			last_answer_bytes = ans.size()


func _search_poll() -> void:
	if _t >= _next_query:
		_send_queries()
		_queries_in_round += 1
		_next_query = _t + (QUERY_SECOND if _queries_in_round == 1 else NetScript.DISCOVERY_PERIOD)
	var now: int = Time.get_ticks_msec()
	var changed: bool = false
	for _k in PACKETS_PER_FRAME:
		if _udp.get_available_packet_count() <= 0:
			break
		var pkt: PackedByteArray = _udp.get_packet()
		var ip: String = _udp.get_packet_ip()
		var e: Dictionary = decode_answer(pkt)
		if e.is_empty() or ip == "":
			continue
		answers_got += 1
		e["ip"] = ip
		var key: String = "%s:%d" % [ip, int(e["port"])]
		var old: Dictionary = hosts.get(key, {})
		e["first_ms"] = int(old.get("first_ms", now - _start_ms))
		e["seen_ms"] = now
		e["ping_ms"] = maxi(0, now - _last_send_ms)
		e["reason"] = incompat_reason(e, my_proto, my_build)
		hosts[key] = e
		if first_host_ms < 0:
			first_host_ms = now - _start_ms
		changed = true
	for key in hosts.keys():
		if now - int(hosts[key]["seen_ms"]) > int(NetScript.DISCOVERY_EXPIRE * 1000.0):
			hosts.erase(key)
			changed = true
	if changed:
		hosts_changed.emit()


func _send_queries() -> void:
	var q: PackedByteArray = encode_query(my_proto)
	var list: PackedStringArray = targets if not targets.is_empty() else broadcast_targets()
	for t in list:
		var ip: String = t
		var p: int = port
		var colon: int = t.rfind(":")
		if colon > 0:
			ip = t.substr(0, colon)
			p = int(t.substr(colon + 1))
		_udp.set_dest_address(ip, p)
		if _udp.put_packet(q) == OK:
			queries_sent += 1
			last_query_bytes = q.size()
	_last_send_ms = Time.get_ticks_msec()


## Записи списка по порядку: сначала совместимые, затем по имени и адресу.
func sorted_hosts() -> Array:
	var list: Array = hosts.values()
	list.sort_custom(func(a, b) -> bool:
		var ra: bool = String(a["reason"]) == ""
		var rb: bool = String(b["reason"]) == ""
		if ra != rb:
			return ra
		if String(a["name"]) != String(b["name"]):
			return String(a["name"]) < String(b["name"])
		return "%s:%d" % [a["ip"], int(a["port"])] < "%s:%d" % [b["ip"], int(b["port"])])
	return list


# ------------------------------------------------------------------ ФОРМАТ

## Запрос: "GCQ1" + proto u16 (big-endian) — 6 Б.
static func encode_query(proto: int) -> PackedByteArray:
	var b: PackedByteArray = QUERY_MAGIC.to_ascii_buffer()
	b.append((proto >> 8) & 0xFF)
	b.append(proto & 0xFF)
	return b


## proto запроса или −1, если это не запрос.
static func decode_query(b: PackedByteArray) -> int:
	if b.size() != 6 or b.slice(0, 4).get_string_from_ascii() != QUERY_MAGIC:
		return -1
	return (b[4] << 8) | b[5]


## Поля ответа и их типы (JSON отдаёт числа как float — приводим).
const ANSWER_FIELDS: Dictionary = {"v": TYPE_INT, "proto": TYPE_INT, "build": TYPE_STRING,
		"name": TYPE_STRING, "host": TYPE_STRING, "n": TYPE_INT, "max": TYPE_INT,
		"port": TYPE_INT, "day": TYPE_INT, "st": TYPE_STRING, "pw": TYPE_BOOL}


## Ответ: "GCA1" + JSON. Недостающие поля — значения по умолчанию.
static func encode_answer(d: Dictionary) -> PackedByteArray:
	var o: Dictionary = {"v": ANSWER_V, "proto": int(d.get("proto", NetScript.PROTO)),
			"build": String(d.get("build", NetScript.build_id())),
			"name": String(d.get("name", "")), "host": String(d.get("host", "")),
			"n": int(d.get("n", 1)), "max": int(d.get("max", 4)),
			"port": int(d.get("port", NetScript.GAME_PORT)), "day": int(d.get("day", 0)),
			"st": String(d.get("st", "lobby")), "pw": bool(d.get("pw", false))}
	var b: PackedByteArray = ANSWER_MAGIC.to_ascii_buffer()
	b.append_array(JSON.stringify(o).to_utf8_buffer())
	return b


## {} — если это не ответ или поля битые.
static func decode_answer(b: PackedByteArray) -> Dictionary:
	if b.size() < 6 or b.size() > ANSWER_MAX or b.slice(0, 4).get_string_from_ascii() != ANSWER_MAGIC:
		return {}
	var v = JSON.parse_string(b.slice(4).get_string_from_utf8())
	if not v is Dictionary:
		return {}
	var out: Dictionary = {}
	for k in ANSWER_FIELDS:
		if not (v as Dictionary).has(k):
			return {}
		var x = v[k]
		match int(ANSWER_FIELDS[k]):
			TYPE_INT:
				if not (x is float or x is int):
					return {}
				out[k] = int(x)
			TYPE_STRING:
				if not x is String:
					return {}
				out[k] = String(x).substr(0, 64)
			TYPE_BOOL:
				if not x is bool:
					return {}
				out[k] = bool(x)
	if int(out["port"]) <= 0 or int(out["port"]) > 65535:
		return {}
	return out


## Почему к игре нельзя подключиться ("" — можно). Сборка сравнивается точно
## (как в рукопожатии Net.check_hello: две "dev" равны).
static func incompat_reason(e: Dictionary, proto: int, build: String) -> String:
	if int(e.get("proto", -1)) != proto:
		return "другой протокол: у хоста %d, у вас %d" % [int(e.get("proto", -1)), proto]
	if String(e.get("build", "")) != build:
		return "другая версия: у хоста %s, у вас %s" % [String(e.get("build", "")), build]
	if int(e.get("n", 0)) >= int(e.get("max", 0)):
		return NetScript.R_FULL
	if bool(e.get("pw", false)):
		return "игра с паролем — нужна новая версия"
	return ""


# ------------------------------------------------------------------ АДРЕСА

## Цели широковещательного запроса: 255.255.255.255 и x.y.z.255 каждого своего IPv4
## (кроме петли и 169.254/16).
static func broadcast_targets() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray([BROADCAST])
	for ip in local_ipv4():
		var o: PackedStringArray = ip.split(".")
		var b: String = "%s.%s.%s.255" % [o[0], o[1], o[2]]
		if not out.has(b):
			out.append(b)
	return out


## Свои IPv4 без петли и link-local.
static func local_ipv4() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for ip in IP.get_local_addresses():
		if not is_ipv4(ip) or ip.begins_with("127.") or ip.begins_with("169.254."):
			continue
		if not out.has(ip):
			out.append(ip)
	return out


## Свои адреса из частных диапазонов (10/8, 172.16/12, 192.168/16) — экран хоста.
static func private_ipv4() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for ip in local_ipv4():
		if is_private(ip):
			out.append(ip)
	out.sort()
	return out


static func is_private(ip: String) -> bool:
	if not is_ipv4(ip):
		return false
	var o: PackedStringArray = ip.split(".")
	var a: int = int(o[0])
	var b: int = int(o[1])
	return a == 10 or (a == 172 and b >= 16 and b <= 31) or (a == 192 and b == 168)


## Строгий IPv4: четыре числа 0..255 без ведущих нулей.
static func is_ipv4(s: String) -> bool:
	var o: PackedStringArray = s.split(".")
	if o.size() != 4:
		return false
	for part in o:
		if part.is_empty() or part.length() > 3 or not part.is_valid_int() or part.begins_with("+") \
				or part.begins_with("-") or (part.length() > 1 and part.begins_with("0")):
			return false
		if int(part) > 255:
			return false
	return true
