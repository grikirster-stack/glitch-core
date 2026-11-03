extends "res://tools/mp/scenarios/mp_threat_base.gd"
## mp_doppel (ADR-002 § 4.8, § 4.7 «Миникарта», D12; MP-J, #95): двойник среди своих.
##
## Хост и три клиента (4 игрока — один двойник, решение #99). Хост, Борис (c1) и Вера (c2)
## стоят у базы в 3 клетках друг от друга, Аня (c0) — в 40 клетках: она самая отбившаяся.
## Двойник появляется рядом с Аней. Проверки:
##  * жертва — Аня (максимум дистанции до ближайшего товарища), маска — Борис (дальше всех
##    от жертвы): у хоста и у каждого клиента над двойником ник «Борис» (тот же NickTag),
##    вид — Look Бориса;
##  * миникарта: маячок товарища — только ближе 20 клеток или в зоне питания (правило
##    § 4.7 у каждого клиента); двойника на ней нет;
##  * перекличка: Борис жмёт G — у всех «Борис: перекличка!»; хост, Аня и Вера отвечают G —
##    огоньки зелёные у всех героев, у двойника в маске Бориса — красный (он не отвечает);
##    повтор G после переклички — кулдаун 20 с;
##  * удар по своему: Борис бьёт хоста, хост бьёт Веру — урона нет, «клац» (у клиентов
##    звук в точке), кулдаун удара 1 с;
##  * удар по двойнику (Аня, ЛКМ по марионетке): двойник получает урон и «глючит»
##    MP_DOPPEL_REVEAL у хоста и у клиентов (TEAM.REVEAL), всплеск GlitchFx у Ани.
## Замер (Вера, 3 товарища и маячки): HUD мкс/кадр с разделом команды и без него; узлы
## и объекты за ALLOC_SEC секунд.

const FAR: int = 40             ## клеток от базы до Ани
const NEAR: int = 3             ## клеток между героями у базы
const WAIT: float = 6.0
const MEASURE_SEC: float = 3.0
const ALLOC_SEC: float = 10.0
const NICKS: Array = ["Аня", "Борис", "Вера"]
const LOOKS: Array = [0x0003, 0x2315, 0x1104]

var _texts: Array = []


func _on_note(text: String, _color: Color) -> void:
	_texts.append(text)


func _has_note(prefix: String) -> bool:
	for t in _texts:
		if String(t).begins_with(prefix):
			return true
	return false


func team() -> NetTeam:
	return NetTeam.instance


func client_args(i: int) -> PackedStringArray:
	return PackedStringArray(["--nick=" + String(NICKS[i]), "--look=%d" % int(LOOKS[i])])


func _tap(code: int) -> void:
	hold(code)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	release(code)


func _slash(pos: Vector2) -> void:
	aim(pos)
	press_mouse(MOUSE_BUTTON_LEFT)
	await wait(0.2)
	release_mouse(MOUSE_BUTTON_LEFT)


# ------------------------------------------------------------------ ХОСТ

