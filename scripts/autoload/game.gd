extends Node
## Глобальное состояние: время суток, волны фантомов, задания, прогресс, цель игры.

signal notification(text: String, color: Color)
signal task_completed(total: int, done: int)
signal state_changed(state: int)
## Новая смена началась — рассвет, ночь кончилась (ADR-001, § 4.1).
signal day_started(day: int)
## Этап цели сменился (ADR-001, § 4.7; этапы ведёт #32).
signal objective_changed(stage: int)
## Выдан следующий чертёж (имя предмета из BLUEPRINT_ORDER). Панель крафта
## сбрасывает кэш списка рецептов.
signal blueprint_changed(name: String)

enum State { PLAYING, DEAD, WON }

const DAY_LENGTH: float = Balance.DAY_LENGTH
const RELAY_TIME: float = Balance.RELAY_TIME

var state: int = State.PLAYING
var time_of_day: float = Balance.START_TIME ## доля цикла: старт на рассвете (NIGHT_END)
var day_number: int = 1
var tasks_total: int = 0
var tasks_done: int = 0
## Чертежи команды (ADR-005 § 7.1, #169): имена предметов из BLUEPRINT_ORDER
## в порядке выдачи. Не предмет — запись. В сети пока локально: маска в global
## ждёт очереди PROTO (эпик #182).
var blueprints: PackedStringArray = PackedStringArray()
var wave: int = 0
var phantoms_alive: int = 0
var game_time: float = 0.0
var player = null                      ## Ссылка на игрока (без типа — цикла зависимостей).
var relay_req: Dictionary = {}
## Вклад деталей в ядро (глава «Сигнал», сеть #139). Свободная игра его не требует:
## там запуск — семь дуг. Старый файл без словаря читается как пустой вклад.
var relay_have: Dictionary = {}
var relay_active: bool = false
var relay_timer: float = 0.0
## Семь дуг Радужного ядра (ADR-005 § 6.3, #175): бит i — цвет 1 << i зажжён.
## Живут в забеге, не в блоке: ядро сняли — дуги не гаснут.
var core_arcs: int = 0
## Клетка активного ядра. (-1, -1) — ядра нет, возрождение у капсулы лагеря.
var core_cell: Vector2i = Vector2i(-1, -1)
## Все поставленные ядра, последнее — активное.
var core_cells: Array[Vector2i] = []
## Радужный кот (#176). Выходит из клетки активного ядра (core_cell).
## IN_CORE — сидит, заряд полон. OUT — летит. RECHARGE — сидит, копит луч.
enum CatState { IN_CORE, OUT, RECHARGE }
var cat_state: int = CatState.IN_CORE
## Секунды луча, уже накопленные в ядре. Полон при CAT_RECHARGE.
var cat_charge: float = Balance.CAT_RECHARGE
var cat_timer: float = 0.0
## Уже выходил в эту ночь после сигнала. Сбрасывается на рассвете.
var _cat_night: bool = false
var stats_mined: int = 0
var stats_crafted: int = 0
var stats_kills: int = 0
var stats_deaths: int = 0              ## Смертей за забег (респаун — #29).
## Сценарии сами создают фантомов: директор угрозы (Threat, #27) при этом
## флаге волны не ведёт. Ставит main.gd.
var scenario_mode: bool = false
## Этап цели свободной игры (временно, #169; F1 перепишет окончательно):
## 0 — не начато, 1 — запитать станцию, 2 — собрать релей, 3 — удержать сигнал.
var objective_stage: int = 0
## Глава кампании (Mission, scripts/campaign/) или null — свободная игра. Без типа —
## как player: цикл autoload → class_name. Цель главы заменяет четыре этапа релея:
## update_objective молчит, трекер HUD показывает задачи главы.
var mission = null

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
	# СЕТЬ (#139): требование релея от числа героев — на входе и выходе героя.
	player_joined.connect(_on_heroes_changed.unbind(1))
	player_left.connect(_on_heroes_changed.unbind(1))


## Сброс забега (при перезапуске сцены).
func reset_run() -> void:
	state = State.PLAYING
	time_of_day = Balance.START_TIME
	day_number = 1
	tasks_done = 0
	blueprints = PackedStringArray()
	wave = 0
	game_time = 0.0
	relay_active = false
	relay_timer = 0.0
	core_arcs = 0
	core_cell = Vector2i(-1, -1)
	core_cells = []
	cat_state = CatState.IN_CORE
	cat_charge = Balance.CAT_RECHARGE
	cat_timer = 0.0
	_cat_night = false
	stats_mined = 0
	stats_crafted = 0
	stats_kills = 0
	stats_deaths = 0
	# scenario_mode НЕ сбрасывается: это режим запуска (--scenario), а не забега.
	# Раннер сценариев зовёт reset_run() перед каждым сценарием — флаг должен
	# пережить сброс, иначе директор угрозы просыпался посреди сценария.
	objective_stage = 0
	mission = null                  # главу создаёт main.gd после сброса (Campaign.start)
	# --- Цель и релей (#32)
	relay_speed = 1.0
	_objective_t = 0.0
	relay_req = DB.relay_req.duplicate()   # требование от N (#139) — с одиночного
	relay_have = {}
	relay_unattended = false
	signal_sent = false             # бесконечная игра (#174)
	signal_sends = 0
	_power_index_size = -1          ## мир мог смениться — индекс пересоберётся
	# --- Журнал и чертежи (#169): живут один забег.
	Tech.reset()
	_apply_blueprint_flag()
	_power_timer = 0.0
	power_output_total = 0.0
	power_load_total = 0.0
	power_unpowered = 0
	_set_brownout(false)


