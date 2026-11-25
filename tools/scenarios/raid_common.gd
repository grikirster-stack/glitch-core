class_name RaidCommon
extends RefCounted
## Общая сборка комнаты налёта (#316). Сценарии не копируют кладку панелей.


static func clear_pad(origin: Vector2i) -> void:
	for y in range(origin.y - 2, origin.y + 6):
		for x in range(origin.x - 2, origin.x + 8):
			if World.in_bounds(x, y):
				World.set_tile(x, y, IDs.T.AIR)
				if World.machines.has(Vector2i(x, y)):
					var m = World.machines[Vector2i(x, y)]
					World.machines.erase(Vector2i(x, y))
					if is_instance_valid(m):
						m.queue_free()


## Комната 5×3 панелей, дверь справа. Пол — камень под ногами героя снаружи.
static func build_room(origin: Vector2i, door_open: bool) -> Dictionary:
	clear_pad(origin)
	var door: Vector2i = origin + Vector2i(4, 1)
	for y in range(0, 3):
		for x in range(0, 5):
			var c: Vector2i = origin + Vector2i(x, y)
			if c == door:
				World.set_tile(c.x, c.y, IDs.T.DOOR_OPEN if door_open else IDs.T.DOOR)
			elif y == 0 or y == 2 or x == 0 or x == 4:
				World.set_tile(c.x, c.y, IDs.T.ROOM_PANEL)
			else:
				World.set_tile(c.x, c.y, IDs.T.AIR)
	var inside: Vector2i = origin + Vector2i(2, 1)
	var outside: Vector2i = origin + Vector2i(6, 1)
	World.set_tile(outside.x, outside.y, IDs.T.AIR)
	World.set_tile(outside.x, outside.y + 1, IDs.T.STONE)
	return {"door": door, "inside": inside, "outside": outside, "origin": origin}


static func place_bed(cell: Vector2i, lit: bool) -> SporeBed:
	if World.get_tile_v(cell) != IDs.T.AIR:
		World.set_tile(cell.x, cell.y, IDs.T.AIR)
	MachineBase.place_machine("SporeBed", cell)
	var bed: SporeBed = World.machines.get(cell) as SporeBed
	if bed != null:
		bed.beam_receive(Beams.W if lit else 0)
	return bed


static func plate() -> String:
	if UI.hud == null:
		return ""
	return UI.hud.plate_text()


static func raid_phantoms() -> Array:
	var out: Array = []
	for p in Threat.get_tree().get_nodes_in_group("phantom"):
		if is_instance_valid(p) and bool(p.get("raid")) and bool(p.get("alive")):
			out.append(p)
	return out

static func arm(day: int = 3) -> void:
	Game.day_number = day
	Game.time_of_day = 0.70
	Game.raid_phase = 0
	Game.raid_active = false
	Threat.active = true
	Threat.night_day = day
	Threat.roster.clear()


static func tick(secs: float, step: float = 0.25) -> void:
	var left: float = secs
	while left > 0.0:
		var dt: float = minf(step, left)
		Game.time_of_day = 0.70
		Threat.tick(dt)
		left -= dt



## Часы директора без кадров дерева. Фантом при этом не шагает.
static func drive(secs: float, step: float = 0.25) -> void:
	tick(secs, step)


## Один шаг: директор и физика фантома. Зовёт сценарий, который ждёт кадр.
static func step_frame(host: Node, dt: float) -> void:
	Game.time_of_day = 0.70
	Threat.tick(dt)
	for ph in raid_phantoms():
		if is_instance_valid(ph) and ph.has_method("_physics_process"):
			ph._physics_process(dt)
	var hero = host.get("player") if host != null else null
	if hero != null and is_instance_valid(hero) and hero.has_method("_physics_process"):
		hero._physics_process(dt)
