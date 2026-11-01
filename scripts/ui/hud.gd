class_name HUD
extends Control
## Игровой интерфейс: здоровье, задачи, время суток, хотбар, миникарта, уведомления.

var player = null   ## Ссылка на игрока без статического типа (иначе цикл зависимостей).
var notes: Array = []          ## [{text, color, ttl}]
var damage_flash: float = 0.0
var panel_alpha: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	damage_flash = maxf(0.0, damage_flash - delta * 2.0)
	var i: int = notes.size() - 1
	while i >= 0:
		notes[i]["ttl"] = float(notes[i]["ttl"]) - delta
		if float(notes[i]["ttl"]) <= 0.0:
			notes.remove_at(i)
		i -= 1
	queue_redraw()


func notify(text: String, color: Color) -> void:
	notes.append({"text": text, "color": color, "ttl": 5.0})
	while notes.size() > 6:
		notes.remove_at(0)


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var font: Font = ThemeDB.fallback_font

	if damage_flash > 0.0:
		draw_rect(Rect2(0, 0, w, h), Color(0.8, 0.1, 0.1, damage_flash * 0.25))

	# ---- Прицел -------------------------------------------------------------
	var mp: Vector2 = get_viewport().get_mouse_position()
	var cross: Color = Color(1, 1, 1, 0.75)
	draw_line(mp - Vector2(7, 0), mp - Vector2(3, 0), cross, 1.5)
	draw_line(mp + Vector2(3, 0), mp + Vector2(7, 0), cross, 1.5)
	draw_line(mp - Vector2(0, 7), mp - Vector2(0, 3), cross, 1.5)
	draw_line(mp + Vector2(0, 3), mp + Vector2(0, 7), cross, 1.5)

	# ---- Здоровье ------------------------------------------------------------
	if player:
		var hp_rect: Rect2 = Rect2(14, 12, 210, 20)
		draw_rect(hp_rect, Color(0, 0, 0, 0.55))
		var frac: float = clampf(player.hp / 100.0, 0.0, 1.0)
		var hp_col: Color = Color(0.85, 0.22, 0.28) if frac > 0.35 else Color(0.95, 0.45, 0.15)
		draw_rect(Rect2(hp_rect.position + Vector2(2, 2), Vector2((hp_rect.size.x - 4) * frac, hp_rect.size.y - 4)), hp_col)
		draw_rect(hp_rect, Color(1, 1, 1, 0.35), false, 1.0)
		draw_string(font, hp_rect.position + Vector2(8, 15), "%d" % int(player.hp),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.9))

		# Индикатор заряда импульса
		var emp_rect: Rect2 = Rect2(14, 38, 150, 8)
		draw_rect(emp_rect, Color(0, 0, 0, 0.5))
		var ef: float = 1.0 - player.emp_cd / player.emp_max
		draw_rect(Rect2(emp_rect.position + Vector2(1, 1), Vector2((emp_rect.size.x - 2) * ef, emp_rect.size.y - 2)),
				Color(0.35, 0.8, 1.0))
		draw_string(font, emp_rect.position + Vector2(156, 8), "ИМПУЛЬС [Q]",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.85, 1.0, 0.85))

		# Инвентарь подсказка
		draw_string(font, Vector2(14, 66), "Задачи: %d/%d   Данные: %d" % [Game.tasks_done, Game.tasks_total, Game.research],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.92, 1.0, 0.9))

	# ---- Время суток ---------------------------------------------------------
	var clock_pos: Vector2 = Vector2(w - 120, 46)
	draw_arc(clock_pos, 22.0, PI, TAU, 32, Color(0, 0, 0, 0.45), 3.0)
	var ang: float = PI + Game.time_of_day * PI
	var sun: Vector2 = clock_pos + Vector2(cos(ang), sin(ang)) * 22.0
	var dl: float = Game.daylight()
	var sky: Color = Color(0.25, 0.30, 0.45).lerp(Color(1.0, 0.85, 0.35), dl)
	draw_circle(sun, 6.0, sky)
	draw_string(font, Vector2(w - 176, 26), "Смена %d — %s" % [Game.day_number, Game.phase_name()],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.9, 0.92, 1.0))

	# ---- Миникарта -----------------------------------------------------------
	_draw_minimap(Rect2(w - 200, 60, 186, 52), font)

	# ---- Уведомления --------------------------------------------------------
	var y: float = h - 150
	for i in range(notes.size() - 1, -1, -1):
		var n: Dictionary = notes[i]
		var a: float = clampf(float(n["ttl"]) / 1.5, 0.0, 1.0)
		# Длинные сообщения не режем — сдвигаем их влево, чтобы текст целиком влезал.
		var txt: String = String(n["text"])
		var tw: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var nx: float = minf(w - 430.0, w - tw - 24.0)
		draw_string(font, Vector2(nx, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
				Color(n["color"].r, n["color"].g, n["color"].b, a))
		y -= 20

	# ---- Хотбар --------------------------------------------------------------
	if player:
		_draw_hotbar(font)

	# ---- Подсказки -----------------------------------------------------------
	var hints: String = ""
	if player:
		if player.hiding:
			hints = "Вы в вентиляции. [V] — вылезть"
		elif not World.terminals.is_empty():
			for t in World.terminals:
				if World.cell_to_world(t).distance_to(player.global_position) < 42.0:
					hints = "[E] — выполнить задание (удерживать)"
					break
		if hints == "" and World.cell_to_world(World.beacon_cell).distance_to(player.global_position) < 56.0:
			hints = "[E] — активировать релей-ядро (удерживать)"
		if hints == "":
			for m in World.machines.values():
				if m is CoalGen and m.global_position.distance_to(player.global_position) < 40.0:
					hints = "[E] — загрузить уголь в ТЭЦ"
					break
		if hints == "":
			for m in World.machines.values():
				if m is Chest and m.global_position.distance_to(player.global_position) < 40.0:
					hints = "[E] — открыть сундук"
					break
	if hints != "":
		draw_string(font, Vector2(size.x * 0.5 - 190, size.y - 116), hints,
				HORIZONTAL_ALIGNMENT_CENTER, 380, 15, Color(1.0, 0.95, 0.75, 0.95))

	# ---- Подсказка управления (затухает) ------------------------------------
	if Game.game_time < 22.0:
		var ta: float = clampf((22.0 - Game.game_time) / 6.0, 0.0, 1.0)
		var lines: Array = [
			"WASD — движение   SPACE — прыжок   SHIFT — бег",
			"ЛКМ — копать / бить   ПКМ — строить   E — взаимодействовать",
			"Q — импульс   V — вентиляция   I / TAB — инвентарь и крафт   1-0 — хотбар",
		]
		for i in lines.size():
			draw_string(font, Vector2(size.x * 0.5 - 260, size.y * 0.30 + i * 20), String(lines[i]),
					HORIZONTAL_ALIGNMENT_CENTER, 520, 14, Color(0.85, 0.92, 1.0, ta))


func _draw_hotbar(font: Font) -> void:
	var slot: float = 46.0
	var count: int = 10
	var total: float = slot * count
	var x0: float = size.x * 0.5 - total * 0.5
	var y0: float = size.y - 74
	for i in count:
		var r: Rect2 = Rect2(x0 + i * slot, y0, slot - 4, slot - 4)
		var sel: bool = (player.inv.selected == i)
		draw_rect(r, Color(0.08, 0.09, 0.12, 0.82))
		draw_rect(r, Color(1, 1, 1, 0.85) if sel else Color(1, 1, 1, 0.22), false, 2.0 if sel else 1.0)
		var st: ItemStack = player.inv.get_slot(i)
		if not st.is_empty():
			var tex: ImageTexture = DB.item_texture(st.id)
			if tex:
				draw_texture_rect(tex, Rect2(r.position + Vector2(7, 7), Vector2(28, 28)), false)
			if st.count > 1:
				draw_string(font, r.position + Vector2(2, r.size.y - 4), str(st.count),
						HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 6, 12, Color(1, 1, 1, 0.95))
		draw_string(font, r.position + Vector2(3, 12), str((i + 1) % 10),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.45))


