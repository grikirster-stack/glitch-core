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
## Глава выпустила безвредное эхо. Сценарий читает: ночью эхо уходит за секунды.
var chapter_echo: bool = false
var pending: Array = []             ## телеграфы: {cell, kind, t, hum}
## Налёт (#316). Фаза и таймер живут в Game — их пишет сейв и GLOBAL.
## Здесь только поиск входа, чтобы кадр не искал весь мир.
var raid_entrance: Vector2i = Vector2i(-1, -1)
var last_raid_day: int = 0
var raid_side: String = ""
## Участок, который налёт повредил. Пусто — участка нет.
var raid_section: Vector2i = Vector2i(-1, -1)
var raid_section_t: float = 0.0

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
	chapter_echo = false
	raid_entrance = Vector2i(-1, -1)
	last_raid_day = 0
	raid_side = ""
	raid_section = Vector2i(-1, -1)
	raid_section_t = 0.0
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

## Уровень угрозы T (ADR-005 § 6.2). Смена не выше потолка: 3 до сигнала,
## 6 после (#261). Кампания и ночи 1–2 потолок не поднимают.
func threat_level() -> float:
	return minf(float(Game.day_number), float(day_cap())) \
			+ Balance.THREAT_PER_BURNER * float(burners_lit()) \
			+ Balance.THREAT_PER_PHAROS * float(pharos_lit()) \
			+ Balance.THREAT_PER_ACCUM * float(accumulators()) \
			+ (Balance.THREAT_RELAY if Game.relay_active else 0.0)



## Потолок смены в формуле T. После сигнала — 6, иначе 3.
## Кампания свой потолок не поднимает: у главы своя ночь.
static func day_cap() -> int:
	if Game.signal_sent and not Game.in_mission():
		return Balance.THREAT_DAY_CAP_POST_RELAY
	return Balance.THREAT_DAY_CAP


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
	var level: float = t if t >= 0.0 else float(mini(day, day_cap()))
	var cap: int = Balance.CAP_BASE + int(floor(level))
	return mini(cap, Balance.CAP_MAX)


## Пауза между появлениями.
static func interval_for(t: float) -> float:
	return clampf(Balance.SPAWN_INTERVAL_MAX - Balance.SPAWN_INTERVAL_PER_T * t,
			Balance.SPAWN_INTERVAL_MIN, Balance.SPAWN_INTERVAL_MAX)


## Открыт ли тип к этой ночи (ADR-005 § 6.1). Эхо — всегда. Рой — если горят
## SWARM_BURNERS горелок (три: две — это R+G для жёлтого, и стая приходила
## раньше ответа). Тень — если есть накопитель или топливо, которое игрок
## положил сам: сундук лагеря (permanent) не считается, иначе тень открыта
## с ночи 3 всегда. Копатель — со смены 4, стена ему не ключ (иначе «не строй
## стену» закрывает его навсегда). Двойник — в свободной игре со смены 6,
## в миссии никогда; на удержании сигнала — как раньше, сразу.
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
			return _count_burners() >= Balance.SWARM_BURNERS
		"shade":
			return _count_accumulators() > 0 or _fuel_stored()
		"burrower":
			return night >= int(Balance.PHANTOMS["burrower"]["from_night"])
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


## Горящие горелки (для T). Бывшие генераторы (#170) сюда не входят.
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
## горелка с запасом в топке (горящая единица не считается запасом). Сундук
## лагеря (permanent) не в счёт: 8 угля там лежат с генерации, и тень была бы
## открыта с ночи 3 без единой постройки игрока. Тайники руин далеко от ядра
## не в счёт по той же причине.
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
		if k == "Chest" and not bool(m.get("permanent")) and _chest_has_fuel(m):
			return true
		if k == "Burner" and m.has_method("fuel_units") and int(m.call("fuel_units")) > 0:
			return true
	return false


