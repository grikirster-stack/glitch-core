class_name InvOps
extends Node
## Инвентари, крафт, сундуки и исследования по сети: слой команд (ADR-002 § 4.2.7,
## § 4.7 «общее и личное», D10; MP-G, #91).
##
## Панель инвентаря больше не пишет в слоты сама — она зовёт атомарные команды отсюда:
## move(откуда, слот, куда, слот, n), split, take_all/put_all (сундук), craft(рецепт, раз),
## drop(слот, n), select(i), unlock(узел).
##   * Одиночная и хост (Net.is_authority()): команда выполняется сразу — статические
##     функции этого файла, тот же код, что раньше был в панели (одиночная побайтно прежняя).
##   * Клиент: команда — кадр CMD хосту (канал 2, NetCodec.encode_inv_args). Хост проверяет
##     (дистанция до сундука, ожидаемый предмет и число в ячейке, место) и выполняет её тем
##     же кодом у прокси. Итог: свежий INV владельцу, CHEST всем, у кого сундук открыт
##     (и самому отправителю), затем CMD_RESULT {req, ok, текст обратной связи}.
##     Опоздавшая команда (ячейку уже опустошил другой) — отказ и свежее содержимое.
##   * «Предмет в руке» у клиента — состояние окна: стопка остаётся в своей ячейке, пока
##     команда move её не переложит (панель рисует ячейку за вычетом руки).
## Сундук по E у прокси (Player._open_chest) — host_open(): хост подписывает владельца
## на сундук и шлёт CHEST с флагом «открыть»; клиент открывает окно у себя. Изменения
## сундука от лент и манипуляторов приходят подписчикам опросом POLL_SEC.
## Исследования, главы и обрывки — общие (D10): хост рассылает TECH всем (канал 0) по
## сигналам Tech; клиент открывает узел командой UNLOCK (Tech.unlock у клиента зовёт её).
##
## Узел живёт под main.gd (секция «СЕТЬ: ИНВЕНТАРИ»); без сети не нужен — одиночная зовёт
## только статические функции.

const Op = NetCodec.InvOp
const Box = NetCodec.Box

## Тон обратной связи: панель берёт цвет строки по нему.
enum Tone { OK, WARN, BAD, DIM, ERR, INFO }

## Хост: дальше этого (px) от сундука команды с ним не принимаются (E открывает с 40 px;
## запас — на движение за время пути команды).
const CHEST_REACH: float = 72.0
## Ближе этого (px) к станку крафт станка загружает в него сырьё (как в панели).
const STATION_REACH: float = 90.0
## Хост: опрос открытых сундуков (ленты, манипуляторы, свой герой хоста), с.
const POLL_SEC: float = 0.25
## Хост: повтор «открыть» тому же игроку для того же сундука не чаще, мс (E держат).
const REOPEN_MS: int = 500

## Узел этого процесса (хост и клиент; в одиночной — null).
static var inst: InvOps = null
## Клиент: номер следующего запроса и ждущие ответа: req → {op, us, cb}.
static var _req: int = 0
static var _pending: Dictionary = {}
## Замеры (сценарии): клиент — отправлено, ответов, отказов, круг команды, мс; хост —
## выполнено, отказано.
static var stats: Dictionary = {}

var main: Node = null
## Хост: клетка сундука → {peer_id: true}; peer_id → клетка; клетка → хэш отправленного.
var _subs: Dictionary = {}
var _sub_of: Dictionary = {}
var _sent_hash: Dictionary = {}
var _open_ms: Dictionary = {}
var _poll_t: float = 0.0


func start(p_main: Node) -> void:
	main = p_main
	inst = self
	reset_stats()
	Net.on(NetCodec.Msg.CMD, _on_cmd)
	Net.on(NetCodec.Msg.CMD_RESULT, _on_result)
	Net.on(NetCodec.Msg.CHEST, _on_chest)
	Net.on(NetCodec.Msg.TECH, _on_tech)
	Net.peer_left.connect(_on_peer_left)
	Net.session_ended.connect(_on_session_ended)
	Tech.node_unlocked.connect(_on_node_unlocked)
	Tech.chapter_read.connect(_on_chapter_read)
	Tech.fragment_found.connect(_on_fragment_found)


