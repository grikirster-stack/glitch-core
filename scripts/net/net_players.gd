class_name NetPlayers
extends Node
## Игроки по сети (ADR-002 § 4.2.3, § 4.4, D3, D6; MP-D, #89).
##
## Роли героев (Player.NetRole):
##   LOCAL  — одиночная игра и свой герой хоста: всё как раньше;
##   PROXY  — чужой герой на хосте: движение не интегрирует (позиция из пакета ввода
##            после проверки), действия — обычным кодом Player через шов test_input;
##   OWNER  — свой герой клиента: движется сам (World.move_body по своим тайлам),
##            действия уходят хосту пакетом ввода, HP и флаги — с хоста (OWN);
##   PUPPET — чужой герой у клиента: рисуется на Net.INTERP_DELAY в прошлом.
##
## Хост: ввод клиента (канал 3, 30 Гц) → test_input прокси; каждый 3-й физический кадр
## (20 Гц) — пакет состояния всем (канал 1) и личное OWN каждому владельцу; инвентарь
## прокси — владельцу при изменении (канал 2). Позиция проверяется:
## |Δ| ≤ (SPRINT_SPEED + MAX_FALL)·dt·1.5 + 8 px и тело не в сплошной клетке; иначе —
## жёсткая поправка. Хост сам двигает прокси (возрождение, телепорт) — тоже поправка.
## Поправка несёт эпоху (2 бита): клиент повторяет её в пакете ввода, и только тогда
## хост снова верит его позициям — отправленные до телепорта пакеты не мешают.
##
## Клиент: пакет ввода собирается из шва Player (_key, _mouse_down, _mouse_pos) —
## клавиатура, сценарий и сенсорное управление (#81) идут одной дорогой; нажатия
## E/Q/V/G — счётчиками по 4 бита (фронт не теряется при потере пакета).
##
## Обратная связь героев (звук, личные уведомления, FX, удар) — обёртки Player
## (_sfx_here, _notify, _fx, _feedback_hit) → статические send_* отсюда → событие EVENT;
## принимает UI.net_event.
##
## «Без связи» (§ 4.4): ввода от клиента нет дольше LINK_LOST — прокси стоит (ввод
## сброшен), урона не получает и целью не служит (Player.net_targetable). У клиента
## пакетов состояния нет дольше Net.LINK_WARN — уведомление; марионетки
## экстраполируются не дальше Net.EXTRAP_MAX и стоят.

const LINK_LOST: float = 1.0          ## ввода нет дольше — прокси «без связи», с
const POS_FACTOR: float = 1.5         ## запас проверки позиции по скорости (§ 4.2.3)
const POS_SLACK: float = 8.0          ## постоянный запас проверки позиции, px
const SNAP_DIST: float = 96.0         ## скачок между пакетами марионетки — телепорт, без интерполяции
const BUF_SEC: float = 1.0            ## сколько секунд состояний держит марионетка
const STATE_EVERY: int = 3            ## физических кадров на пакет состояния (60 / 20 Гц)
const INPUT_EVERY: int = 2            ## физических кадров на пакет ввода (60 / 30 Гц)
const INV_REPEAT: int = 40            ## неизменный инвентарь повторяется раз в столько тактов (2 с)

## Сцена main.gd (герой, end_screen).
var main: Node = null
## peer_id → Player: прокси у хоста, марионетки у клиента.
var heroes: Dictionary = {}
## Замеры и проверки сценариев: хост — по прокси (rx, rej, corr, err); клиент — tx, rx.
var stats: Dictionary = {}