static func _chest_has_fuel(m: Object) -> bool:
	for s in m.slots:
		if not s.is_empty() and Balance.FUEL.has(int(s.id)):
			return true
	return false


## В мире есть стальная стена. Открытие копателя её больше не спрашивает
## (ночь ≥ 4 сама по себе): стена — ответ, не ключ. Функция осталась для замера.
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
	_tick_raid(delta)
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
		# (ночь 3, три горелки, сид 4242).
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
## opts.harmless — эхо не бьёт (главы 1–3); директор его не передаёт.
## Директорское эхо идёт к герою сквозь свет, пока его не видно (#268).
## Глава зовёт spawn_phantom сама и этот флаг не получает.
func _seek_opts(kind: String, opts: Dictionary) -> Dictionary:
	if kind != "echo" or bool(opts.get("harmless", false)):
		return opts
	var o: Dictionary = opts.duplicate()
	o["seek"] = true
	return o


func request_spawn(kind: String, opts: Dictionary = {}) -> bool:
	var ppos: Vector2 = spawn_anchor()
	var vent: Vector2i = pick_vent(ppos, kind)
	if vent.x >= 0:
		opts = _seek_opts(kind, opts)
		telegraph(vent, kind, opts)
		return true
	# Эхо: тёмной вентиляции нет, но устье лагеря залито. Выпуск в пещере
	# (#268, замер) не связан с героем — путь 0, эхо кружит и не доходит.
	# Тёмная клетка у этой вентиляции с путём к герою: эхо идёт сквозь свет
	# до LOS, а спавнится уже в темноте. Гул сумерек вентиляцию не трогает.
	if kind == "echo":
		var mouth: Vector2i = _echo_mouth(ppos)
		if mouth.x >= 0:
			opts = _seek_opts(kind, opts)
			telegraph(mouth, kind, opts)
			return true
	var cell: Vector2i = find_cave_cell(ppos)
	if cell.x < 0:
		return false
	_spawn_now(kind, World.cell_to_world(cell), _seek_opts(kind, opts))
	return true


## Тёмная клетка у ближайшей вентиляции, откуда до героя есть путь.
## Сама вентиляция может быть ярче порога — эхо выходит рядом, не из света.
func _echo_mouth(ppos: Vector2) -> Vector2i:
	var vents: Array[Vector2i] = nearest_vents(ppos)
	if vents.is_empty():
		return Vector2i(-1, -1)
	var hero: Vector2i = World.world_to_cell(ppos)
	var flee: float = float(Balance.PHANTOMS["echo"]["light_flee"])
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: int = 999
	for v in vents:
		var cell: Vector2i = _dark_step(v, hero, flee)
		if cell.x < 0:
			continue
		var d: int = absi(cell.x - v.x) + absi(cell.y - v.y)
		if d < best_d:
			best_d = d
			best = cell
	return best


## Ближайшая к устью тёмная проходимая клетка, из которой A* доходит до героя.
func _dark_step(vent: Vector2i, hero: Vector2i, flee: float) -> Vector2i:
	var seen: Dictionary = {}
	var q: Array[Vector2i] = [vent]
	seen[vent] = true
	var steps: int = 0
	while not q.is_empty() and steps < 160:
		var c: Vector2i = q.pop_front()
		steps += 1
		if c != vent and World.light_at(c) <= flee and not World.astar.is_point_solid(c):
			if World.astar.get_id_path(c, hero).size() > 1:
				return c
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if seen.has(n) or not World.in_bounds(n.x, n.y):
				continue
			if absi(n.x - vent.x) + absi(n.y - vent.y) > 24:
				continue
			seen[n] = true
			if World.astar.is_point_solid(n):
				continue
			q.append(n)
	return Vector2i(-1, -1)


