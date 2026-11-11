class_name InventoryPanel
extends Control
## Экран инвентаря: сетка предметов, крафт (ручной / плавильня / верстак) и сундуки.
##
## Рецепт, чей выход в списке чертежей, без чертежа не рисуется вовсе (#169).
## Под списком — одна строка «Чертежи: N из M». Имя следующего чертежа
## в строку не пишется: длинное имя резалось в «…».
##
## Понятность для новичка (#69):
##  * сундук и инвентарь: ЛКМ — взять/положить, ПКМ — половина/по одному,
##    Shift+ЛКМ — переложить стопку в другой контейнер, кнопки «Забрать всё»
##    и «Сложить всё»; предмет «в руке» рисуется у курсора с количеством,
##    при закрытии панели он возвращается в инвентарь (не влез — в сундук,
##    потом на землю под ноги);
##  * рецепт: по наведению — подсказка с названиями входов, «есть N / нужно M»,
##    станцией, временем и причиной недоступности словами; после клика —
##    вспышка строки и строка обратной связи внизу панели (уведомления HUD
##    панель закрывает).
## Счётчик деталей релея (микросхема, энергоячейка, антенна) с панели снят
## (#169): дерево данных и этот список — не язык чертежей. Прогресс сдачи
## остаётся в трекере HUD и в тексте у ядра.
## Все подписи идут через _text(): она обрезает строку с «…» по ширине шрифта
## и, если включён text_audit, записывает прямоугольник строки — сценарий
## inventory_text_fit проверяет, что ничего не вылезает за свои рамки.

const PANEL: Vector2 = Vector2(820, 540)
const SLOT: int = 38
## Сетка инвентаря (#135, #161): верхний ряд — хотбар (ровно inv.hotbar_size ячеек,
## клавиши 1-0 или 1-6), ниже рюкзак рядами по 10. Шаг чуть мельче SLOT, чтобы
## 10 колонок рюкзака встали левее рецептов.
const INV_SLOT: int = 36
## Зазор между хотбаром и рюкзаком (в нём — разделитель), px.
const HOTBAR_GAP: int = 6
const CHEST_COLS: int = 8
const RECIPE_H: int = 46
## Сколько строк рецептов влезает в панель (дальше — колесо мыши).
const RECIPE_ROWS: int = 7
## Ближе этого (px) к станку клик по рецепту станка загружает в него сырьё.
const STATION_REACH: float = 90.0
## Сколько горит вспышка строки рецепта и держится строка обратной связи, мс.
const FLASH_MS: int = 700
const TOAST_MS: int = 4500
## Ширина всплывающей подсказки.
const TIP_W: float = 360.0

## Одна вкладка (#170). «Исследования» убирает D2 — её уже нет.
const TABS: Array = ["Крафт"]
const STATIONS: Array = ["hand"]
## Руками. Станков больше нет: словарь оставлен, чтобы фразы не падали на пустом ключе.
const STATION_INFO: Dictionary = {
	"hand": {"kind": "", "name": "руками"},
}

const C_TITLE: Color = Color(0.85, 0.93, 1.0)
const C_HEAD: Color = Color(0.7, 0.9, 1.0)
const C_TEXT: Color = Color(0.92, 0.95, 1.0)
const C_DIM: Color = Color(0.62, 0.67, 0.76)
const C_OK: Color = Color(0.45, 0.95, 0.55)
const C_BAD: Color = Color(1.0, 0.5, 0.45)
const C_WARN: Color = Color(1.0, 0.72, 0.35)
const C_CHEST: Color = Color(1.0, 0.8, 0.4)

var player = null    ## Игрок (без типа — во избежание цикла зависимостей).
var chest = null     ## Открытый сундук.
## «Рука»: _hand[0] — стопка у курсора. Одиночная и хост: стопка вынута из ячейки
## (InvOps.xfer перекладывает в руку и из руки). Клиент: рука — состояние окна,
## стопка лежит в ячейке _hand_from, пока команда move её не переложит (ADR-002 § 4.2.7).
var _hand: Array = [ItemStack.new()]
var held: ItemStack:
	get:
		return _hand[0]
	set(v):
		_hand[0] = v
var station_tab: int = 0            ## одна вкладка «Крафт» (#170)
var scroll: int = 0
## Последняя позиция мыши в координатах панели (из _gui_input).
var mouse_pos: Vector2 = Vector2(-1, -1)
## Последнее сообщение обратной связи (крафт, перекладка); его читают сценарии.
var last_feedback: String = ""
## Аудит подписей: null — выключен; массив — каждая подпись дописывает сюда
## {text, full, rect, box, tag} (сценарий inventory_text_fit).
var text_audit = null

## Кэш списков рецептов по станциям и подписей узлов: DB.recipes после загрузки
## не меняется, а панель перерисовывается на каждое движение мыши. Ключ сверки —
## размер DB.recipes (вдруг кто-то допишет рецепт на ходу).
var _recipes_cache: Dictionary = {}     ## station -> Array
var _seen_inv: Inventory = null
var _source: Dictionary = {}            ## id предмета -> «где взять»
## Кадр #171 подменяет список строк. Только список: без сундука, сетки и подвала.
var _shot_rows = null
var _shot_list_only: bool = false
var _cache_size: int = -1

var _font: Font = null
var _width_cache: Dictionary = {}       ## кегль -> {строка -> ширина}
var _line_cache: Dictionary = {}        ## кегль -> {строка -> TextLine}
var _wrap_cache: Dictionary = {}        ## "кегль|ширина|строк|текст" -> строки
var _chest_title: String = "СУНДУК"
var _toast_col: Color = C_TEXT
var _toast_until: int = 0
var _flash_rec: Dictionary = {}
var _flash_ok: bool = true
var _flash_until: int = 0
var _tag: String = ""                   ## раздел для аудита подписей
## Станки рядом и вообще в мире (обновляет _scan_stations): station -> MachineBase / bool.
var _near: Dictionary = {}
var _counts: Dictionary = {}            ## id -> сколько в инвентаре (на кадр)
var _row_named: Dictionary = {}         ## имя рецепта -> входы с названиями влезают
var _built: Dictionary = {}
## Сенсорный тап по списку рецептов (#81): где нажали (x < 0 — нет) и сколько
## палец проехал по вертикали; _drag_acc — остаток до следующей строки прокрутки.
var _tap_at: Vector2 = Vector2(-1, -1)
var _drag_y: float = 0.0
var _drag_acc: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_process(false)
	_font = ThemeDB.fallback_font
	Game.blueprint_changed.connect(func(_n: String) -> void: _cache_size = -1)


func open(p: Player) -> void:
	_return_held()
	player = p
	chest = null
	_bind_seen(p)
	visible = true
	queue_redraw()


func open_chest(p: Player, c: Chest) -> void:
	_return_held()
	player = p
	chest = c
	_bind_seen(p)
	visible = true
	_chest_title = "СУНДУК"
	for rc in World.ruin_caches:
		if rc.get("chest") == c:
			_chest_title = "ТАЙНИК «%s»" % String(rc.get("name", ""))
			break
	queue_redraw()


