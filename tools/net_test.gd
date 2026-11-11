extends SceneTree
## Автотест сети, уровень 1 (ADR-002, § 4.10; MP-A, #86): всё в одном процессе.
##
##   godot --headless --path . --script res://tools/net_test.gd
##
## 1) Кодек: каждое сообщение § 9.3 туда-обратно, граничные значения, битые байты;
##    размеры против var_to_bytes(Dictionary) (таблица замера).
## 2) Рукопожатие: таблица решений хоста (Net.check_hello), ники, флаги --mp-*.
## 3) Петля: хост + 3 клиента — свои SceneMultiplayer на поддеревьях /root/H, /root/C0..
##    (SceneTree.set_multiplayer), ENet только на 127.0.0.1. Повтор ника → «Аня 2»,
##    пятый игрок — «мест нет», чужой протокол — «версии разные»; каналы 0–3; уход
##    клиента и хоста. Замер: подключение + рукопожатие, мс; синтетика 20 Гц, Б/с.
## 4) Схема: хэш образцов всех сообщений + Msg + KEY_BITS + IDs + числа тайлов, предметов,
##    рецептов DB. Изменилась без подъёма Net.PROTO — провал.
##
## Режим --script: имена автозагрузок при компиляции недоступны — Net грузим через
## load(), DB и World берём через get_node().

## Схема протокола PROTO = SCHEMA_PROTO. Поменяли кодек, порядок IDs или таблицы DB —
## поднимите Net.PROTO и впишите сюда новый PROTO и хэш, который напечатает тест.
const SCHEMA_PROTO: int = 14
const SCHEMA_HASH: String = "06a6bbc32ee65158f5006607bb31cb2b"

const PORT_BASE: int = 24900
const LOOP: String = "127.0.0.1"
const SYNTH_SEC: float = 3.0
const WATCHDOG_MS: int = 60000

var NetS: GDScript = null
var checks: int = 0
var fails: int = 0
var _t_start: int = 0


func _initialize() -> void:
	_t_start = Time.get_ticks_msec()
	NetS = load("res://scripts/autoload/net.gd")
	_run()


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _t_start > WATCHDOG_MS:
		print("  FAIL тест уложился в %d с" % (WATCHDOG_MS / 1000))
		print("ИТОГ: проверок %d, провалов %d" % [checks + 1, fails + 1])
		quit(1)
		return true
	return false


func ok(label: String, cond: bool, extra: String = "") -> void:
	checks += 1
	if cond:
		print("  OK   %s %s" % [label, extra])
	else:
		fails += 1
		print("  FAIL %s %s" % [label, extra])


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## Ждать условия до timeout секунд (кадрами: ENet опрашивается в кадре).
func _until(cond: Callable, timeout: float) -> bool:
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(timeout * 1000.0):
		if cond.call():
			return true
		await process_frame
	return bool(cond.call())


func _run() -> void:
	await process_frame          # автозагрузки (DB, World) готовы
	_codec()
	_codec_inv()   # MP-G (#91): команды InvOps, CHEST, TECH
	_codec_coop()  # MP-I (#94): смерть, вклад в релей, итоги
	_codec_team()   # MP-J (#95): TEAM — перекличка, маска и «глюк» двойника
	_sizes()
	_handshake_table()
	await _loop()
	_schema()
	print("")
	print("ИТОГ: проверок %d, провалов %d" % [checks, fails])
	quit(1 if fails > 0 else 0)


# ------------------------------------------------------------------ 1. КОДЕК

