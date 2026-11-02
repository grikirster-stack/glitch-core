extends Node
## Директор угрозы (ADR-001, § 4.5). Заменяет main.gd::_update_waves.
##
## Ночь (и удержание сигнала релея) получает бюджет очков угрозы:
##   T   = смена + 0.5·работающих генераторов + 0.02·ламп игрока + 4·релей
##   B   = 3 + 2·T                      — очков на ночь
##   cap = min(2 + смена, 10), при релее RELAY_HOLD_CAP — единиц одновременно
##   интервал = clamp(7 − 0.5·T, 2.5, 7) с между появлениями
## На бюджет в начале ночи составляется состав (plan_roster): эхо вперемешку
## с открытыми к этой ночи типами, дорогие — пока хватает очков. Стая роя
## для cap — одна единица.
##
## Спавн — из трёх ближайших к игроку незапечатанных вентиляций (взвешенно
## по дистанции): сигнал vent_warning(cell) + гул vent_hum, через
## VENT_TELEGRAPH секунд — фантом. Подходящих вентиляций нет — прежний поиск
## пещеры, без телеграфа.
##
## В сценариях (--scenario, флаг scenario_mode) директор молчит; сценарий
## может вести его вручную через tick(). В --test волны идут, как и раньше.
##
## Чёрный ящик, подобранный игроком, вскрывается здесь же: +данные и обрывок
## журнала (Tech.add_fragment, #28).

## Вентиляция «выдыхает»: через VENT_TELEGRAPH с отсюда выйдет фантом.
## FX (пар, #34) подключается к этому сигналу.
signal vent_warning(cell: Vector2i)
## Фантом (или каждый из стаи) появился в мире.
signal phantom_spawned(ph: Node)

## Порядок «дорогих» типов в составе ночи: сперва самые новые.
const SPECIALS: Array[String] = ["doppel", "burrower", "shade", "swarm"]
## Гул вентиляций в сумерках — громкость ниже, чем у телеграфа.
const DUSK_HUM_DB: float = -20.0
const TELEGRAPH_HUM_DB: float = -14.0
## Как часто пересчитываем «лампы игрока» для T, с.
const LIGHT_RECOUNT: float = 2.0

var active: bool = false            ## идёт ли сейчас ночь/удержание сигнала
var night_day: int = 0              ## номер смены текущей ночи
var budget: float = 0.0             ## бюджет ночи (для HUD/отладки)
var roster: Array[String] = []      ## кто ещё выйдет этой ночью
var spawn_timer: float = 0.0
var spawned_total: int = 0          ## сколько фантомов вышло за забег
var pending: Array = []             ## телеграфы: {cell, kind, t, hum}

var _relay_seen: bool = false
var _pack_seq: int = 0
var _dusk_hums: Array = []          ## ручки гула сумерек
var _player_lights: int = 0
var _light_t: float = 0.0
var _lights_size: int = -1
var _inv_bound: Object = null       ## инвентарь, к которому подключены
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


## Сброс на новый забег (main.gd и раннер сценариев после Game.reset_run()).
func reset() -> void:
	for p in pending:
		Sfx.loop_stop(int(p["hum"]))
	pending.clear()
	_stop_dusk_hum()
	active = false
	night_day = 0
	budget = 0.0
	roster.clear()
	spawn_timer = 0.0
	spawned_total = 0
	_relay_seen = false
	_lights_size = -1


func _process(delta: float) -> void:
	_bind_inventory()
	if in_scenario() or Game.state != Game.State.PLAYING:
		return
	tick(delta)


## Идёт ли сценарий. Game.reset_run() сбрасывает Game.scenario_mode, а раннер
## сценариев зовёт его перед каждым сценарием, поэтому смотрим и флаг сцены
## main.gd — он держится весь прогон (так же было у main.gd::_update_waves).
func in_scenario() -> bool:
	if Game.scenario_mode:
		return true
	var sc: Node = get_tree().current_scene
	return sc != null and sc.get("scenario_mode") == true


# ------------------------------------------------------------------ ФОРМУЛЫ

## Уровень угрозы T по формуле § 4.5.
func threat_level() -> float:
	return float(Game.day_number) \
			+ Balance.THREAT_PER_GENERATOR * float(active_generators()) \
			+ Balance.THREAT_PER_LIGHT * float(player_lights()) \
			+ (Balance.THREAT_RELAY if Game.relay_active else 0.0)


