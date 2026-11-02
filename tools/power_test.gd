extends SceneTree
class_name PowerTest
## Регрессионные тесты индекса источников питания (issue #11, после PR #10).
##
## PR #10 заменил перебор всех машин мира на индекс источников питания:
## `Game.is_powered()` спрашивает только генераторы. Индекс сам следит за
## составом `World.machines` и пересобирается при рассинхроне:
##   * размер `World.machines` изменился — пересборка сразу (O(1));
##   * раз в `POWER_VERIFY_EVERY` (32) вызовов — сверка поимённо, ловит
##     случай «сняли ТЭЦ и тут же поставили конвейер» (число машин не
##     изменилось, а источник сменился).
##
## Без этих тестов тихо ломается ровно то, ради чего индекс и делался:
## игрок ставит ТЭЦ, а буры не работают.
##
## Отдельный запуск:
##   godot --headless --path . --script res://tools/power_test.gd -- --seed=31337
## В составе общего прогона те же самые проверки вызывает tools/test_runner.gd
## (секция «== Индекс питания ==») — общий код, без дублирования.
##
## Внимание: файл запускается как главный цикл движка (--script), а в этом
## режиме глобальные имена автозагрузок (World/Game/DB/UI) на этапе компиляции
## ещё недоступны — поэтому все узлы берём через get_node().

# --------------------------------------------------------------- КОНСТАНТЫ
## Радиус ТЭЦ в клетках (CoalGen.power_radius). В пикселях — 8 * 16 = 128.
const GEN_RADIUS: float = 8.0
## Сколько раз подряд спрашиваем is_powered(), пока ждём сверку индекса.
## Game.POWER_VERIFY_EVERY == 32, поэтому 64 — с запасом.
const SYNC_CALLS: int = 64
## Насколько далеко (в клетках) площадка теста должна быть от чужих
## генераторов: иначе их зона питания «накрыла» бы наши проверки.
const GEN_CLEARANCE: float = 16.0
## Шаг фаз проверки (машина состояний).
enum {
	ST_SETUP = 1,
	ST_ZONE,
	ST_NO_FUEL,
	ST_REMOVE,
	ST_SWAP,
	ST_SWAP_WAIT,
	ST_REGEN,
	ST_REGEN_WAIT,
	ST_REGEN2,
	ST_DONE,
}


