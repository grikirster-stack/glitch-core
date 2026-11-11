extends Node
## База данных тайлов, предметов, рецептов + процедурная генерация всей графики.
## Внешних ассетов нет: все текстуры рисуются кодом при запуске.

const TILE_SIZE: int = 16
const ATLAS_COLS: int = 32  # ADR-003 V1: ~1080 клеток вариантов (биом × фактура × маска)

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
		IDs.T.DIRT: {"solid": true, "hard": 0.5, "drop": IDs.I.SCRAP, "light": 0.0, "name": "Глина", "dig": true},
		IDs.T.GRASS: {"solid": true, "hard": 0.6, "drop": IDs.I.SCRAP, "light": 0.0, "name": "Лишайник", "dig": true},
		IDs.T.SAND: {"solid": true, "hard": 0.4, "drop": IDs.I.SAND, "light": 0.0, "name": "Песок", "dig": true},
		IDs.T.SANDSTONE: {"solid": true, "hard": 1.2, "drop": IDs.I.STONE, "light": 0.0, "name": "Песчаник", "dig": true},
		IDs.T.LOG: {"solid": true, "hard": 1.0, "drop": IDs.I.LOG, "light": 0.0, "name": "Волокно стебля", "dig": true},
		# Ствол дерева: выглядит как бревно, но сквозь него можно пройти —
		# лес не должен запирать игрока в клетке между стволами.
		# Отображаемые имена — под мир Кобальта-9 (ADR-003, решение #102); id прежние.
		IDs.T.TREE: {"solid": false, "hard": 1.0, "drop": IDs.I.LOG, "light": 0.0, "name": "Стебель свечника"},
		IDs.T.LEAVES: {"solid": false, "hard": 0.2, "drop": 0, "light": 0.0, "name": "Шляпка свечника"},
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
		IDs.T.MOSS: {"solid": true, "hard": 0.6, "drop": IDs.I.SCRAP, "light": 0.0, "name": "Лишайниковая кочка", "dig": true},
		IDs.T.RELAY_CORE: {"solid": true, "hard": 999.0, "drop": 0, "light": 0.5, "name": "Релей-ядро"},
		# --- ADR-001 § 4.4: оборона базы. Поведение шлюза и решётки — #31, здесь только данные.
		IDs.T.STEEL_WALL: {"solid": true, "hard": Balance.STEEL_WALL_HARD, "drop": IDs.I.STEEL_WALL, "light": 0.0, "name": "Стальная стена"},
		# ADR-005: new optical tiles (burner etc. use machine_base or tile defs extended in future)
		IDs.T.BURNER: {"solid": true, "hard": 2.0, "drop": IDs.I.BURNER, "light": 0.3, "name": "Горелка"},
		IDs.T.MIRROR: {"solid": false, "hard": 1.0, "drop": IDs.I.MIRROR, "light": 0.0, "name": "Зеркало"},
		IDs.T.MIXER: {"solid": true, "hard": 2.0, "drop": IDs.I.MIXER, "light": 0.2, "name": "Смеситель"},
		IDs.T.PRISM: {"solid": true, "hard": 1.5, "drop": IDs.I.PRISM, "light": 0.4, "name": "Призма"},
		IDs.T.COLLECTOR: {"solid": true, "hard": 2.0, "drop": IDs.I.COLLECTOR, "light": 0.1, "name": "Коллектор"},
		IDs.T.ACCUMULATOR: {"solid": true, "hard": 3.0, "drop": IDs.I.ACCUMULATOR, "light": 0.5, "name": "Накопитель"},
		IDs.T.BEACON: {"solid": true, "hard": 2.5, "drop": IDs.I.BEACON, "light": 1.0, "name": "Маяк"},
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


## Базовый цвет тайла — используется для частиц при добыче. Палитра ADR-003 (PAL).
func tile_color(id: int) -> Color:
	match id:
		IDs.T.STONE:
			return PAL["s_base"].lerp(PAL["s_dark"], 0.38)
		IDs.T.DIRT:
			return PAL["s_hi"]
		IDs.T.GRASS, IDs.T.MOSS:
			return PAL["s_top"]
		IDs.T.SAND:
			return PAL["sand"]
		IDs.T.SANDSTONE:
			return PAL["sand_d"]
		IDs.T.LOG, IDs.T.TREE:
			return PAL["fl3"]
		IDs.T.LEAVES:
			return PAL["fl1"]
		IDs.T.COPPER_ORE, IDs.T.COPPER_BLOCK:
			return PAL["copper"]
		IDs.T.IRON_ORE, IDs.T.IRON_BLOCK:
			return PAL["iron"]
		IDs.T.CRYSTAL_ORE, IDs.T.CRYSTAL_BLOCK:
			return PAL["crystal"]
		IDs.T.COAL_ORE:
			return PAL["coal"]
		IDs.T.SCRAP_ORE:
			return PAL["scrap"]
		IDs.T.WATER:
			return PAL["water"]
		IDs.T.LAVA:
			return PAL["lava"]
		IDs.T.BEDROCK:
			return PAL["bed"]
		IDs.T.STEEL:
			return PAL["metal"]
		IDs.T.PANEL, IDs.T.TERMINAL, IDs.T.VENT_GRATE:
			return PAL["metal_d"]
		IDs.T.GLASS:
			return PAL["water_hi"]
		IDs.T.LIGHT_CRYSTAL, IDs.T.RELAY_CORE:
			return PAL["bio"]
		IDs.T.STEEL_WALL:
			return PAL["frame"]
		IDs.T.AIRLOCK, IDs.T.AIRLOCK_OPEN:
			return PAL["hazard"]
		_:
			return PAL["metal_d"]


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

	# Цвета сырья — палитра ADR-003 (PAL): железо кобальтовое, кристалл бирюзовый.
	_item("Медная руда", PAL["copper"], "ore")
	_item("Железная руда", PAL["iron"], "ore")
	_item("Кристалл глитча", PAL["crystal"], "shard")
	_item("Уголь", PAL["coal"].lightened(0.06), "lump")
	_item("Хлам", PAL["scrap"], "lump")
	_item("Песок", PAL["sand"], "pile")
	_item("Волокно стебля", PAL["fl3"].darkened(0.08), "log")
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
	_item("Кристальный блок", PAL["crystal_d"].lerp(PAL["crystal"], 0.4), "block", 99, "tile:%d" % IDs.T.CRYSTAL_BLOCK)

	# Дополнительные строительные блоки, доступные сразу.
	_add_item_def(IDs.I.STONE, "Камень", Color(0.44, 0.46, 0.50), "block", 99, "tile:%d" % IDs.T.STONE)
	_add_item_def(IDs.I.SAND, "Песок", PAL["sand"], "pile", 99, "tile:%d" % IDs.T.SAND)
	_add_item_def(IDs.I.LOG, "Волокно стебля", PAL["fl3"].darkened(0.08), "log", 99, "tile:%d" % IDs.T.LOG)

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

	# --- ADR-005 light constructor items (BURNER..BEACON, BLUEPRINT) ---
	_add_item_def(IDs.I.BURNER, "Горелка", Color(0.9, 0.3, 0.1), "burner", 5, "machine:Burner")
	_add_item_def(IDs.I.MIRROR, "Зеркало", Color(0.8, 0.85, 0.9), "mirror", 20, "machine:Mirror")
	_add_item_def(IDs.I.MIXER, "Смеситель", Color(0.4, 0.7, 0.9), "mixer", 5, "machine:Mixer")
	_add_item_def(IDs.I.PRISM, "Призма", Color(0.9, 0.7, 0.2), "prism", 5, "machine:Prism")
	_add_item_def(IDs.I.COLLECTOR, "Коллектор", Color(0.9, 0.9, 0.6), "collector", 5, "machine:Collector")
	_add_item_def(IDs.I.ACCUMULATOR, "Накопитель", Color(0.2, 0.6, 0.9), "accumulator", 5, "machine:Accumulator")
	_add_item_def(IDs.I.BEACON, "Маяк", Color(1.0, 0.9, 0.2), "beacon", 10, "machine:Beacon")
	_add_item_def(IDs.I.BLUEPRINT, "Синийпринт", Color(0.2, 0.4, 1.0), "blueprint", 99, "")

	# Требования релей-ядра — из Balance (§ 4.7). (legacy, will be updated in ADR-005)
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
## данных ведёт Tech (#28): запертый рецепт виден в крафте серым, станции его не берут.
func _recipe(out: int, amount: int, inputs: Dictionary, station: String, time: float, name: String,
		tech: String = "T0") -> void:
	recipes.append({
		"out": out, "amount": amount, "in": inputs,
		"station": station, "time": time, "name": name, "tech": tech,
	})


