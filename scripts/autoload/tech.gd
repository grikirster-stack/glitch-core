extends Node
## Журнал экспедиции (ADR-005 § 7.1, #169): прочитанные главы и найденные обрывки.
## Дерево технологий T1–T5 и «данные» сняты — открытие рецептов ведут чертежи
## (`Game.blueprints`, `Game.has_blueprint`). Имя автозагрузки оставлено: на Tech
## ссылаются журнал, терминалы и сохранения.
##
## Главы читаются на терминалах (`read_chapter(i)`), обрывки выпадают из чёрных
## ящиков и самописца (`add_fragment`). Журнал (J, `JournalPanel`) берёт отсюда,
## что открыто, а тексты — из `Lore`.
##
## Состояние живёт один забег: `Game.reset_run()` зовёт `reset()`.

## Прочитана новая глава журнала (номер 0..8).
signal chapter_read(i: int)
## Найден новый обрывок (текст уже в `fragments`).
signal fragment_found(text: String)

## Номера прочитанных глав журнала в порядке прочтения.
var read_chapters: Array = []
## Найденные обрывки (тексты) в порядке находки.
var fragments: Array = []


## Новый забег: журнал пуст.
func reset() -> void:
	read_chapters = []
	fragments = []


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


## Записать найденный обрывок (чёрный ящик, самописец). Пустые и повторы не пишутся.
func add_fragment(text: String) -> bool:
	if text == "" or fragments.has(text):
		return false
	fragments.append(text)
	fragment_found.emit(text)
	return true


# ------------------------------------------------------------------ СОХРАНЕНИЕ (#37)

## Только журнал. Поле "unlocked" старых сохранений (дерево T0–T5) игнорируется:
## открытие рецептов теперь в `Game.blueprints`.
func save_state() -> Dictionary:
	return {
		"read_chapters": read_chapters.duplicate(),
		"fragments": fragments.duplicate(),
	}


## Без сигналов: загрузка не пишет в HUD «Журнал: глава…».
func load_state(d: Dictionary) -> void:
	read_chapters = Array(d.get("read_chapters", [])).duplicate()
	fragments = Array(d.get("fragments", [])).duplicate()


# ------------------------------------------------------------------ СЕТЬ (ADR-002)
## Главы и обрывки — общие для команды (§ 4.7, D10; MP-G #91). Считает хост;
## клиенту они приходят событием TECH (InvOps). Чертежи в сеть ещё не вынесены:
## битовая маска в global ждёт очереди PROTO (C1 → … → D2, эпик #182).

## Клиент: событие с хоста — то же, что у хоста (сигналы, уведомление).
## UNLOCK дерева больше не применяется (пакет старого клиента молча пропускается).
func net_apply(kind: int, arg: int, text: String) -> void:
	match kind:
		NetCodec.TechEv.CHAPTER:
			read_chapter(arg)
		NetCodec.TechEv.FRAGMENT:
			add_fragment(text)
