class_name IDs
## Глобальные идентификаторы тайлов и предметов.
##
## Новые значения добавляются только в конец перечислений: id тайлов лежат
## в PackedByteArray мира, id предметов — в инвентарях и рецептах, их сдвиг
## ломает сохранения и тесты. Резерв под ADR-001 (#24) помечен ниже.

enum T {
	AIR,
	STONE,
	DIRT,
	GRASS,
	SAND,
	SANDSTONE,
	LOG,
	LEAVES,
	COPPER_ORE,
	IRON_ORE,
	CRYSTAL_ORE,
	COAL_ORE,
	SCRAP_ORE,
	WATER,
	LAVA,
	BEDROCK,
	STEEL,
	PANEL,
	TERMINAL,
	GLASS,
	COPPER_BLOCK,
	IRON_BLOCK,
	CRYSTAL_BLOCK,
	LIGHT_CRYSTAL,
	MOSS,
	RELAY_CORE,
	TREE,          ## Ствол дерева: выглядит как бревно, но проходим насквозь.
	# --- ADR-001, § 4.4: оборона базы ---
	STEEL_WALL,    ## Стальная стена: копатель её не роет (#31).
	AIRLOCK,       ## Шлюз закрыт: стена для всех.
	AIRLOCK_OPEN,  ## Шлюз открыт: игрок проходит, в A* по-прежнему стена (#31).
	VENT_GRATE,    ## Решётка на клетке вентиляции: спавн из неё закрыт (#31).
}

enum I {
	NONE,
	# Сырьё
	COPPER_ORE,
	IRON_ORE,
	CRYSTAL,
	COAL,
	SCRAP,
	SAND,
	LOG,
	STONE,
	# Промежуточные
	COPPER_INGOT,
	IRON_INGOT,
	GLASS,
	# Компоненты
	COPPER_PLATE,
	IRON_PLATE,
	CIRCUIT,
	STEEL_PLATE,
	POWER_CELL,
	# Постройки
	DRILL,
	SMELTER,
	ASSEMBLER,
	BELT,
	CHEST,
	COAL_GEN,
	SOLAR,
	LAMP,
	# Блоки-строительный материал
	COPPER_BLOCK,
	IRON_BLOCK,
	CRYSTAL_BLOCK,
	# --- ADR-001: автоматизация (§ 4.2), оборона (§ 4.4), релей (§ 4.7), лор (§ 4.9) ---
	INSERTER,      ## Манипулятор: переносит предметы между соседними клетками (#30).
	ANALYZER,      ## Анализатор: кристалл → данные (#30).
	TURRET,        ## Турель-разрядник (#31).
	FLOODLIGHT,    ## Прожектор: яркий свет от сети (#31).
	STEEL_WALL,    ## Стальная стена, тайл (#31).
	AIRLOCK,       ## Шлюз, тайл (#31).
	VENT_GRATE,    ## Решётка вентиляции, тайл (#31).
	DEEP_DRILL,    ## Глубинный бур (#30).
	RELAY_ANTENNA, ## Антенна релея — последняя деталь ядра (#32).
	BLACK_BOX,     ## Чёрный ящик: выпадает из фантома, даёт данные и обрывок журнала (#27, #28).
	LOOT_BAG,      ## Мешок: хотбар погибшего игрока лежит на месте смерти (#29).
}

const TILE_COUNT := T.VENT_GRATE + 1
