extends "res://tools/mp/scenarios/mp_players_base.gd"
## mp_move (ADR-002 § 4.2.3, § 4.4; MP-D, #89): движение у владельца, марионетки.
##
## Клиент 0 ходит, бежит и прыгает своим героем (шов ввода, как сценарии ADR-001);
## клиент 1 смотрит на его марионетку. Проверки:
##  * хост: позиция прокси совпадает с позицией владельца из пакета ввода —
##    расхождение p95 ≤ 2 px, ложных поправок нет; прыжок виден на хосте;
##  * клиент 1: марионетка рисуется на INTERP_DELAY в прошлом — её отклонение от
##    траектории прокси хоста в тот же момент часов хоста p95 ≤ 1 клетки;
##  * поправка: хост переставил прокси — владелец оказался там же;
##  * «без связи»: клиент 0 молчит 1.6 с — прокси «без связи», урона не получает;
##    ввод вернулся — снова на связи; урон дошёл владельцу (OWN).
## Замер: расхождение p95 (хост по пакетам; хост ↔ владелец в реальном времени —
## по общим часам машины); ошибка марионетки p95; Б/с вниз и вверх на игрока.

const MOVE_SEC: float = 4.0
const CELL: float = 16.0

var _rec: bool = false
var _ref: PackedFloat64Array = PackedFloat64Array()    ## хост: [часы хоста, x, y] прокси c0
var _wall: PackedFloat64Array = PackedFloat64Array()   ## хост: [общие часы, x, y]; c0: свои
var _pup: PackedFloat64Array = PackedFloat64Array()    ## c1: [время рисования, x, y]
var _target: Player = null


## Хост и владелец пишут траектории по физическим кадрам; клиент 1 — марионетку
## в кадрах отрисовки (её ставит NetPlayers._process, как и видит игрок).
func _physics_process(_delta: float) -> void:
	if not _rec or _target == null:
		return
	var p: Vector2 = _target.global_position
	if is_host_side():
		_ref.append_array([np().host_time(), p.x, p.y])
		_wall.append_array([wall_clock(), p.x, p.y])
	elif role == 0:
		_wall.append_array([wall_clock(), p.x, p.y])


func _process(_delta: float) -> void:
	if _rec and _target != null and role == 1:
		var p: Vector2 = _target.global_position
		_pup.append_array([np().render_time, p.x, p.y])


# ------------------------------------------------------------------ ХОСТ

func run_host() -> void:
	var in_ok: bool = await wait_players(1 + clients, 45.0)
	ok("хост + %d клиента вошли" % clients, in_ok, "игроков %d" % Net.peers.size())
	ok("прокси обоих клиентов с вводом", await wait_proxies(clients, 10.0))
	await barrier("in")
	var p0: Player = hero_of(0)
	if p0 == null:
		finish()
		return
	ok("прокси: роль PROXY, без камеры, ник и вид из списка игроков",
			p0.net_role == Player.NetRole.PROXY and p0.camera == null and p0.nick == "Аня"
			and p0.look == 0x0005, "%s 0x%04X" % [p0.nick, p0.look])
	ok("Game.players: свой + 2 прокси", Game.players.size() == 3 and Game.local_player == player)
	var st: Dictionary = np()._st[p0.peer_id]
	var rej0: int = int(st["rej"])
	var corr0: int = int(st["corr_n"])
	st["err"] = PackedFloat32Array()
	var y0: float = p0.global_position.y
	_target = p0
	_traffic_start()
	_rec = true
	await barrier("go")
	await barrier("moved", -1, MOVE_SEC + 20.0)
	_rec = false
	_traffic_end("движение")

	# --- Хост: позиция прокси против пакетов владельца.
	var err: PackedFloat32Array = st["err"]
	ok("ввод владельца дошёл", err.size() >= int(MOVE_SEC * 20.0), "%d пакетов" % err.size())
	ok("расхождение хост ↔ владелец по пакетам p95 ≤ 2 px", p95(err) <= 2.0,
			"p95 %.3f px, max %.3f px" % [p95(err), vmax(err)])
	ok("ложных поправок нет", int(st["rej"]) == rej0 and int(st["corr_n"]) == corr0,
			"отказов %d, поправок %d" % [int(st["rej"]) - rej0, int(st["corr_n"]) - corr0])
	var top: float = y0
	var xs: PackedFloat32Array = PackedFloat32Array()
	for k in range(0, _ref.size(), 3):
		top = minf(top, float(_ref[k + 2]))
		xs.append(float(_ref[k + 1]))
	ok("прыжок виден на хосте", y0 - top > 20.0, "подъём %.0f px" % (y0 - top))
	ok("ходьба видна на хосте", vmax(xs) - _min(xs) > 60.0, "размах %.0f px" % (vmax(xs) - _min(xs)))
	var c0_wall = share_get("c0_wall")
	if c0_wall is PackedFloat64Array:
		var rt: PackedFloat32Array = _lag(_wall, c0_wall)
		print("  ЗАМЕР хост ↔ владелец в реальном времени (общие часы машины, 60 Гц): p95 %.1f px, max %.1f px, n=%d" % [
				p95(rt), vmax(rt), rt.size()])
	share_put("ref", _ref)
	await barrier("ref")

	# --- Поправка: хост переставляет прокси — владелец там же.
	var back: Vector2 = World.spawn_point
	var moved: bool = await teleport_proxy(p0, back)
	ok("поправка: прокси на месте, владелец принял (новая эпоха)", moved,
			"%.1f px" % p0.global_position.distance_to(back))
	share_put("back", back)
	await barrier("corrected")

	# --- «Без связи»: клиент 0 молчит.
	await barrier("mute")
	await wait(1.4)
	ok("ввода нет > 1 с — прокси «без связи»", not p0.net_linked)
	ok("«без связи» — не цель фантома", not p0.net_targetable())
	var hp0: float = p0.hp
	p0.damage(20.0, Vector2.ZERO)
	ok("«без связи» — урон не проходит", p0.hp == hp0, "hp %.0f → %.0f" % [hp0, p0.hp])
	var back_on: bool = await wait_until(func() -> bool: return p0.net_linked, 3.0)
	ok("ввод вернулся — снова на связи", back_on)
	p0.invuln = 0.0
	p0.damage(20.0, Vector2.ZERO)
	ok("на связи — урон проходит", p0.hp < hp0, "hp %.0f → %.0f" % [hp0, p0.hp])
	await barrier("hurt")
	await barrier("done")
	share_clear(["ref", "c0_wall", "back"])
	finish()


