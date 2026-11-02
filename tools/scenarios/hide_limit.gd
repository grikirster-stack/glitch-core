extends "res://tools/scenarios/hide.gd"
## Лимит укрытия (ADR-001 § 4.8, #29): в вентиляции не дольше Balance.HIDE_MAX —
## hide_timer тикает, через 6 с вентиляция выталкивает героя. Повторно залезть
## нельзя ещё Balance.HIDE_COOLDOWN (10 с); после кулдауна — снова можно.
## Кулдаун проматываем ускорением времени (Engine.time_scale).

const TIME_SCALE: float = 5.0


func run() -> void:
	var vent: Vector2i = World.vents[0]
	stand_vent(vent)
	await wait(0.3)
	var dvent: float = World.cell_to_world(vent).distance_to(player.global_position)
	ok("герой у вентиляции", dvent < 40.0, "%.0f px" % dvent)

	ok("герой спрятался по клавише V", await _tap_v() and player.hiding)
	var t0: float = now()
	var timer0: float = player.hide_timer
	await wait(1.0)
	ok("hide_timer тикает", player.hide_timer < timer0 - 0.5,
			"%.2f → %.2f с" % [timer0, player.hide_timer])
	var out: bool = await wait_until(func() -> bool: return not player.hiding, Balance.HIDE_MAX + 3.0)
	var secs: float = now() - t0
	ok("вентиляция вытолкнула героя", out, "%.2f с" % secs)
	ok("вылез через %.0f с" % Balance.HIDE_MAX, absf(secs - Balance.HIDE_MAX) < 0.6, "%.2f с" % secs)
	ok("после выхода неуязвимость не бессрочная", player.invuln <= 0.6, "%.2f с" % player.invuln)
	ok("кулдаун укрытия пошёл", player.hide_cd > Balance.HIDE_COOLDOWN - 0.5, "%.2f с" % player.hide_cd)

	# Сразу назад нельзя.
	await _tap_v()
	ok("повторно сразу — нельзя", not player.hiding, "кулдаун %.1f с" % player.hide_cd)

	# Через кулдаун — можно.
	Engine.time_scale = TIME_SCALE
	var cooled: bool = await wait_until(func() -> bool: return player.hide_cd <= 0.0,
			Balance.HIDE_COOLDOWN * 2.0)   # игровые секунды (wait_until идёт по игровым часам)
	Engine.time_scale = 1.0
	ok("кулдаун %.0f с прошёл" % Balance.HIDE_COOLDOWN, cooled, "%.2f с" % player.hide_cd)
	ok("после кулдауна снова можно спрятаться", await _tap_v() and player.hiding)
	# Сам вышел — тоже кулдаун.
	await _tap_v()
	ok("вышел по V", not player.hiding)
	ok("выход по V тоже запускает кулдаун", player.hide_cd > 0.0, "%.2f с" % player.hide_cd)
	finish()


## Короткое нажатие V (укрытие переключается по фронту). true — состояние сменилось.
func _tap_v() -> bool:
	var was: bool = player.hiding
	hold(KEY_V)
	await wait(0.15)
	release(KEY_V)
	await wait(0.1)
	return player.hiding != was
