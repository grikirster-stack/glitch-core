extends "res://tools/scenarios/terminal_powered.gd"
## Порядок чертежей (#169): два прогона на свежем мире одного сида. Сначала
## терминал базы, потом руины — и наоборот. Выданные имена совпадают: какой
## терминал ни прочитай первым, первый чертёж один и тот же.


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
	await _read_powered(a, ach)
	await _read_powered(b, bch)
	return Game.blueprints.duplicate()
