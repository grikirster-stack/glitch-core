class_name Press
extends MachineBase
## Пресс (ADR-006 § 3.2, #314): волокно → панели.
##
## Вход — грань dir, выход — противоположная. Берёт партию только с входной
## грани: лоток грядки или сундук. Чужой предмет и сундук с другой стороны
## не трогает. Партия лежит во внутреннем слоте, пока идёт работа; готовые
## панели ждут в выходном буфере и уходят в сундук на выходной грани.
## Полный выход работу не обнуляет — завершение просто ждёт места.


## Подписи состояний (ADR-006 § 3.2 и § 5). HUD их не рисует — сценарии и кадр.
const ST_WAIT: String = "Ждёт волокно"
const ST_WORK: String = "Прессует"
const ST_FULL: String = "Выход полон"
const ST_SIDE: String = "Не та сторона"

## Волокон во внутреннем слоте. Партия забирается целиком, не по одному.
var batch: int = 0
## Партий, которые ещё ждут своей очереди (не считая текущей).
var queued: int = 0
## Секунды текущей партии. 0..PRESS_SECONDS.
## Не work: у базы так называется метод такта, поле с тем же именем не компилируется.
var job: float = 0.0
## Готовых панелей в выходном буфере.
var out_buf: int = 0
## Партий завершено — для сценариев и замера смены.
var made: int = 0
## Сколько панелей ушло в выходной сундук.
var pushed: int = 0
## Последний отказ: пустая строка, «Выход полон» или «Не та сторона».
var reject: String = ""
## Кадры, пока вспышка партии ещё видна. Автоперенос тоже её зажигает.
var flash: float = 0.0

var _notified: String = ""


func _init() -> void:
	kind = "Press"
	z_index = 3
	can_turn = true


func _process(delta: float) -> void:
	super(delta)
	if flash > 0.0:
		flash = maxf(0.0, flash - delta)
	# СЕТЬ (ADR-002): партию и буфер считает хост. Клиент рисует по net_state.
	if not Net.is_authority():
		queue_redraw()
		return
	# Сначала отдать готовую панель. Иначе полный сундук не успевает
	# сказать «Выход полон», а очередь уже забрала следующее волокно.
	_push()
	_pull()
	_tick(delta)
	_say()
	queue_redraw()


## Входная грань: куда смотрит пресс. Выход — напротив.
func in_dir() -> Vector2i:
	return [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)][dir & 3]


func out_dir() -> Vector2i:
	return -in_dir()


## Клетка, откуда пресс берёт волокно, и куда отдаёт панели.
func in_cell() -> Vector2i:
	return cell + in_dir()


func out_cell() -> Vector2i:
	return cell + out_dir()


## Свободно партий во внутреннем слоте (текущая тоже занимает место).
func _queue_room() -> int:
	var held: int = queued + (1 if batch > 0 else 0)
	return maxi(0, Balance.PRESS_QUEUE - held)


## Выходной буфер полон: завершать партию некуда.
func _out_full() -> bool:
	return out_buf + Balance.PRESS_PANEL_OUT > Balance.PRESS_BUFFER * Balance.PRESS_PANEL_OUT


## Забрать одну партию с входной грани. Чужое и другая сторона — отказ.
func _pull() -> void:
	if _queue_room() <= 0:
		return
	var n = World.machines.get(in_cell())
	if n == null:
		return
	if n is SporeBed:
		if n.out_dir() != -in_dir():
			_reject(ST_SIDE)
			return
		if int(n.tray) < Balance.PRESS_FIBER_IN:
			return
		if n.take_fiber(Balance.PRESS_FIBER_IN) < Balance.PRESS_FIBER_IN:
			return
		_accept()
		return
	if n is Chest:
		if _chest_count(n, IDs.I.SPORE_FIBER) < Balance.PRESS_FIBER_IN:
			if _chest_has_other(n, IDs.I.SPORE_FIBER):
				_reject(ST_SIDE)
			return
		# Полный выход: не забирать волокно, которое некуда деть.
		if _out_full() and batch > 0:
			_reject(ST_FULL)
			return
		if not _chest_take(n, IDs.I.SPORE_FIBER, Balance.PRESS_FIBER_IN):
			return
		_accept()


