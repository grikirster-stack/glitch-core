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
var relay_active: bool = false
var relay_timer: float = 0.0
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
	relay_have = {}                 # вклад деталей в ядро (MP-I, #94)
	relay_req = DB.relay_req.duplicate()   # требование от N (#139) — с одиночного
	relay_unattended = false
	signal_sent = false             # бесконечная игра (#174)
	signal_sends = 0
	# --- Журнал и чертежи (#169): живут один забег.
	Tech.reset()
	_apply_blueprint_flag()


func _process(delta: float) -> void:
	if not Net.is_authority():   # СЕТЬ (ADR-002, § 4.2.6): у клиента — только свои часы
		_net_client_process(delta)
		return
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
	## на границе ночи (NIGHT_START) ровно COLLECTOR_MIN_DAYLIGHT — коллектор
	## молчит в ту же секунду, когда начинается ночь.
	var t: float = time_of_day
	var dawn: float = Balance.NIGHT_END
	var night: float = Balance.NIGHT_START
	var solar: float = Balance.COLLECTOR_MIN_DAYLIGHT
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


## Терминал всегда доступен: питания больше нет (#170, ADR-005 § 7).
## Имя и аргумент оставлены — HUD и сценарии спрашивают ту же функцию.
func is_powered(_p: Vector2) -> bool:
	return true


# ------------------------------------------------- ЦЕЛЬ И РЕЛЕЙ (ADR-001 § 4.7, #32)
## Три этапа цели (временно, #169: «собрать данные» снят вместе с деревом;
## F1 перепишет этапы окончательно). Этап выводится из состояния забега раз в
## OBJECTIVE_CHECK_INTERVAL и только растёт:
##   1. Запитать станцию — оба терминала базы прочитаны (читаются они только
##      под питанием); главы 1–2 дают сами терминалы, релей отзывается.
##   2. Собрать релей — E у ядра (держать 3 с) сдаёт из инвентаря героя то, чего
##      ядру ещё не хватает (relay_have, ADR-002 § 4.7, MP-I #94 — во всех режимах);
##      набрано всё — отсчёт пошёл. С полным набором — как раньше, одним удержанием.
##   3. Удержать сигнал — Balance.RELAY_TIME с; директор угрозы в режиме релея
##      (cap RELAY_HOLD_CAP, двойник — сразу после разведчика). Победа → эпилог Lore.
## Этап можно перескочить (детали из тайников): сигнал objective_changed тогда
## уходит один раз — сразу с новым номером.
## Старое сохранение с этапом 4 («удержать») при загрузке сжимается в 3.

const OBJECTIVE_STAGES: int = 3
const OBJECTIVE_CHECK_INTERVAL: float = 0.25
## Названия этапов для HUD и инвентаря (индекс — номер этапа).
const OBJECTIVE_TITLES: Array = ["", "ЗАПИТАТЬ СТАНЦИЮ", "СОБРАТЬ РЕЛЕЙ", "УДЕРЖАТЬ СИГНАЛ"]
## Отметки отсчёта (секунд до конца), на которых игроку напоминают, сколько держаться.
const RELAY_REMINDERS: Array = [150, 120, 90, 60, 30, 10]
const RELAY_COLOR: Color = Color(0.4, 1.0, 0.8)

## Ускорение отсчёта релея — для тестов (сценарий relay). В игре всегда 1.
var relay_speed: float = 1.0
var _objective_t: float = 0.0
## Вклад деталей в релей-ядро: id → сколько уже сдано (MP-I, #94). Пишется в сохранение.
var relay_have: Dictionary = {}
## Сеть: отсчёт стоит — у ядра нет живого не спрятавшегося героя (§ 4.7, «зона удержания»).
var relay_unattended: bool = false
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


## Этап, до которого игрок дошёл: первый невыполненный, релей запущен — третий.
func objective_target() -> int:
	if relay_active or state == State.WON:
		return 3
	if not base_terminals_done():
		return 1
	return 2


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