func run_host() -> void:
	Game.notification.connect(_on_note)
	ok("хост + %d клиента вошли" % clients, await wait_players(1 + clients, 45.0))
	ok("прокси всех клиентов с вводом", await wait_proxies(clients, 10.0))
	await barrier("in")
	var p0: Player = hero_of(0)
	var p1: Player = hero_of(1)
	var p2: Player = hero_of(2)
	if p0 == null or p1 == null or p2 == null or team() == null:
		ok("герои и NetTeam на месте", false)
		finish()
		return
	var sx: int = World.world_to_cell(World.spawn_point).x
	player.global_position = surface_stand(sx)
	player.vel = Vector2.ZERO
	ok("Аня отбилась на %d клеток" % FAR, await teleport_proxy(p0, surface_stand(sx - FAR)))
	ok("Борис у базы", await teleport_proxy(p1, surface_stand(sx + NEAR)))
	ok("Вера у базы", await teleport_proxy(p2, surface_stand(sx - NEAR)))
	invulnerable_all()
	clear_phantoms()
	await wait(0.1)
	var made: Array = Threat.spawn_phantom("doppel", _doppel_spot(p0))
	var dop: Phantom = made[0] as Phantom if not made.is_empty() else null
	ok("двойник появился рядом с Аней", dop != null)
	if dop == null:
		finish()
		return
	dop.speed_mul = 0.0             # стоит: по нему бьют, он никого не догоняет
	var masked: bool = await wait_until(func() -> bool:
		return dop.nick != "" and dop.net_id != 0 and int(team().stats["masks_tx"]) > 0, WAIT)
	ok("жертва — самая отбившаяся (Аня)", dop.player == p0, _who(dop.player))
	ok("маска — товарищ дальше всех от жертвы (Борис): ник и вид", masked and dop.nick == p1.nick
			and dop.look == p1.look and dop.net_mask_peer == p1.peer_id,
			"ник «%s», вид %d (у Бориса %d)" % [dop.nick, dop.look, p1.look])
	var tag: Node = dop.get_node_or_null("NickTag")
	ok("над двойником тот же NickTag, что у товарищей", tag != null and tag.call("text") == p1.nick)
	ok("HUD хоста: 3 товарища, маячки — по правилу, двойника на карте нет", _map_ok())
	share_put("dop", {"id": dop.net_id, "pos": dop.global_position})
	await barrier("masked")
	await barrier("map")

	# --- Перекличка: Борис зовёт, остальные отвечают.
	await barrier("call")
	var called: bool = await wait_until(func() -> bool: return int(team().stats["calls"]) >= 1, WAIT)
	ok("Борис начал перекличку (G через шов прокси)", called and team().caller_nick == p1.nick
			and _has_note(p1.nick + ": перекличка!"), "%s" % str(team().stats))
	ok("кулдаун переклички у Бориса — %d с" % int(Balance.MP_ROLLCALL_COOLDOWN),
			team().cooldown_left(p1) > Balance.MP_ROLLCALL_COOLDOWN - 3.0, "%.1f с" % team().cooldown_left(p1))
	await _tap(KEY_G)               # свой герой хоста отвечает
	var answered: bool = await wait_until(func() -> bool: return int(team().stats["answers"]) >= 3, WAIT)
	ok("ответили хост, Аня и Вера", answered, "%s" % str(team().stats))
	ok("огоньки всех героев зелёные, перекличка идёт", NetTeam.rollcall_on() and _all_green(),
			_lamps())
	ok("у двойника в маске Бориса огонёк красный — он не отвечает", dop.nick == p1.nick
			and NetTeam.lamp_state(dop) == NetTeam.Lamp.RED)
	await barrier("answered")
	await barrier("seen")
	ok("перекличка окончена", await wait_until(func() -> bool: return not NetTeam.rollcall_on(), WAIT + 1.0))
	var cd0: int = int(team().stats["cooldown"])
	await barrier("again")
	ok("повтор G Бориса — кулдаун, новой переклички нет", await wait_until(func() -> bool:
		return int(team().stats["cooldown"]) > cd0, WAIT) and int(team().stats["calls"]) == 1)
	await barrier("again_seen")

	# --- Удар по своему: Борис бьёт хоста, хост бьёт Веру.
	player.invuln = 0.0
	p2.invuln = 0.0
	var hp_h: float = player.hp
	var hp_v: float = p2.hp
	var f0: int = int(team().stats["friendly"])
	share_put("slash", {"host": player.global_position})
	await barrier("slash")
	ok("Борис ударил хоста — «клац», кулдаун удара", await wait_until(func() -> bool:
		return int(team().stats["friendly"]) > f0, WAIT) and p1.slash_cd > 0.45,
		"кулдаун %.2f с" % p1.slash_cd)
	await wait(0.3)
	await _slash(p2.global_position)
	ok("хост ударил Веру — «клац», кулдаун %.0f с" % Balance.MP_FRIENDLY_SLASH_CD,
			int(team().stats["friendly"]) >= f0 + 2 and player.slash_cd > 0.45, "кулдаун %.2f с" % player.slash_cd)
	ok("свои урона не получили", player.hp == hp_h and p2.hp == hp_v,
			"хост %.0f → %.0f, Вера %.0f → %.0f" % [hp_h, player.hp, hp_v, p2.hp])
	invulnerable_all()
	await barrier("slashed")

	# --- Удар по двойнику: Аня бьёт его ЛКМ.
	var hp0: float = dop.hp
	await barrier("hit")
	var hit: bool = await wait_until(func() -> bool: return dop.hp < hp0, WAIT)
	ok("Аня ударила двойника — урон", hit, "hp %.0f → %.0f" % [hp0, dop.hp])
	ok("двойник «глючит» %.1f с (TEAM.REVEAL)" % Balance.MP_DOPPEL_REVEAL, hit and dop.net_reveal_t > 0.5
			and int(team().stats["reveals"]) >= 1, "%.2f с" % dop.net_reveal_t)
	await barrier("hit_seen")
	await barrier("measured", -1, 40.0)
	await barrier("done")
	Game.notification.disconnect(_on_note)
	share_clear(["dop", "slash"])
	clear_phantoms()
	finish()


func _who(h: Node) -> String:
	return String(h.get("nick")) if h != null and is_instance_valid(h) else "—"