func _accept() -> void:
	reject = ""
	if batch <= 0:
		batch = Balance.PRESS_FIBER_IN
		job = 0.0
	else:
		queued += 1
	anim = 1.0
	flash = 0.45
	_sync_progress()


## Сундук не на входе отдал волокно, или отдал не волокно. Сообщаем один раз.
func note_wrong_side() -> void:
	_reject(ST_SIDE)


func _reject(why: String) -> void:
	reject = why


func _tick(delta: float) -> void:
	if batch <= 0:
		_sync_progress()
		return
	if _out_full():
		# Завершение ждёт. Секунды партии не сбрасываем и не копим сверх шага.
		_sync_progress()
		return
	job += delta
	var step: float = Balance.PRESS_SECONDS
	if job < step:
		_sync_progress()
		return
	job = 0.0
	batch = 0
	out_buf += Balance.PRESS_PANEL_OUT
	made += 1
	anim = 1.0
	flash = 0.55
	# Следующая партия уже внутри. Выход полон — она ждёт, секунды не тикают.
	if queued > 0:
		queued -= 1
		batch = Balance.PRESS_FIBER_IN
	_sync_progress()


## Выходной сундук — только с выходной грани. Иначе панели остаются в буфере.
func _push() -> void:
	if out_buf <= 0:
		return
	var n = World.machines.get(out_cell())
	if not (n is Chest):
		return
	var left: int = n.receive_item(IDs.I.PANEL, 1)
	if left > 0:
		_reject(ST_FULL)
		return
	out_buf -= 1
	pushed += 1
	anim = 1.0
	flash = 0.35
	if out_buf + Balance.PRESS_PANEL_OUT <= Balance.PRESS_BUFFER * Balance.PRESS_PANEL_OUT:
		if reject == ST_FULL:
			reject = ""


func _say() -> void:
	var text: String = status_text()
	if text == _notified:
		return
	if text != ST_WAIT and text != ST_WORK:
		Game.notify(text, DB.item_color(IDs.I.PANEL), IDs.I.PANEL)
	_notified = text


func status_text() -> String:
	if reject == ST_SIDE and batch <= 0 and queued <= 0:
		return ST_SIDE
	if batch > 0 and _out_full():
		return ST_FULL
	if out_buf > 0 and _out_full() and batch <= 0:
		return ST_FULL
	if batch > 0:
		return ST_WORK
	if reject == ST_FULL and out_buf > 0:
		return ST_FULL
	if reject == ST_SIDE:
		return ST_SIDE
	return ST_WAIT


func _sync_progress() -> void:
	if batch <= 0:
		progress = 0.0
		return
	progress = clampf(job / maxf(Balance.PRESS_SECONDS, 0.001), 0.0, 1.0)


## Руки: то же волокно, что берёт автомат. Не волокно — отказ, слот не тратим.
func receive_item(item_id: int, count: int) -> int:
	if not Net.is_authority():
		return count
	if item_id != IDs.I.SPORE_FIBER:
		_reject(ST_SIDE)
		return count
	var room: int = _queue_room() * Balance.PRESS_FIBER_IN
	if batch <= 0:
		room = maxi(room, Balance.PRESS_FIBER_IN) if _queue_room() > 0 else 0
	var take: int = mini(count, room)
	# Неполная партия руками не принимается: внутренний слот хранит целые.
	take -= take % Balance.PRESS_FIBER_IN
	if take <= 0:
		if count > 0 and _queue_room() <= 0:
			_reject(ST_FULL)
		return count
	var left: int = count - take
	var batches: int = take / Balance.PRESS_FIBER_IN
	if batch <= 0:
		batch = Balance.PRESS_FIBER_IN
		job = 0.0
		batches -= 1
	queued += batches
	reject = ""
	anim = 1.0
	flash = 0.45
	_sync_progress()
	queue_redraw()
	return left


