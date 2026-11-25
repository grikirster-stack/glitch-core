extends SceneTree
## Замер кадра при 20 устройствах у метки (#316).
##
##   godot --headless --audio-driver Dummy --path . --script res://tools/raid_bench.gd -- --seed=31337
##
## До: ночь без налёта. После: предупреждение налёта на те же 20 машин.
## Печатает p95 и максимум интервала кадра в мкс.

const N: int = 20
const FRAMES: int = 90

var _scene: Node = null
var _world: Node = null
var _frame: int = 0
var _phase: int = 0
var _n: int = 0
var _last: int = 0
var _before: Array = []
var _after: Array = []


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		seed(31337)
		_scene = load("res://scenes/main.tscn").instantiate()
		root.add_child(_scene)
		current_scene = _scene
		return false
	if _frame == 6:
		_world = root.get_node("World")
		_place()
		_phase = 1
		return false
	if _phase == 0:
		return false
	return _tick()


func _tick() -> bool:
	var now: int = Time.get_ticks_usec()
	if _last > 0 and _n > 8:
		(_before if _phase == 1 else _after).append(now - _last)
	_last = now
	_n += 1
	if _n < FRAMES:
		return false
	if _phase == 1:
		_arm_raid()
		print("до налёта: p95 %d мкс, макс %d мкс" % [_p95(_before), _max(_before)])
		_phase = 2
		_n = 0
		_last = 0
		return false
	print("налёт, 20 устройств: p95 %d мкс, макс %d мкс" % [_p95(_after), _max(_after)])
	quit(0)
	return true


func _place() -> void:
	var mb: GDScript = load("res://scripts/machines/machine_base.gd")
	var origin: Vector2i = _world.beacon_cell + Vector2i(4, -2)
	for i in N:
		var c: Vector2i = origin + Vector2i((i % 5) * 3, int(i / 5) * 3)
		if not _world.in_bounds(c.x, c.y):
			continue
		_world.set_tile(c.x, c.y, IDs.T.AIR)
		mb.place_machine("Burner" if i > 0 else "SporeBed", c)
	var game: Node = root.get_node("Game")
	game.set("day_number", 3)
	game.set("time_of_day", 0.70)
	game.set("scenario_mode", true)


func _arm_raid() -> void:
	var game: Node = root.get_node("Game")
	var threat: Node = root.get_node("Threat")
	threat.set("active", true)
	game.set("raid_phase", 1)
	game.set("raid_number", 1)
	game.set("raid_remain", 25.0)
	game.set("raid_target", _world.beacon_cell + Vector2i(4, -2))
	threat.tick(0.05)


func _p95(a: Array) -> int:
	if a.is_empty():
		return 0
	var s: Array = a.duplicate()
	s.sort()
	return int(s[mini(s.size() - 1, int(float(s.size()) * 0.95))])


func _max(a: Array) -> int:
	var m: int = 0
	for v in a:
		m = maxi(m, int(v))
	return m
