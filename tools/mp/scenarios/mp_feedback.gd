extends "res://tools/mp/scenarios/mp_players_base.gd"
## mp_feedback (ADR-002 § 4.2.3, § 1.2 п. 3; MP-D, #89): обратная связь — тому, кто
## нажал. Звук, уведомления и эффекты Player идут через обёртки (_sfx_here, _sfx_self,
## _notify, _fx, _feedback_hit); у прокси они уходят владельцу или всем событием.
##
##  * код: в player.gd вне секции «СЕТЬ» нет прямых Sfx./Game.notify/UI.* —
##    все вызовы обратной связи (31) идут через обёртки;
##  * V вдали от вентиляций (одно нажатие в один кадр — его несёт счётчик нажатий):
##    «Рядом нет вентиляции» видит только нажавший — клиент 0 у себя, хост у себя;
##    клиент 1 — ни одного;
##  * Q в один кадр: импульс на хосте (кулдаун прокси), звук и кольцо — всем;
##  * удар по прокси: вспышка урона и HP — только у владельца; марионетка у
##    клиента 1 мигает (флаг удара в STATE).

const NO_VENT: String = "Рядом нет вентиляции."
## Ожидание события (игровые секунды каждого процесса; под нагрузкой машины — с запасом).
const WAIT: float = 6.0
## После барьера: чужое событие, если бы ушло не тому, успело бы дойти.
const GRACE: float = 0.4
## Прямые вызовы обратной связи, которых вне секции «СЕТЬ» в player.gd быть не должно.
const DIRECT: String = "Sfx\\.|Game\\.notify|UI\\.(flash_|spawn_|open_chest|blocking)"
const WRAPPERS: String = "\\b(_sfx_here|_sfx_self|_notify|_fx|_feedback_hit|_open_chest|_ui_blocking)\\("

var _texts: Array = []
var _flash_max: float = 0.0
var _pup_hit: bool = false
var _watch: Player = null


func _on_note(text: String, _color: Color) -> void:
	_texts.append(text)


func _physics_process(_delta: float) -> void:
	if UI.hud != null:
		_flash_max = maxf(_flash_max, float(UI.hud.damage_flash))
	# Марионетка мигнула — или флаг удара пришёл в STATE (если процесс подвис и
	# время рисования проскочило эти 0.3 с, вспышки на экране не будет, а пакет был).
	if _watch != null and not _pup_hit:
		if _watch._hit_flash > 0.0:
			_pup_hit = true
		for e in np()._buf.get(_watch.peer_id, []):
			if (int(e["row"]["flags"]) & NetCodec.PF_HIT) != 0:
				_pup_hit = true


func _count(text: String) -> int:
	var n: int = 0
	for t in _texts:
		if String(t) == text:
			n += 1
	return n


## Одно нажатие длиной в один физический кадр (шов ввода).
func tap(code: int) -> void:
	hold(code)
	await get_tree().physics_frame
	await get_tree().physics_frame
	release(code)


# ------------------------------------------------------------------ ХОСТ

func run_host() -> void:
	_check_source()
	ok("хост + %d клиента вошли" % clients, await wait_players(1 + clients, 45.0))
	ok("прокси обоих клиентов с вводом", await wait_proxies(clients, 10.0))
	await barrier("in")
	var p0: Player = hero_of(0)
	if p0 == null:
		finish()
		return
	var sx: int = World.world_to_cell(World.spawn_point).x
	var far0: Vector2 = vent_free_spot(sx + 30, 1)
	var farh: Vector2 = vent_free_spot(sx - 30, -1)
	ok("клиент 0 вдали от вентиляций", await teleport_proxy(p0, far0) and far_from_vents(p0.global_position, 40.0))
	player.global_position = farh
	player.vel = Vector2.ZERO
	await wait(0.4)
	ok("свой герой хоста вдали от вентиляций", far_from_vents(player.global_position, 40.0))

	# --- V: личное уведомление.
	Game.notification.connect(_on_note)
	await barrier("v")
	await tap(KEY_V)                 # свой герой хоста (LOCAL)
	await wait_until(func() -> bool: return _count(NO_VENT) >= 1, WAIT)
	await barrier("v_done", -1, 30.0)
	await wait(GRACE)
	Game.notification.disconnect(_on_note)
	ok("хост: только своё «%s» — одно, чужое (клиента 0) не показано" % NO_VENT,
			_count(NO_VENT) == 1, str(_texts))

	# --- Q: импульс клиента 0 по нажатию в один кадр.
	var cd0: float = p0.emp_cd
	await barrier("q")
	var emp: bool = await wait_until(func() -> bool: return p0.emp_cd > cd0 + 1.0, WAIT)
	ok("хост: Q в один кадр клиента — импульс прокси (счётчик нажатий)", emp, "кулдаун %.1f с" % p0.emp_cd)
	await barrier("q_done")

	# --- Удар: вспышка и HP — только владельцу.
	await barrier("hit")
	p0.invuln = 0.0
	p0.damage(15.0, Vector2(140.0, -120.0))
	ok("хост: прокси ранен", p0.hp < Player.MAX_HP - 10.0, "hp %.0f" % p0.hp)

	ok("хост: своя вспышка урона не зажглась", UI.hud.damage_flash <= 0.0)
	await barrier("hit_done", -1, 30.0)
	await barrier("done")
	finish()


