class_name Player
extends Node2D
## Капсула-член экипажа: копает, строит, чинит, прячется в вентиляции.

signal died
signal stats_changed

const SIZE: Vector2 = Vector2(12.0, 22.0)
const SPEED: float = 168.0
const SPRINT_SPEED: float = 248.0
const ACCEL: float = 1500.0
const FRICTION: float = 1900.0
const JUMP_VELOCITY: float = -305.0
const GRAVITY: float = 900.0
const MAX_FALL: float = 520.0
const REACH: float = 5.6 * 16.0
const MAX_HP: float = 100.0

# ------------------------------------------------ ОЩУЩЕНИЕ УПРАВЛЕНИЯ
## Койот-тайм: сколько после схода с края ещё можно нажать прыжок, с.
const COYOTE_TIME: float = 0.10
## Буфер прыжка: сколько нажатие живёт в ожидании приземления, с.
const JUMP_BUFFER: float = 0.12
## Заморозка ввода после урона, с. Короткая — игра остаётся управляемой.
const HIT_STUN: float = 0.12
## Длительность красной вспышки корпуса после урона, с.
const HIT_FLASH: float = 0.30
## Длительность трясучки камеры после урона, с.
const HIT_SHAKE: float = 0.22
## Минимальный интервал между шагами, с. Отсекает «пулемёт» на бегу.
const STEP_MIN_GAP: float = 0.26
## Порог скорости, ниже которого игрок считается стоящим: шаги и шум молчат.
const MOVE_EPS: float = 12.0

# ----------------------------------------------------------- ШУМ
## Шум ходьбы: ниже порога фантома (28) — шаги сами по себе не выдают.
const NOISE_WALK: float = 14.0
## Шум бега: сравнимо с копкой (46), но тише — бег выдаёт, а не «кричит».
const NOISE_RUN: float = 40.0
## Скорость набора/спада собственного шума, единиц в секунду.
const NOISE_RAMP: float = 70.0

var hp: float = MAX_HP
var inv: Inventory
var vel: Vector2 = Vector2.ZERO
var on_ground: bool = false
var facing: int = 1
var mining_progress: float = 0.0
var mining_cell: Vector2i = Vector2i(-1, -1)
var building_cell: Vector2i = Vector2i(-1, -1)
var task_progress: float = 0.0
var hiding: bool = false
## Сколько ещё можно сидеть в вентиляции, с (тикает от Balance.HIDE_MAX к нулю).
var hide_timer: float = 0.0
## Через сколько секунд можно снова залезть в вентиляцию (Balance.HIDE_COOLDOWN).
var hide_cd: float = 0.0
var noise: float = 0.0
var invuln: float = 0.0
var slash_cd: float = 0.0
var emp_cd: float = 0.0
var emp_max: float = 8.0
var walk_anim: float = 0.0
var camera: Camera2D
## Зум камеры (колесо, +/−, щипок на телефоне); есть только у своего героя, как и камера.
var view_zoom: ViewZoom = null
var dead: bool = false
var _regen: float = 0.0
var _breath: float = 0.0
var _place_cd: float = 0.0

# Тестовый ввод: сценарии подменяют отдельные вводы.
# Пустой словарь = обычная игра, всё читается из Input.
var test_input: Dictionary = {}
#   "keys"          -> Dictionary[int -> bool]   состояние клавиш
#   "mouse"         -> Vector2                    мировая позиция "курсора"
#   "mouse_buttons" -> Dictionary[int -> bool]   состояние кнопок мыши

# Сенсорный ввод (#81): TouchControls пишет сюда в том же формате, что test_input.
# Клавиши складываются с клавиатурой (ИЛИ). "mouse_buttons" и "mouse" есть, только
# пока палец на экране, и тогда заменяют мышь целиком: эмулированный из касания
# «клик» под джойстиком не должен копать мир. test_input сценария главнее.
var touch_input: Dictionary = {}

var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _jump_prev: bool = false
var _stun: float = 0.0
var _hit_flash: float = 0.0
var _shake: float = 0.0
var _noise_level: float = 0.0
var _step_gap: float = 0.0
var _mine_fx_t: float = 0.0
## Клавиши прошлого кадра: V и E срабатывают по фронту нажатия.
var _v_prev: bool = false
var _e_prev: bool = false
## Пауза между единицами хлама при ремонте с зажатой E, с.
var _repair_cd: float = 0.0
## Ремонт: одна единица хлама раз в REPAIR_GAP, пока E зажата.
const REPAIR_GAP: float = 0.3
## Это нажатие E уже отработало (терминал, ремонт): до отпускания E оно не
## открывает сундук рядом и не дёргает рубильник.
var _e_used: bool = false
## Разбор постройки: сколько E держат (с) и в какой клетке.
var _dismantle_t: float = 0.0
var _dismantle_cell: Vector2i = Vector2i(-1, -1)


func _ready() -> void:
	inv = Inventory.new(36, hotbar_from_profile())
	if not _net_view():   # СЕТЬ (ADR-002): камера только у своего героя
		z_index = 5
		return
	camera = Camera2D.new()
	camera.zoom = Vector2(ViewZoom.DEFAULT, ViewZoom.DEFAULT)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 9.0
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = World.W * World.TILE
	camera.limit_bottom = World.H * World.TILE
	camera.limit_smoothed = true
	add_child(camera)
	camera.make_current()
	view_zoom = ViewZoom.new()
	view_zoom.camera = camera
	add_child(view_zoom)   # зум из профиля — в своём _ready
	z_index = 5


func _physics_process(delta: float) -> void:
	if dead:
		return
	if net_role == NetRole.PUPPET:   # СЕТЬ (ADR-002): марионетку двигает NetPlayers
		_net_puppet_tick(delta)
		return
	var dt: float = delta
	invuln = maxf(0.0, invuln - dt)
	slash_cd = maxf(0.0, slash_cd - dt)
	emp_cd = maxf(0.0, emp_cd - dt)
	_stun = maxf(0.0, _stun - dt)
	_hit_flash = maxf(0.0, _hit_flash - dt)
	_step_gap = maxf(0.0, _step_gap - dt)
	noise = maxf(0.0, noise - dt * 40.0)
	_repair_cd = maxf(0.0, _repair_cd - dt)
	if net_role != NetRole.OWNER:   # СЕТЬ (ADR-002): укрытие и HP героя клиента считает хост
		_tick_hide(dt)
		_regen += dt
		if _regen > 6.0 and hp < MAX_HP:
			_regen = 0.0
			hp = minf(MAX_HP, hp + 6.0)

	var sprint: bool = _key(KEY_SHIFT)
	if net_role != NetRole.PROXY:   # СЕТЬ (ADR-002): прокси не интегрирует — позиция из сети
		_integrate(dt, sprint)

	# Урон от лавы
	var here: int = World.get_tile_v(World.world_to_cell(global_position))
	if here == IDs.T.LAVA:
		damage(18.0 * dt, Vector2.ZERO)

	var prev_phase: float = walk_anim
	walk_anim += absf(vel.x) * dt * 0.08
	_breath += dt * (2.0 if absf(vel.x) > 10.0 else 1.0)

	# Шаги: звук по фазе шага, громче и выше на бегу. Стоящий игрок молчит.
	_update_step(prev_phase, walk_anim, sprint)

	# Шум: покой — тишина, ходьба — тихо, бег — громко (сравнимо с копкой).
	var noise_target: float = 0.0
	if not hiding and absf(vel.x) > MOVE_EPS:
		noise_target = NOISE_RUN if sprint else NOISE_WALK
	_noise_level = move_toward(_noise_level, noise_target, NOISE_RAMP * dt)
	if noise_target > 0.0:
		# Идём или бежим: держим шум на своём уровне.
		noise = maxf(noise, _noise_level)
	else:
		# Стоим: шум гаснет быстрее обычного затухания.
		noise = maxf(0.0, noise - dt * NOISE_RAMP)

	_update_shake(dt)

	_handle_input(dt)
	queue_redraw()


