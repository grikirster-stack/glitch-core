class_name NetCoop
extends Node
## Кооператив по сети (ADR-002 § 3 D10, D11, D13; § 4.4, § 4.7, § 4.9; MP-I, #94).
##
## Смерть (D11), только хост решает:
##   * погибший — мешок с хотбаром на месте смерти (Player._die), первые
##     Balance.MP_BAG_OWNER_LOCK с его поднимает только владелец (ItemEntity.net_may_take);
##   * экран «ТЕБЯ НАШЛИ» с отсчётом Balance.MP_RESPAWN_DELAY, камера — за живым
##     товарищем (A/D — следующий); респаун в капсуле на базе, часы НЕ двигаются;
##   * погибли все живые разом (вайп) — правило одиночной: через Balance.RESPAWN_DELAY
##     все на базе, часы к рассвету;
##   * --hardcore в сети: погибший — зритель до конца забега; погибли все — конец забега
##     для всех (Game.State.DEAD уходит глобальным пакетом).
## Владельцу хост шлёт COOP DEATH (отсчёт, вайп, зритель) — экран у клиента знает правду.
##
## Парковка (§ 4.4): игрок вышел или оборвался — его герой (позиция, HP, инвентарь,
## статистика) ждёт по uid в Net.parked; тот же uid вернулся — получает своё. Новый uid —
## стартовый набор один раз (решение #99): у вернувшегося набор, выданный NetPlayers при
## входе, затирается его инвентарём. Отключение не наказывается: хотбар не падает.
##
## Сохранение (D13, § 4.9): только хост, автосохранение на каждом рассвете в слот
## Save.net_auto_slot(имя игры); формат и загрузка — scripts/core/save.gd.
##
## Итоги (§ 4.7, «Статистика»): на конце забега хост шлёт команде COOP STATS — общие
## счётчики и личные смерти по игрокам для экрана итогов.
##
## Без сети узла нет (main.gd создаёт его вместе с NetPlayers).

## Сцена main.gd (свой герой, end_screen, hardcore).
var main: Node = null
## Хост: герой → секунд до респауна (личный отсчёт MP_RESPAWN_DELAY).
var due: Dictionary = {}
## Хост: идёт отсчёт вайпа (секунд до капсул; < 0 — нет вайпа).
var wipe_left: float = -1.0
## Хост: сколько вайпов было за сессию (сценарии).
var wipes: int = 0
## Клиент: итоги с хоста (COOP STATS) — строки личной статистики.
var net_lines: Array = []
## Свой герой: за кем идёт камера, пока он мёртв.
var watching: Player = null
## Клиент: последнее COOP DEATH ({delay, wipe}), пока герой мёртв.
var last_death: Dictionary = {}

var _active: bool = false
var _a_prev: bool = false
var _d_prev: bool = false
var _spectating: bool = false


func start(p_main: Node) -> void:
	main = p_main
	Net.session_started.connect(_begin)
	Net.session_ended.connect(_end)
	Game.player_joined.connect(_on_joined)
	Game.player_left.connect(_on_left)
	Game.day_started.connect(_on_dawn)
	Game.state_changed.connect(_on_state)
	if Net.is_online():
		_begin()


func _begin() -> void:
	_active = true
	due.clear()
	wipe_left = -1.0
	wipes = 0
	net_lines = []
	last_death = {}
	watching = null
	Net.on(NetCodec.Msg.COOP, _on_coop)
	if Net.is_host():
		Net.parked.clear()
	var own: Player = _own()
	if own != null:
		own.net_uid = int(Net.local_profile.get("uid", 0))
		own.net_stats = {"deaths": 0}
	for h in Game.players:
		if h != own and is_instance_valid(h):
			_on_joined(h)


func _end(_reason: String = "") -> void:
	_active = false
	due.clear()
	wipe_left = -1.0
	_stop_spectating()


func _own() -> Player:
	return main.get("player") as Player if main != null else null


func _hardcore() -> bool:
	return main != null and bool(main.get("hardcore"))


# ------------------------------------------------------------------ ВХОД И ВЫХОД (§ 4.4)

func _on_joined(p) -> void:
	if not _active or not (p is Player):
		return
	var info: Dictionary = Net.peers.get(p.peer_id, {})
	p.net_uid = int(info.get("uid", 0))
	if not Net.is_host() or p.net_uid == 0:
		return
	if Net.parked.has(p.net_uid):
		restore_hero(p, Net.parked[p.net_uid])
		Net.parked.erase(p.net_uid)
		print("СЕТЬ: %s вернулся — герой из парковки (uid %d)" % [p.nick, p.net_uid])


func _on_left(p) -> void:
	if not _active or not Net.is_host() or not (p is Player) or not is_instance_valid(p):
		return
	due.erase(p)
	if p.net_uid != 0:
		Net.parked[p.net_uid] = Save.hero_entry(p)
	if watching == p:
		watching = null


