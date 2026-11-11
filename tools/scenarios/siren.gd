extends ScenarioBase
## Сирена (#172, ADR-005 § 7.2).
##
## Рой из 5 и тень в 6 клетках. Под лучом заряд доходит за 60 с, E гонит всех
## в FLEE на 10 с, расстояние до сирены растёт. Через 10 с снова идут.
## Без луча заряд стоит.


const TILE: float = 16.0


func run() -> void:
	player.invuln = 1.0e9
	var floor_y: int = stand_in_corridor(2)
	await wait(0.3)
	var origin: Vector2i = Vector2i(clampi(World.beacon_cell.x + 36, 12, World.W - 40), floor_y + 8)
	_clear(origin, 28, 10)
	ok("горелка поставлена", MachineBase.place_machine("Burner", origin))
	var sc: Vector2i = origin + Vector2i(4, 0)
	ok("сирена поставлена", MachineBase.place_machine("Siren", sc))
	var burner: Burner = World.machines.get(origin) as Burner
	var siren: Siren = World.machines.get(sc) as Siren
	if burner == null or siren == null:
		finish()
		return
	ok("сирена не крутится", not siren.can_turn)

	# Без луча заряд стоит.
	var c0: float = siren.charge
	await wait(1.2)
	ok("без луча заряд не растёт", siren.charge == c0 and not siren.charging, "%.2f" % siren.charge)

	ok("уголь принят", burner.add_fuel(IDs.I.COAL, 8) == 8)
	_flush()
	ok("луч дошёл до сирены", siren.charging and World.beams.color_at(sc) == 0
			and World.beams.color_at(sc + Vector2i(-1, 0)) != 0)
	await wait(1.0)
	ok("под лучом заряд растёт", siren.charge >= 0.8, "%.2f" % siren.charge)

	# 60 с под лучом — полный заряд. Часы машины — кадры отрисовки, их же
	# ускоряет Engine.time_scale (как в beam_burner).
	var t0: float = now_proc()
	Engine.time_scale = 15.0
	var full: bool = await wait_until(func() -> bool: return siren.ready(), 62.0)
	Engine.time_scale = 1.0
	ok("заряд полон за ≤ 62 с", full and siren.charge >= Balance.SIREN_RECHARGE - 0.05
			and now_proc() - t0 <= 62.5,
			"%.2f / %.0f за %.1f с" % [siren.charge, Balance.SIREN_RECHARGE, now_proc() - t0])
	print("  [замер] заряд сирены: %.2f с под лучом (цель %.0f)" % [siren.charge, Balance.SIREN_RECHARGE])

	# Рой — стая целиком (spawn даёт 4–6, берём пять). Тень в 6 клетках, на полу.
	# Ходячая тень бежит от сирены вбок: под ней нужен коридор, иначе край обрыва.
	player.global_position = World.cell_to_world(origin + Vector2i(0, 8))
	var pack: Array = spawn_pack_at(_foot(sc + Vector2i(6, 1)), "swarm")
	while pack.size() > 5:
		var extra: Node = pack.pop_back()
		if is_instance_valid(extra):
			extra.queue_free()
	while pack.size() < 5:
		var one: Node = spawn_phantom_at(_foot(sc + Vector2i(5, 1)), "swarm")
		if one == null:
			break
		pack.append(one)
	var shade_cell: Vector2i = sc + Vector2i(0, 5)
	for x in range(shade_cell.x - 14, shade_cell.x + 15):
		if World.in_bounds(x, shade_cell.y + 1):
			World.set_tile(x, shade_cell.y + 1, IDs.T.STONE)
		if World.in_bounds(x, shade_cell.y):
			World.set_tile(x, shade_cell.y, IDs.T.AIR)
		if World.in_bounds(x, shade_cell.y - 1):
			World.set_tile(x, shade_cell.y - 1, IDs.T.AIR)
	var shade: Node = spawn_phantom_at(_foot(shade_cell), "shade")
	ok("рой из 5 и тень в 6 клетках", pack.size() == 5 and shade != null,
			"рой %d" % pack.size())
	# До того, как рой улетит к игроку: спавн в 6 клетках, радиус сирены — 10.
	var d_spawn: float = _min_dist(pack, siren.global_position)
	var shade_spawn: float = shade.global_position.distance_to(siren.global_position) if shade != null else 0.0
	ok("до сирены не дальше 7 клеток", d_spawn <= 7.0 * TILE and shade_spawn <= 7.0 * TILE,
			"рой %.0f, тень %.0f" % [d_spawn, shade_spawn])
	await wait(0.4)
	var d0: float = _min_dist(pack, siren.global_position)
	var shade_d0: float = shade.global_position.distance_to(siren.global_position) if shade != null else 0.0

	stand_at_cell(sc + Vector2i(0, 1))
	aim(siren.global_position)
	await await_frame()
	var hint: String = String(UI.hud.hint_text) if UI.hud != null else ""
	var words: PackedStringArray = hint.split(" ", false)
	ok("подсказка E у сирены ≤ 6 слов", words.size() <= 6 and words.size() > 0, "«%s» (%d)" % [hint, words.size()])
	print("  [замер] слов в подсказке E: %d («%s»)" % [words.size(), hint])

	hold(KEY_E)
	await wait(0.15)
	release(KEY_E)
	await wait(0.3)
	var fled: int = _in_flee(pack)
	var shade_flee: bool = shade != null and is_instance_valid(shade) and shade.state == Phantom.St.FLEE
	ok("E отправил рой и тень в FLEE", fled == 5 and shade_flee and siren.blasts == 1,
			"рой %d/5, тень %s, залпов %d" % [fled, str(shade_flee), siren.blasts])
	ok("заряд сброшен", siren.charge < 1.0, "%.2f" % siren.charge)

	await wait(1.2)
	var d1: float = _min_dist(pack, siren.global_position)
	var shade_d1: float = shade.global_position.distance_to(siren.global_position) if shade != null and is_instance_valid(shade) else 0.0
	var shade_state: int = int(shade.state) if shade != null and is_instance_valid(shade) else -1
	ok("рой и тень удаляются от сирены", d1 > d0 + 20.0 and shade_d1 > shade_d0 + 20.0,
			"рой %.0f → %.0f, тень %.0f → %.0f, состояние %d" % [d0, d1, shade_d0, shade_d1, shade_state])
	print("  [замер] гон: рой %.0f → %.0f px, тень %.0f → %.0f px за 1.2 с" % [d0, d1, shade_d0, shade_d1])

	# 10 с гона. Ждём остаток от уже прошедших ~1.5 с.
	Engine.time_scale = 8.0
	await wait(9.0)
	Engine.time_scale = 1.0
	var still: int = _in_flee(pack)
	ok("через 10 с рой снова не в FLEE", still == 0, "ещё в FLEE: %d" % still)
	if shade != null and is_instance_valid(shade):
		ok("тень после гона снова идёт", shade.state != Phantom.St.FLEE,
				"состояние %d" % int(shade.state))

	_save(siren)
	finish()


