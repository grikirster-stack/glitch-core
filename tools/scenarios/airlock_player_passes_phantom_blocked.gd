extends ScenarioBase
## Шлюз (ADR-001 § 4.4, #31): открыт, если игрок в 1.5 клетки и ни одного
## фантома в 3 клетках; для фантомов (и в A*) — стена всегда.
##
## Под землёй — коридор высотой 2 в стальной стене, посередине шлюз из двух
## тайлов (герой выше одной клетки). Бот идёт сквозь шлюз; потом у шлюза
## стоит фантом — шлюз не открывается; открытый шлюз фантом не проходит.

const BOX_W: int = 16
const BOX_H: int = 6
const DOOR_X: int = 7       ## столбец шлюза в коробке

var _o: Vector2i = Vector2i(-1, -1)


func run() -> void:
	player.invuln = 1.0e9
	_o = _find_spot()
	ok("найдено место под землёй", _o.x >= 0, str(_o))
	if _o.x < 0:
		finish()
		return
	_build()
	var lo: Vector2i = _o + Vector2i(DOOR_X, 3)
	var hi: Vector2i = _o + Vector2i(DOOR_X, 2)
	ok("шлюзы в реестре", World.airlocks.has(lo) and World.airlocks.has(hi), "реестр %d" % World.airlocks.size())
	ok("шлюз — стена в A*", World.astar.is_point_solid(lo) and World.astar.is_point_solid(hi))
	var door_px: float = float((_o.x + DOOR_X) * World.TILE)

	# 1. Герой далеко — шлюз закрыт.
	stand_at_cell(_o + Vector2i(2, 3))
	await wait(0.4)
	ok("герой далеко — шлюз закрыт", _closed(), _state())

	# 2. Герой идёт вправо — шлюз открывается, герой проходит насквозь.
	hold(KEY_D)
	var passed: bool = await wait_until(func(): return player.global_position.x > door_px + 24.0, 4.0)
	release(KEY_D)
	ok("герой прошёл сквозь шлюз", passed, "x=%.0f, шлюз %.0f" % [player.global_position.x, door_px])
	ok("открытый шлюз в A* всё равно стена", World.astar.is_point_solid(lo))
	stand_at_cell(_o + Vector2i(DOOR_X + 4, 3))
	await wait(0.4)
	ok("герой отошёл — шлюз закрылся", _closed(), _state())

	# 3. Фантом в 2 клетках за шлюзом (оглушён — стоит на месте): шлюз не пускает.
	stand_at_cell(_o + Vector2i(2, 3))
	var ph: Node = spawn_phantom_at(_floor_pos(_o + Vector2i(DOOR_X + 2, 3)), "echo")
	ok("фантом появился", ph != null)
	if ph == null:
		finish()
		return
	ph.apply_stun(1000.0)
	hold(KEY_D)
	await wait(2.0)
	release(KEY_D)
	ok("фантом у шлюза — герой подошёл, а шлюз закрыт", _closed(), _state())
	ok("герой не прошёл", player.global_position.x < door_px, "x=%.0f" % player.global_position.x)

	# 4. Герой стоит в проёме (шлюз не зажимает его и держится открытым),
	#    фантом идёт на героя — сквозь открытый шлюз ему не пройти.
	World._set_airlock(lo, true)
	World._set_airlock(hi, true)
	stand_at_cell(lo)
	ph.stun = 0.0
	ph.alert = 5.0
	var max_left: float = INF
	var open_samples: int = 0
	var samples: int = 0
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000:
		if is_instance_valid(ph):
			max_left = minf(max_left, ph.global_position.x)
		samples += 1
		if World.get_tile_v(lo) == IDs.T.AIRLOCK_OPEN:
			open_samples += 1
		await wait(0.05)
	ok("герой в проёме — шлюз открыт", open_samples == samples, "%d из %d" % [open_samples, samples])
	ok("фантом не прошёл сквозь открытый шлюз", max_left > door_px + float(World.TILE),
			"ближе всего x=%.0f, шлюз %.0f..%.0f" % [max_left, door_px, door_px + World.TILE])
	ok("фантом пытался (в погоне)", is_instance_valid(ph) and ph.state == Phantom.St.CHASE)

	# 5. Шлюз открыт силой — для тела фантома он всё равно стена.
	World._set_airlock(lo, true)
	World._set_airlock(hi, true)
	var r: Rect2 = World.cell_rect(lo)
	ok("открытый шлюз проходим для героя", not World.rect_solid(r))
	ok("открытый шлюз — стена для фантома", World.rect_solid(r, true) and World.is_phantom_solid_cell(lo))

	# 6. Сломанный шлюз уходит из реестра.
	World.set_tile(lo.x, lo.y, IDs.T.AIR)
	ok("снятый шлюз ушёл из реестра", not World.airlocks.has(lo))
	if is_instance_valid(ph):
		ph.get_parent().remove_child(ph)
		ph.queue_free()
	finish()


func _closed() -> bool:
	return World.get_tile_v(_o + Vector2i(DOOR_X, 3)) == IDs.T.AIRLOCK \
			and World.get_tile_v(_o + Vector2i(DOOR_X, 2)) == IDs.T.AIRLOCK


func _state() -> String:
	return "низ %s, верх %s" % [DB.tile_name(World.get_tile_v(_o + Vector2i(DOOR_X, 3))),
			DB.tile_name(World.get_tile_v(_o + Vector2i(DOOR_X, 2)))]


## Коробка из стальной стены: коридор в рядах 2..3, шлюз — столбец DOOR_X.
func _build() -> void:
	for y in BOX_H:
		for x in BOX_W:
			World.set_tile(_o.x + x, _o.y + y, IDs.T.STEEL_WALL)
	for y in [2, 3]:
		for x in range(1, BOX_W - 1):
			World.set_tile(_o.x + x, _o.y + int(y), IDs.T.AIR)
	World.set_tile(_o.x + DOOR_X, _o.y + 2, IDs.T.AIRLOCK)
	World.set_tile(_o.x + DOOR_X, _o.y + 3, IDs.T.AIRLOCK)


func _floor_pos(c: Vector2i) -> Vector2:
	return Vector2(float(c.x * World.TILE) + 8.0, float((c.y + 1) * World.TILE) - 12.0)


## Тёмное место под землёй (эхо убегает от света).
func _find_spot() -> Vector2i:
	for dx in [70, -70, 90, -90, 110, -110, 130]:
		var x: int = World.beacon_cell.x + int(dx)
		if x < 4 or x + BOX_W > World.W - 4:
			continue
		var y: int = int(World.surface[x]) + 16
		if y + BOX_H >= World.H - 6:
			continue
		var c: Vector2i = Vector2i(x, y)
		if World.light_at(c + Vector2i(DOOR_X + 2, 3)) < 0.4:
			return c
	return Vector2i(-1, -1)
