class_name NetMachines
extends Node
## Машины и предметы по сети (ADR-002, MP-E #90; § 4.2.1, § 4.2.4, § 4.3).
## Узел живёт под Game рядом с NetWorld (секция «СЕТЬ» game.gd) и идёт в физическом
## кадре сразу после него: дельты тайлов такта уходят раньше построек и предметов —
## клиент ставит машину и пускает предмет уже по новым тайлам. Без сессии молчит.
##
## Постройка и снос (§ 4.2.1): хост раз в сетевой такт (20 Гц) сверяет World.machines
##   со своим списком; новая машина — MACHINE_ADD = var_to_bytes(save_state()) всем
##   клиентам в рассылке (NetWorld.synced), снесённая — MACHINE_DEL = u32 клетка.
## Состояние (§ 4.2.4): раз в 0.25 с (Net.MACHINE_HZ) хост собирает net_state() машин
##   в зоне интереса клиента (±Net.AOI_HALF вокруг его героя) и шлёт MACHINES только с
##   теми, чей net_state() изменился с прошлой отправки этому клиенту. Выстрел турели —
##   в ближайший такт, не ждёт 4 Гц. Мягкий предел (§ 4.3): если хост отдаёт клиенту
##   больше Net.SOFT_BUDGET Б/с, машины переходят на 1 Гц.
## Предметы (§ 4.2.1): хост выдаёт предмету net_id и шлёт SPAWN (вид ENT_ITEM, запись
##   ItemEntity.net_record() + мешок) клиенту, в чью зону интереса он попал; при смене
##   числа, приземлении, отказе в подборе — SPAWN заново (обновление); исчез —
##   DESPAWN тем, кто его знает. У клиента предмет — марионетка (item_entity.gd).
## Вход: снимок (NetWorld) уже несёт машины и предметы. Новый клиент в рассылке — его
##   кэш пуст: машины в зоне придут net_state, предметы — SPAWN; предметы снимка у
##   клиента без net_id убираются (их заменят марионетки с номерами хоста).

## Вид сущности в SPAWN/DESPAWN. Остальные виды (фантомы — MP-F) — entity_handlers.
const ENT_ITEM: int = 1
## Машины раз в столько сетевых тактов: 20 / 4 Гц.
const MACHINE_EVERY: int = Net.TICK_HZ / Net.MACHINE_HZ
## Сверх мягкого предела — 1 Гц.
const SLOW_EVERY: int = Net.TICK_HZ
## Центр зоны интереса — с шагом ZONE_SNAP px: герой, переступающий на месте, не
## заставляет заново обходить машины его зоны.
const ZONE_SNAP: float = 32.0
## Окно замеров трафика, тактов (1 с).
const WINDOW_TICKS: int = Net.TICK_HZ

## Чужие виды сущностей: kind → {spawn: Callable(id, data), despawn: Callable(id)}.
var entity_handlers: Dictionary = {}

# --- хост
## Мягкий предел, Б/с на клиента (сценарий меряет и с другим).
var soft_budget: int = Net.SOFT_BUDGET
## true — машины идут раз в секунду (трафик сверх мягкого предела).
var slow: bool = false
var adds_tx: int = 0
var dels_tx: int = 0
var states_tx: int = 0          ## записей net_state отправлено (на всех клиентов)
var spawns_tx: int = 0
var despawns_tx: int = 0
## Б полезной нагрузки (с байтом типа) по клиентам: peer → Б; и по видам.
var peer_bytes: Dictionary = {}
var state_bytes: int = 0
var event_bytes: int = 0
var item_bytes: int = 0
## Сбор net_state за машинный такт, мкс: последний, худший, сумма и число.
var gather_us: int = 0
var gather_us_max: int = 0
var gather_us_sum: int = 0
var gather_n: int = 0
## Машин в последнем сборе (у всех клиентов в зоне).
var gather_machines: int = 0
## Из них — постройка net_state всех машин (остальное — сравнение и раскладка по клиентам).
var build_us: int = 0

