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


func _ready() -> void:
	inv = Inventory.new(36, 10)
	camera = Camera2D.new()
	camera.zoom = Vector2(2.2, 2.2)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 9.0
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = World.W * World.TILE
	camera.limit_bottom = World.H * World.TILE
	camera.limit_smoothed = true
	add_child(camera)
	camera.make_current()
	z_index = 5


func _physics_process(delta: float) -> void:
	if dead:
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
	_tick_hide(dt)
	_regen += dt
	if _regen > 6.0 and hp < MAX_HP:
		_regen = 0.0
		hp = minf(MAX_HP, hp + 6.0)

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

	var sprint: bool = _key(KEY_SHIFT)
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


## Короткая трясучка камеры после урона — читается, но не мешает играть.
func _update_shake(dt: float) -> void:
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
		Sfx.play("step", -11.0, randf_range(1.10, 1.24))
	else:
		Sfx.play("step", -19.0, randf_range(0.86, 1.00))


func _handle_input(dt: float) -> void:
	if dead:
		return
	# Выбор слота хотбара
	for i in 9:
		if _key(KEY_1 + i):
			inv.selected = i
			break
	if _key(KEY_0):
		inv.selected = 9

	if UI.blocking():
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
		_place_cd -= dt
		if _place_cd <= 0.0:
			_place_cd = 0.16
			_do_place(cell)

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
			_sfx("hit", -6.0, 1.4)
			p.take_damage(38.0, global_position)
			_make_slash_fx(mouse)
			return true
	return false


func _empulse() -> void:
	emp_cd = emp_max
	Sfx.play("power", -8.0)
	UI.flash_ring(global_position, Color(0.4, 0.9, 1.0))
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
		Sfx.play("mine", -14.0, randf_range(0.85, 1.2))
		UI.spawn_chip(cell, DB.tile_color(tid))
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
	Sfx.play("break", -8.0, randf_range(0.9, 1.15))
	UI.spawn_chip(cell, DB.tile_color(tid))
	Game.stats_mined += 1
	if drop != IDs.I.NONE:
		spawn_item(drop, 1, World.cell_to_world(cell))


func _do_place(cell: Vector2i) -> void:
	# ПКМ по конвейеру или манипулятору (#30) — повернуть.
	var turnable = World.machines.get(cell)
	if turnable is Belt or turnable is Inserter:
		turnable.turn()
		Sfx.play("place", -14.0, 1.3)
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
			Game.notify("Решётку ставят на вентиляцию.", Color(1.0, 0.6, 0.5))
			return
		World.set_tile(cell.x, cell.y, tid)
		inv.remove_at(inv.selected, 1)
		Sfx.play("place", -10.0)
	elif place.begins_with("machine:"):
		var kind: String = place.substr(7)
		if MachineBase.place_machine(kind, cell):
			inv.remove_at(inv.selected, 1)
			Sfx.play("place_machine", -8.0)
			_auto_orient(cell, kind)
		else:
			Game.notify("Сюда нельзя поставить.", Color(1.0, 0.6, 0.5))


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


func _place_allowed(cell: Vector2i) -> bool:
	var tid: int = World.get_tile_v(cell)
	if tid != IDs.T.AIR and not DB.is_liquid(tid):
		return false
	var r: Rect2 = Rect2(Vector2(cell.x * World.TILE, cell.y * World.TILE), Vector2(World.TILE, World.TILE))
	var pr: Rect2 = Rect2(global_position - SIZE * 0.5, SIZE)
	if r.intersects(pr):
		return false
	return true