## Ввод движения → скорость → World.move_body (свой герой; прокси хоста не интегрирует).
func _integrate(dt: float, sprint: bool) -> void:
	# Прыжок ловим по фронту нажатия: кладём нажатие в буфер и ждём
	# либо приземления, либо конца койот-тайма.
	var jump_held: bool = _key(KEY_SPACE) or _key(KEY_W) or _key(KEY_UP)
	if jump_held and not _jump_prev:
		_jump_buffer = JUMP_BUFFER
	_jump_prev = jump_held
	_jump_buffer = maxf(0.0, _jump_buffer - dt)

	var move_dir: float = 0.0
	if not hiding and _stun <= 0.0:
		if _key(KEY_A) or _key(KEY_LEFT):
			move_dir -= 1.0
		if _key(KEY_D) or _key(KEY_RIGHT):
			move_dir += 1.0

	var target_speed: float = SPRINT_SPEED if sprint else SPEED
	if hiding:
		target_speed = SPEED * 0.4

	# Горизонталь
	if absf(move_dir) > 0.01:
		vel.x = move_toward(vel.x, move_dir * target_speed, ACCEL * dt)
		facing = 1 if move_dir > 0.0 else -1
	else:
		vel.x = move_toward(vel.x, 0.0, FRICTION * dt)

	# Прыжок: койот-тайм (0.1 с после края) + буфер нажатия (0.12 с).
	# Двойного прыжка нет: после прыжка _coyote обнуляется, а наземлиться
	# можно только на твёрдом.
	if not hiding and _stun <= 0.0 and _jump_buffer > 0.0 and (on_ground or _coyote > 0.0):
		vel.y = JUMP_VELOCITY
		on_ground = false
		_coyote = 0.0
		_jump_buffer = 0.0
		noise = maxf(noise, 20.0)

	# Гравитация
	vel.y = minf(vel.y + GRAVITY * dt, MAX_FALL)

	var res: Dictionary = World.move_body(global_position, vel * dt, SIZE)
	global_position = res["position"]
	if res["hit_y"]:
		if vel.y > 0.0:
			on_ground = true
		vel.y = 0.0
	if res["hit_x"]:
		vel.x = 0.0
	if not res["hit_y"]:
		on_ground = false

	# Койот-тайм: пока стоим на земле — окно живёт, слетели — гаснет.
	if on_ground:
		_coyote = COYOTE_TIME
	else:
		_coyote = maxf(0.0, _coyote - dt)


## Короткая трясучка камеры после урона — читается, но не мешает играть.
func _update_shake(dt: float) -> void:
	if camera == null:   # СЕТЬ (ADR-002): у чужого героя камеры нет
		_shake = 0.0
		return
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - dt)
		var amp: float = 4.0 * (_shake / HIT_SHAKE)
		camera.offset = Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
	elif camera.offset != Vector2.ZERO:
		camera.offset = Vector2.ZERO


## Звук шага: фаза шага — каждый переход через PI в walk_anim.
## Минимальный интервал гасит «пулемёт» на бегу.
func _update_step(prev_phase: float, phase: float, sprint: bool) -> void:
	if absf(vel.x) <= MOVE_EPS:
		return
	if int(prev_phase / PI) == int(phase / PI):
		return
	if _step_gap > 0.0:
		return
	_step_gap = STEP_MIN_GAP
	if sprint:
		_sfx_self("step", -11.0, randf_range(1.10, 1.24))
	else:
		_sfx_self("step", -19.0, randf_range(0.86, 1.00))


func _handle_input(dt: float) -> void:
	if dead:
		return
	# Выбор слота хотбара. Клавиши 1–0 всегда читаются (пакет ввода несёт 10 бит),
	# но ячейки за hotbar_size не выбираются: при хотбаре 6 цифры 7–0 ничего не делают (#161).
	for i in 9:
		if i < inv.hotbar_size and _key(KEY_1 + i):
			inv.selected = i
			break
	if inv.hotbar_size > 9 and _key(KEY_0):
		inv.selected = 9

	if net_role == NetRole.OWNER:   # СЕТЬ (ADR-002): действия своего героя клиента — у хоста
		return
	if _ui_blocking():
		return

	var mouse: Vector2 = _mouse_pos()
	var cell: Vector2i = World.world_to_cell(mouse)
	building_cell = cell

	var in_reach: bool = mouse.distance_to(global_position) <= REACH

	if _mouse_down(MOUSE_BUTTON_LEFT):
		if in_reach:
			if _slash_at(mouse):
				return
			_do_mining(cell, dt)
	else:
		mining_progress = 0.0
		mining_cell = Vector2i(-1, -1)

	if _mouse_down(MOUSE_BUTTON_RIGHT) and in_reach:
		var fresh: bool = _place_cd == 0.0   # первый кадр нажатия: поворот — только по нему
		_place_cd -= dt
		if _place_cd <= 0.0:
			_place_cd = 0.16
			_do_place(cell, fresh)
	else:
		_place_cd = 0.0   # новое нажатие ставит сразу: короткий клик или тап не теряется

	# Q — импульс
	if _key(KEY_Q) and emp_cd <= 0.0:
		_empulse()

	# E — взаимодействие
	var e_down: bool = _key(KEY_E)
	if e_down:
		_do_interact(dt, not _e_prev)
	else:
		task_progress = 0.0
		_e_used = false
		_dismantle_t = 0.0
	_e_prev = e_down

	# V — вентиляция (по фронту: зажатая V не дёргает укрытие каждый кадр)
	var v_down: bool = _key(KEY_V)
	if v_down and not _v_prev:
		_toggle_hide()
	_v_prev = v_down


# ------------------------------------------------- ШОВ ТЕСТОВОГО ВВОДА
## Состояние клавиши. Если сценарий подменил ввод — читаем его,
## иначе — обычный Input. Читается каждый кадр, ничего не кэшируется.
func _key(code: int) -> bool:
	if test_input.has("keys"):
		var k: Dictionary = test_input["keys"]
		if k.has(code):
			return bool(k[code])
	if touch_input.has("keys") and bool(touch_input["keys"].get(code, false)):
		return true
	return Input.is_key_pressed(code)


## Состояние кнопки мыши (см. _key).
func _mouse_down(btn: int) -> bool:
	if test_input.has("mouse_buttons"):
		var m: Dictionary = test_input["mouse_buttons"]
		if m.has(btn):
			return bool(m[btn])
	if touch_input.has("mouse_buttons"):
		return bool(touch_input["mouse_buttons"].get(btn, false))
	return Input.is_mouse_button_pressed(btn)


## Позиция «курсора» в мире (см. _key).
func _mouse_pos() -> Vector2:
	if test_input.has("mouse"):
		var m: Vector2 = test_input["mouse"]
		return m
	if touch_input.has("mouse"):
		var t: Vector2 = touch_input["mouse"]
		return t
	return get_global_mouse_position()


