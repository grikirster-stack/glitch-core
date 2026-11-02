extends SceneTree
## Картинки для иллюстрированного справочника README (#46): иконки, тайлы,
## вид объектов в мире и скриншоты игры — всё в docs/img/.
##
## Запуск:
##   1) иконки предметов и тайлы — без окна:
##      godot --headless --path . --script res://tools/gallery_dump.gd -- --seed=31337
##   2) вид в мире (_draw) и скриншоты — headless не рендерит, нужен короткий
##      прогон с окном ЗА ПРЕДЕЛАМИ ЭКРАНА и без звука; скрипт сам выходит:
##      godot --path . --audio-driver Dummy --windowed --position -10000,-10000 \
##            --resolution 960x540 --script res://tools/gallery_dump.gd -- --seed=31337
##
## Всё перебирается по данным, поэтому инструмент можно перезапускать, когда
## появятся новые объекты:
##  * предметы — DB.item_defs, тайлы — DB.tile_defs (имя файла — ключ IDs.I / IDs.T);
##  * машины — ветки match в MachineBase.place_machine (скрипт читает исходник
##    machine_base.gd) плюс все "machine:<вид>" из DB.item_defs: вид без ветки
##    в match печатается как «ещё нет в place_machine» и пропускается;
##  * фантомы — Balance.PHANTOMS: если у фантома есть поле типа (#27), снимается
##    каждый тип, иначе — один базовый фантом и строка «типов в коде ещё нет».
## В конце печатается сводка для таблиц README (строки «MD|»): откуда берётся
## предмет — рецепты, тайлы, тайники руин.
##
## В режиме --script имена автозагрузок на этапе компиляции недоступны, поэтому
## узлы берутся через get_node(), а скрипты — через load() (tools/README_TESTS.md).
## В docs/img/ лежит .gdignore: Godot не импортирует эти PNG и не плодит .import.

const OUT: String = "res://docs/img/"
## Увеличение пиксельных картинок (иконки 16×16, тайлы 16×16), nearest.
const PIXEL_SCALE: int = 6
## Увеличение объектов, нарисованных через _draw().
const DRAW_SCALE: float = 4.0
## Прогон с окном не дольше этого, с: потом выходим, что бы ни случилось.
const HARD_LIMIT: float = 18.0
## Кадр скриншота-«места» — центральная часть окна этого размера.
const CROP: Vector2i = Vector2i(480, 270)

## Названия станций для сводки.
const STATION_NAMES: Dictionary = {"hand": "руками", "smelter": "плавильня", "assembler": "сборщик"}
## Поля «работает» для любой машины (что есть у узла — то и выставляется).
const STATE_ON: Dictionary = {"powered": true, "power_active": true, "enabled": true,
		"efficiency": 1.0, "progress": 0.6}
## Поля «стоит / без питания».
const STATE_OFF: Dictionary = {"powered": false, "power_active": false, "efficiency": 0.0,
		"progress": 0.0}
## Доп. поля по виду машины: что сделать, чтобы состояние было видно на картинке.
## Предметы задаются id, поэтому словарь собирается в _machine_extra().

var scene: Node = null
var db: Node = null
var world: Node = null
var game: Node = null
var ui: Node = null
var tech: Node = null
var windowed: bool = false
var saved: int = 0
var _elapsed: float = 0.0
var _vp: SubViewport = null
var _holder: Node2D = null
var _rev_items: Dictionary = {}
var _rev_tiles: Dictionary = {}


func _initialize() -> void:
	windowed = DisplayServer.get_name() != "headless"
	if windowed:
		# Окно не должно забирать фокус у пользователя (оно и так за экраном).
		root.set_flag(Window.FLAG_NO_FOCUS, true)
		root.position = Vector2i(-10000, -10000)
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	scene = main_scene.instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > HARD_LIMIT:
		push_error("gallery_dump: превышен лимит %.0f с — выходим" % HARD_LIMIT)
		print("ИТОГ: прервано по времени, сохранено PNG: %d" % saved)
		quit(2)
	return false