## Отставание прокси от владельца по общим часам: для каждого кадра хоста —
## позиция владельца в тот же миг (линейно между его кадрами).
func _lag(host: PackedFloat64Array, own: PackedFloat64Array) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var j: int = 0
	for k in range(0, host.size(), 3):
		var t: float = host[k]
		while j + 5 < own.size() and own[j + 3] <= t:
			j += 3
		if j + 5 >= own.size() or t < own[j] or t > own[j + 3]:
			continue
		var f: float = (t - own[j]) / maxf(own[j + 3] - own[j], 0.000001)
		var o: Vector2 = Vector2(own[j + 1], own[j + 2]).lerp(Vector2(own[j + 4], own[j + 5]), f)
		out.append(o.distance_to(Vector2(host[k + 1], host[k + 2])))
	return out


static func _min(v: PackedFloat32Array) -> float:
	var m: float = INF
	for x in v:
		m = minf(m, x)
	return m


## Накладные на датаграмму: ENet + RPC ≈ 44 Б (замер ADR-002 § 9.1) + UDP/IP 28 Б.
const DATAGRAM_OVERHEAD: int = 72

var _t0: int = 0
var _sent0: Dictionary = {}


func _traffic_start() -> void:
	_t0 = Time.get_ticks_msec()
	_sent0 = Net.sent_bytes.duplicate()


## Байт в секунду на игрока: кадры (кодек + тип, Net.sent_bytes) и модель § 4.3 с
## накладными DATAGRAM_OVERHEAD на каждое сообщение (верхняя оценка: ENet склеивает
## сообщения одного кадра в одну датаграмму).
func _traffic_end(what: String) -> void:
	var sec: float = maxf(float(Time.get_ticks_msec() - _t0) / 1000.0, 0.001)
	var d: Dictionary = {}
	for m in Net.sent_bytes:
		d[m] = int(Net.sent_bytes[m]) - int(_sent0.get(m, 0))
	if is_host_side():
		var n: int = maxi(Net.peers.size() - 1, 1)
		# События «всем» — одна отправка на всех; STATE (с MP-F свой у каждого: фантомы по
		# зоне интереса), OWN и INV — по каждому.
		var per: float = (float(d.get(NetCodec.Msg.EVENT, 0))
				+ float(d.get(NetCodec.Msg.STATE, 0) + d.get(NetCodec.Msg.OWN, 0) + d.get(NetCodec.Msg.INV, 0)) / n) / sec
		var pkts: float = float(Net.TICK_HZ) * 2.0     # STATE + OWN в секунду
		print("  ЗАМЕР вниз (хост → клиент), %s %.1f с, %d игрока: кадры %.0f Б/с на игрока (STATE %.0f, OWN %.0f, INV %.0f, события %.0f); с накладными ≤ %.0f Б/с" % [
				what, sec, n + 1, per, d.get(NetCodec.Msg.STATE, 0) / n / sec, d.get(NetCodec.Msg.OWN, 0) / n / sec,
				d.get(NetCodec.Msg.INV, 0) / n / sec, d.get(NetCodec.Msg.EVENT, 0) / sec,
				per + pkts * DATAGRAM_OVERHEAD])
	else:
		var up: float = float(d.get(NetCodec.Msg.INPUT, 0)) / sec
		print("  ЗАМЕР вверх (клиент → хост), %s %.1f с: INPUT %.0f Б/с (%d Б × %.1f Гц); с накладными %.0f Б/с" % [
				what, sec, up, NetCodec.INPUT_BYTES + 1, up / float(NetCodec.INPUT_BYTES + 1),
				up + up / float(NetCodec.INPUT_BYTES + 1) * DATAGRAM_OVERHEAD])


