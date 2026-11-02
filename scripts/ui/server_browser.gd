class_name ServerBrowser
extends VBoxContainer
## Список игр в локальной сети (ADR-002 § 4.5; MP-H, #93) для экрана «Найти игру».
##
## Держит LanDiscovery в режиме поиска; каждая найденная игра — строка-кнопка во всю
## ширину (тап — join_requested(ip, порт)): имя игры, ник хоста, игроков n/max, пинг,
## смена (или «лобби»), версия сборки и протокол. Несовместимая (другой протокол,
## другая сборка, мест нет) — серая, неактивная, с причиной вместо «Войти».
## «Обновить» — refresh(): список заново, запрос сразу.

signal join_requested(ip: String, port: int)

## Скрипт автозагрузки Net (константы): по имени не обращаемся — меню грузят и
## инструменты в режиме --script.
const NetScript = preload("res://scripts/autoload/net.gd")

const ROW_H: float = 64.0
const LIST_H: float = 300.0
const OK_COLOR: Color = Color(0.92, 0.95, 1.0)
const GREY_COLOR: Color = Color(0.5, 0.53, 0.6)
const BAD_COLOR: Color = Color(1.0, 0.62, 0.45)

var discovery: LanDiscovery = null
## Строки списка: "ip:порт" → Button (тесты тапают по ним).
var rows: Dictionary = {}
var empty_label: Label
var list_box: VBoxContainer
var scroll: ScrollContainer

var _width: float = 720.0


func _init(width: float = 720.0) -> void:
	_width = width


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	custom_minimum_size = Vector2(_width, 0)
	scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(_width, LIST_H)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 6)
	scroll.add_child(list_box)
	empty_label = Label.new()
	empty_label.add_theme_font_size_override("font_size", 17)
	empty_label.add_theme_color_override("font_color", GREY_COLOR)
	empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	empty_label.custom_minimum_size = Vector2(_width - 20.0, 0)
	list_box.add_child(empty_label)
	discovery = LanDiscovery.new()
	discovery.name = "Discovery"
	add_child(discovery)
	discovery.hosts_changed.connect(_rebuild)
	_rebuild()


## Начать поиск (bind и цели — для тестов на петле; по умолчанию широковещательно).
func start(port: int = NetScript.DISCOVERY_PORT, bind_ip: String = "*",
		targets: PackedStringArray = PackedStringArray()) -> Error:
	var err: Error = discovery.start_search(port, bind_ip, targets)
	_rebuild()
	return err


func stop() -> void:
	if discovery != null:
		discovery.stop()


func refresh() -> void:
	discovery.refresh()
	_rebuild()


## Подпись строки игры: две строки (тесты сверяют текст).
static func row_text(e: Dictionary) -> String:
	var state: String = "лобби" if String(e.get("st", "")) == "lobby" else "смена %d" % int(e.get("day", 0))
	var head: String = "%s — %s    игроков %d/%d    %d мс    %s" % [String(e.get("name", "?")),
			String(e.get("host", "?")), int(e.get("n", 0)), int(e.get("max", 0)),
			int(e.get("ping_ms", 0)), state]
	var reason: String = String(e.get("reason", ""))
	var tail: String = "%s:%d    версия %s · протокол %d" % [String(e.get("ip", "")), int(e.get("port", 0)),
			String(e.get("build", "?")), int(e.get("proto", 0))]
	return head + "\n" + tail + ("    — " + reason if reason != "" else "")


func _rebuild() -> void:
	if list_box == null:
		return
	var list: Array = discovery.sorted_hosts() if discovery != null else []
	var seen: Dictionary = {}
	for e in list:
		var key: String = "%s:%d" % [String(e["ip"]), int(e["port"])]
		seen[key] = true
		var b: Button = rows.get(key, null)
		if b == null:
			b = Button.new()
			b.custom_minimum_size = Vector2(_width - 20.0, ROW_H)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.add_theme_font_size_override("font_size", 16)
			b.focus_mode = Control.FOCUS_ALL
			b.pressed.connect(_on_row.bind(key))
			list_box.add_child(b)
			rows[key] = b
		b.text = row_text(e)
		var bad: bool = String(e["reason"]) != ""
		b.disabled = bad
		b.tooltip_text = String(e["reason"]) if bad else "Войти"
		b.add_theme_color_override("font_color", OK_COLOR)
		b.add_theme_color_override("font_disabled_color", GREY_COLOR)
		b.set_meta("entry", e)
	for key in rows.keys():
		if not seen.has(key):
			(rows[key] as Button).queue_free()
			rows.erase(key)
	# Порядок строк — как в sorted_hosts (совместимые сверху).
	var i: int = 1
	for e in list:
		var b2: Button = rows["%s:%d" % [String(e["ip"]), int(e["port"])]]
		list_box.move_child(b2, i)
		i += 1
	empty_label.visible = rows.is_empty()
	if discovery == null or not discovery.is_running():
		empty_label.text = "Поиск не запущен"
	else:
		empty_label.text = "Ищем игры в локальной сети… Если игра не находится — «По IP» (адрес — на экране хоста)."


func _on_row(key: String) -> void:
	var b: Button = rows.get(key, null)
	if b == null or b.disabled:
		return
	var e: Dictionary = b.get_meta("entry", {})
	join_requested.emit(String(e.get("ip", "")), int(e.get("port", NetScript.GAME_PORT)))


## Запись найденной игры по ключу ip:порт ({} — нет).
func entry(key: String) -> Dictionary:
	return discovery.hosts.get(key, {}) if discovery != null else {}
