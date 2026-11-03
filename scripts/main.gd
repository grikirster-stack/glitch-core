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
	if _net_boot():   # СЕТЬ (ADR-002): меню или вход по сети — мир позже (_start)
		return
	_start()


func _start() -> void:
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
	add_child(Emission.new())   # слой эмиссии (ADR-003 V3): свечение не темнеет под tint
	add_child(GlitchFx.new())   # глитч по событию и «меньше глитча» (ADR-003 V7, #108)

	player = Player.new()
	player.look = int(Net.local_profile.get("look", 0)) & 0xFFFF   # вид из профиля (MP-B, #87)
	_net_hero(player)   # СЕТЬ (ADR-002): роль своего героя — до _ready (камера только у своего)
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

	give_starter_kit(player)

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

	_net_start()   # СЕТЬ (ADR-002): --mp-host, сетевые сценарии --mp-scenario
	_menu_load()   # МЕНЮ «Загрузить» (#132): одиночная игра из сохранения


## Стартовый набор героя (свой и, в сети, каждого товарища — MP-D, #89).
func give_starter_kit(p: Player) -> void:
	p.inv.add(IDs.I.LAMP, 3)
	p.inv.add(IDs.I.COAL, 6)
	p.inv.add(IDs.I.IRON_PLATE, 2)
	p.inv.add(IDs.I.COPPER_ORE, 4)


## Имена сценариев из --scenario=walk,mining
func _scenario_args() -> Array:
	var out: Array = []
	for a in _args:
		if not a.begins_with("--scenario="):
			continue
		for part in String(a.substr(11)).split(",", false):
			var name: String = String(part).strip_edges()
			if name == "all":   # --scenario=all — весь реестр по порядку (для CI)
				out.append_array(ScenarioRunner.scenario_names())
			elif name != "":
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
	# Световой цикл: амбиент день / сумерки / ночь (ADR-003 V3) — SkyBackdrop.ambient
	tint.color = SkyBackdrop.ambient(Game.daylight())

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
	if net_coop != null:   # СЕТЬ (MP-I): итоги команды и личные по игрокам
		return _base_stats() + net_coop.stats_lines()
	return _base_stats()


func _base_stats() -> Array:
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
	if _net_coop_died():   # СЕТЬ (ADR-002 D11): смерть в сети — NetCoop, часы не двигаются
		return
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


# ------------------------------------------------- СЕТЬ (ADR-002, MP-A #86)
## Крюк меню (§ 4.6): без пользовательских аргументов, не под --script и без сессии —
## меню, если его сцена есть (MP-B, #87); иначе старт как раньше. Любой аргумент —
## немедленный старт. Инструменты --script (save_test, lore_test, …) сами грузят
## main.tscn, часто без аргументов: у их SceneTree свой скрипт — меню им не нужно.
## --mp-join=ip[:порт]: сначала рукопожатие (сид приходит от хоста), мир — после него.
## --mp-host[=порт] [--mp-bind=ip]: сервер поднимается, когда мир готов.
## --mp-scenario=<имя|all>: харнесс сетевых сценариев (tools/mp/mp_runner.gd).
## Без этих флагов ни одна строка ниже не меняет одиночную игру.
const MENU_SCENE: String = "res://scenes/menu.tscn"
## Разобранные флаги сети (Net.parse_args).
var _net: Dictionary = {}


## true — старт мира отложен (ждём рукопожатия) или сцена уходит в меню.
func _net_boot() -> bool:
	if _args.is_empty() and Net.session.is_empty() and get_tree().get_script() == null \
			and ResourceLoader.exists(MENU_SCENE):
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE)
		return true
	_net = Net.parse_args(_args)
	Net.apply_args(_net)
	_net_session_args()
	if _net.has("join_ip") and not Net.is_client():
		Net.session_started.connect(_on_net_joined, CONNECT_ONE_SHOT)
		Net.connection_failed.connect(_on_net_join_failed, CONNECT_ONE_SHOT)
		print("СЕТЬ: подключение к %s:%d" % [_net["join_ip"], int(_net["join_port"])])
		if Net.join(String(_net["join_ip"]), int(_net["join_port"])) != OK:
			_on_net_join_failed.call_deferred(Net.last_error)
		return true
	return false


