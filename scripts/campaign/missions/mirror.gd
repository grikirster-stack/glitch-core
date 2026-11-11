extends Mission
## Глава 3 «Зеркало» (ADR-005 § 9, #178): луч поворачивается.
##
## Горелка лагеря уже горит. Подвал — за углом, прямой луч туда не доходит.
## В наборе два зеркала. Одно стоит у поворота не той гранью: тап поворачивает.
## Луч в комнате открывает сундук-находку.

const LOOT_GLASS: int = 4
const LOOT_COPPER: int = 2

var _cache: Chest = null
var _opened: bool = false


func _init() -> void:
	id = "mirror"
	chapter = 3
	title = "Зеркало"
	brief = "Под лагерем тёмная комната за углом. Горелка светит вниз, но луч упирается в поворот."
	teaches = "зеркало поворачивает луч"
	# День стоит: ночи в этой главе нет.
	start_time = 0.30
	hold_time = 0.30


func kit() -> Array:
	return [[IDs.I.MIRROR, 2]]


func build() -> void:
	_clear_well()
	var burner: Burner = CampaignBase.put("Burner", LightLayout.at(LightLayout.BURNER),
			{"dir": 1}) as Burner
	if burner != null:
		burner.dir = 1
		burner.add_fuel(IDs.I.COAL, Burner.FUEL_MAX)
	# Зеркало у поворота смотрит не туда: «/» уводит луч вверх, в потолок колодца.
	var mirror: Mirror = CampaignBase.put("Mirror", LightLayout.at(LightLayout.CORNER),
			{"dir": 0}) as Mirror
	if mirror != null:
		mirror.dir = 0
	# Второе — на полке у входа, чтобы набор не кончился, если первое разобрали.
	var spare: Mirror = CampaignBase.put("Mirror", LightLayout.at(LightLayout.SPARE),
			{"dir": 0}) as Mirror
	if spare != null:
		spare.permanent = false
	_cache = LightLayout.dig_cellar([[IDs.I.GLASS, LOOT_GLASS], [IDs.I.COPPER_INGOT, LOOT_COPPER]])


func stages() -> Array:
	return [
		{"title": "Поворот",
			"hint": "Тап по зеркалу поворачивает его",
			"say": ["Луч бьёт вниз и упирается. За углом темно.",
					"Зеркало у поворота смотрит не туда."],
			"goals": [["Доведи луч до подвала", func() -> Vector2i: return flag(_cellar_lit()),
				IDs.I.MIRROR, func() -> Vector2: return LightLayout.world_at(LightLayout.DOOR)]],
			"done": _open_cache},
	]


func outro() -> String:
	return "Подвал зажёгся. В сундуке — стекло и медь.\n" \
			+ "ПЁС: «Медь горит другим цветом. Завтра смешаем.»"


## Колодец над полом: панели и лампы лагеря не должны резать луч вниз.
func _clear_well() -> void:
	var b: Vector2i = World.beacon_cell
	for y in range(b.y - 3, b.y + 1):
		var c: Vector2i = Vector2i(b.x + LightLayout.BURNER.x, y)
		if World.get_tile_v(c) != IDs.T.AIR and not World.machines.has(c):
			World.set_tile(c.x, c.y, IDs.T.AIR)


func _cellar_lit() -> bool:
	if World.beams == null:
		return false
	return World.beams.color_at(LightLayout.at(LightLayout.CELLAR)) != 0


## Сундук открывается, когда луч дошёл: содержимое — на пол, уведомление.
func _open_cache() -> void:
	if _opened or _cache == null or not is_instance_valid(_cache):
		return
	_opened = true
	for s in _cache.slots:
		if s.is_empty():
			continue
		_cache.spawn_item(s.id, s.count, _cache.global_position + Vector2(0.0, -6.0))
		s.take(s.count)
	Game.notify("Находка: стекло и медь", Color(0.85, 0.95, 1.0), IDs.I.GLASS)