func close() -> void:
	_return_held()
	if chest and Net.is_client():   # СЕТЬ (ADR-002): хост больше не шлёт этот сундук
		InvOps.send(NetCodec.InvOp.CLOSE, {"cell": InvOps.cell_of(chest)})
	visible = false
	chest = null


## Предмет «в руке» не пропадает: обратно в инвентарь, не влез — в открытый
## сундук, и уж совсем никак — на землю под ноги (подберётся, когда будет место).
func _return_held() -> void:
	if Net.is_client():   # СЕТЬ (ADR-002): рука клиента — окно, стопка не покидала ячейку
		_net_drop_hand()
		return
	var had: bool = not held.is_empty()
	InvOps.return_hand(player, chest, _hand)
	if had:
		InvOps.chest_changed(chest)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		mouse_pos = mb.position
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			scroll = maxi(0, scroll - 1)
			queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			scroll = mini(scroll + 1, _max_scroll())
			queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			# Тап пальцем по рецептам ждёт отпускания: палец мог начать листать (#81).
			if mb.device == InputEvent.DEVICE_ID_EMULATION and _list_rect().has_point(mb.position):
				_tap_at = mb.position
				_drag_y = 0.0
				return
			# Позиция события — уже в координатах панели (она на весь экран), как и
			# все прямоугольники. Раньше здесь вычиталось начало панели, и клик
			# мышью попадал на ~(230, 125) px левее-выше нарисованного (#69).
			_click(mb.position, false, mb.shift_pressed)
		elif mb.button_index == MOUSE_BUTTON_LEFT and _tap_at.x >= 0.0:
			if absf(_drag_y) < RECIPE_H * 0.5:
				_click(_tap_at, false)
			_tap_at = Vector2(-1, -1)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_click(mb.position, true, mb.shift_pressed)
	elif event is InputEventMouseMotion:
		mouse_pos = (event as InputEventMouseMotion).position
		queue_redraw()
	elif event is InputEventScreenDrag:
		# Палец листает список рецептов, как колесо: RECIPE_H px — строка (#81).
		var dy: float = (event as InputEventScreenDrag).relative.y
		_drag_y += dy
		_drag_acc += dy
		while _drag_acc >= RECIPE_H:
			_drag_acc -= RECIPE_H
			scroll = maxi(0, scroll - 1)
		while _drag_acc <= -RECIPE_H:
			_drag_acc += RECIPE_H
			scroll = mini(scroll + 1, _max_scroll())
		queue_redraw()


## Список рецептов: тут палец листает (#81).
func _list_rect() -> Rect2:
	return Rect2(_panel_pos() + Vector2(380, 104), Vector2(424, RECIPE_ROWS * RECIPE_H + 12))


## Вспышка строки и строка обратной связи гаснут сами; когда обе погасли,
## _process выключается.
func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	# Вспышка (0.7 с) гаснет плавно — каждый кадр; строка обратной связи
	# просто держится и исчезает одной перерисовкой.
	if now <= _flash_until + 50:
		queue_redraw()
	if now > _toast_until and now > _flash_until + 50:
		queue_redraw()
		set_process(false)


# ---------------------------------------------------------------- ГЕОМЕТРИЯ
# Рисование и клик берут прямоугольники отсюда, иначе ячейки кликаются
# не там, где нарисованы.

func _panel_pos() -> Vector2:
	return ((size - PANEL) * 0.5).floor()


func _tab_rect(i: int) -> Rect2:
	return Rect2(_panel_pos() + Vector2(16 + i * 170, 38), Vector2(164, 30))


func _chest_slot_rect(i: int) -> Rect2:
	return Rect2(_panel_pos() + Vector2(16 + (i % CHEST_COLS) * SLOT, 100 + int(i / CHEST_COLS) * SLOT),
			Vector2(SLOT - 4, SLOT - 4))


func _take_all_rect() -> Rect2:
	return Rect2(_panel_pos() + Vector2(16, 214), Vector2(147, 22))


func _put_all_rect() -> Rect2:
	return Rect2(_panel_pos() + Vector2(169, 214), Vector2(147, 22))


## Верх сетки инвентаря игрока (подпись «ВЫ» — на 6 px выше, ячейки — на 6 ниже).
## Место сундука над ней есть всегда: без сундука там подсказка, как его открыть.
func _inv_y() -> float:
	return 258.0


## Колонок в верхнем ряду — ровно хотбар; рюкзак всегда по 10 (#161).
func _hotbar_cols() -> int:
	if player == null or player.inv == null:
		return Inventory.HOTBAR_MAX
	return clampi(player.inv.hotbar_size, 1, Inventory.HOTBAR_MAX)


## Ячейка i инвентаря: верхний ряд — хотбар (hotbar_size ячеек), рюкзак ниже на HOTBAR_GAP
## рядами по 10. Индекс слота не меняется: ячейки 6…9 при хотбаре 6 — уже рюкзак.
func _inv_slot_rect(i: int) -> Rect2:
	var cols: int = _hotbar_cols()
	var row: int = 0
	var col: int = i
	if i >= cols:
		var k: int = i - cols
		row = 1 + int(k / Inventory.HOTBAR_MAX)
		col = k % Inventory.HOTBAR_MAX
	var y: float = _inv_y() + 6 + row * INV_SLOT + (HOTBAR_GAP if row > 0 else 0)
	return Rect2(_panel_pos() + Vector2(16 + col * INV_SLOT, y), Vector2(INV_SLOT - 4, INV_SLOT - 4))


## Строка рецепта row (0…RECIPE_ROWS-1) на экране.
func _recipe_row_rect(row: int) -> Rect2:
	return Rect2(_panel_pos() + Vector2(380, 116 + row * RECIPE_H), Vector2(424, RECIPE_H - 6))


# ---------------------------------------------------------------- ПОДПИСИ

## Нарисовать строку от базовой линии pos. Строки держим уже разложенными
## (TextLine): у шрифта свой кэш раскладки всего на несколько десятков строк,
## а у панели их за кадр больше — без своего кэша каждая строка
## раскладывалась бы заново на каждом движении мыши.
func _str(pos: Vector2, text: String, fs: int, col: Color) -> void:
	var by_fs = _line_cache.get(fs)
	if by_fs == null:
		by_fs = {}
		_line_cache[fs] = by_fs
	var tl: TextLine = by_fs.get(text)
	if tl == null:
		if by_fs.size() > 1500:
			by_fs.clear()
		tl = TextLine.new()
		tl.add_string(text, _font, fs)
		by_fs[text] = tl
	tl.draw(get_canvas_item(), Vector2(pos.x, pos.y - tl.get_line_ascent()), col)


## Ширина строки кеглем fs. Панель перерисовывается на каждое движение мыши,
## а набор строк почти не меняется — ширины и переносы кэшируются (иначе
## замер panel_probe вырастал втрое).
func _w(text: String, fs: int) -> float:
	var by_fs = _width_cache.get(fs)
	if by_fs == null:
		by_fs = {}
		_width_cache[fs] = by_fs
	var w = by_fs.get(text)
	if w != null:
		return w
	if by_fs.size() > 2000:
		by_fs.clear()
	var v: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	by_fs[text] = v
	return v


