class_name Analyzer
extends MachineBase
## Анализатор (ADR-001 § 4.2, #30): разбирает кристалл глитча на «данные» для
## исследований. Один кристалл → Balance.ANALYZER_DATA данных за
## Balance.ANALYZER_PERIOD секунд полезной работы (с учётом efficiency).
## Кристаллы — руками (E с кристаллом в хотбаре), с конвейера или манипулятора.

const PERIOD: float = Balance.ANALYZER_PERIOD
## Сколько кристаллов помещается в лоток (не считая того, что в работе).
const CAP: int = 10
## Кристалл в окне: цвета руды-кристалла и светлое ядро свечения (DB.PAL).
const C_CRYSTAL: Color = _PAL["crystal"]
const C_CRYSTAL_D: Color = _PAL["crystal_d"]
const C_BIO_CORE: Color = _PAL["bio_core"]

var crystals: int = 0
## Сколько данных выдал анализатор за всё время (для сценариев и HUD).
var produced: int = 0

var _busy: bool = false
var _timer: float = 0.0


func _init() -> void:
	kind = "Analyzer"
	z_index = 3


func input_accepts(item_id: int) -> bool:
	return item_id == IDs.I.CRYSTAL


func receive_item(item_id: int, count: int) -> int:
	if not input_accepts(item_id):
		return count
	var take: int = mini(CAP - crystals, count)
	if take <= 0:
		return count
	crystals += take
	queue_redraw()
	return count - take


## Разрушен — кристаллы из лотка высыпаются.
func _on_destroyed() -> void:
	if crystals > 0:
		spawn_item(IDs.I.CRYSTAL, crystals, global_position + Vector2(0.0, -4.0))
		crystals = 0


## Работает ли сейчас (для отрисовки: мерцание только в работе).
func has_time_animation() -> bool:
	return _busy and powered


func _process(delta: float) -> void:
	super(delta)
	if not powered:
		return
	if not _busy:
		if crystals <= 0:
			return
		crystals -= 1
		_busy = true
		_timer = 0.0
	_timer += work(delta)
	progress = clampf(_timer / PERIOD, 0.0, 1.0)
	if _timer >= PERIOD:
		_busy = false
		_timer = 0.0
		progress = 0.0
		produced += Balance.ANALYZER_DATA
		Game.research += Balance.ANALYZER_DATA
		Sfx.play("craft", -14.0, 1.5)
		Game.notify("Анализатор: +%d данных" % Balance.ANALYZER_DATA, Color(0.5, 0.95, 0.9))
		queue_redraw()


func _draw() -> void:
	_draw_body(BODY, powered, false)
	# Окно камеры с кристаллом: рама, тёмное стекло.
	draw_rect(Rect2(-5.0, -4.0, 10.0, 9.0), C_FRAME)
	draw_rect(Rect2(-4.0, -3.0, 8.0, 7.0), C_SCREEN)
	var pulse: float = 0.0
	if _busy and powered:
		pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
	# Кристалл — вертикальная призма (язык руд § 3.2): в работе светится и пульсирует.
	var cry: Color = C_CRYSTAL if _busy else C_CRYSTAL_D
	cry = cry.lerp(C_BIO_CORE, pulse * 0.5)
	draw_rect(Rect2(-1.0, -2.0, 3.0, 5.0), cry)
	draw_rect(Rect2(0.0, -3.0, 1.0, 1.0), cry)
	draw_rect(Rect2(-1.0, -2.0, 1.0, 2.0), cry.lerp(C_BIO_CORE, 0.6))
	# Сканирующая линия идёт по окну вместе с прогрессом.
	if _busy:
		var y: float = floorf(-3.0 + 6.99 * progress)
		draw_rect(Rect2(-4.0, y, 8.0, 1.0), Color(C_SCREEN_HI, 0.8))
	# Кристаллы в лотке — квадраты 2×2 на полке снизу.
	draw_rect(Rect2(-7.0, 5.0, 14.0, 2.0), C_METAL_D)
	for i in mini(crystals, 5):
		draw_rect(Rect2(-6.0 + i * 3.0, 5.0, 2.0, 2.0), C_CRYSTAL)
	_draw_lamp(Vector2(6.0, -6.0), C_SCREEN_HI if powered else C_LAMP_OFF)
	if progress > 0.0:
		_draw_progress(-12.0)


# ------------------------------------------------------------- СОХРАНЕНИЕ (#37)
## Лоток, счётчик данных и кристалл в работе.
func save_state() -> Dictionary:
	var d: Dictionary = super()
	d["crystals"] = crystals
	d["produced"] = produced
	d["busy"] = _busy
	d["timer"] = _timer
	return d


func load_state(d: Dictionary) -> void:
	super(d)
	crystals = int(d.get("crystals", crystals))
	produced = int(d.get("produced", produced))
	_busy = bool(d.get("busy", _busy))
	_timer = float(d.get("timer", _timer))
