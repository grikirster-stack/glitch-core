class_name NetWorld
extends Node
## Мир по сети (ADR-002, MP-C #88; § 3 D4, D5; § 4.2.1, § 4.2.2, § 4.2.6, § 4.3).
## Узел живёт под Game (секция «СЕТЬ» game.gd) всю жизнь процесса; без сессии молчит.
##
## Вход (D4): клиент строит мир по сиду из рукопожатия (main.gd), затем просит снимок —
##   кадр SNAPSHOT без данных по каналу 2 («ready_for_snapshot»; повтор, если ответа
##   нет REQUEST_RETRY_MS). Хост сначала отдаёт накопленные дельты остальным, потом шлёт
##   Save.encode(Save.gather_join()) по каналу 0 и с этого момента включает клиента в
##   рассылку: дельты идут тем же каналом после снимка — порядок гарантирует ENet.
##   Клиент кладёт снимок Save.apply_join() — без героя и без пересчёта питания.
## Тайлы и вода (D5): World отмечает изменённые клетки (секция «СЕТЬ» world.gd); раз в
##   сетевой такт — каждый TICK_FRAMES-й физический кадр, 20 Гц — хост шлёт TILES и
##   FLUID (NetCodec.encode_cells: u32 = idx << 8 | значение). Вода — через очередь с
##   бюджетом FLUID_CELLS_PER_TICK клеток за такт (§ 4.3, мягкий предел; порядок клеток
##   сохраняется); уровень, вернувшийся к уже отправленному, не шлётся; у клетки, где
##   правили тайл, уровень идёт сразу с тайлом. Вода и оборона считаются только на хосте.
## Глобальное (§ 4.2.6): GLOBAL раз в секунду и в ближайший такт после события
##   (рассвет, этап цели, состояние забега, задание, браун-аут) — Game.net_global() /
##   Game.net_apply_global(): часы клиента подтягиваются, смена и этап — с уведомлением.
## Сверка (§ 4.2.2 п. 5): раз в Net.WORLD_HASH_PERIOD хост кладёт в GLOBAL world_hash()
##   (тайлы и уровни воды) после дельт того же такта и только при пустой очереди воды;
##   у клиента к этому кадру мир тот же — расхождение значит рассинхрон, клиент просит
##   снимок заново.
## Туман: каждый процесс сам открывает круги вокруг всех героев Game.players (свой
##   герой — World._explore_tick, как в одиночной). Сам туман приходит в снимке.
## Угроза: у клиента директор (Threat) на время сессии выключен — фантомов ведёт хост.

## Клиент: снимок применён, герой в мире хоста.
signal joined

## Сетевой такт: каждый 3-й физический кадр (60 / 20 Гц).
const TICK_FRAMES: int = 3
## Клиент: повтор просьбы о снимке, если хост не ответил, мс.
const REQUEST_RETRY_MS: int = 2000
## Больше клеток в одном кадре TILES/FLUID не кладём (u16 n в кодеке — до 65535).
const CELLS_PER_FRAME: int = 16384
## Окно замера пика трафика мира: столько тактов = 1 с.
const WINDOW_TICKS: int = 20
## Бюджет воды (§ 4.3, мягкий предел): не больше стольких клеток за такт — 60 × 4 Б ×
## 20 Гц ≈ 4.9 КБ/с на клиента; остаток ждёт в очереди по порядку. Обрушение озера
## без бюджета — 13 КБ/с (замер mp_world_deltas --mp-fluid-cap=0).
const FLUID_CELLS_PER_TICK: int = 60

