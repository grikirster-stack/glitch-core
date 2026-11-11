class_name MachineBase
extends Node2D
## Базовый класс построек: приём/выдача предметов и прочность.
##
## Питание снято (#170, ADR-005 § 7): машины не спрашивают ток и не замедляются.
## Готовое отдаётся соседнему сундуку, иначе падает на землю.

## Машины, чья отрисовка зависит от времени (пламя горелки):
## им нужна перерисовка каждый кадр.
const TIME_ANIMATED: Array[String] = ["Burner"]
## Шанс, что разрушенная машина оставит свой предмет (§ 4.4).
const DESTROY_DROP_CHANCE: float = 0.5
## Сколько осколков разлетается при разрушении.
const DESTROY_CHIPS: int = 4

## Машина разрушена (до удаления из мира). Для угрозы/HUD/звука.
signal destroyed(machine: MachineBase)

var cell: Vector2i = Vector2i.ZERO
var kind: String = ""
## Наработка: секунды полезной работы (см. work()). Питания больше нет (#170).
var work_time: float = 0.0
var hp: float = Balance.MACHINE_HP
var max_hp: float = Balance.MACHINE_HP
var progress: float = 0.0
var anim: float = 0.0
var _last_progress: float = 0.0
var _destroyed: bool = false
## Готовое, ещё не отданное (id -> count). deliver() кладёт его в сундук или на землю.
var _output: Dictionary = {}
var _output_count: int = 0
## Направление постройки: 0 — вправо, 1 — вниз, 2 — влево, 3 — вверх (как у конвейера).
## Поворачивается ПКМ или тапом, только если can_turn (ADR-005 § 4).
## Горелка и зеркало ходят по восьми: 4–7 — диагонали (DIR в Beams). Остальные
## машины по-прежнему на четвертях: turn() смотрит turn_steps.
var dir: int = 0
var can_turn: bool = false
## Сколько положений у turn(). 4 — четверть оборота. 8 — ещё и диагонали, шаг 45°.
var turn_steps: int = 4
## Неразборная постройка: её нельзя снять и вернуть в инвентарь (постройки
## кампании, тайники руин). Ставится кодом мира, не игроком.
var permanent: bool = false


static func place_machine(p_kind: String, c: Vector2i) -> bool:
	if World.machines.has(c):
		return false
	if World.get_tile_v(c) != IDs.T.AIR:
		return false
	var m: MachineBase = null
	match p_kind:
		"Chest":
			m = Chest.new()
		# --- Свет (ADR-005, #164) ---
		"Burner":
			m = Burner.new()
		# --- Маяк (ADR-005 § 5, #167) ---
		"Pharos":
			m = Pharos.new()
		# --- Оптика (ADR-005 § 4, #165) ---
		"Mirror":
			m = Mirror.new()
		"Mixer":
			m = Mixer.new()
		"Prism":
			m = Prism.new()
		# --- Коллектор и накопитель (ADR-005 § 4, #166) ---
		"Collector":
			m = Collector.new()
		"Accumulator":
			m = Accumulator.new()
		_:
			# Старый сейв: бур, лента, ТЭЦ и прочие снятые машины (#170).
			return false
	m.cell = c
	m.kind = p_kind
	m.global_position = World.cell_to_world(c)
	m.position = m.global_position
	World.machines[c] = m
	World.add_world_node(m)
	if World.beams != null:
		World.beams.note_machines()
	return true


func _process(delta: float) -> void:
	# Питания нет (#170): каждая постройка работает на полной скорости.
	work(delta)
	# Затухание вспышки анимации (например, после добычи).
	if anim > 0.0:
		anim = maxf(0.0, anim - delta * 2.0)
		queue_redraw()
	if progress != _last_progress:
		_last_progress = progress
		queue_redraw()
	if has_time_animation():
		queue_redraw()


## Один шаг по часовой: четверть оборота или 45°, если turn_steps = 8.
## Один вызов — один поворот; «один поворот на нажатие» обеспечивает игрок.
func turn() -> void:
	var n: int = turn_steps if turn_steps > 1 else 4
	dir = (dir + 1) % n
	queue_redraw()
	_on_turned()


## Хук наследника: направление изменилось (пересчитать луч, зеркало и т. п.).
func _on_turned() -> void:
	if World.beams != null:
		World.beams.mark_dirty()


