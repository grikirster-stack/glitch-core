extends ScenarioBase
## Исследования (#28): 4 данных — T1 не открыть, сборщик не скрафтить;
## 5 данных — кнопка «Открыть» на карточке T1 списывает данные, и рецепт
## сборщика становится доступен.
##
## Панель открывается настоящей клавишей I, вкладка и кнопки нажимаются через
## обработчик клика панели (_click) — тот же путь, что у мыши человека
## (см. tools/scenarios/craft.gd).

func run() -> void:
	await wait(0.2)
	var panel: InventoryPanel = UI.panel
	var rec: Dictionary = _hand_recipe(IDs.I.ASSEMBLER)
	ok("рецепт сборщика есть и висит на T1", not rec.is_empty() and String(rec.get("tech", "")) == "T1")
	if rec.is_empty():
		finish()
		return
	ok("новый забег: открыт только T0", Tech.unlocked == ["T0"], str(Tech.unlocked))
	ok("рецепт сборщика заперт", not DB.recipe_unlocked(rec))
	# Материалы на сборщик — с запасом, чтобы мешал только замок.
	for id in rec["in"].keys():
		player.inv.add(int(id), int(rec["in"][id]) * 2)

	_press_key(KEY_I)
	await wait(0.3)
	ok("панель открыта", panel.visible and UI.blocking())

	# ---- 4 данных: не хватает ------------------------------------------------
	Game.research = 4
	ok("при 4 данных T1 открыть нельзя", not Tech.can_unlock("T1"), Tech.lock_reason("T1"))
	_click_tab(panel, InventoryPanel.RESEARCH_TAB)
	await wait(0.2)
	ok("вкладка «Исследования» выбрана", panel.station_tab == InventoryPanel.RESEARCH_TAB)
	_click_rect(panel, panel._card_button_rect(0))
	await wait(0.2)
	ok("кнопка при 4 данных ничего не открыла", not Tech.is_unlocked("T1"), str(Tech.unlocked))
	ok("данные не списаны", Game.research == 4, "данных %d" % Game.research)

	var asm_before: int = player.inv.count_of(IDs.I.ASSEMBLER)
	_click_tab(panel, 0)
	await wait(0.1)
	_click_recipe(panel, rec)
	await wait(0.2)
	ok("запертый сборщик не скрафтился", player.inv.count_of(IDs.I.ASSEMBLER) == asm_before,
			"сборщиков %d" % player.inv.count_of(IDs.I.ASSEMBLER))

	# ---- 5 данных: открываем T1 -----------------------------------------------
	Game.research = 5
	ok("при 5 данных T1 открыть можно", Tech.can_unlock("T1"))
	ok("T2 без T1 не открыть даже с запасом", not Tech.can_unlock("T2") and Tech.lock_reason("T2") != "")
	_click_tab(panel, InventoryPanel.RESEARCH_TAB)
	await wait(0.1)
	_click_rect(panel, panel._card_button_rect(0))
	await wait(0.2)
	ok("T1 открыт кнопкой карточки", Tech.is_unlocked("T1"), str(Tech.unlocked))
	ok("списано 5 данных", Game.research == 0, "данных %d" % Game.research)
	ok("рецепт сборщика доступен", DB.recipe_unlocked(rec))
	ok("T2 при 0 данных закрыт", not Tech.can_unlock("T2"))

	_click_tab(panel, 0)
	await wait(0.1)
	_click_recipe(panel, rec)
	await wait(0.2)
	ok("сборщик скрафчен", player.inv.count_of(IDs.I.ASSEMBLER) == asm_before + 1,
			"сборщиков %d" % player.inv.count_of(IDs.I.ASSEMBLER))

	# ---- Станции тоже уважают замок -------------------------------------------
	# Турель — T2: сборщик с полным набором деталей её не начинает.
	var asm: Assembler = Assembler.new()
	asm.stock = {IDs.I.STEEL_PLATE: 3, IDs.I.CIRCUIT: 2, IDs.I.POWER_CELL: 1}
	var picked: Dictionary = asm._find_recipe()
	ok("сборщик не берёт рецепт T2 без исследования", picked.is_empty() or String(picked.get("tech", "")) != "T2",
			String(picked.get("name", "—")))
	asm.free()

	_press_key(KEY_I)
	await wait(0.3)
	ok("панель закрыта", not UI.blocking())
	finish()


func _hand_recipe(out_id: int) -> Dictionary:
	for r in DB.recipes_for("hand"):
		if int(r["out"]) == out_id:
			return r
	return {}


func _click_rect(panel: InventoryPanel, r: Rect2) -> void:
	panel._click(r.get_center(), false)


func _click_tab(panel: InventoryPanel, i: int) -> void:
	panel._click(panel._panel_pos() + Vector2(16 + i * 170 + 20, 38 + 15), false)


## Пролистать список колесом до рецепта и кликнуть по его строке.
func _click_recipe(panel: InventoryPanel, rec: Dictionary) -> void:
	var idx: int = DB.recipes_for("hand").find(rec)
	panel.scroll = mini(idx, panel._max_scroll())
	var row: int = idx - panel.scroll
	panel._click(panel._panel_pos() + Vector2(390, 116 + row * InventoryPanel.RECIPE_H + 10), false)


## Настоящее событие клавиши — так UI и панель инвентаря её слышат.
func _press_key(code: int) -> void:
	var ev: InputEventKey = InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
