class_name LightLayout
extends RefCounted
## Подвал глав «Свет» 3–4 (ADR-005 § 9, #178).
##
## Комната 6×4 под полом лагеря, вход сбоку — не из ствола шахты (SHAFT_* слева).
## Пол лагеря на сиде 31337 — сталь x 312..336, ряд beacon.y+1. Луч идёт вниз
## от входа и поворачивает в комнату зеркалом: прямой ход горелки комнату не видит.
##
## Клетки — смещения от релея (World.beacon_cell). Главы и сценарий берут их отсюда,
## чтобы не разъехаться.

## Горелка лагеря на ряд выше пола: носик вниз, луч не упирается в сталь.
const BURNER: Vector2i = Vector2i(6, -1)
## Вход подвала: клетка пола, куда смотрит карточка «до входа».
const DOOR: Vector2i = Vector2i(6, 1)
## Зеркало у поворота: вниз → вправо, в комнату.
const CORNER: Vector2i = Vector2i(6, 5)
## Клетка комнаты, по которой глава считает «подвал освещён».
const CELLAR: Vector2i = Vector2i(9, 5)
## Сундук-находка в дальнем углу комнаты.
const CACHE: Vector2i = Vector2i(10, 5)
## Второе зеркало набора — на полке у входа, пока не понадобится.
const SPARE: Vector2i = Vector2i(4, -2)
## Глава 4: вторая горелка (зелёная), смеситель, маяк, зеркало сведения.
## Всё на одном ряду над полом: пол стальной, луч сквозь него не идёт.
const BURNER_G: Vector2i = Vector2i(0, -1)
const MIXER: Vector2i = Vector2i(4, -1)
const MIRROR4: Vector2i = Vector2i(6, -3)
const PHAROS: Vector2i = Vector2i(6, -1)
## Клетка жёлтого на выходе (первая после смесителя, до маяка).
const MIX_OUT: Vector2i = Vector2i(5, -1)
## Красная горелка: бьёт влево, в зеркало над выходом.
const BURNER_R: Vector2i = Vector2i(9, -3)

const ROOM_X0: int = 7
const ROOM_X1: int = 12
const ROOM_Y0: int = 4
const ROOM_Y1: int = 7


static func at(off: Vector2i) -> Vector2i:
	return World.beacon_cell + off


static func world_at(off: Vector2i) -> Vector2:
	return World.cell_to_world(at(off))


## Вырыть подвал: колодец от пола и комната 6×4. Пол и стены — сталь.
## Возвращает сундук-находку.
static func dig_cellar(items: Array) -> Chest:
	var b: Vector2i = World.beacon_cell
	var fl: int = CampaignBase.floor_row()
	# Колодец входа: две клетки под полом, рядом со стволом не пересекается.
	CampaignBase.fill(b.x + DOOR.x, fl, b.x + DOOR.x, fl + 2, IDs.T.AIR)
	# Комната 6×4 (x 7..12, y 4..7 от релея): воздух, стальной пол и потолок.
	var x0: int = b.x + ROOM_X0
	var x1: int = b.x + ROOM_X1
	var y0: int = b.y + ROOM_Y0
	var y1: int = b.y + ROOM_Y1
	CampaignBase.fill(x0 - 1, y0 - 1, x1 + 1, y1 + 1, IDs.T.STEEL)
	CampaignBase.fill(x0, y0, x1, y1, IDs.T.AIR)
	# Проход из колодца в комнату.
	CampaignBase.fill(b.x + DOOR.x, fl + 1, b.x + CORNER.x, b.y + CORNER.y, IDs.T.AIR)
	var chest: Chest = CampaignBase.put("Chest", at(CACHE), {"items": items}) as Chest
	return chest
