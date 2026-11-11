extends "res://tools/mp/scenarios/mp_players_base.gd"
## mp_factory (ADR-002, § 4.2.1, § 4.2.4, § 4.3, § 4.10; MP-E, #90): машины и предметы
## по сети. Хост и два клиента.
##
## 1. Завод строит клиент 0 своим героем (шов ввода → пакет ввода → прокси на хосте,
##    D3): сундук, две ленты, бур над столбом из ORE_N клеток железной руды (под ним —
##    бедрок); ТЭЦ с углём хост ставит заранее. Постройки — из инвентаря прокси,
##    появляются у обоих клиентов (MACHINE_ADD). У клиентов бур под питанием, прогресс
##    такта растёт, предметы едут по лентам и между пакетами (экстраполяция). Своя логика
##    машин у клиента не идёт: сундук клиента не наполняется, бур не копает (тайлы —
##    дельтами хоста, хэши равны). Сумма у хоста: в сундуке ровно ORE_N руды, на лентах,
##    в буре и на земле её нет — без дублей и потерь.
## 2. Снос и постройка: лента разрушена (destroy: разбирать постройки руками в игре
##    нельзя — сносят фантомы) — пропала у всех; клиент 0 ставит на её место новую и
##    поворачивает ПКМ — у всех новая лента с тем же направлением.
## 3. Турель стреляет по фантому — у клиентов дуга (World.turret_fired) в ближайший такт.
## 4. Предметы на земле: три камня падают рядом и сливаются у хоста в один (3 шт.) —
##    у клиента одна марионетка на 3 шт. там же; убран у хоста — пропал у клиента.
## 5. Замер: база из 130 машин § 9.1 (60 лент с предметами, 20 манипуляторов, 10 буров,
##    18 сундуков, 6 ТЭЦ, 4 плавильни, 4 сборщика, 4 турели, 4 прожектора) в зоне
##    интереса: Б/с машин хост → клиент, сбор net_state на хосте, мкс/такт; машина вне
##    зоны интереса клиентам не шлётся; сверх мягкого предела — 1 Гц.
## Данные клиент сообщает хосту именем барьера.

const JS = preload("res://tools/mp/scenarios/mp_join_snapshot.gd")
const ORE_N: int = 5
const MEASURE_S: float = 5.0
## Оценка ADR (§ 4.3) для машин базы: 60 лент × 10 + 70 × 6 Б при 4 Гц.
const ADR_MACHINES_BPS: int = 4080
## Предел сбора net_state на хосте, мкс за машинный такт (4 Гц): 5 мс — 2 % секунды
## кадров хоста даже на загруженной машине CI (замер на Windows — ≈ 1 мс на 145 машин).
const GATHER_LIMIT_US: int = 5000
## Что строит клиент 0, по порядку: [предмет, вид, смещение клетки]. Сундук и правая
## лента — первыми: лента сама встаёт к соседу справа (Player._auto_orient).
const BUILD: Array = [[IDs.I.CHEST, "Chest", 3], [IDs.I.BELT, "Belt", 2], [IDs.I.BELT, "Belt", 1],
		[IDs.I.DRILL, "Drill", 0]]
## Барьеры после «built» — по порядку (клиент, у которого не вышло, проходит их молча).
const TAIL: Array = ["flowed", "destroyed", "gone", "rebuilt", "turret_ready", "shot", "@ip",
		"items_gone", "measured"]

var _sx: int = 0            ## клетка бура
var _g: int = 0             ## ряд пола (бур стоит в ряду _g − 1)
var _bx: int = 0            ## левый край базы замера


func _layout() -> void:
	_g = World.beacon_cell.y + 1
	_sx = World.beacon_cell.x + 20
	_bx = World.beacon_cell.x + 22


func _cell(dx: int) -> Vector2i:
	return Vector2i(_sx + dx, _g - 1)