func _slash_at(mouse: Vector2) -> bool:
	if slash_cd > 0.0:
		return false
	for p in get_tree().get_nodes_in_group("phantom"):
		if p.global_position.distance_to(mouse) < 20.0:
			slash_cd = 0.45
			_sfx_here("hit", -6.0, 1.4)
			p.take_damage(38.0, global_position)
			_make_slash_fx(mouse)
			return true
	return false


func _empulse() -> void:
	emp_cd = emp_max
	_sfx_here("power", -8.0)
	_fx(NetCodec.Fx.RING_EMP, global_position)
	for p in get_tree().get_nodes_in_group("phantom"):
		if p.global_position.distance_to(global_position) < 130.0:
			p.apply_stun(3.0)
			p.take_damage(10.0, global_position)


func _do_mining(cell: Vector2i, dt: float) -> void:
	var tid: int = World.get_tile_v(cell)
	if tid == IDs.T.AIR:
		mining_progress = 0.0
		return
	if DB.tile_hard(tid) > 100.0:
		return
	if mining_cell != cell:
		mining_cell = cell
		mining_progress = 0.0
	mining_progress += dt / maxf(0.15, DB.tile_hard(tid))
	_mine_fx_t += dt
	noise = maxf(noise, 46.0)
	if fmod(mining_progress, 0.35) < dt:
		_sfx_here("mine", -14.0, randf_range(0.85, 1.2))
		_fx(NetCodec.Fx.CHIP_TILE, World.cell_to_world(cell), tid)
	if mining_progress >= 1.0:
		mining_progress = 0.0
		_break_tile(cell)


func _break_tile(cell: Vector2i) -> void:
	var tid: int = World.get_tile_v(cell)
	var drop: int = DB.tile_drop(tid)
	World.set_tile(cell.x, cell.y, IDs.T.AIR)
	# Сломан ствол или ветка — крона, оставшаяся без опоры, падает.
	if tid == IDs.T.TREE or tid == IDs.T.LEAVES:
		World.fix_floating_near(cell)
	_sfx_here("break", -8.0, randf_range(0.9, 1.15))
	_fx(NetCodec.Fx.CHIP_TILE, World.cell_to_world(cell), tid)
	Game.stats_mined += 1
	if drop != IDs.I.NONE:
		spawn_item(drop, 1, World.cell_to_world(cell))


func _do_place(cell: Vector2i, fresh: bool = true) -> void:
	# ПКМ по поворотной постройке (конвейер, манипулятор, блоки луча) — повернуть.
	# Удержание не крутит по кругу: один поворот на одно нажатие.
	var turnable: MachineBase = World.machines.get(cell)
	if turnable != null and turnable.can_turn:
		if fresh:
			turnable.turn()
		_sfx_here("place", -14.0, 1.3)
		return
	var stack: ItemStack = inv.selected_stack()
	if stack.is_empty():
		return
	var place: String = DB.item_place(stack.id)
	if place == "":
		return
	if not _place_allowed(cell):
		return
	if place.begins_with("tile:"):
		var tid: int = int(place.substr(5))
		if not World.tile_place_ok(cell, tid):   # решётка — только на вентиляцию (#31)
			_notify("Решётку ставят на вентиляцию.", Color(1.0, 0.6, 0.5))
			return
		World.set_tile(cell.x, cell.y, tid)
		inv.remove_at(inv.selected, 1)
		_sfx_here("place", -10.0)
	elif place.begins_with("machine:"):
		# «machine:» — 8 символов, вид машины начинается с девятого.
		var kind: String = place.substr(8)
		if MachineBase.place_machine(kind, cell):
			inv.remove_at(inv.selected, 1)
			_sfx_here("place_machine", -8.0)
			_auto_orient(cell, kind)
		else:
			_notify("Сюда нельзя поставить.", Color(1.0, 0.6, 0.5))


## Конвейер сразу встаёт в сторону ближайшей принимающей постройки.
func _auto_orient(cell: Vector2i, kind: String) -> void:
	if kind != "Belt" or not World.belts.has(cell):
		return
	var b: Belt = World.belts[cell]
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
	for i in 4:
		var n: Vector2i = cell + dirs[i]
		if World.belts.has(n) or World.machines.has(n):
			b.dir = i
			return
	b.dir = 0


## Сюда можно поставить блок или машину: клетка свободна (и машины в ней нет), герой
## не мешает. Сенсорный прицел (TouchControls, #149) выбирает по ней клетку постройки.
func can_place_at(cell: Vector2i) -> bool:
	return not World.machines.has(cell) and _place_allowed(cell)


func _place_allowed(cell: Vector2i) -> bool:
	var tid: int = World.get_tile_v(cell)
	if tid != IDs.T.AIR and not DB.is_liquid(tid):
		return false
	var r: Rect2 = Rect2(Vector2(cell.x * World.TILE, cell.y * World.TILE), Vector2(World.TILE, World.TILE))
	var pr: Rect2 = Rect2(global_position - SIZE * 0.5, SIZE)
	if r.intersects(pr):
		return false
	return true


# ------------------------------------------------- ЦЕЛЬ E (#116)
## Раньше E перебирала объекты жёстким порядком «терминал → … → сундук», и
## терминал руины без питания в ~37 px от тайника забирал E: сундук рядом с
## терминалом было не открыть. Теперь цель одна, её выбирает interact_target(),
## и по ней же HUD рисует подсказку и рамку интерактива (V6): рамка всегда на
## том объекте, который сработает по E.

## Радиусы E — от героя до центра объекта, px.
const E_TERMINAL: float = 42.0
const E_BEACON: float = 56.0
const E_MACHINE: float = 40.0      ## ТЭЦ, сундук, манипулятор рядом
const E_STATION: float = 44.0      ## загрузка предмета в станок и ремонт хламом

## Виды цели E (поле "kind" у interact_target()).
const ET_TERMINAL: String = "terminal"          ## терминал под питанием: держать E — задание
const ET_TERMINAL_OFF: String = "terminal_off"  ## без питания: E даёт только «нет питания»
const ET_BEACON: String = "beacon"              ## релей-ядро: держать E
const ET_GENERATOR: String = "generator"        ## уголь в руке — топка, иначе — рубильник
const ET_INSERTER: String = "inserter"          ## предмет в руке — фильтр, пустая рука — сброс
const ET_CHEST: String = "chest"                ## сундук и тайники руин / небесный тайник
const ET_REPAIR: String = "repair"              ## хлам в руке, машина повреждена
const ET_LOAD: String = "load"                  ## предмет в руке подходит станку
const ET_DISMANTLE: String = "dismantle"        ## разбор постройки (удержание E)

## Сколько секунд держать E над постройкой, чтобы разобрать её (DISMANTLE).
const DISMANTLE_HOLD: float = 0.9

## Клетка цели, по которой копится task_progress: сменилась цель — отсчёт заново.
var _task_cell: Vector2i = Vector2i(-1, -1)