var _active: bool = false
var _frame: int = 0
## Хост: peer_id → состояние ввода прокси.
var _st: Dictionary = {}
## Клиент: свой ввод.
var _seq: int = 0
var _presses: int = 0
var _down_prev: Dictionary = {}
## Клиент: тест «без связи» — не слать ввод (сценарий mp_move).
var mute_input: bool = false
## Клиент: часы хоста. Растянутый номер такта, время хоста последнего пакета
## состояния и местное время его приёма, с.
var _ext_tick: int = -1
var _last_t: float = 0.0
var _last_rx: float = 0.0
var _rt_ok: bool = false
var _last_state_ms: int = 0
var _link_warned: bool = false
## Клиент: время, в котором рисуются марионетки (часы хоста, с) — для замера mp_move.
var render_time: float = 0.0
## Клиент: peer_id → Array[{t, pos, vel, row}] — буфер интерполяции.
var _buf: Dictionary = {}
## Фантомы по сети (MP-F, #92): строки пакета состояния, марионетки у клиента.
var phantoms: NetPhantoms = null


func start(p_main: Node) -> void:
	main = p_main
	phantoms = NetPhantoms.new()   # MP-F (#92): фантомы по сети
	phantoms.name = "NetPhantoms"
	add_child(phantoms)
	phantoms.start(self)
	process_physics_priority = -10   # раньше героев: прокси получают ввод в этом же кадре
	Net.session_started.connect(_begin)
	Net.session_ended.connect(_end)
	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)
	if Net.is_online():
		_begin()


func _begin() -> void:
	if _active:
		return
	_active = true
	_frame = 0
	_st.clear()
	_buf.clear()
	stats = {"tx": 0, "rx_state": 0, "rx_own": 0}
	_seq = 0
	_presses = 0
	_down_prev.clear()
	_ext_tick = -1
	_rt_ok = false
	process_priority = -10
	_last_state_ms = Time.get_ticks_msec()
	_link_warned = false
	Net.on(NetCodec.Msg.INPUT, _on_input)
	Net.on(NetCodec.Msg.STATE, _on_state)
	Net.on(NetCodec.Msg.OWN, _on_own)
	Net.on(NetCodec.Msg.INV, _on_inv)
	Net.on(NetCodec.Msg.EVENT, UI.net_event)
	var own: Player = _own()
	if own != null:
		own.peer_id = Net.my_id()
		own.nick = String(Net.session.get("nick", Net.local_profile.get("nick", "")))
		own.net_epoch = 0
	for id in Net.peers:
		_on_peer_joined(int(id), Net.peers[id])


func _end(_reason: String = "") -> void:
	for id in heroes.keys():
		_remove(int(id))
	_active = false


func _own() -> Player:
	return main.get("player") as Player if main != null else null


## Часы хоста, с: физические кадры сессии (такт состояния k — время k / TICK_HZ).
func host_time() -> float:
	return float(_frame) / float(Engine.physics_ticks_per_second)


# ------------------------------------------------------------------ ГЕРОИ

func _on_peer_joined(id: int, info: Dictionary) -> void:
	if not _active or id == Net.my_id():
		return
	if heroes.has(id):
		var h: Player = heroes[id]
		h.nick = String(info.get("nick", h.nick))
		h.look = int(info.get("look", h.look)) & 0xFFFF
		return
	var p: Player = Player.new()
	p.net_role = Player.NetRole.PROXY if Net.is_host() else Player.NetRole.PUPPET
	p.peer_id = id
	p.look = int(info.get("look", 0)) & 0xFFFF
	p.nick = String(info.get("nick", ""))
	main.add_child(p)
	p.global_position = World.spawn_point
	p.add_child(NickTag.new())
	heroes[id] = p
	if Net.is_host():
		main.give_starter_kit(p)
		p.died.connect(_on_proxy_died.bind(p))
		_st[id] = {"seq": -1, "keys": 0, "presses": 0, "mouse": p.global_position,
			"last_ms": Time.get_ticks_msec(), "epoch": 0, "corr": false,
			"applied": p.global_position, "inv_sum": -1, "pulse": {},
			"rx": 0, "rej": 0, "corr_n": 0, "err": PackedFloat32Array()}
	else:
		_buf[id] = []
	Game.players.append(p)
	Game.player_joined.emit(p)


