class_name EndScreen
extends Control
## Экран победы/поражения с итогами забега. Он же — экран смерти с эпитафией
## из Lore и отсчётом до респауна (ADR-001 § 4.8, #29): тогда R не перезапускает.
## Победа (§ 4.7, #32) — эпилог из Lore.epilogue() абзацами и итоги в две колонки.
##
## Живёт в своём CanvasLayer (LAYER, main.gd): в экранных координатах, поверх
## мира, тумана войны и HUD.

signal restart_requested
## Глава кампании пройдена — дальше следующая (ADR-004): N, Enter или тап.
signal next_requested
## Победа свободной игры: игрок остаётся (ADR-005 § 6.4, #174). C или тап по кнопке.
signal stay_requested

## Слой CanvasLayer экрана: выше UI (HUD, инвентарь, журнал — слой 10).
const LAYER: int = 20
## Эпилог не шире этого, px — строки длиннее читать трудно.
const EPILOGUE_MAX_W: float = 760.0
const EPILOGUE_FONT: int = 15
const STATS_FONT: int = 15
const STATS_ROW: float = 21.0

var title: String = ""
var subtitle: String = ""
var color: Color = Color.WHITE
var stats: Array = []
var t: float = 0.0
## Экран смерти перед респауном: сколько секунд показывать (< 0 — финальный экран).
var respawn_delay: float = -1.0
## Эпилог победы (абзацы через «\n»); пусто — обычный экран.
var epilogue: String = ""
## Итог главы кампании: есть следующая глава (подсказка «[N] — дальше»).
var can_next: bool = false
## Победа свободной игры: кнопка «Остаться на планете» (не кампания, не хардкор).
var can_stay: bool = false
## Прямоугольник кнопки в экранных px (тап и клик); пустой — кнопки нет.
## Хитбокс не меньше нарисованного прямоугольника и не уже пальца (MIN_HIT).
var stay_rect: Rect2 = Rect2()
## Палец не должен промахиваться мимо текста: минимум стороны хитбокса, px.
const STAY_MIN_HIT: float = 44.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func show_end(p_title: String, p_subtitle: String, p_color: Color, p_stats: Array) -> void:
	title = p_title
	subtitle = p_subtitle
	color = p_color
	stats = p_stats
	respawn_delay = -1.0
	epilogue = ""
	can_next = false
	can_stay = false
	stay_rect = Rect2()
	net_death = false
	net_watch = ""
	visible = true
	t = 0.0
	queue_redraw()


## Победа: сигнал ушёл на орбиту — эпилог экспедиции и итоги.
func show_victory(p_epilogue: String, p_stats: Array) -> void:
	show_end("ЭВАКУАЦИЯ", "Сигнал принят на орбите. Капсула уходит вверх.",
			Color(0.40, 1.0, 0.78), p_stats)
	epilogue = p_epilogue


## Итог главы кампании (ADR-004): заголовок, глава, текст абзацами — раскладкой эпилога.
## p_next — есть следующая глава: N / Enter / тап ведут дальше, R — заново.
func show_mission(p_title: String, p_subtitle: String, p_text: String, p_color: Color,
		p_stats: Array, p_next: bool) -> void:
	show_end(p_title, p_subtitle, p_color, p_stats)
	epilogue = p_text if p_text != "" else " "
	can_next = p_next


## Экран смерти с эпитафией и отсчётом до респауна в капсуле.
func show_death(p_epitaph: String, delay: float) -> void:
	show_end("ТЕБЯ НАШЛИ", p_epitaph, Color(0.92, 0.28, 0.34), [])
	respawn_delay = delay


func hide_end() -> void:
	visible = false
	respawn_delay = -1.0
	can_next = false
	can_stay = false
	stay_rect = Rect2()
	epilogue = ""
	net_death = false
	net_watch = ""


func _process(delta: float) -> void:
	if visible:
		t += delta
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	# Клик по кнопке приходит сюда: Control на весь экран с MOUSE_FILTER_STOP,
	# и до _input мышь не доходит. В headless вьюпорт её тоже не доводит —
	# сценарий зовёт _gui_input напрямую, как панель инвентаря (#69, #214).
	_on_pointer(event)


func _input(event: InputEvent) -> void:
	if not visible or respawn_delay >= 0.0 or net_death:   # смерть в сети: R не перезапускает
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event
		if can_next and (k.keycode == KEY_N or k.keycode == KEY_ENTER):
			_eat()
			next_requested.emit()
		elif can_stay and k.keycode == KEY_C:
			_eat()
			stay_requested.emit()
		elif k.keycode == KEY_R or k.keycode == KEY_ENTER or k.keycode == KEY_SPACE:
			_eat()
			restart_requested.emit()
		return
	# Клик мышью Control с MOUSE_FILTER_STOP забирает в _gui_input и до _input
	# не доводит. Тап (и клик, если GUI его пропустил) обрабатываем здесь.
	_on_pointer(event)


