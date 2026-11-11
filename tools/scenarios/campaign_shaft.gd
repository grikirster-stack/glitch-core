extends "res://tools/scenarios/campaign_common.gd"
## Ствол шахты кампании (ADR-004, CampaignBase.MINE) проходим на обычной механике, через
## шов ввода, как у человека: вниз — по центру проёма до пола штольни; наверх — по
## уступам: с разбега сойти с уступа к центру (над ним пусто) и прыгнуть в койот-тайм,
## у другой стены — следующий уступ на LEDGE_STEP рядов выше; с верхнего — на кромку
## стены к базе.

## На один уступ — не дольше, с.
const STEP_TIME: float = 2.5


func run() -> void:
	# Глава «Шахта» ушла с фабрикой (#170). Ствол (SHAFT_*) остался константами,
	# база его больше не строит — проходить нечего. Главы «Свет» ствол не вернут.
	if not Campaign.has("mine"):
		ok("глава «Шахта» снята вместе с фабрикой", true)
		ok("ствол оставлен константами, база его не строит", CampaignBase.SHAFT_DEPTH > 0
				and CampaignBase.LEDGE_STEP > 0 and not Campaign.CHAPTERS.has("mine"))
		finish()
		return
	if start_chapter("mine") == null:
		ok("глава «Шахта» создана", false)
		finish()
		return
	player.invuln = 1.0e9
	var bx: int = World.beacon_cell.x
	var sx0: int = bx + CampaignBase.SHAFT_X0
	var sx1: int = bx + CampaignBase.SHAFT_X1
	var mid: int = (sx0 + sx1) / 2
	var fl: int = CampaignBase.floor_row()
	var mrow: int = CampaignBase.mine_row()
	# Уступы сверху вниз: [ряд, клетка].
	var ledges: Array = []
	for y in range(fl + 1, mrow):
		for x in [sx0, sx1]:
			if World.get_tile(x, y) == IDs.T.STEEL:
				ledges.append([y, x])
	ok("уступы в стволе", ledges.size() >= 15, str(ledges.size()))
	var even: bool = true
	for i in range(1, ledges.size()):
		if int(ledges[i][0]) - int(ledges[i - 1][0]) != CampaignBase.LEDGE_STEP or int(ledges[i][1]) == int(ledges[i - 1][1]):
			even = false
	ok("через %d ряда, стены чередуются" % CampaignBase.LEDGE_STEP, even)
	var center_free: bool = true
	for y in range(fl - 1, mrow + 1):
		if World.is_solid_cell(Vector2i(mid, y)):
			center_free = false
	ok("центр проёма свободен до дна", center_free)

	# --- Вниз: по центру проёма.
	stand_at_cell(Vector2i(mid, fl - 2))
	player.global_position.x = float(mid * World.TILE) + 8.0
	var down: bool = await wait_until(func() -> bool:
		return player.on_ground and World.world_to_cell(player.global_position).y >= mrow - 1, 6.0)
	ok("спуск по центру до пола штольни", down, str(World.world_to_cell(player.global_position)))
	ok("спуск засчитан главой", await wait_stage(1, 2.0), str(mission.stage))

	# --- Вверх: с пола — прыжок к нижнему уступу, дальше — с разбега от уступа к уступу.
	var climbed: int = 0
	for i in range(ledges.size() - 1, -1, -1):
		if not await _hop(int(ledges[i][0]), int(ledges[i][1]) == sx0, i == ledges.size() - 1):
			break
		climbed += 1
	ok("подъём по всем уступам", climbed == ledges.size(), "%d из %d" % [climbed, ledges.size()])
	var out: bool = await _hop(fl, false, false)
	ok("с верхнего уступа — на кромку к базе", out, str(World.world_to_cell(player.global_position)))
	finish()


## К уступу ряда row у левой (left) или правой стены. from_floor — с пола (прыжок сразу),
## иначе — разбег: сойти со своего уступа к центру и прыгнуть в койот-тайм.
## true — герой стоит на нём.
func _hop(row: int, left: bool, from_floor: bool) -> bool:
	var key: int = KEY_A if left else KEY_D
	hold(key)
	if not from_floor:
		await wait_until(func() -> bool: return not player.on_ground, 1.0)
	hold(KEY_SPACE)
	var landed: bool = await wait_until(func() -> bool:
		return player.on_ground and World.world_to_cell(player.global_position).y <= row - 1, STEP_TIME)
	release(KEY_SPACE)
	release(key)
	await wait(0.25)
	if not landed:
		print("  прыжок к ряду %d не вышел: герой в %s" % [row, str(World.world_to_cell(player.global_position))])
	return landed
