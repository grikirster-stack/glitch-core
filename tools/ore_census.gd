extends RefCounted
class_name OreCensus
## Перепись руды для баланса (ADR-005 § 1, § 6): сколько в мире каждой руды, какого
## размера жилы (связные области по 4 соседям) и сколько руды попадает в столбец бура.
##
## Запуск:
##   godot --headless --path . -- --ore-census --seed=31337
##   godot --headless --path . -- --ore-census --days=10 --seed=31337
## Флаг разбирает scripts/main.gd рядом с --map-dump: печатает после генерации мира и выходит.
## --days=N — ещё N рассветов без разведки (World.regrow_ores): руда в тумане
## возвращается к начальной переписи (ADR-005 § 6.4, #174).
##
## «Столбец бура» — 16 (бур) и 40 (глубинный) клеток под клеткой, на которую можно
## поставить бур: воздух, под ним твёрдое. Считаются все такие клетки мира (пещеры и
## поверхность) и отдельно только поверхность (surface[x] - 1), куда ставит новичок.

const ORES: Dictionary = {
	IDs.T.COAL_ORE: "уголь", IDs.T.SCRAP_ORE: "хлам", IDs.T.COPPER_ORE: "медь",
	IDs.T.IRON_ORE: "железо", IDs.T.CRYSTAL_ORE: "кристалл",
}


static func dump(args: PackedStringArray) -> void:
	var days: int = _arg_int(args, "--days=", 0)
	print("== ПЕРЕПИСЬ РУДЫ · сид %d · мир %d×%d ==" % [World.world_seed, World.W, World.H])
	_veins()
	if days > 0:
		_regrow(days)
	_columns(16, "бур (16 вниз)")
	_columns(40, "глубинный бур (40 вниз)")


static func _arg_int(args: PackedStringArray, key: String, fallback: int) -> int:
	for a in args:
		if a.begins_with(key):
			return int(a.substr(key.length()))
	return fallback


## N рассветов без разведки: туман не открывается, regrow_ores растит руду в камне.
static func _regrow(days: int) -> void:
	print("-- отрастание: %d рассветов без разведки (цель — начальная перепись ± 1 %%)" % days)
	var names: Dictionary = ORES
	var before: Dictionary = {}
	for tid in World.REGROW_ORES:
		before[tid] = World.ore_count(tid)
		print("  день 0  %-9s %5d" % [names.get(tid, str(tid)), before[tid]])
	var t0: int = Time.get_ticks_usec()
	for d in range(1, days + 1):
		World.regrow_ores(d)
	var us: int = Time.get_ticks_usec() - t0
	for tid in World.REGROW_ORES:
		var initial: int = int(World.ore_initial.get(str(tid), 0))
		var now: int = World.ore_count(tid)
		var drift: float = 0.0 if initial == 0 else 100.0 * float(now - initial) / float(initial)
		print("  день %-3d %-9s %5d  цель %5d  откл. %+.2f%%" % [days, names.get(tid, str(tid)),
				now, initial, drift])
	print("  рассветов %d за %.0f мс" % [days, float(us) / 1000.0])


## Жилы: связные области одного тайла по 4 соседям.
static func _veins() -> void:
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(World.W * World.H)
	print("-- жилы: тайл · всего клеток · жил · размер жилы мин / медиана / среднее / макс · глубина клеток от поверхности мин..макс")
	for tid in ORES:
		var sizes: Array[int] = []
		var total: int = 0
		var dmin: int = 1 << 30
		var dmax: int = -1
		for y in range(World.H):
			for x in range(World.W):
				var i: int = y * World.W + x
				if seen[i] != 0 or World.get_tile(x, y) != tid:
					continue
				var n: int = 0
				var stack: Array[Vector2i] = [Vector2i(x, y)]
				seen[i] = 1
				while not stack.is_empty():
					var c: Vector2i = stack.pop_back()
					n += 1
					dmin = mini(dmin, c.y - World.surface[c.x])
					dmax = maxi(dmax, c.y - World.surface[c.x])
					for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var q: Vector2i = c + d
						if q.x < 0 or q.y < 0 or q.x >= World.W or q.y >= World.H:
							continue
						var j: int = q.y * World.W + q.x
						if seen[j] == 0 and World.get_tile(q.x, q.y) == tid:
							seen[j] = 1
							stack.append(q)
				sizes.append(n)
				total += n
		sizes.sort()
		if sizes.is_empty():
			print("  %-9s нет" % ORES[tid])
			continue
		var mean: float = float(total) / float(sizes.size())
		print("  %-9s %5d  %4d  %2d / %2d / %4.1f / %3d  %d..%d" % [ORES[tid], total, sizes.size(),
				sizes[0], sizes[sizes.size() / 2], mean, sizes[sizes.size() - 1], dmin, dmax])


## Столбцы бура: сколько руды и прочего он выдаст за всю жизнь.
static func _columns(reach: int, title: String) -> void:
	var all: Dictionary = _column_stats(reach, false)
	var surf: Dictionary = _column_stats(reach, true)
	print("-- %s: столбцов · с рудой · руды в столбце среднее / медиана / макс · камня+глины среднее · работа всего, с (2 с/клетка)" % title)
	for d in [["все места", all], ["поверхность", surf]]:
		var s: Dictionary = d[1]
		print("  %-12s %5d  %4.0f%%  %4.2f / %d / %d  %5.1f  %5.1f" % [d[0], s["n"], 100.0 * s["with_ore"],
				s["ore_mean"], s["ore_median"], s["ore_max"], s["junk_mean"], s["work_mean"]])


static func _column_stats(reach: int, surface_only: bool) -> Dictionary:
	var ores: Array[int] = []
	var junk_sum: int = 0
	var work_sum: int = 0
	for x in range(World.W):
		var ys: Array[int] = []
		if surface_only:
			ys.append(World.surface[x] - 1)
		else:
			for y in range(1, World.H - 1):
				if World.get_tile(x, y) == IDs.T.AIR and DB.tile_solid(World.get_tile(x, y + 1)):
					ys.append(y)
		for y0 in ys:
			var ore: int = 0
			var junk: int = 0
			var work: int = 0
			for y in range(y0 + 1, y0 + reach + 1):
				if y >= World.H:
					break
				var t: int = World.get_tile(x, y)
				if t == IDs.T.AIR or DB.is_liquid(t):
					continue
				if DB.tile_hard(t) > 100.0:
					break
				work += 1
				if ORES.has(t) and t != IDs.T.SCRAP_ORE:
					ore += 1
				else:
					junk += 1
			ores.append(ore)
			junk_sum += junk
			work_sum += work
	ores.sort()
	var n: int = ores.size()
	var with_ore: int = 0
	var ore_sum: int = 0
	for o in ores:
		ore_sum += o
		if o > 0:
			with_ore += 1
	return {
		"n": n, "with_ore": float(with_ore) / float(maxi(1, n)),
		"ore_mean": float(ore_sum) / float(maxi(1, n)), "ore_median": ores[n / 2] if n > 0 else 0,
		"ore_max": ores[n - 1] if n > 0 else 0, "junk_mean": float(junk_sum) / float(maxi(1, n)),
		"work_mean": 2.0 * float(work_sum) / float(maxi(1, n)),
	}
