extends "res://scripts/main.gd"
## Кадр приёмки: Main._ready не должен затереть _args, куда кадр положил --seed=.


func _ready() -> void:
	if _net_boot():
		return
	_start()
