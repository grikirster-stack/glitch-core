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
var hide_timer: float = 0.0
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

var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _jump_prev: bool = false
var _stun: float = 0.0
var _hit_flash: float = 0.0
var _shake: float = 0.0
var _noise_level: float = 0.0
var _step_gap: float = 0.0
var _mine_fx_t: float = 0.0


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
	if _key(KEY_E):
		_do_interact(dt)
	else:
		task_progress = 0.0

	# V — вентиляция
	if _key(KEY_V):
		_toggle_hide()


# ------------------------------------------------- ШОВ ТЕСТОВОГО ВВОДА
## Состояние клавиши. Если сценарий подменил ввод — читаем его,
## иначе — обычный Input. Читается каждый кадр, ничего не кэшируется.
func _key(code: int) -> bool:
	if test_input.has("keys"):
		var k: Dictionary = test_input["keys"]
		if k.has(code):
			return bool(k[code])
	return Input.is_key_pressed(code)


## Состояние кнопки мыши (см. _key).
func _mouse_down(btn: int) -> bool:
	if test_input.has("mouse_buttons"):
		var m: Dictionary = test_input["mouse_buttons"]
		if m.has(btn):
			return bool(m[btn])
	return Input.is_mouse_button_pressed(btn)


## Позиция «курсора» в мире (см. _key).
func _mouse_pos() -> Vector2:
	if test_input.has("mouse"):
		var m: Vector2 = test_input["mouse"]
		return m
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
	# ПКМ по конвейеру — повернуть его.
	if World.belts.has(cell):
		var b: Belt = World.belts[cell]
		b.turn()
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


func _do_interact(dt: float) -> void:
	# Терминалы
	for t in World.terminals:
		if World.cell_to_world(t).distance_to(global_position) < 42.0:
			task_progress += dt / 2.2
			if task_progress >= 1.0:
				task_progress = 0.0
				World.terminals.erase(t)
				World.set_tile(t.x, t.y, IDs.T.PANEL)
				Game.complete_task()
				Sfx.play("craft", -6.0)
			return
	# Релей
	if World.cell_to_world(World.beacon_cell).distance_to(global_position) < 56.0:
		task_progress += dt / 3.0
		if task_progress >= 1.0:
			task_progress = 0.0
			Game.try_finish()
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


func _toggle_hide() -> void:
	if hiding:
		hiding = false
		hide_timer = 0.0
		return
	for v in World.vents:
		if World.cell_to_world(v).distance_to(global_position) < 40.0:
			hiding = true
			hide_timer = 6.0
			invuln = 7.0
			Sfx.play("power", -14.0)
			Game.notify("Вы залезли в вентиляцию. Фантомы вас не видят.", Color(0.6, 0.9, 1.0))
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
		hp = 0.0
		dead = true
		died.emit()
		Game.set_state(Game.State.DEAD)


func _sfx(n: String, v: float = 0.0, p: float = 1.0) -> void:
	Sfx.play(n, v, p)


func _draw() -> void:
	var body_col: Color = Color(0.86, 0.22, 0.24)
	if hiding:
		body_col = body_col.darkened(0.45)
	# Покраснение корпуса после урона.
	var flash: float = _hit_flash / HIT_FLASH
	if flash > 0.0:
		body_col = body_col.lerp(Color(1.0, 0.74, 0.64), flash * 0.85)
	# Живое покойное дыхание + лёгкий подскок корпуса на шаге.
	var idle_amt: float = clampf(1.0 - absf(vel.x) / 60.0, 0.0, 1.0)
	var move_amt: float = clampf(absf(vel.x) / SPEED, 0.0, 1.0)
	var breathe: float = sin(_breath * 1.8) * idle_amt
	var bounce: float = -absf(sin(walk_anim)) * 1.4 * move_amt
	# Низ корпуса неподвижен — дыхание растягивает корпус вверх.
	var body_h: float = SIZE.y * (1.0 + 0.03 * breathe)
	var r: Rect2 = Rect2(-SIZE.x * 0.5, SIZE.y * 0.5 - body_h + bounce, SIZE.x, body_h)
	# Тень
	draw_set_transform(Vector2(0, SIZE.y * 0.5), 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, SIZE.x * 0.6, Color(0, 0, 0, 0.28))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Рюкзак
	draw_rect(Rect2(-r.size.x * 0.5 - 5.0, -r.size.y * 0.5 + 3.0, 5.0, r.size.y - 7.0), body_col.darkened(0.25))
	# Тело
	draw_rect(r, body_col)
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 3.0), body_col.lightened(0.18))
	draw_rect(Rect2(r.position.x, r.end.y - 3.0, r.size.x, 3.0), body_col.darkened(0.22))
	# Ноги
	var step: float = sin(walk_anim) * 2.0
	draw_rect(Rect2(-4.0, r.end.y - 3.0, 3.0, 3.0 + step), body_col.darkened(0.35))
	draw_rect(Rect2(1.0, r.end.y - 3.0, 3.0, 3.0 - step), body_col.darkened(0.35))
	# Визор
	var visor_x: float = -1.0 if facing > 0 else -11.0
	var visor_y: float = r.position.y + 2.0
	var visor: Rect2 = Rect2(visor_x, visor_y, 11.0, 7.0)
	draw_rect(visor, Color(0.72, 0.86, 0.94))
	draw_rect(Rect2(visor.position.x, visor.position.y, visor.size.x, 2.0), Color(0.88, 0.96, 1.0))
	draw_rect(Rect2(visor.position.x + 1.0, visor.position.y + 1.0, 3.0, 2.0), Color(1, 1, 1, 0.85))
	# Мигающий «свет» на шлеме
	var blink: float = 0.5 + 0.5 * sin(_breath * 6.0)
	draw_circle(Vector2(visor_x + 8.0, visor_y), 1.6, Color(1.0, 0.35, 0.3, 0.5 + blink * 0.5))
	# Контур урона
	if flash > 0.0:
		draw_rect(r, Color(1.0, 0.35, 0.32, flash * 0.8), false, 1.5)

	if hiding:
		draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 24, Color(0.4, 0.9, 1.0, 0.5), 1.5)

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