## Постройка пропускает или преобразует луч (зеркало, смеситель, призма).
## База и горелка гасят: у них флаг выключен, Beams пишет в клетку код 1.
var beam_passer: bool = false


## Что луч делает, попав в эту постройку. in_dir — откуда пришёл (0 вправо …),
## color — маска Beams. Возвращает выходы [[out_dir, color], ...].
## База луч гасит. Зеркало, смеситель и призма переопределяют и поднимают beam_passer.
func beam_pass(_in_dir: int, _color: int) -> Array:
	return []


## Полезная работа за кадр. Питания нет (#170): работа идёт на полной скорости.
func work(delta: float) -> float:
	work_time += delta
	return delta


## Зависит ли отрисовка от времени (тогда нужна перерисовка каждый кадр).
func has_time_animation() -> bool:
	return kind in TIME_ANIMATED


## Принимает предмет. Возвращает количество, которое НЕ принято (0 — принято всё).
func receive_item(item_id: int, count: int) -> int:
	return count


func input_accepts(item_id: int) -> bool:
	return false


## Отдаёт предмет соседнему сундуку. Не влезло — на землю (#170).
func deliver(item_id: int, count: int) -> void:
	var left: int = count
	for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		var n = World.machines.get(cell + d)
		if n is Chest:
			left = n.receive_item(item_id, left)
			if left <= 0:
				return
	if left > 0:
		spawn_item(item_id, left, global_position + Vector2(0.0, -4.0))


func spawn_item(item_id: int, count: int, pos: Vector2) -> void:
	var e: ItemEntity = ItemEntity.new()
	e.item_id = item_id
	e.count = count
	e.global_position = pos
	e.z_index = 4
	World.add_world_node(e)


# ------------------------------------------------------------- ПРОЧНОСТЬ (§ 4.4)

## Получить урон. При hp <= 0 машина разрушается.
func take_damage(amount: float) -> void:
	if not Net.is_authority():   # СЕТЬ (ADR-002): прочность считает хост
		return
	if _destroyed or amount <= 0.0:
		return
	# Голубой купол (#168): удар по постройке в радиусе маяка идёт в dome_hp.
	var dome = World.dome_at(cell)
	if dome != null and dome.has_method("absorb_dome"):
		dome.absorb_dome(amount)
		anim = 1.0
		queue_redraw()
		return
	hp = maxf(0.0, hp - amount)
	anim = 1.0
	queue_redraw()
	if hp <= 0.0:
		destroy()


## Разрушить машину: убрать из мира, с шансом DESTROY_DROP_CHANCE оставить
## её предмет, разбросать осколки.
func destroy() -> void:
	if not Net.is_authority():   # СЕТЬ (ADR-002): снос — событие от хоста (net_remove)
		return
	if _destroyed:
		return
	_destroyed = true
	destroyed.emit(self)
	_on_destroyed()
	_drop_output()
	if World.machines.get(cell) == self:
		World.machines.erase(cell)
	if World.beams != null:
		World.beams.note_machines()
	var item: int = machine_item_id(kind)
	if item != IDs.I.NONE and randf() < DESTROY_DROP_CHANCE:
		spawn_item(item, 1, global_position + Vector2(0.0, -4.0))
	var col: Color = DB.item_color(item) if item != IDs.I.NONE else Color(0.5, 0.5, 0.55)
	for i in DESTROY_CHIPS:
		UI.spawn_chip(cell, col)
	Sfx.play("break", -6.0, 0.8)
	queue_free()


## Крюк для наследников: что сделать перед разрушением (например, высыпать
## содержимое). В базовом классе — ничего.
func _on_destroyed() -> void:
	pass