## Строка, обрезанная с «…» до ширины max_w.
func _fit(text: String, max_w: float, fs: int) -> String:
	if max_w <= 0.0 or _w(text, fs) <= max_w:
		return text
	var lo: int = 0
	var hi: int = text.length()
	while lo < hi:
		var mid: int = (lo + hi + 1) / 2
		if _w(text.left(mid).strip_edges(false, true) + "…", fs) <= max_w:
			lo = mid
		else:
			hi = mid - 1
	return text.left(lo).strip_edges(false, true) + "…"


## Разбить текст на строки не шире max_w (по словам). max_lines > 0 — лишнее
## сворачивается в последнюю строку с «…».
func _wrap(text: String, max_w: float, fs: int, max_lines: int = 0) -> PackedStringArray:
	var key: String = "%d|%d|%d|%s" % [fs, int(max_w), max_lines, text]
	if _wrap_cache.has(key):
		return _wrap_cache[key]
	if _wrap_cache.size() > 500:
		_wrap_cache.clear()
	var out: PackedStringArray = PackedStringArray()
	var line: String = ""
	for word in text.split(" ", false):
		var cand: String = word if line == "" else line + " " + word
		if line != "" and _w(cand, fs) > max_w:
			out.append(line)
			line = word
		else:
			line = cand
	if line != "":
		out.append(line)
	if max_lines > 0 and out.size() > max_lines:
		var rest: String = " ".join(out.slice(max_lines - 1))
		out = out.slice(0, max_lines - 1)
		out.append(_fit(rest, max_w, fs))
	_wrap_cache[key] = out
	return out


## Подпись в одну строку не шире max_w (длиннее — обрезается с «…»).
## box — рамка, в которую подпись обязана влезть (для аудита); пустая —
## сама строка шириной max_w. Возвращает ширину нарисованного.
func _text(pos: Vector2, text: String, max_w: float, fs: int, col: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, box: Rect2 = Rect2()) -> float:
	var s: String = text
	var w: float = _w(text, fs)
	if max_w > 0.0 and w > max_w:
		s = _fit(text, max_w, fs)
		w = _w(s, fs)
	var x: float = pos.x
	if align == HORIZONTAL_ALIGNMENT_RIGHT:
		x = pos.x + max_w - w
	elif align == HORIZONTAL_ALIGNMENT_CENTER:
		x = pos.x + (max_w - w) * 0.5
	_str(Vector2(x, pos.y), s, fs, col)
	if text_audit != null:
		# «Чернила» строки: от верха заглавных до хвостиков букв.
		var ink: Rect2 = Rect2(x, pos.y - float(fs) * 0.72, w, float(fs) * 0.92)
		var b: Rect2 = box
		if not b.has_area():
			b = Rect2(pos.x, ink.position.y, max_w, ink.size.y)
		text_audit.append({"text": s, "full": text, "rect": ink, "box": b, "tag": _tag})
	return w


func _icon(id: int, r: Rect2, mod: Color = Color(1, 1, 1, 1)) -> void:
	var tex: ImageTexture = DB.item_texture(id)
	if tex:
		draw_texture_rect(tex, r, false, mod)


# ---------------------------------------------------------------- РИСОВАНИЕ

func _draw() -> void:
	if player == null:
		return
	if _font == null:
		_font = ThemeDB.fallback_font
	if not _hand_from.is_empty():   # СЕТЬ (ADR-002): рука клиента против свежего содержимого
		_net_check_hand()
	if text_audit != null:
		text_audit.clear()     ## аудит — только последний кадр
	_count_inventory()
	var origin: Vector2 = _panel_pos()
	draw_rect(Rect2(origin, PANEL), Color(0.06, 0.07, 0.10, 1.0))
	draw_rect(Rect2(origin, PANEL), Color(0.35, 0.55, 0.75, 0.8), false, 2.0)
	_scan_stations()
	_tag = "panel"
	_text(origin + Vector2(16, 26), "ИНВЕНТАРЬ И КРАФТ", 360, UI.FONT["body"], C_TITLE)

	# ---- Вкладки -------------------------------------------------------------
	_tag = "tabs"
	for i in TABS.size():
		var r: Rect2 = _tab_rect(i)
		var active: bool = (station_tab == i)
		draw_rect(r, Color(0.16, 0.24, 0.34) if active else Color(0.10, 0.12, 0.16))
		draw_rect(r, Color(0.4, 0.8, 1.0, 0.9) if active else Color(1, 1, 1, 0.2), false, 1.0)
		_text(r.position + Vector2(10, 20), String(TABS[i]), r.size.x - 30, UI.FONT["small"],
				Color(1, 1, 1) if active else Color(0.7, 0.75, 0.85), HORIZONTAL_ALIGNMENT_LEFT, r)
	if not _shot_list_only:
		_draw_chest(origin)
		_draw_inventory(origin)

	# ---- Рецепты -------------------------------------------------------------
	var rx: float = origin.x + 380
	_draw_recipes(rx, origin)

	if not _shot_list_only:
		_draw_bottom(origin)
	_draw_held()
	_draw_tooltip()
	_tag = ""


func _draw_chest(origin: Vector2) -> void:
	_tag = "chest"
	if chest == null:
		# Место сундука: подсказка, как его открыть.
		var box: Rect2 = Rect2(origin + Vector2(16, 78), Vector2(300, 158))
		draw_rect(box, Color(0.08, 0.09, 0.12, 0.6))
		draw_rect(box, Color(1, 1, 1, 0.08), false, 1.0)
		_text(origin + Vector2(28, 108), "СУНДУК НЕ ОТКРЫТ", 276, UI.FONT["small"], Color(C_CHEST, 0.7),
				HORIZONTAL_ALIGNMENT_LEFT, box)
		var y: float = 132.0
		for line in _wrap("Подойди к сундуку или тайнику руины и нажми E — его ячейки появятся здесь. "
				+ "Shift+ЛКМ перекладывает стопку между сундуком и инвентарём.", 276, UI.FONT["small"], 5):
			_text(origin + Vector2(28, y), line, 276, UI.FONT["small"], C_DIM, HORIZONTAL_ALIGNMENT_LEFT, box)
			y += 18.0
		return
	_text(origin + Vector2(16, 92), _chest_title, 300, UI.FONT["small"], C_CHEST)
	for i in Chest.CAP:
		_draw_slot(_chest_slot_rect(i), _shown(chest.slots, NetCodec.Box.CHEST, i), false)
	var has_chest: bool = false
	for s in chest.slots:
		if not s.is_empty():
			has_chest = true
			break
	var has_pack: bool = false
	for i in range(player.inv.hotbar_size, player.inv.size):
		if not player.inv.slots[i].is_empty():
			has_pack = true
			break
	_button(_take_all_rect(), "Забрать всё", has_chest)
	_button(_put_all_rect(), "Сложить всё", has_pack)


func _button(r: Rect2, label: String, enabled: bool) -> void:
	var hot: bool = enabled and r.has_point(mouse_pos)
	draw_rect(r, Color(0.14, 0.26, 0.34) if hot else (Color(0.11, 0.18, 0.24) if enabled else Color(0.10, 0.11, 0.14)))
	draw_rect(r, Color(0.45, 0.8, 1.0, 0.7) if enabled else Color(1, 1, 1, 0.12), false, 1.0)
	_text(r.position + Vector2(4, 16), label, r.size.x - 8, UI.FONT["small"], C_TEXT if enabled else Color(0.5, 0.53, 0.6),
			HORIZONTAL_ALIGNMENT_CENTER, r)