## Телеграф из заданной вентиляции: гул и пар, через VENT_TELEGRAPH с — фантом.
## Зовёт и директор (request_spawn), и глава кампании (Mission.wave).
## opts доезжает до spawn_phantom (harmless глав 1–3).
func telegraph(vent: Vector2i, kind: String, opts: Dictionary = {}) -> void:
	var pos: Vector2 = World.cell_to_world(vent)
	var hum: int = Sfx.loop_start("vent_hum", pos, TELEGRAPH_HUM_DB)
	pending.append({"cell": vent, "kind": kind, "t": Balance.VENT_TELEGRAPH, "hum": hum,
			"opts": opts})
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
		_spawn_now(String(p["kind"]), World.cell_to_world(p["cell"]), p.get("opts", {}))
	pending = keep


## Создать фантома (стаю — для роя) в точке. opts: harmless — не бьёт (главы 1–3).
## Возвращает созданных.
func spawn_phantom(kind: String, pos: Vector2, opts: Dictionary = {}) -> Array:
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
		p.harmless = bool(opts.get("harmless", false))
		p.raid = bool(opts.get("raid", false))
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
		if bool(opts.get("raid", false)) and p.has_method("approach"):
			var at: Vector2 = opts.get("at", p.global_position)
			p.approach(Balance.RAID_CONTACT_MAX, at)
		elif bool(opts.get("seek", false)) and p.has_method("seek_until_seen"):
			var hero := _player()
			if hero != null:
				p.seek_until_seen(90.0, hero.global_position)
	return out


func _spawn_now(kind: String, pos: Vector2, opts: Dictionary = {}) -> void:
	var made: Array = spawn_phantom(kind, pos, opts)
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
func pick_vent(ppos: Vector2, kind: String = "") -> Vector2i:
	var vents: Array[Vector2i] = nearest_vents(ppos)
	# Эхо не выходит из вентиляции ярче порога бегства (#268): устье лагеря
	# залито кристаллами, и эхо сразу стоит. Гул сумерек эту вентиляцию
	# по-прежнему берёт — фильтр только у спавна. Нет тёмной — пещера.
	if kind == "echo":
		var flee: float = float(Balance.PHANTOMS["echo"]["light_flee"])
		var dark: Array[Vector2i] = []
		for v in vents:
			if World.light_at(v) <= flee:
				dark.append(v)
		vents = dark
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
	var raid_unit: Dictionary = {}
	var packs: Dictionary = {}
	var alive: int = 0
	for p in get_tree().get_nodes_in_group("phantom"):
		if not is_instance_valid(p) or not bool(p.get("alive")):
			continue
		alive += 1
		if p.raid and Game.raid_phase == RAID_ON:
			raid_unit = {"pos": p.global_position, "hp": p.hp}
			continue
		var pid: int = int(p.get("pack_id"))
		if pid > 0:
			if packs.has(pid):
				continue
			packs[pid] = true
		back.append(String(p.get("kind")))
	for p in pending:
		if p.get("opts", {}).get("raid", false) and Game.raid_phase == RAID_ON:
			raid_unit = {"delay": p["t"]}
			continue
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
		"raid_entrance": raid_entrance,
		"raid_unit": raid_unit,
		"last_raid_day": last_raid_day,
		"raid_side": raid_side,
		"raid_section": raid_section,
		"raid_section_t": raid_section_t,
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
	raid_entrance = d.get("raid_entrance", Vector2i(-1, -1))
	last_raid_day = int(d.get("last_raid_day", night_day if Game.raid_phase != 0 else 0))
	raid_side = String(d.get("raid_side", ""))
	raid_section = d.get("raid_section", Vector2i(-1, -1))
	raid_section_t = float(d.get("raid_section_t", 0.0))
	Game.phantoms_alive = 0
	if Net.is_authority() and Game.raid_phase == RAID_ON and raid_entrance.x >= 0:
		var unit: Dictionary = d.get("raid_unit", {})
		# В старом файле эхо налёта было записано в общей очереди ночи.
		if not d.has("raid_unit") and roster.has("echo"):
			roster.erase("echo")
			unit = {"delay": Balance.VENT_TELEGRAPH}
		var opts := {"raid": true, "at": World.cell_to_world(Game.raid_target)}
		if unit.has("delay"):
			telegraph(raid_entrance, "echo", opts)
			pending.back()["t"] = float(unit["delay"])
		elif unit.has("pos"):
			for ph in spawn_phantom("echo", unit["pos"], opts):
				ph.hp = float(unit["hp"])


