extends "res://tools/mp/scenarios/mp_threat_base.gd"
## mp_phantoms (ADR-002 § 4.2.5, § 4.3; MP-F, #92): фантомы по сети.
##
## Хост и два клиента; герои стоят в 28 клетках друг от друга (хост в середине).
## Хост ставит 16 фантомов (стая роя, двойник, эхо) вокруг героев. Проверки:
##  * хост: цель каждого фантома — ближайший доступный герой; клиент 0 спрятался —
##    его никто не выбирает, вылез — снова цель;
##  * клиенты: фантомы зоны интереса есть, это марионетки — ИИ не работает (возраст,
##    перестроения пути, путь — нули), вид и позиции совпадают с хостом;
##  * движение: фантомы гонятся за героями 4 с — ошибка позиции у клиента против
##    траектории хоста в тот же момент часов хоста p95 ≤ 24 px (§ 4.10);
##  * двойник замирает под взглядом любого героя (клиента 1); окно у клиента
##    открыто (бит ввода) — не замирает; отвернулся — не замирает; у клиента флаг тот же.
## Замер: STATE Б/с на клиента и доля фантомов (12 Б × строк), ошибка марионеток.

const REC_SEC: float = 4.0
const ERR_MAX: float = 24.0
const SEP: int = 28            ## клеток между героями

var _rec: bool = false
## Хост: номер → [часы хоста, x, y, …]; клиент: номер → [время рисования, x, y, …].
var _traj: Dictionary = {}


func _physics_process(_delta: float) -> void:
	if not _rec or not is_host_side():
		return
	var t: float = np().host_time()
	for p in alive_phantoms():
		var ph: Phantom = p
		if ph.net_id == 0:
			continue
		var a: PackedFloat64Array = _traj.get(ph.net_id, PackedFloat64Array())
		a.append_array([t, ph.global_position.x, ph.global_position.y])
		_traj[ph.net_id] = a


func _process(_delta: float) -> void:
	if not _rec or is_host_side() or nph() == null:
		return
	var t: float = np().render_time
	for id in nph().puppets:
		var ph: Phantom = nph().puppets[id] as Phantom
		if ph == null or not is_instance_valid(ph) or not ph.visible:
			continue
		var a: PackedFloat64Array = _traj.get(id, PackedFloat64Array())
		a.append_array([t, ph.global_position.x, ph.global_position.y])
		_traj[id] = a


# ------------------------------------------------------------------ ХОСТ

