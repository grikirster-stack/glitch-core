extends "res://tools/scenarios/terminal.gd"
## Терминал под питанием (ADR-001 § 4.6, #29): ТЭЦ с углём рядом с терминалом
## базы → удерживать E → +5 данных, глава 1 журнала, терминал отработал.
## Затем то же у терминала руины: он есть (баг генерации руин) и выдаёт свою главу.


func run() -> void:
	player.invuln = 1.0e9
	var t: Vector2i = terminal_of_chapter(0)
	ok("есть терминал базы (глава 1)", t.x >= 0, str(t))
	if t.x < 0:
		finish()
		return
	await _read_powered(t, 0)

	# Терминал руины: главы 3–9 живут в руинах.
	var ri: int = 0
	var rt: Vector2i = terminal_of_chapter(Lore.BASE_TERMINALS + ri)
	ok("есть терминал руины", rt.x >= 0, str(rt))
	if rt.x >= 0:
		await _read_powered(rt, Lore.BASE_TERMINALS + ri)
	finish()


## Поставить ТЭЦ с углём рядом с терминалом и прочитать его.
func _read_powered(t: Vector2i, chapter: int) -> void:
	var spot: Vector2 = World.cell_to_world(t)
	var gen: CoalGen = _place_gen_near(t)
	ok("ТЭЦ поставлена рядом с терминалом", gen != null, str(t))
	if gen == null:
		return
	gen.add_fuel(4)
	var powered: bool = await wait_until(func() -> bool: return Game.is_powered(spot), 2.0)
	ok("терминал под питанием", powered)
	if not await stand_at_terminal(t):
		return
	var done_before: int = Game.tasks_done
	var data_before: int = Game.research
	hold(KEY_E)
	await wait(0.6)
	ok("прогресс задания растёт", player.task_progress > 0.05, "%.2f" % player.task_progress)
	var done: bool = await wait_until(func() -> bool: return Game.tasks_done > done_before, 5.0)
	await wait(0.3)          # E ещё зажата: нажатие уже отработало, сундук рядом не открывается
	release(KEY_E)
	await wait(0.1)
	ok("зажатая E после терминала не открыла сундук", not UI.blocking())
	ok("задание засчитано", done, "%d → %d" % [done_before, Game.tasks_done])
	ok("+%d данных" % Balance.TERMINAL_DATA, Game.research - data_before == Balance.TERMINAL_DATA,
			"%d → %d" % [data_before, Game.research])
	ok("глава %d «%s» прочитана" % [chapter + 1, Lore.chapter_title(chapter)], Tech.is_chapter_read(chapter),
			str(Tech.read_chapters))
	ok("терминал отработал", World.get_tile_v(t) == IDs.T.PANEL and not World.terminals.has(t),
			str(World.get_tile_v(t)))


## Свободная клетка на твёрдом полу в радиусе питания ТЭЦ от терминала.
func _place_gen_near(t: Vector2i) -> CoalGen:
	for r in range(2, 7):
		for dy in range(-3, 2):
			for dx in [-r, r]:
				var c: Vector2i = t + Vector2i(int(dx), dy)
				if World.get_tile_v(c) != IDs.T.AIR or not World.is_solid_cell(c + Vector2i(0, 1)):
					continue
				if MachineBase.place_machine("CoalGen", c):
					return World.machines.get(c) as CoalGen
	return null
