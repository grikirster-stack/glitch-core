class_name ScenarioRunner
extends Node
## Раннер игровых сценариев: бот проходит сценарий и проверяет результат.
##
## Сценарий — отдельный скрипт в tools/scenarios/ (наследник ScenarioBase).
## Управление идёт через шов игрока (test_input), поэтому сценарий проверяет
## игру ровно так же, как её играет человек: раскладка клавиш, прицел мышью,
## удержание E, блокировка ввода при открытом инвентаре.
##
## Сценарий запускается в обычной игровой сцене: мир, игрок, физика, Game и
## World — всё как обычно, управление отдаёт сценарий.
##
## Формат вывода — тот же, что у tools/test_runner.gd, чтобы CI умел его
## разобрать. Ненулевой код возврата при провалах.

const DIR: String = "res://tools/scenarios/"
## Максимальное время на один сценарий (страховка от зависшего бота).
## Сценарий может задать свой предел ключом "timeout_ms" в REGISTRY.
const TIMEOUT_MS: int = 60000

const REGISTRY: Dictionary = {
	"smoke": {
		"file": "smoke.gd",
		"title": "дым",
		"desc": "сценарии вообще работают; пустой шов = обычная игра",
	},
	"walk": {
		"file": "walk.gd",
		"title": "ходьба",
		"desc": "бот идёт вправо, тормозит, не проходит сквозь стену",
	},
	"jump": {
		"file": "jump.gd",
		"title": "прыжок",
		"desc": "прыжок вверх, приземление, двойного прыжка нет",
	},
	"mining": {
		"file": "mining.gd",
		"title": "добыча",
		"desc": "навести мышь на тайл, держать ЛКМ, тайл сломан, выпал предмет",
	},
	"pickup": {
		"file": "pickup.gd",
		"title": "подбор",
		"desc": "подойти к выпавшему предмету — он исчез, инвентарь пополнился",
	},
	"craft": {
		"file": "craft.gd",
		"title": "крафт",
		"desc": "открыть панель, выбрать рецепт, скрафтить предмет",
	},
	"terminal": {
		"file": "terminal.gd",
		"title": "терминал",
		"desc": "терминал без питания: E — подсказка «нет питания», задание не засчитано",
	},
	"relay": {
		"file": "relay.gd",
		"title": "релей",
		"desc": "выдать детали, удерживать E, отсчёт и победа",
	},
	"night": {
		"file": "night.gd",
		"title": "ночь",
		"desc": "ночь, фантом идёт на игрока, hp падает",
	},
	"hide": {
		"file": "hide.gd",
		"title": "укрытие",
		"desc": "V — спрятаться в вентиляции, фантом не достаёт",
	},
	"emp": {
		"file": "emp.gd",
		"title": "импульс",
		"desc": "Q рядом с фантомом оглушает и отбрасывает его",
	},
	"noise": {
		"file": "noise.gd",
		"title": "шум",
		"desc": "бег громче ходьбы, стоя — тишина",
	},
	"inventory_block": {
		"file": "inventory_block.gd",
		"title": "блокировка инвентаря",
		"desc": "открыт инвентарь — ЛКМ и ПКМ по миру игнорируются",
	},
	# --- Исследования и журнал (#28)
	"tech_unlock": {
		"file": "tech_unlock.gd",
		"title": "исследования",
		"desc": "4 данных — T1 закрыт; 5 данных → T1 → рецепт сборщика доступен",
	},
	"journal_open": {
		"file": "journal_open.gd",
		"title": "журнал",
		"desc": "J открывает и закрывает журнал, ЛКМ по миру при этом игнорируется",
	},
	# --- Вода (#45) ---
	"fluid": {
		"file": "fluid.gd",
		"title": "вода",
		"desc": "не плёнка по ровной земле, наполняет яму, 1 порция невидима",
	},
	# ---- HUD и предметы на земле (#7) ----
	"hud_no_alloc": {
		"file": "hud_no_alloc.gd",
		"title": "HUD без аллокаций",
		"desc": "60 с простоя: 0 новых узлов, HUD/миникарта/небо не рисуются каждый кадр",
		"timeout_ms": 90000,
	},
	"hud_hints": {
		"file": "hud_hints.gd",
		"title": "подсказки HUD",
		"desc": "подсказка ТЭЦ/сундука появляется и пропадает сразу при 200 постройках",
	},
	"item_cleanup": {
		"file": "item_cleanup.gd",
		"title": "уборка предметов",
		"desc": "одинаковые предметы сливаются, по сроку жизни мигают и исчезают",
	},
	# --- Питание (#25, ADR-001 § 4.3) ---
	"power_budget": {
		"file": "power_budget.gd",
		"title": "бюджет мощности",
		"desc": "1 ТЭЦ + 4 бура — efficiency 0.75, бур медленнее на 25 %, браун-аут",
	},
	"power_switch": {
		"file": "power_switch.gd",
		"title": "рубильник",
		"desc": "E выключает ТЭЦ: 60 с без расхода угля, буры стоят",
	},
	"belt_coal": {
		"file": "belt_coal.gd",
		"title": "уголь с конвейера",
		"desc": "уголь по ленте доезжает до топки ТЭЦ",
	},
	# --- Мир: тайники руин (#35) ---
	"ruin_cache": {
		"file": "ruin_cache.gd",
		"title": "тайники руин",
		"desc": "в каждой руине сундук по роли хозяина и табличка; один сид — один тайник",
	},
	# --- Автоматизация (#30, ADR-001 § 4.2) ---
	"inserter_chain": {
		"file": "inserter_chain.gd",
		"title": "манипулятор",
		"desc": "сундук → манипулятор → лента → плавильня → лента → сундук: 10 слитков за ≤ 40 с",
		"timeout_ms": 90000,
	},
	"analyzer_data": {
		"file": "analyzer_data.gd",
		"title": "анализатор",
		"desc": "1 кристалл → +1 данные за 20 ± 1 с",
	},
	"deep_drill_reach": {
		"file": "deep_drill_reach.gd",
		"title": "глубинный бур",
		"desc": "руда с глубины 40 клеток; обычная буровая туда не достаёт",
	},
	# --- Игрок и терминалы (#29, ADR-001 § 4.6–4.8) ---
	"terminal_powered": {
		"file": "terminal_powered.gd",
		"title": "терминал под питанием",
		"desc": "ТЭЦ у терминала базы и руины: E — +5 данных и глава журнала",
	},
	"hide_limit": {
		"file": "hide_limit.gd",
		"title": "лимит укрытия",
		"desc": "через 6 с вентиляция выталкивает, повторно — через 10 с",
	},
	"respawn": {
		"file": "respawn.gd",
		"title": "смерть и респаун",
		"desc": "мешок с хотбаром на месте смерти, респаун на базе, время у рассвета; --hardcore",
	},
	"repair": {
		"file": "repair.gd",
		"title": "ремонт",
		"desc": "E с хламом по повреждённой машине: +20 HP за единицу",
	},
	# --- Плавильня и замок технологий (#57) ---
	"smelter_locked": {
		"file": "smelter_locked.gd",
		"title": "запертый вход станка",
		"desc": "без питания горнило тёмное; вход рецепта T1 не берут ни станок, ни манипулятор, ни E — после T1 берут",
	},
	# --- Фантомы и директор угрозы (#27) ---
	"swarm_targets_drill": {
		"file": "swarm_targets_drill.gd",
		"title": "рой идёт на бур",
		"desc": "стая летит к работающему буру и грызёт его, игрок не цель",
	},
	"shade_drains_gen": {
		"file": "shade_drains_gen.gd",
		"title": "тень дренирует ТЭЦ",
		"desc": "тень не боится света, у ТЭЦ сжигает уголь",
	},
	"burrower_digs_dirt": {
		"file": "burrower_digs_dirt.gd",
		"title": "копатель роет породу",
		"desc": "камень роет, железный блок — нет",
	},
	"doppel_freezes_under_gaze": {
		"file": "doppel_freezes_under_gaze.gd",
		"title": "двойник под взглядом",
		"desc": "смотришь — стоит; копаешь или отвернулся — идёт; имя над головой",
	},
	"threat_budget": {
		"file": "threat_budget.gd",
		"title": "бюджет ночи",
		"desc": "формулы § 4.5; ночь 1 ≤ 3 фантома, ночь 4 ≥ 6",
	},
	"vent_spawn": {
		"file": "vent_spawn.gd",
		"title": "спавн из вентиляций",
		"desc": "три ближайшие незапечатанные вентиляции, телеграф 2 с",
	},
	# --- Туман войны (#59) ---
	"fog_reveal": {
		"file": "fog_reveal.gd",
		"title": "туман войны",
		"desc": "в начале открыт только старт; по пути клетки открываются; дальние пещеры закрыты",
	},
	# --- Сохранение (#37) ---
	"save_load": {
		"file": "save_load.gd",
		"title": "сохранение и загрузка",
		"desc": "фабрика, F5, мир меняется, F9 — всё как при F5, фабрика плавит дальше",
	},
}