## Где стоит герой: на стальном уступе в ряду _g − 3 над клеткой _sx + dx.
func _ledge(dx: int) -> Vector2:
	return Vector2(float((_sx + dx) * World.TILE) + 8.0, float((_g - 3) * World.TILE) - 11.0)


# ------------------------------------------------------------------ ХОСТ

func run_host() -> void:
	_layout()
	var in_game: bool = await wait_players(1 + clients, 45.0)
	ok("клиенты подключились", in_game, "игроков %d" % Net.peers.size())
	ok("прокси клиентов с вводом", await wait_proxies(clients, 10.0))
	await barrier("joined", -1, 30.0)
	var nm: NetMachines = Game.net_machines
	var p0: Player = hero_of(0)
	var p1: Player = hero_of(1)

	# --- 1. Площадка: расчистка, стальной пол и уступы, столб руды, ТЭЦ.
	_clear(_sx - 2, _sx + 27, _g - 11, _g - 1)
	for x in range(_sx - 2, _sx + 28):
		if World.get_tile(x, _g) == IDs.T.AIR or DB.is_liquid(World.get_tile(x, _g)):
			World.set_tile(x, _g, IDs.T.STEEL)
	for dx in [0, 1, 2, 21, 22, 23]:
		World.set_tile(_sx + dx, _g - 3, IDs.T.STEEL)
	for k in ORE_N:
		World.set_tile(_sx, _g + k, IDs.T.IRON_ORE)
	World.set_tile(_sx, _g + ORE_N, IDs.T.BEDROCK)
	ok("хост: ТЭЦ поставлена", MachineBase.place_machine("CoalGen", _cell(-1)))
	var gen: CoalGen = World.machines.get(_cell(-1))
	if gen != null:
		gen.add_fuel(CoalGen.FUEL_MAX_UNITS)
	# Свой герой хоста — подальше (дроп подбирает ближайший), клиенты — на уступы.
	player.global_position = surface_stand(World.world_to_cell(World.spawn_point).x - 40)
	player.vel = Vector2.ZERO
	var placed_ok: bool = p0 != null and p1 != null
	if placed_ok:
		ok("клиент 0 переставлен на уступ над заводом", await teleport_proxy(p0, _ledge(1)))
		ok("клиент 1 переставлен на дальний уступ", await teleport_proxy(p1, _ledge(22)))
		# Набор — в слоты 7–9 хотбара (стартовые вещи прокси там не мешают выбору).
		p0.inv.slots[7] = ItemStack.new(IDs.I.CHEST, 1)
		p0.inv.slots[8] = ItemStack.new(IDs.I.BELT, 3)
		p0.inv.slots[9] = ItemStack.new(IDs.I.DRILL, 1)
		p0.inv.changed.emit()
	var hands0: int = _ore_in_hands()
	await barrier("kit", -1, 30.0)

	# Клиент 0 строит своим героем; хост — только смотрит, что сделал прокси.
	await barrier("built", -1, 60.0)
	var drill: Drill = World.machines.get(_cell(0)) as Drill
	var chest: Chest = World.machines.get(_cell(3)) as Chest
	var b1: Belt = World.belts.get(_cell(1))
	var b2: Belt = World.belts.get(_cell(2))
	ok("хост: клиент 0 поставил сундук, две ленты и бур",
			drill != null and chest != null and b1 != null and b2 != null)
	ok("хост: ленты встали вправо, к сундуку", b1 != null and b2 != null and b1.dir == 0 and b2.dir == 0)
	if p0 != null:
		var s7: ItemStack = p0.inv.get_slot(7)
		var s8: ItemStack = p0.inv.get_slot(8)
		var s9: ItemStack = p0.inv.get_slot(9)
		ok("хост: постройки списаны из слотов прокси (сундук %d, ленты %d, бур %d)" % [s7.count, s8.count, s9.count],
				s7.is_empty() and s8.id == IDs.I.BELT and s8.count == 1 and s9.is_empty())

	# Руда идёт: бур выкапывает столб, всё уезжает в сундук.
	var flowed: bool = await wait_until(func() -> bool:
			return _chest_count(chest, IDs.I.IRON_ORE) >= ORE_N and _belt_items() == 0, 40.0)
	ok("хост: бур выкопал столб, руда в сундуке", flowed,
			"в сундуке %d из %d" % [_chest_count(chest, IDs.I.IRON_ORE), ORE_N])
	await wait(1.0)                         # лишнего бур не выдал
	var in_chest: int = _chest_count(chest, IDs.I.IRON_ORE)
	var on_ground: int = _ground_count(IDs.I.IRON_ORE)
	var in_drill: int = int(drill._output.get(IDs.I.IRON_ORE, 0)) if drill != null else 0
	var in_hands: int = _ore_in_hands() - hands0
	ok("хост: сумма руды без дублей и потерь (сундук %d, ленты %d, бур %d, земля %d, у героев %d = %d)" % [
			in_chest, _belt_items(), in_drill, on_ground, in_hands, ORE_N],
			in_chest + _belt_items() + in_drill + on_ground + in_hands == ORE_N and in_chest == ORE_N)
	var mined: int = 0
	for k in ORE_N:
		if World.get_tile(_sx, _g + k) == IDs.T.AIR:
			mined += 1
	ok("хост: столб руды выкопан (%d клеток)" % mined, mined == ORE_N)
	await barrier("flowed", -1, 60.0)

	# --- 2. Снос и постройка заново: видны всем.
	var old_b2 = World.machines.get(_cell(2))
	if old_b2 != null:
		old_b2.destroy()
	await barrier("destroyed", -1, 20.0)
	await barrier("gone", -1, 20.0)
	await barrier("rebuilt", -1, 30.0)
	var nb2: Belt = World.belts.get(_cell(2))
	ok("хост: клиент 0 поставил новую ленту и повернул её вниз", nb2 != null and nb2.dir == 1,
			"dir %d" % (nb2.dir if nb2 != null else -1))

	# --- 3. Турель стреляет — у клиентов дуга в ближайший такт.
	var tg_ok: bool = MachineBase.place_machine("CoalGen", _cell(6)) and MachineBase.place_machine("Turret", _cell(7))
	ok("хост: турель с ТЭЦ поставлена", tg_ok)
	if tg_ok:
		(World.machines[_cell(6)] as CoalGen).add_fuel(4)
	var tur = World.machines.get(_cell(7))
	await barrier("turret_ready", -1, 20.0)
	# Выстрел — только когда клиенты УЖЕ знают турель (счётчик выстрелов 0).
	# Клиент проигрывает дугу по изменению счётчика в net_state: если он узнает о
	# турели уже после выстрела, счётчик сразу 1 и дуга не проиграется никогда.
	await barrier("turret_known", -1, 20.0)
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
	ok("хост: три камня упали и слились в один (3 шт.)", merged, "куч %d" % _stones_near().size())
	var stone = _stones_near()[0] if merged else null
	# Клиенты присылают «ip<i>:<x>:<y>:<шт>» своей марионетки — сверяем с хостом.
	for i in clients:
		var rep: String = await _wait_report("ip%d:" % i, 15.0)
		var parts: PackedStringArray = rep.split(":")
		if stone != null and parts.size() >= 4:
			var cp: Vector2 = Vector2(float(parts[1]), float(parts[2]))
			ok("c%d: марионетка камня там же, где у хоста (%.1f px), %s шт." % [i,
					cp.distance_to(stone.global_position), parts[3]],
					cp.distance_to(stone.global_position) <= float(World.TILE) and int(parts[3]) == 3)
		else:
			ok("c%d: прислал марионетку камня" % i, false, rep)
		if rep != "":
			await mp().barrier(rep, 1, 5.0)
	if stone != null:
		stone.queue_free()
	await barrier("items_gone", -1, 20.0)

	# --- 5. Замер: база из 130 машин в зоне интереса и ТЭЦ вне зоны.
	var base: Array = _build_base()
	ok("хост: база из 130 машин построена", base.size() == 130, "%d" % base.size())
	var far: Vector2i = Vector2i(_sx + 90, World.surface[_sx + 90] - 1)
	World.set_tile(far.x, far.y, IDs.T.AIR)
	var far_ok: bool = MachineBase.place_machine("CoalGen", far)
	if far_ok:
		(World.machines[far] as CoalGen).add_fuel(4)    # топливо убывает — net_state меняется
	await wait(1.0)                         # события постройки и первый полный обход прошли
	var pid: int = peer_of_uid(client_uid(0))
	# Замер такта: хост должен быть не в мягком пределе (там машины идут 1 Гц —
	# проверка ниже), иначе счёт за 5 с меньше 20 не из-за поломки сети. Всплеск
	# от постройки базы (130 MACHINE_ADD) поднимает хост над пределом на секунду;
	# ждём, пока окно бюджета (1 с) его отпустит.
	var m: Dictionary = await _measure_hz(nm, pid)
	if not bool(m["cadence_ok"]):
		# Первый замер попал в мягкий предел — меряем заново, уже чистое окно.
		m = await _measure_hz(nm, pid)
	var dt: float = float(m["dt"])
	var pf: int = int(m["pf"])
	var bps: float = float(m["bps"])
	var sbps: float = float(nm.state_bytes) / dt / float(maxi(1, clients))
	var avg_us: float = float(m["avg_us"])
	print("  ЗАМЕР база %d машин (всего в мире %d) в зоне: машины хост → клиент %.0f Б/с (net_state %.0f Б/с, оценка ADR %d), записей %d за %.1f с; сбор net_state %.0f мкс/такт (худший %d, из последнего постройка %d, машин %d, тактов %d); физ. кадров %d (ожидаем %d); в мягком пределе %d из %d замеров; мягкий предел — %s" % [
			base.size(), World.machines.size(), bps, sbps, ADR_MACHINES_BPS, nm.states_tx, dt, avg_us,
			nm.gather_us_max, nm.build_us, nm.gather_machines, nm.gather_n, pf, int(m["want"]),
			int(m["slow_n"]), int(m["samples"]), "1 Гц" if nm.slow else "не достигнут"])
	ok("хост: машины базы — меньше мягкого предела %d Б/с" % Net.SOFT_BUDGET, bps < float(Net.SOFT_BUDGET),
			"%.0f Б/с" % bps)
	# Такт сбора состояний — каждые 15 физических кадров хоста: 3 кадра на сетевой
	# такт (NetWorld.TICK_FRAMES) × 5 тактов на сбор (Net.TICK_HZ / Net.MACHINE_HZ).
	# Сверяем число сборов с числом физических кадров: физика — честный счётчик
	# тактов, от скорости раннера не зависит.
	var per_gather: int = NetWorld.TICK_FRAMES * (Net.TICK_HZ / Net.MACHINE_HZ)
	ok("хост: машины идут 4 Гц (тактов сбора %d за %d физ. кадров, по %d на такт)" % [
			nm.gather_n, pf, per_gather], bool(m["cadence_ok"]),
			"ожидаем %d сборов" % int(m["want"]))
	ok("хост: во время замера хост не был в мягком пределе", int(m["slow_n"]) == 0,
			"в пределе %d из %d замеров" % [int(m["slow_n"]), int(m["samples"])])
	ok("хост: сбор net_state ≤ %d мкс/такт (%.0f)" % [GATHER_LIMIT_US, avg_us], avg_us <= float(GATHER_LIMIT_US))
	var far_idx: int = far.y * World.W + far.x
	var far_sent: bool = false
	for id in nm._peers:
		far_sent = far_sent or (nm._peers[id]["ms"] as Dictionary).has(far_idx)
	ok("хост: ТЭЦ вне зоны интереса клиентам не шлётся (постройка — шлётся)", far_ok and not far_sent)
	# Мягкий предел (§ 4.3): сверх него машины идут раз в секунду.
	nm.soft_budget = 256
	var slowed: bool = await wait_until(func() -> bool: return nm.slow, 3.0)
	var n0: int = nm.gather_n
	var ts: float = now()
	await wait(3.0)
	var hz: float = float(nm.gather_n - n0) / (now() - ts)
	ok("хост: сверх мягкого предела машины идут 1 Гц (%.1f Гц)" % hz, slowed and hz <= 1.5)
	nm.soft_budget = Net.SOFT_BUDGET
	var fast: bool = await wait_until(func() -> bool: return not nm.slow, 3.0)
	ok("хост: в пределе — снова %d Гц" % Net.MACHINE_HZ, fast)
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


