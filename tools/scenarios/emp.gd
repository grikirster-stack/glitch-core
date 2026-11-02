extends ScenarioBase
## Импульс: Q рядом с фантомом → фантом оглушён и получает урон.

func run() -> void:
	stand_in_corridor()
	await wait(0.3)
	var dir: Vector2 = clear_direction(80.0)
	var ph: Node = spawn_phantom_at(player.global_position + dir * 80.0)
	ok("фантом создан рядом", ph != null)
	if ph == null:
		finish()
		return
	await wait(0.3)
	var hp0: float = ph.hp
	var stun0: float = ph.stun

	# Жмём Q — импульс.
	hold(KEY_Q)
	await wait(0.35)
	release(KEY_Q)
	ok("фантом оглушён", ph.stun > stun0, "оглушение %.1f с" % ph.stun)
	ok("фантом получил урон от импульса", ph.hp < hp0, "hp %.0f → %.0f" % [hp0, ph.hp])
	ok("импульс потрачен", player.emp_cd > 0.0, "перезарядка %.1f с" % player.emp_cd)
	finish()
