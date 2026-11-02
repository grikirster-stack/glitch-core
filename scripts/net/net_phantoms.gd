class_name NetPhantoms
extends Node
## Фантомы по сети (ADR-002 § 4.2.5, § 4.3, D1, D6; MP-F, #92).
##
## ИИ, путь, свет, урон — только на хосте. Узел живёт под NetPlayers и молчит без сессии.
##
## Хост: в каждом сетевом такте (NetPlayers._send_state, 20 Гц) сверяет группу «phantom»
##   со списком объявленных: новый фантом получает номер (u16, Phantom.net_id) и уходит
##   клиентам событием SPAWN вида NetCodec.Ent.PHANTOM {вид, стая, имя, позиция} по
##   каналу 0; исчезнувший (убит, растворился, сброс мира) — DESPAWN. Клиент, которому
##   только что ушёл снимок мира (NetWorld.synced), получает SPAWN всех живых — после
##   снимка в том же канале, порядок держит ENet. Позиции и флаги — строки по 12 Б
##   (NetCodec._put_phantom) в пакете состояния, только фантомы в зоне интереса
##   клиента (Net.AOI_HALF вокруг его героя, § 4.2.1).
## Клиент: фантом — марионетка (Phantom.net_puppet): ИИ не работает, _draw прежний.
##   Строки копятся в буфер по номеру и рисуются на Net.INTERP_DELAY в прошлом по тем
##   же часам, что и чужие герои (NetPlayers.render_time): интерполяция между пакетами,
##   за последним — экстраполяция не дальше Net.EXTRAP_MAX, скачок дальше SNAP_DIST —
##   без интерполяции. Строк нет дольше STALE (фантом ушёл из зоны интереса) — марионетка
##   прячется до следующей строки.

## Строк фантома нет дольше этого (часы хоста, с) — ушёл из зоны интереса: прячем.
const STALE: float = 0.3
## Скачок между пакетами — телепорт, без интерполяции, px.
const SNAP_DIST: float = 96.0
## Сколько секунд строк держит буфер марионетки.
const BUF_SEC: float = 1.0

var np: NetPlayers = null
## Замеры и проверки сценариев: хост — spawn/despawn/rows; клиент — rx_rows, spawned.
var stats: Dictionary = {}

var _active: bool = false
# --- хост
var _next_id: int = 1
var _known: Dictionary = {}       ## instance_id фантома → Phantom (объявленные)
var _known_ids: Dictionary = {}   ## instance_id → номер: у освобождённого узла его не прочесть
var _peers_sent: Dictionary = {}  ## peer_id → true: получил SPAWN всех живых
var _rows: Array = []             ## строки этого такта (все объявленные фантомы)
# --- клиент
## Номер → Phantom-марионетка.
var puppets: Dictionary = {}
var _buf: Dictionary = {}         ## номер → Array[{t, pos, vel, row}]


func start(p_np: NetPlayers) -> void:
	np = p_np
	Net.session_started.connect(_begin)
	Net.session_ended.connect(_end)
	if Net.is_online():
		_begin()


func _begin() -> void:
	if _active:
		return
	_active = true
	stats = {"spawn": 0, "despawn": 0, "rows": 0, "rx_rows": 0, "spawned": 0, "despawned": 0}
	_known.clear()
	_known_ids.clear()
	_peers_sent.clear()
	_rows.clear()
	_buf.clear()
	_free_puppets()
	Net.on_entity(NetCodec.Ent.PHANTOM, _on_spawn, _on_despawn)


func _end(_reason: String = "") -> void:
	_active = false
	_known.clear()
	_known_ids.clear()
	_peers_sent.clear()
	_rows.clear()
	_free_puppets()


# ------------------------------------------------------------------ ХОСТ

