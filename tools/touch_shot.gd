extends SceneTree
## Скриншот раскладки сенсорного управления (#81) для README: docs/img/touch_controls.png.
##
## Запуск (headless не рендерит, поэтому окно ЗА ПРЕДЕЛАМИ ЭКРАНА, без звука;
## скрипт сам выходит, ≤ 20 с):
##   godot --path . --audio-driver Dummy --windowed --position -10000,-10000 \
##         --resolution 1280x720 --script res://tools/touch_shot.gd -- --touch --seed=31337
##
## Флаг --touch включает TouchControls и на ПК без сенсорного экрана. Кадр — день,
## подсказка управления погасла, стартовые уведомления ещё видны (видно, что
## кнопки их не перекрывают), джойстик чуть отклонён вправо.

const OUT: String = "res://docs/img/touch_controls.png"
const HARD_LIMIT: float = 18.0

var scene: Node = null
var _elapsed: float = 0.0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("touch_shot: headless не рендерит — нужен прогон с окном за экраном")
		quit(1)
		return
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	root.position = Vector2i(-10000, -10000)
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	scene = main_scene.instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > HARD_LIMIT:
		push_error("touch_shot: превышен лимит %.0f с — выходим" % HARD_LIMIT)
		quit(2)
	return false


func _run() -> void:
	var game: Node = root.get_node("Game")
	scene.set("scenario_mode", true)
	game.set("scenario_mode", true)
	game.set("game_time", 30.0)              ## подсказка управления уже погасла
	game.set("time_of_day", 0.40)
	root.size = Vector2i(1280, 720)
	await _frames(20)
	var tc: Node = get_first_node_in_group("touch_controls")
	if tc == null or not bool(tc.get("enabled")):
		push_error("touch_shot: сенсорное управление не включено (нужен --touch)")
		quit(1)
		return
	var p: Node2D = scene.get("player")
	p.set_physics_process(false)
	p.get("camera").reset_smoothing()
	tc.set("stick_vec", Vector2(0.65, 0.0))
	await _frames(30)
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null or img.is_empty():
		push_error("touch_shot: пустой кадр")
		quit(1)
		return
	var err: int = img.save_png(ProjectSettings.globalize_path(OUT))
	print("снято: %s (%dx%d), код %d" % [OUT, img.get_width(), img.get_height(), err])
	quit(0 if err == OK else 1)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
