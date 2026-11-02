extends SceneTree
## A/B-замер: что именно жрёт кадр. На каждом этапе гасим по очереди
## оверлей света, весь WorldFX, HUD и небо — и смотрим, как падает время кадра.
## Запуск: godot --path . --script res://tools/perf_probe.gd

var scene: Node = null
var world: Node = null
var world_fx: Node = null
var hud: Node = null
var sky: Node = null
var elapsed: float = 0.0
var stage: int = 0
var stage_t: float = 0.0
var frame_acc: float = 0.0
var frame_n: int = 0
var fps_acc: float = 0.0


func _initialize() -> void:
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	scene = main_scene.instantiate()
	root.add_child(scene)
	current_scene = scene


## Ссылки берём на первом кадре: в _initialize сцена ещё не прошла _ready.
## SkyBackdrop по имени класса здесь не компилируется (он ссылается на автозагрузку
## Game, а в режиме --script её имени ещё нет) — узнаём небо по пути скрипта.
func _bind() -> void:
	world = root.get_node("World")
	world_fx = scene.get("world_fx")
	hud = root.get_node("UI").get("hud")
	for c in scene.get_children():
		var sc: Script = c.get_script()
		if sc != null and sc.resource_path == "res://scripts/ui/sky_backdrop.gd":
			sky = c


func _process(delta: float) -> bool:
	if hud == null:
		_bind()
	elapsed += delta
	frame_acc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	fps_acc += Performance.get_monitor(Performance.TIME_FPS)
	frame_n += 1
	if elapsed - stage_t < 15.0:
		return false
	var avg: float = frame_acc / maxf(1.0, float(frame_n))
	print("t=%5.1f  этап=%d  кадр=%7.2f мс  fps=%5.1f  свет=%4d  фантомов=%3d  узлов=%4d"
			% [elapsed, stage, avg, fps_acc / maxf(1.0, float(frame_n)),
			world.lights.size(),
			root.get_tree().get_nodes_in_group("phantom").size(),
			root.get_tree().get_node_count()])
	frame_acc = 0.0
	fps_acc = 0.0
	frame_n = 0
	stage_t = elapsed
	match stage:
		0:
			print("   >> выключаю оверлей света (WorldFX.light_overlay = false)")
			world_fx.light_overlay = false
		1:
			print("   >> выключаю весь WorldFX (visible = false)")
			world_fx.visible = false
		2:
			print("   >> выключаю HUD")
			hud.visible = false
		3:
			print("   >> выключаю небо")
			sky.visible = false
		4:
			print("   >> включаю всё обратно")
			world_fx.light_overlay = true
			world_fx.visible = true
			hud.visible = true
			sky.visible = true
		5:
			print("   >> выключаю только HUD (контроль)")
			hud.visible = false
		6:
			print("   >> всё включено (контроль)")
			hud.visible = true
		7:
			return true
	stage += 1
	return false
