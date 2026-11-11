extends Mission
## Глава 5 «Сигнал»: финал. Детали релей-ядра собраны за прошлые смены — не хватает
## антенны. Собрать её в сборщике, сдать всё в ядро (E у релея) и удержать сигнал.
## Учит: антенну релея, вклад деталей в релей, удержание сигнала — ночь с двойником
## ведёт штатный директор угрозы (director = true с запуска релея).

## Отсчёт сигнала в главе вдвое быстрее (Game.relay_speed): 90 с вместо 180.
const RELAY_SPEED: float = 2.0

var b: Dictionary = {}


func _init() -> void:
	id = "signal"
	chapter = 5
	title = "Сигнал"
	brief = "Детали релей-ядра собраны. Не хватает антенны — и одной ночи, которую надо пережить у ядра."
	teaches = "антенна релея, вклад деталей в ядро, удержание сигнала под атакой"


func build() -> void:
	b = CampaignBase.build(CampaignBase.Tier.DEFENSE)
	var parts: Chest = b["parts"]
	# Антенна: 6 медных пластин, 4 стекла, 2 кристальных блока (DB, сборщик, T5).
	parts.receive_item(IDs.I.COPPER_PLATE, 6)
	parts.receive_item(IDs.I.GLASS, 4)
	parts.receive_item(IDs.I.CRYSTAL_BLOCK, 2)
	# Остальное ядро — в сундуке у релея. Требование растёт с числом героев (#139), а
	# товарищи входят позже постройки базы — кладём на полную команду.
	var core: MachineBase = CampaignBase.put("Chest", Vector2i(World.beacon_cell.x + 2, World.beacon_cell.y))
	b["core_parts"] = core
	var req: Dictionary = Game.relay_req_for(Balance.MP_MAX_PLAYERS)
	for id_item in req:
		if int(id_item) != IDs.I.RELAY_ANTENNA:
			core.receive_item(int(id_item), int(req[id_item]))
	(b["store"] as Chest).receive_item(IDs.I.SCRAP, 30)
	(b["store"] as Chest).receive_item(IDs.I.COAL, 20)


func kit() -> Array:
	return [[IDs.I.COAL, 10], [IDs.I.SCRAP, 12], [IDs.I.LAMP, 4]]


func stages() -> Array:
	return [
		{"title": "Антенна", "hint": "Сундук «Запчасти» у края цеха → в сборщик (E с предметом в руке)",
			"say": ["Последняя деталь — антенна. Рецепт у сборщика в цехе.",
					"Медные пластины, стекло и кристальные блоки — в сундуке у края цеха."],
			"goals": [["Антенна релея собрана", func() -> Vector2i:
				return Vector2i(_antennas(), 1)]]},
		{"title": "Ядро", "hint": "Детали — в сундуке у релея · держите E у релей-ядра: сдать и запустить",
			"say": ["Остальные детали ядра — в сундуке рядом с релеем. Возьмите их и держите E у ядра.",
					"Когда ядро запустится, сигнал услышат все. Будьте у ядра — и не дайте им его заглушить."],
			"goals": [["Релей запущен", func() -> Vector2i: return flag(Game.relay_active)]]},
		{"title": "Сигнал", "hint": "Будьте у ядра · турели и прожекторы — под питанием · двойник носит ваш скафандр",
			"say": ["Сигнал пошёл! Девяносто секунд. Они идут — все, кто есть."],
			"enter": _start_hold,
			"goals": [["Удержать сигнал", func() -> Vector2i:
				return Vector2i(int(Balance.RELAY_TIME - Game.relay_timer), int(Balance.RELAY_TIME))]]},
	]


func outro() -> String:
	return Lore.epilogue(Game.epilogue_stats()) + "\nКампания пройдена. Свободная игра ждёт в главном меню — новый мир, новый сид."


func _start_hold() -> void:
	director = true
	Game.relay_speed = RELAY_SPEED


func _antennas() -> int:
	return heroes_have(IDs.I.RELAY_ANTENNA) + chest_has(b["asm_out"], IDs.I.RELAY_ANTENNA) \
			+ Game.relay_count(IDs.I.RELAY_ANTENNA) + (1 if Game.relay_active else 0)
