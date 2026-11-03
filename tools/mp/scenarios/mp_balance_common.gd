extends "res://tools/mp/scenarios/mp_threat_base.gd"
## Общее ботов баланса кооператива (ADR-002 § 2, § 4.7; MP-K, #96): mp_balance_night,
## mp_balance_siege, mp_balance_mining, mp_balance_doppel.
##
## Это сетевые двойники ботов #33 (tools/scenarios/balance_common.gd): тот же штатный
## директор угрозы (сценарий сам зовёт Threat.tick — в сценариях он молчит), тот же
## случай директора от сида мира, те же «руки» героя через шов ввода. Разница — героев
## N = 1 + клиенты (--mp-clients), и каждый клиент — отдельный процесс: свой герой
## клиента бьёт и ставит лампы своим швом, хост исполняет это прокси (как у человека).
##
## Ускорения нет: сетевые часы (такты, интерполяция марионеток) идут по часам стены,
## Engine.time_scale их бы рассогласовал. Отсчёты — по Game.game_time хоста (часы
## забега; в сети смерть их не останавливает, D11).
##
## Метрики пишет только хост: строкой «  [баланс] ключ=значение» и в файл --balance-out
## (его передаёт tools/mp_balance_probe.gd; ключи без N — зонд знает N запуска).
## Клиенты отдают свои замеры (трафик, с/ед добычи) хосту файлами обмена (share_put).
## Флаги сценария хост читает из своей командной строки (--mpb-…), клиентам они не нужны.

## Ники клиентов по номеру.
const SLOT_NICKS: Array = ["Аня", "Борис", "Вера"]

## Вести директора угрозы из сценария (хост).
var drive_threat: bool = false
## Клиент: хост сказал «конец фазы» (барьер end пройден).
var _end_flag: bool = false


func _process(delta: float) -> void:
	if drive_threat and is_host_side() and Game.state == Game.State.PLAYING:
		Threat.tick(delta)


func finish() -> void:
	drive_threat = false
	if player != null:
		clear_input()
	super()


func client_args(i: int) -> PackedStringArray:
	return PackedStringArray(["--nick=" + String(SLOT_NICKS[mini(i, SLOT_NICKS.size() - 1)])])


## Число героев запуска: хост + клиенты.
func heroes_n() -> int:
	return 1 + clients


## Все герои хоста: свой + прокси клиентов по порядку (null — прокси нет).
func heroes() -> Array:
	var out: Array = [player]
	for i in clients:
		out.append(hero_of(i))
	return out


## Флаг хоста --mpb-<name>[=значение].
static func flag(name: String) -> bool:
	for a in OS.get_cmdline_user_args():
		if a == "--mpb-" + name or a.begins_with("--mpb-" + name + "="):
			return true
	return false


static func flag_int(name: String, def: int) -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mpb-" + name + "="):
			return int(a.substr(6 + name.length() + 1))
	return def


## Хост: все вошли, у хоста прокси с вводом.
func host_join() -> bool:
	var ok_in: bool = await wait_players(heroes_n(), 60.0)
	ok("хост + %d клиента вошли" % clients, ok_in)
	if clients > 0:
		ok("прокси клиентов с вводом", await wait_proxies(clients, 15.0))
	return ok_in


## Случай директора угрозы от сида мира (как balance_common.seed_threat): одна ночь
## на один сид при любом N — разница только в формулах N.
func seed_threat(day: int) -> void:
	Threat._rng.seed = int(scene.get("seed_value")) * 31 + day


## Клиент: ждать «конец фазы» в фоне (бот при этом работает каждый кадр).
func wait_end_async(name: String, timeout: float) -> void:
	_end_flag = false
	await barrier(name, -1, timeout)
	_end_flag = true


# ------------------------------------------------------------------ МЕТРИКИ

func metric(key: String, value: float, note: String = "") -> void:
	print("  [баланс] %s=%.3f%s" % [key, value, ("  # " + note) if note != "" else ""])
	_metric_to_file("%s=%.3f" % [key, value])


func metric_na(key: String, why: String) -> void:
	print("  [баланс] %s=NA  # %s" % [key, why])
	_metric_to_file("%s=NA" % key)


func _metric_to_file(line: String) -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--balance-out="):
			continue
		var path: String = a.substr(14)
		var f: FileAccess = FileAccess.open(path, FileAccess.READ_WRITE)
		if f == null:
			f = FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			return
		f.seek_end()
		f.store_line(line)
		f.close()


# ------------------------------------------------------------------ ТРАФИК

var _tx0: int = 0
var _tx_t0: float = 0.0


## Начать замер отправленных байт этого процесса (полезная нагрузка кадров Net).
func traffic_begin() -> void:
	_tx0 = _sent_total()
	_tx_t0 = Game.game_time


## Б/с с начала замера. Хост: на одного клиента (рассылка всем — один кадр на всех,
## личные — по кадру на клиента; делим всё на число клиентов, как mp_perf).
func traffic_bps() -> float:
	var secs: float = maxf(0.001, Game.game_time - _tx_t0)
	var b: float = float(_sent_total() - _tx0) / secs
	return b / float(maxi(1, clients)) if is_host_side() else b


