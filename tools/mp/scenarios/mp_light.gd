extends "res://tools/mp/scenarios/mp_players_base.gd"
## mp_light (ADR-005 § 7, #180): луч, блоки, ядро и кот у клиента.
##
## Клиент 0 ставит горелку и кладёт уголь — хост и клиент 1 видят тот же красный
## луч (World.beams.color_at). Клиент поворачивает зеркало — луч у всех
## поворачивается за ≤ 2 кадра сети (MACHINE_ADD несёт dir, не отдельный пакет
## луча). Клиент входит в готовую базу из 7 блоков и ядра с 5 дугами: после
## apply_join beams.cells побайтно равен хостовому, core_arcs равен. Кот летит —
## марионетка в ±1 клетке от хоста.
## Сообщений о луче нет: трассировку клиент строит из net_state машин.

const TILE: float = 16.0
## Кадр сети машин — 0.25 с (MACHINE_HZ). Два кадра — с запасом на доставку.
const NET_FRAMES: int = 2
const NET_FRAME_S: float = 0.25
const TURN_WAIT: float = 1.2
const CAT_CELL: float = 16.0

var _col: int = 0
var _ground: int = 0
var _burner: Vector2i = Vector2i(-1, -1)
var _mirror: Vector2i = Vector2i(-1, -1)
var _spot: Vector2i = Vector2i(-1, -1)
var _stand: Vector2 = Vector2.ZERO


func _init() -> void:
	auto_launch = false
	clients = 3


# ------------------------------------------------------------------ ХОСТ

