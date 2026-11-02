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
## Сценарии сами создают фантомов: директор угрозы (Threat, #27) при этом
## флаге волны не ведёт. Ставит main.gd.
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

# ------------------------------------------------- БЮДЖЕТ МОЩНОСТИ (ADR-001 § 4.3, #25)
## Раз в Balance.POWER_CHECK_INTERVAL update_power_budget() раскладывает
## потребителей (машины с power_draw) по ближайшему активному генератору в
## радиусе, суммирует нагрузку генератора (power_load) и выдаёт потребителям
## efficiency = clamp(output / load, 0, 1). Потребители лежат в том же индексе,
## что и источники: перебор — O(потребители × генераторы), генераторов 2–6.
##
## Браун-аут — хотя бы один работающий генератор перегружен. Сигнал и флаг —
## для звука (#36) и HUD (#34).
signal brownout_changed(active: bool)
## Раскладка пересчитана (раз в 0.25 с).
signal power_updated

var brownout: bool = false              ## есть перегруженный генератор
var power_output_total: float = 0.0     ## суммарная мощность работающих генераторов
var power_load_total: float = 0.0       ## суммарная нагрузка запитанных потребителей
var power_unpowered: int = 0            ## потребителей вне зоны питания
## Потребители — параллельные массивы: машины не двигаются, поэтому позиция и
## потребление кэшируются при сборке индекса, а горячий цикл раскладки идёт по
## упакованным массивам без обращений к узлам.
var _power_consumers: Array = []                            ## потребители питания
var _power_consumer_cells: Array = []                       ## их клетки в World.machines
var _power_consumer_pos: PackedVector2Array = PackedVector2Array()
var _power_consumer_draw: PackedFloat32Array = PackedFloat32Array()
## Последний выданный потребителю итог: efficiency (0..1), POWER_STATE_OFF —
## без питания, POWER_STATE_UNKNOWN — ещё не выдавался. Машине звоним только
## при смене итога.
var _power_consumer_state: PackedFloat32Array = PackedFloat32Array()
var _power_timer: float = 0.0
var _power_validate_tick: int = 0

const POWER_STATE_OFF: float = -0.5
const POWER_STATE_UNKNOWN: float = -1.0
## Раз в сколько раскладок сверять потребителей с миром поимённо (ловит
## «сняли бур и в тот же кадр поставили другую машину»). 4 × 0.25 с = 1 с.
const POWER_VALIDATE_EVERY: int = 4


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
	_power_timer = 0.0
	power_output_total = 0.0
	power_load_total = 0.0
	power_unpowered = 0
	_set_brownout(false)


func _process(delta: float) -> void:
	# Питание раскладывается и после смерти/победы: машины мира живут дальше.
	_power_timer += delta
	if _power_timer >= Balance.POWER_CHECK_INTERVAL:
		_power_timer = 0.0
		update_power_budget()
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
## В индекс попадают источники питания (генераторы) и потребители.
func register_power_source(m, cell: Vector2i) -> void:
	var source: bool = _is_power_source(m)
	var consumer: bool = _is_power_consumer(m)
	if not source and not consumer:
		return
	# Индекс мог устареть (например, мир пересоздали) — тогда проще пересобрать.
	if _power_index_size != World.machines.size() or _has_dead_sources():
		_rebuild_power_index()
		return
	if source and not _power_sources.has(m):
		_power_sources.append(m)
		_power_source_cells.append(cell)
	if consumer and not _power_consumers.has(m):
		_add_power_consumer(m, cell)
	_power_index_size = World.machines.size()


## Пересобрать индекс источников питания по текущему составу мира.
func _rebuild_power_index() -> void:
	_power_sources.clear()
	_power_source_cells.clear()
	_power_consumers.clear()
	_power_consumer_cells.clear()
	_power_consumer_pos.clear()
	_power_consumer_draw.clear()
	_power_consumer_state.clear()
	for cell in World.machines.keys():
		var m = World.machines[cell]
		if _is_power_source(m):
			_power_sources.append(m)
			_power_source_cells.append(cell)
		elif _is_power_consumer(m):
			_add_power_consumer(m, cell)
	_power_index_size = World.machines.size()
	_power_verify_tick = 0


## Добавить потребителя в индекс (с кэшем позиции и потребления).
func _add_power_consumer(m, cell: Vector2i) -> void:
	_power_consumers.append(m)
	_power_consumer_cells.append(cell)
	# До add_world_node машина ещё не в дереве — тогда её позиция и есть мировая.
	_power_consumer_pos.append(m.global_position if m.is_inside_tree() else m.position)
	var draw = m.get("power_draw")
	_power_consumer_draw.append(float(draw) if (draw is float or draw is int) else 0.0)
	_power_consumer_state.append(POWER_STATE_UNKNOWN)


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


## Потребитель питания — машина, которой нужен статус питания (consumes_power).
static func _is_power_consumer(m) -> bool:
	if m == null or not is_instance_valid(m):
		return false
	return m.has_method("consumes_power") and m.consumes_power()


