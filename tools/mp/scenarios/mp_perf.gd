extends "res://tools/mp/scenarios/mp_threat_base.gd"
## mp_perf (ADR-002 § 4.3, § 4.10; MP-F, #92): кадр хоста в худшую ночь.
##
## Хост + 3 клиента (4 игрока) стоят рядом, база из 130 машин (сундуки, горелки,
## зеркала, маяки, коллекторы), 16 фантомов гонятся за героями. Ленты сняты (#170).
## Хост считает ИИ всех фантомов, прокси трёх клиентов, машины, воду, шлюзы и шлёт
## каждому клиенту свой пакет состояния 20 Гц. Проверки: p95 интервала кадра хоста
## ≤ 16 мс; все 16 фантомов в зоне интереса каждого клиента и видны у него.
## Замер: интервал кадра хоста (среднее, p95, макс);
## STATE на клиента, Б/с — всего и фантомы (12 Б × строк), строк фантомов за такт.

const PERF_SEC: float = 6.0
const FRAME_P95_MAX: float = 16.0
const CAMP: int = 130
const CAMP_KINDS: Array = ["Chest", "Burner", "Mirror", "Pharos", "Collector", "Accumulator", "Prism"]

var _rec: bool = false
var _us: PackedInt64Array = PackedInt64Array()


func _process(_delta: float) -> void:
	if not _rec:
		return
	_us.append(Time.get_ticks_usec())


# ------------------------------------------------------------------ ХОСТ

func run_host() -> void:
	ok("хост + %d клиента вошли (4 игрока)" % clients, await wait_players(1 + clients, 45.0))
	ok("прокси клиентов с вводом", await wait_proxies(clients, 10.0))
	await barrier("in")
	var hs: Array = []
	for i in clients:
		hs.append(hero_of(i))
	if hs.has(null):
		finish()
		return
	var sx: int = World.world_to_cell(World.spawn_point).x
	player.global_position = surface_stand(sx)
	var placed: int = 0
	for i in clients:
		if await teleport_proxy(hs[i], surface_stand(sx + [-8, 8, 16][i])):
			placed += 1
	ok("герои рядом (в 8–16 клетках)", placed == clients)
	invulnerable_all()
	var m: int = _build_base(sx)
	ok("база из %d машин" % CAMP, m == CAMP, "%d" % m)
	Game.time_of_day = Balance.NIGHT_START + 0.02
	var all: Array = [player]
	all.append_array(hs)
	var n: int = await spawn_sixteen(all, hs[0])
	for p in alive_phantoms():
		(p as Phantom).alert = 30.0
	ok("16 фантомов", n == Balance.MAX_PHANTOMS, "%d" % n)
	await wait(1.0)                    # объявления дошли, пути построены
	var in_aoi: int = Balance.MAX_PHANTOMS
	for h in hs:
		in_aoi = mini(in_aoi, _in_aoi(h))
	await barrier("go")
	var sent0: Dictionary = Net.sent_bytes.duplicate()
	var rows0: int = int(nph().stats["rows"])
	var t0: int = Time.get_ticks_msec()
	_us.clear()
	_rec = true
	await wait(PERF_SEC)
	_rec = false
	var sec: float = float(Time.get_ticks_msec() - t0) / 1000.0
	var alive: int = alive_phantoms().size()
	var fs: Dictionary = frame_stats(_us)
	print("  ЗАМЕР кадр хоста (4 игрока, %d фантомов, %d машин, %.1f с): интервал кадра среднее %.2f мс, p95 %.2f мс, макс %.2f мс, кадров %d" % [
			alive, World.machines.size(), sec, fs["avg"], fs["p95"], fs["max"], fs["n"]])
	ok("p95 кадра хоста ≤ %d мс" % int(FRAME_P95_MAX), float(fs["p95"]) <= FRAME_P95_MAX and int(fs["n"]) > 60,
			"p95 %.2f мс" % fs["p95"])
	ok("фантомы живы весь замер (16)", alive == Balance.MAX_PHANTOMS, "%d" % alive)
	var st: float = float(int(Net.sent_bytes.get(NetCodec.Msg.STATE, 0)) - int(sent0.get(NetCodec.Msg.STATE, 0))) / sec / clients
	var rows: int = int(nph().stats["rows"]) - rows0
	var ph: float = float(rows * NetCodec.PHANTOM_BYTES) / sec / clients
	var tot: int = 0
	for k in Net.sent_bytes:
		tot += int(Net.sent_bytes[k]) - int(sent0.get(k, 0))
	var ticks: float = sec * float(Net.TICK_HZ)
	print("  ЗАМЕР трафик фантомов (4 игрока, фантомов в зоне каждого ≥ %d): строк на клиента за такт %.1f; STATE %.0f Б/с на клиента, из них фантомы %.0f Б/с; все кадры хоста %.0f Б/с на клиента; с накладными (72 Б × %d пакетов/с) ≤ %.0f Б/с" % [
			in_aoi, float(rows) / ticks / clients, st, ph, float(tot) / sec / clients, Net.TICK_HZ * 2,
			float(tot) / sec / clients + Net.TICK_HZ * 2 * 72])
	ok("все 16 фантомов — в зоне интереса каждого клиента", in_aoi == Balance.MAX_PHANTOMS, "минимум %d" % in_aoi)
	ok("фантомы в пакете — 12 Б × 16 × 20 Гц ≈ 3.8 КБ/с (§ 4.3)", absf(ph - 3840.0) < 400.0, "%.0f Б/с" % ph)
	await barrier("measured")
	await barrier("done")
	clear_phantoms()
	finish()


## 130 построек света под поверхностью у базы. Сколько поставлено.
func _build_base(sx: int) -> int:
	var x0: int = sx + 30
	var y0: int = int(World.surface[clampi(x0, 0, World.W - 1)]) + 6
	var n: int = 0
	for k in CAMP:
		var c: Vector2i = Vector2i(x0 + k % 20, y0 + k / 20)
		World.set_tile(c.x, c.y, IDs.T.AIR)
		var kind: String = String(CAMP_KINDS[k % CAMP_KINDS.size()])
		if MachineBase.place_machine(kind, c):
			n += 1
		if kind == "Burner":
			var g: Node = World.machines.get(c)
			if g != null and g.has_method("add_fuel"):
				g.call("add_fuel", IDs.I.COAL, 2)
	return n


func _in_aoi(h: Player) -> int:
	var n: int = 0
	for p in alive_phantoms():
		var d: Vector2 = (p as Node2D).global_position - h.global_position
		if absf(d.x) <= Net.AOI_HALF.x and absf(d.y) <= Net.AOI_HALF.y:
			n += 1
	return n


# ------------------------------------------------------------------ КЛИЕНТЫ

func run_client(i: int) -> void:
	await barrier("in")
	await barrier("go", -1, 40.0)
	_us.clear()
	_rec = true
	await wait(PERF_SEC)
	_rec = false
	await barrier("measured", -1, 20.0)
	var vis: int = 0
	for id in nph().puppets:
		if (nph().puppets[id] as Phantom).visible:
			vis += 1
	ok("c%d: видно 16 фантомов" % i, vis == Balance.MAX_PHANTOMS, "%d из %d" % [vis, nph().puppets.size()])
	var fs: Dictionary = frame_stats(_us)
	print("  ЗАМЕР c%d: кадр клиента среднее %.2f мс, p95 %.2f мс (16 марионеток)" % [i, fs["avg"], fs["p95"]])
	await barrier("done")
	finish()
