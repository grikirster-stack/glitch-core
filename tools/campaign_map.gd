extends RefCounted
class_name CampaignMap
## ASCII-карта окрестностей базы — чтобы проектировать базы глав кампании по клеткам.
##
## Запуск (мир генерируется по сиду; с --mission=<id> — ещё и база главы поверх):
##   godot --headless --path . -- --map-dump --seed=31337 [--mission=siege] [--map-rect=x0,y0,x1,y1]
## Без --map-rect — от релея: 40 клеток влево и вправо, 6 вверх, 50 вниз от поверхности.
## Флаг разбирает scripts/main.gd: карта печатается после генерации мира и выходит.

const CH: Dictionary = {
	IDs.T.AIR: " ", IDs.T.STONE: "#", IDs.T.DIRT: ":", IDs.T.GRASS: "\"", IDs.T.SAND: ".",
	IDs.T.SANDSTONE: "=", IDs.T.LOG: "|", IDs.T.LEAVES: "*", IDs.T.COPPER_ORE: "c",
	IDs.T.IRON_ORE: "i", IDs.T.CRYSTAL_ORE: "k", IDs.T.COAL_ORE: "o", IDs.T.SCRAP_ORE: "s",
	IDs.T.WATER: "~", IDs.T.LAVA: "^", IDs.T.BEDROCK: "B", IDs.T.STEEL: "_", IDs.T.PANEL: "p",
	IDs.T.TERMINAL: "T", IDs.T.GLASS: "g", IDs.T.COPPER_BLOCK: "C", IDs.T.IRON_BLOCK: "I",
	IDs.T.CRYSTAL_BLOCK: "K", IDs.T.LIGHT_CRYSTAL: "l", IDs.T.MOSS: ",", IDs.T.RELAY_CORE: "R",
	IDs.T.TREE: "!", IDs.T.STEEL_WALL: "W", IDs.T.AIRLOCK: "A", IDs.T.AIRLOCK_OPEN: "a",
	IDs.T.VENT_GRATE: "v",
}
## Постройки — заглавными поверх тайла.
const MCH: Dictionary = {
	"Drill": "D", "DeepDrill": "G", "Smelter": "S", "Assembler": "M", "Chest": "H",
	"CoalGen": "E", "Solar": "Z", "Belt": ">", "Inserter": "N", "Analyzer": "Y",
	"Turret": "X", "Floodlight": "F",
}


static func dump(args: PackedStringArray) -> void:
	var bx: int = World.beacon_cell.x
	var top: int = World.surface[bx]
	var r: Array = [bx - 40, top - 6, bx + 40, top + 50]
	for a in args:
		if a.begins_with("--map-rect="):
			var p: PackedStringArray = a.substr(11).split(",")
			if p.size() == 4:
				r = [int(p[0]), int(p[1]), int(p[2]), int(p[3])]
	print("== КАРТА · сид %d · релей (%d,%d) · x %d..%d · y %d..%d ==" % [World.world_seed,
			bx, World.beacon_cell.y, r[0], r[2], r[1], r[3]])
	var ruler: String = "     "
	for x in range(int(r[0]), int(r[2]) + 1):
		ruler += str(absi(x) % 10)
	print(ruler)
	for y in range(int(r[1]), int(r[3]) + 1):
		var row: String = "%4d " % y
		for x in range(int(r[0]), int(r[2]) + 1):
			var c: Vector2i = Vector2i(x, y)
			var m = World.machines.get(c)
			if m != null and is_instance_valid(m):
				row += String(MCH.get(String(m.kind), "?"))
			elif World.vents.has(c):
				row += "V"
			else:
				row += String(CH.get(World.get_tile(x, y), "?"))
		print(row)
	print("Вентиляции рядом: ", World.vents.filter(func(v: Vector2i) -> bool:
			return v.x >= int(r[0]) and v.x <= int(r[2]) and v.y >= int(r[1]) and v.y <= int(r[3])))
