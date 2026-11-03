extends "res://tools/mp/scenarios/mp_balance_common.gd"
## mp_balance_doppel (ADR-002 § 4.8, решение #99 «один двойник»; MP-K, #96): сколько двойник
## живёт до раскрытия и годится ли окно переклички (NetTeam.ANSWER_WINDOW).
##
## Хост и клиенты, кроме последнего, стоят у базы (по 3 клетки), последний клиент —
## в FAR клетках левее: самый отбившийся, жертва. Двойник (штатный Threat.spawn_phantom,
## ночь, директор угрозы молчит — других фантомов нет) появляется ещё на DOPPEL_DX клеток
## дальше, за спиной жертвы (герои смотрят вправо: взгляд не морозит его сразу).
##
## Бот команды — правила § 4.8, как у людей, без подсказок движка:
##  * хост объявляет перекличку (G), как только позволяет кулдаун MP_ROLLCALL_COOLDOWN;
##  * каждый отвечает G через REACT секунд после «перекличка!» (реакция человека);
##  * подозреваемый — «товарищ» в поле зрения (VIEW_PX), у которого во время переклички
##    огонёк красный; узнанного двойника герой бьёт, когда тот подошёл на удар;
##  * ударили героя — он бьёт того, кто рядом (самооборона).
## Меряем: время жизни двойника до первого удара по нему (раскрытие, TEAM.REVEAL), урон
## героям до раскрытия. Вторая фаза — без двойника, CALLS_B перекличек подряд: задержка
## ответа по сети (минус REACT) и доля окна после ответа, когда у уже ответившего
## настоящего товарища огонёк снова красный — «ложный двойник» (если огонёк
## MP_ROLLCALL_LIGHT короче окна NetTeam.ANSWER_WINDOW).

const FAR: int = 40
const NEAR: int = 3
const DOPPEL_DX: int = 18
const LIMIT: float = 90.0        ## не раскрыт за столько — пишем предел
const REACT: float = 1.5         ## реакция человека на «перекличка!», с
const VIEW_PX: float = 320.0     ## «вижу на экране»
const CALLS_B: int = 2           ## перекличек во второй фазе (без двойника)


# ------------------------------------------------------------------ ХОСТ

