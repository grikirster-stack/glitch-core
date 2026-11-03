extends "res://tools/mp/scenarios/mp_players_base.gd"
## Общее сценариев «Фантомы и угроза по сети» (MP-F, #92): mp_phantoms, mp_threat_scale,
## mp_perf. Фантомы ставит хост штатным спавном (Threat.spawn_phantom), директор угрозы
## в сценариях молчит (scenario_mode) — ночь, если нужна, сценарий ведёт сам.


## Узел фантомов по сети (под NetPlayers).
func nph() -> NetPhantoms:
	var n: NetPlayers = np()
	return n.phantoms if n != null else null


## Живые фантомы сцены.
func alive_phantoms() -> Array:
	var out: Array = []
	for p in get_tree().get_nodes_in_group("phantom"):
		if is_instance_valid(p) and (p as Phantom).alive:
			out.append(p)
	return out


## Убрать всех фантомов сразу (из дерева — лимит MAX_PHANTOMS считает группу).
func clear_phantoms() -> void:
	for p in get_tree().get_nodes_in_group("phantom"):
		if is_instance_valid(p):
			p.get_parent().remove_child(p)
			p.queue_free()


## Фантом типа kind на поверхности рядом со столбцом героя (сдвиг dx клеток).
func spawn_near(hero: Node2D, dx: int, kind: String = "echo") -> Array:
	var cx: int = World.world_to_cell(hero.global_position).x + dx
	var pos: Vector2 = surface_stand(cx)
	if kind == "swarm":
		pos.y -= 20.0
	return Threat.spawn_phantom(kind, pos)


## 16 фантомов вокруг героев по кругу: стая роя, двойник (если doppel_at), остальное — эхо.
## heroes — у кого ставить; per — сколько у каждого (последний добирает до лимита).
func spawn_sixteen(heroes: Array, doppel_at: Node2D = null) -> int:
	clear_phantoms()
	await wait(0.05)
	var n: int = 0
	var k: int = 0
	var made: Array = spawn_near(heroes[0], 6, "swarm")
	n += made.size()
	if doppel_at != null:
		n += spawn_near(doppel_at, 4, "doppel").size()
	while n < Balance.MAX_PHANTOMS and k < 64:
		var h: Node2D = heroes[k % heroes.size()]
		var dx: int = (5 + (k / heroes.size()) * 3) * (1 if k % 2 == 0 else -1)
		n += spawn_near(h, dx, "echo").size()
		k += 1
	return alive_phantoms().size()


## Ближайший доступный (Player.net_targetable) герой к точке.
static func nearest_target(pos: Vector2) -> Player:
	var best: Player = null
	var best_d: float = INF
	for h in Game.players:
		var p: Player = h as Player
		if p == null or not p.net_targetable():
			continue
		var d: float = pos.distance_squared_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


## Ни один герой не погибнет за сценарий: урон — мимо (проверяется отдельно в MP-D).
static func invulnerable_all() -> void:
	for h in Game.players:
		(h as Player).invuln = 9999.0


## Средний и p95 интервал кадра, мс, по меткам времени кадров (мкс).
static func frame_stats(us: PackedInt64Array) -> Dictionary:
	var d: PackedFloat32Array = PackedFloat32Array()
	for i in range(1, us.size()):
		d.append(float(us[i] - us[i - 1]) / 1000.0)
	var sum: float = 0.0
	for x in d:
		sum += x
	return {"n": d.size(), "avg": sum / maxf(1.0, float(d.size())), "p95": p95(d), "max": vmax(d)}
