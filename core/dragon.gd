## The dragon's body and steering. The Arena decides what it may run into.
class_name Dragon
extends RefCounted

const MAX_QUEUED_TURNS := 2
const MIN_LENGTH := 2

var body: Array[Vector2i] = []  # head first
var heading := Vector2i.RIGHT
var _turns: Array[Vector2i] = []  # turns wait here until the next tick (Command)
var _growth := 0  # cells still to grow, one per tick


func _init(start: Vector2i, length := 4) -> void:
	for i in length:
		body.append(start - heading * i)


## Queue a turn. Ignored if it would reverse into the neck or repeat the last turn,
## so two quick key presses within one tick still behave.
func turn(direction: Vector2i) -> void:
	var last: Vector2i = heading if _turns.is_empty() else _turns.back()
	if direction == last or direction == -last or _turns.size() >= MAX_QUEUED_TURNS:
		return
	_turns.append(direction)


## Apply the next queued turn and return the cell the head is about to enter.
func steer() -> Vector2i:
	if not _turns.is_empty():
		heading = _turns.pop_front()
	return body[0] + heading


## Move the head forward; the tail follows unless the dragon is still growing.
func advance() -> void:
	body.push_front(body[0] + heading)
	if _growth > 0:
		_growth -= 1
	else:
		body.pop_back()


func grow(cells: int) -> void:
	_growth += cells


func shrink(cells: int) -> void:
	for i in mini(cells, body.size() - MIN_LENGTH):
		body.pop_back()


## Whether the head would hit the body by entering this cell. The tail tip is
## safe when it is about to move away, so a dragon may chase its own tail.
func blocks(cell: Vector2i) -> bool:
	var solid := body.size() if _growth > 0 else body.size() - 1
	return body.slice(0, solid).has(cell)
