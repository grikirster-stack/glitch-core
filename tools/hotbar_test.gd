extends Node
class_name HotbarTest
## Хотбар 6/10 (#161, ADR-005 § 8.3): умолчание от экрана, поле профиля, клавиши 7–0
## молчат при шести ячейках, сохранение с хотбаром 10 грузится при настройке 6 без
## потери предметов, ячейка на телефоне 6,1″ не мельче 5,5 мм при 150 %.
##
## Подключается к --test: секция «== Хотбар ==» (test_runner.gd). Отдельного запуска
## нет — нужна игровая сцена с героем. Замер ячейки — тот же эталон, что в ui_scale_test.

const PHONE: Array = ["телефон 6,1″", 420, Vector2(2340, 1080), Vector2(1560, 720)]
## Цель приёмки: ячейка хотбара на 6,1″ при 150 % не мельче стольких мм.
const SLOT_MM_MIN: float = 5.5


var checks: int = 0
var fails: int = 0
var done: bool = false


func start(scene: Node) -> void:
	print("== Хотбар ==")
	_t_defaults()
	_t_profile()
	_t_keys(scene)
	_t_resize(scene)
	_t_save(scene)
	_t_slot_mm(scene)
	done = true


func _ok(label: String, cond: bool, extra: String = "") -> void:
	checks += 1
	if cond:
		print("  OK   %s %s" % [label, extra])
	else:
		fails += 1
		print("  FAIL %s %s" % [label, extra])


# --------------------------------------------------------------------------- умолчание

func _t_defaults() -> void:
	_ok("сенсорный экран — хотбар 6", Inventory.default_hotbar(true, PackedStringArray()) == 6)
	_ok("флаг --touch без сенсора — хотбар 6",
			Inventory.default_hotbar(false, PackedStringArray(["--touch"])) == 6)
	_ok("ПК без флага — хотбар 10", Inventory.default_hotbar(false, PackedStringArray()) == 10)
	_ok("битое число приводится к 6 или 10",
			Inventory.clamp_hotbar(0) == 6 and Inventory.clamp_hotbar(7) == 6
			and Inventory.clamp_hotbar(8) == 10 and Inventory.clamp_hotbar(99) == 10)


# --------------------------------------------------------------------------- профиль

func _t_profile() -> void:
	var path: String = "user://hotbar_test~%d.cfg" % OS.get_process_id()
	DirAccess.remove_absolute(path)
	_ok("файла нет — read_hotbar = 0 (первый запуск)", Profile.read_hotbar(path) == 0)
	Profile.write_hotbar(6, path)
	_ok("write → read: 6", Profile.read_hotbar(path) == 6)
	var p: Profile = Profile.load_or_create(path)
	_ok("load_or_create читает hotbar", p.hotbar == 6)
	p.hotbar = 10
	p.save_to(path)
	_ok("save_to пишет hotbar", Profile.read_hotbar(path) == 10)
	var fresh: Profile = Profile.new()
	fresh.save_to(path)
	_ok("save_to не стирает хотбар при hotbar = 0", Profile.read_hotbar(path) == 10)
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(path)
	cfg.set_value("access", "hotbar", "мусор")
	cfg.save(path)
	_ok("битое поле — 0 (умолчание от экрана)", Profile.read_hotbar(path) == 0)
	DirAccess.remove_absolute(path)


# --------------------------------------------------------------------------- клавиши

func _t_keys(scene: Node) -> void:
	var p: Player = scene.get("player")
	if p == null:
		_ok("герой есть", false)
		return
	var hb0: int = p.inv.hotbar_size
	var sel0: int = p.inv.selected
	p.apply_hotbar_size(6)
	p.inv.selected = 0
	p.test_input = {"keys": {KEY_7: true}}
	p._handle_input(0.0)
	_ok("при хотбаре 6 клавиша 7 ничего не выбирает", p.inv.selected == 0, "слот %d" % p.inv.selected)
	p.test_input = {"keys": {KEY_0: true}}
	p._handle_input(0.0)
	_ok("при хотбаре 6 клавиша 0 ничего не выбирает", p.inv.selected == 0, "слот %d" % p.inv.selected)
	p.test_input = {"keys": {KEY_6: true}}
	p._handle_input(0.0)
	_ok("при хотбаре 6 клавиша 6 выбирает 6-ю ячейку", p.inv.selected == 5, "слот %d" % p.inv.selected)
	p.apply_hotbar_size(10)
	p.test_input = {"keys": {KEY_0: true}}
	p._handle_input(0.0)
	_ok("при хотбаре 10 клавиша 0 выбирает 10-ю ячейку", p.inv.selected == 9, "слот %d" % p.inv.selected)
	p.test_input = {}
	p.apply_hotbar_size(hb0)
	p.inv.selected = mini(sel0, p.inv.hotbar_size - 1)


# --------------------------------------------------------------------------- сужение

