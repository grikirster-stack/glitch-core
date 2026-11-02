class_name NetCodec
extends RefCounted
## Кодек сетевых сообщений (ADR-002, § 9.3; D2): упакованные PackedByteArray вместо
## var_to_bytes(Dictionary) — фантом 12 Б против ≈ 190, игрок 18 Б против ≈ 250.
##
## Сообщение на проводе — кадр: первый байт — тип (Msg), дальше полезная нагрузка.
## Кадры ходят через четыре RPC автозагрузки Net (каналы 0–3, § 4.1).
## Числа — little-endian. Позиции в мире — u16 в четвертях пикселя (POS_SCALE):
## мир 10240×2880 px помещается с запасом (40960 < 65535).
##
## Любая смена раскладки, порядка Msg или KEY_BITS меняет schema_sample() —
## tools/net_test.gd сверяет её хэш и требует поднять Net.PROTO.
##
## Скрипт не ссылается на автозагрузки по имени: он грузится и в режиме --script
## (net_test), где их имена при компиляции недоступны.

## Типы сообщений. Только дописывать в конец (иначе — поднять Net.PROTO).
enum Msg {
	NONE,
	ROSTER,        ## 0: список игроков сессии (хост → все)
	SNAPSHOT,      ## 0: Save.encode(gather_join()) — MP-C
	TILES,         ## 0: батч тайлов
	FLUID,         ## 0: батч уровней воды
	MACHINE_ADD,   ## 0: var_to_bytes(save_state()) машины
	MACHINE_DEL,   ## 0: u32 клетка
	MACHINES,      ## 0: net_state() изменённых машин
	SPAWN,         ## 0: появление сущности
	DESPAWN,       ## 0: исчезновение сущности
	STATE,         ## 1: пакет состояния 20 Гц
	OWN,           ## 1: личное состояние героя владельцу
	INPUT,         ## 3: ввод и позиция клиента 30 Гц
	GLOBAL,        ## 0: время, угроза, цель 1 Гц
	EVENT,         ## 0 / 2: звук, FX, уведомление
	INV,           ## 2: инвентарь владельцу
	CMD,           ## 2: команда клиента (InvOps, MP-G)
	CMD_RESULT,    ## 2: ответ на команду
	BARRIER,       ## 2: харнесс mp_*: клиент дошёл до точки синхронизации
	BARRIER_PASS,  ## 2: харнесс mp_*: все дошли
	CHEST,         ## 2: открытый сундук — тем, у кого он открыт (MP-G, #91)
	TECH,          ## 0: исследования, главы, обрывки — всем (MP-G, #91)
}

## Типы событий EVENT. Только дописывать в конец.
enum Ev { NONE, SOUND, NOTIFY, FX, HIT }

## Позиция в мире: px · POS_SCALE → u16.
const POS_SCALE: float = 4.0
## Размер мира, px (World.W · World.TILE, World.H · World.TILE) — net_test сверяет.
const WORLD_PX: Vector2 = Vector2(10240.0, 2880.0)
## «Клетки нет» (копка не идёт) в 24-битном индексе клетки.
const NO_CELL: int = 0xFFFFFF
## Ширина мира в клетках: индекс клетки = y · WORLD_W_CELLS + x.
const WORLD_W_CELLS: int = 640

const PLAYER_BYTES: int = 18
const PHANTOM_BYTES: int = 12
const ITEM_BYTES: int = 8
const INPUT_BYTES: int = 26
const OWN_BYTES: int = 6        ## без поправки позиции; с поправкой — 10
const HELLO_MAX: int = 512      ## рукопожатие длиннее — мусор
const NICK_MAX_BYTES: int = 64  ## 16 символов UTF-8 с запасом

## Биты клавиш пакета ввода (§ 4.2.3). Дописывать только в конец.
const KEY_BITS: Array = [KEY_A, KEY_D, KEY_LEFT, KEY_RIGHT, KEY_W, KEY_UP, KEY_SPACE,
		KEY_SHIFT, KEY_E, KEY_Q, KEY_V, KEY_G]
const BIT_LMB: int = 12
const BIT_RMB: int = 13
const BIT_WINDOW: int = 14      ## у клиента открыто окно (инвентарь, журнал)

## Флаги игрока в STATE.
const PF_FACING_LEFT: int = 1
const PF_ON_GROUND: int = 2
const PF_HIDING: int = 4
const PF_DEAD: int = 8
const PF_SPRINT: int = 16
const PF_STUN: int = 32
const PF_HIT: int = 64
const PF_ROLLCALL: int = 128

## Флаги OWN.
const OF_HIDING: int = 1
const OF_DEAD: int = 2
const OF_STUN: int = 4
const OF_INVULN: int = 8
const OF_CORRECTION: int = 16   ## за флагами следует поправка позиции 2×u16


# ------------------------------------------------------------------ КАДР

## Кадр: тип + полезная нагрузка.
static func frame(msg: int, payload: PackedByteArray) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray([msg & 0xFF])
	out.append_array(payload)
	return out


## Тип кадра (Msg.NONE у пустого).
static func frame_type(data: PackedByteArray) -> int:
	return int(data[0]) if data.size() > 0 else Msg.NONE


## Полезная нагрузка кадра.
static func frame_payload(data: PackedByteArray) -> PackedByteArray:
	return data.slice(1) if data.size() > 1 else PackedByteArray()


# ------------------------------------------------------------------ РУКОПОЖАТИЕ (auth)
## hello: {proto, build, uid, nick, look}; welcome: {ok, reason, seed, slot,
## session_name, nick}. Словари простых типов — var_to_bytes без объектов.

const HELLO_FIELDS: Dictionary = {"proto": TYPE_INT, "build": TYPE_STRING, "uid": TYPE_INT,
		"nick": TYPE_STRING, "look": TYPE_INT}
const WELCOME_FIELDS: Dictionary = {"ok": TYPE_BOOL, "reason": TYPE_STRING, "seed": TYPE_INT,
		"slot": TYPE_INT, "session_name": TYPE_STRING, "nick": TYPE_STRING}


static func encode_hello(d: Dictionary) -> PackedByteArray:
	return var_to_bytes(_pick(d, HELLO_FIELDS))


## {} — если байты не hello (размер, тип, поля).
static func decode_hello(b: PackedByteArray) -> Dictionary:
	return _unpick(b, HELLO_FIELDS)


static func encode_welcome(d: Dictionary) -> PackedByteArray:
	return var_to_bytes(_pick(d, WELCOME_FIELDS))


static func decode_welcome(b: PackedByteArray) -> Dictionary:
	return _unpick(b, WELCOME_FIELDS)


