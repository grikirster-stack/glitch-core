extends Node
## База данных тайлов, предметов, рецептов + процедурная генерация всей графики.
## Внешних ассетов нет: все текстуры рисуются кодом при запуске.

const TILE_SIZE: int = 16
const ATLAS_COLS: int = 8

var item_defs: Dictionary = {}
var tile_defs: Dictionary = {}
var relay_req: Dictionary = {}
var recipes: Array = []
var item_textures: Dictionary = {}
var atlas_texture: ImageTexture
var glow_texture: ImageTexture
var atlas_of_tile: Dictionary = {}


func _ready() -> void:
	var t0: int = Time.get_ticks_usec()
	_build_tile_defs()
	_build_item_defs()
	_build_recipes()
	_build_atlas()
	_build_glow()
	print("[DB] тайлов=%d предметов=%d рецептов=%d за %.1f мс" % [
			tile_defs.size(), item_defs.size(), recipes.size(),
			float(Time.get_ticks_usec() - t0) / 1000.0])


# ---------------------------------------------------------------- ТАЙЛЫ

## Поля тайла: solid — стена для тел; hard — секунды копки игроком; drop — предмет;
## light — сила свечения; dig — роет ли его копатель (ADR-001 § 4.4): природная
## порода не твёрже Balance.BURROWER_DIG_MAX_HARD — да, всё построенное — нет.
func _build_tile_defs() -> void:
	tile_defs = {
		IDs.T.AIR: {"solid": false, "hard": 0.0, "drop": 0, "light": 0.0, "name": "Воздух"},
		IDs.T.STONE: {"solid": true, "hard": 1.4, "drop": IDs.I.STONE, "light": 0.0, "name": "Камень", "dig": true},
		IDs.T.DIRT: {"solid": true, "hard": 0.5, "drop": IDs.I.SCRAP, "light": 0.0, "name": "Земля", "dig": true},
		IDs.T.GRASS: {"solid": true, "hard": 0.6, "drop": IDs.I.SCRAP, "light": 0.0, "name": "Трава", "dig": true},
		IDs.T.SAND: {"solid": true, "hard": 0.4, "drop": IDs.I.SAND, "light": 0.0, "name": "Песок", "dig": true},
		IDs.T.SANDSTONE: {"solid": true, "hard": 1.2, "drop": IDs.I.STONE, "light": 0.0, "name": "Песчаник", "dig": true},
		IDs.T.LOG: {"solid": true, "hard": 1.0, "drop": IDs.I.LOG, "light": 0.0, "name": "Бревно", "dig": true},
		# Ствол дерева: выглядит как бревно, но сквозь него можно пройти —
		# лес не должен запирать игрока в клетке между стволами.
		IDs.T.TREE: {"solid": false, "hard": 1.0, "drop": IDs.I.LOG, "light": 0.0, "name": "Ствол дерева"},
		IDs.T.LEAVES: {"solid": false, "hard": 0.2, "drop": 0, "light": 0.0, "name": "Листва"},
		IDs.T.COPPER_ORE: {"solid": true, "hard": 2.0, "drop": IDs.I.COPPER_ORE, "light": 0.0, "name": "Медная руда"},
		IDs.T.IRON_ORE: {"solid": true, "hard": 2.6, "drop": IDs.I.IRON_ORE, "light": 0.0, "name": "Железная руда"},
		IDs.T.CRYSTAL_ORE: {"solid": true, "hard": 3.4, "drop": IDs.I.CRYSTAL, "light": 0.15, "name": "Кристалл глитча"},
		IDs.T.COAL_ORE: {"solid": true, "hard": 1.8, "drop": IDs.I.COAL, "light": 0.0, "name": "Уголь"},
		IDs.T.SCRAP_ORE: {"solid": true, "hard": 1.0, "drop": IDs.I.SCRAP, "light": 0.0, "name": "Хлам", "dig": true},
		IDs.T.WATER: {"solid": false, "hard": 999.0, "drop": 0, "light": 0.0, "name": "Вода"},
		IDs.T.LAVA: {"solid": false, "hard": 999.0, "drop": 0, "light": 0.4, "name": "Лава"},
		IDs.T.BEDROCK: {"solid": true, "hard": 999.0, "drop": 0, "light": 0.0, "name": "Коренная порода"},
		IDs.T.STEEL: {"solid": true, "hard": 3.0, "drop": 0, "light": 0.0, "name": "Сталь"},
		IDs.T.PANEL: {"solid": true, "hard": 3.0, "drop": 0, "light": 0.0, "name": "Панель"},
		IDs.T.TERMINAL: {"solid": true, "hard": 3.0, "drop": 0, "light": 0.25, "name": "Терминал"},
		IDs.T.GLASS: {"solid": true, "hard": 0.8, "drop": 0, "light": 0.0, "name": "Стекло"},
		IDs.T.COPPER_BLOCK: {"solid": true, "hard": 2.4, "drop": IDs.I.COPPER_BLOCK, "light": 0.0, "name": "Медный блок"},
		IDs.T.IRON_BLOCK: {"solid": true, "hard": 2.8, "drop": IDs.I.IRON_BLOCK, "light": 0.0, "name": "Железный блок"},
		IDs.T.CRYSTAL_BLOCK: {"solid": true, "hard": 2.6, "drop": IDs.I.CRYSTAL_BLOCK, "light": 0.2, "name": "Кристальный блок"},
		IDs.T.LIGHT_CRYSTAL: {"solid": true, "hard": 0.6, "drop": IDs.I.LAMP, "light": 1.0, "name": "Светокристалл"},
		IDs.T.MOSS: {"solid": true, "hard": 0.6, "drop": IDs.I.SCRAP, "light": 0.0, "name": "Мох", "dig": true},
		IDs.T.RELAY_CORE: {"solid": true, "hard": 999.0, "drop": 0, "light": 0.5, "name": "Релей-ядро"},
		# --- ADR-001 § 4.4: оборона базы. Поведение шлюза и решётки — #31, здесь только данные.
		IDs.T.STEEL_WALL: {"solid": true, "hard": Balance.STEEL_WALL_HARD, "drop": IDs.I.STEEL_WALL, "light": 0.0, "name": "Стальная стена"},
		IDs.T.AIRLOCK: {"solid": true, "hard": 3.0, "drop": IDs.I.AIRLOCK, "light": 0.0, "name": "Шлюз"},
		IDs.T.AIRLOCK_OPEN: {"solid": false, "hard": 3.0, "drop": IDs.I.AIRLOCK, "light": 0.0, "name": "Шлюз (открыт)"},
		IDs.T.VENT_GRATE: {"solid": false, "hard": 1.0, "drop": IDs.I.VENT_GRATE, "light": 0.0, "name": "Решётка вентиляции"},
	}


