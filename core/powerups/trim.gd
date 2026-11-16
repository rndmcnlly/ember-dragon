## Instantly lose five tail segments: room to breathe in a crowded board.
class_name TrimPowerup
extends Powerup


func _init() -> void:
	title = "Trim"


func start(session: Session) -> void:
	session.dragon.shrink(5)