## Руда в инвентарях всех героев (свой хоста и прокси).
func _ore_in_hands() -> int:
	var n: int = 0
	for p in Game.players:
		if is_instance_valid(p):
			n += p.inv.count_of(IDs.I.IRON_ORE)
	return n


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


## Окно замера такта сбора состояний (MEASURE_S с): хост в обычном режиме, не в
## мягком пределе. Отдаёт метрики окна: сколько сборов, сколько физических
## кадров, сколько замеров попало в мягкий предел.
func _measure_hz(nm, pid: int) -> Dictionary:
	await wait_until(func() -> bool: return not nm.slow, 3.0)
	await wait(1.1)                          # окно бюджета (1 с) отпустило всплеск
	nm.reset_traffic()
	var pf0: int = Engine.get_physics_frames()
	var b0: int = int(nm.peer_bytes.get(pid, 0))
	var t0: float = now()
	var feed_t: float = 0.0
	var slow_n: int = 0
	var samples: int = 0
	while now() - t0 < MEASURE_S:
		await wait(0.1)
		samples += 1
		if nm.slow:
			slow_n += 1
		feed_t += 0.1
		if feed_t >= 0.5:
			feed_t = 0.0
			_feed_base()
	var dt: float = now() - t0
	var pf: int = Engine.get_physics_frames() - pf0
	var per_gather: int = NetWorld.TICK_FRAMES * (Net.TICK_HZ / Net.MACHINE_HZ)
	var want: int = int(round(float(pf) / float(per_gather)))
	return {
		"dt": dt,
		"pf": pf,
		"want": want,
		"slow_n": slow_n,
		"samples": samples,
		"bps": float(int(nm.peer_bytes.get(pid, 0)) - b0) / dt,
		"avg_us": float(nm.gather_us_sum) / float(maxi(1, nm.gather_n)),
		"cadence_ok": slow_n == 0 and absi(nm.gather_n - want) <= 1,
	}


