extends Node
## Директор угрозы (ADR-001 § 4.5, ADR-005 § 6.1–6.2). Заменяет main.gd::_update_waves.
##
## Ночь (и удержание сигнала релея) получает бюджет очков угрозы от готовности базы:
##   T   = min(смена, 3) + 0.5·горящих горелок + 1.0·маяков под лучом
##         + 0.25·накопителей + 4·релей
##   B   = 1 + 2·T                      — очков на ночь
##   cap = min(1 + T, 10), при релее RELAY_HOLD_CAP — единиц одновременно
## Ночи 1–2 (QUIET_NIGHTS) тихие: бюджет не больше 2, живых не больше 1, только эхо.
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
## Чёрный ящик, подобранный игроком, вскрывается здесь же: 2 кристалла и обрывок
## журнала (Tech.add_fragment, #28).
##
## Сеть (ADR-002 § 4.7, D9; MP-F, #92) — только на хосте, N — герои на связи:
##   B_N = B · (1 + MP_BUDGET_PER_PLAYER·(N − 1))       — N на начало ночи
##   cap_N = min(cap(T) + MP_CAP_PER_PLAYER·(N − 1), MAX_PHANTOMS)   — N текущее
##   интервал_N = clamp((7 − 0.5·T) / (1 + MP_INTERVAL_PER_PLAYER·(N − 1)), MP_SPAWN_INTERVAL_MIN, 7)
## Спавн — у героя с наименьшим числом преследователей (ничья — дальний от базы).
## Чёрные ящики вскрываются из инвентаря любого героя. При N = 1 всё как в ADR-001.

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
	night_players = 1


func _process(delta: float) -> void:
	_bind_inventory()
	if in_scenario() or Game.state != Game.State.PLAYING:
		return
	tick(delta)


## Идёт ли сценарий. Флаг ставит main.gd на весь прогон --scenario;
## Game.reset_run() его больше не сбрасывает (#32), обход через флаг сцены не нужен.
func in_scenario() -> bool:
	return Game.scenario_mode


## Глава кампании ведёт волны сама (Mission.director = false): бюджета и состава
## ночи нет, телеграфы и спавн — штатные (telegraph, _tick_pending).
func scripted() -> bool:
	return Game.in_mission() and not bool(Game.mission.director)


# ------------------------------------------------------------------ ФОРМУЛЫ

## Уровень угрозы T (ADR-005 § 6.2). Смена не выше THREAT_DAY_CAP.
func threat_level() -> float:
	return minf(float(Game.day_number), float(Balance.THREAT_DAY_CAP)) \
			+ Balance.THREAT_PER_BURNER * float(burners_lit()) \
			+ Balance.THREAT_PER_PHAROS * float(pharos_lit()) \
			+ Balance.THREAT_PER_ACCUM * float(accumulators()) \
			+ (Balance.THREAT_RELAY if Game.relay_active else 0.0)


## Тихая ночь: первые QUIET_NIGHTS, пока не держим сигнал.
static func quiet_night(night: int, relay: bool) -> bool:
	return night <= Balance.QUIET_NIGHTS and not relay


## Очков на ночь. Ночи 1–2 — не больше QUIET_BUDGET_CAP.
static func night_budget(t: float, night: int = 0, relay: bool = false) -> float:
	var b: float = Balance.NIGHT_BUDGET_BASE + Balance.NIGHT_BUDGET_PER_T * t
	if quiet_night(night, relay):
		return minf(b, Balance.QUIET_BUDGET_CAP)
	return b


## Сколько единиц угрозы держим одновременно. T — уровень угрозы этой ночи.
## Ночи 1–2 — не больше QUIET_ALIVE_CAP. При релее — RELAY_HOLD_CAP.
static func cap_for(day: int, relay: bool, t: float = -1.0) -> int:
	if relay:
		return Balance.RELAY_HOLD_CAP
	if quiet_night(day, false):
		return Balance.QUIET_ALIVE_CAP
	var level: float = t if t >= 0.0 else float(mini(day, Balance.THREAT_DAY_CAP))
	var cap: int = Balance.CAP_BASE + int(floor(level))
	return mini(cap, Balance.CAP_MAX)


## Пауза между появлениями.
static func interval_for(t: float) -> float:
	return clampf(Balance.SPAWN_INTERVAL_MAX - Balance.SPAWN_INTERVAL_PER_T * t,
			Balance.SPAWN_INTERVAL_MIN, Balance.SPAWN_INTERVAL_MAX)