## Код player.gd: обратная связь только через обёртки (секция «СЕТЬ» — их тела).
func _check_source() -> void:
	var src: String = FileAccess.get_file_as_string("res://scripts/entities/player.gd")
	var cut: int = src.find("# ------------------------------------------------- СЕТЬ (ADR-002)")
	ok("player.gd: секция «СЕТЬ (ADR-002)» есть", cut > 0)
	if cut <= 0:
		return
	var body: String = src.substr(0, cut)
	var direct: Array = []
	var wrapped: int = 0
	var re_d: RegEx = RegEx.create_from_string(DIRECT)
	var re_w: RegEx = RegEx.create_from_string(WRAPPERS)
	var ln: int = 0
	for line in body.split("\n"):
		ln += 1
		var code: String = line.split("#")[0]
		if code.strip_edges().begins_with("func "):
			continue
		if re_d.search(code) != null:
			direct.append("%d: %s" % [ln, code.strip_edges()])
		wrapped += re_w.search_all(code).size()
	ok("player.gd: прямых Sfx./Game.notify/UI.* вне секции «СЕТЬ» нет", direct.is_empty(), str(direct))
	ok("player.gd: вызовы обратной связи через обёртки (≥ 31)", wrapped >= 31, "%d" % wrapped)


# ------------------------------------------------------------------ КЛИЕНТЫ

func client_args(i: int) -> PackedStringArray:
	return PackedStringArray(["--nick=" + ["Аня", "Борис"][i]])


func run_client(i: int) -> void:
	await barrier("in")
	if i == 1:
		ok("c1: марионетка клиента 0 есть", await wait_puppets([0], 10.0))
		_watch = hero_of(0)
	Game.notification.connect(_on_note)
	await barrier("v")
	if i == 0:
		await tap(KEY_V)
		await wait_until(func() -> bool: return _count(NO_VENT) >= 1, WAIT)
	await barrier("v_done", -1, 30.0)
	await wait(GRACE)                # чужое уведомление, если бы ушло всем, уже дошло бы
	Game.notification.disconnect(_on_note)
	if i == 0:
		ok("c0: «%s» — у нажавшего, одно" % NO_VENT, _count(NO_VENT) == 1, str(_texts))
	else:
		ok("c1: чужих «%s» нет (ни хоста, ни клиента 0)" % NO_VENT, _count(NO_VENT) == 0, str(_texts))

	UI.net_events.clear()
	await barrier("q")
	if i == 0:
		await tap(KEY_Q)
	var near: Vector2 = hero_of(0).global_position if i == 1 and hero_of(0) != null else player.global_position
	var heard: bool = await wait_until(func() -> bool:
		return events_near(NetCodec.Ev.SOUND, "sound", "power", near, 48.0) > 0 \
				and events_near(NetCodec.Ev.FX, "kind", NetCodec.Fx.RING_EMP, near, 48.0) > 0, WAIT)
	ok("c%d: звук и кольцо импульса клиента 0 — событием" % i, heard)
	await barrier("q_done")

	_flash_max = 0.0
	_pup_hit = false
	await barrier("hit")
	if i == 0:
		await wait_until(func() -> bool: return _flash_max > 0.5 and player.hp < Player.MAX_HP - 1.0, WAIT)
	else:
		await wait_until(func() -> bool: return _pup_hit, WAIT)
	await barrier("hit_done", -1, 30.0)
	await wait(GRACE)
	if i == 0:
		ok("c0: вспышка урона у раненого (событие удара)", _flash_max > 0.5, "%.2f" % _flash_max)
		# −15 с хоста; реген прокси (+6 раз в 6 с) мог уже сработать.
		ok("c0: HP своего героя упало (OWN)", player.hp < Player.MAX_HP - 1.0, "hp %.0f" % player.hp)
	else:
		ok("c1: чужая вспышка урона не зажглась", _flash_max <= 0.0, "%.2f" % _flash_max)
		ok("c1: своё HP цело", player.hp >= Player.MAX_HP)
		ok("c1: удар по товарищу виден: флаг удара в STATE, марионетка мигает", _pup_hit)
	await barrier("done")
	finish()
