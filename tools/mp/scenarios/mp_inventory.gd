extends "res://tools/mp/scenarios/mp_players_base.gd"
## mp_inventory (ADR-002 § 4.2.7; MP-G, #91): инвентари, сундуки и крафт клиента — у хоста.
##
## Два клиента у одного тайника руины (он есть у всех: мир по сиду и снимок):
##  * E у прокси открывает окно сундука у владельца (CHEST с флагом «открыть»), хост
##    подписывает обоих;
##  * клиент 0 перекладывает кликами панели: рука — окно (стопка остаётся в ячейке,
##    пока не придёт команда move), ЛКМ/ПКМ, Shift+ЛКМ обратно — сумма у хоста та же;
##  * гонка: оба клиента в один момент тянут одну и ту же стопку — один получает её,
##    второй — отказ «Опоздали» и свежее содержимое; затем оба «Забрать всё» разом.
##    Сумма предметов (сундук + два инвентаря) не изменилась, у клиентов то же, что
##    у хоста;
##  * изменение сундука на хосте (не командой) доходит подписчикам опросом;
##  * крафт с клиента 0: сырьё списано и результат в инвентаре — на хосте и у себя;
##  * drop и select клиента 1 выполняет хост; окно закрыто — подписчиков нет.
## Замер: круг команды на петле (отправка → ответ), мс; Б на команду (CMD у клиента,
## CMD_RESULT + INV + CHEST у хоста).

const WAIT: float = 6.0
## Содержимое тайника на время сценария: [id, число] по ячейкам.
const FILL: Array = [[IDs.I.SCRAP, 9], [IDs.I.STONE, 30], [IDs.I.GLASS, 3], [IDs.I.SAND, 20], [IDs.I.COAL, 5]]
## Ячейки инвентаря для перекладывания (стартовый набор их не занимает).
const S1: int = 20
const S2: int = 21
const RACE: int = 22

var _race_ok: int = -1
var _race_text: String = ""


# ------------------------------------------------------------------ ХОСТ

