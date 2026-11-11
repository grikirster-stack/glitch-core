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
	# Постройки (legacy + new from ADR-005)
	DRILL,         # legacy
	SMELTER,       # legacy
	ASSEMBLER,     # legacy
	BELT,
	CHEST,
	COAL_GEN,
	SOLAR,
	LAMP,
	COPPER_BLOCK,
	IRON_BLOCK,
	CRYSTAL_BLOCK,
	INSERTER,      # legacy
	ANALYZER,      # legacy
	TURRET,        # legacy
	FLOODLIGHT,    # legacy
	STEEL_WALL,
	AIRLOCK,
	VENT_GRATE,
	DEEP_DRILL,    # legacy
	RELAY_ANTENNA,
	BLACK_BOX,
	LOOT_BAG,
	# --- ADR-005: light constructor (BURNER..BEACON, BLUEPRINT for quick build) ---
	BURNER,
	MIRROR,
	MIXER,
	PRISM,
	COLLECTOR,
	ACCUMULATOR,
	BEACON,
	BLUEPRINT,
}

const TILE_COUNT := T.BEACON + 1
const ITEM_COUNT := I.BLUEPRINT + 1

# ADR-005 (light constructor, epic #182 / ADR-005 step 6): all T.* / I.* exported.
# New optical items appended. Legacy kept for save conversion (core/save.gd).
# ORE_PAL, recipes (hand only), _build_* now compile.