func _exit_tree() -> void:
	if inst == self:
		inst = null


static func reset_stats() -> void:
	stats = {"sent": 0, "replies": 0, "refused": 0, "rtt_ms": PackedFloat32Array(),
			"exec": 0, "host_refused": 0}


# ------------------------------------------------------------------ ЯДРО: СЛОТЫ (одиночная = хост)

## Переложить до n предметов из src[si] в dst[di]: в пустую ячейку — сколько просили,
## в ту же стопку — сколько влезет, в другой предмет — обмен стопками (только swap и
## только если берётся вся стопка). Возвращает, сколько переложено (обмен — вся стопка).
static func xfer(src: Array, si: int, dst: Array, di: int, n: int, swap: bool = false) -> int:
	if si < 0 or si >= src.size() or di < 0 or di >= dst.size() or n <= 0:
		return 0
	var s: ItemStack = src[si]
	if s.is_empty():
		return 0
	var d: ItemStack = dst[di]
	if d == s:
		return 0
	if d.is_empty():
		var k: int = mini(n, s.count)
		dst[di] = ItemStack.new(s.id, k)
		s.take(k)
		return k
	if d.id == s.id:
		var k2: int = mini(mini(DB.item_max_stack(d.id) - d.count, n), s.count)
		if k2 <= 0:
			return 0
		d.count += k2
		s.take(k2)
		return k2
	if swap and n >= s.count:
		src[si] = d
		dst[di] = s
		return s.count
	return 0


## Shift+ЛКМ по ячейке сундука: вся стопка — в инвентарь (что влезет).
## Итог: {n, text, tone}.
static func quick_from_chest(inv: Inventory, chest: Chest, index: int) -> Dictionary:
	if chest == null or index < 0 or index >= chest.slots.size():
		return {"n": 0, "text": "", "tone": Tone.DIM}
	var s: ItemStack = chest.slots[index]
	if s.is_empty():
		return {"n": 0, "text": "", "tone": Tone.DIM}
	var id: int = s.id
	var moved: int = s.count - inv.add(id, s.count)
	s.take(moved)
	chest.queue_redraw()
	if moved > 0:
		return {"n": moved, "text": "Забрано в инвентарь: %s ×%d" % [DB.item_name(id), moved], "tone": Tone.OK}
	return {"n": 0, "text": "Инвентарь полон — некуда забрать %s." % DB.item_name(id), "tone": Tone.BAD}


## Shift+ЛКМ по ячейке инвентаря: с открытым сундуком — стопку в сундук, без
## сундука — из хотбара в рюкзак и обратно. Итог: {n, text, tone}.
static func quick_from_inv(inv: Inventory, chest: Chest, index: int) -> Dictionary:
	if index < 0 or index >= inv.size:
		return {"n": 0, "text": "", "tone": Tone.DIM}
	var s: ItemStack = inv.slots[index]
	if s.is_empty():
		return {"n": 0, "text": "", "tone": Tone.DIM}
	var id: int = s.id
	var left: int = 0
	var where: String = ""
	if chest:
		left = Inventory.stack_into(chest.slots, id, s.count)
		where = "в сундук"
		chest.queue_redraw()
	elif index < inv.hotbar_size:
		left = Inventory.stack_into(inv.slots, id, s.count, inv.hotbar_size)
		where = "в рюкзак"
	else:
		left = Inventory.stack_into(inv.slots, id, s.count, 0, inv.hotbar_size)
		where = "в хотбар"
	var moved: int = s.count - left
	s.take(moved)
	inv.changed.emit()
	if moved > 0:
		return {"n": moved, "text": "Переложено %s: %s ×%d" % [where, DB.item_name(id), moved], "tone": Tone.OK}
	return {"n": 0, "text": "Места нет — %s не переложить %s." % [DB.item_name(id), where], "tone": Tone.BAD}


