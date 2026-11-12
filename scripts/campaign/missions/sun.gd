extends Mission
## Глава 5 «Солнце» (ADR-005 § 9, #179).
##
## Утро. Коллектор даёт белый луч, призма делит его, накопитель копит синий.
## Белый в маяке открывает кристаллы в стене ствола. Ночь 60 с: один копатель
## идёт к маяку. Синий мороз его тормозит — без синего он бьёт постройку,
## и глава проваливается. Победа — ни одна постройка не получила урон.


const CRYSTALS: int = 3
const REVEAL: int = 5
var _crystals0: int = 0
var _night_on: bool = false
var _night_t: float = 0.0
var _dug_ok: bool = false
var _hp0: Dictionary = {}
## Копатель ночи. Сценарий читает путь и урон, не телепортируя его.
var burrower: Phantom = null
## Клеток, которые копатель прошёл от выхода до удара (или до конца ночи).
var path_cells: int = 0
var _path_from: Vector2i = Vector2i(-9999, -9999)
## Секунды от выхода до первого урона постройке. −1 — удара не было.
var strike_at: float = -1.0


func _init() -> void:
	id = "sun"
	chapter = 5
	title = "Солнце"
	brief = "Утро. Коллектор ловит белый свет. В стене ствола спрятаны кристаллы — их покажет маяк."
	teaches = "коллектор, призма, накопитель; белый показывает руду, синий морозит"
	director = false
	start_time = 0.30
	hold_time = 0.30


func kit() -> Array:
	return [[IDs.I.COLLECTOR, 1], [IDs.I.PRISM, 1], [IDs.I.ACCUMULATOR, 1], [IDs.I.MIRROR, 2]]


func build() -> void:
	CampaignBase.build(CampaignBase.Tier.STATION)
	LightLate.clear_lane()
	LightLate.dig_shaft()
	var pharos: Pharos = CampaignBase.put("Pharos", LightLate.at(LightLate.PHAROS)) as Pharos
	if pharos == null:
		push_error("sun: маяк не встал")
	_snapshot_hp()


func stages() -> Array:
	return [
		{"title": "Коллектор",
			"hint": "Коллектор ставят там, где над ним нет крыши",
			"say": ["Утро. Коллектор ловит солнце и бьёт белым.",
					"Поставь его на открытом месте."],
			"goals": [["Поставь коллектор под небом", func() -> Vector2i: return flag(_white_out()),
				IDs.I.COLLECTOR, func() -> Vector2: return LightLate.world_at(LightLate.COLLECTOR)]]},
		{"title": "Ствол",
			"hint": "Белый в маяке показывает руду в стене",
			"say": ["Белый есть. Направь его в маяк — в стене ствола проступят кристаллы.",
					"Зеркало над маяком смотрит вниз."],
			"goals": [["Направь белый к стволу шахты", func() -> Vector2i: return Vector2i(_revealed(), REVEAL),
				IDs.I.PHAROS, func() -> Vector2: return World.cell_to_world(LightLate.nearest_crystal())]]},
		{"title": "Кристаллы",
			"hint": "Кристалл в стене ствола копается, как уголь",
			"say": ["Руда видна. Три кристалла хватит на ночь."],
			"enter": _note_crystals,
			"goals": [["Накопай 3 кристалла", func() -> Vector2i:
				return Vector2i(_crystal_gain(), CRYSTALS),
				IDs.I.CRYSTAL, func() -> Vector2: return World.cell_to_world(LightLate.nearest_crystal())]]},
		{"title": "Запас",
			"hint": "Кристалл в горелку, синий — в накопитель",
			"say": ["Кристалл в горелке даёт синий. Его и копим на ночь.",
					"Горелка смотрит в накопитель."],
			"enter": _place_optics,
			"goals": [["Накопи синий на ночь", func() -> Vector2i: return Vector2i(_stored_blue(), int(LightLate.STORE_NEED)),
				IDs.I.ACCUMULATOR, func() -> Vector2: return LightLate.world_at(LightLate.ACCUM)]]},
		{"title": "Ночь",
			"hint": "Накопитель сам отдаст синий, когда солнце сядет",
			"say": ["Ночь. Копатель идёт к маяку.",
					"Синий мороз его тормозит. Без синего постройка получит урон."],
			"enter": _begin_night,
			"goals": [["Переживи ночь", func() -> Vector2i: return flag(_night_done()),
				IDs.I.PHAROS, func() -> Vector2: return LightLate.world_at(LightLate.PHAROS)]]},
	]


