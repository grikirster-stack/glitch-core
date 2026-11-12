extends Mission
## Глава 3 «Зеркало» (ADR-005 § 9, #178, #216): луч поворачивается.
##
## Горелка лагеря уже горит и смотрит вниз. У поворота зеркала нет: прямой
## луч упирается в сталь. Игрок сам ставит зеркало из набора и крутит его.
## Верная грань («\») уводит луч вправо, в комнату. Любая другая — в тупик
## (вверх, в потолок, или по диагонали в стену): подвал остаётся тёмным,
## глава не закрывается. Один тап по уже стоящему верному зеркалу невозможен —
## его ещё нет.

const LOOT_GLASS: int = 4
const LOOT_COPPER: int = 2
## «\» (dir 1 и 3): вниз-идущий луч уходит вправо, в комнату.
## Остальные шесть положений — промах (см. Mirror._TABLE, вход снизу).
const AIM_DIR: int = 1

var _cache: Chest = null
var _opened: bool = false
## Сколько раз игрок повернул зеркало у поворота. Сценарий читает: глава
## не закрывается одним тапом по уже верному зеркалу.
var turns: int = 0
var _hooked: Mirror = null


func _init() -> void:
	id = "mirror"
	chapter = 3
	title = "Зеркало"
	brief = "Под лагерем тёмная комната за углом. Горелка светит вниз, но на повороте пусто."
	teaches = "зеркало ставят и поворачивают, чтобы луч дошёл"
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
	# Поворот пуст: зеркало ставит игрок. Запасное — на полке, не на луче.
	var spare: Mirror = CampaignBase.put("Mirror", LightLayout.at(LightLayout.SPARE),
			{"dir": 0}) as Mirror
	if spare != null:
		spare.permanent = false
	_cache = LightLayout.dig_cellar([[IDs.I.GLASS, LOOT_GLASS], [IDs.I.COPPER_INGOT, LOOT_COPPER]])


func stages() -> Array:
	return [
		{"title": "Поворот",
			"hint": "Поставь зеркало на поворот и поверни",
			"say": ["Луч бьёт вниз и упирается в сталь. За углом темно.",
					"Зеркало ставят на поворот. Не та грань — луч в стену."],
			"goals": [["Поставь зеркало на поворот", func() -> Vector2i: return flag(_placed()),
				IDs.I.MIRROR, func() -> Vector2: return LightLayout.world_at(LightLayout.CORNER)]]},
		{"title": "Луч",
			"hint": "Тап по зеркалу поворачивает грань",
			"say": ["Зеркало стоит. Крути, пока луч не уйдёт в комнату.",
					"Мимо — и подвал снова тёмный."],
			"goals": [["Доведи луч до подвала", func() -> Vector2i: return flag(_cellar_lit()),
				IDs.I.MIRROR, func() -> Vector2: return LightLayout.world_at(LightLayout.DOOR)]],
			"done": _open_cache},
	]


func on_tick(_delta: float) -> void:
	_hook_corner()


func fail_reason() -> String:
	# Промах не валит главу сразу: игрок крутит зеркало, пока луч не попадёт.
	# Достижимый провал — разобрать своё зеркало и не поставить снова: без
	# зеркала в наборе и на повороте луч до подвала не довести.
	if stage < 1 or result != Result.RUNNING:
		return ""
	if _placed():
		return ""
	if heroes_have(IDs.I.MIRROR) > 0:
		return ""
	return "Зеркало снято, поставить нечем."


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


func _placed() -> bool:
	return World.machines.get(LightLayout.at(LightLayout.CORNER)) is Mirror


func _hook_corner() -> void:
	var m: Mirror = World.machines.get(LightLayout.at(LightLayout.CORNER)) as Mirror
	if m == null:
		_hooked = null
		return
	if m == _hooked:
		return
	_hooked = m
	if not m.turned.is_connected(_on_turn):
		m.turned.connect(_on_turn)


func _on_turn() -> void:
	turns += 1


func _cellar_lit() -> bool:
	if World.beams == null:
		return false
	var m: Mirror = World.machines.get(LightLayout.at(LightLayout.CORNER)) as Mirror
	var d: int = m.dir & 7
	if d != AIM_DIR and d != 3:
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