func run_host() -> void:
	if not await host_join():
		finish()
		return
	await barrier("in")
	clear_phantoms()
	if clients < 1:
		print("  SKIP один герой — маски нет, двойник как в одиночной (§ 4.8)")
		metric_na("doppel_life", "N = 1: двойник без маски")
		await barrier("done", -1, 30.0)
		finish()
		return
	Game.time_of_day = 0.30
	var sx: int = World.world_to_cell(World.spawn_point).x
	var placed: bool = true
	for k in heroes_n():
		var x: int = sx - FAR if k == heroes_n() - 1 else sx + NEAR * k
		placed = await place_hero(k, surface_stand(x)) and placed
	ok("герои у базы, жертва в %d клетках" % FAR, placed)
	await barrier("placed")
	Game.time_of_day = Balance.NIGHT_START + 0.02
	await wait(0.5)
	var victim: Player = heroes()[heroes_n() - 1]
	var made: Array = Threat.spawn_phantom("doppel", surface_stand(sx - FAR - DOPPEL_DX))
	ok("двойник появился", not made.is_empty())
	if made.is_empty():
		await barrier("go")
		await barrier("end")
		await barrier("shared")
		await barrier("done")
		finish()
		return
	var dop: Phantom = made[0]
	await barrier("go")
	var t0: float = Game.game_time
	var hp0: Array = []
	for h in heroes():
		hp0.append((h as Player).hp)
	night_track_begin()
	var revealed: float = -1.0
	var dmg_before: float = 0.0
	var calls: int = 0
	var was_on: bool = false
	var t_call: float = 0.0
	var lat: Array = []
	var answered: Dictionary = {}
	while Game.game_time - t0 < LIMIT and revealed < 0.0 and is_instance_valid(dop) and dop.alive:
		bot_step()
		night_track_step()
		# Перекличка: задержка ответа каждого прокси (rollcall_t > 0 ставит хост по ответу).
		var on: bool = NetTeam.rollcall_on()
		if on and not was_on:
			calls += 1
			t_call = Game.game_time
			answered.clear()
		if on:
			for k in range(1, heroes_n()):
				var h: Player = heroes()[k]
				if h != null and h.rollcall_t > 0.0 and not answered.has(k):
					answered[k] = true
					lat.append(Game.game_time - t_call - REACT)
		was_on = on
		if dop.net_reveal_t > 0.0:
			revealed = Game.game_time - t0
		await get_tree().process_frame
	var r: Dictionary = night_track_result()
	dmg_before = asum(r["dmg"])
	stop_fight()
	var life: float = revealed if revealed >= 0.0 else LIMIT
	var mask_nick: String = dop.nick if is_instance_valid(dop) else "?"
	await barrier("end", -1, 30.0)
	# --- Фаза 2: только перекличка (двойника нет) — калибровка окна. Счёт «ложного
	# красного» с нуля у всех: до этого окна обрывались раскрытием.
	clear_phantoms()
	_known = null
	_fr_frames = 0
	_win_frames = 0
	var t1: float = Game.game_time
	var calls_b: int = 0
	was_on = NetTeam.rollcall_on()
	while Game.game_time - t1 < Balance.MP_ROLLCALL_COOLDOWN * float(CALLS_B) + 12.0:
		bot_step()
		var on_b: bool = NetTeam.rollcall_on()
		if on_b and not was_on:
			calls_b += 1
			t_call = Game.game_time
			answered.clear()
		if on_b:
			for k in range(1, heroes_n()):
				var h: Player = heroes()[k]
				if h != null and h.rollcall_t > 0.0 and not answered.has(k):
					answered[k] = true
					lat.append(Game.game_time - t_call - REACT)
		if not on_b and was_on and calls_b >= CALLS_B:
			break
		was_on = on_b
		await get_tree().process_frame
	stop_fight()
	await barrier("end2", -1, 30.0)
	await barrier("shared", -1, 30.0)
	var fr_frames: int = _fr_frames
	var win_frames: int = _win_frames
	for i in clients:
		var v = share_get("dop_%d" % i)
		if v is Dictionary:
			fr_frames += int(v["fr"])
			win_frames += int(v["win"])
	var false_red: float = float(fr_frames) / float(maxi(1, win_frames))
	print("  [двойник, N = %d] маска «%s», жертва «%s»; раскрыт %s; урон героям до раскрытия %.0f (жертве %.0f); переклички %d + %d без двойника, ответ по сети %s с; у ответившего товарища огонёк снова красный %.0f %% окна (окно %.1f с, огонёк %.1f с)" % [
			heroes_n(), mask_nick, victim.nick,
			("через %.1f с" % revealed) if revealed >= 0.0 else "НЕТ за %.0f с" % LIMIT,
			dmg_before, float(r["dmg"][heroes_n() - 1]), calls, calls_b,
			"%.2f" % mean(lat) if not lat.is_empty() else "—", false_red * 100.0,
			NetTeam.ANSWER_WINDOW, Balance.MP_ROLLCALL_LIGHT])
	metric("doppel_life", life, "с от появления до первого удара по двойнику")
	metric("doppel_dmg", dmg_before, "урон героям до раскрытия")
	metric("doppel_calls", float(calls))
	if not lat.is_empty():
		metric("rollcall_net_lat", mean(lat), "задержка ответа на перекличку по сети (без реакции), с")
	metric("rollcall_false_red", false_red, "доля окна после ответа: огонёк ответившего товарища снова красный")
	ok("перекличек без двойника: %d" % CALLS_B, calls_b >= CALLS_B, "%d" % calls_b)
	ok("двойник раскрыт за %.0f с" % LIMIT, revealed >= 0.0, "%.1f с" % life)
	await barrier("done", -1, 30.0)
	var keys: Array = []
	for i in clients:
		keys.append("dop_%d" % i)
	share_clear(keys)
	clear_phantoms()
	finish()


# ------------------------------------------------------------------ КЛИЕНТЫ

