class_name SporeBed
extends MachineBase
## Споровая грядка (ADR-006 § 3.2, #313): приёмник белого луча.
##
## Белый (Beams.W) приходит от любого источника — коллектор днём, накопитель
## ночью, горелка. Источник не проверяем: Beams сообщает цвет через beam_receive.
## Секунды света копятся здесь, не в Beams. Обрыв луча прогресс не обнуляет.
## Лоток на Balance.SPORE_BED_TRAY: полный — стоим, после забора продолжаем
## с той же доли. Готовое видно на лотке и уходит в соседний сундук.


## Стадии роста для отрисовки и сценариев. 0 — ждём свет или место.
const STAGE_SEED: int = 0
const STAGE_SPROUT: int = 1
const STAGE_CAP: int = 2
const STAGE_READY: int = 3

## Цвет, который растит. Только чистый белый (маска == Beams.W).
const WANT: int = 7

## Подписи состояний (ADR-006 § 3.2). HUD и сценарии читают status_text().
const ST_GROW: String = "Растёт"
const ST_DARK: String = "Нет белого луча"
const ST_FULL: String = "Выход полон"

## Лоток: готовые волокна, ещё не отданные. Не _output базы: deliver() сам
## кладёт в сундук, а лоток должен ждать игрока и соседа.
var tray: int = 0
## Секунды белого, накопленные к текущему волокну. 0..SPORE_BED_SECONDS.
var grow: float = 0.0
## Белый упёрся в грядку на последнем перестроении луча.
var lit: bool = false
## Волокон выпущено за жизнь — для сценариев и замера смены.
var made: int = 0
## Сколько раз отдали соседу-сундуку — для сценариев.
var pushed: int = 0

var _mask: int = 0


func _init() -> void:
	kind = "SporeBed"
	z_index = 3
	# Сторона лотка. Пресс (#314) заберёт волокно с этой грани — не мешаем.
	can_turn = true


func _process(delta: float) -> void:
	super(delta)
	# СЕТЬ (ADR-002): секунды и лоток считает хост. Клиент рисует по net_state.
	if not Net.is_authority():
		queue_redraw()
		return
	_tick(delta)
	_push_tray()
	queue_redraw()


## Белый есть и в лотке есть место — копим секунды. Иначе стоим, не сбрасывая.
func _tick(delta: float) -> void:
	if not lit or tray >= Balance.SPORE_BED_TRAY:
		_sync_progress()
		return
	grow += delta
	var step: float = Balance.SPORE_BED_SECONDS
	while grow >= step and tray < Balance.SPORE_BED_TRAY:
		grow -= step
		tray += 1
		made += 1
		anim = 1.0
	if tray >= Balance.SPORE_BED_TRAY:
		# Лишние секунды сверх полного лотка не копятся: место кончилось.
		grow = 0.0
	_sync_progress()


## Соседний сундук забирает по одному волокну за кадр, пока есть место.
## Игрок забирает то же содержимое через take_fiber — один лоток.
func _push_tray() -> void:
	if tray <= 0:
		return
	for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		var n = World.machines.get(cell + d)
		if not (n is Chest):
			continue
		var left: int = n.receive_item(IDs.I.SPORE_FIBER, 1)
		if left > 0:
			continue
		tray -= 1
		pushed += 1
		return


## Игрок забрал волокно с лотка. 0 — лоток пуст или это клиент.
func take_fiber(n: int = 1) -> int:
	if not Net.is_authority():
		return 0
	var take: int = mini(n, tray)
	tray -= take
	_sync_progress()
	queue_redraw()
	return take


## Цвет, который упёрся в грядку (OR входов). 0 — луча нет.
## Клиент цвет не решает: его трассировка отстаёт от хоста (#180).
func beam_receive(mask: int) -> void:
	if not Net.is_authority():
		return
	_mask = mask & 7
	var next: bool = _mask == WANT
	if next == lit:
		return
	lit = next
	queue_redraw()


