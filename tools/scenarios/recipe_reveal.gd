extends ScenarioBase
## Открытие рецепта по первому подбору (#171, ADR-005 § 7.1).
##
## Новый забег: светокристалл виден (уголь стартового набора), стекло и медный
## слиток — нет. Песок открывает стекло. Уведомление приходит один раз.
## Заодно — запрещённые слова словаря не встречаются в игровых строках scripts/.

const BANNED: PackedStringArray = ["мощность", "перегруз", "узел", "эффективность", "манипулятор", "сборщик"]


func run() -> void:
	player.invuln = 1.0e9
	await wait(0.3)
	var panel: InventoryPanel = UI.panel
	_press_key(KEY_I)
	await wait(0.3)
	ok("панель открыта", panel.visible)

	var hand: Array = panel._recipes("hand")
	var names: PackedStringArray = PackedStringArray()
	for r in hand:
		names.append(DB.item_name(int(r["out"])))
	ok("со старта виден светокристалл", names.has("Светокристалл"), ", ".join(names))
	ok("со старта нет стекла: песка ещё не было", not names.has("Стекло"), ", ".join(names))
	ok("со старта нет медного слитка: руда не в стартовом наборе", not names.has("Медный слиток"))
	if IDs.I.has("BURNER"):
		ok("горелка открыта камнем и хламом старта", names.has("Горелка"), ", ".join(names))
	else:
		ok("горелки ещё нет в IDs — рецепт не заведён", true)

	var notes0: int = _count_notes("Теперь можно сделать: Стекло")
	player.inv.add(IDs.I.SAND, 1)
	await wait(0.2)
	panel._check_cache()
	var hand2: Array = panel._recipes("hand")
	var names2: PackedStringArray = PackedStringArray()
	for r in hand2:
		names2.append(DB.item_name(int(r["out"])))
	ok("песок открыл стекло", names2.has("Стекло"), ", ".join(names2))
	ok("уведомление про стекло пришло один раз", _count_notes("Теперь можно сделать: Стекло") == notes0 + 1,
			str(UI.hud.notes))
	var icon_ok: bool = false
	for n in UI.hud.notes:
		if String(n.get("text", "")).contains("Стекло") and int(n.get("icon", 0)) == IDs.I.GLASS:
			icon_ok = true
	ok("у уведомления иконка стекла", icon_ok)

	player.inv.add(IDs.I.SAND, 3)
	await wait(0.2)
	ok("повторный песок уведомление не повторяет", _count_notes("Теперь можно сделать: Стекло") == notes0 + 1)

	var glass: Dictionary = {}
	for r in hand2:
		if int(r["out"]) == IDs.I.GLASS:
			glass = r
	ok("стекло в списке кликабельно", not glass.is_empty())
	if not glass.is_empty():
		panel.station_tab = 0
		panel._count_inventory()
		panel._craft(glass)
		ok("стекло скрафчено руками", player.inv.count_of(IDs.I.GLASS) >= 1, panel.last_feedback)

	var wall: Dictionary = {}
	for r in DB.recipes_for("hand"):
		if int(r["out"]) == IDs.I.STEEL_WALL:
			wall = r
	ok("стальная стена без чертежа не в панели",
			wall.is_empty() or not panel._recipes("hand").has(wall))

	var banned: PackedStringArray = _banned_in_scripts()
	ok("в scripts/ нет слов словаря-запрета", banned.is_empty(), ", ".join(banned))

	_press_key(KEY_I)
	await wait(0.2)
	finish()


func _count_notes(part: String) -> int:
	var n: int = 0
	for e in UI.hud.notes:
		if String(e.get("text", "")).contains(part):
			n += 1
	return n


func _banned_in_scripts() -> PackedStringArray:
	var hits: PackedStringArray = PackedStringArray()
	_scan(ProjectSettings.globalize_path("res://scripts"), hits)
	return hits


## Игровые строки. Комментарии и главы кампании не считаются.
func _scan(path: String, hits: PackedStringArray) -> void:
	var d: DirAccess = DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var name: String = d.get_next()
	while name != "":
		if name.begins_with("."):
			name = d.get_next()
			continue
		var full: String = path.path_join(name)
		if d.current_is_dir():
			if name != "campaign":
				_scan(full, hits)
		elif name.ends_with(".gd"):
			var text: String = _player_text(FileAccess.get_file_as_string(full)).to_lower()
			for w in BANNED:
				if text.contains(w) and hits.size() < 8:
					hits.append("%s:%s" % [name, w])
		name = d.get_next()


func _player_text(src: String) -> String:
	var out: String = ""
	var i: int = 0
	var n: int = src.length()
	while i < n:
		var c: String = src[i]
		if c == "#":
			var nl: int = src.find("\n", i)
			i = n if nl < 0 else nl
			continue
		if c == "\"":
			var j: int = i + 1
			var piece: String = ""
			while j < n:
				if src[j] == "\\":
					j += 2
					continue
				if src[j] == "\"":
					break
				piece += src[j]
				j += 1
			out += piece + " "
			i = j + 1
			continue
		i += 1
	return out


func _press_key(code: int) -> void:
	var ev: InputEventKey = InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)


func _click(pos: Vector2) -> void:
	var mv: InputEventMouseMotion = InputEventMouseMotion.new()
	mv.position = pos
	mv.global_position = pos
	UI.panel._gui_input(mv)
	await wait(0.05)
	for pressed in [true, false]:
		var ev: InputEventMouseButton = InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		UI.panel._gui_input(ev)
	await wait(0.1)
