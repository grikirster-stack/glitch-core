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
		"desc": "терминал без ТЭЦ читается: E засчитывает задание и главу",
	},
	"blueprint_order": {
		"file": "blueprint_order.gd",
		"title": "порядок чертежей",
		"desc": "два терминала в разном порядке чтения дают чертежи 1 и 2 в одном порядке",
	},
	"relay": {
		"file": "relay.gd",
		"title": "ядро",
		"desc": "семь дуг, удерживать E, этап 4, отсчёт 180 с (ускорен), победа и эпилог",
	},
	"rainbow_core": {
		"file": "rainbow_core.gd",
		"title": "радужное ядро",
		"desc": "ядро в 200 клетках от лагеря, смерть, возрождение у ядра; семь дуг за ≤ 120 с",
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
	# --- Журнал (#28). Дерево T1–T5 снято (#169): tech_unlock больше нет.
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
	"fluid_pools": {
		"file": "fluid_pools.gd",
		"title": "вода (перепроверка)",
		"desc": "независимая перепроверка #45 и #70: плёнка, ямы 12–48, разрыв в полу, видимость порций",
		"timeout_ms": 180000,   # #70: стенды широких ям — ~50 с на нагруженной машине
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
	# Питание, лента и бюджет сняты (#170).
	# --- Мир: тайники руин (#35) ---
	"ruin_cache": {
		"file": "ruin_cache.gd",
		"title": "тайники руин",
		"desc": "в каждой руине сундук по роли хозяина и табличка; один сид — один тайник",
	},
	# Автоматизация и терминал «под питанием» сняты (#170).
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
	"dismantle": {
		"file": "dismantle.gd",
		"title": "разбор постройки",
		"desc": "удержание E снимает машину и возвращает её предмет в рюкзак; кампанийные — нет",
	},
	# Плавильня, рой на бур и тень на ТЭЦ сняты (#170).
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
		"desc": "формулы ADR-005 § 6.2; тихая ночь ≤ 1 живого, пустая смена 4 — бюджет 7",
	},
	"night_autopilot": {
		"file": "night_autopilot.gd",
		"title": "ночь на автопилоте",
		"timeout_ms": 180000,
		"desc": "три уровня базы × 90 с: пусто / горелка+маяк / семь цветов; секунды до первой ночи",
	},
	"vent_spawn": {
		"file": "vent_spawn.gd",
		"title": "спавн из вентиляций",
		"desc": "три ближайшие незапечатанные вентиляции, телеграф 2 с",
	},
	# --- Оборона (#31, ADR-001 § 4.4) ---
	# Турель и шлюз сняты (#170). Красный маяк проверяет pharos_red.
	"vent_grate_blocks_spawn": {
		"file": "vent_grate_blocks_spawn.gd",
		"title": "решётка вентиляции",
		"desc": "решётка закрывает спавн из вентиляции; копатель ломает её за ≈ 8 с",
	},
	"steel_wall_vs_burrower": {
		"file": "steel_wall_vs_burrower.gd",
		"title": "стальная стена и копатель",
		"desc": "землю копатель роет, стальную стену — нет; игрок ломает её за ≈ 4 с",
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
		"desc": "лагерь, F5, мир меняется, F9 — всё как при F5, горелка жжёт дальше",
	},
	# --- Релей и финал (#32, ADR-001 § 4.7) ---
	"objective_stages": {
		"file": "objective_stages.gd",
		"title": "этапы цели",
		"desc": "ядро → этап 2, семь дуг → этап 3, запуск → этап 4",
	},
	"relay_doppel_spawns": {
		"file": "relay_doppel_spawns.gd",
		"title": "двойник на релее",
		"desc": "за первые 30 с удержания сигнала выходит двойник; замер p95 кадра при cap 10",
	},
	# --- Небесный тайник (#60) ---
	"sky_secret": {
		"file": "sky_secret.gd",
		"title": "небесный тайник",
		"desc": "с земли не допрыгнуть; бот строит лестницу из блоков, лезет на обломок и открывает тайник",
		"timeout_ms": 120000,
	},
	# --- Инвентарь и крафт: понятность (#69) ---
	"inventory_transfer": {"file": "inventory_transfer.gd", "title": "сундук ↔ инвентарь",
		"desc": "клики мышью: в руку, Shift+ЛКМ туда и обратно, «Забрать/Сложить всё», предмет в руке не теряется"},
	"craft_feedback": {"file": "craft_feedback.gd", "title": "крафт: подсказка и отклик",
		"desc": "наведение — входы и «есть/нужно»; нехватка, чертёж, станок — причина словами; «Скрафчено» / «Загружено»"},
	"recipe_reveal": {"file": "recipe_reveal.gd", "title": "рецепт по первому подбору",
		"desc": "новый забег — светокристалл виден, стекло и слиток нет; песок открывает стекло; уведомление один раз"},
	"inventory_text_fit": {"file": "inventory_text_fit.gd", "title": "подписи панели в рамках",
		"desc": "1280×720 и 960×540, все вкладки: подписи внутри рамок, без наложений; цель в границах блока"},
	# --- Копка по лучу (ADR-005 § 3) ---
	"mining_ray": {"file": "mining_ray.gd", "title": "копка по лучу",
		"desc": "ЛКМ копает первую твёрдую клетку между героем и курсором: стена из 2 клеток, жила за ней, воздух 5 клеток, выступ за углом, клетка за радиусом; World.first_solid_on_ray и её замер"},
	# --- Сенсорное управление (#81) ---
	"touch_controls": {"file": "touch_controls.gd", "title": "сенсорное управление",
		"desc": "касания: джойстик ведёт, тап — прыжок, второй палец копает, умный прицел копает и строит мимо клетки, щипок — зум, I/J — окна, «Назад» — пауза"},
	"view_zoom": {"file": "view_zoom.gd", "title": "зум камеры",
		"desc": "колесо и + / − — ближе и дальше плавно, пределы, средняя кнопка — сброс, при открытом инвентаре зум стоит, зум в профиле"},
	# --- Баланс: боты ADR-001 § 2 (#33); таблица по сидам — tools/balance_probe.gd ---
	"balance_hand": {
		"file": "balance_hand.gd",
		"title": "баланс: релей руками",
		"desc": "бот копает сырьё релея через шов ввода: ≥ 25 мин чистой добычи",
		"timeout_ms": 240000,
	},
	# balance_factory снят вместе с линиями буров (#170).
	"night_survive_1": {
		"file": "night_survive_1.gd",
		"title": "баланс: ночь 1 с 3 лампами",
		"desc": "без построек, 3 лампы, штатный директор угрозы: hp > 0 через 90 с",
		"timeout_ms": 180000,
	},
	"night_siege_3": {
		"file": "night_siege_3.gd",
		"title": "баланс: ночь 3 без обороны",
		"desc": "обычная база без обороны теряет ≥ 1 машину за ночь 3",
		"timeout_ms": 150000,
	},
	"endless": {
		"file": "endless.gd",
		"title": "бесконечная игра",
		"desc": "руда отрастает только в тумане; тень отдаёт уголь, рой — медь; «Остаться на планете»",
		"timeout_ms": 120000,
	},
	"night_defended_3": {
		"file": "night_defended_3.gd",
		"title": "баланс: ночь 3 с обороной",
		"desc": "та же база + 2 красных маяка и стена: 0 потерь",
		"timeout_ms": 150000,
	},
	# --- HUD и обучение (#34) ---
	"hud_tracker": {
		"file": "hud_tracker.gd",
		"title": "карточка «Сейчас» и отсчёт ночи",
		"desc": "карточка цели (текст, счётчик, иконка), отсчёт в сумерках, вентиляции на миникарте, пар и дуга маяка",
	},
	"place_click": {
		"file": "place_click.gd",
		"title": "ПКМ ставит постройку",
		"desc": "горелка в руке + ПКМ по свободной клетке — постройка на месте",
	},
	"chest_vs_terminal": {
		"file": "chest_vs_terminal.gd",
		"title": "сундук рядом с терминалом",
		"desc": "E достаётся тому, что ближе: сундук вплотную к терминалу открывается, у терминала — терминал",
	},
	"hud_tutorial": {
		"file": "hud_tutorial.gd",
		"title": "обучение первых минут",
		"desc": "копай → крафт горелки → поставить → терминал",
	},
	# --- Стиль V2: флора (ADR-003, #104) ---
	"decor_flora": {
		"file": "decor_flora.gd",
		"title": "флора и декор-слой",
		"desc": "декор без коллизий, под туманом его нет, из сида и тайлов (пересборка та же, не в сохранении), флора по биомам, пересчёт столбца при правке",
	},
	# --- Цель E (#116) ---
	"interact_priority": {
		"file": "interact_priority.gd",
		"title": "приоритет E: сундук у терминала",
		"desc": "сундук рядом с терминалом открывается по E; терминал под курсором читается без ТЭЦ",
	},
	# --- Стиль V7: глитч и доступность (ADR-003, #108) ---
	"glitch_fx": {
		"file": "glitch_fx.gd",
		"title": "глитч по событию и «меньше глитча»",
		"desc": "релей/двойник/браун-аут/вентиляция → эффект ≤ 0.5 с; в простое ни узлов, ни _process; «меньше глитча» — без шейдера; поле профиля",
	},
	# --- Пауза и выход в меню (#119) ---
	"pause_menu": {"file": "pause_menu.gd", "title": "пауза и «Сохранить и выйти в меню»",
		"desc": "ESC: окна, потом пауза (мир стоит); хардкор — серо и «не сохранён»; сохранить → меню → «Продолжить» — смена, инвентарь, позиция те же"},
	# --- Кампания (ADR-004) ---
	"campaign": {"file": "campaign.gd", "title": "кампания: пять глав", "timeout_ms": 240000,
		"desc": "каждая глава на мире кампании: база под питанием, этапы по условиям (линия цеха, сборщик, буры шахты — сами), победа, экран итога, профиль; провал осады; марионетка клиента и HUD"},
	"campaign_shaft": {"file": "campaign_shaft.gd", "title": "ствол шахты кампании", "timeout_ms": 120000,
		"desc": "бот падает по центру ствола до штольни и поднимается прыжками по всем площадкам на кромку у базы"},
	# Главы «Свет» 3–4 (#178). Главы 1–2 (#177) регистрирует campaign_light.gd.
	"campaign_light_late": {"file": "campaign_light_late.gd", "title": "главы «Свет» 3–4",
		"timeout_ms": 180000,
		"desc": "зеркало доводит луч до подвала, цвета сводят жёлтый в маяк; каждая глава ≤ 120 с"},
	# --- Свет: горелка и луч (ADR-005, #164) ---
	"beam_burner": {"file": "beam_burner.gd", "title": "горелка и луч", "timeout_ms": 90000,
		"desc": "уголь даёт красный луч на 24 клетки, стена обрывает, 45 с гаснет, сундук кормит, поворот уводит луч; замер rebuild"},
	# --- Свет: маяк, часть 1 (ADR-005 § 5, #167) ---
	"pharos_red": {"file": "pharos_red.gd", "title": "маяк под красным", "timeout_ms": 60000,
		"desc": "уголь → маяк жжёт эхо в 5 клетках за ≤ 5 с, за стеной молчит; урон/с и мкс кадра"},
	"pharos_yellow": {"file": "pharos_yellow.gd", "title": "маяк под жёлтым", "timeout_ms": 30000,
		"desc": "жёлтый луч на входе: свет ≥ 2.0 в 4 клетках, эхо рядом уходит в FLEE за 2 с"},
	"pharos_green": {"file": "pharos_green.gd", "title": "маяк под зелёным", "timeout_ms": 30000,
		"desc": "медь → маяк чинит соседа 40 → 100 за ≤ 9 с и сам не теряет HP"},
	# --- Свет: зеркало, смеситель, призма (ADR-005, #165) ---
	"beam_optics": {"file": "beam_optics.gd", "title": "зеркало, смеситель, призма", "timeout_ms": 90000,
		"desc": "зеркало поворачивает луч (24−2), смеситель складывает цвета и даёт белый 32−2, призма делит белый, кольцо не зацикливается; замер rebuild"},
	# --- Свет: коллектор и накопитель (ADR-005, #166) ---
	"beam_solar": {"file": "beam_solar.gd", "title": "коллектор и накопитель", "timeout_ms": 90000,
		"desc": "днём белый луч 32, крыша гасит; накопитель копит 10 с и отдаёт ночью; рубильник «отдавать» не копит; чужой цвет не мешает; сохранение"},
	"beam_diagonal": {"file": "beam_diagonal.gd", "title": "луч по диагонали", "timeout_ms": 60000,
		"desc": "восемь направлений: диагональ = 1 клетка длины, стена и угол двух стен обрывают, зеркало переводит прямой в диагональ, старый dir 0..3 тот же"},
	# --- Свет: маяк, часть 2 (ADR-005 § 5, #168) ---
	"pharos_blue": {"file": "pharos_blue.gd", "title": "маяк под синим", "timeout_ms": 60000,
		"desc": "кристалл → эхо в 3 клетках идёт вдвое медленнее и раз в 3 с не бьёт 1 с; мкс slow_factor_at"},
	"pharos_dome": {"file": "pharos_dome.gd", "title": "маяк под голубым", "timeout_ms": 30000,
		"desc": "смесь G+B: горелка под куполом не теряет HP, купол гасит 100 и через 10 с снова есть"},
	"pharos_lure": {"file": "pharos_lure.gd", "title": "маяк под пурпурным", "timeout_ms": 40000,
		"desc": "смесь R+B: рой в 20 клетках за 15 с у маяка, не у горелки; маяк 200 HP"},
	"pharos_white": {"file": "pharos_white.gd", "title": "маяк под белым", "timeout_ms": 30000,
		"desc": "смесь R+G+B: 10 клеток руды в радиусе 8 разведаны за 2 с, камень нет; мкс reveal_cells"},
	# --- Сирена и линза (ADR-005 § 7.2, #172) ---
	"siren": {"file": "siren.gd", "title": "сирена", "timeout_ms": 90000,
		"desc": "рой из 5 и тень в 6 клетках: под лучом 60 с, E гонит в FLEE на 10 с, без луча заряд стоит"},
	"lens": {"file": "lens.gd", "title": "линза в маяке", "timeout_ms": 30000,
		"desc": "без линзы маяк не бьёт эхо на 9 клетках, с линзой бьёт; разбор возвращает линзу"},
	"sky_secret_lens": {"file": "sky_secret_lens.gd", "title": "линза в небесном тайнике",
		"desc": "линза лежит в сундуке тайника на сидах 31337, 4242 и 12345"},
	# --- Радужный кот (ADR-005 § 7, #176) ---
	"rainbow_cat": {"file": "rainbow_cat.gd", "title": "радужный кот", "timeout_ms": 90000,
		"desc": "5 эхо в 15 клетках мертвы за ≤ 30 с; через 90 с кот в ядре; заряд только под лучом; след ≥ 1.5"},
}

