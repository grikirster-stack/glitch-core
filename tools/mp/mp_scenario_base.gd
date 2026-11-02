class_name MpScenarioBase
extends ScenarioBase
## Базовый класс сетевого сценария (ADR-002, § 4.10): то же, что ScenarioBase (шов
## ввода своего героя, ok/wait/wait_until), плюс роль процесса и барьеры.
##
## Один и тот же файл сценария работает в хост-процессе (run_host) и в каждом
## клиенте (run_client(i), i — номер клиента). Оба обязаны закончить finish().
## Точки синхронизации — await barrier("имя"): хост ждёт, пока клиенты дойдут,
## и отпускает их. Проверки печатаются как обычно; клиентские хост собирает в
## общий итог с префиксом [cN].

## −1 — хост; 0.. — номер клиента.
var role: int = -1
## Сколько клиентов в сценарии (MP_REGISTRY "clients" или --mp-clients).
var clients: int = 0
var mp_name: String = ""
## true — раннер сам запускает всех клиентов до run_host(); false — сценарий
## запускает их сам (launch), например чтобы лишний игрок пришёл в полную игру.
var auto_launch: bool = true


func mp_setup(p_role: int, p_clients: int, p_name: String) -> void:
	role = p_role
	clients = p_clients
	mp_name = p_name


func mp() -> MpRunner:
	return runner as MpRunner


func is_host_side() -> bool:
	return role < 0


## Тело на хосте.
func run_host() -> void:
	finish()


## Тело на клиенте i.
func run_client(_i: int) -> void:
	finish()


## Дополнительные флаги клиента i (--nick=, --look=, --mp-proto=…).
func client_args(_i: int) -> PackedStringArray:
	return PackedStringArray()


## uid профиля клиента i (по нему хост узнаёт клиента).
func client_uid(i: int) -> int:
	return 1000 + i


# ------------------------------------------------------------------ ХОСТ

## Запустить клиентов с этими номерами.
func launch(indices: Array) -> void:
	for i in indices:
		mp().launch(int(i))


## Ждать, пока в сессии не станет n игроков (вместе с хостом).
func wait_players(n: int, timeout: float) -> bool:
	return await wait_until(func() -> bool: return Net.peers.size() >= n, timeout)


## Ждать выхода процессов клиентов с этими номерами.
func wait_exit(indices: Array, timeout: float) -> bool:
	return await wait_until(_all_done.bind(indices), timeout)


func _all_done(indices: Array) -> bool:
	for i in indices:
		if not mp().child_done(int(i)):
			return false
	return true


# ------------------------------------------------------------------ ОБЩЕЕ

## Точка синхронизации. Хост: count клиентов (−1 — все вошедшие). Итог — проверка.
func barrier(name: String, count: int = -1, timeout: float = 30.0) -> bool:
	var ok_b: bool = await mp().barrier(name, count, timeout)
	ok("барьер «%s»" % name, ok_b)
	return ok_b
