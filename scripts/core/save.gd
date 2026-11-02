class_name Save
extends RefCounted
## Сохранение и загрузка забега (ADR-001 § 5.3, PR-N, #37). F5 — сохранить,
## F9 — загрузить (UI). Один слот по умолчанию: user://save_1.sav.
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
const VERSION: int = 1
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


static func path_for(s: String) -> String:
	return "user://save_%s.sav" % s


static func exists(s: String = slot) -> bool:
	return FileAccess.file_exists(path_for(s))


## Почему сейчас нельзя сохраниться (пустая строка — можно).
static func save_blocker() -> String:
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
	return d


## Предметы на земле (и мешок после смерти) в порядке узлов сцены.
static func _items_state() -> Array:
	var out: Array = []
	for e in _item_nodes():
		out.append({
			"id": e.item_id, "count": e.count, "pos": e.global_position, "vel": e.vel,
			"grounded": e.grounded, "age": e.age, "despawn": e.despawn,
			"pickup_delay": e.pickup_delay, "bag": e.bag.duplicate(true),
		})
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
	_place_items(d.get("items", []))
	var p = Game.player
	if p != null and is_instance_valid(p) and d.has("player"):
		p.load_state(d["player"])
	Game.load_state(d.get("game", {}))
	Tech.load_state(d.get("tech", {}))
	Threat.load_state(d.get("threat", {}))
	# Питание — сразу, не через 0.25 с: машины с первого кадра в том же режиме.
	Game.update_power_budget()
	# Свет машин (прожекторы, #31) — по новому питанию, через World.add_light_source.
	for m in World.machines.values():
		if m.has_method("relight"):
			m.relight()
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


static func _place_items(list: Array) -> void:
	for it in list:
		if not (it is Dictionary):
			continue
		var e: ItemEntity = ItemEntity.new()
		e.item_id = int(it.get("id", IDs.I.NONE))
		e.count = int(it.get("count", 1))
		e.despawn = bool(it.get("despawn", true))
		e.bag = Array(it.get("bag", [])).duplicate(true)
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
	return d


## Клиент: снимок хоста поверх своего мира того же сида — apply() без героя и без
## пересчёта питания (у клиента update_power_budget молчит: машины — марионетки).
## false — снимок не подходит (last_error — почему).
static func apply_join(d: Dictionary) -> bool:
	var j: Dictionary = d.duplicate()
	j.erase("player")
	return apply(j)
