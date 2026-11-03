class_name Smelter
extends MachineBase
## Плавильня: переплавляет руду в слитки и сталь.

## Горнило без питания — ровный тёмный цвет, без мерцания (#57). Палитра ADR-003.
const FURNACE_COLD: Color = C_SOOT
## Горнило под питанием и цвет, к которому оно пульсирует.
const FURNACE_HOT: Color = C_LAVA
const FURNACE_GLOW: Color = C_LAVA_HI

var stock: Dictionary = {}    ## id -> count
var recipe: Dictionary = {}
var _timer: float = 0.0


func _init() -> void:
	kind = "Smelter"
	z_index = 3


## Нужен ли предмет хоть одному ОТКРЫТОМУ рецепту (#57): вход запертого
## рецепта станок не берёт — иначе он застревает внутри до открытия узла.
func input_accepts(item_id: int) -> bool:
	for r in DB.recipes_for("smelter"):
		if r["in"].has(item_id) and DB.recipe_unlocked(r):
			return true
	return false


## Без питания горнило не мерцает — перерисовка каждый кадр не нужна.
func has_time_animation() -> bool:
	return powered


func receive_item(item_id: int, count: int) -> int:
	if not input_accepts(item_id):
		return count
	stock[item_id] = int(stock.get(item_id, 0)) + count
	return 0


func _process(delta: float) -> void:
	super(delta)
	if not Net.is_authority():   # СЕТЬ (ADR-002): работает хост, клиент рисует по net_state
		return
	if not powered:
		return
	if recipe.is_empty():
		recipe = _find_recipe()
	if recipe.is_empty():
		return
	_timer += work(delta)
	progress = clampf(_timer / float(recipe["time"]), 0.0, 1.0)
	if _timer >= float(recipe["time"]):
		_timer = 0.0
		progress = 0.0
		for k in recipe["in"].keys():
			stock[k] = int(stock.get(k, 0)) - int(recipe["in"][k])
			if int(stock[k]) <= 0:
				stock.erase(k)
		deliver(int(recipe["out"]), int(recipe["amount"]))
		Sfx.play("craft", -14.0, 1.1)
		recipe = {}


func _find_recipe() -> Dictionary:
	for r in DB.recipes_for("smelter"):
		if not DB.recipe_unlocked(r):    ## запертый деревом технологий (#28)
			continue
		var ok: bool = true
		for k in r["in"].keys():
			if int(stock.get(k, 0)) < int(r["in"][k]):
				ok = false
				break
		if ok:
			return r
	return {}


func _draw() -> void:
	_draw_body(BODY, powered)
	# Вытяжка: две щели под верхней кромкой.
	draw_rect(Rect2(-5.0, -5.0, 4.0, 1.0), C_FRAME)
	draw_rect(Rect2(1.0, -5.0, 4.0, 1.0), C_FRAME)
	# Горнило в раме; в работе пульсирует лавовым, середина — светлее.
	var fc: Color = furnace_color(Time.get_ticks_msec())
	draw_rect(Rect2(-5.0, -3.0, 10.0, 8.0), C_FRAME)
	draw_rect(Rect2(-4.0, -2.0, 8.0, 6.0), fc)
	if powered:
		draw_rect(Rect2(-3.0, 1.0, 6.0, 2.0), fc.lerp(FURNACE_GLOW, 0.6))
	if progress > 0.0:
		_draw_progress(-12.0)


## Цвет горнила в момент t_ms: под питанием пульсирует к жёлтому,
## без питания — ровный FURNACE_COLD (#57).
func furnace_color(t_ms: int) -> Color:
	if not powered:
		return FURNACE_COLD
	var glow: float = 0.5 + 0.5 * sin(t_ms * 0.006)
	return FURNACE_HOT.lerp(FURNACE_GLOW, glow * 0.4)


## Плавильню сняли или снесли — сырьё из неё на землю, ничего не пропадает.
func _on_destroyed() -> void:
	for id in stock.keys():
		spawn_item(int(id), int(stock[id]), global_position + Vector2(0.0, -4.0))
	stock.clear()


# ------------------------------------------------------------- СОХРАНЕНИЕ (#37)
## Загрузка входа, рецепт в работе (ссылкой на DB) и таймер плавки.
func save_state() -> Dictionary:
	var d: Dictionary = super()
	d["stock"] = stock.duplicate()
	d["recipe"] = recipe_ref("smelter", recipe)
	d["timer"] = _timer
	return d


func load_state(d: Dictionary) -> void:
	super(d)
	stock = load_counts(d.get("stock", {}))
	recipe = recipe_from("smelter", d.get("recipe"))
	_timer = float(d.get("timer", _timer))
