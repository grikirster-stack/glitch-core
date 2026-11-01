class_name WorldFX
extends Node2D
## Мировые эффекты: частицы, кольца импульса, вентиляция, оверлей питания, свечение.

var chips: Array = []
var rings: Array = []
var slashes: Array = []
var show_power: bool = false
var light_overlay: bool = true


func _ready() -> void:
	z_index = 20


func _process(delta: float) -> void:
	var i: int = chips.size() - 1
	while i >= 0:
		var c: Dictionary = chips[i]
		c["vel"] = Vector2(c["vel"]) + Vector2(0, 520.0) * delta
		c["pos"] = Vector2(c["pos"]) + Vector2(c["vel"]) * delta
		c["life"] = float(c["life"]) - delta
		if float(c["life"]) <= 0.0:
			chips.remove_at(i)
		i -= 1
	i = rings.size() - 1
	while i >= 0:
		var r: Dictionary = rings[i]
		r["t"] = float(r["t"]) + delta
		if float(r["t"]) > 0.7:
			rings.remove_at(i)
		i -= 1
	i = slashes.size() - 1
	while i >= 0:
		var s: Dictionary = slashes[i]
		s["t"] = float(s["t"]) + delta
		if float(s["t"]) > 0.22:
			slashes.remove_at(i)
		i -= 1
	queue_redraw()


func spawn_chip(cell: Vector2i, color: Color) -> void:
	var base: Vector2 = World.cell_to_world(cell)
	for i in 4:
		chips.append({
			"pos": base + Vector2(randf_range(-5.0, 5.0), randf_range(-5.0, 5.0)),
			"vel": Vector2(randf_range(-70.0, 70.0), randf_range(-140.0, -50.0)),
			"life": randf_range(0.25, 0.55),
			"color": color,
			"size": randf_range(1.5, 3.0),
		})


func spawn_ring(pos: Vector2, color: Color) -> void:
	rings.append({"pos": pos, "t": 0.0, "color": color})


func spawn_slash(pos: Vector2) -> void:
	slashes.append({"pos": pos, "t": 0.0})


func _draw() -> void:
	# --- Свечение источников света ------------------------------------------
	if light_overlay and DB.glow_texture:
		for l in World.lights:
			var col: Color = Color(1.0, 0.92, 0.70, float(l["power"]) * 0.55)
			draw_texture_rect(DB.glow_texture, Rect2(Vector2(l["pos"]) - Vector2(l["radius"], l["radius"]) * 0.9,
					Vector2(l["radius"], l["radius"]) * 1.8), false, col)

	# --- Вентиляция -----------------------------------------------------------
	for v in World.vents:
		var p: Vector2 = World.cell_to_world(v)
		draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), Color(0.18, 0.20, 0.24, 0.9))
		draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), Color(0.45, 0.55, 0.65, 0.8), false, 1.0)
		for i in 3:
			draw_line(Vector2(p.x - 4 + i * 4, p.y - 4), Vector2(p.x - 4 + i * 4, p.y + 4), Color(0.35, 0.42, 0.5), 1.0)

	# --- Оверлей питания ------------------------------------------------------
	if show_power:
		for m in World.machines.values():
			if m is Generator:
				var r: float = m.power_radius * World.TILE
				var col: Color = Color(1.0, 0.85, 0.25, 0.16) if m.power_active else Color(0.5, 0.5, 0.55, 0.10)
				draw_circle(m.global_position, r, col)
				draw_arc(m.global_position, r, 0.0, TAU, 48, Color(col.r, col.g, col.b, 0.6), 1.5)

	# --- Релей ----------------------------------------------------------------
	var bp: Vector2 = World.cell_to_world(World.beacon_cell)
	var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.003)
	draw_arc(bp, 10.0 + pulse * 3.0, 0.0, TAU, 28, Color(0.3, 0.95, 1.0, 0.5), 2.0)

	# --- Частицы --------------------------------------------------------------
	for c in chips:
		var life: float = float(c["life"]) / 0.55
		draw_rect(Rect2(Vector2(c["pos"]), Vector2(c["size"], c["size"])),
				Color(c["color"].r, c["color"].g, c["color"].b, clampf(life, 0.0, 1.0)))

	# --- Кольца ---------------------------------------------------------------
	for r in rings:
		var t: float = float(r["t"]) / 0.7
		draw_arc(Vector2(r["pos"]), 10.0 + t * 120.0, 0.0, TAU, 40,
				Color(r["color"].r, r["color"].g, r["color"].b, (1.0 - t) * 0.8), 3.0)

	# --- Взмах ---------------------------------------------------------------
	for s in slashes:
		var t2: float = float(s["t"]) / 0.22
		var col2: Color = Color(1, 1, 1, 1.0 - t2)
		draw_arc(Vector2(s["pos"]), 14.0 + t2 * 8.0, -0.9 + t2 * 1.8, 0.9 + t2 * 1.8, 12, col2, 3.0)