func run_host() -> void:
	ok("хост + %d клиента вошли" % clients, await wait_players(1 + clients, 45.0))
	ok("прокси обоих клиентов с вводом", await wait_proxies(clients, 10.0))
	await barrier("in")
	var p0: Player = hero_of(0)
	var p1: Player = hero_of(1)
	ok("есть тайник руины", not World.ruin_caches.is_empty())
	if p0 == null or p1 == null or World.ruin_caches.is_empty():
		share_put("plan", {})
		await barrier("near")
		finish()
		return
	var ch: Chest = World.ruin_caches[0]["chest"]
	for i in Chest.CAP:
		ch.slots[i] = ItemStack.new()
	for i in FILL.size():
		ch.slots[i] = ItemStack.new(int(FILL[i][0]), int(FILL[i][1]))
	# Свой герой хоста — подальше: ничего не подбирает и сундук не трогает.
	var sx: int = World.world_to_cell(World.spawn_point).x
	player.global_position = surface_stand(sx - 50)
	player.vel = Vector2.ZERO
	var spots: Array = _stands(ch.global_position)
	ok("у тайника есть два места", spots.size() >= 2, str(spots))
	if spots.size() < 2:
		share_put("plan", {})
		await barrier("near")
		finish()
		return
	ok("клиент 0 у тайника", await teleport_proxy(p0, spots[0]))
	ok("клиент 1 у тайника", await teleport_proxy(p1, spots[1]))
	share_put("plan", {"cell": ch.cell})
	await barrier("near")

	# --- E у прокси открывает окно у владельца.
	await barrier("open")
	var subs: Array = scene.net_inv.subscribers(ch)
	ok("хост: оба клиента подписаны на сундук", subs.size() == 2 and subs.has(p0.peer_id) and subs.has(p1.peer_id),
			str(subs))
	var t0: Dictionary = _totals(ch, [p0, p1])
	await barrier("ui")

	# --- Клиент 0 перекладывает кликами панели.
	await barrier("ui_done")
	ok("хост: после кликов клиента 0 сумма та же", _totals(ch, [p0, p1]) == t0, _diff(t0, _totals(ch, [p0, p1])))
	ok("хост: камень вернулся в свою ячейку сундука", ch.slots[1].id == IDs.I.STONE and ch.slots[1].count == 30,
			str(ch.slots[1]))
	ok("хост: ячейки клиента 0 снова пусты", p0.inv.slots[S1].is_empty() and p0.inv.slots[S2].is_empty())

	# --- Гонка: одна стопка, два клиента.
	var refused0: int = int(InvOps.stats.get("host_refused", 0))
	await barrier("race")
	await barrier("pulled")
	var t1: Dictionary = _totals(ch, [p0, p1])
	ok("хост: сумма предметов не изменилась (сундук + 2 инвентаря)", t1 == t0, _diff(t0, t1))
	var r0 = share_get("race0")
	var r1 = share_get("race1")
	ok("хост: стопку получил ровно один клиент", r0 is bool and r1 is bool and int(r0) + int(r1) == 1,
			"клиент 0 %s, клиент 1 %s" % [str(r0), str(r1)])
	ok("хост: опоздавшая команда отклонена", int(InvOps.stats.get("host_refused", 0)) - refused0 >= 1,
			"отказов %d" % (int(InvOps.stats.get("host_refused", 0)) - refused0))
	ok("хост: «Забрать всё» обоих опустошило сундук", _chest_total(ch) == 0, "в сундуке %d" % _chest_total(ch))
	share_put("after", {"chest": _slots(ch.slots), "inv0": _slots(p0.inv.slots), "inv1": _slots(p1.inv.slots)})
	await barrier("after")
	await barrier("compared")

	# --- Сундук изменили на хосте не командой — подписчикам опросом.
	ch.slots[5] = ItemStack.new(IDs.I.LAMP, 2)
	await barrier("poll")

	# --- Крафт с клиента 0.
	var ore0: int = p0.inv.count_of(IDs.I.COPPER_ORE)
	var ingot0: int = p0.inv.count_of(IDs.I.COPPER_INGOT)
	var crafted0: int = Game.stats_crafted
	await barrier("craft")
	await barrier("crafted")
	ok("хост: крафт клиента — сырьё списано, слиток в инвентаре прокси",
			p0.inv.count_of(IDs.I.COPPER_ORE) == ore0 - 2 and p0.inv.count_of(IDs.I.COPPER_INGOT) == ingot0 + 1,
			"руда %d → %d, слитки %d → %d" % [ore0, p0.inv.count_of(IDs.I.COPPER_ORE), ingot0,
			p0.inv.count_of(IDs.I.COPPER_INGOT)])
	ok("хост: крафт посчитан в статистике", Game.stats_crafted == crafted0 + 1)

	# --- drop и select клиента 1.
	var coal_items0: int = _ground(IDs.I.COAL)
	await barrier("drop")
	ok("хост: выброшенный клиентом 1 уголь лежит на земле",
			await wait_until(func() -> bool: return _ground(IDs.I.COAL) > coal_items0, WAIT))
	ok("хост: select клиента 1 — ячейка хотбара 4", await wait_until(func() -> bool: return p1.inv.selected == 4, WAIT),
			"ячейка %d" % p1.inv.selected)
	await barrier("dropped")

	# --- Окна закрыты — подписчиков нет.
	await barrier("close")
	ok("хост: окна закрыты — подписчиков нет",
			await wait_until(func() -> bool: return scene.net_inv.subscribers(ch).is_empty(), WAIT),
			str(scene.net_inv.subscribers(ch)))
	var rb: int = int(Net.sent_bytes.get(NetCodec.Msg.CMD_RESULT, 0))
	var ex: int = int(InvOps.stats.get("exec", 0))
	if ex > 0:
		print("  ЗАМЕР хост: команд выполнено %d, отказано %d; CMD_RESULT в среднем %.1f Б; INV %d Б, CHEST (24 ячейки) %d Б" % [
				ex, int(InvOps.stats.get("host_refused", 0)), float(rb) / float(ex),
				1 + NetCodec.encode_inv(_slots(p0.inv.slots), 0).size(),
				1 + NetCodec.encode_chest(0, 0, _slots(ch.slots)).size()])
	await barrier("done")
	share_clear(["plan", "race0", "race1", "after"])
	finish()