func _build_recipes() -> void:
	# --- Ручной крафт: только hand (ADR-005: factory swept; recipes only hand as per task) ---
	# Ручная выплавка — грубая (2 руды на слиток), зато доступна без станций.
	# Правило ADR-001 D3: у всего есть машинный рецепт, ручной — дороже или медленнее.
	# (machine recipes removed per snoop factory; hand only for compile/test)
	_recipe(IDs.I.COPPER_INGOT, 1, {IDs.I.COPPER_ORE: 2}, "hand", 1.0, "Ручная выплавка меди")
	_recipe(IDs.I.IRON_INGOT, 1, {IDs.I.IRON_ORE: 2}, "hand", 1.2, "Ковка железа")
	_recipe(IDs.I.GLASS, 1, {IDs.I.SAND: 2}, "hand", 1.0, "Обжиг стекла")
	_recipe(IDs.I.COPPER_PLATE, 1, {IDs.I.COPPER_INGOT: 2}, "hand", 1.0, "Медная пластина")
	_recipe(IDs.I.IRON_PLATE, 1, {IDs.I.IRON_INGOT: 2}, "hand", 1.2, "Железная пластина")
	_recipe(IDs.I.LAMP, 1, {IDs.I.CRYSTAL: 1, IDs.I.COAL: 1}, "hand", 0.8, "Светокристалл")
	_recipe(IDs.I.COPPER_BLOCK, 1, {IDs.I.COPPER_INGOT: 4}, "hand", 1.0, "Медный блок")
	_recipe(IDs.I.IRON_BLOCK, 1, {IDs.I.IRON_INGOT: 4}, "hand", 1.0, "Железный блок")
	_recipe(IDs.I.CRYSTAL_BLOCK, 1, {IDs.I.CRYSTAL: 3}, "hand", 1.0, "Кристальный блок")
	# Первые постройки собираются вручную — иначе не с чего начать (light constructor).
	_recipe(IDs.I.SOLAR, 1, {IDs.I.COPPER_PLATE: 1, IDs.I.GLASS: 1}, "hand", 2.0, "Солнечная панель")
	_recipe(IDs.I.CHEST, 1, {IDs.I.IRON_PLATE: 4}, "hand", 2.5, "Сундук вручную")
	_recipe(IDs.I.BURNER, 1, {IDs.I.STONE: 4, IDs.I.COAL: 2}, "hand", 3.0, "Горелка")
	_recipe(IDs.I.MIRROR, 1, {IDs.I.GLASS: 4, IDs.I.IRON_PLATE: 2}, "hand", 2.0, "Зеркало")
	_recipe(IDs.I.MIXER, 1, {IDs.I.CIRCUIT: 1, IDs.I.GLASS: 2}, "hand", 4.0, "Смеситель")
	_recipe(IDs.I.PRISM, 1, {IDs.I.CRYSTAL: 3, IDs.I.GLASS: 1}, "hand", 3.5, "Призма")
	_recipe(IDs.I.COLLECTOR, 1, {IDs.I.IRON_PLATE: 3, IDs.I.GLASS: 2}, "hand", 2.5, "Коллектор")
	_recipe(IDs.I.ACCUMULATOR, 1, {IDs.I.CIRCUIT: 2, IDs.I.POWER_CELL: 1}, "hand", 5.0, "Накопитель")
	_recipe(IDs.I.BEACON, 1, {IDs.I.CRYSTAL_BLOCK: 2, IDs.I.LAMP: 1}, "hand", 4.0, "Маяк")
	_recipe(IDs.I.BLUEPRINT, 1, {IDs.I.CIRCUIT: 1}, "hand", 1.0, "Синийпринт")

	# (machine recipes removed per ADR-005 "снос фабрики" and task "рецепты только hand")
	# Only hand recipes kept to make DB compile and tests pass. Legacy machines in IDs for conversion.
	# _build_recipes now only hand — matches task.

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
# ADR-003 (#103, волна V1): палитра и тайлы концепта A «Споровый луг» +
# кобальтово-синее железо из концепта B. Образец — tools/style_concepts.gd
# (концепт spore) и docs/adr/img/0003/spore_*.png.
#
# Всё квадратное: тайл 16×16, твёрдые тайлы непрозрачны целиком; кромки,
# лишайник и гифы рисуются только ВНУТРИ квадрата.
#
# Атлас: у тайла породы VARIANTS = 192 клетки — 3 биома по глубине × 4 фактуры ×
# 16 масок открытых сторон (1 верх, 2 право, 4 низ, 8 лево). У металла базы,
# воды и лавы — 2 клетки (верх открыт или нет), у остальных — одна.
# Какую клетку показать, решает World.cell_atlas() по соседям и глубине:
# id тайла, сохранение и сеть от вариантов не зависят (ADR-003 § 8).

