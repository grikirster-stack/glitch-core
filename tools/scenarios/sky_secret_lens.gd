extends ScenarioBase
## Линза в небесном тайнике (#172).
##
## Не лезем по лестнице: сундук уже стоит после генерации. На трёх сидах
## линза лежит в грузе, сверх случайных 3–6 предметов.


const SEEDS: Array[int] = [31337, 4242, 12345]


func run() -> void:
	for s in SEEDS:
		_regen(s)
		var sc: Dictionary = World.sky_cache
		ok("тайник есть на сиде %d" % s, not sc.is_empty() and sc.get("chest") != null)
		if sc.is_empty():
			continue
		var chest = sc["chest"]
		var n: int = _count(chest, IDs.I.LENS)
		var kinds: int = _kinds(chest)
		ok("линза в сундуке сида %d" % s, n >= 1, "линз %d, видов %d" % [n, kinds])
		# Случайный груз 3–6, линза — седьмой вид, если её не вытянул пул.
		ok("груз тайника не пуст на сиде %d" % s, kinds >= Balance.SKY_CACHE_MIN, "видов %d" % kinds)
	finish()


func _count(chest, id: int) -> int:
	var n: int = 0
	if chest == null:
		return 0
	for s in chest.slots:
		if not s.is_empty() and s.id == id:
			n += s.count
	return n


func _kinds(chest) -> int:
	var seen: Dictionary = {}
	if chest == null:
		return 0
	for s in chest.slots:
		if not s.is_empty():
			seen[s.id] = true
	return seen.size()


func _regen(s: int) -> void:
	if World.tilemap:
		World.tilemap.clear()
	World.generate(s)
	Game.tasks_total = World.terminals.size()
