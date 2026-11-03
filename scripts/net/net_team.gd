class_name NetTeam
extends Node
## Команда по сети: перекличка (G), двойник среди своих (ADR-002 § 4.8, D12; MP-J, #95).
##
## Узел живёт под сценой (main.gd, как NetPlayers) и молчит без сессии: в одиночной
## игре его нет вовсе — ни узлов, ни работы в кадре.
##
## Перекличка (G, § 4.8 п. 2). Клавиша читается через шов героя (Player._key) — на хосте
## у своего героя и у прокси (у прокси G приходит счётчиком нажатий пакета ввода, MP-D),
## player.gd не правится. G без идущей переклички — начать её (личный кулдаун
## MP_ROLLCALL_COOLDOWN): у всех на HUD «Аня: перекличка!», ANSWER_WINDOW секунд на
## ответ. G во время переклички — ответ: огонёк на шлеме зелёный MP_ROLLCALL_LIGHT
## (Player.rollcall_t; марионеткам — флагом PF_ROLLCALL пакета состояния, своему
## герою клиента — событием). Пока идёт перекличка, у не ответивших огонёк красный;
## у двойника он красный всегда — он не отвечает.
##
## Двойник (§ 4.8). Жертву и маску выбирает сам двойник на хосте (Phantom._net_doppel_pick);
## отсюда маска — клиентам (TEAM.MASK: номер фантома + слот товарища) при смене и раз в
## MASK_RESEND (вошедшим позже), ник маски — тем же NetPlayers.NickTag, что у товарищей.
## Удар по двойнику — TEAM.REVEAL: «глюк» MP_DOPPEL_REVEAL у всех и всплеск GlitchFx
## DOPPEL_REVEAL (V7) в его точке.
##
## Удар по своему (§ 4.7 «Огонь по своим»): ЛКМ по товарищу — урона нет, «клац» и
## кулдаун удара MP_FRIENDLY_SLASH_CD (Player.slash_cd): проверка стоит времени. Узел
## идёт в физическом кадре после героев: если взмах уже попал в фантома (slash_cd > 0),
## по своему он не засчитывается.
##
## Миникарта и список команды — в HUD (scripts/ui/hud.gd, раздел «СЕТЬ»).

## Сколько секунд после начала переклички на неё можно ответить.
const ANSWER_WINDOW: float = 6.0
## Маски двойников повторяются клиентам так часто, с (вошедшим позже — тоже).
const MASK_RESEND: float = 2.0
## Как часто хост сверяет двойников (маска, подпись), с.
const SCAN_SEC: float = 0.25
## Удар по своему засчитывается ближе этого к курсору, px (как Player._slash_at).
const SLASH_PX: float = 20.0
const C_CALL: Color = Color(0.55, 0.95, 0.6)

## Огонёк переклички героя: нет, красный (идёт перекличка, ответа нет), зелёный.
enum Lamp { OFF, RED, GREEN }

## Узел этой сцены (нужен Phantom и HUD без поиска по дереву).
static var instance: NetTeam = null

var main: Node = null
## Идёт перекличка: сколько ещё можно ответить, с.
var window_left: float = 0.0
## Кто начал перекличку: слот и ник.
var caller_slot: int = -1
var caller_nick: String = ""
## Счётчик событий команды (перекличка, ответы) — HUD кладёт его в ключ перерисовки.
var serial: int = 0
## Замеры и проверки сценария mp_doppel.
var stats: Dictionary = {}

var _active: bool = false
var _glitch: GlitchFx = null
var _scan_t: float = 0.0
var _resend_t: float = 0.0
# --- хост
var _g_prev: Dictionary = {}      ## instance_id героя → G была нажата в прошлом кадре
var _cd: Dictionary = {}          ## instance_id героя → кулдаун переклички, с
var _answered: Dictionary = {}    ## instance_id героя → ответил в этой перекличке
var _masks_sent: Dictionary = {}  ## номер фантома → слот маски, отправленный клиентам
# --- клиент
var _masks: Dictionary = {}       ## номер фантома → слот маски (ждёт марионетку, если её ещё нет)