func run_host() -> void:
	ok("хост + %d клиента вошли" % clients, await wait_players(1 + clients, 45.0))
	ok("прокси обоих клиентов с вводом", await wait_proxies(clients, 10.0))
	await barrier("in")
	var p0: Player = hero_of(0)
	var p1: Player = hero_of(1)
	if p0 == null or p1 == null:
		finish()
		return
	var sx: int = World.world_to_cell(World.spawn_point).x
	player.global_position = surface_stand(sx)
	player.vel = Vector2.ZERO
	ok("клиент 0 переставлен", await teleport_proxy(p0, surface_stand(sx - SEP)))
	ok("клиент 1 переставлен", await teleport_proxy(p1, surface_stand(sx + SEP)))
	invulnerable_all()
	Game.time_of_day = Balance.NIGHT_START + 0.02
	var n: int = await spawn_sixteen([p0, player, p1], p1)
	ok("16 фантомов у хоста (стая роя, двойник, эхо)", n == Balance.MAX_PHANTOMS, "%d" % n)

	# --- Цель — ближайший доступный герой. Фантомы оглушены — стоят на месте.
	for p in alive_phantoms():
		(p as Phantom).stun = 60.0
	await wait(0.8)
	ok("цель каждого фантома — ближайший герой", _targets_nearest(), _target_note())
	p0.hiding = true
	p0.hide_timer = 30.0
	await wait(0.8)
	ok("клиент 0 спрятался — его не выбирают, цель — ближайший из остальных",
			_targets_nearest() and _pursuers(p0) == 0, _target_note())
	p0.hiding = false
	p0.hide_timer = 0.0
	await wait(0.8)
	ok("вылез — снова цель ближайших", _targets_nearest() and _pursuers(p0) > 0, _target_note())
	var by: Dictionary = {}
	for p in alive_phantoms():
		var ph: Phantom = p
		by[ph.net_id] = [ph.global_position, ph.kind]
	var aoi: Array = [_in_aoi(p0), _in_aoi(p1)]
	ok("объявлено клиентам 16", nph().known_count() == n, "%d" % nph().known_count())
	share_put("static", {"pos": by, "aoi": aoi})
	await barrier("spawned")
	await barrier("checked")

	# --- Погоня: траектории хоста против марионеток клиентов.
	for p in alive_phantoms():
		(p as Phantom).stun = 0.0
		(p as Phantom).alert = 30.0
	_traj.clear()
	var sent0: int = int(Net.sent_bytes.get(NetCodec.Msg.STATE, 0))
	var rows0: int = int(nph().stats["rows"])
	var t0: int = Time.get_ticks_msec()
	_rec = true
	await barrier("go")
	await wait(REC_SEC)
	_rec = false
	var sec: float = float(Time.get_ticks_msec() - t0) / 1000.0
	var st_bps: float = float(int(Net.sent_bytes.get(NetCodec.Msg.STATE, 0)) - sent0) / sec / float(clients)
	var ph_bps: float = float(int(nph().stats["rows"]) - rows0) * NetCodec.PHANTOM_BYTES / sec / float(clients)
	print("  ЗАМЕР STATE хост → клиент (3 игрока, фантомов в зоне %d/%d): %.0f Б/с кадров, из них фантомы %.0f Б/с (%d Б × строк); с накладными ≤ %.0f Б/с" % [
			aoi[0], aoi[1], st_bps, ph_bps, NetCodec.PHANTOM_BYTES, st_bps + Net.TICK_HZ * 72])
	ok("фантомы гнались (сдвиг от начала)", _moved() > 40.0, "%.0f px" % _moved())
	share_put("traj", _traj)
	await barrier("rec")
	await barrier("compared")

	# --- Двойник под взглядом клиента 1.
	var dop: Phantom = _doppel()
	ok("двойник жив", dop != null)
	if dop != null:
		dop.speed_mul = 0.0
		dop.stun = 0.0
		for p in alive_phantoms():
			if p != dop:
				(p as Phantom).stun = 60.0   # остальные не мешают (не толкают героя)
		dop.global_position = _doppel_spot(dop, p1)
		dop.vel = Vector2.ZERO
		share_put("dop", {"dir": 1 if dop.global_position.x > p1.global_position.x else -1})
	await barrier("face")
	await barrier("faced")
	await wait(0.5)
	if dop != null:
		ok("двойник замер под взглядом клиента 1", dop.frozen,
				"%.0f px, взгляд %d, окно %s, обзор %s, копка %s" % [dop.global_position.distance_to(p1.global_position),
				p1.facing, str(p1.net_window_open), str(dop._compute_los(World.world_to_cell(dop.global_position),
				World.world_to_cell(p1.global_position))), str(p1.mining_cell)])
		ok("цель двойника — клиент 1 (ближайший)", dop.player == p1)
	await barrier("frozen")
	await barrier("window")
	await wait(0.5)
	if dop != null:
		ok("окно у клиента 1 открыто (бит ввода) — двойник не замер", p1.net_window_open and not dop.frozen,
				"окно %s, замер %s" % [str(p1.net_window_open), str(dop.frozen)])
	await barrier("window_seen")
	await barrier("away")
	await wait(0.5)
	if dop != null:
		ok("клиент 1 отвернулся — двойник не замер", not dop.frozen, "взгляд %d" % p1.facing)
	await barrier("done")
	share_clear(["static", "traj", "dop"])
	clear_phantoms()
	finish()


