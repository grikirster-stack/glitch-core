class_name CoalGen
extends Generator
## Угольная ТЭЦ: жжёт уголь и даёт энергию в радиусе.
##
## Уголь — руками (E с углём в хотбаре) или с конвейера/манипулятора
## (receive_item). Выключенная рубильником ТЭЦ уголь не жжёт.

const BURN: float = Balance.COAL_BURN   ## секунд горения одной единицы угля
const FUEL_VALUE: int = 1
const FUEL_MAX_UNITS: int = 12          ## сколько угля помещается в топку

var fuel: float = 0.0


func _init() -> void:
	kind = "CoalGen"
	power_radius = 8.0
	power_output = float(Balance.POWER_OUT["CoalGen"])


func _process(delta: float) -> void:
	super(delta)
	if enabled and fuel > 0.0:
		fuel = maxf(0.0, fuel - delta)
	power_active = enabled and fuel > 0.0
	queue_redraw()


## Есть ли в топке место ещё на одну единицу угля.
func has_room() -> bool:
	return fuel <= BURN * float(FUEL_MAX_UNITS - 1)


## Загрузить уголь. Возвращает, сколько единиц принято (топка не бездонная).
func add_fuel(count: int) -> int:
	var added: int = 0
	for i in count:
		if not has_room():
			break
		fuel += BURN
		added += 1
	return added


func input_accepts(item_id: int) -> bool:
	return item_id == IDs.I.COAL


## Уголь с конвейера/манипулятора. Возвращает, сколько НЕ принято.
func receive_item(item_id: int, count: int) -> int:
	if not input_accepts(item_id):
		return count
	return count - add_fuel(count)


## E: с углём в хотбаре — загрузить топку, иначе — рубильник.
func _on_interact(p) -> void:
	var st = p.inv.selected_stack()
	if st.id == IDs.I.COAL and st.count > 0:
		var added: int = add_fuel(st.count)
		if added > 0:
			p.inv.remove_at(p.inv.selected, added)
			Sfx.play("craft", -12.0)
			Game.notify("Уголь загружен в ТЭЦ.", Color(1.0, 0.8, 0.4))
		else:
			Game.notify("Топка ТЭЦ полна.", Color(1.0, 0.7, 0.4))
		return
	set_enabled(not enabled)
	if enabled and fuel <= 0.0:
		Game.notify("Нужен уголь в хотбаре.", Color(1.0, 0.7, 0.4))


func _draw() -> void:
	var hot: bool = power_active
	var base: Color = Color(0.30, 0.30, 0.34)
	draw_rect(Rect2(-8.0, -8.0, 16.0, 16.0), base)
	draw_rect(Rect2(-8.0, -8.0, 16.0, 2.0), base.lightened(0.2))
	# Топка
	var glow: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.01)
	var c: Color = Color(0.95, 0.45, 0.12) if hot else Color(0.22, 0.20, 0.20)
	if hot:
		c = c.lerp(Color(1.0, 0.85, 0.4), glow * 0.5)
	draw_rect(Rect2(-5.0, 0.0, 10.0, 6.0), c)
	# Труба
	draw_rect(Rect2(4.0, -8.0, 3.0, 9.0), Color(0.38, 0.40, 0.44))
	_draw_status_lamp(Vector2(-5.0, -5.0))
	if fuel > 0.0:
		# Индикатор топлива
		draw_rect(Rect2(-8.0, -13.0, 16.0, 2.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-8.0, -13.0, 16.0 * clampf(fuel / BURN, 0.0, 1.0), 2.0), Color(1.0, 0.7, 0.2))