## Открыт ли тип к этой ночи (ADR-005 § 6.1). Эхо — всегда. Рой — если горят
## две и больше горелки. Тень — если есть накопитель или сундук с топливом
## (горелка с запасом тоже считается). Копатель — со смены 4 и если в мире есть
## стальная стена. Двойник — в свободной игре со смены 6, в миссии никогда;
## на удержании сигнала — как раньше, сразу.
static func kind_open(kind: String, night: int, relay: bool) -> bool:
	if kind == "echo":
		return true
	if quiet_night(night, relay):
		return false
	if relay and kind == "doppel":
		return true
	if Game.in_mission() and kind == "doppel":
		return false
	match kind:
		"swarm":
			return _count_burners() >= 2
		"shade":
			return _count_accumulators() > 0 or _fuel_stored()
		"burrower":
			return night >= int(Balance.PHANTOMS["burrower"]["from_night"]) and _steel_wall()
		"doppel":
			return night >= int(Balance.PHANTOMS["doppel"]["from_night"])
	return false


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


## Горящие горелки (для T). Маяка (#167) ещё нет — pharos_lit() смотрит kind
## «Pharos» и метод lit(); пока блока нет, вклад 0.
func burners_lit() -> int:
	return _count_burners()


func pharos_lit() -> int:
	return _count_pharos()


func accumulators() -> int:
	return _count_accumulators()


static func _count_burners() -> int:
	var n: int = 0
	for m in World.machines.values():
		if is_instance_valid(m) and String(m.get("kind")) == "Burner" \
				and m.has_method("burning") and bool(m.call("burning")):
			n += 1
	return n


static func _count_pharos() -> int:
	var n: int = 0
	for m in World.machines.values():
		if is_instance_valid(m) and String(m.get("kind")) == "Pharos" and _pharos_under_beam(m):
			n += 1
	return n


static func _count_accumulators() -> int:
	var n: int = 0
	for m in World.machines.values():
		if is_instance_valid(m) and String(m.get("kind")) == "Accumulator":
			n += 1
	return n


## Маяк «под лучом»: метод lit() есть — он решает; иначе не горит (крючок #167).
static func _pharos_under_beam(m: Object) -> bool:
	if m.has_method("lit"):
		return bool(m.call("lit"))
	return false


## Есть ли у базы топливо, которое тень может съесть: сундук с топливом или
## горелка с запасом в топке (горящая единица не считается запасом). Тайники
## руин далеко от ядра не в счёт — иначе тень открыта с первой секунды мира.
const FUEL_BASE_RADIUS: int = 24

static func _fuel_stored() -> bool:
	var origin: Vector2i = World.beacon_cell
	for m in World.machines.values():
		if not is_instance_valid(m):
			continue
		var cell: Vector2i = m.cell
		if absi(cell.x - origin.x) > FUEL_BASE_RADIUS or absi(cell.y - origin.y) > FUEL_BASE_RADIUS:
			continue
		var k: String = String(m.get("kind"))
		if k == "Chest" and _chest_has_fuel(m):
			return true
		if k == "Burner" and m.has_method("fuel_units") and int(m.call("fuel_units")) > 0:
			return true
	return false


static func _chest_has_fuel(m: Object) -> bool:
	for s in m.slots:
		if not s.is_empty() and Balance.FUEL.has(int(s.id)):
			return true
	return false