## Очков на ночь.
static func night_budget(t: float) -> float:
	return Balance.NIGHT_BUDGET_BASE + Balance.NIGHT_BUDGET_PER_T * t


## Сколько единиц угрозы держим одновременно.
static func cap_for(day: int, relay: bool) -> int:
	if relay:
		return Balance.RELAY_HOLD_CAP
	return mini(Balance.CAP_BASE + day, Balance.CAP_MAX)


## Пауза между появлениями.
static func interval_for(t: float) -> float:
	return clampf(Balance.SPAWN_INTERVAL_MAX - Balance.SPAWN_INTERVAL_PER_T * t,
			Balance.SPAWN_INTERVAL_MIN, Balance.SPAWN_INTERVAL_MAX)


## Открыт ли тип к этой ночи. Двойник — с ночи from_night или на удержании сигнала.
static func kind_open(kind: String, night: int, relay: bool) -> bool:
	var spec: Dictionary = Balance.PHANTOMS[kind]
	if night >= int(spec["from_night"]):
		return true
	return relay and kind == "doppel"


## Состав ночи на бюджет: по кругу «эхо → открытые дорогие типы → эхо»,
## пока хватает очков. Двойник — не больше одного (поле "max").
static func plan_roster(points: float, night: int, relay: bool, doppel_taken: int = 0) -> Array[String]:
	var out: Array[String] = []
	var specials: Array[String] = []
	for k in SPECIALS:
		if kind_open(k, night, relay):
			specials.append(k)
	var echo_cost: float = float(Balance.PHANTOMS["echo"]["cost"])
	var taken: Dictionary = {"doppel": doppel_taken}
	var left: float = points
	while left >= echo_cost:
		var before: int = out.size()
		var round_kinds: Array[String] = ["echo"]
		round_kinds.append_array(specials)
		round_kinds.append("echo")
		for k in round_kinds:
			var spec: Dictionary = Balance.PHANTOMS[k]
			var cost: float = float(spec["cost"])
			if cost > left:
				continue
			if spec.has("max") and int(taken.get(k, 0)) >= int(spec["max"]):
				continue
			out.append(k)
			taken[k] = int(taken.get(k, 0)) + 1
			left -= cost
		if out.size() == before:
			break
	return out


## Работающие генераторы (для T).
func active_generators() -> int:
	var n: int = 0
	for m in World.machines.values():
		if not is_instance_valid(m):
			continue
		var r = m.get("power_radius")
		if (r is float or r is int) and float(r) > 0.0 and bool(m.get("power_active")):
			n += 1
	return n


## Лампы игрока (для T): светокристаллы и прожекторы. Руда-кристалл и
## статичные огни станции не в счёт. Пересчёт — при смене реестра света
## или раз в LIGHT_RECOUNT с.
func player_lights() -> int:
	if World.lights.size() == _lights_size and _light_t > 0.0:
		return _player_lights
	_lights_size = World.lights.size()
	_light_t = LIGHT_RECOUNT
	var n: int = 0
	for e in World.lights:
		var c: Vector2i = World.world_to_cell(e["pos"])
		if World.get_tile_v(c) == IDs.T.LIGHT_CRYSTAL:
			n += 1
	for m in World.machines.values():
		if is_instance_valid(m) and String(m.get("kind")) == "Floodlight":
			n += 1
	_player_lights = n
	return n


## Живые единицы угрозы: каждый фантом — одна, стая роя — одна на всю стаю.
func units_alive() -> int:
	var n: int = 0
	var packs: Dictionary = {}
	for p in get_tree().get_nodes_in_group("phantom"):
		if not is_instance_valid(p) or not bool(p.get("alive")):
			continue
		var pid: int = int(p.get("pack_id"))
		if pid > 0:
			packs[pid] = true
		else:
			n += 1
	return n + packs.size()


func _doppels_alive() -> int:
	var n: int = 0
	for p in get_tree().get_nodes_in_group("phantom"):
		if is_instance_valid(p) and bool(p.get("alive")) and String(p.get("kind")) == "doppel":
			n += 1
	for p in pending:
		if String(p["kind"]) == "doppel":
			n += 1
	return n


