extends ScenarioBase
## Дым: сценарии вообще работают.
##
## Главная проверка — шов ввода не ломает обычную игру: с пустым test_input
## герой читает обычный Input (в headless нажатий нет — значит, стоит),
## а с заполненным швом — идёт.

func run() -> void:
	ok("игрок создан", player != null)
	ok("мир сгенерирован", World.tiles.size() == World.W * World.H)
	stand_in_corridor()
	await wait(0.4)

	# Пустой шов — обычная игра: герой читает Input, а нажатий нет.
	clear_input()
	var x0: float = player.global_position.x
	await wait(0.6)
	var drift: float = absf(player.global_position.x - x0)
	ok("пустой шов — обычная игра (герой сам не идёт)", drift < 1.0, "сдвиг %.2f px" % drift)

	# Со швом герой идёт вправо.
	hold(KEY_D)
	await wait(0.6)
	var step: float = player.global_position.x - x0
	ok("шов включён — герой идёт вправо", step > 20.0, "сдвиг %.1f px" % step)

	# Сброс шва — снова обычная игра.
	clear_input()
	await wait(0.8)
	ok("после сброса шва герой остановился", absf(player.vel.x) < 1.0, "скорость %.2f" % player.vel.x)
	finish()
