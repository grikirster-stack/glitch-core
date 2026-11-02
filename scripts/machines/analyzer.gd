class_name Analyzer
extends MachineBase
## Анализатор (ADR-001 § 4.2, #30): разбирает кристалл глитча на «данные» для
## исследований. Один кристалл → Balance.ANALYZER_DATA данных за
## Balance.ANALYZER_PERIOD секунд полезной работы (с учётом efficiency).
## Кристаллы — руками (E с кристаллом в хотбаре), с конвейера или манипулятора.

const PERIOD: float = Balance.ANALYZER_PERIOD
## Сколько кристаллов помещается в лоток (не считая того, что в работе).
const CAP: int = 10

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
	var base: Color = Color(0.20, 0.36, 0.36) if powered else Color(0.16, 0.24, 0.25)
	draw_rect(Rect2(-8.0, -8.0, 16.0, 16.0), base)
	draw_rect(Rect2(-8.0, -8.0, 16.0, 2.0), base.lightened(0.25))
	# Окно камеры с кристаллом.
	draw_rect(Rect2(-5.0, -4.0, 10.0, 9.0), Color(0.06, 0.10, 0.12))
	var pulse: float = 0.0
	if _busy and powered:
		pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
	var cry: Color = Color(0.45, 0.85, 1.0) if _busy else Color(0.25, 0.40, 0.48)
	cry = cry.lerp(Color(0.9, 1.0, 1.0), pulse * 0.5)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0.0, -3.0), Vector2(3.0, 0.5), Vector2(0.0, 4.0), Vector2(-3.0, 0.5),
	]), cry)
	# Сканирующая линия идёт по окну вместе с прогрессом.
	if _busy:
		var y: float = -4.0 + 9.0 * progress
		draw_line(Vector2(-5.0, y), Vector2(5.0, y), Color(0.6, 1.0, 0.8, 0.8), 1.0)
	# Кристаллы в лотке — точки снизу.
	for i in mini(crystals, 5):
		draw_rect(Rect2(-6.0 + i * 2.6, 6.0, 1.6, 1.6), Color(0.45, 0.85, 1.0))
	draw_circle(Vector2(5.5, -5.5), 1.4, Color(0.4, 1.0, 0.5) if powered else Color(0.9, 0.25, 0.2))
	if progress > 0.0:
		draw_rect(Rect2(-6.0, -12.0, 12.0, 2.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-6.0, -12.0, 12.0 * progress, 2.0), Color(0.4, 0.9, 1.0))
