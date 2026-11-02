class_name Balance
## Все числа игры в одном месте (ADR-001, решение D11).
##
## Ссылки «§ x.y» — на разделы docs/adr/0001-core-loop.md. Калибровочный PR (#33)
## меняет только этот файл; системные PR читают константы отсюда и не держат
## своих копий. Все значения положительные — это проверяет автотест.

# ---------------------------------------------------------------- § 4.1 Сутки
const DAY_LENGTH: float = 240.0        ## полный цикл день+ночь, с (было 150)
const NIGHT_START: float = 0.66        ## доля цикла, с которой начинается ночь
const NIGHT_END: float = 0.04          ## доля цикла, на которой ночь кончается (рассвет)
const DUSK_START: float = 0.60         ## сумерки: телеграф ночи, вентиляции «гудят»
const START_TIME: float = 0.30         ## время старта забега (утро первой смены)

# -------------------------------------------------------------- § 4.3 Питание
## Условные единицы мощности. Генератор даёт POWER_OUT, потребитель тянет
## POWER_DRAW; при перегрузе машины в радиусе замедляются пропорционально (#25).
## Плавильня 0.5 (было 1.0, калибровка #33): стартовая линия § 4.2 — бур, две
## плавильни (слитки и пластины), два манипулятора, сборщик — ровно 6 = одна ТЭЦ.
const POWER_OUT: Dictionary = {"CoalGen": 6.0, "Solar": 2.0}
const POWER_DRAW: Dictionary = {
	"Drill": 2.0, "Smelter": 0.5, "Assembler": 2.0, "Inserter": 0.5,
	"Analyzer": 2.0, "Turret": 2.0, "Floodlight": 1.0, "DeepDrill": 4.0,
}
const SOLAR_MIN_DAYLIGHT: float = 0.35 ## солнце работает, пока daylight() выше
const FLOODLIGHT_MIN_EFF: float = 0.5  ## прожектор гаснет при просадке ниже
const COAL_BURN: float = 45.0          ## секунд горения одной единицы угля
const POWER_CHECK_INTERVAL: float = 0.25

# ------------------------------------------------------- § 4.2 Автоматизация
const DRILL_CYCLE: float = 2.0         ## с на единицу руды
const DRILL_REACH: int = 16            ## клеток вниз
const DEEP_DRILL_CYCLE: float = 1.2
const DEEP_DRILL_REACH: int = 40
const INSERTER_PERIOD: float = 1.2     ## с на перенос одного предмета
const ANALYZER_PERIOD: float = 20.0    ## с на единицу данных
const ANALYZER_DATA: int = 1           ## данных за один кристалл

# -------------------------------------------------------------- § 4.4 Оборона
## Было 60 (калибровка #33): каждая особь роя бьёт сразу, как долетела, — две
## стаи (до 12 особей) первым же укусом снимали 60+ hp с одного бура, раньше
## чем турели успевали выстрелить. 100 — бур переживает налёт под турелями.
const MACHINE_HP: float = 100.0
const TURRET_HP: float = 120.0
const TURRET_RANGE_TILES: float = 7.0
const TURRET_DAMAGE: float = 20.0
const TURRET_PERIOD: float = 0.8
const FLOODLIGHT_POWER: float = 2.0    ## сила света прожектора (светокристалл — 1.0)
const STEEL_WALL_HARD: float = 4.0
const GRATE_HP: float = 40.0
const REPAIR_PER_SCRAP: float = 20.0   ## HP машины за единицу хлама
const BURROWER_DIG_MAX_HARD: float = 1.5 ## копатель роет тайлы не твёрже этого
const AIRLOCK_OPEN_DIST_TILES: float = 1.5 ## игрок ближе — шлюз открывается
const AIRLOCK_SAFE_DIST_TILES: float = 3.0 ## фантом ближе — шлюз не открывается
# --- Оборона: поведение построек (#31) ---
const AIRLOCK_CHECK_PERIOD: float = 0.1  ## как часто World пересчитывает шлюзы, с
const GRATE_BREAK_TIME: float = 8.0      ## копатель ломает решётку (GRATE_HP) за столько секунд
const GRATE_REACH_PX: float = 24.0       ## копатель ближе — грызёт решётку
## Приоритет целей турели: раньше в списке — важнее (§ 4.4).
## Рой поднят перед копателем, двойником и эхо (калибровка #33): эхо под светом
## базы кружит рядом и забирало все выстрелы, пока стая грызла бур под турелями.
const TURRET_PRIORITY: Array[String] = ["shade", "swarm", "burrower", "doppel", "echo"]
const TURRET_SCAN_PERIOD: float = 0.1    ## турель без цели ищет её не чаще, с
const VENTS_RANDOM: int = 14             ## случайных вентиляций в пещерах (§ 1.1)
const VENT_MIN_GAP: int = 16             ## клеток между соседними вентиляциями

