extends Node
## Кадр главы 5 «Солнце» (#179). Вешается на корень из main.gd по флагу
## --shot=chapter_light_5. Ночь, одна карточка, поле видно.
##
##   timeout 120 /tmp/godot47/Godot --path . --audio-driver Dummy --disable-vsync \
##     --windowed --position -10000,-10000 --resolution 1280x720 \
##     -- --shot=chapter_light_5 --seed=31337

const OUT: String = "res://docs/img/shots/chapter_light_5.png"

var _done: bool = false


func _ready() -> void:
	get_window().position = Vector2i(-10000, -10000)
	_run.call_deferred()


func _run() -> void:
	await _frames(6)
	if not Game.in_mission() or String(Game.mission.id) != "sun":
		push_error("chapter_light_5_shot: глава не «Солнце»")
		get_tree().quit(1)
		return
	var mission: Mission = Game.mission
	# Ночь и этап «Переживи ночь»: одна карточка.
	mission.stage = 4
	mission.hold_time = -1.0
	Game.time_of_day = 0.80
	# Подсказка клавиш гаснет после 22 с. Кадр — ночь и карточка, не учебник.
	Game.game_time = 30.0
	var acc: Accumulator = World.machines.get(LightLate.at(LightLate.ACCUM)) as Accumulator
	if acc == null:
		acc = CampaignBase.put("Accumulator", LightLate.at(LightLate.ACCUM), {"dir": 2}) as Accumulator
	if acc != null:
		acc.dir = 2
		acc.color = Beams.B
		acc.stored = 40.0
		acc.set_mode(Accumulator.MODE_EMIT)
	var burner: Burner = CampaignBase.put("Burner", LightLate.at(LightLate.BURNER), {"dir": 2}) as Burner
	if burner != null:
		burner.dir = 2
		burner.add_fuel(IDs.I.CRYSTAL, 1)
	if World.beams != null:
		World.beams.note_machines()
		World.beams.rebuild()
	var pharos: Pharos = World.machines.get(LightLate.at(LightLate.PHAROS)) as Pharos
	if pharos != null and pharos.color != Beams.B:
		pharos.beam_receive(Beams.B)
	var echo_script: GDScript = load("res://scripts/entities/phantom.gd")
	var burr = echo_script.create("burrower")
	burr.player = Game.player
	get_tree().current_scene.add_child(burr)
	burr.global_position = World.cell_to_world(LightLate.at(LightLate.PHAROS) + Vector2i(3, 0))
	var player: Node2D = Game.player
	if player != null:
		# Ниже машин: подсказка E не должна закрывать маяк.
		player.global_position = World.cell_to_world(LightLate.at(LightLate.PHAROS) + Vector2i(6, 4))
		var cam: Camera2D = player.get("camera")
		if cam != null:
			cam.position_smoothing_enabled = false
			cam.zoom = Vector2(3.0, 3.0)
			cam.global_position = World.cell_to_world(LightLate.at(LightLate.PHAROS) + Vector2i(4, 1))
			cam.reset_smoothing()
	mission.evaluate()
	var hud: Node = UI.hud if UI != null else null
	if hud != null:
		hud.set("tutorial_step", 5)
		hud.set("tutorial_text", "")
		hud.set("hint_text", "")
		hud.set("notes", [])
		hud.set("hint_text", "")
		hud.call("_compute_tracker")
	await _frames(8)
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err: int = img.save_png(path)
	var card: String = String(hud.card_text) if hud != null else ""
	print("chapter_light_5_shot: %s (%d), карточка «%s», маяк %d" % [
			path, err, card, pharos.color if pharos != null else -1])
	_done = true
	get_tree().quit(0 if err == OK and card == "Переживи ночь" else 1)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