# --- хост
## Клиенты, получившие снимок (в рассылке дельт): peer_id → true.
var synced: Dictionary = {}
var snapshots_sent: int = 0
var hash_sent: int = 0
## Замер: Б полезной нагрузки (с байтом типа) TILES + FLUID на одного клиента.
var world_bytes_total: int = 0
## Пик за любое окно в 1 с (WINDOW_TICKS тактов), Б/с.
var world_peak_bps: int = 0
var tiles_tx: int = 0          ## клеток тайлов отправлено (на клиента)
var fluid_tx: int = 0          ## клеток воды отправлено (на клиента)
var fluid_skipped: int = 0     ## уровней воды не отправлено: равны уже отправленному
var fluid_backlog_max: int = 0 ## самая длинная очередь воды, клеток
## Бюджет воды за такт (0 — без бюджета; сценарий меряет и так).
var fluid_cells_per_tick: int = FLUID_CELLS_PER_TICK
var last_gather_ms: float = 0.0

# --- клиент
var is_joined: bool = false
## Подключение (Net.join) → снимок применён (герой управляем), мс; −1 — не входил.
var join_total_ms: int = -1
var snapshots_got: int = 0
var last_apply_ms: float = 0.0
var tiles_rx: int = 0
var fluid_rx: int = 0
var hash_checks: int = 0
var hash_bad: int = 0
var last_host_hash: int = 0
var globals_rx: int = 0

# --- оба
## Размер последнего снимка, Б.
var snapshot_bytes: int = 0

var _frame: int = 0
var _global_t: float = 0.0
var _hash_t: float = 0.0
var _global_dirty: bool = false
var _hash_now: bool = false
var _fluid_sent: PackedByteArray = PackedByteArray()   ## хост: уровни, которые есть у клиентов
var _fl_queue: PackedInt32Array = PackedInt32Array()   ## хост: клетки воды к отправке, по порядку
var _fl_flag: PackedByteArray = PackedByteArray()      ## 1 — клетка уже в очереди
var _win: PackedInt32Array = PackedInt32Array()
var _win_i: int = 0
var _win_sum: int = 0
var _tick_bytes: int = 0
var _want_snapshot: bool = false
var _req_ms: int = 0
var _hero_cells: Dictionary = {}


func _ready() -> void:
	set_physics_process(false)
	Net.session_started.connect(_on_session_started)
	Net.session_ended.connect(_on_session_ended)
	Net.peer_left.connect(_on_peer_left)
	Net.on(NetCodec.Msg.SNAPSHOT, _on_snapshot)
	Net.on(NetCodec.Msg.TILES, _on_tiles)
	Net.on(NetCodec.Msg.FLUID, _on_fluid)
	Net.on(NetCodec.Msg.GLOBAL, _on_global)
	# События глобального состояния — в ближайший такт, а не через секунду.
	Game.day_started.connect(_mark_global.unbind(1))
	Game.objective_changed.connect(_mark_global.unbind(1))
	Game.state_changed.connect(_mark_global.unbind(1))
	Game.task_completed.connect(_mark_global.unbind(2))
	Game.brownout_changed.connect(_mark_global.unbind(1))
	# Сессия могла начаться раньше, чем узел вошёл в дерево.
	if Net.is_online() and Net.session.has("mode"):
		_on_session_started()


# ------------------------------------------------------------------ СЕССИЯ

func _on_session_started() -> void:
	_frame = 0
	_global_t = 0.0
	_hash_t = 0.0
	_hero_cells.clear()
	if Net.is_host():
		synced.clear()
		snapshots_sent = 0
		hash_sent = 0
		reset_traffic()
		World.net_track(true)
		_fluid_sent = World.fluid.duplicate()
		_fl_flag = PackedByteArray()          # flush() заведёт заново
		_fl_queue = PackedInt32Array()
		fluid_cells_per_tick = FLUID_CELLS_PER_TICK
	elif Net.is_client():
		is_joined = false
		join_total_ms = -1
		snapshots_got = 0
		hash_checks = 0
		hash_bad = 0
		tiles_rx = 0
		fluid_rx = 0
		globals_rx = 0
		_want_snapshot = true
		_req_ms = 0
		Threat.set_process(false)
	set_physics_process(true)


func _on_session_ended(_reason: String) -> void:
	World.net_track(false)
	synced.clear()
	is_joined = false
	_want_snapshot = false
	Threat.set_process(true)
	set_physics_process(false)


