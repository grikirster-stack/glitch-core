extends ScenarioBase
## Общая часть сценариев кампании (ADR-004): мир сида Campaign.SEED на время сценария,
## глава в сцене, директор угрозы — вручную (в --scenario он молчит, а волны глав
## телеграфируют через Threat.tick).

var mission: Mission = null
## Вести Threat.tick из сценария (телеграфы волн главы).
var drive_threat: bool = false
var _seed0: int = 0


func _process(delta: float) -> void:
	if drive_threat and Game.state == Game.State.PLAYING:
		Threat.tick(delta)


## Свежий мир кампании и глава id (как main.gd: база, время, первый этап, набор).
func start_chapter(id: String) -> Mission:
	end_chapter()
	if _seed0 == 0:
		_seed0 = int(scene.get("seed_value"))
	scene.set("seed_value", Campaign.SEED)
	runner._reset_world()
	for i in player.inv.slots.size():
		player.inv.slots[i] = ItemStack.new()
	player.invuln = 1.0e9
	mission = Campaign.start(scene, id)
	if mission != null:
		mission.give_kit(player)
	return mission


## Убрать главу из сцены (до следующей или в конце сценария).
func end_chapter() -> void:
	drive_threat = false
	if mission != null and is_instance_valid(mission):
		mission.get_parent().remove_child(mission)
		mission.free()
	mission = null
	Game.mission = null
	var es = scene.get("end_screen")
	if es != null:
		es.hide_end()


## Конец сценария: глава прочь, сид сцены назад (следующий сценарий — на своём мире).
func finish() -> void:
	end_chapter()
	release_all()
	if _seed0 != 0:
		scene.set("seed_value", _seed0)
	super()


## Ждать, пока глава не перейдёт на этап st (или не кончится).
func wait_stage(st: int, timeout: float) -> bool:
	return await wait_until(func() -> bool:
		return mission.stage >= st or mission.result != Mission.Result.RUNNING, timeout)


## Поставить постройку в клетку рядом с базой (как игрок — в пустую клетку).
func build_at(kind: String, c: Vector2i, opts: Dictionary = {}) -> MachineBase:
	return CampaignBase.put(kind, c, opts)
