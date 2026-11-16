## Instantly lose five tail segments: room to breathe in a crowded arena.
class_name TrimPowerup
extends Powerup


func _init() -> void:
	title = "Trim"


func start(arena: Arena) -> void:
	arena.dragon.shrink(5)
