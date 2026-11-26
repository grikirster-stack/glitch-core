extends ScenarioBase
## Споровая грядка (ADR-006 § 3.2, #313).
##
## Белый от коллектора даёт волокно. Обрыв — крыша в столбце коллектора, не флаг:
## доля стоит и не обнуляется. Полный лоток останавливает выпуск. Save под светом,
## load без луча: даже старый ключ lit не растит 1.2 с, затем beam_receive(7)
## продолжает с той же доли. Красный луч грядку не растит. Сундук забирает лоток.
## Ручной рецепт волокно → панели даёт Balance.SPORE_BED_PANEL_OUT.


func run() -> void:
	player.invuln = 1.0e9
	stand_in_corridor(3)
	await wait(0.2)
	var origin: Vector2i = Vector2i(90, 42)
	_clear(Vector2i(origin.x - 2, 0), Vector2i(origin.x + 16, origin.y + 6))
	Game.time_of_day = 0.30
	await await_frame()
	await _grows(origin)
	await _holds_in_dark(origin + Vector2i(0, 4))
	await _stops_when_full(origin + Vector2i(6, 0))
	await _save_mid_grow(origin + Vector2i(10, 0))
	await _red_does_not_grow(origin + Vector2i(0, 6))
	await _chest_takes(origin + Vector2i(6, 4))
	await _hand_panels()
	finish()


## Коллектор светит вправо в грядку. Одно волокно за SPORE_BED_SECONDS.
func _grows(origin: Vector2i) -> void:
	ok("коллектор поставлен", MachineBase.place_machine("Collector", origin))
	var bed_cell: Vector2i = origin + Vector2i(3, 0)
	ok("грядка поставлена", MachineBase.place_machine("SporeBed", bed_cell))
	var col: Collector = World.machines.get(origin) as Collector
	var bed: SporeBed = World.machines.get(bed_cell) as SporeBed
	if col == null or bed == null:
		return
	col.dir = 0
	col._check_sky()
	_flush()
	# Луч гаснет на клетке приёмника: цвет пишется в клетку перед ней, как у маяка.
	var into: int = World.beams.color_at(bed_cell + Vector2i(-1, 0))
	ok("белый дошёл до грядки", bed.lit and into == Beams.W,
			"lit %s, цвет перед входом %d" % [bed.lit, into])
	ok("ждёт свет — подпись «Растёт»", bed.status_text() == SporeBed.ST_GROW, bed.status_text())
	var need: float = Balance.SPORE_BED_SECONDS
	var got: bool = await wait_until(func() -> bool:
		return bed.tray >= 1 and bed.made >= 1, need + 1.5)
	ok("волокно вышло за %.0f с света" % need, got,
			"лоток %d, выпущено %d, рост %.2f" % [bed.tray, bed.made, bed.grow])
	ok("после выпуска лоток не пуст, доля следующего мала", bed.tray == 1 and bed.grow < 1.0,
			"стадия %d, лоток %d, рост %.3f" % [bed.stage(), bed.tray, bed.grow])
	_gone(col)
	_gone(bed)
	_flush()


