extends Node
## Исследования (ADR-001, § 4.6): дерево технологий, прочитанные главы журнала,
## найденные обрывки.
##
## Дерево — цепочка из пяти узлов T1…T5 поверх стартового T0. Узел открывается
## за «данные» (`Game.research`, цены — `Balance.TECH_COST`) и только после
## предыдущего: T2 не купить, пока не открыт T1. Рецепт в `DB` несёт поле
## "tech" — узел, с которого он доступен; панель крафта серит запертые, станции
## их не берут.
##
## Главы журнала читаются на терминалах (#29 зовёт `read_chapter(i)`), обрывки
## выпадают из чёрных ящиков (`add_fragment`). Журнал (J, `JournalPanel`) берёт
## отсюда, что открыто, а тексты — из `Lore`.
##
## Состояние живёт один забег: `Game.reset_run()` зовёт `reset()`.

## Открыт узел дерева (после списания данных).
signal node_unlocked(node: String)
## Прочитана новая глава журнала (номер 0..8).
signal chapter_read(i: int)
## Найден новый обрывок (текст уже в `fragments`).
signal fragment_found(text: String)

## Узлы по порядку: каждый следующий требует предыдущий.
const ORDER: Array = ["T0", "T1", "T2", "T3", "T4", "T5"]
## Названия узлов (ADR-001, § 4.6).
const NAMES: Dictionary = {
	"T0": "Старт",
	"T1": "Сборка",
	"T2": "Оборона",
	"T3": "Бурение",
	"T4": "Герметизация",
	"T5": "Релей",
}

## Открытые узлы. T0 открыт всегда.
var unlocked: Array = ["T0"]
## Номера прочитанных глав журнала в порядке прочтения.
var read_chapters: Array = []
## Найденные обрывки (тексты) в порядке находки.
var fragments: Array = []


## Новый забег: открыт только T0, журнал пуст.
func reset() -> void:
	unlocked = ["T0"]
	read_chapters = []
	fragments = []


# ------------------------------------------------------------------ ДЕРЕВО

## Цена узла в данных (T0 — 0, неизвестный узел — -1).
func cost(node: String) -> int:
	if node == "T0":
		return 0
	return int(Balance.TECH_COST.get(node, -1))


## Узел, который нужно открыть раньше (пустая строка у T0 и неизвестных).
func prerequisite(node: String) -> String:
	var i: int = ORDER.find(node)
	if i <= 0:
		return ""
	return String(ORDER[i - 1])


## Открыт ли узел. Пустой узел у рецепта считается стартовым.
func is_unlocked(node: String) -> bool:
	if node == "" or node == "T0":
		return true
	return unlocked.has(node)


## Можно ли открыть узел прямо сейчас: ещё закрыт, предыдущий открыт, данных хватает.
func can_unlock(node: String) -> bool:
	if not ORDER.has(node) or is_unlocked(node):
		return false
	if not is_unlocked(prerequisite(node)):
		return false
	return Game.research >= cost(node)


## Почему узел нельзя открыть (пустая строка — можно или уже открыт).
func lock_reason(node: String) -> String:
	if not ORDER.has(node) or is_unlocked(node):
		return ""
	var pre: String = prerequisite(node)
	if not is_unlocked(pre):
		return "Сначала откройте %s" % title(pre)
	if Game.research < cost(node):
		return "Не хватает данных: %d из %d" % [Game.research, cost(node)]
	return ""


## Открыть узел: списывает `Game.research`. false — нельзя (см. `lock_reason`).
func unlock(node: String) -> bool:
	if not can_unlock(node):
		return false
	Game.research -= cost(node)
	unlocked.append(node)
	node_unlocked.emit(node)
	Game.notify("Открыто: %s. Новые рецепты в крафте." % title(node), Color(0.45, 0.9, 1.0))
	return true


## «T1 «Сборка»» — подпись узла для интерфейса.
func title(node: String) -> String:
	if not NAMES.has(node):
		return node
	return "%s «%s»" % [node, String(NAMES[node])]


## Рецепты, которые открывает узел (из `DB.recipes`, в порядке описания).
func recipes_of(node: String) -> Array:
	var out: Array = []
	for r in DB.recipes:
		if String(r.get("tech", "T0")) == node:
			out.append(r)
	return out


# ------------------------------------------------------------------ ЖУРНАЛ

## Отметить главу прочитанной. true — глава новая (повторное чтение ничего не даёт).
## Зовут терминалы (#29); номер — 0..Lore.chapter_count()-1.
func read_chapter(i: int) -> bool:
	if i < 0 or i >= Lore.chapter_count() or read_chapters.has(i):
		return false
	read_chapters.append(i)
	chapter_read.emit(i)
	Game.notify("Журнал: глава «%s» (J)" % Lore.chapter_title(i), Color(0.85, 0.85, 0.6))
	return true


## Прочитана ли глава i.
func is_chapter_read(i: int) -> bool:
	return read_chapters.has(i)


## Записать найденный обрывок (чёрный ящик). Пустые и повторы не пишутся.
func add_fragment(text: String) -> bool:
	if text == "" or fragments.has(text):
		return false
	fragments.append(text)
	fragment_found.emit(text)
	return true


# ------------------------------------------------------------------ СОХРАНЕНИЕ (#37)

func save_state() -> Dictionary:
	return {
		"unlocked": unlocked.duplicate(),
		"read_chapters": read_chapters.duplicate(),
		"fragments": fragments.duplicate(),
	}


## Без сигналов: загрузка не пишет в HUD «Открыто…» и «Журнал: глава…».
func load_state(d: Dictionary) -> void:
	unlocked = Array(d.get("unlocked", ["T0"])).duplicate()
	if not unlocked.has("T0"):
		unlocked.push_front("T0")
	read_chapters = Array(d.get("read_chapters", [])).duplicate()
	fragments = Array(d.get("fragments", [])).duplicate()
