extends ScenarioBase
## Линза в маяке (#172).
##
## Красный без линзы не бьёт эхо на 9 клетках. С линзой — бьёт, урон × 1.5.
## Разбор возвращает маяк и линзу.


func run() -> void:
	player.invuln = 1.0e9
	var floor_y: int = stand_in_corridor(3)
	await wait(0.3)
	var origin: Vector2i = Vector2i(clampi(World.beacon_cell.x + 28, 10, World.W - 36), floor_y + 8)
	for x in range(origin.x - 2, origin.x + 22):
		for y in range(origin.y - 3, origin.y + 6):
			if World.in_bounds(x, y):
				World.set_tile(x, y, IDs.T.AIR)
	ok("горелка поставлена", MachineBase.place_machine("Burner", origin))
	var pc: Vector2i = origin + Vector2i(5, 0)
	ok("маяк поставлен", MachineBase.place_machine("Pharos", pc))
	var burner: Burner = World.machines.get(origin) as Burner
	var pharos: Pharos = World.machines.get(pc) as Pharos
	if burner == null or pharos == null:
		finish()
		return
	ok("уголь принят", burner.add_fuel(IDs.I.COAL, 4) == 4)
	if World.beams != null:
		World.beams.rebuild()
	ok("маяк красный без линзы", pharos.color == Beams.R and not pharos.lens)

	var far: Vector2i = pc + Vector2i(9, 0)
	var echo: Node = spawn_phantom_at(_foot(far), "echo")
	if echo != null:
		echo.set_process(false)
		echo.set_physics_process(false)
	var dist_tiles: float = pharos.global_position.distance_to(echo.global_position) / 16.0 if echo != null else 0.0
	ok("эхо стоит в 9 клетках", echo != null and dist_tiles > 7.5 and dist_tiles < 10.0, "%.1f" % dist_tiles)
	await wait(1.2)
	ok("без линзы маяк на 9 клетках молчит", echo != null and is_instance_valid(echo) and echo.alive
			and pharos.shots == 0 and pharos.pick_target() == null,
			"выстрелов %d, дальность %.0f" % [pharos.shots, pharos.red_range_px()])

	# Вставить линзу руками: E у маяка.
	player.inv.add(IDs.I.LENS, 1)
	var slot: int = _slot(IDs.I.LENS)
	ok("линза в хотбаре", slot >= 0)
	player.inv.selected = slot
	stand_at_cell(pc + Vector2i(0, 1))
	aim(pharos.global_position)
	await await_frame()
	var hint: String = String(UI.hud.hint_text) if UI.hud != null else ""
	ok("подсказка — вставить линзу", hint.find("линз") >= 0, "«%s»" % hint)
	hold(KEY_E)
	await wait(0.2)
	release(KEY_E)
	await wait(0.2)
	ok("линза вставлена и ушла из рюкзака", pharos.lens and player.inv.count_of(IDs.I.LENS) == 0)
	ok("дальность красного — 10 клеток", is_equal_approx(pharos.red_range_px(), Balance.LENS_RANGE_TILES * 16.0),
			"%.0f px" % pharos.red_range_px())
	ok("урон × 1.5", is_equal_approx(pharos.red_damage(), Balance.PHAROS_RED_DAMAGE * Balance.LENS_MUL),
			"%.1f" % pharos.red_damage())
	print("  [замер] дальность %d → %d клеток, урон %.0f → %.0f" % [
			int(Balance.PHAROS_RANGE_TILES), int(Balance.LENS_RANGE_TILES),
			Balance.PHAROS_RED_DAMAGE, pharos.red_damage()])

	var hit: bool = await wait_until(func() -> bool:
		return echo == null or not is_instance_valid(echo) or not echo.alive or pharos.shots > 0, 2.0)
	ok("с линзой маяк бьёт эхо на 9 клетках", hit and pharos.shots > 0, "выстрелов %d" % pharos.shots)
	if echo != null and is_instance_valid(echo):
		echo.queue_free()

	# Жёлтый с линзой ярче. Свет считаем до разбора.
	pharos.beam_receive(Beams.Y)
	var lit: float = World.light_at(pc + Vector2i(4, 0))
	print("  [замер] light_at в 4 клетках с линзой: %.3f (без линзы цель ≥ 2.0, множитель %.1f)" % [
			lit, Balance.LENS_MUL])
	ok("жёлтый с линзой светит не слабее 2.5", lit >= 2.5, "%.3f" % lit)

	# Разбор возвращает маяк и линзу. Пол под ногами, иначе герой проваливается.
	World.set_tile(pc.x + 1, pc.y + 1, IDs.T.STONE)
	player.global_position = World.cell_to_world(pc + Vector2i(1, 0))
	player.vel = Vector2.ZERO
	player.inv.selected = _empty_hotbar()
	aim(World.cell_to_world(pc))
	await wait(0.2)
	var tg: Dictionary = player.interact_target()
	var before_pharos: int = player.inv.count_of(IDs.I.PHAROS)
	hold(KEY_E)
	var gone: bool = await wait_until(func() -> bool:
		return World.machines.get(pc) == null, 2.0)
	release(KEY_E)
	await wait(0.2)
	ok("маяк разобран", gone)
	ok("разбор вернул маяк и линзу", player.inv.count_of(IDs.I.PHAROS) == before_pharos + 1
			and player.inv.count_of(IDs.I.LENS) >= 1,
			"маяков %d, линз %d" % [player.inv.count_of(IDs.I.PHAROS), player.inv.count_of(IDs.I.LENS)])
	finish()


func _foot(c: Vector2i) -> Vector2:
	return Vector2(float(c.x * World.TILE) + 8.0, float(c.y * World.TILE) + 8.0)


func _slot(id: int) -> int:
	for i in 10:
		var s: ItemStack = player.inv.slots[i]
		if not s.is_empty() and s.id == id:
			return i
	return -1


func _empty_hotbar() -> int:
	for i in 10:
		if player.inv.slots[i].is_empty():
			return i
	return 0
