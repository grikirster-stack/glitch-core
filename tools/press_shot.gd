extends SceneTree
## Кадр пресса (#314): коллектор → грядка → сундук → пресс → сундук.
## Зелёная щель — вход, светлая — выход. Партия в работе, панель на выходе.
##
## Headless не рисует. Окно за экраном, без звука. Оба кадра пишет SubViewport:
## дисплей режет 720×1280, а камера окна на этот ряд не смотрит.
##   flock /tmp/godot-stand.lock ~/godot-4.7.2/godot --path . \
##     --audio-driver Dummy --disable-vsync --fixed-fps 60 --windowed \
##     --position -10000,-10000 --resolution 1280x720 \
##     --script res://tools/press_shot.gd -- --seed=31337
## Телефон — тот же прогон с --phone (зум 5, 720×1280).

const OUT_WIDE: String = "res://docs/img/shots/press.png"
const OUT_PHONE: String = "res://docs/img/shots/press_phone.png"
const HARD_LIMIT: float = 25.0
const ZOOM: float = 8.0

var _elapsed: float = 0.0
var _phone: bool = false


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("press_shot: headless не рендерит — нужен прогон с окном за экраном")
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if str(arg) == "--phone":
			_phone = true
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	root.position = Vector2i(-10000, -10000)
	_boot.call_deferred()


func _boot() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > HARD_LIMIT:
		push_error("press_shot: превышен лимит %.0f с" % HARD_LIMIT)
		quit(2)
		return true
	return false


func _run() -> void:
	var world: Node = root.get_node("World")
	var game: Node = root.get_node("Game")
	game.set("time_of_day", 0.30)
	game.set("game_time", 40.0)
	await _frames(8)
	# Цепочка всегда слева направо, как в сценарии: носик коллектора (dir 0)
	# светит вправо, вход пресса смотрит влево. Портрет — тот же ряд, только
	# кадр узкий и высокий, а не разворот входа вниз (вниз луч гаснет о грядку).
	# Как в сценарии press: коллектор на 3 клетки левее грядки, носик вправо.
	# Вплотную луч упирается в грядку и не доходит (длина белого — одна клетка).
	var bed_cell: Vector2i = Vector2i(world.beacon_cell.x + 30, world.beacon_cell.y + 6)
	var col_at: Vector2i = bed_cell + Vector2i(-3, 0)
	var chest_cell: Vector2i = bed_cell + Vector2i(1, 0)
	var press_cell: Vector2i = bed_cell + Vector2i(2, 0)
	var out_cell: Vector2i = bed_cell + Vector2i(3, 0)
	for x in range(col_at.x - 1, out_cell.x + 2):
		var y0: int = 0 if x == col_at.x or x == col_at.x + 1 else bed_cell.y - 4
		for y in range(y0, bed_cell.y + 6):
			if world.in_bounds(x, y):
				world.set_tile(x, y, IDs.T.AIR)
	var floor_y: int = bed_cell.y + 2
	for x in range(col_at.x - 1, out_cell.x + 2):
		if world.in_bounds(x, floor_y):
			world.set_tile(x, floor_y, IDs.T.STONE)
	var mb: GDScript = load("res://scripts/machines/machine_base.gd")
	if not mb.place_machine("Collector", col_at):
		push_error("press_shot: коллектор не встал")
		quit(1)
		return
	var col = world.machines[col_at]
	col.dir = 0
	if col.has_method("_check_sky"):
		col._check_sky()
	if not mb.place_machine("SporeBed", bed_cell):
		push_error("press_shot: грядка не встала")
		quit(1)
		return
	if not mb.place_machine("Chest", chest_cell) or not mb.place_machine("Press", press_cell) \
			or not mb.place_machine("Chest", out_cell):
		push_error("press_shot: цепочка не встала")
		quit(1)
		return
	var bed = world.machines[bed_cell]
	var press = world.machines[press_cell]
	var inn = world.machines[chest_cell]
	var outc = world.machines[out_cell]
	# Как в сценарии press: лоток вправо, вход пресса влево, на сундук волокна.
	bed.dir = 0
	bed.tray = 2
	bed.grow = 6.0
	if bed.has_method("_sync_progress"):
		bed._sync_progress()
	press.dir = 2
	press.batch = 2
	press.job = 4.0
	press.out_buf = 2
	press.queued = 1
	if press.has_method("_sync_progress"):
		press._sync_progress()
	inn.receive_item(IDs.I.SPORE_FIBER, 2)
	outc.receive_item(IDs.I.PANEL, 4)
	world.beams.note_machines()
	world.beams.rebuild()
	world._apply_beam_lights()
	world.reveal_around(press_cell, 16)
	# Иначе за кадры ожидания пресс сам отдаст буфер в сундук.
	press.set_process(false)
	var player: Node2D = current_scene.get("player")
	if player != null:
		player.visible = false
		player.set_physics_process(false)
		player.set_process(false)
		var pcam: Camera2D = player.get("camera")
		if pcam != null:
			pcam.enabled = false
			pcam.set_process(false)
	var ui: Node = root.get_node_or_null("UI")
	var hud: Node = ui.get("hud") if ui != null else null
	if hud != null:
		hud.set("tutorial_step", 5)
		hud.set("tutorial_text", "")
		hud.set("hint_text", "")
		hud.set("notes", [])
		hud.visible = false
	var img: Image
	if _phone:
		img = await _phone_frame(world, [col, bed, inn, press, outc], world.beams.segments, Vector2i(720, 1280), 5.0)
	else:
		img = await _phone_frame(world, [col, bed, inn, press, outc], world.beams.segments, Vector2i(1280, 720), ZOOM)
	if img == null:
		return
	var path: String = ProjectSettings.globalize_path(OUT_PHONE if _phone else OUT_WIDE)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err: int = img.save_png(path)
	# Носик коллектора при dir 0 смотрит вправо, на клетку перед грядкой.
	var into: int = world.beams.color_at(col_at + Vector2i(1, 0))
	print("press_shot: %s (%d) %dx%d, белый %d, lit %s, партия %d, буфер %d, вход %s, выход %s" % [
			path, err, img.get_width(), img.get_height(), into, bed.lit,
			press.batch, press.out_buf, press.in_cell(), press.out_cell()])
	var want_w: int = 720 if _phone else 1280
	var want_h: int = 1280 if _phone else 720
	var size_ok: bool = img.get_width() == want_w and img.get_height() == want_h
	quit(0 if err == OK and size_ok and into == 7 and bed.lit and press.batch == 2 and press.out_buf >= 1 else 1)