# ------------------------------------------------------------------ ТАКТ

## Один шаг директора. _process зовёт его сам вне сценариев; сценарий может
## звать вручную (с любым dt), чтобы прогнать ночь быстрее реального времени.
func tick(delta: float) -> void:
	_light_t -= delta
	Game.phantoms_alive = get_tree().get_nodes_in_group("phantom").size()
	_tick_pending(delta)
	var now_active: bool = Game.is_night() or Game.relay_active
	_update_dusk_hum()
	if now_active and not active:
		_begin_night()
	elif not now_active and active:
		_end_night()
	if not active:
		return
	# Релей запустили посреди ночи — к бюджету добавляется его вклад в T.
	if Game.relay_active and not _relay_seen:
		_relay_seen = true
		var extra: float = Balance.NIGHT_BUDGET_PER_T * Balance.THREAT_RELAY
		budget += extra
		roster.append_array(plan_roster(extra, night_day, true, _doppels_alive()))
	spawn_timer -= delta
	if spawn_timer > 0.0 or roster.is_empty():
		return
	if units_alive() + pending.size() >= cap_for(night_day, Game.relay_active):
		return
	spawn_timer = interval_for(threat_level())
	var kind: String = roster.pop_front()
	if kind == "doppel" and _doppels_alive() > 0:
		return
	if not request_spawn(kind):
		roster.push_front(kind)


func _begin_night() -> void:
	active = true
	night_day = Game.day_number
	Game.wave += 1
	_relay_seen = Game.relay_active
	budget = night_budget(threat_level())
	roster = plan_roster(budget, night_day, Game.relay_active, _doppels_alive())
	# Эхо — первым (разведка), остальное вперемешку.
	var head: Array[String] = []
	if not roster.is_empty() and roster[0] == "echo":
		head.append(roster.pop_front())
	_shuffle(roster)
	head.append_array(roster)
	roster = head
	spawn_timer = minf(interval_for(threat_level()), 3.0)


func _end_night() -> void:
	active = false
	roster.clear()
	_relay_seen = false


func _shuffle(a: Array[String]) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp: String = a[i]
		a[i] = a[j]
		a[j] = tmp


# ------------------------------------------------------------------ СПАВН

## Поставить фантома в очередь появления: из вентиляции — с телеграфом,
## иначе сразу в пещере. false — места не нашлось.
func request_spawn(kind: String) -> bool:
	var ppos: Vector2 = _player_pos()
	var vent: Vector2i = pick_vent(ppos)
	if vent.x >= 0:
		var pos: Vector2 = World.cell_to_world(vent)
		var hum: int = Sfx.loop_start("vent_hum", pos, TELEGRAPH_HUM_DB)
		pending.append({"cell": vent, "kind": kind, "t": Balance.VENT_TELEGRAPH, "hum": hum})
		vent_warning.emit(vent)
		return true
	var cell: Vector2i = find_cave_cell(ppos)
	if cell.x < 0:
		return false
	_spawn_now(kind, World.cell_to_world(cell))
	return true


func _tick_pending(delta: float) -> void:
	if pending.is_empty():
		return
	var keep: Array = []
	for p in pending:
		p["t"] = float(p["t"]) - delta
		if float(p["t"]) > 0.0:
			keep.append(p)
			continue
		Sfx.loop_stop(int(p["hum"]))
		_spawn_now(String(p["kind"]), World.cell_to_world(p["cell"]))
	pending = keep


## Создать фантома (стаю — для роя) в точке. Возвращает созданных.
func spawn_phantom(kind: String, pos: Vector2) -> Array:
	var out: Array = []
	var host: Node = get_tree().current_scene
	if host == null:
		return out
	var pl: Node2D = _player()
	var n: int = 1
	var pid: int = 0
	if kind == "swarm":
		var pack: int = int(Balance.PHANTOMS["swarm"].get("pack", 5))
		n = _rng.randi_range(pack - Balance.SWARM_PACK_SPREAD, pack + Balance.SWARM_PACK_SPREAD)
		_pack_seq += 1
		pid = _pack_seq
	for i in n:
		var p: Phantom = Phantom.create(kind)
		p.player = pl
		p.pack_id = pid
		host.add_child(p)
		if not p.alive:
			continue   # лимит MAX_PHANTOMS: копия растворилась сразу
		var off: Vector2 = Vector2.ZERO
		if n > 1:
			off = Vector2(_rng.randf_range(-10.0, 10.0), _rng.randf_range(-8.0, 4.0))
		p.global_position = pos + off
		p.spawn_point = p.global_position
		out.append(p)
		spawned_total += 1
		phantom_spawned.emit(p)
	return out