var scene: Node = null
var checks: int = 0
var fails: int = 0
var scenarios_total: int = 0

## Игровые часы сценариев, с: сумма delta физических кадров (с учётом
## Engine.time_scale). Под нагрузкой физика отстаёт от часов стены (не больше
## 8 шагов на кадр), поэтому ожидания сценариев идут по этим часам, а не по
## Time.get_ticks_msec(): иначе сценарий проживал меньше игрового времени,
## чем рассчитывал, и падал только в длинном/нагруженном прогоне.
var sim_time: float = 0.0
## То же по кадрам отрисовки (delta _process): по ним живут Game.game_time,
## машины и SceneTreeTimer.
var proc_time: float = 0.0

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


func _physics_process(delta: float) -> void:
	sim_time += delta


func _process(delta: float) -> void:
	proc_time += delta
	if _current == null or not is_instance_valid(_current):
		return
	if Time.get_ticks_msec() - _started_ms > _timeout_ms:
		ok("сценарий уложился в отведённое время", false,
				"%.0f с" % (float(_timeout_ms) / 1000.0))
		_next_scenario()


# ------------------------------------------------------------------ ЧЕРЕЗ МЕНЮ (#119)
## Сценарий паузы уходит в главное меню и возвращается «Продолжить»: сцена игры
## сменяется дважды. Раннер (а с ним сценарий) переезжает под /root и переживает смену;
## новая сцена игры (main.gd) принимает его — adopt, — а не запускает список заново.