func tile_def(id: int) -> Dictionary:
	return tile_defs.get(id, tile_defs[IDs.T.AIR])


func tile_solid(id: int) -> bool:
	return bool(tile_def(id).get("solid", false))


func tile_hard(id: int) -> float:
	return float(tile_def(id).get("hard", 1.0))


func tile_drop(id: int) -> int:
	return int(tile_def(id).get("drop", 0))


func tile_light(id: int) -> float:
	return float(tile_def(id).get("light", 0.0))


func tile_name(id: int) -> String:
	return String(tile_def(id).get("name", "?"))


## Роет ли копатель этот тайл (ADR-001 § 4.4). Флаг "dig" задаётся явно в tile_defs:
## природная порода — да, построенное (блоки, сталь, стена) — нет.
func tile_diggable(id: int) -> bool:
	return bool(tile_def(id).get("dig", false))


## Базовый цвет тайла — используется для частиц при добыче.
func tile_color(id: int) -> Color:
	match id:
		IDs.T.STONE:
			return Color(0.42, 0.44, 0.48)
		IDs.T.DIRT:
			return Color(0.47, 0.33, 0.20)
		IDs.T.GRASS:
			return Color(0.29, 0.55, 0.24)
		IDs.T.SAND:
			return Color(0.85, 0.76, 0.49)
		IDs.T.SANDSTONE:
			return Color(0.76, 0.65, 0.42)
		IDs.T.LOG:
			return Color(0.42, 0.29, 0.17)
		IDs.T.TREE:
			return Color(0.42, 0.29, 0.17)
		IDs.T.LEAVES:
			return Color(0.24, 0.48, 0.21)
		IDs.T.MOSS:
			return Color(0.35, 0.33, 0.31)
		IDs.T.COPPER_ORE:
			return Color(0.80, 0.48, 0.25)
		IDs.T.IRON_ORE:
			return Color(0.85, 0.88, 0.93)
		IDs.T.CRYSTAL_ORE:
			return Color(0.72, 0.44, 0.99)
		IDs.T.COAL_ORE:
			return Color(0.14, 0.14, 0.17)
		IDs.T.SCRAP_ORE:
			return Color(0.60, 0.48, 0.29)
		IDs.T.WATER:
			return Color(0.16, 0.38, 0.72)
		IDs.T.LAVA:
			return Color(0.95, 0.52, 0.12)
		IDs.T.BEDROCK:
			return Color(0.18, 0.19, 0.22)
		IDs.T.STEEL:
			return Color(0.55, 0.58, 0.63)
		IDs.T.PANEL:
			return Color(0.28, 0.31, 0.36)
		IDs.T.TERMINAL:
			return Color(0.20, 0.22, 0.26)
		IDs.T.GLASS:
			return Color(0.62, 0.85, 0.91)
		IDs.T.COPPER_BLOCK:
			return Color(0.79, 0.46, 0.26)
		IDs.T.IRON_BLOCK:
			return Color(0.84, 0.87, 0.91)
		IDs.T.CRYSTAL_BLOCK:
			return Color(0.63, 0.36, 0.92)
		IDs.T.LIGHT_CRYSTAL:
			return Color(1.0, 0.91, 0.64)
		IDs.T.RELAY_CORE:
			return Color(0.35, 0.95, 0.65)
		IDs.T.STEEL_WALL:
			return Color(0.58, 0.62, 0.68)
		IDs.T.AIRLOCK, IDs.T.AIRLOCK_OPEN:
			return Color(0.85, 0.70, 0.20)
		IDs.T.VENT_GRATE:
			return Color(0.50, 0.55, 0.60)
		_:
			return Color(0.60, 0.60, 0.65)


func is_liquid(id: int) -> bool:
	return id == IDs.T.WATER or id == IDs.T.LAVA


# ---------------------------------------------------------------- ПРЕДМЕТЫ

func _item(p_name: String, p_color: Color, p_shape: String, p_stack: int = 99,
		p_place: String = "", p_fuel: int = 0) -> void:
	# Заглушка NONE уже лежит под ключом 0, поэтому первый предмет = 1.
	var id: int = item_defs.size()
	item_defs[id] = {
		"id": id,
		"name": p_name,
		"color": p_color,
		"shape": p_shape,
		"stack": p_stack,
		"place": p_place,
		"fuel": p_fuel,
	}


