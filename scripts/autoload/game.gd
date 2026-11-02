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
	# scenario_mode НЕ сбрасывается: это режим запуска (--scenario), а не забега.
	# Раннер сценариев зовёт reset_run() перед каждым сценарием — флаг должен
	# пережить сброс, иначе директор угрозы просыпался посреди сценария.
	objective_stage = 0
	# --- Цель и релей (#32)
	relay_speed = 1.0
	_objective_t = 0.0
	_power_index_size = -1          ## мир мог смениться — индекс пересоберётся
	# --- Исследования (#28): дерево и журнал живут один забег.
	Tech.reset()
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
		day_started.emit(day_number)
		notify("Смена %d. Фантомы голоднее." % day_number, Color(0.9, 0.9, 0.7))
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


# ------------------------------------------------- ЦЕЛЬ И РЕЛЕЙ (ADR-001 § 4.7, #32)
## Четыре этапа цели. Этап выводится из состояния забега раз в
## OBJECTIVE_CHECK_INTERVAL и только растёт:
##   1. Запитать станцию — оба терминала базы прочитаны (читаются они только
##      под питанием); +10 данных и главы 1–2 дают сами терминалы, релей отзывается.
##   2. Собрать данные — открыт узел T5: антенна релея в рецептах сборщика.
##   3. Собрать релей — E у ядра с полным набором relay_req запускает отсчёт.
##   4. Удержать сигнал — Balance.RELAY_TIME с; директор угрозы в режиме релея
##      (cap RELAY_HOLD_CAP, двойник — сразу после разведчика). Победа → эпилог Lore.
## Этап можно перескочить (данные с анализаторов, детали из тайников): сигнал
## objective_changed тогда уходит один раз — сразу с новым номером.

const OBJECTIVE_STAGES: int = 4
const OBJECTIVE_CHECK_INTERVAL: float = 0.25
## Названия этапов для HUD и инвентаря (индекс — номер этапа).
const OBJECTIVE_TITLES: Array = ["", "ЗАПИТАТЬ СТАНЦИЮ", "СОБРАТЬ ДАННЫЕ", "СОБРАТЬ РЕЛЕЙ", "УДЕРЖАТЬ СИГНАЛ"]
## Отметки отсчёта (секунд до конца), на которых игроку напоминают, сколько держаться.
const RELAY_REMINDERS: Array = [150, 120, 90, 60, 30, 10]
const RELAY_COLOR: Color = Color(0.4, 1.0, 0.8)

## Ускорение отсчёта релея — для тестов (сценарий relay). В игре всегда 1.
var relay_speed: float = 1.0
var _objective_t: float = 0.0


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
	var target: int = objective_target()
	if target > objective_stage:
		_enter_stage(target)


## Этап, до которого игрок дошёл: первый невыполненный, релей запущен — четвёртый.
func objective_target() -> int:
	if relay_active or state == State.WON:
		return 4
	if not base_terminals_done():
		return 1
	if not Tech.is_unlocked("T5"):
		return 2
	return 3


## Оба терминала базы отработали (главы 1–2 у Lore — терминалы базы).
## Отработавший терминал уходит из World.terminals, но остаётся в terminal_chapters.
func base_terminals_done() -> bool:
	var n: int = 0
	for c in World.terminal_chapters.keys():
		if int(World.terminal_chapters[c]) >= Lore.BASE_TERMINALS:
			continue
		if World.terminals.has(c):
			return false
		n += 1
	return n > 0


## Строка этапа для HUD/инвентаря: «ЦЕЛЬ 3/4: СОБРАТЬ РЕЛЕЙ», на удержании — с отсчётом.
func objective_text() -> String:
	var s: int = clampi(objective_stage, 1, OBJECTIVE_STAGES)
	var head: String = "ЦЕЛЬ %d/%d: %s" % [s, OBJECTIVE_STAGES, OBJECTIVE_TITLES[s]]
	if relay_active:
		head += " — %d с" % ceili(relay_timer)
	return head


