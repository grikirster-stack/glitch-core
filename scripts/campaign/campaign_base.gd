class_name CampaignBase
extends RefCounted
## База экспедиции «Кербер-9» (ADR-004). Цех, шахта и оборона ушли с фабрикой (#170).
## Осталась станция: релей, терминалы, лампы, вентиляция и ствол шахты (SHAFT_*).
## Главы «Свет» достроят базу сами (#177).

enum Tier { STATION }

## Ствол шахты: x от релея (левая и правая клетки проёма), ряды — от пола базы.
const SHAFT_X0: int = -18
const SHAFT_X1: int = -16
const SHAFT_DEPTH: int = 43        ## пол штольни: пол базы + столько рядов
## Ряды между соседними уступами (они у разных стен). Прыжок героя — ~3 клетки, но с
## места под уступом той же стены (4 ряда выше) места на него нет: прыгают, сойдя с
## уступа к центру проёма, над которым пусто.
const LEDGE_STEP: int = 2


## Достроить базу до уровня tier. Итог: имя → постройка (MachineBase).
static func build(tier: int) -> Dictionary:
	var named: Dictionary = {}
	if tier >= Tier.STATION:
		_station(named)
	return named


## Пол базы (ряд стального пола под релеем).
static func floor_row() -> int:
	return World.beacon_cell.y + 1


## Дно шахты: ряд, на котором стоят постройки штольни.
static func mine_row() -> int:
	return floor_row() + SHAFT_DEPTH - 1


## Прочитать терминалы базы (главы журнала 1–2) без уведомлений: станция давно работает.
static func read_base_terminals() -> void:
	for t in World.terminals.duplicate():
		var ch: int = int(World.terminal_chapters.get(t, -1))
		if ch < 0 or ch >= Lore.BASE_TERMINALS:
			continue
		World.terminals.erase(t)
		World.set_tile(t.x, t.y, IDs.T.PANEL)
		if not Tech.read_chapters.has(ch):
			Tech.read_chapters.append(ch)
		Game.tasks_done += 1


# ------------------------------------------------------------------ ПОСТРОЙКИ

## Поставить постройку в клетку (клетку освобождает). opts: dir, items [[id, n], …]
## (сундук), fuel (уголь в горелку). null — не вышло.
static func put(kind: String, c: Vector2i, opts: Dictionary = {}) -> MachineBase:
	if World.machines.has(c):
		return World.machines[c]
	if World.get_tile_v(c) != IDs.T.AIR:
		World.set_tile(c.x, c.y, IDs.T.AIR)
	if not MachineBase.place_machine(kind, c):
		return null
	var m: MachineBase = World.machines[c]
	m.permanent = true   # постройка базы: разобрать её нельзя
	if opts.has("dir") and "dir" in m:
		m.set("dir", int(opts["dir"]))
	if opts.has("fuel") and m.kind == "Burner" and m.has_method("add_fuel"):
		m.add_fuel(IDs.I.COAL, int(opts["fuel"]))
	for e in opts.get("items", []):
		m.receive_item(int(e[0]), int(e[1]))
	return m


static func fill(x0: int, y0: int, x1: int, y1: int, id: int) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if World.get_tile(x, y) != id:
				World.set_tile(x, y, id)


# ------------------------------------------------------------------ УРОВНИ

static func _station(named: Dictionary) -> void:
	var bx: int = World.beacon_cell.x
	var row: int = World.beacon_cell.y
	read_base_terminals()
	# Горелка у релея: станция без тока, терминал читается и так (#170).
	named["burner_station"] = put("Burner", Vector2i(bx - 1, row), {"fuel": 4})