func _codec() -> void:
	print("== Кодек ==")
	# Кадр
	var fr: PackedByteArray = NetCodec.frame(NetCodec.Msg.STATE, PackedByteArray([1, 2]))
	ok("кадр: тип + нагрузка", NetCodec.frame_type(fr) == NetCodec.Msg.STATE and NetCodec.frame_payload(fr) == PackedByteArray([1, 2]))
	ok("пустой кадр — NONE", NetCodec.frame_type(PackedByteArray()) == NetCodec.Msg.NONE)

	# Мир и числа
	var world: Node = root.get_node("/root/World")
	var w_px: Vector2 = Vector2(int(world.W) * int(world.TILE), int(world.H) * int(world.TILE))
	ok("WORLD_PX = размер мира", NetCodec.WORLD_PX == w_px, str(w_px))
	ok("WORLD_W_CELLS = World.W", NetCodec.WORLD_W_CELLS == int(world.W))
	ok("мир помещается в u16 · POS_SCALE", maxf(w_px.x, w_px.y) * NetCodec.POS_SCALE <= 65535.0)
	ok("индекс клетки помещается в 24 бита", int(world.W) * int(world.H) < NetCodec.NO_CELL)
	var db: Node = root.get_node("/root/DB")
	ok("id тайлов и предметов — 8 бит", db.tile_defs.size() <= 256 and db.item_defs.size() <= 256,
			"тайлов %d, предметов %d" % [db.tile_defs.size(), db.item_defs.size()])

	# Рукопожатие
	var hello: Dictionary = {"proto": 1, "build": "0.5.0", "uid": -9223372036854775807, "nick": "Аня",
			"look": 0xFFFF}
	ok("hello туда-обратно", NetCodec.decode_hello(NetCodec.encode_hello(hello)) == hello)
	ok("hello: мусор → {}", NetCodec.decode_hello(PackedByteArray([1, 2, 3])).is_empty())
	ok("hello: не словарь → {}", NetCodec.decode_hello(var_to_bytes([1, 2])).is_empty())
	ok("hello: поле не того типа → {}", NetCodec.decode_hello(var_to_bytes({"proto": "1", "build": "dev",
			"uid": 1, "nick": "a", "look": 0})).is_empty())
	ok("hello: нет поля → {}", NetCodec.decode_hello(var_to_bytes({"proto": 1, "build": "dev", "uid": 1,
			"nick": "Аня"})).is_empty())
	var big: PackedByteArray = var_to_bytes({"proto": 1, "build": "x".repeat(600), "uid": 1, "nick": "a", "look": 0})
	ok("hello длиннее %d Б → {}" % NetCodec.HELLO_MAX, NetCodec.decode_hello(big).is_empty())
	var welcome: Dictionary = {"ok": false, "reason": "версии разные: хост 0.5.0, у вас 0.4.2",
			"seed": 4294967295, "slot": 3, "session_name": "Экспедиция Ани", "nick": "Аня 2",
			"mission": "siege"}   # ADR-004: глава кампании хоста
	ok("welcome туда-обратно", NetCodec.decode_welcome(NetCodec.encode_welcome(welcome)) == welcome)

	# Список игроков
	var roster: Array = [{"slot": 0, "peer": 1, "uid": -1, "look": 0, "nick": "Хост"},
			{"slot": 3, "peer": 2147483647, "uid": 9223372036854775807, "look": 0xFFFF, "nick": "Ёжик_42"}]
	ok("ROSTER туда-обратно", NetCodec.decode_roster(NetCodec.encode_roster(roster)) == roster)
	var rb: PackedByteArray = NetCodec.encode_roster(roster)
	ok("ROSTER обрезанный → null", NetCodec.decode_roster(rb.slice(0, rb.size() - 1)) == null)
	ok("ROSTER с хвостом → null", NetCodec.decode_roster(rb + PackedByteArray([0])) == null)

	# Тайлы и вода
	var idx: PackedInt32Array = PackedInt32Array([0, 1, 115199, 0xFFFFFF])
	var val: PackedByteArray = PackedByteArray([0, 255, 31, 7])
	var cells: Dictionary = NetCodec.decode_cells(NetCodec.encode_cells(idx, val))
	ok("TILES/FLUID туда-обратно (idx 0..2^24−1, значение 0..255)",
			cells.get("idx") == idx and cells.get("val") == val)
	ok("TILES: 4 Б на клетку + 2", NetCodec.encode_cells(idx, val).size() == 2 + 4 * idx.size())
	ok("TILES пустой", NetCodec.decode_cells(NetCodec.encode_cells(PackedInt32Array(), PackedByteArray())).get("idx", null) == PackedInt32Array())
	ok("TILES неверной длины → {}", NetCodec.decode_cells(PackedByteArray([2, 0, 1, 2, 3])).is_empty())

	# Машины, сущности
	var st: Dictionary = {"kind": "belt", "cell": Vector2i(3, 4), "items": [[1, 0.5]]}
	ok("MACHINE_ADD туда-обратно", NetCodec.decode_machine_add(NetCodec.encode_machine_add(st)) == st)
	ok("MACHINE_DEL u32", NetCodec.decode_u32(NetCodec.encode_u32(0xFFFFFFFF)) == 0xFFFFFFFF and NetCodec.decode_u32(PackedByteArray([1])) == -1)
	var ml: Array = [[0, PackedByteArray()], [115199, PackedByteArray([1, 2, 3, 4, 5, 6])]]
	ok("MACHINES туда-обратно", NetCodec.decode_machines(NetCodec.encode_machines(ml)) == ml)
	ok("MACHINES обрезанный → null", NetCodec.decode_machines(NetCodec.encode_machines(ml).slice(0, 9)) == null)
	var sp: Dictionary = NetCodec.decode_spawn(NetCodec.encode_spawn(2, 65535, {"kind": "doppel", "name": "Аня"}))
	ok("SPAWN туда-обратно", sp.get("kind") == 2 and sp.get("id") == 65535 and sp.get("data") == {"kind": "doppel", "name": "Аня"})
	ok("DESPAWN туда-обратно", NetCodec.decode_despawn(NetCodec.encode_despawn(1, 300)) == {"kind": 1, "id": 300})

	# Состояние 20 Гц
	var pl: Dictionary = {"slot": 3, "pos": Vector2(10239.75, 0.25), "vel": Vector2(248, -520),
			"flags": NetCodec.PF_FACING_LEFT | NetCodec.PF_DEAD | NetCodec.PF_ROLLCALL, "hp": 1.0, "mine_cell": 115199,
			"mine": 0.0, "held": 255, "anim": 1.0, "noise": 255.0}
	var ph: Dictionary = {"id": 65535, "pos": Vector2(0.0, 2880.0), "vel": Vector2(-2048.0, 2032.0),
			"kind": 7, "state": 3, "facing_left": true, "frozen": false, "stunned": true, "hp": 0.0,
			"stun": 12.75, "flags": 255}
	var it: Dictionary = {"id": 1, "pos": Vector2(5000.5, 1440.25), "vel": Vector2(160.0, -320.0)}
	var sb: PackedByteArray = NetCodec.encode_state(65535, [pl, pl], [ph], [it, it, it])
	ok("STATE: 5 + 18·nP + 12·nF + 8·nI", sb.size() == 5 + 2 * 18 + 12 + 3 * 8, "%d Б" % sb.size())
	var sd: Dictionary = NetCodec.decode_state(sb)
	ok("STATE разобран", sd.size() == 4 and sd["players"].size() == 2 and sd["phantoms"].size() == 1 and sd["items"].size() == 3)
	if sd.size() == 4:
		ok("игрок туда-обратно (граница мира, скорость, флаги, клетка копки)", sd["players"][0] == pl,
				str(sd["players"][0]))
		ok("фантом туда-обратно (вид 7, состояние 3, скорость ±2048/16)", sd["phantoms"][0] == ph,
				str(sd["phantoms"][0]))
		ok("предмет туда-обратно", sd["items"][2] == it, str(sd["items"][2]))
		ok("tick u16", sd["tick"] == 65535)
	var clamp_p: Dictionary = NetCodec.decode_state(NetCodec.encode_state(0, [{"pos": Vector2(-50, 99999), "vel": Vector2(99999, -99999),
			"mine_cell": -1, "hp": 7.0}], [], []))["players"][0]
	ok("игрок: позиция и скорость обрезаются, «нет клетки» = NO_CELL",
			clamp_p["pos"] == Vector2(0, 65535 / NetCodec.POS_SCALE) and clamp_p["vel"] == Vector2(32767, -32768)
			and clamp_p["mine_cell"] == NetCodec.NO_CELL and clamp_p["hp"] == 1.0, str(clamp_p))
	var prec: float = 0.0
	for x in [0.1, 17.37, 5123.49, 10239.9]:
		var q: Vector2 = NetCodec.decode_state(NetCodec.encode_state(0, [], [], [{"pos": Vector2(x, x / 4.0)}]))["items"][0]["pos"]
		prec = maxf(prec, maxf(absf(q.x - x), absf(q.y - x / 4.0)))
	ok("точность позиции ≤ 1/8 px", prec <= 0.125 + 1e-6, "%.3f px" % prec)
	ok("STATE битый → {}", NetCodec.decode_state(sb.slice(0, sb.size() - 1)).is_empty() and NetCodec.decode_state(PackedByteArray([0, 0])).is_empty())
	ok("STATE пустой", NetCodec.decode_state(NetCodec.encode_state(1, [], [], [])).get("tick") == 1)

	# Свой герой
	var own: Dictionary = {"hp": 0.0, "flags": NetCodec.OF_HIDING | NetCodec.OF_STUN, "hide_timer": 6.0, "emp_cd": 8.0, "seq_ack": 65535}
	var ob: PackedByteArray = NetCodec.encode_own(own)
	ok("OWN без поправки — 6 Б, туда-обратно", ob.size() == 6 and NetCodec.decode_own(ob) == own, str(NetCodec.decode_own(ob)))
	var own2: Dictionary = own.duplicate()
	own2["correction"] = Vector2(10240, 2880)
	var ob2: PackedByteArray = NetCodec.encode_own(own2)
	ok("OWN с поправкой — 10 Б, туда-обратно", ob2.size() == 10 and NetCodec.decode_own(ob2) == own2)
	ok("OWN: флаг поправки без поправки → {}", NetCodec.decode_own(ob2.slice(0, 6)).is_empty())

	# Ввод клиента
	var keys: Dictionary = {KEY_A: true, KEY_SPACE: true, KEY_G: true, KEY_S: true, KEY_D: false}
	var mask: int = NetCodec.keys_mask(keys, {MOUSE_BUTTON_RIGHT: true}, true)
	var back: Dictionary = NetCodec.mask_to_input(mask)
	ok("клавиши → маска → шов ввода", back["keys"][KEY_A] and back["keys"][KEY_SPACE] and back["keys"][KEY_G]
			and not back["keys"][KEY_D] and back["mouse_buttons"][MOUSE_BUTTON_RIGHT]
			and not back["mouse_buttons"][MOUSE_BUTTON_LEFT] and (mask >> NetCodec.BIT_WINDOW) & 1 == 1)
	ok("клавиша вне KEY_BITS по сети не ходит", NetCodec.key_bit(KEY_S) == -1)
	var pr: int = 0
	for i in 17:
		pr = NetCodec.presses_bump(pr, 2)
	ok("счётчик нажатий V: 17 → 1 (по модулю 16), соседи не тронуты",
			NetCodec.presses_get(pr, 2) == 1 and NetCodec.presses_get(pr, 0) == 0 and NetCodec.presses_get(pr, 3) == 0)
	var inp: Dictionary = {"seq": 65535, "keys": mask, "mouse": Vector2(10239.75, 2879.5), "slot": 9,
			"presses": 0xFFFF, "pos": Vector2(5000.125, 1400.5), "vel": Vector2(-248, 520), "flags": 3}
	var ib: PackedByteArray = NetCodec.encode_input(inp)
	ok("INPUT — 26 Б, туда-обратно", ib.size() == 26 and NetCodec.decode_input(ib) == inp, str(NetCodec.decode_input(ib)))
	ok("INPUT не 26 Б → {}", NetCodec.decode_input(ib.slice(0, 25)).is_empty())

	# Глобальное
	var gl: Dictionary = {"time": 0.5, "day": 65535, "state": 2, "research": 999, "stage": 4,
			"relay_active": true, "relay_timer": 180.0, "tasks_done": 3, "tasks_total": 12, "threat": 1,
			"threat_budget": 7.25, "brownout": false, "hash": 0xFFFFFFFF, "game_time": 3600.5}
	var gb: PackedByteArray = NetCodec.encode_global(gl)
	ok("GLOBAL — %d Б, туда-обратно" % NetCodec.GLOBAL_BYTES, gb.size() == NetCodec.GLOBAL_BYTES and NetCodec.decode_global(gb) == gl,
			str(NetCodec.decode_global(gb)))

	# События
	var ev: Dictionary = NetCodec.decode_event(NetCodec.encode_sound(Vector2(100, 200), 255, -128.0, 2.55))
	ok("EVENT звук туда-обратно", ev.get("type") == NetCodec.Ev.SOUND and ev.get("sound") == 255
			and ev.get("volume_db") == -128.0 and absf(float(ev.get("pitch", 0)) - 2.55) < 0.001
			and ev.get("pos") == Vector2(100, 200))
	var col: Color = Color8(255, 128, 64, 255)
	var en: Dictionary = NetCodec.decode_event(NetCodec.encode_notify(Vector2(8, 9), "Рядом нет вентиляции", col))
	ok("EVENT уведомление (UTF-8, цвет, без иконки)", en.get("text") == "Рядом нет вентиляции"
			and en.get("color") == col and int(en.get("icon", -1)) == 0)
	var eg: Dictionary = NetCodec.decode_event(NetCodec.encode_notify(Vector2(1, 2), "Теперь можно сделать: Стекло", col, 7))
	ok("EVENT уведомление с иконкой предмета", eg.get("text") == "Теперь можно сделать: Стекло" and int(eg.get("icon", 0)) == 7)
	ok("EVENT FX", NetCodec.decode_event(NetCodec.encode_fx(Vector2.ZERO, 3, 200)).get("arg") == 200)
	ok("EVENT битый → {}", NetCodec.decode_event(NetCodec.encode_notify(Vector2.ZERO, "abc", col).slice(0, 9)).is_empty())
	# MP-D (#89): удар по своему герою, таблица звуков.
	var eh: Dictionary = NetCodec.decode_event(NetCodec.encode_hit(Vector2(40, 50), Vector2(-120, 300), 0.12))
	ok("EVENT удар: отбрасывание и оглушение", eh.get("type") == NetCodec.Ev.HIT
			and eh.get("knock") == Vector2(-120, 300) and absf(float(eh.get("stun", 0)) - 0.12) < 0.001, str(eh))
	ok("EVENT удар битый → {}", NetCodec.decode_event(NetCodec.encode_hit(Vector2.ZERO, Vector2.ONE, 0.1).slice(0, 8)).is_empty())
	var snd_ok: bool = NetCodec.SOUNDS.size() <= 256
	for i in NetCodec.SOUNDS.size():
		snd_ok = snd_ok and NetCodec.sound_id(NetCodec.sound_name(i)) == i
	ok("звуки: имя ↔ id u8, неизвестный — −1 / \"\"", snd_ok and NetCodec.sound_id("нет") == -1
			and NetCodec.sound_name(255) == "")

	# Инвентарь
	var slots: Array = []
	for i in 36:
		slots.append([i % 40, i * 1000])
	slots[35] = [255, 65535]
	var inv: Dictionary = NetCodec.decode_inv(NetCodec.encode_inv(slots, 35))
	ok("INV 36 слотов без seen — 111 Б, туда-обратно", NetCodec.encode_inv(slots, 35).size() == 111
			and inv.get("slots") == slots and inv.get("selected") == 35 and inv.get("seen") == [])
	var seen: Array = [3, 9, 3, 0]
	var invs: Dictionary = NetCodec.decode_inv(NetCodec.encode_inv(slots, 2, seen))
	ok("INV хвост seen: id без нуля и повторов", NetCodec.encode_inv(slots, 2, seen).size() == 113
			and invs.get("seen") == [3, 9] and invs.get("selected") == 2)
	ok("INV: count обрезается до u16", NetCodec.decode_inv(NetCodec.encode_inv([[1, 99999]], 0))["slots"][0][1] == 65535)

	# Команды
	var cmd: Dictionary = NetCodec.decode_cmd(NetCodec.encode_cmd(7, 65535, PackedByteArray([9, 8])))
	ok("CMD туда-обратно", cmd.get("op") == 7 and cmd.get("req") == 65535 and cmd.get("args") == PackedByteArray([9, 8]))
	ok("CMD_RESULT туда-обратно", NetCodec.decode_cmd_result(NetCodec.encode_cmd_result(5, false, "сундук далеко"))
			== {"req": 5, "ok": false, "reason": "сундук далеко"})
	var long_s: String = "Ж".repeat(200)     # 400 Б UTF-8
	var s8 = NetCodec.decode_str8(NetCodec.encode_str8(long_s))
	ok("строка u8: обрезка до 255 Б по границе символа", s8 is String and String(s8).length() == 127
			and String(s8) == "Ж".repeat(127))

	# MP-F (#92): появление фантома (SPAWN вида Ent.PHANTOM), типы — те же, что Phantom.KINDS.
	var fsp: Dictionary = {"kind": 4, "pack": 7, "name": "Ефим Л.", "pos": Vector2(5120.25, 1400.5)}
	var fsd: Dictionary = NetCodec.decode_phantom_spawn(NetCodec.encode_phantom_spawn(65535, fsp))
	ok("SPAWN фантома туда-обратно (двойник, стая, имя)", fsd.get("id") == 65535 and fsd.get("kind") == 4
			and fsd.get("pack") == 7 and fsd.get("name") == "Ефим Л." and fsd.get("pos") == fsp["pos"], str(fsd))
	ok("SPAWN чужого вида / битый → {}", NetCodec.decode_phantom_spawn(NetCodec.encode_spawn(NetCodec.Ent.ITEM, 1,
			{"kind": 0, "pos": Vector2.ZERO})).is_empty() and NetCodec.decode_phantom_spawn(
			NetCodec.encode_spawn(NetCodec.Ent.PHANTOM, 1, {"kind": 9, "pos": Vector2.ZERO})).is_empty()
			and NetCodec.decode_phantom_spawn(PackedByteArray([1, 2])).is_empty())
	var kinds_ok: bool = NetCodec.PHANTOM_KINDS == (load("res://scripts/entities/phantom.gd") as GDScript) \
			.get_script_constant_map().get("KINDS", [])
	ok("типы фантомов кодека = Phantom.KINDS (3 бита)", kinds_ok and NetCodec.PHANTOM_KINDS.size() <= 8)