## E — взаимодействие. fresh — первый кадр нажатия (подсказки — один раз на нажатие).
func _do_interact(dt: float, fresh: bool = true) -> void:
	# Терминалы: работают только под питанием (ADR-001 § 4.6, #29)
	for t in World.terminals:
		var tw: Vector2 = World.cell_to_world(t)
		if tw.distance_to(global_position) < 42.0:
			if not Game.is_powered(tw):
				task_progress = 0.0
				if fresh:
					Sfx.play("craft", -16.0, 0.6)
					Game.notify("Терминал: нет питания. Поставьте рядом ТЭЦ или солнечную панель.",
							Color(1.0, 0.7, 0.4))
				return
			task_progress += dt / 2.2
			if task_progress >= 1.0:
				task_progress = 0.0
				_read_terminal(t)
			return
	# Ремонт: E с хламом в хотбаре по повреждённой машине (§ 4.4)
	if _try_repair() or _e_used:
		return
	# Релей
	if World.cell_to_world(World.beacon_cell).distance_to(global_position) < 56.0:
		task_progress += dt / 3.0
		if task_progress >= 1.0:
			task_progress = 0.0
			Game.try_finish()
		return
	# Манипулятор под курсором (#30): E с предметом — фильтр, пустой рукой — сброс.
	var ins = World.machines.get(building_cell)
	if ins is Inserter and ins.global_position.distance_to(global_position) <= REACH:
		ins.interact(self)
		return
	# Сундуки
	for m in World.machines.values():
		if m is Chest and m.global_position.distance_to(global_position) < 40.0:
			UI.open_chest(m)
			return
	# Генератор: ТЭЦ с углём в хотбаре — загрузить топку, иначе — рубильник (#25)
	for m2 in World.machines.values():
		if m2 is Generator and m2.global_position.distance_to(global_position) < 40.0:
			m2.interact(self)
			return
	# Станции — закинуть предмет из хотбара
	var sel: ItemStack = inv.selected_stack()
	if not sel.is_empty():
		for m3 in World.machines.values():
			if m3 is Belt or m3 is Chest or m3 is CoalGen:
				continue
			if m3.global_position.distance_to(global_position) > 44.0:
				continue
			if m3.input_accepts(sel.id):
				var left: int = m3.receive_item(sel.id, sel.count)
				if left < sel.count:
					inv.remove_at(inv.selected, sel.count - left)
					Sfx.play("place", -12.0)
					Game.notify("Загружено: %s" % DB.item_name(sel.id), Color(0.7, 0.9, 1.0))
					return


## Терминал отработал: +данные (Game.complete_task), глава журнала этого места.
func _read_terminal(t: Vector2i) -> void:
	var chapter: int = int(World.terminal_chapters.get(t, -1))
	World.terminals.erase(t)
	World.set_tile(t.x, t.y, IDs.T.PANEL)
	_e_used = true
	Game.complete_task()
	if chapter >= 0:
		Tech.read_chapter(chapter)
	Sfx.play("craft", -6.0)


## Ремонт хламом: +Balance.REPAIR_PER_SCRAP HP ближайшей повреждённой машине за
## единицу, пока E зажата — раз в REPAIR_GAP. true — рядом есть что чинить (E занята).
func _try_repair() -> bool:
	var sel: ItemStack = inv.selected_stack()
	if sel.is_empty() or sel.id != IDs.I.SCRAP:
		return false
	var best: MachineBase = null
	var best_d: float = 44.0
	for m in World.machines.values():
		if m.hp >= m.max_hp:
			continue
		var d: float = m.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = m
	if best == null:
		return false
	if _repair_cd > 0.0:
		return true
	_repair_cd = REPAIR_GAP
	_e_used = true
	best.hp = minf(best.max_hp, best.hp + Balance.REPAIR_PER_SCRAP)
	best.anim = 1.0
	best.queue_redraw()
	inv.remove_at(inv.selected, 1)
	Sfx.play("place", -10.0, 1.2)
	UI.spawn_chip(best.cell, Color(0.75, 0.7, 0.6))
	Game.notify("Ремонт: %s %d/%d" % [DB.item_name(MachineBase.machine_item_id(best.kind)),
			int(best.hp), int(best.max_hp)], Color(0.7, 0.95, 0.7))
	return true


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
		Game.notify("Вентиляция вытолкнула вас наружу.", Color(1.0, 0.75, 0.5))


func _leave_vent() -> void:
	hiding = false
	hide_timer = 0.0
	hide_cd = Balance.HIDE_COOLDOWN
	invuln = minf(invuln, 0.6)
	Sfx.play("power", -16.0, 0.8)


func _toggle_hide() -> void:
	if hiding:
		_leave_vent()
		return
	for v in World.vents:
		if World.cell_to_world(v).distance_to(global_position) < 40.0:
			if hide_cd > 0.0:
				Game.notify("Вентиляция ещё не остыла: %d с." % ceili(hide_cd), Color(0.8, 0.8, 0.8))
				return
			hiding = true
			hide_timer = Balance.HIDE_MAX
			invuln = Balance.HIDE_MAX + 0.6
			vel = Vector2.ZERO
			Sfx.play("power", -14.0)
			Game.notify("Вы в вентиляции: %d с, фантомы вас не видят." % int(Balance.HIDE_MAX),
					Color(0.6, 0.9, 1.0))
			return
	Game.notify("Рядом нет вентиляции.", Color(0.8, 0.8, 0.8))


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
		Sfx.play("pickup", -16.0, randf_range(0.95, 1.15))
		stats_changed.emit()
	return left


func damage(amount: float, knock: Vector2) -> void:
	if invuln > 0.0 or dead:
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
	UI.flash_damage()
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
	drop_hotbar_bag()
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
	Sfx.play(n, v, p)


