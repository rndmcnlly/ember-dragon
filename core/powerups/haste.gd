## Double speed for a while: more risk, same score per food.
class_name HastePowerup
extends Powerup


func _init() -> void:
	title = "Haste"
	duration = 60


func start(arena: Arena) -> void:
	arena.speed = 2.0


func finish(arena: Arena) -> void:
	arena.speed = 1.0