## Размеры кодека против var_to_bytes(Dictionary) — таблица замера.
func _sizes() -> void:
	print("== Замер: размер сообщений, кодек против var_to_bytes ==")
	var pl: Dictionary = {"slot": 1, "pos": Vector2(5000.25, 1400.5), "vel": Vector2(168, 0), "flags": 2,
			"hp": 0.8, "mine_cell": 56789, "mine": 0.4, "held": 9, "anim": 0.3, "noise": 14.0}
	var ph: Dictionary = {"id": 17, "pos": Vector2(5123.5, 1402.25), "vel": Vector2(32, 0), "kind": 1,
			"state": 2, "facing_left": true, "frozen": false, "stunned": false, "hp": 0.76, "stun": 0.0, "flags": 0}
	var it: Dictionary = {"id": 3, "pos": Vector2(10, 20), "vel": Vector2(16, -32)}
	var inp: Dictionary = {"seq": 1, "keys": 5, "mouse": Vector2(5100, 1390), "slot": 2, "presses": 0x11,
			"pos": Vector2(5000.25, 1400.5), "vel": Vector2(168, 0), "flags": 2}
	var own: Dictionary = {"hp": 0.8, "flags": 1, "hide_timer": 3.0, "emp_cd": 0.0, "seq_ack": 7}
	var gl: Dictionary = {"time": 0.66, "day": 3, "state": 0, "research": 12, "stage": 2, "relay_active": false,
			"relay_timer": 0.0, "tasks_done": 2, "tasks_total": 5, "threat": 1, "threat_budget": 7.5,
			"brownout": false, "hash": 12345678, "game_time": 1234.5}
	var slots: Array = []
	for i in 36:
		slots.append([i % 40, 10 + i])
	var inv_d: Dictionary = {"slots": slots, "selected": 3}
	var tiles: PackedInt32Array = PackedInt32Array()
	var tv: PackedByteArray = PackedByteArray()
	var tdict: Array = []
	for i in 50:
		tiles.append(1000 + i * 7)
		tv.append(i % 30)
		tdict.append({"x": (1000 + i * 7) % 640, "y": (1000 + i * 7) / 640, "id": i % 30})
	var state16: PackedByteArray = NetCodec.encode_state(1, [pl, pl, pl], _rep(ph, 16), [])
	var state16_d: Dictionary = {"tick": 1, "players": [pl, pl, pl], "phantoms": _rep(ph, 16), "items": []}
	var rows: Array = [
		["игрок (в STATE)", NetCodec.encode_state(0, [pl], [], []).size() - 5, var_to_bytes(pl).size()],
		["фантом (в STATE)", NetCodec.encode_state(0, [], [ph], []).size() - 5, var_to_bytes(ph).size()],
		["предмет в полёте", NetCodec.encode_state(0, [], [], [it]).size() - 5, var_to_bytes(it).size()],
		["STATE: 3 игрока + 16 фантомов", state16.size(), var_to_bytes(state16_d).size()],
		["INPUT", NetCodec.encode_input(inp).size(), var_to_bytes(inp).size()],
		["OWN", NetCodec.encode_own(own).size(), var_to_bytes(own).size()],
		["GLOBAL", NetCodec.encode_global(gl).size(), var_to_bytes(gl).size()],
		["INV (36 слотов)", NetCodec.encode_inv(slots, 3).size(), var_to_bytes(inv_d).size()],
		["TILES (50 клеток)", NetCodec.encode_cells(tiles, tv).size(), var_to_bytes(tdict).size()],
	]
	print("  | Сообщение | Кодек, Б | var_to_bytes, Б | × |")
	print("  |---|---|---|---|")
	for r in rows:
		print("  | %s | %d | %d | %.1f |" % [r[0], r[1], r[2], float(r[2]) / float(r[1])])
	ok("кодек: игрок 18 Б, фантом 12 Б, предмет 8 Б, ввод 26 Б", rows[0][1] == 18 and rows[1][1] == 12
			and rows[2][1] == 8 and rows[4][1] == 26)