# ------------------------------------------------------------------ НАЛЁТ (ADR-006 § 4, #316)

const RAID_NONE: int = 0
const RAID_WARN: int = 1
const RAID_ON: int = 2
const RAID_DONE: int = 3
const RAID_NEIGHBOR: int = 18
const RAID_DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


## Часы налёта. Хост и одиночная считают; клиент только показывает пакет.
## Кампания (scripted) налёт не ведёт. Сценарий зовёт tick сам.
func _tick_raid(delta: float) -> void:
	if scripted():
		return
	if Net.is_client():
		return
	_restore_section(delta)
	if Game.raid_phase == RAID_WARN:
		Game.raid_remain = maxf(0.0, Game.raid_remain - delta)
		if Game.raid_remain <= 0.0:
			_raid_contact()
		return
	if Game.raid_phase == RAID_ON:
		Game.raid_remain = maxf(0.0, Game.raid_remain - delta)
		_raid_hold_course()
		# Сценарий глушит _process директора, но физику фантома дерево крутит
		# само. Здесь только курс: удар и шаг — в phantom._physics_process.
		if raid_entrance.x >= 0 and not _raid_phantom_alive():
			_raid_finish(Game.raid_damage != "")
		elif Game.raid_remain <= 0.0 and Game.raid_damage == "":
			_raid_finish(false)
		return
	if Game.raid_phase == RAID_DONE:
		Game.raid_remain = maxf(0.0, Game.raid_remain - delta)
		if Game.raid_remain <= 0.0:
			_raid_clear()
		return
	if not Game.is_night() or Game.day_number < 1:
		return
	# Ночь началась, налёта ещё нет — предупреждение до контакта.
	# Ночи 1–2 — эхо и прежний потолок. Лишний фантом налёта ломает бюджет.
	if not active:
		return
	if quiet_night(Game.day_number, Game.relay_active):
		return
	if Game.day_number == last_raid_day:
		return
	_raid_begin_warn()


func _raid_begin_warn() -> void:
	var pick: Dictionary = _raid_pick()
	# Без устройства у метки налёт не начинается: иначе эхо выходит на саму метку
	# и ломает потолок ночи, где базы ещё нет.
	if String(pick.get("kind", "")) == "mark":
		return
	Game.raid_phase = RAID_WARN
	last_raid_day = Game.day_number
	Game.raid_number += 1
	Game.raid_target = pick["target"]
	Game.raid_remain = Balance.RAID_WARN_LEAD
	Game.raid_damage = ""
	Game.raid_active = false
	raid_entrance = pick["entrance"]
	raid_side = String(pick["side"])
	_raid_was_sync()
	var line: String = _raid_line(pick)
	if UI.hud != null:
		UI.hud.raid_line = line
		UI.hud.raid_cell = Game.raid_target if Game.raid_target.x >= 0 else raid_entrance
	Game.notify(line, Color(1.0, 0.55, 0.35))


func _raid_contact() -> void:
	var cell: Vector2i = raid_entrance
	if cell.x < 0 or not _raid_outside(cell):
		var again: Dictionary = _raid_pick()
		cell = again["entrance"]
		raid_entrance = cell
		raid_side = String(again["side"])
		if Game.raid_target.x < 0:
			Game.raid_target = again["target"]
	if cell.x < 0:
		Game.raid_phase = RAID_ON
		Game.raid_active = true
		Game.raid_remain = Balance.RAID_GIVE_UP
		_raid_was_sync()
		return
	Game.raid_checked = cell
	Game.raid_phase = RAID_ON
	Game.raid_active = true
	Game.raid_remain = Balance.RAID_CONTACT_MAX
	_raid_was_sync()
	var opts: Dictionary = {"raid": true, "at": World.cell_to_world(Game.raid_target if Game.raid_target.x >= 0 else cell)}
	telegraph(cell, "echo", opts)


