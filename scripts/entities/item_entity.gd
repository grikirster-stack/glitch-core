class_name ItemEntity
extends Node2D
## Лежащий на земле предмет: притягивается к игроку, может попасть на конвейер.

var item_id: int = IDs.I.NONE
var count: int = 1
var vel: Vector2 = Vector2.ZERO
var grounded: bool = false
var age: float = 0.0
var magnet: bool = false
var pickup_delay: float = 0.45


func _ready() -> void:
	z_index = 4
	vel = Vector2(randf_range(-40.0, 40.0), randf_range(-130.0, -70.0))


func _physics_process(delta: float) -> void:
	age += delta
	pickup_delay = maxf(0.0, pickup_delay - delta)
	var player: Node2D = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var d: float = global_position.distance_to(player.global_position)
	if d < 70.0 and pickup_delay <= 0.0:
		magnet = true
	if magnet:
		var dir: Vector2 = (player.global_position - global_position).normalized()
		global_position += dir * 340.0 * delta
		if d < 14.0:
			var left: int = player.collect(item_id, count)
			if left <= 0:
				queue_free()
			else:
				count = left
				magnet = false
		return
	if grounded:
		return
	vel.y += 900.0 * delta
	var res: Dictionary = World.move_body(global_position, vel * delta, Vector2(10.0, 10.0))
	global_position = res["position"]
	if res["hit_y"]:
		vel.y = 0.0
		vel.x *= 0.7
		grounded = true
	if res["hit_x"]:
		vel.x = 0.0
	queue_redraw()


func _draw() -> void:
	var tex: ImageTexture = DB.item_texture(item_id)
	if tex == null:
		return
	draw_texture_rect(tex, Rect2(-7.0, -7.0, 14.0, 14.0), false, Color(1, 1, 1, 0.95))
	if count > 1:
		draw_rect(Rect2(-7.0, -9.0, 14.0, 8.0), Color(0, 0, 0, 0.45))