## Точка в 4–5 клетках от героя на поверхности, в досягаемости удара и с прямой видимостью.
func _doppel_spot(h: Player) -> Vector2:
	var hc: Vector2i = World.world_to_cell(h.global_position)
	for dx in [4, -4, 5, -5, 3, -3]:
		var s: Vector2 = surface_stand(hc.x + int(dx))
		if s.distance_to(h.global_position) < Player.REACH - 8.0 and _los_clear(s, h.global_position):
			return s
	return h.global_position + Vector2(56.0, 0.0)


func _all_green() -> bool:
	for h in Game.players:
		if NetTeam.lamp_state(h) != NetTeam.Lamp.GREEN:
			return false
	return true


func _lamps() -> String:
	var parts: Array = []
	for h in Game.players:
		parts.append("%s %d" % [(h as Player).nick, NetTeam.lamp_state(h)])
	return ", ".join(parts)


## HUD этого процесса: товарищи — все герои, кроме своего; маячок — ровно у тех, кто
## проходит правило § 4.7; на карте только герои (двойника нет).
func _map_ok() -> bool:
	var hud: HUD = UI.hud
	if hud == null or hud.team_mates.size() != Game.players.size() - 1:
		return false
	for h in Game.players:
		if h == player:
			continue
		if hud.team_beacons.has(h) != hud.team_beacon_rule(h):
			return false
	for b in hud.team_beacons:
		if not (b is Player):
			return false
	return true


func _map_note() -> String:
	var hud: HUD = UI.hud
	var parts: Array = []
	for h in Game.players:
		if h == player:
			continue
		parts.append("%s %.0f кл.%s%s" % [(h as Player).nick,
				player.global_position.distance_to((h as Player).global_position) / World.TILE,
				" питание" if Game.is_powered((h as Player).global_position) else "",
				" — маячок" if hud != null and hud.team_beacons.has(h) else ""])
	return ", ".join(parts)


# ------------------------------------------------------------------ КЛИЕНТЫ

func run_client(i: int) -> void:
	Game.notification.connect(_on_note)
	var me: String = "c%d" % i
	await barrier("in")
	await barrier("masked")
	var d = share_get("dop")
	var id: int = int((d as Dictionary).get("id", 0)) if d is Dictionary else 0
	var boris: Dictionary = _peer_info(String(NICKS[1]))
	var got: bool = await wait_until(func() -> bool:
		var ph: Phantom = _puppet(id)
		return ph != null and ph.nick != "", WAIT)
	var dop: Phantom = _puppet(id)
	ok("%s: у марионетки двойника ник и вид Бориса" % me, got and dop.nick == String(boris.get("nick", "?"))
			and dop.look == int(boris.get("look", -1)),
			"ник «%s», вид %d" % [dop.nick if dop != null else "", dop.look if dop != null else -1])
	var tag: Node = dop.get_node_or_null("NickTag") if dop != null else null
	ok("%s: ник Бориса над двойником — тем же NickTag" % me, tag != null and tag.call("text") == dop.nick)
	await wait(0.6)               # HUD пересчитывает маячки раз в 0.25 с
	ok("%s: миникарта — маячки по правилу § 4.7, двойника нет" % me, _map_ok(), _map_note())
	if i == 2:
		var near: int = 0
		for b in UI.hud.team_beacons:
			if (b as Player).global_position.distance_to(player.global_position) <= 20.0 * World.TILE:
				near += 1
		ok("c2: маячки товарищей рядом (хост, Борис) на карте", near >= 2, _map_note())
	if i == 0:
		ok("c0: двойник в маске Бориса рядом, а маячка Бориса рядом нет",
				dop != null and dop.global_position.distance_to(player.global_position) < 8.0 * World.TILE
				and not UI.hud.team_beacons.any(func(b) -> bool:
					return (b as Player).global_position.distance_to(dop.global_position) < 4.0 * World.TILE),
				_map_note())
	await barrier("map")

	# --- Перекличка.
	await barrier("call")
	if i == 1:
		await _tap(KEY_G)
	ok("%s: «Борис: перекличка!» на HUD" % me, await wait_until(func() -> bool:
		return _has_note(String(NICKS[1]) + ": перекличка!"), WAIT))
	if i != 1:
		await _tap(KEY_G)
	await barrier("answered")
	ok("%s: свой огонёк зелёный" % me, await wait_until(func() -> bool:
		return NetTeam.lamp_state(player) == NetTeam.Lamp.GREEN, WAIT))
	var all_green: bool = await wait_until(func() -> bool:
		for h in Game.players:
			if NetTeam.lamp_state(h) != NetTeam.Lamp.GREEN:
				return false
		return true, WAIT)
	ok("%s: огоньки товарищей зелёные (PF_ROLLCALL)" % me, all_green, _lamps())
	var real: Player = hero_of(1) if i != 1 else player
	ok("%s: два «Бориса» — настоящий зелёный, двойник красный: перекличка выдаёт" % me,
			real != null and NetTeam.lamp_state(real) == NetTeam.Lamp.GREEN and dop != null
			and dop.nick == real.nick and NetTeam.lamp_state(dop) == NetTeam.Lamp.RED)
	ok("%s: HUD — строка переклички и огоньки в ключе" % me, UI.hud._key[48] > 0
			and (UI.hud._key[51] & 2) != 0)
	await barrier("seen")
	await barrier("again")
	if i == 1:
		await wait_until(func() -> bool: return not NetTeam.rollcall_on(), WAIT + 1.0)
		await wait(0.3)
		await _tap(KEY_G)
		ok("c1: повтор G — «Перекличка — через N с»", await wait_until(func() -> bool:
			return _has_note("Перекличка — через"), WAIT))
	await barrier("again_seen")

	# --- Удар по своему.
	await barrier("slash")
	if i == 1:
		var s = share_get("slash")
		var hp: Vector2 = (s as Dictionary).get("host", Vector2.ZERO) if s is Dictionary else Vector2.ZERO
		await _slash(hp)
	if i == 2:
		ok("c2: «клац» слышен в точке Бориса", await wait_until(func() -> bool:
			var b: Player = hero_of(1)
			return b != null and events_near(NetCodec.Ev.SOUND, "sound", "place", b.global_position, 48.0) > 0, WAIT))
	await barrier("slashed")

	# --- Удар по двойнику.
	await barrier("hit")
	if i == 0 and dop != null:
		await _slash(dop.global_position)
	ok("%s: двойник «глючит» (TEAM.REVEAL)" % me, await wait_until(func() -> bool:
		return dop != null and is_instance_valid(dop) and dop.net_reveal_t > 0.0, WAIT),
		"%s" % str(team().stats))
	if i == 0:
		ok("c0: всплеск GlitchFx «двойник раскрыт»", int(team().stats["reveal_fx"]) >= 1, str(team().stats))
		ok("c0: урон двойника виден (hp марионетки)", dop != null and dop.hp < dop.max_hp,
				"%.0f / %.0f" % [dop.hp if dop != null else 0.0, dop.max_hp if dop != null else 0.0])
	await barrier("hit_seen")
	if i == 2:
		await _measure()
	await barrier("measured", -1, 40.0)
	await barrier("done")
	Game.notification.disconnect(_on_note)
	finish()