var scene: Node = null
var checks: int = 0
var fails: int = 0
var scenarios_total: int = 0

var _queue: Array = []
var _current: ScenarioBase = null
var _started_ms: int = 0
var _timeout_ms: int = TIMEOUT_MS


# ------------------------------------------------------------------ РЕЕСТР

## Имена всех доступных сценариев.
static func scenario_names() -> Array:
	return REGISTRY.keys()


## Короткое описание сценария.
static func scenario_desc(name: String) -> String:
	return String(REGISTRY.get(name, {}).get("desc", ""))


# ------------------------------------------------------------------ ЗАПУСК

## Запустить список сценариев (по одному, каждый — на свежем мире).
func start(main_scene: Node, names: Array) -> void:
	scene = main_scene
	_queue = names.duplicate()
	scenarios_total = _queue.size()
	_next_scenario()


func _next_scenario() -> void:
	if _current != null and is_instance_valid(_current):
		_current.queue_free()
		_current = null
	if _queue.is_empty():
		_summary()
		return
	var name: String = String(_queue.pop_front())
	if not REGISTRY.has(name):
		print("== Сценарий: %s ==" % name)
		ok("сценарий есть в реестре", false)
		_next_scenario()
		return
	print("== Сценарий: %s ==" % String(REGISTRY[name]["title"]))
	_reset_world()
	var sc: ScenarioBase = load(DIR + String(REGISTRY[name]["file"])).new()
	sc.setup(self, scene)
	add_child(sc)
	_current = sc
	_started_ms = Time.get_ticks_msec()
	_timeout_ms = int(REGISTRY[name].get("timeout_ms", TIMEOUT_MS))
	sc.done.connect(_on_scenario_done.bind(sc))
	sc.run()