func _on_peer_left(id: int, info: Dictionary) -> void:
	if not heroes.has(id):
		return
	_remove(id)
	Game.notify("%s покидает экспедицию." % String(info.get("nick", "Игрок")), Color(0.8, 0.8, 0.85))


func _remove(id: int) -> void:
	var p: Player = heroes.get(id)
	heroes.erase(id)
	_st.erase(id)
	_buf.erase(id)
	if p == null or not is_instance_valid(p):
		return
	Game.players.erase(p)
	Game.player_left.emit(p)
	p.get_parent().remove_child(p)
	p.queue_free()


## Смерть прокси (хост): мешок уже выпал (Player._die); респаун, вайп и зритель
## --hardcore — NetCoop (scripts/net/net_coop.gd, MP-I #94).
func _on_proxy_died(p: Player) -> void:
	var coop: NetCoop = main.get("net_coop") as NetCoop if main != null else null
	if coop != null:
		coop.on_hero_died(p)


# ------------------------------------------------------------------ КАДР

func _physics_process(_delta: float) -> void:
	if not _active:
		return
	_frame += 1
	if Net.is_host():
		_host_tick()
	elif Net.is_client():
		_client_tick()


# ------------------------------------------------------------------ ХОСТ

func _host_tick() -> void:
	var now: int = Time.get_ticks_msec()
	for id in _st:
		var p: Player = heroes[id]
		var st: Dictionary = _st[id]
		var linked: bool = now - int(st["last_ms"]) <= int(LINK_LOST * 1000.0)
		if linked != p.net_linked:
			p.net_linked = linked
			if not linked:
				st["pulse"] = {}
		_apply_input(p, st)
		# Хост сам переставил прокси (возрождение, телепорт): поправка владельцу.
		if p.global_position.distance_to(st["applied"]) > 0.5:
			_correct(p, st)
	if _frame % STATE_EVERY == 0 and not _st.is_empty():
		_send_state()
		for id in _st:
			_send_own(int(id))
			_send_inv(int(id))


## Ввод владельца → шов test_input прокси. Нажатия, пропавшие между пакетами, —
## импульсом на один кадр. Цифры хотбара — всегда «отпущены» (слот — из пакета).
## Десять бит клавиш 0–9 остаются в пакете (#161): формат не меняется, PROTO не растёт.
## Ячейки за hotbar_size хост не выбирает — лишние нажатия просто не доходят до слота.
func _apply_input(p: Player, st: Dictionary) -> void:
	var mask: int = int(st["keys"]) if p.net_linked else 0
	var inp: Dictionary = NetCodec.mask_to_input(mask)
	var keys: Dictionary = inp["keys"]
	for i in 10:
		keys[KEY_0 + i] = false
	var pulse: Dictionary = st["pulse"]
	for code in pulse.keys():
		var seq: Array = pulse[code]
		if seq.is_empty():
			pulse.erase(code)
			continue
		keys[code] = bool(seq.pop_front())
	p.net_window_open = p.net_linked and (mask & (1 << NetCodec.BIT_WINDOW)) != 0
	p.test_input = {"keys": keys, "mouse": st["mouse"], "mouse_buttons": inp["mouse_buttons"]}


