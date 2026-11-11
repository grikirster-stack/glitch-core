class_name Save
extends RefCounted
## Сохранение и загрузка забега (ADR-001 § 5.3, PR-N, #37). F5 — сохранить,
## F9 — загрузить (UI). Один слот по умолчанию: user://save_1.sav. Из меню — «Загрузить»
## (list_saves, #132) и «Продолжить» (latest_single, #119). Пауза в забеге (PauseMenu,
## #119): «Сохранить» и «Сохранить и выйти в меню» пишут в тот же слот, что F5.
##
## Что пишется — по одному словарю на систему, каждая сериализует себя сама:
##   world    — World.save_state(): тайлы, вода (уровни и очередь), туман войны,
##              прочитанные терминалы, вентиляции, таблички руин, шлюзы и решётки
##              с HP (#31), состояние небесного тайника (#60);
##   machines — MachineBase.save_state() каждой постройки (общий механизм: база
##              пишет тип, клетку, hp, прогресс, готовое; наследник дописывает
##              своё через super). Сундуки тайников руин — такие же машины;
##   items    — предметы на земле, мешок после смерти — тоже предмет (bag);
##   player   — Player.save_state(): позиция, hp, инвентарь и хотбар, кулдауны;
##   game, tech, threat — Game/Tech/Threat.save_state().
## Фантомы поштучно не пишутся — см. Threat.save_state(): живые возвращаются в
## очередь ночи и выйдут из вентиляций заново.
##
## Файл: «GCSV», версия формата (u32), размер несжатых данных (u32), дальше
## var_to_bytes(словарь), сжатый ZSTD. Объекты в словарь не попадают:
## bytes_to_var их и не декодирует — чужой файл не выполнит код.
##
## Загрузка того же сида не пересоздаёт мир: тайлы кладутся поверх, постройки
## и предметы ставятся заново. Другой сид — сначала World.generate(сид).
## Неизвестные поля игнорируются: новая машина грузится хотя бы с базовыми
## полями, файл старой версии — с тем, что в нём есть. Свет прожекторов
## возвращается сразу после раскладки питания (Floodlight.relight).

## Версия формата. Поднимать, когда старый файл уже нельзя прочитать как есть.
## 2 — сетевая игра (ADR-002 § 4.9, MP-I #94): у хоста ещё session и players по uid;
## раздел player остался, поэтому версия 1 читается как раньше (одиночная).
const VERSION: int = 2
const MAGIC: String = "GCSV"
const HEADER_SIZE: int = 12

## Слот клавиш F5/F9. Сценарии и тесты подменяют его, чтобы не трогать сохранение игрока.
static var slot: String = "1"
## Замеры последней операции (для PR, тестов и HUD).
static var last_save_ms: float = 0.0
static var last_load_ms: float = 0.0
static var last_size: int = 0          ## байт в файле
static var last_raw_size: int = 0      ## байт до сжатия
static var last_error: String = ""


## Файл слота. В тестовом прогоне (TestEnv, #132) — с суффиксом процесса:
## save_<слот>~t<pid>.sav — параллельные прогоны не делят файлы, сохранения игрока
## тесты не трогают.
static func path_for(s: String) -> String:
	return "user://save_%s%s.sav" % [s, TestEnv.suffix()]


static func exists(s: String = slot) -> bool:
	return FileAccess.file_exists(path_for(s))


## Почему сейчас нельзя сохраниться (пустая строка — можно).
static func save_blocker() -> String:
	if Net.is_client():   # СЕТЬ (ADR-002 § 4.9): сохраняет только хост
		return NET_HOST_SAVES
	if Game.in_mission():   # ADR-004: глава короткая и начинается с готовой базы
		return MISSION_NO_SAVE
	var p = Game.player
	if p == null or not is_instance_valid(p):
		return "нет игрока"
	if Game.state != Game.State.PLAYING:
		return "забег окончен"
	if bool(p.get("dead")):
		return "герой погиб"
	return ""


# ------------------------------------------------------------------ СБОРКА