func _raid_hold_course() -> void:
	var at: Vector2 = World.cell_to_world(Game.raid_target if Game.raid_target.x >= 0 else raid_entrance)
	for p in get_tree().get_nodes_in_group("phantom"):
		if not is_instance_valid(p) or not bool(p.get("raid")):
			continue
		if not p.has_method("approach"):
			continue
		# Повторный approach обнуляет путь каждый кадр — эхо стоит у входа.
		if float(p.get("approach_t")) > 1.0:
			continue
		p.approach(8.0, at)


func _raid_phantom_alive() -> bool:
	for p in get_tree().get_nodes_in_group("phantom"):
		if is_instance_valid(p) and bool(p.get("raid")) and bool(p.get("alive")):
			return true
	for p in pending:
		if bool(p.get("opts", {}).get("raid", false)):
			return true
	return false


func raid_repelled() -> void:
	if Game.raid_phase == RAID_ON:
		_raid_finish(true)


func _raid_finish(resolved: bool) -> void:
	if not resolved:
		for ph in get_tree().get_nodes_in_group("phantom"):
			if ph.raid and ph.alive:
				ph.alive = false
				ph.queue_free()
	Game.raid_phase = RAID_DONE
	Game.raid_active = false
	Game.raid_remain = 8.0
	_raid_was_sync()
	if resolved and Game.raid_reward_id != Game.raid_number:
		Game.raid_reward_id = Game.raid_number
		var hero = _player()
		if hero != null and hero.get("inv") != null:
			hero.inv.add(IDs.I.SCRAP, 2)
	var line: String = _raid_result_line(resolved)
	if UI.hud != null:
		UI.hud.raid_line = line
	Game.notify(line, Color(0.85, 0.9, 1.0))


func _raid_clear() -> void:
	Game.raid_phase = RAID_NONE
	Game.raid_active = false
	Game.raid_remain = 0.0
	Game.raid_target = Vector2i(-1, -1)
	Game.raid_damage = ""
	raid_entrance = Vector2i(-1, -1)
	raid_side = ""
	_raid_was_sync()
	if UI.hud != null:
		UI.hud.raid_line = ""
		UI.hud.raid_cell = Vector2i(-1, -1)


func _raid_was_sync() -> void:
	Game._poll_raid()


func _raid_line(pick: Dictionary) -> String:
	var side: String = String(pick["side"])
	var what: String = "грядка" if String(pick["kind"]) == "bed" else "база"
	if side == "":
		side = "сторона не ясна"
	return "Налёт с %s, цель — %s" % [side, what]


func _raid_result_line(resolved: bool) -> String:
	var side: String = raid_side if raid_side != "" else "неясной стороны"
	if not resolved:
		return "Налёт с %s не дошёл" % side
	if Game.raid_damage == "section":
		return "Налёт с %s: участок встанет за сутки" % side
	if Game.raid_damage == "device":
		return "Налёт с %s: чини камнем или хламом" % side
	return "Налёт с %s отбит" % side