## Раскладка частей фигуры в локальных координатах героя (issue #58).
## Все части задаются «лицом вправо», а при facing = -1 каждая отражается
## относительно вертикальной оси героя (x = 0): рюкзак уходит за спину,
## визор и огонёк — вперёд, ноги меняются местами вместе с фазой шага.
## Вынесено из _draw, чтобы anim_test проверял ровно то, что рисуется.
## Ключи: body, backpack, leg_back, leg_front, visor, visor_top, visor_glint —
## Rect2; light — Vector2 (центр огонька на шлеме).
func body_layout() -> Dictionary:
	# Живое покойное дыхание + лёгкий подскок корпуса на шаге.
	var idle_amt: float = clampf(1.0 - absf(vel.x) / 60.0, 0.0, 1.0)
	var move_amt: float = clampf(absf(vel.x) / SPEED, 0.0, 1.0)
	var breathe: float = sin(_breath * 1.8) * idle_amt
	var bounce: float = -absf(sin(walk_anim)) * 1.4 * move_amt
	# Низ корпуса неподвижен — дыхание растягивает корпус вверх.
	var body_h: float = SIZE.y * (1.0 + 0.03 * breathe)
	var r: Rect2 = Rect2(-SIZE.x * 0.5, SIZE.y * 0.5 - body_h + bounce, SIZE.x, body_h)
	var step: float = sin(walk_anim) * 2.0
	var visor: Rect2 = Rect2(-1.0, r.position.y + 2.0, 11.0, 7.0)
	var light: Vector2 = Vector2(visor.position.x + 8.0, visor.position.y)
	var f: float = -1.0 if facing < 0 else 1.0
	return {
		"body": r,
		# Рюкзак за спиной: при взгляде вправо — слева от корпуса.
		"backpack": _mirror(Rect2(-r.size.x * 0.5 - 5.0, -r.size.y * 0.5 + 3.0, 5.0, r.size.y - 7.0)),
		"leg_back": _mirror(Rect2(-4.0, r.end.y - 3.0, 3.0, 3.0 + step)),
		"leg_front": _mirror(Rect2(1.0, r.end.y - 3.0, 3.0, 3.0 - step)),
		"visor": _mirror(visor),
		"visor_top": _mirror(Rect2(visor.position.x, visor.position.y, visor.size.x, 2.0)),
		"visor_glint": _mirror(Rect2(visor.position.x + 1.0, visor.position.y + 1.0, 3.0, 2.0)),
		"light": Vector2(light.x * f, light.y),
	}


## Отражение прямоугольника относительно оси героя, если он смотрит влево.
func _mirror(rect: Rect2) -> Rect2:
	if facing >= 0:
		return rect
	return Rect2(-rect.end.x, rect.position.y, rect.size.x, rect.size.y)


func _draw() -> void:
	# Рисунок героя — шов Avatar (ADR-002 § 4.6): тот же для превью меню и
	# товарищей по сети. Фигура уже отзеркалена по facing (body_layout).
	Avatar.draw(self, body_layout(), look,
			{"hiding": hiding, "flash": _hit_flash / HIT_FLASH, "breath": _breath})

	# Индикатор копки живёт в мировых координатах (кирка смотрит на клетку
	# сама) — его не зеркалим.
	_draw_mining_fx()


## Индикатор копки: контур клетки, полоса прогресса и дрожащая кирка.
## Читается за долю секунды: видно ЧТО копают и СКОЛЬКО осталось.
func _draw_mining_fx() -> void:
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
	var pivot: Vector2 = Vector2(0.0, -6.0)
	var to_cell: Vector2 = cell_pos - pivot
	var ang: float = to_cell.angle() + sin(_mine_fx_t * 26.0) * 0.35
	var reach: float = clampf(to_cell.length(), 10.0, 30.0)
	var head: Vector2 = pivot + Vector2(cos(ang), sin(ang)) * reach
	draw_line(pivot, head, Color(0.42, 0.32, 0.24), 2.0)
	var perp: Vector2 = Vector2(-sin(ang), cos(ang))
	draw_line(head - perp * 4.5, head + perp * 4.5, Color(0.78, 0.82, 0.88), 2.0)


func _make_slash_fx(p: Vector2) -> void:
	UI.spawn_slash(p)


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
## Параметры вида (Profile.Look, u16): цвет скафандра, шлем, аксессуар, рюкзак.
## Рисует Avatar.draw; 0 — прежний красный герой. Одиночная игра из меню —
## вид из профиля (main.gd), в сети — вид пира (MP-D).
var look: int = 0