static func _pick(d: Dictionary, fields: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in fields:
		var v = d.get(k, null)
		match int(fields[k]):
			TYPE_INT:
				out[k] = int(v) if v != null else 0
			TYPE_BOOL:
				out[k] = bool(v) if v != null else false
			_:
				out[k] = String(v) if v != null else ""
	return out


static func _unpick(b: PackedByteArray, fields: Dictionary) -> Dictionary:
	if b.size() < 4 or b.size() > HELLO_MAX:
		return {}
	var v = bytes_to_var(b)
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = v
	for k in fields:
		if not d.has(k) or typeof(d[k]) != int(fields[k]):
			return {}
	return _pick(d, fields)


# ------------------------------------------------------------------ СПИСОК ИГРОКОВ
## u8 n + n × (u8 slot, u32 peer, s64 uid, u16 look, u8 len, ник UTF-8).
## list — массив {slot, peer, uid, look, nick}.

static func encode_roster(list: Array) -> PackedByteArray:
	var s: StreamPeerBuffer = StreamPeerBuffer.new()
	s.put_u8(mini(list.size(), 255))
	for i in mini(list.size(), 255):
		var e: Dictionary = list[i]
		s.put_u8(int(e.get("slot", 0)) & 0xFF)
		s.put_u32(int(e.get("peer", 0)) & 0xFFFFFFFF)
		s.put_64(int(e.get("uid", 0)))
		s.put_u16(int(e.get("look", 0)) & 0xFFFF)
		_put_str8(s, String(e.get("nick", "")))
	return s.data_array


## null — если байты битые.
static func decode_roster(b: PackedByteArray):
	var s: StreamPeerBuffer = _reader(b)
	if s.get_available_bytes() < 1:
		return null
	var n: int = s.get_u8()
	var out: Array = []
	for i in n:
		if s.get_available_bytes() < 16:
			return null
		var e: Dictionary = {}
		e["slot"] = s.get_u8()
		e["peer"] = s.get_u32()
		e["uid"] = s.get_64()
		e["look"] = s.get_u16()
		var nick = _get_str8(s)
		if nick == null:
			return null
		e["nick"] = nick
		out.append(e)
	return out if s.get_available_bytes() == 0 else null


# ------------------------------------------------------------------ МИР: ТАЙЛЫ И ВОДА
## u16 n + n × u32 (idx << 8 | значение). idx — до 24 бит (мир 640×180 = 115 200).

static func encode_cells(idx: PackedInt32Array, val: PackedByteArray) -> PackedByteArray:
	var n: int = mini(mini(idx.size(), val.size()), 0xFFFF)
	var out: PackedByteArray = PackedByteArray()
	out.resize(2 + 4 * n)
	out.encode_u16(0, n)
	for i in n:
		out.encode_u32(2 + 4 * i, ((idx[i] & 0xFFFFFF) << 8) | (val[i] & 0xFF))
	return out


## {idx: PackedInt32Array, val: PackedByteArray} или {} у битого.
static func decode_cells(b: PackedByteArray) -> Dictionary:
	if b.size() < 2:
		return {}
	var n: int = b.decode_u16(0)
	if b.size() != 2 + 4 * n:
		return {}
	var idx: PackedInt32Array = PackedInt32Array()
	var val: PackedByteArray = PackedByteArray()
	idx.resize(n)
	val.resize(n)
	for i in n:
		var w: int = b.decode_u32(2 + 4 * i)
		idx[i] = w >> 8
		val[i] = w & 0xFF
	return {"idx": idx, "val": val}


# ------------------------------------------------------------------ МАШИНЫ
## MACHINE_ADD — var_to_bytes(save_state()); MACHINE_DEL — u32 клетка;
## MACHINES — u16 n + n × (u32 клетка, u8 длина, net_state).

static func encode_machine_add(state: Dictionary) -> PackedByteArray:
	return var_to_bytes(state)


static func decode_machine_add(b: PackedByteArray):
	var v = bytes_to_var(b) if b.size() >= 4 else null
	return v if typeof(v) == TYPE_DICTIONARY else null


static func encode_u32(v: int) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(4)
	out.encode_u32(0, v & 0xFFFFFFFF)
	return out


## -1 у битого.
static func decode_u32(b: PackedByteArray) -> int:
	return b.decode_u32(0) if b.size() == 4 else -1


## list — массив [клетка: int, net_state: PackedByteArray (≤ 255 Б)].
static func encode_machines(list: Array) -> PackedByteArray:
	var s: StreamPeerBuffer = StreamPeerBuffer.new()
	var n: int = mini(list.size(), 0xFFFF)
	s.put_u16(n)
	for i in n:
		var st: PackedByteArray = list[i][1]
		var len: int = mini(st.size(), 255)
		s.put_u32(int(list[i][0]))
		s.put_u8(len)
		s.put_data(st.slice(0, len))
	return s.data_array


static func decode_machines(b: PackedByteArray):
	var s: StreamPeerBuffer = _reader(b)
	if s.get_available_bytes() < 2:
		return null
	var n: int = s.get_u16()
	var out: Array = []
	for i in n:
		if s.get_available_bytes() < 5:
			return null
		var cell: int = s.get_u32()
		var len: int = s.get_u8()
		if s.get_available_bytes() < len:
			return null
		var r: Array = s.get_data(len)
		out.append([cell, r[1] as PackedByteArray])
	return out if s.get_available_bytes() == 0 else null


# ------------------------------------------------------------------ СУЩНОСТИ
## SPAWN — u8 вид, u16 id, var_to_bytes(данные появления); DESPAWN — u8 вид, u16 id.

static func encode_spawn(kind: int, id: int, data: Dictionary) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(3)
	out.encode_u8(0, kind & 0xFF)
	out.encode_u16(1, id & 0xFFFF)
	out.append_array(var_to_bytes(data))
	return out


static func decode_spawn(b: PackedByteArray) -> Dictionary:
	if b.size() < 7:
		return {}
	var v = bytes_to_var(b.slice(3))
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	return {"kind": b.decode_u8(0), "id": b.decode_u16(1), "data": v}


static func encode_despawn(kind: int, id: int) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(3)
	out.encode_u8(0, kind & 0xFF)
	out.encode_u16(1, id & 0xFFFF)
	return out


static func decode_despawn(b: PackedByteArray) -> Dictionary:
	if b.size() != 3:
		return {}
	return {"kind": b.decode_u8(0), "id": b.decode_u16(1)}


# ------------------------------------------------------------------ СОСТОЯНИЕ 20 Гц
## u16 tick, u8 nP + nP × 18, u8 nF + nF × 12, u8 nI + nI × 8.
##
## Игрок (18 Б): slot u8 · x,y u16 · vx,vy s16 (px/с) · флаги u8 (PF_*) · hp u8 (доля) ·
##   клетка копки u24 (NO_CELL — нет) · прогресс копки u8 · предмет в руке u8 ·
##   фаза шага u8 · шум u8.
## Фантом (12 Б): id u16 · x,y u16 · vx,vy s8 (/16) · вид(3)|состояние(2)<<3|
##   facing_left<<5|frozen<<6|stunned<<7 · hp u8 (доля) · оглушение u8 (×20) · флаги u8.
## Предмет в полёте (8 Б): id u16 · x,y u16 · vx,vy s8 (/16).

static func encode_state(tick: int, players: Array, phantoms: Array, items: Array) -> PackedByteArray:
	var np: int = mini(players.size(), 255)
	var nf: int = mini(phantoms.size(), 255)
	var ni: int = mini(items.size(), 255)
	var out: PackedByteArray = PackedByteArray()
	out.resize(5 + np * PLAYER_BYTES + nf * PHANTOM_BYTES + ni * ITEM_BYTES)
	out.encode_u16(0, tick & 0xFFFF)
	var o: int = 2
	out.encode_u8(o, np)
	o += 1
	for i in np:
		_put_player(out, o, players[i])
		o += PLAYER_BYTES
	out.encode_u8(o, nf)
	o += 1
	for i in nf:
		_put_phantom(out, o, phantoms[i])
		o += PHANTOM_BYTES
	out.encode_u8(o, ni)
	o += 1
	for i in ni:
		_put_item(out, o, items[i])
		o += ITEM_BYTES
	return out


## {tick, players, phantoms, items} или {} у битого.
static func decode_state(b: PackedByteArray) -> Dictionary:
	if b.size() < 5:
		return {}
	var o: int = 2
	var np: int = b.decode_u8(o)
	o += 1
	if b.size() < o + np * PLAYER_BYTES + 2:
		return {}
	var players: Array = []
	for i in np:
		players.append(_get_player(b, o))
		o += PLAYER_BYTES
	var nf: int = b.decode_u8(o)
	o += 1
	if b.size() < o + nf * PHANTOM_BYTES + 1:
		return {}
	var phantoms: Array = []
	for i in nf:
		phantoms.append(_get_phantom(b, o))
		o += PHANTOM_BYTES
	var ni: int = b.decode_u8(o)
	o += 1
	if b.size() != o + ni * ITEM_BYTES:
		return {}
	var items: Array = []
	for i in ni:
		items.append(_get_item(b, o))
		o += ITEM_BYTES
	return {"tick": b.decode_u16(0), "players": players, "phantoms": phantoms, "items": items}


static func _put_player(out: PackedByteArray, o: int, p: Dictionary) -> void:
	var pos: Vector2 = p.get("pos", Vector2.ZERO)
	var vel: Vector2 = p.get("vel", Vector2.ZERO)
	out.encode_u8(o, int(p.get("slot", 0)) & 0xFF)
	out.encode_u16(o + 1, pos_u16(pos.x))
	out.encode_u16(o + 3, pos_u16(pos.y))
	out.encode_s16(o + 5, clampi(roundi(vel.x), -32768, 32767))
	out.encode_s16(o + 7, clampi(roundi(vel.y), -32768, 32767))
	out.encode_u8(o + 9, int(p.get("flags", 0)) & 0xFF)
	out.encode_u8(o + 10, frac_u8(float(p.get("hp", 1.0))))
	var cell: int = int(p.get("mine_cell", NO_CELL))
	if cell < 0 or cell > NO_CELL:
		cell = NO_CELL
	out.encode_u16(o + 11, cell & 0xFFFF)
	out.encode_u8(o + 13, (cell >> 16) & 0xFF)
	out.encode_u8(o + 14, frac_u8(float(p.get("mine", 0.0))))
	out.encode_u8(o + 15, int(p.get("held", 0)) & 0xFF)
	out.encode_u8(o + 16, frac_u8(float(p.get("anim", 0.0))))
	out.encode_u8(o + 17, clampi(roundi(float(p.get("noise", 0.0))), 0, 255))


static func _get_player(b: PackedByteArray, o: int) -> Dictionary:
	return {
		"slot": b.decode_u8(o),
		"pos": Vector2(u16_pos(b.decode_u16(o + 1)), u16_pos(b.decode_u16(o + 3))),
		"vel": Vector2(b.decode_s16(o + 5), b.decode_s16(o + 7)),
		"flags": b.decode_u8(o + 9),
		"hp": u8_frac(b.decode_u8(o + 10)),
		"mine_cell": b.decode_u16(o + 11) | (b.decode_u8(o + 13) << 16),
		"mine": u8_frac(b.decode_u8(o + 14)),
		"held": b.decode_u8(o + 15),
		"anim": u8_frac(b.decode_u8(o + 16)),
		"noise": float(b.decode_u8(o + 17)),
	}


static func _put_phantom(out: PackedByteArray, o: int, f: Dictionary) -> void:
	var pos: Vector2 = f.get("pos", Vector2.ZERO)
	var vel: Vector2 = f.get("vel", Vector2.ZERO)
	out.encode_u16(o, int(f.get("id", 0)) & 0xFFFF)
	out.encode_u16(o + 2, pos_u16(pos.x))
	out.encode_u16(o + 4, pos_u16(pos.y))
	out.encode_s8(o + 6, vel_s8(vel.x))
	out.encode_s8(o + 7, vel_s8(vel.y))
	var bits: int = (int(f.get("kind", 0)) & 7) | ((int(f.get("state", 0)) & 3) << 3)
	if bool(f.get("facing_left", false)):
		bits |= 32
	if bool(f.get("frozen", false)):
		bits |= 64
	if bool(f.get("stunned", false)):
		bits |= 128
	out.encode_u8(o + 8, bits)
	out.encode_u8(o + 9, frac_u8(float(f.get("hp", 1.0))))
	out.encode_u8(o + 10, clampi(roundi(float(f.get("stun", 0.0)) * 20.0), 0, 255))
	out.encode_u8(o + 11, int(f.get("flags", 0)) & 0xFF)


static func _get_phantom(b: PackedByteArray, o: int) -> Dictionary:
	var bits: int = b.decode_u8(o + 8)
	return {
		"id": b.decode_u16(o),
		"pos": Vector2(u16_pos(b.decode_u16(o + 2)), u16_pos(b.decode_u16(o + 4))),
		"vel": Vector2(b.decode_s8(o + 6) * 16.0, b.decode_s8(o + 7) * 16.0),
		"kind": bits & 7,
		"state": (bits >> 3) & 3,
		"facing_left": (bits & 32) != 0,
		"frozen": (bits & 64) != 0,
		"stunned": (bits & 128) != 0,
		"hp": u8_frac(b.decode_u8(o + 9)),
		"stun": b.decode_u8(o + 10) / 20.0,
		"flags": b.decode_u8(o + 11),
	}


static func _put_item(out: PackedByteArray, o: int, it: Dictionary) -> void:
	var pos: Vector2 = it.get("pos", Vector2.ZERO)
	var vel: Vector2 = it.get("vel", Vector2.ZERO)
	out.encode_u16(o, int(it.get("id", 0)) & 0xFFFF)
	out.encode_u16(o + 2, pos_u16(pos.x))
	out.encode_u16(o + 4, pos_u16(pos.y))
	out.encode_s8(o + 6, vel_s8(vel.x))
	out.encode_s8(o + 7, vel_s8(vel.y))


static func _get_item(b: PackedByteArray, o: int) -> Dictionary:
	return {
		"id": b.decode_u16(o),
		"pos": Vector2(u16_pos(b.decode_u16(o + 2)), u16_pos(b.decode_u16(o + 4))),
		"vel": Vector2(b.decode_s8(o + 6) * 16.0, b.decode_s8(o + 7) * 16.0),
	}


# ------------------------------------------------------------------ СВОЙ ГЕРОЙ (OWN)
## hp u8 (доля) · флаги u8 (OF_*) · hide_timer u8 (×40) · emp_cd u8 (×20) · seq_ack u16
## [+ поправка позиции 2×u16, если OF_CORRECTION]. 6 или 10 Б.

static func encode_own(d: Dictionary) -> PackedByteArray:
	var flags: int = int(d.get("flags", 0)) & 0xFF & ~OF_CORRECTION
	var has_corr: bool = d.has("correction")
	if has_corr:
		flags |= OF_CORRECTION
	var out: PackedByteArray = PackedByteArray()
	out.resize(OWN_BYTES + (4 if has_corr else 0))
	out.encode_u8(0, frac_u8(float(d.get("hp", 1.0))))
	out.encode_u8(1, flags)
	out.encode_u8(2, clampi(roundi(float(d.get("hide_timer", 0.0)) * 40.0), 0, 255))
	out.encode_u8(3, clampi(roundi(float(d.get("emp_cd", 0.0)) * 20.0), 0, 255))
	out.encode_u16(4, int(d.get("seq_ack", 0)) & 0xFFFF)
	if has_corr:
		var c: Vector2 = d["correction"]
		out.encode_u16(6, pos_u16(c.x))
		out.encode_u16(8, pos_u16(c.y))
	return out


static func decode_own(b: PackedByteArray) -> Dictionary:
	if b.size() != OWN_BYTES and b.size() != OWN_BYTES + 4:
		return {}
	var flags: int = b.decode_u8(1)
	var has_corr: bool = (flags & OF_CORRECTION) != 0
	if has_corr != (b.size() == OWN_BYTES + 4):
		return {}
	var d: Dictionary = {
		"hp": u8_frac(b.decode_u8(0)),
		"flags": flags & ~OF_CORRECTION,
		"hide_timer": b.decode_u8(2) / 40.0,
		"emp_cd": b.decode_u8(3) / 20.0,
		"seq_ack": b.decode_u16(4),
	}
	if has_corr:
		d["correction"] = Vector2(u16_pos(b.decode_u16(6)), u16_pos(b.decode_u16(8)))
	return d


# ------------------------------------------------------------------ ВВОД КЛИЕНТА (26 Б)
## seq u16 · клавиши u32 (KEY_BITS, BIT_LMB, BIT_RMB, BIT_WINDOW) · мышь 2×u16 ·
## слот u8 · счётчики нажатий E/Q/V/G по 4 бита (u16) · позиция 2×f32 ·
## скорость 2×s16 · флаги u8 (1 — facing_left, 2 — on_ground).

static func encode_input(d: Dictionary) -> PackedByteArray:
	var mouse: Vector2 = d.get("mouse", Vector2.ZERO)
	var pos: Vector2 = d.get("pos", Vector2.ZERO)
	var vel: Vector2 = d.get("vel", Vector2.ZERO)
	var out: PackedByteArray = PackedByteArray()
	out.resize(INPUT_BYTES)
	out.encode_u16(0, int(d.get("seq", 0)) & 0xFFFF)
	out.encode_u32(2, int(d.get("keys", 0)) & 0xFFFFFFFF)
	out.encode_u16(6, pos_u16(mouse.x))
	out.encode_u16(8, pos_u16(mouse.y))
	out.encode_u8(10, int(d.get("slot", 0)) & 0xFF)
	out.encode_u16(11, int(d.get("presses", 0)) & 0xFFFF)
	out.encode_float(13, pos.x)
	out.encode_float(17, pos.y)
	out.encode_s16(21, clampi(roundi(vel.x), -32768, 32767))
	out.encode_s16(23, clampi(roundi(vel.y), -32768, 32767))
	out.encode_u8(25, int(d.get("flags", 0)) & 0xFF)
	return out


static func decode_input(b: PackedByteArray) -> Dictionary:
	if b.size() != INPUT_BYTES:
		return {}
	return {
		"seq": b.decode_u16(0),
		"keys": b.decode_u32(2),
		"mouse": Vector2(u16_pos(b.decode_u16(6)), u16_pos(b.decode_u16(8))),
		"slot": b.decode_u8(10),
		"presses": b.decode_u16(11),
		"pos": Vector2(b.decode_float(13), b.decode_float(17)),
		"vel": Vector2(b.decode_s16(21), b.decode_s16(23)),
		"flags": b.decode_u8(25),
	}


## Бит клавиши в маске ввода (-1 — клавиша по сети не ходит).
static func key_bit(code: int) -> int:
	return KEY_BITS.find(code)


## Маска клавиш из словаря {код: нажата} шва ввода Player (keys/mouse_buttons).
static func keys_mask(keys: Dictionary, buttons: Dictionary = {}, window_open: bool = false) -> int:
	var m: int = 0
	for code in keys:
		var bit: int = key_bit(int(code))
		if bit >= 0 and bool(keys[code]):
			m |= 1 << bit
	if bool(buttons.get(MOUSE_BUTTON_LEFT, false)):
		m |= 1 << BIT_LMB
	if bool(buttons.get(MOUSE_BUTTON_RIGHT, false)):
		m |= 1 << BIT_RMB
	if window_open:
		m |= 1 << BIT_WINDOW
	return m


## Обратно в шов ввода Player.test_input: {keys, mouse_buttons}.
static func mask_to_input(mask: int) -> Dictionary:
	var keys: Dictionary = {}
	for i in KEY_BITS.size():
		keys[KEY_BITS[i]] = (mask & (1 << i)) != 0
	return {"keys": keys, "mouse_buttons": {
		MOUSE_BUTTON_LEFT: (mask & (1 << BIT_LMB)) != 0,
		MOUSE_BUTTON_RIGHT: (mask & (1 << BIT_RMB)) != 0,
	}}


## Счётчик нажатий i (0 — E, 1 — Q, 2 — V, 3 — G) по 4 бита: фронт не теряется
## при потере пакета — хост сравнивает с прошлым значением.
static func presses_get(presses: int, i: int) -> int:
	return (presses >> (4 * i)) & 0xF


static func presses_bump(presses: int, i: int) -> int:
	var v: int = (presses_get(presses, i) + 1) & 0xF
	return (presses & ~(0xF << (4 * i))) | (v << (4 * i))


# ------------------------------------------------------------------ ГЛОБАЛЬНОЕ (1 Гц)
## time f32 · смена u16 · состояние u8 · данные u16 · этап u8 · релей u8 + f32 ·
## задания 2×u8 · угроза u8 + f32 · браун-аут u8 · hash мира u32 · game_time f32. 31 Б.

const GLOBAL_BYTES: int = 31


static func encode_global(d: Dictionary) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(GLOBAL_BYTES)
	out.encode_float(0, float(d.get("time", 0.0)))
	out.encode_u16(4, clampi(int(d.get("day", 0)), 0, 0xFFFF))
	out.encode_u8(6, int(d.get("state", 0)) & 0xFF)
	out.encode_u16(7, clampi(int(d.get("research", 0)), 0, 0xFFFF))
	out.encode_u8(9, int(d.get("stage", 0)) & 0xFF)
	out.encode_u8(10, 1 if bool(d.get("relay_active", false)) else 0)
	out.encode_float(11, float(d.get("relay_timer", 0.0)))
	out.encode_u8(15, clampi(int(d.get("tasks_done", 0)), 0, 255))
	out.encode_u8(16, clampi(int(d.get("tasks_total", 0)), 0, 255))
	out.encode_u8(17, int(d.get("threat", 0)) & 0xFF)
	out.encode_float(18, float(d.get("threat_budget", 0.0)))
	out.encode_u8(22, 1 if bool(d.get("brownout", false)) else 0)
	out.encode_u32(23, int(d.get("hash", 0)) & 0xFFFFFFFF)
	out.encode_float(27, float(d.get("game_time", 0.0)))
	return out


static func decode_global(b: PackedByteArray) -> Dictionary:
	if b.size() != GLOBAL_BYTES:
		return {}
	return {
		"time": b.decode_float(0), "day": b.decode_u16(4), "state": b.decode_u8(6),
		"research": b.decode_u16(7), "stage": b.decode_u8(9), "relay_active": b.decode_u8(10) != 0,
		"relay_timer": b.decode_float(11), "tasks_done": b.decode_u8(15),
		"tasks_total": b.decode_u8(16), "threat": b.decode_u8(17),
		"threat_budget": b.decode_float(18), "brownout": b.decode_u8(22) != 0,
		"hash": b.decode_u32(23), "game_time": b.decode_float(27),
	}


# ------------------------------------------------------------------ СОБЫТИЯ
## u8 тип (Ev) · координата 2×u16 · аргументы:
##   SOUND — id звука u8, громкость s8 (дБ), тон u8 (×100);
##   NOTIFY — u16 длина + текст UTF-8 + цвет u32 (RGBA8);
##   FX — вид u8 (Fx) + u8 аргумент;
##   HIT — удар по своему герою (владельцу, канал 2): отбрасывание 2×s16 (px/с) +
##         оглушение u8 (×100 с) — MP-D.

static func encode_event(type: int, pos: Vector2, args: PackedByteArray) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(5)
	out.encode_u8(0, type & 0xFF)
	out.encode_u16(1, pos_u16(pos.x))
	out.encode_u16(3, pos_u16(pos.y))
	out.append_array(args)
	return out


static func encode_sound(pos: Vector2, sound_id: int, volume_db: float, pitch: float) -> PackedByteArray:
	var a: PackedByteArray = PackedByteArray()
	a.resize(3)
	a.encode_u8(0, sound_id & 0xFF)
	a.encode_s8(1, clampi(roundi(volume_db), -128, 127))
	a.encode_u8(2, clampi(roundi(pitch * 100.0), 0, 255))
	return encode_event(Ev.SOUND, pos, a)


static func encode_notify(pos: Vector2, text: String, color: Color) -> PackedByteArray:
	var t: PackedByteArray = text.to_utf8_buffer()
	if t.size() > 0xFFFF:
		t = t.slice(0, 0xFFFF)
	var a: PackedByteArray = PackedByteArray()
	a.resize(2)
	a.encode_u16(0, t.size())
	a.append_array(t)
	var c: PackedByteArray = PackedByteArray()
	c.resize(4)
	c.encode_u32(0, color.to_rgba32())
	a.append_array(c)
	return encode_event(Ev.NOTIFY, pos, a)


static func encode_fx(pos: Vector2, kind: int, arg: int) -> PackedByteArray:
	return encode_event(Ev.FX, pos, PackedByteArray([kind & 0xFF, arg & 0xFF]))


static func encode_hit(pos: Vector2, knock: Vector2, stun: float) -> PackedByteArray:
	var a: PackedByteArray = PackedByteArray()
	a.resize(5)
	a.encode_s16(0, clampi(roundi(knock.x), -32768, 32767))
	a.encode_s16(2, clampi(roundi(knock.y), -32768, 32767))
	a.encode_u8(4, clampi(roundi(stun * 100.0), 0, 255))
	return encode_event(Ev.HIT, pos, a)


## {type, pos, ...} или {} у битого.
static func decode_event(b: PackedByteArray) -> Dictionary:
	if b.size() < 5:
		return {}
	var d: Dictionary = {"type": b.decode_u8(0),
			"pos": Vector2(u16_pos(b.decode_u16(1)), u16_pos(b.decode_u16(3)))}
	var a: PackedByteArray = b.slice(5)
	match int(d["type"]):
		Ev.SOUND:
			if a.size() != 3:
				return {}
			d["sound"] = a.decode_u8(0)
			d["volume_db"] = float(a.decode_s8(1))
			d["pitch"] = a.decode_u8(2) / 100.0
		Ev.NOTIFY:
			if a.size() < 6:
				return {}
			var n: int = a.decode_u16(0)
			if a.size() != 2 + n + 4:
				return {}
			d["text"] = a.slice(2, 2 + n).get_string_from_utf8()
			d["color"] = Color.hex(a.decode_u32(2 + n))
		Ev.FX:
			if a.size() != 2:
				return {}
			d["kind"] = a[0]
			d["arg"] = a[1]
		Ev.HIT:
			if a.size() != 5:
				return {}
			d["knock"] = Vector2(a.decode_s16(0), a.decode_s16(2))
			d["stun"] = a.decode_u8(4) / 100.0
		_:
			d["args"] = a
	return d


# ------------------------------------------------------------------ ИНВЕНТАРЬ
## u8 n + n × (u8 id, u16 count) + u8 selected. 36 слотов — 110 Б.
## slots — массив [id, count].

static func encode_inv(slots: Array, selected: int) -> PackedByteArray:
	var n: int = mini(slots.size(), 255)
	var out: PackedByteArray = PackedByteArray()
	out.resize(2 + 3 * n)
	out.encode_u8(0, n)
	for i in n:
		out.encode_u8(1 + 3 * i, int(slots[i][0]) & 0xFF)
		out.encode_u16(2 + 3 * i, clampi(int(slots[i][1]), 0, 0xFFFF))
	out.encode_u8(1 + 3 * n, selected & 0xFF)
	return out


static func decode_inv(b: PackedByteArray) -> Dictionary:
	if b.size() < 2:
		return {}
	var n: int = b.decode_u8(0)
	if b.size() != 2 + 3 * n:
		return {}
	var slots: Array = []
	for i in n:
		slots.append([b.decode_u8(1 + 3 * i), b.decode_u16(2 + 3 * i)])
	return {"slots": slots, "selected": b.decode_u8(1 + 3 * n)}


# ------------------------------------------------------------------ КОМАНДЫ
## CMD — u8 команда · u16 номер запроса · аргументы;
## CMD_RESULT — u16 номер запроса · u8 ok · u8 длина + причина UTF-8.

static func encode_cmd(op: int, req: int, args: PackedByteArray) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(3)
	out.encode_u8(0, op & 0xFF)
	out.encode_u16(1, req & 0xFFFF)
	out.append_array(args)
	return out


static func decode_cmd(b: PackedByteArray) -> Dictionary:
	if b.size() < 3:
		return {}
	return {"op": b.decode_u8(0), "req": b.decode_u16(1), "args": b.slice(3)}


static func encode_cmd_result(req: int, ok: bool, reason: String) -> PackedByteArray:
	var s: StreamPeerBuffer = StreamPeerBuffer.new()
	s.put_u16(req & 0xFFFF)
	s.put_u8(1 if ok else 0)
	_put_str8(s, reason)
	return s.data_array


static func decode_cmd_result(b: PackedByteArray) -> Dictionary:
	var s: StreamPeerBuffer = _reader(b)
	if s.get_available_bytes() < 4:
		return {}
	var req: int = s.get_u16()
	var ok: bool = s.get_u8() != 0
	var reason = _get_str8(s)
	if reason == null or s.get_available_bytes() != 0:
		return {}
	return {"req": req, "ok": ok, "reason": reason}


# ------------------------------------------------------------------ СТРОКА (харнесс, имена)

## u8 длина + UTF-8 (обрезается до 255 байт по границе символа).
static func encode_str8(text: String) -> PackedByteArray:
	var s: StreamPeerBuffer = StreamPeerBuffer.new()
	_put_str8(s, text)
	return s.data_array


static func decode_str8(b: PackedByteArray):
	var s: StreamPeerBuffer = _reader(b)
	var t = _get_str8(s)
	return t if t != null and s.get_available_bytes() == 0 else null


# ------------------------------------------------------------------ ЧИСЛА

static func pos_u16(px: float) -> int:
	return clampi(roundi(px * POS_SCALE), 0, 0xFFFF)


static func u16_pos(v: int) -> float:
	return float(v) / POS_SCALE


static func vel_s8(v: float) -> int:
	return clampi(roundi(v / 16.0), -128, 127)


static func frac_u8(f: float) -> int:
	return clampi(roundi(clampf(f, 0.0, 1.0) * 255.0), 0, 255)


static func u8_frac(v: int) -> float:
	return float(v) / 255.0


static func _reader(b: PackedByteArray) -> StreamPeerBuffer:
	var s: StreamPeerBuffer = StreamPeerBuffer.new()
	s.data_array = b
	return s


static func _put_str8(s: StreamPeerBuffer, text: String) -> void:
	var t: PackedByteArray = text.to_utf8_buffer()
	while t.size() > 255:
		text = text.substr(0, text.length() - 1)
		t = text.to_utf8_buffer()
	s.put_u8(t.size())
	s.put_data(t)


static func _get_str8(s: StreamPeerBuffer):
	if s.get_available_bytes() < 1:
		return null
	var n: int = s.get_u8()
	if s.get_available_bytes() < n:
		return null
	var r: Array = s.get_data(n)
	return (r[1] as PackedByteArray).get_string_from_utf8()


# ------------------------------------------------------------------ СХЕМА

## Канонический набор всех сообщений: по одному образцу каждого. Хэш этих байтов
## (вместе с Msg, KEY_BITS и таблицами DB) хранит net_test: схема поменялась —
## поднимите Net.PROTO и обновите хэш.
static func schema_sample() -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	var parts: Array = [
		encode_hello({"proto": 1, "build": "dev", "uid": 123456789012, "nick": "Аня", "look": 0x1234}),
		encode_welcome({"ok": true, "reason": "", "seed": 31337, "slot": 1,
				"session_name": "Экспедиция", "nick": "Аня 2"}),
		encode_roster([{"slot": 0, "peer": 1, "uid": -5, "look": 7, "nick": "Хост"}]),
		encode_cells(PackedInt32Array([0, 115199]), PackedByteArray([3, 9])),
		encode_machine_add({"kind": "belt", "cell": Vector2i(3, 4)}),
		encode_u32(0x01020304),
		encode_machines([[77, PackedByteArray([1, 2, 3])]]),
		encode_spawn(2, 513, {"kind": "echo"}),
		encode_despawn(2, 513),
		encode_state(258, [{"slot": 1, "pos": Vector2(5000.25, 1400.5), "vel": Vector2(168, -305),
				"flags": PF_ON_GROUND | PF_SPRINT, "hp": 0.5, "mine_cell": 70000, "mine": 0.25,
				"held": 9, "anim": 0.75, "noise": 40.0}],
				[{"id": 17, "pos": Vector2(5123.5, 1402.25), "vel": Vector2(-64, 32), "kind": 3,
				"state": 2, "facing_left": true, "frozen": true, "stunned": false, "hp": 0.76,
				"stun": 1.5, "flags": 5}],
				[{"id": 300, "pos": Vector2(10.0, 20.0), "vel": Vector2(48, -96)}]),
		encode_own({"hp": 0.9, "flags": OF_HIDING, "hide_timer": 2.5, "emp_cd": 4.0, "seq_ack": 999,
				"correction": Vector2(100.0, 200.0)}),
		encode_input({"seq": 65535, "keys": 0x5005, "mouse": Vector2(321.0, 654.0), "slot": 3,
				"presses": 0x4321, "pos": Vector2(5000.5, 1400.25), "vel": Vector2(-248, 520), "flags": 3}),
		encode_global({"time": 0.66, "day": 3, "state": 0, "research": 12, "stage": 2,
				"relay_active": true, "relay_timer": 90.5, "tasks_done": 2, "tasks_total": 5,
				"threat": 1, "threat_budget": 7.5, "brownout": true, "hash": 0xDEADBEEF, "game_time": 1234.5}),
		encode_sound(Vector2(100, 200), 5, -6.0, 1.2),
		encode_notify(Vector2(0, 0), "Рядом нет вентиляции", Color(1.0, 0.5, 0.25)),
		encode_fx(Vector2(1, 2), 3, 4),
		encode_hit(Vector2(5, 6), Vector2(-120.0, -80.0), 0.12),
		encode_inv([[9, 99], [0, 0], [255, 65535]], 2),
		encode_cmd(4, 77, PackedByteArray([1, 2])),
		encode_cmd_result(77, false, "далеко"),
		encode_str8("барьер"),
	]
	for p in parts:
		out.append_array(encode_u32((p as PackedByteArray).size()))
		out.append_array(p)
	out.append_array(var_to_bytes(Msg.keys()))
	out.append_array(var_to_bytes(Ev.keys()))
	out.append_array(var_to_bytes(KEY_BITS))
	out.append_array(var_to_bytes([POS_SCALE, WORLD_PX, WORLD_W_CELLS, BIT_LMB, BIT_RMB, BIT_WINDOW]))
	# MP-D (#89): звуки, FX, флаги ввода и эпоха поправки.
	out.append_array(var_to_bytes(SOUNDS))
	out.append_array(var_to_bytes(Fx.keys()))
	out.append_array(var_to_bytes([IF_FACING_LEFT, IF_ON_GROUND, IF_EPOCH_SHIFT, OF_EPOCH_SHIFT, PRESS_KEYS]))
	# MP-G (#91): команды InvOps, сундук, исследования.
	out.append_array(inv_schema_sample())
	return out


# ------------------------------------------------------------------ ИГРОКИ (MP-D, #89)

## Звуки EVENT.SOUND: id u8 — индекс здесь. Только дописывать в конец (иначе — PROTO).
const SOUNDS: Array = ["mine", "break", "place", "pickup", "craft", "place_machine", "hit",
		"alarm", "power", "step", "vent_hum", "turret_zap", "swarm", "doppel_whisper", "brownout"]

## Виды EVENT.FX (аргумент — в скобках). Только дописывать в конец.
enum Fx {
	NONE,
	CHIP_TILE,     ## крошка тайла в клетке точки (id тайла — цвет)
	CHIP_REPAIR,   ## крошка ремонта в клетке точки
	RING_EMP,      ## кольцо импульса Q
	SLASH,         ## удар по фантому
}

## Флаги пакета ввода (младшие биты u8): взгляд влево, на земле; биты 2–3 — эпоха
## поправки: клиент повторяет эпоху последней принятой поправки, хост до этого не
## верит позициям из пакетов (они отправлены до телепорта).
const IF_FACING_LEFT: int = 1
const IF_ON_GROUND: int = 2
const IF_EPOCH_SHIFT: int = 2
## Эпоха поправки в флагах OWN (биты 5–6).
const OF_EPOCH_SHIFT: int = 5
## Счётчики нажатий пакета ввода по порядку (presses_get i): E, Q, V, G.
const PRESS_KEYS: Array = [KEY_E, KEY_Q, KEY_V, KEY_G]


## id звука по имени (−1 — по сети не ходит).
static func sound_id(name: String) -> int:
	return SOUNDS.find(name)


## Имя звука по id ("" — неизвестный).
static func sound_name(id: int) -> String:
	return String(SOUNDS[id]) if id >= 0 and id < SOUNDS.size() else ""


# ------------------------------------------------------------------ ИНВЕНТАРИ (MP-G, #91)
## Слой команд InvOps (ADR-002 § 4.2.7): CMD = u8 команда · u16 номер запроса · аргументы
## (encode_inv_args); итог — CMD_RESULT, свежий INV владельцу и CHEST подписчикам сундука.

## Команды CMD. Только дописывать в конец (иначе — поднять Net.PROTO).
enum InvOp { NONE, MOVE, SPLIT, TAKE_ALL, PUT_ALL, CRAFT, DROP, SELECT, UNLOCK, CLOSE }
## Контейнеры команд: инвентарь героя, открытый сундук, «рука» (окно, по сети не ходит).
enum Box { INV, CHEST, HAND }
## События TECH. Только дописывать в конец.
enum TechEv { NONE, UNLOCK, CHAPTER, FRAGMENT }
## Слот «куда» = сам: стопка целиком по правилам Shift+ЛКМ панели.
const SLOT_AUTO: int = 0xFF
## Клетка сундука «нет».
const CELL_NONE: int = 0xFFFFFFFF
## Флаг MOVE: в «куда» другой предмет — обмен стопками (только если берётся вся стопка).
const MOVE_SWAP: int = 1
## Флаги CHEST: открыть окно сундука; окно закрыть (сундука больше нет).
const CHEST_OPEN: int = 1
const CHEST_CLOSED: int = 2


## Клетка → u32 (y · WORLD_W_CELLS + x); клетка с минусом → CELL_NONE.
static func cell_idx(c: Vector2i) -> int:
	if c.x < 0 or c.y < 0:
		return CELL_NONE
	return c.y * WORLD_W_CELLS + c.x


static func idx_cell(i: int) -> Vector2i:
	if i == CELL_NONE or i < 0:
		return Vector2i(-1, -1)
	return Vector2i(i % WORLD_W_CELLS, i / WORLD_W_CELLS)


## Аргументы команды по её виду (поля словаря — в скобках):
##   MOVE, SPLIT — откуда u8 (from, Box) · слот u8 (fslot) · куда u8 (to) · слот u8 (tslot,
##       SLOT_AUTO — сам) · ожидаемый предмет u8 (id) · n u16 · флаги u8 (MOVE_SWAP) ·
##       клетка сундука u32 (cell, индекс cell_idx) — 12 Б;
##   TAKE_ALL, PUT_ALL, CLOSE — клетка сундука u32 (cell);
##   CRAFT — рецепт u16 (recipe, индекс DB.recipes) · раз u8 (times);
##   DROP — откуда u8 · слот u8 · id u8 · n u16 · клетка u32;
##   SELECT — слот u8 (slot); UNLOCK — узел u8 (node, индекс Tech.ORDER).
static func encode_inv_args(op: int, d: Dictionary) -> PackedByteArray:
	var s: StreamPeerBuffer = StreamPeerBuffer.new()
	match op:
		InvOp.MOVE, InvOp.SPLIT:
			s.put_u8(int(d.get("from", 0)) & 0xFF)
			s.put_u8(int(d.get("fslot", 0)) & 0xFF)
			s.put_u8(int(d.get("to", 0)) & 0xFF)
			s.put_u8(int(d.get("tslot", 0)) & 0xFF)
			s.put_u8(int(d.get("id", 0)) & 0xFF)
			s.put_u16(clampi(int(d.get("n", 0)), 0, 0xFFFF))
			s.put_u8(int(d.get("flags", 0)) & 0xFF)
			s.put_u32(int(d.get("cell", CELL_NONE)) & 0xFFFFFFFF)
		InvOp.TAKE_ALL, InvOp.PUT_ALL, InvOp.CLOSE:
			s.put_u32(int(d.get("cell", CELL_NONE)) & 0xFFFFFFFF)
		InvOp.CRAFT:
			s.put_u16(int(d.get("recipe", 0)) & 0xFFFF)
			s.put_u8(clampi(int(d.get("times", 1)), 0, 0xFF))
		InvOp.DROP:
			s.put_u8(int(d.get("from", 0)) & 0xFF)
			s.put_u8(int(d.get("fslot", 0)) & 0xFF)
			s.put_u8(int(d.get("id", 0)) & 0xFF)
			s.put_u16(clampi(int(d.get("n", 0)), 0, 0xFFFF))
			s.put_u32(int(d.get("cell", CELL_NONE)) & 0xFFFFFFFF)
		InvOp.SELECT:
			s.put_u8(int(d.get("slot", 0)) & 0xFF)
		InvOp.UNLOCK:
			s.put_u8(int(d.get("node", 0)) & 0xFF)
	return s.data_array


## Размер аргументов каждой команды, Б.
const INV_ARGS_SIZE: Dictionary = {InvOp.MOVE: 12, InvOp.SPLIT: 12, InvOp.TAKE_ALL: 4,
		InvOp.PUT_ALL: 4, InvOp.CLOSE: 4, InvOp.CRAFT: 3, InvOp.DROP: 9, InvOp.SELECT: 1,
		InvOp.UNLOCK: 1}


## {} — неизвестная команда или размер не тот.
static func decode_inv_args(op: int, b: PackedByteArray) -> Dictionary:
	if not INV_ARGS_SIZE.has(op) or b.size() != int(INV_ARGS_SIZE[op]):
		return {}
	var s: StreamPeerBuffer = _reader(b)
	match op:
		InvOp.MOVE, InvOp.SPLIT:
			return {"from": s.get_u8(), "fslot": s.get_u8(), "to": s.get_u8(), "tslot": s.get_u8(),
					"id": s.get_u8(), "n": s.get_u16(), "flags": s.get_u8(), "cell": s.get_u32()}
		InvOp.TAKE_ALL, InvOp.PUT_ALL, InvOp.CLOSE:
			return {"cell": s.get_u32()}
		InvOp.CRAFT:
			return {"recipe": s.get_u16(), "times": s.get_u8()}
		InvOp.DROP:
			return {"from": s.get_u8(), "fslot": s.get_u8(), "id": s.get_u8(), "n": s.get_u16(),
					"cell": s.get_u32()}
		InvOp.SELECT:
			return {"slot": s.get_u8()}
	return {"node": s.get_u8()}


## CHEST: клетка u32 · флаги u8 (CHEST_OPEN, CHEST_CLOSED) · u8 n · n × (u8 id, u16 count).
## 24 слота — 78 Б. slots — массив [id, count].
static func encode_chest(cell: int, flags: int, slots: Array) -> PackedByteArray:
	var n: int = mini(slots.size(), 255)
	var out: PackedByteArray = PackedByteArray()
	out.resize(6 + 3 * n)
	out.encode_u32(0, cell & 0xFFFFFFFF)
	out.encode_u8(4, flags & 0xFF)
	out.encode_u8(5, n)
	for i in n:
		out.encode_u8(6 + 3 * i, int(slots[i][0]) & 0xFF)
		out.encode_u16(7 + 3 * i, clampi(int(slots[i][1]), 0, 0xFFFF))
	return out


## {cell, flags, slots} или {} у битого.
static func decode_chest(b: PackedByteArray) -> Dictionary:
	if b.size() < 6:
		return {}
	var n: int = b.decode_u8(5)
	if b.size() != 6 + 3 * n:
		return {}
	var slots: Array = []
	for i in n:
		slots.append([b.decode_u8(6 + 3 * i), b.decode_u16(7 + 3 * i)])
	return {"cell": int(b.decode_u32(0)), "flags": b.decode_u8(4), "slots": slots}


## TECH: вид u8 (TechEv) · данные u16 (Game.research после события) · дальше по виду:
## UNLOCK — узел u8 (индекс Tech.ORDER), CHAPTER — глава u8, FRAGMENT — u8 длина + UTF-8.
static func encode_tech(kind: int, research: int, arg: int, text: String = "") -> PackedByteArray:
	var s: StreamPeerBuffer = StreamPeerBuffer.new()
	s.put_u8(kind & 0xFF)
	s.put_u16(clampi(research, 0, 0xFFFF))
	if kind == TechEv.FRAGMENT:
		_put_str8(s, text)
	else:
		s.put_u8(arg & 0xFF)
	return s.data_array


## {kind, research, arg, text} или {} у битого.
static func decode_tech(b: PackedByteArray) -> Dictionary:
	var s: StreamPeerBuffer = _reader(b)
	if s.get_available_bytes() < 4:
		return {}
	var kind: int = s.get_u8()
	var research: int = s.get_u16()
	var d: Dictionary = {"kind": kind, "research": research, "arg": 0, "text": ""}
	if kind == TechEv.FRAGMENT:
		var t = _get_str8(s)
		if t == null:
			return {}
		d["text"] = t
	else:
		d["arg"] = s.get_u8()
	if s.get_available_bytes() != 0:
		return {}
	return d


## Образцы сообщений MP-G для schema_sample().
static func inv_schema_sample() -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	var parts: Array = [
		encode_cmd(InvOp.MOVE, 300, encode_inv_args(InvOp.MOVE, {"from": Box.CHEST, "fslot": 23,
				"to": Box.INV, "tslot": SLOT_AUTO, "id": 9, "n": 999, "flags": MOVE_SWAP, "cell": 115199})),
		encode_inv_args(InvOp.TAKE_ALL, {"cell": 77}),
		encode_inv_args(InvOp.CRAFT, {"recipe": 34, "times": 2}),
		encode_inv_args(InvOp.DROP, {"from": Box.INV, "fslot": 35, "id": 3, "n": 64, "cell": CELL_NONE}),
		encode_inv_args(InvOp.SELECT, {"slot": 9}),
		encode_inv_args(InvOp.UNLOCK, {"node": 5}),
		encode_chest(cell_idx(Vector2i(320, 90)), CHEST_OPEN, [[9, 99], [0, 0], [255, 65535]]),
		encode_tech(TechEv.UNLOCK, 12, 1),
		encode_tech(TechEv.FRAGMENT, 0, 0, "…сигнал с глубины 40…"),
	]
	for p in parts:
		out.append_array(encode_u32((p as PackedByteArray).size()))
		out.append_array(p)
	out.append_array(var_to_bytes([InvOp.keys(), Box.keys(), TechEv.keys(), SLOT_AUTO, CELL_NONE,
			MOVE_SWAP, CHEST_OPEN, CHEST_CLOSED, INV_ARGS_SIZE.values()]))
	return out