func _build_item_defs() -> void:
	# Порядок _item() задаёт id по порядку: 1 == NONE-заглушка.
	item_defs[IDs.I.NONE] = {"id": 0, "name": "—", "color": Color(0, 0, 0, 0), "shape": "none", "stack": 1, "place": "", "fuel": 0}

	_item("Медная руда", Color(0.79, 0.47, 0.24), "ore")
	_item("Железная руда", Color(0.82, 0.85, 0.89), "ore")
	_item("Кристалл глитча", Color(0.70, 0.42, 0.98), "shard")
	_item("Уголь", Color(0.17, 0.17, 0.20), "lump")
	_item("Хлам", Color(0.60, 0.48, 0.29), "lump")
	_item("Песок", Color(0.85, 0.75, 0.48), "pile")
	_item("Бревно", Color(0.42, 0.29, 0.17), "log")
	_item("Камень", Color(0.42, 0.44, 0.47), "ore")

	_item("Медный слиток", Color(0.86, 0.53, 0.30), "ingot")
	_item("Железный слиток", Color(0.87, 0.90, 0.94), "ingot")
	_item("Стекло", Color(0.62, 0.85, 0.91), "glass")

	_item("Медная пластина", Color(0.90, 0.58, 0.33), "plate")
	_item("Железная пластина", Color(0.90, 0.93, 0.97), "plate")
	_item("Микросхема", Color(0.29, 0.75, 0.42), "circuit")
	_item("Стальная пластина", Color(0.62, 0.67, 0.74), "plate")
	_item("Энергоячейка", Color(0.35, 0.80, 0.95), "cell")

	_item("Буровая станция", Color(0.55, 0.58, 0.63), "drill", 5, "machine:Drill")
	_item("Плавильня", Color(0.72, 0.42, 0.28), "smelter", 5, "machine:Smelter")
	_item("Сборщик", Color(0.45, 0.62, 0.78), "assembler", 3, "machine:Assembler")
	_item("Конвейер", Color(0.75, 0.60, 0.25), "belt", 30, "machine:Belt")
	_item("Сундук", Color(0.55, 0.36, 0.20), "chest", 10, "machine:Chest")
	_item("Угольная ТЭЦ", Color(0.35, 0.35, 0.40), "gen", 5, "machine:CoalGen")
	_item("Солнечная панель", Color(0.25, 0.40, 0.72), "solar", 5, "machine:Solar")
	_item("Светокристалл", Color(1.0, 0.91, 0.64), "lamp", 20, "tile:%d" % IDs.T.LIGHT_CRYSTAL)

	_item("Медный блок", Color(0.80, 0.46, 0.26), "block", 99, "tile:%d" % IDs.T.COPPER_BLOCK)
	_item("Железный блок", Color(0.85, 0.88, 0.92), "block", 99, "tile:%d" % IDs.T.IRON_BLOCK)
	_item("Кристальный блок", Color(0.66, 0.38, 0.92), "block", 99, "tile:%d" % IDs.T.CRYSTAL_BLOCK)

	# Дополнительные строительные блоки, доступные сразу.
	_add_item_def(IDs.I.STONE, "Камень", Color(0.44, 0.46, 0.50), "block", 99, "tile:%d" % IDs.T.STONE)
	_add_item_def(IDs.I.SAND, "Песок", Color(0.85, 0.75, 0.48), "pile", 99, "tile:%d" % IDs.T.SAND)
	_add_item_def(IDs.I.LOG, "Бревно", Color(0.42, 0.29, 0.17), "log", 99, "tile:%d" % IDs.T.LOG)

	# --- ADR-001 (#24): новые предметы по явным id, чтобы порядок _item() выше не сдвигался.
	# Машины ставятся через MachineBase.place_machine — свои ветки в match добавят
	# #30 (манипулятор, анализатор, глубинный бур) и #31 (турель, прожектор).
	# До этого постройка отвечает «Сюда нельзя поставить».
	# Автоматизация (§ 4.2)
	_add_item_def(IDs.I.INSERTER, "Манипулятор", Color(0.80, 0.62, 0.30), "inserter", 30, "machine:Inserter")
	_add_item_def(IDs.I.ANALYZER, "Анализатор", Color(0.40, 0.75, 0.70), "analyzer", 3, "machine:Analyzer")
	_add_item_def(IDs.I.DEEP_DRILL, "Глубинный бур", Color(0.40, 0.44, 0.52), "deep_drill", 3, "machine:DeepDrill")
	# Оборона (§ 4.4)
	_add_item_def(IDs.I.TURRET, "Турель-разрядник", Color(0.55, 0.60, 0.70), "turret", 5, "machine:Turret")
	_add_item_def(IDs.I.FLOODLIGHT, "Прожектор", Color(0.95, 0.90, 0.60), "floodlight", 10, "machine:Floodlight")
	_add_item_def(IDs.I.STEEL_WALL, "Стальная стена", Color(0.58, 0.62, 0.68), "wall", 99, "tile:%d" % IDs.T.STEEL_WALL)
	_add_item_def(IDs.I.AIRLOCK, "Шлюз", Color(0.85, 0.70, 0.20), "airlock", 10, "tile:%d" % IDs.T.AIRLOCK)
	_add_item_def(IDs.I.VENT_GRATE, "Решётка вентиляции", Color(0.50, 0.55, 0.60), "grate", 20, "tile:%d" % IDs.T.VENT_GRATE)
	# Релей и лор (§ 4.7, § 4.9) — не ставятся, только носятся.
	_add_item_def(IDs.I.RELAY_ANTENNA, "Антенна релея", Color(0.35, 0.95, 0.80), "antenna", 1, "")
	_add_item_def(IDs.I.BLACK_BOX, "Чёрный ящик", Color(0.90, 0.35, 0.20), "blackbox", 20, "")
	_add_item_def(IDs.I.LOOT_BAG, "Мешок", Color(0.45, 0.38, 0.30), "bag", 1, "")

	# Требования релей-ядра — из Balance (§ 4.7).
	relay_req = Balance.RELAY_REQ.duplicate()

func _add_item_def(id: int, p_name: String, p_color: Color, p_shape: String,
		p_stack: int, p_place: String, p_fuel: int = 0) -> void:
	item_defs[id] = {
		"id": id, "name": p_name, "color": p_color, "shape": p_shape,
		"stack": p_stack, "place": p_place, "fuel": p_fuel,
	}


func item_def(id: int) -> Dictionary:
	return item_defs.get(id, item_defs[IDs.I.NONE])


func item_name(id: int) -> String:
	return String(item_def(id).get("name", "?"))


func item_max_stack(id: int) -> int:
	return int(item_def(id).get("stack", 99))


func item_place(id: int) -> String:
	return String(item_def(id).get("place", ""))


func item_fuel(id: int) -> int:
	return int(item_def(id).get("fuel", 0))


func item_color(id: int) -> Color:
	return item_def(id).get("color", Color.MAGENTA)


# ---------------------------------------------------------------- РЕЦЕПТЫ

## tech — узел дерева технологий (ключ Balance.TECH_COST), с которого рецепт
## открыт; "T0" — доступен с самого начала (ADR-001 § 4.6). Дерево и трату
## данных ведёт #28; пока Tech.is_unlocked() отвечает «да» на всё, и крафт
## ведёт себя как раньше.
func _recipe(out: int, amount: int, inputs: Dictionary, station: String, time: float, name: String,
		tech: String = "T0") -> void:
	recipes.append({
		"out": out, "amount": amount, "in": inputs,
		"station": station, "time": time, "name": name, "tech": tech,
	})


