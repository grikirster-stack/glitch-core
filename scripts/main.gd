extends Node2D
## Точка входа: генерация мира, игрок, световой цикл. Волны фантомов ведёт Threat (#27).

var player: Player
var world_fx: WorldFX
var tint: CanvasModulate
var end_screen: EndScreen
var wave: int = 0
var seed_value: int = 0
var _shot_taken: bool = false
var _args: PackedStringArray = PackedStringArray()
## Режим сценария: директор угрозы молчит, фантомов создаёт сам сценарий.
var scenario_mode: bool = false


func _ready() -> void:
	_args = OS.get_cmdline_user_args()
	seed_value = randi()
	for a in _args:
		if a.begins_with("--seed="):
			seed_value = int(a.substr(7))

	# Список сценариев печатаем до генерации мира — так быстрее.
	var scenarios: Array = _scenario_args()
	if scenarios.has("list"):
		_print_scenarios()
		get_tree().quit(0)
		return

	# Печать лора по сиду для ревью текста (мир не нужен, поэтому до его генерации):
	# godot --headless --path . -- --lore-dump --seed=31337
	if _args.has("--lore-dump"):
		load("res://tools/lore_dump.gd").dump(seed_value)
		get_tree().quit(0)
		return

	Game.reset_run()
	Threat.reset()
	World.generate(seed_value)
	Game.tasks_total = World.terminals.size()

	var sky: SkyBackdrop = SkyBackdrop.new()
	add_child(sky)

	world_fx = WorldFX.new()
	add_child(world_fx)
	UI.world_fx = world_fx
	add_child(FogLayer.new())   # туман войны (#59), поверх мира и WorldFX

	tint = CanvasModulate.new()
	add_child(tint)

	player = Player.new()
	player.add_to_group("player")
	add_child(player)
	player.global_position = World.spawn_point
	Game.player = player
	UI.bind(player)

	# Экран финала/смерти — в своём CanvasLayer поверх HUD (#32): под Node2D сцены
	# он рисовался в мировых координатах и уходил под туман войны.
	var end_layer: CanvasLayer = CanvasLayer.new()
	end_layer.layer = EndScreen.LAYER
	add_child(end_layer)
	end_screen = EndScreen.new()
	end_layer.add_child(end_screen)
	end_screen.restart_requested.connect(_restart)
	Game.state_changed.connect(_on_state_changed)
	_setup_respawn()
	add_child(TouchControls.new())   # сенсорное управление (#81): сенсорный экран или --touch

	# Стартовый набор
	player.inv.add(IDs.I.LAMP, 3)
	player.inv.add(IDs.I.COAL, 6)
	player.inv.add(IDs.I.IRON_PLATE, 2)
	player.inv.add(IDs.I.COPPER_ORE, 4)

	Game.notify("Экспедиция «Кербер-9». Связь с орбитой потеряна.", Color(0.8, 0.9, 1.0))
	Game.notify("Цель: собрать релей-ядро и улететь. Начните с добычи руды.", Color(0.5, 0.95, 0.8))
	Game.notify("Задания у терминалов дают данные. Копать — ЛКМ, строить — ПКМ.", Color(0.85, 0.85, 0.7))

	# Автотест логики: godot --path . -- --test
	if _args.has("--test") and scenarios.is_empty():
		var runner: Node = load("res://tools/test_runner.gd").new()
		add_child(runner)
		runner.start(self)

	# Игровые сценарии: godot --path . -- --scenario=walk,mining
	if not scenarios.is_empty():
		scenario_mode = true
		Game.scenario_mode = true   # директор угрозы (Threat) читает флаг отсюда
		var srunner: ScenarioRunner = ScenarioRunner.new()
		add_child(srunner)
		srunner.start(self, scenarios)


## Имена сценариев из --scenario=walk,mining
func _scenario_args() -> Array:
	var out: Array = []
	for a in _args:
		if not a.begins_with("--scenario="):
			continue
		for part in String(a.substr(11)).split(",", false):
			var name: String = String(part).strip_edges()
			if name != "":
				out.append(name)
	return out


## Печать списка сценариев (удобно для CI и для человека).
func _print_scenarios() -> void:
	print("Доступные сценарии:")
	for name in ScenarioRunner.scenario_names():
		print("  %-16s %s" % [name, ScenarioRunner.scenario_desc(name)])


func _process(_delta: float) -> void:
	if tint == null:
		return
	# Световой цикл
	var dl: float = Game.daylight()
	tint.color = Color(0.26, 0.30, 0.50).lerp(Color(1.0, 1.0, 1.0), dl)

	if _args.has("--shot") and not _shot_taken and Game.game_time > 2.0:
		_shot_taken = true
		_take_screenshot()


func _restart() -> void:
	get_tree().reload_current_scene()


func _on_state_changed(s: int) -> void:
	if s == Game.State.DEAD:
		end_screen.show_end("ТЕБЯ НАШЛИ", Lore.epitaph(), Color(0.92, 0.28, 0.34), _stats())
	elif s == Game.State.WON:
		end_screen.show_victory(Lore.epilogue(Game.epilogue_stats()), _stats())


func _stats() -> Array:
	return [
		"Добыто блоков: %d" % Game.stats_mined,
		"Изготовлено предметов: %d" % Game.stats_crafted,
		"Уничтожено фантомов: %d" % Game.stats_kills,
		"Выполнено заданий: %d из %d" % [Game.tasks_done, Game.tasks_total],
		"Смертей: %d" % Game.stats_deaths,
		"Время в игре: %d:%02d" % [int(Game.game_time) / 60, int(Game.game_time) % 60],
	]


func _take_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = ProjectSettings.globalize_path("res://_shot.png")
	img.save_png(path)
	print("SCREENSHOT: ", path)
	get_tree().quit()


# ------------------------------------------------- СМЕРТЬ И РЕСПАУН (ADR-001 § 4.8, #29)
## --hardcore — пермасмерть: смерть заканчивает забег (экран с эпитафией и итогами).
## Без флага: экран «ТЕБЯ НАШЛИ» с эпитафией, через Balance.RESPAWN_DELAY — респаун
## в капсуле на базе, время прыгает к рассвету (ночь проиграна). Мешок с хотбаром
## остаётся на месте смерти (Player.drop_hotbar_bag).
var hardcore: bool = false


func _setup_respawn() -> void:
	hardcore = _args.has("--hardcore")
	player.died.connect(_on_player_died)


func _on_player_died() -> void:
	if hardcore:
		Game.set_state(Game.State.DEAD)
		return
	end_screen.show_death(Lore.epitaph(), Balance.RESPAWN_DELAY)
	get_tree().create_timer(Balance.RESPAWN_DELAY).timeout.connect(_respawn)


func _respawn() -> void:
	if not player.dead or Game.state != Game.State.PLAYING:
		return
	player.respawn_at(World.spawn_point)
	end_screen.hide_end()
	# К рассвету: ставим время чуть раньше конца ночи — Game сам перейдёт рубеж
	# и начнёт новую смену (day_number, «Смена N», роспуск фантомов — по сигналу).
	Game.time_of_day = Balance.NIGHT_END - 0.0005
	Game.notify("Капсула на базе. Мешок с вещами остался на месте гибели.", Color(1.0, 0.85, 0.6))