# ---------------------------------------------------------------- § 4.5 Враги
## Таблица типов фантомов. light_flee — порог света, от которого фантом
## убегает; INF — свет ему безразличен. from_night — с какой ночи появляется.
## cost — цена в бюджете ночи у директора угрозы (#27).
const PHANTOMS: Dictionary = {
	"echo":     {"hp": 100.0, "speed": 160.0, "dmg": 24.0, "light_flee": 0.55, "from_night": 1, "cost": 1.0},
	"swarm":    {"hp": 30.0,  "speed": 200.0, "dmg": 8.0,  "light_flee": INF,  "from_night": 2, "cost": 2.0, "pack": 5},
	"shade":    {"hp": 180.0, "speed": 120.0, "dmg": 18.0, "light_flee": INF,  "from_night": 3, "cost": 3.0},
	"burrower": {"hp": 140.0, "speed": 90.0,  "dmg": 30.0, "light_flee": 0.80, "from_night": 4, "cost": 4.0},
	"doppel":   {"hp": 120.0, "speed": 168.0, "dmg": 40.0, "light_flee": INF,  "from_night": 6, "cost": 6.0, "max": 1},
}
## Было 0.5 (калибровка #33): у базы с 2 ТЭЦ ночь 3 получала B ≈ 11.7 — состав
## из 6 единиц при cap 5, и единственная стая роя, выпав в очереди последней,
## всю ночь ждала места за эхо, которые не умирают под светом базы. С 0.25
## B ≈ 10.7: в составе две стаи (§ 4.5: «3 эхо + стая + тень»), одна выходит всегда.
const THREAT_PER_GENERATOR: float = 0.25
const THREAT_PER_LIGHT: float = 0.02
const THREAT_RELAY: float = 4.0
const NIGHT_BUDGET_BASE: float = 3.0
const NIGHT_BUDGET_PER_T: float = 2.0
const CAP_BASE: int = 2                ## живых фантомов ночью: CAP_BASE + смена
const CAP_MAX: int = 10
const SPAWN_INTERVAL_MAX: float = 7.0
const SPAWN_INTERVAL_MIN: float = 2.5
const SPAWN_INTERVAL_PER_T: float = 0.5
const VENT_TELEGRAPH: float = 2.0      ## с от «пара из вентиляции» до появления
const BLACK_BOX_CHANCE: float = 0.25
const MAX_PHANTOMS: int = 16           ## поднято с 12 после замера freeze_probe в #27

# ------------------------------------------ § 4.5 Враги: поведение типов (#27)
const SWARM_SEEK_PX: float = 300.0     ## рой видит работающий бур/сборщик в этом радиусе
const SWARM_PACK_SPREAD: int = 1       ## стая = pack ± это число (4–6)
const SHADE_SEEK_PX: float = 640.0     ## тень чует генератор в этом радиусе
const SHADE_DRAIN_PERIOD: float = 3.0  ## тень у ТЭЦ сжигает 1 уголь за столько секунд
const BURROWER_DIG_PERIOD: float = 0.6 ## копатель роет 1 клетку за столько секунд
const BURROWER_HUNT_PX: float = 600.0  ## копатель чует игрока сквозь породу
const DOPPEL_GAZE_PX: float = 200.0    ## двойник замирает под взглядом ближе этого
## Пауза между ударами фантома по машине, с. Было 0.8 (калибровка #33): стая из
## 5–6 особей сносила машину за секунду — турели не успевали ответить.
const MACHINE_HIT_PERIOD: float = 2.0
const BLACK_BOX_DATA: int = 1          ## данных за чёрный ящик (§ 4.6)
const VENT_SPAWN_COUNT: int = 3        ## из скольких ближайших вентиляций спавн
const VENT_SPAWN_MIN_PX: float = 160.0 ## ближе к игроку вентиляция не «выдыхает»
## Дальше — спавн в пещере, как раньше. Было 1600 (калибровка #33): стая из
## вентиляции за ~80 клеток видела базу, но не находила к ней пути и всю ночь
## висела в пещере — ночь 3 без обороны не стоила базе ни одной машины.
const VENT_SPAWN_MAX_PX: float = 1000.0