## Цель E: {"kind": ET_*, "cell": Vector2i, "node": машина или null, "pos": Vector2}.
## Пустой словарь — E сейчас некуда.
## Правило: объект под курсором, если герой до него дотягивается (радиус E
## объекта); иначе — ближайший к герою. Терминал без питания — цель, только
## если он под курсором или строго ближе всего остального (E подскажет «нет
## питания»); при равенстве соседний сундук или ТЭЦ важнее.
## powered — проверка питания терминала (клетка -> bool); HUD передаёт свою,
## с кэшем; по умолчанию — Game.is_powered.
func interact_target(powered: Callable = Callable()) -> Dictionary:
	var pos: Vector2 = global_position
	var aimed: Dictionary = _target_at(building_cell, pos, true, powered)
	if not aimed.is_empty():
		return aimed
	var best: Dictionary = {}
	var best_d: float = INF
	var off: Dictionary = {}
	var off_d: float = INF
	for t in World.terminals:
		var tt: Dictionary = _target_at(t, pos, false, powered)
		if tt.is_empty():
			continue
		var td: float = Vector2(tt["pos"]).distance_to(pos)
		if tt["kind"] == ET_TERMINAL_OFF:
			if td < off_d:
				off_d = td
				off = tt
		elif td < best_d:
			best_d = td
			best = tt
	var bt: Dictionary = _target_at(World.beacon_cell, pos, false, powered)
	if not bt.is_empty() and Vector2(bt["pos"]).distance_to(pos) < best_d:
		best_d = Vector2(bt["pos"]).distance_to(pos)
		best = bt
	# Постройки — только клетки в радиусе E, а не все машины мира.
	var r: int = int(ceil(E_STATION / float(World.TILE))) + 1
	var pc: Vector2i = World.world_to_cell(pos)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c: Vector2i = pc + Vector2i(dx, dy)
			if not World.machines.has(c):
				continue
			var mt: Dictionary = _target_at(c, pos, false, powered, false)
			if mt.is_empty():
				continue
			var md: float = Vector2(mt["pos"]).distance_to(pos)
			if md < best_d:
				best_d = md
				best = mt
	var res: Dictionary = off if off_d < best_d else best
	if not res.is_empty():
		return res
	# Рядом нет ничего с особым действием E — разбор: ближайшая машина.
	return _dismantle_target(pos)


## Цель разбора: ближайшая машина, которую можно снять (пустая рука, не
## кампанийная, сундук — пустой). Это запасной путь: если рядом есть терминал,
## сундук с вещами или станок — E делает обычное дело, разбор — только когда
## игрок целится в машину (aimed) или рядом нет ничего другого.
func _dismantle_target(pos: Vector2) -> Dictionary:
	if not inv.selected_stack().is_empty():
		return {}
	var r: int = int(ceil(E_MACHINE / float(World.TILE))) + 1
	var pc: Vector2i = World.world_to_cell(pos)
	var best: Dictionary = {}
	var best_d: float = INF
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c: Vector2i = pc + Vector2i(dx, dy)
			var m = World.machines.get(c)
			if m == null or not is_instance_valid(m) or m.is_queued_for_deletion():
				continue
			if not _can_dismantle(m):
				continue
			var mp: Vector2 = m.global_position
			var d: float = mp.distance_to(pos)
			if d > E_MACHINE or d >= best_d:
				continue
			best_d = d
			best = {"kind": ET_DISMANTLE, "cell": c, "node": m, "pos": mp,
					"item": MachineBase.machine_item_id(m.kind)}
	return best


## Можно ли снять постройку m и вернуть её в инвентарь: не кампанийная и не
## тайник руин, сундук — пустой (полный сначала открывают).
func _can_dismantle(m) -> bool:
	if m == null or not is_instance_valid(m) or m.is_queued_for_deletion():
		return false
	if bool(m.permanent):
		return false
	if m is Chest and not _chest_empty(m):
		return false
	return true


## Пуст ли сундук (ни одного предмета).
func _chest_empty(m) -> bool:
	var ch = m as Chest
	for s in ch.slots:
		if not s.is_empty():
			return false
	return true


## Что E сделает с объектом в клетке c (пусто — ничего или далеко).
## aimed — клетка под курсором: манипулятор тогда достаётся на всю досягаемость.
## allow_dismantle — искать цель разбора (бур, конвейер…): в поиске «ближайшего»
## разбор не участвует, чтобы не отбирать E у сундука и терминала.
func _target_at(c: Vector2i, pos: Vector2, aimed: bool, powered: Callable,
		allow_dismantle: bool = true) -> Dictionary:
	if c.x < 0:
		return {}
	var m = World.machines.get(c)
	if m != null and is_instance_valid(m) and not m.is_queued_for_deletion():
		var mp: Vector2 = m.global_position
		var d: float = mp.distance_to(pos)
		var sel: ItemStack = inv.selected_stack()
		var tg: Dictionary = {"cell": c, "node": m, "pos": mp}
		if not sel.is_empty() and sel.id == IDs.I.SCRAP and m.hp < m.max_hp and d < E_STATION:
			tg["kind"] = ET_REPAIR
		elif m is Generator and d < E_MACHINE:
			tg["kind"] = ET_GENERATOR
		elif m is Inserter and (d < E_MACHINE or (aimed and d <= REACH)):
			tg["kind"] = ET_INSERTER
		elif m is Chest and d < E_MACHINE and not _chest_empty(m):
			tg["kind"] = ET_CHEST
		elif not sel.is_empty() and d <= E_STATION and not (m is Belt or m is Chest or m is Generator) \
				and m.input_accepts(sel.id):
			tg["kind"] = ET_LOAD
		elif allow_dismantle and d < E_MACHINE and sel.is_empty() and _can_dismantle(m):
			# Разбор: своего действия E у машины нет (бур, плавильня, сборщик,
			# конвейер) или сундук пуст.
			tg["kind"] = ET_DISMANTLE
			tg["item"] = MachineBase.machine_item_id(m.kind)
		else:
			return {}
		return tg
	if c == World.beacon_cell:
		var bp: Vector2 = World.cell_to_world(c)
		if bp.distance_to(pos) < E_BEACON:
			return {"kind": ET_BEACON, "cell": c, "node": null, "pos": bp}
		return {}
	if World.terminals.has(c):
		var tp: Vector2 = World.cell_to_world(c)
		if tp.distance_to(pos) >= E_TERMINAL:
			return {}
		var on: bool = bool(powered.call(c)) if powered.is_valid() else Game.is_powered(tp)
		return {"kind": ET_TERMINAL if on else ET_TERMINAL_OFF, "cell": c, "node": null, "pos": tp}
	return {}


