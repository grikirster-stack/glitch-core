extends ScenarioBase
## Турель-разрядник (ADR-001 § 4.4, #31): при efficiency 1 убивает эхо
## (100 HP, 20 урона / 0.8 с) не дольше чем за 6 с. Заодно — приоритет целей
## (тень раньше эха), сигнал fired и звук разряда.
##
## Под землёй — закрытая коробка из стальной стены: ТЭЦ, турель, игрок
## (неуязвимый) у левого края, фантом — справа в 5 клетках от турели.

const BOX_W: int = 12
const BOX_H: int = 6
const KILL_LIMIT: float = 6.0

var _origin: Vector2i = Vector2i(-1, -1)
var _fired: Array = []


func run() -> void:
	player.invuln = 1.0e9
	_origin = find_box_spot(self, BOX_W, BOX_H)
	ok("найдено тёмное место под землёй", _origin.x >= 0, str(_origin))
	if _origin.x < 0:
		finish()
		return
	var turret: Turret = build_turret_box(self, _origin, BOX_W, BOX_H)
	ok("турель поставлена", turret != null)
	if turret == null:
		finish()
		return
	turret.fired.connect(func(a: Vector2, b: Vector2) -> void: _fired.append([a, b]))
	var on: bool = await wait_until(func(): return turret.powered and turret.efficiency >= 0.999, 2.0)
	ok("турель запитана, efficiency 1", on, "eff=%.2f" % turret.efficiency)
	ok("турель прочнее машин", is_equal_approx(turret.max_hp, Balance.TURRET_HP), "hp=%.0f" % turret.max_hp)

	# Эхо в 5 клетках: должно умереть за ≤ 6 с.
	var echo: Node = spawn_phantom_at(_floor_pos(_origin + Vector2i(8, 3)), "echo")
	ok("эхо появилось", echo != null)
	var t0: float = now_proc()   # турель стреляет в кадрах отрисовки
	var ref: WeakRef = weakref(echo)   # захват освобождённого узла в лямбде — ошибка движка
	var dead: bool = await wait_until(func(): return ref.get_ref() == null or not ref.get_ref().alive, KILL_LIMIT + 1.0)
	var secs: float = now_proc() - t0
	ok("эхо убито турелью за ≤ 6 с", dead and secs <= KILL_LIMIT, "%.2f с, выстрелов %d" % [secs, turret.shots])
	ok("на эхо ушло 5 разрядов", turret.shots == 5, "выстрелов %d" % turret.shots)
	ok("сигнал fired на каждый выстрел", _fired.size() == turret.shots, "%d" % _fired.size())

	# Приоритет: тень и эхо в радиусе — первой бьёт тень.
	var e2: Node = spawn_phantom_at(_floor_pos(_origin + Vector2i(5, 3)), "echo")
	var sh: Node = spawn_phantom_at(_floor_pos(_origin + Vector2i(9, 3)), "shade")
	await await_frame()
	var pick: Node = turret.pick_target()
	ok("приоритет: тень раньше эха (и ближе стоящего)", pick == sh,
			"цель %s" % (String(pick.kind) if pick != null else "нет"))
	for p in [e2, sh]:
		if p != null and is_instance_valid(p):
			p.get_parent().remove_child(p)
			p.queue_free()
	finish()


func _floor_pos(c: Vector2i) -> Vector2:
	return Vector2(float(c.x * World.TILE) + 8.0, float((c.y + 1) * World.TILE) - 12.0)


# ------------------------------------------------------------------ ОБЩЕЕ (#31)
# Статические помощники — их же зовёт turret_brownout.gd.

## Тёмное место под землёй под коробку w×h, вдали от базы.
static func find_box_spot(sc: ScenarioBase, w: int, h: int) -> Vector2i:
	for dx in [70, -70, 90, -90, 110, -110, 130, -130, 150]:
		var x: int = World.beacon_cell.x + int(dx)
		if x < 4 or x + w > World.W - 4:
			continue
		var y: int = int(World.surface[x]) + 16
		if y + h >= World.H - 6:
			continue
		var c: Vector2i = Vector2i(x, y)
		var dark: bool = true
		for k in range(1, w - 1):
			if World.light_at(c + Vector2i(k, 3)) > 0.4:
				dark = false
				break
		if dark:
			return c
	return Vector2i(-1, -1)


## Коробка из стальной стены с полостью (ряды 2..3, столбцы 1..w-2).
## Игрок — в столбце 1, ТЭЦ — в 2, турель — в 3 (ряд 3, на полу).
static func build_turret_box(sc: ScenarioBase, o: Vector2i, w: int, h: int) -> Turret:
	for y in h:
		for x in w:
			World.set_tile(o.x + x, o.y + y, IDs.T.STEEL_WALL)
	for y in [2, 3]:
		for x in range(1, w - 1):
			World.set_tile(o.x + x, o.y + int(y), IDs.T.AIR)
	sc.stand_at_cell(Vector2i(o.x + 1, o.y + 3))
	var gc: Vector2i = Vector2i(o.x + 2, o.y + 3)
	var tc: Vector2i = Vector2i(o.x + 3, o.y + 3)
	if not MachineBase.place_machine("CoalGen", gc) or not MachineBase.place_machine("Turret", tc):
		return null
	var gen: CoalGen = World.machines[gc]
	gen.add_fuel(CoalGen.FUEL_MAX_UNITS)
	return World.machines[tc]
