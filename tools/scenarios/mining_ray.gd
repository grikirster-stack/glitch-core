extends ScenarioBase
## Копка по лучу (ADR-005 § 3 п. 1): ЛКМ копает первую твёрдую клетку между героем и
## курсором — сквозь стену нельзя. Заодно проверяет World.first_solid_on_ray и меряет
## время вызова (10 000 вызовов на отрезке в 6 клеток).

const NONE: Vector2i = Vector2i(-1, -1)

var _hx: int = 0
var _hy: int = 0


func run() -> void:
	await wait(0.3)
	var base: int = stand_in_corridor(0)
	_hx = int(floor(player.global_position.x / float(World.TILE)))
	_hy = base - 1
	await wait(0.3)

	_check_ray_function()
	await _check_wall_and_vein()
	await _check_air_gap()
	await _check_corner()
	await _check_out_of_reach()
	_bench()
	finish()


## Чистый коридор: две строки над полом от героя на 9 клеток вправо, мышь отпущена.
func _clear_room() -> void:
	release_mouse(MOUSE_BUTTON_LEFT)
	for dy in [-1, 0]:
		for dx in range(1, 10):
			World.set_tile(_hx + dx, _hy + dy, IDs.T.AIR)
	player.global_position = Vector2(float(_hx * World.TILE) + 8.0, float(_hy * World.TILE) + 5.0)
	player.vel = Vector2.ZERO
	player.mining_progress = 0.0
	player.mining_cell = NONE


func _c(dx: int, dy: int = 0) -> Vector2i:
	return Vector2i(_hx + dx, _hy + dy)


func _check_ray_function() -> void:
	_clear_room()
	var from: Vector2 = World.cell_to_world(_c(0))
	ok("пустой коридор: луч ничего не находит",
			World.first_solid_on_ray(from, World.cell_to_world(_c(6))) == NONE)
	World.set_tile(_hx + 4, _hy, IDs.T.STONE)
	ok("камень на пути: возвращается он",
			World.first_solid_on_ray(from, World.cell_to_world(_c(6))) == _c(4))
	ok("камень за концом отрезка не считается",
			World.first_solid_on_ray(from, World.cell_to_world(_c(3))) == NONE)
	ok("конечная клетка считается",
			World.first_solid_on_ray(from, World.cell_to_world(_c(4))) == _c(4))
	ok("стартовая клетка не проверяется",
			World.first_solid_on_ray(World.cell_to_world(_c(4)), World.cell_to_world(_c(6))) == NONE)
	ok("в обратную сторону — тот же камень",
			World.first_solid_on_ray(World.cell_to_world(_c(8)), from) == _c(4))
	World.set_tile(_hx + 4, _hy, IDs.T.WATER)
	ok("жидкость — пусто", World.first_solid_on_ray(from, World.cell_to_world(_c(6))) == NONE)
	World.set_tile(_hx + 4, _hy, IDs.T.AIR)
	# Диагональ строго через угол: оба соседа по стороне твёрдые — луч не просачивается.
	World.set_tile(_hx + 1, _hy, IDs.T.STONE)
	World.set_tile(_hx, _hy - 1, IDs.T.STONE)
	ok("через угол между двумя твёрдыми луч не проходит",
			World.first_solid_on_ray(from, World.cell_to_world(_c(3, -3))) != NONE)
	World.set_tile(_hx + 1, _hy, IDs.T.AIR)
	World.set_tile(_hx, _hy - 1, IDs.T.AIR)
	# Машины — твёрдые (клетка в World.machines), для видимости фантомов — нет.
	var fake: Node2D = Node2D.new()
	World.machines[_c(3)] = fake
	ok("машина на пути: луч упирается в неё",
			World.first_solid_on_ray(from, World.cell_to_world(_c(6))) == _c(3))
	ok("машины не мешают трассировке видимости (machines_block = false)",
			World.first_solid_on_ray(from, World.cell_to_world(_c(6)), false) == NONE)
	World.machines.erase(_c(3))
	fake.free()


