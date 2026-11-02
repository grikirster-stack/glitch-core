extends MpScenarioBase
## mp_world_deltas (ADR-002, § 4.2.1, § 4.3, § 4.10; MP-C, #88): мир дельтами.
##
## Клиент уже в игре. Хост строит стенд § 9.1 «озеро с полки»: бокс 39×23 из стали,
## в нём полка — озеро 15×8 на земляном поддоне. Бот хоста копает поддон героем
## (шов ввода), затем поддон рушится целиком — 120 полных клеток падают в бокс.
## Всё это — дельты TILES/FLUID раз в сетевой такт. Когда вода у хоста успокоилась,
## у клиента те же тайлы и та же вода (хэши и сверка GLOBAL совпали), а своя вода
## у клиента не считалась.
## Замер: тайлы и вода, Б/с — пик за 1 с во время обрушения (цель ≤ 5.5 КБ/с), всего Б,
## клеток отправлено и сэкономлено (уровень за время в очереди вернулся к отправленному),
## наибольшая очередь воды и отставание клиента. Без бюджета воды (NetWorld.
## FLUID_CELLS_PER_TICK) — флагом хоста --mp-fluid-cap=0:
##   godot --headless --path . -- --mp-scenario=mp_world_deltas --seed=31337 --mp-fluid-cap=0

const JS = preload("res://tools/mp/scenarios/mp_join_snapshot.gd")
## Цель ADR (§ 4.3): пик тайлов и воды при обрушении озера.
const PEAK_TARGET_BPS: int = 5632
const BOX_W: int = 39          ## бокс внутри: 39 × 23
const BOX_H: int = 23
const LAKE_W: int = 15         ## озеро 15 × 8 на поддоне
const LAKE_H: int = 8

var _bx: int = 0               ## левая стенка бокса
var _top: int = 0              ## верхний ряд бокса
var _shelf: int = 0            ## ряд поддона полки


# ------------------------------------------------------------------ ХОСТ

func run_host() -> void:
	var in_game: bool = await wait_players(2, 30.0)
	ok("клиент подключился", in_game)
	await barrier("joined", 1, 30.0)
	var nw: NetWorld = Game.net_world
	# --mp-fluid-cap=N — бюджет воды за такт (0 — без бюджета: замер «как есть»).
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mp-fluid-cap="):
			nw.fluid_cells_per_tick = maxi(0, int(a.substr(15)))
	var built_t0: int = Time.get_ticks_msec()
	if not _build_stand():
		ok("нашлось место для стенда", false)
		await barrier("checked", 1, 60.0)
		await barrier("done", 1, 30.0)
		finish()
		return
	# Озеро на полке стоит.
	for x in range(_bx + 1, _bx + 1 + LAKE_W):
		for y in range(_shelf - LAKE_H, _shelf):
			World.set_fluid(Vector2i(x, y), World.FLUID_MAX)
	var calm: bool = await wait_until(func() -> bool: return World.fluid_pending() == 0, 5.0)
	ok("хост: озеро %d×%d стоит на полке" % [LAKE_W, LAKE_H], calm and _lake_cells() == LAKE_W * LAKE_H,
			"полных клеток %d" % _lake_cells())
	print("  ЗАМЕР стройка стенда: тайлов %d, воды %d клеток, %d Б за %d мс" % [nw.tiles_tx,
			nw.fluid_tx, nw.world_bytes_total, Time.get_ticks_msec() - built_t0])

	# Бот копает поддон героем, стоя на ступеньке снаружи бокса.
	stand_at_cell(Vector2i(_bx - 2, _shelf + 1))
	await wait(0.3)
	var dig: Vector2i = Vector2i(_bx + 1, _shelf)
	aim(World.cell_to_world(dig))
	nw.reset_traffic()
	var t0: float = now()
	press_mouse(MOUSE_BUTTON_LEFT)
	var dug: bool = await wait_until(func() -> bool: return World.get_tile_v(dig) == IDs.T.AIR, 6.0)
	release_mouse(MOUSE_BUTTON_LEFT)
	ok("бот хоста выкопал клетку поддона", dug)
	# Поддон рушится целиком: озеро падает в бокс.
	for x in range(_bx + 1, _bx + 1 + LAKE_W):
		World.set_tile(x, _shelf, IDs.T.AIR)
	var fell: bool = await wait_until(func() -> bool: return World.fluid_pending() == 0, 30.0)
	var secs: float = now() - t0
	ok("хост: вода упала и успокоилась", fell, "%.1f с, в очереди %d" % [secs, World.fluid_pending()])
	# Хвост очереди воды уходит клиенту уже после того, как вода у хоста встала.
	var t1: float = now()
	var drained: bool = await wait_until(func() -> bool: return nw.fluid_backlog() == 0, 10.0)
	var lag: float = now() - t1
	ok("хост: очередь воды отправлена", drained, "осталось %d" % nw.fluid_backlog())
	var wet: int = _box_water()
	ok("хост: вода внизу бокса (%d порций из %d)" % [wet, LAKE_W * LAKE_H * World.FLUID_MAX],
			wet == LAKE_W * LAKE_H * World.FLUID_MAX)
	var cap: String = "%d клеток/такт" % nw.fluid_cells_per_tick if nw.fluid_cells_per_tick > 0 \
			else "без бюджета"
	# Отставание воды клиента от хоста — до (очередь / бюджет) тактов по 50 мс.
	var lag_ms: int = 0 if nw.fluid_cells_per_tick <= 0 else \
			ceili(float(nw.fluid_backlog_max) / float(nw.fluid_cells_per_tick)) * 1000 / Net.TICK_HZ
	print("  ЗАМЕР обрушение озера %d×%d (бюджет воды: %s): пик тайлов и воды %d Б/с на клиента (цель ≤ %d), всего %d Б, вода активна %.1f с + хвост очереди %.2f с (наибольшая %d клеток, отставание ≤ %d мс); клеток: тайлов %d, воды %d, повторов не отправлено %d" % [
			LAKE_W, LAKE_H, cap, nw.world_peak_bps, PEAK_TARGET_BPS, nw.world_bytes_total, secs,
			lag, nw.fluid_backlog_max, lag_ms, nw.tiles_tx, nw.fluid_tx, nw.fluid_skipped])
	if nw.fluid_cells_per_tick > 0:
		ok("пик тайлов и воды ≤ 5.5 КБ/с", nw.world_peak_bps <= PEAK_TARGET_BPS, "%d Б/с" % nw.world_peak_bps)

	await JS.host_check(self)
	await JS.host_compare(self, false)
	await barrier("done", 1, 30.0)
	finish()