# --- клиент
var adds_rx: int = 0
var dels_rx: int = 0
var states_rx: int = 0
var spawns_rx: int = 0
var despawns_rx: int = 0
var purged: int = 0             ## предметов снимка убрано (их заменили марионетки)

var _frame: int = 0
var _tick: int = 0
## хост: клиент → {"ms": {клетка: net_state, отправленный ему}, "items": {net_id: true}}
var _peers: Dictionary = {}
var _snap_seen: int = 0
var _machines: Dictionary = {}  ## хост: клетка (y·W + x) → машина, какой её знают клиенты
var _last: Dictionary = {}      ## хост: клетка → net_state прошлого машинного такта
var _ids: Dictionary = {}       ## хост: клетка → instance_id той машины
var _shots: Dictionary = {}     ## хост: клетка турели → выстрелов, о которых клиенты знают
var _items: Dictionary = {}     ## хост: net_id → ItemEntity
var _item_sig: Dictionary = {}  ## хост: net_id → подпись (число, приземлён, мешок)
var _next_item: int = 1
var _rate_prev: int = 0
var _puppets: Dictionary = {}   ## клиент: net_id → ItemEntity
var _snap_got: int = 0


func _ready() -> void:
	set_physics_process(false)
	Net.session_started.connect(_on_session_started)
	Net.session_ended.connect(_on_session_ended)
	Net.on(NetCodec.Msg.MACHINE_ADD, _on_add)
	Net.on(NetCodec.Msg.MACHINE_DEL, _on_del)
	Net.on(NetCodec.Msg.MACHINES, _on_machines)
	Net.on(NetCodec.Msg.SPAWN, _on_spawn)
	Net.on(NetCodec.Msg.DESPAWN, _on_despawn)
	if Net.is_online() and Net.session.has("mode"):
		_on_session_started()


# ------------------------------------------------------------------ СЕССИЯ

func _on_session_started() -> void:
	_frame = 0
	_tick = 0
	_peers.clear()
	_machines.clear()
	_last.clear()
	_ids.clear()
	_shots.clear()
	_items.clear()
	_item_sig.clear()
	_puppets.clear()
	_snap_seen = Game.net_world.snapshots_sent if Game.net_world != null else 0
	_snap_got = 0
	slow = false
	reset_traffic()
	if Net.is_host():
		_scan_machines(false)
		# Предметы, упавшие до сессии, — тоже в рассылку.
		for e in Save._item_nodes():
			e.add_to_group(ItemEntity.NET_GROUP)
	set_physics_process(true)


func _on_session_ended(_reason: String) -> void:
	_peers.clear()
	_puppets.clear()
	set_physics_process(false)


## Обнулить замеры трафика и сбора.
func reset_traffic() -> void:
	adds_tx = 0
	dels_tx = 0
	states_tx = 0
	spawns_tx = 0
	despawns_tx = 0
	peer_bytes.clear()
	state_bytes = 0
	event_bytes = 0
	item_bytes = 0
	gather_us = 0
	gather_us_max = 0
	gather_us_sum = 0
	gather_n = 0
	_rate_prev = _net_total()


# ------------------------------------------------------------------ ТАКТ

func _physics_process(_delta: float) -> void:
	if Net.is_host():
		_frame += 1
		if _frame % NetWorld.TICK_FRAMES == 0:
			_host_tick()
	elif Net.is_client():
		_client_tick()


func _host_tick() -> void:
	_tick += 1
	_sync_peers()
	var send: bool = not _peers.is_empty()
	_scan_machines(send)
	if not send:
		return
	if _tick % WINDOW_TICKS == 0:
		_check_budget()
	var every: int = SLOW_EVERY if slow else MACHINE_EVERY
	var machine_tick: bool = _tick % every == 0
	_scan_items(machine_tick)
	if machine_tick:
		send_states()
	else:
		_send_shots()


