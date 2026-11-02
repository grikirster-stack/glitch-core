class_name MachineBase
extends Node2D
## Базовый класс построек: питание, приём/выдача предметов, логистика, прочность.
##
## Питание (ADR-001, § 4.3): статус `powered` и `efficiency` машине выставляет
## Game.update_power_budget() раз в Balance.POWER_CHECK_INTERVAL — сама машина
## питание больше не опрашивает. Станки умножают свой прогресс на efficiency
## через work(delta).

## Как часто Game раскладывает потребителей по генераторам (оставлено для
## совместимости: значение берётся из Balance).
const POWER_CHECK_INTERVAL: float = Balance.POWER_CHECK_INTERVAL
## Машины, которые потребляют питание. Полная таблица потребления —
## Balance.POWER_DRAW: всё, что в ней есть, тоже потребитель (см. consumes_power).
## У конвейеров и сундуков питание не используется вовсе.
const POWER_CONSUMERS: Array[String] = ["Drill", "Smelter", "Assembler"]
## Машины, чья отрисовка зависит от времени (вращение, мерцание):
## им нужна перерисовка каждый кадр.
const TIME_ANIMATED: Array[String] = ["Drill", "Smelter", "Assembler", "DeepDrill"]
## Шанс, что разрушенная машина оставит свой предмет (§ 4.4).
const DESTROY_DROP_CHANCE: float = 0.5
## Сколько осколков разлетается при разрушении.
const DESTROY_CHIPS: int = 4
## Сколько готовых предметов машина держит для манипулятора (take_output, #30),
## прежде чем снова выбрасывать готовое на землю.
const OUTPUT_CAP: int = 20

## Машина разрушена (до удаления из мира). Для угрозы/HUD/звука.
signal destroyed(machine: MachineBase)

var cell: Vector2i = Vector2i.ZERO
var kind: String = ""
var powered: bool = false
var power_radius: float = 0.0
var power_active: bool = false
## Сколько мощности тянет потребитель (Balance.POWER_DRAW; ставится при постройке).
var power_draw: float = 0.0
## Доля мощности, которую машина получает: clamp(output / load, 0, 1).
## У потребителя — от своего генератора (0 без питания); у генератора — его
## собственное отношение мощности к нагрузке.
var efficiency: float = 0.0
## Наработка: секунды полезной работы с учётом efficiency (см. work()).
var work_time: float = 0.0
var hp: float = Balance.MACHINE_HP
var max_hp: float = Balance.MACHINE_HP
var progress: float = 0.0
var anim: float = 0.0
var _last_progress: float = 0.0
var _destroyed: bool = false
## Готовое, ждущее манипулятора (#30): id -> count. См. deliver() и take_output().
var _output: Dictionary = {}
var _output_count: int = 0


static func place_machine(p_kind: String, c: Vector2i) -> bool:
	if World.machines.has(c):
		return false
	if World.belts.has(c):
		return false
	if World.get_tile_v(c) != IDs.T.AIR:
		return false
	var m: MachineBase = null
	match p_kind:
		"Drill":
			m = Drill.new()
		"Smelter":
			m = Smelter.new()
		"Assembler":
			m = Assembler.new()
		"Chest":
			m = Chest.new()
		"CoalGen":
			m = CoalGen.new()
		"Solar":
			m = Solar.new()
		"Belt":
			m = Belt.new()
		# --- Автоматизация (#30) ---
		"Inserter":
			m = Inserter.new()
		"Analyzer":
			m = Analyzer.new()
		"DeepDrill":
			m = DeepDrill.new()
		# --- Оборона (#31) ---
		"Turret":
			m = Turret.new()
		"Floodlight":
			m = Floodlight.new()
		_:
			return false
	m.cell = c
	m.kind = p_kind
	m.power_draw = float(Balance.POWER_DRAW.get(p_kind, 0.0))
	m.global_position = World.cell_to_world(c)
	m.position = m.global_position
	World.machines[c] = m
	if m is Belt:
		World.belts[c] = m
	Game.register_power_source(m, c)
	World.add_world_node(m)
	return true