func _on_peer_left(id: int, _info: Dictionary) -> void:
	synced.erase(id)


func _mark_global() -> void:
	_global_dirty = true


## Хост: в ближайший такт — глобальный пакет со сверкой мира (тесты зовут на барьерах).
func check_now() -> void:
	_hash_now = true


## Хост: обнулить замер трафика мира.
func reset_traffic() -> void:
	world_bytes_total = 0
	world_peak_bps = 0
	tiles_tx = 0
	fluid_tx = 0
	fluid_skipped = 0
	fluid_backlog_max = 0
	_win = PackedInt32Array()
	_win.resize(WINDOW_TICKS)
	_win.fill(0)
	_win_i = 0
	_win_sum = 0
	_tick_bytes = 0


# ------------------------------------------------------------------ ТАКТ

func _physics_process(delta: float) -> void:
	_explore_others()
	if Net.is_host():
		_host_tick(delta)
	elif Net.is_client():
		_client_tick()


func _host_tick(delta: float) -> void:
	_frame += 1
	_global_t += delta
	_hash_t += delta
	if _frame % TICK_FRAMES != 0:
		return
	flush()
	_push_window()
	if synced.is_empty():
		_global_dirty = false
		return
	# Сверка — только когда хвост воды отправлен: иначе клиент законно отстаёт.
	var with_hash: bool = (_hash_now or _hash_t >= Net.WORLD_HASH_PERIOD) and _fl_queue.is_empty()
	if with_hash or _global_dirty or _global_t >= 1.0 / float(Net.GLOBAL_HZ):
		_send_global(with_hash)
		_global_t = 0.0
		_global_dirty = false
		if with_hash:
			_hash_t = 0.0
			_hash_now = false


func _client_tick() -> void:
	if not _want_snapshot:
		return
	var now: int = Time.get_ticks_msec()
	if _req_ms != 0 and now - _req_ms < REQUEST_RETRY_MS:
		return
	# Мир по сиду готов (main.gd строит его в том же кадре, что и вход).
	var p = Game.player
	if p == null or not is_instance_valid(p) or World.tiles.size() != World.W * World.H \
			or World.world_seed != int(Net.session.get("seed", World.world_seed)):
		return
	_req_ms = now
	Net.send_on(2, NetCodec.Msg.SNAPSHOT, PackedByteArray())


## Туман общий: круг открывается и вокруг чужих героев (свой — World._explore_tick).
func _explore_others() -> void:
	if Game.players.is_empty():
		return
	for p in Game.players:
		if p == null or not is_instance_valid(p) or p == Game.player:
			continue
		var c: Vector2i = World.world_to_cell(p.global_position)
		var k: int = p.get_instance_id()
		if _hero_cells.get(k, Vector2i(-9999, -9999)) == c:
			continue
		_hero_cells[k] = c
		World.reveal_around(c, World.explore_radius_at(c))


# ------------------------------------------------------------------ ХОСТ: ДЕЛЬТЫ