## Клиенты в рассылке — те, кому NetWorld отдал снимок. Новый — с пустым кэшем;
## снимок заново тому, кто уже был (сверка разошлась), — кэш пуст у всех.
func _sync_peers() -> void:
	var nw: NetWorld = Game.net_world
	for id in _peers.keys():
		if not nw.synced.has(id):
			_peers.erase(id)
	var fresh: int = 0
	for id in nw.synced:
		if not _peers.has(id):
			_peers[id] = {"ms": {}, "items": {}}
			fresh += 1
	if nw.snapshots_sent != _snap_seen:
		if nw.snapshots_sent - _snap_seen > fresh:
			for id in _peers:
				_peers[id] = {"ms": {}, "items": {}}
		_snap_seen = nw.snapshots_sent


## Мягкий предел (§ 4.3): всё, что Net отдал за секунду, на одного клиента.
func _check_budget() -> void:
	var total: int = _net_total()
	var rate: int = (total - _rate_prev) / maxi(1, _peers.size())
	_rate_prev = total
	slow = rate > soft_budget


func _net_total() -> int:
	var s: int = 0
	for k in Net.sent_bytes:
		s += int(Net.sent_bytes[k])
	return s


# ------------------------------------------------------------------ ХОСТ: ПОСТРОЙКИ

## Сверить World.machines со списком, который знают клиенты: новые — MACHINE_ADD,
## пропавшие и заменённые — MACHINE_DEL (send = false — только запомнить).
func _scan_machines(send: bool) -> void:
	var matched: int = 0
	for c in World.machines:
		var m = World.machines[c]
		if not is_instance_valid(m) or m.is_queued_for_deletion():
			continue
		var idx: int = c.y * World.W + c.x
		var iid: int = m.get_instance_id()
		matched += 1
		if int(_ids.get(idx, 0)) == iid:
			continue
		if _ids.has(idx) and send:
			_send_del(idx)                   # та же клетка, другая машина: замена
		_ids[idx] = iid
		_machines[idx] = m
		_last.erase(idx)
		if m is Turret:
			_shots[idx] = m.shots
		if send:
			_send_add(m)
	if matched == _ids.size():
		return
	for idx in _ids.keys():
		var m = _machines.get(idx)
		var c: Vector2i = Vector2i(idx % World.W, idx / World.W)
		if is_instance_valid(m) and not m.is_queued_for_deletion() and World.machines.get(c) == m:
			continue
		_ids.erase(idx)
		_machines.erase(idx)
		_last.erase(idx)
		_shots.erase(idx)
		if send:
			_send_del(idx)


func _send_add(m) -> void:
	var payload: PackedByteArray = NetCodec.encode_machine_add(m.save_state())
	for id in _peers:
		_peers[id]["ms"].erase(m.cell.y * World.W + m.cell.x)
		_tx(NetCodec.Msg.MACHINE_ADD, payload, id)
		event_bytes += payload.size() + 1
	adds_tx += 1


func _send_del(idx: int) -> void:
	var payload: PackedByteArray = NetCodec.encode_u32(idx)
	for id in _peers:
		_peers[id]["ms"].erase(idx)
		_tx(NetCodec.Msg.MACHINE_DEL, payload, id)
		event_bytes += payload.size() + 1
	dels_tx += 1


# ------------------------------------------------------------------ ХОСТ: СОСТОЯНИЕ