## Разобрать постройку: снять с мира и вернуть предмет в инвентарь героя.
## Неразборные постройки (permanent) и уже снятые — не трогаем: возвращают NONE.
## Содержимое высыпается на землю — ничего не пропадает.
## Возвращает id предмета, который надо вернуть герою.
func dismantle() -> int:
	if permanent or _destroyed:
		return IDs.I.NONE
	if not Net.is_authority():   # СЕТЬ (ADR-002): снос — событие от хоста
		return IDs.I.NONE
	var item: int = machine_item_id(kind)
	_on_destroyed()      # содержимое постройки — на землю
	_drop_output()
	if World.machines.get(cell) == self:
		World.machines.erase(cell)
	if World.beams != null:
		World.beams.note_machines()
	_destroyed = true
	# Осколки — как при сносе (звук и подсказку даёт герой, который разбирает).
	var col: Color = DB.item_color(item) if item != IDs.I.NONE else Color(0.5, 0.5, 0.55)
	for i in DESTROY_CHIPS:
		UI.spawn_chip(cell, col)
	queue_free()
	return item


## Высыпать на землю готовое, которое ещё не отдали.
func _drop_output() -> void:
	for id in _output.keys():
		spawn_item(int(id), int(_output[id]), global_position + Vector2(0.0, -4.0))
	_output.clear()
	_output_count = 0


## Предмет, из которого ставится машина данного вида (NONE, если такого нет).
static func machine_item_id(p_kind: String) -> int:
	var place: String = "machine:" + p_kind
	for id in DB.item_defs.keys():
		if String(DB.item_defs[id].get("place", "")) == place:
			return int(id)
	return IDs.I.NONE


# ------------------------------------------------------------- ВИД (ADR-003, V6)
## «Споровый луг»: кремовые короба в голубовато-серых рамах, жёлтая разметка,
## лишайник на верхних кромках. Всё — прямоугольники по пиксельной сетке.
## Цвета — из палитры DB.PAL (V1), не дублируются: константы разворачиваются
## при компиляции, и _draw не ищет в словаре каждый кадр.

const _PAL: Dictionary = preload("res://scripts/autoload/db.gd").PAL
const C_METAL: Color = _PAL["metal"]          ## кремовая эмаль корпуса
const C_METAL_D: Color = _PAL["metal_d"]      ## кромка и тень эмали
const C_METAL_HI: Color = _PAL["metal_hi"]    ## блик верхней кромки
const C_FRAME: Color = _PAL["frame"]          ## рамы, окна, механика
const C_HAZARD: Color = _PAL["hazard"]        ## жёлтая разметка
const C_SCREEN: Color = _PAL["screen"]        ## тёмное стекло окон и экранов
const C_SCREEN_HI: Color = _PAL["screen_hi"]  ## экран/лампа «работает»
const C_LICHEN: Color = _PAL["s_top"]         ## лишайник, проросший на кромке
const C_LICHEN_HI: Color = _PAL["s_top2"]     ## кончики лишайника
const C_LAVA: Color = _PAL["lava"]            ## топка, горнило
const C_LAVA_HI: Color = _PAL["lava_hi"]
const C_BIO: Color = _PAL["bio"]              ## био-бирюза: прогресс, кристаллы в работе
const C_SOOT: Color = _PAL["bed"]             ## холодная топка, фон шкал
## Лампа «выключено» — единственный красный у машин (в палитре концепта его
## нет: `danger` оставлен угрозе — фантомам и ночи).
const C_LAMP_OFF: Color = Color("#E0503C")
## Корпус выключенной постройки: та же эмаль, приглушённая к тени.
const C_METAL_OFF: Color = Color("#C9C3B5")
## Корпус машины по умолчанию — вся клетка.
const BODY: Rect2 = Rect2(-8.0, -8.0, 16.0, 16.0)

## Где на верхней кромке пророс лишайник: биты 0..15 — столбцы пикселей
## (считается один раз от клетки, -1 — ещё не считали).
var _moss_mask: int = -1


## Кремовый короб: кромка 1 px, блик сверху, жёлтая разметка штрихами над
## нижней кромкой и лишайник на верхней (ADR-003 § 4.1, «обрастание»).
## on — работает (выключенная эмаль тусклее). hazard — рисовать ли разметку.
func _draw_body(r: Rect2 = BODY, on: bool = true, hazard: bool = true) -> void:
	draw_rect(r, C_METAL_D)
	draw_rect(r.grow(-1.0), C_METAL if on else C_METAL_OFF)
	draw_rect(Rect2(r.position.x + 1.0, r.position.y + 1.0, r.size.x - 2.0, 1.0), C_METAL_HI)
	if hazard:
		var y: float = r.end.y - 3.0
		var x: float = r.position.x + 1.0
		while x < r.end.x - 1.0:
			draw_rect(Rect2(x, y, minf(2.0, r.end.x - 1.0 - x), 1.0), C_HAZARD)
			x += 4.0
	_draw_moss(r)