## В мире есть стальная стена — копателю есть что рыть. По строкам: один
## find() по всему миру — это кадр, а открытие вида спрашивают на состав ночи.
static func _steel_wall() -> bool:
	var row: int = World.W
	var id: int = IDs.T.STEEL_WALL
	for y in World.H:
		var slice: PackedByteArray = World.tiles.slice(y * row, y * row + row)
		if slice.find(id) >= 0:
			return true
	return false


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
	Game.phantoms_alive = get_tree().get_nodes_in_group("phantom").size()
	_tick_pending(delta)
	if scripted():   # КАМПАНИЯ: волны ведёт глава (Mission.wave), телеграфы — здесь
		_update_dusk_hum()
		return
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
		var extra: float = Balance.NIGHT_BUDGET_PER_T * Balance.THREAT_RELAY * budget_mul(night_players)
		budget += extra
		roster.append_array(plan_roster(extra, night_day, true, _doppels_alive()))
		_hurry_doppel(0)
	spawn_timer -= delta
	if spawn_timer > 0.0 or roster.is_empty():
		return
	if units_alive() + pending.size() >= cap_for_n(night_day, Game.relay_active, players_online(), threat_level()):
		return
	spawn_timer = interval_for_n(threat_level(), players_online())
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
	night_players = players_online()
	budget = night_budget_n(threat_level(), night_players, night_day, Game.relay_active)
	roster = plan_roster(budget, night_day, Game.relay_active, _doppels_alive())
	# Эхо — первым (разведка), остальное вперемешку. Рой, если открыт, — сразу
	# за разведчиком: иначе эхо занимает cap, и стая не выходит за ночь
	# (ночь 3, две горелки, сид 4242).
	var head: Array[String] = []
	if not roster.is_empty() and roster[0] == "echo":
		head.append(roster.pop_front())
	var swarm_at: int = roster.find("swarm")
	if swarm_at >= 0:
		head.append(roster[swarm_at])
		roster.remove_at(swarm_at)
	_shuffle(roster)
	head.append_array(roster)
	roster = head
	if Game.relay_active:
		_hurry_doppel(1)
	spawn_timer = minf(interval_for_n(threat_level(), night_players), 3.0)


func _end_night() -> void:
	active = false
	roster.clear()
	_relay_seen = false


## Удержание сигнала (§ 4.7, #32): двойник обязателен и не ждёт конца
## перемешанного состава — ставим его на место at (после разведчика-эха).
func _hurry_doppel(at: int) -> void:
	var i: int = roster.find("doppel")
	if i < 0 or i <= at:
		return
	roster.remove_at(i)
	roster.insert(mini(at, roster.size()), "doppel")


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
	var ppos: Vector2 = spawn_anchor()
	var vent: Vector2i = pick_vent(ppos)
	if vent.x >= 0:
		telegraph(vent, kind)
		return true
	var cell: Vector2i = find_cave_cell(ppos)
	if cell.x < 0:
		return false
	_spawn_now(kind, World.cell_to_world(cell))
	return true


## Телеграф из заданной вентиляции: гул и пар, через VENT_TELEGRAPH с — фантом.
## Зовёт и директор (request_spawn), и глава кампании (Mission.wave).
func telegraph(vent: Vector2i, kind: String) -> void:
	var pos: Vector2 = World.cell_to_world(vent)
	var hum: int = Sfx.loop_start("vent_hum", pos, TELEGRAPH_HUM_DB)
	pending.append({"cell": vent, "kind": kind, "t": Balance.VENT_TELEGRAPH, "hum": hum})
	vent_warning.emit(vent)


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
		if World.is_vent_sealed(v):   # решётка (#31): World.vents_sealed
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
	if Game.players.size() > 1:   # СЕТЬ (ADR-002 § 4.2.5): инвентари товарищей
		_net_bind_inventories()
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


## Вскрыть чёрный ящик (#169): 2 кристалла в инвентарь (не влезло — на пол) и обрывок.
func open_black_box() -> void:
	var hero = Game.player
	var n: int = Balance.BLACK_BOX_CRYSTALS
	var left: int = n
	if hero != null and is_instance_valid(hero):
		left = hero.inv.add(IDs.I.CRYSTAL, n)
		if left > 0:
			hero.spawn_item(IDs.I.CRYSTAL, left, hero.global_position)
	var text: String = Lore.fragment(_rng)
	Tech.add_fragment(text)
	var where: String = "на пол" if left == n else ("в инвентарь" if left == 0 else "часть на пол")
	Game.notify("Чёрный ящик: +%d кристалла (%s). «%s»" % [n, where, text], Color(0.95, 0.6, 0.35))
	if Net.is_host():   # СЕТЬ (ADR-002 § 4.2.5): обрывок — команде, уведомление всем
		Net.send(NetCodec.Msg.EVENT, NetCodec.encode_notify(Vector2.ZERO,
				"Чёрный ящик: +%d кристалла. «%s»" % [n, text], Color(0.95, 0.6, 0.35)))


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
		if is_instance_valid(p) and not bool(p.get("net_puppet")):   # СЕТЬ: марионетки ведёт NetPhantoms
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
	Game.phantoms_alive = 0


# ------------------------------------------------------------------ СЕТЬ (ADR-002 § 4.7, MP-F #92)
## Формулы угрозы на N игроков (D9). При n ≤ 1 — ровно формулы ADR-001.

