## Pass through your own body. Careful: if it wears off mid-overlap, the next bite counts.
class_name GhostPowerup
extends Powerup


func _init() -> void:
	title = "Ghost"
	duration = 40


func start(arena: Arena) -> void:
	arena.ghost = true


func finish(arena: Arena) -> void:
	arena.ghost = false