## Пучки лишайника на верхней кромке: где именно — по хэшу клетки (у соседних
## машин узор разный, у одной и той же — всегда один и тот же).
func _draw_moss(r: Rect2) -> void:
	if _moss_mask < 0:
		var h: int = hash(cell) & 0x7fffffff
		_moss_mask = 0
		for k in 16:
			if ((h >> (k % 30)) & 3) == 0 or (k * 7 + h) % 11 == 0:
				_moss_mask |= 1 << k
	var n: int = mini(int(r.size.x), 16)
	for k in n:
		if _moss_mask & (1 << k) == 0:
			continue
		var x: float = r.position.x + float(k)
		draw_rect(Rect2(x, r.position.y - 1.0, 1.0, 2.0), C_LICHEN)
		if k % 3 == 0:
			draw_rect(Rect2(x, r.position.y - 2.0, 1.0, 1.0), C_LICHEN_HI)


## Лампа состояния 2×2 в рамке 4×4 (центр — at).
func _draw_lamp(at: Vector2, col: Color) -> void:
	draw_rect(Rect2(at.x - 2.0, at.y - 2.0, 4.0, 4.0), C_FRAME)
	draw_rect(Rect2(at.x - 1.0, at.y - 1.0, 2.0, 2.0), col)


## Полоса прогресса станка над корпусом (y — верх полосы).
func _draw_progress(y: float) -> void:
	draw_rect(Rect2(-6.0, y, 12.0, 2.0), Color(C_SOOT, 0.8))
	draw_rect(Rect2(-6.0, y, 12.0 * progress, 2.0), C_BIO)


# ------------------------------------------------------------- СОХРАНЕНИЕ (#37)
## Общий механизм сериализации машин (Save, scripts/core/save.gd). Базовые поля
## пишет MachineBase, наследник дописывает своё через super:
##     func save_state() -> Dictionary:
##         var d: Dictionary = super()
##         d["fuel"] = fuel
##         return d
## В словаре только простые типы (числа, строки, векторы, массивы, словари):
## файл кодируется var_to_bytes без объектов. Машина, которая своё ещё не
## дописала (новый тип), сохраняется и загружается с базовыми полями.

## Состояние машины для файла сохранения. kind и cell нужны Save, чтобы
## поставить машину заново (place_machine), остальное — её внутреннее состояние.
func save_state() -> Dictionary:
	return {
		"kind": kind,
		"cell": cell,
		"dir": dir,
		"hp": hp,
		"max_hp": max_hp,
		"progress": progress,
		"work_time": work_time,
		"output": _output.duplicate(),
		"permanent": permanent,
	}


## Восстановить состояние после place_machine. Неизвестные ключи игнорируются,
## отсутствующие оставляют значение, как у только что построенной машины.
func load_state(d: Dictionary) -> void:
	# Старый сейв хранит 0..3. Восемь положений — только у turn_steps = 8,
	# и они тоже влезают в тот же int: отдельного поля нет.
	var n: int = turn_steps if turn_steps > 1 else 4
	dir = posmod(int(d.get("dir", dir)), n)
	hp = float(d.get("hp", hp))
	max_hp = float(d.get("max_hp", max_hp))
	progress = float(d.get("progress", progress))
	work_time = float(d.get("work_time", work_time))
	permanent = bool(d.get("permanent", permanent))
	_output = load_counts(d.get("output", {}))
	_output_count = 0
	for id in _output.keys():
		_output_count += int(_output[id])
	_last_progress = -1.0
	queue_redraw()


## Словарь «id -> число» из файла: ключи и значения приводятся к int.
static func load_counts(v) -> Dictionary:
	var out: Dictionary = {}
	if v is Dictionary:
		for k in v.keys():
			if int(v[k]) > 0:
				out[int(k)] = int(v[k])
	return out


## Рецепт станка в файле: номер в DB.recipes_for(station) и id выхода ([-1, NONE] — нет).
static func recipe_ref(station: String, r: Dictionary) -> Array:
	if r.is_empty():
		return [-1, IDs.I.NONE]
	return [DB.recipes_for(station).find(r), int(r.get("out", IDs.I.NONE))]


