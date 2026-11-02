extends ScenarioBase
## HUD в простое (issue #7): за 60 с простоя не появляется ни одного нового
## узла, а HUD, миникарта и небо не перерисовываются каждый кадр.
##
## Герой стоит в коридоре базы, ничего не нажимает. День (старт смены 0.30,
## за 60 с время доходит до ~0.55 — до сумерек далеко), волн фантомов в режиме
## сценария нет. Число узлов меряем всё время простоя — ловим и временные
## узлы, которые успели бы появиться и исчезнуть между замерами в начале и конце.

const IDLE_SEC: float = 60.0
## Перерисовки считаем на второй половине простоя: в начале ещё затухают
## уведомления и подсказка управления (первые 22 с смены).
const RATE_FROM_SEC: float = 30.0
## Потолки перерисовок в секунду в покое. Кадров в секунду — десятки и сотни,
## поэтому «каждый кадр» потолки не пройдёт ни на какой машине.
const HUD_MAX_HZ: float = 4.0
const MAP_MAX_HZ: float = 2.0
const SKY_MAX_HZ: float = 6.0


func run() -> void:
	stand_in_corridor(6)
	clear_input()
	await wait(1.0)
	var hud: HUD = UI.hud
	var sky: SkyBackdrop = null
	for c in scene.get_children():
		if c is SkyBackdrop:
			sky = c
	ok("HUD и небо на месте", hud != null and sky != null)
	if hud == null or sky == null:
		finish()
		return

	var nodes0: int = get_tree().get_node_count()
	var orphans0: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var nodes_max: int = nodes0
	var nodes_min: int = nodes0
	var t0: int = Time.get_ticks_msec()
	var rate_started: bool = false
	var r_hud: int = 0
	var r_map: int = 0
	var r_sky: int = 0
	var frames: int = 0
	var rate_t0: int = 0
	while Time.get_ticks_msec() - t0 < int(IDLE_SEC * 1000.0):
		await get_tree().process_frame
		var n: int = get_tree().get_node_count()
		nodes_max = maxi(nodes_max, n)
		nodes_min = mini(nodes_min, n)
		if not rate_started and Time.get_ticks_msec() - t0 >= int(RATE_FROM_SEC * 1000.0):
			rate_started = true
			rate_t0 = Time.get_ticks_msec()
			r_hud = hud.stat_redraws
			r_map = hud.stat_map_redraws
			r_sky = sky.stat_redraws
			frames = 0
		frames += 1
	var nodes1: int = get_tree().get_node_count()
	var orphans1: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var secs: float = maxf(0.001, float(Time.get_ticks_msec() - rate_t0) / 1000.0)
	var fps: float = float(frames) / secs

	ok("0 новых узлов за %.0f с простоя" % IDLE_SEC, nodes_max == nodes0 and nodes1 == nodes0,
			"узлов: в начале %d, в конце %d, максимум %d, минимум %d" % [nodes0, nodes1, nodes_max, nodes_min])
	ok("нет новых узлов-сирот", orphans1 <= orphans0, "%d → %d" % [orphans0, orphans1])

	var hz_hud: float = float(hud.stat_redraws - r_hud) / secs
	var hz_map: float = float(hud.stat_map_redraws - r_map) / secs
	var hz_sky: float = float(sky.stat_redraws - r_sky) / secs
	ok("HUD в покое не перерисовывается каждый кадр", hz_hud <= HUD_MAX_HZ,
			"%.2f раз/с при %.0f кадрах/с" % [hz_hud, fps])
	ok("миникарта в покое не перерисовывается", hz_map <= MAP_MAX_HZ,
			"%.2f раз/с, запеканий рельефа всего %d" % [hz_map, hud.stat_map_bakes])
	ok("небо днём не перерисовывается каждый кадр", hz_sky <= SKY_MAX_HZ,
			"%.2f раз/с" % hz_sky)
	finish()
