extends SceneTree
## Пошаговый ручной плейтест с удержаниями и кадрами. Протокол и запуск
## описаны в docs/playtest-freeplay.md. Использует обычный мир и его правила.

const POLL_MS: int = 25
const MAX_REQUEST_TICKS: int = 7200
const IDLE_AIM: Vector2 = Vector2.INF

var _output_dir: String = ""
var _game: Node
var _world: Node
var _ui: Node
var _db: Node
var _player: Node2D
var _last_request: int = 0
var _last_poll: int = 0
var _busy: bool = true
var _pointer: Vector2
var _world_aim: Vector2 = IDLE_AIM
var _keys: Dictionary = {}
var _buttons: Dictionary = {}


func _initialize() -> void:
	var has_seed: bool = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--playtest-dir="):
			_output_dir = arg.trim_prefix("--playtest-dir=")
		elif arg.begins_with("--seed=") and arg.trim_prefix("--seed=").is_valid_int():
			has_seed = true
		else:
			_fail("Ожидаются --seed=N и --playtest-dir=абсолютный_путь. Получено: " + arg)
			return
	if DisplayServer.get_name() == "headless":
		_fail("Для кадров нужно окно Godot.")
		return
	if not has_seed or not _output_dir.is_absolute_path() or not DirAccess.dir_exists_absolute(_output_dir):
		_fail("Укажите --seed=N и существующую абсолютную папку --playtest-dir.")
		return
	for file_name in ["input.json", "state.json", "frame.png", "state.tmp"]:
		if FileAccess.file_exists(_path(file_name)):
			_fail("Для нового забега выберите папку без файлов прошлого прогона.")
			return
	_boot.call_deferred()


func _boot() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_player = scene.get("player")
	_game = root.get_node("Game")
	_world = root.get_node("World")
	_ui = root.get_node("UI")
	_db = root.get_node("DB")
	_pointer = root.get_visible_rect().get_center()
	await _wait_ticks(45)
	paused = true
	await _snapshot(0)
	_busy = false
	print("Плейтест: ждём input.json в ", _output_dir)


func _process(_delta: float) -> bool:
	var now: int = Time.get_ticks_msec()
	if _busy or now - _last_poll < POLL_MS:
		return false
	_last_poll = now
	var file_path: String = _path("input.json")
	if not FileAccess.file_exists(file_path):
		return false
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(file_path)) != OK or not json.data is Dictionary:
		return false
	var request: Dictionary = json.data
	var id: Variant = request.get("id", -1)
	if not _is_integer(id) or int(id) <= _last_request:
		return false
	_last_request = int(id)
	_busy = true
	_run_request.call_deferred(request.get("actions"))
	return false


func _run_request(actions: Variant) -> void:
	var error_text: String = _validate(actions)
	if error_text.is_empty():
		paused = false
		for action in actions:
			match action[0]:
				"key":
					_key(OS.find_keycode_from_string(action[1]), action[2])
				"pointer":
					_move_pointer(Vector2(action[1], action[2]))
				"cell":
					var cell: Vector2i = Vector2i(int(action[1]), int(action[2]))
					var point: Vector2 = _world.cell_to_world(cell)
					_move_pointer(root.get_canvas_transform() * point)
					_world_aim = point
				"button":
					_button(int(action[1]), action[2])
				"wait":
					await _wait_ticks(int(action[1]))
				"quit":
					_release_input()
					quit()
					return
			Input.flush_buffered_events()
		_release_input()
		await _wait_ticks(1)
		paused = true
	await _snapshot(_last_request, error_text)
	_busy = false


