extends "res://tools/scenarios/terminal.gd"
## Порядок чертежей (#169, без ТЭЦ — #170): два прогона на свежем мире одного
## сида. Сначала терминал базы, потом руины — и наоборот. Питания больше нет:
## глава, чертёж и подарок выдаются удержанием E. Выданные имена совпадают.


func run() -> void:
	player.invuln = 1.0e9
	var base_t: Vector2i = terminal_of_chapter(0)
	var ruin_t: Vector2i = terminal_of_chapter(Lore.BASE_TERMINALS)
	ok("есть терминал базы и руины", base_t.x >= 0 and ruin_t.x >= 0, "%s / %s" % [base_t, ruin_t])
	if base_t.x < 0 or ruin_t.x < 0:
		finish()
		return
	var forward: PackedStringArray = await _pair(base_t, 0, ruin_t, Lore.BASE_TERMINALS)
	runner.reset_world()
	await wait(0.3)
	player = scene.get("player")
	player.invuln = 1.0e9
	var back: PackedStringArray = await _pair(ruin_t, Lore.BASE_TERMINALS, base_t, 0)
	ok("чертёж 1, потом чертёж 2 — независимо от терминала", forward == back and forward.size() == 2,
			"база→руина %s, руина→база %s" % [str(forward), str(back)])
	finish()


func _pair(a: Vector2i, ach: int, b: Vector2i, bch: int) -> PackedStringArray:
	await _read_terminal(a, ach)
	await _read_terminal(b, bch)
	return Game.blueprints.duplicate()


## Прочитать терминал без ТЭЦ: питание всегда есть, E выдаёт главу, чертёж и подарок.
func _read_terminal(t: Vector2i, chapter: int) -> void:
	var spot: Vector2 = World.cell_to_world(t)
	ok("терминал главы %d читается без ТЭЦ" % (chapter + 1), Game.is_powered(spot), str(t))
	if not await stand_at_terminal(t):
		return
	var done_before: int = Game.tasks_done
	var bp_before: int = Game.blueprints.size()
	var want: String = Game.next_blueprint_name()
	var inv_before: Dictionary = {}
	for e in World.terminal_gift(chapter):
		inv_before[int(e[0])] = player.inv.count_of(int(e[0]))
	hold(KEY_E)
	await wait(0.6)
	ok("прогресс задания растёт", player.task_progress > 0.05, "%.2f" % player.task_progress)
	var done: bool = await wait_until(func() -> bool: return Game.tasks_done > done_before, 5.0)
	await wait(0.3)
	release(KEY_E)
	await wait(0.1)
	ok("зажатая E после терминала не открыла сундук", not UI.blocking())
	ok("задание засчитано", done, "%d → %d" % [done_before, Game.tasks_done])
	ok("выдан следующий чертёж «%s»" % want, want != "" and Game.blueprints.size() == bp_before + 1
			and String(Game.blueprints[bp_before]) == want, str(Game.blueprints))
	ok("подарок терминала выдан", _gift_received(World.terminal_gift(chapter), spot, inv_before))
	ok("глава %d «%s» прочитана" % [chapter + 1, Lore.chapter_title(chapter)], Tech.is_chapter_read(chapter),
			str(Tech.read_chapters))
	ok("терминал отработал", World.get_tile_v(t) == IDs.T.PANEL and not World.terminals.has(t),
			str(World.get_tile_v(t)))


func _gift_received(gift: Array, at: Vector2, inv_before: Dictionary) -> bool:
	if gift.is_empty():
		return false
	for e in gift:
		var id: int = int(e[0])
		var n: int = player.inv.count_of(id) - int(inv_before.get(id, 0))
		for c in scene.get_children():
			if c is ItemEntity and c.item_id == id and c.global_position.distance_to(at) < 80.0:
				n += c.count
		if n < int(e[1]):
			return false
	return true