## Цель: исправная тёмная грядка у метки, иначе ближайшее устройство.
## Вход — снаружи, с путём. Второй налёт не повторяет проверенный вход.
func _raid_pick() -> Dictionary:
	var anchor: Vector2i = Game.base_mark_anchor()
	var target: Vector2i = Vector2i(-1, -1)
	var kind: String = ""
	var best: int = 9999
	var bed_best: int = 9999
	for m in World.machines.values():
		if not is_instance_valid(m) or not (m is MachineBase):
			continue
		var c: Vector2i = m.cell
		var d: int = absi(c.x - anchor.x) + absi(c.y - anchor.y)
		if d > RAID_NEIGHBOR:
			continue
		# Зажжённая грядка целью не становится: луч ночью её уже сторожит.
		if m.kind == "SporeBed" and bool(m.get("lit")):
			continue
		# Тёмная живая грядка важнее ближней горелки: луч ночью выключен.
		if m.kind == "SporeBed" and float(m.hp) > 0.0 and not bool(m.get("lit")):
			if d < bed_best:
				target = c
				kind = "bed"
				bed_best = d
				best = d
			continue
		if kind == "bed" or d >= best:
			continue
		target = c
		kind = "device"
		best = d
	if target.x < 0:
		target = anchor
		kind = "mark"
	var door: bool = _raid_door_open(target)
	var entrance: Vector2i = _raid_entrance(target, door)
	# Сторона — от цели, не от метки базы: западный проём у восточной метки иначе «восток».
	var side_from: Vector2i = target if target.x >= 0 else anchor
	var side: String = _raid_side_name(entrance if entrance.x >= 0 else side_from, side_from)
	return {"target": target, "kind": kind, "entrance": entrance, "side": side, "open": door}


func _raid_door_open(target: Vector2i) -> bool:
	for d in RAID_DIRS:
		var n: Vector2i = target + d
		if World.in_bounds(n.x, n.y) and World.get_tile_v(n) == IDs.T.DOOR_OPEN:
			return true
	# Дверь комнаты может быть не в соседней клетке устройства.
	for y in range(maxi(0, target.y - 6), mini(World.H, target.y + 7)):
		for x in range(maxi(0, target.x - 8), mini(World.W, target.x + 9)):
			if World.get_tile_v(Vector2i(x, y)) == IDs.T.DOOR_OPEN:
				return true
	return false


func _raid_entrance(target: Vector2i, open_door: bool) -> Vector2i:
	var skip: Vector2i = Game.raid_checked if Game.raid_number >= 1 else Vector2i(-1, -1)
	# Второй налёт ищет другой подход, не соседнюю клетку уже проверенного входа.
	# Первый налёт skip пустой — этот проход его не касается.
	var alt: bool = skip.x >= 0 and _raid_has_other_approach(target, skip, open_door)
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: int = 9999
	var x0: int = maxi(1, target.x - RAID_NEIGHBOR)
	var x1: int = mini(World.W - 2, target.x + RAID_NEIGHBOR)
	var y0: int = maxi(1, target.y - 8)
	var y1: int = mini(World.H - 2, target.y + 8)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var c: Vector2i = Vector2i(x, y)
			if c == skip:
				continue
			if alt and _raid_same_approach(c, skip, target):
				continue
			if not _raid_outside(c):
				continue
			var here: int = World.get_tile_v(c)
			if here == IDs.T.DOOR or here == IDs.T.DOOR_OPEN or here == IDs.T.ROOM_PANEL:
				continue
			if World.astar != null and World.astar.is_point_solid(c):
				continue
			var d: int = absi(c.x - target.x) + absi(c.y - target.y)
			# Пеший шаг не поднимается на две клетки. Вход на другой высоте хуже.
			d += absi(c.y - target.y) * 8
			if d < 2:
				continue
			if not World.is_solid_cell(c + Vector2i.DOWN):
				d += RAID_NEIGHBOR
			# Со стороны двери, не через крышу: открытый проход ближе, чем обход.
			if open_door and not _raid_row_clear(c, target):
				d += 12
			if d >= best_d:
				continue
			if open_door:
				if not _raid_reaches(c, target):
					continue
			else:
				if not _raid_faces_shell(c):
					continue
			best = c
			best_d = d
	return best



## Тот же подход: соседняя клетка проверенного входа или та же сторона от цели.
func _raid_same_approach(c: Vector2i, checked: Vector2i, target: Vector2i) -> bool:
	if absi(c.x - checked.x) + absi(c.y - checked.y) <= 2:
		return true
	# Сторона считается от цели налёта. raid_target в момент выбора ещё пуст.
	var anchor: Vector2i = target if target.x >= 0 else checked
	return _raid_side_name(c, anchor) == _raid_side_name(checked, anchor)


