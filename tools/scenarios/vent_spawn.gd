extends ScenarioBase
## Спавн из вентиляций (ADR-001, § 4.5): фантом выходит из одной из трёх
## ближайших к игроку незапечатанных вентиляций, с телеграфом
## (сигнал vent_warning + гул) за VENT_TELEGRAPH секунд до появления.
##
## Вентиляций в мире мало (генератор мира ставит их редко), поэтому сценарий
## добавляет свои на поверхности на разных расстояниях от игрока.

const REQUESTS: int = 12
const EXTRA_DX: Array = [14, 22, -24, 32, -36, 48, 60]

var _warned: Array = []


func run() -> void:
	player.invuln = 1.0e9
	Game.time_of_day = Balance.START_TIME   # днём директор сам не спавнит
	Threat.reset()
	var pc: Vector2i = World.world_to_cell(player.global_position)
	for dx in EXTRA_DX:
		var x: int = clampi(pc.x + int(dx), 2, World.W - 3)
		var c: Vector2i = Vector2i(x, int(World.surface[x]) - 1)
		if World.get_tile_v(c) == IDs.T.AIR and not World.vents.has(c):
			World.vents.append(c)
	var exp0: Array = _expected()
	ok("есть три кандидата в вентиляции", exp0.size() == Balance.VENT_SPAWN_COUNT, str(exp0))
	if exp0.size() < 2:
		finish()
		return
	# Ближайшую запечатываем решёткой — из неё спавна быть не должно.
	var sealed: Vector2i = exp0[0]
	World.set_tile(sealed.x, sealed.y, IDs.T.VENT_GRATE)
	var expected: Array = _expected()
	ok("запечатанная вентиляция выбыла", not expected.has(sealed), str(expected))

	Threat.vent_warning.connect(_on_warning)
	var loops0: int = Sfx.loop_count()
	var before: int = _alive()
	for i in REQUESTS:
		Threat.request_spawn("echo")
	ok("телеграф: сигнал vent_warning на каждый спавн", _warned.size() == REQUESTS,
			"%d из %d" % [_warned.size(), REQUESTS])
	var all_in: bool = true
	var distinct: Dictionary = {}
	for c in _warned:
		distinct[c] = true
		if not expected.has(c):
			all_in = false
	ok("все спавны — из трёх ближайших вентиляций", all_in, str(distinct.keys()))
	ok("вентиляции выбираются взвешенно, а не одна и та же", distinct.size() >= 2,
			"разных %d" % distinct.size())
	ok("из запечатанной — ни одного", not _warned.has(sealed))
	ok("вентиляции гудят на телеграфе", Sfx.loop_count() >= loops0 + REQUESTS,
			"эмиттеров %d → %d" % [loops0, Sfx.loop_count()])

	# До конца телеграфа фантомов нет, после — появляются у вентиляций.
	Threat.tick(Balance.VENT_TELEGRAPH * 0.5)
	await await_frame()
	ok("до конца телеграфа фантомов нет", _alive() == before, "живых %d" % _alive())
	Threat.tick(Balance.VENT_TELEGRAPH * 0.5 + 0.05)
	await await_frame()
	var spawned: Array = []
	for p in get_tree().get_nodes_in_group("phantom"):
		if is_instance_valid(p) and p.alive:
			spawned.append(p)
	ok("после телеграфа фантомы вышли", spawned.size() - before == REQUESTS,
			"вышло %d" % (spawned.size() - before))
	var at_vents: bool = true
	for p in spawned:
		var near: bool = false
		for v in expected:
			if p.global_position.distance_to(World.cell_to_world(v)) < 24.0:
				near = true
		if not near:
			at_vents = false
	ok("фантомы стоят у вентиляций", at_vents)
	ok("гул телеграфа стих", Sfx.loop_count() == loops0, "эмиттеров %d" % Sfx.loop_count())
	Threat.vent_warning.disconnect(_on_warning)
	finish()


func _on_warning(cell: Vector2i) -> void:
	_warned.append(cell)


## Три ближайшие незапечатанные вентиляции в допустимом кольце — считаем
## сами, независимо от директора.
func _expected() -> Array:
	var cand: Array = []
	for v in World.vents:
		if World.get_tile_v(v) == IDs.T.VENT_GRATE:
			continue
		var d: float = World.cell_to_world(v).distance_to(player.global_position)
		if d < Balance.VENT_SPAWN_MIN_PX or d > Balance.VENT_SPAWN_MAX_PX:
			continue
		cand.append([d, v])
	cand.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var out: Array = []
	for i in mini(Balance.VENT_SPAWN_COUNT, cand.size()):
		out.append(cand[i][1])
	return out


func _alive() -> int:
	var n: int = 0
	for p in get_tree().get_nodes_in_group("phantom"):
		if is_instance_valid(p) and p.alive:
			n += 1
	return n