# ------------------------------------------------------------------ КЛИЕНТ

func run_client(i: int) -> void:
	_layout()
	var nw: NetWorld = Game.net_world
	var nm: NetMachines = Game.net_machines
	var got: bool = await wait_until(func() -> bool: return nw.is_joined, 20.0)
	ok("c%d: снимок получен" % i, got)
	await barrier("joined")
	await barrier("kit")
	if i == 0:
		await _build_factory()
	await barrier("built")
	# Постройки клиента 0 (через прокси на хосте) пришли событиями.
	var kinds: Array = [["CoalGen", -1], ["Drill", 0], ["Belt", 1], ["Belt", 2], ["Chest", 3]]
	var arrived: bool = await wait_until(func() -> bool:
			for kv in kinds:
				var m = World.machines.get(_cell(int(kv[1])))
				if m == null or String(m.kind) != String(kv[0]):
					return false
			return true, 5.0)
	ok("c%d: завод появился (MACHINE_ADD %d)" % [i, nm.adds_rx], arrived)
	var drill = World.machines.get(_cell(0))
	var b1 = World.belts.get(_cell(1))
	var chest = World.machines.get(_cell(3))
	if not arrived or drill == null or b1 == null:
		for b in TAIL:
			await barrier("ip%d:0:0:0" % i if b == "@ip" else String(b))
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
	if i == 0:
		var put: bool = await _place(IDs.I.BELT, "Belt", 2)
		ok("c0: новая лента поставлена своим героем", put)
		var turned: bool = put and await _click(_cell(2), func() -> bool:
				var b = World.belts.get(_cell(2))
				return b != null and b.dir == 1)
		ok("c0: лента повёрнута ПКМ (вниз)", turned)
	await barrier("rebuilt")
	var back: bool = await wait_until(func() -> bool:
			var b = World.belts.get(_cell(2))
			return b != null and b.dir == 1, 3.0)
	ok("c%d: новая лента у клиента, направление как у хоста" % i, back)

	var arcs: Array = [0]
	World.turret_fired.connect(func(_a: Vector2, _b: Vector2) -> void: arcs[0] += 1)
	await barrier("turret_ready")
	var t_ok: bool = await wait_until(func() -> bool: return World.machines.get(_cell(7)) is Turret, 3.0)
	ok("c%d: турель хоста появилась" % i, t_ok)
	await barrier("turret_known")
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
	var sid: int = st[0].net_id if landed else -1
	var rep: String = "ip%d:0:0:0" % i
	if landed:
		rep = "ip%d:%.1f:%.1f:%d" % [i, st[0].global_position.x, st[0].global_position.y, st[0].count]
	await barrier(rep)
	await barrier("items_gone")
	var vanished: bool = await wait_until(func() -> bool:
			return _stones_near().all(func(e): return e.net_id != sid), 3.0)
	ok("c%d: убранный у хоста камень пропал (исчезновений %d)" % [i, nm.despawns_rx], vanished)

	await barrier("measured")
	print("  ЗАМЕР c%d: построек %d, событий постройки %d, сноса %d, записей net_state %d, предметов: появлений %d, исчезновений %d, убрано из снимка %d" % [
			i, World.machines.size(), nm.adds_rx, nm.dels_rx, nm.states_rx, nm.spawns_rx,
			nm.despawns_rx, nm.purged])
	await JS.client_report(self, i)
	await barrier("done")
	finish()


