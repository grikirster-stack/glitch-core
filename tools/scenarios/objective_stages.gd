extends "res://tools/scenarios/terminal_powered.gd"
## Этапы цели (ADR-001 § 4.7, #32): 1 → 2 → 3 → 4 переключаются по условиям.
##   1 → 2: оба терминала базы прочитаны под питанием (ТЭЦ рядом, удерживать E):
##          +10 данных, главы 1–2 журнала. Один терминал — ещё этап 1.
##   2 → 3: открыт узел T5 (T1–T4 — ещё этап 2), антенна релея в рецептах.
##   3 → 4: E у ядра с полным набором — Game.try_finish().
## Сигнал objective_changed уходит по разу на этап, по порядку.

var _seen: Array = []


func run() -> void:
	player.invuln = 1.0e9
	Game.objective_changed.connect(_on_stage)
	# Этап 1 ставит первый такт Game после сброса забега (до него — 0, «не начато»).
	var started: bool = await wait_until(func() -> bool: return Game.objective_stage == 1, 2.0)
	ok("старт забега — этап 1", started, str(Game.objective_stage))
	ok("строка цели «ЦЕЛЬ 1/4»", Game.objective_text().begins_with("ЦЕЛЬ 1/4"), Game.objective_text())

	# --- 1 → 2: терминалы базы под питанием.
	var data0: int = Game.research
	for ch in Lore.BASE_TERMINALS:
		var t: Vector2i = terminal_of_chapter(ch)
		ok("терминал базы (глава %d)" % (ch + 1), t.x >= 0, str(t))
		if t.x < 0:
			_end()
			return
		if not await _read_quick(t):
			_end()
			return
		await wait(0.4)
		if ch < Lore.BASE_TERMINALS - 1:
			ok("один терминал — ещё этап 1", Game.objective_stage == 1, str(Game.objective_stage))
	ok("оба терминала базы → этап 2", Game.objective_stage == 2, Game.objective_text())
	ok("+10 данных за станцию", Game.research - data0 == 2 * Balance.TERMINAL_DATA,
			"%d → %d" % [data0, Game.research])
	ok("главы 1–2 журнала прочитаны", Tech.is_chapter_read(0) and Tech.is_chapter_read(1),
			str(Tech.read_chapters))

	# --- 2 → 3: дерево до T5.
	var total: int = 0
	for n in Balance.TECH_COST.keys():
		total += int(Balance.TECH_COST[n])
	Game.research = maxi(Game.research, total)
	for n in ["T1", "T2", "T3", "T4"]:
		Tech.unlock(n)
	await wait(0.4)
	ok("T1–T4 открыты — ещё этап 2", Game.objective_stage == 2, str(Tech.unlocked))
	var antenna_locked: bool = not Tech.is_unlocked(_antenna_tech())
	ok("до T5 антенна заперта", antenna_locked, _antenna_tech())
	ok("T5 открыт", Tech.unlock("T5"))
	await wait(0.4)
	ok("открыт T5 → этап 3", Game.objective_stage == 3, Game.objective_text())
	ok("антенна релея в рецептах", Tech.is_unlocked(_antenna_tech()))

	# --- 3 → 4: запуск релея.
	ok("без деталей релей не стартует", not Game.try_finish() and Game.objective_stage == 3)
	for id in Game.relay_req.keys():
		player.inv.add(int(id), int(Game.relay_req[id]))
	ok("с полным набором релей стартует", Game.try_finish())
	ok("этап 4 — сразу при запуске", Game.objective_stage == 4, Game.objective_text())
	ok("строка цели с отсчётом", Game.objective_text().begins_with("ЦЕЛЬ 4/4")
			and Game.objective_text().ends_with(" с"), Game.objective_text())
	ok("этапы по порядку 1 → 2 → 3 → 4, по разу", _seen == [1, 2, 3, 4], str(_seen))
	_end()


func _end() -> void:
	if Game.objective_changed.is_connected(_on_stage):
		Game.objective_changed.disconnect(_on_stage)
	finish()


func _on_stage(s: int) -> void:
	_seen.append(s)


## Поставить ТЭЦ у терминала, встать рядом, удерживать E до засчитанного задания.
func _read_quick(t: Vector2i) -> bool:
	var spot: Vector2 = World.cell_to_world(t)
	if not Game.is_powered(spot):
		var gen: CoalGen = _place_gen_near(t)
		ok("ТЭЦ у терминала", gen != null, str(t))
		if gen == null:
			return false
		gen.add_fuel(4)
	var powered: bool = await wait_until(func() -> bool: return Game.is_powered(spot), 2.0)
	ok("терминал под питанием", powered)
	if not await stand_at_terminal(t):
		return false
	var done0: int = Game.tasks_done
	hold(KEY_E)
	var done: bool = await wait_until(func() -> bool: return Game.tasks_done > done0, 5.0)
	release(KEY_E)
	ok("терминал прочитан", done and not World.terminals.has(t))
	return done


## Узел, с которого доступен рецепт антенны.
func _antenna_tech() -> String:
	for r in DB.recipes:
		if int(r.get("out", -1)) == IDs.I.RELAY_ANTENNA:
			return String(r.get("tech", "T0"))
	return "?"