## Оба кадра — SubViewport. Окно стола портрет режет, а камера окна на ряд не смотрит.
## Мир в SubViewport не рисуется, пока живёт в окне: в кадр встают новые
## экземпляры станков (копия машины рисует пусто — _draw читает поля, которые
## duplicate не приносит), пол под цепочкой и белый луч. Фон — цвет пещеры,
## иначе ряд из пяти станков тонет полоской в чёрном поле.
func _phone_frame(world: Node, chain: Array, segs: Array, want: Vector2i, zoom: float) -> Image:
	var sub := SubViewport.new()
	sub.size = want
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.transparent_bg = false
	sub.disable_3d = true
	sub.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(sub)
	var holder := Node2D.new()
	# zoom — аргумент: портрет 5 (на 8 ряд не влезает в 720), широкий 8.
	# +0.5 px ниже — щель входа (1 px) иначе попадает на границу пикселя.
	holder.scale = Vector2(zoom, zoom)
	sub.add_child(holder)
	var col_cell: Vector2i = chain[0].cell
	var out_cell: Vector2i = chain[4].cell
	var mid: Vector2 = (world.cell_to_world(col_cell) + world.cell_to_world(out_cell)) * 0.5
	# Содержимое сдвинуто, холдер в нуле: позиция холдера вместе с масштабом
	# уводила ряд к краю кадра.
	var shift: Vector2 = Vector2(want) / zoom * 0.5 - mid + Vector2(0.5, 0.5)
	var stage := Node2D.new()
	stage.position = shift
	holder.add_child(stage)
	var cave := ColorRect.new()
	cave.color = Color(0.09, 0.09, 0.11)
	var view_world: Vector2 = Vector2(want) / zoom
	cave.position = mid - view_world * 0.5
	cave.size = view_world
	stage.add_child(cave)
	print("press_shot: сдвиг %s середина ряда %s" % [shift, mid])
	var copied: int = _stand_chain(stage, Vector2.ZERO, chain)
	var tiles := TileMapLayer.new()
	tiles.tile_set = world.tilemap.tile_set
	var floor_id: int = world.get_tile(col_cell.x, col_cell.y + 2)
	print("press_shot: коллектор %s пол id %d" % [col_cell, floor_id])
	# Только видимая полоса. Копия на всю ширину мира уезжает за край кадра:
	# тайл 16 px на зуме 5 — это 80 px, и пол касается обоих краёв 720.
	var view_cells_x: float = float(want.x) / zoom / 16.0
	# +2/-2, не +1/-1: сдвиг на полпикселя раздвигает крайний тайл до края кадра.
	var x0: int = int(floor(mid.x / 16.0 - view_cells_x * 0.5)) + 2
	var x1: int = int(ceil(mid.x / 16.0 + view_cells_x * 0.5)) - 2
	var painted: int = 0
	for dy in range(1, 4):
		for x in range(x0, x1):
			var tc: Vector2i = Vector2i(x, col_cell.y + dy)
			if not world.in_bounds(tc.x, tc.y):
				continue
			var src: Vector2i = world.tilemap.get_cell_atlas_coords(tc)
			if src.x < 0:
				continue
			tiles.set_cell(tc, 0, src)
			painted += 1
	print("press_shot: пол x %d..%d" % [x0, x1])
	stage.add_child(tiles)
	stage.move_child(tiles, 1)
	var beam := Node2D.new()
	beam.set_script(_beam_draw_script(segs, Vector2.ZERO))
	stage.add_child(beam)
	print("press_shot: в кадр %d узлов, тайлов %d, лучей %d, запрошено %dx%d" % [
			copied, painted, segs.size(), want.x, want.y])
	await _frames(3)
	await RenderingServer.frame_post_draw
	var img: Image = sub.get_texture().get_image()
	print("press_shot: кадр %dx%d" % [img.get_width(), img.get_height()])
	if img.get_width() != want.x or img.get_height() != want.y:
		push_error("press_shot: кадр %dx%d, ждали %dx%d" % [img.get_width(), img.get_height(), want.x, want.y])
		quit(3)
		return null
	if not _has_detail(img):
		push_error("press_shot: кадр сплошного цвета")
		quit(4)
		return null
	return img