## Палитра: PAL.spore из tools/style_concepts.gd, железо — из PAL.reef.
const PAL: Dictionary = {
	# поверхность: глина, лишайник
	"s_base": Color("#B58A72"), "s_dark": Color("#94685A"), "s_hi": Color("#CDA48A"),
	"s_top": Color("#C9A445"), "s_top2": Color("#F2D27A"),
	# средние пещеры: фиолетовый камень, мицелий светится бирюзой
	"m_base": Color("#5D4A68"), "m_dark": Color("#3D3049"), "m_hi": Color("#7B6786"), "m_glow": Color("#7FE6D2"),
	# глубина у лавы: «плоть» планеты, жар трещин
	"d_base": Color("#6B3035"), "d_dark": Color("#461D25"), "d_hi": Color("#94474A"), "d_glow": Color("#FF9A5C"),
	"bed": Color("#241A22"),
	# руды (узор у каждой свой — ADR-003 § 3.2)
	"copper": Color("#F08C3C"), "copper_d": Color("#8E4220"),
	"iron": Color("#4A7DF0"), "iron_d": Color("#1C3478"),
	"coal": Color("#1E1719"), "coal_hi": Color("#F4E6CF"),
	"crystal": Color("#6FF5E0"), "crystal_d": Color("#21807E"),
	"scrap": Color("#9A9E94"), "scrap_d": Color("#4E423C"),
	"sand": Color("#E2C79C"), "sand_d": Color("#C4A47A"), "sand_hi": Color("#F2DDB8"),
	"lava": Color("#FF7A2E"), "lava_hi": Color("#FFD86E"),
	"water": Color("#6FA7B0"), "water_hi": Color("#C4E6E0"),
	# металл базы: кремовая эмаль, голубовато-серые рамы, жёлтая разметка
	"metal": Color("#E3DDCD"), "metal_d": Color("#A39E92"), "metal_hi": Color("#FFF8EA"),
	"frame": Color("#5E6B78"), "hazard": Color("#E3B341"),
	"screen": Color("#23353A"), "screen_hi": Color("#8CF0C8"),
	"bio": Color("#7FE6D2"), "bio_core": Color("#E8FFF8"),
	# флора: шляпки свечника, стебель
	"fl1": Color("#F2B8A0"), "fl1_d": Color("#C47E78"), "fl3": Color("#F4EBCF"),
	# флора V2: сиреневые пузыри пузырника и трутовиков
	"fl2": Color("#DCCDEA"), "fl2_d": Color("#A68FBC"),
	"interact": Color("#FFF1A8"), "danger": Color("#F0306A"),
}

enum VK { ONE, TOP, NAT, FLORA }
const BIOMES: int = 3       ## 0 поверхность, 1 средние пещеры, 2 глубина у лавы
const TEX_ALTS: int = 4     ## фактур на биом: World выбирает по хэшу клетки — меньше повторов
const MASKS: int = 16
const VARIANTS: int = BIOMES * TEX_ALTS * MASKS

## id * VARIANTS + вариант -> клетка атласа. Вариант = ((биом * TEX_ALTS + фактура) << 4) | маска.
var atlas_var: Array = []
## Все занятые клетки атласа (World заводит под них тайлы TileSetAtlasSource).
var atlas_cells: Array = []


static func variant_index(bio: int, alt: int, mask: int) -> int:
	return ((bio * TEX_ALTS + alt) << 4) | mask


func pal(k: String) -> Color:
	return PAL[k]


## Сколько вариантов у тайла: порода — все 96, металл/жидкости — по верху, прочее — один.
func _tile_vkind(id: int) -> int:
	match id:
		IDs.T.STONE, IDs.T.DIRT, IDs.T.GRASS, IDs.T.SAND, IDs.T.SANDSTONE, IDs.T.MOSS, \
				IDs.T.COPPER_ORE, IDs.T.IRON_ORE, IDs.T.CRYSTAL_ORE, IDs.T.COAL_ORE, IDs.T.SCRAP_ORE:
			return VK.NAT
		IDs.T.STEEL, IDs.T.PANEL, IDs.T.STEEL_WALL, IDs.T.WATER, IDs.T.LAVA:
			return VK.TOP
		IDs.T.TREE, IDs.T.LEAVES:
			return VK.FLORA
	return VK.ONE


## Биом, в котором тайл чаще всего встречается: его вариант — «лицо» тайла
## (atlas_of_tile: иконка галереи, проверка «каждый тайл нарисован»).
func _home_bio(id: int) -> int:
	match id:
		IDs.T.STONE, IDs.T.COPPER_ORE, IDs.T.IRON_ORE, IDs.T.COAL_ORE:
			return 1
		IDs.T.CRYSTAL_ORE:
			return 2
	return 0