func _process(delta: float) -> void:
	if not Net.is_authority():   # СЕТЬ (ADR-002, § 4.2.6): у клиента — только свои часы
		_net_client_process(delta)
		return
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
		_cat_night = false
		day_started.emit(day_number)
		notify("Смена %d. Фантомы голоднее." % day_number, Color(0.9, 0.9, 0.7))
	_tick_cat(delta)
	_tick_objective(delta)


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


## Иконка последнего уведомления. Сигнал остаётся (text, color): лишний аргумент
## ломает чужие connect. HUD читает last_note_icon.
var last_note_icon: int = 0


func notify(text: String, color: Color = Color(0.85, 0.9, 1.0), icon: int = 0) -> void:
	last_note_icon = icon
	notification.emit(text, color)


func complete_task() -> void:
	tasks_done += 1
	task_completed.emit(tasks_total, tasks_done)
	notify("Задание выполнено! (%d/%d)" % [tasks_done, tasks_total], Color(0.4, 0.95, 0.6))


# ---------------------------------------------------------- ЧЕРТЕЖИ (#169)
## Имена из Balance.BLUEPRINT_ORDER, которые уже есть в IDs.I. Отсутствующие
## (их заводят C*, E2, F1) пропускаются с предупреждением — после слияния список
## заработает целиком без правок здесь. Кэш на состав IDs: за забег он не меняется.
var _bp_order: PackedStringArray = PackedStringArray()
var _bp_ids: PackedInt32Array = PackedInt32Array()
var _bp_ready: bool = false


func _ensure_blueprint_order() -> void:
	if _bp_ready:
		return
	_bp_ready = true
	_bp_order = PackedStringArray()
	_bp_ids = PackedInt32Array()
	var known: Dictionary = IDs.I
	for name in Balance.BLUEPRINT_ORDER:
		var key: String = String(name)
		if not known.has(key):
			push_warning("чертёж «%s» пропущен: предмета ещё нет в IDs.I" % key)
			continue
		_bp_order.append(key)
		_bp_ids.append(int(known[key]))


## Имена чертежей, которые игра уже умеет выдавать (подмножество BLUEPRINT_ORDER).
func blueprint_order() -> PackedStringArray:
	_ensure_blueprint_order()
	return _bp_order


## Сколько чертежей игра умеет выдать сейчас (знаменатель строки «N из M»).
func blueprint_total() -> int:
	return blueprint_order().size()


## Есть ли чертёж на предмет (по id или по имени из BLUEPRINT_ORDER).
func has_blueprint(item_id) -> bool:
	_ensure_blueprint_order()
	var name: String = ""
	if item_id is String:
		name = String(item_id)
	else:
		var i: int = _bp_ids.find(int(item_id))
		if i < 0:
			return false
		name = String(_bp_order[i])
	return blueprints.has(name)


## id предмета i-го доступного чертежа (−1 — нет такого).
func blueprint_item_id(i: int) -> int:
	_ensure_blueprint_order()
	if i < 0 or i >= _bp_ids.size():
		return -1
	return int(_bp_ids[i])


## Имя предмета по id чертежа (пусто — предмета нет или это не чертёж).
func blueprint_name(item_id: int) -> String:
	_ensure_blueprint_order()
	var i: int = _bp_ids.find(item_id)
	if i < 0:
		return ""
	return String(_bp_order[i])


## Подпись предмета чертежа: имя из DB, если предмет уже есть, иначе имя из списка.
func blueprint_label(name: String) -> String:
	_ensure_blueprint_order()
	var i: int = _bp_order.find(name)
	if i < 0:
		return name
	return DB.item_name(int(_bp_ids[i]))


## Следующий ещё не выданный чертёж: имя или "" , если всё выдано.
func next_blueprint_name() -> String:
	for name in blueprint_order():
		if not blueprints.has(name):
			return String(name)
	return ""


## id следующего чертежа (−1 — всё выдано или список пуст).
func next_blueprint_id() -> int:
	var name: String = next_blueprint_name()
	if name == "":
		return -1
	return blueprint_item_id(blueprint_order().find(name))


## Выдать следующий чертёж из списка. id предмета или −1, если всё выдано.
## Уведомление и кольцо — у вызывающего (терминал знает место).
func give_next_blueprint() -> int:
	var name: String = next_blueprint_name()
	if name == "":
		return -1
	blueprints.append(name)
	blueprint_changed.emit(name)
	return blueprint_item_id(blueprints.size() - 1)


## --blueprints=all: все доступные чертежи сразу (сценарии, как раньше unlock_to).
func _apply_blueprint_flag() -> void:
	if not OS.get_cmdline_user_args().has("--blueprints=all"):
		return
	blueprints = blueprint_order().duplicate()


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
	if not Net.is_authority():   # СЕТЬ (ADR-002): питание считает хост
		return
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