func _validate(actions: Variant) -> String:
	if not actions is Array:
		return "Поле actions должно быть массивом."
	var ticks: int = 0
	for action in actions:
		if not action is Array or action.is_empty():
			return "Каждое действие должно быть непустым массивом."
		match action[0]:
			"key":
				if action.size() != 3 or not action[1] is String or not action[2] is bool \
						or OS.find_keycode_from_string(action[1]) == KEY_NONE:
					return "key ожидает имя клавиши и true/false."
			"pointer", "cell":
				if action.size() != 3 or not _is_integer(action[1]) or not _is_integer(action[2]):
					return "pointer и cell ожидают две целых координаты."
			"button":
				if action.size() != 3 or not _is_integer(action[1]) \
						or not int(action[1]) in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT] or not action[2] is bool:
					return "button ожидает 1 (ЛКМ) или 2 (ПКМ) и true/false."
			"wait":
				if action.size() != 2 or not _is_integer(action[1]) or int(action[1]) < 1:
					return "wait ожидает положительное число физических кадров."
				ticks += int(action[1])
			"quit":
				if action.size() != 1:
					return "quit не принимает аргументов."
			_:
				return "Неизвестное действие: " + str(action[0])
	if ticks > MAX_REQUEST_TICKS:
		return "Лимит ожидания за запрос — %d физических кадров." % MAX_REQUEST_TICKS
	return ""


func _key(code: Key, pressed: bool) -> void:
	if pressed:
		_keys[code] = true
	else:
		_keys.erase(code)
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.shift_pressed = _keys.has(KEY_SHIFT)
	Input.parse_input_event(event)


func _move_pointer(point: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = point - _pointer
	_pointer = point
	_world_aim = IDLE_AIM
	Input.parse_input_event(event)


func _button(code: MouseButton, pressed: bool) -> void:
	if pressed:
		_buttons[code] = true
	else:
		_buttons.erase(code)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = code
	event.position = _pointer
	event.global_position = _pointer
	event.pressed = pressed
	event.shift_pressed = _keys.has(KEY_SHIFT)
	Input.parse_input_event(event)


func _release_input() -> void:
	for code in _keys.keys():
		_key(code, false)
	for code in _buttons.keys():
		_button(code, false)
	Input.flush_buffered_events()


func _wait_ticks(count: int) -> void:
	for _i in range(count):
		# GUI получает обычные события мыши. Луч копки и мира читает ту же
		# координату через штатный шов прицеливания без перемещения курсора ОС.
		var world_point: Vector2 = _world_aim
		if world_point == IDLE_AIM:
			world_point = root.get_canvas_transform().affine_inverse() * _pointer
		_player.test_input["mouse"] = world_point
		await physics_frame


func _snapshot(id: int, error_text: String = "") -> void:
	await RenderingServer.frame_post_draw
	var png: Error = root.get_texture().get_image().save_png(_path("frame.png"))
	var inv: Variant = _player.get("inv")
	var items: Array = []
	for i in range(inv.slots.size()):
		var slot: Variant = inv.slots[i]
		if not slot.is_empty():
			items.append([i + 1, _db.item_name(slot.id), slot.count])
	var tile: Vector2i = _world.world_to_cell(_player.global_position)
	var aim: Vector2i = _player.get("building_cell")
	var screen: Vector2 = root.get_canvas_transform() * _player.global_position
	var data: Dictionary = {
		"id": id, "error": error_text, "png": png, "seed": _world.world_seed,
		"tile": [tile.x, tile.y], "pos": [_player.position.x, _player.position.y],
		"screen": [screen.x, screen.y], "pointer_cell": [aim.x, aim.y],
		"HP": round(_player.get("hp")), "items": items, "selected": inv.selected + 1,
		"stage": _game.objective_stage, "ore": _game.stats_ore, "day": _game.day_number,
		"time": snappedf(_game.game_time, 0.1), "night_fraction": snappedf(_game.time_of_day, 0.001),
		"deaths": _game.stats_deaths, "mined": _game.stats_mined, "arcs": _game.core_arc_count(),
		"relay": _game.relay_active, "remaining": _game.relay_timer,
		"signal_sent": _game.signal_sent, "state": _game.state,
		"inventory_open": _ui.panel.visible, "goal": _ui.hud.card_text, "hint": _ui.hud.hint_text,
	}
	var temp_path: String = _path("state.tmp")
	var output: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)
	if output == null:
		_fail("Ошибка записи state.tmp.")
		return
	output.store_string(JSON.stringify(data))
	output.close()
	if DirAccess.rename_absolute(temp_path, _path("state.json")) != OK:
		_fail("Ошибка публикации state.json.")


func _path(file_name: String) -> String:
	return _output_dir.path_join(file_name)


func _fail(message: String) -> void:
	push_error("playtest_input: " + message)
	quit(1)


static func _is_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(value) and float(value) == floorf(value)