func _on_input(sender: int, payload: PackedByteArray) -> void:
	var p: Player = heroes.get(sender)
	if p == null or not _st.has(sender):
		return
	var st: Dictionary = _st[sender]
	var d: Dictionary = NetCodec.decode_input(payload)
	if d.is_empty():
		return
	var steps: int = 1
	if int(st["seq"]) >= 0:
		steps = ((int(d["seq"]) - int(st["seq"]) + 0x8000) & 0xFFFF) - 0x8000
		if steps <= 0:
			return               # устаревший пакет
		_presses_to_pulses(st, int(d["presses"]))
	st["seq"] = int(d["seq"])
	st["keys"] = int(d["keys"])
	st["presses"] = int(d["presses"])
	st["mouse"] = d["mouse"]
	st["last_ms"] = Time.get_ticks_msec()
	st["rx"] = int(st["rx"]) + 1
	p.inv.selected = clampi(int(d["slot"]), 0, p.inv.hotbar_size - 1)
	var flags: int = int(d["flags"])
	if p.dead:
		return                   # мёртвый стоит, позиция владельца не важна
	var pos: Vector2 = d["pos"]
	if ((flags >> NetCodec.IF_EPOCH_SHIFT) & 3) == int(st["epoch"]):
		st["corr"] = false       # поправка принята; пакеты до неё (другая эпоха) не верим
		var dt: float = clampf(float(steps) / float(Net.INPUT_HZ), 1.0 / float(Net.INPUT_HZ), 1.0)
		if position_ok(p.global_position, pos, dt):
			p.global_position = pos
			p.vel = d["vel"]
			p.facing = -1 if (flags & NetCodec.IF_FACING_LEFT) != 0 else 1
			p.on_ground = (flags & NetCodec.IF_ON_GROUND) != 0
			st["applied"] = pos
		else:
			st["rej"] = int(st["rej"]) + 1
			_correct(p, st)
	# Расхождение «хост ↔ владелец» на этом пакете (замер mp_move).
	var err: PackedFloat32Array = st["err"]   # Packed* в словаре — копия: кладём обратно
	err.append(p.global_position.distance_to(pos))
	st["err"] = err


## Правдоподобие позиции владельца (§ 4.2.3): скорость и не в стене.
static func position_ok(from: Vector2, to: Vector2, dt: float) -> bool:
	var limit: float = (Player.SPRINT_SPEED + Player.MAX_FALL) * dt * POS_FACTOR + POS_SLACK
	if from.distance_to(to) > limit:
		return false
	return not World.rect_solid(Rect2(to - Player.SIZE * 0.5, Player.SIZE))


## Счётчики нажатий E/Q/V/G: каждое новое нажатие — хотя бы один кадр «нажата» у
## прокси, даже если пакет с зажатой клавишей затёрт следующим в том же кадре или
## нажали и отпустили между пакетами. Была зажата и в прошлом пакете — сначала кадр
## «отпущена» (фронт для V и E).
func _presses_to_pulses(st: Dictionary, presses: int) -> void:
	var old_keys: int = int(st["keys"])
	var old: int = int(st["presses"])
	for i in NetCodec.PRESS_KEYS.size():
		if NetCodec.presses_get(presses, i) == NetCodec.presses_get(old, i):
			continue
		var code: int = int(NetCodec.PRESS_KEYS[i])
		var was: bool = (old_keys & (1 << NetCodec.key_bit(code))) != 0
		st["pulse"][code] = [false, true] if was else [true]


## Жёсткая поправка: владелец встаёт туда, где прокси на хосте.
func _correct(p: Player, st: Dictionary) -> void:
	st["epoch"] = (int(st["epoch"]) + 1) & 3
	st["corr"] = true
	st["corr_n"] = int(st["corr_n"]) + 1
	st["applied"] = p.global_position
	p.vel = Vector2.ZERO


func _send_state() -> void:
	var rows: Array = []
	var own: Player = _own()
	if own != null:
		rows.append(own.net_state_row(_slot_of(Net.my_id())))
	for id in heroes:
		rows.append((heroes[id] as Player).net_state_row(_slot_of(int(id))))
	var tick: int = (_frame / STATE_EVERY) & 0xFFFF
	# MP-F (#92): пакет — каждому клиенту свой, фантомы — в зоне интереса его героя.
	# Предметы MP-E (#90) идут своими SPAWN-обновлениями, строки предметов пусты.
	phantoms.host_sync()
	for id in _st:
		Net.send(NetCodec.Msg.STATE, NetCodec.encode_state(tick, rows, phantoms.rows_for(heroes[id]), []), int(id))


