extends ScenarioBase
## Бюджет ночи директора угрозы (ADR-005 § 6.1–6.2): тихие ночи 1–2 — бюджет
## не больше 2 и не больше 1 живого; пустая база со смены 3 — T = 3, бюджет 7.
##
## Ночь прогоняется быстрее реального времени: директор ведётся вручную
## (Threat.tick с шагом 0.25 с), фантомы при этом живут в настоящей сцене.
## Открытие видов зависит от базы, не от номера смены: здесь базы нет, поэтому
## состав пустой ночи — только эхо, даже на смене 6.

const STEP: float = 0.25
const MAX_STEPS: int = 500


func run() -> void:
	player.invuln = 1.0e9
	# Формулы § 6.2. Пустая база: T ночи = min(смена, 3).
	ok("бюджет: B(3) = 7, тихая ночь не больше 2", is_equal_approx(Threat.night_budget(3.0, 3), 7.0)
			and is_equal_approx(Threat.night_budget(3.0, 1), 2.0))
	ok("смена в формуле не выше 3: B(9) = B(3)", is_equal_approx(Threat.night_budget(3.0, 9), 7.0))
	ok("cap: тихая ночь — 1, пустая смена 4 — 4, смена 9 — 4", Threat.cap_for(1, false) == 1
			and Threat.cap_for(4, false, 3.0) == 4 and Threat.cap_for(9, false, 3.0) == 4)
	ok("cap при релее — 10", Threat.cap_for(1, true) == Balance.RELAY_HOLD_CAP)
	ok("интервал: 5.5 с при T=3, не меньше 2.5 с", is_equal_approx(Threat.interval_for(3.0), 5.5)
			and is_equal_approx(Threat.interval_for(20.0), 2.5))
	var r1: Array = Threat.plan_roster(Threat.night_budget(1.0, 1), 1, false)
	ok("ночь 1 — только эхо, не больше двух", r1.size() <= 2 and not r1.is_empty()
			and r1.count("echo") == r1.size(), str(r1))
	var r4: Array = Threat.plan_roster(Threat.night_budget(3.0, 4), 4, false)
	ok("пустая смена 4 — без роя (нужны две горелки)", not r4.has("swarm")
			and r4.count("echo") >= 1, str(r4))
	var r6: Array = Threat.plan_roster(Threat.night_budget(3.0, 6), 6, false)
	ok("свободная смена 6 — ровно один двойник", r6.count("doppel") == 1, str(r6))
	var rr: Array = Threat.plan_roster(Threat.night_budget(5.0, 2, true), 2, true)
	ok("релей открывает двойника", rr.count("doppel") == 1, str(rr))

	var peak1: int = await _run_night(1)
	ok("ночь 1: не больше 1 фантома одновременно", peak1 <= Balance.QUIET_ALIVE_CAP
			and Threat.spawned_total >= 1, "пик %d, вышло %d" % [peak1, Threat.spawned_total])
	var peak4: int = await _run_night(4)
	ok("пустая смена 4: бюджет 7, одновременно не больше 4", peak4 <= 4 and peak4 >= 1,
			"пик %d, вышло %d, бюджет %.1f" % [peak4, Threat.spawned_total, Threat.budget])
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
