## One game: the board, the rules, and the score. No Nodes; the engine only
## listens to these signals (Observer) and reads the state to draw it.
class_name Arena
extends RefCounted

signal ate(cell: Vector2i)
signal powered(powerup: Powerup)
signal died(reason: String)

enum State { READY, PLAYING, OVER }

const GROWTH_PER_FOOD := 3
const PICKUP_CHANCE := 0.3  # chance that eating spawns a powerup pickup

## Add a Powerup subclass here and it can appear on the board.
var pickup_kinds: Array[GDScript] = [HastePowerup, GhostPowerup, TrimPowerup]
var size: Vector2i
var dragon: Dragon
var food: Vector2i
var pickup: Powerup = null  # waiting on the board at pickup_cell
var pickup_cell := Vector2i(-1, -1)
var active: Array[Powerup] = []
var score := 0
var state := State.READY
var death := ""
var speed := 1.0  # ticks per base tick; HastePowerup raises it
var ghost := false  # GhostPowerup lets the head pass through the body
var rng := RandomNumberGenerator.new()


func _init(grid_size: Vector2i, seed := 0) -> void:
	size = grid_size
	rng.seed = seed
	dragon = Dragon.new(grid_size / 2)
	food = _empty_cell()


## The dragon waits for the player's first move.
func start() -> void:
	if state == State.READY:
		state = State.PLAYING


func tick() -> void:
	if state != State.PLAYING:
		return
	var next := dragon.steer()
	if not Rect2i(Vector2i.ZERO, size).has_point(next):
		_die("the wall")
		return
	if dragon.blocks(next) and not ghost:
		_die("your own tail")
		return
	dragon.advance()
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
	food = _empty_cell()
	if pickup == null and rng.randf() < PICKUP_CHANCE:
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


func _empty_cell() -> Vector2i:
	while true:
		var cell := Vector2i(rng.randi_range(0, size.x - 1), rng.randi_range(0, size.y - 1))
		if not dragon.body.has(cell) and cell != food and cell != pickup_cell:
			return cell
	return Vector2i.ZERO