# ------------------------------------------------- ЦЕЛЬ И ЯДРО (ADR-005 § 6.3, #175)
## Четыре этапа свободной игры. Этап выводится из состояния забега раз в
## OBJECTIVE_CHECK_INTERVAL и только растёт:
##   1. Поставить ядро — постройки RainbowCore ещё нет.
##   2. Зажечь семь дуг — луч чистого цвета в клетку ядра ставит бит core_arcs.
##   3. Запустить ядро — E 3 с у активного ядра, если горят все семь.
##   4. Удержать сигнал — Balance.RELAY_TIME с; директор угрозы в режиме релея
##      (cap RELAY_HOLD_CAP, двойник — сразу после разведчика). Победа → эпилог Lore.
## Терминалы базы в этапах не участвуют: это журнал и подарок (D2, #169).
## Старое сохранение с этапом > 4 сжимается в 4.

const OBJECTIVE_STAGES: int = 4
const OBJECTIVE_CHECK_INTERVAL: float = 0.25
## Названия этапов для HUD и инвентаря (индекс — номер этапа).
const OBJECTIVE_TITLES: Array = ["", "ПОСТАВЬ ЯДРО", "ЗАЖГИ СЕМЬ ДУГ", "ЗАПУСТИ ЯДРО", "УДЕРЖИ СИГНАЛ"]
## Имена семи дуг: индекс — бит core_arcs, значение — маска Beams.
const CORE_ARC_COLOR: Array[int] = [Beams.R, Beams.G, Beams.B, Beams.Y, Beams.C, Beams.M, Beams.W]
## Все семь дуг горят.
const CORE_ARCS_FULL: int = 0x7F
## Отметки отсчёта (секунд до конца), на которых игроку напоминают, сколько держаться.
const RELAY_REMINDERS: Array = [150, 120, 90, 60, 30, 10]
const RELAY_COLOR: Color = Color(0.4, 1.0, 0.8)

## Ускорение отсчёта удержания — для тестов (сценарий relay). В игре всегда 1.
var relay_speed: float = 1.0
var _objective_t: float = 0.0
## Сеть: отсчёт стоит — у ядра нет живого не спрятавшегося героя (§ 4.7, «зона удержания»).
var relay_unattended: bool = false
## Кот уже выходил в это удержание (#176). Сбрасывается вместе с отсчётом.
var _core_cat_hatched: bool = false
## Сигнал уже уходил на орбиту (ADR-005 § 6.4, #174): игрок остался на планете.
## Пишется в сохранение и в глобальный пакет. Повторный запуск ядра возможен.
var signal_sent: bool = false
## Сколько раз сигнал удержан до конца (эпилог «вторая передача» — со второй).
var signal_sends: int = 0


func _tick_objective(delta: float) -> void:
	_objective_t -= delta
	if _objective_t <= 0.0:
		_objective_t = OBJECTIVE_CHECK_INTERVAL
		update_objective()
	if relay_active:
		_tick_relay(delta * relay_speed)


## Пересчитать этап цели сейчас (обычно — сам раз в 0.25 с; публичная — для тестов).
func update_objective() -> void:
	if not Net.is_authority():   # СЕТЬ (ADR-002): этап цели приходит от хоста
		return
	if in_mission():             # КАМПАНИЯ: цель — задачи главы, этапы релея молчат
		return
	var target: int = objective_target()
	if target > objective_stage:
		_enter_stage(target)


## Идёт ли глава кампании (Game.mission жив).
func in_mission() -> bool:
	return mission != null and is_instance_valid(mission)


## Этап, до которого игрок дошёл: ядра нет — 1, дуг не семь — 2, не запущено — 3.
func objective_target() -> int:
	if relay_active or state == State.WON:
		return 4
	if not core_placed():
		return 1
	if (core_arcs & CORE_ARCS_FULL) != CORE_ARCS_FULL:
		return 2
	return 3


## Стоит ли хоть одно ядро (активная клетка жива).
func core_placed() -> bool:
	var core = World.machines.get(core_cell)
	return core_cell.x >= 0 and core != null and String(core.kind) == "RainbowCore"


## Сколько дуг уже горит (0..7).
func core_arc_count() -> int:
	var n: int = 0
	var bits: int = core_arcs & CORE_ARCS_FULL
	while bits != 0:
		n += bits & 1
		bits >>= 1
	return n


## Имя цвета дуги (маска Beams) или «?» у чужого бита.
func core_color_name(color: int) -> String:
	if color > 0 and color < Beams.NAME.size():
		return Beams.NAME[color]
	return "?"


## Имена цветов, которых ещё нет среди семи дуг.
func core_missing_names() -> Array:
	var out: Array = []
	for i in CORE_ARC_COLOR.size():
		if (core_arcs & (1 << i)) == 0:
			out.append(core_color_name(CORE_ARC_COLOR[i]))
	return out


## Картинка этапа для карточки «Сейчас»: ядро, пока оно есть в предметах.
## В главе картинку даёт цель главы.
func objective_icon() -> int:
	if in_mission():
		return -1
	return IDs.I.RAINBOW_CORE


## Куда вести маркер карточки. Ядро стоит — к нему; нет — к сундуку лагеря.
## Нет точки — Vector2.INF. В главе точку даёт цель.
func objective_at() -> Vector2:
	if in_mission():
		return Vector2.INF
	if core_placed():
		return World.cell_to_world(core_cell)
	if World.camp_chest_cell.x >= 0:
		return World.cell_to_world(World.camp_chest_cell)
	return Vector2.INF