func _draw_minimap(r: Rect2, font: Font) -> void:
	if World.surface.is_empty():
		return
	draw_rect(r, Color(0.05, 0.06, 0.09, 0.72))
	draw_rect(r, Color(1, 1, 1, 0.25), false, 1.0)
	var sx: float = r.size.x / float(World.W)
	var sy: float = r.size.y / float(World.H)
	for x in range(0, World.W, 2):
		var top: int = World.surface[x]
		var c: Color = Color(0.20, 0.45, 0.20)
		var tid: int = World.get_tile(x, top)
		if tid == IDs.T.SAND:
			c = Color(0.70, 0.62, 0.35)
		elif tid == IDs.T.STONE:
			c = Color(0.35, 0.35, 0.40)
		draw_line(Vector2(r.position.x + x * sx, r.position.y + top * sy),
				Vector2(r.position.x + x * sx, r.end.y), c, 1.0)
	# Релей
	var bp: Vector2 = r.position + Vector2(World.beacon_cell.x * sx, World.beacon_cell.y * sy)
	draw_rect(Rect2(bp - Vector2(3, 3), Vector2(6, 6)), Color(0.3, 0.95, 1.0))
	# Игрок
	if player:
		var pc: Vector2 = World.world_to_cell(player.global_position)
		var pp: Vector2 = r.position + Vector2(pc.x * sx, pc.y * sy)
		draw_circle(pp, 3.0, Color(0.95, 0.25, 0.28))
	draw_string(font, r.position + Vector2(4, 12), "КАРТА", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.6))
