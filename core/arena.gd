## One game: the board, the rules, and the score. No Nodes; the engine only
## listens to these signals (Observer) and reads the state to draw it.
class_name Arena
extends RefCounted

signal ate(cell: Vector2i)
signal powered(powerup: Powerup)
signal died(reason: String)
signal won
signal ticked  # after every tick of play; levels' rules listen (see Rulebook)
signal announced(text: String)  # a message for the player, from a level's rules

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
var ticks := 0  # ticks of play since the first move
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
	ticks += 1
	if state == State.PLAYING:
		ticked.emit()


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


func announce(text: String) -> void:
	announced.emit(text)


## Put the ember somewhere new.
func move_food() -> void:
	food = _empty_cell()


## Put a pickup of this kind on the board, replacing any waiting one.
func drop(kind: GDScript) -> void:
	pickup = kind.new()
	pickup_cell = _empty_cell()


## Open ground with nothing on it: where embers, pickups, and spreading tiles may go.
## (A rival dragon would be checked here too.)
func is_clear(cell: Vector2i) -> bool:
	var taken := dragon.body.has(cell) or cell == food or cell == pickup_cell
	return board.spawns_at(cell) and not taken


## Whether a cell is within reach of the head in a few moves; changing the ground
## there would be a trap the player could not see coming.
func near_head(cell: Vector2i, moves := 3) -> bool:
	var gap := (cell - dragon.body[0]).abs()
	return gap.x + gap.y <= moves


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


## A random clear cell for food or a pickup.
func _empty_cell() -> Vector2i:
	while true:
		var cell := Vector2i(
			rng.randi_range(0, board.size.x - 1), rng.randi_range(0, board.size.y - 1)
		)
		if is_clear(cell):
			return cell
	return Vector2i.ZERO
