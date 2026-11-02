class_name ScenarioBase
extends Node
## Базовый класс сценария: доступ к игроку, шву ввода, проверкам и ожиданиям.
##
## Наследник реализует run(): там сценарий жмёт клавиши через шов игрока
## (test_input) и смотрит, как на это отреагировала игра. Никаких прямых
## вызовов внутренних методов игрока — только управление, как у человека.
##
## Ожидания отсчитываются по реальному времени: в headless частота кадров
## не гарантирована, а физика идёт по delta.

signal done

var runner: ScenarioRunner = null
var scene = null
var player: Player = null

var _keys: Dictionary = {}
var _mouse_buttons: Dictionary = {}
var _mouse: Vector2 = Vector2.ZERO


func setup(p_runner: ScenarioRunner, p_scene: Node) -> void:
	runner = p_runner
	scene = p_scene
	player = p_scene.get("player")


## Тело сценария. Наследник обязан закончить вызовом finish().
func run() -> void:
	pass


## Сценарий закончился — раннер переходит к следующему.
func finish() -> void:
	done.emit()


# ------------------------------------------------------------------ ПРОВЕРКИ

## Записать результат проверки (тот же формат, что у тест-раннера).
func ok(label: String, cond: bool, extra: String = "") -> void:
	runner.ok(label, cond, extra)


## Подождать реальные секунды.
func wait(secs: float) -> void:
	await runner.wait(secs)


## Подождать, пока условие не станет истинным (или не выйдет время).
func wait_until(cond: Callable, timeout: float) -> bool:
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(timeout * 1000.0):
		if cond.call():
			return true
		await wait(0.05)
	return bool(cond.call())


# ------------------------------------------------------------------ ВВОД

## Зажать клавишу (через шов игрока).
func hold(code: int) -> void:
	_keys[code] = true
	_apply_input()


## Отпустить клавишу.
func release(code: int) -> void:
	_keys[code] = false
	_apply_input()


## Зажать несколько клавиш сразу.
func hold_all(codes: Array) -> void:
	for c in codes:
		_keys[int(c)] = true
	_apply_input()


## Отпустить все клавиши.
func release_all() -> void:
	_keys.clear()
	_apply_input()


## Навести «курсор» в мировую точку.
func aim(pos: Vector2) -> void:
	_mouse = pos
	_apply_input()


## Зажать кнопку мыши.
func press_mouse(btn: int) -> void:
	_mouse_buttons[btn] = true
	_apply_input()


## Отпустить кнопку мыши.
func release_mouse(btn: int) -> void:
	_mouse_buttons[btn] = false
	_apply_input()


## Полностью снять шов: игрок снова читает обычный Input.
func clear_input() -> void:
	_keys.clear()
	_mouse_buttons.clear()
	player.test_input = {}


func _apply_input() -> void:
	player.test_input = {
		"keys": _keys.duplicate(),
		"mouse": _mouse,
		"mouse_buttons": _mouse_buttons.duplicate(),
	}


# ------------------------------------------------------------------ МИР

## Расчистить коридор у базы (справа от релея) и поставить туда героя.
## Пол базы — ровная сталь, рядом нет ни стен, ни ям: сценарию не мешает рельеф.
## Возвращает ряд пола.
func stand_in_corridor(offset: int = 0) -> int:
	var bx: int = World.beacon_cell.x
	var base: int = World.beacon_cell.y + 1
	# Площадка базы выровнена на bx±17: пол там ровный, без ям и уступов.
	for x in range(bx + 1, bx + 18):
		World.set_tile(x, base - 1, IDs.T.AIR)
	var px: int = clampi(bx + 1 + offset, bx + 1, bx + 17)
	player.global_position = Vector2(float(px * World.TILE) + 8.0, float(base * World.TILE) - 11.0)
	player.vel = Vector2.ZERO
	return base


## Встать рядом с релей-ядром (радиус взаимодействия 56 px) и убрать
## постройки базы, которые мешают встать. Возвращает false, если не вышло.
func stand_next_to_beacon() -> bool:
	var bx: int = World.beacon_cell.x
	var base: int = World.beacon_cell.y + 1
	for dx in [1, -1, 2, -2, 3, -3]:
		var px: int = bx + int(dx)
		# Пол должен быть, иначе герой провалится.
		if not World.is_solid_cell(Vector2i(px, base)):
			continue
		# Убираем постройки базы над головой (панели, лампы) — сценарий не мешает.
		for y in range(base - 3, base):
			if World.get_tile_v(Vector2i(px, y)) != IDs.T.AIR:
				World.set_tile(px, y, IDs.T.AIR)
		player.global_position = Vector2(float(px * World.TILE) + 8.0, float(base * World.TILE) - 11.0)
		player.vel = Vector2.ZERO
		return true
	return false


