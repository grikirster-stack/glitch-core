extends ScenarioBase
## Копатель роет природную породу (ADR-001, § 4.4–4.5): камень роет,
## железный блок — нет.
##
## Под землёй строится закрытая коробка из материала: две полости (игрок и
## копатель) и стена между ними. Пути нет — копатель роет напрямую к игроку.

const BOX_W: int = 10
const BOX_H: int = 6
const WALL_X0: int = 3      ## стена — столбцы 3..5
const WALL_X1: int = 5

var _origin: Vector2i = Vector2i(-1, -1)


func run() -> void:
	player.invuln = 1.0e9
	ok("копатель роет землю", Phantom.can_dig(IDs.T.DIRT))
	ok("копатель роет камень", Phantom.can_dig(IDs.T.STONE))
	ok("копатель не роет железный блок", not Phantom.can_dig(IDs.T.IRON_BLOCK))
	ok("копатель не роет стальную стену", not Phantom.can_dig(IDs.T.STEEL_WALL))
	ok("копатель не роет руду", not Phantom.can_dig(IDs.T.COPPER_ORE))

	_origin = _find_spot()
	ok("найдено тёмное место под землёй", _origin.x >= 0, str(_origin))
	if _origin.x < 0:
		finish()
		return

	# Камень: копатель прорывается к игроку.
	var ph: Node = _build_and_spawn(IDs.T.STONE)
	ok("копатель появился", ph != null and ph.kind == "burrower")
	if ph == null:
		finish()
		return
	var dug: bool = await wait_until(func(): return _wall_air() >= 2, 8.0)
	ok("камень вырыт", dug, "вырыто клеток стены %d, всего %d"
			% [_wall_air(), int(ph.tiles_dug) if is_instance_valid(ph) else -1])
	_drop(ph)

	# Железный блок: та же коробка — стена стоит.
	ph = _build_and_spawn(IDs.T.IRON_BLOCK)
	if ph == null:
		finish()
		return
	await wait(4.0)
	ok("железный блок не вырыт", _wall_air() == 0 and is_instance_valid(ph) and int(ph.tiles_dug) == 0,
			"вырыто %d" % (int(ph.tiles_dug) if is_instance_valid(ph) else -1))
	ok("копатель пытался рыть (в погоне)", is_instance_valid(ph) and ph.state == Phantom.St.CHASE)
	_drop(ph)
	finish()


## Коробка из материала, игрок слева, копатель справа.
func _build_and_spawn(mat: int) -> Node:
	var o: Vector2i = _origin
	for y in BOX_H:
		for x in BOX_W:
			World.set_tile(o.x + x, o.y + y, mat)
	# Полости: ряды 2..3; игрок — столбцы 1..2, копатель — 6..8.
	for y in [2, 3]:
		for x in [1, 2, 6, 7, 8]:
			World.set_tile(o.x + int(x), o.y + int(y), IDs.T.AIR)
	stand_at_cell(Vector2i(o.x + 1, o.y + 3))
	var pos: Vector2 = Vector2(float((o.x + 7) * World.TILE) + 8.0, float((o.y + 4) * World.TILE) - 12.0)
	return spawn_phantom_at(pos, "burrower")


## Сколько клеток стены стало воздухом.
func _wall_air() -> int:
	var n: int = 0
	for y in [2, 3]:
		for x in range(WALL_X0, WALL_X1 + 1):
			if World.get_tile(_origin.x + x, _origin.y + int(y)) == IDs.T.AIR:
				n += 1
	return n


func _drop(ph: Node) -> void:
	if ph != null and is_instance_valid(ph):
		ph.get_parent().remove_child(ph)
		ph.queue_free()


## Место для коробки: под поверхностью, вдали от базы, темно (копатель
## убегает от света > 0.8).
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