func _foot(c: Vector2i) -> Vector2:
	return Vector2(float(c.x * World.TILE) + 8.0, float(c.y * World.TILE) + 8.0)


func _clear(origin: Vector2i, w: int, h: int) -> void:
	for x in range(origin.x - 2, origin.x + w):
		for y in range(origin.y - 4, origin.y + h):
			if World.in_bounds(x, y):
				World.set_tile(x, y, IDs.T.AIR)


func _flush() -> void:
	if World.beams != null:
		World.beams.rebuild()


func _min_dist(pack: Array, pos: Vector2) -> float:
	var best: float = INF
	for p in pack:
		if is_instance_valid(p) and bool(p.get("alive")):
			best = minf(best, p.global_position.distance_to(pos))
	return best


func _in_flee(pack: Array) -> int:
	var n: int = 0
	for p in pack:
		if is_instance_valid(p) and bool(p.get("alive")) and p.state == Phantom.St.FLEE:
			n += 1
	return n


func _save(siren: Siren) -> void:
	siren.charge = 12.5
	var slot0: String = Save.slot
	Save.slot = "siren"
	Save.remove("siren")
	var packed: PackedByteArray = var_to_bytes(Save.gather())
	Save.apply(Save.decode(packed))
	var back: Siren = World.machines.get(siren.cell) as Siren
	ok("заряд сирены сохранился", back != null and absf(back.charge - 12.5) < 0.05,
			"%.2f" % (back.charge if back != null else -1.0))
	Save.remove("siren")
	Save.slot = slot0