## «Забрать всё»: всё из сундука — в инвентарь, что влезет. Итог: {n, text, tone}.
static func take_all(inv: Inventory, chest: Chest) -> Dictionary:
	if chest == null:
		return {"n": 0, "text": "", "tone": Tone.DIM}
	var moved: int = 0
	var left_total: int = 0
	for s in chest.slots:
		if s.is_empty():
			continue
		var m: int = s.count - inv.add(s.id, s.count)
		s.take(m)
		moved += m
		left_total += s.count
	chest.queue_redraw()
	if left_total > 0:
		return {"n": moved, "text": "Инвентарь полон: забрано %d, в сундуке осталось %d." % [moved, left_total],
				"tone": Tone.WARN}
	if moved > 0:
		return {"n": moved, "text": "Забрано из сундука: %d шт." % moved, "tone": Tone.OK}
	return {"n": 0, "text": "Сундук пуст.", "tone": Tone.DIM}


## «Сложить всё»: рюкзак (всё, кроме хотбара) — в сундук. Итог: {n, text, tone}.
static func put_all(inv: Inventory, chest: Chest) -> Dictionary:
	if chest == null:
		return {"n": 0, "text": "", "tone": Tone.DIM}
	var moved: int = 0
	var left_total: int = 0
	for i in range(inv.hotbar_size, inv.size):
		var s: ItemStack = inv.slots[i]
		if s.is_empty():
			continue
		var m: int = s.count - Inventory.stack_into(chest.slots, s.id, s.count)
		s.take(m)
		moved += m
		left_total += s.count
	inv.changed.emit()
	chest.queue_redraw()
	if left_total > 0:
		return {"n": moved, "text": "Сундук полон: сложено %d, осталось %d." % [moved, left_total], "tone": Tone.WARN}
	if moved > 0:
		return {"n": moved, "text": "Сложено в сундук: %d шт. Хотбар не тронут." % moved, "tone": Tone.OK}
	return {"n": 0, "text": "Рюкзак пуст (хотбар «Сложить всё» не трогает).", "tone": Tone.DIM}


## Предмет «в руке» (hand[0]) не пропадает: обратно в инвентарь, не влез — в открытый
## сундук, и уж совсем никак — на землю под ноги (подберётся, когда будет место).
static func return_hand(p: Player, chest, hand: Array) -> void:
	var held: ItemStack = hand[0]
	if held.is_empty():
		hand[0] = ItemStack.new()
		return
	var left: int = held.count
	if p:
		left = p.inv.add(held.id, left)
		if left > 0 and chest and is_instance_valid(chest):
			left = Inventory.stack_into(chest.slots, held.id, left)
		if left > 0:
			p.spawn_item(held.id, left, p.global_position)
	hand[0] = ItemStack.new()


## Выбросить n предметов из ячейки под ноги. Итог: {n, text, tone}.
static func drop(p: Player, arr: Array, index: int, n: int) -> Dictionary:
	if index < 0 or index >= arr.size() or n <= 0:
		return {"n": 0, "text": "", "tone": Tone.DIM}
	var s: ItemStack = arr[index]
	if s.is_empty():
		return {"n": 0, "text": "", "tone": Tone.DIM}
	var id: int = s.id
	var k: int = s.take(n)
	p.spawn_item(id, k, p.global_position)
	p.inv.changed.emit()
	return {"n": k, "text": "Выброшено: %s ×%d" % [DB.item_name(id), k], "tone": Tone.INFO}


## Хотбар: выбрать ячейку i.
static func select(p: Player, i: int) -> void:
	if Net.is_client():
		p.inv.selected = clampi(i, 0, p.inv.hotbar_size - 1)
		send(Op.SELECT, {"slot": i})
		return
	if i >= 0 and i < p.inv.hotbar_size:
		p.inv.selected = i


# ------------------------------------------------------------------ КРАФТ

## Станок рядом с героем (ближе STATION_REACH): kind — "Smelter", "Assembler".
static func near_machine(p: Player, kind: String) -> MachineBase:
	if p == null:
		return null
	for m in World.machines.values():
		if m.kind == kind and m.global_position.distance_to(p.global_position) < STATION_REACH:
			return m
	return null