func _run() -> void:
	db = root.get_node("DB")
	world = root.get_node("World")
	game = root.get_node("Game")
	ui = root.get_node("UI")
	tech = root.get_node("Tech")
	for k in IDs.I.keys():
		_rev_items[int(IDs.I[k])] = String(k).to_lower()
	for k in IDs.T.keys():
		_rev_tiles[int(IDs.T[k])] = String(k).to_lower()
	for sub in ["items", "tiles", "world", "shots"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + sub))
	# В сценарном режиме волны фантомов не идут: кадры детерминированы.
	scene.set("scenario_mode", true)
	game.set("scenario_mode", true)

	_dump_items()
	_dump_tiles()
	_print_md()
	if windowed:
		await _dump_world_views()
		await _dump_shots()
	else:
		print("headless: вид в мире и скриншоты пропущены (нужен прогон с окном за экраном)")
	print("ИТОГ: сохранено PNG: %d" % saved)
	quit(0)


# ------------------------------------------------------------------ ПИКСЕЛИ

func _save(img: Image, rel: String) -> void:
	var path: String = ProjectSettings.globalize_path(OUT + rel)
	var err: int = img.save_png(path)
	if err != OK:
		push_error("не сохранён %s (код %d)" % [rel, err])
		return
	saved += 1


func _upscale(img: Image, k: int) -> Image:
	var out: Image = img.duplicate()
	if out.is_compressed():
		out.decompress()
	out.convert(Image.FORMAT_RGBA8)
	out.resize(out.get_width() * k, out.get_height() * k, Image.INTERPOLATE_NEAREST)
	return out