## Сетевой такт хоста (из NetPlayers._send_state): объявить новых, убрать исчезнувших,
## разослать живых вошедшим клиентам, собрать строки такта.
func host_sync() -> void:
	if not _active or not Net.is_host():
		return
	# Исчезнувшие — первыми: место в лимите MAX_PHANTOMS у клиента освобождается раньше,
	# чем приходит новый.
	for key in _known.keys():
		if is_instance_valid(_known[key]) and (_known[key] as Phantom).alive \
				and (_known[key] as Phantom).is_inside_tree():
			continue
		_send_all(NetCodec.encode_despawn(NetCodec.Ent.PHANTOM, int(_known_ids.get(key, 0))))
		_known.erase(key)
		_known_ids.erase(key)
		stats["despawn"] = int(stats["despawn"]) + 1
	for n in get_tree().get_nodes_in_group("phantom"):
		var p: Phantom = n as Phantom
		if p == null or not p.alive or _known.has(p.get_instance_id()):
			continue
		p.net_id = _next_id
		_next_id = _next_id % 0xFFFF + 1     # 1..65535, 0 — «не объявлен»
		_known[p.get_instance_id()] = p
		_known_ids[p.get_instance_id()] = p.net_id
		_send_all(_spawn_payload(p))
		stats["spawn"] = int(stats["spawn"]) + 1
	# Вошедшие клиенты (снимок ушёл) — все живые фантомы разом.
	var synced: Dictionary = Game.net_world.synced if Game.net_world != null else {}
	for id in synced:
		if _peers_sent.has(id):
			continue
		_peers_sent[id] = true
		for key in _known:
			Net.send(NetCodec.Msg.SPAWN, _spawn_payload(_known[key]), int(id))
	for id in _peers_sent.keys():
		if not synced.has(id):
			_peers_sent.erase(id)
	_rows.clear()
	for key in _known:
		_rows.append((_known[key] as Phantom).net_row())


## Строки фантомов в зоне интереса героя (у хоста герой клиента — прокси).
func rows_for(hero: Node2D) -> Array:
	if hero == null or not is_instance_valid(hero) or _rows.is_empty():
		return []
	var c: Vector2 = hero.global_position
	var out: Array = []
	for r in _rows:
		var d: Vector2 = (r["pos"] as Vector2) - c
		if absf(d.x) <= Net.AOI_HALF.x and absf(d.y) <= Net.AOI_HALF.y:
			out.append(r)
	stats["rows"] = int(stats["rows"]) + out.size()
	return out


## Сколько фантомов объявлено клиентам.
func known_count() -> int:
	return _known.size()


func _spawn_payload(p: Phantom) -> PackedByteArray:
	return NetCodec.encode_phantom_spawn(p.net_id, {"kind": maxi(0, NetCodec.PHANTOM_KINDS.find(p.kind)),
			"pack": p.pack_id, "name": p.display_name, "pos": p.global_position})


## Каждому клиенту, получившему снимок (до снимка его мир ещё не тот).
func _send_all(payload: PackedByteArray) -> void:
	var msg: int = NetCodec.Msg.SPAWN if payload.size() > 3 else NetCodec.Msg.DESPAWN
	for id in _peers_sent:
		Net.send(msg, payload, int(id))


# ------------------------------------------------------------------ КЛИЕНТ

func _on_spawn(sender: int, payload: PackedByteArray) -> void:
	if sender != 1 or not Net.is_client():
		return
	var d: Dictionary = NetCodec.decode_phantom_spawn(payload)
	if d.is_empty():
		return
	var id: int = int(d["id"])
	var p: Phantom = puppets[id] if is_instance_valid(puppets.get(id)) else null
	if p == null:
		var host: Node = get_tree().current_scene
		if host == null:
			return
		p = Phantom.create(String(NetCodec.PHANTOM_KINDS[int(d["kind"])]))
		p.net_puppet = true
		p.net_id = id
		host.add_child(p)
		puppets[id] = p
		_buf[id] = []
		stats["spawned"] = int(stats["spawned"]) + 1
	p.pack_id = int(d["pack"])
	if String(d["name"]) != "":
		p.display_name = String(d["name"])
	p.global_position = d["pos"]
	p.spawn_point = d["pos"]
	p.visible = false        # покажется с первой строкой состояния