# --------------------------------------------------------- § 4.6 Исследования
const TECH_COST: Dictionary = {"T1": 5, "T2": 10, "T3": 15, "T4": 20, "T5": 25}
const TERMINAL_DATA: int = 5           ## данных за терминал под питанием

# ---------------------------------------------------------------- § 4.7 Релей
## Вдвое против § 4.7 (калибровка #33, риск «ручной путь жизнеспособен», § 6):
## руками было ≈ 15 мин копки при цели ≥ 25, две линии буров — ≈ 4 мин при ≤ 12.
const RELAY_REQ: Dictionary = {
	IDs.I.IRON_PLATE: 48,
	IDs.I.STEEL_PLATE: 24,
	IDs.I.CIRCUIT: 24,
	IDs.I.POWER_CELL: 12,
	IDs.I.RELAY_ANTENNA: 1,
}
const RELAY_TIME: float = 180.0        ## удержание сигнала, этап 4 (#32)
const RELAY_HOLD_CAP: int = 10         ## живых фантомов во время удержания сигнала

# --------------------------------------------------------------- § 4.8 Игрок
const HIDE_MAX: float = 6.0            ## с в вентиляции, потом выталкивает
const HIDE_COOLDOWN: float = 10.0
const RESPAWN_DELAY: float = 3.0

# ------------------------------------------------------- Туман войны (#59)
## Обзор — простое правило: круг радиусом в клетках вокруг героя. Под землёй
## темно и тесно, на поверхности видно дальше. Круг открывается в битовой карте
## World.explored при смене клетки героя; внутри круга туман снят, за ним
## исследованное затемнено на FOG_DIM, неисследованное — чёрное.
const FOG_RADIUS: int = 8              ## клеток обзора под землёй
const FOG_RADIUS_SURFACE: int = 16     ## клеток обзора на поверхности
const FOG_SURFACE_DEPTH: int = 3       ## не глубже стольких клеток под рельефом — «на поверхности»
const FOG_EDGE: int = 3                ## ширина мягкого края обзора, клеток
const FOG_DIM: float = 0.55            ## затемнение исследованного вне обзора (1 — чёрное)

# ------------------------------------------------------ § 4.9 Небесный тайник (#60)
## Обломок «Кербер-9» в небе: между верхом рельефа под ним (с деревьями и
## руинами) и днищем обломка — SKY_CLEARANCE_MIN..MAX пустых клеток. Прыжок
## героя — 3.2 клетки (Player.JUMP_VELOCITY, GRAVITY), с ростом — 4.6: допрыгнуть
## нельзя, достроиться лестницей из блоков — можно (блоки ставятся в воздух).
const SKY_CLEARANCE_MIN: int = 9
const SKY_CLEARANCE_MAX: int = 12
const SKY_TOP_MARGIN: int = 2          ## клеток от верха мира до крыши обломка
const SKY_BASE_GAP: int = 40           ## клеток от релея: тайник не висит над лагерем
const SKY_EDGE_GAP: int = 32           ## клеток от левого края мира до носа: место под лестницу
const SKY_TRIES: int = 32              ## попыток найти колонку, где обломок помещается
const SKY_DEBRIS_CHANCE: float = 0.5   ## шанс второго, малого обломка рядом
const SKY_CACHE_MIN: int = 3           ## разных предметов в тайнике
const SKY_CACHE_MAX: int = 6
const SKY_REVEAL_TILES: float = 6.0    ## ближе — обломок проступает из силуэта
const SKY_HAZE_ALPHA: float = 0.82     ## насколько тёмен силуэт издалека
## Груз обломка: предмет → [мин, макс]. Позиций не меньше SKY_CACHE_MAX.
const SKY_LOOT: Dictionary = {
	IDs.I.POWER_CELL: [1, 2],
	IDs.I.CIRCUIT: [3, 6],
	IDs.I.STEEL_PLATE: [3, 6],
	IDs.I.CRYSTAL: [3, 6],
	IDs.I.SOLAR: [1, 1],
	IDs.I.DEEP_DRILL: [1, 1],
	IDs.I.ANALYZER: [1, 1],
	IDs.I.FLOODLIGHT: [1, 1],
}
