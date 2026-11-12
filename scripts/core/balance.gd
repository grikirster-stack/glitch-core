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
const START_TIME: float = 0.04         ## старт забега на рассвете (ADR-005 § 6.1): до ночи полный день

# -------------------------------------------------------------- § 4.3 Питание
## Бюджет мощности снят (#170, ADR-005 § 7). Порог света дня остался у коллектора.

# --------------------------------------------------------- Луч (ADR-005 § 4–5)
## Горелка бьёт на BEAM_LEN клеток; белый (коллектор или смесь W) — длиннее.
## Каждая постройка луча на пути съедает BEAM_BLOCK_COST клеток длины.
## Свет клетки луча — BEAM_LIGHT; белый ярче. Топливо горелки: предмет → секунды.
const BEAM_LEN: int = 24
const BEAM_LEN_WHITE: int = 32
const BEAM_BLOCK_COST: int = 2
const BEAM_LIGHT: float = 1.0
const BEAM_LIGHT_WHITE: float = 1.5
const FUEL: Dictionary = {IDs.I.COAL: 45.0, IDs.I.COPPER_ORE: 30.0, IDs.I.CRYSTAL: 60.0}
## Запасная длительность угля, если предмет не в FUEL (шкала горелки, тень).
const COAL_BURN: float = 45.0
## Накопитель хранит столько секунд луча одного цвета (ADR-005 § 4, #166).
const ACCUMULATOR_CAP: float = 120.0
## Коллектор молчит, пока daylight() не выше этого (бывший порог солнечной панели).
const COLLECTOR_MIN_DAYLIGHT: float = 0.35

# ---------------------------------------------------- Радужный кот (ADR-005 § 7, #176)
## Страж на 90 с: скорость полёта, след-свет, перезарядка от любого луча в ядро.
## Тишина 10 с без фантомов — кот возвращается, не ждёт конца срока.
const CAT_TIME: float = 90.0
const CAT_RECHARGE: float = 60.0
const CAT_SPEED: float = 320.0
const CAT_TRAIL_LIGHT: float = 1.5
const CAT_TRAIL_STEP: float = 0.05
const CAT_TRAIL_LIFE: float = 1.5
const CAT_TRAIL_POINTS: int = 30
const CAT_QUIET: float = 10.0

# ------------------------------------------------------- Маяк (ADR-005 § 5, #167)
## Красный жжёт как турель: 20 урона раз в 0.8 с, дальность 7 клеток, прямая
## видимость. Жёлтый светит как прожектор (сила 2.0). Зелёный чинит +20 HP
## раз в 3 с всем постройкам в 3 клетках.
const PHAROS_HP: float = 100.0
const PHAROS_RED_DAMAGE: float = 20.0
const PHAROS_RED_PERIOD: float = 0.8
const PHAROS_RANGE_TILES: float = 7.0
const PHAROS_GREEN_PERIOD: float = 3.0
const PHAROS_GREEN_HEAL: float = 20.0
const PHAROS_GREEN_RADIUS: int = 3
## Сила и радиус жёлтого — те же числа, что у прожектора (46 + 2·60 px, сила 2.0).
const PHAROS_YELLOW_POWER: float = 2.0
## Синий морозит: в 4 клетках скорость × 0.5, 1 с без удара из каждых 3.
const PHAROS_BLUE_RADIUS: int = 4
const PHAROS_BLUE_SLOW: float = 0.5
const PHAROS_BLUE_STUN: float = 1.0
const PHAROS_BLUE_STUN_PERIOD: float = 3.0
## Голубой купол: 3 клетки, 100 урона, потом 10 с тишины и снова 100.
const PHAROS_DOME_RADIUS: int = 3
const PHAROS_DOME_HP: float = 100.0
const PHAROS_DOME_DOWN: float = 10.0
## Пурпурный зовёт рой и тень на 640 px; сам маяк под ним крепче.
const PHAROS_LURE_PX: float = 640.0
const PHAROS_LURE_HP: float = 200.0
## Белый показывает руду в 8 клетках (квадрат Чебышёва), раз в секунду.
const PHAROS_WHITE_RADIUS: int = 8
const PHAROS_WHITE_PERIOD: float = 1.0
## Линза в маяке (#172): красный бьёт на 10 клеток, урон и жёлтый свет × 1.5,
## синий, купол и приманка + 2 клетки, белый — 12. Зелёный радиус не растёт.
## Без линзы числа выше не меняются.
const LENS_RANGE_TILES: float = 10.0
const LENS_MUL: float = 1.5
const LENS_RADIUS_BONUS: int = 2
const LENS_LURE_BONUS_PX: float = 32.0
const LENS_WHITE_RADIUS: int = 12