## Честный обрыв: белый от коллектора растит, крыша гасит луч, небо снова
## открыто — доля продолжается. lit сценарий сам не пишет.
func _holds_in_dark(origin: Vector2i) -> void:
	var col_cell: Vector2i = origin
	var bed_cell: Vector2i = origin + Vector2i(3, 0)
	ok("коллектор для обрыва", MachineBase.place_machine("Collector", col_cell))
	ok("грядка на белом для обрыва", MachineBase.place_machine("SporeBed", bed_cell))
	var col: Collector = World.machines.get(col_cell) as Collector
	var bed: SporeBed = World.machines.get(bed_cell) as SporeBed
	if col == null or bed == null:
		return
	col.dir = 0
	col._check_sky()
	_flush()
	var into: int = World.beams.color_at(bed_cell + Vector2i(-1, 0))
	ok("белый луч дошёл до грядки до обрыва", bed.lit and into == Beams.W,
			"lit %s, цвет перед входом %d" % [bed.lit, into])
	# Долю задаём, чтобы не ждать полный цикл. Свет — только от луча.
	bed.grow = Balance.SPORE_BED_SECONDS * 0.4
	bed._sync_progress()
	await wait(0.3)
	var mid: float = bed.grow
	ok("под белым лучом доля растёт", mid > Balance.SPORE_BED_SECONDS * 0.4, "рост %.3f" % mid)
	# Крыша в столбец коллектора: set_tile зовёт note_column, луч гаснет.
	World.set_tile(col_cell.x, 0, IDs.T.STONE)
	_flush()
	ok("крыша погасила белый", not bed.lit and not col.emitting(),
			"lit %s, коллектор светит %s" % [bed.lit, col.emitting()])
	var frozen: float = bed.grow
	await wait(1.2)
	ok("погашенный луч прогресс заморозил", absf(bed.grow - frozen) < 0.001,
			"было %.3f, стало %.3f" % [frozen, bed.grow])
	ok("обрыв долю не обнулил", bed.grow > 1.0, "рост %.3f" % bed.grow)
	ok("подпись «Нет белого луча»", bed.status_text() == SporeBed.ST_DARK, bed.status_text())
	World.set_tile(col_cell.x, 0, IDs.T.AIR)
	col._check_sky()
	_flush()
	ok("небо снова открыто, белый вернулся", bed.lit and col.emitting(),
			"lit %s, светит %s" % [bed.lit, col.emitting()])
	var left: float = Balance.SPORE_BED_SECONDS - bed.grow
	var got: bool = await wait_until(func() -> bool: return bed.made >= 1, left + 1.0)
	ok("после возврата луча волокно дозрело с сохранённой доли", got,
			"лоток %d, рост %.3f" % [bed.tray, bed.grow])
	_gone(col)
	_gone(bed)
	_flush()


## Четвёртое волокно заполняет лоток. Дальше секунды не копятся.
func _stops_when_full(origin: Vector2i) -> void:
	ok("грядка под замер лотка", MachineBase.place_machine("SporeBed", origin))
	var bed: SporeBed = World.machines.get(origin) as SporeBed
	if bed == null:
		return
	bed.beam_receive(Beams.W)
	var cap: int = Balance.SPORE_BED_TRAY
	# Три волокна уже в лотке, четвёртое почти дозрело: стоп проверяем за секунду,
	# не за четыре полных цикла. Логика та же — место кончилось, секунды не копятся.
	bed.tray = cap - 1
	bed.made = cap - 1
	bed.grow = Balance.SPORE_BED_SECONDS - 0.4
	var got: bool = await wait_until(func() -> bool: return bed.tray >= cap, 2.0)
	ok("лоток полон (%d)" % cap, got, "лоток %d, выпущено %d" % [bed.tray, bed.made])
	ok("подпись «Выход полон»", bed.status_text() == SporeBed.ST_FULL, bed.status_text())
	var made0: int = bed.made
	await wait(1.2)
	ok("полный лоток выпуск остановил", bed.made == made0 and bed.grow < 0.05,
			"выпущено %d, рост %.3f" % [bed.made, bed.grow])
	# Забрали одно — продолжаем со следующего волокна, не с обнулённого цикла.
	var took: int = bed.take_fiber(1)
	ok("из лотка забрали 1", took == 1 and bed.tray == cap - 1, "забрали %d, лоток %d" % [took, bed.tray])
	ok("после забора подпись снова «Растёт»", bed.status_text() == SporeBed.ST_GROW, bed.status_text())
	bed.grow = Balance.SPORE_BED_SECONDS - 0.4
	var got2: bool = await wait_until(func() -> bool: return bed.made > made0, 2.0)
	ok("после места в лотке выпуск продолжился", got2, "выпущено %d" % bed.made)
	_gone(bed)
	_flush()