## Картинка этапа для карточки «Сейчас»: IDs.I или −1 (тогда HUD рисует пиктограмму).
## В главе картинку даёт цель главы. Этап 3 — антенна релея; этапы 1–2 без предмета.
func objective_icon() -> int:
	if in_mission():
		return -1
	var s: int = clampi(objective_stage, 1, OBJECTIVE_STAGES)
	if relay_active:
		s = OBJECTIVE_STAGES
	if s == 3:
		return IDs.I.RELAY_ANTENNA
	return -1


## Куда вести маркер карточки. Этап 3 и удержание — релей-ядро; этап 1 — ближайший
## непрочитанный терминал базы. Нет точки — Vector2.INF. В главе точку даёт цель.
func objective_at() -> Vector2:
	if in_mission():
		return Vector2.INF
	var s: int = clampi(objective_stage, 1, OBJECTIVE_STAGES)
	if relay_active:
		s = OBJECTIVE_STAGES
	# Этап 2 — собрать релей у ядра; этап 3 — удержать сигнал там же.
	if s == 2 or s == 3:
		return World.cell_to_world(World.beacon_cell)
	if s == 1:
		return _nearest_unread_terminal()
	return Vector2.INF


## Ближайший к герою терминал базы, который ещё не прочитан (главы 1–2).
func _nearest_unread_terminal() -> Vector2:
	var best: Vector2 = Vector2.INF
	var best_d: float = INF
	var origin: Vector2 = player.global_position if player != null else World.cell_to_world(World.beacon_cell)
	for c in World.terminal_chapters.keys():
		if int(World.terminal_chapters[c]) >= Lore.BASE_TERMINALS:
			continue
		if not World.terminals.has(c):
			continue
		var p: Vector2 = World.cell_to_world(c)
		var d: float = origin.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = p
	return best


## Строка этапа для HUD/инвентаря: «ЦЕЛЬ 2/3: СОБРАТЬ РЕЛЕЙ», на удержании — с отсчётом.
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
			notify("Цель 1/3: запитать станцию — оба терминала базы под питанием.", Color(0.5, 0.95, 0.8))
		2:
			notify("Станция ожила: релей отзывается. Цель 2/3: собрать релей-ядро.", RELAY_COLOR)
			UI.flash_ring(bp, RELAY_COLOR)
			Sfx.play("power", -8.0)
		3:
			notify("Цель 3/3: удержать сигнал %d с. Они идут." % int(RELAY_TIME), RELAY_COLOR)
			UI.flash_ring(bp, RELAY_COLOR)


func _tick_relay(dt: float) -> void:
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


## Попытка запустить релей-ядро: сначала вклад деталей героя hero (по умолчанию —
## Game.player), потом запуск, если набрано всё. Возвращает true, если запуск прошёл.
func try_finish(hero = null) -> bool:
	if not Net.is_authority():   # СЕТЬ (ADR-002): релей запускает хост
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
	notify("РЕЛЕЙ ЗАПУЩЕН! Держитесь %d секунд." % int(RELAY_TIME), RELAY_COLOR)
	Sfx.play("power", -2.0)
	update_objective()          # этап 3 — сразу, а не через 0.25 с
	return true


## Сколько деталей id уже сдано в ядро.
func relay_count(id: int) -> int:
	return int(relay_have.get(id, 0))


## Вклад деталей (ADR-002 § 4.7, MP-I #94): из инвентаря героя — то, чего ядру ещё не
## хватает. Итог — строки «Предмет ×N» сданного (пусто — нечего было сдать).
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


## Уведомление релея: в одиночной — как раньше (Game.notify). В сети: team — всем с
## ником героя, иначе — лично ему (у прокси — владельцу).
func _relay_say(hero, text: String, color: Color, team: bool) -> void:
	if not Net.is_online():
		notify(text, color)
	elif team:
		NetCoop.team_notify("%s: %s" % [String(hero.nick), text], color)
	else:
		hero._notify(text, color)