func _spawn_now(kind: String, pos: Vector2) -> void:
	var made: Array = spawn_phantom(kind, pos)
	if not made.is_empty() and Game.is_night():
		Sfx.play("alarm", -20.0, 1.6)


## Незапечатанные вентиляции не ближе VENT_SPAWN_MIN_PX и не дальше
## VENT_SPAWN_MAX_PX от игрока, по возрастанию дистанции; первые count.
func nearest_vents(ppos: Vector2, count: int = Balance.VENT_SPAWN_COUNT) -> Array[Vector2i]:
	var cand: Array = []
	for v in World.vents:
		if World.get_tile_v(v) == IDs.T.VENT_GRATE:
			continue
		var d: float = World.cell_to_world(v).distance_to(ppos)
		if d < Balance.VENT_SPAWN_MIN_PX or d > Balance.VENT_SPAWN_MAX_PX:
			continue
		cand.append([d, v])
	cand.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var out: Array[Vector2i] = []
	for i in mini(count, cand.size()):
		out.append(cand[i][1])
	return out


## Вентиляция для спавна: одна из трёх ближайших, вес — 1/дистанция.
func pick_vent(ppos: Vector2) -> Vector2i:
	var vents: Array[Vector2i] = nearest_vents(ppos)
	if vents.is_empty():
		return Vector2i(-1, -1)
	var weights: Array[float] = []
	var total: float = 0.0
	for v in vents:
		var w: float = 1.0 / maxf(1.0, World.cell_to_world(v).distance_to(ppos))
		weights.append(w)
		total += w
	var r: float = _rng.randf() * total
	for i in vents.size():
		r -= weights[i]
		if r <= 0.0:
			return vents[i]
	return vents[vents.size() - 1]


## Прежний поиск пещеры (бывший main.gd::_find_spawn_cell): воздух с полом,
## под поверхностью, не ближе 340 px к игроку.
func find_cave_cell(ppos: Vector2) -> Vector2i:
	for attempt in 400:
		var x: int = _rng.randi_range(8, World.W - 8)
		var top: int = World.surface[x]
		var y: int = _rng.randi_range(top + 6, World.H - 12)
		if World.get_tile(x, y) != IDs.T.AIR:
			continue
		if World.get_tile(x, y + 1) == IDs.T.AIR:
			continue
		var w: Vector2 = World.cell_to_world(Vector2i(x, y))
		if w.distance_to(ppos) < 340.0:
			continue
		return Vector2i(x, y)
	return Vector2i(-1, -1)


## Фантом в пещере сразу, без телеграфа (автотест, отладка).
func spawn_in_cave(kind: String = "echo") -> Array:
	var cell: Vector2i = find_cave_cell(_player_pos())
	if cell.x < 0:
		return []
	return spawn_phantom(kind, World.cell_to_world(cell))


# ------------------------------------------------------------------ СУМЕРКИ

## В сумерках три ближайшие вентиляции гудят — телеграф ночи (§ 4.1).
func _update_dusk_hum() -> void:
	var want: bool = Game.is_dusk() and not in_scenario()
	if want and _dusk_hums.is_empty():
		for v in nearest_vents(_player_pos()):
			_dusk_hums.append(Sfx.loop_start("vent_hum", World.cell_to_world(v), DUSK_HUM_DB))
	elif not want and not _dusk_hums.is_empty():
		_stop_dusk_hum()


func _stop_dusk_hum() -> void:
	for h in _dusk_hums:
		Sfx.loop_stop(int(h))
	_dusk_hums.clear()


# ------------------------------------------------------------------ ЧЁРНЫЙ ЯЩИК