## Грядка — конец линии, не труба. Выход предмета — лоток, не луч.
func beam_pass(_in_dir: int, _color: int) -> Array:
	return []


## Доля текущего волокна. Полный лоток — 1, чтобы полоса не мигала нулём.
func _sync_progress() -> void:
	if tray >= Balance.SPORE_BED_TRAY:
		progress = 1.0
		return
	progress = clampf(grow / maxf(Balance.SPORE_BED_SECONDS, 0.001), 0.0, 1.0)


## Стадия ростка по накопленным секундам. Готовое волокно рисует лоток.
func stage() -> int:
	if grow <= 0.0:
		return STAGE_SEED
	var t: float = grow / maxf(Balance.SPORE_BED_SECONDS, 0.001)
	if t < 0.34:
		return STAGE_SPROUT
	if t < 0.84:
		return STAGE_CAP
	return STAGE_READY


## «Растёт», «Нет белого луча», «Выход полон». Полный лоток важнее темноты.
func status_text() -> String:
	if tray >= Balance.SPORE_BED_TRAY:
		return ST_FULL
	if not lit:
		return ST_DARK
	return ST_GROW


## Сторона выдачи: куда смотрит стрелка лотка. Пресс встанет с этой грани.
func out_dir() -> Vector2i:
	return [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)][dir & 3]


## Сняли грядку — волокно с лотка на землю. Доля текущего волокна — не штука,
## в предметы её не переводим.
func _on_destroyed() -> void:
	if tray > 0:
		spawn_item(IDs.I.SPORE_FIBER, tray, global_position + Vector2(0.0, -4.0))
		tray = 0


func interact(p) -> void:
	if tray <= 0 or p == null:
		return
	var got: int = take_fiber(tray)
	if got <= 0:
		return
	var left: int = p.inv.add(IDs.I.SPORE_FIBER, got)
	if left > 0:
		spawn_item(IDs.I.SPORE_FIBER, left, p.global_position)
	Game.notify("Забрано: %s ×%d" % [DB.item_name(IDs.I.SPORE_FIBER), got],
			DB.item_color(IDs.I.SPORE_FIBER), IDs.I.SPORE_FIBER)


func _draw() -> void:
	var full: bool = tray >= Balance.SPORE_BED_TRAY
	var on: bool = lit and not full
	_draw_body(Rect2(-7.0, -2.0, 14.0, 10.0), on or tray > 0, false)
	# Земля лотка: тёмная полоса, в ней виден росток.
	draw_rect(Rect2(-6.0, 1.0, 12.0, 5.0), C_SOOT)
	_draw_sprout()
	_draw_tray()
	_draw_arrow()
	_draw_beam_mark()
	if grow > 0.0 and not full:
		_draw_progress(-5.0)
	var lamp: Color = C_LAMP_OFF
	if lit:
		lamp = Color.WHITE
	elif full:
		lamp = C_HAZARD
	_draw_lamp(Vector2(-5.0, -5.0), lamp)


## Росток по стадии. Готовое волокно рисует лоток, не стебель.
func _draw_sprout() -> void:
	var st: int = stage()
	if st == STAGE_SEED and tray <= 0:
		draw_rect(Rect2(-1.0, 3.0, 2.0, 1.0), C_LICHEN.darkened(0.3))
		return
	var stem: Color = C_LICHEN if lit or tray > 0 else C_LICHEN.darkened(0.35)
	draw_rect(Rect2(-1.0, 2.0, 2.0, 3.0), stem)
	if st >= STAGE_SPROUT:
		draw_rect(Rect2(-2.0, 1.0, 1.0, 2.0), C_LICHEN_HI)
		draw_rect(Rect2(1.0, 1.0, 1.0, 2.0), C_LICHEN_HI)
	if st >= STAGE_CAP:
		draw_rect(Rect2(-2.0, -1.0, 4.0, 2.0), Color(0.78, 0.88, 0.42))
		draw_rect(Rect2(-1.0, -2.0, 2.0, 1.0), Color(0.90, 0.95, 0.55))


