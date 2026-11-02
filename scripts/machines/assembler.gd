class_name Assembler
extends MachineBase
## Сборщик: соединяет компоненты в сложные изделия.

var stock: Dictionary = {}
var recipe: Dictionary = {}
var _timer: float = 0.0


func _init() -> void:
	kind = "Assembler"
	z_index = 3


## Нужен ли предмет хоть одному ОТКРЫТОМУ рецепту (#57) — как у плавильни.
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
	var base: Color = Color(0.24, 0.34, 0.44) if powered else Color(0.17, 0.22, 0.28)
	draw_rect(Rect2(-8.0, -8.0, 16.0, 16.0), base)
	draw_rect(Rect2(-8.0, -8.0, 16.0, 2.0), base.lightened(0.25))
	# Шестерня
	var a: float = Time.get_ticks_msec() * 0.003 * (1.0 if powered else 0.0)
	for i in 4:
		var ang: float = a + i * TAU / 4.0
		draw_line(Vector2.ZERO, Vector2(cos(ang), sin(ang)) * 5.5, Color(0.75, 0.85, 0.95), 2.0)
	draw_circle(Vector2.ZERO, 2.6, Color(0.85, 0.92, 1.0))
	if progress > 0.0:
		draw_rect(Rect2(-6.0, -13.0, 12.0, 2.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-6.0, -13.0, 12.0 * progress, 2.0), Color(0.4, 0.9, 1.0))


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