func _enter_stage(s: int) -> void:
	set_objective_stage(s)
	var bp: Vector2 = World.cell_to_world(World.beacon_cell)
	match s:
		1:
			notify("Цель 1/4: запитать станцию — оба терминала базы под питанием.", Color(0.5, 0.95, 0.8))
		2:
			notify("Станция ожила: релей отзывается. Цель 2/4: открыть узел T5 «Релей».", RELAY_COLOR)
			UI.flash_ring(bp, RELAY_COLOR)
			Sfx.play("power", -8.0)
		3:
			notify("Цель 3/4: собрать релей-ядро — антенна релея в рецептах сборщика.", RELAY_COLOR)
			UI.flash_ring(bp, RELAY_COLOR)
		4:
			notify("Цель 4/4: удержать сигнал %d с. Они идут." % int(RELAY_TIME), RELAY_COLOR)


func _tick_relay(dt: float) -> void:
	var before: float = relay_timer
	relay_timer -= dt
	for r in RELAY_REMINDERS:
		if before > float(r) and relay_timer <= float(r) and relay_timer > 0.0:
			notify("Сигнал: осталось %d с." % int(r), Color(0.6, 0.95, 1.0))
	if relay_timer <= 0.0:
		relay_timer = 0.0
		relay_active = false
		notify("СИГНАЛ УШЁЛ НА ОРБИТУ. ЭВАКУАЦИЯ!", Color(0.4, 1.0, 0.7))
		set_state(State.WON)


## Итоги забега для Lore.epilogue(): смены, убитые фантомы, смерти, время.
func epilogue_stats() -> Dictionary:
	return {"days": day_number, "kills": stats_kills, "deaths": stats_deaths, "time": game_time}


## Попытка запустить релей-ядро. Возвращает true, если запуск прошёл.
func try_finish() -> bool:
	if not Net.is_authority():   # СЕТЬ (ADR-002): релей запускает хост
		return false
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
	notify("РЕЛЕЙ ЗАПУЩЕН! Держитесь %d секунд." % int(RELAY_TIME), RELAY_COLOR)
	Sfx.play("power", -2.0)
	update_objective()          # этап 4 — сразу, а не через 0.25 с
	return true


# ------------------------------------------------- СОХРАНЕНИЕ (#37)
## Поля забега, которые пишет Save (scripts/core/save.gd). Новое поле состояния
## забега — допишите его имя сюда. Питание и браун-аут не пишутся: их пересчитывает
## первая же раскладка после загрузки.
const SAVE_FIELDS: Array[String] = [
	"time_of_day", "day_number", "tasks_total", "tasks_done", "research", "wave",
	"game_time", "relay_active", "relay_timer", "stats_mined", "stats_crafted",
	"stats_kills", "stats_deaths", "objective_stage",
	"relay_speed",                       # цель и релей (#32)
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
	if relay_active:
		relay_timer = maxf(0.0, relay_timer - delta * relay_speed)


## Хост: глобальное состояние для NetCodec.encode_global (hash кладёт NetWorld).
func net_global() -> Dictionary:
	return {"time": time_of_day, "day": day_number, "state": state, "research": research,
			"stage": objective_stage, "relay_active": relay_active, "relay_timer": relay_timer,
			"tasks_done": tasks_done, "tasks_total": tasks_total,
			"threat": 1 if Threat.active else 0, "threat_budget": Threat.budget,
			"brownout": brownout, "game_time": game_time}


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
	research = int(d["research"])
	tasks_total = int(d["tasks_total"])
	if int(d["tasks_done"]) != tasks_done:
		tasks_done = int(d["tasks_done"])
		task_completed.emit(tasks_total, tasks_done)
	relay_active = bool(d["relay_active"])
	relay_timer = float(d["relay_timer"])
	var stage: int = int(d["stage"])
	if stage > objective_stage:
		_enter_stage(stage)
	else:
		set_objective_stage(stage)
	_set_brownout(bool(d["brownout"]))
	Threat.active = (int(d["threat"]) & 1) != 0
	Threat.budget = float(d["threat_budget"])
	set_state(int(d["state"]))