## Сессия, заданная меню (MP-B) или рукопожатием: сид и --hardcore — теми же флагами,
## что из командной строки (последний --seed= главнее).
func _net_session_args() -> void:
	if Net.session.is_empty():
		return
	var s: int = int(Net.session.get("seed", -1))
	if s >= 0:
		_args.append("--seed=%d" % s)
	if bool(Net.session.get("hardcore", false)) and not _args.has("--hardcore"):
		_args.append("--hardcore")


func _on_net_joined() -> void:
	if Net.connection_failed.is_connected(_on_net_join_failed):
		Net.connection_failed.disconnect(_on_net_join_failed)
	print("СЕТЬ: вход как «%s», слот %d, сид %d, %d мс" % [Net.session.get("nick", ""),
			int(Net.session.get("slot", -1)), int(Net.session.get("seed", 0)), Net.join_ms])
	Net.session_ended.connect(_on_net_ended)
	_net_session_args()
	_start()


func _on_net_join_failed(reason: String) -> void:
	if Net.session_started.is_connected(_on_net_joined):
		Net.session_started.disconnect(_on_net_joined)
	print("СЕТЬ: вход не удался: %s" % reason)
	if _net.has("scenario"):
		_net_runner()        # харнесс: клиент сам проверяет причину отказа, мира нет
	elif ResourceLoader.exists(MENU_SCENE):
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE)
	else:
		get_tree().quit(1)


func _on_net_ended(reason: String) -> void:
	if _net.has("scenario"):
		return               # харнесс сам решает, провал ли это
	print("СЕТЬ: сессия окончена: %s" % reason)
	if ResourceLoader.exists(MENU_SCENE):
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE)
	else:
		get_tree().quit(0)


## Мир готов: --mp-host поднимает сервер, --mp-scenario запускает харнесс.
func _net_start() -> void:
	_net_players_start()
	_net_inv_start()
	_net_team_start()   # MP-J (#95): перекличка, двойник среди своих
	_net_coop_start()
	if Net.is_host():
		_net_load_save()   # хост из меню (лобби MP-H): сервер уже поднят
	if _net.has("scenario"):
		scenario_mode = true
		Game.scenario_mode = true   # фантомов, как и в --scenario, создаёт сам сценарий
		_net_runner()
		return
	if _net.has("host_port") and not Net.is_host():
		var port: int = int(_net["host_port"])
		var bind: String = String(_net.get("bind", "*"))
		var title: String = "Экспедиция " + String(Net.local_profile.get("nick", Net.DEFAULT_NICK))
		if Net.host(port, bind, seed_value, title) == OK:
			print("СЕТЬ: хост %s:%d, сид %d" % [bind, port, seed_value])
			_net_load_save()
		else:
			print("СЕТЬ: " + Net.last_error)


func _net_runner() -> void:
	var r: MpRunner = MpRunner.new()
	add_child(r)
	r.start_mp(self, _net)


# ------------------------------------------------- СЕТЬ: ИГРОКИ (ADR-002 § 4.2.3, MP-D #89)
## Герои по пирам ведёт NetPlayers (scripts/net/net_players.gd): прокси у хоста,
## марионетки у клиента. Без сети узла нет, свой герой — LOCAL, всё как раньше.
var net_players: NetPlayers = null


## Свой герой: LOCAL (одиночная, хост) или OWNER (клиент); Game.players — все герои.
func _net_hero(p: Player) -> void:
	p.net_role = Player.NetRole.OWNER if Net.is_client() else Player.NetRole.LOCAL
	p.peer_id = Net.my_id()
	p.nick = String(Net.session.get("nick", Net.local_profile.get("nick", "")))
	p.net_respawned.connect(_on_net_respawned)
	Game.local_player = p
	Game.players = [p]


## Сеть есть или будет (--mp-host, --mp-scenario): NetPlayers следит за сессией сам.
func _net_players_start() -> void:
	if net_players != null:
		return
	if not (Net.is_online() or _net.has("scenario") or _net.has("host_port")):
		return
	net_players = NetPlayers.new()
	add_child(net_players)
	net_players.start(self)


