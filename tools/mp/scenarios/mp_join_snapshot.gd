extends MpScenarioBase
## mp_join_snapshot (ADR-002, § 4.2.2, § 4.10; MP-C, #88): вход в идущую игру снимком.
##
## Хост до входа клиента копает героем (шов ввода), строит, ставит постройки (сундук,
## солнечная панель, прожектор) и льёт воду в яму. Клиент входит позже: мир по сиду,
## затем снимок Save.gather_join() по каналу 0. После входа хост льёт ещё воды и
## копает — это уже дельты. Когда вода у хоста успокоилась, хэши тайлов, воды и
## построек у хоста и клиента равны, сверка GLOBAL совпала. У клиента не работают
## вода, питание, цель и угроза (счётчики = 0).
## Замер: вход (Net.join → снимок применён), мс; снимок, Б; сборка и применение, мс.
##
## Хэши клиент сообщает хосту именем барьера «h:тайлы:вода:постройки» — у харнесса
## нет своего канала данных, а имя барьера доходит как есть.

const HASH_PREFIX: String = "h:"
## Цель ADR (§ 2): от «Подключиться» до управления героем.
const JOIN_TARGET_MS: int = 2000

var _col: int = 0
var _ground: int = 0


func _init() -> void:
	auto_launch = false


# ------------------------------------------------------------------ ХОСТ

func run_host() -> void:
	await wait(0.3)
	# --- 1. Герой хоста копает, как в одиночной (шов ввода).
	var cell: Vector2i = find_mineable()
	ok("хост: есть клетка для копки", cell.x >= 0, str(cell))
	if cell.x >= 0:
		var before: int = World.get_tile_v(cell)
		aim(World.cell_to_world(cell))
		press_mouse(MOUSE_BUTTON_LEFT)
		var broke: bool = await wait_until(func() -> bool: return World.get_tile_v(cell) != before, 6.0)
		release_mouse(MOUSE_BUTTON_LEFT)
		ok("хост: герой выкопал %s" % DB.tile_name(before), broke)
	# --- 2. Стройка, постройки и вода до входа клиента.
	_col = clampi(World.beacon_cell.x + 30, 20, World.W - 20)
	_ground = World.surface[_col]
	for x in range(_col - 12, _col + 9):
		for y in range(_ground - 6, _ground):
			World.set_tile(x, y, IDs.T.AIR)
	for y in range(_ground - 5, _ground):
		World.set_tile(_col - 1, y, IDs.T.STEEL)          # стенка
	for x in range(_col, _col + 5):                       # яма 5×3
		for y in range(_ground, _ground + 3):
			World.set_tile(x, y, IDs.T.AIR)
	var placed: int = 0
	for kv in [["Chest", -4], ["Solar", -7], ["Floodlight", -10]]:
		if MachineBase.place_machine(String(kv[0]), Vector2i(_col + int(kv[1]), _ground - 1)):
			placed += 1
	ok("хост: постройки поставлены (сундук, панель, прожектор)", placed == 3, "%d из 3" % placed)
	# Горелка (#164): клиент после входа сам строит луч из реплицированного состояния.
	var bcell: Vector2i = Vector2i(_col - 12, _ground - 1)
	for k in range(0, 8):
		World.set_tile(bcell.x + k, bcell.y, IDs.T.AIR)
	if MachineBase.place_machine("Burner", bcell):
		var burner: Burner = World.machines[bcell]
		burner.add_fuel(IDs.I.COAL, 1)
		World.beams.rebuild()
	ok("хост: горелка горит до входа клиента", World.beams.color_at(bcell + Vector2i(1, 0)) == Beams.R)
	_pour(Vector2i(_col + 1, _ground - 4), 3, 2)
	ok("хост: вода течёт, когда клиент входит", World.fluid_pending() > 0,
			"в очереди %d" % World.fluid_pending())

	# --- 3. Клиент входит в идущую игру.
	launch([0])
	var in_game: bool = await wait_players(2, 30.0)
	ok("клиент подключился", in_game)
	await barrier("joined", 1, 30.0)
	print("  ЗАМЕР снимок: %d Б (сырые %d Б), gather_join + encode %.1f мс; запуск клиента-процесса до входа %d мс" % [
			Game.net_world.snapshot_bytes, Save.last_raw_size, Game.net_world.last_gather_ms,
			mp().join_ms_of_uid(client_uid(0))])
	ok("хост: снимок отправлен один раз", Game.net_world.snapshots_sent == 1,
			"%d" % Game.net_world.snapshots_sent)

	# --- 4. После входа — уже дельтами: ещё вода и копка.
	_pour(Vector2i(_col + 3, _ground - 4), 2, 2)
	World.set_tile(_col + 6, _ground, IDs.T.AIR)
	World.set_tile(_col - 6, _ground - 1, IDs.T.STEEL)

	# --- 5. Вода успокоилась — сверка и хэши.
	var calm: bool = await wait_until(func() -> bool: return World.fluid_pending() == 0, 20.0)
	ok("хост: вода успокоилась", calm, "в очереди %d" % World.fluid_pending())
	await host_check(self)
	await host_compare(self, true)
	await barrier("done", 1, 30.0)
	finish()


func _pour(at: Vector2i, w: int, h: int) -> void:
	for x in range(at.x, at.x + w):
		for y in range(at.y, at.y + h):
			World.set_fluid(Vector2i(x, y), World.FLUID_MAX)