## Всё состояние забега одним словарем (только простые типы).
static func gather() -> Dictionary:
	var machines: Array = []
	for c in World.machines.keys():
		var m = World.machines[c]
		if is_instance_valid(m) and not m.is_queued_for_deletion() and m.has_method("save_state"):
			machines.append(m.save_state())
	var d: Dictionary = {
		"version": VERSION,
		"seed": World.world_seed,
		"world": World.save_state(),
		"machines": machines,
		"items": _items_state(),
		"game": Game.save_state(),
		"tech": Tech.save_state(),
		"threat": Threat.save_state(),
	}
	var p = Game.player
	if p != null and is_instance_valid(p):
		d["player"] = p.save_state()
	_net_gather(d)   # СЕТЬ (ADR-002 § 4.9): у хоста — session и players по uid
	return d


## Предметы на земле (и мешок после смерти) в порядке узлов сцены.
static func _items_state() -> Array:
	var out: Array = []
	for e in _item_nodes():
		var rec: Dictionary = {
			"id": e.item_id, "count": e.count, "pos": e.global_position, "vel": e.vel,
			"grounded": e.grounded, "age": e.age, "despawn": e.despawn,
			"pickup_delay": e.pickup_delay, "bag": e.bag.duplicate(true),
		}
		if e.bag_owner != 0:   # мешок погибшего в сети — чей (MP-I, #94)
			rec["bag_owner"] = e.bag_owner
		out.append(rec)
	return out


static func _item_nodes() -> Array:
	var out: Array = []
	var tree: SceneTree = World.get_tree()
	var hosts: Array = [World]
	if tree.current_scene != null and tree.current_scene != World:
		hosts.push_front(tree.current_scene)
	for h in hosts:
		for c in h.get_children():
			if c is ItemEntity and not c.is_queued_for_deletion():
				out.append(c)
	return out


# ------------------------------------------------------------------ ПРИМЕНЕНИЕ

## Положить состояние в мир. false — файл не подходит (last_error — почему).
static func apply(d: Dictionary) -> bool:
	if int(d.get("version", 0)) > VERSION or int(d.get("version", 0)) <= 0:
		last_error = "версия файла %d, игра знает до %d" % [int(d.get("version", 0)), VERSION]
		return false
	# Сетку проверяем до того, как что-то снести: битый файл не ломает текущий забег.
	var wd = d.get("world", {})
	var n: int = World.W * World.H
	if not (wd is Dictionary) or int(wd.get("w", 0)) != World.W or int(wd.get("h", 0)) != World.H \
			or _bytes_len(wd.get("tiles")) != n or _bytes_len(wd.get("fluid")) != n \
			or _bytes_len(wd.get("explored")) != n:
		last_error = "сетка мира в файле повреждена"
		return false
	var sd: int = int(d.get("seed", World.world_seed))
	# Окна — до инвентаря: предмет «в руке» панели вернётся в старый инвентарь,
	# а не добавится к загруженному.
	close_windows()
	_clear_world_nodes()
	# Машины снесены: их лучи больше не светят. Новые зажгутся после постановки.
	if World.beams != null:
		World.beams.cells.clear()
		World.beams.segments.clear()
		World._apply_beam_lights()
	# Другой мир — сначала тот же мир по сиду (терминалы, руины, таблички, лор).
	if sd != World.world_seed or World.tiles.size() != World.W * World.H:
		if World.tilemap:
			World.tilemap.clear()
		World.generate(sd)
		_clear_world_nodes()   # сундуки тайников генерации — их заменят сундуки из файла
	if not World.load_state(d.get("world", {})):
		last_error = "сетка мира в файле повреждена"
		return false
	_place_machines(d.get("machines", []))
	_migrate_relay_tiles()
	_place_items(d.get("items", []))
	var p = Game.player
	if p != null and is_instance_valid(p) and d.has("player"):
		p.load_state(d["player"])
	_net_apply(d)   # СЕТЬ (ADR-002 § 4.9): у хоста — герои по uid, остальные ждут в Net.parked
	Game.load_state(d.get("game", {}))
	Tech.load_state(d.get("tech", {}))
	Threat.load_state(d.get("threat", {}))
	# Питание — сразу, не через 0.25 с: машины с первого кадра в том же режиме.
	Game.update_power_budget()
	# Свет машин (прожекторы, #31) — по новому питанию, через World.add_light_source.
	for m in World.machines.values():
		if m.has_method("relight"):
			m.relight()
	# Луч (#164): горелки уже с топливом, карту и свет считаем в этом же кадре.
	if World.beams != null:
		World.beams.mark_dirty()
		World.beams.rebuild()
		World._apply_beam_lights()
	# Экран смерти — прочь: после загрузки герой жив и в мире.
	var sc: Node = World.get_tree().current_scene
	if sc != null:
		var es = sc.get("end_screen")
		if es != null and is_instance_valid(es) and es.has_method("hide_end"):
			es.hide_end()
	last_error = ""
	return true


