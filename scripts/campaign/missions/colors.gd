extends Mission
## Глава 4 «Цвета» (ADR-005 § 9, #178): медь — зелёный, смесь — жёлтый.
##
## Красная горелка уже горит. Вторая пустая, смеситель и маяк стоят.
## В наборе — медная руда. Жёлтый в маяке зажигает прожектор; короткая ночь
## (40 с) с двумя эхо. С этой главы эхо бьёт, но жёлтый свет его не подпускает.

## Ночь главы, с. До главы 6 ночь не длиннее 60.
const NIGHT_SEC: float = 40.0
const ECHOES: int = 2

var _day0: int = 1
var _night_on: bool = false
var _night_t: float = 0.0


func _init() -> void:
	id = "colors"
	chapter = 4
	title = "Цвета"
	brief = "Медь горит зелёным. Два луча в смесителе дают жёлтый — его ждёт маяк."
	teaches = "медь даёт зелёный луч, смесь — жёлтый, маяк светит прожектором"
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
			"goals": [["Сведи лучи в смеситель", func() -> Vector2i: return flag(_mixed()),
				IDs.I.MIXER, func() -> Vector2: return LightLayout.world_at(LightLayout.MIX_OUT)]]},
		{"title": "Маяк",
			"hint": "Жёлтый должен упереться в маяк",
			"say": ["Жёлтый есть. Маяк стоит дальше по лучу.",
					"Попадёт жёлтый — башня зажжётся прожектором."],
			"goals": [["Направь жёлтый в маяк", func() -> Vector2i: return flag(_pharos_yellow()),
				IDs.I.PHAROS, func() -> Vector2: return LightLayout.world_at(LightLayout.PHAROS)]]},
		{"title": "Ночь",
			"hint": "Держись в жёлтом свете маяка",
			"say": ["Короткая ночь. Эхо уже бьёт.",
					"В жёлтом свете оно не подходит."],
			"enter": _begin_night,
			"goals": [["Переживи короткую ночь", func() -> Vector2i: return flag(_night_done()),
				IDs.I.PHAROS, func() -> Vector2: return LightLayout.world_at(LightLayout.PHAROS)]]},
	]


func on_tick(delta: float) -> void:
	if not _night_on or result != Result.RUNNING:
		return
	_night_t += delta
	# 40 с ночи, потом сразу рассвет — не ждать остаток цикла.
	if _night_t >= NIGHT_SEC:
		Game.time_of_day = Balance.NIGHT_END - 0.002
		_night_on = false


func outro() -> String:
	return "Рассвет. Маяк горит жёлтым, эхо к базе не подошло.\n" \
			+ "ПЁС: «Прожектор держит. Завтра научимся копить свет на ночь.»"


func _green() -> bool:
	var b: Burner = World.machines.get(LightLayout.at(LightLayout.BURNER_G)) as Burner
	return b != null and b.burning() and b.color == Beams.G


## Смесь видна либо жёлтым на выходе, либо жёлтым маяком: выход смесителя
## делит клетку с зелёным входом, и чистый жёлтый там не держится.
func _mixed() -> bool:
	if _yellow_out() or _pharos_yellow():
		return true
	return false


func _yellow_out() -> bool:
	if World.beams == null:
		return false
	return World.beams.color_at(LightLayout.at(LightLayout.MIX_OUT)) == Beams.Y


func _pharos_yellow() -> bool:
	var p: Pharos = World.machines.get(LightLayout.at(LightLayout.PHAROS)) as Pharos
	return p != null and p.color == Beams.Y and p.active


func _night_done() -> bool:
	return _night_t >= NIGHT_SEC and Game.day_number > _day0


func _begin_night() -> void:
	_day0 = Game.day_number
	hold_time = -1.0
	Game.time_of_day = Balance.NIGHT_START
	_night_on = true
	_night_t = 0.0
	var vent: Vector2i = _base_vent()
	for i in ECHOES:
		wave("echo", vent, 4.0 + float(i) * 8.0)


func _base_vent() -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var bd: int = 1 << 30
	for v in World.vents:
		var d: int = absi(v.x - World.beacon_cell.x) + absi(v.y - World.beacon_cell.y)
		if d < bd:
			bd = d
			best = v
	return best


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
