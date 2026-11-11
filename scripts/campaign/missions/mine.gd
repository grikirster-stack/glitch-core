extends Mission
## Глава 3 «Шахта»: к западу от базы — ствол до пещеры, внизу штольня с двумя
## глубинными бурами на одной ТЭЦ. Учит: спуск и подъём по стволу, бюджет мощности
## и перегруз сети, глубинный бур, ручную добычу кристаллов, анализатор (кристалл сгорает).

const ORE: int = 20
const CRYSTALS: int = 6

var b: Dictionary = {}
var _burned0: int = 0


func _init() -> void:
	id = "mine"
	chapter = 3
	title = "Шахта"
	brief = "Жила под цехом выработана. Ствол у западного края базы уходит на сорок клеток вниз — к пещере и руде."
	teaches = "спуск по стволу, мощность и перегруз, глубинный бур, кристаллы, анализатор"
	hold_time = 0.5


func build() -> void:
	b = CampaignBase.build(CampaignBase.Tier.MINE)
	(b["mine_supply"] as Chest).receive_item(IDs.I.COAL_GEN, 1)
	(b["mine_supply"] as Chest).receive_item(IDs.I.COAL, 12)
	var bx: int = World.beacon_cell.x
	b["analyzer"] = CampaignBase.put("Analyzer", Vector2i(bx + 4, World.beacon_cell.y))


func kit() -> Array:
	return [[IDs.I.COAL, 8], [IDs.I.LAMP, 4], [IDs.I.SCRAP, 10]]


func stages() -> Array:
	return [
		{"title": "Спуск", "hint": "Ствол — слева от базы, за вентиляцией · вниз — по центру · наверх — с разбега к центру и прыжок",
			"say": ["Ствол шахты — у западного края базы. Сорок клеток вниз, на дне — штольня.",
					"Вниз — просто по центру, внизу мягко. Наверх — по уступам: сходите с уступа к центру и сразу прыгайте."],
			"goals": [["Спуститься в штольню", func() -> Vector2i: return flag(_deepest() >= CampaignBase.mine_row() - 2)]]},
		{"title": "Перегруз", "hint": "Сундук снабжения в штольне: ТЭЦ и уголь · ПКМ — поставить, E с углём — топка · P — радиусы",
			"say": ["Слышите, как буры захлёбываются? Два глубинных бура тянут 8, ТЭЦ даёт 6. Сеть в перегрузе — всё медленнее.",
					"В сундуке снабжения в штольне — вторая ТЭЦ. Поставьте её у буров."],
			"goals": [["Перегруза нет, буры на полной мощности", func() -> Vector2i: return flag(_drills_full())]]},
		{"title": "Добыча", "hint": "Буры кладут руду в сундук между ними",
			"say": ["Теперь глубинные буры работают в полную силу: сорок клеток вглубь, железо и медь."],
			"goals": [["Руды в сундуке добычи", func() -> Vector2i:
				return Vector2i(chest_has(b["mine_chest"], IDs.I.IRON_ORE) + chest_has(b["mine_chest"], IDs.I.COPPER_ORE), ORE)]]},
		{"title": "Кристаллы", "hint": "Светящиеся ниши в стенах ствола · ЛКМ — копать (кристалл твёрдый, держите дольше)",
			"say": ["В стенах ствола — ниши с кристаллами глитча, они светятся."],
			"goals": [["Кристаллов с собой", func() -> Vector2i: return Vector2i(heroes_have(IDs.I.CRYSTAL), CRYSTALS)]]},
		{"title": "Анализатор", "hint": "Анализатор — справа от релей-ядра · E с кристаллами в руке — загрузить",
			"say": ["Наверх, к релею. Справа от ядра — анализатор: кристалл в нём сгорает. Чертежи теперь дают терминалы."],
			"enter": func() -> void: _burned0 = int(b["analyzer"].produced),
			"goals": [["Кристалл сожжён анализатором", func() -> Vector2i: return Vector2i(int(b["analyzer"].produced) - _burned0, 1)]]},
	]


func outro() -> String:
	return "Шахта дышит: буры гудят на дне, анализатор щёлкает у релея.\n" \
			+ "ПЁС: «Чем громче база, тем лучше её слышно. Фантомы считают генераторы и свет. Сегодня ночью они придут все.»"


## Самый глубокий ряд, где стоит живой герой.
func _deepest() -> int:
	var d: int = -1
	for h in heroes():
		d = maxi(d, World.world_to_cell(h.global_position).y)
	return d


func _drills_full() -> bool:
	if Game.brownout:
		return false
	for k in ["deep1", "deep2"]:
		var m = b.get(k)
		if m == null or not is_instance_valid(m) or not m.powered or float(m.efficiency) < 0.99:
			return false
	return true