func input_accepts(item_id: int) -> bool:
	return item_id == IDs.I.SPORE_FIBER and _queue_room() > 0


## Игрок забрал панели с выхода. 0 — буфер пуст или это клиент.
func take_panels(n: int = 1) -> int:
	if not Net.is_authority():
		return 0
	var take: int = mini(n, out_buf)
	out_buf -= take
	if out_buf + Balance.PRESS_PANEL_OUT <= Balance.PRESS_BUFFER * Balance.PRESS_PANEL_OUT:
		if reject == ST_FULL:
			reject = ""
	queue_redraw()
	return take


func interact(p) -> void:
	if out_buf <= 0 or p == null:
		return
	var got: int = take_panels(out_buf)
	if got <= 0:
		return
	var left: int = p.inv.add(IDs.I.PANEL, got)
	if left > 0:
		spawn_item(IDs.I.PANEL, left, p.global_position)
	Game.notify("Забрано: %s ×%d" % [DB.item_name(IDs.I.PANEL), got],
			DB.item_color(IDs.I.PANEL), IDs.I.PANEL)


## Сняли пресс — волокно партии и готовые панели на землю. Доля секунд — не штука.
func _on_destroyed() -> void:
	var fiber: int = batch + queued * Balance.PRESS_FIBER_IN
	if fiber > 0:
		spawn_item(IDs.I.SPORE_FIBER, fiber, global_position + Vector2(-4.0, -4.0))
	if out_buf > 0:
		spawn_item(IDs.I.PANEL, out_buf, global_position + Vector2(4.0, -4.0))
	batch = 0
	queued = 0
	job = 0.0
	out_buf = 0


func _draw() -> void:
	var working: bool = batch > 0
	_draw_body(Rect2(-7.0, -6.0, 14.0, 12.0), working or out_buf > 0, false)
	_draw_mouths()
	_draw_batch()
	_draw_out()
	if working:
		_draw_progress(7.0)
	var lamp: Color = C_LAMP_OFF
	if status_text() == ST_FULL or status_text() == ST_SIDE:
		lamp = C_HAZARD
	elif working:
		lamp = Color(0.95, 0.82, 0.35)
	elif out_buf > 0:
		lamp = Color(0.86, 0.84, 0.72)
	_draw_lamp(Vector2(-5.0, -8.0), lamp)


## Зелёная щель входа и светлая щель выхода. Сторона читается без подписи.
func _draw_mouths() -> void:
	var inn: Vector2 = _mouth(dir & 3)
	var outp: Vector2 = _mouth((dir + 2) & 3)
	draw_rect(Rect2(inn.x, inn.y, 3.0, 3.0), Color(0.22, 0.28, 0.16))
	draw_rect(Rect2(inn.x + 1.0, inn.y + 1.0, 1.0, 1.0), Color(0.62, 0.82, 0.28))
	draw_rect(Rect2(outp.x, outp.y, 3.0, 3.0), Color(0.28, 0.26, 0.22))
	var out_col: Color = Color(0.95, 0.92, 0.72) if out_buf > 0 else Color(0.55, 0.52, 0.46)
	draw_rect(Rect2(outp.x + 1.0, outp.y + 1.0, 1.0, 1.0), out_col)
	if flash > 0.0:
		draw_rect(Rect2(outp.x - 1.0, outp.y - 1.0, 5.0, 5.0), Color(1.0, 0.95, 0.55, flash))


func _mouth(d: int) -> Vector2:
	match d:
		0:
			return Vector2(5.0, -2.0)
		1:
			return Vector2(-2.0, 4.0)
		2:
			return Vector2(-8.0, -2.0)
		_:
			return Vector2(-2.0, -8.0)