## Места у сундука, где герой стоит и дотягивается по E (< 40 px).
func _stands(at: Vector2) -> Array:
	var out: Array = []
	for o in [Vector2(14, -4), Vector2(-14, -4), Vector2(0, -4), Vector2(14, -20), Vector2(-14, -20),
			Vector2(0, -20), Vector2(24, -4), Vector2(-24, -4)]:
		var p: Vector2 = at + o
		if not World.rect_solid(Rect2(p - Player.SIZE * 0.5, Player.SIZE)) and _no_terminal(p):
			out.append(p)
	return out


## Терминал рядом может стать целью E (Player.interact_target, #116) — такие места не берём:
## сценарий проверяет сундук по сети, а не выбор цели.
static func _no_terminal(p: Vector2) -> bool:
	for t in World.terminals:
		if World.cell_to_world(t).distance_to(p) < 44.0:
			return false
	return true


## Сумма каждого предмета: сундук + инвентари героев.
static func _totals(ch: Chest, heroes: Array) -> Dictionary:
	var t: Dictionary = {}
	var all: Array = [ch.slots]
	for h in heroes:
		all.append((h as Player).inv.slots)
	for arr in all:
		for s in arr:
			if not s.is_empty():
				t[s.id] = int(t.get(s.id, 0)) + s.count
	return t


static func _diff(a: Dictionary, b: Dictionary) -> String:
	var out: PackedStringArray = PackedStringArray()
	for k in a.keys() + b.keys():
		if int(a.get(k, 0)) != int(b.get(k, 0)) and not out.has("%s %d→%d" % [DB.item_name(k), int(a.get(k, 0)), int(b.get(k, 0))]):
			out.append("%s %d→%d" % [DB.item_name(k), int(a.get(k, 0)), int(b.get(k, 0))])
	return ", ".join(out)


static func _chest_total(ch: Chest) -> int:
	var n: int = 0
	for s in ch.slots:
		n += s.count
	return n


static func _slots(arr: Array) -> Array:
	var out: Array = []
	for s in arr:
		out.append([s.id, s.count] if not s.is_empty() else [0, 0])
	return out


## Предметы id на земле (ItemEntity в сцене).
func _ground(id: int) -> int:
	var n: int = 0
	for c in get_tree().current_scene.get_children():
		if c is ItemEntity and c.item_id == id:
			n += 1
	return n


# ------------------------------------------------------------------ КЛИЕНТ

