extends ScenarioBase
## Радужный кот (#176): пять эхо в 15 клетках, все мертвы за ≤ 30 с.
## Через 90 с кот в ядре. Заряд растёт только под лучом. След светит ≥ 1.5.


func run() -> void:
	player.invuln = 1.0e9
	var floor_y: int = stand_in_corridor(2)
	await wait(0.2)
	var home: Vector2i = Vector2i(World.beacon_cell.x + 8, floor_y - 4)
	_clear(home + Vector2i(-2, -2), 36, 10)
	ok("ядро стоит", MachineBase.place_machine("RainbowCore", home))
	ok("заряд полон в ядре", Game.cat_charged() and Game.cat_state == Game.CatState.IN_CORE)
	var before: float = Game.cat_charge
	await wait(0.4)
	ok("без луча заряд не растёт", absf(Game.cat_charge - before) < 0.01, "%.2f" % Game.cat_charge)

	var echoes: Array = []
	for i in 5:
		var c: Vector2i = home + Vector2i(6 + i * 2, 0)
		var e: Node = spawn_phantom_at(_foot(c), "echo")
		if e != null:
			echoes.append(e)
	ok("пять эхо в 15 клетках", echoes.size() == 5)
	var cat: RainbowCat = Game.cat_hatch_at()
	ok("кот вышел из точки ядра", cat != null and cat.global_position.distance_to(World.cell_to_world(home)) < 2.0
			and Game.cat_state == Game.CatState.OUT)
	ok("кот не в группе фантомов", cat != null and not cat.is_in_group("phantom"))
	var t0: float = now()
	var dead: bool = await wait_until(func() -> bool: return _alive(echoes) == 0, 30.0)
	var secs: float = now() - t0
	ok("все пять мертвы за ≤ 30 с", dead and secs <= 30.0, "%.2f с, живых %d" % [secs, _alive(echoes)])
	print("  [замер] кот снял 5 эхо за %.2f с (цель ≤ 30)" % secs)

	var fx = scene.get("world_fx")
	var lit: bool = false
	if fx != null and cat != null and is_instance_valid(cat):
		for p in fx.cat_pts:
			if World.light_at(World.world_to_cell(p["pos"])) + 0.001 >= Balance.CAT_TRAIL_LIGHT:
				lit = true
				break
		if fx.cat_pts.is_empty():
			lit = World.light_at(World.world_to_cell(cat.global_position)) + 0.001 >= Balance.CAT_TRAIL_LIGHT
	ok("свет следа ≥ 1.5", lit, "точек %d" % (fx.cat_pts.size() if fx != null else -1))

	# Стена на обратном пути: кот должен обойти, а не застрять.
	if cat != null and is_instance_valid(cat):
		var wall: Vector2i = World.world_to_cell(cat.global_position)
		for dy in range(-2, 3):
			World.set_tile(wall.x, wall.y + dy, IDs.T.STONE)
		World.set_tile(wall.x, wall.y + 3, IDs.T.AIR)
	cat.age = Balance.CAT_TIME - 0.1
	var home_back: bool = await wait_until(func() -> bool:
		return Game.cat_state == Game.CatState.RECHARGE, 25.0)
	ok("через 90 с кот в ядре", home_back and Game.cat_state == Game.CatState.RECHARGE
			and Game.cat_charge == 0.0, "состояние %d заряд %.1f" % [Game.cat_state, Game.cat_charge])

	var still: float = Game.cat_charge
	await wait(0.5)
	ok("заряд стоит, пока луча нет", absf(Game.cat_charge - still) < 0.01, "%.3f" % Game.cat_charge)
	var burner_c: Vector2i = home + Vector2i(-4, 0)
	ok("горелка к ядру", MachineBase.place_machine("Burner", burner_c))
	var burner: Burner = World.machines.get(burner_c) as Burner
	if burner != null:
		burner.dir = 0
		burner.add_fuel(IDs.I.COAL, 8)
	_flush()
	var core = World.machines.get(home)
	var hit: bool = core != null and bool(core.get("_beam"))
	ok("луч упёрся в ядро", hit, "маска перед ядром %d" % World.beams.color_at(home + Vector2i(-1, 0)))
	var c0: float = Game.cat_charge
	await wait(1.2)
	ok("под лучом заряд растёт", Game.cat_charge > c0 + 0.5, "%.2f → %.2f" % [c0, Game.cat_charge])
	_bench()
	finish()


func _alive(nodes: Array) -> int:
	var n: int = 0
	for e in nodes:
		if is_instance_valid(e) and bool(e.alive):
			n += 1
	return n


func _foot(c: Vector2i) -> Vector2:
	return Vector2(float(c.x * World.TILE) + 8.0, float(c.y * World.TILE) + 8.0)


func _clear(origin: Vector2i, w: int, h: int) -> void:
	for x in range(origin.x, origin.x + w):
		for y in range(origin.y, origin.y + h):
			if World.in_bounds(x, y):
				World.set_tile(x, y, IDs.T.AIR)


func _flush() -> void:
	if World.beams != null:
		World.beams.note_machines()
		World.beams.rebuild()
		World._apply_beam_lights()


## Кадр со следом: 30 источников кота, мкс _process WorldFX.
func _bench() -> void:
	var fx = scene.get("world_fx")
	if fx == null:
		return
	fx.cat_trail_clear()
	var origin: Vector2 = Game.cat_home()
	var bare_lights: int = World.lights.size()
	var t0: int = Time.get_ticks_usec()
	for _i in 30:
		fx._process(0.016)
	var bare: float = float(Time.get_ticks_usec() - t0) / 30.0
	for i in Balance.CAT_TRAIL_POINTS:
		fx.cat_trail(origin + Vector2(float(i) * 6.0, sin(float(i)) * 2.0))
	var with_lights: int = World.lights.size()
	var t1: int = Time.get_ticks_usec()
	for _i in 30:
		fx._process(0.016)
	var us: float = float(Time.get_ticks_usec() - t1) / 30.0
	print("  [замер] кадр следа: %.0f мкс с %d точками (%d источников света, было %d), %.0f мкс без" % [
			us, fx.cat_pts.size(), with_lights - bare_lights, bare_lights, bare])
	ok("след держит не больше 30 точек", fx.cat_pts.size() <= Balance.CAT_TRAIL_POINTS
			and fx.cat_pts.size() > 0, "точек %d" % fx.cat_pts.size())
	fx.cat_trail_clear()
