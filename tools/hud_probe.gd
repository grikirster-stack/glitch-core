extends SceneTree
## Замер зоны HUD (issue #7): сколько стоят HUD и небо при большой фабрике
## и сколько узлов-предметов копится на земле.
##
## Запуск:
##   godot --headless --path . --script res://tools/hud_probe.gd -- --seed=31337
##
## Что делает:
##  1. Ставит 200 построек (100 сундуков + 100 ТЭЦ) — подсказки HUD раньше
##     перебирали их все дважды за кадр.
##  2. Чередует этапы «всё включено» / «HUD выключен» / «небо выключено»
##     (A/B, как perf_probe) и печатает среднее время кадра. Если у HUD и неба
##     есть счётчики stat_us / stat_frames — печатает и их: это точное время
##     _process + _draw, без шума остальных систем.
##  3. Считает перерисовки HUD и неба в секунду (сигнал draw всех их CanvasItem).
##  4. Роняет 200 предметов на землю (как добыча 200 блоков) и считает узлы
##     ItemEntity и время физического кадра с ними.
##
## Внимание: файл запускается как главный цикл (--script), поэтому автозагрузки
## берём через get_node(), а скрипты — через load().

const STAGE_SEC: float = 4.0
const MACHINES: int = 200
const ITEMS: int = 200
const SKY_SCRIPT: String = "res://scripts/ui/sky_backdrop.gd"
const ITEM_SCRIPT: String = "res://scripts/entities/item_entity.gd"

var scene: Node = null
var world: Node = null
var hud: Node = null
var sky: Node = null

var _t: float = 0.0
var _stage: int = -1
var _stage_t0: float = 0.0
var _last_us: int = 0
var _frame_us: float = 0.0
var _frames: int = 0
var _phys_ms: float = 0.0
var _hud_draws: int = 0
var _sky_draws: int = 0
var _hud_us0: int = 0
var _hud_fr0: int = 0
var _sky_us0: int = 0
var _sky_fr0: int = 0
var _results: Dictionary = {}
var _item_us0: int = 0
var _item_ticks0: int = 0
var _phys_frames: int = 0
var _map_us0: int = 0
var _hint_us0: int = 0

## Этапы: [имя, hud.visible, sky.visible, предметы на земле]
const STAGES: Array = [
	["прогрев", true, true, false],
	["всё включено", true, true, false],
	["HUD выключен", false, true, false],
	["всё включено", true, true, false],
	["HUD выключен", false, true, false],
	["небо выключено", true, false, false],
	["всё включено", true, true, false],
	["200 предметов на земле", true, true, true],
]


func _initialize() -> void:
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	scene = main_scene.instantiate()
	root.add_child(scene)
	current_scene = scene


func _setup() -> void:
	# Ссылки берём на первом кадре: к этому моменту _ready сцены и автозагрузок
	# уже отработали (в _initialize дерево ещё не собрано).
	world = root.get_node("World")
	hud = root.get_node("UI").get("hud")
	# Классы с автозагрузками внутри (SkyBackdrop, ItemEntity) в режиме --script
	# по имени не компилируются — узнаём узлы по пути скрипта.
	for c in scene.get_children():
		if _script_is(c, SKY_SCRIPT):
			sky = c
	_count_draws(hud, true)
	_count_draws(sky, false)
	var mb: GDScript = load("res://scripts/machines/machine_base.gd")
	var placed: int = 0
	# Поле построек над поверхностью, подальше от игрока: подсказка не находится,
	# и старый HUD перебирает все постройки до конца.
	var x0: int = 20
	var y0: int = 4
	while placed < MACHINES:
		var cell: Vector2i = Vector2i(x0 + placed % 40, y0 + placed / 40)
		world.set_tile(cell.x, cell.y, IDs.T.AIR)
		if mb.place_machine("Chest" if placed % 2 == 0 else "CoalGen", cell):
			placed += 1
		else:
			x0 += 1
	print("построек в мире: %d" % world.machines.size())


func _script_is(n: Node, path: String) -> bool:
	var sc: Script = n.get_script()
	return sc != null and sc.resource_path == path


func _count_draws(n: Node, is_hud: bool) -> void:
	if n is CanvasItem:
		if is_hud:
			n.draw.connect(func() -> void: _hud_draws += 1)
		else:
			n.draw.connect(func() -> void: _sky_draws += 1)
	for c in n.get_children():
		_count_draws(c, is_hud)


func _drop_items() -> void:
	var player: Node2D = scene.get("player")
	# 200 разных клеток на поверхности, далеко от игрока: как добыча 200 блоков.
	var pc: Vector2i = world.world_to_cell(player.global_position)
	var ids: Array = [IDs.I.STONE, IDs.I.SAND, IDs.I.COPPER_ORE, IDs.I.COAL]
	var placed: int = 0
	var x: int = 2
	while placed < ITEMS and x < world.W - 2:
		if absi(x - pc.x) > 12:
			var top: int = int(world.surface[x])
			for k in 2:
				var pos: Vector2 = Vector2(float(x * 16) + 8.0, float((top - 1 - k) * 16) + 8.0)
				player.spawn_item(int(ids[placed % ids.size()]), 1, pos)
				placed += 1
		x += 1