# ------------------------------------------------------- Сирена (ADR-005 § 7.2, #172)
## E при полном заряде гонит всех фантомов в 10 клетках, включая рой и тень.
## Заряд копится только под лучом: 60 с до готовности, гон длится 10 с.
const SIREN_RADIUS_TILES: float = 10.0
const SIREN_TIME: float = 10.0
const SIREN_RECHARGE: float = 60.0

# -------------------------------------------------------------- § 4.4 Оборона
## Прочность построек. Фабрика и турель сняты (#170): маяк держит свой PHAROS_HP.
const MACHINE_HP: float = 100.0
const STEEL_WALL_HARD: float = 4.0
const GRATE_HP: float = 40.0
const REPAIR_PER_SCRAP: float = 20.0   ## HP машины за единицу хлама
const BURROWER_DIG_MAX_HARD: float = 1.5 ## копатель роет тайлы не твёрже этого
# --- Оборона: поведение построек (#31) ---
## Шлюз снят (#170): тайлы старого мира становятся камнем при загрузке.
const GRATE_BREAK_TIME: float = 8.0      ## копатель ломает решётку (GRATE_HP) за столько секунд
const GRATE_REACH_PX: float = 24.0       ## копатель ближе — грызёт решётку
## Приоритет целей красного маяка: раньше в списке — важнее.
const TURRET_PRIORITY: Array[String] = ["shade", "swarm", "burrower", "doppel", "echo"]
const TURRET_SCAN_PERIOD: float = 0.1    ## маяк без цели ищет её не чаще, с
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
## Угроза по мощности базы (ADR-005 § 6.2, #173). Смена в формуле не выше 3:
## кто ничего не строит, получает ту же ночь, что и раньше. Старые множители
## генератора и лампы сняты — их место у горелок, маяков и накопителей.
const THREAT_DAY_CAP: int = 3
const THREAT_PER_BURNER: float = 0.5   ## горящая горелка
const THREAT_PER_PHAROS: float = 1.0   ## маяк под лучом (блока ещё нет — вклад 0)
const THREAT_PER_ACCUM: float = 0.25   ## накопитель
const THREAT_RELAY: float = 4.0        ## удержание сигнала, как раньше
const NIGHT_BUDGET_BASE: float = 1.0
const NIGHT_BUDGET_PER_T: float = 2.0
## Ночи 1–2 тихие: бюджет не больше 2, живых не больше 1, только эхо.
const QUIET_NIGHTS: int = 2
const QUIET_BUDGET_CAP: float = 2.0
const QUIET_ALIVE_CAP: int = 1
const CAP_BASE: int = 1                ## живых ночью: CAP_BASE + T, не больше CAP_MAX
const CAP_MAX: int = 10
const SPAWN_INTERVAL_MAX: float = 7.0
const SPAWN_INTERVAL_MIN: float = 2.5
const SPAWN_INTERVAL_PER_T: float = 0.5
const VENT_TELEGRAPH: float = 2.0      ## с от «пара из вентиляции» до появления
const BLACK_BOX_CHANCE: float = 0.25
const MAX_PHANTOMS: int = 16           ## поднято с 12 после замера freeze_probe в #27
# --- Бесконечная игра (ADR-005 § 6.4, #174) ---
## Доля начальной переписи, которую руда возвращает за рассвет (уголь ≈ 42 клетки).
const ORE_REGROW_RATE: float = 0.01
## Ближе к поверхности руда не растёт: только глубже стольких клеток, в тумане.
const ORE_REGROW_MIN_DEPTH: int = 10
## Тень при смерти отдаёт уголь (ела топливо; горелки ещё нет — #164).
const SHADE_DROP_COAL: int = 2
## Мотылёк роя при смерти отдаёт медную руду.
const SWARM_DROP_COPPER: int = 1

