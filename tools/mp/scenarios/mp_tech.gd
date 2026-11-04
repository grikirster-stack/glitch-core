extends "res://tools/mp/scenarios/mp_players_base.gd"
## mp_tech (ADR-002 § 4.2.7, § 4.7 «общее и личное», D10; MP-G, #91): исследования,
## главы журнала и обрывки — общие для команды, считает хост.
##
##  * хост даёт данные, читает главу и находит обрывок — у обоих клиентов то же (TECH);
##  * клиент 0 открывает T1 во вкладке «Исследования» — команда UNLOCK хосту; узел открыт
##    у хоста и у обоих клиентов, данные списаны у всех, рецепты T1 доступны всем;
##  * T3 без T2 — отказ хоста словами, ничего не открыто;
##  * клиент 1 крафтит «Сборщик» (рецепт T1) — у хоста он в инвентаре прокси.

const WAIT: float = 6.0
const FRAGMENT: String = "…mp_tech: обрывок с глубины…"


func _assembler_rec() -> Dictionary:
	for r in DB.recipes:
		if String(r["name"]) == "Сборщик":
			return r
	return {}


# ------------------------------------------------------------------ ХОСТ

func run_host() -> void:
	ok("хост + %d клиента вошли" % clients, await wait_players(1 + clients, 45.0))
	ok("прокси обоих клиентов с вводом", await wait_proxies(clients, 10.0))
	await barrier("in")
	var p1: Player = hero_of(1)
	var cost: int = Tech.cost("T1")
	Game.research = cost + 3
	if Game.net_world != null:
		Game.net_world._mark_global()
	Tech.read_chapter(0)
	Tech.add_fragment(FRAGMENT)
	if p1 != null:
		p1.inv.add(IDs.I.IRON_PLATE, 4)
		p1.inv.add(IDs.I.COPPER_PLATE, 2)
	ok("до открытия рецепт T1 заперт", not DB.recipe_unlocked(_assembler_rec()))
	await barrier("data")

	# Все клиенты подтвердили, что данные хоста до них дошли. Только после этого
	# клиент 0 просит открыть T1: иначе хост спишет данные (8 → 3) и пришлёт
	# TECH UNLOCK раньше, чем медленный клиент увидит 8, — тот не найдёт окна,
	# в котором Game.research == 8 (сценарий падал в CI).
	await barrier("data_ok")

	await barrier("unlock")
	ok("хост: T1 открыт командой клиента 0", await wait_until(func() -> bool: return Tech.is_unlocked("T1"), WAIT))
	ok("хост: данные списаны", Game.research == 3, "данных %d" % Game.research)
	ok("хост: рецепт T1 доступен", DB.recipe_unlocked(_assembler_rec()))
	await barrier("unlocked")
	ok("хост: T3 без T2 не открыт", not Tech.is_unlocked("T3") and not Tech.is_unlocked("T2"))

	await barrier("craft")
	var got: bool = p1 != null and await wait_until(func() -> bool: return p1.inv.count_of(IDs.I.ASSEMBLER) == 1, WAIT)
	ok("хост: «Сборщик» (T1) скрафчен клиентом 1 — в инвентаре прокси", got)
	await barrier("done")
	finish()


# ------------------------------------------------------------------ КЛИЕНТ

func run_client(i: int) -> void:
	await barrier("in")
	await barrier("data")
	var cost: int = Tech.cost("T1")
	ok("данные хоста пришли (GLOBAL)", await wait_until(func() -> bool: return Game.research == cost + 3, WAIT),
			"данных %d" % Game.research)
	ok("глава журнала, прочитанная на хосте, — и у клиента (TECH)",
			await wait_until(func() -> bool: return Tech.is_chapter_read(0), WAIT))
	ok("обрывок, найденный на хосте, — и у клиента (TECH)",
			await wait_until(func() -> bool: return Tech.fragments.has(FRAGMENT), WAIT))
	ok("до открытия рецепт T1 заперт и у клиента", not DB.recipe_unlocked(_assembler_rec()))
	# Данные у всех. Только теперь клиент 0 может просить открыть T1: пока он
	# не попросил, хост не списывает 8 → 3, и у каждого клиента есть окно,
	# в котором Game.research == 8 (без этого медленный клиент его пропускал).
	await barrier("data_ok")
	var panel: InventoryPanel = UI.panel
	if i == 0:
		panel.open(player)
		panel.station_tab = InventoryPanel.RESEARCH_TAB
		panel._unlock_card(InventoryPanel.CARD_NODES.find("T1"))
		ok("клиент сам узел не открыл — команда хосту", not Tech.is_unlocked("T1") and InvOps.pending_count() == 1)
	await barrier("unlock")
	ok("T1 открыт и у клиента %d (TECH с хоста)" % i, await wait_until(func() -> bool: return Tech.is_unlocked("T1"), WAIT))
	ok("данные списаны и у клиента %d" % i, await wait_until(func() -> bool: return Game.research == 3, WAIT),
			"данных %d" % Game.research)
	ok("рецепт T1 доступен клиенту %d" % i, DB.recipe_unlocked(_assembler_rec()))
	if i == 0:
		await wait_until(func() -> bool: return InvOps.pending_count() == 0, WAIT)
		ok("обратная связь открытия — с хоста", panel.last_feedback.begins_with("Открыто: T1"), panel.last_feedback)
		var res: Array = []
		InvOps.unlock("T3", func(okk: bool, text: String) -> void: res.append([okk, text]))
		await wait_until(func() -> bool: return not res.is_empty(), WAIT)
		ok("T3 без T2: хост отказал словами", not res.is_empty() and not bool(res[0][0])
				and String(res[0][1]).begins_with("Сначала откройте"), str(res))
		panel.close()
	await barrier("unlocked")

	await barrier("craft")
	if i == 1:
		ok("материалы для «Сборщика» пришли (INV)", await wait_until(func() -> bool:
			return player.inv.count_of(IDs.I.IRON_PLATE) >= 4 and player.inv.count_of(IDs.I.COPPER_PLATE) >= 2, WAIT))
		panel.open(player)
		panel._craft(_assembler_rec())
		ok("«Сборщик» скрафчен (INV с хоста)",
				await wait_until(func() -> bool: return player.inv.count_of(IDs.I.ASSEMBLER) == 1, WAIT))
		panel.close()
	await barrier("done")
	finish()