func on_tick(delta: float) -> void:
	if not _night_on or result != Result.RUNNING:
		return
	_night_t += delta
	_steer_burrower()
	_note_path()
	if _night_t >= _guard_sec():
		Game.time_of_day = Balance.NIGHT_END - 0.002
		_night_on = false


func fail_reason() -> String:
	if stage < 4:
		return ""
	for c in _hp0:
		var m = World.machines.get(c)
		if m == null or not is_instance_valid(m) or m.is_queued_for_deletion():
			return "Постройка разрушена."
		if float(m.hp) < float(_hp0[c]) - 0.5:
			return "Постройка получила урон."
	return ""


func outro() -> String:
	return "Рассвет. Копатель шёл к маяку — синий мороз его не пустил.\n" \
			+ "ПЁС: «Свет можно копить. Завтра соберём все цвета.»"


func _white_out() -> bool:
	var c: Collector = _collector()
	if c == null or not c.emitting():
		return false
	if World.beams == null:
		return false
	var step: Vector2i = Beams.DIR[c.dir & 7]
	return World.beams.color_at(c.cell + step) == Beams.W


func _collector() -> Collector:
	for m in World.machines.values():
		if m is Collector and is_instance_valid(m):
			return m
	return null


func _pharos() -> Pharos:
	return World.machines.get(LightLate.at(LightLate.PHAROS)) as Pharos


## Клеток кристалла в стене, которые белый уже открыл.
func _revealed() -> int:
	var n: int = 0
	for row in LightLate.CRYSTAL_ROWS:
		var c: Vector2i = LightLate.crystal_cell(int(row))
		if World.get_tile_v(c) == IDs.T.CRYSTAL_ORE and World.is_explored(c):
			n += 1
	return n


func _note_crystals() -> void:
	_crystals0 = heroes_have(IDs.I.CRYSTAL)


func _crystal_gain() -> int:
	var n: int = heroes_have(IDs.I.CRYSTAL) - _crystals0
	if n >= CRYSTALS:
		_dug_ok = true
	return CRYSTALS if _dug_ok else maxi(0, n)


## Призма, накопитель и горелка — на площадке. Игрок кладёт кристалл сам.
func _place_optics() -> void:
	# Призма на линии белого: игрок видит, как белый делится. Синий в запас
	# даёт горелка — кристалл кладёт игрок, носик смотрит в накопитель.
	var prism: Prism = CampaignBase.put("Prism", LightLate.at(LightLate.PRISM), {"dir": 0}) as Prism
	if prism != null:
		prism.dir = 0
	var acc: Accumulator = CampaignBase.put("Accumulator", LightLate.at(LightLate.ACCUM), {"dir": 2}) as Accumulator
	if acc != null:
		acc.dir = 2
	var burner: Burner = CampaignBase.put("Burner", LightLate.at(LightLate.BURNER), {"dir": 2}) as Burner
	if burner != null:
		burner.dir = 2
		burner.permanent = false
	_snapshot_hp()


func _stored_blue() -> int:
	var acc: Accumulator = World.machines.get(LightLate.at(LightLate.ACCUM)) as Accumulator
	if acc == null or acc.color != Beams.B:
		return 0
	return int(floor(acc.stored))


func _begin_night() -> void:
	hold_time = -1.0
	Game.time_of_day = Balance.NIGHT_START
	_night_on = true
	_night_t = 0.0
	_arm_blue()
	_snapshot_hp()
	# Лампы лагеря светят до самой ямы ствола: тёмной клетки на полу нет,
	# и копатель не выходит (#218). Гасим две левые и кладём пол хода.
	# Синий стан держит его у кромки мороза; без синего он доходит и бьёт.
	_carve_lane()
	var spot: Vector2i = _burrower_spot()
	var made: Array = Threat.spawn_phantom("burrower", World.cell_to_world(spot), {})
	if made.is_empty():
		return
	burrower = made[0]
	_path_from = World.world_to_cell(burrower.global_position)
	_steer_burrower()


## Сколько ночи держит запас. Без запаса — полная ночь: копатель успевает ударить.
func _guard_sec() -> float:
	var acc: Accumulator = World.machines.get(LightLate.at(LightLate.ACCUM)) as Accumulator
	if acc == null or acc.color != Beams.B or acc.stored < 1.0:
		return LightLate.NIGHT_SEC
	return minf(LightLate.NIGHT_SEC, acc.stored)