func _rep(d: Dictionary, n: int) -> Array:
	var a: Array = []
	for i in n:
		a.append(d)
	return a


# ------------------------------------------------------------------ 2. РУКОПОЖАТИЕ

func _handshake_table() -> void:
	print("== Рукопожатие: таблица решений хоста ==")
	var hs: Dictionary = {"proto": NetS.PROTO, "build": "0.5.0", "open": true, "free_slot": 2,
			"nicks": ["Хост", "Аня"]}
	var good: Dictionary = {"proto": NetS.PROTO, "build": "0.5.0", "uid": 7, "nick": "Борис", "look": 1}
	var cases: Array = [
		# [что, hello-правка, host-правка, ok, причина (начало), ник]
		["свободный слот, новый ник — вход", {}, {}, true, "", "Борис"],
		["битое hello — отказ", null, {}, false, NetS.R_BAD_HELLO, ""],
		["игра закрыта", {}, {"open": false}, false, NetS.R_CLOSED, ""],
		["чужой proto", {"proto": NetS.PROTO + 1}, {}, false,
				"версии разные: протокол хоста %d, у вас %d" % [NetS.PROTO, NetS.PROTO + 1], ""],
		["чужая сборка", {"build": "0.4.2"}, {}, false, "версии разные: хост 0.5.0, у вас 0.4.2", ""],
		["dev против релиза", {"build": "dev"}, {}, false, "версии разные: хост 0.5.0, у вас dev", ""],
		["оба dev — вход", {"build": "dev"}, {"build": "dev"}, true, "", "Борис"],
		["мест нет", {}, {"free_slot": -1}, false, NetS.R_FULL, ""],
		["протокол важнее мест", {"proto": 0}, {"free_slot": -1}, false, "версии разные", ""],
		["недопустимый ник", {"nick": "!!"}, {}, false, "недопустимый ник", ""],
		["короткий ник", {"nick": " a "}, {}, false, "недопустимый ник", ""],
		["повтор ника → «Аня 2»", {"nick": "Аня"}, {}, true, "", "Аня 2"],
		["повтор без регистра → «аня 2»", {"nick": "аня"}, {}, true, "", "аня 2"],
		["третья Аня → «Аня 3»", {"nick": "Аня"}, {"nicks": ["Аня", "Аня 2"]}, true, "", "Аня 3"],
		["ник с пробелами по краям обрезается", {"nick": "  Вера "}, {}, true, "", "Вера"],
		["16 символов + повтор — не длиннее 16", {"nick": "Абвгдежзийклмноп"},
				{"nicks": ["Абвгдежзийклмноп"]}, true, "", "Абвгдежзийклмн 2"],
	]
	for c in cases:
		var h: Dictionary = {}
		if c[1] != null:
			h = good.duplicate()
			h.merge(c[1], true)
		var st: Dictionary = hs.duplicate()
		st.merge(c[2], true)
		var r: Dictionary = NetS.check_hello(h, st)
		var good_r: bool = bool(r["ok"]) == bool(c[3]) and String(r["reason"]).begins_with(String(c[4])) \
				and (not bool(c[3]) or (String(r["nick"]) == String(c[5]) and int(r["slot"]) == int(st["free_slot"])))
		ok(String(c[0]), good_r, "→ %s «%s» %s" % ["вход" if r["ok"] else "отказ", r["reason"], r["nick"]])

	var valid: Array = ["Аня", "Ab", "Ёжик_42", "Bob-1.2", "А Б", "ёлка", "1234567890123456"]
	var invalid: Array = ["A", "   ", "12345678901234567", "a  b", "_ab", "ab_", "ab!", "😀ab", "ab\tc", "-x-"]
	var bad_v: Array = []
	for n in valid:
		if NetS.nick_error(n) != "":
			bad_v.append(n)
	var bad_i: Array = []
	for n in invalid:
		if NetS.nick_error(n) == "":
			bad_i.append(n)
	ok("ники: %d допустимых проходят" % valid.size(), bad_v.is_empty(), str(bad_v))
	ok("ники: %d недопустимых отклонены" % invalid.size(), bad_i.is_empty(), str(bad_i))

	var pa: Dictionary = NetS.parse_args(PackedStringArray(["--mp-host", "--nick=Аня", "--look=0x1203",
			"--mp-bind=127.0.0.1", "--mp-clients=3", "--seed=5"]))
	ok("флаги: --mp-host без порта → 24642, ник, вид hex, bind, клиенты",
			pa.get("host_port") == NetS.GAME_PORT and pa.get("nick") == "Аня" and pa.get("look") == 0x1203
			and pa.get("bind") == "127.0.0.1" and pa.get("clients") == 3, str(pa))
	var pj: Dictionary = NetS.parse_args(PackedStringArray(["--mp-join=192.168.1.5:25000", "--look=70000",
			"--mp-host=abc", "--mp-scenario=all", "--mp-role=2"]))
	ok("флаги: --mp-join=ip:порт, --look обрезается до u16, плохой порт → 24642",
			pj.get("join_ip") == "192.168.1.5" and pj.get("join_port") == 25000 and pj.get("look") == 0xFFFF
			and pj.get("host_port") == NetS.GAME_PORT and pj.get("scenario") == "all" and pj.get("role") == 2, str(pj))
	var pd: Dictionary = NetS.parse_args(PackedStringArray(["--mp-join=10.0.0.2"]))
	ok("флаги: --mp-join без порта → 24642", pd.get("join_ip") == "10.0.0.2" and pd.get("join_port") == NetS.GAME_PORT)
	ok("без флагов --mp-* — пусто", NetS.parse_args(PackedStringArray(["--test", "--seed=1"])).is_empty())
	ok("сборка: application/config/version или dev", NetS.build_id() != "", NetS.build_id())


