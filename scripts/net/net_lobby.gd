class_name NetLobby
extends Node
## Лобби сетевой игры из меню (ADR-002 § 4.5, § 4.6; MP-H, #93): готовность игроков,
## старт хостом, ответы на поиск в локальной сети, возврат в меню по концу сессии.
##
## Узел живёт под /root (ensure()) — переживает смену сцены меню → игра, — пока идёт
## сессия, начатая из меню; с концом сессии уходит сам. Сессии из командной строки
## (--mp-host, --mp-join, харнесс --mp-scenario) его не создают: там всё как в MP-A.
##
## Хост: Net.host() + LanDiscovery-ответчик (поиск видит игру и в лобби, и в игре:
##   остальные входят в любой момент, § 4.6). Клиенты шлют LOBBY_READY; хост рассылает
##   LOBBY_STATE (кто готов, идёт ли игра) при каждом изменении и каждому вошедшему.
##   «Старт» — когда готовы все вошедшие (хост готов всегда): хост меняет сцену на игру
##   и, когда его мир построен, рассылает «игра идёт». Клиент строит мир по сиду
##   только после этого — снимок (MP-C) он просит у хоста с готовым миром.
## Клиент: «игра идёт» — сцена игры (вошедший позже попадает в мир сразу). Хост без
##   лобби (--mp-host) LOBBY не шлёт — через LOBBY_WAIT_MS клиент входит в мир сам.
## Конец сессии (хост закрыл игру, связь потеряна, «Выйти»): причина — в last_reason,
##   сцена игры сменяется меню.
##
## Пока меню на экране, дерево на паузе; узел, ответчик поиска и Net работают
## (PROCESS_MODE_ALWAYS) — иначе у Net не тикают таймауты входа.

signal changed

const NODE_NAME: String = "NetLobby"
const GAME_SCENE: String = "res://scenes/main.tscn"
const MENU_SCENE: String = "res://scenes/menu.tscn"
## Клиент: хост без лобби (--mp-host) не прислал LOBBY_STATE за столько — в мир.
const LOBBY_WAIT_MS: int = 2500

## Причина последнего конца сессии или отказа (меню показывает её строкой статуса).
static var last_reason: String = ""

## Игра идёт (хост нажал «Старт» и построил мир).
var started: bool = false
## peer_id → true: готовые клиенты (хост готов всегда).
var ready_peers: Dictionary = {}
## Хост: ответчик поиска (null — у клиента).
var discovery: LanDiscovery = null
## Хост: поиск не поднялся (порт занят) — причина; подключение по IP работает.
var discovery_error: String = ""
## Клиент: своя готовность (как ушла хосту).
var my_ready: bool = false

var _entering: bool = false      ## хост: мир строится — «игра идёт» разошлём, когда готов
var _joined_ms: int = -1         ## клиент: когда вошёл в сессию (ждём LOBBY_STATE)
var _got_state: bool = false
var _net_mode0: Node.ProcessMode = Node.PROCESS_MODE_INHERIT


## Узел лобби этого процесса (создаёт, если нет).
static func ensure(tree: SceneTree) -> NetLobby:
	var n: Node = tree.root.get_node_or_null(NODE_NAME)
	if n is NetLobby and not n.is_queued_for_deletion():
		return n
	if n != null:
		n.name = NODE_NAME + "_old"
	var l: NetLobby = NetLobby.new()
	l.name = NODE_NAME
	tree.root.add_child(l)
	return l


## Узел лобби или null.
static func find(tree: SceneTree) -> NetLobby:
	var n: Node = tree.root.get_node_or_null(NODE_NAME)
	return n if n is NetLobby and not n.is_queued_for_deletion() else null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_net_mode0 = Net.process_mode
	Net.process_mode = Node.PROCESS_MODE_ALWAYS
	Net.on(NetCodec.Msg.LOBBY, _on_lobby)
	Net.session_started.connect(_on_session_started)
	Net.session_ended.connect(_on_session_ended)
	Net.connection_failed.connect(_on_connection_failed)
	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)


func _exit_tree() -> void:
	if discovery != null:
		discovery.stop()
	Net.process_mode = _net_mode0
	if Net.session_started.is_connected(_on_session_started):
		Net.session_started.disconnect(_on_session_started)
		Net.session_ended.disconnect(_on_session_ended)
		Net.connection_failed.disconnect(_on_connection_failed)
		Net.peer_joined.disconnect(_on_peer_joined)
		Net.peer_left.disconnect(_on_peer_left)
	Net.on(NetCodec.Msg.LOBBY, Callable())


# ------------------------------------------------------------------ ХОСТ

## Поднять игру: сервер Net и ответчик поиска на disc_port (тот же bind_ip).
func host(port: int, bind_ip: String, p_seed: int, session_name: String, slots: int,
		disc_port: int = Net.DISCOVERY_PORT) -> Error:
	started = false
	ready_peers.clear()
	discovery_error = ""
	last_reason = ""
	var err: int = Net.host(port, bind_ip, p_seed, session_name, slots)
	if err != OK:
		last_reason = Net.last_error
		return err as Error
	discovery = LanDiscovery.new()
	discovery.name = "Discovery"
	add_child(discovery)
	var derr: Error = discovery.start_host(disc_port, bind_ip, announce)
	if derr != OK:
		discovery_error = "поиск в сети недоступен: порт %d занят (%s)" % [disc_port, error_string(derr)]
		push_warning("СЕТЬ: " + discovery_error)
	print("СЕТЬ: лобби «%s», %s:%d, мест %d, поиск %s:%d" % [session_name, bind_ip, port, slots,
			bind_ip, disc_port])
	changed.emit()
	return OK