## --------------------------------------------------------------------- исполнитель
class Runner extends Node:
	## Узел, который выполняет проверки. Живёт в дереве сцены и сам себя
	## добавляет по таймеру: шаги с паузами по реальному времени (в headless
	## частота кадров не гарантирована, а симуляция идёт по delta).
	var host: Node = null          ## кто-то снаружи (test_runner)
	var scene: Node = null
	# Типы узлов намеренно не указаны: в режиме --script статическая ссылка на
	# class_name заставила бы компилировать их на старте, когда имена
	# автозагрузок ещё не зарегистрированы. Поэтому всё через get_node().
	var world = null               ## узел автозагрузки World
	var game = null                ## узел автозагрузки Game

	var checks: int = 0
	var fails: int = 0
	var step: int = 0
	var done: bool = false

	var _wait_until_ms: int = 0
	var _gen_cell: Vector2i = Vector2i.ZERO
	var _in_cell: Vector2i = Vector2i.ZERO
	var _out_cell: Vector2i = Vector2i.ZERO
	var _gen: Node = null
	var _in_machine: Node = null
	var _out_machine: Node = null
	var _state0: int = 0


	func _init(p_host: Node = null) -> void:
		host = p_host


	## Запуск: main_scene — корень сцены игры (у него есть player).
	func start(main_scene: Node) -> void:
		scene = main_scene
		print("== Индекс питания ==")
		_next(ST_SETUP, 0.2)


	func _ok(label: String, cond: bool, extra: String = "") -> void:
		checks += 1
		if cond:
			print("  OK   %s %s" % [label, extra])
		else:
			fails += 1
			print("  FAIL %s %s" % [label, extra])


	func _next(s: int, secs: float = 0.1) -> void:
		step = s
		_wait_until_ms = Time.get_ticks_msec() + int(secs * 1000.0)


	func _process(_delta: float) -> void:
		if done:
			return
		if Time.get_ticks_msec() < _wait_until_ms:
			return
		match step:
			ST_SETUP: _s_setup()
			ST_ZONE: _s_zone()
			ST_NO_FUEL: _s_no_fuel()
			ST_REMOVE: _s_remove()
			ST_SWAP: _s_swap()
			ST_SWAP_WAIT: _s_swap_wait()
			ST_REGEN: _s_regen()
			ST_REGEN_WAIT: _s_regen_wait()
			ST_REGEN2: _s_regen2()
			_: _finish()


	# ------------------------------------------------------------------ помощники

	## Точка мира в центре клетки.
	func _pos(cell: Vector2i) -> Vector2:
		return world.cell_to_world(cell)


	## Есть ли питание в точке (обёртка над Game.is_powered).
	func _powered_at(p: Vector2) -> bool:
		return bool(game.is_powered(p))


	## Ставит постройку. Статику берём из рантайма — так работает и в
	## отдельном запуске, и в составе общего прогона.
	func _place(kind: String, cell: Vector2i) -> Node:
		var mb: GDScript = load("res://scripts/machines/machine_base.gd")
		mb.place_machine(kind, cell)
		return world.machines.get(cell)


	## Расчищает площадку под постройки: клетки должны быть пустыми.
	func _clear_area(from: Vector2i, to: Vector2i) -> void:
		for x in range(from.x, to.x + 1):
			for y in range(from.y, to.y + 1):
				world.set_tile(x, y, IDs.T.AIR)


	## Клетки машин-генераторов (у них есть радиус питания).
	func _generator_cells() -> Array:
		var out: Array = []
		for cell in world.machines.keys():
			var m = world.machines[cell]
			if m == null or not is_instance_valid(m):
				continue
			var r = m.get("power_radius")
			if (r is float or r is int) and float(r) > 0.0:
				out.append(cell)
		return out


	## Выбирает площадку для теста так, чтобы её не накрывала зона питания
	## чужого генератора (в общем прогоне ТЭЦ уже стоят).
	func _pick_area() -> Vector2i:
		var gens: Array = _generator_cells()
		var bx: int = world.beacon_cell.x
		var base: int = world.beacon_cell.y
		var cands: Array = [
			Vector2i(bx - 80, base + 6),
			Vector2i(bx + 80, base + 6),
			Vector2i(40, base + 6),
			Vector2i(bx - 80, base + 20),
			Vector2i(bx + 80, base + 20),
			Vector2i(40, base + 20),
		]
		for c in cands:
			var far: Vector2i = c + Vector2i(12, 0)
			var ok: bool = true
			for g in gens:
				if Vector2(g - far).length() < GEN_CLEARANCE:
					ok = false
					break
			if ok:
				return c
		return cands[0]


	# ------------------------------------------------------------------ проверки

	func _s_setup() -> void:
		world = get_tree().root.get_node("World")
		game = get_tree().root.get_node("Game")
		_ok("автозагрузка World на месте", world != null)
		_ok("автозагрузка Game на месте", game != null)
		if world == null or game == null:
			_finish()
			return
		# Тест перегенерирует мир — игрок в этот момент может оказаться
		# в породе. Делаем его бессмертным на время прогона и возвращаем
		# состояние игры как было.
		var player = scene.get("player")
		if player:
			player.invuln = 1.0e9
		_state0 = int(game.state)
		# Площадка — подальше от чужих генераторов, чтобы их зона питания
		# не влияла на проверки.
		_gen_cell = _pick_area()
		_in_cell = _gen_cell + Vector2i(3, 0)     ## внутри радиуса (3 клетки)
		_out_cell = _gen_cell + Vector2i(12, 0)   ## за радиусом (12 клеток)
		_clear_area(_gen_cell - Vector2i(2, 2), _out_cell + Vector2i(2, 2))
		_gen = _place("CoalGen", _gen_cell)
		_ok("ТЭЦ поставлена", _gen != null, str(_gen_cell))
		if _gen:
			_gen.add_fuel(3)
		_in_machine = _place("Smelter", _in_cell)
		_out_machine = _place("Smelter", _out_cell)
		_ok("плавильня в зоне питания поставлена", _in_machine != null, str(_in_cell))
		_ok("плавильня за зоной питания поставлена", _out_machine != null, str(_out_cell))
		# Ждём, пока CoalGen выставит power_active, а машины опросят питание
		# (MachineBase.POWER_CHECK_INTERVAL == 0.25 с).
		_next(ST_ZONE, 1.2)


	func _s_zone() -> void:
		var radius_px: float = GEN_RADIUS * float(world.TILE)
		var gp: Vector2 = _gen.global_position if _gen else _pos(_gen_cell)
		_ok("питание есть в самой ТЭЦ", _powered_at(gp))
		_ok("питание есть в радиусе", _powered_at(_pos(_in_cell)),
				"расстояние %d px, радиус %d px" % [int(gp.distance_to(_pos(_in_cell))), int(radius_px)])
		_ok("питания нет за радиусом", not _powered_at(_pos(_out_cell)),
				"расстояние %d px, радиус %d px" % [int(gp.distance_to(_pos(_out_cell))), int(radius_px)])
		# Граница радиуса включительно: ровно на радиусе — питание есть.
		_ok("на границе радиуса питание есть", _powered_at(gp + Vector2(radius_px, 0.0)))
		_ok("чуть за радиусом питания нет", not _powered_at(gp + Vector2(radius_px + 1.0, 0.0)))
		# Постройки: потребитель внутри зоны получает питание, за зоной — нет.
		_ok("постройка в зоне под питанием", _in_machine != null and bool(_in_machine.powered))
		_ok("постройка за зоной без питания", _out_machine != null and not bool(_out_machine.powered))
		_next(ST_NO_FUEL)


	func _s_no_fuel() -> void:
		# ТЭЦ без угля: power_active == false → питания нет.
		_gen.fuel = 0.0
		_gen.power_active = false
		_ok("ТЭЦ без угла не даёт питания", not _powered_at(_pos(_in_cell)))
		# И наоборот: с углом — даёт.
		_gen.add_fuel(3)
		_gen.power_active = true
		_ok("ТЭЦ с углом даёт питание", _powered_at(_pos(_in_cell)))
		_next(ST_REMOVE)


	func _s_remove() -> void:
		# ТЭЦ снята из мира: число машин изменилось → индекс пересобирается
		# сразу, на следующем же вызове is_powered().
		var before: int = world.machines.size()
		world.machines.erase(_gen_cell)
		_ok("ТЭЦ убрана из мира", world.machines.size() == before - 1,
				"машин было %d, стало %d" % [before, world.machines.size()])
		_ok("после снятия ТЭЦ питания нет", not _powered_at(_pos(_in_cell)))
		_ok("после снятия ТЭЦ зона не питается даже у самой ТЭЦ",
				not _powered_at(_pos(_gen_cell)))
		_next(ST_SWAP)


	func _s_swap() -> void:
		# «Сняли одну машину, поставили другую» — число машин не изменилось,
		# поэтому проверка размера молчит, и индекс приводится в соответствие
		# только поимённой сверкой (раз в 32 вызова).
		# Ставим новую ТЭЦ и ещё одну постройку рядом.
		_gen = _place("CoalGen", _gen_cell)
		if _gen:
			_gen.add_fuel(3)
			_gen.power_active = true
		var spare_cell: Vector2i = _gen_cell + Vector2i(2, 2)
		_place("Chest", spare_cell)
		# Синхронизируем индекс с миром: после поставки сундука число машин
		# разошлось с тем, под что индекс собирался, — следующий вызов
		# is_powered() пересоберёт индекс. Это нужно сделать ДО обмена:
		# иначе проверка размера сработала бы раньше поимённой сверки и
		# нужный случай («число машин не изменилось») не проверялся бы.
		_powered_at(_pos(_gen_cell))
		var size_before: int = world.machines.size()
		# Меняем ТЭЦ на сундук: количество машин возвращается к прежнему.
		# Важно: между erase и place не должно пройти ни одного кадра —
		# иначе сработала бы проверка размера, и сверка поимённо не
		# проверялась бы.
		world.machines.erase(_gen_cell)
		var swapped: Node = _place("Chest", _gen_cell)
		_ok("ТЭЦ заменена другой постройкой (число машин не изменилось)",
				swapped != null and world.machines.size() == size_before,
				"машин %d → %d" % [size_before, world.machines.size()])
		# Пока сверка не сработала, индекс ещё считает снятую ТЭЦ источником.
		# Ждём, когда сверка пройдёт.
		_next(ST_SWAP_WAIT, 0.05)


	func _s_swap_wait() -> void:
		# Сверка индекса идёт раз в POWER_VERIFY_EVERY (32) вызовов is_powered,
		# поэтому опрашиваем с запасом и ждём, когда ответ станет верным.
		var became_false: bool = false
		var calls: int = 0
		while calls < SYNC_CALLS:
			calls += 1
			if not _powered_at(_pos(_in_cell)):
				became_false = true
				break
		_ok("индекс приведён в соответствие после замены машины", became_false,
				"вызовов is_powered: %d" % calls)
		_ok("после сверки питания у снятой ТЭЦ нет", not _powered_at(_pos(_in_cell)))
		_next(ST_REGEN)


	func _s_regen() -> void:
		# Мир перегенерирован: старые машины и источники питания исчезают.
		var seed_used: int = int(world.world_seed)
		world.generate(seed_used)
		# Сундуки-тайники руин (#35) ставит сама генерация — их не считаем.
		_ok("после перегенерации машин в мире нет", world.machines.size() == world.ruin_caches.size(),
				"машин %d, тайников руин %d" % [world.machines.size(), world.ruin_caches.size()])
		_ok("после перегенерации питания нет нигде", not _powered_at(_pos(_in_cell)))
		_ok("после перегенерации старый источник не питает",
				not _powered_at(_pos(_gen_cell)))
		# Ставим новую ТЭЦ — питание должно появиться только от неё.
		_clear_area(_gen_cell - Vector2i(2, 2), _out_cell + Vector2i(2, 2))
		_gen = _place("CoalGen", _gen_cell)
		_ok("новая ТЭЦ после перегенерации поставлена", _gen != null, str(_gen_cell))
		if _gen:
			_gen.add_fuel(3)
		_next(ST_REGEN_WAIT, 1.0)


	func _s_regen_wait() -> void:
		# Ждём, пока CoalGen выставит power_active = true.
		_next(ST_REGEN2, 0.2)


	func _s_regen2() -> void:
		var active: bool = false
		if _gen != null and is_instance_valid(_gen):
			active = bool(_gen.power_active)
		_ok("новая ТЭЦ питает свою зону", _powered_at(_pos(_in_cell)),
				"power_active=%s" % str(active))
		_ok("за радиусом новой ТЭЦ питания нет", not _powered_at(_pos(_out_cell)))
		_next(ST_DONE)


	func _finish() -> void:
		# Возвращаем состояние игры: тест перегенерировал мир, и игрок мог
		# погибнуть в новом рельефе — это артефакт теста, а не регрессия.
		if game != null:
			game.state = _state0
		done = true
		step = 0


# ------------------------------------------------------------- отдельный запуск

var _runner: Node = null
var _scene: Node = null
var _started: bool = false
var _seed_value: int = 31337


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			_seed_value = int(a.substr(7))


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		# Фиксированный сид: сцена должна быть воспроизводимой.
		seed(_seed_value)
		_scene = load("res://scenes/main.tscn").instantiate()
		root.add_child(_scene)
		current_scene = _scene
		_runner = Runner.new(null)
		root.add_child(_runner)
		_runner.start(_scene)
		return false
	if _runner == null:
		return false
	if _runner.done:
		print("")
		print("ИТОГ: проверок %d, провалов %d" % [_runner.checks, _runner.fails])
		quit(1 if _runner.fails > 0 else 0)
		return true
	return false