# ------------------------------------------ § 4.5 Враги: поведение типов (#27)
const SWARM_SEEK_PX: float = 300.0     ## рой видит горящую горелку в этом радиусе
const SWARM_PACK_SPREAD: int = 1       ## стая = pack ± это число (4–6)
const SHADE_SEEK_PX: float = 640.0     ## тень чует горящую горелку в этом радиусе
const SHADE_DRAIN_PERIOD: float = 3.0  ## тень у горелки сжигает одну единицу топлива за столько секунд
const BURROWER_DIG_PERIOD: float = 0.6 ## копатель роет 1 клетку за столько секунд
const BURROWER_HUNT_PX: float = 600.0  ## копатель чует игрока сквозь породу
const DOPPEL_GAZE_PX: float = 200.0    ## двойник замирает под взглядом ближе этого
## Пауза между ударами фантома по машине, с. Было 0.8 (калибровка #33): стая из
## 5–6 особей сносила машину за секунду — турели не успевали ответить.
const MACHINE_HIT_PERIOD: float = 2.0
const BLACK_BOX_CRYSTALS: int = 2      ## кристаллов за чёрный ящик (ADR-005 § 7, #169)
const VENT_SPAWN_COUNT: int = 3        ## из скольких ближайших вентиляций спавн
const VENT_SPAWN_MIN_PX: float = 160.0 ## ближе к игроку вентиляция не «выдыхает»
## Дальше — спавн в пещере, как раньше. Было 1600 (калибровка #33): стая из
## вентиляции за ~80 клеток видела базу, но не находила к ней пути и всю ночь
## висела в пещере — ночь 3 без обороны не стоила базе ни одной машины.
const VENT_SPAWN_MAX_PX: float = 1000.0

# --------------------------------------------------- чертежи (ADR-005 § 7.1, #169)
## Девять терминалов выдают чертежи по этому списку, в порядке прочтения — какой
## терминал ни найди. Имена предметов строками: тех, кого ещё нет в IDs.I (их
## заводят C*, E2, F1), в списке пока нет — Game.blueprint_order их пропускает
## с push_warning, и после слияния список заработает целиком без правок здесь.
const BLUEPRINT_ORDER: Array = [
	"MIXER", "PHAROS", "COLLECTOR", "ACCUMULATOR", "STEEL_WALL",
	"VENT_GRATE", "SIREN", "LENS", "RAINBOW_CORE",
]
## Подарок терминала: 2–3 вида из этого набора, числа — [мин, макс] на вид.
## Роль места (капитан, инженер, …) выбирает, какие виды, как у тайников руин.
const TERMINAL_GIFT_POOL: Array = [
	[IDs.I.COAL, 4, 8],
	[IDs.I.GLASS, 2, 4],
	[IDs.I.COPPER_INGOT, 2, 4],
	[IDs.I.IRON_INGOT, 1, 3],
	[IDs.I.CRYSTAL, 1, 2],
]
const TERMINAL_GIFT_MIN: int = 2
const TERMINAL_GIFT_MAX: int = 3

