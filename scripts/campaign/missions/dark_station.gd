extends Mission
## Глава 1 «Тёмная станция». Фабрики нет (#170): учит копать, крафтить горелку,
## читать терминал и ставить свет. Новые главы «Свет» — #177, здесь их нет.

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
	teaches = "копка, ручной крафт, горелка, терминал, свет против фантомов"


func kit() -> Array:
	return [[IDs.I.LAMP, 3], [IDs.I.COAL, 6], [IDs.I.STONE, 8], [IDs.I.SCRAP, 4]]


func stages() -> Array:
	return [
		{"title": "Хлам", "hint": "ЛКМ по глине и лишайнику рядом — выпадет хлам",
			"say": ["Вы живы. Это уже неплохо. Станция мертва — питания нет ни на одном терминале.",
					"Начнём с простого: наковыряйте хлама. Зажмите ЛКМ на клетке земли рядом."],
			"goals": [["Накопать хлама", func() -> Vector2i: return Vector2i(heroes_have(IDs.I.SCRAP), HUD.TUT_SCRAP),
				IDs.I.SCRAP, func() -> Vector2: return _dig_spot()]]},
		{"title": "Горелка", "hint": "I — инвентарь, вкладка «Крафт» → «Горелка»",
			"say": ["Из камня и хлама собирается горелка. Откройте крафт: I."],
			"goals": [["Собрать горелку", func() -> Vector2i:
				return Vector2i(heroes_have(IDs.I.BURNER) + machines_of("Burner"), 1), IDs.I.BURNER]]},
		{"title": "Свет базы", "hint": "ПКМ — поставить горелку у терминала · E с углём — топка",
			"say": ["Поставьте горелку у терминала и затопите её углём. Ток больше не нужен.",
					"Терминал читается и без горелки — она светит и греет луч."],
			"goals": [["Горелка горит", func() -> Vector2i: return flag(_burner_lit()),
				IDs.I.BURNER, func() -> Vector2: return _terminal_spot()]]},
		{"title": "Терминал", "hint": "Держите E у терминала",
			"say": ["Терминал отдаёт главу журнала и подарок (J — журнал). Питание ему не нужно."],
			"goals": [["Прочитать терминал", func() -> Vector2i: return Vector2i(Game.tasks_done, 1),
				-1, func() -> Vector2: return _terminal_spot()]]},
		{"title": "Свет", "hint": "Светокристалл в руку (1–0), ПКМ — поставить. Крафт: кристалл + уголь",
			"say": ["Солнце садится. Ночью из вентиляций выходят фантомы — эхо экипажа. Света они боятся.",
					"Поставьте у базы ещё два светокристалла — они у вас в наборе."],
			"enter": func() -> void: _lamps0 = _base_lamps(),
			"goals": [["Светокристаллы у базы", func() -> Vector2i: return Vector2i(_base_lamps() - _lamps0, LAMPS),
				IDs.I.LAMP, func() -> Vector2: return World.cell_to_world(World.beacon_cell)]]},
		{"title": "Первая ночь", "hint": "Держитесь в свете ламп. Q — импульс, V у вентиляции — спрятаться",
			"say": ["Ночь. Вентиляция у края базы уже гудит — пар из неё значит, что сейчас кто-то выйдет.",
					"Не уходите в темноту. Эхо в свету не нападает. Импульс Q оглушает того, кто рядом."],
			"enter": _begin_night,
			"goals": [["Дожить до рассвета", func() -> Vector2i: return flag(Game.day_number > _day0),
				IDs.I.LAMP, func() -> Vector2: return World.cell_to_world(World.beacon_cell)]]},
	]


func outro() -> String:
	return "Рассвет. Станция дышит: одна горелка, один терминал и лампы против целой планеты.\n" \
			+ "ПЁС: «Цех к востоку мёртв. Строить теперь будем светом.»"


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


## Куда копать хлам: первая клетка земли у поверхности справа от базы.
func _dig_spot() -> Vector2:
	var x: int = World.beacon_cell.x + 8
	var y: int = int(World.surface[x]) if x >= 0 and x < World.surface.size() else World.beacon_cell.y + 2
	return World.cell_to_world(Vector2i(x, y))


## Терминал базы (глава 0), иначе релей.
func _terminal_spot() -> Vector2:
	for c in World.terminal_chapters.keys():
		if int(World.terminal_chapters[c]) == 0:
			return World.cell_to_world(c)
	return World.cell_to_world(World.beacon_cell)


## Горит ли хоть одна горелка у базы.
func _burner_lit() -> bool:
	for m in World.machines.values():
		if m.kind == "Burner" and m.has_method("is_lit") and m.is_lit():
			return true
		if m.kind == "Burner" and float(m.get("burn_left")) > 0.0:
			return true
	return false


func _base_lamps() -> int:
	var n: int = 0
	var b: Vector2i = World.beacon_cell
	for y in range(b.y - 8, b.y + 4):
		for x in range(b.x - BASE_R, b.x + BASE_R + 1):
			if World.get_tile(x, y) == IDs.T.LIGHT_CRYSTAL:
				n += 1
	return n
