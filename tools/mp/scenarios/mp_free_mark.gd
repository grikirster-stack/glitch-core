extends "res://tools/mp/scenarios/mp_coop_base.gd"
## mp_free_mark (#315): игрок переносит метку базы через E, не через прямой API.
## Чужой сундук отказывает. Поздний вход видит новую клетку в GLOBAL, не только
## в снимке: клиент входит, метку двигают, он выходит и входит снова.

const WAIT: float = 12.0


func run_host() -> void:
	ok("хост + клиент вошли", await wait_players(2, 45.0))
	await barrier("in")
	var mine: int = int(player.net_uid)
	var own: Vector2i = _chest(World.beacon_cell + Vector2i(4, 0), mine)
	var foreign: Vector2i = _chest(World.beacon_cell + Vector2i(6, 0), 7 if mine != 7 else 9)
	ok("свой и чужой сундуки поставлены", own.x >= 0 and foreign.x >= 0, "%s / %s" % [own, foreign])
	var box = World.machines.get(own)
	ok("штамп хозяина дожил до E", box != null and int(box.owner_uid) == mine,
			"сундук %s, герой %d" % [str(box.owner_uid if box != null else -2), mine])
	var moved: bool = await _press(own)
	ok("E по своему сундуку перенёс метку", moved and Game.base_mark_cell() == own, str(Game.base_mark_cell()))
	ok("хост услышал перенос", notes_with("Метка базы перенесена") >= 1, str(notes))
	var denied: bool = await _press(foreign)
	ok("чужой сундук метку не берёт", not denied and Game.base_mark_cell() == own, str(Game.base_mark_cell()))
	ok("чужой сундук говорит отказом", notes_with("Чужой сундук") >= 1, str(notes))
	share_put("mark", own)
	share_put("sends", Game.signal_sends)
	# Уже вошедший клиент должен увидеть клетку живым пакетом, до повторного входа.
	await barrier("moved")
	var later: Vector2i = _chest(World.beacon_cell + Vector2i(8, 0), mine)
	var again: bool = await _press(later)
	ok("второй перенос после барьера", again and Game.base_mark_cell() == later, str(Game.base_mark_cell()))
	share_put("mark2", later)
	# Публикация не молчит: метод есть и зовётся из base_mark_move.
	ok("публикация GLOBAL ушла сразу, не заглушкой", Game.net_world != null
			and int(Game.net_world.get("globals_now")) >= 2, str(Game.net_world.get("globals_now") if Game.net_world != null else "нет"))
	await barrier("leave")
	ok("клиент вышел", await wait_until(func() -> bool: return Net.peers.size() == 1, 15.0))
	relaunch(0)
	ok("клиент вошёл снова", await wait_players(2, 45.0))
	await barrier("back")
	share_clear(["mark", "mark2", "sends"])
	finish()


func run_client(_i: int) -> void:
	if is_rejoin():
		# Порт сессии и снимок приходят после рукопожатия. Читать share раньше — null.
		var back: bool = await wait_until(func() -> bool:
			return int(Net.session.get("port", 0)) != 0 and Game.net_world != null and Game.net_world.is_joined, WAIT)
		var want = share_get("mark2")
		var got: bool = back and want is Vector2i and await wait_until(func() -> bool:
			return Game.base_mark_set and Game.base_mark == want, WAIT)
		ok("поздний вход видит метку после переноса", got, "ждали %s, метка %s set=%s" % [
			str(want), str(Game.base_mark), str(Game.base_mark_set)])
		await barrier("back")
		finish()
		return
	await barrier("in")
	await barrier("moved")
	# Снимок входа уже мог принести первую клетку. Вторая ставится после барьера —
	# её клиент видит только живым GLOBAL, не снимком.
	var second = share_get("mark2")
	var live: bool = second is Vector2i and await wait_until(func() -> bool:
		return Game.base_mark_set and Game.base_mark == second, WAIT)
	ok("уже вошедший видит вторую метку живым пакетом", live,
			"ждали %s, метка %s" % [str(second), str(Game.base_mark)])
	await barrier("leave")
	finish()


func _chest(cell: Vector2i, owner: int) -> Vector2i:
	if World.get_tile_v(cell) != IDs.T.AIR:
		World.set_tile(cell.x, cell.y, IDs.T.AIR)
	if World.machines.has(cell):
		return Vector2i(-1, -1)
	if not MachineBase.place_machine("Chest", cell):
		return Vector2i(-1, -1)
	var box = World.machines.get(cell)
	if box != null:
		box.owner_uid = owner
	return cell


func _press(cell: Vector2i) -> bool:
	var box = World.machines.get(cell)
	if box == null or not player.has_method("_open_chest"):
		return false
	var before: Vector2i = Game.base_mark_cell()
	player._open_chest(box)
	await await_frame()
	return Game.base_mark_cell() == cell and cell != before