## Хост: можно ли сделать рецепт этому герою. {code: ok|locked|far|missing, near, reason}.
## Панель считает то же со своими кэшами и подписями; здесь — проверка команды клиента.
static func craft_check(p: Player, rec: Dictionary) -> Dictionary:
	var station: String = String(rec["station"])
	if not DB.recipe_unlocked(rec):
		return {"code": "locked", "near": null,
				"reason": "Заперто: нужен узел %s — вкладка «Исследования»." % Tech.title(String(rec.get("tech", "T0")))}
	var near: MachineBase = null
	if station != "hand":
		near = near_machine(p, "Smelter" if station == "smelter" else "Assembler")
		if near == null:
			return {"code": "far", "near": null, "reason": "Станок далеко: подойди ближе (≤ 5 клеток)."}
	for id in rec["in"].keys():
		if p.inv.count_of(id) < int(rec["in"][id]):
			return {"code": "missing", "near": near, "reason": "Не хватает материалов."}
	return {"code": "ok", "near": near, "reason": ""}


## Сделать рецепт (проверка уже пройдена): руками — в инвентарь (полон — под ноги),
## станком near — сырьё в станок. Итог: {text, tone} для обратной связи.
static func do_craft(p: Player, rec: Dictionary, near: MachineBase) -> Dictionary:
	var station: String = String(rec["station"])
	var out: Dictionary = {}
	for id in rec["in"].keys():
		p.inv.remove_id(id, int(rec["in"][id]))
	var out_id: int = int(rec["out"])
	var amount: int = int(rec["amount"])
	if station == "hand":
		var left: int = p.inv.add(out_id, amount)
		if left > 0:
			# Инвентарь полон — результат не пропадает, падает под ноги.
			p.spawn_item(out_id, left, p.global_position)
			out = {"text": "Скрафчено: %s ×%d — инвентарь полон, лежит под ногами." % [DB.item_name(out_id), amount],
					"tone": Tone.WARN}
		else:
			out = {"text": "Скрафчено: %s ×%d — в инвентаре." % [DB.item_name(out_id), amount], "tone": Tone.OK}
	else:
		var loaded: PackedStringArray = PackedStringArray()
		for id in rec["in"].keys():
			var n: int = int(rec["in"][id])
			var back: int = near.receive_item(id, n)
			if back > 0:
				# Станок не взял — обратно в инвентарь, ничего не теряется.
				p.inv.add(id, back)
			if n - back > 0:
				loaded.append("%s ×%d" % [DB.item_name(id), n - back])
		var si: Dictionary = InventoryPanel.STATION_INFO[station]
		var tail: String = "%s сделает %s %s (≈ %.1f с)" % [String(si["it"]), DB.item_name(out_id),
				String(si["self"]), float(rec["time"])]
		if not near.powered:
			tail += ", когда будет питание"
		out = {"text": "Загружено %s: %s. %s." % [String(si["in"]), ", ".join(loaded), tail], "tone": Tone.OK}
	Game.stats_crafted += 1
	return out


# ------------------------------------------------------------------ ИССЛЕДОВАНИЯ

## Открыть узел дерева: одиночная и хост — Tech.unlock; клиент — команда UNLOCK хосту
## (итог придёт TECH всем и CMD_RESULT нажавшему), сразу — false.
static func unlock(node: String, cb: Callable = Callable()) -> bool:
	if not Net.is_client():
		return Tech.unlock(node)
	var i: int = Tech.ORDER.find(node)
	if i < 0:
		return false
	send(Op.UNLOCK, {"node": i}, cb)
	return false


# ------------------------------------------------------------------ КЛИЕНТ: КОМАНДЫ

## Отправить команду хосту. cb(ok: bool, text: String) — по ответу. Номер запроса.
static func send(op: int, args: Dictionary, cb: Callable = Callable()) -> int:
	_req = (_req % 0xFFFF) + 1
	if op != Op.CLOSE:
		_pending[_req] = {"op": op, "us": Time.get_ticks_usec(), "cb": cb}
	stats["sent"] = int(stats.get("sent", 0)) + 1
	Net.send(NetCodec.Msg.CMD, NetCodec.encode_cmd(op, _req, NetCodec.encode_inv_args(op, args)))
	return _req


## Сколько команд ещё ждут ответа хоста.
static func pending_count() -> int:
	return _pending.size()


