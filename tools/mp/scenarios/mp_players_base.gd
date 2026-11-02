extends MpScenarioBase
## Общее сценариев «Игроки по сети» (MP-D, #89): mp_move, mp_actions, mp_feedback.
##
## Хост находит прокси клиента i по uid, клиент — марионетку по uid. Телепорт героя
## клиента делает хост (переставить прокси → жёсткая поправка владельцу): так же,
## как возрождение. Данные между процессами (план сценария, траектории для замера)
## идут файлами user://mp_share/<порт>_<ключ>.bin — процессы на одной машине, порт
## сессии у каждого запуска свой; хост стирает файлы в конце.

const SHARE_DIR: String = "user://mp_share/"


func np() -> NetPlayers:
	return scene.get("net_players") as NetPlayers


## peer_id игрока с этим uid (−1 — нет такого).
func peer_of_uid(uid: int) -> int:
	for id in Net.peers:
		if int(Net.peers[id].get("uid", 0)) == uid:
			return int(id)
	return -1


## Хост: прокси клиента i. Клиент: марионетка клиента i (у себя — null).
func hero_of(i: int) -> Player:
	var n: NetPlayers = np()
	if n == null:
		return null
	return n.heroes.get(peer_of_uid(client_uid(i))) as Player


## Ждать, пока у хоста появятся прокси всех клиентов и придёт их ввод.
func wait_proxies(n: int, timeout: float) -> bool:
	return await wait_until(func() -> bool:
		for i in n:
			var p: Player = hero_of(i)
			if p == null or not np()._st.has(p.peer_id) or int(np()._st[p.peer_id]["rx"]) < 5:
				return false
		return true, timeout)


## Клиент: ждать марионеток остальных клиентов.
func wait_puppets(others: Array, timeout: float) -> bool:
	return await wait_until(func() -> bool:
		for i in others:
			var p: Player = hero_of(int(i))
			if p == null or (np()._buf.get(p.peer_id, []) as Array).size() < 3:
				return false
		return true, timeout)


## Хост: поставить прокси в точку (поправка владельцу) и дождаться, пока владелец
## её принял (пакеты ввода с новой эпохой, позиция рядом).
func teleport_proxy(p: Player, pos: Vector2, timeout: float = 3.0) -> bool:
	p.global_position = pos
	p.vel = Vector2.ZERO
	await wait(0.1)
	return await wait_until(func() -> bool:
		var st: Dictionary = np()._st.get(p.peer_id, {})
		return not st.is_empty() and not bool(st["corr"]) and p.global_position.distance_to(pos) < 24.0,
		timeout)


## Точка «стоя на поверхности» в столбце x (или рядом), не в стене.
func surface_stand(x: int) -> Vector2:
	for dx in [0, 1, -1, 2, -2, 3, -3, 4, -4]:
		var cx: int = clampi(x + int(dx), 2, World.W - 3)
		var p: Vector2 = Vector2(float(cx * World.TILE) + 8.0, float(World.surface[cx] * World.TILE) - 11.0)
		if not World.rect_solid(Rect2(p - Player.SIZE * 0.5, Player.SIZE)):
			return p
	return World.spawn_point


## Ни одной вентиляции ближе d px.
func far_from_vents(pos: Vector2, d: float) -> bool:
	for v in World.vents:
		if World.cell_to_world(v).distance_to(pos) < d:
			return false
	return true


## Точка на поверхности без вентиляций рядом, начиная со столбца x0 в сторону dir.
func vent_free_spot(x0: int, dir: int) -> Vector2:
	for k in 60:
		var p: Vector2 = surface_stand(x0 + dir * k * 3)
		if far_from_vents(p, 96.0):
			return p
	return surface_stand(x0)


static func p95(v: PackedFloat32Array) -> float:
	if v.is_empty():
		return 0.0
	var s: PackedFloat32Array = v.duplicate()
	s.sort()
	return s[clampi(int(ceil(0.95 * s.size())) - 1, 0, s.size() - 1)]


static func vmax(v: PackedFloat32Array) -> float:
	var m: float = 0.0
	for x in v:
		m = maxf(m, x)
	return m


static func wall_clock() -> float:
	return Time.get_unix_time_from_system()


## Принятые события UI.net_event (звук по имени / FX по виду) не дальше d от точки.
static func events_near(type: int, key: String, value, pos: Vector2, d: float) -> int:
	var n: int = 0
	for e in UI.net_events:
		if int(e["type"]) == type and e.get(key) == value and (e["pos"] as Vector2).distance_to(pos) <= d:
			n += 1
	return n


## Есть ли у клиента приём дельт мира (MP-C, #88): без него тайлы у второго клиента
## не меняются, и эта часть приёмки ждёт MP-C.
static func has_world_deltas() -> bool:
	return Net._handlers.has(NetCodec.Msg.TILES)


# ------------------------------------------------------------------ ФАЙЛЫ ОБМЕНА

func _share_port() -> int:
	return mp().port if is_host_side() else int(Net.session.get("port", 0))


func _share_path(key: String) -> String:
	return SHARE_DIR + "%d_%s.bin" % [_share_port(), key]


func share_put(key: String, value) -> void:
	DirAccess.make_dir_recursive_absolute(SHARE_DIR)
	var f: FileAccess = FileAccess.open(_share_path(key), FileAccess.WRITE)
	if f != null:
		f.store_buffer(var_to_bytes(value))
		f.close()


func share_get(key: String):
	var path: String = _share_path(key)
	if not FileAccess.file_exists(path):
		return null
	return bytes_to_var(FileAccess.get_file_as_bytes(path))


## Хост: стереть файлы обмена этого запуска.
func share_clear(keys: Array) -> void:
	for k in keys:
		var path: String = _share_path(String(k))
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