## Белый луч в кадр телефона. Сегменты мира в SubViewport не попадают:
## world_fx рисует их в окне, не в этом вьюпорте.
func _beam_step(d: int) -> Vector2i:
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1), Vector2i(1, -1),
	]
	return dirs[d] if d >= 0 and d < dirs.size() else Vector2i.ZERO


## Маска 7 — белый. Остальные цвета кадру пресса не нужны, но не теряем их.
func _beam_color(mask: int) -> Color:
	var cols: Array[Color] = [
		Color(0, 0, 0, 0), Color("#FFD86E"), Color("#7FE6D2"), Color(1.0, 1.0, 0.4275),
		Color("#6FF5E0"), Color(1.0, 0.8471, 1.0), Color(0.4353, 1.0, 1.0), Color.WHITE,
	]
	return cols[mask] if mask > 0 and mask < cols.size() else Color.WHITE


func _beam_draw_script(segs: Array, center: Vector2) -> GDScript:
	var lines: PackedStringArray = PackedStringArray()
	var tile: float = 16.0
	for s in segs:
		var a: Vector2 = (Vector2(s["from"]) + Vector2(0.5, 0.5)) * tile - center
		var b: Vector2 = (Vector2(s["to"]) + Vector2(0.5, 0.5)) * tile - center
		var step: Vector2i = _beam_step(int(s["dir"]) & 7)
		b += Vector2(step) * tile * 0.5
		var col: Color = _beam_color(int(s["color"]))
		lines.append("draw_line(Vector2(%.1f, %.1f), Vector2(%.1f, %.1f), Color(%.3f, %.3f, %.3f), 4.0)" % [
				a.x, a.y, b.x, b.y, col.r, col.g, col.b])
	if lines.is_empty():
		lines.append("pass")
	var src := "extends Node2D\nfunc _draw() -> void:\n\t" + "\n\t".join(lines) + "\n"
	var scr := GDScript.new()
	scr.source_code = src
	scr.reload()
	return scr


func _stand_chain(holder: Node2D, center: Vector2, chain: Array) -> int:
	var n: int = 0
	for src_m in chain:
		var stand: Node2D = src_m.get_script().new()
		stand.set("kind", src_m.kind)
		stand.set("dir", src_m.dir)
		stand.set("hp", src_m.hp)
		stand.set("max_hp", src_m.max_hp)
		stand.set("progress", src_m.progress)
		stand.position = src_m.global_position - center
		var kind: String = str(src_m.kind)
		if kind == "Press":
			stand.set("batch", src_m.batch)
			stand.set("queued", src_m.queued)
			stand.set("job", src_m.job)
			stand.set("out_buf", src_m.out_buf)
		elif kind == "SporeBed":
			stand.set("tray", src_m.tray)
			stand.set("grow", src_m.grow)
			stand.set("lit", src_m.lit)
		elif kind == "Chest":
			var a: Array = src_m.slots
			var b: Array = stand.get("slots")
			for i in mini(a.size(), b.size()):
				b[i].id = a[i].id
				b[i].count = a[i].count
		elif kind == "Collector":
			stand.set("sky_open", src_m.sky_open)
		stand.set_process(false)
		stand.set_physics_process(false)
		holder.add_child(stand)
		stand.queue_redraw()
		n += 1
	return n


func _has_detail(img: Image) -> bool:
	var c0: Color = img.get_pixel(0, 0)
	for y in range(0, img.get_height(), 3):
		for x in range(0, img.get_width(), 3):
			if not img.get_pixel(x, y).is_equal_approx(c0):
				return true
	return false


func _frames(n: int) -> void:
	for i in n:
		await process_frame