## E — взаимодействие. fresh — первый кадр нажатия (подсказки — один раз на нажатие).
func _do_interact(dt: float, fresh: bool = true) -> void:
	var tg: Dictionary = interact_target()
	var kind: String = String(tg.get("kind", ""))
	var cell: Vector2i = tg.get("cell", Vector2i(-1, -1))
	# Держать E копит отсчёт только у одной цели: отошёл к другой — заново.
	if (kind != ET_TERMINAL and kind != ET_BEACON) or cell != _task_cell:
		task_progress = 0.0
		_task_cell = cell if kind == ET_TERMINAL or kind == ET_BEACON else Vector2i(-1, -1)
	# Ремонт: E с хламом в хотбаре по повреждённой машине (§ 4.4) — пока E зажата.
	if kind == ET_REPAIR:
		_repair(tg["node"])
		return
	# Нажатие уже отработало (терминал, ремонт): до отпускания E — ничего больше.
	if _e_used:
		return
	match kind:
		ET_TERMINAL_OFF:
			# Терминалы работают только под питанием (ADR-001 § 4.6, #29).
			if fresh:
				_sfx_here("craft", -16.0, 0.6)
				_notify("Терминал: нет питания. Поставьте рядом ТЭЦ или солнечную панель.",
						Color(1.0, 0.7, 0.4))
		ET_TERMINAL:
			task_progress += dt / 2.2
			if task_progress >= 1.0:
				task_progress = 0.0
				_read_terminal(cell)
		ET_BEACON:
			task_progress += dt / 3.0
			if task_progress >= 1.0:
				task_progress = 0.0
				Game.try_finish(self)   # вклад деталей — из своего инвентаря (MP-I, #94)
		ET_GENERATOR, ET_INSERTER:
			# ТЭЦ: уголь — топка, иначе рубильник (#25); манипулятор: фильтр/сброс (#30).
			tg["node"].interact(self)
		ET_CHEST:
			# Сундук — через сетевую обёртку: у прокси окно открывает владелец (MP-G).
			_open_chest(tg["node"])
		ET_LOAD:
			# Станок — закинуть предмет из хотбара.
			var sel: ItemStack = inv.selected_stack()
			var left: int = tg["node"].receive_item(sel.id, sel.count)
			if left < sel.count:
				inv.remove_at(inv.selected, sel.count - left)
				_sfx_here("place", -12.0)
				_notify("Загружено: %s" % DB.item_name(sel.id), Color(0.7, 0.9, 1.0))
	# Разбор постройки (DISMANTLE): удержание E с пустой рукой снимает машину и
	# возвращает её предмет в инвентарь. Отпустил раньше — ничего не разобрано.
	var dm: MachineBase = _dismantle_node(tg, kind)
	if dm != null:
		if cell != _dismantle_cell:
			_dismantle_cell = cell
			_dismantle_t = 0.0
		_dismantle_t += dt
		task_progress = clampf(_dismantle_t / DISMANTLE_HOLD, 0.0, 1.0)
		if _dismantle_t >= DISMANTLE_HOLD:
			_dismantle_t = 0.0
			task_progress = 0.0
			_dismantle(dm)
		return
	_dismantle_t = 0.0
	_dismantle_cell = Vector2i(-1, -1)


## Машина под целью E, которую можно разобрать удержанием E. Полный сундук —
## нет (его сначала открывают); кампанийные постройки — нет.
func _dismantle_node(tg: Dictionary, kind: String) -> MachineBase:
	if kind == ET_CHEST:
		return null
	var node = tg.get("node")
	if not (node is MachineBase):
		return null
	var m: MachineBase = node
	if not is_instance_valid(m) or m.is_queued_for_deletion():
		return null
	if not _can_dismantle(m):
		return null
	if not inv.selected_stack().is_empty():
		return null
	return m


## Разобрать постройку: предмет вернётся в инвентарь (нет места — под ноги).
func _dismantle(m: MachineBase) -> void:
	var item: int = m.dismantle()
	if item == IDs.I.NONE:
		return
	var left: int = inv.add(item, 1)
	if left > 0:
		spawn_item(item, left, global_position)
	_sfx_here("pickup", -10.0, 1.1)
	_notify("Разобрано: %s" % DB.item_name(item), Color(0.8, 0.9, 0.75))


## Терминал отработал: +данные (Game.complete_task), глава журнала этого места.
func _read_terminal(t: Vector2i) -> void:
	var chapter: int = int(World.terminal_chapters.get(t, -1))
	World.terminals.erase(t)
	World.set_tile(t.x, t.y, IDs.T.PANEL)
	_e_used = true
	Game.complete_task()
	if chapter >= 0:
		Tech.read_chapter(chapter)
	_sfx_here("craft", -6.0)
	_net_terminal_read(chapter)   # СЕТЬ (ADR-002 § 4.7): терминал — один раз на команду


## Ремонт хламом: +Balance.REPAIR_PER_SCRAP HP машине-цели E (ET_REPAIR) за
## единицу, пока E зажата — раз в REPAIR_GAP.
func _repair(best: MachineBase) -> void:
	if _repair_cd > 0.0:
		return
	_repair_cd = REPAIR_GAP
	_e_used = true
	best.hp = minf(best.max_hp, best.hp + Balance.REPAIR_PER_SCRAP)
	best.anim = 1.0
	best.queue_redraw()
	inv.remove_at(inv.selected, 1)
	_sfx_here("place", -10.0, 1.2)
	_fx(NetCodec.Fx.CHIP_REPAIR, World.cell_to_world(best.cell))
	_notify("Ремонт: %s %d/%d" % [DB.item_name(MachineBase.machine_item_id(best.kind)),
			int(best.hp), int(best.max_hp)], Color(0.7, 0.95, 0.7))


# ------------------------------------------------- УКРЫТИЕ (ADR-001 § 4.8)
## В вентиляции — не дольше Balance.HIDE_MAX: hide_timer тикает, потом выталкивает.
## Повторно залезть можно через Balance.HIDE_COOLDOWN после выхода (любого).
## Внутри герой неуязвим; после выхода — короткая передышка, не бессрочная.
func _tick_hide(dt: float) -> void:
	if not hiding:
		hide_cd = maxf(0.0, hide_cd - dt)
		return
	hide_timer = maxf(0.0, hide_timer - dt)
	if hide_timer <= 0.0:
		_leave_vent()
		_notify("Вентиляция вытолкнула вас наружу.", Color(1.0, 0.75, 0.5))


func _leave_vent() -> void:
	hiding = false
	hide_timer = 0.0
	hide_cd = Balance.HIDE_COOLDOWN
	invuln = minf(invuln, 0.6)
	_sfx_here("power", -16.0, 0.8)


func _toggle_hide() -> void:
	if hiding:
		_leave_vent()
		return
	for v in World.vents:
		if World.cell_to_world(v).distance_to(global_position) < 40.0:
			if hide_cd > 0.0:
				_notify("Вентиляция ещё не остыла: %d с." % ceili(hide_cd), Color(0.8, 0.8, 0.8))
				return
			if _net_vent_busy(v):   # СЕТЬ (ADR-002 § 4.7): одна вентиляция — один герой
				return
			hiding = true
			hide_timer = Balance.HIDE_MAX
			invuln = Balance.HIDE_MAX + 0.6
			vel = Vector2.ZERO
			_sfx_here("power", -14.0)
			_notify("Вы в вентиляции: %d с, фантомы вас не видят." % int(Balance.HIDE_MAX),
					Color(0.6, 0.9, 1.0))
			return
	_notify("Рядом нет вентиляции.", Color(0.8, 0.8, 0.8))


func spawn_item(item_id: int, count: int, pos: Vector2) -> void:
	var e: ItemEntity = ItemEntity.new()
	e.item_id = item_id
	e.count = count
	e.global_position = pos
	e.z_index = 4
	World.add_world_node(e)


func collect(item_id: int, count: int) -> int:
	var left: int = inv.add(item_id, count)
	if left < count:
		_sfx_here("pickup", -16.0, randf_range(0.95, 1.15))
		stats_changed.emit()
	return left


func damage(amount: float, knock: Vector2) -> void:
	if invuln > 0.0 or dead or not _net_takes_damage():   # СЕТЬ: урон считает хост
		return
	hp -= amount
	invuln = 0.6
	stats_changed.emit()
	vel += knock
	# Локальная реакция: вспышка корпуса, короткая заморозка ввода,
	# лёгкая трясучка камеры. Игра остаётся управляемой.
	_hit_flash = HIT_FLASH
	_stun = HIT_STUN
	_shake = HIT_SHAKE
	_feedback_hit(knock)
	if hp <= 0.0:
		_die()


# ------------------------------------------------- СМЕРТЬ (ADR-001 § 4.8)
## Смерть: хотбар падает мешком на месте смерти, основной инвентарь остаётся.
## Что дальше — респаун или конец забега (--hardcore) — решает main.gd по died.
func _die() -> void:
	hp = 0.0
	dead = true
	hiding = false
	hide_timer = 0.0
	vel = Vector2.ZERO
	task_progress = 0.0
	mining_progress = 0.0
	Game.stats_deaths += 1
	_net_own_bag(drop_hotbar_bag())   # СЕТЬ (ADR-002 § 4.7): мешок — сначала владельцу
	died.emit()