# ------------------------------------------------------------------ КЛИЕНТЫ

func client_args(i: int) -> PackedStringArray:
	return PackedStringArray(["--nick=" + ["Аня", "Борис"][i], "--look=%d" % [0x0005, 0x0003][i]])


func run_client(i: int) -> void:
	ok("c%d: свой герой — OWNER с камерой" % i, player.net_role == Player.NetRole.OWNER
			and player.camera != null and Game.local_player == player)
	await barrier("in")
	if i == 0:
		await _mover()
	else:
		await _watcher()
	await barrier("done")
	finish()


func _mover() -> void:
	_target = player
	_traffic_start()
	_rec = true
	await barrier("go")
	# Вправо шагом, прыжок, влево бегом, прыжок, стоп.
	hold(KEY_D)
	await wait(0.9)
	hold(KEY_SPACE)
	await wait(0.15)
	release(KEY_SPACE)
	await wait(0.6)
	release(KEY_D)
	hold_all([KEY_A, KEY_SHIFT])
	await wait(0.9)
	hold(KEY_W)
	await wait(0.15)
	release(KEY_W)
	await wait(0.7)
	release_all()
	await wait(MOVE_SEC - 3.4)
	_rec = false
	_traffic_end("движение")
	share_put("c0_wall", _wall)
	await barrier("moved", -1, 20.0)
	await barrier("ref")
	await barrier("corrected")
	var back = share_get("back")
	var d: float = player.global_position.distance_to(back) if back is Vector2 else INF
	ok("c0: поправка хоста — герой переставлен", d < 12.0, "%.1f px" % d)
	await barrier("mute")
	np().mute_input = true
	await wait(1.6)
	np().mute_input = false
	await barrier("hurt")
	var hurt: bool = await wait_until(func() -> bool: return player.hp < Player.MAX_HP - 1.0, 2.0)
	ok("c0: HP своего героя — с хоста (OWN)", hurt, "hp %.0f" % player.hp)


func _watcher() -> void:
	ok("c1: марионетка клиента 0 есть", await wait_puppets([0], 10.0))
	var pup: Player = hero_of(0)
	if pup != null:
		ok("c1: марионетка — PUPPET без камеры, ник «Аня»", pup.net_role == Player.NetRole.PUPPET
				and pup.camera == null and pup.nick == "Аня")
	_target = pup
	_rec = true
	await barrier("go")
	await barrier("moved", -1, MOVE_SEC + 20.0)
	_rec = false
	await barrier("ref")
	var ref = share_get("ref")
	ok("c1: траектория хоста получена", ref is PackedFloat64Array and (ref as PackedFloat64Array).size() > 30)
	if ref is PackedFloat64Array:
		var e: PackedFloat32Array = _puppet_err(ref, _pup)
		ok("c1: марионетка ≤ 1 клетки от хоста (p95, на INTERP_DELAY в прошлом)", e.size() > 30
				and p95(e) <= CELL, "p95 %.2f px, max %.2f px, n=%d" % [p95(e), vmax(e), e.size()])
		print("  ЗАМЕР c1: ошибка марионетки p95 %.2f px, max %.2f px (задержка рисования %d мс)" % [
				p95(e), vmax(e), int(Net.INTERP_DELAY * 1000.0)])
	await barrier("corrected")
	await barrier("mute")
	await barrier("hurt")


## Для каждого кадра c1 (время рисования, позиция марионетки) — позиция прокси на
## хосте в тот же миг часов хоста (линейно между кадрами хоста).
func _puppet_err(ref: PackedFloat64Array, pup: PackedFloat64Array) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var j: int = 0
	for k in range(0, pup.size(), 3):
		var t: float = pup[k]
		while j + 5 < ref.size() and ref[j + 3] <= t:
			j += 3
		if j + 5 >= ref.size() or t < ref[j] or t > ref[j + 3]:
			continue
		var f: float = (t - ref[j]) / maxf(ref[j + 3] - ref[j], 0.000001)
		var h: Vector2 = Vector2(ref[j + 1], ref[j + 2]).lerp(Vector2(ref[j + 4], ref[j + 5]), f)
		out.append(h.distance_to(Vector2(pup[k + 1], pup[k + 2])))
	return out