## Клетка сундука для команд (CELL_NONE — без сундука).
static func cell_of(c: Chest) -> int:
	if c == null or not is_instance_valid(c):
		return NetCodec.CELL_NONE
	return NetCodec.cell_idx(c.cell)


func _on_result(sender: int, payload: PackedByteArray) -> void:
	if sender != 1:
		return
	var d: Dictionary = NetCodec.decode_cmd_result(payload)
	if d.is_empty() or not _pending.has(int(d["req"])):
		return
	var e: Dictionary = _pending[int(d["req"])]
	_pending.erase(int(d["req"]))
	stats["replies"] = int(stats.get("replies", 0)) + 1
	if not bool(d["ok"]):
		stats["refused"] = int(stats.get("refused", 0)) + 1
	var rtt: PackedFloat32Array = stats.get("rtt_ms", PackedFloat32Array())
	rtt.append(float(Time.get_ticks_usec() - int(e["us"])) / 1000.0)
	stats["rtt_ms"] = rtt     # PackedFloat32Array — значение: кладём обратно
	var cb: Callable = e["cb"]
	if cb.is_valid():
		cb.call(bool(d["ok"]), String(d["reason"]))


## Клиент: содержимое сундука с хоста (открыть окно, обновить, закрыть).
func _on_chest(sender: int, payload: PackedByteArray) -> void:
	if sender != 1 or not Net.is_client():
		return
	var d: Dictionary = NetCodec.decode_chest(payload)
	if d.is_empty():
		return
	var c: Chest = World.machines.get(NetCodec.idx_cell(int(d["cell"]))) as Chest
	var flags: int = int(d["flags"])
	if c == null:
		# Сундука у клиента нет (снесён): окно, открытое на нём, закрыть.
		var open_c = UI.panel.chest if UI.panel != null else null
		if open_c != null and (not is_instance_valid(open_c) or cell_of(open_c) == int(d["cell"])):
			UI.panel.close()
		return
	var slots: Array = d["slots"]
	for i in mini(slots.size(), c.slots.size()):
		var e: Array = slots[i]
		c.slots[i] = ItemStack.new(int(e[0]), int(e[1])) if int(e[1]) > 0 else ItemStack.new()
	c.queue_redraw()
	if flags & NetCodec.CHEST_CLOSED:
		if UI.panel != null and UI.panel.chest == c:
			UI.panel.close()
		return
	if flags & NetCodec.CHEST_OPEN:
		UI.open_chest(c)
	elif UI.panel != null:
		UI.panel.queue_redraw()


## Клиент: исследования, главы и обрывки команды (общие, D10).
func _on_tech(sender: int, payload: PackedByteArray) -> void:
	if sender != 1 or not Net.is_client():
		return
	var d: Dictionary = NetCodec.decode_tech(payload)
	if d.is_empty():
		return
	Game.research = int(d["research"])
	Tech.net_apply(int(d["kind"]), int(d["arg"]), String(d["text"]))


func _on_session_ended(_reason: String = "") -> void:
	_pending.clear()
	_subs.clear()
	_sub_of.clear()
	_sent_hash.clear()
	_open_ms.clear()


# ------------------------------------------------------------------ ХОСТ: ВЫПОЛНЕНИЕ

## Хост: команда клиента. Порядок ответа: INV, CHEST (подписчикам и отправителю), CMD_RESULT —
## к ответу у клиента всё уже свежее.
func _on_cmd(sender: int, payload: PackedByteArray) -> void:
	if not Net.is_host():
		return
	var c: Dictionary = NetCodec.decode_cmd(payload)
	if c.is_empty():
		return
	var op: int = int(c["op"])
	var a: Dictionary = NetCodec.decode_inv_args(op, c["args"])
	var p: Player = _proxy(sender)
	var res: Dictionary = {"ok": false, "text": "Команда не распознана.", "chest": null}
	if p == null:
		res["text"] = "Героя нет."
	elif not a.is_empty():
		res = _exec(p, sender, op, a)
	stats["exec"] = int(stats.get("exec", 0)) + 1
	if not bool(res["ok"]):
		stats["host_refused"] = int(stats.get("host_refused", 0)) + 1
	if op == Op.CLOSE:
		return
	if p != null:
		_push_inv(sender, p)
	var ch: Chest = res.get("chest") as Chest
	if ch != null:
		_push_chest(ch, sender)
	Net.send(NetCodec.Msg.CMD_RESULT, NetCodec.encode_cmd_result(int(c["req"]), bool(res["ok"]),
			String(res["text"])), sender)