static func _bytes_len(v) -> int:
	return v.size() if v is PackedByteArray else -1


## Убрать постройки и предметы текущего мира. Из дерева — сразу, а не только
## queue_free: иначе старая лента в этом же кадре отдала бы предмет новой.
static func _clear_world_nodes() -> void:
	for m in World.machines.values():
		if is_instance_valid(m):
			if m.get_parent() != null:
				m.get_parent().remove_child(m)
			m.queue_free()
	World.machines.clear()
	World.belts.clear()
	for c in World.ruin_caches:
		c["chest"] = null
	for e in _item_nodes():
		e.get_parent().remove_child(e)
		e.queue_free()


## Поставить постройки из файла. Неизвестный тип пропускается (файл новее игры).
static func _place_machines(list: Array) -> void:
	for md in list:
		if not (md is Dictionary):
			continue
		var c: Vector2i = md.get("cell", Vector2i(-1, -1))
		var kind: String = String(md.get("kind", ""))
		if not World.in_bounds(c.x, c.y):
			continue
		# place_machine ставит только в воздух; под машиной мог оказаться другой
		# тайл (вода натекла в клетку постройки) — на время постановки воздух.
		var t: int = World.get_tile_v(c)
		if t != IDs.T.AIR:
			World.set_tile_raw(c.x, c.y, IDs.T.AIR)
		var placed: bool = MachineBase.place_machine(kind, c)
		if t != IDs.T.AIR:
			World.set_tile_raw(c.x, c.y, t)
		if not placed:
			push_warning("Save: постройка «%s» в %s не поставлена" % [kind, str(c)])
			continue
		World.machines[c].load_state(md)
	# Тайники руин — снова ссылки на свои сундуки.
	for rc in World.ruin_caches:
		var ch = World.machines.get(rc["cell"])
		rc["chest"] = ch if ch is Chest else null
	# Небесный тайник (#60) — тоже: и запись тайника, и обломок (выдача обрывка).
	if not World.sky_cache.is_empty():
		var sc = World.machines.get(World.sky_cache.get("cell", Vector2i(-1, -1)))
		var sky_chest = sc if sc is Chest else null
		World.sky_cache["chest"] = sky_chest
		var wreck = World.sky_cache.get("wreck")
		if wreck != null and is_instance_valid(wreck):
			wreck.chest = sky_chest


## Старое сохранение: тайл RELAY_CORE — это уже не ядро. На его месте встаёт
## постройка RainbowCore, дуги с нуля (вклад деталей старого релея не переносится).
static func _migrate_relay_tiles() -> void:
	var n: int = World.W * World.H
	if World.tiles.size() != n:
		return
	for i in n:
		if int(World.tiles[i]) != IDs.T.RELAY_CORE:
			continue
		var c: Vector2i = Vector2i(i % World.W, int(i / World.W))
		World.set_tile(c.x, c.y, IDs.T.AIR)
		if not World.machines.has(c):
			MachineBase.place_machine("RainbowCore", c)


static func _place_items(list: Array) -> void:
	for it in list:
		if not (it is Dictionary):
			continue
		var e: ItemEntity = ItemEntity.new()
		e.item_id = int(it.get("id", IDs.I.NONE))
		e.count = int(it.get("count", 1))
		e.despawn = bool(it.get("despawn", true))
		e.bag = Array(it.get("bag", [])).duplicate(true)
		e.bag_owner = int(it.get("bag_owner", 0))
		e.global_position = it.get("pos", Vector2.ZERO)
		World.add_world_node(e)
		# _ready() даёт случайный подброс — ставим сохранённое после него.
		e.vel = it.get("vel", Vector2.ZERO)
		e.age = float(it.get("age", 0.0))
		e.pickup_delay = float(it.get("pickup_delay", 0.0))
		e.grounded = bool(it.get("grounded", false))
		if e.grounded:
			e._land()   # лежащий предмет — снова в реестре слияния
		e.queue_redraw()