func _targets_nearest() -> bool:
	for p in alive_phantoms():
		var ph: Phantom = p
		if ph.player != nearest_target(ph.global_position):
			return false
	return true


func _pursuers(h: Player) -> int:
	var n: int = 0
	for p in alive_phantoms():
		if (p as Phantom).player == h:
			n += 1
	return n


func _target_note() -> String:
	var parts: Array = []
	for h in Game.players:
		parts.append("%s %d" % [(h as Player).nick, _pursuers(h)])
	return ", ".join(parts)


func _in_aoi(h: Player) -> int:
	var n: int = 0
	for p in alive_phantoms():
		var d: Vector2 = (p as Node2D).global_position - h.global_position
		if absf(d.x) <= Net.AOI_HALF.x and absf(d.y) <= Net.AOI_HALF.y:
			n += 1
	return n


func _moved() -> float:
	var best: float = 0.0
	for id in _traj:
		var a: PackedFloat64Array = _traj[id]
		if a.size() >= 6:
			best = maxf(best, Vector2(a[1], a[2]).distance_to(Vector2(a[a.size() - 2], a[a.size() - 1])))
	return best


func _doppel() -> Phantom:
	for p in alive_phantoms():
		if (p as Phantom).kind == "doppel":
			return p
	return null


## Точка в 3–7 клетках от героя на поверхности с прямой видимостью до него.
func _doppel_spot(dop: Phantom, h: Player) -> Vector2:
	var hc: Vector2i = World.world_to_cell(h.global_position)
	for dx in [5, -5, 4, -4, 6, -6, 3, -3, 7, -7]:
		var s: Vector2 = surface_stand(hc.x + int(dx))
		if s.distance_to(h.global_position) < Balance.DOPPEL_GAZE_PX * 0.6 				and dop._compute_los(World.world_to_cell(s), hc):
			return s
	return h.global_position + Vector2(64.0, 0.0)


# ------------------------------------------------------------------ КЛИЕНТЫ

func client_args(i: int) -> PackedStringArray:
	return PackedStringArray(["--nick=" + ["Аня", "Борис"][i]])


func run_client(i: int) -> void:
	await barrier("in")
	await barrier("spawned")
	var st = share_get("static")
	var want: int = int((st as Dictionary)["aoi"][i]) if st is Dictionary else -1
	var seen: bool = await wait_until(func() -> bool: return _visible() >= want and want > 0, 5.0)
	ok("c%d: фантомы зоны интереса видны (%d)" % [i, want], seen, "видно %d из %d марионеток" % [
			_visible(), nph().puppets.size()])
	ok("c%d: все 16 объявлены (SPAWN)" % i, nph().puppets.size() == Balance.MAX_PHANTOMS,
			"%d" % nph().puppets.size())
	ok("c%d: у клиента ИИ фантомов не работает" % i, _no_ai(), _ai_note())
	ok("c%d: директор угрозы у клиента молчит" % i, not Threat.is_processing())
	if st is Dictionary:
		var by: Dictionary = st["pos"]
		var worst: float = 0.0
		var kinds_ok: bool = true
		for id in nph().puppets:
			var ph: Phantom = nph().puppets[id]
			if not by.has(id) or not ph.visible:
				continue
			worst = maxf(worst, ph.global_position.distance_to(by[id][0]))
			kinds_ok = kinds_ok and ph.kind == String(by[id][1])
		ok("c%d: вид и позиции оглушённых фантомов = хост" % i, kinds_ok and worst <= 1.0,
				"расхождение до %.2f px" % worst)
		ok("c%d: оглушение видно (флаг и таймер)" % i, _all_stunned())
	await barrier("checked")
	_traj.clear()
	_rec = true
	await barrier("go")
	await wait(REC_SEC)
	_rec = false
	await barrier("rec")
	var ref = share_get("traj")
	ok("c%d: траектории хоста получены" % i, ref is Dictionary and not (ref as Dictionary).is_empty())
	if ref is Dictionary:
		var e: PackedFloat32Array = _errors(ref)
		ok("c%d: ошибка позиции фантомов p95 ≤ %d px" % [i, int(ERR_MAX)], e.size() > 200 and p95(e) <= ERR_MAX,
				"p95 %.2f px, max %.2f px, n=%d" % [p95(e), vmax(e), e.size()])
		print("  ЗАМЕР c%d: ошибка марионеток фантомов p95 %.2f px, max %.2f px (задержка рисования %d мс)" % [
				i, p95(e), vmax(e), int(Net.INTERP_DELAY * 1000.0)])
	ok("c%d: пока гнались — ИИ у клиента так и не работал" % i, _no_ai(), _ai_note())
	await barrier("compared")
	await barrier("face")
	if i == 1:
		var d = share_get("dop")
		var dir: int = int((d as Dictionary).get("dir", 1)) if d is Dictionary else 1
		await _tap(KEY_D if dir > 0 else KEY_A)
	await barrier("faced")
	await barrier("frozen")
	if i == 1:
		var dop: Phantom = _puppet_doppel()
		ok("c1: у марионетки двойника флаг «замер»", dop != null and dop.frozen)
		UI.journal.visible = true       # окно открыто — бит BIT_WINDOW во вводе
		await wait(0.2)
	await barrier("window")
	await barrier("window_seen")
	if i == 1:
		UI.journal.visible = false
		var d2 = share_get("dop")
		var dir2: int = int((d2 as Dictionary).get("dir", 1)) if d2 is Dictionary else 1
		await _tap(KEY_A if dir2 > 0 else KEY_D)
	await barrier("away")
	await barrier("done")
	finish()


