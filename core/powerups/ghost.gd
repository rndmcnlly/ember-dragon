## Pass through your own body. Careful: if it wears off mid-overlap, the next bite counts.
class_name GhostPowerup
extends Powerup


func _init() -> void:
	title = "Ghost"
	duration = 40


func start(session: Session) -> void:
	session.ghost = true


func finish(session: Session) -> void:
	session.ghost = false
