extends Mission
## Глава 4 «Цвета» (ADR-005 § 9, #178, #217): медь — зелёный, смесь — жёлтый.
##
## Красная горелка уже горит. Вторая пустая — медь кладёт игрок. Зеркало
## над смесителем смотрит мимо: тап сводит лучи, жёлтый сам доходит до маяка.
## Ночь — не ожидание. Эхо выходит из тёмной клетки у входа и идёт к герою.
## Прожектор на старте ночи погашен: пока игрок его не зажжёт тапом, эхо
## доходит и бьёт. Зажёг — эхо отступает, и ночь можно пережить.

## Ночь главы, с. До главы 6 ночь не длиннее 60.
const NIGHT_SEC: float = 40.0
const ECHOES: int = 2
## Сколько эхо ведём к герою, с. Свет ярче порога перебивает — оно отступает.
const APPROACH_SEC: float = 16.0
## Ближе этого эхо уже у героя: удар засчитан, даже если кадр прошёл мимо.
const HIT_PX: float = 28.0

var _day0: int = 1
var _night_on: bool = false
var _night_t: float = 0.0
## Эхо дошло до героя (удар или дистанция). Сценарий читает.
var echo_struck: bool = false
## Игрок зажёг прожектор тапом, пока эхо было в мире.
var lamp_lit: bool = false
## Секунды от выхода эха до удара или до отступления. −1 — ещё не было.
var strike_at: float = -1.0
var _echoes: Array = []


func _init() -> void:
	id = "colors"
	chapter = 4
	title = "Цвета"
	brief = "Медь горит зелёным. Два луча в смесителе дают жёлтый — его ждёт маяк."
	teaches = "медь даёт зелёный луч, смесь — жёлтый; прожектор гасит тапом и зажигает снова"
	start_time = 0.30
	hold_time = 0.30


func kit() -> Array:
	return [[IDs.I.COPPER_ORE, 4]]


func build() -> void:
	# Красная — правее зеркала, носик влево.
	var red: Burner = CampaignBase.put("Burner", LightLayout.at(LightLayout.BURNER_R),
			{"dir": 2}) as Burner
	if red != null:
		red.dir = 2
		red.add_fuel(IDs.I.COAL, Burner.FUEL_MAX)
	# Вторая горелка пустая, носик вправо — зелёный входит в смеситель слева.
	var green: Burner = CampaignBase.put("Burner", LightLayout.at(LightLayout.BURNER_G),
			{"dir": 0}) as Burner
	if green != null:
		green.dir = 0
	# Зеркало над смесителем. Два тапа (шаг 45°) ставят «\»: вправо → вниз.
	var bend: Mirror = CampaignBase.put("Mirror", LightLayout.at(LightLayout.MIRROR4),
			{"dir": 0}) as Mirror
	if bend != null:
		bend.dir = 0
		bend.permanent = false
	# Смеситель: выход вправо. Красный входит сверху, зелёный — слева.
	var mixer: Mixer = CampaignBase.put("Mixer", LightLayout.at(LightLayout.MIXER),
			{"dir": 0}) as Mixer
	if mixer != null:
		mixer.dir = 0
	var pharos: Pharos = CampaignBase.put("Pharos", LightLayout.at(LightLayout.PHAROS)) as Pharos
	if pharos == null:
		push_error("colors: маяк не встал")
	# Подвал прошлой главы уже открыт: та же комната, сундук пуст.
	LightLayout.dig_cellar([])
	_clear_lane()


func stages() -> Array:
	return [
		{"title": "Медь",
			"hint": "Тап медью у второй горелки",
			"say": ["Красный уже горит. Вторая горелка пустая.",
					"Медь в топке даёт зелёный луч."],
			"goals": [["Положи медь во вторую горелку", func() -> Vector2i: return flag(_green()),
				IDs.I.COPPER_ORE, func() -> Vector2: return LightLayout.world_at(LightLayout.BURNER_G)]]},
		{"title": "Смесь",
			"hint": "Тап по зеркалу сводит лучи",
			"say": ["Два цвета надо свести. Зеркало над лагерем смотрит мимо.",
					"На выходе смесителя будет жёлтый."],
			"goals": [["Сведи лучи в смеситель", func() -> Vector2i: return flag(_yellow_out()),
				IDs.I.MIXER, func() -> Vector2: return LightLayout.world_at(LightLayout.MIX_OUT)]]},
		{"title": "Маяк",
			"hint": "Тап по маяку гасит прожектор",
			"say": ["Жёлтый дошёл. Прожектор горит — эхо к нему не подойдёт.",
					"Погаси его: ночью зажжёшь снова, когда эхо будет близко."],
			"goals": [["Погаси прожектор маяка", func() -> Vector2i: return flag(_lamp_out()),
				IDs.I.PHAROS, func() -> Vector2: return LightLayout.world_at(LightLayout.PHAROS)]]},
		{"title": "Ночь",
			"hint": "Эхо бьёт, пока прожектор погашен",
			"say": ["Короткая ночь. Эхо идёт к тебе и бьёт.",
					"Зажги прожектор тапом — и оно отступит."],
			"enter": _begin_night,
			"goals": [["Переживи короткую ночь", func() -> Vector2i: return flag(_night_done()),
				IDs.I.PHAROS, func() -> Vector2: return LightLayout.world_at(LightLayout.PHAROS)]]},
	]


func on_tick(delta: float) -> void:
	if not _night_on or result != Result.RUNNING:
		return
	_night_t += delta
	_steer(delta)
	if _night_t >= NIGHT_SEC:
		Game.time_of_day = Balance.NIGHT_END - 0.002
		_night_on = false


