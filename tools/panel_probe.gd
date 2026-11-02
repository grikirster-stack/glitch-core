extends SceneTree
## Замер отрисовки панели крафта (issue #28): сколько миллисекунд занимает
## один вызов InventoryPanel._draw() при 25 рецептах во вкладке.
##
## Запуск:
##   godot --headless --path . --script res://tools/panel_probe.gd -- --seed=31337
##
## Как меряем. Наследник панели (собирается из исходника на лету) оборачивает
## _draw() в Time.get_ticks_usec(): super() — ровно та отрисовка, что в игре.
## Ручных рецептов дописывается до 25 (копии настоящих, с теми же узлами
## технологий), панель перерисовывается каждый кадр, первые WARMUP кадров
## отбрасываются. Печатается среднее, p95 и максимум на вкладку.
##
## В режиме --script имена автозагрузок на этапе компиляции недоступны,
## поэтому всё берётся через get_node() и load() (см. tools/README_TESTS.md).

const WARMUP: int = 30
const FRAMES: int = 600
const TARGET_RECIPES: int = 25

const PROBE_SRC: String = """extends "res://scripts/ui/inventory_panel.gd"
var samples: Array = []
func _draw() -> void:
	var t0: int = Time.get_ticks_usec()
	super()
	samples.append(Time.get_ticks_usec() - t0)
"""

var scene: Node = null
var panel: Control = null
var frame: int = 0
var tabs: Array = []          ## вкладки, которые есть в этой версии панели
var tab_i: int = 0
var results: Array = []


func _initialize() -> void:
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	scene = main_scene.instantiate()
	root.add_child(scene)
	current_scene = scene


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 20:
		_setup()
		return false
	if panel == null:
		return false
	var s: Array = panel.get("samples")
	if s.size() >= WARMUP + FRAMES:
		_report_tab(s.slice(WARMUP))
		tab_i += 1
		if tab_i >= tabs.size():
			_summary()
			return true
		panel.set("station_tab", int(tabs[tab_i]))
		panel.set("scroll", 0)
		panel.set("samples", [])
	panel.queue_redraw()
	return false


func _setup() -> void:
	var db: Node = root.get_node("DB")
	var hand: Array = db.recipes_for("hand")
	var n: int = hand.size()
	var i: int = 0
	while n < TARGET_RECIPES:
		var copy: Dictionary = (hand[i % hand.size()] as Dictionary).duplicate(true)
		copy["name"] = String(copy["name"]) + " (копия)"
		db.recipes.append(copy)
		n += 1
		i += 1
	print("ручных рецептов: %d" % db.recipes_for("hand").size())
	var scr: GDScript = GDScript.new()
	scr.source_code = PROBE_SRC
	scr.reload()
	panel = Control.new()
	panel.set_script(scr)
	var ui: Node = root.get_node("UI")
	ui.add_child(panel)
	panel.open(scene.get("player"))
	tabs = [0]
	var tab_names: Array = panel.get("TABS")
	# Вкладка «Исследования» есть только после #28.
	for t in tab_names.size():
		if String(tab_names[t]) == "Исследования":
			tabs.append(t)
	panel.set("station_tab", int(tabs[0]))


func _report_tab(s: Array) -> void:
	var sorted: Array = s.duplicate()
	sorted.sort()
	var sum: int = 0
	for v in sorted:
		sum += int(v)
	var avg: float = float(sum) / float(sorted.size()) / 1000.0
	var p95: float = float(sorted[int(sorted.size() * 0.95)]) / 1000.0
	var mx: float = float(sorted[sorted.size() - 1]) / 1000.0
	var tab_names: Array = panel.get("TABS")
	var name: String = String(tab_names[int(tabs[tab_i])])
	results.append([name, avg, p95, mx])
	print("вкладка «%s»: отрисовка среднее %.3f мс, p95 %.3f мс, максимум %.3f мс (кадров %d)"
			% [name, avg, p95, mx, sorted.size()])


func _summary() -> void:
	print("ИТОГ: замер панели готов, вкладок %d" % results.size())
	quit(0)