## Погасить клавишу в текущем вьюпорте.
##
## Зовём ДО сигнала: сигнал может перезагрузить сцену (R — заново, N — следующая
## глава), а сцена уходит из дерева уже внутри сигнала — тогда get_viewport()
## вернёт null, и падение на set_input_as_handled() уронит кадр (#225).
func _eat() -> void:
	var vp: Viewport = get_viewport()
	if vp != null:
		vp.set_input_as_handled()


## Тап и клик ЛКМ. Кнопка «Остаться» срабатывает сразу; промах по экрану — новая
## попытка, но не раньше 1.5 с (случайный тап в момент смерти забег не рвёт).
func _on_pointer(event: InputEvent) -> void:
	if not visible or respawn_delay >= 0.0 or net_death:
		return
	var pos: Vector2 = Vector2(-1, -1)
	var down: bool = false
	if event is InputEventScreenTouch and event.pressed:
		pos = event.position
		down = true
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
		down = true
	if not down:
		return
	if can_stay and _stay_hit(pos):
		_eat()
		accept_event()
		stay_requested.emit()
	elif event is InputEventScreenTouch and t > 1.5:
		_eat()
		if can_next:
			next_requested.emit()
		else:
			restart_requested.emit()


func _draw() -> void:
	var a: float = clampf(t * 1.6, 0.0, 1.0)
	if net_death:   # СЕТЬ (ADR-002 § 4.7): мир виден — глазами товарища
		_draw_net_death(a)
		return
	# Победа с выбором «остаться» — мир просвечивает: туман и база видны, это не конец.
	var veil: float = 0.38 if can_stay else 0.86
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.05, veil * a))
	var font: Font = ThemeDB.fallback_font
	if epilogue != "":
		_draw_victory(font, a)
		return
	var cy: float = size.y * 0.30
	var bob: float = sin(t * 2.0) * 3.0
	draw_string(font, Vector2(0, cy + bob), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 52, Color(color.r, color.g, color.b, a))
	draw_string(font, Vector2(0, cy + 44), subtitle, HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, Color(0.85, 0.9, 1.0, a))
	var y: float = cy + 90
	for s in stats:
		draw_string(font, Vector2(0, y), String(s), HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, Color(0.8, 0.85, 0.95, a))
		y += 26
	if respawn_delay >= 0.0:
		var left: int = ceili(maxf(0.0, respawn_delay - t))
		draw_string(font, Vector2(0, size.y * 0.78), "Капсула на базе через %d с…" % left,
				HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, Color(1.0, 0.95, 0.7, a))
		return
	_draw_prompt(font, a, size.y * 0.78)


## Победа: заголовок выше, эпилог абзацами по ширине, итоги в две колонки.
## Раскладка от высоты экрана — влезает и в 960×540.
func _draw_victory(font: Font, a: float) -> void:
	var w: float = size.x
	var bob: float = sin(t * 2.0) * 3.0
	var y: float = maxf(56.0, size.y * 0.13)
	draw_string(font, Vector2(0, y + bob), title, HORIZONTAL_ALIGNMENT_CENTER, w, 44, Color(color.r, color.g, color.b, a))
	y += 34
	draw_string(font, Vector2(0, y), subtitle, HORIZONTAL_ALIGNMENT_CENTER, w, 18, Color(0.85, 0.9, 1.0, a))
	y += 30
	# Эпилог: абзацы — по «\n», перенос по словам внутри колонки.
	var ew: float = minf(EPILOGUE_MAX_W, w - 64.0)
	var ex: float = (w - ew) * 0.5
	var line_h: float = font.get_height(EPILOGUE_FONT) + 2.0
	for para in epilogue.split("\n", false):
		var ps: Vector2 = font.get_multiline_string_size(para, HORIZONTAL_ALIGNMENT_CENTER, ew, EPILOGUE_FONT)
		draw_multiline_string(font, Vector2(ex, y + font.get_ascent(EPILOGUE_FONT)), para,
				HORIZONTAL_ALIGNMENT_CENTER, ew, EPILOGUE_FONT, -1, Color(0.92, 0.94, 1.0, a))
		y += maxf(ps.y, line_h) + 6.0
	# Итоги — две колонки по центру.
	y += 10.0
	var col_w: float = minf(320.0, (w - 64.0) * 0.5)
	var half: int = ceili(float(stats.size()) / 2.0)
	for i in stats.size():
		var cx: float = w * 0.5 - col_w + (col_w if i >= half else 0.0)
		var sy: float = y + float(i % half) * STATS_ROW
		draw_string(font, Vector2(cx, sy), String(stats[i]), HORIZONTAL_ALIGNMENT_CENTER, col_w,
				STATS_FONT, Color(0.75, 0.82, 0.95, a))
	y += float(half) * STATS_ROW + 14.0
	var prompt_y: float = maxf(y + 8.0, size.y - 34.0)
	if can_stay:
		# Кнопка — над хотбаром (он кончается за 32 px от низа) и над подсказкой
		# клавиш. На 960×540 остаётся под итогами, на 720 — не тонет в них.
		var by: float = minf(maxf(y + 6.0, size.y - 168.0), prompt_y - 52.0)
		_draw_stay(font, a, by)
	_draw_prompt(font, a, prompt_y)