## Хост: выполнить команду героя p. Итог: {ok, text, chest} — chest, если команда его трогала
## (подписчики получат свежее содержимое).
func _exec(p: Player, peer: int, op: int, a: Dictionary) -> Dictionary:
	var res: Dictionary = {"ok": false, "text": "", "chest": null}
	match op:
		Op.MOVE, Op.SPLIT:
			return _exec_move(p, op, a)
		Op.TAKE_ALL, Op.PUT_ALL:
			var ch: Chest = _chest_near(p, int(a["cell"]))
			if ch == null:
				res["text"] = "Сундук далеко."
				res["chest"] = _chest_at(int(a["cell"]))
				return res
			var r: Dictionary = take_all(p.inv, ch) if op == Op.TAKE_ALL else put_all(p.inv, ch)
			return {"ok": int(r["n"]) > 0, "text": String(r["text"]), "chest": ch}
		Op.CRAFT:
			var idx: int = int(a["recipe"])
			if idx < 0 or idx >= DB.recipes.size():
				res["text"] = "Нет такого рецепта."
				return res
			var rec: Dictionary = DB.recipes[idx]
			for k in maxi(1, int(a["times"])):
				var chk: Dictionary = craft_check(p, rec)
				if String(chk["code"]) != "ok":
					if k == 0:
						res["text"] = String(chk["reason"])
						return res
					break
				var r2: Dictionary = do_craft(p, rec, chk["near"])
				res = {"ok": true, "text": String(r2["text"]), "chest": null}
			return res
		Op.DROP:
			var chd: Chest = null
			if int(a["from"]) == Box.CHEST:
				chd = _chest_near(p, int(a["cell"]))
				if chd == null:
					res["text"] = "Сундук далеко."
					return res
			var arr = _arr(p, chd, int(a["from"]))
			if arr == null or not _expect(arr, int(a["fslot"]), int(a["id"]), int(a["n"])):
				res["text"] = "Опоздали: в ячейке уже другое."
				res["chest"] = chd
				return res
			var r3: Dictionary = drop(p, arr, int(a["fslot"]), int(a["n"]))
			if chd != null:
				chd.queue_redraw()
			return {"ok": int(r3["n"]) > 0, "text": String(r3["text"]), "chest": chd}
		Op.SELECT:
			var s: int = int(a["slot"])
			if s < 0 or s >= p.inv.hotbar_size:
				res["text"] = "Нет такой ячейки."
				return res
			p.inv.selected = s
			return {"ok": true, "text": "", "chest": null}
		Op.UNLOCK:
			var i: int = int(a["node"])
			if i < 0 or i >= Tech.ORDER.size():
				res["text"] = "Нет такого узла."
				return res
			var node: String = String(Tech.ORDER[i])
			if Tech.is_unlocked(node):
				return {"ok": true, "text": "", "chest": null}
			if Tech.unlock(node):
				return {"ok": true, "text": "Открыто: %s — новые рецепты в крафте." % Tech.title(node), "chest": null}
			res["text"] = Tech.lock_reason(node) + "."
			return res
		Op.CLOSE:
			_unsubscribe(peer)
			return {"ok": true, "text": "", "chest": null}
	return res