static func _sent_total() -> int:
	var t: int = 0
	for k in Net.sent_bytes:
		t += int(Net.sent_bytes[k])
	return t


# ------------------------------------------------------------------ БОЙ И РУКИ

var _q_down: bool = false

## Боец на месте (как balance_common.fight_step): фантом в досягаемости удара — мышь на
## него и ЛКМ, вплотную и импульс готов — Q. У клиента фантомы — марионетки (позиция
## на 100 мс в прошлом), удар исполняет прокси на хосте: сетевая задержка в счёте.
func fight_step(strike_px: float = 44.0) -> void:
	var near: Node2D = null
	var best: float = strike_px
	for p in get_tree().get_nodes_in_group("phantom"):
		if not is_instance_valid(p) or not bool(p.get("alive")):
			continue
		if not is_host_side() and not (p as Node2D).visible:   # марионетка без строк состояния
			continue
		var d: float = p.global_position.distance_to(player.global_position)
		if d < best:
			best = d
			near = p
	if near == null or player.dead:
		release_mouse(MOUSE_BUTTON_LEFT)
		if _q_down:
			_q_down = false
			release(KEY_Q)
		return
	aim(near.global_position)
	press_mouse(MOUSE_BUTTON_LEFT)
	if _q_down:
		_q_down = false
		release(KEY_Q)
	elif best < 36.0 and player.emp_cd <= 0.0:
		_q_down = true
		hold(KEY_Q)


func stop_fight() -> void:
	release_mouse(MOUSE_BUTTON_LEFT)
	release(KEY_Q)
	_q_down = false


## Выбрать слот хотбара с предметом id цифрой (шов ввода). false — нет предмета.
func select_item(id: int) -> bool:
	for i in player.inv.hotbar_size:
		if player.inv.slots[i].id == id and not player.inv.slots[i].is_empty():
			var key: int = KEY_1 + i if i < 9 else KEY_0
			hold(key)
			await wait(0.1)
			release(key)
			await wait(0.1)
			return player.inv.selected == i
	return false


## Поставить выбранный предмет в клетку (навести, ПКМ, ждать тайл — у клиента дельтой).
func place_selected(c: Vector2i, expect_tile: int) -> bool:
	aim(World.cell_to_world(c))
	press_mouse(MOUSE_BUTTON_RIGHT)
	var done_ok: bool = await wait_until(func() -> bool: return World.get_tile_v(c) == expect_tile, 3.0)
	release_mouse(MOUSE_BUTTON_RIGHT)
	await wait(0.1)
	return done_ok


## Три лампы вокруг своего героя (как night_survive_1). Сколько поставлено.
func place_lamps(n: int = 3) -> int:
	var pc: Vector2i = World.world_to_cell(player.global_position)
	var placed: int = 0
	if not await select_item(IDs.I.LAMP):
		return 0
	for c in [pc + Vector2i(-2, 0), pc + Vector2i(2, 0), pc + Vector2i(0, -3),
			pc + Vector2i(-3, 0), pc + Vector2i(3, 0), pc + Vector2i(-1, -3),
			pc + Vector2i(1, -3), pc + Vector2i(-2, -2), pc + Vector2i(2, -2)]:
		if placed >= n:
			break
		if World.get_tile_v(c) == IDs.T.AIR and await place_selected(c, IDs.T.LIGHT_CRYSTAL):
			placed += 1
	return placed


# ------------------------------------------------------------------ МЕСТА

## Тёмные точки поверхности для k героев «по шахтам»: свободно на две клетки вверх,
## пол, свет ≤ max_light, от релея по x не ближе min_dx, друг от друга ≥ gap клеток.
## Сначала — точки, у которых есть вентиляция в радиусе спавна (VENT_SPAWN_MIN..MAX_PX):
## у #33 тёмная точка вдали от базы оказалась без вентиляций, и ночь до героя не доходила.
## Порядок детерминирован сидом мира: при N = 1 герой стоит в первой точке, при N = 4 —
## в тех же четырёх.
func spread_spots(k: int, min_dx: int = 40, gap: int = 30, max_light: float = 0.3) -> Array:
	var out: Array = []
	for need_vent in [true, false]:
		var bx: int = World.beacon_cell.x
		for d in range(min_dx, World.W):
			for x in [bx + d, bx - d]:
				if out.size() >= k:
					return out
				if x < 3 or x >= World.W - 3:
					continue
				var c: Vector2i = Vector2i(x, World.surface[x] - 1)
				if World.get_tile_v(c) != IDs.T.AIR or World.get_tile_v(c + Vector2i(0, -1)) != IDs.T.AIR:
					continue
				if not World.is_solid_cell(c + Vector2i(0, 1)) or World.light_at(c) > max_light:
					continue
				var far: bool = true
				for o in out:
					if absi((o as Vector2i).x - x) < gap:
						far = false
				if not far:
					continue
				var pos: Vector2 = World.cell_to_world(c)
				if need_vent and Threat.nearest_vents(pos, 1).is_empty():
					continue
				out.append(c)
	return out