func _send_own(id: int) -> void:
	var p: Player = heroes[id]
	var st: Dictionary = _st[id]
	var d: Dictionary = p.net_own(maxi(int(st["seq"]), 0), int(st["epoch"]), bool(st["corr"]))
	Net.send(NetCodec.Msg.OWN, NetCodec.encode_own(d), id)


## Инвентарь прокси — владельцу при изменении (полный, 36 слотов). Команды
## клиента (перекладывание, крафт, сундуки) — слой InvOps MP-G (#91).
func _send_inv(id: int) -> void:
	var p: Player = heroes[id]
	var st: Dictionary = _st[id]
	var slots: Array = []
	for s in p.inv.slots:
		slots.append([s.id, s.count])
	var seen: Array = p.inv.seen_items.keys()
	var sum: int = hash([slots, seen])
	var t: int = int(st.get("inv_t", 0)) + 1
	# Без изменений — повтор раз в INV_REPEAT тактов (клиент мог ещё строить мир).
	if sum == int(st["inv_sum"]) and t < INV_REPEAT:
		st["inv_t"] = t
		return
	st["inv_t"] = 0
	st["inv_sum"] = sum
	Net.send(NetCodec.Msg.INV, NetCodec.encode_inv(slots, p.inv.selected, seen), id)


func _slot_of(id: int) -> int:
	return int(Net.peers.get(id, {}).get("slot", 0))


func _peer_of_slot(slot: int) -> int:
	for id in Net.peers:
		if int(Net.peers[id].get("slot", -1)) == slot:
			return int(id)
	return -1


# ------------------------------------------------------------------ КЛИЕНТ

func _client_tick() -> void:
	var own: Player = _own()
	if own == null:
		return
	var s: Dictionary = own.net_input_sample()
	var keys: Dictionary = s["keys"]
	for i in NetCodec.PRESS_KEYS.size():
		var code: int = int(NetCodec.PRESS_KEYS[i])
		var down: bool = bool(keys.get(code, false))
		if down and not bool(_down_prev.get(code, false)):
			_presses = NetCodec.presses_bump(_presses, i)
		_down_prev[code] = down
	if _frame % INPUT_EVERY == 0 and not mute_input:
		var flags: int = (own.net_epoch & 3) << NetCodec.IF_EPOCH_SHIFT
		if own.facing < 0:
			flags |= NetCodec.IF_FACING_LEFT
		if own.on_ground:
			flags |= NetCodec.IF_ON_GROUND
		Net.send(NetCodec.Msg.INPUT, NetCodec.encode_input({"seq": _seq,
			"keys": NetCodec.keys_mask(keys, s["buttons"], UI.blocking()), "mouse": s["mouse"],
			"slot": own.inv.selected, "presses": _presses, "pos": own.global_position,
			"vel": own.vel, "flags": flags}))
		_seq = (_seq + 1) & 0xFFFF
		stats["tx"] = int(stats.get("tx", 0)) + 1
	if not _link_warned and Time.get_ticks_msec() - _last_state_ms > int(Net.LINK_WARN * 1000.0):
		_link_warned = true
		Game.notify("Связь с хостом прерывается…", Color(1.0, 0.7, 0.4))


## Марионетки — в кадре отрисовки (после приёма пакетов этого кадра), на
## INTERP_DELAY в прошлом по часам хоста. Часы рисования идут местным временем и
## плавно подтягиваются к «последний пакет + сколько прошло с его приёма − задержка»;
## скачок больше RT_SNAP (подвисание, смена хоста) — сразу.
const RT_SNAP: float = 0.3
const RT_PULL: float = 5.0            ## скорость подтяжки часов рисования, 1/с