## MOVE и SPLIT: проверка «опоздавшей» команды — в ячейке «откуда» должен лежать тот же
## предмет и не меньше n (иначе отказ и свежее содержимое).
func _exec_move(p: Player, op: int, a: Dictionary) -> Dictionary:
	var res: Dictionary = {"ok": false, "text": "", "chest": null}
	var from: int = int(a["from"])
	var to: int = int(a["to"])
	var fslot: int = int(a["fslot"])
	var tslot: int = int(a["tslot"])
	var ch: Chest = null
	if from == Box.CHEST or to == Box.CHEST or (tslot == NetCodec.SLOT_AUTO and int(a["cell"]) != NetCodec.CELL_NONE):
		ch = _chest_near(p, int(a["cell"]))
		if ch == null:
			res["text"] = "Сундук далеко."
			res["chest"] = _chest_at(int(a["cell"]))
			return res
	res["chest"] = ch
	var src = _arr(p, ch, from)
	if src == null:
		res["text"] = "Нет такой ячейки."
		return res
	var need: int = 1 if tslot == NetCodec.SLOT_AUTO or op == Op.SPLIT else int(a["n"])
	if not _expect(src, fslot, int(a["id"]), need):
		res["text"] = "Опоздали: в ячейке уже другое."
		return res
	if tslot == NetCodec.SLOT_AUTO and op == Op.MOVE:
		var r: Dictionary = quick_from_chest(p.inv, ch, fslot) if from == Box.CHEST else quick_from_inv(p.inv, ch, fslot)
		return {"ok": int(r["n"]) > 0, "text": String(r["text"]), "chest": ch}
	var dst = _arr(p, ch, to)
	if dst == null:
		res["text"] = "Нет такой ячейки."
		return res
	var n: int = int(a["n"])
	if op == Op.SPLIT:
		n = int(ceil(float((src[fslot] as ItemStack).count) * 0.5))
		if tslot == NetCodec.SLOT_AUTO:
			tslot = -1
			for i in dst.size():
				if (dst[i] as ItemStack).is_empty():
					tslot = i
					break
	if tslot < 0 or tslot >= dst.size():
		res["text"] = "Места нет."
		return res
	var k: int = xfer(src, fslot, dst, tslot, n, (int(a["flags"]) & NetCodec.MOVE_SWAP) != 0)
	if ch != null:
		ch.queue_redraw()
	if k <= 0:
		res["text"] = "Не переложить: ячейка занята."
		return res
	return {"ok": true, "text": "", "chest": ch}


## Ячейка arr[i] держит предмет id не меньше n штук.
static func _expect(arr: Array, i: int, id: int, n: int) -> bool:
	if i < 0 or i >= arr.size():
		return false
	var s: ItemStack = arr[i]
	return not s.is_empty() and s.id == id and s.count >= maxi(n, 1)


## Слоты контейнера героя p (рука по сети не ходит — null).
static func _arr(p: Player, ch: Chest, box: int):
	match box:
		Box.INV:
			return p.inv.slots
		Box.CHEST:
			return ch.slots if ch != null else null
	return null


func _proxy(peer: int) -> Player:
	for p in Game.players:
		if is_instance_valid(p) and p.peer_id == peer and p.net_role == Player.NetRole.PROXY:
			return p
	return null


static func _chest_at(cell: int) -> Chest:
	return World.machines.get(NetCodec.idx_cell(cell)) as Chest


## Сундук в клетке, если герой рядом (CHEST_REACH).
static func _chest_near(p: Player, cell: int) -> Chest:
	var c: Chest = _chest_at(cell)
	if c == null or c.global_position.distance_to(p.global_position) > CHEST_REACH:
		return null
	return c


# ------------------------------------------------------------------ ХОСТ: РАССЫЛКА

## Инвентарь владельцу сразу (не ждать такта NetPlayers): тот же кадр INV; сумму, по
## которой NetPlayers решает «изменился ли», сбрасываем, чтобы он не дублировал.
func _push_inv(peer: int, p: Player) -> void:
	var np = main.get("net_players") if main != null else null
	if np != null and np._st.has(peer):
		np._st[peer]["inv_sum"] = -1
		np._send_inv(peer)
		return
	var slots: Array = []
	for s in p.inv.slots:
		slots.append([s.id, s.count])
	Net.send(NetCodec.Msg.INV, NetCodec.encode_inv(slots, p.inv.selected), peer)


static func _chest_slots(c: Chest) -> Array:
	var slots: Array = []
	for s in c.slots:
		slots.append([s.id, s.count])
	return slots


