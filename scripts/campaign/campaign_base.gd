class_name CampaignBase
extends RefCounted
## База экспедиции «Кербер-9» (ADR-004). Цех, шахта и оборона ушли с фабрикой (#170):
## бура, ленты, плавильни, ТЭЦ и турели нет. Осталась станция (релей, терминалы,
## лампы, вентиляция) и константы ствола (SHAFT_*). Главы «Свет» достраивают лагерь
## сами: жила угля у пещеры слева (COAL_*). Площадка глав 5–6 — LightLate (#179).

enum Tier { STATION }

## Ствол шахты: x от релея (левая и правая клетки проёма), ряды — от пола базы.
const SHAFT_X0: int = -18
const SHAFT_X1: int = -16
const SHAFT_DEPTH: int = 43        ## пол штольни: пол базы + столько рядов
## Ряды между соседними уступами (они у разных стен). Прыжок героя — ~3 клетки, но с
## места под уступом той же стены (4 ряда выше) места на него нет: прыгают, сойдя с
## уступа к центру проёма, над которым пусто.
const LEDGE_STEP: int = 2
## Жила главы «Копай»: 6 клеток угля в 10 клетках от базы. Ход от входа лагеря
## (пол базы − 2 клетки по x, на 4 ряда вниз) выходит к жиле: она видна из
## пещеры. Верхняя клетка жилы — воздух хода, нижние — порода: сквозь стену
## луч не копает. Центр — COAL_AT (маркер карточки).
const COAL_DX: int = -10
const COAL_N: int = 6
const COAL_AT: Vector2i = Vector2i(COAL_DX, 3)   ## от пола базы: x, ряд вниз


## Клетка центра жилы угля (маркер «Накопай 5 угля»).
static func coal_spot() -> Vector2i:
	return Vector2i(World.beacon_cell.x + COAL_AT.x, floor_row() + COAL_AT.y)


## Клетка входа в лагерь: воздух у левого края пола, рядом с вентиляцией.
static func camp_door() -> Vector2i:
	return Vector2i(World.beacon_cell.x - 12, World.beacon_cell.y)


## Достроить базу до уровня tier. Итог: имя → постройка (MachineBase).
static func build(tier: int) -> Dictionary:
	var named: Dictionary = {}
	if tier >= Tier.STATION:
		_camp(named)
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
		m.queue_redraw()
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

## Лагерь высадки и жила угля. Сундук мира уже стоит (кирка нет — её в игре нет,
## светокристаллы и уголь). Ход от входа лагеря выходит к жиле в 10 клетках.
static func _camp(named: Dictionary) -> void:
	var door: Vector2i = camp_door()
	var spot: Vector2i = coal_spot()
	# Ход: от входа вниз и влево, до клетки перед жилой. Пол хода — камень,
	# над ним воздух на два ряда: от входа жилу видно.
	var x0: int = spot.x + 1
	var x1: int = door.x
	var y_air0: int = door.y + 1
	var y_air1: int = spot.y - 1
	fill(x0, y_air0, x1, y_air1, IDs.T.AIR)
	fill(x0, spot.y, x1, spot.y, IDs.T.STONE)
	# Ствол шахты (SHAFT_X0) начинается левее жилы — ход его не трогает.
	for dy in range(COAL_N):
		World.set_tile(spot.x, spot.y - 2 + dy, IDs.T.COAL_ORE)
	named["coal"] = spot
	named["door"] = door


static func _station(named: Dictionary) -> void:
	var bx: int = World.beacon_cell.x
	var row: int = World.beacon_cell.y
	read_base_terminals()
	# Горелка у релея: станция без тока, терминал читается и так (#170).
	named["burner_station"] = put("Burner", Vector2i(bx - 1, row), {"fuel": 4})



