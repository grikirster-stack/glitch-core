extends MpScenarioBase
## mp_smoke (ADR-002, § 4.10; MP-A, #86): основа сети на настоящих процессах.
##
## Хост и клиенты 0–2 входят; у хоста и у клиентов один список игроков: ник, вид,
## uid, слоты 0–3. Клиенты 0 и 1 приходят с одним ником «Аня» — второй получает
## «Аня 2». Клиент строит мир сам по сиду из рукопожатия. Когда мест нет, клиент 3
## (пятый игрок) получает отказ «мест нет», клиент 4 с чужим протоколом — «версии
## разные». Отказанные в сессию не попадают.
## Замер: запуск процесса клиента до входа, мс; подключение + рукопожатие у клиента, мс.

const NICKS: Array = ["Аня", "Аня", "Борис", "Вера", "Глеб"]
const LOOKS: Array = [0x0001, 0x1203, 0xF00F, 0x0002, 0x0003]
const JOINERS: int = 3


func _init() -> void:
	auto_launch = false


func client_args(i: int) -> PackedStringArray:
	var a: PackedStringArray = PackedStringArray(["--nick=" + String(NICKS[i]), "--look=%d" % int(LOOKS[i])])
	if i == 4:
		a.append("--mp-proto=%d" % (Net.PROTO + 1))
	return a


# ------------------------------------------------------------------ ХОСТ

func run_host() -> void:
	launch(range(JOINERS))
	var all_in: bool = await wait_players(1 + JOINERS, 45.0)
	ok("хост + %d клиента вошли" % JOINERS, all_in, "игроков %d" % Net.peers.size())
	var by_uid: Dictionary = {}
	for id in Net.peers:
		by_uid[int(Net.peers[id]["uid"])] = Net.peers[id]
	var nicks: Array = []
	var slots: Dictionary = {}
	var times: Array = []
	for i in JOINERS:
		var e: Dictionary = by_uid.get(client_uid(i), {})
		ok("c%d: uid %d дошёл" % [i, client_uid(i)], not e.is_empty())
		if e.is_empty():
			continue
		ok("c%d: вид 0x%04X дошёл" % [i, int(LOOKS[i])], int(e["look"]) == int(LOOKS[i]),
				"0x%04X" % int(e["look"]))
		nicks.append(String(e["nick"]))
		slots[int(e["slot"])] = true
		times.append("c%d %d мс" % [i, mp().join_ms_of_uid(client_uid(i))])
	nicks.sort()
	ok("ники: «Аня», «Аня 2», «Борис» (повтор разведён)", nicks == ["Аня", "Аня 2", "Борис"],
			", ".join(nicks))
	slots[int(Net.peers.get(1, {}).get("slot", -1))] = true
	ok("слоты 0–3 у четверых разные", slots.size() == 4 and slots.has(0) and slots.has(3))
	print("  ЗАМЕР запуск клиента-процесса до входа: %s" % ", ".join(times))
	await barrier("joined", JOINERS)

	# Игра полна: пятый игрок и клиент с чужим протоколом.
	launch([3, 4])
	var gone: bool = await wait_exit([3, 4], 30.0)
	ok("отказанные клиенты вышли сами", gone)
	print("  ЗАМЕР запуск клиента-процесса до отказа и выхода: c3 %d мс, c4 %d мс" % [
			mp().exit_ms_of(3), mp().exit_ms_of(4)])
	ok("отказанные в сессию не попали", Net.peers.size() == 1 + JOINERS, "игроков %d" % Net.peers.size())
	await barrier("done", JOINERS)
	finish()


# ------------------------------------------------------------------ КЛИЕНТ

func run_client(i: int) -> void:
	if i >= JOINERS:
		ok("c%d: вход отклонён" % i, not Net.is_client() and Net.session.is_empty())
		if i == 3:
			ok("c3: причина «%s»" % Net.R_FULL, Net.last_error == Net.R_FULL, "«%s»" % Net.last_error)
		else:
			ok("c4: чужой протокол — «версии разные»", Net.last_error.begins_with("версии разные"),
					"«%s»" % Net.last_error)
		finish()
		return
	ok("c%d: вошёл клиентом" % i, Net.is_client())
	ok("c%d: мир построен по сиду из рукопожатия" % i,
			World.world_seed == int(Net.session.get("seed", -1)) and player != null,
			"сид %d" % World.world_seed)
	var nick: String = String(Net.session.get("nick", ""))
	var want: Array = ["Аня", "Аня 2"] if i < 2 else ["Борис"]
	ok("c%d: ник от хоста «%s»" % [i, nick], want.has(nick))
	var slot: int = int(Net.session.get("slot", -1))
	ok("c%d: слот %d из 1–3" % [i, slot], slot >= 1 and slot <= 3)
	print("  ЗАМЕР c%d: подключение + рукопожатие %d мс" % [i, Net.join_ms])
	await barrier("joined")
	# Список игроков у клиента — тот же, что у хоста.
	ok("c%d: в списке 4 игрока" % i, Net.peers.size() == 4, "%d" % Net.peers.size())
	var me: Dictionary = Net.peers.get(Net.my_id(), {})
	ok("c%d: своя запись: uid, ник, вид" % i, not me.is_empty() and int(me["uid"]) == client_uid(i)
			and String(me["nick"]) == nick and int(me["look"]) == int(LOOKS[i]))
	var host_e: Dictionary = Net.peers.get(1, {})
	ok("c%d: хост — слот 0, «Хост»" % i, not host_e.is_empty() and int(host_e["slot"]) == 0
			and String(host_e["nick"]) == "Хост")
	await barrier("done")
	finish()