## Save под светом, load без луча: 1.2 с роста нет. Потом белый beam_receive(7)
## — доля продолжается. Даже старый ключ lit в файле грядку не зажигает.
func _save_mid_grow(origin: Vector2i) -> void:
	var col_cell: Vector2i = origin
	var bed_cell: Vector2i = origin + Vector2i(3, 0)
	ok("коллектор перед сохранением", MachineBase.place_machine("Collector", col_cell))
	ok("грядка в сохранение", MachineBase.place_machine("SporeBed", bed_cell))
	var col: Collector = World.machines.get(col_cell) as Collector
	var bed: SporeBed = World.machines.get(bed_cell) as SporeBed
	if col == null or bed == null:
		return
	col.dir = 0
	col._check_sky()
	_flush()
	ok("перед сохранением грядка под белым", bed.lit,
			"lit %s, цвет перед входом %d" % [bed.lit, World.beams.color_at(bed_cell + Vector2i(-1, 0))])
	bed.dir = 1
	bed.grow = Balance.SPORE_BED_SECONDS * 0.55
	bed.tray = 2
	bed.made = 2
	bed._sync_progress()
	var slot0: String = Save.slot
	Save.slot = "spore"
	Save.remove("spore")
	var packed_d: Dictionary = Save.gather()
	# Старый сейв мог нести lit=true. Загрузка обязана его проигнорировать.
	for rec in packed_d.get("machines", []):
		if str(rec.get("kind", "")) == "SporeBed":
			rec["lit"] = true
	# Коллектор в файл не кладём: после apply луча быть не должно.
	var kept: Array = []
	for rec in packed_d.get("machines", []):
		if str(rec.get("kind", "")) != "Collector":
			kept.append(rec)
	packed_d["machines"] = kept
	var packed: PackedByteArray = var_to_bytes(packed_d)
	# Источник жив до apply — иначе load не доказывает «без луча».
	_gone(col)
	_flush()
	Save.apply(Save.decode(packed))
	var back: SporeBed = World.machines.get(bed_cell) as SporeBed
	ok("грядка загрузилась", back != null)
	if back == null:
		Save.remove("spore")
		Save.slot = slot0
		return
	ok("после загрузки без луча грядка тёмная", not back.lit, "lit %s" % back.lit)
	ok("доля, лоток и сторона те же",
			back.dir == 1 and back.tray == 2 and absf(back.grow - Balance.SPORE_BED_SECONDS * 0.55) < 0.05,
			"dir %d, лоток %d, рост %.3f" % [back.dir, back.tray, back.grow])
	var frozen: float = back.grow
	var made0: int = back.made
	await wait(1.2)
	ok("1.2 с без луча роста нет", absf(back.grow - frozen) < 0.001 and back.made == made0,
			"рост %.3f → %.3f, выпущено %d" % [frozen, back.grow, back.made])
	# Реальный белый, не запись в lit. Коллектор в этот кадр уже снесён.
	back.beam_receive(Beams.W)
	ok("beam_receive(7) зажёг грядку", back.lit, "lit %s" % back.lit)
	var left: float = Balance.SPORE_BED_SECONDS - back.grow
	var got: bool = await wait_until(func() -> bool: return back.made > made0, left + 1.0)
	ok("после белого луча выпуск продолжился с доли", got,
			"выпущено %d → %d, лоток %d" % [made0, back.made, back.tray])
	Save.remove("spore")
	Save.slot = slot0
	_gone(back)
	_flush()


## Красный в грядку — не белый. Доля не растёт, подпись про белый.
func _red_does_not_grow(origin: Vector2i) -> void:
	ok("горелка для красного", MachineBase.place_machine("Burner", origin))
	var bed_cell: Vector2i = origin + Vector2i(2, 0)
	ok("грядка на красном", MachineBase.place_machine("SporeBed", bed_cell))
	var burner: Burner = World.machines.get(origin) as Burner
	var bed: SporeBed = World.machines.get(bed_cell) as SporeBed
	if burner == null or bed == null:
		return
	burner.dir = 0
	burner.add_fuel(IDs.I.COAL, 2)
	_flush()
	await wait(0.6)
	_flush()
	ok("красный дошёл до входа грядки", World.beams.color_at(bed_cell + Vector2i(-1, 0)) == Beams.R,
			"цвет перед входом %d" % World.beams.color_at(bed_cell + Vector2i(-1, 0)))
	ok("красный грядку не зажёг", not bed.lit, "lit %s, маска %d" % [bed.lit, bed._mask])
	var grow0: float = bed.grow
	await wait(1.0)
	ok("красный долю не растит", absf(bed.grow - grow0) < 0.001 and bed.made == 0,
			"рост %.3f, выпущено %d" % [bed.grow, bed.made])
	_gone(burner)
	_gone(bed)
	_flush()