func start(p_main: Node) -> void:
	main = p_main
	instance = self
	name = "NetTeam"
	add_to_group("net_team")
	process_physics_priority = 10   # после героев: их взмах (slash_cd) уже посчитан
	Net.session_started.connect(_begin)
	Net.session_ended.connect(_end)
	Game.player_joined.connect(_add_lamp)
	if Net.is_online():
		_begin()


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _begin() -> void:
	if _active:
		return
	_active = true
	window_left = 0.0
	caller_slot = -1
	caller_nick = ""
	stats = {"calls": 0, "answers": 0, "cooldown": 0, "masks_tx": 0, "masks_rx": 0,
			"reveals": 0, "reveal_rx": 0, "reveal_fx": 0, "friendly": 0}
	_g_prev.clear()
	_cd.clear()
	_answered.clear()
	_masks_sent.clear()
	_masks.clear()
	Net.on(NetCodec.Msg.TEAM, _on_team)
	for c in main.get_children():
		if c is GlitchFx:
			_glitch = c
	for h in Game.players:
		_add_lamp(h)


func _end(_reason: String = "") -> void:
	_active = false
	window_left = 0.0


## Огонёк переклички на герое (свой, прокси, марионетка) — отдельным узлом-ребёнком.
func _add_lamp(h) -> void:
	var p: Node = h as Node
	if p == null or not is_instance_valid(p) or p.get_node_or_null("RollcallLamp") != null:
		return
	var l: RollcallLamp = RollcallLamp.new()
	l.name = "RollcallLamp"
	p.add_child(l)


# ------------------------------------------------------------------ ЗАПРОСЫ

## Идёт ли перекличка (огоньки на шлемах горят).
static func rollcall_on() -> bool:
	return instance != null and instance._active and instance.window_left > 0.0


## Огонёк (Lamp) героя: зелёный — ответил, красный — перекличка без его ответа.
## У двойника — красный всю перекличку: ответить он не может.
static func lamp_state(h) -> int:
	if h is Phantom:
		return Lamp.RED if rollcall_on() and (h as Phantom).alive else Lamp.OFF
	var p: Player = h as Player
	if p == null or p.dead:
		return Lamp.OFF
	if p.rollcall_t > 0.0:
		return Lamp.GREEN
	return Lamp.RED if rollcall_on() else Lamp.OFF


## Сколько ещё ждать до своей переклички, с (хост; 0 — можно).
func cooldown_left(p: Node) -> float:
	return float(_cd.get(p.get_instance_id(), 0.0)) if p != null else 0.0


## Ник игрока в этом слоте ("" — нет такого).
static func nick_of_slot(slot: int) -> String:
	for id in Net.peers:
		if int(Net.peers[id].get("slot", -1)) == slot:
			return String(Net.peers[id].get("nick", ""))
	return ""


static func _slot_of(peer: int) -> int:
	return int(Net.peers.get(peer, {}).get("slot", NetCodec.TEAM_NO_SLOT))


static func _peer_of_slot(slot: int) -> int:
	for id in Net.peers:
		if int(Net.peers[id].get("slot", -1)) == slot:
			return int(id)
	return 0


# ------------------------------------------------------------------ КАДР

func _physics_process(dt: float) -> void:
	if not _active:
		return
	if window_left > 0.0:
		window_left = maxf(0.0, window_left - dt)
	# Огоньки ответа гаснут у своих героев (марионеткам их ставит пакет состояния).
	for h in Game.players:
		var p: Player = h as Player
		if p != null and p.net_role != Player.NetRole.PUPPET and p.rollcall_t > 0.0:
			p.rollcall_t = maxf(0.0, p.rollcall_t - dt)
	if Net.is_host():
		for h in Game.players:
			var p: Player = h as Player
			if p != null and is_instance_valid(p) and p.net_role != Player.NetRole.PUPPET:
				_host_hero(p, dt)
	_scan_t -= dt
	if _scan_t <= 0.0:
		_scan_t = SCAN_SEC
		if Net.is_host():
			_host_masks()
		elif Net.is_client():
			_apply_masks()


# ------------------------------------------------------------------ ХОСТ