## Подключаемся к инвентарю игрока: подобранный чёрный ящик вскрывается сразу.
func _bind_inventory() -> void:
	var pl = Game.player
	if pl == null or not is_instance_valid(pl):
		return
	var inv = pl.get("inv")
	if inv == null or inv == _inv_bound:
		return
	if _inv_bound != null and is_instance_valid(_inv_bound) \
			and _inv_bound.is_connected("changed", _on_inventory_changed):
		_inv_bound.disconnect("changed", _on_inventory_changed)
	_inv_bound = inv
	inv.connect("changed", _on_inventory_changed)


func _on_inventory_changed() -> void:
	var pl = Game.player
	if pl == null or not is_instance_valid(pl):
		return
	var n: int = int(pl.inv.count_of(IDs.I.BLACK_BOX))
	if n <= 0:
		return
	pl.inv.remove_id(IDs.I.BLACK_BOX, n)
	for i in n:
		open_black_box()


## Вскрыть чёрный ящик: данные и обрывок журнала.
func open_black_box() -> void:
	Game.research += Balance.BLACK_BOX_DATA
	var text: String = Lore.fragment(_rng)
	Tech.add_fragment(text)
	Game.notify("Чёрный ящик: +%d данных. «%s»" % [Balance.BLACK_BOX_DATA, text], Color(0.95, 0.6, 0.35))


# ------------------------------------------------------------------ СЛУЖЕБНОЕ

func _player() -> Node2D:
	var pl = Game.player
	if pl != null and is_instance_valid(pl):
		return pl
	return get_tree().get_first_node_in_group("player")


func _player_pos() -> Vector2:
	var pl: Node2D = _player()
	return pl.global_position if pl != null else World.spawn_point


# ------------------------------------------------------------------ СОХРАНЕНИЕ (#37)
## Фантомы поштучно не сохраняются: их ИИ (путь, заморозка двойника, стая, цель
## роя) — большая поверхность сериализации, а ночь и так случайна. Вместо этого
## живые фантомы и те, что ждут в вентиляции, возвращаются в начало очереди ночи
## (roster): после загрузки они заново выходят из вентиляций с телеграфом. Так
## загрузка ночью не стирает угрозу (от ночи не спрятаться через F9) и не
## удваивает её (бюджет ночи не пересчитывается заново).

func save_state() -> Dictionary:
	var back: Array = []
	var packs: Dictionary = {}
	var alive: int = 0
	for p in get_tree().get_nodes_in_group("phantom"):
		if not is_instance_valid(p) or not bool(p.get("alive")):
			continue
		alive += 1
		var pid: int = int(p.get("pack_id"))
		if pid > 0:
			if packs.has(pid):
				continue
			packs[pid] = true
		back.append(String(p.get("kind")))
	for p in pending:
		back.append(String(p["kind"]))
	back.append_array(roster)
	return {
		"active": active,
		"night_day": night_day,
		"budget": budget,
		"roster": back,
		"spawn_timer": spawn_timer,
		"spawned_total": maxi(0, spawned_total - alive),   ## вернувшиеся выйдут и посчитаются заново
		"relay_seen": _relay_seen,
		"pack_seq": _pack_seq,
		"rng_state": _rng.state,
	}


## Фантомы текущего мира уходят без следа (не убиты: stats_kills не растёт),
## телеграфы и гул сумерек глушатся, очередь ночи — из файла.
func load_state(d: Dictionary) -> void:
	for p in pending:
		Sfx.loop_stop(int(p["hum"]))
	pending.clear()
	_stop_dusk_hum()
	for p in get_tree().get_nodes_in_group("phantom"):
		if is_instance_valid(p):
			if p.get_parent() != null:
				p.get_parent().remove_child(p)
			p.queue_free()
	active = bool(d.get("active", false))
	night_day = int(d.get("night_day", 0))
	budget = float(d.get("budget", 0.0))
	roster.clear()
	for k in d.get("roster", []):
		if Balance.PHANTOMS.has(String(k)):
			roster.append(String(k))
	spawn_timer = float(d.get("spawn_timer", 0.0))
	spawned_total = int(d.get("spawned_total", 0))
	_relay_seen = bool(d.get("relay_seen", false))
	_pack_seq = int(d.get("pack_seq", 0))
	if d.has("rng_state"):
		_rng.state = int(d["rng_state"])
	_lights_size = -1
	Game.phantoms_alive = 0
