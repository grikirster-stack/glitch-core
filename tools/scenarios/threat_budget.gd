extends ScenarioBase
## Бюджет ночи директора угрозы (ADR-001, § 4.5): ночь 1 — не больше 3 фантомов
## одновременно, ночь 4 — не меньше 6.
##
## Ночь прогоняется быстрее реального времени: директор ведётся вручную
## (Threat.tick с шагом 0.25 с), фантомы при этом живут в настоящей сцене.

const STEP: float = 0.25
const MAX_STEPS: int = 500


func run() -> void:
	player.invuln = 1.0e9
	# Формулы § 4.5.
	ok("бюджет: B(1) = 5", is_equal_approx(Threat.night_budget(1.0), 5.0))
	ok("cap: ночь 1 — 3, ночь 4 — 6, ночь 9 — 10", Threat.cap_for(1, false) == 3
			and Threat.cap_for(4, false) == 6 and Threat.cap_for(9, false) == 10)
	ok("cap при релее — 10", Threat.cap_for(1, true) == Balance.RELAY_HOLD_CAP)
	ok("интервал: 6.5 с при T=1, не меньше 2.5 с", is_equal_approx(Threat.interval_for(1.0), 6.5)
			and is_equal_approx(Threat.interval_for(20.0), 2.5))
	var r1: Array = Threat.plan_roster(Threat.night_budget(1.0), 1, false)
	ok("ночь 1 — только эхо", not r1.is_empty() and r1.count("echo") == r1.size(), str(r1))
	var r4: Array = Threat.plan_roster(Threat.night_budget(4.0), 4, false)
	ok("ночь 4 — рой, тень и копатель, без двойника", r4.has("swarm") and r4.has("shade")
			and r4.has("burrower") and not r4.has("doppel"), str(r4))
	var r6: Array = Threat.plan_roster(Threat.night_budget(6.0), 6, false)
	ok("ночь 6 — ровно один двойник", r6.count("doppel") == 1, str(r6))
	var rr: Array = Threat.plan_roster(Threat.night_budget(5.0), 2, true)
	ok("релей открывает двойника", rr.count("doppel") == 1, str(rr))

	var peak1: int = await _run_night(1)
	ok("ночь 1: не больше 3 фантомов", peak1 <= 3 and Threat.spawned_total >= 2,
			"пик %d, вышло %d" % [peak1, Threat.spawned_total])
	var peak4: int = await _run_night(4)
	ok("ночь 4: не меньше 6 фантомов", peak4 >= 6,
			"пик %d, вышло %d" % [peak4, Threat.spawned_total])
	_clear()
	Game.time_of_day = Balance.START_TIME
	Threat.reset()
	finish()


## Прогнать ночь смены day. Возвращает пик фантомов одновременно.
func _run_night(day: int) -> int:
	_clear()
	await await_frame()
	Threat.reset()
	Game.day_number = day
	Game.time_of_day = 0.70
	var peak: int = 0
	for i in MAX_STEPS:
		player.invuln = 1.0e9
		Game.time_of_day = 0.70
		Threat.tick(STEP)
		await await_frame()
		peak = maxi(peak, _alive())
		if i > 4 and Threat.roster.is_empty() and Threat.pending.is_empty():
			break
	print("    ночь %d: T=%.2f бюджет %.1f, пик %d, вышло %d" %
			[day, Threat.threat_level(), Threat.budget, peak, Threat.spawned_total])
	return peak


func _alive() -> int:
	var n: int = 0
	for p in get_tree().get_nodes_in_group("phantom"):
		if is_instance_valid(p) and p.alive:
			n += 1
	return n


func _clear() -> void:
	for n in get_tree().get_nodes_in_group("phantom"):
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.queue_free()