## Кнопка «Остаться на планете» под итогами. Прямоугольник — хитбокс тапа и клика.
func _draw_stay(font: Font, a: float, y: float) -> float:
	var label: String = "Остаться на планете"
	var fs: int = 22
	var tw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var bw: float = maxf(tw + 48.0, STAY_MIN_HIT)
	var bh: float = maxf(40.0, STAY_MIN_HIT)
	var bx: float = (size.x - bw) * 0.5
	stay_rect = Rect2(bx, y, bw, bh)
	var hot: Color = Color(0.40, 1.0, 0.78, a)
	draw_rect(stay_rect, Color(0.06, 0.14, 0.12, 0.92 * a))
	draw_rect(stay_rect, hot, false, 2.0)
	var ascent: float = font.get_ascent(fs)
	draw_string(font, Vector2(bx, y + (bh - font.get_height(fs)) * 0.5 + ascent), label,
			HORIZONTAL_ALIGNMENT_CENTER, bw, fs, hot)
	return y + bh + 8.0


## Точка в хитбоксе кнопки. Прямоугольник уже не уже текста и не уже пальца.
func _stay_hit(pos: Vector2) -> bool:
	return stay_rect.size.x > 0.0 and stay_rect.has_point(pos)


func _draw_prompt(font: Font, a: float, y: float) -> void:
	var blink: float = 0.55 + 0.45 * sin(t * 4.0)
	var line: String = "[R] — новая попытка"
	if can_next:
		line = "[N] — следующая глава   [R] — заново"
	elif can_stay:
		line = "[C] — остаться на планете   [R] — новая попытка"
	draw_string(font, Vector2(0, y), line,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, Color(1.0, 0.95, 0.7, a * blink))


# ------------------------------------------------- СЕТЬ (ADR-002 § 4.7, MP-I #94)
## Смерть в сети: экран не закрывает мир — камера идёт за живым товарищем (NetCoop,
## A/D — следующий), сверху «ТЕБЯ НАШЛИ», эпитафия и отсчёт до капсулы. Время забега не
## двигается. delay < 0 — --hardcore: зритель до конца забега. Вайп (погибли все)
## меняет отсчёт на одиночный (Balance.RESPAWN_DELAY) — тем же вызовом.

## Экран смерти в сети (показан, пока герой мёртв).
var net_death: bool = false
## Ник товарища, за которым идёт камера ("" — живых нет).
var net_watch: String = ""
## Зритель до конца забега (--hardcore в сети).
var net_spectator: bool = false
## Погибла вся команда — отсчёт одиночный, часы уйдут к рассвету.
var net_wipe: bool = false


## Показать (или обновить отсчёт, если экран уже открыт) смерть в сети.
func show_net_death(p_epitaph: String, delay: float, wipe: bool = false) -> void:
	if not (visible and net_death):
		show_end("ТЕБЯ НАШЛИ", p_epitaph, Color(0.92, 0.28, 0.34), [])
		net_death = true
	net_spectator = delay < 0.0
	net_wipe = wipe
	respawn_delay = -1.0 if net_spectator else t + delay
	queue_redraw()


## Секунд до капсулы (−1 — зритель или экран не про смерть в сети).
func net_respawn_left() -> float:
	if not net_death or net_spectator:
		return -1.0
	return maxf(0.0, respawn_delay - t)


func _draw_net_death(a: float) -> void:
	var font: Font = ThemeDB.fallback_font
	var w: float = size.x
	draw_rect(Rect2(0, 0, w, 120.0), Color(0.02, 0.02, 0.05, 0.62 * a))
	draw_rect(Rect2(0, size.y - 64.0, w, 64.0), Color(0.02, 0.02, 0.05, 0.62 * a))
	draw_string(font, Vector2(0, 52), title, HORIZONTAL_ALIGNMENT_CENTER, w, 40,
			Color(color.r, color.g, color.b, a))
	draw_string(font, Vector2(0, 84), subtitle, HORIZONTAL_ALIGNMENT_CENTER, w, 17, Color(0.85, 0.9, 1.0, a))
	var eyes: String = "Глазами: %s · A/D — следующий" % net_watch if net_watch != "" else "Живых рядом нет"
	draw_string(font, Vector2(0, 108), eyes, HORIZONTAL_ALIGNMENT_CENTER, w, 14, Color(0.7, 0.85, 1.0, a))
	var line: String
	if net_spectator:
		line = "Хардкор: ты — зритель до конца забега."
	elif net_wipe:
		line = "Погибла вся команда. Капсулы на базе через %d с — к рассвету…" % ceili(net_respawn_left())
	else:
		line = "Капсула на базе через %d с…" % ceili(net_respawn_left())
	draw_string(font, Vector2(0, size.y - 26.0), line, HORIZONTAL_ALIGNMENT_CENTER, w, 20,
			Color(1.0, 0.95, 0.7, a))
