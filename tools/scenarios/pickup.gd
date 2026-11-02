extends ScenarioBase
## Подбор: подойти к выпавшему предмету → он исчез, инвентарь пополнился.
##
## Предмет кладём тем же путём, каким его роняет разрушенный тайл
## (player.spawn_item), но далеко от героя — чтобы пришлось реально дойти.

func run() -> void:
	var base: int = stand_in_corridor()
	await wait(0.4)
	var bx: int = World.beacon_cell.x
	var item_id: int = IDs.I.SCRAP
	var before: int = player.inv.count_of(item_id)

	# Предмет падает на пол коридора, далеко от героя.
	var pos: Vector2 = Vector2(float((bx + 9) * World.TILE) + 8.0, float(base * World.TILE) - 12.0)
	player.spawn_item(item_id, 1, pos)
	await wait(0.2)
	var on_floor: bool = false
	for n in scene.get_children():
		if n is ItemEntity and n.item_id == item_id:
			on_floor = true
			break
	ok("предмент лежит на земле", on_floor, DB.item_name(item_id))

	# Идём к предмету.
	var x0: float = player.global_position.x
	hold(KEY_D)
	var t0: int = Time.get_ticks_msec()
	var picked: bool = false
	while Time.get_ticks_msec() - t0 < 8000:
		if player.inv.count_of(item_id) > before:
			picked = true
			break
		await wait(0.05)
	release_all()
	ok("герой подошёл к предмету", player.global_position.x > x0 + 30.0,
			"%.1f → %.1f px" % [x0, player.global_position.x])
	ok("предмет подобран", picked)
	ok("инвентарь пополнился", player.inv.count_of(item_id) > before,
			"%d → %d" % [before, player.inv.count_of(item_id)])

	# Предмет исчез с земли.
	await wait(0.3)
	var left: bool = false
	for n in scene.get_children():
		if n is ItemEntity and n.item_id == item_id:
			left = true
			break
	ok("предмет исчез с земли", not left)
	finish()