func _process(delta: float) -> void:
	# Затухание вспышки анимации (например, после добычи).
	if anim > 0.0:
		anim = maxf(0.0, anim - delta * 2.0)
		queue_redraw()
	# Полоса прогресса у станков.
	if progress != _last_progress:
		_last_progress = progress
		queue_redraw()
	# Непрерывная анимация отрисовки (вращение бура, мерцание горна).
	if has_time_animation():
		queue_redraw()


## Нужен ли этой машине статус питания.
func consumes_power() -> bool:
	return kind in POWER_CONSUMERS or Balance.POWER_DRAW.has(kind)


## Итог раскладки питания для этой машины. Вызывает Game.update_power_budget().
func apply_power(p_powered: bool, p_efficiency: float) -> void:
	if p_powered != powered:
		powered = p_powered
		queue_redraw()
	efficiency = p_efficiency if p_powered else 0.0


## Полезная работа за кадр: delta, умноженная на efficiency (0 без питания).
## Станки двигают прогресс на это значение вместо голого delta.
func work(delta: float) -> float:
	if not powered:
		return 0.0
	var w: float = delta * efficiency
	work_time += w
	return w


## Зависит ли отрисовка от времени (тогда нужна перерисовка каждый кадр).
func has_time_animation() -> bool:
	return kind in TIME_ANIMATED


## Принимает предмет. Возвращает количество, которое НЕ принято (0 — принято всё).
func receive_item(item_id: int, count: int) -> int:
	return count


func input_accepts(item_id: int) -> bool:
	return false


## Отдаёт предмет: сначала соседний конвейер/сундук/станция, иначе — на землю.
func deliver(item_id: int, count: int) -> void:
	for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		var n: Vector2i = cell + d
		if World.belts.has(n):
			var b: Belt = World.belts[n]
			# Лента, которая везёт в нас, — вход, а не выход (#30): иначе готовое
			# уезжает обратно в станок (слиток — во вход проката пластин).
			if b.cell + b._dir_cell() == cell:
				continue
			if b.add_item(item_id, count):
				return
			continue
		if World.machines.has(n):
			var m: MachineBase = World.machines[n]
			if m.receive_item(item_id, count) == 0:
				return
	# Готовое забирает манипулятор (#30) — держим у себя, не бросаем на землю.
	if _output_count + count <= OUTPUT_CAP and _has_puller():
		_output[item_id] = int(_output.get(item_id, 0)) + count
		_output_count += count
		return
	spawn_item(item_id, count, global_position + Vector2(0.0, -4.0))


## Выдать манипулятору один готовый предмет (#30). filter — только этот id
## (NONE — любой); accepts — возьмёт ли приёмник (пустой Callable — да).
## Возвращает id выданного предмета или IDs.I.NONE.
func take_output(filter: int = IDs.I.NONE, accepts: Callable = Callable()) -> int:
	if _output_count <= 0:
		return IDs.I.NONE
	for id in _output.keys():
		if filter != IDs.I.NONE and int(id) != filter:
			continue
		if accepts.is_valid() and not bool(accepts.call(int(id))):
			continue
		var left: int = int(_output[id]) - 1
		if left <= 0:
			_output.erase(id)
		else:
			_output[id] = left
		_output_count -= 1
		return int(id)
	return IDs.I.NONE


## Стоит ли рядом манипулятор, который берёт из этой клетки.
func _has_puller() -> bool:
	for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		var n = World.machines.get(cell + d)
		if n is Inserter and n.source_cell() == cell:
			return true
	return false


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
	hp = maxf(0.0, hp - amount)
	anim = 1.0
	queue_redraw()
	if hp <= 0.0:
		destroy()


