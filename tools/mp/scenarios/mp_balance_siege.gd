extends "res://tools/mp/scenarios/mp_balance_common.gd"
## mp_balance_siege (ADR-002 § 2, § 4.7 «на базу давление растёт полностью»; MP-K, #96):
## осада базы на N героев.
##
## Сетевой двойник night_siege_3 / night_defended_3 (#33): у релея — «обычная» база
## (2 ТЭЦ, 2 бура, плавильня, сборщик; с --mpb-def — ещё 2 турели и стальная стена по
## бокам). Все N героев стоят у ядра и базу не защищают (не бьют; бессмертны — иначе
## смерть и респаун меняют, кто цель). Ночь ведёт штатный директор угрозы с формулами
## N. Меряем машин потеряно, ударов по машинам, мин. hp уцелевших, фантомов вышло, трафик
## хост → клиент (база в зоне интереса).
##
## Флаги хоста: --mpb-day=<смена> (по умолчанию 3), --mpb-def — с обороной.

var _lost: Array = []


func run_host() -> void:
	var day: int = flag_int("day", 3)
	var defended: bool = flag("def")
	if not await host_join():
		finish()
		return
	await barrier("in")
	Game.time_of_day = 0.30
	clear_phantoms()
	var base: Dictionary = build_base(defended)
	ok("база поставлена: %d машин%s" % [base["machines"].size(), ", турелей %d" % int(base["turrets"]) if defended else ""],
			bool(base["ok"]) and (not defended or int(base["turrets"]) == 2))
	ok("хост у ядра", stand_next_to_beacon())
	var at_core: Vector2 = player.global_position
	var placed: bool = true
	for k in range(1, heroes_n()):
		placed = await place_hero(k, at_core) and placed
	ok("все %d героя у ядра" % heroes_n(), placed)
	for h in heroes():
		if h != null:
			(h as Player).invuln = 1.0e9
	await barrier("ready")

	var bx: int = World.beacon_cell.x
	var row: int = World.beacon_cell.y
	var s0: int = Threat.spawned_total
	var kinds: Dictionary = {}
	var on_spawn: Callable = func(ph: Node) -> void:
		var kk: String = String(ph.get("kind"))
		kinds[kk] = int(kinds.get(kk, 0)) + 1
	Threat.phantom_spawned.connect(on_spawn)
	await night_begin(day)
	var budget: float = Threat.budget
	traffic_begin()
	var t0: float = Game.game_time
	var night_len: float = (1.0 - Balance.NIGHT_START + Balance.NIGHT_END) * Balance.DAY_LENGTH
	var hits: Dictionary = {}
	var max_alive: int = 0
	while Game.game_time - t0 < night_len + 2.0 and Game.is_night():
		for p in get_tree().get_nodes_in_group("phantom"):
			if is_instance_valid(p):
				hits[p.get_instance_id()] = int(p.get("machine_hits"))
		max_alive = maxi(max_alive, Threat.units_alive())
		await get_tree().process_frame
	night_end()
	var h2c: float = traffic_bps()
	Threat.phantom_spawned.disconnect(on_spawn)
	var min_hp: float = INF
	var gens_out: int = 0
	for m in World.machines.values():
		if m is CoalGen and not m.power_active:
			gens_out += 1
		if m is MachineBase and is_instance_valid(m) and absi(m.cell.x - bx) < 20 and absi(m.cell.y - row) < 6:
			min_hp = minf(min_hp, m.hp / m.max_hp)
	var hit_sum: int = 0
	for k in hits:
		hit_sum += int(hits[k])
	print("  [ночь %d, N = %d%s] бюджет %.1f, вышло %s (одновременно до %d); ударов по машинам %d; машин потеряно %d %s; мин. hp уцелевших %d %%; ТЭЦ погасло %d; трафик хост → клиент %.0f Б/с" % [
			day, heroes_n(), ", с обороной" if defended else "", budget, str(kinds), max_alive, hit_sum,
			_lost.size(), str(_lost), int(round(min_hp * 100.0)) if min_hp < INF else 0, gens_out, h2c])
	metric("siege_lost", float(_lost.size()), "машин потеряно за ночь")
	metric("siege_hits", float(hit_sum), "ударов фантомов по машинам")
	metric("siege_min_hp", (min_hp * 100.0) if min_hp < INF else 0.0, "мин. hp уцелевших машин, %")
	metric("siege_spawned", float(Threat.spawned_total - s0))
	metric("siege_budget", budget)
	if clients > 0:
		metric("siege_h2c_bps", h2c, "полезная нагрузка хост → клиент, Б/с (база в зоне интереса)")
	if defended:
		ok("ночь %d с обороной, %d героев: 0 потерь" % [day, heroes_n()], _lost.is_empty(), "%d" % _lost.size())
	else:
		ok("ночь %d без обороны, %d героев: потеряно ≥ 1 машины" % [day, heroes_n()], _lost.size() >= 1, "%d" % _lost.size())
	await barrier("done", -1, 30.0)
	clear_phantoms()
	finish()


## «Обычная» база § 4.5 у релея — как balance_common.build_base (#33): та же раскладка,
## чтобы цифры N = 1 совпадали с night_siege_3 / night_defended_3.
func build_base(defended: bool) -> Dictionary:
	var bx: int = World.beacon_cell.x
	var row: int = World.beacon_cell.y
	stand_in_corridor(0)
	var plan: Array = [["CoalGen", 5], ["Drill", 7], ["Drill", 8], ["Smelter", 10],
			["Assembler", 12], ["CoalGen", 14]]
	if defended:
		plan.append(["Turret", 6])
		plan.append(["Turret", 13])
	var machines: Array = []
	var turrets: int = 0
	var all_ok: bool = true
	for e in plan:
		var c: Vector2i = Vector2i(bx + int(e[1]), row)
		World.set_tile(c.x, c.y, IDs.T.AIR)
		if not MachineBase.place_machine(String(e[0]), c):
			all_ok = false
			continue
		var m: MachineBase = World.machines[c]
		machines.append(m)
		if m.kind == "Turret":
			turrets += 1
		if m is CoalGen:
			(m as CoalGen).add_fuel(CoalGen.FUEL_MAX_UNITS)
		m.destroyed.connect(func(mb: MachineBase) -> void: _lost.append(mb.kind))
	if defended:
		for x in [bx + 3, bx + 16]:
			for y in range(row - 3, row + 1):
				if World.get_tile(x, y) == IDs.T.AIR and not World.machines.has(Vector2i(x, y)):
					World.set_tile(x, y, IDs.T.STEEL_WALL)
	for m in machines:
		if m is Smelter:
			m.receive_item(IDs.I.IRON_ORE, 40)
	Game.update_power_budget()
	return {"ok": all_ok, "machines": machines, "turrets": turrets}


# ------------------------------------------------------------------ КЛИЕНТЫ

## Клиент стоит у ядра и ничего не делает: ввод (пустой) уходит хосту — прокси на связи.
func run_client(_i: int) -> void:
	await barrier("in", -1, 60.0)
	await barrier("ready", -1, 60.0)
	await barrier("done", -1, 160.0)
	finish()