## Раскладка бюджета мощности (§ 4.3). Вызывается из _process раз в
## Balance.POWER_CHECK_INTERVAL; публичная — для тестов и замеров.
##
## Каждый потребитель питается от БЛИЖАЙШЕГО активного генератора, в радиус
## которого попадает. Нагрузка генератора — сумма power_draw его потребителей,
## efficiency = clamp(output / load, 0, 1) (при нулевой нагрузке — 1).
func update_power_budget() -> void:
	_sync_power_index()
	# Поимённая сверка потребителей с миром — раз в POWER_VALIDATE_EVERY тиков.
	# Добавление/снятие машин ловит проверка размера в _sync_power_index().
	_power_validate_tick += 1
	if _power_validate_tick >= POWER_VALIDATE_EVERY:
		_power_validate_tick = 0
		if not _power_consumers_valid():
			_rebuild_power_index()
	var tile: float = float(World.TILE)
	# Работающие генераторы — в плоские массивы.
	var gens: Array = []
	var gpos: PackedVector2Array = PackedVector2Array()
	var grad2: PackedFloat32Array = PackedFloat32Array()
	var gout: PackedFloat32Array = PackedFloat32Array()
	var out_total: float = 0.0
	var stale: bool = false
	for i in _power_sources.size():
		var s = _power_sources[i]
		if not is_instance_valid(s) or World.machines.get(_power_source_cells[i]) != s:
			stale = true
			continue
		if not s.power_active:
			_set_source_budget(s, 0.0, 0.0)
			continue
		gens.append(s)
		gpos.append(s.global_position)
		var r: float = float(s.power_radius) * tile
		grad2.append(r * r)
		var o: float = _source_output(s)
		gout.append(o)
		out_total += o
	var ng: int = gens.size()
	var gload: PackedFloat32Array = PackedFloat32Array()
	gload.resize(ng)
	gload.fill(0.0)
	# Потребители → ближайший генератор в радиусе. Только упакованные массивы.
	var nc: int = _power_consumers.size()
	var assign: PackedInt32Array = PackedInt32Array()
	assign.resize(nc)
	var unpowered: int = 0
	for ci in nc:
		var p: Vector2 = _power_consumer_pos[ci]
		var best: int = -1
		var best_d2: float = INF
		for gi in ng:
			var d2: float = p.distance_squared_to(gpos[gi])
			if d2 <= grad2[gi] and d2 < best_d2:
				best_d2 = d2
				best = gi
		assign[ci] = best
		if best >= 0:
			gload[best] += _power_consumer_draw[ci]
		else:
			unpowered += 1
	# Отношение мощности к нагрузке на каждом генераторе.
	var geff: PackedFloat32Array = PackedFloat32Array()
	geff.resize(ng)
	var load_total: float = 0.0
	var over: bool = false
	for gi in ng:
		var l: float = gload[gi]
		var e: float = 1.0 if l <= 0.0 else clampf(gout[gi] / l, 0.0, 1.0)
		geff[gi] = e
		load_total += l
		if l > gout[gi]:
			over = true
		_set_source_budget(gens[gi], l, e)
	# Итог — потребителям, и только тем, у кого он сменился.
	for ci in nc:
		var a: int = assign[ci]
		var st: float = geff[a] if a >= 0 else POWER_STATE_OFF
		if st == _power_consumer_state[ci]:
			continue
		var c = _power_consumers[ci]
		if not is_instance_valid(c):
			stale = true
			continue
		_power_consumer_state[ci] = st
		c.apply_power(a >= 0, st if a >= 0 else 0.0)
	power_output_total = out_total
	power_load_total = load_total
	power_unpowered = unpowered
	_set_brownout(over)
	# Машину сняли/заменили — к следующему тику индекс будет свежим.
	if stale:
		_rebuild_power_index()
	power_updated.emit()


## Все ли потребители индекса на месте в мире.
func _power_consumers_valid() -> bool:
	for ci in _power_consumers.size():
		var c = _power_consumers[ci]
		if not is_instance_valid(c) or World.machines.get(_power_consumer_cells[ci]) != c:
			return false
	return true


## Мощность источника сейчас (утиная типизация: см. _is_power_source).
static func _source_output(s) -> float:
	if s.has_method("current_output"):
		return float(s.current_output())
	return 0.0


## Записать генератору его нагрузку и отношение мощности к нагрузке.
static func _set_source_budget(s, p_load: float, p_eff: float) -> void:
	if "power_load" in s:
		s.power_load = p_load
	if "efficiency" in s:
		s.efficiency = p_eff


func _set_brownout(on: bool) -> void:
	if on == brownout:
		return
	brownout = on
	brownout_changed.emit(on)


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


# ------------------------------------------------- СОХРАНЕНИЕ (#37)
## Поля забега, которые пишет Save (scripts/core/save.gd). Новое поле состояния
## забега — допишите его имя сюда. Питание и браун-аут не пишутся: их пересчитывает
## первая же раскладка после загрузки.
const SAVE_FIELDS: Array[String] = [
	"time_of_day", "day_number", "tasks_total", "tasks_done", "research", "wave",
	"game_time", "relay_active", "relay_timer", "stats_mined", "stats_crafted",
	"stats_kills", "stats_deaths", "objective_stage",
]


func save_state() -> Dictionary:
	var d: Dictionary = {}
	for f in SAVE_FIELDS:
		d[f] = get(f)
	return d


## Неизвестные ключи игнорируются, отсутствующие — остаются как есть.
func load_state(d: Dictionary) -> void:
	for f in SAVE_FIELDS:
		if d.has(f):
			set(f, d[f])
	set_state(State.PLAYING)
	_power_index_size = -1          ## машины поставлены заново — индекс пересоберётся
	_power_timer = 0.0