func run_host() -> void:
	await wait(0.4)
	_col = clampi(World.beacon_cell.x + 36, 24, World.W - 40)
	_ground = World.surface[_col]
	_clear_pad()
	# На клетку выше пола: вниз от зеркала — воздух, не сталь. Луч в сталь не входит.
	_burner = Vector2i(_col, _ground - 2)
	_mirror = _burner + Vector2i(3, 0)
	# dir 0 («/») уводит луч вверх. Один ПКМ — «\», луч вниз.
	_spot = _mirror + Vector2i(0, 1)
	# Герой 12×22 не должен пересекать клетку горелки: иначе ПКМ не ставит.
	_stand = Vector2(float((_burner.x + 2) * World.TILE) + 8.0, float(_ground * World.TILE) - 12.0)
	ok("хост: площадка под луч свободна", World.get_tile_v(_burner) == IDs.T.AIR)
	launch([0, 1])
	ok("хост + 2 клиента вошли", await wait_players(3, 40.0))
	ok("прокси обоих клиентов с вводом", await wait_proxies(2, 12.0))
	await barrier("in", 2)
	var p0: Player = hero_of(0)
	var p1: Player = hero_of(1)
	if p0 == null or p1 == null:
		finish()
		return
	ok("клиент 0 у горелки", await teleport_proxy(p0, _stand))
	# Клиент 1 смотрит издалека: его зона интереса не обязана покрывать площадку,
	# MACHINE_ADD идёт всем, не только зоне.
	var far: Vector2 = surface_stand(_col + 28)
	ok("клиент 1 в стороне", await teleport_proxy(p1, far))
	# Предметы — в инвентарь прокси: клиентский add сеть затирает свежим INV.
	p0.inv.add(IDs.I.BURNER, 1)
	p0.inv.add(IDs.I.MIRROR, 1)
	if p0.inv.count_of(IDs.I.COAL) < 1:
		p0.inv.add(IDs.I.COAL, 1)
	var pad: Dictionary = {"col": _col, "ground": _ground, "bx": _burner.x, "by": _burner.y,
			"mx": _mirror.x, "my": _mirror.y, "sx": _spot.x, "sy": _spot.y}
	share_put("pad", pad)
	await barrier("pad", 2)
	await barrier("placed", 2)

	var lit: bool = await wait_until(func() -> bool:
		return World.beams.color_at(_burner + Vector2i(1, 0)) == Beams.R, 6.0)
	ok("хост: клиент зажёг красный луч", lit, _beam_at(_burner + Vector2i(1, 0)))
	var burner: Burner = World.machines.get(_burner) as Burner
	ok("хост: горелка горит от угля клиента", burner != null and burner.burning() and burner.color == Beams.R)
	share_put("beam", _beam_blob())
	await barrier("lit", 2)

	ok("хост: до поворота луч вверх, не вниз",
			World.beams.color_at(_mirror + Vector2i(0, -1)) == Beams.R and World.beams.color_at(_spot) == 0,
			"вверх %s, вниз %s" % [_beam_at(_mirror + Vector2i(0, -1)), _beam_at(_spot)])
	var turned: bool = await wait_until(func() -> bool:
		var m: Mirror = World.machines.get(_mirror) as Mirror
		return m != null and (m.dir & 7) == 1, TURN_WAIT)
	var frames: int = 0
	if turned:
		var t0: int = Time.get_ticks_msec()
		var up: bool = await wait_until(func() -> bool:
			return World.beams.color_at(_spot) == Beams.R, TURN_WAIT)
		frames = int(ceil(float(Time.get_ticks_msec() - t0) / (NET_FRAME_S * 1000.0)))
		ok("хост: луч повернулся вниз", up, _beam_at(_spot))
	else:
		ok("хост: клиент повернул зеркало", false)
	print("  ЗАМЕР поворот зеркала → луч у хоста: %d кадров сети (порог %d)" % [frames, NET_FRAMES])
	ok("хост: поворот уложился в %d кадра сети" % NET_FRAMES, turned and frames <= NET_FRAMES,
			"%d" % frames)
	share_put("turn_frames", frames)
	share_put("beam2", _beam_blob())
	await barrier("turned", 2)

	# --- Готовая база: 7 блоков и ядро с 5 дугами. Клиент входит в неё позже.
	# Горелка и зеркало актёра в семёрку не входят. Снимаем без лута: скан хоста
	# сам шлёт MACHINE_DEL, когда узла нет в мире.
	_drop_quiet(_burner)
	_drop_quiet(_mirror)
	await wait(0.3)
	_build_base()
	World.beams.rebuild()
	var arcs: int = Game.core_arcs
	ok("хост: база из 7 блоков и ядро", _base_count() == 7 and Game.core_placed(),
			"блоков %d, ядро %s" % [_base_count(), str(Game.core_cell)])
	ok("хост: пять дуг горят", Game.core_arc_count() == 5, str(arcs))
	share_put("arcs", arcs)
	share_put("cells", _cells_blob())
	var snap_before: int = Game.net_world.snapshots_sent
	launch([2])
	var joined: bool = await wait_until(func() -> bool: return Net.peers.size() >= 2, 40.0)
	ok("третий клиент вошёл в готовую базу", joined, "пиров %d" % Net.peers.size())
	await barrier("joined", 1, 30.0)
	print("  ЗАМЕР снимок базы «семь цветов»: %d Б (сырые %d Б)" % [
			Game.net_world.snapshot_bytes, Save.last_raw_size])
	ok("хост: снимок входа ушёл вошедшему", Game.net_world.snapshots_sent > snap_before)
	await barrier("snap_ok", 1, 20.0)

	# --- Кот. Выход — из ядра, позиция хоста известна клиенту по Msg.CAT.
	Game.time_of_day = Balance.NIGHT_START + 0.02
	var cat: RainbowCat = Game.cat_hatch_at(World.cell_to_world(Game.core_cell) + Vector2(0.0, -20.0))
	ok("хост: кот вышел", cat != null and cat.alive)
	await wait(0.35)
	if cat != null and is_instance_valid(cat):
		share_put("cat", {"x": cat.global_position.x, "y": cat.global_position.y})
	await barrier("cat", 1, 15.0)
	await wait(0.2)
	if cat != null and is_instance_valid(cat):
		cat.queue_free()
	share_clear(["pad", "beam", "beam2", "arcs", "cells", "cat", "turn_frames"])
	finish()


