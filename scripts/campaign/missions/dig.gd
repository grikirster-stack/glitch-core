extends Mission
## Глава 1 «Копай» (ADR-005 § 9): кирка копает только через пустоту.
## Жила угля видна из пещеры у базы. Клетка за стеной — красный крест (B1).
## Сумерки: одно безвредное эхо подходит к светокристаллу и отступает.

## Сколько угля накопать сверх того, что уже лежит в сундуке лагеря.
const COAL: int = 5
## Светокристаллов у входа сверх тех, что уже горят в лагере. В наборе их три.
const LAMPS: int = 1


func _init() -> void:
	id = "dig"
	chapter = 1
	title = "Копай"
	brief = "Капсула села у лагеря. Рядом пещера, в стене — уголь. Кирка достаёт только через пустоту."
	teaches = "копка по лучу: сквозь стену клетка не ломается"
	director = false
	start_time = 0.30


func build() -> void:
	CampaignBase.build(CampaignBase.Tier.STATION)
	_coal0 = heroes_have(IDs.I.COAL)


func kit() -> Array:
	# Кирки в игре нет: копают рукой. Светокристаллы — на второй этап.
	return [[IDs.I.LAMP, 3]]


func stages() -> Array:
	return [
		{"title": "Уголь",
			"hint": "Копать можно только то, до чего достаёт луч от тебя",
			"say": ["Кирка бьёт по лучу. Сквозь стену она не достаёт."],
			"goals": [["Накопай 5 угля", func() -> Vector2i:
				return Vector2i(heroes_have(IDs.I.COAL) - _coal0, COAL),
				IDs.I.COAL, func() -> Vector2: return World.cell_to_world(CampaignBase.coal_spot())]]},
		{"title": "Свет",
			"hint": "Свет у входа их останавливает",
			"say": ["Темнеет. Поставь свет у входа — эхо к нему не подойдёт."],
			"enter": _begin_dusk,
			"goals": [["Поставь свет у входа", func() -> Vector2i:
				return Vector2i(_lamps_at_door() - _lamps0, LAMPS),
				IDs.I.LAMP, func() -> Vector2: return World.cell_to_world(CampaignBase.camp_door())]]},
	]


func outro() -> String:
	return "Свет их пугает. Завтра сделаем свой."


## Уголь, уже лежавший у героев на старте (сундук лагеря). Его не считаем накопанным.
var _coal0: int = 0
## Лампы лагеря, уже горевшие у входа, когда этап начался.
var _lamps0: int = 0


## Сумерки и одно безвредное эхо из вентиляции у входа.
func _begin_dusk() -> void:
	_lamps0 = _lamps_at_door()
	# Ночь короче 60 с (DAY_LENGTH × (1 − NIGHT_START + NIGHT_END) ≈ 91 с — длинно).
	# До главы 4 эхо не бьёт. Ночь, а не сумерки: днём эхо само уходит в глубину.
	Game.time_of_day = Balance.NIGHT_START
	hold_time = Balance.NIGHT_START + 50.0 / Balance.DAY_LENGTH
	_spawn_echo(0.6)


## Светокристаллы у входа: лампа на клетке входа или рядом, в трёх клетках.
func _lamps_at_door() -> int:
	var door: Vector2i = CampaignBase.camp_door()
	var n: int = 0
	for y in range(door.y - 1, door.y + 3):
		for x in range(door.x - 2, door.x + 3):
			if World.get_tile(x, y) == IDs.T.LIGHT_CRYSTAL:
				n += 1
	return n
