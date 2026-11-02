extends MpScenarioBase
## mp_lobby (ADR-002 § 4.5, § 4.6, § 4.10; MP-H, #93): поиск в локалке, лобби и старт —
## через настоящее меню двух процессов (tools/mp/lobby_driver.gd, тапами по экранам).
##
## Хост-процесс харнесса сам не играет: запускает процесс-хост лобби («Создать игру»:
## имя, сид, 3 места, свой порт; ответчик поиска; ответчик чужой сборки), убеждается,
## что тот отвечает на поиск, и запускает процесс-клиент: «Найти игру» → хост в списке
## ≤ 1.5 с, чужая сборка серая → тап → лобби (ники, вид, готовность) → «Готов» → хост
## «Старт» → оба в мире (сид хоста, снимок MP-C). Это и приёмка mp_discovery (§ 5.3).
## Всё на 127.0.0.1: окна брандмауэра Windows нет. Порты процессов — свои
## (LOBBY_PORT_BASE + pid % 200 · 3: игра, поиск, чужой поиск) — не пересекаются с
## сервером харнесса и с соседними прогонами.
## Вывод процессов — с префиксом [c0] (хост лобби) и [c1] (клиент), их ИТОГ — в общем.

const LOBBY_PORT_BASE: int = 25100
const DRIVER: String = "res://tools/mp/lobby_driver.gd"


func _init() -> void:
	auto_launch = false


func run_host() -> void:
	var g: int = LOBBY_PORT_BASE + OS.get_process_id() % 200 * 3
	var d: int = g + 1
	var d2: int = g + 2
	var sd: int = int(scene.get("seed_value"))
	_spawn(0, ["--lobby-role=host", "--lobby-port=%d" % g, "--lobby-disc=%d" % d,
			"--lobby-other=%d" % d2, "--lobby-seed=%d" % sd])
	# Хост лобби поднят, когда отвечает на поиск — тогда и клиент (замер «≤ 1.5 с»
	# у клиента идёт от его тапа «Найти игру», а не от запуска хоста).
	var probe: LanDiscovery = LanDiscovery.new()
	add_child(probe)
	probe.start_search(d, "127.0.0.1", PackedStringArray(["127.0.0.1:%d" % d]))
	var t0: int = Time.get_ticks_msec()
	var up: bool = await wait_until(func() -> bool: return not probe.hosts.is_empty() or mp().child_done(0), 30.0)
	ok("хост лобби отвечает на поиск (127.0.0.1:%d)" % d, up and not probe.hosts.is_empty(),
			"%d мс от запуска процесса" % (Time.get_ticks_msec() - t0))
	if not probe.hosts.is_empty():
		var e: Dictionary = probe.hosts.values()[0]
		ok("анонс: лобби, 1/3, порт игры, без пароля", String(e["st"]) == "lobby" and int(e["n"]) == 1
				and int(e["max"]) == 3 and int(e["port"]) == g and not bool(e["pw"]), str(e))
		print("  ЗАМЕР: запрос %d Б, ответ %d Б; запросы на каждую цель: сразу, через %.1f с, дальше раз в %.1f с (%.2f/с)"
				% [probe.last_query_bytes, LanDiscovery.encode_answer(e).size(), LanDiscovery.QUERY_SECOND,
				Net.DISCOVERY_PERIOD, 1.0 / Net.DISCOVERY_PERIOD])
	probe.stop()
	probe.queue_free()
	_spawn(1, ["--lobby-role=client", "--lobby-port=%d" % g, "--lobby-disc=%d,%d" % [d, d2],
			"--lobby-seed=%d" % sd])
	var done: bool = await wait_exit([0, 1], 60.0)
	ok("процессы лобби вышли сами", done)
	finish()


func run_client(_i: int) -> void:
	finish()


## Процесс драйвера меню i — в список клиентов харнесса (вывод [ci], ИТОГ, таймаут).
func _spawn(i: int, extra: Array) -> void:
	var args: PackedStringArray = PackedStringArray(["--headless", "--path",
			ProjectSettings.globalize_path("res://"), "--script", DRIVER, "--"])
	for a in extra:
		args.append(String(a))
	var r: Dictionary = OS.execute_with_pipe(OS.get_executable_path(), args, false)
	if r.is_empty():
		ok("[c%d] процесс запущен" % i, false)
		return
	mp().children.append({"i": i, "pid": int(r["pid"]), "out": r["stdio"], "err": r["stderr"],
			"buf": PackedByteArray(), "ebuf": PackedByteArray(), "summary": false,
			"code": -1, "done": false, "killed": false, "t0": Time.get_ticks_msec(), "ms": -1})