# ------------------------------------------------------------------ 3. ПЕТЛЯ

var _got: Dictionary = {}      ## узел → {тип: число}


func _make(holder_name: String) -> Node:
	var h: Node = Node.new()
	h.name = holder_name
	root.add_child(h)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/" + holder_name))
	var n: Node = NetS.new()
	n.name = "Net"
	h.add_child(n)
	_got[n] = {}
	for m in [NetCodec.Msg.STATE, NetCodec.Msg.INPUT, NetCodec.Msg.INV, NetCodec.Msg.EVENT, NetCodec.Msg.CMD]:
		n.on(m, _count.bind(n, m))
	return n


func _count(sender: int, payload: PackedByteArray, n: Node, m: int) -> void:
	var d: Dictionary = _got[n]
	d[m] = int(d.get(m, 0)) + 1
	d["from_%d" % sender] = true
	d["last_%d" % m] = payload


func _loop() -> void:
	print("== Петля: хост + 3 клиента, ENet на %s ==" % LOOP)
	var host: Node = _make("H")
	host.local_profile = {"uid": 1, "nick": "Хост", "look": 0}
	var port: int = 0
	var base: int = PORT_BASE + OS.get_process_id() % 90
	for k in 10:
		if host.host(base + k, LOOP, 31337, "Петля") == OK:
			port = base + k
			break
	ok("хост слушает %s:%d" % [LOOP, port], port > 0 and host.is_host() and host.is_authority(), host.last_error)
	if port == 0:
		return
	var cl: Array = []
	var nicks: Array = ["Аня", "Аня", "Борис", "Вера", "Глеб"]
	for i in 5:
		var c: Node = _make("C%d" % i)
		c.local_profile = {"uid": 100 + i, "nick": nicks[i], "look": 0x1100 + i}
		cl.append(c)
	cl[4].hello_proto = NetS.PROTO + 1

	var t0: int = Time.get_ticks_usec()
	for i in 3:
		cl[i].join(LOOP, port)
	var all_in: Callable = func() -> bool: return host.peers.size() == 4 and cl[0].join_ms >= 0 and cl[1].join_ms >= 0 and cl[2].join_ms >= 0
	var in3: bool = await _until(all_in, 5.0)
	var join_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	ok("3 клиента вошли", in3, "игроков у хоста %d" % host.peers.size())
	print("  ЗАМЕР подключение + рукопожатие трёх клиентов на петле: %.1f мс (у клиентов %d / %d / %d мс)" % [
			join_ms, cl[0].join_ms, cl[1].join_ms, cl[2].join_ms])
	var hn: Array = []
	for id in host.peers:
		hn.append(String(host.peers[id]["nick"]))
	hn.sort()
	ok("ники у хоста: повтор разведён", hn == ["Аня", "Аня 2", "Борис", "Хост"], str(hn))
	ok("клиенты: роль CLIENT, не авторитет", cl[0].is_client() and not cl[0].is_authority())
	ok("сид и имя сессии дошли", cl[1].session.get("seed") == 31337 and cl[1].session.get("session_name") == "Петля")
	var rost: Callable = func() -> bool: return cl[0].peers.size() == 4 and cl[1].peers.size() == 4 and cl[2].peers.size() == 4
	var roster_ok: bool = await _until(rost, 2.0)
	ok("список игроков у каждого клиента — 4", roster_ok)
	var me: Dictionary = cl[2].peers.get(cl[2].my_id(), {})
	ok("своя запись клиента: uid, ник, вид, слот", me.get("uid") == 102 and me.get("nick") == "Борис"
			and me.get("look") == 0x1102 and int(me.get("slot", -1)) == int(cl[2].session.get("slot", -2)), str(me))

	# Пятый игрок и чужой протокол.
	var fail_reason: Array = ["", ""]
	cl[3].connection_failed.connect(func(r: String) -> void: fail_reason[0] = r)
	cl[4].connection_failed.connect(func(r: String) -> void: fail_reason[1] = r)
	cl[3].join(LOOP, port)
	cl[4].join(LOOP, port)
	var failed_c: Callable = func() -> bool: return fail_reason[0] != "" and fail_reason[1] != ""
	await _until(failed_c, 5.0)
	ok("пятый игрок: «мест нет»", fail_reason[0] == NetS.R_FULL, "«%s»" % fail_reason[0])
	ok("чужой протокол: «версии разные»", String(fail_reason[1]).begins_with("версии разные"), "«%s»" % fail_reason[1])
	ok("отказанные — снова OFFLINE", not cl[3].is_online() and not cl[4].is_online())
	await _frames(40)            # хост отключает отказанных через REJECT_LINGER_MS
	ok("у хоста по-прежнему 4 игрока", host.peers.size() == 4)

	# Каналы.
	host.send(NetCodec.Msg.STATE, NetCodec.encode_state(1, [], [], []))
	host.send(NetCodec.Msg.EVENT, NetCodec.encode_fx(Vector2.ZERO, 1, 2))
	host.send(NetCodec.Msg.INV, NetCodec.encode_inv([[1, 2]], 0), cl[1].my_id())
	for i in 3:
		cl[i].send(NetCodec.Msg.INPUT, NetCodec.encode_input({"seq": i}))
	cl[0].send(NetCodec.Msg.CMD, NetCodec.encode_cmd(1, 2, PackedByteArray()))
	cl[0].send_on(0, NetCodec.Msg.EVENT, PackedByteArray([1]))   # клиент по каналу 0 — не уходит
	var arrived: Callable = func() -> bool: return int(_got[host].get(NetCodec.Msg.INPUT, 0)) >= 3 and int(_got[host].get(NetCodec.Msg.CMD, 0)) >= 1 and int(_got[cl[2]].get(NetCodec.Msg.EVENT, 0)) >= 1 and int(_got[cl[1]].get(NetCodec.Msg.INV, 0)) >= 1
	await _until(arrived, 2.0)
	await _frames(5)
	ok("канал 1: состояние дошло до всех клиентов", int(_got[cl[0]].get(NetCodec.Msg.STATE, 0)) >= 1
			and int(_got[cl[2]].get(NetCodec.Msg.STATE, 0)) >= 1)
	ok("канал 0: событие — всем", int(_got[cl[0]].get(NetCodec.Msg.EVENT, 0)) == 1 and int(_got[cl[2]].get(NetCodec.Msg.EVENT, 0)) == 1)
	ok("канал 2: инвентарь — только владельцу", int(_got[cl[1]].get(NetCodec.Msg.INV, 0)) == 1
			and int(_got[cl[0]].get(NetCodec.Msg.INV, 0)) == 0 and int(_got[cl[2]].get(NetCodec.Msg.INV, 0)) == 0)
	ok("канал 3: ввод от трёх клиентов у хоста", int(_got[host].get(NetCodec.Msg.INPUT, 0)) >= 3
			and _got[host].has("from_%d" % cl[0].my_id()) and _got[host].has("from_%d" % cl[2].my_id()))
	ok("канал 2: команда клиента у хоста", int(_got[host].get(NetCodec.Msg.CMD, 0)) == 1)
	ok("клиент не шлёт по каналам хоста (0–1)", int(_got[host].get(NetCodec.Msg.EVENT, 0)) == 0)

	await _synthetic(host, cl)

	# Уход клиента и хоста.
	var left: Array = [0]
	host.peer_left.connect(func(_id: int, _info: Dictionary) -> void: left[0] += 1)
	cl[2].leave()
	var gone_c: Callable = func() -> bool: return left[0] == 1 and cl[0].peers.size() == 3
	var gone: bool = await _until(gone_c, 3.0)
	ok("клиент ушёл: хост и остальные видят 3 игрока", gone, "у хоста %d, у c0 %d" % [host.peers.size(), cl[0].peers.size()])
	var ended: Array = ["", ""]
	cl[0].session_ended.connect(func(r: String) -> void: ended[0] = r)
	cl[1].session_ended.connect(func(r: String) -> void: ended[1] = r)
	host.leave()
	var ended_c: Callable = func() -> bool: return ended[0] != "" and ended[1] != ""
	await _until(ended_c, 5.0)
	ok("хост ушёл: клиенты — «%s»" % NetS.R_HOST_LEFT, ended[0] == NetS.R_HOST_LEFT and ended[1] == NetS.R_HOST_LEFT,
			str(ended))
	ok("все снова OFFLINE", not host.is_online() and not cl[0].is_online() and not cl[1].is_online())