## Вернуть герою его запись (парковка или сохранение): позиция, HP, инвентарь,
## статистика. Погибший — в капсулу на базе; в --hardcore погибший остаётся зрителем.
static func restore_hero(p: Player, e: Dictionary) -> void:
	var st = e.get("state", {})
	if st is Dictionary and not (st as Dictionary).is_empty():
		p.load_state(st)
	var stats = e.get("stats", {})
	if stats is Dictionary:
		p.net_stats = (stats as Dictionary).duplicate(true)
	if not p.net_stats.has("deaths"):
		p.net_stats["deaths"] = 0
	if not (bool(e.get("dead", false)) or p.hp <= 0.0):
		return
	var sc: Node = p.get_tree().current_scene if p.is_inside_tree() else null
	if sc != null and bool(sc.get("hardcore")):
		p.hp = 0.0
		p.dead = true
		if p.net_role == Player.NetRole.PROXY:
			Net.send_on(2, NetCodec.Msg.COOP, NetCodec.encode_coop_death(-1.0, false), p.peer_id)
	else:
		p.respawn_at(Game.respawn_point())


# ------------------------------------------------------------------ СМЕРТЬ (D11)

## Хост: герой погиб (свой — из main.gd, прокси — из NetPlayers).
func on_hero_died(p: Player) -> void:
	if not _active or not Net.is_host() or Game.state != Game.State.PLAYING:
		return
	p.net_stats["deaths"] = int(p.net_stats.get("deaths", 0)) + 1
	if _hardcore():
		due.erase(p)
		_tell_death(p, -1.0, false)
		if _all_dead():
			Game.notify("Экспедиция потеряна: погибли все.", Color(0.92, 0.28, 0.34))
			Game.set_state(Game.State.DEAD)
		return
	if _all_dead():
		due.clear()
		wipe_left = Balance.RESPAWN_DELAY
		wipes += 1
		for h in Game.players:
			if is_instance_valid(h) and h.dead:
				_tell_death(h, wipe_left, true)
		return
	due[p] = Balance.MP_RESPAWN_DELAY
	_tell_death(p, Balance.MP_RESPAWN_DELAY, false)


## Клиент: свой герой погиб (флаг OWN). COOP DEATH уже открыл экран — ничего; иначе
## экран с обычным сетевым отсчётом, COOP DEATH (надёжный канал) его поправит.
func on_own_died_client() -> void:
	var es: EndScreen = main.get("end_screen")
	if es == null or (es.visible and es.net_death):
		return
	es.show_net_death(Lore.epitaph(), Balance.MP_RESPAWN_DELAY, false)


## Все герои сессии мертвы (на связи и без: «без связи» урона не получает — жив).
func _all_dead() -> bool:
	var n: int = 0
	for h in Game.players:
		if not is_instance_valid(h):
			continue
		if not h.dead:
			return false
		n += 1
	return n > 0


## Владельцу — отсчёт и вид экрана смерти: свой герой хоста — сразу, прокси — COOP DEATH.
func _tell_death(p: Player, delay: float, wipe: bool) -> void:
	if p == _own():
		var es: EndScreen = main.get("end_screen")
		if es != null:
			es.show_net_death(Lore.epitaph(), delay, wipe)
	elif p.net_role == Player.NetRole.PROXY:
		Net.send_on(2, NetCodec.Msg.COOP, NetCodec.encode_coop_death(delay, wipe), p.peer_id)


func _process(delta: float) -> void:
	if not _active:
		return
	_spectate()
	if not Net.is_host() or Game.state != Game.State.PLAYING:
		return
	if wipe_left >= 0.0:
		wipe_left -= delta
		if wipe_left <= 0.0:
			_wipe_respawn()
		return
	for h in due.keys():
		if not is_instance_valid(h) or not h.dead:
			due.erase(h)
			continue
		due[h] = float(due[h]) - delta
		if float(due[h]) <= 0.0:
			due.erase(h)
			_respawn(h, _respawn_text())


## Респаун у ядра хозяина (нет ядра — капсула лагеря) без сдвига часов (D11).
func _respawn(h: Player, text: String) -> void:
	h.respawn_at(Game.respawn_point())
	if h == _own():
		var es: EndScreen = main.get("end_screen")
		if es != null:
			es.hide_end()
	h._notify(text, Color(1.0, 0.85, 0.6))


## Вайп — правило одиночной (main._respawn): все на базе, часы к рассвету.
func _respawn_text() -> String:
	if Game.core_placed():
		return "У ядра. Мешок с вещами остался на месте гибели."
	return "Капсула на базе. Мешок с вещами остался на месте гибели."


func _wipe_respawn() -> void:
	wipe_left = -1.0
	for h in Game.players:
		if is_instance_valid(h) and h.dead:
			_respawn(h, "Капсулы на базе. Мешки с вещами остались на местах гибели.")
	if not Game.in_mission():   # ADR-004: в главе ночь не перематывается — её надо пережить
		Game.time_of_day = Balance.NIGHT_END - 0.0005


# ------------------------------------------------------------------ КАМЕРА ЗА ТОВАРИЩЕМ

