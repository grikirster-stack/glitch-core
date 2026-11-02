extends Node
## Глобальное состояние: время суток, волны фантомов, задания, прогресс, цель игры.

signal notification(text: String, color: Color)
signal task_completed(total: int, done: int)
signal state_changed(state: int)
## Новая смена началась — рассвет, ночь кончилась (ADR-001, § 4.1).
signal day_started(day: int)
## Этап цели сменился (ADR-001, § 4.7; этапы ведёт #32).
signal objective_changed(stage: int)

enum State { PLAYING, DEAD, WON }

const DAY_LENGTH: float = Balance.DAY_LENGTH
const RELAY_TIME: float = Balance.RELAY_TIME

var state: int = State.PLAYING
var time_of_day: float = Balance.START_TIME ## доля цикла: 0.04 — рассвет, 0.66 — ночь
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
var stats_deaths: int = 0              ## Смертей за забег (респаун — #29).
## Сценарии и автотесты сами создают фантомов: директор угрозы (#27) и
## main.gd::_update_waves при этом флаге волны не ведут. Ставит main.gd.
var scenario_mode: bool = false
## Этап цели по ADR-001 § 4.7: 0 — не начато, 1 — запитать станцию,
## 2 — собрать данные, 3 — собрать релей, 4 — удержать сигнал. Ведёт #32.
var objective_stage: int = 0

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
	time_of_day = Balance.START_TIME
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
	stats_deaths = 0
	scenario_mode = false
	objective_stage = 0
	_power_index_size = -1          ## мир мог смениться — индекс пересоберётся
	# --- Исследования (#28): дерево и журнал живут один забег.
	Tech.reset()


func _process(delta: float) -> void:
	if state != State.PLAYING:
		return
	game_time += delta
	var prev_t: float = time_of_day
	time_of_day = fmod(time_of_day + delta / DAY_LENGTH, 1.0)
	# Смена начинается с рассветом — в момент, когда ночь кончилась.
	# Раньше номер считался как 1 + int(t * 2): он прыгал 1↔2 внутри одного
	# цикла, дважды за цикл слал «Смена N» и никогда не рос дальше двух.
	if prev_t < Balance.NIGHT_END and time_of_day >= Balance.NIGHT_END:
		day_number += 1
		day_started.emit(day_number)
		notify("Смена %d. Фантомы голоднее." % day_number, Color(0.9, 0.9, 0.7))
	if relay_active:
		relay_timer -= delta
		if relay_timer <= 0.0:
			relay_timer = 0.0
			notify("СИГНАЛ УШЁЛ НА ОРБИТУ. ЭВАКУАЦИЯ!", Color(0.4, 1.0, 0.7))
			set_state(State.WON)


func is_night() -> bool:
	return time_of_day >= Balance.NIGHT_START or time_of_day < Balance.NIGHT_END


## Сумерки: ночь ещё не началась, но уже близко — время телеграфа (§ 4.1).
func is_dusk() -> bool:
	return time_of_day >= Balance.DUSK_START and time_of_day < Balance.NIGHT_START


func daylight() -> float:
	## 0 — глубокая ночь, 1 — полдень. Кусочно-линейная кривая без скачков;
	## на границе ночи (NIGHT_START) ровно SOLAR_MIN_DAYLIGHT — солнечные
	## панели гаснут в ту же секунду, когда начинается ночь.
	var t: float = time_of_day
	var dawn: float = Balance.NIGHT_END
	var night: float = Balance.NIGHT_START
	var solar: float = Balance.SOLAR_MIN_DAYLIGHT
	if t < dawn:
		return lerpf(0.0, 0.55, t / dawn)
	if t < 0.30:
		return lerpf(0.55, 1.0, (t - dawn) / (0.30 - dawn))
	if t < 0.55:
		return lerpf(1.0, 0.72, (t - 0.30) / 0.25)
	if t < night:
		return lerpf(0.72, solar, (t - 0.55) / (night - 0.55))
	return lerpf(solar, 0.0, (t - night) / (1.0 - night))


func notify(text: String, color: Color = Color(0.85, 0.9, 1.0)) -> void:
	notification.emit(text, color)


func complete_task() -> void:
	tasks_done += 1
	research += Balance.TERMINAL_DATA
	task_completed.emit(tasks_total, tasks_done)
	notify("Задание выполнено! (%d/%d)  +%d данных" % [tasks_done, tasks_total, Balance.TERMINAL_DATA],
			Color(0.4, 0.95, 0.6))


func set_state(s: int) -> void:
	if state == s:
		return
	state = s
	state_changed.emit(s)


## Сменить этап цели (§ 4.7). Сигнал уходит только при реальной смене.
func set_objective_stage(s: int) -> void:
	if objective_stage == s:
		return
	objective_stage = s
	objective_changed.emit(s)


func phase_name() -> String:
	if is_night():
		return "НОЧЬ"
	if is_dusk():
		return "СУМЕРКИ"
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