## Синтетика 20 Гц (как § 9.1): хост шлёт STATE (3 игрока + 16 фантомов), клиенты —
## INPUT 30 Гц. Трафик — по статистике ENet хоста, плюс UDP/IP 28 Б на датаграмму.
func _synthetic(host: Node, cl: Array) -> void:
	var pl: Dictionary = {"slot": 1, "pos": Vector2(5000, 1400), "vel": Vector2(168, 0)}
	var ph: Dictionary = {"id": 17, "pos": Vector2(5123, 1402)}
	var st: PackedByteArray = NetCodec.encode_state(0, [pl, pl, pl], _rep(ph, 16), [])
	var inp: PackedByteArray = NetCodec.encode_input({"seq": 1, "pos": Vector2(5000, 1400)})
	var ec: ENetConnection = host._peer.host
	for s in [ENetConnection.HOST_TOTAL_SENT_DATA, ENetConnection.HOST_TOTAL_SENT_PACKETS,
			ENetConnection.HOST_TOTAL_RECEIVED_DATA, ENetConnection.HOST_TOTAL_RECEIVED_PACKETS]:
		ec.pop_statistic(s)
	var got0: int = int(_got[cl[0]].get(NetCodec.Msg.STATE, 0))
	var t0: int = Time.get_ticks_msec()
	var sent: int = 0
	var sent_in: int = 0
	while Time.get_ticks_msec() - t0 < int(SYNTH_SEC * 1000.0):
		var el: float = float(Time.get_ticks_msec() - t0) / 1000.0
		while sent < int(el * NetS.TICK_HZ):
			st.encode_u16(0, sent)            # tick — номер такта
			host.send(NetCodec.Msg.STATE, st)
			sent += 1
		while sent_in < int(el * NetS.INPUT_HZ):
			for i in 3:
				cl[i].send(NetCodec.Msg.INPUT, inp)
			sent_in += 1
		await process_frame
	await _frames(5)
	var secs: float = float(Time.get_ticks_msec() - t0) / 1000.0
	var sd: int = ec.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
	var sp: int = ec.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS)
	var rd: int = ec.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)
	var rp: int = ec.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_PACKETS)
	var down: float = float(sd + 28 * sp) / secs / 3.0
	var up: float = float(rd + 28 * rp) / secs / 3.0
	var delivered: int = int(_got[cl[0]].get(NetCodec.Msg.STATE, 0)) - got0
	print("  ЗАМЕР синтетика %d Гц, %.1f с: STATE %d Б (+1 Б кадр) — отправлено %d, у c0 получено %d" % [
			NetS.TICK_HZ, secs, st.size(), sent, delivered])
	print("  ЗАМЕР хост → клиент: %.0f Б/с в ENet, %.0f Б/с с UDP/IP; клиент → хост (INPUT %d Гц): %.0f Б/с с UDP/IP" % [
			float(sd) / secs / 3.0, down, NetS.INPUT_HZ, up])
	# ENet может придержать ненадёжные пакеты (троттлинг при росте RTT на загруженной
	# машине) — рядом печатаем модель § 4.3: (кадр + ≈ 44 Б ENet/RPC + 28 Б UDP/IP) × 20 Гц.
	print("  ЗАМЕР модель § 4.3 для этого STATE: (%d + 44 + 28) × %d = %d Б/с на клиента" % [
			st.size() + 1, NetS.TICK_HZ, (st.size() + 1 + 44 + 28) * NetS.TICK_HZ])
	ok("синтетика: хост → клиент ≤ 12 КБ/с (цель обычной ночи)", down > 0.0 and down <= 12.0 * 1024.0, "%.0f Б/с" % down)
	ok("синтетика: клиент → хост ≤ 4 КБ/с", up > 0.0 and up <= 4.0 * 1024.0, "%.0f Б/с" % up)
	# Ненадёжный упорядоченный канал сам выбрасывает устаревшее (несколько пакетов за кадр —
	# доходит последний): проверяем не долю, а что свежее состояние дошло.
	var last: Dictionary = NetCodec.decode_state(_got[cl[0]].get("last_%d" % NetCodec.Msg.STATE, PackedByteArray()))
	var last_tick: int = int(last.get("tick", -1))
	ok("синтетика: свежее состояние дошло (последний такт)", delivered > 0 and last_tick >= sent - 2,
			"такт %d из %d, доставлено %d (%.0f %%)" % [last_tick, sent - 1, delivered, 100.0 * delivered / maxf(1.0, sent)])


