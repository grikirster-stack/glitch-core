extends MpScenarioBase
## mp_factory (ADR-002, § 4.2.1, § 4.2.4, § 4.3, § 4.10; MP-E, #90): машины и предметы
## по сети. Хост и два клиента.
##
## 1. Завод: бур над столбом из ORE_N клеток железной руды (под ним — бедрок), ТЭЦ с
##    углём, две ленты вправо, сундук. Постройки появляются у обоих клиентов
##    (MACHINE_ADD), у клиента бур под питанием, прогресс такта растёт между пакетами,
##    предметы едут по лентам и между пакетами (экстраполяция). Своя логика машин у
##    клиента не идёт: сундук клиента не наполняется, бур клиента не копает (тайлы —
##    только дельтами хоста, хэши равны). Сумма у хоста: в сундуке ровно ORE_N руды,
##    на лентах, в буре и на земле её нет — без дублей и потерь.
## 2. Снос и постройка: лента разрушена (destroy) — пропала у всех, на её месте новая —
##    появилась у всех, направление то же.
## 3. Турель стреляет по фантому — у клиентов дуга (World.turret_fired) в ближайший такт.
## 4. Предметы на земле: три камня падают рядом и сливаются у хоста в один (3 шт.) —
##    у клиента одна марионетка на 3 шт. там же; убран у хоста — пропал у клиента.
## 5. Замер: база из 130 машин § 9.1 (60 лент с предметами, 20 манипуляторов, 10 буров,
##    18 сундуков, 6 ТЭЦ, 4 плавильни, 4 сборщика, 4 турели, 4 прожектора) в зоне
##    интереса: Б/с машин хост → клиент, сбор net_state на хосте, мкс/такт.
##
## Пока сеть игроков (MP-D, #89) не в main, постройку за клиента делает хост тем же
## MachineBase.place_machine, каким её сделает прокси-герой клиента (D3: действия —
## на хосте обычным кодом Player). Данные клиент сообщает хосту именем барьера.

const JS = preload("res://tools/mp/scenarios/mp_join_snapshot.gd")
const ORE_N: int = 5
const MEASURE_S: float = 5.0
## Оценка ADR (§ 4.3) для машин базы: 60 лент × 10 + 70 × 6 Б при 4 Гц.
const ADR_MACHINES_BPS: int = 4080
## Предел сбора net_state на хосте, мкс за машинный такт (4 Гц): 5 мс — 2 % секунды
## кадров хоста даже на загруженной машине CI (замер на Windows — ≈ 1 мс на 145 машин).
const GATHER_LIMIT_US: int = 5000

var _sx: int = 0            ## клетка бура
var _g: int = 0             ## ряд пола (бур стоит в ряду _g − 1)
var _bx: int = 0            ## левый край базы замера


func _layout() -> void:
	_g = World.beacon_cell.y + 1
	_sx = World.beacon_cell.x + 20
	_bx = World.beacon_cell.x + 22


func _cell(dx: int) -> Vector2i:
	return Vector2i(_sx + dx, _g - 1)


# ------------------------------------------------------------------ ХОСТ

