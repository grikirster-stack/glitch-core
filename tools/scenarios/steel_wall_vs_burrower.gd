extends ScenarioBase
## Стальная стена против копателя (ADR-001 § 4.4, #31): копатель роет
## природную породу (флаг dig, твёрдость ≤ 1.5), а стальную стену (4.0) — нет.
## Игрок ломает стальную стену за ≈ 4 с.
##
## Коробка как в burrower_digs_dirt: две полости и стена между ними. Сначала
## стена из земли (контроль: копатель её роет), потом — из стальной стены.

const BOX_W: int = 10
const BOX_H: int = 6
const WALL_X0: int = 3
const WALL_X1: int = 5

var _o: Vector2i = Vector2i(-1, -1)


func run() -> void:
	player.invuln = 1.0e9
	ok("флаг dig: земля — да, стальная стена — нет",
			World.is_diggable(IDs.T.DIRT) and not World.is_diggable(IDs.T.STEEL_WALL))
	ok("стальная стена твёрдостью 4.0", is_equal_approx(DB.tile_hard(IDs.T.STEEL_WALL), Balance.STEEL_WALL_HARD))
	ok("копатель не роет стальную стену", not Phantom.can_dig(IDs.T.STEEL_WALL))
	_o = _find_spot()
	ok("найдено тёмное место под землёй", _o.x >= 0, str(_o))
	if _o.x < 0:
		finish()
		return

	# Контроль: стена из земли — копатель прорывается.
	var ph: Node = _build_and_spawn(IDs.T.DIRT)
	ok("копатель появился", ph != null and ph.kind == "burrower")
	if ph == null:
		finish()
		return
	var dug: bool = await wait_until(func(): return _wall_air() >= 2, 8.0)
	ok("контроль: земляную стену копатель роет", dug, "вырыто %d" % _wall_air())
	_drop(ph)

	# Стальная стена: копатель в погоне, а стена цела.
	ph = _build_and_spawn(IDs.T.STEEL_WALL)
	if ph == null:
		finish()
		return
	await wait(5.0)
	ok("стальная стена устояла 5 с", _wall_air() == 0 and is_instance_valid(ph) and int(ph.tiles_dug) == 0,
			"вырыто %d, копатель вырыл %d" % [_wall_air(), int(ph.tiles_dug) if is_instance_valid(ph) else -1])
	ok("копатель пытался (в погоне)", is_instance_valid(ph) and ph.state == Phantom.St.CHASE)
	ok("копатель не прошёл сквозь стену", is_instance_valid(ph)
			and ph.global_position.x > float((_o.x + WALL_X1 + 1) * World.TILE))
	_drop(ph)

	# Игрок ломает стальную стену за ≈ 4 с.
	var target: Vector2i = Vector2i(_o.x + WALL_X0, _o.y + 3)
	aim(World.cell_to_world(target))
	press_mouse(MOUSE_BUTTON_LEFT)
	var t0: float = now()   # добыча идёт в физических кадрах игрока
	var broke: bool = await wait_until(func(): return World.get_tile_v(target) == IDs.T.AIR, 7.0)
	release_mouse(MOUSE_BUTTON_LEFT)
	var secs: float = now() - t0
	ok("игрок ломает стальную стену за ≈ 4 с", broke and secs >= 3.5 and secs <= 5.0, "%.2f с" % secs)
	finish()


## Коробка из стальной стены, полости: игрок — столбцы 1..2, копатель — 6..8,
## между ними стена из материала mat (столбцы 3..5).
func _build_and_spawn(mat: int) -> Node:
	for y in BOX_H:
		for x in BOX_W:
			World.set_tile(_o.x + x, _o.y + y, IDs.T.STEEL_WALL)
	for y in [2, 3]:
		for x in range(WALL_X0, WALL_X1 + 1):
			World.set_tile(_o.x + x, _o.y + int(y), mat)
		for x in [1, 2, 6, 7, 8]:
			World.set_tile(_o.x + int(x), _o.y + int(y), IDs.T.AIR)
	stand_at_cell(Vector2i(_o.x + 2, _o.y + 3))
	var pos: Vector2 = Vector2(float((_o.x + 7) * World.TILE) + 8.0, float((_o.y + 4) * World.TILE) - 12.0)
	return spawn_phantom_at(pos, "burrower")


func _wall_air() -> int:
	var n: int = 0
	for y in [2, 3]:
		for x in range(WALL_X0, WALL_X1 + 1):
			if World.get_tile(_o.x + x, _o.y + int(y)) == IDs.T.AIR:
				n += 1
	return n


func _drop(ph: Node) -> void:
	if ph != null and is_instance_valid(ph):
		ph.get_parent().remove_child(ph)
		ph.queue_free()


func _find_spot() -> Vector2i:
	for dx in [70, 90, -70, -90, 110, -110, 130]:
		var x: int = World.beacon_cell.x + int(dx)
		if x < 4 or x + BOX_W > World.W - 4:
			continue
		var y: int = int(World.surface[x]) + 18
		if y + BOX_H >= World.H - 4:
			continue
		var c: Vector2i = Vector2i(x, y)
		if World.light_at(c + Vector2i(7, 3)) < 0.5 and World.light_at(c + Vector2i(1, 3)) < 0.5:
			return c
	return Vector2i(-1, -1)
