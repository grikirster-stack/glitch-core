extends Node
## Глобальное состояние: время суток, волны фантомов, задания, прогресс, цель игры.

signal notification(text: String, color: Color)
signal task_completed(total: int, done: int)
signal state_changed(state: int)

enum State { PLAYING, DEAD, WON }

const DAY_LENGTH: float = 150.0
const RELAY_TIME: float = 90.0

var state: int = State.PLAYING
var time_of_day: float = 0.30          ## 0 — рассвет, 0.5 — полдень, 0.75 — ночь
var day_number: int = 1
var tasks_total: int = 0
var tasks_done: int = 0
var research: int = 0
var wave: int = 0
var phantoms_alive: int = 0
var game_time: float = 0.0
var player = null                      ## Ссылка на игрока (без типа — цикла зависимостей).
var relay_req: Dictionary = {}
var relay_active: bool = false
var relay_timer: float = 0.0
var stats_mined: int = 0
var stats_crafted: int = 0
var stats_kills: int = 0

# ------------------------------------------------- ИНДЕКС ИСТОЧНИКОВ ПИТАНИЯ
## Список генераторов (источников питания) — чтобы is_powered() не перебирал
## ВСЕ машины мира. Старая версия давала O(N^2): каждая машина раз в 0.4 с
## спрашивала питание у всех остальных. Теперь машина спрашивает только у
## генераторов, а их обычно 2–5 на всю фабрику.
##
## Индекс сам следит за составом World.machines и перестраивается при
## рассинхроне: править world.gd (его зона другого агента) нельзя, поэтому
## явную очистку в World.generate() добавить невозможно. Вместо этого:
##   * World.generate() делает machines.clear() → размер словаря меняется →
##     индекс пересобирается и очищается сам (проверка размера — O(1));
##   * новая машина-генератор добавляется в индекс сразу при постройке
##     (MachineBase.place_machine → register_power_source);
##   * раз в VERIFY_EVERY вызовов индекс сверяется с миром поимённо —
##     ловит случай «сняли ТЭЦ и тут же поставили конвейер» (число машин
##     не изменилось, а источник сменился).
var _power_sources: Array = []          ## сами источники питания
var _power_source_cells: Array = []     ## их клетки в World.machines
var _power_index_size: int = -1         ## размер World.machines на момент сборки индекса
var _power_verify_tick: int = 0         ## счётчик вызовов до сверки состава

const POWER_VERIFY_EVERY: int = 32      ## как часто сверять индекс с миром


func _ready() -> void:
	relay_req = DB.relay_req.duplicate()


## Сброс забега (при перезапуске сцены).
func reset_run() -> void:
	state = State.PLAYING
	time_of_day = 0.30
	day_number = 1
	tasks_done = 0
	research = 0
	wave = 0
	game_time = 0.0
	relay_active = false
	relay_timer = 0.0
	stats_mined = 0
	stats_crafted = 0
	stats_kills = 0
	_power_index_size = -1          ## мир мог смениться — индекс пересоберётся


func _process(delta: float) -> void:
	if state != State.PLAYING:
		return
	game_time += delta
	time_of_day = fmod(time_of_day + delta / DAY_LENGTH, 1.0)
	var prev_day: int = day_number
	day_number = 1 + int(time_of_day * 2.0)
	if day_number != prev_day:
		notify("Смена %d. Фантомы голоднее." % day_number, Color(0.9, 0.9, 0.7))
	if relay_active:
		relay_timer -= delta
		if relay_timer <= 0.0:
			relay_timer = 0.0
			notify("СИГНАЛ УШЁЛ НА ОРБИТУ. ЭВАКУАЦИЯ!", Color(0.4, 1.0, 0.7))
			set_state(State.WON)


func is_night() -> bool:
	return time_of_day >= 0.62 or time_of_day < 0.06


func daylight() -> float:
	## 0 — глубокая ночь, 1 — полдень.
	var t: float = time_of_day
	if t < 0.06:
		return lerpf(0.0, 0.55, t / 0.06)
	if t < 0.30:
		return lerpf(0.55, 1.0, (t - 0.06) / 0.24)
	if t < 0.55:
		return lerpf(1.0, 0.72, (t - 0.30) / 0.25)
	if t < 0.62:
		return lerpf(0.72, 0.35, (t - 0.55) / 0.07)
	return lerpf(0.35, 0.0, (t - 0.62) / 0.38)


func notify(text: String, color: Color = Color(0.85, 0.9, 1.0)) -> void:
	notification.emit(text, color)


