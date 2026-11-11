class_name Campaign
extends RefCounted
## Кампания (ADR-004, ADR-005 § 9): главы «Свет» на одном мире — сиде SEED.
## Фабрика снята (#170): цеха, шахты и осады нет. Главы 1–2: копать по лучу
## и зажечь горелку. Главы 3–6 добавят G2–G3.
##
## Запуск: меню «Кампания» (одиночная) или «Создать игру» → «Режим» (сеть) кладут id
## главы в Net.session["mission"]; для отладки — флаг --mission=<id>. main.gd строит
## мир по SEED и зовёт start(). Пройденные главы — в профиле (Profile.campaign_done):
## следующая открывается, когда пройдена предыдущая.

## Мир кампании. На нём сняты картинки README; база глав рассчитана на его рельеф.
const SEED: int = 31337
const DIR: String = "res://scripts/campaign/missions/"
## Главы по порядку (id = имя файла в DIR).
const CHAPTERS: Array[String] = ["dig", "fire"]


static func has(id: String) -> bool:
	return CHAPTERS.has(id)


## Новая глава (ещё не в дереве). Неизвестный id — null.
static func create(id: String) -> Mission:
	if not has(id):
		return null
	var m: Mission = load(DIR + id + ".gd").new()
	m.name = "Mission"
	return m


## Описание главы для меню: {id, chapter, title, brief, teaches}.
static func info(id: String) -> Dictionary:
	var m: Mission = create(id)
	if m == null:
		return {}
	var d: Dictionary = {"id": id, "chapter": m.chapter, "title": m.title, "brief": m.brief,
			"teaches": m.teaches}
	m.free()
	return d


## Следующая глава ("" — последняя или id неизвестен).
static func next_of(id: String) -> String:
	var i: int = CHAPTERS.find(id)
	if i < 0 or i + 1 >= CHAPTERS.size():
		return ""
	return CHAPTERS[i + 1]


## Открыта ли глава: первая — всегда, остальные — после предыдущей.
static func unlocked(id: String, done: PackedStringArray) -> bool:
	var i: int = CHAPTERS.find(id)
	if i < 0:
		return false
	return i == 0 or done.has(CHAPTERS[i - 1])


## Хост и одиночная: глава id в сцене игры (мир сида SEED уже построен).
static func start(scene: Node, id: String) -> Mission:
	var m: Mission = create(id)
	if m == null:
		return null
	scene.add_child(m)
	Game.mission = m
	m.begin()
	return m


## Отметить главу пройденной в профиле игрока (не в тестовом прогоне чужого профиля:
## Profile.default_path сам изолирован TestEnv).
static func mark_done(id: String) -> void:
	if not Profile.done_memory.has(id):
		Profile.done_memory.append(id)
	var p: Profile = Profile.load_or_create()
	if p.campaign_done.has(id):
		return
	p.campaign_done.append(id)
	p.save_to()


# ------------------------------------------------------------------ СЕТЬ

## Клиент: состояние главы от хоста (снимок входа или кадр MISSION). Главы ещё нет —
## создаётся марионетка в текущей сцене.
static func net_apply(d: Dictionary) -> void:
	var id: String = String(d.get("id", ""))
	if not has(id):
		return
	var m = Game.mission
	if m == null or not is_instance_valid(m) or String(m.id) != id:
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree == null or tree.current_scene == null:
			return
		m = create(id)
		m.puppet = true
		tree.current_scene.add_child(m)
		Game.mission = m
	m.apply_state(d)
