extends Mission
## Глава 6 «Радуга» (ADR-005 § 9, #179).
##
## Ядро — предмет. Сундук несёт топливо на семь цветов и само ядро.
## Семь дуг, запуск (E 3 с), удержание 90 с на скорости 2. Ночь ведёт директор
## по формуле E3; двойник в главе не приходит. Кот выходит из ядра — победа.


const HOLD_SEC: float = 90.0
const SPEED: float = 2.0

var _held: float = 0.0
var _hold0: float = -1.0
var _launched: bool = false


func _init() -> void:
	id = "rainbow"
	chapter = 6
	title = "Радуга"
	brief = "В сундуке — ядро и топливо на семь цветов. Семь дуг зовут кота. Ночь придёт сама."
	teaches = "радужное ядро: семь дуг, запуск, кот на ночи осады"
	director = true
	start_time = 0.30
	hold_time = 0.30


func kit() -> Array:
	# Ядро и топливо — в сундуке, не в руках. Зеркало и призма — довести луч.
	return [[IDs.I.MIRROR, 2], [IDs.I.PRISM, 1]]


func build() -> void:
	CampaignBase.build(CampaignBase.Tier.STATION)
	LightLate.clear_lane()
	LightLate.dig_shaft()
	# Площадка света уже стоит: коллектор, маяк, горелка. Ядро игрок ставит сам.
	var col: Collector = CampaignBase.put("Collector", LightLate.at(LightLate.COLLECTOR), {"dir": 2}) as Collector
	if col != null:
		col.dir = 2
	var pharos: Pharos = CampaignBase.put("Pharos", LightLate.at(LightLate.PHAROS)) as Pharos
	if pharos == null:
		push_error("rainbow: маяк не встал")
	var burner: Burner = CampaignBase.put("Burner", LightLate.at(LightLate.BURNER), {"dir": 2}) as Burner
	if burner != null:
		burner.dir = 2
		burner.permanent = false
	var chest: Chest = CampaignBase.put("Chest", LightLate.at(LightLate.CHEST), {"items": [
		[IDs.I.COAL, 12], [IDs.I.COPPER_ORE, 12], [IDs.I.CRYSTAL, 8], [IDs.I.RAINBOW_CORE, 1],
	]}) as Chest
	if chest != null:
		chest.permanent = false
	_clear_parts()


func stages() -> Array:
	return [
		{"title": "Ядро",
			"hint": "Ядро лежит в сундуке у лагеря",
			"say": ["Ядро — предмет. Поставь его, где хочешь.",
					"Топливо на семь цветов — там же."],
			"goals": [["Поставь ядро", func() -> Vector2i: return flag(Game.core_placed()),
				IDs.I.RAINBOW_CORE]],
			"done": _lock_core},
		{"title": "Дуги",
			"hint": "Каждый чистый цвет луча зажигает свою дугу",
			"say": ["Семь цветов — семь дуг. Смесь на карточке.",
					"Уголь красный, медь зелёная, кристалл синий."],
			"goals": [["Зажги семь дуг", func() -> Vector2i: return Vector2i(Game.core_arc_count(), 7),
				IDs.I.RAINBOW_CORE, func() -> Vector2: return _core_at()]]},
		{"title": "Запуск",
			"hint": "Держи у ядра, пока столб не ударит в небо",
			"say": ["Семь дуг горят. Запусти ядро.",
					"Три секунды удержания — и пойдёт сигнал."],
			"goals": [["Запусти ядро", func() -> Vector2i: return flag(Game.relay_active or _launched),
				IDs.I.RAINBOW_CORE, func() -> Vector2: return _core_at()]],
			"done": _on_launch},
		{"title": "Сигнал",
			"hint": "Держись у ядра, пока кот не выйдет",
			"say": ["Ночь-осада. Кот выйдет из ядра сам.",
					"Двойника не будет — его место занял кот."],
			"enter": _begin_hold,
			"goals": [["Удержи сигнал", func() -> Vector2i: return Vector2i(_hold_have(), int(HOLD_SEC)),
				IDs.I.RAINBOW_CORE, func() -> Vector2: return _core_at()]]},
	]


func on_tick(delta: float) -> void:
	if stage == 2 and Game.relay_active:
		_launched = true
	if not _launched or result != Result.RUNNING:
		return
	# Удержание главы — 90 с, не 180. Скорость 2, как у старой главы 5.
	# Считаем по Game.game_time: физика сценария отстаёт от часов машин.
	if Game.relay_active:
		Game.relay_speed = SPEED
		if _hold0 < 0.0:
			_hold0 = Game.game_time
		_held = (Game.game_time - _hold0) * SPEED
	if _held >= HOLD_SEC and result == Result.RUNNING:
		_finish_hold()


func fail_reason() -> String:
	if stage >= 1 and not Game.core_placed() and not _launched:
		return "Ядро снято."
	return ""





func outro() -> String:
	return "Сигнал держится. Из ядра вылетел Радужный кот — страж на девяносто секунд.\n" \
			+ "ПЁС: «Семь цветов собраны. Планета больше не тёмная.»"


func _core_at() -> Vector2:
	if Game.core_cell.x >= 0:
		return World.cell_to_world(Game.core_cell)
	return LightLate.world_at(LightLate.CHEST)


func _on_launch() -> void:
	_launched = true
	Game.relay_speed = SPEED
	# Солнце держим до запуска: иначе ночь осады приходит на этапе дуг.
	hold_time = -1.0


## Ядро главы не разбирается: E у него — запуск, не снятие.
func _lock_core() -> void:
	var core = World.machines.get(Game.core_cell)
	if core != null and is_instance_valid(core):
		core.permanent = true


func _begin_hold() -> void:
	hold_time = -1.0
	# Ночь сразу: директор считает уровень «семь цветов» (релей в формуле T).
	Game.time_of_day = Balance.NIGHT_START
	Game.relay_speed = SPEED
	if not Game.relay_active:
		Game.core_launch()
	_launched = Game.relay_active


## В главе запуск — семь дуг и E, не сдача деталей свободного релея.
## try_finish в миссии зовёт _try_finish_parts и смотрит relay_req.
func _clear_parts() -> void:
	if not Game.relay_req.is_empty():
		Game.relay_req = {}


func _hold_have() -> int:
	return mini(int(HOLD_SEC), int(floor(_held)))


## 90 с удержания — победа главы, не эвакуация свободной игры.
func _finish_hold() -> void:
	Game.relay_speed = 1.0
	Game.relay_active = false
	Game.relay_timer = Balance.RELAY_TIME
	win()