## Волокно во внутреннем слоте: столбик на каждую партию.
func _draw_batch() -> void:
	var n: int = (1 if batch > 0 else 0) + queued
	for i in Balance.PRESS_QUEUE:
		var x: float = -4.0 + float(i) * 4.0
		draw_rect(Rect2(x, -1.0, 3.0, 3.0), Color(C_FRAME, 0.55))
		if i < n:
			draw_rect(Rect2(x, -6.0, 3.0, 8.0), Color(0.62, 0.82, 0.28))
			draw_rect(Rect2(x, -8.0, 3.0, 2.0), Color(0.95, 1.0, 0.55))


## Панели буфера — светлые пластины у выходной грани.
func _draw_out() -> void:
	var shown: int = mini(out_buf, 4)
	for i in shown:
		var y: float = -4.0 + float(i) * 2.0
		draw_rect(Rect2(1.0, y, 5.0, 1.0), Color(0.90, 0.88, 0.74))


func _chest_count(chest: Chest, id: int) -> int:
	var n: int = 0
	for s in chest.slots:
		if s.id == id:
			n += s.count
	return n


func _chest_has_other(chest: Chest, id: int) -> bool:
	for s in chest.slots:
		if not s.is_empty() and s.id != id:
			return true
	return false


func _chest_take(chest: Chest, id: int, n: int) -> bool:
	if _chest_count(chest, id) < n:
		return false
	var left: int = n
	for s in chest.slots:
		if s.id != id or s.is_empty():
			continue
		var take: int = mini(left, s.count)
		s.take(take)
		left -= take
		if left <= 0:
			break
	chest.queue_redraw()
	return left <= 0


# ------------------------------------------------------------- СОХРАНЕНИЕ (#37)
## Добавочные ключи. Старый сейв их не имеет — .get оставляет нули.
## reject и flash не пишем: это реакция кадра, не запас.
func save_state() -> Dictionary:
	var d: Dictionary = super()
	d["batch"] = batch
	d["queued"] = queued
	d["job"] = job
	d["out_buf"] = out_buf
	d["made"] = made
	d["pushed"] = pushed
	return d


func load_state(d: Dictionary) -> void:
	super(d)
	batch = maxi(0, int(d.get("batch", 0)))
	queued = maxi(0, int(d.get("queued", 0)))
	job = maxf(0.0, float(d.get("job", d.get("work", 0.0))))
	out_buf = maxi(0, int(d.get("out_buf", 0)))
	made = maxi(0, int(d.get("made", 0)))
	pushed = maxi(0, int(d.get("pushed", 0)))
	reject = ""
	_notified = ""
	_sync_progress()
	queue_redraw()


# ------------------------------------------------------------- СЕТЬ (ADR-002)
## Хвост после базы, поля только в конец: work u8 · batch u8 · queued u8 ·
## out u8 · флаги u8. Длина базы не меняется.
func net_state() -> PackedByteArray:
	var b: PackedByteArray = super()
	b.append(net_u8(job / maxf(Balance.PRESS_SECONDS, 0.001)))
	b.append(clampi(batch, 0, 255))
	b.append(clampi(queued, 0, 255))
	b.append(clampi(out_buf, 0, 255))
	var flags: int = 0
	if reject == ST_FULL:
		flags |= 1
	elif reject == ST_SIDE:
		flags |= 2
	b.append(flags)
	return b


func apply_net_state(b: PackedByteArray) -> int:
	var o: int = super(b)
	if o < 0 or b.size() < o + 5:
		return -1
	var prev_out: int = out_buf
	var prev_batch: int = batch
	job = float(b[o]) / 255.0 * Balance.PRESS_SECONDS
	batch = int(b[o + 1])
	queued = int(b[o + 2])
	out_buf = int(b[o + 3])
	var flags: int = int(b[o + 4])
	if flags & 1:
		reject = ST_FULL
	elif flags & 2:
		reject = ST_SIDE
	else:
		reject = ""
	if out_buf != prev_out or batch != prev_batch:
		flash = 0.4
	_sync_progress()
	queue_redraw()
	return o + 5