func run_host() -> void:
	_layout()
	var in_game: bool = await wait_players(1 + clients, 30.0)
	ok("клиенты подключились", in_game, "игроков %d" % Net.peers.size())
	await barrier("joined", -1, 30.0)
	var nm: NetMachines = Game.net_machines

	# --- 1. Завод: бур → лента → лента → сундук, ТЭЦ слева.
	_clear(_sx - 2, _sx + 27, _g - 11, _g - 1)
	for x in range(_sx - 2, _sx + 28):
		if World.get_tile(x, _g) == IDs.T.AIR or DB.is_liquid(World.get_tile(x, _g)):
			World.set_tile(x, _g, IDs.T.STEEL)
	for k in ORE_N:
		World.set_tile(_sx, _g + k, IDs.T.IRON_ORE)
	World.set_tile(_sx, _g + ORE_N, IDs.T.BEDROCK)
	var placed: int = 0
	for kv in [["CoalGen", -1], ["Belt", 1], ["Belt", 2], ["Chest", 3], ["Drill", 0]]:
		if MachineBase.place_machine(String(kv[0]), _cell(int(kv[1]))):
			placed += 1
	ok("хост: завод поставлен (ТЭЦ, бур, 2 ленты, сундук)", placed == 5, "%d из 5" % placed)
	var gen: CoalGen = World.machines.get(_cell(-1))
	var drill: Drill = World.machines.get(_cell(0))
	var chest: Chest = World.machines.get(_cell(3))
	gen.add_fuel(CoalGen.FUEL_MAX_UNITS)
	await barrier("built", -1, 30.0)

	# Руда идёт: бур выкапывает столб, всё уезжает в сундук.
	var flowed: bool = await wait_until(func() -> bool:
			return _chest_count(chest, IDs.I.IRON_ORE) >= ORE_N and _belt_items() == 0, 40.0)
	ok("хост: бур выкопал столб, руда в сундуке", flowed,
			"в сундуке %d из %d" % [_chest_count(chest, IDs.I.IRON_ORE), ORE_N])
	await wait(1.0)                         # лишнего бур не выдал
	var in_chest: int = _chest_count(chest, IDs.I.IRON_ORE)
	var on_ground: int = _ground_count(IDs.I.IRON_ORE)
	var in_drill: int = int(drill._output.get(IDs.I.IRON_ORE, 0))
	ok("хост: сумма руды без дублей и потерь (сундук %d, ленты %d, бур %d, земля %d = %d)" % [
			in_chest, _belt_items(), in_drill, on_ground, ORE_N],
			in_chest + _belt_items() + in_drill + on_ground == ORE_N and in_chest == ORE_N)
	var mined: int = 0
	for k in ORE_N:
		if World.get_tile(_sx, _g + k) == IDs.T.AIR:
			mined += 1
	ok("хост: столб руды выкопан (%d клеток)" % mined, mined == ORE_N)
	await barrier("flowed", -1, 60.0)

	# --- 2. Снос и постройка заново: видны всем.
	var b2 = World.machines.get(_cell(2))
	if b2 != null:
		b2.destroy()
	await barrier("destroyed", -1, 20.0)
	await barrier("gone", -1, 20.0)
	var rebuilt: bool = MachineBase.place_machine("Belt", _cell(2))
	if rebuilt:
		World.machines[_cell(2)].dir = 3
	ok("хост: на месте ленты новая (вверх)", rebuilt)
	await barrier("rebuilt", -1, 20.0)

	# --- 3. Турель стреляет — у клиентов дуга в ближайший такт.
	var tg_ok: bool = MachineBase.place_machine("CoalGen", _cell(6)) and MachineBase.place_machine("Turret", _cell(7))
	ok("хост: турель с ТЭЦ поставлена", tg_ok)
	if tg_ok:
		(World.machines[_cell(6)] as CoalGen).add_fuel(4)
	var tur = World.machines.get(_cell(7))
	await barrier("turret_ready", -1, 20.0)
	var ph = spawn_phantom_at(World.cell_to_world(_cell(11)) + Vector2(0.0, -4.0), "echo")
	ok("хост: фантом у турели", ph != null)
	var shot: bool = await wait_until(func() -> bool: return tur != null and tur.shots > 0, 10.0)
	ok("хост: турель выстрелила (%d)" % (tur.shots if tur != null else 0), shot)
	if ph != null and is_instance_valid(ph):
		ph.queue_free()
	await barrier("shot", -1, 20.0)

	# --- 4. Предметы на земле: три камня сливаются в один.
	var drop_at: Vector2 = World.cell_to_world(_cell(14)) + Vector2(0.0, -40.0)
	for k in 3:
		_drop(IDs.I.STONE, 1, drop_at + Vector2(float(k * 6 - 6), float(-k * 10)))
	var merged: bool = await wait_until(func() -> bool:
			var l: Array = _stones_near()
			return l.size() == 1 and l[0].count == 3 and l[0].grounded, 10.0)
	ok("хост: три камня упали и слились в один (3 шт.)", merged,
			"куч %d" % _stones_near().size())
	var stone = _stones_near()[0] if merged else null
	# Клиенты присылают «ip:<x>:<y>:<шт>» своей марионетки — сверяем с хостом.
	for i in clients:
		var rep: String = await _wait_report("ip%d:" % i, 15.0)
		var p: PackedStringArray = rep.split(":")
		if stone != null and p.size() >= 4:
			var cp: Vector2 = Vector2(float(p[1]), float(p[2]))
			ok("c%d: марионетка камня там же, где у хоста (%.1f px), %s шт." % [i,
					cp.distance_to(stone.global_position), p[3]],
					cp.distance_to(stone.global_position) <= float(World.TILE) and int(p[3]) == 3)
		else:
			ok("c%d: прислал марионетку камня" % i, false, rep)
		await mp().barrier(rep, 1, 5.0)
	if stone != null:
		print("  хост: камень #%d убран; все камни хоста %s" % [stone.net_id, str(_stones_near().map(func(e): return [e.net_id, e.count, e.global_position, e.age]))])
		stone.queue_free()
	await barrier("items_gone", -1, 20.0)

	# --- 5. Замер: база из 130 машин в зоне интереса.
	var base: Array = _build_base()
	ok("хост: база из 130 машин построена", base.size() == 130, "%d" % base.size())
	await wait(1.0)                         # события постройки и первый полный обход прошли
	var pid: int = _peer_of(0)
	nm.reset_traffic()
	var b0: int = int(nm.peer_bytes.get(pid, 0))
	var t0: float = now()
	var feed_t: float = 0.0
	while now() - t0 < MEASURE_S:
		await wait(0.1)
		feed_t += 0.1
		if feed_t >= 0.5:
			feed_t = 0.0
			_feed_base()
	var dt: float = now() - t0
	var bps: float = float(int(nm.peer_bytes.get(pid, 0)) - b0) / dt
	var sbps: float = float(nm.state_bytes) / dt / float(maxi(1, clients))
	var avg_us: float = float(nm.gather_us_sum) / float(maxi(1, nm.gather_n))
	print("  ЗАМЕР база %d машин (всего в мире %d) в зоне: машины хост → клиент %.0f Б/с (net_state %.0f Б/с, оценка ADR %d), записей %d за %.1f с; сбор net_state %.0f мкс/такт (худший %d, из последнего постройка %d, машин %d, тактов %d); мягкий предел — %s" % [
			base.size(), World.machines.size(), bps, sbps, ADR_MACHINES_BPS, nm.states_tx, dt, avg_us,
			nm.gather_us_max, nm.build_us, nm.gather_machines, nm.gather_n, "1 Гц" if nm.slow else "не достигнут"])
	ok("хост: машины базы — меньше мягкого предела %d Б/с" % Net.SOFT_BUDGET, bps < float(Net.SOFT_BUDGET),
			"%.0f Б/с" % bps)
	ok("хост: машины идут 4 Гц (тактов сбора %d за %.1f с)" % [nm.gather_n, dt],
			absi(nm.gather_n - roundi(dt * Net.MACHINE_HZ)) <= 1)
	ok("хост: сбор net_state ≤ %d мкс/такт (%.0f)" % [GATHER_LIMIT_US, avg_us], avg_us <= float(GATHER_LIMIT_US))
	await barrier("measured", -1, 30.0)
	# Сверка: тайлы, вода и постройки у клиентов как у хоста.
	await JS.host_check(self)
	await _compare_all()
	await barrier("done", -1, 30.0)
	finish()


