extends ScenarioBase
## Крафт: открыть панель (I), скрафтить по рецепту → предмет в инвентаре.
##
## Панель открывается настоящей клавишей I — так же, как у человека.
##
## Замечание: кликнуть по рецепту мышью нельзя — в scripts/ui/inventory_panel.gd
## в _click() тернарник затесался внутрь Rect2(...), и обработчик падает с
## «Nonexistent 'Rect2' constructor», не доходя до ветки рецептов. Поэтому
## здесь вызывается тот же метод панели, куда попадает клик: _craft(recipe).

func run() -> void:
	# Заготовка: руда на ручной крафт.
	player.inv.add(IDs.I.COPPER_ORE, 5)
	var ore_before: int = player.inv.count_of(IDs.I.COPPER_ORE)
	ok("руда есть в инвентаре", ore_before > 0, "руды %d" % ore_before)

	# Открываем панель крафта.
	_press_key(KEY_I)
	await wait(0.4)
	ok("панель крафта открыта", UI.blocking() and UI.panel.visible)

	# Ищем рецепт медного слитка.
	var recipes: Array = DB.recipes_for("hand")
	var rec: Dictionary = {}
	for r in recipes:
		if int(r["out"]) == IDs.I.COPPER_INGOT:
			rec = r
			break
	ok("рецепт медного слитка есть", not rec.is_empty())
	if rec.is_empty():
		_press_key(KEY_I)
		await wait(0.2)
		finish()
		return

	# Крафтим — тем же методом, что вызывает клик по рецепту.
	var panel: InventoryPanel = UI.panel
	panel._craft(rec)
	await wait(0.3)
	var ingots: int = player.inv.count_of(IDs.I.COPPER_INGOT)
	ok("слиток получен", ingots > 0, "слитков %d" % ingots)
	ok("руда списана", player.inv.count_of(IDs.I.COPPER_ORE) < ore_before,
			"было %d, стало %d" % [ore_before, player.inv.count_of(IDs.I.COPPER_ORE)])
	ok("счётчик крафта вырос", Game.stats_crafted > 0, "крафтов %d" % Game.stats_crafted)

	# Закрываем панель.
	_press_key(KEY_I)
	await wait(0.3)
	ok("панель закрыта", not UI.blocking())
	finish()


## Настоящее событие клавиши — так UI и панель инвентаря её слышат.
func _press_key(code: int) -> void:
	var ev: InputEventKey = InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