## Строка этапа для HUD/инвентаря: «ЦЕЛЬ 2/3: СОБРАТЬ РЕЛЕЙ», на удержании — с отсчётом.
func objective_text() -> String:
	var s: int = clampi(objective_stage, 1, OBJECTIVE_STAGES)
	var head: String = "ЦЕЛЬ %d/%d: %s" % [s, OBJECTIVE_STAGES, OBJECTIVE_TITLES[s]]
	if relay_active:
		head += " — %d с" % ceili(relay_timer)
	return head


func _enter_stage(s: int) -> void:
	set_objective_stage(s)
	var bp: Vector2 = _core_pos()
	match s:
		1:
			notify("Цель 1/4: поставь Радужное ядро. Оно в сундуке лагеря.", Color(0.5, 0.95, 0.8))
		2:
			notify("Ядро стоит. Цель 2/4: зажги семь дуг — по лучу каждого цвета.", RELAY_COLOR)
			UI.flash_ring(bp, RELAY_COLOR)
		3:
			notify("Семь дуг горят. Цель 3/4: удерживай E у ядра 3 с.", RELAY_COLOR)
			UI.flash_ring(bp, RELAY_COLOR)
			Sfx.play("power", -8.0)
		4:
			notify("Цель 4/4: удержать сигнал %d с. Они идут." % int(RELAY_TIME), RELAY_COLOR)
			UI.flash_ring(bp, RELAY_COLOR)


func _tick_relay(dt: float) -> void:
	_hatch_cat_if_night()
	if not _relay_hold_ok():   # СЕТЬ (ADR-002 § 4.7): у ядра никого — отсчёт стоит
		return
	var before: float = relay_timer
	relay_timer -= dt
	for r in RELAY_REMINDERS:
		if before > float(r) and relay_timer <= float(r) and relay_timer > 0.0:
			notify("Сигнал: осталось %d с." % int(r), Color(0.6, 0.95, 1.0))
	if relay_timer <= 0.0:
		relay_timer = 0.0
		relay_active = false
		signal_sends += 1
		var again: bool = signal_sent
		signal_sent = true
		if again:
			notify("ВТОРАЯ ПЕРЕДАЧА. Сигнал снова ушёл на орбиту.", Color(0.4, 1.0, 0.7))
		else:
			notify("СИГНАЛ УШЁЛ НА ОРБИТУ. ЭВАКУАЦИЯ!", Color(0.4, 1.0, 0.7))
		set_state(State.WON)


# ------------------------------------------------- РАДУЖНЫЙ КОТ (#176)
## Выходит из клетки активного ядра (core_cell). Ночь удержания зовёт
## RainbowCore.cat_hatch(); после сигнала — каждую ночь, если заряд полон.

## Мировая точка ядра. Ядра нет — капсула лагеря.
func cat_home() -> Vector2:
	var c: Vector2i = core_cell if core_cell.x >= 0 else World.beacon_cell
	return World.cell_to_world(c)


## Крючок выхода. Ядро зовёт его из cat_hatch(); тесты могут звать сами.
## Без типа RainbowCat: class_name в автозагрузке замыкает загрузку машин.
func cat_hatch_at(at: Vector2 = Vector2.INF):
	if not Net.is_authority():
		return null
	if cat_state != CatState.IN_CORE or cat_charge < Balance.CAT_RECHARGE:
		return null
	var script: GDScript = load("res://scripts/entities/rainbow_cat.gd")
	if script.live != null and is_instance_valid(script.live):
		return null
	var pos: Vector2 = at if at != Vector2.INF else cat_home()
	var cat = script.create(pos)
	World.add_world_node(cat)
	cat.global_position = pos
	cat_state = CatState.OUT
	cat_timer = Balance.CAT_TIME
	notify("Радужный кот вышел из ядра.", Color(0.85, 0.7, 1.0))
	return cat


## Кот сел в ядро: заряд с нуля, пока в клетку не попадёт луч.
func cat_returned() -> void:
	if not Net.is_authority():
		return
	cat_state = CatState.RECHARGE
	cat_charge = 0.0
	cat_timer = 0.0
	notify("Кот в ядре. Ему нужен луч — %d с." % int(Balance.CAT_RECHARGE), Color(0.7, 0.85, 1.0))


## Маска луча, упёршегося в ядро. В клетке приёмника color_at пуст: луч обрывается перед ней.
func _cat_beam_mask() -> int:
	var core = World.machines.get(core_cell) if core_cell.x >= 0 else null
	if core == null:
		return 0
	return int(core.get("_beam")) & 7


## Любой луч в клетку ядра кормит перезарядку. Дуги зажигает ядро само.
func _cat_drink(dt: float) -> void:
	cat_beam(_cat_beam_mask(), dt)


## Любой луч в клетку ядра кормит перезарядку.
func cat_beam(mask: int, dt: float) -> void:
	if not Net.is_authority() or cat_state != CatState.RECHARGE:
		return
	if (mask & 7) == 0 or dt <= 0.0:
		return
	cat_charge = minf(Balance.CAT_RECHARGE, cat_charge + dt)
	if cat_charge >= Balance.CAT_RECHARGE:
		cat_state = CatState.IN_CORE
		notify("Кот заряжен. Ждёт ночь.", Color(0.85, 0.7, 1.0))


func cat_charged() -> bool:
	return cat_state == CatState.IN_CORE and cat_charge >= Balance.CAT_RECHARGE