## Поля ответа на поиск (LanDiscovery.encode_answer).
func announce() -> Dictionary:
	var full: bool = not Net.accepting or Net.peers.size() >= Net.max_players
	return {"proto": Net.PROTO, "build": Net.build_id(),
			"name": String(Net.session.get("session_name", "")),
			"host": String(Net.session.get("nick", "")),
			"n": Net.peers.size() if not full else maxi(Net.peers.size(), Net.max_players),
			"max": Net.max_players, "port": int(Net.session.get("port", Net.GAME_PORT)),
			"day": Game.day_number if started else 0, "st": "game" if started else "lobby",
			"pw": false}


## Готовы ли все вошедшие клиенты (хост — всегда).
func all_ready() -> bool:
	for id in Net.peers:
		if int(id) != 1 and not ready_peers.has(int(id)):
			return false
	return true


func is_ready(peer: int) -> bool:
	return peer == 1 or ready_peers.has(peer)


func can_start() -> bool:
	return Net.is_host() and not started and not _entering and all_ready()


## «Старт»: сцена игры; «игра идёт» клиентам — когда мир хоста построен (_process).
func start_game() -> bool:
	if not can_start():
		return false
	_entering = true
	changed.emit()
	get_tree().change_scene_to_file(GAME_SCENE)
	return true


## Хост: «Старт» нажат, мир ещё строится.
func is_entering() -> bool:
	return _entering


func _broadcast_state(peer: int = 0) -> void:
	if not Net.is_host():
		return
	var payload: PackedByteArray = NetCodec.encode_lobby_state(started, ready_peers.keys())
	if peer != 0:
		Net.send(NetCodec.Msg.LOBBY, payload, peer)
		return
	for id in Net.peers:
		if int(id) != 1:
			Net.send(NetCodec.Msg.LOBBY, payload, int(id))


func _on_peer_joined(id: int, _info: Dictionary) -> void:
	if Net.is_host():
		_broadcast_state(id)
	changed.emit()


func _on_peer_left(id: int, _info: Dictionary) -> void:
	ready_peers.erase(id)
	if Net.is_host():
		_broadcast_state()
	changed.emit()


## Мир этого процесса построен по сиду сессии (main.gd → World.generate, свой герой).
func world_ready() -> bool:
	var sc: Node = get_tree().current_scene
	if sc == null or sc.scene_file_path != GAME_SCENE:
		return false
	var p = Game.player
	return p != null and is_instance_valid(p) and p.is_inside_tree() \
			and World.world_seed == int(Net.session.get("seed", World.world_seed))


# ------------------------------------------------------------------ КЛИЕНТ

func join(ip: String, port: int) -> Error:
	started = false
	ready_peers.clear()
	my_ready = false
	_got_state = false
	_joined_ms = -1
	last_reason = ""
	var err: int = Net.join(ip, port)
	if err != OK:
		last_reason = Net.last_error
	return err as Error


func set_ready(on: bool) -> void:
	if not Net.is_client() or started:
		return
	my_ready = on
	Net.send(NetCodec.Msg.LOBBY, NetCodec.encode_lobby_ready(on))
	changed.emit()


func _enter_game() -> void:
	var sc: Node = get_tree().current_scene
	if sc != null and sc.scene_file_path == GAME_SCENE:
		return
	print("СЕТЬ: игра идёт — вход в мир хоста")
	get_tree().change_scene_to_file(GAME_SCENE)


# ------------------------------------------------------------------ СООБЩЕНИЯ И СЕССИЯ

func _on_lobby(sender: int, payload: PackedByteArray) -> void:
	var d: Dictionary = NetCodec.decode_lobby(payload)
	if d.is_empty():
		return
	if Net.is_host():
		if int(d["kind"]) != NetCodec.LOBBY_READY or sender == 1:
			return
		if bool(d["on"]):
			ready_peers[sender] = true
		else:
			ready_peers.erase(sender)
		_broadcast_state()
		changed.emit()
	elif Net.is_client() and sender == 1 and int(d["kind"]) == NetCodec.LOBBY_STATE:
		_got_state = true
		ready_peers.clear()
		for id in d["ready"]:
			ready_peers[int(id)] = true
		my_ready = ready_peers.has(Net.my_id())
		var was: bool = started
		started = bool(d["started"])
		changed.emit()
		if started and not was:
			_enter_game()


func _on_session_started() -> void:
	if Net.is_client():
		_joined_ms = Time.get_ticks_msec()
	changed.emit()


func _on_session_ended(reason: String) -> void:
	last_reason = reason
	if discovery != null:
		discovery.stop()
	var sc: Node = get_tree().current_scene
	if sc != null and sc.scene_file_path == GAME_SCENE and ResourceLoader.exists(MENU_SCENE):
		print("СЕТЬ: сессия окончена%s — в меню" % ((": " + reason) if reason != "" else ""))
		get_tree().paused = false
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE)
	changed.emit()
	queue_free()


func _on_connection_failed(reason: String) -> void:
	last_reason = reason
	changed.emit()
	queue_free()


func _process(_delta: float) -> void:
	if Net.is_host() and _entering and world_ready():
		_entering = false
		started = true
		_broadcast_state()
		print("СЕТЬ: мир хоста готов — «игра идёт» (%d игроков)" % Net.peers.size())
		changed.emit()
	elif Net.is_client() and not _got_state and not started and _joined_ms >= 0 \
			and Time.get_ticks_msec() - _joined_ms > LOBBY_WAIT_MS:
		started = true            # хост без лобби (--mp-host): игра уже идёт
		changed.emit()
		_enter_game()
