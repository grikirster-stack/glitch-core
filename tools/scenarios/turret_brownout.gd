extends ScenarioBase
## Турель при браун-ауте (ADR-001 § 4.3–4.4, #31): скорострельность
## умножается на efficiency. ТЭЦ (6) + турель (2) + 5 анализаторов (по 2) —
## нагрузка 12, efficiency 0.5: эхо умирает примерно вдвое дольше, чем при
## полной мощности. Без питания турель молчит.

const Box = preload("res://tools/scenarios/turret_kills_echo.gd")
const BOX_W: int = 12
const BOX_H: int = 6
const ANALYZERS: int = 5

var _origin: Vector2i = Vector2i(-1, -1)


func run() -> void:
	player.invuln = 1.0e9
	_origin = Box.find_box_spot(self, BOX_W, BOX_H)
	ok("найдено тёмное место под землёй", _origin.x >= 0, str(_origin))
	if _origin.x < 0:
		finish()
		return
	var turret: Turret = Box.build_turret_box(self, _origin, BOX_W, BOX_H)
	ok("турель поставлена", turret != null)
	if turret == null:
		finish()
		return
	await wait_until(func(): return turret.powered and turret.efficiency >= 0.999, 2.0)
	var full: float = await _kill_time(turret)
	ok("при efficiency 1 эхо убито", full > 0.0, "%.2f с" % full)

	# Нагрузка: 5 анализаторов в верхнем ряду коробки → efficiency 0.5.
	for i in ANALYZERS:
		MachineBase.place_machine("Analyzer", _origin + Vector2i(4 + i, 2))
	var half: bool = await wait_until(func(): return absf(turret.efficiency - 0.5) < 0.01, 2.0)
	ok("браун-аут: efficiency турели 0.5", half, "eff=%.3f" % turret.efficiency)
	ok("браун-аут: флаг поднят", Game.brownout)
	var slow: float = await _kill_time(turret)
	var ratio: float = slow / maxf(full, 0.001)
	ok("при 0.5 турель убивает медленнее (≈ ×2)", slow > 0.0 and ratio >= 1.6 and ratio <= 2.4,
			"%.2f с против %.2f с, ×%.2f" % [slow, full, ratio])

	# Без питания — ни одного выстрела.
	var gen: CoalGen = World.machines.get(_origin + Vector2i(2, 3))
	gen.set_enabled(false)
	await wait_until(func(): return not turret.powered, 2.0)
	ok("ТЭЦ выключена — турель без питания", not turret.powered)
	var shots0: int = turret.shots
	var e: Node = spawn_phantom_at(_floor_pos(_origin + Vector2i(8, 3)), "echo")
	await wait(2.0)
	ok("без питания турель не стреляет", turret.shots == shots0, "выстрелов +%d" % (turret.shots - shots0))
	if e != null and is_instance_valid(e):
		e.get_parent().remove_child(e)
		e.queue_free()
	finish()


## Время от появления эха до его смерти (−1 — не умерло за 12 с).
func _kill_time(turret: Turret) -> float:
	# Дождаться полной перезарядки: первый выстрел — сразу при появлении цели.
	await wait(Balance.TURRET_PERIOD * 2.0 + 0.2)
	var echo: Node = spawn_phantom_at(_floor_pos(_origin + Vector2i(8, 3)), "echo")
	if echo == null:
		return -1.0
	var t0: int = Time.get_ticks_msec()
	var ref: WeakRef = weakref(echo)   # захват освобождённого узла в лямбде — ошибка движка
	var dead: bool = await wait_until(func(): return ref.get_ref() == null or not ref.get_ref().alive, 12.0)
	if not dead:
		return -1.0
	return float(Time.get_ticks_msec() - t0) / 1000.0


func _floor_pos(c: Vector2i) -> Vector2:
	return Vector2(float(c.x * World.TILE) + 8.0, float((c.y + 1) * World.TILE) - 12.0)