## Героев на связи на начало этой ночи (бюджет и интервал считаются по нему).
var night_players: int = 1
## Инвентари товарищей, к которым подключены: instance_id инвентаря → герой.
var _net_inv: Dictionary = {}


## Игроки на связи (герои Game.players с net_linked). Без сети — 1.
func players_online() -> int:
	var n: int = 0
	for h in Game.players:
		if is_instance_valid(h) and bool(h.get("net_linked")):
			n += 1
	return maxi(1, n)


## Множитель бюджета ночи: 1 + MP_BUDGET_PER_PLAYER·(N − 1).
static func budget_mul(n: int) -> float:
	if n <= 1:
		return 1.0
	return 1.0 + Balance.MP_BUDGET_PER_PLAYER * float(n - 1)


static func night_budget_n(t: float, n: int, night: int = 0, relay: bool = false) -> float:
	if n <= 1:
		return night_budget(t, night, relay)
	return night_budget(t, night, relay) * budget_mul(n)


## cap + MP_CAP_PER_PLAYER·(N − 1), не выше MAX_PHANTOMS (предел freeze_probe, #27).
static func cap_for_n(day: int, relay: bool, n: int, t: float = -1.0) -> int:
	if n <= 1:
		return cap_for(day, relay, t)
	return mini(cap_for(day, relay, t) + Balance.MP_CAP_PER_PLAYER * (n - 1), Balance.MAX_PHANTOMS)


## (7 − 0.5·T) / (1 + MP_INTERVAL_PER_PLAYER·(N − 1)), в пределах MP_SPAWN_INTERVAL_MIN…7 с.
static func interval_for_n(t: float, n: int) -> float:
	if n <= 1:
		return interval_for(t)
	var raw: float = Balance.SPAWN_INTERVAL_MAX - Balance.SPAWN_INTERVAL_PER_T * t
	return clampf(raw / (1.0 + Balance.MP_INTERVAL_PER_PLAYER * float(n - 1)),
			Balance.MP_SPAWN_INTERVAL_MIN, Balance.SPAWN_INTERVAL_MAX)


## Сколько живых фантомов охотится на героя (Phantom.player).
func pursuers_of(hero: Node) -> int:
	var n: int = 0
	for p in get_tree().get_nodes_in_group("phantom"):
		if is_instance_valid(p) and bool(p.get("alive")) and p.get("player") == hero:
			n += 1
	return n


## Герой, у которого появится следующий фантом: доступный (живой, не спрятался, на
## связи) с наименьшим числом преследователей; ничья — дальний от базы. Один герой —
## он сам (как ADR-001).
func spawn_hero() -> Node2D:
	if Game.players.size() <= 1:
		return _player()
	var best: Node2D = null
	var best_n: int = 1 << 30
	var best_d: float = -1.0
	for h in Game.players:
		if not is_instance_valid(h) or not h.has_method("net_targetable") or not bool(h.call("net_targetable")):
			continue
		var n: int = pursuers_of(h)
		var d: float = (h as Node2D).global_position.distance_to(World.spawn_point)
		if n < best_n or (n == best_n and d > best_d):
			best = h
			best_n = n
			best_d = d
	return best if best != null else _player()


## Точка, у которой ищем вентиляцию для спавна.
func spawn_anchor() -> Vector2:
	if Game.players.size() <= 1:
		return _player_pos()
	var h: Node2D = spawn_hero()
	return h.global_position if h != null else World.spawn_point


## Подключиться к инвентарям всех героев, кроме своего (его ведёт _bind_inventory):
## у хоста инвентари прокси авторитетны, подобранный товарищем ящик вскрывается здесь.
func _net_bind_inventories() -> void:
	for h in Game.players:
		if not is_instance_valid(h) or h == Game.player:
			continue
		var inv = h.get("inv")
		if inv == null or _net_inv.has(inv.get_instance_id()):
			continue
		_net_inv[inv.get_instance_id()] = h
		inv.connect("changed", _net_on_inventory_changed.bind(h))


func _net_on_inventory_changed(hero: Node) -> void:
	if not is_instance_valid(hero) or not Net.is_authority():
		return
	var n: int = int(hero.inv.count_of(IDs.I.BLACK_BOX))
	if n <= 0:
		return
	hero.inv.remove_id(IDs.I.BLACK_BOX, n)
	for i in n:
		open_black_box()