## Высыпать хотбар в мешок (ItemEntity с bag) на месте героя. null — хотбар пуст.
func drop_hotbar_bag() -> ItemEntity:
	var bag: Array = []
	for i in inv.hotbar_size:
		var s: ItemStack = inv.slots[i]
		if s.is_empty():
			continue
		bag.append([s.id, s.count])
		inv.slots[i] = ItemStack.new()
	if bag.is_empty():
		return null
	inv.changed.emit()
	stats_changed.emit()
	var e: ItemEntity = ItemEntity.new()
	e.bag = bag
	e.item_id = int(bag[0][0])
	e.despawn = false
	e.pickup_delay = 1.0
	e.global_position = global_position
	World.add_world_node(e)
	return e


## Респаун в капсуле на базе: полное здоровье, короткая неуязвимость.
func respawn_at(pos: Vector2) -> void:
	global_position = pos
	vel = Vector2.ZERO
	hp = MAX_HP
	dead = false
	hiding = false
	hide_timer = 0.0
	hide_cd = 0.0
	invuln = 2.0
	_stun = 0.0
	_regen = 0.0
	stats_changed.emit()


func _sfx(n: String, v: float = 0.0, p: float = 1.0) -> void:
	_sfx_here(n, v, p)


## Раскладка частей фигуры в локальных координатах героя (issue #58).
## Все части задаются «лицом вправо», а при facing = -1 каждая отражается
## относительно вертикальной оси героя (x = 0): ранец уходит за спину,
## визор, фонарь и рука — вперёд, ноги меняются местами вместе с фазой шага.
## Считает Avatar.layout() (скафандр «Кербер-9», V4/MP-L #97) по виду героя
## и его позе; отдельно от _draw, чтобы anim_test проверял ровно то, что рисуется.
## Ключи — см. Avatar.layout: body, torso, helmet, visor*, arm, glove, backpack,
## tank, leg_*, boot_* — Rect2; light — Vector2 (место фонаря на шлеме).
func body_layout() -> Dictionary:
	var air: bool = not on_ground and not hiding and absf(vel.y) > 40.0
	return Avatar.layout(look, facing, walk_anim, _breath, absf(vel.x) / SPEED, air, _works_ahead())


## Рука вытянута вперёд: копает клетку перед собой (или над/под собой) либо
## чинит/читает терминал. Клетка за спиной — рука опущена, кирка тянется назад.
func _works_ahead() -> bool:
	if task_progress > 0.0:
		return true
	if mining_cell.x < 0 or mining_progress <= 0.0:
		return false
	return (World.cell_to_world(mining_cell).x - global_position.x) * float(facing) > -4.0


func _draw() -> void:
	# Рисунок героя — шов Avatar (ADR-002 § 4.6): тот же для превью меню,
	# товарищей по сети и двойника. Фигура уже отзеркалена по facing (body_layout).
	var lay: Dictionary = body_layout()
	Avatar.draw(self, lay, look,
			{"hiding": hiding, "flash": _hit_flash / HIT_FLASH, "breath": _breath})

	# Индикатор копки живёт в мировых координатах (кирка смотрит на клетку
	# сама) — его не зеркалим. Кирка — из перчатки.
	_draw_mining_fx((lay["glove"] as Rect2).get_center())


## Индикатор копки: контур клетки, полоса прогресса и дрожащая кирка.
## Читается за долю секунды: видно ЧТО копают и СКОЛЬКО осталось.
## pivot — откуда растёт кирка (перчатка героя).
func _draw_mining_fx(pivot: Vector2) -> void:
	if mining_cell.x < 0 or mining_progress <= 0.0:
		return
	var cell_pos: Vector2 = World.cell_to_world(mining_cell) - global_position
	var half: Vector2 = Vector2(World.TILE, World.TILE) * 0.5
	var cell_rect: Rect2 = Rect2(cell_pos - half, half * 2.0)
	# Контур клетки — видно, ЧТО копают.
	draw_rect(cell_rect, Color(1.0, 0.85, 0.35, 0.9), false, 1.5)
	# Полоса прогресса — видно, СКОЛЬКО осталось.
	var bar_w: float = World.TILE * 0.9
	var bar_x: float = cell_rect.position.x + (World.TILE - bar_w) * 0.5
	var bar_y: float = cell_rect.end.y - 3.0
	draw_rect(Rect2(bar_x, bar_y, bar_w, 2.5), Color(0.0, 0.0, 0.0, 0.65))
	draw_rect(Rect2(bar_x, bar_y, bar_w * clampf(mining_progress, 0.0, 1.0), 2.5), Color(1.0, 0.78, 0.28))
	# Дрожащая кирка — видно, что копает игрок.
	var to_cell: Vector2 = cell_pos - pivot
	var ang: float = to_cell.angle() + sin(_mine_fx_t * 26.0) * 0.35
	var reach: float = clampf(to_cell.length(), 10.0, 30.0)
	var head: Vector2 = pivot + Vector2(cos(ang), sin(ang)) * reach
	draw_line(pivot, head, Color(0.42, 0.32, 0.24), 2.0)
	var perp: Vector2 = Vector2(-sin(ang), cos(ang))
	draw_line(head - perp * 4.5, head + perp * 4.5, Color(0.78, 0.82, 0.88), 2.0)


func _make_slash_fx(p: Vector2) -> void:
	_fx(NetCodec.Fx.SLASH, p)


## Размер хотбара при создании героя (#161): из профиля; поля нет — 6 на сенсорном
## экране или с --touch, иначе 10. Файл здесь не пишем: умолчание записывает меню.
static func hotbar_from_profile() -> int:
	var saved: int = Profile.read_hotbar()
	if saved > 0:
		return saved
	return Inventory.default_hotbar(DisplayServer.is_touchscreen_available(), OS.get_cmdline_user_args())


## Применить размер хотбара из меню или профиля. Сужение переносит ячейки 7–10
## в рюкзак; что не влезло — падает под ноги (spawn_item), ничего не теряется.
func apply_hotbar_size(n: int) -> void:
	if inv == null:
		return
	var spilled: Array[ItemStack] = inv.set_hotbar_size(n)
	for s in spilled:
		spawn_item(s.id, s.count, global_position)


# ------------------------------------------------- СОХРАНЕНИЕ (#37)
## Позиция, здоровье, инвентарь с хотбаром (первые hotbar_size слотов) и
## кулдауны. Копка, ремонт и прогресс терминала — по нажатию, не пишутся.
func save_state() -> Dictionary:
	var slots_out: Array = []
	for s in inv.slots:
		slots_out.append([s.id, s.count])
	return {
		"pos": global_position, "vel": vel, "on_ground": on_ground, "facing": facing,
		"hp": hp, "inv": slots_out, "selected": inv.selected,
		"hiding": hiding, "hide_timer": hide_timer, "hide_cd": hide_cd,
		"invuln": invuln, "emp_cd": emp_cd, "slash_cd": slash_cd, "noise": noise,
		"regen": _regen,
	}


