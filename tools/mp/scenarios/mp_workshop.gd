extends "res://tools/mp/scenarios/mp_threat_base.gd"
## ADR-006 D1. В зоне одного клиента восемь коллекторов и восемь грядок.
## У четырёх лотков стоят прессы. Замер включает выпуск и передачу партии.

const ROWS: int = 8
var frames := PackedInt64Array()
var recording: bool = false


func _process(_dt: float) -> void:
	if recording:
		frames.append(Time.get_ticks_usec())


func run_host() -> void:
	ok("клиент вошёл", await wait_players(2, 40.0))
	await barrier("start")
	Game.time_of_day = 0.3
	var beds: Array[SporeBed] = []
	var presses: Array[Press] = []
	var collectors: Array[Collector] = []
	for row in ROWS:
		var c := World.beacon_cell + Vector2i(-16 + row * 4, -5)
		for y in range(c.y + 1):
			World.set_tile(c.x, y, IDs.T.AIR)
		for dx in range(1, 4):
			World.set_tile(c.x + dx, c.y, IDs.T.AIR)
		if MachineBase.place_machine("Collector", c):
			collectors.append(World.machines[c])
		var at := c + Vector2i(2, 0)
		if MachineBase.place_machine("SporeBed", at):
			beds.append(World.machines[at])
		if row % 2 == 0 and MachineBase.place_machine("Press", at + Vector2i.RIGHT):
			var press: Press = World.machines[at + Vector2i.RIGHT]
			press.dir = 2
			presses.append(press)
	ok("20 устройств", collectors.size() + beds.size() + presses.size() == 20)
	await wait(1.0)
	var bytes0: int = sent_total()
	var start: int = Time.get_ticks_usec()
	recording = true
	await wait(Balance.SPORE_BED_SECONDS * Balance.PRESS_FIBER_IN + Balance.PRESS_SECONDS + 2.0)
	recording = false
	var secs := float(Time.get_ticks_usec() - start) / 1000000.0
	var rate := float(sent_total() - bytes0) / secs
	var stats := frame_stats(frames)
	var growing := 0
	var producing := 0
	for bed in beds:
		if bed.lit and bed.made >= Balance.PRESS_FIBER_IN:
			growing += 1
	for press in presses:
		if press.out_buf >= Balance.PRESS_PANEL_OUT:
			producing += 1
	ok("реальный белый луч и выпуск во всех линиях", growing == ROWS and producing == ROWS / 2)
	print("  ЗАМЕР мастерская: 20 устройств, %d кадров, %.1f с, p95 %.0f мкс, максимум %.0f мкс, хост → клиент %.0f Б/с" % [
			stats.n, secs, stats.p95 * 1000, stats.max * 1000, rate])
	ok("кадр хоста p95 ≤ 16 мс", stats.n > 60 and stats.p95 <= 16.0)
	ok("полезная нагрузка хоста ≤ 12 КБ/с", rate > 0 and rate <= 12000.0)
	await barrier("done", -1, 60.0)
	finish()


func run_client(_i: int) -> void:
	await barrier("start")
	var bytes0 := sent_total()
	var start := Time.get_ticks_usec()
	var at := World.beacon_cell + Vector2i(-13, -5)
	ok("панели появились у клиента", await wait_until(func() -> bool:
		var press := World.machines.get(at) as Press
		return press != null and press.out_buf >= Balance.PRESS_PANEL_OUT, 55.0))
	await barrier("done", -1, 60.0)
	var secs := float(Time.get_ticks_usec() - start) / 1000000.0
	var rate := float(sent_total() - bytes0) / secs
	print("  ЗАМЕР мастерская: клиент → хост %.0f Б/с" % rate)
	ok("полезная нагрузка клиента ≤ 4 КБ/с", rate > 0 and rate <= 4000.0)
	finish()


static func sent_total() -> int:
	var total := 0
	for count in Net.sent_bytes.values():
		total += int(count)
	return total