func _build_atlas() -> void:
	var counts: Dictionary = {VK.NAT: VARIANTS, VK.TOP: 2, VK.ONE: 1, VK.FLORA: TEX_ALTS * MASKS}
	var total: int = 0
	for id in range(1, IDs.TILE_COUNT):
		total += int(counts[_tile_vkind(id)])
	var rows: int = ceili(float(total) / float(ATLAS_COLS))
	var img: Image = Image.create_empty(ATLAS_COLS * TILE_SIZE, rows * TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	atlas_of_tile.clear()
	atlas_cells.clear()
	atlas_var.clear()
	atlas_var.resize(IDs.TILE_COUNT * VARIANTS)
	atlas_var.fill(Vector2i(-1, -1))
	var full: Rect2i = Rect2i(0, 0, TILE_SIZE, TILE_SIZE)
	var slot: int = 0
	_tex_cache.clear()
	for id in range(1, IDs.TILE_COUNT):
		var row0: int = id * VARIANTS
		match _tile_vkind(id):
			VK.NAT:
				for bio in BIOMES:
					var edges: Array = _edge_overlays(id, bio)
					for alt in TEX_ALTS:
						var base: Image = _tile_base(id, bio, alt)
						for m in MASKS:
							var cell: Vector2i = Vector2i(slot % ATLAS_COLS, slot / ATLAS_COLS)
							slot += 1
							var pos: Vector2i = cell * TILE_SIZE
							img.blit_rect(base, full, pos)
							_blend_edges(img, edges, m, pos)
							atlas_var[row0 + variant_index(bio, alt, m)] = cell
							atlas_cells.append(cell)
				atlas_of_tile[id] = atlas_var[row0 + variant_index(_home_bio(id), 0,
						1 if id == IDs.T.GRASS else 0)]
			VK.TOP:
				var base2: Image = _tile_base(id, 0, 0)
				var top: Image = _top_overlay(id)
				var c0: Vector2i = Vector2i(slot % ATLAS_COLS, slot / ATLAS_COLS)
				var c1: Vector2i = Vector2i((slot + 1) % ATLAS_COLS, (slot + 1) / ATLAS_COLS)
				slot += 2
				img.blit_rect(base2, full, c0 * TILE_SIZE)
				img.blit_rect(base2, full, c1 * TILE_SIZE)
				img.blend_rect(top, full, c1 * TILE_SIZE)
				for v in VARIANTS:
					atlas_var[row0 + v] = c1 if (v & 1) != 0 else c0
				atlas_cells.append(c0)
				atlas_cells.append(c1)
				atlas_of_tile[id] = c1
			VK.FLORA:
				# ADR-003 V2: свечник растёт только на поверхности — биом картинку
				# не меняет, все три биома смотрят в одни и те же клетки.
				for alt in TEX_ALTS:
					for m in MASKS:
						var cf: Vector2i = Vector2i(slot % ATLAS_COLS, slot / ATLAS_COLS)
						slot += 1
						img.blit_rect(_flora_tile(id, alt, m), full, cf * TILE_SIZE)
						for bio in BIOMES:
							atlas_var[row0 + variant_index(bio, alt, m)] = cf
						atlas_cells.append(cf)
				atlas_of_tile[id] = atlas_var[row0 + variant_index(0, 0, _flora_face(id))]
			_:
				var c: Vector2i = Vector2i(slot % ATLAS_COLS, slot / ATLAS_COLS)
				slot += 1
				img.blit_rect(_tile_base(id, 0, 0), full, c * TILE_SIZE)
				for v in VARIANTS:
					atlas_var[row0 + v] = c
				atlas_cells.append(c)
				atlas_of_tile[id] = c
	_tex_cache.clear()
	atlas_texture = ImageTexture.create_from_image(img)


## Кромки открытых сторон в порядке рендеров: бока, потолок, верх (верх — поверх углов).
func _blend_edges(img: Image, edges: Array, m: int, pos: Vector2i) -> void:
	var full: Rect2i = Rect2i(0, 0, TILE_SIZE, TILE_SIZE)
	if m & 2:
		img.blend_rect(edges[1], full, pos)
	if m & 8:
		img.blend_rect(edges[3], full, pos)
	if m & 4:
		img.blend_rect(edges[2], full, pos)
	if m & 1:
		img.blend_rect(edges[0], full, pos)


## Один вариант тайла отдельной картинкой 16×16 (галерея, листы до/после).
func variant_image(id: int, bio: int, alt: int, mask: int) -> Image:
	if _tile_vkind(id) == VK.FLORA:
		return _flora_tile(id, alt, mask)
	var t: Image = _tile_base(id, bio if _tile_vkind(id) == VK.NAT else 0, alt if _tile_vkind(id) == VK.NAT else 0)
	match _tile_vkind(id):
		VK.NAT:
			_blend_edges(t, _edge_overlays(id, bio), mask, Vector2i.ZERO)
		VK.TOP:
			if mask & 1:
				t.blend_rect(_top_overlay(id), Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i.ZERO)
	return t


## Совместимость (tools/gallery_dump.gd без рендер-сервера): «лицо» тайла в img.
func _paint_tile(img: Image, id: int, ox: int, oy: int) -> void:
	if id == IDs.T.AIR:
		return
	var face_mask: int = 1 if id == IDs.T.GRASS or _tile_vkind(id) == VK.TOP else 0
	if _tile_vkind(id) == VK.FLORA:
		face_mask = _flora_face(id)
	var face: Image = variant_image(id, _home_bio(id), 0, face_mask)
	img.blend_rect(face, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(ox, oy))


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


func _new_tile() -> Image:
	var t: Image = Image.create_empty(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	t.fill(Color(0, 0, 0, 0))
	return t


func _rng_for(id: int, bio: int, alt: int, salt: int = 0) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 9871 + id * 7717 + bio * 1319 + alt * 977 + salt * 31
	return rng


## Цвета породы биома: [основа, тень, блик, акцент (лишайник / мицелий / жар)].
func _bio_cols(bio: int) -> Array:
	match bio:
		1:
			return [pal("m_base"), pal("m_dark"), pal("m_hi"), pal("m_glow")]
		2:
			return [pal("d_base"), pal("d_dark"), pal("d_hi"), pal("d_glow")]
	return [pal("s_base"), pal("s_dark"), pal("s_hi"), pal("s_top")]


## Камень биома: на поверхности чуть темнее глины и слоится (видно, где кончается мягкое).
func _rock_cols(bio: int) -> Array:
	var bc: Array = _bio_cols(bio)
	if bio == 0:
		return [(bc[0] as Color).lerp(bc[1], 0.25), bc[1], (bc[0] as Color).lerp(bc[2], 0.5), bc[2]]
	return bc


## Кэш на время сборки атласа: порода камня (под рудами та же) и узоры руд.
var _tex_cache: Dictionary = {}


func _rock_base(bio: int, alt: int) -> Image:
	var key: String = "rock%d_%d" % [bio, alt]
	if not _tex_cache.has(key):
		var t: Image = _new_tile()
		_paint_rock(t, bio, alt, _rng_for(IDs.T.STONE, bio, alt))
		_tex_cache[key] = t
	return (_tex_cache[key] as Image).duplicate()


## Глина биома: светлее камня, мягкий «войлок» с нитями мицелия.
func _clay_cols(bio: int) -> Array:
	var bc: Array = _bio_cols(bio)
	return [bc[2], bc[0], (bc[2] as Color).lightened(0.12), (bc[2] as Color).lightened(0.28)]


func _tile_base(id: int, bio: int, alt: int) -> Image:
	var t: Image = _new_tile()
	var rng: RandomNumberGenerator = _rng_for(id, bio, alt)
	match id:
		IDs.T.STONE:
			t = _rock_base(bio, alt)
		IDs.T.COPPER_ORE, IDs.T.IRON_ORE, IDs.T.CRYSTAL_ORE, IDs.T.COAL_ORE, IDs.T.SCRAP_ORE:
			# Порода под рудой — та же, что у камня этого биома и фактуры;
			# узор руды от биома не зависит (нечётные фактуры — зеркально).
			t = _rock_base(bio, alt)
			t.blend_rect(_ore_pattern(id, alt), Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i.ZERO)
		IDs.T.DIRT:
			_paint_clay(t, bio, rng)
		IDs.T.GRASS:
			_paint_clay(t, bio, _rng_for(IDs.T.DIRT, bio, alt))
			_paint_lichen(t, bio, rng)
		IDs.T.SAND, IDs.T.SANDSTONE:
			_paint_sand(t, bio, rng, id == IDs.T.SANDSTONE)
		IDs.T.MOSS:
			_paint_moss(t, bio, rng)
		IDs.T.BEDROCK:
			_paint_bedrock(t, rng)
		IDs.T.LOG:
			_paint_fiber(t, rng)
		IDs.T.WATER:
			_paint_water(t)
		IDs.T.LAVA:
			_paint_lava(t, rng)
		_:
			_paint_built(t, id, rng)
	return t


# --------------------------------------------------- фактуры породы

## «Войлок»: мягкие пятна 4×4 и крапины 2×2 (ADR-003 § 4.1, поверхность).
func _felt(t: Image, base: Color, dark: Color, hi: Color, rng: RandomNumberGenerator, amp: float) -> void:
	var blobs: PackedFloat32Array = PackedFloat32Array()
	blobs.resize(16)
	for i in 16:
		blobs[i] = rng.randf()
	var specks: PackedFloat32Array = PackedFloat32Array()
	specks.resize(64)
	for i in 64:
		specks[i] = rng.randf()
	for y in TILE_SIZE:
		for x in TILE_SIZE:
			var n: float = blobs[(y >> 2) * 4 + (x >> 2)]
			var col: Color = base.lerp(dark if n < 0.5 else hi, absf(n - 0.5) * amp)
			var n2: float = specks[(y >> 1) * 8 + (x >> 1)]
			if n2 < 0.06:
				col = dark
			elif n2 > 0.95:
				col = hi
			t.set_pixel(x, y, col)


## Нити мицелия: периодическая по ширине тайла кривая (соседние тайлы той же
## фактуры стыкуются), с разрывами. bright — доля пикселей полного цвета glow.
func _threads(t: Image, col: Color, rng: RandomNumberGenerator, count: int, density: float,
		glow: Color = Color(0, 0, 0, 0), bright: float = 0.0) -> void:
	for i in count:
		var y0: int = rng.randi_range(2, 13)
		var a: float = float(rng.randi_range(1, 2))
		var ph: float = rng.randf() * TAU
		for x in TILE_SIZE:
			if rng.randf() > density:
				continue
			var y: int = clampi(y0 + int(round(a * sin(TAU * float(x) / 16.0 + ph))), 0, TILE_SIZE - 1)
			t.set_pixel(x, y, glow if glow.a > 0.0 and rng.randf() < bright else col)


## Камешки: блоки 2×2 / 3×2 тенью с бликом в углу.
func _pebbles(t: Image, dark: Color, hi: Color, rng: RandomNumberGenerator, n: int) -> void:
	for i in n:
		var w: int = rng.randi_range(2, 3)
		var px: int = rng.randi_range(1, TILE_SIZE - 1 - w)
		var py: int = rng.randi_range(1, TILE_SIZE - 3)
		for yy in 2:
			for xx in w:
				t.set_pixel(px + xx, py + yy, dark)
		t.set_pixel(px, py, hi)


func _paint_rock(t: Image, bio: int, alt: int, rng: RandomNumberGenerator) -> void:
	var rc: Array = _rock_cols(bio)
	var base: Color = rc[0]
	var dark: Color = rc[1]
	var hi: Color = rc[2]
	_felt(t, base, dark, hi, rng, 0.7)
	match bio:
		0:
			# Пласт: горизонтальный шов с разрывами — камень «слоится», глина нет.
			var sy: int = rng.randi_range(5, 11)
			for x in TILE_SIZE:
				if rng.randf() < 0.8:
					t.set_pixel(x, sy, dark)
					if rng.randf() < 0.3:
						t.set_pixel(x, sy - 1, base.lerp(dark, 0.5))
			_pebbles(t, dark, hi, rng, 2)
			_threads(t, hi.lerp(base, 0.3), rng, 1, 0.45)
		1:
			# Нити мицелия светятся бирюзой (ADR-003 § 4.1, средние пещеры).
			_pebbles(t, dark, hi, rng, 1)
			_threads(t, pal("m_glow").lerp(base, 0.6), rng, 1 + (alt & 1), 0.38, pal("m_glow"), 0.18)
		2:
			_pebbles(t, dark, hi, rng, 2)
			if (alt & 1) == 0:
				# Светящаяся трещина: «жар снизу» (ADR-003 § 4.1, глубина).
				var cx: int = rng.randi_range(3, 12)
				for y in TILE_SIZE:
					if rng.randf() < 0.35:
						cx = clampi(cx + (1 if rng.randf() > 0.5 else -1), 1, TILE_SIZE - 2)
					t.set_pixel(cx, y, pal("d_glow"))
					t.set_pixel(cx + 1, y, base.lerp(pal("d_glow"), 0.25))
			else:
				for i in 4:
					t.set_pixel(rng.randi_range(1, 14), rng.randi_range(1, 14), pal("d_glow").lerp(base, 0.35))


func _paint_clay(t: Image, bio: int, rng: RandomNumberGenerator) -> void:
	var cc: Array = _clay_cols(bio)
	_felt(t, cc[0], cc[1], cc[2], rng, 0.8)
	_threads(t, cc[3], rng, 2, 0.65)
	if bio == 1:
		_threads(t, pal("m_glow"), rng, 1, 0.3)
	# корешки — короткие тёмные чёрточки
	for i in 2:
		var rx: int = rng.randi_range(1, 12)
		var ry: int = rng.randi_range(4, 14)
		for k in rng.randi_range(2, 3):
			t.set_pixel(rx + k, ry, (cc[1] as Color).darkened(0.12))


## Лишайник травы: горчичная полоса 2–4 px (по парам столбцов), кончики светлее.
func _paint_lichen(t: Image, bio: int, rng: RandomNumberGenerator) -> void:
	var top: Color = pal("s_top")
	var tip: Color = pal("s_top2")
	if bio == 1:
		top = pal("m_hi").lerp(pal("m_glow"), 0.35)
		tip = pal("m_glow")
	elif bio == 2:
		top = pal("d_hi")
		tip = pal("d_glow")
	var under: Color = top.darkened(0.3)
	var d: int = 3
	for x in TILE_SIZE:
		if x % 2 == 0:
			d = 3 + rng.randi_range(0, 2)
		for y in d:
			t.set_pixel(x, y, top)
		t.set_pixel(x, d, under)
		if rng.randf() < 0.18:
			t.set_pixel(x, d + 1, top)      # нить лишайника уходит в глину
		t.set_pixel(x, 0, tip if rng.randf() < 0.45 else top)


func _paint_sand(t: Image, bio: int, rng: RandomNumberGenerator, layered: bool) -> void:
	var bc: Array = _bio_cols(bio)
	var k: float = 0.0 if bio == 0 else 0.55
	var base: Color = pal("sand").lerp(bc[2], k)
	var dark: Color = pal("sand_d").lerp(bc[0], k)
	var hi: Color = pal("sand_hi").lerp(bc[2], k)
	for y in TILE_SIZE:
		for x in TILE_SIZE:
			var r: float = rng.randf()
			t.set_pixel(x, y, dark if r < 0.12 else (hi if r > 0.9 else base))
	if layered:
		# Песчаник: пласты через 4 px с разрывами.
		for y in [3, 7, 11, 15]:
			for x in TILE_SIZE:
				if rng.randf() < 0.85:
					t.set_pixel(x, y, dark.darkened(0.08))


## Кочка лишайника: весь блок — горчичный «войлок», кончики на верхнем ряду.
func _paint_moss(t: Image, bio: int, rng: RandomNumberGenerator) -> void:
	var base: Color = pal("s_top")
	var hi: Color = pal("s_top2")
	if bio == 1:
		base = pal("m_hi")
		hi = pal("m_glow")
	elif bio == 2:
		base = pal("d_hi")
		hi = pal("d_glow")
	var dark: Color = base.darkened(0.32)
	_felt(t, base, dark, hi, rng, 0.8)
	for x in TILE_SIZE:
		t.set_pixel(x, TILE_SIZE - 1, dark)
		if rng.randf() < 0.5:
			t.set_pixel(x, 0, hi)


func _paint_bedrock(t: Image, rng: RandomNumberGenerator) -> void:
	var b: Color = pal("bed")
	var blobs: PackedFloat32Array = PackedFloat32Array()
	blobs.resize(16)
	for i in 16:
		blobs[i] = rng.randf()
	for y in TILE_SIZE:
		for x in TILE_SIZE:
			t.set_pixel(x, y, b.lightened(0.07) if blobs[(y >> 2) * 4 + (x >> 2)] > 0.68 else b)
	for x in TILE_SIZE:
		t.set_pixel(x, 0, b.lightened(0.1))
	for i in 3:
		t.set_pixel(rng.randi_range(1, 14), rng.randi_range(2, 14), pal("d_dark"))


# --------------------------------------------------- кромки по маске

## Кромки открытых сторон для тайла породы в биоме: [верх, право, низ, лево],
## каждая — прозрачная картинка 16×16 с пикселями только внутри квадрата.
func _edge_overlays(id: int, bio: int) -> Array:
	var bc: Array = _bio_cols(bio)
	var dark: Color = bc[1]
	var rng: RandomNumberGenerator = _rng_for(id, bio, 0, 5)
	var top: Image = _new_tile()
	var right: Image = _new_tile()
	var bottom: Image = _new_tile()
	var left: Image = _new_tile()
	for y in TILE_SIZE:
		right.set_pixel(TILE_SIZE - 1, y, dark)
		left.set_pixel(0, y, dark)
	# Низ (потолок пещеры): тёмная кайма, в средних пещерах — гифы со светящимися кончиками.
	var yb: int = TILE_SIZE - 1
	for x in TILE_SIZE:
		bottom.set_pixel(x, yb, dark)
		var h: float = rng.randf()
		match bio:
			0:
				if h < 0.25:
					bottom.set_pixel(x, yb - 1, dark)
			1:
				if h < 0.3:
					var l: int = rng.randi_range(2, 6)
					for k in l:
						bottom.set_pixel(x, yb - k, pal("m_hi"))
					bottom.set_pixel(x, yb, pal("m_glow"))
			2:
				if h < 0.18:
					bottom.set_pixel(x, yb, pal("d_glow"))
	# Верх: на поверхности — светлый край и пятна лишайника, в пещерах — светящиеся точки.
	for x in TILE_SIZE:
		var h1: float = rng.randf()
		match bio:
			0:
				if id == IDs.T.GRASS:
					if h1 < 0.4:
						top.set_pixel(x, 0, pal("s_top2"))
				elif id == IDs.T.MOSS:
					if h1 < 0.3:
						top.set_pixel(x, 0, pal("s_top2"))
				else:
					top.set_pixel(x, 0, bc[2] if id != IDs.T.SAND else pal("sand_hi"))
					if h1 < (0.4 if id == IDs.T.DIRT else 0.2):
						top.set_pixel(x, 0, pal("s_top"))
						if rng.randf() < 0.5:
							top.set_pixel(x, 1, pal("s_top"))
			1:
				top.set_pixel(x, 0, pal("m_hi"))
				if h1 < 0.14:
					top.set_pixel(x, 0, pal("m_glow"))
			2:
				top.set_pixel(x, 0, pal("d_hi"))
				if h1 < 0.15:
					top.set_pixel(x, 0, pal("d_glow"))
	return [top, right, bottom, left]


## Верх металла/жидкости, когда над ним пусто: лишайник на эмали, блик воды, корка лавы.
func _top_overlay(id: int) -> Image:
	var t: Image = _new_tile()
	var rng: RandomNumberGenerator = _rng_for(id, 0, 0, 7)
	match id:
		IDs.T.WATER:
			for x in TILE_SIZE:
				var w: Color = pal("water_hi")
				t.set_pixel(x, 0, Color(w.r, w.g, w.b, 0.92))
				if rng.randf() < 0.4:
					t.set_pixel(x, 1, Color(w.r, w.g, w.b, 0.5))
		IDs.T.LAVA:
			for x in TILE_SIZE:
				t.set_pixel(x, 0, pal("lava_hi"))
				if rng.randf() < 0.6:
					t.set_pixel(x, 1, pal("lava_hi"))
		_:
			# Лишайник прорастает на верхней кромке техники (ADR-003 § 4.1).
			var share: float = 0.38 if id == IDs.T.STEEL else 0.25
			for x in TILE_SIZE:
				if rng.randf() < share:
					var d: int = rng.randi_range(1, 3)
					for y in d:
						t.set_pixel(x, y, pal("s_top"))
					if rng.randf() < 0.5:
						t.set_pixel(x, 0, pal("s_top2"))
	return t


# --------------------------------------------------- руды

## Узор руды для фактуры alt (прозрачная картинка 16×16): пары фактур — свой
## разброс жил, нечётная — зеркально. Кэшируется на время сборки атласа.
func _ore_pattern(id: int, alt: int) -> Image:
	var key: String = "ore%d_%d" % [id, alt]
	if not _tex_cache.has(key):
		var p: Image = _new_tile()
		_paint_ore(p, id, (alt & 1) == 1, _rng_for(id, 0, alt >> 1, 3))
		_tex_cache[key] = p
	return _tex_cache[key]


## Руды: у каждой свой УЗОР (ADR-003 § 3.2), тёмный контур 1 px и блик —
## их различают и при дальтонизме. mirror — зеркальная фактура.
func _paint_ore(t: Image, id: int, mirror: bool, rng: RandomNumberGenerator) -> void:
	var p: Image = _new_tile()
	var dk: Color = Color.BLACK
	match id:
		IDs.T.COPPER_ORE:
			# медь — диагональные жилы
			var cu: Color = pal("copper")
			dk = pal("copper_d")
			for v in 3:
				var vx: int = rng.randi_range(1, 8)
				var vy: int = 1 + v * 5
				for k in 6:
					var xx: int = vx + k
					var yy: int = vy + k / 2
					if xx < 15 and yy < 14:
						p.set_pixel(xx, yy, cu)
						p.set_pixel(xx, yy + 1, cu.darkened(0.15))
				p.set_pixel(vx, vy, cu.lightened(0.35))
		IDs.T.IRON_ORE:
			# железо (кобальт) — квадратные самородки
			var fe: Color = pal("iron")
			dk = pal("iron_d")
			for v in 3:
				var nx: int = [2, 9, 5][v] + rng.randi_range(0, 1)
				var ny: int = [2, 3, 10][v]
				var nw: int = 4 if v != 2 else 5
				for yy in 3:
					for xx in nw:
						p.set_pixel(nx + xx, ny + yy, fe)
				p.set_pixel(nx, ny, fe.lightened(0.45))
				p.set_pixel(nx + nw - 1, ny + 2, fe.darkened(0.25))
		IDs.T.COAL_ORE:
			# уголь — чёрные блоки 3×2 с бликом
			dk = pal("coal").lightened(0.1)
			for v in 5:
				var cx: int = [2, 8, 11, 3, 9][v] + rng.randi_range(-1, 1)
				var cy: int = [2, 3, 8, 9, 12][v] + rng.randi_range(0, 1)
				for yy in 2:
					for xx in 3:
						p.set_pixel(cx + xx, cy + yy, pal("coal"))
				p.set_pixel(cx, cy, pal("coal_hi"))
		IDs.T.CRYSTAL_ORE:
			# кристалл — вертикальные призмы, светится
			var cr: Color = pal("crystal")
			dk = pal("crystal_d")
			for v in 3:
				var px0: int = [3, 7, 11][v]
				var ph: int = [7, 11, 6][v] + rng.randi_range(-2, 1)
				for yy in ph:
					p.set_pixel(px0, 14 - yy, cr.lightened(0.4))
					p.set_pixel(px0 + 1, 14 - yy, cr)
				p.set_pixel(px0, 14 - ph, Color.WHITE)
		IDs.T.SCRAP_ORE:
			# хлам — пластина с заклёпками
			var sc: Color = pal("scrap")
			dk = pal("scrap_d")
			for yy in 4:
				for xx in 7:
					p.set_pixel(3 + xx, 5 + yy, sc)
			for q in [Vector2i(3, 5), Vector2i(9, 5), Vector2i(3, 8), Vector2i(9, 8)]:
				p.set_pixel(q.x, q.y, dk)
			for yy in 5:
				p.set_pixel(11, 6 + yy, sc.darkened(0.2))
			p.set_pixel(6, 11, pal("hazard").darkened(0.2))
			p.set_pixel(5, 12, dk)
	# Тёмный контур вокруг узора — руда читается на любой породе.
	var src: Image = p.duplicate()
	for y in TILE_SIZE:
		for x in TILE_SIZE:
			if src.get_pixel(x, y).a > 0.0:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + d
				if q.x >= 0 and q.y >= 0 and q.x < TILE_SIZE and q.y < TILE_SIZE and src.get_pixel(q.x, q.y).a > 0.0:
					p.set_pixel(x, y, dk)
					break
	if mirror:
		p.flip_x()
	t.blend_rect(p, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i.ZERO)


# --------------------------------------------------- жидкости, флора

func _paint_water(t: Image) -> void:
	var w: Color = pal("water")
	for y in TILE_SIZE:
		for x in TILE_SIZE:
			var c: Color = w
			if (y % 4) == 2 and ((x >> 2) + (y >> 2)) % 2 == 0:
				c = w.lightened(0.1)
			t.set_pixel(x, y, Color(c.r, c.g, c.b, 0.8))


func _paint_lava(t: Image, rng: RandomNumberGenerator) -> void:
	var cells: PackedFloat32Array = PackedFloat32Array()
	cells.resize(64)
	for i in 64:
		cells[i] = rng.randf()
	for y in TILE_SIZE:
		for x in TILE_SIZE:
			var n: float = cells[(y >> 1) * 8 + (x >> 1)]
			var col: Color = pal("lava")
			if n > 0.82:
				col = pal("lava_hi")
			elif n < 0.18:
				col = pal("lava").darkened(0.25)
			t.set_pixel(x, y, col)


## Волокно стебля свечника, сложенное блоком (тайл LOG): кремовые волокна,
## обвязка и фаска.
func _paint_fiber(t: Image, rng: RandomNumberGenerator) -> void:
	var f: Color = pal("fl3")
	var fd: Color = pal("fl3").darkened(0.16)
	for x in TILE_SIZE:
		var col: Color = f if x % 3 != 0 else fd
		col = col.lightened(rng.randf_range(-0.03, 0.03))
		for y in TILE_SIZE:
			t.set_pixel(x, y, col)
	for x in TILE_SIZE:
		for y in [4, 11]:
			t.set_pixel(x, y, pal("fl1_d"))
		t.set_pixel(x, 0, f.lightened(0.15))
		t.set_pixel(x, TILE_SIZE - 1, fd.darkened(0.2))


# --------------------------------------------------- флора (ADR-003 V2, #104)
# «Свечник» — тот же TREE (стебель) и LEAVES (шляпки): оба не твёрдые, проходимость
# и форма дерева в мире прежние (World._place_tree). Меняется только рисунок:
#  * стебель — узкий столб STEM_W px посреди клетки, вокруг пусто;
#  * шляпка — плита CAP_H px в верхней части клетки, ниже просвет. Ряды кроны
#    читаются стопкой квадратных шляпок-дождевиков (ADR-003 § 4.1), а в просвете
#    шляпок над стволом стебель дорисовывает декор-слой (scripts/world/decor.gd);
#  * верх ствола (над ним шляпка) несёт нижнюю шляпку кроны поперёк стебля.
# Варианты — по маске открытых сторон (как у породы V1) и 4 фактуры. Край тайла прямой.

const CAP_H: int = 9          ## высота шляпки в клетке, px
const STEM_X: int = 6         ## левый край стебля в клетке, px (декор рисует так же)
const STEM_W: int = 4         ## ширина стебля, px


## Маска «лица» флоры для галереи: шляпка — одиночная (открыты верх и бока), стебель — середина.
func _flora_face(id: int) -> int:
	return 1 | 2 | 8 if id == IDs.T.LEAVES else 0


## Клетка флоры: id — TREE или LEAVES, alt — фактура, m — маска открытых сторон.
func _flora_tile(id: int, alt: int, m: int) -> Image:
	var t: Image = _new_tile()
	var rng: RandomNumberGenerator = _rng_for(id, 0, alt, 40 + m)
	if id == IDs.T.TREE:
		paint_flora_stem(t, 0, TILE_SIZE, alt)
		if m & 1:
			# Над стеблем шляпка или пусто — это верх ствола: нижняя шляпка кроны.
			# Бока не скругляем: у широкой кроны слева и справа та же шляпка.
			_paint_cap_slab(t, false, rng)
	else:
		_paint_cap_slab(t, (m & 1) != 0, rng)
		if m & 4:
			# Нижняя шляпка столбца: пластинки длиннее.
			for x in range(1, TILE_SIZE, 4):
				t.set_pixel(x, CAP_H + 1, pal("fl1_d").darkened(0.15))
	return t


## Стебель свечника в строках y0..y1-1: светлый левый край, тень справа, кольца роста.
func paint_flora_stem(t: Image, y0: int, y1: int, alt: int) -> void:
	var f: Color = pal("fl3")
	var cols: Array = [f.lightened(0.12), f, f.darkened(0.05), f.darkened(0.22)]
	for y in range(y0, y1):
		for k in STEM_W:
			t.set_pixel(STEM_X + k, y, cols[k])
	# Розовое кольцо роста — у половины фактур, на своей высоте.
	if alt % 2 == 1:
		var ry: int = 3 + alt * 3
		if ry >= y0 and ry < y1:
			for k in STEM_W:
				t.set_pixel(STEM_X + k, ry, pal("fl1"))
	# Волокно: тёмная черточка посреди стебля.
	var wy: int = (5 + alt * 5) % TILE_SIZE
	if wy >= y0 and wy + 2 < y1:
		t.set_pixel(STEM_X + 1, wy, f.darkened(0.14))
		t.set_pixel(STEM_X + 1, wy + 1, f.darkened(0.14))


## Шляпка-плита CAP_H px сверху клетки: блик сверху, тёмная кромка снизу, под ней —
## пластинки через пиксель; кремовые споровые пятна (на верхней шляпке больше).
## Бока не выделяем: сосед-стебель для маски тоже «открыт», а шляпка через него
## должна идти без шва. Все края — прямые.
func _paint_cap_slab(t: Image, top: bool, rng: RandomNumberGenerator) -> void:
	var c: Color = pal("fl1")
	var d: Color = pal("fl1_d")
	for y in CAP_H:
		for x in TILE_SIZE:
			var col: Color = c
			if y == 0:
				col = c.lightened(0.2)
			elif y == CAP_H - 1:
				col = d
			elif y == CAP_H - 2 and x % 2 == 0:
				col = c.lerp(d, 0.45)
			t.set_pixel(x, y, col)
	for x in range(0, TILE_SIZE, 2):
		t.set_pixel(x, CAP_H, d.darkened(0.15))
	var spots: int = 3 if top else 1
	for i in spots:
		var sx: int = rng.randi_range(1, TILE_SIZE - 3)
		var sy: int = rng.randi_range(2, CAP_H - 4)
		_rect(t, sx, sy, 2, 2, pal("fl3"))
		t.set_pixel(sx + 1, sy + 1, pal("fl3").darkened(0.12))


# --------------------------------------------------- постройки

func _rect(t: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	t.fill_rect(Rect2i(x, y, w, h), c)


## Блок с фаской: светлый верх/лево, тёмный низ/право.
func _paint_block(t: Image, base: Color, rng: RandomNumberGenerator) -> void:
	for y in TILE_SIZE:
		for x in TILE_SIZE:
			var c: Color = base.lightened(rng.randf_range(-0.04, 0.04))
			if x == 0 or y == 0:
				c = c.lightened(0.2)
			if x == TILE_SIZE - 1 or y == TILE_SIZE - 1:
				c = c.darkened(0.25)
			t.set_pixel(x, y, c)


func _paint_built(t: Image, id: int, rng: RandomNumberGenerator) -> void:
	var mt: Color = pal("metal")
	var md: Color = pal("metal_d")
	var mh: Color = pal("metal_hi")
	var fr: Color = pal("frame")
	match id:
		IDs.T.STEEL:
			# Пол базы: кремовая эмаль, жёлтая полоса, заклёпки рамы.
			_rect(t, 0, 0, 16, 16, mt)
			_rect(t, 0, 0, 16, 1, mh)
			_rect(t, 0, 15, 16, 1, md)
			_rect(t, 15, 0, 1, 16, md)
			_rect(t, 0, 6, 16, 2, pal("hazard").lerp(mt, 0.25))
			for q in [Vector2i(2, 3), Vector2i(13, 3), Vector2i(2, 12), Vector2i(13, 12)]:
				t.set_pixel(q.x, q.y, fr)
		IDs.T.PANEL:
			# Стенная панель: рёбра эмали на тёмном.
			_rect(t, 0, 0, 16, 16, md)
			for x in range(1, 16, 4):
				_rect(t, x, 0, 2, 16, mt)
			_rect(t, 0, 0, 16, 1, mh)
			_rect(t, 0, 15, 16, 1, fr)
		IDs.T.STEEL_WALL:
			# Клёпаная стальная плита рамного цвета: шов посередине, заклёпки по углам.
			_paint_block(t, fr, rng)
			for x in TILE_SIZE:
				t.set_pixel(x, 8, fr.darkened(0.3))
			for q in [Vector2i(2, 2), Vector2i(13, 2), Vector2i(2, 13), Vector2i(13, 13)]:
				t.set_pixel(q.x, q.y, mh)
		IDs.T.TERMINAL:
			_rect(t, 0, 0, 16, 16, md)
			_rect(t, 0, 0, 16, 1, mh)
			_rect(t, 2, 2, 12, 8, pal("screen"))
			for l in 3:
				_rect(t, 3, 3 + l * 2, rng.randi_range(3, 9), 1, pal("screen_hi"))
			_rect(t, 3, 12, 2, 2, pal("hazard"))
			_rect(t, 7, 12, 2, 2, fr)
			_rect(t, 11, 12, 2, 2, fr)
		IDs.T.RELAY_CORE:
			_rect(t, 0, 0, 16, 16, fr)
			_rect(t, 1, 1, 14, 14, md)
			_rect(t, 4, 4, 8, 8, pal("bio"))
			_rect(t, 6, 6, 4, 4, Color.WHITE)
		IDs.T.GLASS:
			var g: Color = pal("water_hi")
			_rect(t, 0, 0, 16, 16, Color(g.r, g.g, g.b, 0.3))
			_rect(t, 0, 0, 16, 1, fr)
			_rect(t, 0, 15, 16, 1, fr)
			_rect(t, 0, 0, 1, 16, fr)
			_rect(t, 15, 0, 1, 16, fr)
			for k in 4:
				t.set_pixel(3 + k, 9 - k, Color(1, 1, 1, 0.7))
				t.set_pixel(4 + k, 12 - k, Color(1, 1, 1, 0.45))
		IDs.T.LIGHT_CRYSTAL:
			# Светоблок: клетка с живой светящейся колонией.
			_rect(t, 0, 0, 16, 16, pal("m_dark"))
			_rect(t, 4, 3, 8, 10, pal("bio"))
			_rect(t, 6, 5, 4, 6, pal("bio_core"))
			_rect(t, 0, 0, 16, 2, fr)
			_rect(t, 0, 14, 16, 2, fr)
			for x in [0, 5, 10, 15]:
				_rect(t, x, 2, 1, 12, fr)
			_rect(t, 0, 0, 16, 1, fr.lightened(0.2))
		IDs.T.COPPER_BLOCK:
			_paint_block(t, pal("copper").darkened(0.08), rng)
			for k in 5:
				t.set_pixel(4 + k, 9 - k, pal("copper").lightened(0.3))
		IDs.T.IRON_BLOCK:
			_paint_block(t, pal("iron").lerp(mt, 0.35), rng)
			_rect(t, 3, 3, 4, 3, pal("iron").lerp(mh, 0.5))
		IDs.T.CRYSTAL_BLOCK:
			_paint_block(t, pal("crystal_d"), rng)
			for v in 3:
				_rect(t, 3 + v * 4, 3 + v, 2, 10 - v, pal("crystal"))
				t.set_pixel(3 + v * 4, 3 + v, Color.WHITE)
		IDs.T.AIRLOCK:
			# Закрытая дверь: плита рамы с жёлто-тёмной полосой посередине.
			_paint_block(t, md.darkened(0.25), rng)
			for x in TILE_SIZE:
				var stripe: Color = pal("hazard") if int(x / 4) % 2 == 0 else fr.darkened(0.4)
				t.set_pixel(x, 7, stripe)
				t.set_pixel(x, 8, stripe)
		IDs.T.AIRLOCK_OPEN:
			# Открытая дверь: только рама, середина прозрачна.
			var od: Color = md.darkened(0.25)
			_rect(t, 0, 0, 2, 16, od)
			_rect(t, 14, 0, 2, 16, od)
			_rect(t, 0, 0, 16, 2, od)
			_rect(t, 0, 14, 16, 2, od)
			_rect(t, 2, 1, 12, 1, pal("hazard"))
		IDs.T.VENT_GRATE:
			# Решётка: планки эмали, между ними темнота шахты.
			for y in TILE_SIZE:
				var slat: int = y % 4
				var c: Color = Color(0.10, 0.08, 0.10, 0.85)
				if slat == 0:
					c = mt
				elif slat == 1:
					c = md
				_rect(t, 0, y, 16, 1, c)


# --------------------------------------------------- читаемость (ADR-003 § 5)

## Дейтеранопия: матрица Machado et al. 2009 (тяжесть 1.0) в sRGB — та же, что
## у tools/style_concepts.gd (_deutan).
static func deutan(c: Color) -> Color:
	return Color(clampf(0.367322 * c.r + 0.860646 * c.g - 0.227968 * c.b, 0.0, 1.0),
			clampf(0.280085 * c.r + 0.672501 * c.g + 0.047413 * c.b, 0.0, 1.0),
			clampf(-0.011820 * c.r + 0.042940 * c.g + 0.968881 * c.b, 0.0, 1.0))


## sRGB → CIE Lab (D65).
static func to_lab(c: Color) -> Vector3:
	var lin: Array = []
	for v in [c.r, c.g, c.b]:
		lin.append(v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4))
	var x: float = (0.4124 * lin[0] + 0.3576 * lin[1] + 0.1805 * lin[2]) / 0.95047
	var y: float = 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]
	var z: float = (0.0193 * lin[0] + 0.1192 * lin[1] + 0.9505 * lin[2]) / 1.08883
	var f: Array = []
	for t in [x, y, z]:
		f.append(pow(t, 1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0)
	return Vector3(116.0 * f[1] - 16.0, 500.0 * (f[0] - f[1]), 200.0 * (f[1] - f[2]))


## ΔE (CIE76) между двумя цветами.
static func delta_e(a: Color, b: Color) -> float:
	return to_lab(a).distance_to(to_lab(b))


## Цвета руд для проверки читаемости (ADR-003 § 5): ключ палитры по тайлу.
const ORE_PAL: Dictionary = {
	IDs.T.COPPER_ORE: "copper", IDs.T.IRON_ORE: "iron", IDs.T.COAL_ORE: "coal",
	IDs.T.CRYSTAL_ORE: "crystal", IDs.T.SCRAP_ORE: "scrap",
}  # const expression now valid after IDs.T.* fixed; used in tools/ore_census.gd etc.


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