## Хост: хэши всех клиентов (барьеры «h:тайлы:вода:постройки») против своих.
func _compare_all() -> void:
	var mine: String = JS.HASH_PREFIX + ":".join(PackedStringArray(JS.hashes()))
	var names: Dictionary = {}
	var t0: float = now()
	while now() - t0 < 30.0:
		names = {}
		var total: int = 0
		for n in mp()._arrived.keys():
			if String(n).begins_with(JS.HASH_PREFIX):
				names[n] = mp()._arrived[n].size()
				total += int(names[n])
		if total >= clients:
			break
		await wait(0.05)
	var total_ok: int = 0
	for n in names:
		total_ok += int(names[n]) if String(n) == mine else 0
	ok("хэши тайлов, воды и построек у всех клиентов как у хоста (%d из %d)" % [total_ok, clients],
			total_ok == clients, "хост %s, клиенты %s" % [mine, str(names.keys())])
	for n in names:
		await mp().barrier(String(n), int(names[n]), 5.0)


func _clear(x0: int, x1: int, y0: int, y1: int) -> void:
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			if World.machines.has(Vector2i(x, y)):
				continue
			World.set_tile(x, y, IDs.T.AIR)


func _drop(id: int, n: int, pos: Vector2) -> void:
	var e: ItemEntity = ItemEntity.new()
	e.item_id = id
	e.count = n
	e.global_position = pos
	World.add_world_node(e)
	e.vel = Vector2.ZERO