# ---------------------------------------------------------------- § 4.7 Релей
## Релей до F1 (#175). Пластины и антенна — legacy: при загрузке станут слитками.
## Числа не меняем здесь — требование переписывает F1.
const RELAY_REQ: Dictionary = {
	IDs.I.IRON_PLATE: 48,
	IDs.I.STEEL_PLATE: 24,
	IDs.I.CIRCUIT: 24,
	IDs.I.POWER_CELL: 12,
	IDs.I.RELAY_ANTENNA: 1,
}
const RELAY_TIME: float = 180.0        ## удержание сигнала, этап 6 (#175, #212)
const RELAY_HOLD_CAP: int = 10         ## живых фантомов во время удержания сигнала
## Цена запуска ядра в свободной игре (#212, ADR-005 § 6.3–6.4).
## Белый луч коллектора не заменяет шахту: до E нужно накопать руду и пережить ночь.
## 12 клеток — уголь с 4-й, медь с 8-й, не поверхность (хлам и глина не считаются).
const FREE_ORE_NEED: int = 12
const FREE_NIGHTS_NEED: int = 1
## Радужное ядро (#175): дороже правила 15 с — работает вечно и это цель игры
## (ADR-005 § 1.2, § 6.3). 4 жел. слитка + 3 кристалла ≈ 29 с копки.
const CORE_HP: float = 300.0

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
## Снятые предметы (пластины, панели, буры) в новый тайник не кладём (#170).
const SKY_LOOT: Dictionary = {
	IDs.I.IRON_INGOT: [2, 4],
	IDs.I.COPPER_INGOT: [2, 4],
	IDs.I.GLASS: [2, 4],
	IDs.I.CRYSTAL: [3, 6],
	IDs.I.COAL: [4, 8],
	IDs.I.COLLECTOR: [1, 1],
	IDs.I.PHAROS: [1, 1],
	IDs.I.BURNER: [1, 1],
}

# ---------------------------------------- ADR-002 Сеть и кооператив (docs/adr/0002-multiplayer.md)
## Секция зарезервирована MP-A (#86, § 9.2). Транспортные числа (порты, частоты,
## таймауты) — константы Net, а не Balance: калибровочный PR (MP-K) их не трогает.
const MP_MAX_PLAYERS: int = 4                ## хост + 3 клиента (§ 4.1)
const MP_BUDGET_PER_PLAYER: float = 0.5      ## бюджет ночи × (1 + k·(N−1)) (§ 4.7)
const MP_CAP_PER_PLAYER: int = 2             ## + к cap за каждого игрока сверх первого, не выше MAX_PHANTOMS
const MP_INTERVAL_PER_PLAYER: float = 0.35   ## интервал спавна ÷ (1 + k·(N−1))
const MP_SPAWN_INTERVAL_MIN: float = 1.5     ## нижняя граница интервала в сети, с
const MP_RESPAWN_DELAY: float = 15.0         ## респаун в сети без сдвига времени, с
const MP_BAG_OWNER_LOCK: float = 120.0       ## мешок поднимает только владелец, с
const MP_RELAY_HOLD_RADIUS_TILES: float = 12.0 ## отсчёт релея идёт, пока герой ближе
const MP_TEAM_RADIO_TILES: float = 20.0      ## товарищ на миникарте без питания ближе этого
const MP_ROLLCALL_COOLDOWN: float = 20.0     ## перекличка (G), с
## Было 4 (калибровка MP-K, #96): окно ответа NetTeam.ANSWER_WINDOW = 6 с, и у ответившего
## в первые 2 с огонёк гас раньше конца переклички — 17–28 % окна настоящий товарищ горел
## красным, как двойник (mp_balance_doppel). Огонёк не короче окна — ложного красного нет.
const MP_ROLLCALL_LIGHT: float = 6.0         ## зелёный огонёк ответившего, с
const MP_DOPPEL_REVEAL: float = 1.5          ## двойник «глючит» после удара, с
const MP_FRIENDLY_SLASH_CD: float = 1.0      ## кулдаун удара по своему, с
## Требование релея от N (#139; ADR-002 § 8 вопрос 3): RELAY_REQ × (1 + k·(N−1)),
## по детали — до целого. Зонд MP-K оценил первую победу вчетвером в 29.4 мин при цели
## 30–45: вчетвером копают вчетверо быстрее, а сырья релея нужно столько же.
const MP_RELAY_REQ_PER_PLAYER: float = 0.25