## Хост возродил своего героя клиента (OWN): экран смерти прочь.
func _on_net_respawned() -> void:
	if end_screen != null:
		end_screen.hide_end()


# ------------------------------------------------- СЕТЬ: ИНВЕНТАРИ (ADR-002 § 4.2.7, MP-G #91)
## Команды инвентаря, крафта, сундуков и исследований клиента выполняет хост: InvOps
## (scripts/net/inv_ops.gd). Без сети узла нет — панель зовёт статические функции InvOps.
var net_inv: InvOps = null


func _net_inv_start() -> void:
	if net_inv != null or net_players == null:
		return
	net_inv = InvOps.new()
	add_child(net_inv)
	net_inv.start(self)


# ------------------------------------------------- СЕТЬ: КООПЕРАТИВ (ADR-002 § 4.7, § 4.9, MP-I #94)
## Смерть, респаун, вайп, зритель --hardcore, парковка по uid и автосохранение на
## рассвете ведёт NetCoop (scripts/net/net_coop.gd). Без сети узла нет, а смерть,
## респаун и сохранение — прежние (_on_player_died, _respawn, Save).
## Загрузка сетевого сохранения — при создании игры: флаг --mp-load=<слот> или
## Net.session["load"] (меню); F9 в сети выключена.
var net_coop: NetCoop = null


func _net_coop_start() -> void:
	if net_coop != null or net_players == null:
		return
	net_coop = NetCoop.new()
	add_child(net_coop)
	net_coop.start(self)


## true — свой герой погиб в сети: решает NetCoop (хост) или ждём хоста (клиент).
func _net_coop_died() -> bool:
	if not Net.is_online() or net_coop == null:
		return false
	if Net.is_host():
		net_coop.on_hero_died(player)
	else:
		net_coop.on_own_died_client()
	return true


## Хост: загрузить сетевое сохранение (--mp-load=<слот> или Net.session["load"]).
func _net_load_save() -> void:
	var slot: String = String(Net.session.get("load", ""))
	for a in _args:
		if a.begins_with("--mp-load="):
			slot = a.substr(10).strip_edges()
	if slot == "":
		return
	if Save.load_net(slot):
		print("СЕТЬ: загружено сохранение «%s» (%.1f мс), игроков ждёт %d" % [slot,
				Save.last_load_ms, Net.parked.size()])
	else:
		print("СЕТЬ: сохранение «%s» не загружено: %s" % [slot, Save.last_error])


# ------------------------------------------------- СЕТЬ: КОМАНДА (ADR-002 § 4.8, MP-J #95)
## Перекличка (G), маска и «глюк» двойника, удар по своему — NetTeam
## (scripts/net/net_team.gd). Без сети узла нет.
var net_team: NetTeam = null


func _net_team_start() -> void:
	if net_team != null or net_players == null:
		return
	net_team = NetTeam.new()
	add_child(net_team)
	net_team.start(self)


# ------------------------------------------------- МЕНЮ «ЗАГРУЗИТЬ» (#132)
## Одиночная игра из меню «Загрузить»: Net.session = {mode: single, seed: сид файла,
## load: слот} — мир уже построен по сиду, слот кладётся поверх (Save.load_game, как F9).
## Ключ снимается: перезапуск (R после финала) — новый забег на том же сиде.
func _menu_load() -> void:
	if Net.is_online() or String(Net.session.get("mode", "")) != "single" or not Net.session.has("load"):
		return
	var slot: String = String(Net.session["load"])
	Net.session.erase("load")
	if Save.load_game(slot):
		print("МЕНЮ: загружено сохранение «%s» (%.1f мс), смена %d" % [slot, Save.last_load_ms,
				Game.day_number])
		Game.notify("Забег загружен: смена %d." % Game.day_number, Color(0.6, 1.0, 0.75))
	else:
		print("МЕНЮ: сохранение «%s» не загружено: %s" % [slot, Save.last_error])
		Game.notify("Загрузить нельзя: %s." % Save.last_error, Color(1.0, 0.6, 0.4))