func _draw_inventory(origin: Vector2) -> void:
	_tag = "inv"
	var inv_y: float = _inv_y()
	var cols: int = _hotbar_cols()
	var keys: String = "1-0" if cols >= Inventory.HOTBAR_MAX else "1-%d" % cols
	var w: float = _text(origin + Vector2(16, inv_y - 6), "ВЫ", 40, UI.FONT["small"], C_HEAD)
	_text(origin + Vector2(16 + w + 8, inv_y - 6), "верхний ряд — хотбар (%s)" % keys, 300 - w, UI.FONT["small"], C_DIM)
	# Разделитель хотбар | рюкзак — посередине зазора между рядами, по ширине рюкзака (10).
	var a: Rect2 = _inv_slot_rect(0)
	var b: Rect2 = _inv_slot_rect(cols + Inventory.HOTBAR_MAX - 1)
	var ly: float = floorf((a.end.y + b.position.y) * 0.5) + 0.5
	draw_line(Vector2(a.position.x, ly), Vector2(b.end.x, ly), Color(0.5, 0.8, 1.0, 0.25), 1.0)
	for i in player.inv.size:
		var r: Rect2 = _inv_slot_rect(i)
		_draw_slot(r, _shown(player.inv.slots, NetCodec.Box.INV, i), i < player.inv.hotbar_size)
		if i < player.inv.hotbar_size:
			# Клавиша ячейки хотбара — как на HUD: 1…9, 0.
			_str(r.position + Vector2(3, 11), str((i + 1) % 10), UI.FONT["small"], Color(0.75, 0.88, 1.0, 0.55))


func _draw_recipes(rx: float, origin: Vector2) -> void:
	_tag = "recipes"
	var station: String = String(STATIONS[station_tab])
	var head: String = "РЕЦЕПТЫ — руками, сразу в инвентарь"
	_text(Vector2(rx, origin.y + 90), head, 424, UI.FONT["small"], C_HEAD)
	var st: Array = _station_line(station)
	_text(Vector2(rx, origin.y + 108), String(st[0]), 424, UI.FONT["small"], st[1])

	var recipes: Array = _recipes(station)
	var first: int = mini(scroll, _max_scroll())
	var last: int = mini(recipes.size(), first + RECIPE_ROWS)
	for i in range(first, last):
		_draw_recipe(_recipe_row_rect(i - first), recipes[i])
	_tag = "recipes"
	var y: float = origin.y + 116 + RECIPE_ROWS * RECIPE_H + 6
	# Иконку следующего чертежа не рисуем: она была чужим предметом рядом со строкой.
	_text(Vector2(rx, y), _blueprint_line(), 424, UI.FONT["small"], Color(0.45, 0.95, 1.0))
	if recipes.size() > RECIPE_ROWS:
		y += 16
		_text(Vector2(rx, y), "%d–%d из %d · колесо мыши — листать" % [first + 1, last, recipes.size()],
				424, UI.FONT["small"], C_DIM)
	if _shot_list_only:
		return
	# Пояснение вкладки: станков больше нет (#170).
	var info: String = "Руками сразу и без станка. Слиток — две руды."
	var ly: float = y + 18
	for line in _wrap(info, 424, UI.FONT["small"], 2):
		_text(Vector2(rx, ly), line, 424, UI.FONT["small"], Color(C_DIM, 0.85))
		ly += 16


## Строка состояния под заголовком рецептов: [текст, цвет].
func _station_line(_station: String) -> Array:
	return ["Наведи — что нужно. Клик — сделать.", C_DIM]


## Семь дуг ядра под рецептами: горящая — цветом, тёмная — серым квадратом.
func _draw_goal(origin: Vector2) -> void:
	if Game.in_mission():
		return
	var y: float = origin.y + 496.0
	var lit: int = Game.core_arcs & 0x7F
	var label: String = "Дуги %d/7" % Game.core_arc_count()
	_text(Vector2(origin.x + 16.0, y), label, 80.0, UI.FONT["small"], Color(C_DIM, 0.9))
	for i in 7:
		var col: Color = Color(0.35, 0.37, 0.40)
		if (lit & (1 << i)) != 0:
			col = Beams.COLOR[Game.CORE_ARC_COLOR[i]]
		draw_rect(Rect2(origin.x + 96.0 + float(i) * 14.0, y - 10.0, 10.0, 10.0), col)


func _draw_bottom(origin: Vector2) -> void:
	_tag = "bottom"
	var now: int = Time.get_ticks_msec()
	if now < _toast_until and last_feedback != "":
		var a: float = 1.0
		_text(origin + Vector2(16, 513), last_feedback, PANEL.x - 32, UI.FONT["small"], Color(_toast_col, a))
	_draw_goal(origin)
	var parts: Array = []
	if not held.is_empty():
		parts = ["В руке: %s ×%d" % [DB.item_name(held.id), held.count], "ЛКМ по ячейке — положить",
				"ПКМ — положить 1", "закроешь панель — вернётся в инвентарь"]
	else:
		parts = ["ЛКМ — взять/положить", "ПКМ — половина"]
		parts.append("Shift+ЛКМ — переложить в сундук/инвентарь" if chest else "Shift+ЛКМ — хотбар/рюкзак")
		parts.append_array(["I / Esc — закрыть", "наведи — подсказка"])
	# Части по важности: что не влезает целиком — пропускаем, не обрезаем.
	var line: String = ""
	for p in parts:
		var cand: String = String(p) if line == "" else line + "  ·  " + String(p)
		if _w(cand, UI.FONT["small"]) <= PANEL.x - 32:
			line = cand
	_text(origin + Vector2(16, 532), line, PANEL.x - 32, UI.FONT["small"],
			Color(0.95, 0.9, 0.6, 0.95) if not held.is_empty() else Color(0.72, 0.77, 0.87, 0.95))


## Предмет «в руке» — у курсора: иконка в рамке и количество.
func _draw_held() -> void:
	if held.is_empty() or mouse_pos.x < 0.0:
		return
	_tag = "held"
	var r: Rect2 = Rect2(mouse_pos + Vector2(-6, -6), Vector2(32, 32))
	draw_rect(r, Color(0.1, 0.12, 0.16, 0.85))
	draw_rect(r, Color(1.0, 0.9, 0.5, 0.9), false, 1.0)
	_icon(held.id, r.grow(-4))
	var s: String = str(held.count)
	var w: float = _w(s, UI.FONT["small"])
	var p: Vector2 = Vector2(r.end.x - w - 1, r.end.y - 2)
	draw_string_outline(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.FONT["small"], 3, Color(0, 0, 0, 0.9))
	_str(p, s, UI.FONT["small"], Color(1, 1, 1))


func _near_machine(kind: String) -> MachineBase:
	if player == null:
		return null
	for m in World.machines.values():
		if m.kind == kind and m.global_position.distance_to(player.global_position) < STATION_REACH:
			return m
	return null