# ------------------------------------------------- СОХРАНЕНИЕ (#37)
## Поля забега, которые пишет Save (scripts/core/save.gd). Новое поле состояния
## забега — допишите его имя сюда. Питание и браун-аут не пишутся: их пересчитывает
## первая же раскладка после загрузки.
const SAVE_FIELDS: Array[String] = [
	"time_of_day", "day_number", "tasks_total", "tasks_done", "wave",
	"game_time", "relay_active", "relay_timer", "stats_mined", "stats_crafted",
	"stats_kills", "stats_deaths", "objective_stage",
	"relay_speed",                       # цель и релей (#32)
	"relay_have",                        # вклад деталей в релей (MP-I, #94)
	"signal_sent", "signal_sends",       # бесконечная игра (#174)
	"blueprints",                        # чертежи команды (ADR-005 § 7.1, #169)
]


func save_state() -> Dictionary:
	var d: Dictionary = {}
	for f in SAVE_FIELDS:
		d[f] = get(f)
	d["relay_have"] = relay_have.duplicate()   # снимок, а не ссылка на живой словарь
	d["blueprints"] = blueprints.duplicate()
	return d


## Неизвестные ключи игнорируются, отсутствующие — остаются как есть.
func load_state(d: Dictionary) -> void:
	for f in SAVE_FIELDS:
		if d.has(f):
			set(f, d[f])
	if not d.has("relay_have"):     # файл до MP-I (#94): вклада ещё не было
		relay_have = {}
	relay_have = relay_have.duplicate()
	# Поле "research" старых сохранений игнорируется: счётчик данных снят (#169).
	if d.has("blueprints"):
		blueprints = PackedStringArray(d["blueprints"])
	else:
		blueprints = PackedStringArray()
	# Старый этап 4 («удержать сигнал») — теперь третий. Этап 2 «собрать данные»
	# снят: после запитанной станции сразу сборка релея, если он ещё не запущен.
	if objective_stage > OBJECTIVE_STAGES or (objective_stage == 2 and relay_active):
		objective_stage = OBJECTIVE_STAGES
	# Требование от N (#139): клиент берёт хостово из снимка входа, хост и одиночная
	# считают сами (не ниже загруженного вклада).
	if Net.is_client():
		if d.get("relay_req") is Dictionary:
			relay_req = (d["relay_req"] as Dictionary).duplicate()
	else:
		relay_req_update()
	set_state(State.PLAYING)
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
## у клиента не считаются (Net.is_authority() в update_objective,
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
## Поле research в пакете — заглушка 0: длина global не меняется без бампа PROTO.
## Чертежи в пакет не кладём — битовая маска ждёт очереди PROTO (эпик #182).
func net_global() -> Dictionary:
	return {"time": time_of_day, "day": day_number, "state": state, "research": 0,
			"stage": objective_stage, "relay_active": relay_active, "relay_timer": relay_timer,
			"tasks_done": tasks_done, "tasks_total": tasks_total,
			# бит 1 — сигнал уже отправлен (#174): отдельного поля в пакете нет, PROTO не растёт
			"threat": (1 if Threat.active else 0) | (2 if signal_sent else 0),
			"threat_budget": Threat.budget,
			"brownout": false, "game_time": game_time}


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
	var stage: int = int(d["stage"])
	if stage > objective_stage:
		_enter_stage(stage)
	else:
		set_objective_stage(stage)
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
	var bp: Vector2 = World.cell_to_world(World.beacon_cell)
	var r: float = Balance.MP_RELAY_HOLD_RADIUS_TILES * float(World.TILE)
	for h in players:
		if is_instance_valid(h) and h.is_inside_tree() and h.net_targetable() \
				and h.global_position.distance_to(bp) < r:
			return true
	return false


## Хост: вклад в ядро или требование изменились — всем (канал 0, после снимка — по порядку).
func _net_relay_changed() -> void:
	if Net.is_host():
		Net.send_on(0, NetCodec.Msg.COOP, NetCodec.encode_coop_relay(relay_have, relay_req))


## Клиент: вклад в ядро и требование с хоста (#139: требование от N считает хост).
func net_apply_relay(have: Dictionary, req: Dictionary) -> void:
	relay_have = have.duplicate()
	if not req.is_empty() and req != relay_req:
		relay_req = req.duplicate()


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