## Герой хоста или прокси: кулдаун, фронт G, удар по своему.
func _host_hero(p: Player, dt: float) -> void:
	var id: int = p.get_instance_id()
	var cd: float = float(_cd.get(id, 0.0))
	if cd > 0.0:
		_cd[id] = maxf(0.0, cd - dt)
	var g: bool = not p.dead and not p._ui_blocking() and p._key(KEY_G)
	var was: bool = bool(_g_prev.get(id, false))
	_g_prev[id] = g
	if g and not was:
		_press_g(p)
	_friendly_slash(p)


func _press_g(p: Player) -> void:
	var id: int = p.get_instance_id()
	var slot: int = _slot_of(p.peer_id)
	if window_left > 0.0:
		if _answered.has(id):
			return
		_answered[id] = true
		p.rollcall_t = Balance.MP_ROLLCALL_LIGHT
		Net.send(NetCodec.Msg.TEAM, NetCodec.encode_team(NetCodec.TeamEv.ANSWER, slot))
		_apply_event(NetCodec.TeamEv.ANSWER, slot)
		return
	var cd: float = float(_cd.get(id, 0.0))
	if cd > 0.0:
		stats["cooldown"] = int(stats["cooldown"]) + 1
		p._notify("Перекличка — через %d с" % ceili(cd), Color(0.85, 0.85, 0.7))
		return
	_cd[id] = Balance.MP_ROLLCALL_COOLDOWN
	_answered.clear()
	_answered[id] = true
	p.rollcall_t = Balance.MP_ROLLCALL_LIGHT
	Net.send(NetCodec.Msg.TEAM, NetCodec.encode_team(NetCodec.TeamEv.CALL, slot))
	_apply_event(NetCodec.TeamEv.CALL, slot)


## ЛКМ по товарищу (а не по фантому): «клац», кулдаун удара, урона нет.
func _friendly_slash(p: Player) -> void:
	if p.dead or p.slash_cd > 0.0 or p._ui_blocking() or not p._mouse_down(MOUSE_BUTTON_LEFT):
		return
	var mouse: Vector2 = p._mouse_pos()
	if mouse.distance_to(p.global_position) > Player.REACH:
		return
	for h in Game.players:
		var o: Player = h as Player
		if o == null or o == p or o.dead or not is_instance_valid(o):
			continue
		if o.global_position.distance_to(mouse) >= SLASH_PX:
			continue
		p.slash_cd = Balance.MP_FRIENDLY_SLASH_CD
		p._sfx_here("place", -4.0, 1.7)
		p._notify("Свой: %s" % o.nick, Color(0.85, 0.9, 1.0))
		stats["friendly"] = int(stats["friendly"]) + 1
		return


## Двойники хоста: подпись маски, маска клиентам при смене и раз в MASK_RESEND.
func _host_masks() -> void:
	_resend_t -= SCAN_SEC
	var resend: bool = _resend_t <= 0.0
	if resend:
		_resend_t = MASK_RESEND
	for n in get_tree().get_nodes_in_group("phantom"):
		var ph: Phantom = n as Phantom
		if ph == null or ph.kind != "doppel" or not ph.alive:
			continue
		_ensure_tag(ph)
		if ph.net_id == 0:
			continue             # NetPhantoms ещё не объявил его клиентам
		var slot: int = NetCodec.TEAM_NO_SLOT if ph.net_mask_peer == 0 else _slot_of(ph.net_mask_peer)
		if not resend and int(_masks_sent.get(ph.net_id, -1)) == slot:
			continue
		_masks_sent[ph.net_id] = slot
		Net.send(NetCodec.Msg.TEAM, NetCodec.encode_team(NetCodec.TeamEv.MASK, slot, ph.net_id))
		stats["masks_tx"] = int(stats["masks_tx"]) + 1


## Хост: двойника ударили (Phantom._net_reveal) — «глюк» клиентам и у себя.
static func doppel_revealed(ph: Phantom) -> void:
	if instance == null or not instance._active or not Net.is_host():
		return
	instance.stats["reveals"] = int(instance.stats["reveals"]) + 1
	if ph.net_id != 0:
		Net.send(NetCodec.Msg.TEAM, NetCodec.encode_team(NetCodec.TeamEv.REVEAL, 0, ph.net_id))
	instance._reveal_fx(ph)


# ------------------------------------------------------------------ ВСЕ