## Сколько чего в инвентаре — один проход за кадр (иначе count_of по 36
## ячейкам зовётся на каждый вход каждого рецепта и каждую деталь цели).
func _count_inventory() -> void:
	_counts.clear()
	for st in player.inv.slots:
		if not st.is_empty():
			_counts[st.id] = int(_counts.get(st.id, 0)) + st.count


func _have(id: int) -> int:
	return int(_counts.get(id, 0))


## Станков нет (#170): рядом ничего не ищем.
func _scan_stations() -> void:
	_near = {}
	_built = {}


func _draw_slot(r: Rect2, stack: ItemStack, hotbar: bool) -> void:
	draw_rect(r, Color(0.13, 0.15, 0.19, 0.95))
	var hot: bool = r.has_point(mouse_pos)
	draw_rect(r, Color(1, 1, 1, 0.45) if hot else Color(1, 1, 1, 0.18), false, 1.0)
	if hotbar:
		draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), Color(0.5, 0.8, 1.0, 0.4))
	if stack.is_empty():
		return
	var isz: Vector2 = Vector2(SLOT - 14, SLOT - 14)   # иконка 24 px по центру ячейки (34 или 32 px)
	_icon(stack.id, Rect2((r.position + (r.size - isz) * 0.5).floor(), isz))
	if stack.count > 1:
		var s: String = str(stack.count)
		var w: float = _w(s, UI.FONT["small"])
		var p: Vector2 = Vector2(r.end.x - w - 2, r.end.y - 3)
		_str(p, s, UI.FONT["small"], Color(1, 1, 1, 0.95))


func _draw_recipe(r: Rect2, rec: Dictionary) -> void:
	_tag = "recipe"
	var out_id: int = int(rec["out"])
	var code: String = _recipe_code(rec)
	var can: bool = code == "ok"
	draw_rect(r, Color(0.09, 0.11, 0.14, 0.9))
	if r.has_point(mouse_pos) and held.is_empty():
		draw_rect(r, Color(1, 1, 1, 0.05))
	draw_rect(r, Color(0.4, 0.9, 0.5, 0.7) if can else Color(1, 1, 1, 0.15), false, 1.0)
	# Вспышка после клика: зелёная — получилось, красная — нет.
	var now: int = Time.get_ticks_msec()
	if now < _flash_until and _flash_rec == rec:
		var a: float = float(_flash_until - now) / float(FLASH_MS)
		var fc: Color = C_OK if _flash_ok else C_BAD
		draw_rect(r, Color(fc, 0.30 * a))
		draw_rect(r, Color(fc, 0.9 * a), false, 2.0)
	var dim: Color = Color(1, 1, 1, 1)
	_icon(out_id, Rect2(r.position + Vector2(6, 6), Vector2(28, 28)), dim)
	# Ярлык состояния справа.
	var tag: String = ""
	var tag_col: Color = C_OK
	match code:
		"missing":
			tag = "не хватает"
			tag_col = C_BAD
		"far", "none":
			tag = "станок далеко" if code == "far" else "нет станка"
			tag_col = C_WARN
	var tw: float = 0.0
	if tag != "":
		tw = minf(_w(tag, UI.FONT["small"]), 170.0)
		_text(Vector2(r.end.x - tw - 8, r.position.y + 17), tag, tw, UI.FONT["small"], tag_col, HORIZONTAL_ALIGNMENT_LEFT, r)
	var name_col: Color = Color(0.95, 0.97, 1.0) if can else Color(0.72, 0.75, 0.82)
	var title: String = String(rec["name"]) if String(rec["name"]) != "" else DB.item_name(out_id)
	if int(rec["amount"]) > 1:
		title += " ×%d" % int(rec["amount"])
	_text(r.position + Vector2(42, 17), title, r.size.x - 42 - tw - 18, UI.FONT["small"], name_col, HORIZONTAL_ALIGNMENT_LEFT, r)
	# Входы — иконка и короткое имя. Счёт «есть/нужно» остаётся в подсказке.
	var ins: Array = rec["in"].keys()
	var gx: float = r.position.x + 42
	for id in ins:
		var need: int = int(rec["in"][id])
		var have: int = _have(id)
		var col: Color = C_OK if have >= need else C_BAD
		_icon(id, Rect2(Vector2(gx, r.position.y + 23), Vector2(14, 14)), dim)
		gx += 16
		var label: String = _short_name(id)
		if need > 1:
			label += " ×%d" % need
		var left_n: int = ins.size() - ins.find(id)
		var room: float = maxf(8.0, (r.end.x - 6.0 - gx) / float(maxi(left_n, 1)) - 8.0)
		gx += _text(Vector2(gx, r.position.y + 34), label, room, UI.FONT["small"], col, HORIZONTAL_ALIGNMENT_LEFT, r) + 8


# ---------------------------------------------------------------- ПОДСКАЗКИ

## Что под курсором: {kind, i | rec | id}; пусто — ничего.
func _hover_target() -> Dictionary:
	var p: Vector2 = mouse_pos
	if player == null or not Rect2(_panel_pos(), PANEL).has_point(p):
		return {}
	if chest:
		for i in Chest.CAP:
			if _chest_slot_rect(i).has_point(p):
				return {"kind": "chest", "i": i}
		if _take_all_rect().has_point(p):
			return {"kind": "take_all"}
		if _put_all_rect().has_point(p):
			return {"kind": "put_all"}
	for i in player.inv.size:
		if _inv_slot_rect(i).has_point(p):
			return {"kind": "inv", "i": i}
	for i in TABS.size():
		if _tab_rect(i).has_point(p):
			return {"kind": "tab", "i": i}
	var recipes: Array = _recipes(String(STATIONS[station_tab]))
	var first: int = mini(scroll, _max_scroll())
	for i in range(first, mini(recipes.size(), first + RECIPE_ROWS)):
		if _recipe_row_rect(i - first).has_point(p):
			return {"kind": "recipe", "rec": recipes[i]}
	return {}


## Строки подсказки для цели под курсором: [{t, c, icon}].
func _tooltip_for(t: Dictionary) -> Array:
	var out: Array = []
	if player == null:
		return out
	_count_inventory()
	match String(t.get("kind", "")):
		"chest", "inv":
			if not held.is_empty():
				return out
			var from_chest: bool = String(t["kind"]) == "chest"
			var s: ItemStack = chest.slots[int(t["i"])] if from_chest else player.inv.slots[int(t["i"])]
			if s.is_empty():
				return out
			out.append(_line("%s ×%d" % [DB.item_name(s.id), s.count], C_TEXT, s.id))
			if from_chest:
				out.append(_line("Shift+ЛКМ — забрать стопку в инвентарь", C_HEAD))
			elif chest:
				out.append(_line("Shift+ЛКМ — положить стопку в сундук", C_HEAD))
			elif int(t["i"]) < player.inv.hotbar_size:
				out.append(_line("Shift+ЛКМ — убрать из хотбара в рюкзак", C_HEAD))
			else:
				out.append(_line("Shift+ЛКМ — переложить в хотбар", C_HEAD))
			out.append(_line("ЛКМ — взять в руку, ПКМ — взять половину", C_DIM))
		"take_all":
			out.append(_line("Переложить всё из сундука в инвентарь (что влезет).", C_TEXT))
		"put_all":
			out.append(_line("Переложить весь рюкзак в сундук. Хотбар (верхний ряд) остаётся при тебе.", C_TEXT))
		"tab":
			var tips: Array = [
				"Крафт руками: без станка, сразу в инвентарь.",
				"Плавильня: встань рядом с построенной плавильней — клик загружает в неё сырьё, плавит она сама.",
				"Верстак: встань рядом с построенным верстаком — клик загружает в него детали, собирает он сам.",
			]
			out.append(_line(String(tips[int(t["i"])]), C_TEXT))
		"recipe":
			out = _recipe_tooltip(t["rec"])
	return out