## Накопитель отдаёт, даже если вход ещё жив: ночью коллектор молчит,
## но рубильник не даёт синему застрять на грани.
func _arm_blue() -> void:
	var acc: Accumulator = World.machines.get(LightLate.at(LightLate.ACCUM)) as Accumulator
	if acc == null:
		return
	acc.set_mode(Accumulator.MODE_EMIT)


func _night_done() -> bool:
	# Запаса синего хватает на 30 с. Ночь не длиннее запаса: иначе копатель
	# бьёт маяк в ту же секунду, как луч гаснет, и защита не побеждает.
	return _night_t >= _guard_sec() and not Game.is_night()


## Две левые лампы лагеря (cx−11 и cx−3) светят на 1.0 до кромки ямы.
## Без них ход слева от двери темнее порога бегства, и копатель выходит.
func _dim_camp() -> void:
	var b: Vector2i = World.beacon_cell
	for dx in [-11, -3]:
		var c: Vector2i = Vector2i(b.x + dx, b.y)
		if World.get_tile_v(c) == IDs.T.LIGHT_CRYSTAL:
			World.set_tile(c.x, c.y, IDs.T.AIR)


## Ход на ряду маяка: воздух над сталью, от тёмной клетки до башни.
## Сталь копатель не роет. Яма ствола западнее двери закрыта полом.
func _carve_lane() -> void:
	_dim_camp()
	var ph: Vector2i = LightLate.at(LightLate.PHAROS)
	var door: Vector2i = CampaignBase.camp_door()
	var x0: int = door.x - 6
	for x in range(x0, ph.x):
		var c: Vector2i = Vector2i(x, ph.y)
		if not World.machines.has(c) and World.get_tile_v(c) != IDs.T.AIR:
			World.set_tile(c.x, c.y, IDs.T.AIR)
		var floor: Vector2i = Vector2i(x, ph.y + 1)
		if not World.machines.has(floor) and not World.is_solid_cell(floor):
			World.set_tile(floor.x, floor.y, IDs.T.STEEL)


## Тёмная клетка хода не ближе четырёх клеток к маяку: вплотную удар
## не выглядит ходом, а свет ламп западнее двери копателя разворачивает.
func _burrower_spot() -> Vector2i:
	var door: Vector2i = CampaignBase.camp_door()
	var flee: float = float(Balance.PHANTOMS["burrower"]["light_flee"])
	var ph: Vector2i = LightLate.at(LightLate.PHAROS)
	var best: Vector2i = Vector2i(door.x - 2, ph.y)
	var bd: int = 1 << 30
	for x in range(door.x - 6, ph.x - 3):
		var c: Vector2i = Vector2i(x, ph.y)
		if not _walkable(c) or World.light_at(c) > flee:
			continue
		var d: int = absi(c.x - ph.x)
		if d < bd:
			bd = d
			best = c
	return best


func _walkable(c: Vector2i) -> bool:
	if not World.in_bounds(c.x, c.y) or World.machines.has(c):
		return false
	if World.is_solid_cell(c):
		return false
	return World.is_solid_cell(c + Vector2i(0, 1))


## Цель осады — маяк. Пока он стоит, копатель идёт к нему сквозь свет луча.
func _steer_burrower() -> void:
	if burrower == null or not is_instance_valid(burrower) or not burrower.alive:
		return
	var pharos: Pharos = _pharos()
	if pharos == null or not is_instance_valid(pharos):
		return
	if burrower.siege_target == pharos:
		return
	burrower.siege(pharos)


func _note_path() -> void:
	if burrower == null or not is_instance_valid(burrower):
		return
	var here: Vector2i = World.world_to_cell(burrower.global_position)
	if _path_from.x < -1000:
		_path_from = here
		return
	path_cells = maxi(path_cells, absi(here.x - _path_from.x) + absi(here.y - _path_from.y))
	if strike_at < 0.0 and _building_hurt():
		strike_at = _night_t


func _building_hurt() -> bool:
	for c in _hp0:
		var m = World.machines.get(c)
		if m == null or not is_instance_valid(m):
			return true
		if float(m.hp) < float(_hp0[c]) - 0.5:
			return true
	return false


func _snapshot_hp() -> void:
	_hp0.clear()
	for c in World.machines:
		var m = World.machines[c]
		if is_instance_valid(m) and not m.is_queued_for_deletion():
			_hp0[c] = float(m.hp)