## Поставить героя рядом с точкой, не засовывая его в стену.
func place_near(target: Vector2, offsets: Array) -> bool:
	for o in offsets:
		var p: Vector2 = target + Vector2(o)
		if not World.rect_solid(Rect2(p - Player.SIZE * 0.5, Player.SIZE)):
			player.global_position = p
			player.vel = Vector2.ZERO
			return true
	return false


## Найти тайл, который герой может выкопать: не твёрже 1.0, с дропом и в досягаемости.
## Сначала ищем тайлы в своём ряду (как «копнуть перед собой»), потом — под ногами.
func find_mineable() -> Vector2i:
	var pc: Vector2i = World.world_to_cell(player.global_position)
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: float = -1.0
	# Сначала ищем тайл в своём ряду (как «копнуть перед собой»), потом — под ногами.
	for band in [[0, -1, -2], [1, 2, 3, 4]]:
		for dy in band:
			for dx in range(-7, 8):
				var c: Vector2i = pc + Vector2i(dx, dy)
				var t: int = World.get_tile_v(c)
				if t == IDs.T.AIR:
					continue
				if DB.tile_hard(t) > 1.0:
					continue
				if DB.tile_drop(t) == IDs.I.NONE:
					continue
				var w: Vector2 = World.cell_to_world(c)
				var d: float = w.distance_to(player.global_position)
				if d > Player.REACH - 4.0:
					continue
				if d > best_d:
					best_d = d
					best = c
		if best.x >= 0:
			return best
	return best


## Создать фантома (штатным спавном директора угрозы) в нужной точке.
## Для роя создаётся вся стая, возвращается первый из неё.
func spawn_phantom_at(pos: Vector2, kind: String = "echo") -> Node:
	var made: Array = Threat.spawn_phantom(kind, pos)
	return made[0] if not made.is_empty() else null


## То же, но вся стая (рой) целиком.
func spawn_pack_at(pos: Vector2, kind: String = "swarm") -> Array:
	return Threat.spawn_phantom(kind, pos)


## Дождаться одного кадра.
func await_frame() -> void:
	await get_tree().process_frame


## Поставить героя в клетку, стоя на полу под ней.
func stand_at_cell(cell: Vector2i) -> void:
	player.global_position = Vector2(float(cell.x * World.TILE) + 8.0,
			float((cell.y + 1) * World.TILE) - 11.0)
	player.vel = Vector2.ZERO


## Найти тёмное место на поверхности: фантомы убегают из освещённых клеток,
## поэтому охотиться на героя можно только там, где темно.
func find_dark_spot(max_light: float = 0.45) -> Vector2i:
	for x in range(2, World.W - 2):
		var cell: Vector2i = Vector2i(x, World.surface[x] - 1)
		if World.is_solid_cell(cell):
			continue
		if not World.is_solid_cell(Vector2i(x, World.surface[x])):
			continue
		if World.light_at(cell) > max_light:
			continue
		return cell
	return Vector2i(-1, -1)


## Направление, в котором от героя видно (как видит фантом) и есть свободное место.
func clear_direction(dist: float) -> Vector2:
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var p: Vector2 = player.global_position + d * dist
		if World.is_solid_cell(World.world_to_cell(p)):
			continue
		if _los_clear(player.global_position, p):
			return d
	return Vector2(1, 0)


## То же, но строго: если ни в одну сторону не видно — ноль, а не «на всякий случай».
func clear_direction_strict(dist: float) -> Vector2:
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var p: Vector2 = player.global_position + d * dist
		if World.is_solid_cell(World.world_to_cell(p)):
			continue
		if _los_clear(player.global_position, p):
			return d
	return Vector2.ZERO


## Прямая видимость между точками — как у фантома.
func _los_clear(a: Vector2, b: Vector2) -> bool:
	var from: Vector2i = World.world_to_cell(a)
	var to: Vector2i = World.world_to_cell(b)
	var steps: int = maxi(absi(to.x - from.x), absi(to.y - from.y))
	if steps <= 0:
		return true
	for i in range(1, steps):
		var t: float = float(i) / float(steps)
		var cx: int = int(round(lerpf(float(from.x), float(to.x), t)))
		var cy: int = int(round(lerpf(float(from.y), float(to.y), t)))
		if World.is_solid_cell(Vector2i(cx, cy)):
			return false
	return true
