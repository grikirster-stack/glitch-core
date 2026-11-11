extends SceneTree
## Замер луча (#164): мкс rebuild на 20 горелках и мкс кадра WorldFX до/после.
##
##   godot --headless --path . --script res://tools/beam_bench.gd -- --seed=31337
##
## Кадр — как в defense_bench: WorldFX.queue_redraw каждый кадр, p95 интервала.

const BURNERS: int = 20
const FRAMES: int = 120

var _scene: Node = null
var _world: Node = null
var _fx: Node = null
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
	if _frame == 4:
		_world = root.get_node("World")
		_fx = _scene.get("world_fx")
		_phase = 1
		return false
	if _phase == 0:
		return false
	return _tick()


func _tick() -> bool:
	var now: int = Time.get_ticks_usec()
	if _last > 0 and _n > 20:
		(_before if _phase == 1 else _after).append(now - _last)
	_last = now
	_n += 1
	if _fx != null:
		_fx.queue_redraw()
	var need: int = FRAMES
	if _n < need:
		return false
	if _phase == 1:
		_place()
		print("кадр без лучей: среднее %.2f мс, p95 %.2f мс" % [_mean(_before) / 1000.0, float(_p95(_before)) / 1000.0])
		_phase = 2
		_n = 0
		_last = 0
		return false
	var us: int = _world.beams.rebuild()
	print("rebuild %d горелок: %d мкс (клеток %d, сегментов %d)" % [
			BURNERS, us, _world.beams.cells.size(), _world.beams.segments.size()])
	print("кадр с %d лучами: среднее %.2f мс, p95 %.2f мс; _draw_beams %d мкс" % [
			BURNERS, _mean(_after) / 1000.0, float(_p95(_after)) / 1000.0, int(_fx.beam_draw_us)])
	quit(0)
	return true


func _place() -> void:
	var mb: GDScript = load("res://scripts/machines/machine_base.gd")
	var origin: Vector2i = _world.beacon_cell + Vector2i(-40, 8)
	for i in BURNERS:
		var c: Vector2i = origin + Vector2i((i % 5) * 4, int(i / 5) * 3)
		for k in range(0, 26):
			var a: Vector2i = c + Vector2i(k, 0)
			if _world.in_bounds(a.x, a.y):
				_world.set_tile(a.x, a.y, IDs.T.AIR)
		if mb.place_machine("Burner", c):
			_world.machines[c].add_fuel(IDs.I.COAL, 1)
	_world.beams.rebuild()
	_world._apply_beam_lights()
	var player: Node2D = _scene.get("player")
	if player != null:
		player.global_position = _world.cell_to_world(origin + Vector2i(8, 2))


func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s: float = 0.0
	for v in a:
		s += float(v)
	return s / float(a.size())


func _p95(a: Array) -> int:
	if a.is_empty():
		return 0
	var s: Array = a.duplicate()
	s.sort()
	return int(s[mini(s.size() - 1, int(float(s.size()) * 0.95))])