func run_client(i: int) -> void:
	await barrier("in", -1, 60.0)
	if clients < 1:
		await barrier("done", -1, 30.0)
		finish()
		return
	await barrier("placed", -1, 60.0)
	await barrier("go", -1, 60.0)
	wait_end_async("end", LIMIT + 30.0)
	while not _end_flag:
		bot_step()
		await get_tree().process_frame
	stop_fight()
	_known = null
	_fr_frames = 0
	_win_frames = 0
	wait_end_async("end2", Balance.MP_ROLLCALL_COOLDOWN * float(CALLS_B) + 40.0)
	while not _end_flag:
		bot_step()
		await get_tree().process_frame
	stop_fight()
	share_put("dop_%d" % i, {"fr": _fr_frames, "win": _win_frames})
	await barrier("shared", -1, 30.0)
	await barrier("done", -1, 30.0)
	finish()


# ------------------------------------------------------------------ БОТ КОМАНДЫ (свой герой)

var _g_left: int = 0               ## физ. кадров ещё держать G
var _answered: bool = false
var _known: Node2D = null          ## узнанный двойник
var _my_hp: float = -1.0
var _fr_frames: int = 0            ## кадров окна: ответивший товарищ в поле зрения — красный
var _win_frames: int = 0           ## кадров окна: ответивший товарищ в поле зрения
var _green_seen: Dictionary = {}   ## instance_id товарища → в этом окне был зелёным


func bot_step() -> void:
	if _g_left > 0:
		_g_left -= 1
		if _g_left == 0:
			release(KEY_G)
	var nt: NetTeam = NetTeam.instance
	if nt == null:
		return
	var on: bool = NetTeam.rollcall_on()
	# Хост — зовёт перекличку, как только можно.
	if is_host_side() and not on and nt.cooldown_left(player) <= 0.0 and _g_left == 0:
		_press_g()
	# Ответ через REACT.
	if not on:
		_answered = false
	elif not _answered and nt.window_left <= NetTeam.ANSWER_WINDOW - REACT and _g_left == 0:
		_answered = true
		if NetTeam.lamp_state(player) != NetTeam.Lamp.GREEN:
			_press_g()
	# Кто в поле зрения «в виде товарища»: настоящие и двойник. Настоящий, у которого в
	# этом окне огонёк уже был зелёным (ответил), а теперь красный, — «ложный двойник».
	if not on:
		_green_seen.clear()
	if on:
		for h in Game.players:
			var o: Player = h as Player
			if o == null or o == player or o.dead or o.global_position.distance_to(player.global_position) > VIEW_PX:
				continue
			var lamp: int = NetTeam.lamp_state(o)
			if lamp == NetTeam.Lamp.GREEN:
				_green_seen[o.get_instance_id()] = true
			if _green_seen.has(o.get_instance_id()):
				_win_frames += 1
				if lamp == NetTeam.Lamp.RED:
					_fr_frames += 1
		for p in get_tree().get_nodes_in_group("phantom"):
			var ph: Phantom = p as Phantom
			if ph == null or not ph.alive or ph.kind != "doppel" or not ph.visible:
				continue
			if ph.global_position.distance_to(player.global_position) <= VIEW_PX \
					and NetTeam.lamp_state(ph) == NetTeam.Lamp.RED:
				_known = ph
	# Самооборона: ударили — бьём ближайшего в маске.
	if _my_hp >= 0.0 and player.hp < _my_hp:
		var near: Node2D = _nearest_doppel(60.0)
		if near != null:
			_known = near
	_my_hp = player.hp
	if _known != null and is_instance_valid(_known) and bool(_known.get("alive")) \
			and _known.global_position.distance_to(player.global_position) < 44.0:
		aim(_known.global_position)
		press_mouse(MOUSE_BUTTON_LEFT)
	else:
		release_mouse(MOUSE_BUTTON_LEFT)


func _press_g() -> void:
	hold(KEY_G)
	_g_left = 4


func _nearest_doppel(d: float) -> Node2D:
	var best: Node2D = null
	for p in get_tree().get_nodes_in_group("phantom"):
		var ph: Phantom = p as Phantom
		if ph == null or not ph.alive or ph.kind != "doppel":
			continue
		var dd: float = ph.global_position.distance_to(player.global_position)
		if dd < d:
			d = dd
			best = ph
	return best
