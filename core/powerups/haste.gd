## Double speed for a while: more risk, same score per food.
class_name HastePowerup
extends Powerup


func _init() -> void:
	title = "Haste"
	duration = 60


func start(session: Session) -> void:
	session.speed = 2.0


func finish(session: Session) -> void:
	session.speed = 1.0
