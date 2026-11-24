extends "res://tools/mp/scenarios/mp_coop_base.gd"
## mp_free_mark (#315): открытие сундука метку не двигает. Перенос — кнопка
## «Сделать меткой базы». Чужой сундук отказывает. Клиент жмёт кнопку — хост
## переносит, клиент слышит подтверждение. Поздний вход видит клетку в GLOBAL.

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
	var opened: bool = await _open(own)
	ok("открытие своего сундука метку не сдвинуло", opened and Game.base_mark_cell() == World.beacon_cell,
			str(Game.base_mark_cell()))
	ok("открытие не пишет про перенос", notes_with("Метка базы перенесена") == 0, str(notes))
	var moved: bool = await _press(own)
	ok("кнопка по своему сундуку перенесла метку", moved and Game.base_mark_cell() == own, str(Game.base_mark_cell()))
	ok("хост услышал перенос", notes_with("Метка базы перенесена") >= 1, str(notes))
	var foreign_open: bool = await _open(foreign)
	var foreign_btn: bool = UI.panel != null and UI.panel.has_method("_mark_enabled") and UI.panel._mark_enabled()
	var denied: bool = await _press(foreign)
	ok("чужой сундук: кнопки нет и метка не едет", foreign_open and not foreign_btn and not denied
			and Game.base_mark_cell() == own, "кнопка %s, метка %s" % [str(foreign_btn), str(Game.base_mark_cell())])
	ok("чужой сундук говорит отказом", notes_with("Чужой сундук") >= 1, str(notes))
	share_put("mark", own)
	share_put("sends", Game.signal_sends)
	# Клиент жмёт кнопку своего сундука. Хост ставит прокси рядом: иначе «Сундук далеко».
	var client_uid: int = client_uid(0)
	var client_cell: Vector2i = _chest(World.beacon_cell + Vector2i(-4, 0), client_uid)
	share_put("client_mark", client_cell)
	var proxy: Player = hero_of(0)
	var near: bool = proxy != null and client_cell.x >= 0 and await teleport_proxy(proxy, World.cell_to_world(client_cell))
	ok("прокси клиента стоит у своего сундука", near, str(proxy.global_position if proxy != null else "нет прокси"))
	await barrier("press")
	var by_client: bool = await wait_until(func() -> bool: return Game.base_mark_cell() == client_cell, WAIT)
	ok("кнопка клиента перенесла метку на хосте", by_client, str(Game.base_mark_cell()))
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
	share_clear(["mark", "mark2", "sends", "client_mark"])
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
	await barrier("press")
	# Кнопка клиента идёт командой MARK. Сундук клиент ставит сам: снимок
	# входа его ещё не содержит, а клетка в команде — та же.
	var client_cell = share_get("client_mark")
	var sent: bool = false
	if client_cell is Vector2i and player.has_method("request_base_mark"):
		var box = World.machines.get(client_cell)
		if box == null:
			_chest(client_cell, int(player.net_uid))
			box = World.machines.get(client_cell)
		if box != null:
			player.request_base_mark(box)
			sent = true
	var heard: bool = sent and await wait_until(func() -> bool:
		return notes_with("Метка базы перенесена") >= 1 and Game.base_mark == client_cell, WAIT)
	ok("клиент нажал кнопку и услышал перенос", heard,
			"послал %s, ждали %s, метка %s, заметки %s" % [str(sent), str(client_cell), str(Game.base_mark), str(notes)])
	await barrier("moved")
	# Барьер отпускает клиента раньше, чем хост дописывает файл.
	# Лямбда не пишет во внешнюю переменную — клетка копится в ячейке массива.
	var box: Array = [null]
	var shared: bool = await wait_until(func() -> bool:
		box[0] = share_get("mark2")
		return box[0] is Vector2i, WAIT)
	var second = box[0]
	var live: bool = shared and await wait_until(func() -> bool:
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


func _open(cell: Vector2i) -> bool:
	var box = World.machines.get(cell)
	if box == null or not player.has_method("_open_chest"):
		return false
	player._open_chest(box)
	await await_frame()
	return UI.panel != null and UI.panel.chest == box


## Кнопка в окне. На базе mark_base нет — проверка красная, не ошибка скрипта.
func _press(cell: Vector2i) -> bool:
	if not await _open(cell):
		return false
	if UI.panel == null or not UI.panel.has_method("mark_base"):
		return false
	var before: Vector2i = Game.base_mark_cell()
	UI.panel.mark_base()
	await await_frame()
	return Game.base_mark_cell() == cell and cell != before
