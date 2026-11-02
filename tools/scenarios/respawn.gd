extends ScenarioBase
## Смерть и респаун (ADR-001 § 4.8, #29): герой гибнет ночью у базы →
## экран «ТЕБЯ НАШЛИ» с эпитафией из Lore, хотбар падает мешком на месте смерти,
## основной инвентарь остаётся, Game.stats_deaths + 1. Через RESPAWN_DELAY —
## респаун в капсуле на базе, время у рассвета, новая смена. Мешок ждёт на месте
## и подбирается целиком. В конце — --hardcore: смерть заканчивает забег.


func run() -> void:
	stand_in_corridor(15)
	await wait(0.4)
	Game.time_of_day = 0.80                  # глубокая ночь
	var day0: int = Game.day_number
	var deaths0: int = Game.stats_deaths
	player.inv.slots[20] = ItemStack.new(IDs.I.STONE, 7)   # основной инвентарь
	var hot: Dictionary = {}
	for i in player.inv.hotbar_size:
		var s: ItemStack = player.inv.slots[i]
		if not s.is_empty():
			hot[s.id] = int(hot.get(s.id, 0)) + s.count
	ok("в хотбаре есть вещи", not hot.is_empty(), str(hot))
	var death_pos: Vector2 = player.global_position

	player.invuln = 0.0
	player.damage(Player.MAX_HP * 2.0, Vector2.ZERO)
	var t0: float = now_proc()   # респаун — SceneTreeTimer, он идёт по кадрам отрисовки
	await await_frame()
	ok("герой погиб", player.dead)
	ok("смерть посчитана", Game.stats_deaths == deaths0 + 1, "%d → %d" % [deaths0, Game.stats_deaths])
	ok("забег не окончен (не hardcore)", Game.state == Game.State.PLAYING, "state=%d" % Game.state)
	var es: EndScreen = scene.get("end_screen")
	ok("экран «ТЕБЯ НАШЛИ»", es.visible and es.title == "ТЕБЯ НАШЛИ", es.title)
	ok("эпитафия из Lore", es.subtitle != "" and es.respawn_delay > 0.0, es.subtitle)
	var hot_left: int = 0
	for i in player.inv.hotbar_size:
		hot_left += player.inv.slots[i].count
	ok("хотбар пуст", hot_left == 0, "осталось %d" % hot_left)
	ok("основной инвентарь остался", player.inv.count_of(IDs.I.STONE) == 7)

	await wait(1.5)
	var bag: ItemEntity = _find_bag()
	ok("мешок лежит на месте смерти", bag != null and bag.global_position.distance_to(death_pos) < 32.0,
			"%.0f px" % (bag.global_position.distance_to(death_pos) if bag != null else -1.0))
	if bag == null:
		finish()
		return
	ok("в мешке весь хотбар", _bag_dict(bag) == hot, str(bag.bag))
	ok("мешок не исчезает по сроку", not bag.despawn)
	ok("погибший герой мешок не подобрал", is_instance_valid(bag) and player.dead)

	var back: bool = await wait_until(func() -> bool: return not player.dead, Balance.RESPAWN_DELAY + 3.0)
	var secs: float = now_proc() - t0
	ok("респаун через %.0f с" % Balance.RESPAWN_DELAY, back and absf(secs - Balance.RESPAWN_DELAY) < 0.7,
			"%.2f с" % secs)
	ok("респаун на базе", player.global_position.distance_to(World.spawn_point) < 24.0,
			"%.0f px" % player.global_position.distance_to(World.spawn_point))
	ok("здоровье полное", player.hp >= Player.MAX_HP)
	ok("экран смерти скрыт", not es.visible)
	await wait(0.4)
	ok("время у рассвета", absf(Game.time_of_day - Balance.NIGHT_END) < 0.02,
			"t=%.3f (рассвет %.2f)" % [Game.time_of_day, Balance.NIGHT_END])
	ok("началась новая смена", Game.day_number == day0 + 1, "%d → %d" % [day0, Game.day_number])
	ok("мешок ждёт на месте", is_instance_valid(bag) and bag.global_position.distance_to(death_pos) < 32.0)

	# Вернуться к мешку — он подбирается целиком.
	player.global_position = bag.global_position + Vector2(-30.0, -4.0)
	player.vel = Vector2.ZERO
	var bag_id: int = bag.get_instance_id()
	var picked: bool = await wait_until(func() -> bool: return not is_instance_id_valid(bag_id), 4.0)
	ok("мешок подобран", picked)
	var got: bool = true
	for id in hot.keys():
		if player.inv.count_of(int(id)) < int(hot[id]):
			got = false
	ok("вещи из мешка вернулись в инвентарь", got)

	# --hardcore: смерть заканчивает забег, на экране эпитафия и итоги.
	scene.set("hardcore", true)
	player.invuln = 0.0
	player.damage(Player.MAX_HP * 2.0, Vector2.ZERO)
	await wait(0.2)
	scene.set("hardcore", false)
	ok("hardcore: забег окончен", Game.state == Game.State.DEAD, "state=%d" % Game.state)
	ok("hardcore: экран с эпитафией", es.visible and es.subtitle != "" and es.respawn_delay < 0.0, es.subtitle)
	ok("hardcore: смерти в итогах", es.stats.has("Смертей: %d" % (deaths0 + 2)), str(es.stats))
	finish()


func _find_bag() -> ItemEntity:
	for c in scene.get_children():
		if c is ItemEntity and not c.bag.is_empty():
			return c
	return null


func _bag_dict(bag: ItemEntity) -> Dictionary:
	var out: Dictionary = {}
	for e in bag.bag:
		out[int(e[0])] = int(out.get(int(e[0]), 0)) + int(e[1])
	return out