## Ночь после сигнала — каждую, если заряжен. Ночь удержания зовёт _tick_relay.
func _tick_cat(delta: float) -> void:
	if cat_state == CatState.OUT:
		cat_timer = maxf(0.0, cat_timer - delta)
		return
	if cat_state == CatState.RECHARGE:
		_cat_drink(delta)
		return
	if cat_state != CatState.IN_CORE or not cat_charged():
		return
	if signal_sent and is_night() and not _cat_night:
		_cat_night = true
		cat_hatch_at()


## Первая ночь удержания: кот выходит из активного ядра.
func _hatch_cat_if_night() -> void:
	if _core_cat_hatched or not is_night() or not core_placed() or not cat_charged():
		return
	_core_cat_hatched = true
	var core = World.machines.get(core_cell)
	if core != null and core.has_method("cat_hatch"):
		core.cat_hatch()
		if cat_state == CatState.IN_CORE:
			cat_hatch_at()
		return
	cat_hatch_at()


## Итоги забега для Lore.epilogue(): смены, убитые фантомы, смерти, время.
## signal_sends > 1 — повторное удержание, эпилог помечает «вторая передача».
func epilogue_stats() -> Dictionary:
	return {"days": day_number, "kills": stats_kills, "deaths": stats_deaths, "time": game_time,
			"sends": signal_sends}


## После сигнала игрок остаётся (ADR-005 § 6.4, #174): PLAYING, ядро и дуги на месте,
## ночи идут прежней формулой (THREAT_RELAY — только пока relay_active). Новой цели нет.
## Повторный запуск ядра возможен: ещё RELAY_TIME удержания — ещё эпилог.
func continue_run() -> void:
	if state != State.WON:
		return
	signal_sent = true
	set_state(State.PLAYING)
	notify("Остаёмся. Смена %d · сигнал отправлен." % day_number, Color(0.4, 1.0, 0.8))


## Попытка запустить ядро (E 3 с). Свободная игра — семь дуг. Глава и сеть
## сначала сдают детали (relay_req), потом запускают, если набрано всё.
## hero — кто держит E. true — отсчёт пошёл.
func try_finish(hero = null) -> bool:
	if in_mission():
		return _try_finish_parts(hero)
	return core_launch()


## Глава «Сигнал» и сеть: вклад деталей, затем запуск. Свободную игру не трогает.
func _try_finish_parts(hero = null) -> bool:
	if not Net.is_authority():
		return false
	if hero == null:
		hero = player
	if hero == null or relay_active:
		return false
	var given: Array = relay_deposit(hero)
	var missing: Array = []
	for id in relay_req.keys():
		var have: int = relay_count(id)
		if have < int(relay_req[id]):
			missing.append("%s (%d/%d)" % [DB.item_name(id), have, int(relay_req[id])])
	if not missing.is_empty():
		if not given.is_empty():
			_relay_say(hero, "В релей сдано: " + ", ".join(given), RELAY_COLOR, true)
		_relay_say(hero, "Релею не хватает: " + ", ".join(missing), Color(1.0, 0.6, 0.4), false)
		return false
	relay_have = {}
	_net_relay_changed()
	relay_active = true
	relay_timer = RELAY_TIME
	_core_cat_hatched = false
	notify("РЕЛЕЙ ЗАПУЩЕН! Держитесь %d секунд." % int(RELAY_TIME), RELAY_COLOR)
	Sfx.play("power", -2.0)
	update_objective()
	return true


## Сколько деталей id уже сдано в ядро.
func relay_count(id: int) -> int:
	return int(relay_have.get(id, 0))


## Вклад деталей из инвентаря героя — то, чего ядру ещё не хватает.
func relay_deposit(hero) -> Array:
	var given: Array = []
	if not Net.is_authority() or hero == null or relay_active:
		return given
	for id in relay_req.keys():
		var n: int = mini(int(relay_req[id]) - relay_count(id), hero.inv.count_of(id))
		if n <= 0:
			continue
		hero.inv.remove_id(id, n)
		relay_have[id] = relay_count(id) + n
		given.append("%s ×%d" % [DB.item_name(id), n])
	if not given.is_empty():
		hero.stats_changed.emit()
		_net_relay_changed()
	return given


## Уведомление вклада: в одиночной — Game.notify. В сети — команде или лично.
func _relay_say(hero, text: String, color: Color, team: bool) -> void:
	if not Net.is_online():
		notify(text, color)
	elif team:
		NetCoop.team_notify("%s: %s" % [String(hero.nick), text], color)
	else:
		hero._notify(text, color)


## Запуск ядра: семь дуг, ядро стоит, отсчёт ещё не идёт. Иначе — перечень
## недостающих цветов. true — отсчёт пошёл.
func core_launch() -> bool:
	if not Net.is_authority():   # СЕТЬ (ADR-002): ядро запускает хост
		return false
	if relay_active or not core_placed():
		return false
	if (core_arcs & CORE_ARCS_FULL) != CORE_ARCS_FULL:
		var missing: Array = core_missing_names()
		notify("Не хватает дуг: " + ", ".join(missing), Color(1.0, 0.6, 0.4))
		return false
	relay_active = true
	relay_timer = RELAY_TIME
	_core_cat_hatched = false
	notify("ЯДРО ЗАПУЩЕНО! Держитесь %d секунд." % int(RELAY_TIME), RELAY_COLOR)
	Sfx.play("power", -2.0)
	UI.flash_ring(_core_pos(), Color.WHITE)
	_net_core_changed()
	update_objective()          # этап 4 — сразу, а не через 0.25 с
	return true