static func _chest_count(ch, id: int) -> int:
	var n: int = 0
	if ch == null or not is_instance_valid(ch):
		return 0
	for s in ch.slots:
		if s.id == id:
			n += s.count
	return n


func _belt_items() -> int:
	var n: int = 0
	for dx in [1, 2]:
		var b = World.belts.get(_cell(dx))
		if b != null:
			for it in b.items:
				n += int(it["count"])
	return n


func _ground_items(id: int) -> Array:
	var out: Array = []
	for e in Save._item_nodes():
		if e.item_id == id:
			out.append(e)
	return out


## Камни у точки сброса (§ 4 сценария): другие камни мира не мешают проверке.
func _stones_near() -> Array:
	var x: float = World.cell_to_world(_cell(14)).x
	return _ground_items(IDs.I.STONE).filter(func(e): return absf(e.global_position.x - x) <= 48.0)


func _ground_count(id: int) -> int:
	var n: int = 0
	for e in _ground_items(id):
		n += e.count
	return n


## Хост: id пира клиента i (по uid харнесса).
func _peer_of(i: int) -> int:
	for id in Net.peers:
		if int(Net.peers[id]["uid"]) == client_uid(i):
			return int(id)
	return 0


## Хост: дождаться барьера клиента с этим префиксом (данные — в имени).
func _wait_report(prefix: String, timeout: float) -> String:
	var t0: float = now()
	while now() - t0 < timeout:
		for n in mp()._arrived.keys():
			if String(n).begins_with(prefix):
				return String(n)
		await wait(0.05)
	return ""


## База § 9.1 из 130 машин: строки сверху вниз, 22 столбца.
func _build_base() -> Array:
	var rows: Array = [
		_row("Belt", 20) + ["Chest", "Chest"],
		_row("Belt", 20) + ["Chest", "Chest"],
		_row("Belt", 20) + ["Chest", "Chest"],
		_row("Drill", 10) + _row("CoalGen", 6) + _row("Smelter", 4) + ["Chest", "Chest"],
		_row("Inserter", 20) + ["Chest", "Chest"],
		_row("Assembler", 4) + _row("Turret", 4) + _row("Floodlight", 4) + _row("Chest", 8),
	]
	# Под бурами базы — бедрок: они работают (такт идёт), но мир не копают —
	# сверка тайлов в конце не гоняется за ними.
	for i in 10:
		World.set_tile(_bx + i, _g, IDs.T.BEDROCK)
	var out: Array = []
	var full: int = 0
	for r in rows.size():
		var y: int = _g - 10 + r
		for i in rows[r].size():
			var c: Vector2i = Vector2i(_bx + i, y)
			if not MachineBase.place_machine(String(rows[r][i]), c):
				continue
			var m = World.machines[c]
			out.append(m)
			if m is CoalGen:
				m.add_fuel(CoalGen.FUEL_MAX_UNITS)
			elif m is Smelter:
				m.receive_item(IDs.I.IRON_ORE, 20)
			elif m is Chest and full < 10:
				full += 1
				for s in m.slots:
					s.id = IDs.I.STONE
					s.count = DB.item_max_stack(IDs.I.STONE)
	_feed_base()
	return out