func _process(delta: float) -> void:
	if not _active or not Net.is_client() or _ext_tick < 0:
		return
	var target: float = _last_t + (_now() - _last_rx) - Net.INTERP_DELAY
	if not _rt_ok or absf(target - render_time) > RT_SNAP:
		render_time = target
		_rt_ok = true
	else:
		render_time += delta
		render_time += (target - render_time) * minf(1.0, delta * RT_PULL)
	for id in heroes:
		_interp(heroes[id], _buf.get(id, []), render_time)


static func _now() -> float:
	return float(Time.get_ticks_usec()) / 1000000.0


func _on_state(sender: int, payload: PackedByteArray) -> void:
	if sender != 1:
		return
	var d: Dictionary = NetCodec.decode_state(payload)
	if d.is_empty():
		return
	var tick: int = int(d["tick"])
	if _ext_tick < 0:
		_ext_tick = tick
	else:
		var step: int = ((tick - (_ext_tick & 0xFFFF) + 0x8000) & 0xFFFF) - 0x8000
		if step <= 0:
			return
		_ext_tick += step
	var t: float = float(_ext_tick) / float(Net.TICK_HZ)
	_last_t = t
	_last_rx = _now()
	_last_state_ms = Time.get_ticks_msec()
	_link_warned = false
	stats["rx_state"] = int(stats.get("rx_state", 0)) + 1
	phantoms.on_state(t, d["phantoms"])   # MP-F (#92)
	var me: int = Net.my_id()
	for row in d["players"]:
		var peer: int = _peer_of_slot(int(row["slot"]))
		if peer == me:
			var own: Player = _own()
			if own != null:
				own.net_apply_own_row(row)
		elif _buf.has(peer):
			var b: Array = _buf[peer]
			b.append({"t": t, "pos": row["pos"], "vel": row["vel"], "row": row})
			while b.size() > 2 and float(b[0]["t"]) < t - BUF_SEC:
				b.pop_front()


## Интерполяция марионетки между пакетами; за последним — экстраполяция не дальше
## EXTRAP_MAX; скачок дальше SNAP_DIST (возрождение) — без интерполяции.
func _interp(p: Player, b: Array, rt: float) -> void:
	if b.is_empty():
		return
	var pos: Vector2
	var vel: Vector2
	var row: Dictionary
	var last: Dictionary = b[b.size() - 1]
	if rt >= float(last["t"]):
		var ex: float = minf(rt - float(last["t"]), Net.EXTRAP_MAX)
		vel = last["vel"]
		if (int(last["row"]["flags"]) & NetCodec.PF_ON_GROUND) != 0:
			vel.y = 0.0
		pos = last["pos"] + vel * ex
		if rt - float(last["t"]) > Net.EXTRAP_MAX:
			vel = Vector2.ZERO
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
	p.net_apply_puppet(pos, vel, row)


func _on_own(sender: int, payload: PackedByteArray) -> void:
	var own: Player = _own()
	if sender != 1 or own == null:
		return
	var d: Dictionary = NetCodec.decode_own(payload)
	if d.is_empty():
		return
	stats["rx_own"] = int(stats.get("rx_own", 0)) + 1
	own.net_apply_own(d)


## Инвентарь своего героя с хоста. Выбранный слот — свой (его шлёт пакет ввода).
func _on_inv(sender: int, payload: PackedByteArray) -> void:
	var own: Player = _own()
	if sender != 1 or own == null:
		return
	var d: Dictionary = NetCodec.decode_inv(payload)
	if d.is_empty():
		return
	var slots: Array = d["slots"]
	for i in mini(slots.size(), own.inv.size):
		var e: Array = slots[i]
		own.inv.slots[i] = ItemStack.new(int(e[0]), int(e[1])) if int(e[1]) > 0 else ItemStack.new()
	# Хвост seen (#171): потраченное тоже открывает рецепт. Слоты не помечаем
	# сами — иначе пустой подбор на клиенте открыл бы строку без сигнала хоста.
	for sid in d.get("seen", []):
		own.inv.mark_seen(int(sid))
	own.inv.changed.emit()
	own.stats_changed.emit()


