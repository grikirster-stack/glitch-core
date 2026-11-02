extends ScenarioBase
## Шум: бег (Shift) → шум растёт; стоя → падает; ходьба → тише бега.

func run() -> void:
	stand_in_corridor(5)
	await wait(0.6)
	ok("в покое шума нет", player.noise < 5.0, "%.1f" % player.noise)

	# Ходьба: шум набирается до «шагов» (14).
	var walk_peak: float = 0.0
	hold(KEY_D)
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 700:
		walk_peak = maxf(walk_peak, player.noise)
		await wait(0.03)
	release_all()
	ok("ходьба шумит", walk_peak > 5.0, "пик %.1f" % walk_peak)

	# Стоим — шум стихает.
	await wait(1.3)
	ok("в покое шум стихает", player.noise < 5.0, "%.1f" % player.noise)

	# Бег: громче ходьбы.
	var run_peak: float = 0.0
	hold(KEY_SHIFT)
	hold(KEY_A)
	var t1: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 700:
		run_peak = maxf(run_peak, player.noise)
		await wait(0.03)
	release_all()
	ok("бег громче ходьбы", run_peak > walk_peak + 5.0,
			"ходьба %.1f, бег %.1f" % [walk_peak, run_peak])
	ok("бег выдаёт героя", run_peak > 28.0, "%.1f" % run_peak)
	finish()