## Свежий сундук всем подписчикам (и also_peer, даже если он не подписан — отказ).
func _push_chest(c: Chest, also_peer: int = 0) -> void:
	var slots: Array = _chest_slots(c)
	var payload: PackedByteArray = NetCodec.encode_chest(cell_of(c), 0, slots)
	_sent_hash[c.cell] = hash(slots)
	var subs: Dictionary = _subs.get(c.cell, {})
	for peer in subs:
		Net.send(NetCodec.Msg.CHEST, payload, int(peer))
	if also_peer > 1 and not subs.has(also_peer):
		Net.send(NetCodec.Msg.CHEST, payload, also_peer)


## Хост: прокси нажал E у сундука — окно открывается у владельца, он подписан на сундук.
static func host_open(p: Player, c: Chest) -> void:
	if inst == null or not Net.is_host() or c == null:
		return
	inst._open_for(p.peer_id, c)


func _open_for(peer: int, c: Chest) -> void:
	var now: int = Time.get_ticks_msec()
	if _sub_of.get(peer) == c.cell and now - int(_open_ms.get(peer, 0)) < REOPEN_MS:
		return
	_unsubscribe(peer)
	_open_ms[peer] = now
	_sub_of[peer] = c.cell
	if not _subs.has(c.cell):
		_subs[c.cell] = {}
	_subs[c.cell][peer] = true
	var slots: Array = _chest_slots(c)
	_sent_hash[c.cell] = hash(slots)
	Net.send(NetCodec.Msg.CHEST, NetCodec.encode_chest(cell_of(c), NetCodec.CHEST_OPEN, slots), peer)


func _unsubscribe(peer: int) -> void:
	if not _sub_of.has(peer):
		return
	var cell: Vector2i = _sub_of[peer]
	_sub_of.erase(peer)
	if _subs.has(cell):
		(_subs[cell] as Dictionary).erase(peer)
		if (_subs[cell] as Dictionary).is_empty():
			_subs.erase(cell)
			_sent_hash.erase(cell)


## Хост: сундук изменили не командой клиента (свой герой хоста в панели) — подписчикам сразу.
static func chest_changed(c) -> void:
	if inst == null or not Net.is_host() or c == null or not is_instance_valid(c) or not inst._subs.has(c.cell):
		return
	inst._push_chest(c)


## Подписчики сундука (сценарии).
func subscribers(c: Chest) -> Array:
	return (_subs.get(c.cell, {}) as Dictionary).keys()


func _on_peer_left(id: int, _info: Dictionary) -> void:
	_unsubscribe(id)
	_open_ms.erase(id)


## Хост: сундуки, открытые у клиентов, меняют ленты и манипуляторы — раз в POLL_SEC
## сверяем хэш содержимого; сундука больше нет — окно закрыть.
func _process(delta: float) -> void:
	if not Net.is_host() or _subs.is_empty():
		return
	_poll_t += delta
	if _poll_t < POLL_SEC:
		return
	_poll_t = 0.0
	for cell in _subs.keys():
		var c: Chest = World.machines.get(cell) as Chest
		if c == null:
			var payload: PackedByteArray = NetCodec.encode_chest(NetCodec.cell_idx(cell), NetCodec.CHEST_CLOSED, [])
			for peer in (_subs[cell] as Dictionary).keys():
				Net.send(NetCodec.Msg.CHEST, payload, int(peer))
				_sub_of.erase(peer)
			_subs.erase(cell)
			_sent_hash.erase(cell)
			continue
		if hash(_chest_slots(c)) != int(_sent_hash.get(cell, 0)):
			_push_chest(c)


## Хост: исследования, главы и обрывки — всем клиентам (канал 0).
func _on_node_unlocked(node: String) -> void:
	if Net.is_host():
		Net.send_on(0, NetCodec.Msg.TECH, NetCodec.encode_tech(NetCodec.TechEv.UNLOCK, Game.research,
				Tech.ORDER.find(node)))


func _on_chapter_read(i: int) -> void:
	if Net.is_host():
		Net.send_on(0, NetCodec.Msg.TECH, NetCodec.encode_tech(NetCodec.TechEv.CHAPTER, Game.research, i))


func _on_fragment_found(text: String) -> void:
	if Net.is_host():
		Net.send_on(0, NetCodec.Msg.TECH, NetCodec.encode_tech(NetCodec.TechEv.FRAGMENT, Game.research, 0, text))
