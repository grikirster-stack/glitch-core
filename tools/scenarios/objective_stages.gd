extends "res://tools/scenarios/terminal_powered.gd"
## Этапы цели (ADR-001 § 4.7, #32; временно три этапа, #169): 1 → 2 → 3.
##   1 → 2: оба терминала базы прочитаны под питанием (ТЭЦ рядом, удерживать E):
##          главы 1–2 журнала и два чертежа. Один терминал — ещё этап 1.
##   2 → 3: E у ядра с полным набором — Game.try_finish().
## Сигнал objective_changed уходит по разу на этап, по порядку.

var _seen: Array = []


func run() -> void:
	player.invuln = 1.0e9
	Game.objective_changed.connect(_on_stage)
	# Этап 1 ставит первый такт Game после сброса забега (до него — 0, «не начато»).
	var started: bool = await wait_until(func() -> bool: return Game.objective_stage == 1, 2.0)
	ok("старт забега — этап 1", started, str(Game.objective_stage))
	ok("строка цели «ЦЕЛЬ 1/3»", Game.objective_text().begins_with("ЦЕЛЬ 1/3"), Game.objective_text())

	# --- 1 → 2: терминалы базы под питанием.
	var bp0: int = Game.blueprints.size()
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
	ok("два чертежа за станцию", Game.blueprints.size() == bp0 + Lore.BASE_TERMINALS, str(Game.blueprints))
	ok("главы 1–2 журнала прочитаны", Tech.is_chapter_read(0) and Tech.is_chapter_read(1),
			str(Tech.read_chapters))

	# --- 2 → 3: запуск релея. Дерева технологий больше нет (#169).
	ok("без деталей релей не стартует", not Game.try_finish() and Game.objective_stage == 2)
	for id in Game.relay_req.keys():
		player.inv.add(int(id), int(Game.relay_req[id]))
	ok("с полным набором релей стартует", Game.try_finish())
	ok("этап 3 — сразу при запуске", Game.objective_stage == 3, Game.objective_text())
	ok("строка цели с отсчётом", Game.objective_text().begins_with("ЦЕЛЬ 3/3")
			and Game.objective_text().ends_with(" с"), Game.objective_text())
	ok("этапы по порядку 1 → 2 → 3, по разу", _seen == [1, 2, 3], str(_seen))
	_end()


func _end() -> void:
	if Game.objective_changed.is_connected(_on_stage):
		Game.objective_changed.disconnect(_on_stage)
	finish()


func _on_stage(s: int) -> void:
	_seen.append(s)


## Встать у терминала и удерживать E до засчитанного задания. ТЭЦ не нужна (#170).
func _read_quick(t: Vector2i) -> bool:
	var spot: Vector2 = World.cell_to_world(t)
	ok("терминал читается без ТЭЦ", Game.is_powered(spot))
	if not await stand_at_terminal(t):
		return false
	var done0: int = Game.tasks_done
	hold(KEY_E)
	var done: bool = await wait_until(func() -> bool: return Game.tasks_done > done0, 5.0)
	release(KEY_E)
	ok("терминал прочитан", done and not World.terminals.has(t))
	return done