static var carried: ScenarioRunner = null


func carry_over() -> void:
	carried = self
	reparent(get_tree().root)


func adopt(main_scene: Node) -> void:
	carried = null
	scene = main_scene


# ------------------------------------------------------------------ ПРОВЕРКИ

## Записать результат проверки (формат как у тест-раннера).
func ok(label: String, cond: bool, extra: String = "") -> void:
	checks += 1
	if cond:
		print("  OK   %s %s" % [label, extra])
	else:
		fails += 1
		print("  FAIL %s %s" % [label, extra])


## Подождать игровые секунды (по физическим кадрам, см. sim_time; не число
## кадров: в headless частота кадров не гарантирована).
func wait(secs: float) -> void:
	var until: float = sim_time + secs
	while sim_time < until:
		await get_tree().process_frame


# ------------------------------------------------------------------ СБРОС МИРА

## Сбросить мир и игрока перед очередным сценарием: тот же сид — тот же мир.
## Свежий мир того же сида. Сценарий blueprint_order зовёт между двумя порядками чтения.
func reset_world() -> void:
	_reset_world()


func _reset_world() -> void:
	# Ускорение прошлого сценария не должно течь дальше. balance_factory
	# ставит time_scale 8 и снимает его в finish(); по таймауту finish не
	# зовётся, и следующий сценарий живёт ускоренным.
	Engine.time_scale = 1.0
	var p: Player = scene.get("player")
	# Фантомы прошлого сценария — долой.
	for n in get_tree().get_nodes_in_group("phantom"):
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.queue_free()
	# Кот прошлого сценария (#176) — тоже: он не в группе phantom.
	if RainbowCat.live != null and is_instance_valid(RainbowCat.live):
		RainbowCat.live.queue_free()
		RainbowCat.live = null
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
	# Окна и зажатые клавиши прошлого сценария (#116): открытый сундук или журнал
	# забирают ввод у мира (UI.blocking), а держание E — следующее нажатие, и один
	# провал каскадом валил все сценарии дальше. Окна закрываем до сброса
	# инвентаря: предмет «в руке» панель возвращает в него.
	if UI.panel != null and UI.panel.visible:
		UI.panel.close()
	if UI.journal != null and UI.journal.visible:
		UI.journal.close()
	if UI.panel != null:
		UI.panel.held = ItemStack.new()
	p.touch_input = {}
	p._e_prev = false
	p._e_used = false
	p._v_prev = false
	p._repair_cd = 0.0
	p._task_cell = Vector2i(-1, -1)
	p._dismantle_t = 0.0
	p._dismantle_cell = Vector2i(-1, -1)
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
	p.inv.seen_items = {}
	# Стартовый набор — как в обычной игре. Подбор рецептов (#171) идёт от него.
	p.inv.add(IDs.I.LAMP, 3)
	p.inv.add(IDs.I.COAL, 6)
	p.inv.add(IDs.I.STONE, 4)
	p.inv.add(IDs.I.SCRAP, 4)
	p.global_position = World.spawn_point
	# Экран финала мог остаться от прошлого сценария.
	var es: Node = scene.get("end_screen")
	if es != null:
		es.visible = false