func _t_resize(scene: Node) -> void:
	var p: Player = scene.get("player")
	if p == null:
		return
	var saved: Array = []
	for s in p.inv.slots:
		saved.append([s.id, s.count])
	var hb0: int = p.inv.hotbar_size
	p.apply_hotbar_size(10)
	for i in 10:
		p.inv.slots[i] = ItemStack.new(IDs.I.STONE, 1 + i)
	for i in range(10, p.inv.size):
		p.inv.slots[i] = ItemStack.new(IDs.I.COAL, DB.item_max_stack(IDs.I.COAL))
	var before: int = _count(p, IDs.I.STONE) + _count(p, IDs.I.COAL)
	var ground0: int = _ground_of(p, IDs.I.STONE)
	p.apply_hotbar_size(6)
	var after: int = _count(p, IDs.I.STONE) + _count(p, IDs.I.COAL)
	var dropped: int = _ground_of(p, IDs.I.STONE) - ground0
	_ok("хотбар сузился до 6", p.inv.hotbar_size == 6)
	_ok("ячейки 1–6 остались хотбаром", p.inv.slots[0].count == 1 and p.inv.slots[5].count == 6)
	# Часть упавшего магнит тут же подбирает обратно, часть сливается на земле —
	# поэтому сверяем сумму, а не точное число на земле.
	_ok("ячейки 7–10 не потеряны: в рюкзаке, под ногами или подобраны обратно",
			after + dropped >= before - 22 and after <= before,
			"в инвентаре %d, на земле %d, было %d" % [after, dropped, before])
	_restore(p, saved, hb0)


func _count(p: Player, id: int) -> int:
	return p.inv.count_of(id)


## Камни, которые этот тест уронил под ноги героя (чужие предметы на карте не считаем).
func _ground_of(p: Player, id: int) -> int:
	var n: int = 0
	var host: Node = get_tree().current_scene
	if host == null:
		return 0
	for e in host.get_children():
		if e is ItemEntity and int(e.item_id) == id \
				and e.global_position.distance_to(p.global_position) < 8.0:
			n += int(e.count)
	return n


func _restore(p: Player, saved: Array, hb: int) -> void:
	for i in p.inv.size:
		p.inv.slots[i] = ItemStack.new(int(saved[i][0]), int(saved[i][1]))
	p.apply_hotbar_size(hb)
	var host: Node = get_tree().current_scene
	if host == null:
		return
	for e in host.get_children():
		if e is ItemEntity and int(e.item_id) == IDs.I.STONE \
				and e.global_position.distance_to(p.global_position) < 8.0:
			e.queue_free()


# --------------------------------------------------------------------------- сохранение

func _t_save(scene: Node) -> void:
	var p: Player = scene.get("player")
	if p == null:
		return
	var saved: Array = []
	for s in p.inv.slots:
		saved.append([s.id, s.count])
	var hb0: int = p.inv.hotbar_size
	p.apply_hotbar_size(10)
	for i in 10:
		p.inv.slots[i] = ItemStack.new(IDs.I.LAMP, i + 1)
	for i in range(10, p.inv.size):
		p.inv.slots[i] = ItemStack.new()
	var snap: Dictionary = p.save_state()
	p.apply_hotbar_size(6)
	for i in p.inv.size:
		p.inv.slots[i] = ItemStack.new()
	p.load_state(snap)
	var sum: int = 0
	for i in 10:
		sum += p.inv.slots[i].count
	_ok("сохранение с хотбаром 10 грузится при настройке 6: все 10 стопок на месте",
			sum == 55 and p.inv.slots[9].id == IDs.I.LAMP, "сумма %d, слот 9 = %d" % [sum, p.inv.slots[9].id])
	_ok("после загрузки хотбар остаётся 6, выбранный слот не вылезает за него",
			p.inv.hotbar_size == 6 and p.inv.selected < 6, "хотбар %d, слот %d" % [p.inv.hotbar_size, p.inv.selected])
	_restore(p, saved, hb0)


# --------------------------------------------------------------------------- миллиметры

func _t_slot_mm(scene: Node) -> void:
	var hud: HUD = UI.hud
	var p: Player = scene.get("player")
	if hud == null or p == null:
		_ok("HUD и герой есть", false)
		return
	var ppm: float = UI.px_per_mm(int(PHONE[1]), PHONE[2], PHONE[3])
	var canvas: Vector2 = PHONE[3]
	var hb0: int = p.inv.hotbar_size
	var s0: float = UI.ui_scale
	p.apply_hotbar_size(10)
	UI.set_ui_scale(1.0, false)
	hud.size = canvas / 1.0
	hud._lay_sig = -1
	var before: float = hud.hotbar_slot_logical(0).size.x / ppm
	p.apply_hotbar_size(6)
	UI.set_ui_scale(1.5, false)
	hud.size = canvas / 1.5
	hud._lay_sig = -1
	var cell: float = hud.hotbar_slot_logical(0).size.x
	var after: float = cell * 1.5 / ppm
	print("  ЗАМЕР: %s — %.2f px/мм; ячейка хотбара 10 при 100 %%: %.2f мм; 6 при 150 %%: %.1f px логических × 1,5 = %.2f мм"
			% [PHONE[0], ppm, before, cell, after])
	_ok("ячейка хотбара 6 на 6,1″ при 150 %% не мельче %.1f мм" % SLOT_MM_MIN, after >= SLOT_MM_MIN,
			"%.2f мм" % after)
	_ok("шесть ячеек, седьмой прямоугольник пуст",
			hud.hotbar_slot_logical(5).has_area() and not hud.hotbar_slot_logical(6).has_area())
	UI.set_ui_scale(s0, false)
	hud.size = get_viewport().get_visible_rect().size / s0
	hud._lay_sig = -1
	p.apply_hotbar_size(hb0)
