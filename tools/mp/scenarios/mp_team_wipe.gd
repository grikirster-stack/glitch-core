extends "res://tools/mp/scenarios/mp_coop_base.gd"
## mp_team_wipe (ADR-002 § 4.7, § 4.9; решение #99; MP-I, #94): вся команда погибла.
##
##  * вайп: Аня погибла (личный отсчёт 15 с), следом хост — погибли все живые: правило
##    одиночной — через Balance.RESPAWN_DELAY оба на базе, часы к рассвету (новая смена);
##    у Ани экран переключился на отсчёт вайпа; на рассвете хост сохранил игру в слот
##    mp_<имя игры>_auto;
##  * --hardcore в сети: погибшая Аня — зритель до конца забега (и через 15 с мертва),
##    погиб хост — погибли все: забег окончен у всех (Game.State.DEAD), на экране итогов
##    у Ани — личная статистика команды (COOP STATS).

const WAIT: float = 6.0


# ------------------------------------------------------------------ ХОСТ

func run_host() -> void:
	ok("хост + клиент вошли", await wait_players(2, 45.0))
	ok("прокси клиента с вводом", await wait_proxies(1, 10.0))
	await barrier("in")
	var p0: Player = hero_of(0)
	var nc: NetCoop = coop()
	var es: EndScreen = end_screen()
	if p0 == null or nc == null:
		finish()
		return
	var slot: String = Save.net_auto_slot(String(Net.session.get("session_name", "")))
	Save.remove(slot)
	Game.time_of_day = 0.45          # день: до рассвета далеко, вайп сдвинет к нему
	var day0: int = Game.day_number
	await wait(0.3)

	# --- Вайп.
	kill(p0)
	await barrier("c_dead")
	ok("хост: Аня ждёт личного отсчёта, вайпа нет", nc.due.has(p0) and nc.wipe_left < 0.0)
	var t0: float = Game.game_time   # отсчёты NetCoop идут в _process — меряем теми же часами (часы забега)
	kill(player)
	ok("хост: погибли все — отсчёт вайпа RESPAWN_DELAY = %.0f с" % Balance.RESPAWN_DELAY,
			absf(nc.wipe_left - Balance.RESPAWN_DELAY) < 0.2 and nc.due.is_empty(), "%.2f" % nc.wipe_left)
	ok("хост: свой экран — вайп, отсчёт одиночный", es.visible and es.net_death and es.net_wipe
			and es.net_respawn_left() <= Balance.RESPAWN_DELAY + 0.1)
	await barrier("wipe")
	var back: bool = await wait_until(func() -> bool: return not player.dead and not p0.dead,
			Balance.RESPAWN_DELAY + 4.0)
	var dt: float = Game.game_time - t0
	ok("вайп: оба на базе через %.0f с" % Balance.RESPAWN_DELAY, back and at_base(player) and at_base(p0)
			and dt < Balance.RESPAWN_DELAY + 2.0, "%.1f с" % dt)
	await wait(0.2)
	ok("вайп: часы к рассвету — новая смена", Game.day_number == day0 + 1
			and Game.time_of_day >= Balance.NIGHT_END and Game.time_of_day < Balance.NIGHT_END + 0.01,
			"смена %d → %d, время %.4f" % [day0, Game.day_number, Game.time_of_day])
	ok("хост: экран смерти закрыт", not es.visible)
	ok("автосохранение рассвета — в слот «%s»" % slot, Save.exists(slot))
	if Save.exists(slot):
		var d: Dictionary = Save.decode(FileAccess.get_file_as_bytes(Save.path_for(slot)))
		ok("автосохранение — версия 2, игроки по uid", int(d.get("version", 0)) == Save.VERSION
				and (d.get("players", {}) as Dictionary).has(client_uid(0)), str((d.get("players", {}) as Dictionary).keys()))
	Save.remove(slot)
	await barrier("back")

	# --- --hardcore: зритель до конца, погибли все — конец забега.
	scene.set("hardcore", true)
	kill(p0)
	await barrier("hc_dead")
	await wait(Balance.MP_RESPAWN_DELAY + 1.0)
	ok("хардкор: Аня мертва и через %d с — зритель" % int(Balance.MP_RESPAWN_DELAY + 1.0),
			p0.dead and not nc.due.has(p0) and nc.wipe_left < 0.0)
	ok("хардкор: пока жив хост — забег идёт", Game.state == Game.State.PLAYING)
	kill(player)
	ok("хардкор: погибли все — забег окончен", Game.state == Game.State.DEAD)
	await wait(0.2)
	ok("хост: экран итогов, не экран смерти в сети", es.visible and not es.net_death
			and es.title == "ТЕБЯ НАШЛИ", es.title)
	ok("хост: в итогах — личная статистика", es.stats.has("Аня: смертей 2") and es.stats.has("Хост: смертей 2"),
			str(es.stats))
	ok("хардкор: автосохранения нет", not Save.exists(slot))
	await barrier("end")
	scene.set("hardcore", false)
	finish()


# ------------------------------------------------------------------ КЛИЕНТ

func run_client(_i: int) -> void:
	await barrier("in")
	var es: EndScreen = end_screen()
	ok("c0: свой герой погиб — личный отсчёт 15 с", await wait_until(func() -> bool:
		return (player.dead and es.visible and es.net_death and not es.net_wipe
				and es.net_respawn_left() > Balance.MP_RESPAWN_DELAY - 4.0), WAIT))
	await barrier("c_dead")
	await barrier("wipe")
	ok("c0: вайп — отсчёт сменился на одиночный", await wait_until(func() -> bool:
		return es.net_wipe and es.net_respawn_left() <= Balance.RESPAWN_DELAY + 0.5, WAIT),
			"%.1f с" % es.net_respawn_left())
	var day0: int = Game.day_number
	# До барьера: сразу после него хост начинает хардкор и снова убивает Аню.
	ok("c0: после вайпа — на базе, экран закрыт, новая смена", await wait_until(func() -> bool:
		return not player.dead and not es.visible and at_base(player) and Game.day_number > day0, WAIT),
			"смена %d → %d, мёртв %s, экран %s, %.0f px от капсулы" % [day0, Game.day_number, player.dead, es.visible,
			player.global_position.distance_to(World.spawn_point)])
	await barrier("back")
	await barrier("hc_dead")
	ok("c0: хардкор — зритель до конца забега", await wait_until(func() -> bool:
		return player.dead and es.net_death and es.net_spectator and es.net_respawn_left() < 0.0, WAIT))
	await barrier("end")
	ok("c0: забег окончен и у клиента (глобальный пакет)", await wait_until(func() -> bool:
		return Game.state == Game.State.DEAD and es.visible and not es.net_death, WAIT), "state %d" % Game.state)
	ok("c0: итоги команды с хоста (COOP STATS)", es.stats.has("Аня: смертей 2") and es.stats.has("Хост: смертей 2")
			and Game.stats_deaths >= 4, str(es.stats))
	finish()