## Закрыть инвентарь и журнал. Предмет «в руке» панели возвращается в инвентарь —
## поэтому перед сохранением (иначе он пропал бы из файла) и перед загрузкой.
static func close_windows() -> void:
	if UI.panel != null and UI.panel.visible:
		UI.panel.close()
	if UI.journal != null and UI.journal.visible:
		UI.journal.close()


# ------------------------------------------------------------------ ФАЙЛ

## Словарь → байты файла (заголовок + сжатые данные).
static func encode(d: Dictionary) -> PackedByteArray:
	var raw: PackedByteArray = var_to_bytes(d)
	var packed: PackedByteArray = raw.compress(FileAccess.COMPRESSION_ZSTD)
	var out: PackedByteArray = MAGIC.to_ascii_buffer()
	out.resize(HEADER_SIZE)
	out.encode_u32(4, VERSION)
	out.encode_u32(8, raw.size())
	out.append_array(packed)
	last_raw_size = raw.size()
	return out


## Байты файла → словарь ({} — файл не наш или повреждён, last_error — почему).
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < HEADER_SIZE or bytes.slice(0, 4).get_string_from_ascii() != MAGIC:
		last_error = "это не файл сохранения"
		return {}
	var ver: int = bytes.decode_u32(4)
	if ver > VERSION:
		last_error = "файл новее игры (версия %d)" % ver
		return {}
	var raw_size: int = bytes.decode_u32(8)
	var raw: PackedByteArray = bytes.slice(HEADER_SIZE).decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != raw_size:
		last_error = "файл повреждён"
		return {}
	var v = bytes_to_var(raw)
	if not (v is Dictionary):
		last_error = "файл повреждён"
		return {}
	return v


## Сохранить забег в слот. Пишем во временный файл и подменяем: оборванная
## запись не портит прежнее сохранение.
static func save_game(s: String = slot) -> bool:
	var t0: int = Time.get_ticks_usec()
	close_windows()
	var bytes: PackedByteArray = encode(gather())
	var path: String = path_for(s)
	var tmp: String = path + ".tmp"
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		last_error = "не открыть %s: %s" % [tmp, error_string(FileAccess.get_open_error())]
		return false
	f.store_buffer(bytes)
	f.close()
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		last_error = "нет доступа к user://"
		return false
	if dir.file_exists(path.get_file()):
		dir.remove(path.get_file())
	if dir.rename(tmp.get_file(), path.get_file()) != OK:
		last_error = "не переименовать %s" % tmp
		return false
	last_size = bytes.size()
	last_save_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	last_error = ""
	return true


## Загрузить забег из слота. false — файла нет или он не подходит.
static func load_game(s: String = slot) -> bool:
	if Net.is_online() and not _net_loading:   # СЕТЬ (ADR-002 § 4.9): F9 в сети выключена
		last_error = NET_LOAD_IN_MENU
		return false
	var t0: int = Time.get_ticks_usec()
	var path: String = path_for(s)
	if not FileAccess.file_exists(path):
		last_error = "сохранения нет"
		return false
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var d: Dictionary = decode(bytes)
	if d.is_empty() or not apply(d):
		return false
	last_load_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	return true


## Удалить слот (тесты и сценарии убирают за собой).
static func remove(s: String) -> void:
	var dir: DirAccess = DirAccess.open("user://")
	if dir != null and dir.file_exists(path_for(s).get_file()):
		dir.remove(path_for(s).get_file())


# ------------------------------------------------------------------ СЕТЬ (ADR-002, MP-C #88)
## Вход в сетевую игру (§ 4.2.2, D4): хост шлёт снимок Save.encode(gather_join())
## по каналу 0, клиент кладёт его в мир своего сида через apply_join(). Тот же
## словарь, что у F5, без раздела player — герой клиента свой (MP-D ставит героев).