## (а) стена из 2 клеток и жила за ней: курсор на жиле — копается ближняя клетка стены.
func _check_wall_and_vein() -> void:
	_clear_room()
	World.set_tile(_hx + 2, _hy, IDs.T.STONE)
	World.set_tile(_hx + 3, _hy, IDs.T.STONE)
	World.set_tile(_hx + 4, _hy, IDs.T.IRON_ORE)
	aim(World.cell_to_world(_c(4)))
	press_mouse(MOUSE_BUTTON_LEFT)
	await wait(0.3)
	ok("(а) курсор на жиле за стеной: копается ближняя клетка стены",
			player.mining_cell == _c(2), str(player.mining_cell))
	ok("(а) цель копки подсвечена рамкой (dig_cell)", player.dig_cell == _c(2), str(player.dig_cell))
	ok("(а) жила под курсором помечена красным крестом", player.dig_denied_cell == _c(4),
			str(player.dig_denied_cell))
	var broke: bool = await wait_until(func() -> bool: return World.get_tile_v(_c(2)) == IDs.T.AIR, 6.0)
	release_mouse(MOUSE_BUTTON_LEFT)
	ok("(а) ближняя клетка сломана", broke)
	ok("(а) вторая клетка стены и жила не тронуты",
			World.get_tile_v(_c(3)) == IDs.T.STONE and World.get_tile_v(_c(4)) == IDs.T.IRON_ORE)


## (б) курсор на клетке через 5 клеток воздуха — копается она.
func _check_air_gap() -> void:
	_clear_room()
	World.set_tile(_hx + 5, _hy, IDs.T.STONE)
	aim(World.cell_to_world(_c(5)))
	press_mouse(MOUSE_BUTTON_LEFT)
	var broke: bool = await wait_until(func() -> bool: return World.get_tile_v(_c(5)) == IDs.T.AIR, 6.0)
	release_mouse(MOUSE_BUTTON_LEFT)
	ok("(б) через воздух копается клетка под курсором (5 клеток)", broke)


## (в) курсор «за углом»: выступ на пути луча копается первым.
func _check_corner() -> void:
	_clear_room()
	World.set_tile(_hx + 3, _hy - 1, IDs.T.STONE)
	World.set_tile(_hx + 4, _hy - 1, IDs.T.IRON_ORE)
	aim(World.cell_to_world(_c(4, -1)))
	press_mouse(MOUSE_BUTTON_LEFT)
	await wait(0.3)
	ok("(в) за углом: цель — выступ, а не клетка под курсором",
			player.mining_cell == _c(3, -1), str(player.mining_cell))
	var broke: bool = await wait_until(func() -> bool: return World.get_tile_v(_c(3, -1)) == IDs.T.AIR, 6.0)
	release_mouse(MOUSE_BUTTON_LEFT)
	ok("(в) выступ сломан, клетка под курсором цела",
			broke and World.get_tile_v(_c(4, -1)) == IDs.T.IRON_ORE)


## (г) клетка на 7 клеток — за REACH, не копается.
func _check_out_of_reach() -> void:
	_clear_room()
	World.set_tile(_hx + 7, _hy, IDs.T.STONE)
	aim(World.cell_to_world(_c(7)))
	press_mouse(MOUSE_BUTTON_LEFT)
	await wait(0.8)
	ok("(г) за радиусом (7 клеток) копка не начинается",
			player.mining_progress == 0.0 and player.dig_cell == NONE, "%.2f %s" % [player.mining_progress, str(player.dig_cell)])
	release_mouse(MOUSE_BUTTON_LEFT)
	ok("(г) клетка цела", World.get_tile_v(_c(7)) == IDs.T.STONE)
	ok("(г) на ней красный крест", player.dig_denied_cell == _c(7))


## Замер: 10 000 вызовов на отрезке в 6 клеток (мкс на вызов).
func _bench() -> void:
	_clear_room()
	var from: Vector2 = World.cell_to_world(_c(0))
	var to: Vector2 = World.cell_to_world(_c(6, -1))
	var n: int = 10000
	var t0: int = Time.get_ticks_usec()
	for _i in range(n):
		World.first_solid_on_ray(from, to)
	var us: float = float(Time.get_ticks_usec() - t0) / float(n)
	print("  [замер] first_solid_on_ray: %.2f мкс на вызов (%d вызовов, отрезок 6 клеток)" % [us, n])
	ok("замер: вызов быстрее 200 мкс (запас под нагруженный CI)", us < 200.0, "%.2f мкс" % us)