func complete_task() -> void:
	tasks_done += 1
	research += 5
	task_completed.emit(tasks_total, tasks_done)
	notify("Задание выполнен! (%d/%d)  +5 данных" % [tasks_done, tasks_total], Color(0.4, 0.95, 0.6))


func set_state(s: int) -> void:
	if state == s:
		return
	state = s
	state_changed.emit(s)


func phase_name() -> String:
	if is_night():
		return "НОЧЬ"
	if time_of_day < 0.3:
		return "УТРО"
	if time_of_day < 0.55:
		return "ДЕНЬ"
	return "ВЕЧЕР"


## Есть ли в радиусе генератора энергия для точки p.
## Перебираются только источники питания (генераторы), а не все машины мира.
func is_powered(p: Vector2) -> bool:
	_sync_power_index()
	for s in _power_sources:
		if not is_instance_valid(s):
			continue
		if not s.power_active:
			continue
		if p.distance_to(s.global_position) <= s.power_radius * World.TILE:
			return true
	return false


## Сообщить о новой машине. Вызывается из MachineBase.place_machine().
## В индекс попадают только источники питания (генераторы).
func register_power_source(m, cell: Vector2i) -> void:
	if not _is_power_source(m):
		return
	# Индекс мог устареть (например, мир пересоздали) — тогда проще пересобрать.
	if _power_index_size != World.machines.size() or _has_dead_sources():
		_rebuild_power_index()
		return
	if _power_sources.has(m):
		return
	_power_sources.append(m)
	_power_source_cells.append(cell)
	_power_index_size = World.machines.size()


## Пересобрать индекс источников питания по текущему составу мира.
func _rebuild_power_index() -> void:
	_power_sources.clear()
	_power_source_cells.clear()
	for cell in World.machines.keys():
		var m = World.machines[cell]
		if _is_power_source(m):
			_power_sources.append(m)
			_power_source_cells.append(cell)
	_power_index_size = World.machines.size()
	_power_verify_tick = 0


## Остались ли в индексе освобождённые машины.
func _has_dead_sources() -> bool:
	for s in _power_sources:
		if not is_instance_valid(s):
			return true
	return false


## Сверить индекс с миром и пересобрать его при рассинхроне.
## Быстрая проверка (O(1)) — сравнение числа машин; полная сверка поимённо
## идёт раз в POWER_VERIFY_EVERY вызовов, чтобы не платить за неё каждый раз.
func _sync_power_index() -> void:
	if World.machines.size() != _power_index_size:
		_rebuild_power_index()
		return
	_power_verify_tick += 1
	if _power_verify_tick < POWER_VERIFY_EVERY:
		return
	_power_verify_tick = 0
	for i in _power_sources.size():
		var s = _power_sources[i]
		if not is_instance_valid(s) or World.machines.get(_power_source_cells[i]) != s:
			_rebuild_power_index()
			return


## Источник питания — машина с ненулевым радиусом и признаком активности.
## Проверка «утиной типизацией» (по имени свойства), а не через class_name:
## game.gd — автозагрузка, и ссылка на MachineBase/Generator создала бы
## циклическую зависимость autoload → class_name → autoload.
## Активность (power_active) не кэшируется — она меняется в coal_gen.gd/solar.gd.
static func _is_power_source(m) -> bool:
	if m == null or not is_instance_valid(m):
		return false
	var radius = m.get("power_radius")
	var active = m.get("power_active")
	if not (radius is float or radius is int) or not (active is bool):
		return false
	return float(radius) > 0.0


## Попытка запустить релей-ядро. Возвращает true, если запуск прошёл.
func try_finish() -> bool:
	if player == null or relay_active:
		return false
	var missing: Array = []
	for id in relay_req.keys():
		var have: int = player.inv.count_of(id)
		if have < int(relay_req[id]):
			missing.append("%s (%d/%d)" % [DB.item_name(id), have, int(relay_req[id])])
	if not missing.is_empty():
		notify("Релею не хватает: " + ", ".join(missing), Color(1.0, 0.6, 0.4))
		return false
	for id in relay_req.keys():
		player.inv.remove_id(id, int(relay_req[id]))
	relay_active = true
	relay_timer = RELAY_TIME
	notify("РЕЛЕЙ ЗАПУЩЕН! Держитесь %d секунд." % int(RELAY_TIME), Color(0.4, 1.0, 0.8))
	Sfx.play("power", -2.0)
	return true
