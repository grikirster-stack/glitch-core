extends ScenarioBase
## Двойник замирает под взглядом (ADR-001, § 4.5): игрок лицом к нему, ближе
## 200 px, прямая видимость — стоит; игрок копает или отвернулся — идёт.
## Над головой — имя «того самого» члена экипажа (Lore.impostor).

func run() -> void:
	stand_in_corridor(0)
	player.invuln = 1.0e9
	# Лицом вправо — короткое нажатие D.
	hold(KEY_D)
	await wait(0.06)
	release(KEY_D)
	await wait(0.4)
	ok("игрок смотрит вправо", player.facing == 1)

	var ph: Node = spawn_phantom_at(player.global_position + Vector2(180.0, 0.0), "doppel")
	ok("двойник появился", ph != null and ph.kind == "doppel")
	if ph == null:
		finish()
		return
	var imp: String = String(Lore.impostor.get("full", ""))
	ok("над двойником — имя того самого", imp != "" and ph.display_name == imp, ph.display_name)

	# 1. Под взглядом — стоит.
	await wait(0.3)
	var x0: float = ph.global_position.x
	await wait(1.2)
	ok("под взглядом двойник замер", ph.frozen and absf(ph.global_position.x - x0) < 4.0,
			"сдвиг %.1f px" % absf(ph.global_position.x - x0))

	# 2. Игрок копает (ЛКМ по полу позади себя) — двойник идёт.
	var dig_cell: Vector2i = World.world_to_cell(player.global_position) + Vector2i(-2, 1)
	aim(World.cell_to_world(dig_cell))
	press_mouse(MOUSE_BUTTON_LEFT)
	var x1: float = ph.global_position.x
	await wait(0.45)
	release_mouse(MOUSE_BUTTON_LEFT)
	ok("пока игрок копает — двойник идёт", ph.global_position.x < x1 - 8.0,
			"%.0f → %.0f" % [x1, ph.global_position.x])
	await wait(0.4)
	var x2: float = ph.global_position.x
	await wait(0.6)
	ok("перестал копать — снова замер", ph.frozen and absf(ph.global_position.x - x2) < 4.0,
			"сдвиг %.1f px" % absf(ph.global_position.x - x2))

	# 3. Игрок отвернулся — двойник идёт к нему.
	hold(KEY_A)
	await wait(0.06)
	release(KEY_A)
	await wait(0.1)
	var d0: float = ph.global_position.distance_to(player.global_position)
	var closer: bool = await wait_until(func():
			return ph.global_position.distance_to(player.global_position) < d0 - 30.0, 3.0)
	ok("отвернулся — двойник идёт", closer and not ph.frozen,
			"%.0f → %.0f px" % [d0, ph.global_position.distance_to(player.global_position)])
	ok("двойник — один на сцене", _doppels() == 1)

	# Двойник всегда роняет чёрный ящик; подобранный — 2 кристалла и обрывок.
	var crystals0: int = player.inv.count_of(IDs.I.CRYSTAL)
	var frag0: int = Tech.fragments.size()
	ph.take_damage(1000.0, player.global_position)
	ok("двойник рассеян", not ph.alive)
	var box: Node = null
	for c in scene.get_children():
		if c is ItemEntity and c.item_id == IDs.I.BLACK_BOX:
			box = c
	ok("выпал чёрный ящик", box != null)
	# Идём к ящику, пока его не притянет к игроку.
	if box != null:
		hold(KEY_D if box.global_position.x > player.global_position.x else KEY_A)
	var opened: bool = await wait_until(func(): return Tech.fragments.size() > frag0, 3.0)
	release_all()
	ok("чёрный ящик вскрыт: +%d кристалла и обрывок" % Balance.BLACK_BOX_CRYSTALS, opened
			and player.inv.count_of(IDs.I.BLACK_BOX) == 0
			and player.inv.count_of(IDs.I.CRYSTAL) >= crystals0 + Balance.BLACK_BOX_CRYSTALS,
			"кристаллов %d → %d, обрывков %d" % [crystals0, player.inv.count_of(IDs.I.CRYSTAL), Tech.fragments.size()])
	finish()


func _doppels() -> int:
	var n: int = 0
	for p in get_tree().get_nodes_in_group("phantom"):
		if is_instance_valid(p) and p.kind == "doppel":
			n += 1
	return n
