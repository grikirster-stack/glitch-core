extends Mission
## Глава 2 «Огонь» (ADR-005 § 9): горелка даёт луч.
## Горелка у входа, уголь в топку — красный луч через лагерь. Сумерки примерно
## через 40 с: безвредное эхо подходит к лучу и отступает.

## Метка на полу: куда ставить горелку, клеток от центра лагеря.
## +1 занят коридором сценариев, +2 и +5 — панели базы, +3 — лампа.
const MARK_DX: int = 7
## Сколько ждать сумерек после угля в топке, с игрового времени.
const DUSK_WAIT: float = 40.0
## Эхо уже отступило от луча (кадр мог пройти до проверки сценария).
var _retreated: bool = false
## Эхо этой ночи уже выпущено (один раз).
var _echo_out: bool = false


func _init() -> void:
	id = "fire"
	chapter = 2
	title = "Огонь"
	brief = "Уголь есть. Горелка жжёт его и бьёт красным лучом — эхо от луча отступает."
	teaches = "горелка: поставить, положить уголь, красный луч"
	director = false
	start_time = 0.35
	# Солнце стоит, пока горелка не зажжена. Потом — до сумерек около 40 с.
	hold_time = 0.40


func build() -> void:
	CampaignBase.build(CampaignBase.Tier.STATION)
	var m: Vector2i = mark()
	# Метка и воздух над ней: луч идёт вверх через лагерь, не в пол.
	for dy in range(0, 8):
		var c: Vector2i = m + Vector2i(0, -dy)
		if World.get_tile_v(c) != IDs.T.AIR:
			World.set_tile(c.x, c.y, IDs.T.AIR)



func kit() -> Array:
	return [[IDs.I.BURNER, 1], [IDs.I.COAL, 3]]


func stages() -> Array:
	return [
		{"title": "Горелка",
			"hint": "Горелку ставят у метки на полу",
			"say": ["Горелка — наш свет. Поставь её у метки."],
			"goals": [["Поставь горелку у входа", func() -> Vector2i:
				return Vector2i(machines_of("Burner"), 1),
				IDs.I.BURNER, func() -> Vector2: return World.cell_to_world(mark())]]},
		{"title": "Уголь",
			"hint": "Уголь в руке — и горелка зажигается",
			"say": ["Положи уголь в горелку. Луч пойдёт сам."],
			"goals": [["Положи уголь в горелку", func() -> Vector2i:
				return flag(_burner_lit()),
				IDs.I.COAL, func() -> Vector2: return _burner_at()]],
			"done": _after_coal},
		{"title": "Сумерки",
			"hint": "Эхо подходит к лучу и отступает",
			"say": ["Ждём сумерек. Эхо само подойдёт — и само уйдёт."],
			"goals": [["Дождись сумерек", func() -> Vector2i:
				return flag(_echo_retreated()),
				IDs.I.BURNER, func() -> Vector2: return _burner_at()]]},
	]


func on_tick(_delta: float) -> void:
	# Эхо выходит с ночью, не раньше: за 40 с ожидания оно ушло бы в глубину.
	if stage != 2 or not Game.is_night() or _echo_out:
		return
	_echo_out = true
	var spot: Vector2i = _echo_spot()
	var made: Array = Threat.spawn_phantom("echo", World.cell_to_world(spot), {"harmless": true})
	if made.is_empty():
		_echo_out = false
	else:
		Threat.chapter_echo = true


func outro() -> String:
	return "Красный луч через весь лагерь. Эхо подошло — и отступило."


## Метка на полу лагеря: пустая клетка справа от центра.
func mark() -> Vector2i:
	return Vector2i(World.beacon_cell.x + MARK_DX, World.beacon_cell.y)


func _burner() -> Burner:
	for c in World.machines:
		var m = World.machines[c]
		if m is Burner and is_instance_valid(m):
			return m
	return null


func _burner_at() -> Vector2:
	var b: Burner = _burner()
	if b == null:
		return World.cell_to_world(mark())
	return b.global_position


## Уголь в топке и луч красный. Эхо планируем здесь же: done и enter
## зовутся из того же _process, и волна с нулевой задержкой сгорает сразу.
func _burner_lit() -> bool:
	var b: Burner = _burner()
	if b == null or not b.burning() or b.color != Beams.R:
		return false
	if World.beams == null or World.beams.color_at(b.cell + Vector2i(0, -1)) != Beams.R:
		return false
	return true


## Уголь в топке: солнце идёт к сумеркам. Эхо выйдет в on_tick, с сумерками.
func _after_coal() -> void:
	_release_sun()


## Солнце больше не стоит: до сумерек около 40 с игрового времени.
func _release_sun() -> void:
	var dusk_in: float = Balance.DUSK_START - Game.time_of_day
	if dusk_in < 0.0:
		dusk_in += 1.0
	var want: float = DUSK_WAIT / Balance.DAY_LENGTH
	if dusk_in > want + 0.002:
		Game.time_of_day = Balance.DUSK_START - want
	# Ночь короче 60 с: солнце дойдёт до NIGHT_START и встанет на 50 с.
	hold_time = Balance.NIGHT_START + 50.0 / Balance.DAY_LENGTH


## Эхо вышло, подошло к лучу и отступило. Пока его нет — этап не закрыт,
## и on_tick ещё успевает его выпустить.
## Флаг копится: эхо у луча живёт один кадр, сценарий может не застать его в группе.
func _echo_retreated() -> bool:
	if _retreated:
		return true
	if not Game.is_night():
		return false
	for n in get_tree().get_nodes_in_group("phantom"):
		if not is_instance_valid(n) or not (n is Phantom):
			continue
		var p: Phantom = n
		if p.state == Phantom.St.FLEE and bool(p.get("harmless")):
			_retreated = true
			return true
	return false