## c0: построить завод своим героем — постройки по BUILD.
func _build_factory() -> void:
	var kit: bool = await wait_until(func() -> bool:
			return (player.inv.get_slot(9).id == IDs.I.DRILL and player.inv.get_slot(8).count >= 3
					and player.inv.get_slot(7).id == IDs.I.CHEST), 5.0)
	ok("c0: набор построек пришёл в свой инвентарь (INV)", kit)
	var n: int = 0
	for b in BUILD:
		if await _place(int(b[0]), String(b[1]), int(b[2])):
			n += 1
	ok("c0: построил своим героем сундук, две ленты и бур (%d из %d)" % [n, BUILD.size()], n == BUILD.size())


## c0: выбрать в хотбаре предмет и щёлкнуть ПКМ по клетке; true — у себя появилась
## постройка этого вида (MACHINE_ADD от хоста).
func _place(item: int, kind: String, dx: int) -> bool:
	var slot: int = -1
	for k in range(player.inv.hotbar_size - 1, -1, -1):     # набор — в слотах 7–9
		if player.inv.get_slot(k).id == item:
			slot = k
			break
	if slot < 0:
		return false
	player.inv.selected = slot
	var c: Vector2i = _cell(dx)
	return await _click(c, func() -> bool:
			var m = World.machines.get(c)
			return m != null and String(m.kind) == kind)


## c0: короткий щелчок ПКМ (0.1 с — меньше паузы постройки 0.16 с: одно действие)
## и ожидание итога; не вышло (пауза постройки не истекла) — ещё раз.
func _click(c: Vector2i, done_fn: Callable) -> bool:
	for attempt in 4:
		aim(World.cell_to_world(c))
		press_mouse(MOUSE_BUTTON_RIGHT)
		await wait(0.1)
		release_mouse(MOUSE_BUTTON_RIGHT)
		if await wait_until(done_fn, 2.0):
			return true
	return false
