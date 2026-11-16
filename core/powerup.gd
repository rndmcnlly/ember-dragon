## A pickup's effect (Strategy): each subclass changes the Session in its own way,
## and the Session never needs to know which one it holds.
class_name Powerup
extends RefCounted

var title := "Powerup"
var duration := 0  # in ticks; 0 means the effect is instant
var remaining := 0


func start(_session: Session) -> void:
	pass


func finish(_session: Session) -> void:
	pass