## Иконка предмета: та же текстура, что в инвентаре (DB.item_texture). Если
## рендер-сервер без картинки (headless), рисуем тем же кодом, тем же сидом.
func _item_image(id: int) -> Image:
	var tex: Texture2D = db.item_texture(id)
	var img: Image = tex.get_image() if tex != null else null
	if img == null or img.is_empty():
		img = Image.create_empty(db.TILE_SIZE, db.TILE_SIZE, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = 4242 + id * 131
		var def: Dictionary = db.item_def(id)
		db._paint_item(img, String(def.get("shape", "lump")), def.get("color", Color.MAGENTA), rng)
	return img


func _tile_image(id: int) -> Image:
	var ts: int = db.TILE_SIZE
	var atlas: Image = db.atlas_texture.get_image() if db.atlas_texture != null else null
	if atlas != null and not atlas.is_empty():
		var a: Vector2i = db.atlas_of_tile.get(id, Vector2i.ZERO)
		return atlas.get_region(Rect2i(a.x * ts, a.y * ts, ts, ts))
	var img: Image = Image.create_empty(ts, ts, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	db._paint_tile(img, id, 0, 0)
	return img


func _dump_items() -> void:
	var ids: Array = db.item_defs.keys()
	ids.sort()
	for id in ids:
		if int(id) == IDs.I.NONE:
			continue
		_save(_upscale(_item_image(int(id)), PIXEL_SCALE), "items/%s.png" % _item_slug(int(id)))
	print("иконок предметов: %d" % (ids.size() - 1))


func _dump_tiles() -> void:
	var ids: Array = db.tile_defs.keys()
	ids.sort()
	for id in ids:
		if int(id) == IDs.T.AIR:
			continue
		_save(_upscale(_tile_image(int(id)), PIXEL_SCALE), "tiles/%s.png" % _tile_slug(int(id)))
	print("тайлов: %d" % (ids.size() - 1))


func _item_slug(id: int) -> String:
	return String(_rev_items.get(id, "item_%d" % id))


func _tile_slug(id: int) -> String:
	return String(_rev_tiles.get(id, "tile_%d" % id))


# ------------------------------------------------------------------ СВОДКА

## Строки «MD|» — сырьё для таблиц README: откуда берётся каждый предмет.
func _print_md() -> void:
	var roles: Dictionary = {}   ## id -> [роль, ...] из тайников руин
	var loot: Dictionary = world.get("RUIN_LOOT")
	for role in loot.keys():
		for e in loot[role]:
			var arr: Array = roles.get(int(e[0]), [])
			arr.append(String(role))
			roles[int(e[0])] = arr
	var ids: Array = db.item_defs.keys()
	ids.sort()
	print("MD|== Предметы: id | файл | имя | стак | ставится | откуда ==")
	for id in ids:
		if int(id) == IDs.I.NONE:
			continue
		var src: PackedStringArray = PackedStringArray()
		for tid in db.tile_defs.keys():
			if int(db.tile_drop(int(tid))) == int(id):
				src.append("тайл «%s» (%.1f с)" % [db.tile_name(int(tid)), db.tile_hard(int(tid))])
		for r in db.recipes:
			if int(r["out"]) != int(id):
				continue
			var parts: PackedStringArray = PackedStringArray()
			for k in r["in"].keys():
				parts.append("%d %s" % [int(r["in"][k]), db.item_name(int(k))])
			src.append("%s: %s → %d за %.1f с [%s]" % [STATION_NAMES.get(String(r["station"]), r["station"]),
					" + ".join(parts), int(r["amount"]), float(r["time"]), String(r.get("tech", "T0"))])
		if roles.has(int(id)):
			src.append("тайники: " + ", ".join(PackedStringArray(roles[int(id)])))
		print("MD|%d | items/%s.png | %s | %d | %s | %s" % [int(id), _item_slug(int(id)), db.item_name(int(id)),
				db.item_max_stack(int(id)), db.item_place(int(id)), "; ".join(src)])
	print("MD|== Тайлы: id | файл | имя | твёрдый | копка, с | дроп | свет | роет копатель ==")
	var tids: Array = db.tile_defs.keys()
	tids.sort()
	for tid in tids:
		if int(tid) == IDs.T.AIR:
			continue
		var d: Dictionary = db.tile_def(int(tid))
		print("MD|%d | tiles/%s.png | %s | %s | %.1f | %s | %.2f | %s" % [int(tid), _tile_slug(int(tid)), d["name"],
				"да" if d["solid"] else "нет", float(d["hard"]),
				db.item_name(int(d["drop"])) if int(d["drop"]) != 0 else "—", float(d["light"]),
				"да" if d.get("dig", false) else "нет"])
	print("MD|== Машины: вид | класс | скрипт ==")
	var kinds: Dictionary = _machine_kinds()
	for k in kinds.keys():
		print("MD|%s | %s" % [k, kinds[k] if kinds[k] != "" else "ещё нет в place_machine"])
	print("MD|== Мир этого сида ==")
	print("MD|терминалов: %d, руин с тайником: %d, вентиляций: %d, релей: %s" % [world.terminals.size(),
			world.get("ruin_caches").size(), world.vents.size(), str(world.beacon_cell)])
	print("MD|== Фантомы (Balance.PHANTOMS) ==")
	for t in Balance.PHANTOMS.keys():
		print("MD|%s | %s" % [t, str(Balance.PHANTOMS[t])])


# ------------------------------------------------------------------ МАШИНЫ

## Вид машины -> путь к скрипту ("" — предмет есть, ветки в place_machine нет).
## Ветки match читаются прямо из исходника machine_base.gd: новый вид машины
## попадёт в галерею без правки этого файла.
func _machine_kinds() -> Dictionary:
	var classes: Dictionary = {}
	for c in ProjectSettings.get_global_class_list():
		classes[String(c["class"])] = String(c["path"])
	var src: String = FileAccess.get_file_as_string("res://scripts/machines/machine_base.gd")
	var re: RegEx = RegEx.new()
	re.compile("\"(\\w+)\":\\s*\\n\\s*m = (\\w+)\\.new\\(\\)")
	var out: Dictionary = {}
	for m in re.search_all(src):
		out[m.get_string(1)] = String(classes.get(m.get_string(2), ""))
	for id in db.item_defs.keys():
		var place: String = db.item_place(int(id))
		if place.begins_with("machine:") and not out.has(place.substr(8)):
			out[place.substr(8)] = ""
	return out


## Что ещё выставить машине, чтобы состояние читалось на картинке.
func _machine_extra(kind: String, on: bool) -> Dictionary:
	match kind:
		"CoalGen":
			return {"fuel": Balance.COAL_BURN * 0.7} if on else {"fuel": 0.0}
		"Analyzer":
			return {"_busy": true, "crystals": 4} if on else {"crystals": 2}
		"Inserter":
			return {"held": IDs.I.IRON_ORE, "progress": 0.5} if on else {}
		"Belt":
			return {"items": [{"id": IDs.I.COPPER_ORE, "count": 1, "pos": 0.55}]}
		"Drill", "DeepDrill":
			return {"_spin": 0.5}
	return {}


func _apply(node: Object, fields: Dictionary) -> void:
	for k in fields.keys():
		if String(k) in node:
			node.set(String(k), fields[k])


# ------------------------------------------------------------------ ВИД В МИРЕ

func _ensure_vp() -> void:
	if _vp != null:
		return
	_vp = SubViewport.new()
	_vp.transparent_bg = false        ## тёмный фон как у игры (default_clear_color)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(_vp)
	_holder = Node2D.new()
	_vp.add_child(_holder)


## Снимает узел в отдельном SubViewport: size — кадр в пикселях, center — где
## в кадре точка (0, 0) узла (в мировых px до увеличения); post — поля, которые
## узел сам перезаписывает в _ready (их ставим после добавления в кадр).
func _shoot_node(node: Node2D, rel: String, size: Vector2i, center: Vector2,
		post: Dictionary = {}) -> void:
	_ensure_vp()
	for c in _holder.get_children():
		_holder.remove_child(c)
		c.queue_free()
	_vp.size = size
	_holder.scale = Vector2(DRAW_SCALE, DRAW_SCALE)
	_holder.position = Vector2(size) * 0.5 - center * DRAW_SCALE
	_holder.add_child(node)
	# У игрока в _ready своя камера — в кадре она не нужна.
	var cam = node.get("camera")
	if cam is Camera2D:
		cam.enabled = false
	_apply(node, post)
	# Объект только рисуется: логика (бур копает мир, фантом бегает) не нужна.
	node.set_process(false)
	node.set_physics_process(false)
	node.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = _vp.get_texture().get_image()
	_check_and_save(img, rel)


func _check_and_save(img: Image, rel: String) -> void:
	if img == null or img.is_empty():
		push_error("пустой кадр: %s" % rel)
		return
	# Сплошной цвет = ничего не нарисовалось.
	var c0: Color = img.get_pixel(0, 0)
	var differs: bool = false
	for y in range(0, img.get_height(), 3):
		for x in range(0, img.get_width(), 3):
			if not img.get_pixel(x, y).is_equal_approx(c0):
				differs = true
				break
		if differs:
			break
	if not differs:
		push_error("кадр сплошного цвета: %s" % rel)
	_save(img, rel)


func _dump_world_views() -> void:
	var kinds: Dictionary = _machine_kinds()
	var n: int = 0
	for kind in kinds.keys():
		var path: String = String(kinds[kind])
		if path == "":
			print("машина %s: ещё нет в place_machine — пропуск" % kind)
			continue
		var scr: GDScript = load(path)
		var probe: Node2D = scr.new()
		var two: bool = probe.consumes_power() or float(probe.get("power_radius")) > 0.0
		probe.free()
		for on in ([true, false] if two else [true]):
			var m: Node2D = scr.new()
			m.set("kind", kind)
			_apply(m, STATE_ON if on else STATE_OFF)
			_apply(m, _machine_extra(kind, on))
			var suffix: String = ("_on" if on else "_off") if two else ""
			await _shoot_node(m, "world/%s%s.png" % [kind.to_snake_case(), suffix], Vector2i(128, 128), Vector2(0, 1))
			n += 1
	print("машин в мире: %d кадров" % n)

	# Игрок: обычный и в вентиляции.
	var player_scr: GDScript = load("res://scripts/entities/player.gd")
	for hiding in [false, true]:
		var p: Node2D = player_scr.new()
		p.set("hiding", hiding)
		await _shoot_node(p, "world/player%s.png" % ("_hiding" if hiding else ""), Vector2i(128, 160), Vector2(0, -4))

	# Фантомы: типы из Balance.PHANTOMS, если фантом уже знает своё поле типа (#27).
	var ph_scr: GDScript = load("res://scripts/entities/phantom.gd")
	var st: Dictionary = ph_scr.get_script_constant_map().get("St", {})
	var probe_ph: Node2D = ph_scr.new()
	var type_field: String = ""
	for f in ["type", "ptype", "phantom_type", "kind"]:
		if f in probe_ph:
			type_field = f
			break
	probe_ph.free()
	var types: Array = Balance.PHANTOMS.keys() if type_field != "" else [""]
	if type_field == "":
		print("фантомы: поля типа ещё нет (#27) — снимаю базового, типов в Balance.PHANTOMS: %d" % Balance.PHANTOMS.size())
	# jitter фантом берёт случайный в _ready; 0.1 — визор светится, копии разъехались.
	var ph_states: Dictionary = {
		"roam": {"state": int(st.get("ROAM", 1)), "facing": -1, "jitter": 0.1},
		"chase": {"state": int(st.get("CHASE", 2)), "facing": -1, "jitter": 0.1},
		"stun": {"state": int(st.get("ROAM", 1)), "stun": 2.0, "hp": 60.0, "facing": -1, "jitter": 0.1},
	}
	for t in types:
		for sname in ph_states.keys():
			var ph: Node2D = ph_scr.new()
			if type_field != "":
				ph.set(type_field, t)
			var tag: String = ("_" + String(t)) if String(t) != "" else ""
			await _shoot_node(ph, "world/phantom%s_%s.png" % [tag, sname], Vector2i(128, 160), Vector2(0, -4),
					ph_states[sname])

	# Предмет на земле (стопка из 5 — видно счётчик).
	var item_scr: GDScript = load("res://scripts/entities/item_entity.gd")
	var it: Node2D = item_scr.new()
	it.set("item_id", IDs.I.IRON_ORE)
	it.set("count", 5)
	await _shoot_node(it, "world/item_drop.png", Vector2i(96, 96), Vector2(0, -1))


# ------------------------------------------------------------------ СКРИНШОТЫ

func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _grab(rel: String, crop: bool) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if crop:
		var sz: Vector2i = img.get_size()
		var r: Rect2i = Rect2i((sz - CROP) / 2, CROP)
		img = img.get_region(r)
	_check_and_save(img, rel)


## Ставит камеру игрока на точку мира: игрок без физики, видимый или нет;
## zoom — увеличение камеры (в игре 2.2).
func _look_at(pos: Vector2, show_player: bool, zoom: float = 2.2) -> void:
	var p: Node2D = scene.get("player")
	p.set_physics_process(false)
	p.global_position = pos
	p.visible = show_player
	p.queue_redraw()
	var cam: Camera2D = p.get("camera")
	cam.zoom = Vector2(zoom, zoom)
	cam.reset_smoothing()
	await _frames(3)
	cam.reset_smoothing()
	await _frames(3)


func _dump_shots() -> void:
	var p: Node2D = scene.get("player")
	var spawn: Vector2 = world.get("spawn_point")
	var tile: float = float(world.TILE)
	ui.get("hud").set("notes", [])

	# 1. Стартовая база днём (с подсказкой управления, как в первые секунды игры).
	game.set("time_of_day", 0.40)
	await _look_at(spawn + Vector2(0, -3), true)
	await _frames(10)
	await _grab("shots/base_day.png", false)
	game.set("game_time", 30.0)           ## дальше подсказка управления не нужна

	# 2. Копка за пределами базы: кирка, полоса прогресса, выпавший предмет.
	var dx: int = int(world.beacon_cell.x) - 21
	var dig: Vector2i = Vector2i(dx, int(world.surface[dx]))
	var stand: Vector2i = Vector2i(dx + 1, int(world.surface[dx + 1]) - 1)
	await _look_at(world.cell_to_world(stand) + Vector2(0, -3), true, 3.0)
	p.set("facing", -1)
	p.set("mining_cell", dig)
	p.set("mining_progress", 0.6)
	var drop_scr: GDScript = load("res://scripts/entities/item_entity.gd")
	var drop: Node2D = drop_scr.new()
	drop.set("item_id", IDs.I.SCRAP)
	drop.set("count", 3)
	drop.global_position = world.cell_to_world(stand + Vector2i(2, 0)) + Vector2(0, 1)
	world.add_world_node(drop)
	drop.set_physics_process(false)
	p.queue_redraw()
	await _frames(4)
	await _grab("shots/mining.png", true)
	p.set("mining_cell", Vector2i(-1, -1))
	p.set("mining_progress", 0.0)
	p.queue_redraw()
	drop.queue_free()

	# 3. Маленькая фабрика справа от базы: ТЭЦ + бур + конвейер + плавильня + сундук.
	var bx: int = world.beacon_cell.x
	var row: int = int(world.surface[bx + 14]) - 1
	for y in range(row + 1, row + 17):
		world.set_tile(bx + 13, y, IDs.T.IRON_ORE)   ## под буром — железная жила
	var mb: GDScript = load("res://scripts/machines/machine_base.gd")
	mb.place_machine("Drill", Vector2i(bx + 13, row))
	mb.place_machine("Belt", Vector2i(bx + 14, row))
	mb.place_machine("Smelter", Vector2i(bx + 15, row))
	mb.place_machine("Belt", Vector2i(bx + 16, row))
	mb.place_machine("Chest", Vector2i(bx + 17, row))
	mb.place_machine("CoalGen", Vector2i(bx + 15, row - 1))
	var gen = world.machines.get(Vector2i(bx + 15, row - 1))
	if gen != null:
		gen.add_fuel(6)
	var smelter = world.machines.get(Vector2i(bx + 15, row))
	if smelter != null:
		smelter.receive_item(IDs.I.IRON_ORE, 3)
	var belt = world.machines.get(Vector2i(bx + 16, row))
	if belt != null:
		belt.add_item(IDs.I.IRON_INGOT, 1)
	p.visible = true
	await _look_at(world.cell_to_world(Vector2i(bx + 15, row - 1)), false, 3.0)
	ui.get("world_fx").set("show_power", true)
	await _frames(70)                     ## ~1 с: бур, лента и горн в работе
	await _grab("shots/factory.png", false)
	ui.get("world_fx").set("show_power", false)

	# 4. Инвентарь и крафт: немного добра, вкладка «Ручной крафт».
	var inv = p.get("inv")
	for e in [[IDs.I.STONE, 14], [IDs.I.SCRAP, 9], [IDs.I.IRON_ORE, 6], [IDs.I.COPPER_INGOT, 3], [IDs.I.SAND, 4]]:
		inv.add(int(e[0]), int(e[1]))
	await _look_at(spawn + Vector2(0, -3), true)
	ui.toggle_inventory()
	await _frames(4)
	await _grab("shots/inventory.png", false)
	game.set("research", 7)                ## хватает на T1 — кнопка «Открыть» активна
	ui.get("panel").set("station_tab", 3)   ## вкладка «Исследования»
	ui.get("panel").queue_redraw()
	await _frames(3)
	await _grab("shots/research.png", false)
	ui.get("panel").close()

	# 5. Журнал J: две прочитанные главы и обрывок.
	tech.read_chapter(0)
	tech.read_chapter(1)
	var lore: Node = root.get_node("Lore")
	if lore.has_method("fragment_count") and int(lore.fragment_count()) > 0:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = 7
		tech.add_fragment(String(lore.fragment_at(0, rng)))
	ui.get("hud").set("notes", [])
	ui.toggle_journal()
	await _frames(4)
	await _grab("shots/journal.png", false)
	ui.get("journal").close()

	# 6. Ночь и фантом рядом с базой.
	game.set("time_of_day", 0.80)
	ui.get("hud").set("notes", [])
	await _look_at(spawn + Vector2(0, -3), true, 3.0)
	var ph_scr: GDScript = load("res://scripts/entities/phantom.gd")
	var ph: Node2D = ph_scr.new()
	scene.add_child(ph)
	ph.set_physics_process(false)
	ph.global_position = spawn + Vector2(2.5 * tile, -3)
	ph.set("state", int(ph_scr.get_script_constant_map()["St"]["CHASE"]))
	ph.set("facing", -1)
	ph.set("jitter", 0.1)
	await _frames(8)
	await _grab("shots/night_phantom.png", false)
	ph.queue_free()

	# Места мира — центральные кадры 480×270.
	game.set("time_of_day", 0.40)
	# Руина с тайником и табличкой: первая не под водой.
	for c in world.get("ruin_caches"):
		var cc: Vector2i = c["cell"]
		if world.get_tile(cc.x, cc.y - 1) == IDs.T.WATER or world.get_tile(cc.x, cc.y) == IDs.T.WATER:
			continue
		var mid: Vector2 = (world.cell_to_world(c["sign_cell"]) + world.cell_to_world(cc)) * 0.5
		await _look_at(mid + Vector2(0, tile), false)
		await _frames(30)                 ## табличка проявляет имя при подходе
		await _grab("shots/place_ruin.png", true)
		break
	# Терминал и релей-ядро на базе.
	await _look_at(world.cell_to_world(world.terminals[0]) + Vector2(0, -tile), false, 3.5)
	await _grab("shots/place_terminal.png", true)
	await _look_at(world.cell_to_world(world.beacon_cell) + Vector2(0, -tile), false, 3.5)
	await _grab("shots/place_relay.png", true)
	# Вентиляция под землёй (не та, что у базы) и игрок в ней.
	var vents: Array = world.get("vents")
	var vent: Vector2i = vents[0]
	for v in vents:
		if int(v.y) >= int(world.surface[v.x]) + 6:
			vent = v
			break
	print("вентиляций: %d, в кадре %s" % [vents.size(), str(vent)])
	await _look_at(world.cell_to_world(vent) + Vector2(0, -3), true, 3.0)
	p.set("hiding", true)
	p.queue_redraw()
	await _frames(3)
	await _grab("shots/place_vent.png", true)
	p.set("hiding", false)
	# Вода и лава: первые подходящие клетки мира.
	var water: Vector2i = _find_tile(IDs.T.WATER, 0)
	if water.x >= 0:
		await _look_at(world.cell_to_world(water + Vector2i(0, 1)), false)
		await _grab("shots/place_water.png", true)
	var lava: Vector2i = _find_tile(IDs.T.LAVA, 120)
	if lava.x >= 0:
		await _look_at(world.cell_to_world(lava), false, 3.0)
		await _grab("shots/place_lava.png", true)
	# Кристальный биом / руда глубоко: кадр с кристаллами.
	var crys: Vector2i = _find_tile(IDs.T.CRYSTAL_ORE, 60)
	if crys.x >= 0:
		await _look_at(world.cell_to_world(crys), false)
		await _grab("shots/place_deep_ore.png", true)


## Первая клетка с тайлом id не выше строки min_y, подальше от краёв мира.
func _find_tile(id: int, min_y: int) -> Vector2i:
	var w: int = int(world.W)
	var h: int = int(world.H)
	for x in range(40, w - 40, 3):
		for y in range(min_y, h):
			if world.get_tile(x, y) == id:
				return Vector2i(x, y)
	return Vector2i(-1, -1)