func _on_despawn(sender: int, payload: PackedByteArray) -> void:
	if sender != 1 or not Net.is_client():
		return
	var d: Dictionary = NetCodec.decode_despawn(payload)
	if d.is_empty():
		return
	_remove(int(d["id"]))
	stats["despawned"] = int(stats["despawned"]) + 1


## Строки пакета состояния (NetPlayers._on_state): t — часы хоста этого такта, с.
func on_state(t: float, rows: Array) -> void:
	if not _active:
		return
	for row in rows:
		var id: int = int(row["id"])
		if not _buf.has(id):
			continue          # SPAWN ещё не дошёл (каналы разные) — строку пропускаем
		var b: Array = _buf[id]
		# Перерыв (фантом выходил из зоны интереса): старые строки не интерполируем.
		if not b.is_empty() and t - float(b[b.size() - 1]["t"]) > STALE:
			b.clear()
		b.append({"t": t, "pos": row["pos"], "vel": row["vel"], "row": row})
		while b.size() > 2 and float(b[0]["t"]) < t - BUF_SEC:
			b.pop_front()
		stats["rx_rows"] = int(stats["rx_rows"]) + 1


## Марионетки — в кадре отрисовки, после NetPlayers._process (часы рисования).
func _process(_delta: float) -> void:
	if not _active or not Net.is_client() or np == null:
		return
	var rt: float = np.render_time
	for id in puppets.keys():
		if not is_instance_valid(puppets[id]):
			puppets.erase(id)
			_buf.erase(id)
			continue
		var p: Phantom = puppets[id]
		var b: Array = _buf.get(id, [])
		if b.is_empty() or rt - float(b[b.size() - 1]["t"]) > STALE:
			p.visible = false
			continue
		p.visible = true
		_interp(p, b, rt)
	Game.phantoms_alive = puppets.size()


## Интерполяция марионетки между строками (как NetPlayers._interp у героев).
func _interp(p: Phantom, b: Array, rt: float) -> void:
	var pos: Vector2
	var vel: Vector2
	var row: Dictionary
	var last: Dictionary = b[b.size() - 1]
	if rt >= float(last["t"]):
		var ex: float = minf(rt - float(last["t"]), Net.EXTRAP_MAX)
		vel = last["vel"]
		if (int(last["row"]["flags"]) & NetCodec.PHF_ON_GROUND) != 0:
			vel.y = 0.0
		pos = last["pos"] + vel * ex
		row = last["row"]
	elif rt <= float(b[0]["t"]):
		pos = b[0]["pos"]
		vel = b[0]["vel"]
		row = b[0]["row"]
	else:
		var i: int = 0
		while i < b.size() - 2 and float(b[i + 1]["t"]) <= rt:
			i += 1
		var a: Dictionary = b[i]
		var c: Dictionary = b[i + 1]
		var f: float = (rt - float(a["t"])) / maxf(float(c["t"]) - float(a["t"]), 0.0001)
		var pa: Vector2 = a["pos"]
		var pc: Vector2 = c["pos"]
		if pa.distance_to(pc) > SNAP_DIST:
			pos = pc if f >= 0.5 else pa
		else:
			pos = pa.lerp(pc, f)
		vel = (a["vel"] as Vector2).lerp(c["vel"], f)
		row = c["row"] if f >= 0.5 else a["row"]
	p.net_apply(pos, vel, row)


func _remove(id: int) -> void:
	var ok: bool = is_instance_valid(puppets.get(id))
	var p: Phantom = puppets[id] if ok else null
	puppets.erase(id)
	_buf.erase(id)
	if p == null:
		return
	# Из дерева сразу: в этом же кадре может прийти новый, а лимит MAX_PHANTOMS
	# считает группу.
	if p.get_parent() != null:
		p.get_parent().remove_child(p)
	p.queue_free()


func _free_puppets() -> void:
	for id in puppets.keys():
		_remove(int(id))
	puppets.clear()
	_buf.clear()