# ------------------------------------------------------------------ 4. СХЕМА

func _schema() -> void:
	print("== Схема протокола ==")
	var db: Node = root.get_node("/root/DB")
	var s: String = NetCodec.schema_sample().hex_encode()
	s += "|T:" + ",".join(PackedStringArray(IDs.T.keys()))
	s += "|I:" + ",".join(PackedStringArray(IDs.I.keys()))
	s += "|DB:%d,%d,%d" % [db.tile_defs.size(), db.item_defs.size(), db.recipes.size()]
	var h: String = s.md5_text()
	print("  схема: PROTO %d, хэш %s (тайлов %d, предметов %d, рецептов %d)" % [NetS.PROTO, h,
			db.tile_defs.size(), db.item_defs.size(), db.recipes.size()])
	if NetS.PROTO != SCHEMA_PROTO:
		ok("PROTO поднят — обновите SCHEMA_PROTO и SCHEMA_HASH в tools/net_test.gd", false,
				"PROTO %d, SCHEMA_PROTO %d, хэш %s" % [NetS.PROTO, SCHEMA_PROTO, h])
		return
	ok("схема сообщений не изменилась без подъёма Net.PROTO", h == SCHEMA_HASH,
			"" if h == SCHEMA_HASH else "хэш %s, ждали %s: поднимите Net.PROTO и обновите SCHEMA_PROTO/SCHEMA_HASH" % [h, SCHEMA_HASH])


# ------------------------------------------------------------------ 5. ИНВЕНТАРИ (MP-G, #91)