## Рецепт по ссылке из файла. Номер сверяется с id выхода: если список рецептов
## сменился между версиями, ищем по выходу; не нашли — пустой рецепт.
static func recipe_from(station: String, ref) -> Dictionary:
	if not (ref is Array) or ref.size() < 2 or int(ref[0]) < 0:
		return {}
	var list: Array = DB.recipes_for(station)
	var i: int = int(ref[0])
	var out_id: int = int(ref[1])
	if i < list.size() and int(list[i].get("out", IDs.I.NONE)) == out_id:
		return list[i]
	for r in list:
		if int(r.get("out", IDs.I.NONE)) == out_id:
			return r
	return {}


# ------------------------------------------------------------- СЕТЬ (ADR-002, MP-E #90)
## Машины по сети (scripts/net/net_machines.gd, § 4.2.4). Постройка и снос — события
## с save_state(); раз в 0.25 с хост шлёт компактный net_state() изменённых машин в
## зоне интереса клиента, клиент кладёт его apply_net_state(). У клиента логика машин
## не идёт (Net.is_authority() в _process наследников): ни прогресса, ни выдачи, ни
## питания — только анимация и отрисовка по полученному состоянию.
##
## База — NET_BASE_BYTES: hp u8 (доля max_hp) · флаги u8 (NF_*) · резерв u8 ·
## progress u8. Длина та же (#170): байт питания больше не пишется смыслом,
## но пакет не короче — иначе PROTO. Наследник дописывает своё через super().

const NET_BASE_BYTES: int = 4
const NF_POWERED: int = 1     ## резерв: питание снято, бит не ставится
const NF_ACTIVE: int = 2      ## резерв генератора (класса больше нет)
const NF_ENABLED: int = 4     ## рубильник (накопитель читает свой байт)
const NF_OVERLOAD: int = 8    ## резерв браун-аута
const NF_DIR_SHIFT: int = 4   ## dir 0..3 — биты 4–5 байта флагов
## Восемь положений в эти два бита не влезают (биты 2–3 — рубильник генератора).
## Горелка кладёт dir в свободные биты своего байта пламени, зеркало — в свой
## байт. База по-прежнему пишет только 0..3, длина пакетов других машин та же.


func net_state() -> PackedByteArray:
	var b: PackedByteArray = PackedByteArray()
	b.resize(NET_BASE_BYTES)
	b[0] = net_u8(hp / maxf(max_hp, 0.001))
	b[1] = (dir & 3) << NF_DIR_SHIFT   ## 0..3; диагональ 4..7 дописывает наследник
	b[2] = 0                           ## байт efficiency снят (#170), длина та же
	b[3] = net_u8(progress)
	return b


## Клиент: состояние от хоста. Итог — смещение после прочитанного (−1 — коротко).
func apply_net_state(b: PackedByteArray) -> int:
	if b.size() < NET_BASE_BYTES:
		return -1
	hp = float(b[0]) / 255.0 * max_hp
	# Восемь положений базу не касаются: два бита здесь — только 0..3.
	# Горелка и зеркало дочитывают dir сами, иначе диагональ затиралась бы.
	if turn_steps <= 4:
		var d: int = (b[1] >> NF_DIR_SHIFT) & 3
		if d != dir:
			dir = d
			queue_redraw()
	progress = float(b[3]) / 255.0
	return NET_BASE_BYTES


## Клиент: машину снёс хост — убрать без выдачи и выпадения (предметы — от хоста).
func net_remove() -> void:
	if _destroyed:
		return
	_destroyed = true
	destroyed.emit(self)
	if World.machines.get(cell) == self:
		World.machines.erase(cell)
	if World.beams != null:
		World.beams.note_machines()
	var item: int = machine_item_id(kind)
	var col: Color = DB.item_color(item) if item != IDs.I.NONE else Color(0.5, 0.5, 0.55)
	for i in DESTROY_CHIPS:
		UI.spawn_chip(cell, col)
	Sfx.play_at("break", global_position, -6.0, 0.8)
	queue_free()


static func net_u8(f: float) -> int:
	return clampi(roundi(clampf(f, 0.0, 1.0) * 255.0), 0, 255)
