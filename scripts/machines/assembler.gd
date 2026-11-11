class_name Assembler
extends MachineBase
## Верстак: соединяет компоненты в сложные изделия.

var stock: Dictionary = {}
var recipe: Dictionary = {}
var _timer: float = 0.0


func _init() -> void:
	kind = "Assembler"
	z_index = 3


## Нужен ли предмет хоть одному открытому рецепту (#169) — как у плавильни.
func input_accepts(item_id: int) -> bool:
	for r in DB.recipes_for("assembler"):
		if r["in"].has(item_id) and DB.recipe_unlocked(r):
			return true
	return false


## Без питания шестерня стоит — перерисовка каждый кадр не нужна.
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
		Sfx.play("craft", -14.0, 1.3)
		Game.stats_crafted += 1
		recipe = {}


func _find_recipe() -> Dictionary:
	for r in DB.recipes_for("assembler"):
		if not DB.recipe_unlocked(r):    ## нет чертежа на выход (#169)
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
	# Окно со «шестернёй» из квадратов: под питанием зубья перескакивают
	# «+» ↔ «×» (поворот на 45° в два кадра), без питания стоят.
	draw_rect(Rect2(-5.0, -4.0, 10.0, 9.0), C_FRAME)
	draw_rect(Rect2(-4.0, -3.0, 8.0, 7.0), C_SCREEN)
	var g: Color = C_METAL_HI if powered else C_METAL_D
	var turn: bool = powered and (Time.get_ticks_msec() / 160) % 2 == 1
	if turn:
		for k in 4:
			var sx: float = -4.0 if k % 2 == 0 else 2.0
			var sy: float = -3.0 if k < 2 else 2.0
			draw_rect(Rect2(sx, sy, 2.0, 2.0), g)
	else:
		draw_rect(Rect2(-1.0, -3.0, 2.0, 7.0), g)
		draw_rect(Rect2(-4.0, -1.0, 8.0, 2.0), g)
	draw_rect(Rect2(-2.0, -2.0, 4.0, 4.0), g)
	draw_rect(Rect2(-1.0, -1.0, 2.0, 2.0), C_FRAME)
	_draw_lamp(Vector2(6.0, -6.0), C_SCREEN_HI if powered else C_LAMP_OFF)
	if progress > 0.0:
		_draw_progress(-13.0)


## Верстак сняли или снесли — сырьё из него на землю, ничего не пропадает.
func _on_destroyed() -> void:
	for id in stock.keys():
		spawn_item(int(id), int(stock[id]), global_position + Vector2(0.0, -4.0))
	stock.clear()


# ------------------------------------------------------------- СОХРАНЕНИЕ (#37)
## Как у плавильни: вход, рецепт в работе и таймер.
func save_state() -> Dictionary:
	var d: Dictionary = super()
	d["stock"] = stock.duplicate()
	d["recipe"] = recipe_ref("assembler", recipe)
	d["timer"] = _timer
	return d


func load_state(d: Dictionary) -> void:
	super(d)
	stock = load_counts(d.get("stock", {}))
	recipe = recipe_from("assembler", d.get("recipe"))
	_timer = float(d.get("timer", _timer))
