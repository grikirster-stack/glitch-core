extends "res://tools/mp/scenarios/mp_players_base.gd"
## mp_pause (#119): пауза в сетевой игре мир не останавливает. ESC — настоящим событием
## ввода (Input.parse_input_event), его ловят UI и PauseMenu, как у человека.
##
##  * клиент жмёт ESC: панель поверх, дерево не на паузе, ввод у мира забран
##    (UI.blocking); «Сохранить» серая — «сохраняет хост», выход — «Отключиться и выйти
##    в меню»; у хоста прокси клиента получает бит окна (net_window_open) — существующий
##    пакет ввода, схема та же; мир хоста идёт (Game.game_time растёт);
##  * хост жмёт ESC: дерево не на паузе, мир идёт; «Сохранить» доступна (F5 хоста),
##    выход — «Сохранить и выйти в меню», подсказка «закончит игру для всех»;
##  * ESC закрывает паузу у обоих, бит окна у прокси снят.

const WAIT: float = 6.0


# ------------------------------------------------------------------ ХОСТ

func run_host() -> void:
	ok("хост + клиент вошли", await wait_players(2, 45.0))
	ok("прокси клиента с вводом", await wait_proxies(1, 10.0))
	await barrier("in")
	var p0: Player = hero_of(0)
	await barrier("c_paused")
	ok("хост: у прокси клиента окно открыто (бит окна в пакете ввода)", await wait_until(func() -> bool:
			return p0 != null and is_instance_valid(p0) and p0.net_window_open, WAIT))
	var t0: float = Game.game_time
	await wait(1.0)
	ok("хост: пауза клиента мир не остановила", Game.game_time > t0 + 0.5 and not get_tree().paused,
			"%.2f → %.2f" % [t0, Game.game_time])

	var pm: PauseMenu = UI.pause
	await press(KEY_ESCAPE)
	ok("хост: ESC — пауза поверх, дерево не стоит", pm.visible and not get_tree().paused and UI.blocking())
	ok("хост: «Сохранить» доступна, выход — «Сохранить и выйти в меню», «для всех»",
			not pm.save_button.disabled and pm.exit_button.text == PauseMenu.T_SAVE_EXIT
			and pm.hint_label.text.contains("для всех"), "%s | %s" % [pm.exit_button.text, pm.hint_label.text])
	var t1: float = Game.game_time
	await wait(0.5)
	ok("хост: в своей паузе мир идёт", Game.game_time > t1 + 0.2, "%.2f → %.2f" % [t1, Game.game_time])
	await press(KEY_ESCAPE)
	ok("хост: ESC закрыл паузу", not pm.visible and not UI.blocking())
	await barrier("host_done")
	await barrier("c_closed")
	ok("хост: окно клиента закрыто — бит снят", await wait_until(func() -> bool:
			return p0 != null and is_instance_valid(p0) and not p0.net_window_open, WAIT))
	finish()


# ------------------------------------------------------------------ КЛИЕНТ

func run_client(_i: int) -> void:
	await barrier("in")
	var pm: PauseMenu = UI.pause
	await press(KEY_ESCAPE)
	ok("клиент: ESC — пауза поверх, дерево не стоит, ввод у мира забран", pm.visible
			and not get_tree().paused and UI.blocking())
	ok("клиент: «Сохранить» серая — «%s»" % Save.NET_HOST_SAVES, pm.save_button.disabled
			and pm.hint_label.text.contains(Save.NET_HOST_SAVES), pm.hint_label.text)
	ok("клиент: выход — «%s», без предупреждения" % PauseMenu.T_LEAVE,
			pm.exit_button.text == PauseMenu.T_LEAVE and pm.exit_mode == PauseMenu.Exit.LEAVE)
	var t0: float = now()
	await wait(0.5)
	ok("клиент: в паузе кадры идут (дерево не стоит)", now() > t0 + 0.4)
	await barrier("c_paused")
	await barrier("host_done")
	await press(KEY_ESCAPE)
	ok("клиент: ESC закрыл паузу", not pm.visible and not UI.blocking())
	await barrier("c_closed")
	finish()


## Нажать и отпустить клавишу настоящим событием ввода.
func press(code: int) -> void:
	for pressed in [true, false]:
		var ev: InputEventKey = InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await get_tree().process_frame
		await get_tree().process_frame