## Луч чистого цвета попал в ядро. Бит ставится один раз, дуга не гаснет.
func core_feed(color: int) -> void:
	if not Net.is_authority():
		return
	var bit: int = _arc_bit(color)
	if bit == 0 or (core_arcs & bit) != 0:
		return
	core_arcs |= bit
	var n: int = core_arc_count()
	notify("Дуга «%s» зажглась (%d/7)" % [core_color_name(color), n], Beams.COLOR[color])
	UI.flash_ring(_core_pos(), Beams.COLOR[color])
	_net_core_changed()
	update_objective()


## Бит дуги по маске цвета. 0 — это не один из семи чистых.
func _arc_bit(color: int) -> int:
	var i: int = CORE_ARC_COLOR.find(color)
	if i < 0:
		return 0
	return 1 << i


## Поставили ядро: последнее становится активным. Дуги не трогаем.
func core_note_placed(c: Vector2i) -> void:
	if not Net.is_authority():
		return
	core_cells.erase(c)
	core_cells.append(c)
	core_cell = c
	_net_core_changed()
	update_objective()


## Сняли ядро. Активным становится другое, если есть.
func core_note_removed(c: Vector2i) -> void:
	if not Net.is_authority():
		return
	core_cells.erase(c)
	if core_cell != c:
		return
	core_cell = core_cells[core_cells.size() - 1] if not core_cells.is_empty() else Vector2i(-1, -1)
	_net_core_changed()


## Мировая точка активного ядра (нет ядра — центр лагеря).
func _core_pos() -> Vector2:
	if core_cell.x >= 0:
		return World.cell_to_world(core_cell)
	return World.cell_to_world(World.beacon_cell)


## Куда встаёт герой после смерти: клетка над ядром, если свободна, иначе
## ближайшая свободная. Нет ядра — капсула лагеря.
func respawn_point() -> Vector2:
	if not core_placed():
		return World.spawn_point
	var above: Vector2i = core_cell + Vector2i(0, -1)
	if _stand_free(above):
		return _stand_pos(above)
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: int = 1 << 30
	for r in range(1, 8):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c: Vector2i = core_cell + Vector2i(dx, dy)
				if not _stand_free(c):
					continue
				var d: int = absi(dx) + absi(dy)
				if d < best_d:
					best_d = d
					best = c
		if best.x >= 0:
			break
	if best.x < 0:
		return World.spawn_point
	return _stand_pos(best)


## Герой (12×22) помещается в клетке, не в стене и не в постройке.
func _stand_free(c: Vector2i) -> bool:
	if not World.in_bounds(c.x, c.y):
		return false
	if World.machines.has(c):
		return false
	var p: Vector2 = _stand_pos(c)
	return not World.rect_solid(Rect2(p - Player.SIZE * 0.5, Player.SIZE))


func _stand_pos(c: Vector2i) -> Vector2:
	return World.cell_to_world(c) + Vector2(0.0, -4.0)


# ------------------------------------------------- СОХРАНЕНИЕ (#37)
## Поля забега, которые пишет Save (scripts/core/save.gd). Новое поле состояния
## забега — допишите его имя сюда. Питание и браун-аут не пишутся: их пересчитывает
## первая же раскладка после загрузки.
const SAVE_FIELDS: Array[String] = [
	"time_of_day", "day_number", "tasks_total", "tasks_done", "wave",
	"game_time", "relay_active", "relay_timer", "stats_mined", "stats_crafted",
	"stats_kills", "stats_deaths", "objective_stage",
	"relay_speed",                       # цель и релей (#32)
	"relay_have",                        # вклад деталей (глава и сеть, #94)
	"core_arcs", "core_cell",            # дуги и активное ядро (#175)
	"signal_sent", "signal_sends",       # бесконечная игра (#174)
	"blueprints",                        # чертежи команды (ADR-005 § 7.1, #169)
]


func save_state() -> Dictionary:
	var d: Dictionary = {}
	for f in SAVE_FIELDS:
		d[f] = get(f)
	d["relay_have"] = relay_have.duplicate()
	d["blueprints"] = blueprints.duplicate()
	d["core_cell"] = core_cell
	return d


## Неизвестные ключи игнорируются, отсутствующие — остаются как есть.
func load_state(d: Dictionary) -> void:
	for f in SAVE_FIELDS:
		if d.has(f):
			set(f, d[f])
	if not d.has("relay_have"):
		relay_have = {}
	relay_have = relay_have.duplicate()
	if d.has("core_cell"):
		core_cell = d["core_cell"]
	core_arcs = int(d.get("core_arcs", core_arcs)) & 0x7F
	# Поле "research" старых сохранений игнорируется: счётчик данных снят (#169).
	if d.has("blueprints"):
		blueprints = PackedStringArray(d["blueprints"])
	else:
		blueprints = PackedStringArray()
	# Старый этап > 4 сжимается в удержание.
	if objective_stage > OBJECTIVE_STAGES:
		objective_stage = OBJECTIVE_STAGES
	_rebuild_cores()
	# Требование от N (#139): клиент берёт хостово из снимка входа, хост и одиночная
	# считают сами (не ниже загруженного вклада).
	if Net.is_client():
		if d.get("relay_req") is Dictionary:
			relay_req = (d["relay_req"] as Dictionary).duplicate()
	else:
		relay_req_update()
	set_state(State.PLAYING)
	_power_index_size = -1          ## машины поставлены заново — индекс пересоберётся
	_power_timer = 0.0
	_apply_blueprint_flag()         # --blueprints=all важнее файла: сценарии так и ждут