func _drop_quiet(c: Vector2i) -> void:
	var m: MachineBase = World.machines.get(c) as MachineBase
	if m == null:
		return
	World.machines.erase(c)
	if is_instance_valid(m):
		m.queue_free()
	if World.beams != null:
		World.beams.note_machines()


func _clear_pad() -> void:
	for x in range(_col - 2, _col + 10):
		for y in range(_ground - 8, _ground):
			World.set_tile(x, y, IDs.T.AIR)
	for x in range(_col - 2, _col + 10):
		World.set_tile(x, _ground, IDs.T.STEEL)


## Семь блоков конструктора и ядро. Горелка с углём — чтобы карта луча в снимке
## была не пустой. Пять дуг — кодом хоста: луч их не зажигает, сверка смотрит,
## что снимок и CORE везут уже зажжённое. Смеситель в семёрку не входит: его
## поворот проверяет тот же байт dir базы, что и у призмы.
func _build_base() -> void:
	var kinds: Array = ["Burner", "Mirror", "Prism", "Collector", "Accumulator", "Pharos", "Siren"]
	var y: int = _ground - 4
	var burner_cell: Vector2i = Vector2i(_col, y)
	for i in kinds.size():
		var c: Vector2i = Vector2i(_col + i, y)
		World.set_tile(c.x, c.y, IDs.T.AIR)
		MachineBase.place_machine(String(kinds[i]), c)
	var burner: Burner = World.machines.get(burner_cell) as Burner
	if burner != null:
		burner.add_fuel(IDs.I.COAL, 2)
	var core: Vector2i = Vector2i(_col + 4, _ground - 6)
	World.set_tile(core.x, core.y, IDs.T.AIR)
	MachineBase.place_machine("RainbowCore", core)
	for c in [Beams.R, Beams.G, Beams.B, Beams.Y, Beams.C]:
		Game.core_feed(c)


func _base_count() -> int:
	var n: int = 0
	for m in World.machines.values():
		if m is Burner or m is Mirror or m is Mixer or m is Prism or m is Collector \
				or m is Accumulator or m is Pharos or m is Siren:
			n += 1
	return n


func _beam_at(c: Vector2i) -> String:
	return "%s=%d" % [str(c), World.beams.color_at(c)]


func _beam_blob() -> PackedByteArray:
	return _cells_blob()


func _cells_blob() -> PackedByteArray:
	var keys: Array = World.beams.cells.keys()
	keys.sort_custom(func(a, b):
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x)
	var out: PackedByteArray = PackedByteArray()
	out.resize(keys.size() * 5)
	var i: int = 0
	for c in keys:
		out.encode_u16(i, c.x & 0xFFFF)
		out.encode_u16(i + 2, c.y & 0xFFFF)
		out.encode_u8(i + 4, int(World.beams.cells[c]) & 0xFF)
		i += 5
	return out


# ------------------------------------------------------------------ КЛИЕНТЫ

func run_client(i: int) -> void:
	if i == 2:
		await _late(i)
		return
	await barrier("in")
	# Лямбда не пишет во внешнюю переменную: площадка копится в ячейке массива.
	var box: Array = [null]
	var got_pad: bool = await wait_until(func() -> bool:
		box[0] = share_get("pad")
		return box[0] is Dictionary, 8.0)
	var pad = box[0]
	ok("c%d: площадка хоста получена" % i, got_pad)
	if not got_pad:
		await barrier("pad")
		await barrier("placed")
		await barrier("lit")
		await barrier("turned")
		finish()
		return
	_col = int(pad["col"])
	_ground = int(pad["ground"])
	_burner = Vector2i(int(pad["bx"]), int(pad["by"]))
	_mirror = Vector2i(int(pad["mx"]), int(pad["my"]))
	_spot = Vector2i(int(pad["sx"]), int(pad["sy"]))
	await barrier("pad")
	if i == 0:
		await _actor()
	else:
		await _watcher()


