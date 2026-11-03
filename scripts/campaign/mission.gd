class_name Mission
extends Node
## Глава кампании: готовая база на сиде Campaign.SEED, задачи по этапам, свои волны
## фантомов и итог главы (ADR-004).
##
## Наследник (scripts/campaign/missions/) задаёт в _init() описание (id, chapter,
## title, brief, teaches) и переопределяет:
##   build()       — достроить базу поверх мира сида (CampaignBase.build + своё);
##   kit()         — стартовый набор героя [[id предмета, число], …];
##   stages()      — этапы по порядку: {title, hint, say: [строки ПСА], enter: Callable,
##                   goals: [[текст, Callable → Vector2i(есть, нужно)], …]};
##   fail_reason() — непустая строка — глава провалена (почему);
##   on_tick(dt)   — своё поведение каждый кадр (держать сумерки, ускорить релей…);
##   outro()       — текст экрана победы.
## Этап пройден, когда выполнены все его задачи; выполненная задача не «откатывается»
## (хлам потратили на ТЭЦ — задача «накопать хлам» остаётся выполненной). Последний
## этап пройден — победа: Game.State.WON, отметка в профиле (Campaign.mark_done).
##
## Волны: wave(вид, вентиляция, через сколько с) — телеграф из той вентиляции
## (Threat.telegraph); запечатанная решёткой — фантом выйдет из ближайшей открытой
## (Threat.request_spawn). Пока director = false, директор угрозы ночь не ведёт.
##
## Сеть (ADR-002): логика главы — только у хоста (и в одиночной). Клиент держит
## «марионетку» (puppet = true): она ничего не считает, а показывает state() хоста —
## снимок входа несёт его в поле mission (Save.gather_join), дальше — кадр MISSION
## при каждой смене и раз в NET_RESEND_SEC. Базу клиент получает обычным снимком мира.

## Голос главы — бортовой ИИ станции «Кербер-9».
const VOICE: String = "ПЁС"
const C_VOICE: Color = Color(0.55, 0.9, 1.0)
const C_WIN: Color = Color(0.4, 1.0, 0.7)
const C_LOSE: Color = Color(1.0, 0.45, 0.4)
## Задачи проверяются раз в столько секунд.
const CHECK_SEC: float = 0.25
## Хост повторяет кадр MISSION не реже, с.
const NET_RESEND_SEC: float = 1.0

enum Result { RUNNING, WON, LOST }

# --- описание главы (наследник задаёт в _init)
var id: String = ""
var chapter: int = 0
var title: String = ""
## Завязка для меню кампании: одна-две фразы.
var brief: String = ""
## Чему учит глава — строка для меню.
var teaches: String = ""
## true — ночь ведёт штатный директор угрозы (Threat), иначе — волны главы.
var director: bool = false
## Доля суток на старте главы.
var start_time: float = Balance.START_TIME
## Солнце «стоит» на этой доле суток (< 0 — время идёт как обычно): главам без ночи
## не нужен закат посреди обучения, осаде — ночь, пока база не готова.
var hold_time: float = -1.0

# --- состояние (state() / apply_state())
var stage: int = 0
var stage_title: String = ""
## Задачи текущего этапа для показа: [{text, have, need}].
var goals: Array = []
var hint: String = ""
var result: int = Result.RUNNING
var result_title: String = ""
var result_text: String = ""
## Клиент: только показ состояния хоста.
var puppet: bool = false

var _stages: Array = []
var _stages_total: int = 0          ## марионетка: этапов у хоста
var _latched: Dictionary = {}
var _check_t: float = 0.0
var _net_t: float = 0.0
var _net_hash: int = 0
## Запланированные фантомы: [{t, kind, vent}].
var _waves: Array = []


# ------------------------------------------------------------------ ДЛЯ НАСЛЕДНИКА

func build() -> void:
	pass


func kit() -> Array:
	return []


func stages() -> Array:
	return []


func fail_reason() -> String:
	return ""


