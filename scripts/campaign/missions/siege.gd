extends Mission
## Глава 4 «Осада»: вся база — станция, цех, шахта и три турели. Сумерки ждут, пока
## база не готова: поставить четвёртую турель, решётку на вентиляцию базы, второй
## прожектор. Потом — ночь осады: волны эха, роя, теней и копателей из вентиляций.
## Учит: турели и их питание, решётки вентиляций, прожекторы, ремонт хламом (E),
## импульс. Провал — фантомы разрушили LOST_MAX построек.

## Сколько построек можно потерять: на LOST_MAX-й база пала.
const LOST_MAX: int = 4
## Волны ночи: [через сколько с от начала ночи, вид].
const WAVES: Array = [
	[4.0, "echo"], [6.0, "echo"], [14.0, "swarm"], [24.0, "shade"], [32.0, "echo"],
	[40.0, "burrower"], [48.0, "swarm"], [56.0, "shade"], [64.0, "burrower"], [66.0, "echo"],
	[74.0, "swarm"],
]

var b: Dictionary = {}
var lost: int = 0
var _vent: Vector2i = Vector2i(-1, -1)
var _day0: int = 1
var _watched: Dictionary = {}


func _init() -> void:
	id = "siege"
	chapter = 4
	title = "Осада"
	brief = "База гудит на всю планету: цех, шахта, шесть генераторов. Этой ночью фантомы придут все разом."
	teaches = "турели и их питание, решётка вентиляции, прожектор, ремонт хламом, оборона ночью"
	start_time = 0.45
	hold_time = Balance.DUSK_START - 0.01


func build() -> void:
	b = CampaignBase.build(CampaignBase.Tier.DEFENSE)
	CampaignBase.unlock_to("T4")
	Game.research = 6
	_vent = _base_vent()
	(b["parts"] as Chest).receive_item(IDs.I.SCRAP, 30)
	(b["parts"] as Chest).receive_item(IDs.I.COAL, 20)


func kit() -> Array:
	return [[IDs.I.TURRET, 1], [IDs.I.VENT_GRATE, 1], [IDs.I.FLOODLIGHT, 1], [IDs.I.COAL, 10],
			[IDs.I.SCRAP, 12], [IDs.I.STEEL_WALL, 8]]


func stages() -> Array:
	return [
		{"title": "Подготовка", "hint": "Сумерки ждут, пока база не готова · турели и прожектор — только в зоне питания (P)",
			"say": ["База шумит: шесть генераторов, свет, буры. Ночью нас будет слышно с любого конца карты.",
					"Сумерки подождут, пока мы готовимся. В наборе — турель, решётка и прожектор.",
					"Решётка на вентиляцию у края базы закроет ближайший выход. Им придётся идти издалека."],
			"goals": [
				["Четвёртая турель под питанием", func() -> Vector2i: return Vector2i(_powered("Turret"), 4)],
				["Решётка на вентиляции базы", func() -> Vector2i: return flag(World.is_vent_sealed(_vent))],
				["Второй прожектор под питанием", func() -> Vector2i: return Vector2i(_powered("Floodlight"), 2)]],
			"done": func() -> void: hold_time = -1.0},
		{"title": "Осада", "hint": "Чините постройки: E с хламом в руке · Q — импульс · сталь и уголь — в сундуке «Запчасти»",
			"say": ["Темнеет. Турели бьют сами — следите, чтобы у ТЭЦ был уголь.",
					"Рой грызёт буры, тени высасывают генераторы, копатели роют глину. Держитесь до рассвета."],
			"enter": _begin_night,
			"goals": [["Дожить до рассвета", func() -> Vector2i: return flag(Game.day_number > _day0)]]},
	]


func on_tick(_delta: float) -> void:
	if stage == 1:
		hint = "Построек потеряно: %d из %d · E с хламом — починить · Q — импульс" % [lost, LOST_MAX - 1]


func fail_reason() -> String:
	if lost >= LOST_MAX:
		return "База пала: фантомы разрушили %d построек." % lost
	return ""


func outro() -> String:
	return "Рассвет над разбитым полем. Турели остывают, ПЁС считает потери: %d.\n" % lost \
			+ "ПЁС: «Мы выстояли. Теперь — релей. Если сигнал уйдёт на орбиту, за нами прилетят.»"


func _begin_night() -> void:
	_day0 = Game.day_number
	Game.time_of_day = Balance.NIGHT_START - 2.0 / Balance.DAY_LENGTH
	lost = 0
	for c in World.machines:
		_watch(World.machines[c])
	for w in WAVES:
		wave(String(w[1]), _vent, float(w[0]))


func _process(delta: float) -> void:
	super(delta)
	if stage == 1 and not puppet:
		for c in World.machines:   # постройки, поставленные посреди осады, тоже считаются
			_watch(World.machines[c])


func _watch(m) -> void:
	if not is_instance_valid(m) or _watched.has(m.get_instance_id()):
		return
	_watched[m.get_instance_id()] = true
	m.destroyed.connect(func(_mb) -> void: lost += 1)


func _powered(kind: String) -> int:
	var n: int = 0
	for c in World.machines:
		var m = World.machines[c]
		if is_instance_valid(m) and String(m.kind) == kind and m.powered:
			n += 1
	return n


func _base_vent() -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var bd: int = 1 << 30
	for v in World.vents:
		var d: int = absi(v.x - World.beacon_cell.x) + absi(v.y - World.beacon_cell.y)
		if d < bd:
			bd = d
			best = v
	return best
