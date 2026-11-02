extends "res://tools/mp/scenarios/mp_players_base.gd"
## Общее сценариев «Кооператив» (MP-I, #94): mp_death, mp_team_wipe, mp_vent_one,
## mp_relay_coop, mp_save_rejoin, mp_disconnect.
##
## Повторный вход того же клиента (тот же uid): хост запускает процесс клиента i ещё раз
## (relaunch), у второго запуска есть флаг REJOIN_FLAG — сценарий клиента по нему
## понимает, что он «вернувшийся».

const REJOIN_FLAG: String = "--mp94-rejoin"

## Уведомления этого процесса (Game.notification) с начала сценария.
var notes: Array = []
## Хост: сколько раз запущен клиент i.
var _launches: Dictionary = {}


func _ready() -> void:
	Game.notification.connect(_on_note)


func _exit_tree() -> void:
	if Game.notification.is_connected(_on_note):
		Game.notification.disconnect(_on_note)


func _on_note(text: String, _color: Color) -> void:
	notes.append(text)


## Сколько уведомлений содержит часть текста.
func notes_with(part: String) -> int:
	var n: int = 0
	for t in notes:
		if String(t).contains(part):
			n += 1
	return n


func coop() -> NetCoop:
	return scene.get("net_coop") as NetCoop


func end_screen() -> EndScreen:
	return scene.get("end_screen") as EndScreen


## Одно нажатие (несколько физических кадров — пакет ввода уходит раз в 2 кадра).
func tap(code: int) -> void:
	hold(code)
	for _k in 4:
		await get_tree().physics_frame
	release(code)
	for _k in 2:
		await get_tree().physics_frame


## Хост: убить героя (свой или прокси) — обычный урон, мешок и died.
func kill(p: Player) -> void:
	p.invuln = 0.0
	p.damage(10000.0, Vector2.ZERO)


## Мешки погибших на земле.
func bags() -> Array:
	var out: Array = []
	for c in Save._item_nodes():
		if not (c as ItemEntity).bag.is_empty():
			out.append(c)
	return out


func bag_of(uid: int) -> ItemEntity:
	for b in bags():
		if (b as ItemEntity).bag_owner == uid:
			return b
	return null


## Свой герой этого процесса на базе (у капсулы).
func at_base(p: Player, d: float = 40.0) -> bool:
	return p.global_position.distance_to(World.spawn_point) < d


# ------------------------------------------------------------------ ПОВТОРНЫЙ ВХОД

func client_args(i: int) -> PackedStringArray:
	var a: PackedStringArray = PackedStringArray(["--nick=" + ["Аня", "Борис", "Вера"][mini(i, 2)]])
	var n: int = int(_launches.get(i, 0))
	_launches[i] = n + 1
	if n > 0:
		a.append(REJOIN_FLAG)
	return a


## Клиент: это второй запуск того же клиента?
static func is_rejoin() -> bool:
	return OS.get_cmdline_user_args().has(REJOIN_FLAG)


## Хост: запустить клиента i ещё раз (тот же uid).
func relaunch(i: int) -> void:
	mp().launch(i)


## Хост: «обрыв» — убить процесс клиента i. Его запись убирается из списка процессов
## раннера: убитый не напечатает ИТОГ, и это не провал сценария, а его суть.
func kill_client(i: int) -> bool:
	for c in mp().children.duplicate():
		if int(c["i"]) != i or bool(c["done"]):
			continue
		var pid: int = int(c["pid"])
		mp()._drain(c)
		OS.kill(pid)
		await wait_until(func() -> bool: return not OS.is_process_running(pid), 5.0)
		mp().children.erase(c)
		return not OS.is_process_running(pid)
	return false