## Стенд над землёй вдали от базы. false — места нет.
func _build_stand() -> bool:
	var bx0: int = World.beacon_cell.x
	var cand: Array = [bx0 + 60, bx0 - 60 - BOX_W - 2]
	for c in cand:
		var x0: int = int(c)
		if x0 - 4 < 0 or x0 + BOX_W + 2 >= World.W:
			continue
		var low: int = World.H
		for x in range(x0 - 4, x0 + BOX_W + 3):
			low = mini(low, World.surface[x])
		var top: int = low - BOX_H - 8
		if top < 4:
			continue
		_bx = x0
		_top = top
		_shelf = top + 1 + LAKE_H
		break
	if _top <= 0:
		return false
	var floor_y: int = _top + BOX_H
	var right: int = _bx + BOX_W + 1
	# Расчистить воздух вокруг (деревья, кроны).
	for x in range(_bx - 4, right + 2):
		for y in range(_top - 3, floor_y + 1):
			if World.get_tile(x, y) != IDs.T.AIR:
				World.set_tile(x, y, IDs.T.AIR)
	# Бокс: стенки и пол.
	for y in range(_top, floor_y + 1):
		World.set_tile(_bx, y, IDs.T.STEEL)
		World.set_tile(right, y, IDs.T.STEEL)
	for x in range(_bx, right + 1):
		World.set_tile(x, floor_y, IDs.T.STEEL)
	# Полка: земляной поддон и бортик справа (слева — стенка бокса).
	for x in range(_bx + 1, _bx + 1 + LAKE_W):
		World.set_tile(x, _shelf, IDs.T.DIRT)
	for y in range(_top + 1, _shelf + 1):
		World.set_tile(_bx + 1 + LAKE_W, y, IDs.T.STEEL)
	# Ступенька снаружи — бот стоит на ней и достаёт до поддона.
	for x in range(_bx - 3, _bx):
		World.set_tile(x, _shelf + 2, IDs.T.STEEL)
	return true


func _lake_cells() -> int:
	var n: int = 0
	for x in range(_bx + 1, _bx + 1 + LAKE_W):
		for y in range(_shelf - LAKE_H, _shelf):
			if World.fluid_level(Vector2i(x, y)) == World.FLUID_MAX:
				n += 1
	return n


## Порций воды в боксе ниже полки (вся вода озера должна быть там).
func _box_water() -> int:
	var n: int = 0
	for x in range(_bx + 1, _bx + 1 + BOX_W):
		for y in range(_shelf, _top + BOX_H):
			n += World.fluid_level(Vector2i(x, y))
	return n


# ------------------------------------------------------------------ КЛИЕНТ

func run_client(i: int) -> void:
	var nw: NetWorld = Game.net_world
	var got: bool = await wait_until(func() -> bool: return nw.is_joined, 20.0)
	ok("c%d: снимок получен и применён" % i, got)
	if not got:
		finish()
		return
	await barrier("joined")
	await JS.client_report(self, i)
	ok("c%d: дельты пришли (тайлов %d, воды %d клеток), своя вода не считалась (шагов %d)" % [
			i, nw.tiles_rx, nw.fluid_rx, World.fluid_ticks],
			nw.tiles_rx > 0 and nw.fluid_rx > 0 and World.fluid_ticks == 0)
	ok("c%d: снимок один, без повторов" % i, nw.snapshots_got == 1, "%d" % nw.snapshots_got)
	await barrier("done")
	finish()
