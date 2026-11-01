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
func is_powered(p: Vector2) -> bool:
	for m in World.machines.values():
		if m.power_active and m.power_radius > 0.0:
			if p.distance_to(m.global_position) <= m.power_radius * World.TILE:
				return true
	return false


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