func fail_reason() -> String:
	if stage < 3 or result != Result.RUNNING:
		return ""
	var p = Game.player
	if p != null and is_instance_valid(p) and bool(p.get("dead")):
		return "Эхо дошло. Прожектор был погашен."
	return ""


func outro() -> String:
	return "Рассвет. Эхо дошло — и отступило, когда прожектор зажёгся.\n" \
			+ "ПЁС: «Свет держит, пока ты его не погасишь. Завтра научимся копить.»"


func _green() -> bool:
	var b: Burner = World.machines.get(LightLayout.at(LightLayout.BURNER_G)) as Burner
	return b != null and b.burning() and b.color == Beams.G


## Жёлтый на выходе смесителя. Маяк сюда не подмешиваем: иначе «сведи лучи»
## закрывается тем же лучом, что и следующий этап (#217).
func _yellow_out() -> bool:
	if World.beams == null:
		return false
	return World.beams.color_at(LightLayout.at(LightLayout.MIX_OUT)) == Beams.Y


func _pharos() -> Pharos:
	return World.machines.get(LightLayout.at(LightLayout.PHAROS)) as Pharos


func _pharos_yellow() -> bool:
	var p: Pharos = _pharos()
	return p != null and p.color == Beams.Y and p.active


## Прожектор погашен, жёлтый луч при этом остаётся: иначе этап «Маяк» —
## просто следствие смеси, и своего действия у него нет.
func _lamp_out() -> bool:
	var p: Pharos = _pharos()
	return p != null and p.color == Beams.Y and p.active and p.lamp_off and not p._lit


func _night_done() -> bool:
	if _night_t < NIGHT_SEC or Game.day_number <= _day0:
		return false
	# Ночь не проходит сама: либо эхо ударило, либо игрок его остановил.
	return echo_struck or lamp_lit


func _begin_night() -> void:
	_day0 = Game.day_number
	hold_time = -1.0
	Game.time_of_day = Balance.NIGHT_START
	_night_on = true
	_night_t = 0.0
	# Прожектор на старте ночи погашен, даже если игрок снова его зажёг.
	# Иначе эхо выходит уже в свете и отступает, не дойдя.
	var p: Pharos = _pharos()
	if p != null and p.color == Beams.Y:
		p.lamp_off = true
		p.relight()
	var spot: Vector2i = _echo_spot()
	for i in ECHOES:
		_release(spot, 1.2 + float(i) * 6.0)


## Тёмная клетка у входа лагеря, откуда до героя есть ход по воздуху.
## Вентиляция базы светит сильнее порога бегства — оттуда эхо сразу убегает.
func _echo_spot() -> Vector2i:
	var door: Vector2i = CampaignBase.camp_door()
	var flee: float = float(Balance.PHANTOMS["echo"]["light_flee"])
	var best: Vector2i = door + Vector2i(-4, -2)
	var bd: int = 1 << 30
	for y in range(door.y - 4, door.y + 1):
		for x in range(door.x - 8, door.x - 1):
			var c: Vector2i = Vector2i(x, y)
			if not _open(c) or World.light_at(c) > flee:
				continue
			if not _open(c + Vector2i(0, 1)):
				continue
			var d: int = absi(c.x - door.x) + absi(c.y - (door.y - 1))
			if d < bd:
				bd = d
				best = c
	return best


func _open(c: Vector2i) -> bool:
	if not World.in_bounds(c.x, c.y):
		return false
	if World.machines.has(c):
		return false
	return not World.is_solid_cell(c)


func _release(spot: Vector2i, after: float) -> void:
	_echoes.append({"t": after, "spot": spot, "ph": null, "led": false})


func _steer(delta: float) -> void:
	var hero = Game.player
	if hero == null or not is_instance_valid(hero):
		return
	var flee: float = float(Balance.PHANTOMS["echo"]["light_flee"])
	var lamp: Pharos = _pharos()
	if lamp != null and lamp.color == Beams.Y and lamp.active and not lamp.lamp_off and lamp._lit:
		if not _echoes.is_empty():
			lamp_lit = true
	for e in _echoes:
		e["t"] = float(e["t"]) - delta
		var ph: Phantom = e["ph"] as Phantom
		if ph == null or not is_instance_valid(ph) or not ph.alive:
			if float(e["t"]) <= 0.0 and not bool(e["led"]):
				var made: Array = Threat.spawn_phantom("echo", World.cell_to_world(e["spot"]), {})
				if not made.is_empty():
					e["ph"] = made[0]
					e["led"] = true
					ph = made[0]
			else:
				continue
		var dist: float = ph.global_position.distance_to(hero.global_position)
		if dist <= HIT_PX or hero.hp < Player.MAX_HP - 0.5:
			if not echo_struck:
				echo_struck = true
				strike_at = _night_t
		if ph.state == Phantom.St.FLEE:
			if strike_at < 0.0:
				strike_at = _night_t
			continue
		if World.light_at(World.world_to_cell(ph.global_position)) > flee:
			continue
		var at: Vector2 = hero.global_position
		if ph.approach_t > 1.0 and ph.approach_at.distance_to(at) < 24.0:
			continue
		ph.approach(APPROACH_SEC, at)


## Воздух на линиях лучей главы: полка, сход красного, выход смесителя до маяка.
func _clear_lane() -> void:
	var b: Vector2i = World.beacon_cell
	# Полоса над полом и ряд зеркала: панели лагеря и лампы луч не пропускают.
	for y in [b.y - 5, b.y - 4, b.y - 3, b.y - 2, b.y - 1]:
		for x in range(b.x + 3, b.x + 14):
			if World.machines.has(Vector2i(x, y)):
				continue
			if World.get_tile(x, y) != IDs.T.AIR:
				World.set_tile(x, y, IDs.T.AIR)