func _line(t: String, c: Color, icon: int = IDs.I.NONE) -> Dictionary:
	return {"t": t, "c": c, "icon": icon}


## Подсказка рецепта: что получится, где и за сколько, что нужно и почему нельзя.
func _recipe_tooltip(rec: Dictionary) -> Array:
	var out: Array = []
	var out_id: int = int(rec["out"])
	var station: String = String(rec["station"])
	var res: String = "%s ×%d" % [DB.item_name(out_id), int(rec["amount"])]
	if String(rec["name"]) != DB.item_name(out_id):
		res = "%s → %s" % [String(rec["name"]), res]
	out.append(_line(res, C_TEXT, out_id))
	out.append(_line("Станция: руками · сразу", C_DIM))
	for id in rec["in"].keys():
		var need: int = int(rec["in"][id])
		var have: int = _have(id)
		var col: Color = C_OK if have >= need else C_BAD
		out.append(_line("%s — есть %d / нужно %d" % [DB.item_name(id), have, need], col, int(id)))
	# Все причины, а не только первая: игрок сразу видит, что чинить.
	var reasons: Array = _recipe_problems(rec)
	for r in reasons:
		out.append(_line(String(r), C_WARN))
	if reasons.is_empty():
		out.append(_line("Клик — сделать: результат сразу в инвентаре.", C_OK))
	return out


func _draw_tooltip() -> void:
	var lines: Array = _tooltip_for(_hover_target())
	if lines.is_empty():
		return
	_tag = "tip"
	var fs_tip: int = UI.FONT["small"]
	const LH: float = 18.0
	# Раскладываем строки по ширине, считаем размер рамки.
	var rows: Array = []    ## [текст, цвет, иконка (только у первой части строки)]
	var max_w: float = 0.0
	for l in lines:
		var icon: int = int(l["icon"])
		var indent: float = 18.0 if icon != IDs.I.NONE else 0.0
		var parts: PackedStringArray = _wrap(String(l["t"]), TIP_W - 16.0 - indent, fs_tip)
		for k in parts.size():
			rows.append([parts[k], l["c"], icon if k == 0 else IDs.I.NONE, indent])
			max_w = maxf(max_w, _w(parts[k], fs_tip) + indent)
	var box_size: Vector2 = Vector2(minf(max_w + 16.0, TIP_W), rows.size() * LH + 10.0)
	var pos: Vector2 = mouse_pos + Vector2(18, 18)
	pos.x = clampf(pos.x, 4.0, size.x - box_size.x - 4.0)
	if pos.y + box_size.y > size.y - 4.0:
		pos.y = mouse_pos.y - box_size.y - 10.0
	pos.y = maxf(pos.y, 4.0)
	var box: Rect2 = Rect2(pos, box_size)
	draw_rect(box, Color(0.04, 0.05, 0.08, 0.97))
	draw_rect(box, Color(0.45, 0.8, 1.0, 0.8), false, 1.0)
	var y: float = pos.y + 5.0 + 13.0
	for row in rows:
		var x: float = pos.x + 8.0
		if int(row[2]) != IDs.I.NONE:
			_icon(int(row[2]), Rect2(Vector2(x, y - 12.0), Vector2(14, 14)))
		_text(Vector2(x + float(row[3]), y), String(row[0]), box.size.x - 16.0 - float(row[3]), fs_tip,
				row[1], HORIZONTAL_ALIGNMENT_LEFT, box)
		y += LH
	if text_audit != null:
		text_audit.append({"text": "<подсказка>", "full": "", "rect": box, "box": Rect2(Vector2.ZERO, size), "tag": "tip_box"})


# ---------------------------------------------------------------- СОСТОЯНИЕ РЕЦЕПТА

## Можно ли сделать рецепт прямо сейчас: {code, short, reason}.
## code: ok | far | none | missing. Рецепт без чертежа в список не попадает (#169).
func _recipe_status(rec: Dictionary) -> Dictionary:
	var code: String = _recipe_code(rec)
	var station: String = String(rec["station"])
	match code:
		"far", "none":
			return {"code": code, "short": "станок далеко" if code == "far" else "нет станка",
					"reason": _station_text(station)}
		"missing":
			return {"code": code, "short": "не хватает", "reason": "Не хватает: " + ", ".join(_missing(rec)) + "."}
	return {"code": "ok", "short": "клик — сделать" if station == "hand" else "клик — загрузить", "reason": ""}


## Только код состояния — без строк (строка рецепта зовёт его каждый кадр).
func _recipe_code(rec: Dictionary) -> String:
	var station: String = String(rec["station"])
	if station != "hand" and _near.get(station) == null:
		return "far" if bool(_built.get(station, false)) else "none"
	for id in rec["in"].keys():
		if _have(id) < int(rec["in"][id]):
			return "missing"
	return "ok"


## Все причины, почему рецепт сейчас не сделать (для подсказки).
func _recipe_problems(rec: Dictionary) -> Array:
	var out: Array = []
	var station: String = String(rec["station"])
	if station != "hand" and _near.get(station) == null:
		out.append(_station_text(station))
	var miss: Array = _missing(rec)
	if not miss.is_empty():
		out.append("Не хватает: " + ", ".join(miss) + ".")
	return out


func _station_text(_station: String) -> String:
	return "Крафт только руками."


## Чего не хватает: ["Медная руда (ещё 1)", …].
func _missing(rec: Dictionary) -> Array:
	var out: Array = []
	for id in rec["in"].keys():
		var short: int = int(rec["in"][id]) - _have(id)
		if short > 0:
			out.append("%s (ещё %d)" % [DB.item_name(id), short])
	return out


## Где взять предмет: станции рецептов, которые его делают.
func _source_of(id: int) -> String:
	_check_cache()
	if not _source.has(id):
		var parts: PackedStringArray = PackedStringArray()
		for r in DB.recipes:
			if int(r["out"]) != id:
				continue
			var p: String = "руками"
			if not parts.has(p):
				parts.append(p)
		_source[id] = ", ".join(parts) if not parts.is_empty() else "добыча и тайники руин"
	return String(_source[id])


## Одна строка про чертежи (#169): сколько уже есть. Имя следующего
## сюда не входит — длинное («Решётка вентиляции») резалось в «…».
func _blueprint_line() -> String:
	return "Чертежи: %d из %d" % [Game.blueprints.size(), Game.blueprint_total()]


# ---------------------------------------------------------------- КЭШ РЕЦЕПТОВ