## Разрушить машину: убрать из мира, с шансом DESTROY_DROP_CHANCE оставить
## её предмет, разбросать осколки. Индекс питания в Game пересоберётся сам
## (число машин в мире изменилось).
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
	if World.belts.get(cell) == self:
		World.belts.erase(cell)
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


## Высыпать на землю готовое, не забранное манипулятором (#30).
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


func power_label() -> String:
	if power_radius <= 0.0:
		return ""
	return "%d" % int(power_radius)


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
## Лампа «нет питания / выключено» — единственный красный у машин (в палитре
## концепта его нет: `danger` оставлен угрозе — фантомам и ночи).
const C_LAMP_OFF: Color = Color("#E0503C")
## Корпус без питания: та же эмаль, приглушённая к тени.
const C_METAL_OFF: Color = Color("#C9C3B5")
## Корпус машины по умолчанию — вся клетка.
const BODY: Rect2 = Rect2(-8.0, -8.0, 16.0, 16.0)

## Где на верхней кромке пророс лишайник: биты 0..15 — столбцы пикселей
## (считается один раз от клетки, -1 — ещё не считали).
var _moss_mask: int = -1


## Кремовый короб: кромка 1 px, блик сверху, жёлтая разметка штрихами над
## нижней кромкой и лишайник на верхней (ADR-003 § 4.1, «обрастание»).
## on — под питанием (без питания эмаль тусклее). hazard — рисовать ли разметку.
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
		"hp": hp,
		"max_hp": max_hp,
		"progress": progress,
		"work_time": work_time,
		"output": _output.duplicate(),
	}


## Восстановить состояние после place_machine. Неизвестные ключи игнорируются,
## отсутствующие оставляют значение, как у только что построенной машины.
func load_state(d: Dictionary) -> void:
	hp = float(d.get("hp", hp))
	max_hp = float(d.get("max_hp", max_hp))
	progress = float(d.get("progress", progress))
	work_time = float(d.get("work_time", work_time))
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
## База — NET_BASE_BYTES: hp u8 (доля max_hp) · флаги u8 (NF_*) · efficiency u8 ·
## progress u8. Наследник дописывает своё через super(); apply_net_state() возвращает
## смещение после прочитанного — наследник читает дальше с него.

const NET_BASE_BYTES: int = 4
const NF_POWERED: int = 1
const NF_ACTIVE: int = 2      ## power_active (генераторы)
const NF_ENABLED: int = 4     ## рубильник генератора
const NF_OVERLOAD: int = 8    ## генератор перегружен (браун-аут в радиусе)


func net_state() -> PackedByteArray:
	var b: PackedByteArray = PackedByteArray()
	b.resize(NET_BASE_BYTES)
	b[0] = net_u8(hp / maxf(max_hp, 0.001))
	b[1] = (NF_POWERED if powered else 0) | (NF_ACTIVE if power_active else 0)
	b[2] = net_u8(efficiency)
	b[3] = net_u8(progress)
	return b


## Клиент: состояние от хоста. Итог — смещение после прочитанного (−1 — коротко).
func apply_net_state(b: PackedByteArray) -> int:
	if b.size() < NET_BASE_BYTES:
		return -1
	hp = float(b[0]) / 255.0 * max_hp
	power_active = (b[1] & NF_ACTIVE) != 0
	apply_power((b[1] & NF_POWERED) != 0, float(b[2]) / 255.0)
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
	if World.belts.get(cell) == self:
		World.belts.erase(cell)
	var item: int = machine_item_id(kind)
	var col: Color = DB.item_color(item) if item != IDs.I.NONE else Color(0.5, 0.5, 0.55)
	for i in DESTROY_CHIPS:
		UI.spawn_chip(cell, col)
	Sfx.play_at("break", global_position, -6.0, 0.8)
	queue_free()


static func net_u8(f: float) -> int:
	return clampi(roundi(clampf(f, 0.0, 1.0) * 255.0), 0, 255)