func _build_recipes() -> void:
	# --- Ручной крафт: с чего начать -----------------------------------------
	# Ручная выплавка — грубая (2 руды на слиток), зато доступна без станций.
	# Правило ADR-001 D3: у всего есть машинный рецепт, ручной — дороже или медленнее.
	_recipe(IDs.I.COPPER_INGOT, 1, {IDs.I.COPPER_ORE: 2}, "hand", 1.0, "Ручная выплавка меди")
	_recipe(IDs.I.IRON_INGOT, 1, {IDs.I.IRON_ORE: 2}, "hand", 1.2, "Ковка железа")
	_recipe(IDs.I.GLASS, 1, {IDs.I.SAND: 2}, "hand", 1.0, "Обжиг стекла")
	_recipe(IDs.I.COPPER_PLATE, 1, {IDs.I.COPPER_INGOT: 2}, "hand", 1.0, "Медная пластина")
	_recipe(IDs.I.IRON_PLATE, 1, {IDs.I.IRON_INGOT: 2}, "hand", 1.2, "Железная пластина")
	_recipe(IDs.I.LAMP, 1, {IDs.I.CRYSTAL: 1, IDs.I.COAL: 1}, "hand", 0.8, "Светокристалл")
	_recipe(IDs.I.COPPER_BLOCK, 1, {IDs.I.COPPER_INGOT: 4}, "hand", 1.0, "Медный блок")
	_recipe(IDs.I.IRON_BLOCK, 1, {IDs.I.IRON_INGOT: 4}, "hand", 1.0, "Железный блок")
	_recipe(IDs.I.CRYSTAL_BLOCK, 1, {IDs.I.CRYSTAL: 3}, "hand", 1.0, "Кристальный блок")
	# Первые постройки собираются вручную — иначе не с чего начать.
	_recipe(IDs.I.SOLAR, 1, {IDs.I.COPPER_PLATE: 1, IDs.I.GLASS: 1}, "hand", 2.0, "Солнечная панель")
	_recipe(IDs.I.SMELTER, 1, {IDs.I.STONE: 6, IDs.I.SCRAP: 4}, "hand", 2.0, "Плавильня")
	_recipe(IDs.I.COAL_GEN, 1, {IDs.I.IRON_PLATE: 2, IDs.I.SCRAP: 6}, "hand", 2.5, "Угольная ТЭЦ")
	_recipe(IDs.I.ASSEMBLER, 1, {IDs.I.IRON_PLATE: 4, IDs.I.COPPER_PLATE: 2}, "hand", 3.0, "Сборщик", "T1")
	# Конвейер и сундук доступны с первой смены руками (T0): сборщик делает их выгоднее.
	_recipe(IDs.I.BELT, 1, {IDs.I.IRON_PLATE: 1}, "hand", 1.5, "Конвейер вручную")
	_recipe(IDs.I.CHEST, 1, {IDs.I.IRON_PLATE: 4}, "hand", 2.5, "Сундук вручную")

	# --- Плавильня: вдвое больше слитков за ту же руду -----------------------
	_recipe(IDs.I.IRON_INGOT, 1, {IDs.I.IRON_ORE: 1}, "smelter", 2.0, "Выплавка железа")
	_recipe(IDs.I.COPPER_INGOT, 1, {IDs.I.COPPER_ORE: 1}, "smelter", 1.6, "Выплавка меди")
	_recipe(IDs.I.GLASS, 1, {IDs.I.SAND: 2}, "smelter", 2.2, "Плавка стекла")
	_recipe(IDs.I.STEEL_PLATE, 1, {IDs.I.IRON_INGOT: 2, IDs.I.COAL: 1}, "smelter", 3.5, "Стальная пластина")
	# Пластины на плавильне — чтобы цепочка «руда → релей» собиралась без рук (§ 4.2).
	_recipe(IDs.I.COPPER_PLATE, 1, {IDs.I.COPPER_INGOT: 2}, "smelter", 2.0, "Прокат меди", "T1")
	_recipe(IDs.I.IRON_PLATE, 1, {IDs.I.IRON_INGOT: 2}, "smelter", 2.0, "Прокат железа", "T1")
	_recipe(IDs.I.STEEL_WALL, 4, {IDs.I.STEEL_PLATE: 2}, "smelter", 2.0, "Стальная стена", "T2")

	# --- Сборщик: сложные изделия ------------------------------------------
	_recipe(IDs.I.CIRCUIT, 1, {IDs.I.COPPER_PLATE: 1, IDs.I.CRYSTAL: 2}, "assembler", 3.0, "Микросхема", "T1")
	_recipe(IDs.I.POWER_CELL, 1, {IDs.I.IRON_PLATE: 1, IDs.I.CRYSTAL: 1}, "assembler", 3.0, "Энергоячейка", "T1")
	_recipe(IDs.I.BELT, 2, {IDs.I.IRON_PLATE: 1}, "assembler", 1.5, "Конвейер", "T1")
	_recipe(IDs.I.CHEST, 1, {IDs.I.IRON_PLATE: 3}, "assembler", 2.0, "Сундук", "T1")
	_recipe(IDs.I.DRILL, 1, {IDs.I.IRON_PLATE: 4, IDs.I.CIRCUIT: 2}, "assembler", 4.0, "Буровая станция", "T3")
	# ADR-001: автоматизация (§ 4.2), оборона (§ 4.4), релей (§ 4.7).
	_recipe(IDs.I.INSERTER, 1, {IDs.I.IRON_PLATE: 1, IDs.I.COPPER_PLATE: 1}, "assembler", 2.0, "Манипулятор", "T1")
	_recipe(IDs.I.TURRET, 1, {IDs.I.STEEL_PLATE: 3, IDs.I.CIRCUIT: 2, IDs.I.POWER_CELL: 1}, "assembler", 5.0, "Турель-разрядник", "T2")
	_recipe(IDs.I.AIRLOCK, 1, {IDs.I.STEEL_PLATE: 2, IDs.I.CIRCUIT: 1}, "assembler", 3.0, "Шлюз", "T2")
	_recipe(IDs.I.ANALYZER, 1, {IDs.I.IRON_PLATE: 4, IDs.I.CIRCUIT: 2, IDs.I.GLASS: 2}, "assembler", 4.0, "Анализатор", "T3")
	_recipe(IDs.I.FLOODLIGHT, 1, {IDs.I.COPPER_PLATE: 2, IDs.I.GLASS: 1, IDs.I.CRYSTAL: 1}, "assembler", 2.5, "Прожектор", "T3")
	_recipe(IDs.I.VENT_GRATE, 1, {IDs.I.IRON_PLATE: 2}, "assembler", 1.5, "Решётка вентиляции", "T4")
	_recipe(IDs.I.DEEP_DRILL, 1, {IDs.I.DRILL: 1, IDs.I.STEEL_PLATE: 4, IDs.I.CIRCUIT: 2}, "assembler", 6.0, "Глубинный бур", "T4")
	_recipe(IDs.I.RELAY_ANTENNA, 1, {IDs.I.COPPER_PLATE: 6, IDs.I.GLASS: 4, IDs.I.CRYSTAL_BLOCK: 2}, "assembler", 8.0, "Антенна релея", "T5")