## Отдать изменения тайлов и воды всем клиентам в рассылке. Тайлы — все сразу (вместе с
## уровнем воды их клеток: клиент ставит тайл тем же set_tile, а он трогает воду).
## Вода — из очереди по порядку, не больше fluid_cells_per_tick клеток (all — всю).
## Без клиентов — только запомнить «отправленное»: тень уровней равна миру.
func flush(all: bool = false) -> void:
	if not Net.is_host():
		return
	var d: Dictionary = World.net_take_dirty()
	var ti: PackedInt32Array = d["tiles"]
	var n: int = World.fluid.size()
	if _fluid_sent.size() != n:
		_fluid_sent = World.fluid.duplicate()
	if _fl_flag.size() != n:
		_fl_flag.resize(n)
		_fl_flag.fill(0)
		_fl_queue = PackedInt32Array()
	for i in d["fluid"]:
		if _fl_flag[i] == 0:
			_fl_flag[i] = 1
			_fl_queue.append(i)
	if ti.is_empty() and _fl_queue.is_empty():
		return
	var fluid: PackedByteArray = World.fluid
	var fo: PackedInt32Array = PackedInt32Array()
	var fv: PackedByteArray = PackedByteArray()
	var tv: PackedByteArray = PackedByteArray()
	tv.resize(ti.size())
	for k in ti.size():
		var i: int = ti[k]
		tv[k] = World.tiles[i]
		fo.append(i)
		fv.append(fluid[i])
		_fluid_sent[i] = fluid[i]
	var cap: int = fluid_cells_per_tick if not all and fluid_cells_per_tick > 0 and not synced.is_empty() \
			else n
	var taken: int = 0
	var q: int = 0
	while q < _fl_queue.size() and taken < cap:
		var i: int = _fl_queue[q]
		q += 1
		_fl_flag[i] = 0
		var lvl: int = fluid[i]
		if lvl == _fluid_sent[i]:
			fluid_skipped += 1       # за время в очереди вернулся к отправленному
			continue
		_fluid_sent[i] = lvl
		fo.append(i)
		fv.append(lvl)
		taken += 1
	_fl_queue = _fl_queue.slice(q)
	fluid_backlog_max = maxi(fluid_backlog_max, _fl_queue.size())
	if synced.is_empty():
		return
	if not ti.is_empty():
		_send_cells(NetCodec.Msg.TILES, ti, tv)
		tiles_tx += ti.size()
	if not fo.is_empty():
		_send_cells(NetCodec.Msg.FLUID, fo, fv)
		fluid_tx += fo.size()


## Хост: клеток воды ещё ждут отправки (0 — клиенты видят ту же воду).
func fluid_backlog() -> int:
	return _fl_queue.size()


func _send_cells(msg: int, idx: PackedInt32Array, val: PackedByteArray) -> void:
	var n: int = idx.size()
	var start: int = 0
	while start < n:
		var end: int = mini(start + CELLS_PER_FRAME, n)
		var payload: PackedByteArray = NetCodec.encode_cells(idx.slice(start, end), val.slice(start, end))
		for id in synced:
			Net.send(msg, payload, int(id))
		var b: int = payload.size() + 1     # + байт типа кадра
		world_bytes_total += b
		_tick_bytes += b
		start = end


func _push_window() -> void:
	if _win.size() != WINDOW_TICKS:
		reset_traffic()
	_win_sum += _tick_bytes - _win[_win_i]
	_win[_win_i] = _tick_bytes
	_win_i = (_win_i + 1) % WINDOW_TICKS
	_tick_bytes = 0
	world_peak_bps = maxi(world_peak_bps, _win_sum)


func _send_global(with_hash: bool) -> void:
	var g: Dictionary = Game.net_global()
	g["hash"] = world_hash() if with_hash else 0
	if with_hash:
		hash_sent += 1
	var payload: PackedByteArray = NetCodec.encode_global(g)
	for id in synced:
		Net.send(NetCodec.Msg.GLOBAL, payload, int(id))


# ------------------------------------------------------------------ СНИМОК

func _on_snapshot(sender: int, payload: PackedByteArray) -> void:
	if Net.is_host():
		if sender != 1 and Net.peers.has(sender):
			send_snapshot(sender)
	elif Net.is_client() and sender == 1:
		_apply_snapshot(payload)


## Хост: снимок мира клиенту. Сначала дельты остальным — после этого тень воды равна
## миру, и новый клиент встаёт в рассылку с тем же состоянием, что у всех.
func send_snapshot(peer: int) -> void:
	flush(true)
	var t0: int = Time.get_ticks_usec()
	var bytes: PackedByteArray = Save.encode(Save.gather_join())
	last_gather_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	snapshot_bytes = bytes.size()
	Net.send(NetCodec.Msg.SNAPSHOT, bytes, peer)
	_fluid_sent = World.fluid.duplicate()
	synced[peer] = true
	snapshots_sent += 1
	_global_dirty = true
	print("СЕТЬ: снимок пиру %d: %d Б (сырые %d Б), сборка %.1f мс" % [peer, bytes.size(),
			Save.last_raw_size, last_gather_ms])