func _puppet(id: int) -> Phantom:
	if nph() == null:
		return null
	var ph = nph().puppets.get(id)
	return ph as Phantom if is_instance_valid(ph) else null


func _peer_info(nick: String) -> Dictionary:
	for pid in Net.peers:
		if String(Net.peers[pid].get("nick", "")) == nick:
			return Net.peers[pid]
	return {}


## Замер HUD у Веры (3 товарища, маячки): мкс/кадр с разделом команды и без него;
## узлы и объекты за ALLOC_SEC.
func _measure() -> void:
	var hud: HUD = UI.hud
	var on: Array = await _hud_us(hud, true)
	var off: Array = await _hud_us(hud, false)
	hud.team_on = true
	await wait(0.5)
	var n0: int = get_tree().get_node_count()
	var o0: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var nmax: int = n0
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(ALLOC_SEC * 1000.0):
		await get_tree().process_frame
		nmax = maxi(nmax, get_tree().get_node_count())
	var o1: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	print("  ЗАМЕР HUD c2 (4 игрока, %d маячка): с командой %.1f мкс/кадр (%d кадров), без раздела команды %.1f мкс/кадр" % [
			hud.team_beacons.size(), on[0], on[1], off[0]])
	print("  ЗАМЕР c2 за %.0f с: узлов %d → %d (максимум %d), объектов %d → %d" % [
			ALLOC_SEC, n0, get_tree().get_node_count(), nmax, o0, o1])
	ok("c2: HUD с командой — 0 новых узлов за %.0f с" % ALLOC_SEC, nmax == n0 and get_tree().get_node_count() == n0,
			"%d → %d" % [n0, nmax])
	ok("c2: раздел команды на HUD (3 товарища)", hud.team_mates.size() == 3)


func _hud_us(hud: HUD, on: bool) -> Array:
	hud.team_on = on
	await wait(0.4)
	var us0: int = hud.stat_us
	var f0: int = hud.stat_frames
	await wait(MEASURE_SEC)
	var frames: int = maxi(1, hud.stat_frames - f0)
	return [float(hud.stat_us - us0) / float(frames), frames]
