extends Mission
## Глава 2 «Конвейер»: станция запитана, к востоку — цех. Линия «бур → конвейер →
## плавильня → склад» порвана: одной ленты нет. Учит: конвейер и его поворот, работу
## бура и плавильни, загрузку сборщика, манипулятор.

const INGOTS: int = 8
const CIRCUITS: int = 2
const MOVED: int = 3

var b: Dictionary = {}
var _gap: Vector2i = Vector2i(-1, -1)


func _init() -> void:
	id = "conveyor"
	chapter = 2
	title = "Конвейер"
	brief = "Станция ожила. В журнале — цех к востоку от релея: бур, плавильня, сборщик. Линия стоит."
	teaches = "конвейер, бур и плавильня, склад, сборщик, манипулятор"
	hold_time = 0.5


func build() -> void:
	b = CampaignBase.build(CampaignBase.Tier.FACTORY)
	# Разрыв линии: средней ленты нет — её ставит игрок.
	var gap = b["belt1"]
	_gap = gap.cell
	World.machines.erase(_gap)
	World.belts.erase(_gap)
	gap.queue_free()
	b.erase("belt1")
	(b["parts"] as Chest).receive_item(IDs.I.COPPER_PLATE, CIRCUITS)
	(b["parts"] as Chest).receive_item(IDs.I.CRYSTAL, CIRCUITS * 2)


func kit() -> Array:
	return [[IDs.I.BELT, 2], [IDs.I.INSERTER, 1], [IDs.I.CHEST, 1], [IDs.I.COAL, 6], [IDs.I.LAMP, 2]]


func stages() -> Array:
	return [
		{"title": "Разрыв линии", "hint": "Конвейер в руку (1–0), ПКМ в разрыв ленты · ПКМ по ленте — повернуть",
			"say": ["Цех к востоку от релея. Бур стоит на железной жиле, лента везёт руду в плавильню, слитки падают в склад.",
					"Одной ленты не хватает — линия стоит. Поставьте конвейер в разрыв, стрелкой к плавильне."],
			"goals": [
				["Лента в разрыве", func() -> Vector2i: return flag(World.belts.has(_gap))],
				["Первый слиток на складе", func() -> Vector2i: return Vector2i(chest_has(b["store"], IDs.I.IRON_INGOT), 1)]]},
		{"title": "Склад", "hint": "Бур ест жилу снизу вверх · ТЭЦ цеха: E с углём — топка",
			"say": ["Пошло. Пока линия работает сама — посмотрите, как: P показывает радиусы питания.",
					"Нужно %d слитков. Плавильня из одной руды даёт слиток — вдвое выгоднее ручной ковки." % INGOTS],
			"goals": [["Слитков на складе", func() -> Vector2i: return Vector2i(chest_has(b["store"], IDs.I.IRON_INGOT), INGOTS)]]},
		{"title": "Сборщик", "hint": "Сундук «Запчасти» у края цеха · E с предметом в руке у сборщика — загрузить",
			"say": ["Сборщик стоит на солнечных панелях. В сундуке у края цеха — медные пластины и кристаллы.",
					"Загрузите их в сборщик: микросхема — пластина и два кристалла. Готовое ляжет в сундук рядом."],
			"goals": [["Микросхемы собраны", func() -> Vector2i:
				return Vector2i(chest_has(b["asm_out"], IDs.I.CIRCUIT) + heroes_have(IDs.I.CIRCUIT), CIRCUITS)]]},
		{"title": "Манипулятор", "hint": "Склад → манипулятор → сундук в ряд · ПКМ по манипулятору — повернуть",
			"say": ["Последнее. Манипулятор переносит предметы сзади вперёд — так станки кормят друг друга.",
					"Поставьте справа от склада манипулятор, за ним — сундук. Пусть перекладывает слитки."],
			"goals": [["Манипулятор перенёс", func() -> Vector2i: return Vector2i(_moved(), MOVED)]]},
	]


func outro() -> String:
	return "Цех работает без рук: бур, лента, плавильня, склад. Так строится всё остальное.\n" \
			+ "ПЁС: «Жила под цехом кончится. Настоящая руда — глубже. У западного края базы есть ствол шахты.»"


func _moved() -> int:
	var n: int = 0
	for c in World.machines:
		var m = World.machines[c]
		if m is Inserter and is_instance_valid(m):
			n = maxi(n, (m as Inserter).moved)
	return n
