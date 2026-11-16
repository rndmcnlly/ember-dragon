## The player's controller. game/main.gd forwards each arrow key with press(); the
## turns wait here until the next tick, then go to the dragon in the order pressed,
## so two quick taps between ticks are still two turns (Command).
class_name PlayerController
extends Controller

var pending: Array[Vector2i] = []  # pressed since the last tick


func press(direction: Vector2i) -> void:
	pending.append(direction)


func steer(_arena: Arena, dragon: Dragon) -> void:
	for direction in pending:
		dragon.turn(direction)
	pending.clear()
