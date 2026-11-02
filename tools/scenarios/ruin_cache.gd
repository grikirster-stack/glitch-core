extends ScenarioBase
## Тайники руин (ADR-001 § 4.9, #35): в каждой руине сундук хозяина с 3–6
## предметами по его роли и табличка с именем места из Lore.
##
## Герой подходит к тайнику, держит E — открывается сундук; табличка при подходе
## даёт подсказку в HUD. Потом мир пересоздаётся: тот же сид — те же тайники и
## имена, другой сид — другие. В конце мир возвращается к сиду сцены.

func run() -> void:
	var caches: Array = World.ruin_caches
	ok("у каждой руины есть тайник", caches.size() == Lore.RUIN_COUNT,
			"тайников %d из %d" % [caches.size(), Lore.RUIN_COUNT])
	var bad: Array = []
	for c in caches:
		var chest = c["chest"]
		var n: int = _items(chest).size()
		if chest == null or not is_instance_valid(chest) or World.machines.get(c["cell"]) != chest \
				or n < World.RUIN_CACHE_MIN or n > World.RUIN_CACHE_MAX:
			bad.append("%d:%d" % [int(c["index"]), n])
	ok("в каждом тайнике сундук с 3–6 предметами", bad.is_empty(), str(bad))
	if caches.is_empty():
		finish()
		return

	# Подойти к тайнику и открыть его, как человек: держать E.
	var cache: Dictionary = caches[0]
	var spot: Vector2 = World.cell_to_world(cache["cell"])
	# Терминал руины без питания перехватывает E в радиусе 42 px (player.gd::_do_interact),
	# поэтому встаём с той стороны сундука, где терминала рядом нет (сид 12345: терминал
	# в двух клетках от тайника).
	var offsets: Array = []
	for o in [Vector2(0, -4), Vector2(16, -4), Vector2(-16, -4), Vector2(24, -4), Vector2(-24, -4),
			Vector2(0, -20), Vector2(16, -20), Vector2(-16, -20)]:
		if not _near_terminal(spot + o):
			offsets.append(o)
	var placed: bool = place_near(spot, offsets)
	ok("герой встал у тайника", placed, str(cache["cell"]))
	hold(KEY_E)
	var opened: bool = await wait_until(func() -> bool:
		return UI.panel.visible and UI.panel.chest == cache["chest"], 3.0)
	release(KEY_E)
	ok("тайник открывается по E", opened, "«%s»" % cache["name"])
	var sign = cache["sign"]
	var told: bool = await wait_until(func() -> bool: return bool(sign.announced), 2.0)
	ok("табличка подсказала имя места при подходе", told, "«%s»" % sign.title)
	if UI.panel.visible:
		UI.panel.close()

	# Детерминизм: тот же сид — те же тайники, другой сид — другие.
	var seed0: int = World.world_seed
	var snap0: Array = _snapshot()
	_regen(seed0)
	ok("тот же сид — те же тайники и имена", _snapshot() == snap0)
	_regen(seed0 + 7)
	var snap1: Array = _snapshot()
	ok("другой сид — другие имена мест", _col(snap1, 0) != _col(snap0, 0),
			"%s / %s" % [str(_col(snap0, 0)), str(_col(snap1, 0))])
	ok("другой сид — другое содержимое тайников", _col(snap1, 3) != _col(snap0, 3))
	_regen(seed0)
	player.global_position = World.spawn_point
	player.vel = Vector2.ZERO
	finish()


## Точка в зоне терминала (там E достаётся терминалу, а не сундуку).
func _near_terminal(p: Vector2) -> bool:
	for t in World.terminals:
		if World.cell_to_world(t).distance_to(p) < 44.0:
			return true
	return false


## Предметы сундука: [[id, число], ...] по непустым слотам.
func _items(chest) -> Array:
	var out: Array = []
	if chest == null or not is_instance_valid(chest):
		return out
	for s in chest.slots:
		if not s.is_empty():
			out.append([s.id, s.count])
	return out


## Слепок тайников мира: имя, роль, клетка, содержимое.
func _snapshot() -> Array:
	var out: Array = []
	for c in World.ruin_caches:
		out.append([c["name"], c["role"], c["cell"], _items(c["chest"])])
	return out


## Один столбец слепка: 0 — имена, 3 — содержимое.
func _col(snap: Array, k: int) -> Array:
	var out: Array = []
	for e in snap:
		out.append(e[k])
	return out


func _regen(s: int) -> void:
	if World.tilemap:
		World.tilemap.clear()
	World.generate(s)
	Game.tasks_total = World.terminals.size()
