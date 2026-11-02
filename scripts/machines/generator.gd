class_name Generator
extends MachineBase
## Базовый генератор энергии (ADR-001, § 4.3).
##
## Генератор даёт power_output в радиусе power_radius, пока power_active.
## Game.update_power_budget() раз в 0.25 с раскладывает потребителей по
## ближайшему активному генератору и пишет сюда нагрузку (power_load) и
## отношение мощности к нагрузке (efficiency, поле MachineBase).
## Рубильник (enabled): E по генератору — вкл/выкл.

## Сколько мощности даёт генератор, когда работает (Balance.POWER_OUT).
var power_output: float = 0.0
## Нагрузка: сумма power_draw потребителей, которые питаются от этого генератора.
## (В ADR поле названо `load`, но так называется встроенная функция GDScript.)
var power_load: float = 0.0
## Рубильник. Выключенный генератор не даёт питания (ТЭЦ при этом не жжёт уголь).
var enabled: bool = true
## Номер физического кадра последнего interact(): игрок вызывает его каждый
## кадр, пока держит E, — переключаем только на первом кадре нажатия.
var _interact_frame: int = -10


func _init() -> void:
	kind = "Generator"
	z_index = 3


## Мощность, которую генератор отдаёт прямо сейчас.
func current_output() -> float:
	return power_output if power_active else 0.0


## Перегружен ли генератор (браун-аут в его радиусе).
func overloaded() -> bool:
	return power_active and power_load > power_output


## Крюк взаимодействия: игрок держит E рядом с генератором. Вызывается каждый
## физический кадр, пока клавиша зажата; срабатывает один раз на нажатие.
func interact(p) -> void:
	var f: int = Engine.get_physics_frames()
	var fresh: bool = f - _interact_frame > 1
	_interact_frame = f
	if fresh:
		_on_interact(p)


## Что делает нажатие E. Базовый генератор — только рубильник.
func _on_interact(_p) -> void:
	set_enabled(not enabled)


## Рубильник: включить/выключить генератор.
func set_enabled(on: bool) -> void:
	if on == enabled:
		return
	enabled = on
	if not on:
		power_active = false
	queue_redraw()
	Sfx.play("power", -10.0, 1.0 if on else 0.7)
	Game.notify("%s: %s" % [DB.item_name(machine_item_id(kind)), "ВКЛ" if on else "ВЫКЛ"],
			Color(0.6, 1.0, 0.6) if on else Color(1.0, 0.7, 0.4))


func _draw_power_ring(color: Color) -> void:
	if power_radius <= 0.0:
		return
	var r: float = power_radius * World.TILE
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(color.r, color.g, color.b, 0.12), 2.0)


## Лампа состояния: зелёная — норма, жёлтая — перегруз, красная — выключен.
func _draw_status_lamp(pos: Vector2) -> void:
	if not enabled:
		draw_circle(pos, 1.8, Color(0.9, 0.25, 0.2))
	elif overloaded():
		draw_circle(pos, 1.8, Color(1.0, 0.8, 0.2))
	elif power_active:
		draw_circle(pos, 1.8, Color(0.4, 1.0, 0.5))