func on_tick(_delta: float) -> void:
	pass


func outro() -> String:
	return ""


# ------------------------------------------------------------------ ЗАПУСК

## Хост и одиночная: база, время, первый этап. Зовёт Campaign.start.
func begin() -> void:
	_stages = stages()
	Game.time_of_day = start_time
	build()
	Game.update_power_budget()
	Game.tasks_total = World.terminals.size() + Game.tasks_done
	say("Глава %d. %s" % [chapter, title])
	_enter(0)


## Стартовый набор героя (свой и каждого товарища в сети).
func give_kit(p) -> void:
	for e in kit():
		p.inv.add(int(e[0]), int(e[1]))


func _process(delta: float) -> void:
	if puppet or not Net.is_authority():
		return
	if result == Result.RUNNING and Game.state == Game.State.PLAYING:
		if hold_time >= 0.0 and Game.time_of_day > hold_time and Game.time_of_day < hold_time + 0.25:
			Game.time_of_day = hold_time
		_tick_waves(delta)
		on_tick(delta)
		_check_t -= delta
		if _check_t <= 0.0:
			_check_t = CHECK_SEC
			evaluate()
	if Net.is_host():
		_net_t -= delta
		var h: int = hash(state())
		if h != _net_hash or _net_t <= 0.0:
			send_state()


## Проверить задачи сейчас (обычно — сама раз в CHECK_SEC; публичная — для сценариев).
func evaluate() -> void:
	if result != Result.RUNNING or stage >= _stages.size():
		return
	var why: String = fail_reason()
	if why != "":
		lose(why)
		return
	var all_done: bool = true
	var shown: Array = []
	var list: Array = _stages[stage].get("goals", [])
	for i in list.size():
		var g: Array = list[i]
		var v: Vector2i = (g[1] as Callable).call()
		var need: int = maxi(1, v.y)
		if v.x >= need:
			_latched[i] = true
		var done: bool = _latched.has(i)
		shown.append({"text": String(g[0]), "have": need if done else clampi(v.x, 0, need), "need": need})
		if not done:
			all_done = false
	goals = shown
	if all_done:
		_advance()


func _advance() -> void:
	var after: Callable = _stages[stage].get("done", Callable())
	if after.is_valid():
		after.call()
	stage += 1
	if stage >= _stages.size():
		win()
		return
	_enter(stage)


func _enter(i: int) -> void:
	stage = i
	_latched.clear()
	var st: Dictionary = _stages[i]
	stage_title = String(st.get("title", ""))
	hint = String(st.get("hint", ""))
	for line in st.get("say", []):
		say(String(line))
	var enter: Callable = st.get("enter", Callable())
	if enter.is_valid():
		enter.call()
	_check_t = 0.0
	evaluate()


## Глава пройдена: экран победы (main.gd), отметка в профиле.
func win() -> void:
	if result != Result.RUNNING:
		return
	result = Result.WON
	result_title = "ГЛАВА %d ПРОЙДЕНА" % chapter
	result_text = outro()
	goals = []
	hint = ""
	Campaign.mark_done(id)
	send_state()
	Game.set_state(Game.State.WON)


## Глава провалена: why — причина для экрана.
func lose(why: String) -> void:
	if result != Result.RUNNING:
		return
	result = Result.LOST
	result_title = "ГЛАВА ПРОВАЛЕНА"
	result_text = why
	send_state()
	Game.set_state(Game.State.DEAD)


## Забег кончился не по главе (сигнал релея ушёл, хардкор-смерть): итог главы — из
## состояния игры. Зовёт main.gd до показа экрана.
func on_game_state(s: int) -> void:
	if result != Result.RUNNING or puppet or not Net.is_authority():
		return
	if s == Game.State.WON:
		win()
	elif s == Game.State.DEAD:
		lose("Экспедиция погибла.")


# ------------------------------------------------------------------ ВОЛНЫ

## Фантом kind из вентиляции vent через after секунд.
func wave(kind: String, vent: Vector2i, after: float) -> void:
	_waves.append({"t": after, "kind": kind, "vent": vent})