func _item_nodes() -> int:
	var n: int = 0
	for c in scene.get_children():
		if _script_is(c, ITEM_SCRIPT):
			n += 1
	return n


func _physics_process(_delta: float) -> bool:
	_phys_frames += 1
	return false


func _process(delta: float) -> bool:
	if _stage < 0:
		_setup()
		_begin(0)
		return false
	var now: int = Time.get_ticks_usec()
	if _last_us > 0:
		_frame_us += float(now - _last_us)
		_frames += 1
		_phys_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_last_us = now
	_t += delta
	if _t - _stage_t0 < STAGE_SEC:
		return false
	_end(_stage)
	if _stage + 1 >= STAGES.size():
		_summary()
		return true
	_begin(_stage + 1)
	return false


func _begin(i: int) -> void:
	_stage = i
	_stage_t0 = _t
	var st: Array = STAGES[i]
	hud.visible = bool(st[1])
	sky.visible = bool(st[2])
	if bool(st[3]) and _item_nodes() == 0:
		_drop_items()
	_frame_us = 0.0
	_frames = 0
	_phys_ms = 0.0
	_hud_draws = 0
	_sky_draws = 0
	_hud_us0 = int(hud.get("stat_us")) if "stat_us" in hud else 0
	_hud_fr0 = int(hud.get("stat_frames")) if "stat_frames" in hud else 0
	_sky_us0 = int(sky.get("stat_us")) if "stat_us" in sky else 0
	_sky_fr0 = int(sky.get("stat_frames")) if "stat_frames" in sky else 0
	_last_us = 0
	var isc: GDScript = load(ITEM_SCRIPT)
	_item_us0 = int(isc.stat_us) if "stat_us" in isc else 0
	_item_ticks0 = int(isc.stat_ticks) if "stat_us" in isc else 0
	_phys_frames = 0
	_map_us0 = int(hud.get("stat_map_us")) if "stat_map_us" in hud else 0
	_hint_us0 = int(hud.get("stat_hint_us")) if "stat_hint_us" in hud else 0


func _end(i: int) -> void:
	var st: Array = STAGES[i]
	var secs: float = maxf(0.001, _t - _stage_t0)
	var fr: float = maxf(1.0, float(_frames))
	var line: String = "%-24s кадр %6.3f мс  физика %6.3f мс  перерисовок/с: HUD %5.1f, небо %5.1f" % [
		String(st[0]), _frame_us / fr / 1000.0, _phys_ms / fr,
		float(_hud_draws) / secs, float(_sky_draws) / secs]
	if "stat_us" in hud:
		var hf: float = maxf(1.0, float(int(hud.get("stat_frames")) - _hud_fr0))
		var sf: float = maxf(1.0, float(int(sky.get("stat_frames")) - _sky_fr0)) if "stat_us" in sky else 1.0
		var hus: float = float(int(hud.get("stat_us")) - _hud_us0) / hf
		var sus: float = float(int(sky.get("stat_us")) - _sky_us0) / sf if "stat_us" in sky else 0.0
		line += "  | HUD %6.1f мкс/кадр, небо %6.1f мкс/кадр" % [hus, sus]
		if "stat_map_us" in hud:
			line += " (миникарта %5.1f, подсказки %5.1f)" % [
				float(int(hud.get("stat_map_us")) - _map_us0) / hf,
				float(int(hud.get("stat_hint_us")) - _hint_us0) / hf]
	if bool(st[3]):
		line += "  | узлов-предметов: %d" % _item_nodes()
		var isc: GDScript = load(ITEM_SCRIPT)
		if "stat_us" in isc:
			var ticks: float = maxf(1.0, float(int(isc.stat_ticks) - _item_ticks0))
			var phys: float = maxf(1.0, float(_phys_frames))
			line += ", предметы %.1f мкс/физ.кадр (%.2f мкс на предмет)" % [
				float(int(isc.stat_us) - _item_us0) / phys,
				float(int(isc.stat_us) - _item_us0) / ticks]
	print(line)
	if i > 0:
		var key: String = String(st[0])
		if not _results.has(key):
			_results[key] = []
		_results[key].append(_frame_us / fr / 1000.0)


func _avg(key: String) -> float:
	var a: Array = _results.get(key, [])
	if a.is_empty():
		return 0.0
	var s: float = 0.0
	for v in a:
		s += float(v)
	return s / float(a.size())


func _summary() -> void:
	var on: float = _avg("всё включено")
	print("")
	print("=== СВОДКА (%d построек) ===" % world.machines.size())
	print("кадр, всё включено:   %6.3f мс" % on)
	print("кадр, HUD выключен:   %6.3f мс  → HUD стоит ~%6.3f мс/кадр" % [_avg("HUD выключен"), on - _avg("HUD выключен")])
	print("кадр, небо выключено: %6.3f мс  → небо стоит ~%6.3f мс/кадр" % [_avg("небо выключено"), on - _avg("небо выключено")])
	print("узлов-предметов после %d выпавших (%.0f с): %d" % [ITEMS, STAGE_SEC, _item_nodes()])
	print("узлов в дереве: %d" % get_node_count())