## Машинный такт: каждому клиенту — изменённые net_state машин его зоны интереса.
## net_state каждой машины строится один раз за такт и сравнивается с прошлым (_last):
## изменённые идут всем клиентам, у кого машина в зоне. Клиенту, чья зона сдвинулась
## (герой ушёл дальше ZONE_SNAP) или кто только вошёл, — полный проход по его кэшу:
## машины, вошедшие в зону, получат своё состояние. Сбор меряется в gather_us.
func send_states() -> void:
	var t0: int = Time.get_ticks_usec()
	var changed: Array = []
	for idx in _machines:
		var m = _machines[idx]
		if not is_instance_valid(m):
			continue
		var st: PackedByteArray = m.net_state()
		if _last.get(idx) != st:
			_last[idx] = st
			changed.append(idx)
	build_us = Time.get_ticks_usec() - t0
	var out: Dictionary = {}
	for id in _peers:
		var pd: Dictionary = _peers[id]
		var cache: Dictionary = pd["ms"]
		var has_c: Array = [false]
		var rect: Rect2 = _aoi(id, has_c)
		var list: Array = []
		if bool(pd.get("full", true)) or pd.get("rect") != rect:
			pd["full"] = false
			pd["rect"] = rect
			for idx in _machines:
				if has_c[0] and not rect.has_point(_machines[idx].global_position):
					continue
				var st = _last.get(idx)
				if st == null or cache.get(idx) == st:
					continue
				cache[idx] = st
				list.append([idx, st])
		else:
			for idx in changed:
				if has_c[0] and not rect.has_point(_machines[idx].global_position):
					continue
				cache[idx] = _last[idx]
				list.append([idx, _last[idx]])
		out[id] = list
	for idx in _shots:
		var t = _machines.get(idx)
		if is_instance_valid(t):
			_shots[idx] = t.shots
	gather_us = Time.get_ticks_usec() - t0
	gather_us_max = maxi(gather_us_max, gather_us)
	gather_us_sum += gather_us
	gather_n += 1
	gather_machines = _machines.size()
	for id in out:
		_send_states_to(id, out[id])


## Выстрел турели — в ближайший такт (дуга и звук у клиента без задержки 4 Гц).
func _send_shots() -> void:
	var fired: Array = []
	for idx in _shots:
		var t = _machines.get(idx)
		if is_instance_valid(t) and t.shots != int(_shots[idx]):
			_shots[idx] = t.shots
			fired.append(idx)
	if fired.is_empty():
		return
	for idx in fired:
		_last[idx] = _machines[idx].net_state()
	for id in _peers:
		var cache: Dictionary = _peers[id]["ms"]
		var has_c: Array = [false]
		var rect: Rect2 = _aoi(id, has_c)
		var list: Array = []
		for idx in fired:
			var t = _machines[idx]
			if has_c[0] and not rect.has_point(t.global_position):
				continue
			var st: PackedByteArray = _last[idx]
			cache[idx] = st
			list.append([idx, st])
		_send_states_to(id, list)


func _send_states_to(id: int, list: Array) -> void:
	if list.is_empty():
		return
	var payload: PackedByteArray = NetCodec.encode_machines(list)
	_tx(NetCodec.Msg.MACHINES, payload, id)
	state_bytes += payload.size() + 1
	states_tx += list.size()


## Зона интереса клиента: ±Net.AOI_HALF вокруг его героя (Game.players, peer_id).
## Героя нет (он ещё не поставлен) — has[0] = false: зона — весь мир.
func _aoi(peer: int, has: Array) -> Rect2:
	for p in Game.players:
		if is_instance_valid(p) and int(p.get("peer_id")) == peer:
			has[0] = true
			var c: Vector2 = (p.global_position / ZONE_SNAP).round() * ZONE_SNAP
			return Rect2(c - Net.AOI_HALF, Net.AOI_HALF * 2.0)
	has[0] = false
	return Rect2()


# ------------------------------------------------------------------ ХОСТ: ПРЕДМЕТЫ