## Точка «стоя» в клетке (как ScenarioBase.stand_at_cell).
static func stand_pos(cell: Vector2i) -> Vector2:
	return Vector2(float(cell.x * World.TILE) + 8.0, float((cell.y + 1) * World.TILE) - 11.0)


## Хост: поставить героя k (0 — свой, 1.. — прокси клиента k−1) в точку.
func place_hero(k: int, pos: Vector2) -> bool:
	if k == 0:
		player.global_position = pos
		player.vel = Vector2.ZERO
		return true
	var h: Player = hero_of(k - 1)
	return h != null and await teleport_proxy(h, pos)


# ------------------------------------------------------------------ НОЧЬ: ЗАМЕР НА ХОСТЕ

## Пары «фантом — герой», сошедшиеся ближе ENC_PX (встреча) за ночь.
const ENC_PX: float = 48.0

var _enc: Dictionary = {}       ## "фантом:герой" → true
var _hunt: Dictionary = {}      ## "фантом:герой" → true (фантом выбрал героя целью)
var _dmg: Dictionary = {}       ## индекс героя → урон
var _deaths: Dictionary = {}    ## индекс героя → смертей
var _hp_prev: Dictionary = {}
var _dead_prev: Dictionary = {}
var _min_hp: Dictionary = {}


func night_track_begin() -> void:
	_enc.clear()
	_hunt.clear()
	_dmg.clear()
	_deaths.clear()
	_hp_prev.clear()
	_dead_prev.clear()
	_min_hp.clear()
	var hs: Array = heroes()
	for k in hs.size():
		var h: Player = hs[k]
		_dmg[k] = 0.0
		_deaths[k] = 0
		_hp_prev[k] = h.hp if h != null else 0.0
		_dead_prev[k] = h.dead if h != null else false
		_min_hp[k] = h.hp if h != null else 0.0


## Звать каждый кадр ночи (хост).
func night_track_step() -> void:
	var hs: Array = heroes()
	var ph: Array = alive_phantoms()
	for k in hs.size():
		var h: Player = hs[k]
		if h == null:
			continue
		if h.dead and not bool(_dead_prev[k]):
			_deaths[k] = int(_deaths[k]) + 1
		_dead_prev[k] = h.dead
		if not h.dead:
			if h.hp < float(_hp_prev[k]):
				_dmg[k] = float(_dmg[k]) + float(_hp_prev[k]) - h.hp
			_min_hp[k] = minf(float(_min_hp[k]), h.hp)
		else:
			_min_hp[k] = 0.0
		_hp_prev[k] = h.hp
		for p in ph:
			var key: String = "%d:%d" % [(p as Node).get_instance_id(), k]
			if (p as Phantom).player == h:
				_hunt[key] = true
			if (p as Node2D).global_position.distance_to(h.global_position) < ENC_PX:
				_enc[key] = true


## Итог ночи по героям: {enc, hunt, dmg, deaths, min_hp, hp_end} — массивы по героям.
func night_track_result() -> Dictionary:
	var hs: Array = heroes()
	var n: int = hs.size()
	var enc: Array = []
	var hunt: Array = []
	enc.resize(n)
	hunt.resize(n)
	enc.fill(0)
	hunt.fill(0)
	for key in _enc:
		enc[int(String(key).get_slice(":", 1))] += 1
	for key in _hunt:
		hunt[int(String(key).get_slice(":", 1))] += 1
	var dmg: Array = []
	var deaths: Array = []
	var min_hp: Array = []
	var hp_end: Array = []
	for k in n:
		var h: Player = hs[k]
		dmg.append(float(_dmg[k]))
		deaths.append(int(_deaths[k]))
		min_hp.append(float(_min_hp[k]))
		hp_end.append(0.0 if h == null or h.dead or int(_deaths[k]) > 0 else h.hp)
	return {"enc": enc, "hunt": hunt, "dmg": dmg, "deaths": deaths, "min_hp": min_hp, "hp_end": hp_end}


static func mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s: float = 0.0
	for v in a:
		s += float(v)
	return s / float(a.size())


static func amin(a: Array) -> float:
	var m: float = INF
	for v in a:
		m = minf(m, float(v))
	return 0.0 if m == INF else m


static func asum(a: Array) -> float:
	var s: float = 0.0
	for v in a:
		s += float(v)
	return s


## Ночь day (хост): часы — к началу ночи, директор угрозы штатный (как siege_night и
## night_survive_1 #33: без Threat.reset — в сценарии директор до этого молчал). Ждём начала ночи.
func night_begin(day: int) -> void:
	seed_threat(day)
	Game.day_number = day
	Game.time_of_day = Balance.NIGHT_START - 1.0 / Balance.DAY_LENGTH
	drive_threat = true
	await wait_until(func() -> bool: return Game.is_night() and Threat.active, 5.0)


func night_end() -> void:
	drive_threat = false
	stop_fight()