## Команды InvOps, сундук, исследования: туда-обратно, размеры, битые кадры.
func _codec_inv() -> void:
	print("== Кодек: команды инвентаря, сундук, исследования (MP-G) ==")
	var Op: Dictionary = NetCodec.InvOp
	var samples: Array = [
		[Op.MOVE, {"from": NetCodec.Box.CHEST, "fslot": 23, "to": NetCodec.Box.INV, "tslot": NetCodec.SLOT_AUTO,
				"id": 255, "n": 65535, "flags": NetCodec.MOVE_SWAP, "cell": 115199}],
		[Op.SPLIT, {"from": NetCodec.Box.INV, "fslot": 0, "to": NetCodec.Box.INV, "tslot": 35, "id": 9, "n": 0,
				"flags": 0, "cell": NetCodec.CELL_NONE}],
		[Op.TAKE_ALL, {"cell": 4242}], [Op.PUT_ALL, {"cell": 0}], [Op.CLOSE, {"cell": NetCodec.CELL_NONE}],
		[Op.CRAFT, {"recipe": 34, "times": 3}],
		[Op.DROP, {"from": NetCodec.Box.INV, "fslot": 35, "id": 3, "n": 64, "cell": NetCodec.CELL_NONE}],
		[Op.SELECT, {"slot": 9}], [Op.UNLOCK, {"node": 5}],
	]
	var all_ok: bool = true
	var bad_ok: bool = true
	for smp in samples:
		var b: PackedByteArray = NetCodec.encode_inv_args(int(smp[0]), smp[1])
		if NetCodec.decode_inv_args(int(smp[0]), b) != smp[1]:
			all_ok = false
			print("    расхождение: команда %d" % int(smp[0]))
		if not NetCodec.decode_inv_args(int(smp[0]), b.slice(0, b.size() - 1)).is_empty():
			bad_ok = false
	ok("команды InvOps: аргументы туда-обратно (9 видов)", all_ok)
	ok("команды InvOps: короткий кадр — отказ", bad_ok and NetCodec.decode_inv_args(99, PackedByteArray([1])).is_empty())
	var move: PackedByteArray = NetCodec.frame(NetCodec.Msg.CMD, NetCodec.encode_cmd(Op.MOVE, 1,
			NetCodec.encode_inv_args(Op.MOVE, samples[0][1])))
	ok("MOVE на проводе — 16 Б (кадр)", move.size() == 16, "%d Б" % move.size())
	ok("клетка ↔ u32", NetCodec.idx_cell(NetCodec.cell_idx(Vector2i(639, 179))) == Vector2i(639, 179)
			and NetCodec.cell_idx(Vector2i(-1, -1)) == NetCodec.CELL_NONE)
	var cs: Array = []
	for i in 24:
		cs.append([i % 40, i * 2])
	cs[23] = [255, 65535]
	var ch: Dictionary = NetCodec.decode_chest(NetCodec.encode_chest(77, NetCodec.CHEST_OPEN, cs))
	ok("CHEST 24 слота — 78 Б, туда-обратно", NetCodec.encode_chest(77, NetCodec.CHEST_OPEN, cs).size() == 78
			and ch.get("cell") == 77 and ch.get("flags") == NetCodec.CHEST_OPEN and ch.get("slots") == cs)
	ok("CHEST: битый — пусто", NetCodec.decode_chest(PackedByteArray([1, 2, 3, 4, 0, 5])).is_empty())
	var tu: Dictionary = NetCodec.decode_tech(NetCodec.encode_tech(NetCodec.TechEv.UNLOCK, 1234, 3))
	var tf: Dictionary = NetCodec.decode_tech(NetCodec.encode_tech(NetCodec.TechEv.FRAGMENT, 7, 0, "…сигнал…"))
	ok("TECH туда-обратно (узел, обрывок)", tu.get("kind") == NetCodec.TechEv.UNLOCK and tu.get("research") == 1234
			and tu.get("arg") == 3 and tf.get("text") == "…сигнал…" and tf.get("research") == 7)
	ok("TECH UNLOCK — 4 Б", NetCodec.encode_tech(NetCodec.TechEv.UNLOCK, 1, 1).size() == 4)



# ------------------------------------------------------------------ MP-I (#94): КООПЕРАТИВ

func _codec_coop() -> void:
	print("== Кодек: кооператив (MP-I) ==")
	var d: Dictionary = NetCodec.decode_coop(NetCodec.encode_coop_death(15.0, false))
	var h: Dictionary = NetCodec.decode_coop(NetCodec.encode_coop_death(-1.0, true))
	ok("COOP DEATH туда-обратно (отсчёт, зритель, вайп)", d.get("kind") == NetCodec.CoopEv.DEATH
			and is_equal_approx(float(d.get("delay", 0.0)), 15.0) and d.get("wipe") == false
			and float(h.get("delay", 0.0)) < 0.0 and h.get("wipe") == true)
	ok("COOP DEATH — 6 Б", NetCodec.encode_coop_death(3.0, true).size() == 6)
	var have: Dictionary = {9: 24, 3: 48, 255: 65535}
	var r: Dictionary = NetCodec.decode_coop(NetCodec.encode_coop_relay(have))
	ok("COOP RELAY туда-обратно, порядок ключей не важен", r.get("have") == have
			and NetCodec.encode_coop_relay({3: 48, 9: 24}) == NetCodec.encode_coop_relay({9: 24, 3: 48}))
	ok("COOP RELAY пустой — 2 Б", NetCodec.encode_coop_relay({}).size() == 2
			and (NetCodec.decode_coop(NetCodec.encode_coop_relay({})).get("have", null) as Dictionary).is_empty())
	# Требование релея от N (#139) — в том же кадре; деталь без вклада — с нулём «сдано».
	var need: Dictionary = {3: 60, 9: 30, 12: 2}
	var rq: Dictionary = NetCodec.decode_coop(NetCodec.encode_coop_relay({9: 24}, need))
	ok("COOP RELAY с требованием туда-обратно", rq.get("have") == {9: 24} and rq.get("req") == need
			and NetCodec.encode_coop_relay({9: 24}, need).size() == 2 + 5 * 3,
			"%s / %s" % [str(rq.get("have")), str(rq.get("req"))])
	var s: Dictionary = NetCodec.decode_coop(NetCodec.encode_coop_stats([120, 30, 7, 2],
			[["Аня", 1], ["Борис", 65535]]))
	ok("COOP STATS туда-обратно", s.get("team") == [120, 30, 7, 2]
			and s.get("players") == [["Аня", 1], ["Борис", 65535]])
	var bad: bool = NetCodec.decode_coop(PackedByteArray()).is_empty() \
			and NetCodec.decode_coop(PackedByteArray([NetCodec.CoopEv.DEATH, 1, 2])).is_empty() \
			and NetCodec.decode_coop(PackedByteArray([NetCodec.CoopEv.RELAY, 2, 9, 1])).is_empty() \
			and NetCodec.decode_coop(PackedByteArray([NetCodec.CoopEv.RELAY, 1, 9, 1, 0])).is_empty() \
			and NetCodec.decode_coop(PackedByteArray([99])).is_empty()
	ok("COOP: битый кадр — пусто", bad)


# ------------------------------------------------------------------ 6. КОМАНДА (MP-J, #95)

func _codec_team() -> void:
	print("== Кодек команды: TEAM ==")
	var ev: Dictionary = NetCodec.TeamEv
	ok("TEAM.CALL туда-обратно", NetCodec.decode_team(NetCodec.encode_team(ev.CALL, 3))
			== {"kind": ev.CALL, "slot": 3, "id": 0})
	ok("TEAM.ANSWER туда-обратно", NetCodec.decode_team(NetCodec.encode_team(ev.ANSWER, 0))
			== {"kind": ev.ANSWER, "slot": 0, "id": 0})
	ok("TEAM.MASK туда-обратно (номер u16, слот; без маски — TEAM_NO_SLOT)",
			NetCodec.decode_team(NetCodec.encode_team(ev.MASK, 2, 65535)) == {"kind": ev.MASK, "slot": 2, "id": 65535}
			and NetCodec.decode_team(NetCodec.encode_team(ev.MASK, NetCodec.TEAM_NO_SLOT, 1))["slot"]
			== NetCodec.TEAM_NO_SLOT)
	ok("TEAM.REVEAL туда-обратно", NetCodec.decode_team(NetCodec.encode_team(ev.REVEAL, 0, 4097))["id"] == 4097)
	ok("TEAM битый / чужой вид → {}", NetCodec.decode_team(PackedByteArray([0])).is_empty()
			and NetCodec.decode_team(PackedByteArray([ev.CALL, 1, 2])).is_empty()
			and NetCodec.decode_team(PackedByteArray([ev.MASK, 1, 2])).is_empty()
			and NetCodec.decode_team(PackedByteArray([9, 1])).is_empty())