## Предметы: новые — номер; изменённые — обновление тем, кто знает; попавшие в зону
## интереса — появление (новые сразу, остальные — в машинный такт); исчезнувшие —
## DESPAWN тем, кто знал.
func _scan_items(full: bool) -> void:
	for e in get_tree().get_nodes_in_group(ItemEntity.NET_GROUP):
		if e.is_queued_for_deletion():
			continue
		var fresh: bool = false
		if e.net_id == 0:
			e.net_id = _alloc_item()
			_items[e.net_id] = e
			_item_sig[e.net_id] = _sig(e)
			fresh = true
		var id: int = e.net_id
		var sig: int = _sig(e)
		var old: int = int(_item_sig.get(id, sig))
		var changed: bool = sig != old
		_item_sig[id] = sig
		# Начало притяжения к герою клиент предсказывает сам — его не шлём.
		if changed and (old ^ sig) == SIG_MAGNET and (sig & SIG_MAGNET) != 0:
			changed = false
		if not (fresh or changed or full):
			continue
		var payload: PackedByteArray = PackedByteArray()
		for pid in _peers:
			var known: Dictionary = _peers[pid]["items"]
			if known.has(id):
				if not changed:
					continue
			elif not _in_aoi(pid, e.global_position):
				continue
			if payload.is_empty():
				payload = _item_payload(e)
			known[id] = true
			_tx(NetCodec.Msg.SPAWN, payload, pid)
			item_bytes += payload.size() + 1
			spawns_tx += 1
	for id in _items.keys():
		var e = _items[id]
		if is_instance_valid(e) and not e.is_queued_for_deletion() and e.is_inside_tree():
			continue
		_items.erase(id)
		_item_sig.erase(id)
		var payload: PackedByteArray = NetCodec.encode_despawn(ENT_ITEM, id)
		for pid in _peers:
			if _peers[pid]["items"].erase(id):
				_tx(NetCodec.Msg.DESPAWN, payload, pid)
				item_bytes += payload.size() + 1
				despawns_tx += 1


const SIG_GROUNDED: int = 1 << 20
const SIG_MAGNET: int = 1 << 21


func _sig(e) -> int:
	return (e.count & 0xFFFFF) | (SIG_GROUNDED if e.grounded else 0) | (SIG_MAGNET if e.magnet else 0) \
			| (e.bag.size() << 22)


func _item_payload(e) -> PackedByteArray:
	var data: Dictionary = {"r": e.net_record()}
	if not e.bag.is_empty():
		data["b"] = e.bag.duplicate(true)
	return NetCodec.encode_spawn(ENT_ITEM, e.net_id, data)


func _alloc_item() -> int:
	for _k in 0xFFFF:
		var id: int = _next_item
		_next_item = _next_item % 0xFFFF + 1
		if not _items.has(id):
			return id
	return _next_item


func _in_aoi(peer: int, pos: Vector2) -> bool:
	var has_c: Array = [false]
	var rect: Rect2 = _aoi(peer, has_c)
	return not has_c[0] or rect.has_point(pos)


func _tx(msg: int, payload: PackedByteArray, peer: int) -> void:
	Net.send(msg, payload, peer)
	peer_bytes[peer] = int(peer_bytes.get(peer, 0)) + payload.size() + 1


# ------------------------------------------------------------------ КЛИЕНТ

func _client_tick() -> void:
	var nw: NetWorld = Game.net_world
	if nw == null or nw.snapshots_got == _snap_got:
		return
	# Снимок применён (вход или заново): предметы снимка — без номеров хоста, их
	# заменят марионетки из SPAWN; старые марионетки снимок уже убрал.
	_snap_got = nw.snapshots_got
	for id in _puppets.keys():
		if not is_instance_valid(_puppets[id]):
			_puppets.erase(id)
	for e in get_tree().get_nodes_in_group(ItemEntity.NET_GROUP):
		if e.net_id == 0 and not e.is_queued_for_deletion():
			e.queue_free()
			purged += 1


func _joined_from(sender: int) -> bool:
	return Net.is_client() and sender == 1 and Game.net_world != null and Game.net_world.is_joined


