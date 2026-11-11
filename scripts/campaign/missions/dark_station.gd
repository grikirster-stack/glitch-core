extends Mission
## Глава 1 «Тёмная станция»: станция без питания, как в начале свободной игры.
## Учит: копать, крафтить, ставить и топить ТЭЦ, читать терминал, ставить свет;
## в конце — короткая ночь: две волны эха из вентиляции базы, свет их держит.

## Сколько светокристаллов поставить у базы.
const LAMPS: int = 2
## Радиус «у базы» от релея, клеток.
const BASE_R: int = 18

var _lamps0: int = 0
var _day0: int = 1


func _init() -> void:
	id = "dark_station"
	chapter = 1
	title = "Тёмная станция"
	brief = "Капсула села у станции «Кербер-9». Станция обесточена, связь молчит, а до ночи четыре минуты."
	teaches = "копка, ручной крафт, ТЭЦ и питание, терминал, свет против фантомов"


func kit() -> Array:
	return [[IDs.I.LAMP, 3], [IDs.I.COAL, 6], [IDs.I.IRON_PLATE, 2], [IDs.I.COPPER_ORE, 4]]


func stages() -> Array:
	return [
		{"title": "Хлам", "hint": "ЛКМ по глине и лишайнику рядом — выпадет хлам",
			"say": ["Вы живы. Это уже неплохо. Станция мертва — питания нет ни на одном терминале.",
					"Начнём с простого: наковыряйте хлама. Зажмите ЛКМ на клетке земли рядом."],
			"goals": [["Накопать хлама", func() -> Vector2i: return Vector2i(heroes_have(IDs.I.SCRAP), HUD.TUT_SCRAP)]]},
		{"title": "ТЭЦ", "hint": "I — инвентарь, вкладка «Ручной крафт» → «Угольная ТЭЦ»",
			"say": ["Из хлама и двух пластин из набора собирается угольная ТЭЦ. Откройте крафт: I."],
			"goals": [["Собрать угольную ТЭЦ", func() -> Vector2i:
				return Vector2i(heroes_have(IDs.I.COAL_GEN) + machines_of("CoalGen"), 1)]]},
		{"title": "Питание", "hint": "ПКМ — поставить ТЭЦ у терминала · E с углём в руке — топка · P — радиус",
			"say": ["Поставьте ТЭЦ рядом с терминалом — зелёный экран у релея. Радиус питания — 8 клеток.",
					"Потом возьмите уголь в руку и нажмите E у ТЭЦ: без топлива она не греет."],
			"goals": [["ТЭЦ даёт ток", func() -> Vector2i: return flag(Game.power_output_total > 0.0)]]},
		{"title": "Терминал", "hint": "Держите E у терминала под питанием",
			"say": ["Есть ток! Терминал под питанием отдаёт главу журнала и подарок (J — журнал)."],
			"goals": [["Прочитать терминал", func() -> Vector2i: return Vector2i(Game.tasks_done, 1)]]},
		{"title": "Свет", "hint": "Светокристалл в руку (1–0), ПКМ — поставить. Крафт: кристалл + уголь",
			"say": ["Солнце садится. Ночью из вентиляций выходят фантомы — эхо экипажа. Света они боятся.",
					"Поставьте у базы ещё два светокристалла — они у вас в наборе."],
			"enter": func() -> void: _lamps0 = _base_lamps(),
			"goals": [["Светокристаллы у базы", func() -> Vector2i: return Vector2i(_base_lamps() - _lamps0, LAMPS)]]},
		{"title": "Первая ночь", "hint": "Держитесь в свете ламп. Q — импульс, V у вентиляции — спрятаться",
			"say": ["Ночь. Вентиляция у края базы уже гудит — пар из неё значит, что сейчас кто-то выйдет.",
					"Не уходите в темноту. Эхо в свету не нападает. Импульс Q оглушает того, кто рядом."],
			"enter": _begin_night,
			"goals": [["Дожить до рассвета", func() -> Vector2i: return flag(Game.day_number > _day0)]]},
	]


func outro() -> String:
	return "Рассвет. Станция дышит: одна ТЭЦ, один терминал и четыре лампы против целой планеты.\n" \
			+ "ПЁС: «В журнале экипажа сказано про цех к востоку от релея. Если его запустить — можно строить по-настоящему.»"


## Ночь сразу, без ожидания: сумерки — и волны эха из вентиляции у базы.
func _begin_night() -> void:
	_day0 = Game.day_number
	Game.time_of_day = Balance.NIGHT_START - 4.0 / Balance.DAY_LENGTH
	var vent: Vector2i = _base_vent()
	wave("echo", vent, 6.0)
	wave("echo", vent, 26.0)
	wave("echo", vent, 48.0)


func _base_vent() -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var bd: int = 1 << 30
	for v in World.vents:
		var d: int = absi(v.x - World.beacon_cell.x) + absi(v.y - World.beacon_cell.y)
		if d < bd:
			bd = d
			best = v
	return best


func _base_lamps() -> int:
	var n: int = 0
	var b: Vector2i = World.beacon_cell
	for y in range(b.y - 8, b.y + 4):
		for x in range(b.x - BASE_R, b.x + BASE_R + 1):
			if World.get_tile(x, y) == IDs.T.LIGHT_CRYSTAL:
				n += 1
	return n