## Хост: снимок мира для входа — всё, кроме героя.
static func gather_join() -> Dictionary:
	var d: Dictionary = gather()
	d.erase("player")
	d.erase("players")   # MP-I (#94): чужие инвентари клиенту не нужны
	d.erase("session")
	# Требование релея от N (#139) — только во входе: файл его не пишет.
	(d["game"] as Dictionary)["relay_req"] = Game.relay_req.duplicate()
	if Game.in_mission():   # ADR-004: глава кампании — клиенту марионеткой (Campaign.net_apply)
		d["mission"] = Game.mission.state()
	return d


## Клиент: снимок хоста поверх своего мира того же сида — apply() без героя и без
## пересчёта питания (у клиента update_power_budget молчит: машины — марионетки).
## false — снимок не подходит (last_error — почему).
static func apply_join(d: Dictionary) -> bool:
	var j: Dictionary = d.duplicate()
	j.erase("player")
	j.erase("players")
	return apply(j)


# ------------------------------------------------------------------ СЕТЬ (ADR-002 § 4.9, MP-I #94)
## Сохраняет только хост: F5 и автосохранение на каждом рассвете (NetCoop) в слот
## net_auto_slot(имя игры). У клиента F5 молчит с подсказкой (save_blocker), F9 в сети
## выключена у всех (load_game): загрузка — при создании игры (load_net, флаг --mp-load=).
## Версия 2: к словарю добавляются
##   session {name, max} и
##   players {uid: {nick, look, state = Player.save_state(), stats, dead}} —
## и подключённые (с героем хоста), и запаркованные (Net.parked). Раздел player остаётся
## (герой хоста): одиночная игра читает версию 2, беря только его, а файл версии 1
## в сети грузится как одиночный (без players). При загрузке у хоста герои на связи
## (и свой) получают своё по uid, остальные ждут в Net.parked до входа; незнакомый uid
## входит со стартовым набором.

const NET_HOST_SAVES: String = "сохраняет хост"
const MISSION_NO_SAVE: String = "в главе кампании сохранений нет — её можно начать заново"
const NET_LOAD_IN_MENU: String = "в сети загрузка — из меню при создании игры"

static var _net_loading: bool = false


## Слот автосохранения сетевой игры: mp_<имя игры>_auto (в имени — буквы и цифры).
static func net_auto_slot(session_name: String) -> String:
	var s: String = ""
	for i in session_name.length():
		var c: String = session_name[i]
		var u: int = c.unicode_at(0)
		var alnum: bool = (u >= 0x30 and u <= 0x39) or (u >= 0x41 and u <= 0x5A) \
				or (u >= 0x61 and u <= 0x7A) or (u >= 0x410 and u <= 0x44F) or u == 0x401 or u == 0x451
		s += c if alnum else "_"
	return "mp_%s_auto" % s


## Хост: загрузить сетевое сохранение (в обход запрета F9 в сети).
static func load_net(s: String) -> bool:
	_net_loading = true
	var res: bool = load_game(s)
	_net_loading = false
	return res


## Запись героя в players / Net.parked.
static func hero_entry(p) -> Dictionary:
	return {"nick": String(p.nick), "look": int(p.look), "state": p.save_state(),
			"stats": (p.net_stats as Dictionary).duplicate(true), "dead": bool(p.dead)}


static func _net_gather(d: Dictionary) -> void:
	if not Net.is_host():
		return
	d["session"] = {"name": String(Net.session.get("session_name", "")), "max": Net.max_players}
	var players: Dictionary = {}
	for uid in Net.parked:
		players[int(uid)] = (Net.parked[uid] as Dictionary).duplicate(true)
	for h in Game.players:
		if is_instance_valid(h) and int(h.net_uid) != 0:
			players[int(h.net_uid)] = hero_entry(h)
	d["players"] = players