# ------------------------------------------------------------------ СВЕРКА (и для mp_world_deltas)

## Хост: сверка мира в ближайший такт; клиент получает её после барьера «checked».
static func host_check(sc: MpScenarioBase) -> void:
	var sent: int = Game.net_world.hash_sent
	Game.net_world.check_now()
	var ok_s: bool = await sc.wait_until(func() -> bool: return Game.net_world.hash_sent > sent, 2.0)
	sc.ok("хост: сверка мира отправлена", ok_s)
	# Барьер — на ВСЕХ клиентов: хост отпускает тех, кто уже пришёл, и BARRIER_PASS
	# уходит только дошедшим (mp_runner: BARRIER_PASS по списку пришедших). С count=1
	# хост отпускал барьер после первого клиента, и второй висел до своего таймаута
	# (сценарий mp_factory падал на «хэши тайлов… (1 из 2)»).
	await sc.barrier("checked", -1, 60.0)


## Хост: хэши клиента (имя его барьера «h:…») против своих.
static func host_compare(sc: MpScenarioBase, with_machines: bool) -> void:
	var name: String = ""
	var t0: float = sc.now()
	while name == "" and sc.now() - t0 < 30.0:
		for n in sc.mp()._arrived.keys():
			if String(n).begins_with(HASH_PREFIX):
				name = String(n)
		await sc.wait(0.05)
	sc.ok("клиент прислал хэши", name != "")
	if name == "":
		return
	var parts: PackedStringArray = name.substr(HASH_PREFIX.length()).split(":")
	var mine: Array = hashes()
	var labels: Array = ["тайлов", "воды", "построек"]
	for k in (3 if with_machines else 2):
		var theirs: String = parts[k] if parts.size() > k else "?"
		sc.ok("хэш %s равен" % labels[k], theirs == mine[k], "клиент %s, хост %s" % [theirs, mine[k]])
	await sc.mp().barrier(name, 1, 5.0)


## Клиент: дождаться сверки хоста и прислать свои хэши (тайлы, вода, постройки).
static func client_report(sc: MpScenarioBase, i: int) -> void:
	var nw: NetWorld = Game.net_world
	await sc.barrier("checked", -1, 60.0)
	var same: bool = await sc.wait_until(func() -> bool:
			return nw.hash_checks > 0 and NetWorld.world_hash() == nw.last_host_hash, 10.0)
	sc.ok("c%d: сверка мира с хостом совпала (сверок %d, расхождений %d)" % [i, nw.hash_checks,
			nw.hash_bad], same and nw.hash_bad == 0)
	await sc.barrier(HASH_PREFIX + ":".join(PackedStringArray(hashes())), -1, 30.0)


static func hashes() -> Array:
	return ["%08x" % NetWorld.tiles_hash(), "%08x" % NetWorld.fluid_hash(),
			"%08x" % NetWorld.machines_hash()]


# ------------------------------------------------------------------ КЛИЕНТ

func run_client(i: int) -> void:
	var nw: NetWorld = Game.net_world
	var power: Array = [0]
	Game.power_updated.connect(func() -> void: power[0] += 1)
	var got: bool = await wait_until(func() -> bool: return nw.is_joined, 20.0)
	ok("c%d: снимок получен и применён" % i, got)
	if not got:
		finish()
		return
	print("  ЗАМЕР c%d вход: подключение → управление героем %d мс (рукопожатие %d мс), снимок %d Б, применение %.1f мс" % [
			i, nw.join_total_ms, Net.join_ms, nw.snapshot_bytes, nw.last_apply_ms])
	ok("c%d: вход ≤ %d мс (цель ADR § 2)" % [i, JOIN_TARGET_MS], nw.join_total_ms <= JOIN_TARGET_MS,
			"%d мс" % nw.join_total_ms)
	ok("c%d: постройки хоста на месте" % i, World.machines.size() >= 4, "%d" % World.machines.size())
	var saw: bool = false
	for m in World.machines.values():
		if m is Burner and m.burning():
			World.beams.rebuild()
			saw = World.beams.color_at(m.cell + Vector2i(1, 0)) == Beams.R
	ok("c%d: после входа видит луч горелки" % i, saw)
	await barrier("joined")
	await client_report(self, i)
	# Клиент не считает мир: вода, питание, цель, угроза.
	Game.update_power_budget()            # и прямой вызов молчит
	ok("c%d: вода не считается (шагов %d, пересчётов %d), уровни пришли (%d клеток)" % [
			i, World.fluid_ticks, World.fluid_steps, nw.fluid_rx],
			World.fluid_ticks == 0 and World.fluid_steps == 0 and nw.fluid_rx > 0)
	ok("c%d: питание не считается (раскладок %d)" % [i, power[0]], power[0] == 0)
	ok("c%d: цель не считается" % i, Game._objective_t == 0.0, "таймер %.2f" % Game._objective_t)
	ok("c%d: угроза не работает (директор выключен, фантомов %d)" % [i, Threat.spawned_total],
			not Threat.is_processing() and Threat.spawned_total == 0)
	ok("c%d: глобальный пакет идёт (%d), часы подтянуты %d раз" % [i, nw.globals_rx,
			Game.net_clock_snaps], nw.globals_rx > 0)
	await barrier("done")
	finish()
