class_name Smelter
extends MachineBase
## Плавильня: переплавляет руду в слитки и сталь.

var stock: Dictionary = {}    ## id -> count
var recipe: Dictionary = {}
var _timer: float = 0.0


func _init() -> void:
	kind = "Smelter"
	z_index = 3


func input_accepts(item_id: int) -> bool:
	for r in DB.recipes_for("smelter"):
		if r["in"].has(item_id):
			return true
	return false


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
		Sfx.play("craft", -14.0, 1.1)
		recipe = {}


func _find_recipe() -> Dictionary:
	for r in DB.recipes_for("smelter"):
		var ok: bool = true
		for k in r["in"].keys():
			if int(stock.get(k, 0)) < int(r["in"][k]):
				ok = false
				break
		if ok:
			return r
	return {}


func _draw() -> void:
	var base: Color = Color(0.46, 0.28, 0.20) if powered else Color(0.30, 0.20, 0.16)
	draw_rect(Rect2(-8.0, -8.0, 16.0, 16.0), base)
	draw_rect(Rect2(-8.0, -8.0, 16.0, 2.0), base.lightened(0.2))
	# Горнило
	var glow: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
	var hot: Color = Color(0.95, 0.45, 0.12) if powered else Color(0.30, 0.20, 0.16)
	hot = hot.lerp(Color(1.0, 0.85, 0.4), glow * 0.4)
	draw_rect(Rect2(-5.0, -2.0, 10.0, 7.0), hot)
	if progress > 0.0:
		draw_rect(Rect2(-6.0, -12.0, 12.0, 2.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-6.0, -12.0, 12.0 * progress, 2.0), Color(0.4, 0.9, 1.0))