func _actor() -> void:
	var have: bool = await wait_until(func() -> bool:
		return player.inv.count_of(IDs.I.BURNER) > 0 and player.inv.count_of(IDs.I.MIRROR) > 0 \
				and player.inv.count_of(IDs.I.COAL) > 0, 4.0)
	ok("c0: горелка, зеркало и уголь в инвентаре", have)
	var placed: bool = await _place_item(IDs.I.BURNER, _burner)
	ok("c0: горелка поставлена", placed, str(_burner))
	await wait(0.15)
	var fed: bool = await _feed_burner()
	ok("c0: уголь в топке", fed)
	var mirror: bool = await _place_item(IDs.I.MIRROR, _mirror)
	ok("c0: зеркало поставлено", mirror, str(_mirror))
	var saw: bool = await wait_until(func() -> bool:
		return World.beams.color_at(_burner + Vector2i(1, 0)) == Beams.R, 4.0)
	ok("c0: свой луч красный", saw, _beam_at(_burner + Vector2i(1, 0)))
	await barrier("placed")
	await barrier("lit")
	var host_beam = share_get("beam")
	ok("c0: карта луча побайтно как у хоста", host_beam is PackedByteArray and host_beam == _cells_blob(),
			"клиент %d Б, хост %s" % [_cells_blob().size(),
			str((host_beam as PackedByteArray).size()) if host_beam is PackedByteArray else "?"])
	# Поворот — ПКМ по зеркалу. Хост крутит прокси, MACHINE_ADD везёт новый dir.
	ok("c0: до поворота вниз пусто", World.beams.color_at(_spot) == 0, _beam_at(_spot))
	var t0: int = Time.get_ticks_msec()
	aim(World.cell_to_world(_mirror))
	press_mouse(MOUSE_BUTTON_RIGHT)
	await wait(0.2)
	release_mouse(MOUSE_BUTTON_RIGHT)
	var turned: bool = await wait_until(func() -> bool:
		var m: Mirror = World.machines.get(_mirror) as Mirror
		return m != null and (m.dir & 7) == 1 and World.beams.color_at(_spot) == Beams.R, TURN_WAIT)
	var frames: int = int(ceil(float(Time.get_ticks_msec() - t0) / (NET_FRAME_S * 1000.0)))
	print("  ЗАМЕР c0: ПКМ → луч повернулся у клиента: %d кадров сети" % frames)
	ok("c0: луч повернулся за ≤ %d кадров сети" % NET_FRAMES, turned and frames <= NET_FRAMES,
			"%d, клетка %s" % [frames, _beam_at(_spot)])
	await barrier("turned")
	finish()


func _watcher() -> void:
	await barrier("placed")
	var saw: bool = await wait_until(func() -> bool:
		var b: Burner = World.machines.get(_burner) as Burner
		return b != null and World.beams.color_at(_burner + Vector2i(1, 0)) == Beams.R, 6.0)
	ok("c1: видит луч горелки клиента", saw, _beam_at(_burner + Vector2i(1, 0)))
	await barrier("lit")
	var host_beam = share_get("beam")
	ok("c1: карта луча побайтно как у хоста", host_beam is PackedByteArray and host_beam == _cells_blob())
	await barrier("turned")
	var host2 = share_get("beam2")
	var turned: bool = await wait_until(func() -> bool:
		return World.beams.color_at(_spot) == Beams.R, TURN_WAIT)
	ok("c1: после поворота зеркала луч тот же", turned and host2 is PackedByteArray and host2 == _cells_blob(),
			_beam_at(_spot))
	var frames = share_get("turn_frames")
	ok("c1: хост уложился в %d кадра сети" % NET_FRAMES, frames is int and int(frames) <= NET_FRAMES,
			str(frames))
	finish()


