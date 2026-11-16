## A pickup's effect (Strategy): each subclass changes the Arena in its own way,
## and the Arena never needs to know which one it holds.
class_name Powerup
extends RefCounted

var title := "Powerup"
var duration := 0  # in ticks; 0 means the effect is instant
var remaining := 0


func start(_arena: Arena) -> void:
	pass


func finish(_arena: Arena) -> void:
	pass