static func _row(kind: String, n: int) -> Array:
	var a: Array = []
	for i in n:
		a.append(kind)
	return a


## Подбросить руду на начало каждой ленты базы (поток не иссякает).
func _feed_base() -> void:
	for r in 3:
		for i in [0, 5, 10]:
			var b = World.belts.get(Vector2i(_bx + i, _g - 10 + r))
			if b != null:
				b.add_item(IDs.I.IRON_ORE, 1)


# ------------------------------------------------------------------ КЛИЕНТ

func run_client(i: int) -> void:
	_layout()
	var nw: NetWorld = Game.net_world
	var nm: NetMachines = Game.net_machines
	var got: bool = await wait_until(func() -> bool: return nw.is_joined, 20.0)
	ok("c%d: снимок получен" % i, got)
	await barrier("joined")
	await barrier("built")
	# Постройки хоста пришли событиями.
	var kinds: Array = [["CoalGen", -1], ["Drill", 0], ["Belt", 1], ["Belt", 2], ["Chest", 3]]
	var arrived: bool = await wait_until(func() -> bool:
			for kv in kinds:
				var m = World.machines.get(_cell(int(kv[1])))
				if m == null or String(m.kind) != String(kv[0]):
					return false
			return true, 5.0)
	ok("c%d: завод хоста появился (MACHINE_ADD %d)" % [i, nm.adds_rx], arrived)
	var drill = World.machines.get(_cell(0))
	var b1 = World.belts.get(_cell(1))
	var chest = World.machines.get(_cell(3))
	if not arrived or drill == null or b1 == null:
		await barrier("flowed")
		await barrier("destroyed")
		await barrier("gone")
		await barrier("rebuilt")
		await barrier("turret_ready")
		await barrier("shot")
		await barrier("ip%d:0:0:0" % i)
		await barrier("items_gone")
		await barrier("measured")
		await JS.client_report(self, i)
		await barrier("done")
		finish()
		return
	# Пока руда едет: прогресс бура растёт, предметы движутся и между пакетами.
	var seen: Dictionary = {"powered": false, "rises": 0, "items": 0, "glide": 0}
	var last: Array = [drill.cycle_fraction(), -1.0, nm.states_rx]
	var t0: float = now()
	while now() - t0 < 30.0 and (seen["rises"] < 3 or seen["glide"] < 5 or not seen["powered"]):
		await get_tree().physics_frame
		if drill.powered:
			seen["powered"] = true
		var f: float = drill.cycle_fraction()
		if f > float(last[0]) + 0.01:
			seen["rises"] += 1
		last[0] = f
		var front: float = float(b1.items[0]["pos"]) if not b1.items.is_empty() else -1.0
		seen["items"] = maxi(int(seen["items"]), b1.items.size())
		if front > float(last[1]) and float(last[1]) >= 0.0 and nm.states_rx == int(last[2]):
			seen["glide"] += 1             # сдвинулся без пакета — экстраполяция
		last[1] = front
		last[2] = nm.states_rx
	ok("c%d: бур под питанием (net_state)" % i, seen["powered"])
	ok("c%d: прогресс такта бура растёт (%d раз)" % [i, seen["rises"]], int(seen["rises"]) >= 3)
	ok("c%d: предметы едут по ленте (до %d), между пакетами — сами (%d кадров)" % [i,
			seen["items"], seen["glide"]], int(seen["items"]) > 0 and int(seen["glide"]) >= 5)
	await barrier("flowed")
	# Своя логика машин у клиента не шла: сундук не наполнился, ленты опустели по хосту.
	var empty: bool = await wait_until(func() -> bool:
			return World.belts.get(_cell(1)).items.is_empty() and World.belts.get(_cell(2)).items.is_empty(), 3.0)
	ok("c%d: ленты опустели вслед за хостом" % i, empty)
	ok("c%d: сундук клиента сам не наполнялся (руда приходит только к хосту)" % i,
			_chest_count(chest, IDs.I.IRON_ORE) == 0, "%d" % _chest_count(chest, IDs.I.IRON_ORE))
	var col_air: bool = true
	for k in ORE_N:
		col_air = col_air and World.get_tile(_sx, _g + k) == IDs.T.AIR
	ok("c%d: столб руды выкопан и у клиента (дельтами хоста)" % i, col_air)

	await barrier("destroyed")
	var gone: bool = await wait_until(func() -> bool: return World.machines.get(_cell(2)) == null, 3.0)
	ok("c%d: снесённая лента пропала (MACHINE_DEL %d)" % [i, nm.dels_rx], gone)
	await barrier("gone")
	await barrier("rebuilt")
	var back: bool = await wait_until(func() -> bool:
			var b = World.belts.get(_cell(2))
			return b != null and b.dir == 3, 3.0)
	ok("c%d: новая лента появилась, направление как у хоста" % i, back)

	var arcs: Array = [0]
	World.turret_fired.connect(func(_a: Vector2, _b: Vector2) -> void: arcs[0] += 1)
	await barrier("turret_ready")
	var t_ok: bool = await wait_until(func() -> bool: return World.machines.get(_cell(7)) is Turret, 3.0)
	ok("c%d: турель хоста появилась" % i, t_ok)
	await barrier("shot")
	var arc: bool = await wait_until(func() -> bool: return arcs[0] > 0, 3.0)
	ok("c%d: выстрел турели виден (дуг %d)" % [i, arcs[0]], arc)

	# Камни: марионетка одна, 3 шт., на земле.
	var box: Array = [[]]
	var landed: bool = await wait_until(func() -> bool:
			var l: Array = _stones_near()
			box[0] = l
			return l.size() == 1 and l[0].count == 3 and l[0].grounded and l[0].net_id != 0, 10.0)
	var st: Array = box[0]
	ok("c%d: марионетка камня одна, 3 шт., на земле (появлений %d)" % [i, nm.spawns_rx], landed,
			"куч %d" % st.size())
	var rep: String = "ip%d:0:0:0" % i
	if landed:
		rep = "ip%d:%.1f:%.1f:%d" % [i, st[0].global_position.x, st[0].global_position.y, st[0].count]
	await barrier(rep)
	await barrier("items_gone")
	var sid: int = st[0].net_id if landed else -1
	var vanished: bool = await wait_until(func() -> bool:
			return _stones_near().all(func(e): return e.net_id != sid), 3.0)
	ok("c%d: убранный у хоста камень пропал (исчезновений %d)" % [i, nm.despawns_rx], vanished,
			str(_stones_near().map(func(e): return [e.net_id, e.count, e.global_position])))

	await barrier("measured")
	print("  ЗАМЕР c%d: построек %d, событий постройки %d, сноса %d, записей net_state %d, предметов: появлений %d, исчезновений %d, убрано из снимка %d" % [
			i, World.machines.size(), nm.adds_rx, nm.dels_rx, nm.states_rx, nm.spawns_rx,
			nm.despawns_rx, nm.purged])
	await JS.client_report(self, i)
	await barrier("done")
	finish()