func _on_add(sender: int, payload: PackedByteArray) -> void:
	if not _joined_from(sender):
		return
	var d = NetCodec.decode_machine_add(payload)
	if d == null:
		return
	var c: Vector2i = d.get("cell", Vector2i(-1, -1))
	var kind: String = String(d.get("kind", ""))
	if not World.in_bounds(c.x, c.y):
		return
	adds_rx += 1
	var old = World.machines.get(c)
	if is_instance_valid(old):
		if String(old.kind) == kind:
			old.load_state(d)                # уже есть (пришла и снимком) — состояние
			return
		old.net_remove()
	# Постройку ставит хост: у клиента в её клетке на миг может быть не воздух
	# (вода натекла) — как Save, на время постановки воздух.
	var t: int = World.get_tile_v(c)
	if t != IDs.T.AIR:
		World.set_tile_raw(c.x, c.y, IDs.T.AIR)
	var placed: bool = MachineBase.place_machine(kind, c)
	if t != IDs.T.AIR:
		World.set_tile_raw(c.x, c.y, t)
	if placed:
		World.machines[c].load_state(d)
	else:
		push_warning("СЕТЬ: постройка «%s» в %s не поставлена" % [kind, str(c)])


func _on_del(sender: int, payload: PackedByteArray) -> void:
	if not _joined_from(sender):
		return
	var idx: int = NetCodec.decode_u32(payload)
	if idx < 0:
		return
	dels_rx += 1
	var m = World.machines.get(Vector2i(idx % World.W, idx / World.W))
	if is_instance_valid(m):
		m.net_remove()


func _on_machines(sender: int, payload: PackedByteArray) -> void:
	if not _joined_from(sender):
		return
	var list = NetCodec.decode_machines(payload)
	if list == null:
		return
	for e in list:
		var idx: int = int(e[0])
		var m = World.machines.get(Vector2i(idx % World.W, idx / World.W))
		if is_instance_valid(m) and m.has_method("apply_net_state"):
			m.apply_net_state(e[1])
			states_rx += 1


func _on_spawn(sender: int, payload: PackedByteArray) -> void:
	if not _joined_from(sender):
		return
	var s: Dictionary = NetCodec.decode_spawn(payload)
	if s.is_empty():
		return
	var kind: int = int(s["kind"])
	var id: int = int(s["id"])
	if kind != ENT_ITEM:
		var h: Dictionary = entity_handlers.get(kind, {})
		if h.has("spawn"):
			h["spawn"].call(id, s["data"])
		return
	var rec = s["data"].get("r")
	if not (rec is PackedByteArray):
		return
	var bag: Array = []
	var b = s["data"].get("b", [])
	if b is Array:
		bag = b
	var e = _puppets.get(id)
	if not is_instance_valid(e) or e.is_queued_for_deletion():
		e = ItemEntity.new()
		e.net_id = id
		World.add_world_node(e)          # _ready даёт случайный подброс — запись поверх
		_puppets[id] = e
	e.net_apply(rec, bag)
	spawns_rx += 1


func _on_despawn(sender: int, payload: PackedByteArray) -> void:
	if not _joined_from(sender):
		return
	var s: Dictionary = NetCodec.decode_despawn(payload)
	if s.is_empty():
		return
	var kind: int = int(s["kind"])
	var id: int = int(s["id"])
	if kind != ENT_ITEM:
		var h: Dictionary = entity_handlers.get(kind, {})
		if h.has("despawn"):
			h["despawn"].call(id)
		return
	despawns_rx += 1
	var e = _puppets.get(id)
	_puppets.erase(id)
	if is_instance_valid(e):
		e.queue_free()


## Клиент: марионетки предметов (сценарии).
func puppet_count() -> int:
	var n: int = 0
	for id in _puppets:
		if is_instance_valid(_puppets[id]) and not _puppets[id].is_queued_for_deletion():
			n += 1
	return n
