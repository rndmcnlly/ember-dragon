## One game: the board, the rules, and the score. No Nodes; the engine only
## listens to these signals (Observer) and reads the state to draw it.
class_name Arena
extends RefCounted

signal ate(cell: Vector2i)
signal powered(powerup: Powerup)
signal died(reason: String)
signal won

enum State { READY, PLAYING, OVER, WON }

const GROWTH_PER_FOOD := 3
const PICKUP_CHANCE := 0.3  # chance that eating spawns a powerup pickup

## Add a Powerup subclass here and it can appear on the board.
var pickup_kinds: Array[GDScript] = [HastePowerup, GhostPowerup, TrimPowerup]
var board: Board
var dragon: Dragon
var food: Vector2i
var pickup: Powerup = null  # waiting on the board at pickup_cell
var pickup_cell := Vector2i(-1, -1)
var active: Array[Powerup] = []
var score := 0
var goal := 0  # embers that clear the level; 0 means endless (Campaign.Step sets it)
var state := State.READY
var death := ""
var tempo := 1.0  # the level's base speed, from the campaign
var speed := 1.0  # HastePowerup doubles it
var ghost := false  # GhostPowerup lets the head pass through the body
var rng := RandomNumberGenerator.new()


func _init(ground: Board, seed := 0) -> void:
	board = ground
	rng.seed = seed
	dragon = Dragon.new(board.start, 4, board.facing)
	food = _empty_cell()


## Ticks per base tick right now: the level's tempo, times Haste, times the ground
## under the head (so wading through water with Haste comes out even).
func pace() -> float:
	return tempo * speed * board.pace_at(dragon.body[0])


## The dragon waits for the player's first move.
func start() -> void:
	if state == State.READY:
		state = State.PLAYING


func tick() -> void:
	if state != State.PLAYING:
		return
	var next := dragon.steer()
	if board.is_solid(next):
		_die("You ran into the %s" % board.kind_at(next))
		return
	if dragon.blocks(next) and not ghost:
		_die("You bit your own tail")
		return
	dragon.advance()
	if board.is_deadly(next):  # unlike a wall, the head goes in first
		_die("You fell into the %s" % board.kind_at(next))
		return
	if next == food:
		_eat()
	if pickup != null and next == pickup_cell:
		_activate(pickup)
		pickup = null
	_age_powerups()


func _eat() -> void:
	score += 1
	dragon.grow(GROWTH_PER_FOOD)
	ate.emit(food)
	if goal > 0 and score >= goal:
		state = State.WON
		won.emit()
		return
	food = _empty_cell()
	if pickup == null and not pickup_kinds.is_empty() and rng.randf() < PICKUP_CHANCE:
		pickup = pickup_kinds[rng.randi_range(0, pickup_kinds.size() - 1)].new()
		pickup_cell = _empty_cell()


func _activate(powerup: Powerup) -> void:
	for running in active.filter(func(p): return p.title == powerup.title):
		running.finish(self)
		active.erase(running)
	powerup.start(self)
	powered.emit(powerup)
	if powerup.duration > 0:
		powerup.remaining = powerup.duration
		active.append(powerup)


func _age_powerups() -> void:
	for powerup in active.duplicate():
		powerup.remaining -= 1
		if powerup.remaining <= 0:
			powerup.finish(self)
			active.erase(powerup)


func _die(reason: String) -> void:
	state = State.OVER
	death = reason
	died.emit(reason)


## A random cell where food or a pickup may appear: open ground with nothing on it.
func _empty_cell() -> Vector2i:
	while true:
		var cell := Vector2i(
			rng.randi_range(0, board.size.x - 1), rng.randi_range(0, board.size.y - 1)
		)
		var taken := dragon.body.has(cell) or cell == food or cell == pickup_cell
		if not taken and board.spawns_at(cell):
			return cell
	return Vector2i.ZERO