func run_client(i: int) -> void:
	await barrier("in")
	var panel: InventoryPanel = UI.panel
	var plan = null
	await barrier("near")
	plan = share_get("plan")
	if not (plan is Dictionary) or (plan as Dictionary).is_empty():
		finish()
		return
	var ch: Chest = World.machines.get(plan["cell"]) as Chest
	ok("тайник есть и у клиента", ch != null, str(plan["cell"]))

	# --- E своим героем: окно сундука открывает хост.
	player.invuln = 1.0e9
	await wait(0.3)
	hold(KEY_E)
	var opened: bool = await wait_until(func() -> bool: return panel.visible and panel.chest == ch, WAIT)
	release(KEY_E)
	clear_input()
	ok("E у сундука: окно открыто у клиента (CHEST с хоста)", opened)
	ok("содержимое сундука — с хоста", ch != null and ch.slots[0].id == IDs.I.SCRAP and ch.slots[0].count == 9
			and ch.slots[1].id == IDs.I.STONE and ch.slots[1].count == 30, "" if ch == null else str(ch.slots.slice(0, 5)))
	await barrier("open")
	await barrier("ui")

	if i == 0 and opened:
		await _ui_flow(panel, ch)
	await barrier("ui_done")

	# --- Гонка: оба в один момент тянут камень (ячейка 1, 30 шт.) в свою ячейку.
	await barrier("race")
	if opened:
		InvOps.send(NetCodec.InvOp.MOVE, {"from": NetCodec.Box.CHEST, "fslot": 1, "to": NetCodec.Box.INV,
				"tslot": RACE, "id": IDs.I.STONE, "n": 30, "flags": 0, "cell": InvOps.cell_of(ch)},
				func(okk: bool, text: String) -> void:
					_race_ok = 1 if okk else 0
					_race_text = text)
		panel.take_all()
	var replied: bool = await wait_until(func() -> bool: return InvOps.pending_count() == 0, WAIT)
	ok("гонка: ответы хоста пришли", replied and _race_ok >= 0)
	share_put("race%d" % i, _race_ok == 1)
	if _race_ok == 0:
		ok("опоздавшему — отказ словами", _race_text.begins_with("Опоздали"), _race_text)
	print("  клиент %d: стопка камня — %s" % [i, "получена" if _race_ok == 1 else "отказ «%s»" % _race_text])
	await barrier("pulled")
	await barrier("after")
	var after = share_get("after")
	if after is Dictionary and ch != null:
		var same: bool = await wait_until(func() -> bool:
			return _slots(ch.slots) == after["chest"] and _slots(player.inv.slots) == after["inv%d" % i], WAIT)
		ok("у клиента сундук и инвентарь — как у хоста", same,
				"сундук %s / %s" % [str(_slots(ch.slots).slice(0, 6)), str((after["chest"] as Array).slice(0, 6))])
	await barrier("compared")

	# --- Сундук изменили на хосте — опрос подписчикам.
	await barrier("poll")
	ok("изменение сундука на хосте дошло (опрос подписчиков)", ch != null and await wait_until(func() -> bool:
		return ch.slots[5].id == IDs.I.LAMP and ch.slots[5].count == 2, WAIT))

	# --- Крафт с клиента 0: «Ручная выплавка меди» (2 руды → слиток).
	await barrier("craft")
	if i == 0:
		var rec: Dictionary = {}
		for r in DB.recipes:
			if String(r["name"]) == "Ручная выплавка меди":
				rec = r
		var ore0: int = player.inv.count_of(IDs.I.COPPER_ORE)
		var ingot0: int = player.inv.count_of(IDs.I.COPPER_INGOT)
		var rtt0: int = (InvOps.stats["rtt_ms"] as PackedFloat32Array).size()
		panel._craft(rec)
		ok("крафт: команда ушла хосту", InvOps.pending_count() == 1)
		await wait_until(func() -> bool: return InvOps.pending_count() == 0, WAIT)
		ok("крафт с клиента: слиток в инвентаре, руда списана (INV с хоста)",
				player.inv.count_of(IDs.I.COPPER_INGOT) == ingot0 + 1 and player.inv.count_of(IDs.I.COPPER_ORE) == ore0 - 2,
				"руда %d → %d" % [ore0, player.inv.count_of(IDs.I.COPPER_ORE)])
		ok("крафт: обратная связь с хоста", panel.last_feedback.begins_with("Скрафчено"), panel.last_feedback)
		var rtt: PackedFloat32Array = InvOps.stats["rtt_ms"]
		if rtt.size() > rtt0:
			print("  ЗАМЕР круг команды крафта: %.1f мс" % rtt[rtt.size() - 1])
	await barrier("crafted")

	# --- drop и select клиента 1.
	await barrier("drop")
	if i == 1:
		var ci: int = -1
		for k in player.inv.size:
			if player.inv.slots[k].id == IDs.I.COAL:
				ci = k
				break
		ok("у клиента 1 есть уголь", ci >= 0)
		if ci >= 0:
			var res: Array = []
			InvOps.send(NetCodec.InvOp.DROP, {"from": NetCodec.Box.INV, "fslot": ci, "id": IDs.I.COAL, "n": 1,
					"cell": NetCodec.CELL_NONE}, func(okk: bool, text: String) -> void: res.append([okk, text]))
			await wait_until(func() -> bool: return not res.is_empty(), WAIT)
			ok("drop: хост выполнил", not res.is_empty() and bool(res[0][0]), str(res))
		InvOps.select(player, 4)
	await barrier("dropped")

	# --- Закрыть окно.
	await barrier("close")
	panel.close()
	ok("окно закрыто", not panel.visible)
	var rtt_all: PackedFloat32Array = InvOps.stats["rtt_ms"]
	if not rtt_all.is_empty():
		var sent: int = int(InvOps.stats.get("sent", 0))
		print("  ЗАМЕР клиент %d: команд %d, ответов %d, отказов %d; круг команды p50 %.1f мс, p95 %.1f мс, макс %.1f мс; CMD в среднем %.1f Б" % [
				i, sent, int(InvOps.stats.get("replies", 0)), int(InvOps.stats.get("refused", 0)),
				_p(rtt_all, 0.5), p95(rtt_all), vmax(rtt_all),
				float(Net.sent_bytes.get(NetCodec.Msg.CMD, 0)) / float(maxi(sent, 1))])
	await barrier("done")
	finish()