func _late(i: int) -> void:
	var nw: NetWorld = Game.net_world
	var got: bool = await wait_until(func() -> bool: return nw.is_joined, 25.0)
	ok("c%d: снимок применён" % i, got)
	if not got:
		await barrier("joined")
		await barrier("snap_ok")
		await barrier("cat")
		finish()
		return
	World.beams.rebuild()
	var host_cells = share_get("cells")
	var mine: PackedByteArray = _cells_blob()
	ok("c%d: beams.cells побайтно равен хосту" % i,
			host_cells is PackedByteArray and host_cells == mine,
			"клиент %d Б, хост %s" % [mine.size(),
			str((host_cells as PackedByteArray).size()) if host_cells is PackedByteArray else "?"])
	var arcs = share_get("arcs")
	ok("c%d: core_arcs равен хосту" % i, arcs is int and Game.core_arcs == int(arcs),
			"клиент %d, хост %s" % [Game.core_arcs, str(arcs)])
	ok("c%d: ядро на месте" % i, Game.core_placed(), str(Game.core_cell))
	ok("c%d: семь блоков базы и ядро на месте" % i, _base_count() == 7 and Game.core_placed(),
			"блоков %d" % _base_count())
	print("  ЗАМЕР c%d снимок входа: %d Б" % [i, nw.snapshot_bytes])
	await barrier("joined")
	await barrier("snap_ok")
	await wait(0.3)
	await barrier("cat")
	var cat_pos = share_get("cat")
	var box: Array = [null]
	var seen: bool = await wait_until(func() -> bool:
		var found: Array = get_tree().get_nodes_in_group("rainbow_cat")
		if found.is_empty():
			return false
		box[0] = found[0]
		return true
	, 4.0)
	var puppet: Node = box[0]
	var dist: float = INF
	if seen and cat_pos is Dictionary and puppet != null:
		var host_at: Vector2 = Vector2(float(cat_pos["x"]), float(cat_pos["y"]))
		dist = puppet.global_position.distance_to(host_at)
	ok("c%d: кот — марионетка в ±1 клетке" % i, seen and dist <= CAT_CELL,
			"%.1f px" % dist)
	finish()


## Поставить предмет из хотбара в клетку. ПКМ идёт прокси на хосте.
func _place_item(item: int, cell: Vector2i) -> bool:
	if await _select(item) < 0:
		return false
	aim(World.cell_to_world(cell))
	press_mouse(MOUSE_BUTTON_RIGHT)
	await wait(0.25)
	release_mouse(MOUSE_BUTTON_RIGHT)
	await wait(0.2)
	var m = World.machines.get(cell)
	return m != null and is_instance_valid(m)


func _feed_burner() -> bool:
	if await _select(IDs.I.COAL) < 0:
		return false
	aim(World.cell_to_world(_burner))
	hold(KEY_E)
	await wait(0.3)
	release(KEY_E)
	await wait(0.2)
	var b: Burner = World.machines.get(_burner) as Burner
	return b != null and (b.burning() or b.fuel_units() > 0)


func _select(item: int) -> int:
	var slot: int = -1
	for k in player.inv.slots.size():
		if player.inv.slots[k].id == item and player.inv.slots[k].count > 0:
			slot = k
			break
	if slot < 0:
		return -1
	if slot >= player.inv.hotbar_size:
		# В хотбар 6 слот 0 освобождаем обменом: цифра выбирает только хотбар.
		var hand: Array = [ItemStack.new()]
		InvOps.xfer(player.inv.slots, slot, hand, 0, player.inv.slots[slot].count, true)
		InvOps.xfer(hand, 0, player.inv.slots, 0, hand[0].count, true)
		slot = 0
	var key: int = KEY_1 + slot if slot < 9 else KEY_0
	hold(key)
	await wait(0.08)
	release(key)
	await wait(0.05)
	return slot if player.inv.selected == slot else -1