# ------------------------------------------------- СЕТЬ (ADR-002)
## Крюки MP-A (#86, § 5.1 правило 1): объявления без логики. Героев по пирам
## заводит MP-D (#89); в одиночной игре списки пусты и ни на что не влияют.
## Игрок вошёл в сессию / вышел из неё (аргумент — Player).
signal player_joined(p)
signal player_left(p)
## Все герои сессии (свой, прокси у хоста, марионетки у клиента).
var players: Array = []
## Свой герой этого процесса (без типа — цикла зависимостей).
var local_player = null

# --- Мир по сети (MP-C, #88; § 4.2.6): часы клиента и глобальный пакет.
## Клиент сам двигает time_of_day той же формулой и подтягивается к хосту, если
## разница больше NET_CLOCK_SNAP цикла (0.5 с). Смена, этап, данные, релей, угроза —
## из глобального пакета хоста (1 Гц и сразу по событию). Питание, цель и релей
## у клиента не считаются (Net.is_authority() в update_power_budget, update_objective,
## try_finish и в начале _process).
const NET_CLOCK_SNAP: float = 0.002
## Узел мира по сети (scripts/net/net_world.gd): живёт под Game, без сессии молчит.
var net_world: NetWorld = null
## Клиент: сколько раз часы подтянуты к хосту.
var net_clock_snaps: int = 0
## Узел машин и предметов по сети (scripts/net/net_machines.gd, MP-E #90).
var net_machines: NetMachines = null


func _enter_tree() -> void:
	if net_world == null:
		net_world = NetWorld.new()
		net_world.name = "NetWorld"
		add_child.call_deferred(net_world)
	# --- Машины и предметы по сети (MP-E, #90): после NetWorld — в физическом кадре
	# идёт следом за ним (дельты тайлов раньше построек и предметов).
	if net_machines == null:
		net_machines = NetMachines.new()
		net_machines.name = "NetMachines"
		add_child.call_deferred(net_machines)


## Клиент: только часы забега (и отсчёт релея для HUD между пакетами — победу
## объявляет хост).
func _net_client_process(delta: float) -> void:
	if state != State.PLAYING:
		return
	game_time += delta
	time_of_day = fmod(time_of_day + delta / DAY_LENGTH, 1.0)
	if relay_active and _relay_hold_ok():   # MP-I (#94): без присмотра отсчёт стоит и здесь
		relay_timer = maxf(0.0, relay_timer - delta * relay_speed)


## Хост: глобальное состояние для NetCodec.encode_global (hash кладёт NetWorld).
## Поле research в пакете — заглушка 0. Чертежи в пакет не кладём — битовая маска
## ждёт очереди PROTO (эпик #182). Дуги и клетка ядра — хвост global (#175, PROTO 15).
func net_global() -> Dictionary:
	return {"time": time_of_day, "day": day_number, "state": state, "research": 0,
			"stage": objective_stage, "relay_active": relay_active, "relay_timer": relay_timer,
			"tasks_done": tasks_done, "tasks_total": tasks_total,
			# бит 1 — сигнал уже отправлен (#174): отдельного поля в пакете нет, PROTO не растёт
			"threat": (1 if Threat.active else 0) | (2 if signal_sent else 0),
			"threat_budget": Threat.budget,
			"brownout": brownout, "game_time": game_time,
			"core_arcs": core_arcs & CORE_ARCS_FULL, "core_cell": core_cell}


## Клиент: глобальный пакет хоста. Рассвет и этап цели — с теми же уведомлениями,
## что видит хост (тексты — как в _process и _enter_stage).
func net_apply_global(d: Dictionary) -> void:
	var t: float = float(d["time"])
	if absf(wrapf(t - time_of_day, -0.5, 0.5)) > NET_CLOCK_SNAP:
		time_of_day = t
		net_clock_snaps += 1
	game_time = float(d["game_time"])
	var day: int = int(d["day"])
	var new_day: bool = day > day_number
	day_number = day
	if new_day:
		day_started.emit(day)
		notify("Смена %d. Фантомы голоднее." % day, Color(0.9, 0.9, 0.7))
	# d["research"] — заглушка старого пакета (счётчик данных снят, #169): не читаем.
	tasks_total = int(d["tasks_total"])
	if int(d["tasks_done"]) != tasks_done:
		tasks_done = int(d["tasks_done"])
		task_completed.emit(tasks_total, tasks_done)
	relay_active = bool(d["relay_active"])
	relay_timer = float(d["relay_timer"])
	if d.has("core_arcs"):
		core_arcs = int(d["core_arcs"]) & CORE_ARCS_FULL
	if d.has("core_cell"):
		core_cell = d["core_cell"]
	var stage: int = int(d["stage"])
	if stage > objective_stage:
		_enter_stage(stage)
	else:
		set_objective_stage(stage)
	_set_brownout(bool(d["brownout"]))
	var th: int = int(d["threat"])
	Threat.active = (th & 1) != 0
	signal_sent = (th & 2) != 0
	Threat.budget = float(d["threat_budget"])
	set_state(int(d["state"]))