## Сундук рядом забирает готовое. Лоток пустеет, счётчик pushed растёт.
func _chest_takes(origin: Vector2i) -> void:
	ok("сундук у грядки", MachineBase.place_machine("Chest", origin))
	ok("грядка у сундука", MachineBase.place_machine("SporeBed", origin + Vector2i(1, 0)))
	var chest: Chest = World.machines.get(origin) as Chest
	var bed: SporeBed = World.machines.get(origin + Vector2i(1, 0)) as SporeBed
	if chest == null or bed == null:
		return
	bed.tray = 3
	bed.beam_receive(0)
	bed.dir = 0
	await wait(0.15)
	ok("сундук сбоку от стрелки оставил лоток полным", bed.pushed == 0 and bed.tray == 3)
	bed.dir = 2
	await await_frame()
	await wait(0.1)
	ok("сундук забрал волокно", bed.pushed >= 1 and bed.tray < 3, "лоток %d, отдано %d" % [bed.tray, bed.pushed])
	var in_chest: int = 0
	for s in chest.slots:
		if s.id == IDs.I.SPORE_FIBER:
			in_chest += s.count
	ok("в сундуке лежит волокно", in_chest == bed.pushed, "в сундуке %d, отдано %d" % [in_chest, bed.pushed])
	_gone(chest)
	_gone(bed)


## Ручной рецепт: 2 волокна → 4 панели. Тот же предмет, что возьмёт пресс.
func _hand_panels() -> void:
	var rec: Dictionary = {}
	for r in DB.recipes_for("hand"):
		if int(r["out"]) == IDs.I.PANEL:
			rec = r
			break
	ok("рецепт панелей есть в DB", not rec.is_empty())
	if rec.is_empty():
		return
	ok("рецепт берёт волокно", int(rec["in"].get(IDs.I.SPORE_FIBER, 0)) == Balance.SPORE_BED_PANEL_IN,
			"вход %s" % str(rec["in"]))
	ok("рецепт даёт панели пресса", int(rec["amount"]) == Balance.SPORE_BED_PANEL_OUT,
			"выход %d" % int(rec["amount"]))
	player.inv.add(IDs.I.SPORE_FIBER, Balance.SPORE_BED_PANEL_IN)
	var fiber0: int = player.inv.count_of(IDs.I.SPORE_FIBER)
	var panels0: int = player.inv.count_of(IDs.I.PANEL)
	var panel: InventoryPanel = UI.panel
	panel._craft(rec)
	await wait(0.2)
	ok("волокно списано", player.inv.count_of(IDs.I.SPORE_FIBER) == fiber0 - Balance.SPORE_BED_PANEL_IN,
			"было %d, стало %d" % [fiber0, player.inv.count_of(IDs.I.SPORE_FIBER)])
	ok("панелей прибавилось ровно %d" % Balance.SPORE_BED_PANEL_OUT,
			player.inv.count_of(IDs.I.PANEL) == panels0 + Balance.SPORE_BED_PANEL_OUT,
			"было %d, стало %d" % [panels0, player.inv.count_of(IDs.I.PANEL)])


func _clear(a: Vector2i, b: Vector2i) -> void:
	for x in range(a.x, b.x + 1):
		for y in range(a.y, b.y + 1):
			if World.in_bounds(x, y):
				World.set_tile(x, y, IDs.T.AIR)


func _flush() -> void:
	if World.beams != null:
		World.beams.note_machines()
		World.beams.rebuild()


func _gone(m) -> void:
	if m != null and is_instance_valid(m) and not m.is_queued_for_deletion():
		m.dismantle()
