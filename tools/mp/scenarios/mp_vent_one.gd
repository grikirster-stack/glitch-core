extends "res://tools/mp/scenarios/mp_coop_base.gd"
## mp_vent_one (ADR-002 § 3 D10, § 4.7; MP-I, #94): укрытие на одного, терминал — команде.
##
##  * хост и Аня у одной вентиляции; хост прячется (V); Аня жмёт V — «Вентиляция
##    занята: Хост.» видит только она, не прячется; у Ани марионетка хоста в вентиляции,
##    над ней ник (NickTag) — «товарищи видят ник у занятой вентиляции»;
##  * хост вылез — Аня прячется в ту же вентиляцию;
##  * терминал под питанием, оба держат E одновременно: задание и данные — один раз на
##    команду, всем — кто прочёл.

const WAIT: float = 6.0
const BUSY: String = "Вентиляция занята: Хост."


# ------------------------------------------------------------------ ХОСТ

func run_host() -> void:
	ok("хост + клиент вошли", await wait_players(2, 45.0))
	ok("прокси клиента с вводом", await wait_proxies(1, 10.0))
	await barrier("in")
	var p0: Player = hero_of(0)
	var v: Vector2i = Vector2i(-1, -1)
	var spot: Vector2 = Vector2.ZERO
	for c in World.vents:
		var s: Vector2 = _stand_at_vent(c)
		if s != Vector2.INF:
			v = c
			spot = s
			break
	ok("вентиляция, у которой можно стоять", v.x >= 0, str(v))
	if p0 == null or v.x < 0:
		finish()
		return
	ok("Аня у вентиляции", await teleport_proxy(p0, spot))
	player.global_position = spot
	player.vel = Vector2.ZERO
	await wait(0.4)
	ok("оба в радиусе вентиляции (40 px)", World.cell_to_world(v).distance_to(player.global_position) < 40.0
			and World.cell_to_world(v).distance_to(p0.global_position) < 40.0)
	await tap(KEY_V)
	ok("хост в вентиляции", player.hiding and player.net_vent == v, str(player.net_vent))
	await barrier("host_in")
	await barrier("c_tried")
	ok("хост: Аня не залезла в занятую", not p0.hiding)
	ok("хост: «занята» ушло только Ане — у хоста его нет", notes_with("Вентиляция занята") == 0, str(notes))
	await tap(KEY_V)
	ok("хост вылез", not player.hiding)
	await barrier("host_out")
	ok("хост: Аня в той же вентиляции", await wait_until(func() -> bool:
		return p0.hiding and p0.net_vent == v, WAIT), str(p0.net_vent))
	await barrier("c_in")

	# --- Терминал: оба держат E.
	var term: Vector2i = _terminal()
	var gen: CoalGen = _place_gen_near(term) if term.x >= 0 else null
	ok("терминал базы и ТЭЦ рядом", term.x >= 0 and gen != null)
	if gen == null:
		await barrier("term")
		await barrier("read")
		finish()
		return
	gen.add_fuel(4)
	var tp: Vector2 = World.cell_to_world(term)
	ok("терминал под питанием", await wait_until(func() -> bool: return Game.is_powered(tp), 3.0))
	var stand: Vector2 = _stand_near(tp)
	await wait_until(func() -> bool: return not p0.hiding, Balance.HIDE_MAX + 1.0)
	ok("Аня у терминала", await teleport_proxy(p0, stand))
	player.global_position = stand
	player.vel = Vector2.ZERO
	await wait(0.4)
	var done0: int = Game.tasks_done
	var bp0: int = Game.blueprints.size()
	notes.clear()
	await barrier("term")
	hold(KEY_E)
	await wait_until(func() -> bool: return Game.tasks_done > done0, 8.0)
	await wait(1.0)
	release(KEY_E)
	ok("терминал прочитан один раз на команду: задание +1 и чертёж",
			Game.tasks_done == done0 + 1 and Game.blueprints.size() == bp0 + 1,
			"задания %d → %d, чертежи %s" % [done0, Game.tasks_done, str(Game.blueprints)])
	ok("терминал отработал", not World.terminals.has(term))
	ok("хост: всем — кто прочёл", notes_with("прочитан") == 1, str(notes))
	await barrier("read")
	finish()


## Точка стоя рядом с вентиляцией (центр героя ближе 40 px), Vector2.INF — нет.
func _stand_at_vent(c: Vector2i) -> Vector2:
	var vp: Vector2 = World.cell_to_world(c)
	for o in [Vector2(0, -4), Vector2(0, -8), Vector2(12, -4), Vector2(-12, -4), Vector2(0, 0), Vector2(16, -8), Vector2(-16, -8)]:
		var p: Vector2 = vp + o
		if World.rect_solid(Rect2(p - Player.SIZE * 0.5, Player.SIZE)):
			continue
		# Стоит на полу: под ногами твёрдо в пределах клетки.
		var feet: Rect2 = Rect2(p + Vector2(-Player.SIZE.x * 0.5, Player.SIZE.y * 0.5), Vector2(Player.SIZE.x, 6.0))
		if World.rect_solid(feet):
			return p
	return Vector2.INF


func _terminal() -> Vector2i:
	for t in World.terminals:
		if int(World.terminal_chapters.get(t, -1)) == 0:
			return t
	return World.terminals[0] if not World.terminals.is_empty() else Vector2i(-1, -1)


func _stand_near(spot: Vector2) -> Vector2:
	for o in [Vector2(0, -24), Vector2(24, 0), Vector2(-24, 0), Vector2(24, -24), Vector2(-24, -24)]:
		var p: Vector2 = spot + o
		if not World.rect_solid(Rect2(p - Player.SIZE * 0.5, Player.SIZE)):
			return p
	return spot + Vector2(0, -24)


## Как в mp_actions: ТЭЦ на свободной клетке с полом рядом с терминалом.
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


# ------------------------------------------------------------------ КЛИЕНТ

func run_client(_i: int) -> void:
	await barrier("in")
	await barrier("host_in")
	var host: Player = np().heroes.get(1) as Player
	ok("c0: марионетка хоста в вентиляции", await wait_until(func() -> bool:
		return host != null and host.hiding, WAIT))
	var tag: Node = null
	if host != null:
		for c in host.get_children():
			if c is NetPlayers.NickTag:
				tag = c
	ok("c0: у занятой вентиляции виден ник товарища", tag != null and host.nick == "Хост" and not host.dead,
			host.nick if host != null else "—")
	await tap(KEY_V)
	ok("c0: «%s» — у нажавшего" % BUSY, await wait_until(func() -> bool: return notes_with(BUSY) == 1, WAIT),
			str(notes))
	await wait(0.4)
	ok("c0: не спрятался", not player.hiding)
	await barrier("c_tried")
	await barrier("host_out")
	await wait_until(func() -> bool: return host != null and not host.hiding, WAIT)
	await tap(KEY_V)
	ok("c0: в вентиляции (OWN)", await wait_until(func() -> bool: return player.hiding, WAIT))
	await barrier("c_in")
	var done0: int = Game.tasks_done
	notes.clear()
	await barrier("term")
	hold(KEY_E)
	await wait_until(func() -> bool: return Game.tasks_done > done0, 9.0)
	release(KEY_E)
	await barrier("read")
	ok("c0: задание засчитано один раз (глобальный пакет)", Game.tasks_done == done0 + 1,
			"%d → %d" % [done0, Game.tasks_done])
	ok("c0: всем — кто прочёл терминал", await wait_until(func() -> bool:
		return notes_with("прочитан") == 1, WAIT), str(notes))
	finish()
