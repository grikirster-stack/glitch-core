extends ScenarioBase
## Подписи панели инвентаря влезают в свои рамки (#69).
##
## Панель рисует каждую подпись через _text(): при включённом text_audit туда
## пишется прямоугольник «чернил» строки (ширина — Font.get_string_size) и рамка,
## в которую строка обязана влезть (строка рецепта, кнопка, вкладка, подсказка).
## Проверяем на 1280×720 и 960×540 (размер панели задаётся явно),
## на всех вкладках, с сундуком тайника с самым длинным именем, с наведением
## на рецепты и ячейки:
##  * каждая подпись внутри своей рамки и внутри панели;
##  * никакие две подписи не налезают друг на друга (кроме подсказки поверх);
##  * подсказка целиком на экране.
## Счётчик деталей релея с панели снят (#169) — его рамки больше нет.

const SIZES: Array = [Vector2(1280, 720), Vector2(960, 540)]

var panel: InventoryPanel = null
var fails: Array = []
var checked: int = 0
var cut: int = 0
var cut_texts: Array = []


func run() -> void:
	panel = UI.panel
	# Тайник с самым длинным именем — худший заголовок.
	var best = null
	var best_name: String = ""
	for c in World.ruin_caches:
		if c["chest"] != null and String(c["name"]).length() > best_name.length():
			best = c["chest"]
			best_name = String(c["name"])
	ok("есть тайник руины", best != null, "«%s»" % best_name)
	if best == null:
		finish()
		return
	# Полные стопки — самые длинные числа в ячейках и «есть/нужно».
	for e in [[IDs.I.IRON_PLATE, 99], [IDs.I.STEEL_PLATE, 7], [IDs.I.COPPER_ORE, 99], [IDs.I.CRYSTAL, 3],
			[IDs.I.IRON_INGOT, 1]]:
		player.inv.add(int(e[0]), int(e[1]))
	Game.give_next_blueprint()
	UI.open_chest(best)
	await wait(0.2)
	ok("панель открыта у тайника", panel.visible and panel.chest == best)
	ok("счётчик деталей релея с панели снят", not panel.has_method("_goal_cells")
			and not panel.has_method("_draw_goal"))

	for sz in SIZES:
		panel.size = sz
		for tab in InventoryPanel.TABS.size():
			panel.station_tab = tab
			panel.scroll = 0
			for hover in _hovers():
				await _audit("%dx%d, вкладка %d, мышь %s" % [int(sz.x), int(sz.y), tab, str(hover)], hover)
	ok("все подписи внутри своих рамок и панели (1280×720 и 960×540)", fails.is_empty(),
			"подписей %d, обрезано с «…» %d; %s" % [checked, cut, "; ".join(fails.slice(0, 4))])
	# Обрезка — запасной вариант; что обрезалось, печатаем для глаз.
	print("  обрезано с «…» (разных строк %d): %s" % [cut_texts.size(), " | ".join(cut_texts)])

	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.close()
	await wait(0.1)
	finish()


## Куда навести мышь: никуда, первая и последняя строка рецепта,
## ячейка сундука, правый нижний угол инвентаря.
func _hovers() -> Array:
	var out: Array = [Vector2(-1, -1)]
	out.append(panel._recipe_row_rect(0).position + Vector2(60, 12))
	out.append(panel._recipe_row_rect(InventoryPanel.RECIPE_ROWS - 1).end - Vector2(20, 8))
	out.append(panel._chest_slot_rect(0).get_center())
	out.append(panel._inv_slot_rect(player.inv.size - 1).get_center())
	return out


func _audit(label: String, mouse: Vector2) -> void:
	panel.mouse_pos = mouse
	panel.text_audit = []
	panel.queue_redraw()
	await runner.get_tree().process_frame
	await runner.get_tree().process_frame
	var entries: Array = panel.text_audit
	panel.text_audit = null
	if entries.is_empty():
		fails.append("%s: панель ничего не нарисовала" % label)
		return
	var prect: Rect2 = Rect2(panel._panel_pos(), InventoryPanel.PANEL).grow(0.5)
	var screen: Rect2 = Rect2(Vector2.ZERO, panel.size).grow(0.5)
	var body: Array = []
	for e in entries:
		checked += 1
		var r: Rect2 = e["rect"]
		var b: Rect2 = e["box"]
		var tag: String = String(e["tag"])
		if String(e["text"]) != String(e["full"]) and tag != "tip_box":
			cut += 1
			if not cut_texts.has(String(e["full"])):
				cut_texts.append(String(e["full"]))
		if tag == "tip_box":
			if not screen.encloses(r):
				fails.append("%s: подсказка за краем экрана %s" % [label, str(r)])
			continue
		if not b.grow(0.5).encloses(r):
			fails.append("%s: «%s» вылезает из рамки (%s в %s)" % [label, e["text"], str(r), str(b)])
		if tag != "tip":
			if not prect.encloses(r):
				fails.append("%s: «%s» за краем панели" % [label, e["text"]])
			body.append(e)
	# Наложения: две подписи не должны пересекаться (подсказка — поверх, её не считаем).
	for i in body.size():
		var a: Rect2 = body[i]["rect"]
		for j in range(i + 1, body.size()):
			var c: Rect2 = body[j]["rect"]
			var x: Rect2 = a.intersection(c)
			if x.get_area() > 2.0:
				fails.append("%s: «%s» налезает на «%s»" % [label, body[i]["text"], body[j]["text"]])
