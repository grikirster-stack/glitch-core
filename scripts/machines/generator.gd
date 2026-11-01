class_name Generator
extends MachineBase
## Базовый генератор энергии.

func _init() -> void:
	kind = "Generator"
	z_index = 3


func _draw_power_ring(color: Color) -> void:
	if power_radius <= 0.0:
		return
	var r: float = power_radius * World.TILE
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(color.r, color.g, color.b, 0.12), 2.0)