## Сколько фантомов ещё впереди: запланированы, телеграф идёт или они в мире.
func threats_left() -> int:
	return _waves.size() + Threat.pending.size() + get_tree().get_nodes_in_group("phantom").size()


func _tick_waves(delta: float) -> void:
	if _waves.is_empty():
		return
	var keep: Array = []
	for w in _waves:
		w["t"] = float(w["t"]) - delta
		if float(w["t"]) > 0.0:
			keep.append(w)
			continue
		var v: Vector2i = w["vent"]
		if World.vents.has(v) and not World.is_vent_sealed(v):
			Threat.telegraph(v, String(w["kind"]))
		else:
			Threat.request_spawn(String(w["kind"]))
	_waves = keep


# ------------------------------------------------------------------ СЛУЖЕБНОЕ

## Реплика ПСА: всем (в сети — и товарищам).
func say(text: String, color: Color = C_VOICE) -> void:
	var line: String = "%s: %s" % [VOICE, text]
	if Net.is_host():
		NetCoop.team_notify(line, color)
	else:
		Game.notify(line, color)


## Живые герои (в сети — все на связи).
func heroes() -> Array:
	var out: Array = []
	for h in Game.players:
		if is_instance_valid(h) and not bool(h.dead):
			out.append(h)
	if out.is_empty() and Game.player != null and is_instance_valid(Game.player) and not Game.player.dead:
		out.append(Game.player)
	return out


## Сколько предмета id у всех героев.
func heroes_have(id_item: int) -> int:
	var n: int = 0
	for h in heroes():
		n += h.inv.count_of(id_item)
	return n


## Сколько предмета id в сундуке (null — 0).
static func chest_has(c, id_item: int) -> int:
	if c == null or not is_instance_valid(c):
		return 0
	var n: int = 0
	for s in c.slots:
		if not s.is_empty() and s.id == id_item:
			n += s.count
	return n


## Сколько построек вида kind в мире.
static func machines_of(kind: String) -> int:
	var n: int = 0
	for c in World.machines:
		var m = World.machines[c]
		if is_instance_valid(m) and not m.is_queued_for_deletion() and String(m.kind) == kind:
			n += 1
	return n


static func flag(cond: bool) -> Vector2i:
	return Vector2i(1 if cond else 0, 1)


# ------------------------------------------------------------------ СЕТЬ

## Состояние для показа (только простые типы — уходит в var_to_bytes).
func state() -> Dictionary:
	var g: Array = []
	for e in goals:
		g.append([String(e["text"]), int(e["have"]), int(e["need"])])
	return {"id": id, "stage": stage, "stages": _stages.size(), "title": stage_title, "goals": g,
			"hint": hint, "result": result, "rt": result_title, "rx": result_text}


func apply_state(d: Dictionary) -> void:
	stage = int(d.get("stage", stage))
	stage_title = String(d.get("title", stage_title))
	hint = String(d.get("hint", hint))
	var g: Array = []
	for e in d.get("goals", []):
		if e is Array and (e as Array).size() == 3:
			g.append({"text": String(e[0]), "have": int(e[1]), "need": int(e[2])})
	goals = g
	_stages_total = int(d.get("stages", _stages_total))
	var r: int = int(d.get("result", result))
	if r == Result.WON and result != Result.WON:
		Campaign.mark_done(id)   # товарищ прошёл главу вместе с хостом
	result = r
	result_title = String(d.get("rt", result_title))
	result_text = String(d.get("rx", result_text))


## Этапов в главе (у марионетки — от хоста).
func stages_total() -> int:
	return _stages.size() if not puppet else _stages_total


## Хост: состояние главы всем клиентам.
func send_state() -> void:
	_net_t = NET_RESEND_SEC
	var d: Dictionary = state()
	_net_hash = hash(d)
	if Net.is_host():
		Net.send(NetCodec.Msg.MISSION, NetCodec.encode_mission(d))
