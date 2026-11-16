## The player's controller. game/main.gd forwards each arrow key with press(); the
## turns wait here until the next tick, then go to the dragon in the order pressed,
## so two quick taps between ticks are still two turns (Command). Because commands
## only take effect on ticks, writing down which tick each went to records the whole
## game (see Replay).
class_name PlayerController
extends Controller

var pending: Array[Vector2i] = []  # pressed since the last tick
var log := {}  # tick -> the directions handed over on it; a Replay's turns


func press(direction: Vector2i) -> void:
	pending.append(direction)


func steer(arena: Arena, dragon: Dragon) -> void:
	if pending.is_empty():
		return
	log[arena.ticks] = pending.duplicate()
	for direction in pending:
		dragon.turn(direction)
	pending.clear()