# ------------------------------------------------------------------ ОБРАТНАЯ СВЯЗЬ
## Отправители событий (хост). Их зовут обёртки Player; принимает UI.net_event.

## Звук в точке — всем клиентам (канал 0).
static func send_sound(pos: Vector2, id: String, volume_db: float, pitch: float) -> void:
	var sid: int = NetCodec.sound_id(id)
	if sid >= 0:
		Net.send(NetCodec.Msg.EVENT, NetCodec.encode_sound(pos, sid, volume_db, pitch))


## Личное уведомление — только владельцу (канал 2). icon — предмет в кадре (#171).
static func send_notify(peer: int, pos: Vector2, text: String, color: Color, icon: int = 0) -> void:
	Net.send_on(2, NetCodec.Msg.EVENT, NetCodec.encode_notify(pos, text, color, icon), peer)


## Эффект в мире — всем клиентам (канал 0).
static func send_fx(kind: int, pos: Vector2, arg: int) -> void:
	Net.send(NetCodec.Msg.EVENT, NetCodec.encode_fx(pos, kind, arg))


## Удар по герою — владельцу (канал 2): отбрасывание, оглушение, вспышка.
static func send_hit(peer: int, pos: Vector2, knock: Vector2, stun: float) -> void:
	Net.send_on(2, NetCodec.Msg.EVENT, NetCodec.encode_hit(pos, knock, stun), peer)


## Нарисовать эффект в мире (и у своего героя, и по событию с хоста).
static func play_fx(kind: int, pos: Vector2, arg: int) -> void:
	match kind:
		NetCodec.Fx.CHIP_TILE:
			UI.spawn_chip(World.world_to_cell(pos), DB.tile_color(arg))
		NetCodec.Fx.CHIP_REPAIR:
			UI.spawn_chip(World.world_to_cell(pos), Color(0.75, 0.7, 0.6))
		NetCodec.Fx.RING_EMP:
			UI.flash_ring(pos, Color(0.4, 0.9, 1.0))
		NetCodec.Fx.SLASH:
			UI.spawn_slash(pos)


# ------------------------------------------------------------------ НИК НАД ГОЛОВОЙ

## Ник товарища над головой (§ 4.2.3): шрифт ThemeDB.fallback_font 8 px, светлый тон
## скафандра. Отдельный узел-ребёнок: рисунок героя (Avatar, MP-B/MP-L) не тронут.
## Родитель — герой или двойник в маске товарища (MP-J, #95): узел читает его поля
## nick и look (у Player и у Phantom они одни и те же), мёртвого не подписывает.
class NickTag extends Node2D:
	const FONT_SIZE: int = 8
	const LIFT: float = 9.0

	var _shown: String = ""

	func _ready() -> void:
		z_index = 1

	## Текст над головой: "" — не подписывать (нет ника, погиб, рассеян).
	func text() -> String:
		var p: Node = get_parent()
		if p == null or p.get("dead") == true or p.get("alive") == false:
			return ""
		return String(p.get("nick"))

	func _process(_delta: float) -> void:
		var p: Node = get_parent()
		var n: String = text()
		var key: String = "" if n == "" else n + "|%d" % int(p.get("look"))
		if key != _shown:
			_shown = key
			queue_redraw()

	func _draw() -> void:
		var n: String = text()
		if n == "":
			return
		var font: Font = ThemeDB.fallback_font
		var w: float = font.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		var y: float = -Player.SIZE.y * 0.5 - LIFT
		draw_string(font, Vector2(-w * 0.5 + 0.5, y + 0.5), n, HORIZONTAL_ALIGNMENT_LEFT, -1,
				FONT_SIZE, Color(0, 0, 0, 0.6))
		draw_string(font, Vector2(-w * 0.5, y), n, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE,
				Avatar.suit_color(int(get_parent().get("look"))).lightened(0.55))