func load_state(d: Dictionary) -> void:
	global_position = d.get("pos", global_position)
	vel = d.get("vel", Vector2.ZERO)
	on_ground = bool(d.get("on_ground", false))
	facing = int(d.get("facing", facing))
	hp = float(d.get("hp", MAX_HP))
	var src: Array = d.get("inv", [])
	for i in inv.size:
		var e = src[i] if i < src.size() else null
		if e is Array and e.size() >= 2 and int(e[1]) > 0:
			inv.slots[i] = ItemStack.new(int(e[0]), int(e[1]))
		else:
			inv.slots[i] = ItemStack.new()
	inv.selected = clampi(int(d.get("selected", 0)), 0, inv.hotbar_size - 1)
	hiding = bool(d.get("hiding", false))
	hide_timer = float(d.get("hide_timer", 0.0))
	hide_cd = float(d.get("hide_cd", 0.0))
	invuln = float(d.get("invuln", 0.0))
	emp_cd = float(d.get("emp_cd", 0.0))
	slash_cd = float(d.get("slash_cd", 0.0))
	noise = float(d.get("noise", 0.0))
	_regen = float(d.get("regen", 0.0))
	dead = false
	mining_progress = 0.0
	mining_cell = Vector2i(-1, -1)
	task_progress = 0.0
	_stun = 0.0
	_hit_flash = 0.0
	_shake = 0.0
	if camera != null:
		camera.reset_smoothing()
	inv.changed.emit()
	stats_changed.emit()
	queue_redraw()


# ------------------------------------------------- СЕТЬ (ADR-002)
## Крюки MP-A (#86, § 5.1 правило 1): только поля, без логики. Роли и обёртки
## обратной связи — MP-D (#89), вид — MP-B (#87), перекличка — MP-J (#95).
## LOCAL — одиночная и свой герой хоста; PROXY — чужой герой на хосте;
## OWNER — свой герой клиента; PUPPET — чужой герой у клиента (§ 4.2.3).
enum NetRole { LOCAL, PROXY, OWNER, PUPPET }
var net_role: int = NetRole.LOCAL
## Пир владельца (1 — хост и одиночная).
var peer_id: int = 1
## Параметры вида (Profile.Look, u16): цвет скафандра, шлем, аксессуар, рюкзак.
## Рисует Avatar.draw (скафандр «Кербер-9», ADR-003 V4); 0 — вид по умолчанию.
var look: int = 0
var nick: String = ""
## Огонёк ответа на перекличку (G), с (MP-J).
var rollcall_t: float = 0.0

# --- MP-D (#89): роли, обёртки обратной связи, поправки (§ 4.2.3, § 4.4)
## Прокси на связи: ввод от владельца не старше NetPlayers.LINK_LOST. «Без связи» —
## стоит, урона не получает, целью не служит (net_targetable).
var net_linked: bool = true
## У владельца прокси открыто окно (бит BIT_WINDOW ввода) — вместо UI.blocking() хоста.
var net_window_open: bool = false
## Марионетка: предмет в руке (id), бег (громкость шагов).
var net_held: int = 0
var net_sprint: bool = false
## Эпоха последней поправки позиции (NetCodec.IF_EPOCH_SHIFT / OF_EPOCH_SHIFT).
var net_epoch: int = 0
## Свой герой клиента возрождён хостом (main.gd прячет экран смерти).
signal net_respawned


## Свой герой этого процесса: камера, HUD, звук без позиции.
func _net_view() -> bool:
	return net_role == NetRole.LOCAL or net_role == NetRole.OWNER


## Урон, смерть, укрытие считает этот процесс (одиночная, свой герой хоста, прокси на связи).
func _net_takes_damage() -> bool:
	return net_role == NetRole.LOCAL or (net_role == NetRole.PROXY and net_linked)


## Может ли герой быть целью фантома (MP-F): живой, не спрятался, на связи.
func net_targetable() -> bool:
	return not dead and not hiding and net_linked


## Открыто ли окно, забирающее ввод у мира: у прокси — по пакету ввода владельца.
func _ui_blocking() -> bool:
	if net_role == NetRole.PROXY:
		return net_window_open
	return UI.blocking()


## Звук действия героя. Свой герой — как раньше (Sfx.play); хост ещё рассылает его
## клиентам в точке героя (канал 0, Sfx.play_at у тех, кто слышит). Прокси: хост
## слышит в точке, клиенты (и владелец) — событием.
func _sfx_here(id: String, v: float = 0.0, p: float = 1.0) -> void:
	if _net_view():
		Sfx.play(id, v, p)
	else:
		Sfx.play_at(id, global_position, v, p)
	if Net.is_host() and (net_role == NetRole.LOCAL or net_role == NetRole.PROXY):
		NetPlayers.send_sound(global_position, id, v, p)


## Звук, который каждый процесс играет сам и по сети не шлёт (шаги: скорость есть
## у всех — у прокси из пакета ввода, у марионетки из состояния).
func _sfx_self(id: String, v: float = 0.0, p: float = 1.0) -> void:
	if _net_view():
		Sfx.play(id, v, p)
	else:
		Sfx.play_at(id, global_position, v, p)


## Личное уведомление: видит только этот игрок. Прокси — владельцу (канал 2).
func _notify(text: String, color: Color = Color(0.85, 0.9, 1.0)) -> void:
	if net_role == NetRole.PROXY:
		NetPlayers.send_notify(peer_id, global_position, text, color)
	elif _net_view():
		Game.notify(text, color)


## Эффект в мире (крошка, кольцо, удар): видят все — хост рисует и рассылает.
func _fx(kind: int, pos: Vector2, arg: int = 0) -> void:
	NetPlayers.play_fx(kind, pos, arg)
	if Net.is_host() and (net_role == NetRole.LOCAL or net_role == NetRole.PROXY):
		NetPlayers.send_fx(kind, pos, arg)


## Удар по герою: вспышка экрана и тряска — своему; прокси шлёт владельцу удар
## с отбрасыванием (движение у владельца, § 4.2.3).
func _feedback_hit(knock: Vector2) -> void:
	if net_role == NetRole.PROXY:
		NetPlayers.send_hit(peer_id, global_position, knock, HIT_STUN)
	elif _net_view():
		UI.flash_damage()


## Сундук рядом по E: у прокси окно открывается у владельца — слой команд MP-G (#91).
func _open_chest(c: Chest) -> void:
	if net_role != NetRole.PROXY:
		UI.open_chest(c)
	else:
		InvOps.host_open(self, c)


## Владелец: удар с хоста (событие HIT) — отбрасывание, заморозка ввода, вспышка, тряска.
func net_on_hit(knock: Vector2, stun: float) -> void:
	if net_role != NetRole.OWNER or dead:
		return
	vel += knock
	_hit_flash = HIT_FLASH
	_stun = maxf(_stun, stun)
	_shake = HIT_SHAKE
	UI.flash_damage()


## Владелец: ввод из шва (клавиатура, сценарий, сенсор #81) для пакета ввода.
func net_input_sample() -> Dictionary:
	var keys: Dictionary = {}
	for code in NetCodec.KEY_BITS:
		keys[code] = _key(int(code))
	return {"keys": keys, "mouse": _mouse_pos(), "buttons": {
		MOUSE_BUTTON_LEFT: _mouse_down(MOUSE_BUTTON_LEFT),
		MOUSE_BUTTON_RIGHT: _mouse_down(MOUSE_BUTTON_RIGHT)}}