static func _net_apply(d: Dictionary) -> void:
	if not Net.is_host() or not (d.get("players") is Dictionary):
		return
	var on_line: Dictionary = {}
	for h in Game.players:
		if is_instance_valid(h) and int(h.net_uid) != 0:
			on_line[int(h.net_uid)] = h
	Net.parked.clear()   # прежние парковки — из другого забега
	var players: Dictionary = d["players"]
	for uid in players:
		var e = players[uid]
		if not (e is Dictionary):
			continue
		if on_line.has(int(uid)):
			NetCoop.restore_hero(on_line[int(uid)], e)
		else:
			Net.parked[int(uid)] = (e as Dictionary).duplicate(true)


# ------------------------------------------------------------------ СПИСОК ДЛЯ МЕНЮ (#132)
## «Загрузить» в меню (одиночная игра и «Создать игру»): какие слоты есть и что в них.
## Слоты — по файлам user://save_*.sav; в тестовом прогоне видны только файлы этого
## процесса (TestEnv), в игре тестовые файлы не видны.

## Слоты на диске, без чтения файлов (меню решает, серая ли кнопка).
static func slots() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		return out
	var sfx: String = TestEnv.suffix()
	for f in dir.get_files():
		if not f.begins_with("save_") or not f.ends_with(".sav"):
			continue
		var s: String = f.substr(5, f.length() - 9)
		if sfx != "":
			if not s.ends_with(sfx):
				continue
			s = s.substr(0, s.length() - sfx.length())
		elif s.contains(TestEnv.MARK):
			continue
		if s != "":
			out.append(s)
	return out


## Что в слоте: {slot, time (unix, изменён), ok, error, seed, day, net, name, nicks,
## players}. Файл читается целиком (распаковка); ok = false — не наш или битый.
static func slot_info(s: String) -> Dictionary:
	var path: String = path_for(s)
	var info: Dictionary = {"slot": s, "time": FileAccess.get_modified_time(path), "ok": false,
			"error": "", "seed": 0, "day": 1, "net": false, "name": "",
			"nicks": PackedStringArray(), "players": 1}
	var err0: String = last_error   # список не портит причину последней операции F5/F9
	last_error = "сохранения нет"
	var d: Dictionary = decode(FileAccess.get_file_as_bytes(path)) if FileAccess.file_exists(path) else {}
	var why: String = last_error if d.is_empty() else ""
	last_error = err0
	if why == "" and int(d.get("version", 0)) <= 0:
		why = "файл повреждён"
	if why != "":
		info["error"] = why
		return info
	info["ok"] = true
	info["seed"] = int(d.get("seed", 0))
	var g = d.get("game", {})
	info["day"] = int(g.get("day_number", 1)) if g is Dictionary else 1
	var pl = d.get("players")
	if pl is Dictionary and not (pl as Dictionary).is_empty():
		info["net"] = true
		var nicks: PackedStringArray = PackedStringArray()
		for uid in pl:
			var e = pl[uid]
			if e is Dictionary:
				nicks.append(String(e.get("nick", "?")))
		info["nicks"] = nicks
		info["players"] = (pl as Dictionary).size()
	var ses = d.get("session", {})
	if ses is Dictionary:
		info["name"] = String(ses.get("name", ""))
	return info


## Все сохранения для меню: новые сверху.
static func list_saves() -> Array:
	var out: Array = []
	for s in slots():
		out.append(slot_info(s))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if int(a["time"]) != int(b["time"]):
				return int(a["time"]) > int(b["time"])
			return String(a["slot"]) < String(b["slot"]))
	return out


## «Продолжить» в меню (#119): самое новое (по времени файла) читаемое одиночное
## сохранение — {} если такого нет. Файлы читаются по одному от новых, пока не найдётся
## подходящий (обычно — один: слот F5, куда пишет и «Сохранить и выйти в меню»).
static func latest_single() -> Dictionary:
	var order: Array = []
	for s in slots():
		order.append([FileAccess.get_modified_time(path_for(s)), s])
	order.sort_custom(func(a: Array, b: Array) -> bool:
			if int(a[0]) != int(b[0]):
				return int(a[0]) > int(b[0])
			return String(a[1]) < String(b[1]))
	for e in order:
		var info: Dictionary = slot_info(String(e[1]))
		if bool(info["ok"]) and not bool(info["net"]):
			return info
	return {}