func recipes_for(station: String) -> Array:
	var out: Array = []
	for r in recipes:
		if String(r["station"]) == station:
			out.append(r)
	return out


## Открыт ли рецепт по дереву технологий. Панель крафта (#28) серит закрытые.
func recipe_unlocked(r: Dictionary) -> bool:
	return Tech.is_unlocked(String(r.get("tech", "T0")))


func find_recipe_for(item_id: int) -> Dictionary:
	for r in recipes:
		if int(r["out"]) == item_id:
			return r
	return {}


# ---------------------------------------------------------------- ТЕКСТУРЫ

func _build_atlas() -> void:
	var rows: int = int(ceil(float(IDs.TILE_COUNT) / float(ATLAS_COLS)))
	var img: Image = Image.create_empty(ATLAS_COLS * TILE_SIZE, rows * TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for id in range(IDs.TILE_COUNT):
		var ox: int = (id % ATLAS_COLS) * TILE_SIZE
		var oy: int = int(id / ATLAS_COLS) * TILE_SIZE
		atlas_of_tile[id] = Vector2i(id % ATLAS_COLS, int(id / ATLAS_COLS))
		_paint_tile(img, id, ox, oy)
	atlas_texture = ImageTexture.create_from_image(img)


func _build_glow() -> void:
	var s: int = 64
	var img2: Image = Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
	var c: float = float(s) * 0.5
	for y in s:
		for x in s:
			var d: float = Vector2(x + 0.5, y + 0.5).distance_to(Vector2(c, c)) / c
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			a = pow(a, 2.0)
			img2.set_pixel(x, y, Color(1.0, 0.92, 0.72, a))
	glow_texture = ImageTexture.create_from_image(img2)


func _paint_tile(img: Image, id: int, ox: int, oy: int) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 9871 + id * 7717
	match id:
		IDs.T.AIR:
			return
		IDs.T.GRASS:
			_paint_dirt(img, ox, oy, rng, Color(0.47, 0.33, 0.20))
			var green: Color = Color(0.29, 0.55, 0.24)
			for x in range(TILE_SIZE):
				var h: int = 4 + rng.randi_range(0, 2)
				for y in range(h):
					var col: Color = green.lightened(rng.randf_range(0.0, 0.14))
					img.set_pixel(ox + x, oy + y, col)
			return
		IDs.T.DIRT:
			_paint_dirt(img, ox, oy, rng, Color(0.47, 0.33, 0.20))
			return
		IDs.T.MOSS:
			_paint_stone(img, ox, oy, rng, Color(0.35, 0.33, 0.31))
			for i in 14:
				var px: int = rng.randi_range(0, TILE_SIZE - 1)
				var py: int = rng.randi_range(0, TILE_SIZE - 1)
				img.set_pixel(ox + px, oy + py, Color(0.30, 0.48, 0.25))
			return
		IDs.T.STONE:
			_paint_stone(img, ox, oy, rng, Color(0.42, 0.44, 0.48))
			return
		IDs.T.SANDSTONE:
			_paint_stone(img, ox, oy, rng, Color(0.76, 0.65, 0.42))
			for y in range(0, TILE_SIZE, 4):
				for x in range(TILE_SIZE):
					img.set_pixel(ox + x, oy + y, Color(0.68, 0.57, 0.35))
			return
		IDs.T.SAND:
			_paint_dirt(img, ox, oy, rng, Color(0.85, 0.76, 0.49))
			return
		IDs.T.LOG:
			for x in range(TILE_SIZE):
				var bark: Color = Color(0.42, 0.29, 0.17).lightened(rng.randf_range(-0.05, 0.05))
				for y in range(TILE_SIZE):
					if x % 5 == 0:
						bark = bark.darkened(0.18)
					img.set_pixel(ox + x, oy + y, bark)
			return
		IDs.T.TREE:
			# Тот же bark, что и у бревна: ствол дерева должен выглядеть как бревно.
			for x in range(TILE_SIZE):
				var bark2: Color = Color(0.42, 0.29, 0.17).lightened(rng.randf_range(-0.05, 0.05))
				for y in range(TILE_SIZE):
					if x % 5 == 0:
						bark2 = bark2.darkened(0.18)
					img.set_pixel(ox + x, oy + y, bark2)
			return
		IDs.T.LEAVES:
			for y in range(TILE_SIZE):
				for x in range(TILE_SIZE):
					if rng.randf() < 0.13:
						continue
					var g: Color = Color(0.24, 0.48, 0.21).lightened(rng.randf_range(0.0, 0.18))
					img.set_pixel(ox + x, oy + y, g)
			return
		IDs.T.COPPER_ORE:
			_paint_ore(img, ox, oy, rng, Color(0.80, 0.48, 0.25))
			return
		IDs.T.IRON_ORE:
			_paint_ore(img, ox, oy, rng, Color(0.85, 0.88, 0.93))
			return
		IDs.T.CRYSTAL_ORE:
			_paint_ore(img, ox, oy, rng, Color(0.72, 0.44, 0.99))
			return
		IDs.T.COAL_ORE:
			_paint_ore(img, ox, oy, rng, Color(0.14, 0.14, 0.17))
			return
		IDs.T.SCRAP_ORE:
			_paint_ore(img, ox, oy, rng, Color(0.60, 0.48, 0.29))
			return
		IDs.T.WATER:
			for y in range(TILE_SIZE):
				for x in range(TILE_SIZE):
					var w: Color = Color(0.16, 0.38, 0.72, 0.72).lightened(rng.randf_range(0.0, 0.08))
					img.set_pixel(ox + x, oy + y, w)
			return
		IDs.T.LAVA:
			for y in range(TILE_SIZE):
				for x in range(TILE_SIZE):
					var v: float = rng.randf()
					var lc: Color = Color(0.85, 0.28, 0.08) if v > 0.7 else Color(0.95, 0.52, 0.12)
					img.set_pixel(ox + x, oy + y, lc)
			return
		IDs.T.BEDROCK:
			for y in range(TILE_SIZE):
				for x in range(TILE_SIZE):
					var b: Color = Color(0.18, 0.19, 0.22).lightened(rng.randf_range(0.0, 0.12))
					img.set_pixel(ox + x, oy + y, b)
			return
		IDs.T.STEEL:
			_paint_stone(img, ox, oy, rng, Color(0.55, 0.58, 0.63))
			for x in range(TILE_SIZE):
				img.set_pixel(ox + x, oy + TILE_SIZE - 1, Color(0.35, 0.38, 0.42))
			return
		IDs.T.PANEL:
			for y in range(TILE_SIZE):
				for x in range(TILE_SIZE):
					var p: Color = Color(0.28, 0.31, 0.36)
					if (x / 4 + y / 4) % 2 == 0:
						p = p.lightened(0.05)
					img.set_pixel(ox + x, oy + y, p)
			for i in 4:
				img.set_pixel(ox + 3 + i * 3, oy + 3, Color(0.55, 0.58, 0.62))
			return
		IDs.T.TERMINAL:
			for y in range(TILE_SIZE):
				for x in range(TILE_SIZE):
					img.set_pixel(ox + x, oy + y, Color(0.20, 0.22, 0.26))
			for y in range(3, 13):
				for x in range(2, 14):
					img.set_pixel(ox + x, oy + y, Color(0.10, 0.45, 0.35))
			for i in 5:
				for x in range(3, 3 + i * 2):
					img.set_pixel(ox + x, oy + 5 + i * 2, Color(0.35, 0.95, 0.65))
			return
		IDs.T.GLASS:
			for y in range(TILE_SIZE):
				for x in range(TILE_SIZE):
					var gcol: Color = Color(0.62, 0.86, 0.92, 0.28)
					if x == 0 or y == 0 or x == TILE_SIZE - 1 or y == TILE_SIZE - 1:
						gcol = Color(0.75, 0.92, 0.96, 0.85)
					img.set_pixel(ox + x, oy + y, gcol)
			return
		IDs.T.COPPER_BLOCK:
			_paint_block(img, ox, oy, rng, Color(0.79, 0.46, 0.26))
			return
		IDs.T.IRON_BLOCK:
			_paint_block(img, ox, oy, rng, Color(0.84, 0.87, 0.91))
			return
		IDs.T.CRYSTAL_BLOCK:
			_paint_block(img, ox, oy, rng, Color(0.63, 0.36, 0.92))
			for i in 3:
				var sx: int = 3 + i * 4
				img.set_pixel(ox + sx, oy + 4 + i, Color(0.90, 0.72, 1.0))
			return
		IDs.T.LIGHT_CRYSTAL:
			for y in range(TILE_SIZE):
				for x in range(TILE_SIZE):
					var d: float = Vector2(x - 7.5, y - 7.5).length() / 8.0
					var c2: Color = Color(1.0, 0.88, 0.55).lerp(Color(1.0, 1.0, 0.90), 1.0 - clampf(d, 0.0, 1.0))
					img.set_pixel(ox + x, oy + y, c2)
			return
		IDs.T.RELAY_CORE:
			for y in range(TILE_SIZE):
				for x in range(TILE_SIZE):
					var rc: Color = Color(0.16, 0.18, 0.22)
					if x < 2 or y < 2 or x > 13 or y > 13:
						rc = Color(0.34, 0.38, 0.44)
					img.set_pixel(ox + x, oy + y, rc)
			for y in range(4, 12):
				for x in range(4, 12):
					img.set_pixel(ox + x, oy + y, Color(0.25, 0.85, 0.95))
			return
		IDs.T.STEEL_WALL:
			# Клёпаная стальная плита: шов посередине, заклёпки по углам.
			_paint_block(img, ox, oy, rng, Color(0.58, 0.62, 0.68))
			for p in [Vector2i(2, 2), Vector2i(13, 2), Vector2i(2, 13), Vector2i(13, 13)]:
				img.set_pixel(ox + p.x, oy + p.y, Color(0.82, 0.85, 0.90))
			for x in range(TILE_SIZE):
				img.set_pixel(ox + x, oy + 8, Color(0.42, 0.46, 0.52))
			return
		IDs.T.AIRLOCK:
			# Закрытая дверь: тёмная плита с жёлто-чёрной полосой посередине.
			_paint_block(img, ox, oy, rng, Color(0.30, 0.33, 0.38))
			for x in range(TILE_SIZE):
				var stripe: Color = Color(0.85, 0.70, 0.20) if int(x / 4) % 2 == 0 else Color(0.12, 0.12, 0.14)
				img.set_pixel(ox + x, oy + 7, stripe)
				img.set_pixel(ox + x, oy + 8, stripe)
			return
		IDs.T.AIRLOCK_OPEN:
			# Открытая дверь: только рама, середина прозрачна.
			for y in range(TILE_SIZE):
				for x in range(TILE_SIZE):
					if x < 2 or x > 13 or y < 2 or y > 13:
						img.set_pixel(ox + x, oy + y, Color(0.30, 0.33, 0.38))
			for x in range(2, 14):
				img.set_pixel(ox + x, oy + 1, Color(0.85, 0.70, 0.20))
			return
		IDs.T.VENT_GRATE:
			# Решётка: горизонтальные планки, между ними темнота шахты.
			for y in range(TILE_SIZE):
				for x in range(TILE_SIZE):
					var slat: bool = y % 4 < 2
					img.set_pixel(ox + x, oy + y, Color(0.50, 0.55, 0.60) if slat else Color(0.06, 0.07, 0.09, 0.85))
			return
	return


func _paint_stone(img: Image, ox: int, oy: int, rng: RandomNumberGenerator, base: Color) -> void:
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var c: Color = base.lightened(rng.randf_range(-0.06, 0.06))
			img.set_pixel(ox + x, oy + y, c)
	# тёмная кромка снизу — «кладка» породы
	for x in range(TILE_SIZE):
		img.set_pixel(ox + x, oy + TILE_SIZE - 1, base.darkened(0.20))
	# трещины
	for i in rng.randi_range(1, 3):
		var cx: int = rng.randi_range(1, TILE_SIZE - 2)
		var cy: int = rng.randi_range(1, TILE_SIZE - 4)
		var ln: int = rng.randi_range(2, 5)
		for k in ln:
			var px: int = clampi(cx + int(k / 2), 0, TILE_SIZE - 1)
			var py: int = clampi(cy + k, 0, TILE_SIZE - 1)
			img.set_pixel(ox + px, oy + py, base.darkened(0.24))
	# светлые вкрапления
	for i in rng.randi_range(2, 5):
		img.set_pixel(ox + rng.randi_range(0, TILE_SIZE - 1), oy + rng.randi_range(0, TILE_SIZE - 1),
				base.lightened(0.16))


func _paint_dirt(img: Image, ox: int, oy: int, rng: RandomNumberGenerator, base: Color) -> void:
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var c: Color = base.lightened(rng.randf_range(-0.08, 0.08))
			img.set_pixel(ox + x, oy + y, c)
	# камешки и корни
	for i in rng.randi_range(2, 4):
		var px: int = rng.randi_range(1, TILE_SIZE - 2)
		var py: int = rng.randi_range(1, TILE_SIZE - 2)
		img.set_pixel(ox + px, oy + py, base.lightened(0.16))
		img.set_pixel(ox + px + 1, oy + py, base.darkened(0.18))
	for i in rng.randi_range(1, 2):
		var rx: int = rng.randi_range(0, TILE_SIZE - 2)
		var ry: int = rng.randi_range(0, TILE_SIZE - 3)
		for k in rng.randi_range(3, 6):
			img.set_pixel(ox + clampi(rx + k, 0, TILE_SIZE - 1), oy + clampi(ry + int(k / 3), 0, TILE_SIZE - 1),
					base.darkened(0.22))


func _paint_block(img: Image, ox: int, oy: int, rng: RandomNumberGenerator, base: Color) -> void:
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var c: Color = base.lightened(rng.randf_range(-0.05, 0.05))
			if x == 0 or y == 0:
				c = c.lightened(0.18)
			if x == TILE_SIZE - 1 or y == TILE_SIZE - 1:
				c = c.darkened(0.20)
			img.set_pixel(ox + x, oy + y, c)


func _paint_ore(img: Image, ox: int, oy: int, rng: RandomNumberGenerator, ore: Color) -> void:
	_paint_stone(img, ox, oy, rng, Color(0.40, 0.42, 0.46))
	var blobs: int = rng.randi_range(3, 5)
	for i in blobs:
		var cx: int = rng.randi_range(2, TILE_SIZE - 3)
		var cy: int = rng.randi_range(2, TILE_SIZE - 3)
		var r: int = rng.randi_range(1, 2)
		for y in range(cy - r, cy + r + 1):
			for x in range(cx - r, cx + r + 1):
				if x < 0 or y < 0 or x >= TILE_SIZE or y >= TILE_SIZE:
					continue
				var c: Color = ore.lightened(rng.randf_range(-0.05, 0.12))
				img.set_pixel(ox + x, oy + y, c)


# ------------------------------------------------------- ТЕКСТУРЫ ПРЕДМЕТОВ

func item_texture(id: int) -> ImageTexture:
	if item_textures.has(id):
		return item_textures[id]
	var def: Dictionary = item_def(id)
	var img: Image = Image.create_empty(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 4242 + id * 131
	var col: Color = def.get("color", Color.MAGENTA)
	_paint_item(img, String(def.get("shape", "lump")), col, rng)
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	item_textures[id] = tex
	return tex


func _paint_item(img: Image, shape: String, c: Color, rng: RandomNumberGenerator) -> void:
	match shape:
		"ore":
			_paint_item(img, "block", Color(0.40, 0.42, 0.46), rng)
			for i in 4:
				var cx: int = rng.randi_range(2, 13)
				var cy: int = rng.randi_range(2, 13)
				_px(img, cx, cy, c)
				_px(img, cx + 1, cy, c.lightened(0.2))
				_px(img, cx, cy + 1, c.darkened(0.2))
		"block":
			for y in range(TILE_SIZE):
				for x in range(TILE_SIZE):
					var cc: Color = c.lightened(rng.randf_range(-0.06, 0.06))
					if x == 0 or y == 0:
						cc = cc.lightened(0.2)
					if x == TILE_SIZE - 1 or y == TILE_SIZE - 1:
						cc = cc.darkened(0.22)
					_px(img, x, y, cc)
		"ingot":
			for y in range(4, 12):
				var w: int = 10 - int(abs(y - 8)) * 0
				var half: int = 5 - int(abs(y - 8))
				for x in range(8 - half, 8 + half):
					_px(img, x, y, c.lightened(0.15 if y < 6 else 0.0))
		"plate":
			for y in range(5, 11):
				for x in range(3, 13):
					_px(img, x, y, c.lightened(0.22 if y == 5 else 0.0))
		"shard":
			for y in range(3, 14):
				var half: int = int((y - 2) * 0.8)
				for x in range(8 - half, 8 + half):
					_px(img, x, y, c.lightened(0.25 if x > 8 else 0.0))
			_px(img, 8, 2, c.lightened(0.5))
		"lump":
			for y in range(TILE_SIZE):
				for x in range(TILE_SIZE):
					var d: float = Vector2(x - 7.5, y - 8.0).length()
					if d < 5.2 + rng.randf_range(-0.6, 0.6):
						_px(img, x, y, c.lightened(rng.randf_range(-0.08, 0.12)))
		"pile":
			for y in range(6, 15):
				var half: int = 6 - int((y - 6) * 0.5)
				for x in range(8 - half, 8 + half):
					_px(img, x, y, c.lightened(rng.randf_range(-0.05, 0.08)))
		"log":
			for y in range(TILE_SIZE):
				for x in range(TILE_SIZE):
					_px(img, x, y, c.lightened(rng.randf_range(-0.05, 0.05)))
			for x in range(3, 13):
				_px(img, x, 3, c.lightened(0.2))
				_px(img, x, 12, c.darkened(0.25))
		"glass":
			for y in range(TILE_SIZE):
				for x in range(TILE_SIZE):
					var g: Color = c
					g.a = 0.4
					if x == 0 or y == 0 or x == TILE_SIZE - 1 or y == TILE_SIZE - 1:
						g.a = 0.95
					_px(img, x, y, g)
		"circuit":
			for y in range(3, 13):
				for x in range(3, 13):
					_px(img, x, y, c.darkened(0.3))
			for i in 3:
				for x in range(4, 12):
					_px(img, x, 4 + i * 3, c)
			_px(img, 6, 6, Color(0.15, 0.15, 0.18))
			_px(img, 9, 9, Color(0.15, 0.15, 0.18))
		"cell":
			for y in range(4, 13):
				for x in range(5, 11):
					_px(img, x, y, c)
			_px(img, 7, 2, c)
			_px(img, 8, 2, c)
			_px(img, 7, 13, c.lightened(0.4))
		"drill":
			for y in range(3, 9):
				for x in range(3, 13):
					_px(img, x, y, Color(0.55, 0.58, 0.63))
			for y in range(9, 15):
				var half: int = int((y - 8) * 0.9)
				for x in range(8 - half, 8 + half):
					_px(img, x, y, Color(0.75, 0.78, 0.82))
		"smelter":
			for y in range(2, 14):
				for x in range(2, 14):
					_px(img, x, y, Color(0.72, 0.42, 0.28).darkened(0.1))
			for y in range(8, 13):
				for x in range(5, 11):
					_px(img, x, y, Color(0.95, 0.55, 0.15))
		"assembler":
			for y in range(3, 13):
				for x in range(3, 13):
					_px(img, x, y, Color(0.45, 0.62, 0.78))
			for i in 5:
				_px(img, 5 + i, 8, Color(0.9, 0.95, 1.0))
				_px(img, 8, 5 + i, Color(0.9, 0.95, 1.0))
		"belt":
			for y in range(4, 12):
				for x in range(1, 15):
					_px(img, x, y, Color(0.30, 0.30, 0.33))
			for i in 3:
				_px(img, 3 + i * 4, 6, c)
				_px(img, 3 + i * 4, 7, c)
				_px(img, 3 + i * 4, 8, c)
		"chest":
			for y in range(4, 13):
				for x in range(2, 14):
					_px(img, x, y, c)
			for x in range(2, 14):
				_px(img, x, 8, c.darkened(0.3))
			_px(img, 7, 8, Color(0.85, 0.75, 0.35))
		"gen":
			for y in range(3, 13):
				for x in range(3, 13):
					_px(img, x, y, c)
			for i in 4:
				_px(img, 8, 4 + i, Color(1.0, 0.9, 0.4))
				_px(img, 9 - i, 4 + i, Color(1.0, 0.9, 0.4))
				_px(img, 8 + i, 4 + i, Color(1.0, 0.9, 0.4))
		"solar":
			for y in range(3, 12):
				for x in range(2, 14):
					_px(img, x, y, Color(0.20, 0.32, 0.60))
			for x in range(6, 10):
				_px(img, x, 2, Color(0.8, 0.85, 0.9))
			for x in range(7, 9):
				_px(img, x, 12, Color(0.8, 0.85, 0.9))
		"lamp":
			for y in range(3, 11):
				for x in range(4, 12):
					_px(img, x, y, c)
			for x in range(4, 12):
				_px(img, x, 11, c.darkened(0.4))
		# --- ADR-001 (#24): иконки новых предметов ---
		"inserter":
			# Стойка и рука с захватом.
			for y in range(9, 14):
				for x in range(5, 11):
					_px(img, x, y, Color(0.35, 0.37, 0.42))
			for i in 6:
				_px(img, 7 + i, 8 - i, c)
				_px(img, 8 + i, 8 - i, c.darkened(0.2))
			_px(img, 13, 2, c.lightened(0.3))
			_px(img, 12, 3, c.lightened(0.3))
		"analyzer":
			for y in range(3, 13):
				for x in range(3, 13):
					_px(img, x, y, c.darkened(0.35))
			for y in range(5, 11):
				for x in range(5, 11):
					_px(img, x, y, c)
			_px(img, 8, 8, Color(1.0, 1.0, 1.0, 0.9))
		"turret":
			for y in range(9, 14):
				for x in range(3, 13):
					_px(img, x, y, c.darkened(0.3))
			for y in range(5, 9):
				for x in range(5, 11):
					_px(img, x, y, c)
			for x in range(9, 15):
				_px(img, x, 6, c.lightened(0.3))
			_px(img, 14, 5, Color(0.5, 0.9, 1.0))
		"floodlight":
			for y in range(8, 14):
				_px(img, 7, y, Color(0.40, 0.42, 0.48))
				_px(img, 8, y, Color(0.40, 0.42, 0.48))
			for y in range(2, 8):
				for x in range(3, 13):
					_px(img, x, y, c if y > 3 else c.lightened(0.3))
		"wall":
			_paint_item(img, "block", c, rng)
			for p in [Vector2i(2, 2), Vector2i(13, 2), Vector2i(2, 13), Vector2i(13, 13)]:
				_px(img, p.x, p.y, c.lightened(0.4))
			for x in range(TILE_SIZE):
				_px(img, x, 8, c.darkened(0.3))
		"airlock":
			_paint_item(img, "block", Color(0.30, 0.33, 0.38), rng)
			for x in range(TILE_SIZE):
				var stripe: Color = c if int(x / 4) % 2 == 0 else Color(0.12, 0.12, 0.14)
				_px(img, x, 7, stripe)
				_px(img, x, 8, stripe)
		"grate":
			for y in range(2, 14):
				for x in range(2, 14):
					_px(img, x, y, c if y % 4 < 2 else Color(0.06, 0.07, 0.09))
		"deep_drill":
			_paint_item(img, "drill", c, rng)
			for y in range(3, 9):
				for x in range(3, 13):
					_px(img, x, y, c)
			_px(img, 5, 5, Color(0.4, 1.0, 0.5))
		"antenna":
			for y in range(6, 15):
				_px(img, 7, y, Color(0.55, 0.58, 0.63))
				_px(img, 8, y, Color(0.55, 0.58, 0.63))
			for i in 4:
				_px(img, 4 + i, 6 - i, c)
				_px(img, 11 - i, 6 - i, c)
			_px(img, 7, 2, c.lightened(0.4))
			_px(img, 8, 2, c.lightened(0.4))
		"blackbox":
			for y in range(5, 12):
				for x in range(3, 13):
					_px(img, x, y, c)
			for x in range(3, 13):
				_px(img, x, 5, c.lightened(0.25))
			_px(img, 11, 7, Color(0.3, 1.0, 0.4))
		"bag":
			for y in range(5, 14):
				var half: int = 5 - int(absf(float(y) - 10.0) * 0.5)
				for x in range(8 - half, 8 + half):
					_px(img, x, y, c.lightened(rng.randf_range(-0.05, 0.08)))
			for x in range(6, 10):
				_px(img, x, 4, c.darkened(0.3))


func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	img.set_pixel(x, y, c)