# --- Кооператив (MP-I, #94; § 4.7): зона удержания релея и вклад деталей по сети.
## Отсчёт релея в сети идёт, пока хотя бы один живой не спрятавшийся герой на связи
## ближе Balance.MP_RELAY_HOLD_RADIUS_TILES к ядру; иначе стоит (не сбрасывается),
## HUD и уведомление — «Сигнал без присмотра». Только в сети (решение #99): одиночный
## баланс откалиброван. Каждый процесс считает сам по позициям всех героев (у клиента —
## свой и марионетки), поэтому и его отсчёт между глобальными пакетами стоит вместе с хостом.
const RELAY_UNATTENDED_TEXT: String = "Сигнал без присмотра: у ядра никого — отсчёт стоит."


## true — отсчёт релея сейчас идёт (в одиночной — всегда).
func _relay_hold_ok() -> bool:
	if not Net.is_online():
		return true
	var ok: bool = relay_attended()
	if ok == relay_unattended:
		relay_unattended = not ok
		if relay_unattended:
			notify(RELAY_UNATTENDED_TEXT, Color(1.0, 0.55, 0.35))
		else:
			notify("Сигнал снова под присмотром — отсчёт идёт.", RELAY_COLOR)
	return ok


## Есть ли у ядра живой не спрятавшийся герой на связи.
func relay_attended() -> bool:
	var bp: Vector2 = _core_pos()
	var r: float = Balance.MP_RELAY_HOLD_RADIUS_TILES * float(World.TILE)
	for h in players:
		if is_instance_valid(h) and h.is_inside_tree() and h.net_targetable() \
				and h.global_position.distance_to(bp) < r:
			return true
	return false


## Хост: вклад деталей или требование изменились — кадр RELAY, как до ядра (#139).
func _net_relay_changed() -> void:
	if Net.is_host():
		Net.send_on(0, NetCodec.Msg.COOP, NetCodec.encode_coop_relay(relay_have, relay_req))


## Клиент: вклад и требование с хоста.
func net_apply_relay(have: Dictionary, req: Dictionary) -> void:
	relay_have = have.duplicate()
	if not req.is_empty() and req != relay_req:
		relay_req = req.duplicate()


## Хост: дуги или клетка ядра изменились — кадр CORE (#175).
func _net_core_changed() -> void:
	if Net.is_host():
		Net.send_on(0, NetCodec.Msg.COOP, NetCodec.encode_coop_core(core_arcs, core_cell))


## Клиент: дуги и клетка активного ядра с хоста.
func net_apply_core(arcs: int, cell: Vector2i) -> void:
	core_arcs = arcs & CORE_ARCS_FULL
	core_cell = cell


# --- Требование релея от N (#139; ADR-002 § 4.7 «Релей вчетвером»).
## Требование = DB.relay_req × (1 + Balance.MP_RELAY_REQ_PER_PLAYER·(N − 1)), по детали —
## до ближайшего целого; N — героев в сессии (Game.players). Пересчитывает хост на входе и
## выходе героя и при загрузке; клиент получает итог в COOP RELAY и в снимке входа. Уже
## сданное в ядро не теряется: требование детали не ниже relay_count(id) — ушёл товарищ, и
## сверх нового требования сданное просто засчитано. При N = 1 — ровно DB.relay_req.

## Множитель требования релея при n героях.
static func relay_req_scale(n: int) -> float:
	return 1.0 + Balance.MP_RELAY_REQ_PER_PLAYER * float(maxi(n, 1) - 1)


## Требование при n героях (с учётом уже сданного в ядро).
func relay_req_for(n: int) -> Dictionary:
	var k: float = relay_req_scale(n)
	var out: Dictionary = {}
	for id in DB.relay_req.keys():
		var need: int = int(DB.relay_req[id])
		if n > 1:
			need = roundi(float(need) * k)
		out[id] = maxi(need, relay_count(int(id)))
	return out


## Героев в сессии (в одиночной — 1).
func hero_count() -> int:
	return maxi(players.size(), 1)


## После загрузки: какие ядра реально стоят. Активное из файла, если оно живо.
func _rebuild_cores() -> void:
	core_cells = []
	for c in World.machines.keys():
		var m = World.machines[c]
		if m != null and String(m.kind) == "RainbowCore":
			core_cells.append(c)
	var active = World.machines.get(core_cell)
	if core_cell.x >= 0 and (active == null or String(active.kind) != "RainbowCore"):
		core_cell = core_cells[core_cells.size() - 1] if not core_cells.is_empty() else Vector2i(-1, -1)
	elif core_cell.x < 0 and not core_cells.is_empty():
		core_cell = core_cells[core_cells.size() - 1]


## Хост и одиночная: пересчитать требование по числу героев. Изменилось — клиентам
## (COOP RELAY) и уведомление команде. true — требование изменилось.
func relay_req_update() -> bool:
	if Net.is_client():
		return false
	var req: Dictionary = relay_req_for(hero_count())
	if req == relay_req:
		return false
	relay_req = req
	_net_relay_changed()
	if Net.is_online() and not relay_active and state == State.PLAYING:
		NetCoop.team_notify("Героев на связи: %d — релею нужно деталей ×%.2f." % [hero_count(),
				relay_req_scale(hero_count())], RELAY_COLOR)
	return true


func _on_heroes_changed() -> void:
	relay_req_update()
