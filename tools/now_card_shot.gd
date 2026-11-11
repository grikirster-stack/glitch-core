extends SceneTree
## Кадр карточки «Сейчас» (#160): docs/img/shots/now_card.png.
##
## Headless не рисует. Окно за экраном, без звука; скрипт сам выходит.
##
##   timeout 120 /tmp/godot47/Godot --path . --audio-driver Dummy --disable-vsync \
##         --fixed-fps 60 --windowed --position -10000,-10000 --resolution 1280x720 \
##         --script res://tools/now_card_shot.gd -- --seed=31337
##
## Кадр: одна карточка (картинка, ≤ 6 слов, счётчик «0 / 6»), стрелка к цели.
## Подсказка управления на кадре погашена (game_time 30).

const OUT: String = "res://docs/img/shots/now_card.png"
const HARD_LIMIT: float = 18.0

var scene: Node = null
var _elapsed: float = 0.0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("now_card_shot: headless не рендерит — нужен прогон с окном за экраном")
		quit(1)
		return
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	root.position = Vector2i(-10000, -10000)
	_boot.call_deferred()


func _boot() -> void:
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	scene = main_scene.instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > HARD_LIMIT:
		push_error("now_card_shot: превышен лимит %.0f с — выходим" % HARD_LIMIT)
		quit(2)
	return false


func _run() -> void:
	var game: Node = root.get_node("Game")
	var world: Node = root.get_node("World")
	scene.set("scenario_mode", true)
	game.set("scenario_mode", true)
	game.set("game_time", 30.0)          ## подсказка управления уже погасла
	game.set("time_of_day", 0.40)        ## день: без скобок ночи
	root.size = Vector2i(1280, 720)
	var hud: Node = root.get_node("UI").get("hud")
	if hud == null:
		push_error("now_card_shot: HUD нет")
		quit(1)
		return
	hud.set("notes", [])
	await _frames(12)

	var p: Node2D = scene.get("player")
	var tile: int = int(world.TILE)
	var bx: int = int(world.beacon_cell.x)
	var base: int = int(world.beacon_cell.y) + 1
	p.set_physics_process(false)
	p.set_process(false)
	# В стороне от терминалов базы: иначе подсказка «нет питания» рисуется у хотбара.
	p.global_position = Vector2(float((bx + 18) * tile) + 8.0, float((base + 10) * tile) + 14.0)
	p.set("vel", Vector2.ZERO)
	var cam: Camera2D = p.get("camera")
	cam.zoom = Vector2(2.2, 2.2)
	cam.reset_smoothing()
	# Игра не тикает: иначе каждый кадр шлёт «Цель 1/3» и затирает карточку.
	game.set_process(false)
	game.set("state", 1)             ## PLAYING — HUD рисует карточку
	game.set("game_time", 30.0)      ## подсказка управления уже погасла
	hud.call("_compute_tracker")
	_pin_card(hud, world, bx, base)
	await _frames(8)
	_pin_card(hud, world, bx, base)
	await _frames(2)
	cam.reset_smoothing()
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null or img.is_empty():
		push_error("now_card_shot: пустой кадр")
		quit(1)
		return
	var err: int = img.save_png(ProjectSettings.globalize_path(OUT))
	print("снято: %s (%dx%d), код %d; карточка «%s» %d / %d" % [
		OUT, img.get_width(), img.get_height(), err,
		hud.get("card_text"), int(hud.get("card_have")), int(hud.get("card_need"))])
	quit(0 if err == OK else 1)


## Зафиксировать карточку кадра и погасить всё, что рисуется строками под ней.
func _pin_card(hud: Node, world: Node, bx: int, base: int) -> void:
	var ids: GDScript = load("res://scripts/core/ids.gd")
	hud.set("card_text", "Накопай хлама")
	hud.set("card_have", 0)
	hud.set("card_need", 6)
	hud.set("card_icon", int(ids.I.SCRAP))
	hud.set("card_at", world.cell_to_world(Vector2i(bx + 28, base)))
	hud.set("tutorial_text", "")
	hud.set("hint_text", "")
	hud.set("mission_lines", [])
	hud.set("tracker_title", "")
	hud.set("tracker_detail", "")
	hud.set("notes", [])
	hud.set("_state_t", 10.0)           ## не пересчитать карточку до кадра
	hud.set("_lay_sig", -1)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
