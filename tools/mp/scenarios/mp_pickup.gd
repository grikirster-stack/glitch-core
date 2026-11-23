extends "res://tools/mp/scenarios/mp_players_base.gd"
## mp_pickup (#309, A1): клавиатурный забор клиента LAN доходит до хоста.
##
## X — бит 12 маски ввода (KEY_BITS), не счётчик нажатий: фронт считает прокси
## по уровню бита. Клиент держит X у своей горелки; хост видит, что прокси снял
## машину и получил предмет. ЛКМ ту же клетку не снимает.

const WAIT: float = 8.0


# ------------------------------------------------------------------ ХОСТ

func run_host() -> void:
	ok("хост + клиент вошли", await wait_players(2, 45.0))
	ok("прокси клиента с вводом", await wait_proxies(1, 10.0))
	await barrier("in")
	var p0: Player = hero_of(0)
	if p0 == null:
		ok("прокси клиента есть", false)
		await barrier("plan")
		await barrier("held")
		await barrier("done")
		finish()
		return
	var cell: Vector2i = await _prep(p0)
	var had: int = p0.inv.count_of(IDs.I.BURNER)
	share_put("plan", {"cx": cell.x, "cy": cell.y})
	await barrier("plan")
	await barrier("lmb")
	ok("хост: ЛКМ клиента горелку не снял", World.machines.has(cell)
			and p0.inv.count_of(IDs.I.BURNER) == had)
	await barrier("held")
	var gone: bool = await wait_until(func() -> bool:
		return not World.machines.has(cell) and p0.inv.count_of(IDs.I.BURNER) == had + 1, WAIT)
	ok("хост: X клиента снял горелку и вернул предмет прокси", gone,
			"машина %s, горелок %d → %d" % [World.machines.has(cell), had, p0.inv.count_of(IDs.I.BURNER)])
	await barrier("done")
	share_clear(["plan"])
	finish()


## Горелка в воздухе у ног прокси, курсор клиента дотягивается.
func _prep(p0: Player) -> Vector2i:
	var sx: int = World.world_to_cell(World.spawn_point).x
	var stand: Vector2 = vent_free_spot(sx + 18, 1)
	ok("клиент у своей горелки", await teleport_proxy(p0, stand))
	var foot: Vector2i = World.world_to_cell(p0.global_position)
	var cell: Vector2i = Vector2i(foot.x + 1, foot.y - 1)
	if World.get_tile_v(cell) != IDs.T.AIR or World.machines.has(cell):
		cell = Vector2i(foot.x, foot.y - 1)
	if World.machines.has(cell):
		var old = World.machines[cell]
		if is_instance_valid(old):
			old.dismantle()
	if World.get_tile_v(cell) != IDs.T.AIR:
		World.set_tile(cell.x, cell.y, IDs.T.AIR)
	MachineBase.place_machine("Burner", cell)
	return cell


# ------------------------------------------------------------------ КЛИЕНТ

func run_client(_i: int) -> void:
	await barrier("in")
	await barrier("plan")
	var plan = share_get("plan")
	if not (plan is Dictionary) or not (plan as Dictionary).has("cx"):
		ok("c0: план клетки получен", false)
		await barrier("lmb")
		await barrier("held")
		await barrier("done")
		finish()
		return
	var cell: Vector2i = Vector2i(int(plan["cx"]), int(plan["cy"]))
	var aim_at: Vector2 = World.cell_to_world(cell)
	aim(aim_at)
	var had: int = player.inv.count_of(IDs.I.BURNER)
	# Короткий ЛКМ: удар или копка, не забор. Машину снимает только X.
	press_mouse(MOUSE_BUTTON_LEFT)
	await wait(0.3)
	release_mouse(MOUSE_BUTTON_LEFT)
	await barrier("lmb")
	aim(aim_at)
	hold(KEY_X)
	var got: bool = await wait_until(func() -> bool:
		return player.inv.count_of(IDs.I.BURNER) == had + 1, WAIT)
	ok("c0: горелка вернулась в свой инвентарь (INV)", got,
			"%d → %d" % [had, player.inv.count_of(IDs.I.BURNER)])
	release(KEY_X)
	await barrier("held")
	await barrier("done")
	finish()