func _check_cache() -> void:
	var seen_n: int = player.inv.seen_items.size() if player != null and player.inv != null else 0
	var bp_n: int = Game.blueprints.size()
	var key: int = DB.recipes.size() * 1000 + seen_n * 10 + bp_n
	if _cache_size == key:
		return
	_cache_size = key
	_recipes_cache = {}
	_source = {}


## Подписка на первое появление предмета: уведомление и сброс списка рецептов.
func _bind_seen(p: Player) -> void:
	if p == null or p.inv == null or p.inv == _seen_inv:
		return
	if _seen_inv != null and _seen_inv.item_first_seen.is_connected(_on_item_first_seen):
		_seen_inv.item_first_seen.disconnect(_on_item_first_seen)
	_seen_inv = p.inv
	if not _seen_inv.item_first_seen.is_connected(_on_item_first_seen):
		_seen_inv.item_first_seen.connect(_on_item_first_seen)


func _on_item_first_seen(id: int) -> void:
	_cache_size = -1
	for r in DB.recipes_opened_by(id, player):
		var text: String = "Теперь можно сделать: %s" % DB.item_name(int(r["out"]))
		var icon: int = int(r["out"])
		if player != null and player.has_method("_notify"):
			player._notify(text, Color(0.55, 0.95, 0.7), icon)
		else:
			Game.notify(text, Color(0.55, 0.95, 0.7), icon)
	queue_redraw()


## Короткое имя входа: 2–4 слова, без «…».
func _short_name(id: int) -> String:
	var name: String = DB.item_name(id)
	var words: PackedStringArray = name.split(" ", false)
	if words.size() <= 2:
		return name
	return " ".join(words.slice(0, 2))


## Рецепты станции. Чертёж и подбор прячут строку целиком (#169, #171).
func _recipes(station: String) -> Array:
	if _shot_rows is Array and station == "hand":
		return _shot_rows
	_check_cache()
	if not _recipes_cache.has(station):
		var shown: Array = []
		for r in DB.recipes_for(station):
			if DB.recipe_unlocked(r, player):
				shown.append(r)
		_recipes_cache[station] = shown
	return _recipes_cache[station]


func _max_scroll() -> int:
	return maxi(0, _recipes(String(STATIONS[station_tab])).size() - RECIPE_ROWS)


# ---------------------------------------------------------------- КЛИКИ

## Клик в точке pos (координаты панели). right — ПКМ, shift — с зажатым Shift.
func _click(pos: Vector2, right: bool, shift: bool = false) -> void:
	var quick: bool = shift and not right and held.is_empty()
	# Сундук
	if chest:
		for i in Chest.CAP:
			if _chest_slot_rect(i).has_point(pos):
				if quick:
					quick_move_chest(i)
				else:
					_click_chest(i, right)
				queue_redraw()
				return
		if _take_all_rect().has_point(pos):
			take_all()
			queue_redraw()
			return
		if _put_all_rect().has_point(pos):
			put_all()
			queue_redraw()
			return
	# Инвентарь
	for i in player.inv.size:
		if _inv_slot_rect(i).has_point(pos):
			if quick:
				quick_move_inv(i)
			else:
				_click_inv(i, right)
			queue_redraw()
			return
	# Рецепты: те же строки, что нарисованы (не больше RECIPE_ROWS).
	var recipes: Array = _recipes(String(STATIONS[station_tab]))
	var first: int = mini(scroll, _max_scroll())
	for i in range(first, mini(recipes.size(), first + RECIPE_ROWS)):
		if _recipe_row_rect(i - first).has_point(pos):
			_craft(recipes[i])
			queue_redraw()
			return
	# Вкладки
	for i in TABS.size():
		if _tab_rect(i).has_point(pos):
			station_tab = i
			scroll = 0
			queue_redraw()
			return


## Shift+ЛКМ по ячейке сундука: вся стопка — в инвентарь (что влезет).
func quick_move_chest(index: int) -> int:
	if chest == null:
		return 0
	if Net.is_client():   # СЕТЬ (ADR-002): команду выполняет хост
		return _net_quick(NetCodec.Box.CHEST, index)
	var r: Dictionary = InvOps.quick_from_chest(player.inv, chest, index)
	InvOps.chest_changed(chest)
	return _op_feedback(r, -14.0)


## Shift+ЛКМ по ячейке инвентаря: с открытым сундуком — стопку в сундук,
## без сундука — из хотбара в рюкзак и обратно.
func quick_move_inv(index: int) -> int:
	if Net.is_client():   # СЕТЬ (ADR-002): команду выполняет хост
		return _net_quick(NetCodec.Box.INV, index)
	var r: Dictionary = InvOps.quick_from_inv(player.inv, chest, index)
	InvOps.chest_changed(chest)
	return _op_feedback(r, -14.0)


## «Забрать всё»: всё из сундука — в инвентарь, что влезет. Возвращает число предметов.
func take_all() -> int:
	if chest == null:
		return 0
	if Net.is_client():   # СЕТЬ (ADR-002): команду выполняет хост
		InvOps.send(NetCodec.InvOp.TAKE_ALL, {"cell": InvOps.cell_of(chest)}, _on_net_op.bind(-12.0))
		return 0
	var r: Dictionary = InvOps.take_all(player.inv, chest)
	InvOps.chest_changed(chest)
	return _op_feedback(r, -12.0)


## «Сложить всё»: рюкзак (всё, кроме хотбара) — в сундук.
func put_all() -> int:
	if chest == null:
		return 0
	if Net.is_client():   # СЕТЬ (ADR-002): команду выполняет хост
		InvOps.send(NetCodec.InvOp.PUT_ALL, {"cell": InvOps.cell_of(chest)}, _on_net_op.bind(-12.0))
		return 0
	var r: Dictionary = InvOps.put_all(player.inv, chest)
	InvOps.chest_changed(chest)
	return _op_feedback(r, -12.0)


## Итог команды InvOps ({n, text, tone}) — звук и строка обратной связи. Возвращает n.
func _op_feedback(r: Dictionary, volume_db: float) -> int:
	var n: int = int(r["n"])
	if n > 0:
		Sfx.play("pickup", volume_db)
	if String(r["text"]) != "":
		_feedback(String(r["text"]), _tone_color(int(r["tone"])))
	return n


func _tone_color(tone: int) -> Color:
	match tone:
		InvOps.Tone.OK:
			return C_OK
		InvOps.Tone.WARN:
			return C_WARN
		InvOps.Tone.BAD:
			return C_BAD
		InvOps.Tone.DIM:
			return C_DIM
		InvOps.Tone.ERR:
			return Color(1.0, 0.6, 0.4)
	return C_TEXT


func _click_inv(index: int, right: bool) -> void:
	if Net.is_client():   # СЕТЬ (ADR-002): рука — окно, перекладывает хост
		_net_click(NetCodec.Box.INV, index, right)
		return
	_click_slot(player.inv.slots, index, right, not right)


func _click_chest(index: int, right: bool) -> void:
	if Net.is_client():   # СЕТЬ (ADR-002): рука — окно, перекладывает хост
		_net_click(NetCodec.Box.CHEST, index, right)
		return
	_click_slot(chest.slots, index, right, true)
	InvOps.chest_changed(chest)