## Перекличка и ответ — у хоста сразу, у клиента по TEAM.
func _apply_event(kind: int, slot: int) -> void:
	serial += 1
	var own: Player = Game.local_player as Player
	var mine: bool = own != null and slot == _slot_of(Net.my_id())
	if kind == NetCodec.TeamEv.CALL:
		window_left = ANSWER_WINDOW
		caller_slot = slot
		caller_nick = nick_of_slot(slot)
		stats["calls"] = int(stats["calls"]) + 1
		Game.notify("%s: перекличка! [G] — ответить" % caller_nick, C_CALL)
	else:
		stats["answers"] = int(stats["answers"]) + 1
	if mine and own.net_role == Player.NetRole.OWNER:
		own.rollcall_t = Balance.MP_ROLLCALL_LIGHT


func _reveal_fx(ph: Phantom) -> void:
	if _glitch != null and is_instance_valid(_glitch) and _glitch.fire(GlitchFx.Kind.DOPPEL_REVEAL, ph.global_position):
		stats["reveal_fx"] = int(stats["reveal_fx"]) + 1


## Подпись над двойником в маске — тот же узел, что у товарищей (MP-D).
static func _ensure_tag(ph: Phantom) -> void:
	if ph.get_node_or_null("NickTag") == null:
		var tag: NetPlayers.NickTag = NetPlayers.NickTag.new()
		tag.name = "NickTag"
		ph.add_child(tag)


# ------------------------------------------------------------------ КЛИЕНТ

func _on_team(sender: int, payload: PackedByteArray) -> void:
	if sender != 1 or not Net.is_client():
		return
	var d: Dictionary = NetCodec.decode_team(payload)
	if d.is_empty():
		return
	match int(d["kind"]):
		NetCodec.TeamEv.CALL, NetCodec.TeamEv.ANSWER:
			_apply_event(int(d["kind"]), int(d["slot"]))
		NetCodec.TeamEv.MASK:
			stats["masks_rx"] = int(stats["masks_rx"]) + 1
			_masks[int(d["id"])] = int(d["slot"])
			_apply_masks()
		NetCodec.TeamEv.REVEAL:
			stats["reveal_rx"] = int(stats["reveal_rx"]) + 1
			var ph: Phantom = _puppet(int(d["id"]))
			if ph != null:
				ph.net_reveal_t = Balance.MP_DOPPEL_REVEAL
				_reveal_fx(ph)


func _puppet(id: int) -> Phantom:
	var np: NetPlayers = main.get("net_players") as NetPlayers if main != null else null
	if np == null or np.phantoms == null:
		return null
	var ph = np.phantoms.puppets.get(id)
	return ph as Phantom if is_instance_valid(ph) else null


## Маски — марионеткам двойников (марионетка могла прийти позже маски: каналы разные).
func _apply_masks() -> void:
	for id in _masks:
		var ph: Phantom = _puppet(int(id))
		if ph == null:
			continue
		var slot: int = int(_masks[id])
		var peer: int = 0 if slot == NetCodec.TEAM_NO_SLOT else _peer_of_slot(slot)
		if peer == 0:
			ph.net_apply_mask("", 0)
		else:
			var info: Dictionary = Net.peers[peer]
			ph.net_apply_mask(String(info.get("nick", "")), int(info.get("look", 0)))
		_ensure_tag(ph)


# ------------------------------------------------------------------ ОГОНЁК НА ШЛЕМЕ

## Огонёк переклички героя (Avatar.draw_rollcall) поверх его рисунка: player.gd не
## тронут. Перерисовывается, пока горит (шлем качается с шагом), и раз — когда погас.
class RollcallLamp extends Node2D:
	var _state: int = NetTeam.Lamp.OFF

	func _ready() -> void:
		z_index = 1

	func _process(_delta: float) -> void:
		var s: int = NetTeam.lamp_state(get_parent())
		if s != NetTeam.Lamp.OFF or s != _state:
			queue_redraw()
		_state = s

	func _draw() -> void:
		var p: Player = get_parent() as Player
		if _state == NetTeam.Lamp.OFF or p == null:
			return
		Avatar.draw_rollcall(self, p.body_layout(), _state == NetTeam.Lamp.GREEN)