## Есть ли снаружи вход не с того же подхода. Иначе второй налёт остаётся на старом.
func _raid_has_other_approach(target: Vector2i, checked: Vector2i, open_door: bool) -> bool:
	var x0: int = maxi(1, target.x - RAID_NEIGHBOR)
	var x1: int = mini(World.W - 2, target.x + RAID_NEIGHBOR)
	var y0: int = maxi(1, target.y - 8)
	var y1: int = mini(World.H - 2, target.y + 8)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var c: Vector2i = Vector2i(x, y)
			if _raid_same_approach(c, checked, target):
				continue
			if not _raid_entrance_ok(c, target, open_door):
				continue
			return true
	return false


func _raid_entrance_ok(c: Vector2i, target: Vector2i, open_door: bool) -> bool:
	if not _raid_outside(c):
		return false
	var here: int = World.get_tile_v(c)
	if here == IDs.T.DOOR or here == IDs.T.DOOR_OPEN or here == IDs.T.ROOM_PANEL:
		return false
	if World.astar != null and World.astar.is_point_solid(c):
		return false
	var d: int = absi(c.x - target.x) + absi(c.y - target.y)
	if d < 2:
		return false
	if open_door:
		return _raid_reaches(c, target)
	return _raid_faces_shell(c)



func _raid_row_clear(from: Vector2i, to: Vector2i) -> bool:
	if from.y != to.y:
		return false
	var x0: int = mini(from.x, to.x)
	var x1: int = maxi(from.x, to.x)
	for x in range(x0 + 1, x1):
		var id: int = World.get_tile_v(Vector2i(x, from.y))
		if id == IDs.T.ROOM_PANEL or id == IDs.T.DOOR:
			return false
	return true


func _raid_outside(c: Vector2i) -> bool:
	if not World.in_bounds(c.x, c.y):
		return false
	if World.get_tile_v(c) == IDs.T.ROOM_PANEL or World.get_tile_v(c) == IDs.T.DOOR:
		return false
	# Внутри комнаты — клетка, у которой все четыре стороны упираются в панели/двери
	# ближе, чем в воздух мира. Снаружи — есть путь к поверхности без панели.
	return not _raid_enclosed(c)


func _raid_enclosed(c: Vector2i) -> bool:
	# Замкнуто, если от клетки нельзя выйти на воздух без двери-стены,
	# и рядом есть панель. Открытая дверь комнатой не является.
	var seen: Dictionary = {}
	var q: Array[Vector2i] = [c]
	seen[c] = true
	var steps: int = 0
	var saw_panel: bool = false
	while not q.is_empty() and steps < 80:
		var cur: Vector2i = q.pop_front()
		steps += 1
		if cur != c and not _raid_near_shell(cur) and steps > 4:
			return false
		for d in RAID_DIRS:
			var n: Vector2i = cur + d
			if seen.has(n) or not World.in_bounds(n.x, n.y):
				continue
			var id: int = World.get_tile_v(n)
			if id == IDs.T.ROOM_PANEL or id == IDs.T.DOOR:
				saw_panel = true
				continue
			if World.astar != null and World.astar.is_point_solid(n):
				continue
			seen[n] = true
			q.append(n)
	return saw_panel


func _raid_near_shell(c: Vector2i) -> bool:
	for d in RAID_DIRS:
		var id: int = World.get_tile_v(c + d)
		if id == IDs.T.ROOM_PANEL or id == IDs.T.DOOR or id == IDs.T.DOOR_OPEN:
			return true
	return false


func _raid_faces_shell(c: Vector2i) -> bool:
	for d in RAID_DIRS:
		var n: Vector2i = c + d
		var id: int = World.get_tile_v(n)
		if id == IDs.T.ROOM_PANEL or id == IDs.T.DOOR:
			return true
		if World.machines.has(n):
			return true
	return false