## ЛКМ — взять стопку в руку / положить / обменять с рукой, ПКМ — взять половину /
## положить по одному. swap — другой предмет меняется с рукой (у сундука — и по ПКМ).
func _click_slot(arr: Array, index: int, right: bool, swap: bool) -> void:
	var slot: ItemStack = arr[index]
	if held.is_empty():
		if slot.is_empty():
			return
		InvOps.xfer(arr, index, _hand, 0, int(ceil(float(slot.count) * 0.5)) if right else slot.count)
		return
	var one: bool = right and (slot.is_empty() or slot.id == held.id)
	InvOps.xfer(_hand, 0, arr, index, 1 if one else held.count, swap)


## Обратная связь: строка внизу панели (HUD с уведомлениями панель закрывает),
## вспышка строки рецепта rec и, если notify, то же сообщение в журнал HUD.
func _feedback(text: String, col: Color, rec: Dictionary = {}, ok: bool = true, notify: bool = false) -> void:
	last_feedback = text
	_toast_col = col
	var now: int = Time.get_ticks_msec()
	_toast_until = now + TOAST_MS
	if not rec.is_empty():
		_flash_rec = rec
		_flash_ok = ok
		_flash_until = now + FLASH_MS
	if notify:
		Game.notify(text, col)
	set_process(true)
	queue_redraw()


func _craft(rec: Dictionary) -> void:
	_scan_stations()
	_count_inventory()
	var st: Dictionary = _recipe_status(rec)
	if String(st["code"]) != "ok":
		_feedback(String(st["reason"]), Color(1.0, 0.6, 0.4), rec, false, true)
		return
	var station: String = String(rec["station"])
	if Net.is_client():   # СЕТЬ (ADR-002): крафт выполняет хост у прокси, итог — ответом
		InvOps.send(NetCodec.InvOp.CRAFT, {"recipe": DB.recipes.find(rec), "times": 1}, _on_net_craft.bind(rec))
		return
	var r: Dictionary = InvOps.do_craft(player, rec, _near.get(station))
	_feedback(String(r["text"]), _tone_color(int(r["tone"])), rec, true, true)
	Sfx.play("craft", -6.0)


# ------------------------------------------------- СЕТЬ (ADR-002)
## Клиент (MP-G, #91, § 4.2.7): ячейки пишет хост — панель шлёт команды InvOps и
## показывает итог. «Рука» — состояние окна: стопка лежит в своей ячейке (_hand_from),
## ячейка рисуется за вычетом руки; клик по другой ячейке — команда move. Перекладывание
## панель сразу повторяет у себя тем же InvOps.xfer (прогноз), свежий INV и CHEST хоста
## его подтверждают или откатывают (опоздали — отказ и свежее содержимое).

## Клиент: откуда стопка в руке — [Box, слот]; пусто — рука пуста.
var _hand_from: Array = []


func _net_drop_hand() -> void:
	held = ItemStack.new()
	_hand_from = []


func _box_slots(box: int):
	if box == NetCodec.Box.CHEST:
		return chest.slots if chest else null
	return player.inv.slots if player else null


## Ячейка, как её рисовать: у клиента — без стопки, что сейчас «в руке».
func _shown(arr: Array, box: int, i: int) -> ItemStack:
	var s: ItemStack = arr[i]
	if _hand_from.is_empty() or int(_hand_from[0]) != box or int(_hand_from[1]) != i:
		return s
	return ItemStack.new(s.id, s.count - held.count) if s.count > held.count else ItemStack.new()


## Рука клиента указывает на ячейку, которую мог изменить хост (другой игрок забрал
## стопку из сундука): предмета там нет — рука пуста, стало меньше — в руке столько же.
func _net_check_hand() -> void:
	if _hand_from.is_empty() or InvOps.pending_count() > 0:
		return
	var arr = _box_slots(int(_hand_from[0]))
	var s: ItemStack = arr[int(_hand_from[1])] if arr != null else null
	if s == null or s.is_empty() or s.id != held.id:
		_net_drop_hand()
	elif s.count < held.count:
		held.count = s.count


func _net_click(box: int, index: int, right: bool) -> void:
	var arr = _box_slots(box)
	if arr == null:
		return
	var slot: ItemStack = arr[index]
	if held.is_empty():
		if slot.is_empty():
			return
		held = ItemStack.new(slot.id, int(ceil(float(slot.count) * 0.5)) if right else slot.count)
		_hand_from = [box, index]
		return
	var fbox: int = int(_hand_from[0])
	var fi: int = int(_hand_from[1])
	if fbox == box and fi == index:
		# Обратно в свою ячейку: стопка и не уходила.
		if right:
			held.take(1)
		else:
			held = ItemStack.new()
		if held.is_empty():
			_hand_from = []
		return
	var src = _box_slots(fbox)
	if src == null:
		_net_drop_hand()
		return
	var same: bool = slot.is_empty() or slot.id == held.id
	var swap: bool = box == NetCodec.Box.CHEST or not right
	if not same:
		if not swap:
			return
		if (src[fi] as ItemStack).count != held.count:
			_feedback("Обменять можно только всю стопку: сначала положи её в пустую ячейку.", C_WARN)
			return
	var n: int = 1 if right and same else held.count
	var id: int = held.id
	var k: int = InvOps.xfer(src, fi, arr, index, n, swap)
	if k <= 0:
		return
	InvOps.send(NetCodec.InvOp.MOVE, {"from": fbox, "fslot": fi, "to": box, "tslot": index, "id": id,
			"n": n, "flags": NetCodec.MOVE_SWAP if swap and not same else 0, "cell": InvOps.cell_of(chest)},
			_on_net_move)
	if not same:
		# Обмен: в руке теперь стопка, что лежала в «куда» — она уже в ячейке руки.
		var now_src: ItemStack = src[fi]
		held = ItemStack.new(now_src.id, now_src.count)
	else:
		held.take(k)
		if held.is_empty():
			_hand_from = []


## Shift+ЛКМ у клиента: стопка целиком «в другое место» — хост решает куда.
func _net_quick(box: int, index: int) -> int:
	var arr = _box_slots(box)
	if arr == null:
		return 0
	var s: ItemStack = arr[index]
	if s.is_empty():
		return 0
	InvOps.send(NetCodec.InvOp.MOVE, {"from": box, "fslot": index,
			"to": NetCodec.Box.INV if box == NetCodec.Box.CHEST or chest == null else NetCodec.Box.CHEST,
			"tslot": NetCodec.SLOT_AUTO, "id": s.id, "n": s.count, "cell": InvOps.cell_of(chest)},
			_on_net_op.bind(-14.0))
	return 0


func _on_net_op(ok: bool, text: String, volume_db: float) -> void:
	if ok:
		Sfx.play("pickup", volume_db)
	if text != "":
		_feedback(text, C_OK if ok else C_BAD)


func _on_net_move(ok: bool, text: String) -> void:
	if not ok and text != "":
		_feedback(text, C_BAD)
	_net_check_hand()
	queue_redraw()


func _on_net_craft(ok: bool, text: String, rec: Dictionary) -> void:
	_feedback(text, C_OK if ok else Color(1.0, 0.6, 0.4), rec, ok, true)
	if ok:
		Sfx.play("craft", -6.0)



