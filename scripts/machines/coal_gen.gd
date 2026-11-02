class_name CoalGen
extends Generator
## Угольная ТЭЦ: жжёт уголь и даёт энергию в радиусе.
##
## Уголь — руками (E с углём в хотбаре) или с конвейера/манипулятора
## (receive_item). Выключенная рубильником ТЭЦ уголь не жжёт.

const BURN: float = Balance.COAL_BURN   ## секунд горения одной единицы угля
const FUEL_VALUE: int = 1
const FUEL_MAX_UNITS: int = 12          ## сколько угля помещается в топку
## Дым ТЭЦ — сиреневые споры (ADR-003 § 4.1; `fl2` концепта, в DB.PAL его нет).
const SPORE_SMOKE: Color = Color("#DCCDEA")

var fuel: float = 0.0


func _init() -> void:
	kind = "CoalGen"
	power_radius = 8.0
	power_output = float(Balance.POWER_OUT["CoalGen"])


func _process(delta: float) -> void:
	super(delta)
	if not Net.is_authority():   # СЕТЬ (ADR-002): топливо и активность — от хоста
		queue_redraw()
		return
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
	var t: float = Time.get_ticks_msec() * 0.001
	_draw_body(BODY, true)
	# Мох: ТЭЦ стоит давно — лишайник затянул левый верхний угол и бок.
	draw_rect(Rect2(-8.0, -9.0, 6.0, 2.0), C_LICHEN)
	draw_rect(Rect2(-8.0, -7.0, 2.0, 5.0), C_LICHEN)
	draw_rect(Rect2(-7.0, -10.0, 1.0, 1.0), C_LICHEN_HI)
	draw_rect(Rect2(-4.0, -10.0, 1.0, 1.0), C_LICHEN_HI)
	draw_rect(Rect2(-8.0, -3.0, 1.0, 2.0), C_LICHEN_HI)
	# Труба над корпусом: рама-бандаж и блик.
	draw_rect(Rect2(2.0, -12.0, 4.0, 8.0), C_METAL_D)
	draw_rect(Rect2(2.0, -12.0, 4.0, 1.0), C_METAL_HI)
	draw_rect(Rect2(2.0, -9.0, 4.0, 1.0), C_FRAME)
	# Топка в раме: в работе светится лавовым и мерцает, колосники поверх.
	draw_rect(Rect2(-5.0, -2.0, 10.0, 7.0), C_FRAME)
	var c: Color = C_SOOT
	if hot:
		c = C_LAVA.lerp(C_LAVA_HI, (0.5 + 0.5 * sin(t * 10.0)) * 0.5)
	draw_rect(Rect2(-4.0, -1.0, 8.0, 5.0), c)
	if hot:
		draw_rect(Rect2(-3.0, 1.0, 6.0, 2.0), C_LAVA_HI)
	draw_rect(Rect2(-2.0, -1.0, 1.0, 5.0), C_FRAME)
	draw_rect(Rect2(1.0, -1.0, 1.0, 5.0), C_FRAME)
	# Шкала топлива справа от топки: доля текущей единицы угля, снизу вверх.
	if fuel > 0.0:
		var f: float = roundf(5.0 * clampf(fuel / BURN, 0.0, 1.0))
		draw_rect(Rect2(5.0, -1.0, 2.0, 5.0), C_SOOT)
		draw_rect(Rect2(5.0, 4.0 - f, 2.0, f), C_LAVA_HI)
	_draw_status_lamp(Vector2(-4.0, -5.0))
	# Дым — сиреневые споры квадратами, поднимаются и тают.
	if hot:
		for k in 3:
			var p: float = fmod(t * 0.7 + float(k) / 3.0, 1.0)
			var sz: float = 2.0 + float(k)
			draw_rect(Rect2(roundf(3.0 + p * 4.0 - sz * 0.5 + 1.0), roundf(-14.0 - p * 12.0), sz, sz),
					Color(SPORE_SMOKE, 0.6 * (1.0 - p)))


# ------------------------------------------------------------- СОХРАНЕНИЕ (#37)
func save_state() -> Dictionary:
	var d: Dictionary = super()
	d["fuel"] = fuel
	return d


func load_state(d: Dictionary) -> void:
	super(d)
	fuel = float(d.get("fuel", fuel))


# ------------------------------------------------------------- СЕТЬ (ADR-002, MP-E #90)
## + топливо u8 — доля полной топки (FUEL_MAX_UNITS единиц).
func net_state() -> PackedByteArray:
	var b: PackedByteArray = super()
	b.append(net_u8(fuel / (BURN * float(FUEL_MAX_UNITS))))
	return b


func apply_net_state(b: PackedByteArray) -> int:
	var o: int = super(b)
	if o < 0 or b.size() < o + 1:
		return -1
	fuel = float(b[o]) / 255.0 * BURN * float(FUEL_MAX_UNITS)
	return o + 1