## Свой герой мёртв: камера идёт за живым товарищем, A/D — следующий (шов ввода героя:
## клавиатура, сценарий, сенсор).
func _spectate() -> void:
	var own: Player = _own()
	if own == null or own.camera == null:
		return
	if not own.dead:
		_stop_spectating()
		return
	var alive: Array = []
	for h in Game.players:
		if h != own and is_instance_valid(h) and h.is_inside_tree() and not h.dead:
			alive.append(h)
	alive.sort_custom(func(a, b): return int(a.peer_id) < int(b.peer_id))
	var a_down: bool = own._key(KEY_A) or own._key(KEY_LEFT)
	var d_down: bool = own._key(KEY_D) or own._key(KEY_RIGHT)
	var step: int = (1 if d_down and not _d_prev else 0) - (1 if a_down and not _a_prev else 0)
	_a_prev = a_down
	_d_prev = d_down
	var i: int = alive.find(watching)
	if alive.is_empty():
		watching = null
	elif i < 0:
		watching = alive[0]
	elif step != 0:
		watching = alive[posmod(i + step, alive.size())]
	_spectating = true
	own.camera.position = (watching.global_position - own.global_position) if watching != null else Vector2.ZERO
	var es: EndScreen = main.get("end_screen")
	if es != null and es.net_death:
		var nick: String = String(watching.nick) if watching != null else ""
		if es.net_watch != nick:
			es.net_watch = nick
			es.queue_redraw()


func _stop_spectating() -> void:
	watching = null
	if not _spectating:
		return
	_spectating = false
	var own: Player = _own()
	if own != null and own.camera != null:
		own.camera.position = Vector2.ZERO
		own.camera.reset_smoothing()


# ------------------------------------------------------------------ СООБЩЕНИЯ

func _on_coop(sender: int, payload: PackedByteArray) -> void:
	if sender != 1 or not Net.is_client():
		return
	var d: Dictionary = NetCodec.decode_coop(payload)
	match int(d.get("kind", 0)):
		NetCodec.CoopEv.DEATH:
			last_death = {"delay": float(d["delay"]), "wipe": bool(d["wipe"])}
			var es: EndScreen = main.get("end_screen")
			if es != null:
				es.show_net_death(Lore.epitaph(), float(d["delay"]), bool(d["wipe"]))
		NetCodec.CoopEv.RELAY:
			Game.net_apply_relay(d.get("have", {}), d.get("req", {}))
		NetCodec.CoopEv.CORE:
			Game.net_apply_core(int(d.get("arcs", 0)), d.get("cell", Vector2i(-1, -1)))
		NetCodec.CoopEv.STATS:
			var team: Array = d["team"]
			Game.stats_mined = int(team[0])
			Game.stats_crafted = int(team[1])
			Game.stats_kills = int(team[2])
			Game.stats_deaths = int(team[3])
			net_lines = []
			for e in d["players"]:
				net_lines.append(_line(String(e[0]), int(e[1])))


## Сообщение всей команде: у себя и (хост) у каждого клиента.
static func team_notify(text: String, color: Color) -> void:
	Game.notify(text, color)
	if Net.is_host():
		Net.send(NetCodec.Msg.EVENT, NetCodec.encode_notify(Vector2.ZERO, text, color))


# ------------------------------------------------------------------ РАССВЕТ И ИТОГИ

## Хост: автосохранение на каждом рассвете (D13). В --hardcore сохранений нет.
func _on_dawn(_day: int) -> void:
	if not _active or not Net.is_host() or _hardcore() or Game.in_mission():   # ADR-004: в главе не пишем
		return
	var slot: String = Save.net_auto_slot(String(Net.session.get("session_name", "")))
	if Save.save_game(slot):
		print("СЕТЬ: автосохранение «%s»: %d Б, %.1f мс" % [slot, Save.last_size, Save.last_save_ms])
	else:
		push_warning("СЕТЬ: автосохранение не вышло: %s" % Save.last_error)


## Хост: конец забега — итоги команде (до глобального пакета с новым состоянием: канал 0).
func _on_state(s: int) -> void:
	if not _active or not Net.is_host() or s == Game.State.PLAYING:
		return
	var players: Array = []
	for r in _rows():
		players.append([r[0], r[1]])
	Net.send_on(0, NetCodec.Msg.COOP, NetCodec.encode_coop_stats(
			[Game.stats_mined, Game.stats_crafted, Game.stats_kills, Game.stats_deaths], players))


## [[ник, смертей], …] — герои на связи, потом запаркованные.
func _rows() -> Array:
	var out: Array = []
	for h in Game.players:
		if is_instance_valid(h):
			out.append([String(h.nick), int(h.net_stats.get("deaths", 0))])
	for uid in Net.parked:
		var e: Dictionary = Net.parked[uid]
		out.append([String(e.get("nick", "")), int((e.get("stats", {}) as Dictionary).get("deaths", 0))])
	return out


static func _line(nick: String, deaths: int) -> String:
	return "%s: смертей %d" % [nick, deaths]


## Строки личной статистики для экрана итогов (main._stats).
func stats_lines() -> Array:
	if not _active and net_lines.is_empty():
		return []
	if Net.is_client() or not _active:
		return net_lines
	var out: Array = []
	for r in _rows():
		out.append(_line(String(r[0]), int(r[1])))
	return out