func _on_scenario_done(sc: ScenarioBase) -> void:
	# Сценарий мог остаться висеть после таймаута — такие вызовы игнорируем.
	if sc != _current:
		return
	_next_scenario()


func _summary() -> void:
	print("")
	print("ИТОГ: сценариев %d, проверок %d, провалов %d" % [scenarios_total, checks, fails])
	get_tree().quit(1 if fails > 0 else 0)


func _process(_delta: float) -> void:
	if _current == null or not is_instance_valid(_current):
		return
	if Time.get_ticks_msec() - _started_ms > _timeout_ms:
		ok("сценарий уложился в отведённое время", false,
				"%.0f с" % (float(_timeout_ms) / 1000.0))
		_next_scenario()


# ------------------------------------------------------------------ ПРОВЕРКИ

## Записать результат проверки (формат как у тест-раннера).
func ok(label: String, cond: bool, extra: String = "") -> void:
	checks += 1
	if cond:
		print("  OK   %s %s" % [label, extra])
	else:
		fails += 1
		print("  FAIL %s %s" % [label, extra])


## Подождать реальные секунды (не кадры: в headless частота не гарантирована).
func wait(secs: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(secs * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


# ------------------------------------------------------------------ СБРОС МИРА

## Сбросить мир и игрока перед очередным сценарием: тот же сид — тот же мир.
func _reset_world() -> void:
	var p: Player = scene.get("player")
	# Фантомы прошлого сценария — долой.
	for n in get_tree().get_nodes_in_group("phantom"):
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.queue_free()
	# Выпавшие предметы — тоже.
	for c in scene.get_children():
		if c is ItemEntity:
			c.get_parent().remove_child(c)
			c.queue_free()
	# Мир заново (тайлы, постройки, свет, терминалы).
	if World.tilemap:
		World.tilemap.clear()
	World.generate(int(scene.get("seed_value")))
	Game.reset_run()
	Threat.reset()
	Game.tasks_total = World.terminals.size()
	# Игрок заново.
	p.test_input = {}
	p.hp = Player.MAX_HP
	p.vel = Vector2.ZERO
	p.dead = false
	p.on_ground = false
	p.hiding = false
	p.hide_timer = 0.0
	p.hide_cd = 0.0
	p.noise = 0.0
	p.invuln = 0.0
	p.mining_progress = 0.0
	p.mining_cell = Vector2i(-1, -1)
	p.task_progress = 0.0
	p.emp_cd = 0.0
	p.slash_cd = 0.0
	p._regen = 0.0
	for i in p.inv.slots.size():
		p.inv.slots[i] = ItemStack.new()
	p.inv.selected = 0
	# Стартовый набор — как в обычной игре.
	p.inv.add(IDs.I.LAMP, 3)
	p.inv.add(IDs.I.COAL, 6)
	p.inv.add(IDs.I.IRON_PLATE, 2)
	p.inv.add(IDs.I.COPPER_ORE, 4)
	p.global_position = World.spawn_point
	# Экран финала мог остаться от прошлого сценария.
	var es: Node = scene.get("end_screen")
	if es != null:
		es.visible = false