func _apply_snapshot(payload: PackedByteArray) -> void:
	var t0: int = Time.get_ticks_usec()
	var d: Dictionary = Save.decode(payload)
	if d.is_empty() or not Save.apply_join(d):
		push_warning("СЕТЬ: снимок не применён: %s" % Save.last_error)
		_want_snapshot = true
		_req_ms = Time.get_ticks_msec()
		return
	last_apply_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	snapshot_bytes = payload.size()
	snapshots_got += 1
	_want_snapshot = false
	if is_joined:
		print("СЕТЬ: снимок заново: %d Б, %.1f мс" % [payload.size(), last_apply_ms])
		return
	is_joined = true
	# От Net.join() (Net._join_t0): рукопожатие, мир по сиду (main.gd строит его в
	# обработчике session_started — раньше или позже нашего), просьба и снимок.
	join_total_ms = Time.get_ticks_msec() - int(Net._join_t0)
	print("СЕТЬ: мир хоста получен: снимок %d Б, применён за %.1f мс; вход %d мс" % [
			payload.size(), last_apply_ms, join_total_ms])
	joined.emit()


## Просить снимок заново (расхождение сверки).
func request_snapshot() -> void:
	if Net.is_client():
		_want_snapshot = true
		_req_ms = 0


# ------------------------------------------------------------------ КЛИЕНТ: ДЕЛЬТЫ

func _on_tiles(sender: int, payload: PackedByteArray) -> void:
	if not Net.is_client() or sender != 1 or not is_joined:
		return
	var d: Dictionary = NetCodec.decode_cells(payload)
	if d.is_empty():
		return
	World.net_apply_tiles(d["idx"], d["val"])
	tiles_rx += (d["idx"] as PackedInt32Array).size()


func _on_fluid(sender: int, payload: PackedByteArray) -> void:
	if not Net.is_client() or sender != 1 or not is_joined:
		return
	var d: Dictionary = NetCodec.decode_cells(payload)
	if d.is_empty():
		return
	World.net_apply_fluid(d["idx"], d["val"])
	fluid_rx += (d["idx"] as PackedInt32Array).size()


func _on_global(sender: int, payload: PackedByteArray) -> void:
	if not Net.is_client() or sender != 1 or not is_joined:
		return
	var d: Dictionary = NetCodec.decode_global(payload)
	if d.is_empty():
		return
	globals_rx += 1
	Game.net_apply_global(d)
	var h: int = int(d["hash"])
	if h == 0 or _want_snapshot:
		return
	hash_checks += 1
	last_host_hash = h
	if world_hash() != h:
		hash_bad += 1
		print("СЕТЬ: мир разошёлся с хостом (сверка %08x ≠ %08x) — снимок заново" % [world_hash(), h])
		request_snapshot()


# ------------------------------------------------------------------ СВЕРКА

## Хэш мира для сверки: тайлы и уровни воды (u32, не 0 — 0 в GLOBAL значит «без сверки»).
static func world_hash() -> int:
	var h: int = (hash(World.tiles) ^ (hash(World.fluid) * 16777619)) & 0xFFFFFFFF
	return h if h != 0 else 1


static func tiles_hash() -> int:
	return hash(World.tiles) & 0xFFFFFFFF


static func fluid_hash() -> int:
	return hash(World.fluid) & 0xFFFFFFFF


## Хэш построек: клетка и тип каждой машины (состояние машин по сети — MP-E).
static func machines_hash() -> int:
	var list: Array = []
	for c in World.machines.keys():
		var m = World.machines[c]
		if is_instance_valid(m) and not m.is_queued_for_deletion():
			list.append([c.y * World.W + c.x, String(m.get("kind"))])
	list.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
	return hash(list) & 0xFFFFFFFF