## Клиент 0: перекладывание кликами панели. Рука — окно: стопка в своей ячейке, пока
## хост не выполнил move; прогноз сразу, ответ хоста подтверждает.
func _ui_flow(panel: InventoryPanel, ch: Chest) -> void:
	# ЛКМ по хламу: в руке 9, в ячейке сундука по-прежнему 9 (рисуется пустой).
	panel._click_chest(0, false)
	ok("ЛКМ: хлам в руке, ячейка сундука не тронута (рука — окно)",
			panel.held.id == IDs.I.SCRAP and panel.held.count == 9 and ch.slots[0].count == 9
			and panel._shown(ch.slots, NetCodec.Box.CHEST, 0).is_empty(), str(panel.held))
	ok("до команды хосту ничего не ушло", InvOps.pending_count() == 0)
	panel._click_inv(S1, false)
	ok("ЛКМ в ячейку инвентаря: команда move ушла, прогноз сразу",
			InvOps.pending_count() == 1 and panel.held.is_empty() and player.inv.slots[S1].id == IDs.I.SCRAP
			and ch.slots[0].is_empty())
	await wait_until(func() -> bool: return InvOps.pending_count() == 0, WAIT)
	ok("хост подтвердил: хлам в инвентаре, сундук без него",
			player.inv.slots[S1].id == IDs.I.SCRAP and player.inv.slots[S1].count == 9 and ch.slots[0].is_empty())
	# ПКМ: половина камня в руку, ПКМ по пустой ячейке — одна штука, ЛКМ туда же — остальное.
	panel._click_chest(1, true)
	ok("ПКМ: в руке половина камня", panel.held.id == IDs.I.STONE and panel.held.count == 15, str(panel.held))
	panel._click_inv(S2, true)
	ok("ПКМ: одна штука в ячейку, в руке 14", panel.held.count == 14 and player.inv.slots[S2].count == 1)
	panel._click_inv(S2, false)
	ok("ЛКМ: остальное туда же, рука пуста", panel.held.is_empty() and player.inv.slots[S2].count == 15)
	await wait_until(func() -> bool: return InvOps.pending_count() == 0, WAIT)
	ok("хост подтвердил: 15 камня у клиента, 15 в сундуке",
			player.inv.slots[S2].count == 15 and ch.slots[1].count == 15, "%d / %d" % [player.inv.slots[S2].count,
			ch.slots[1].count])
	# Shift+ЛКМ — обратно в сундук (что влезет — в свои стопки).
	panel.quick_move_inv(S1)
	panel.quick_move_inv(S2)
	await wait_until(func() -> bool: return InvOps.pending_count() == 0, WAIT)
	ok("Shift+ЛКМ: хлам и камень вернулись в сундук",
			player.inv.slots[S1].is_empty() and player.inv.slots[S2].is_empty() and ch.slots[0].id == IDs.I.SCRAP
			and ch.slots[1].count == 30, "%s %s" % [str(ch.slots[0]), str(ch.slots[1])])
	ok("обратная связь Shift+ЛКМ — с хоста", panel.last_feedback.begins_with("Переложено в сундук"), panel.last_feedback)


static func _p(v: PackedFloat32Array, q: float) -> float:
	var s: PackedFloat32Array = v.duplicate()
	s.sort()
	return s[clampi(int(ceil(q * s.size())) - 1, 0, s.size() - 1)]