## Строка пакета состояния (NetCodec, игрок 18 Б).
func net_state_row(slot: int) -> Dictionary:
	var flags: int = 0
	if facing < 0:
		flags |= NetCodec.PF_FACING_LEFT
	if on_ground:
		flags |= NetCodec.PF_ON_GROUND
	if hiding:
		flags |= NetCodec.PF_HIDING
	if dead:
		flags |= NetCodec.PF_DEAD
	if _key(KEY_SHIFT) and absf(vel.x) > MOVE_EPS:
		flags |= NetCodec.PF_SPRINT
	if _stun > 0.0:
		flags |= NetCodec.PF_STUN
	if _hit_flash > 0.0:
		flags |= NetCodec.PF_HIT
	if rollcall_t > 0.0:
		flags |= NetCodec.PF_ROLLCALL
	var mc: int = NetCodec.NO_CELL
	if mining_cell.x >= 0 and mining_progress > 0.0:
		mc = mining_cell.y * NetCodec.WORLD_W_CELLS + mining_cell.x
	return {"slot": slot, "pos": global_position, "vel": vel, "flags": flags, "hp": hp / MAX_HP,
		"mine_cell": mc, "mine": mining_progress, "held": inv.selected_stack().id,
		"anim": fposmod(walk_anim, TAU) / TAU, "noise": noise}


## Личное состояние прокси для владельца (OWN); эпоху и поправку ведёт NetPlayers.
func net_own(seq_ack: int, epoch: int, correction: bool) -> Dictionary:
	var flags: int = (epoch & 3) << NetCodec.OF_EPOCH_SHIFT
	if hiding:
		flags |= NetCodec.OF_HIDING
	if dead:
		flags |= NetCodec.OF_DEAD
	if _stun > 0.0:
		flags |= NetCodec.OF_STUN
	if invuln > 0.0:
		flags |= NetCodec.OF_INVULN
	var d: Dictionary = {"hp": hp / MAX_HP, "flags": flags, "hide_timer": hide_timer,
		"emp_cd": emp_cd, "seq_ack": seq_ack}
	if correction:
		d["correction"] = global_position
	return d


## Владелец: личное состояние с хоста. Поправка с новой эпохой — телепорт; смерть и
## возрождение — по флагу (место возрождения приходит поправкой).
func net_apply_own(d: Dictionary) -> void:
	var flags: int = int(d["flags"])
	var epoch: int = (flags >> NetCodec.OF_EPOCH_SHIFT) & 3
	var new_hp: float = float(d["hp"]) * MAX_HP
	if absf(new_hp - hp) > 0.01:
		hp = new_hp
		stats_changed.emit()
	hiding = (flags & NetCodec.OF_HIDING) != 0
	hide_timer = float(d["hide_timer"])
	emp_cd = float(d["emp_cd"])
	if (flags & NetCodec.OF_STUN) != 0:
		_stun = maxf(_stun, 1.0 / float(Net.TICK_HZ))
	if (flags & NetCodec.OF_INVULN) != 0:
		invuln = maxf(invuln, 1.0 / float(Net.TICK_HZ))
	if d.has("correction") and epoch != net_epoch:
		net_epoch = epoch
		global_position = d["correction"]
		vel = Vector2.ZERO
		_jump_buffer = 0.0
		if camera != null:
			camera.reset_smoothing()
	var now_dead: bool = (flags & NetCodec.OF_DEAD) != 0
	if now_dead and not dead:
		dead = true
		hiding = false
		vel = Vector2.ZERO
		task_progress = 0.0
		mining_progress = 0.0
		died.emit()
	elif dead and not now_dead:
		dead = false
		_stun = 0.0
		stats_changed.emit()
		net_respawned.emit()


## Владелец: своя строка состояния — копка и предмет в руке (рисует индикатор копки).
func net_apply_own_row(row: Dictionary) -> void:
	_net_apply_mining(row)


## Марионетка: интерполированная позиция и состояние из пакета (§ 4.2.3, D6).
func net_apply_puppet(pos: Vector2, v: Vector2, row: Dictionary) -> void:
	global_position = pos
	vel = v
	var flags: int = int(row["flags"])
	facing = -1 if (flags & NetCodec.PF_FACING_LEFT) != 0 else 1
	on_ground = (flags & NetCodec.PF_ON_GROUND) != 0
	hiding = (flags & NetCodec.PF_HIDING) != 0
	dead = (flags & NetCodec.PF_DEAD) != 0
	net_sprint = (flags & NetCodec.PF_SPRINT) != 0
	if (flags & NetCodec.PF_HIT) != 0 and _hit_flash <= 0.0:
		_hit_flash = HIT_FLASH
	rollcall_t = 1.0 if (flags & NetCodec.PF_ROLLCALL) != 0 else 0.0
	hp = float(row["hp"]) * MAX_HP
	net_held = int(row["held"])
	_net_apply_mining(row)


func _net_apply_mining(row: Dictionary) -> void:
	var mc: int = int(row["mine_cell"])
	if mc == NetCodec.NO_CELL:
		mining_cell = Vector2i(-1, -1)
		mining_progress = 0.0
	else:
		mining_cell = Vector2i(mc % NetCodec.WORLD_W_CELLS, mc / NetCodec.WORLD_W_CELLS)
		mining_progress = float(row["mine"])
	queue_redraw()


## Кадр марионетки: позицию ставит NetPlayers; здесь анимация, шаги, вспышка.
func _net_puppet_tick(dt: float) -> void:
	_hit_flash = maxf(0.0, _hit_flash - dt)
	_step_gap = maxf(0.0, _step_gap - dt)
	var prev_phase: float = walk_anim
	walk_anim += absf(vel.x) * dt * 0.08
	_breath += dt * (2.0 if absf(vel.x) > 10.0 else 1.0)
	_update_step(prev_phase, walk_anim, net_sprint)
	if mining_progress > 0.0:
		_mine_fx_t += dt
	queue_redraw()


# --- MP-I (#94): кооператив — укрытие на одного, терминал команды, мешок владельца (§ 4.7)
## uid профиля владельца героя (по нему — мешок, парковка, сохранение; 0 — одиночная).
var net_uid: int = 0
## Вентиляция, в которой сидит герой (пока hiding): «Вентиляция занята: Аня».
var net_vent: Vector2i = Vector2i(-1, -1)
## Личная статистика для экрана итогов (ведёт хост, NetCoop): {"deaths": N}.
var net_stats: Dictionary = {"deaths": 0}


## Вентиляцию v уже занял товарищ (только в сети): личное «Вентиляция занята: Аня».
## false — свободна (герой сейчас в неё залезет — запоминаем, в какую).
func _net_vent_busy(v: Vector2i) -> bool:
	if not Net.is_online():
		return false
	for h in Game.players:
		if h != self and is_instance_valid(h) and h.hiding and h.net_vent == v:
			_notify("Вентиляция занята: %s." % String(h.nick), Color(1.0, 0.75, 0.5))
			return true
	net_vent = v
	return false


## Терминал прочитан (хост): всем — кто прочёл и где. Данные и глава — один раз на
## команду: терминал ушёл из World.terminals, второй дочитывающий его уже не найдёт.
func _net_terminal_read(chapter: int) -> void:
	if not Net.is_host():
		return
	var place: String = Lore.chapter_place(chapter) if chapter >= 0 else ""
	var what: String = "терминал «%s»" % place if place != "" else "терминал"
	NetCoop.team_notify("%s: %s прочитан, +%d данных." % [nick, what, Balance.TERMINAL_DATA],
			Color(0.4, 0.95, 0.6))


## Мешок с хотбаром погибшего — MP_BAG_OWNER_LOCK с поднимает только владелец (по uid).
func _net_own_bag(bag: ItemEntity) -> void:
	if bag != null and Net.is_online():
		bag.bag_owner = net_uid
