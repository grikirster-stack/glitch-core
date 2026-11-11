extends ScenarioBase
## Двойник на удержании сигнала (ADR-001 § 4.5, § 4.7, #32): за первые 30 с
## этапа 4 появляется двойник — даже на первой смене и днём (обычно он
## открывается с ночи 6). Директор угрозы ведётся вручную (Threat.tick, шаг
## STEP): сцена живая, время — быстрее реального.
##
## Затем замер: удержание сигнала при cap 10 (RELAY_HOLD_CAP живых единиц угрозы)
## HOLD_S реальных секунд — p95 и максимум времени кадра. Печатается строкой
## «замер:», провалом не считается.

const STEP: float = 0.25
const DOPPEL_WINDOW: float = 30.0
const HOLD_S: float = 8.0
## Чем доливаем до cap на замере (по кругу).
const FILL_KINDS: Array = ["echo", "shade", "burrower", "swarm", "echo"]


func run() -> void:
	player.invuln = 1.0e9
	Game.time_of_day = Balance.START_TIME   # день: ночь двойника не откроет
	Game.day_number = 1
	Threat.reset()
	var cell: Vector2i = World.beacon_cell + Vector2i(2, 0)
	World.set_tile(cell.x, cell.y, IDs.T.AIR)
	MachineBase.place_machine("RainbowCore", cell)
	for c in [Beams.R, Beams.G, Beams.B, Beams.Y, Beams.C, Beams.M, Beams.W]:
		Game.core_feed(c)
	ok("ядро запущено", Game.try_finish())
	ok("этап 4 — удержать сигнал", Game.objective_stage == 4, Game.objective_text())
	ok("cap на удержании — %d" % Balance.RELAY_HOLD_CAP,
			Threat.cap_for(Game.day_number, true) == Balance.RELAY_HOLD_CAP)

	var sim: float = 0.0
	var doppel_at: float = -1.0
	var peak_doppels: int = 0
	while sim < DOPPEL_WINDOW:
		player.invuln = 1.0e9
		Threat.tick(STEP)
		sim += STEP
		await await_frame()
		var n: int = _count("doppel")
		peak_doppels = maxi(peak_doppels, n)
		if n > 0 and doppel_at < 0.0:
			doppel_at = sim
			break
	print("    директор: T=%.2f бюджет %.1f, состав %s, вышло %d" %
			[Threat.threat_level(), Threat.budget, str(Threat.roster), Threat.spawned_total])
	ok("двойник вышел за первые %d с удержания" % int(DOPPEL_WINDOW), doppel_at >= 0.0,
			"%.2f с" % doppel_at)
	ok("двойник один", peak_doppels <= 1, str(peak_doppels))
	var d: Node = _first("doppel")
	ok("над двойником — имя «того самого»", d != null and String(d.get("display_name")) != "",
			String(d.get("display_name")) if d != null else "")

	await _measure_hold()
	finish()


## Замер: HOLD_S с удержания сигнала при cap 10, директор в реальном времени.
func _measure_hold() -> void:
	var cap: int = Balance.RELAY_HOLD_CAP
	var fill_i: int = 0
	var frames: Array = []
	var peak: int = 0
	var prev: int = Time.get_ticks_usec()
	var end_ms: int = Time.get_ticks_msec() + int(HOLD_S * 1000.0)
	while Time.get_ticks_msec() < end_ms:
		player.invuln = 1.0e9
		var guard: int = 0
		while Threat.units_alive() + Threat.pending.size() < cap and guard < cap:
			Threat.spawn_in_cave(String(FILL_KINDS[fill_i % FILL_KINDS.size()]))
			fill_i += 1
			guard += 1
		await await_frame()
		var now: int = Time.get_ticks_usec()
		frames.append(float(now - prev) / 1000.0)
		prev = now
		Threat.tick(get_process_delta_time())
		peak = maxi(peak, Threat.units_alive())
	frames.sort()
	var n: int = frames.size()
	var p95: float = float(frames[mini(n - 1, int(floor(float(n) * 0.95)))]) if n > 0 else 0.0
	var mx: float = float(frames[n - 1]) if n > 0 else 0.0
	print("    замер: удержание сигнала, cap %d (пик %d единиц, фантомов %d), %d кадров: p95 %.2f мс, макс %.2f мс"
			% [cap, peak, get_tree().get_nodes_in_group("phantom").size(), n, p95, mx])
	ok("на удержании держится cap %d" % cap, peak >= cap - 1 and peak <= cap, "пик %d" % peak)


func _count(kind: String) -> int:
	var n: int = 0
	for p in get_tree().get_nodes_in_group("phantom"):
		if is_instance_valid(p) and bool(p.get("alive")) and String(p.get("kind")) == kind:
			n += 1
	return n


func _first(kind: String) -> Node:
	for p in get_tree().get_nodes_in_group("phantom"):
		if is_instance_valid(p) and bool(p.get("alive")) and String(p.get("kind")) == kind:
			return p
	return null