func _tap(code: int) -> void:
	hold(code)
	await wait(0.05)
	release(code)
	await wait(0.25)


func _visible() -> int:
	var n: int = 0
	for id in nph().puppets:
		var ph: Phantom = nph().puppets[id]
		if is_instance_valid(ph) and ph.visible:
			n += 1
	return n


func _no_ai() -> bool:
	if nph().puppets.is_empty():
		return false
	for id in nph().puppets:
		var ph: Phantom = nph().puppets[id]
		if not ph.net_puppet or ph._age != 0.0 or ph.rebuilds != 0 or not ph.path.is_empty():
			return false
	return true


func _ai_note() -> String:
	var age: float = 0.0
	var reb: int = 0
	for id in nph().puppets:
		var ph: Phantom = nph().puppets[id]
		age = maxf(age, ph._age)
		reb += ph.rebuilds
	return "марионеток %d, возраст ИИ %.2f с, перестроений пути %d" % [nph().puppets.size(), age, reb]


func _all_stunned() -> bool:
	for id in nph().puppets:
		var ph: Phantom = nph().puppets[id]
		if ph.visible and ph.stun <= 0.0:
			return false
	return true


func _puppet_doppel() -> Phantom:
	for id in nph().puppets:
		var ph: Phantom = nph().puppets[id]
		if ph.kind == "doppel":
			return ph
	return null


## Для каждого кадра клиента (время рисования, позиция) — позиция того же фантома
## на хосте в тот же миг часов хоста (линейно между кадрами хоста).
func _errors(ref: Dictionary) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	for id in _traj:
		if not ref.has(id):
			continue
		var h: PackedFloat64Array = ref[id]
		var c: PackedFloat64Array = _traj[id]
		var j: int = 0
		for k in range(0, c.size(), 3):
			var t: float = c[k]
			while j + 5 < h.size() and h[j + 3] <= t:
				j += 3
			if j + 5 >= h.size() or t < h[j] or t > h[j + 3]:
				continue
			var f: float = (t - h[j]) / maxf(h[j + 3] - h[j], 0.000001)
			var hp: Vector2 = Vector2(h[j + 1], h[j + 2]).lerp(Vector2(h[j + 4], h[j + 5]), f)
			out.append(hp.distance_to(Vector2(c[k + 1], c[k + 2])))
	return out