func _raid_reaches(from: Vector2i, to: Vector2i) -> bool:
	if World.astar == null:
		return false
	var goal: Vector2i = to
	if World.astar.is_point_solid(goal):
		goal = _raid_free_near(to)
	if goal.x < 0:
		return false
	return World.astar.get_id_path(from, goal).size() > 1


func _raid_free_near(c: Vector2i) -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: int = 99
	for y in range(c.y - 3, c.y + 4):
		for x in range(c.x - 3, c.x + 4):
			var n: Vector2i = Vector2i(x, y)
			if not World.in_bounds(x, y) or World.astar.is_point_solid(n):
				continue
			var d: int = absi(x - c.x) + absi(y - c.y)
			if d < best_d:
				best_d = d
				best = n
	return best


func _raid_side_name(cell: Vector2i, anchor: Vector2i) -> String:
	var dx: int = cell.x - anchor.x
	var dy: int = cell.y - anchor.y
	if absi(dx) >= absi(dy):
		return "востока" if dx >= 0 else "запада"
	return "юга" if dy >= 0 else "севера"


## Рабочая оборона: есть панель у базы. Иначе встаёт одно устройство.
func raid_apply_hit(at: Vector2i) -> void:
	if Game.raid_phase != RAID_ON or Game.raid_damage != "":
		return
	if _raid_has_panels(at):
		var sec: Vector2i = _raid_section_cell(at)
		if sec.x >= 0:
			raid_section = sec
			raid_section_t = Balance.RAID_SECTION_RESTORE
			World.set_tile(sec.x, sec.y, IDs.T.AIR)
			Game.raid_damage = "section"
			_raid_finish(true)
			return
	var m = World.machines.get(at) if World.machines.has(at) else null
	if m == null:
		m = _raid_nearest_machine(at)
	if m != null and m.has_method("raid_stop"):
		m.raid_stop()
		Game.raid_damage = "device"
		_raid_finish(true)
	elif m != null:
		m.hp = minf(m.hp, 20.0)
		m.set("raid_stopped", true)
		Game.raid_damage = "device"
		_raid_finish(true)


func _raid_has_panels(at: Vector2i) -> bool:
	for y in range(at.y - 6, at.y + 7):
		for x in range(at.x - 8, at.x + 9):
			if World.in_bounds(x, y) and World.get_tile_v(Vector2i(x, y)) == IDs.T.ROOM_PANEL:
				return true
	return false


func _raid_section_cell(at: Vector2i) -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: int = 99
	for y in range(at.y - 6, at.y + 7):
		for x in range(at.x - 8, at.x + 9):
			var c: Vector2i = Vector2i(x, y)
			if not World.in_bounds(x, y) or World.get_tile_v(c) != IDs.T.ROOM_PANEL:
				continue
			var d: int = absi(x - at.x) + absi(y - at.y)
			if d < best_d:
				best_d = d
				best = c
	return best


func _raid_nearest_machine(at: Vector2i):
	var best = null
	var best_d: int = 99
	for m in World.machines.values():
		if not is_instance_valid(m) or not (m is MachineBase):
			continue
		var d: int = absi(m.cell.x - at.x) + absi(m.cell.y - at.y)
		if d < best_d:
			best_d = d
			best = m
	return best


func _restore_section(delta: float) -> void:
	if raid_section.x < 0 or raid_section_t <= 0.0:
		return
	raid_section_t -= delta
	if raid_section_t > 0.0:
		return
	if World.in_bounds(raid_section.x, raid_section.y) and World.get_tile_v(raid_section) == IDs.T.AIR:
		World.set_tile(raid_section.x, raid_section.y, IDs.T.ROOM_PANEL)
	raid_section = Vector2i(-1, -1)
	raid_section_t = 0.0


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