## Готовые волокна — столбики на лотке. Четыре места видны всегда.
func _draw_tray() -> void:
	var slots: int = Balance.SPORE_BED_TRAY
	for i in slots:
		var x: float = -6.0 + float(i) * 3.0
		draw_rect(Rect2(x, 5.0, 2.0, 2.0), Color(C_FRAME, 0.7))
		if i < tray:
			# Палочка волокна выше корпуса: на кадре лоток читается без лупы.
			draw_rect(Rect2(x, -10.0, 2.0, 16.0), Color(0.62, 0.82, 0.28))
			draw_rect(Rect2(x, -12.0, 2.0, 2.0), Color(0.95, 1.0, 0.55))


## Стрелка стороны выдачи. Пресс и сундук встают по ней.
func _draw_arrow() -> void:
	var tip: Vector2 = Vector2(7.0, 4.0)
	var tail: Vector2 = Vector2(5.0, 4.0)
	match dir & 3:
		1:
			tip = Vector2(0.0, 8.0)
			tail = Vector2(0.0, 6.0)
		2:
			tip = Vector2(-7.0, 4.0)
			tail = Vector2(-5.0, 4.0)
		3:
			tip = Vector2(0.0, -4.0)
			tail = Vector2(0.0, -2.0)
	var col: Color = C_HAZARD if tray > 0 else C_FRAME
	draw_rect(Rect2(tail.x - 0.5, tail.y - 0.5, 2.0, 2.0), col)
	draw_rect(Rect2(tip.x - 0.5, tip.y - 0.5, 2.0, 2.0), col)


## Белая точка входа: луч попал — горит, нет — тёмное стекло.
func _draw_beam_mark() -> void:
	draw_rect(Rect2(-2.0, -7.0, 4.0, 3.0), C_FRAME)
	draw_rect(Rect2(-1.0, -6.0, 2.0, 2.0), Color.WHITE if lit else C_SCREEN)


# ------------------------------------------------------------- СОХРАНЕНИЕ (#37)
## Добавочные ключи. Старый сейв их не имеет — .get оставляет нули.
func save_state() -> Dictionary:
	var d: Dictionary = super()
	d["tray"] = tray
	d["grow"] = grow
	d["lit"] = lit
	d["made"] = made
	return d


func load_state(d: Dictionary) -> void:
	super(d)
	tray = maxi(0, int(d.get("tray", 0)))
	grow = maxf(0.0, float(d.get("grow", 0.0)))
	lit = bool(d.get("lit", false))
	made = maxi(0, int(d.get("made", 0)))
	_sync_progress()
	queue_redraw()


# ------------------------------------------------------------- СЕТЬ (ADR-002)
## Хвост после базы, поля только в конец: grow u8 · tray u8 · флаги u8.
## Флаги: бит 0 — белый на входе. Длина базы не меняется.
func net_state() -> PackedByteArray:
	var b: PackedByteArray = super()
	b.append(net_u8(grow / maxf(Balance.SPORE_BED_SECONDS, 0.001)))
	b.append(clampi(tray, 0, 255))
	b.append(1 if lit else 0)
	return b


func apply_net_state(b: PackedByteArray) -> int:
	var o: int = super(b)
	if o < 0 or b.size() < o + 3:
		return -1
	var was: bool = lit
	grow = float(b[o]) / 255.0 * Balance.SPORE_BED_SECONDS
	tray = int(b[o + 1])
	lit = (int(b[o + 2]) & 1) != 0
	_mask = WANT if lit else 0
	_sync_progress()
	if lit != was and World.beams != null:
		World.beams.mark_dirty()
	queue_redraw()
	return o + 3
