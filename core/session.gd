## One run at one level: the board, the rules, and the score. No Nodes; the engine only
## listens to these signals (Observer) and reads the state to draw it.
class_name Session
extends RefCounted

signal ate(cell: Vector2i)
signal powered(powerup: Powerup)
signal died(reason: String)
signal won
signal ticked  # after every tick of play; levels' rules listen (see Rulebook)
signal announced(text: String)  # a message for the player, from a level's rules
signal rival_ate(cell: Vector2i)
signal rival_crashed(cell: Vector2i)  # where it hit; the rival is gone after this

enum State { READY, PLAYING, OVER, WON }

const GROWTH_PER_FOOD := 3
const PICKUP_CHANCE := 0.3  # chance that eating spawns a powerup pickup
const RIVAL_DISTANCE := 12  # a rival hatches at least this many moves from the player
const NOWHERE := Vector2i(-1000, -1000)  # the next cell of a dragon that is not there

## Add a Powerup subclass here and it can appear on the board.
var pickup_kinds: Array[GDScript] = [HastePowerup, GhostPowerup, TrimPowerup]
var board: Board
var dragon: Dragon  # the player's
var controller: Controller = Controller.new()  # steers it; app/main.gd sets a PlayerController
var rival: Dragon = null  # a second dragon, once a level summons one; null again if it crashes
var rival_controller: Controller = null
var rival_score := 0
var food: Vector2i
var pickup: Powerup = null  # waiting on the board at pickup_cell
var pickup_cell := Vector2i(-1, -1)
var active: Array[Powerup] = []
var score := 0
var ticks := 0  # ticks of play since the first move; the first tick is 1
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


## Ticks per base tick right now: the level's tempo, times Haste. This is the clock
## both dragons share; the ground sets each one's own pace on it (see will_move).
func pace() -> float:
	return tempo * speed


## Whether this dragon moves on the next tick. Every tick adds the pace of the ground
## under its head to its stride, and a full stride is one cell: on floor that is every
## tick, in water (pace 0.5) every other tick. One rule for both dragons, so the rival
## wades like you do, and wading with Haste comes out even.
func will_move(mover: Dragon) -> bool:
	return mover.stride + board.pace_at(mover.body[0]) >= 1.0


## Take this tick's stride; true if it completes a cell.
func _stride(mover: Dragon) -> bool:
	var moves := will_move(mover)
	mover.stride = minf(mover.stride + board.pace_at(mover.body[0]), 1.0)
	if moves:
		mover.stride -= 1.0
	return moves


## The dragon waits for the player's first move.
func start() -> void:
	if state == State.READY:
		state = State.PLAYING


## One step for every dragon at once. Both decide, then both crashes are judged on
## where everything was before anyone moved, so neither dragon has the first move.
## A dragon wading this tick (see will_move) is not steered and stays put: its "next"
## cell is its own head, so the other can still bump into it.
func tick() -> void:
	if state != State.PLAYING:
		return
	ticks += 1  # first, so the tick that ends the session counts too
	var moves := _stride(dragon)
	var rival_moves := rival != null and _stride(rival)
	if moves:
		controller.steer(self, dragon)
	if rival_moves:
		rival_controller.steer(self, rival)
	var next := dragon.steer() if moves else dragon.body[0]
	var rival_next := NOWHERE
	if rival != null:
		rival_next = rival.steer() if rival_moves else rival.body[0]
	var crash := _crash(dragon, next, rival_next)
	if not crash.is_empty():
		_die("You " + crash)
		return
	if rival != null:
		var rival_crash := _crash(rival, rival_next, next)
		if not rival_crash.is_empty():
			_rival_down("The rival " + rival_crash, rival_next)
	if moves:
		dragon.advance()
	if rival_moves and rival != null:
		rival.advance()
	if board.is_deadly(next):  # unlike a wall, the head goes in first
		_die("You fell into the %s" % board.kind_at(next))
		return
	if rival_moves and rival != null and board.is_deadly(rival_next):
		_rival_down("The rival fell into the %s" % board.kind_at(rival_next), rival_next)
	if moves and next == food:
		_eat()
	elif rival_moves and rival != null and rival_next == food:
		_rival_eat()
	if moves and pickup != null and next == pickup_cell:  # pickups are the player's alone
		_activate(pickup)
		pickup = null
	_age_powerups()
	if state == State.PLAYING:
		ticked.emit()


## What goes wrong if this dragon enters the cell while the other dragon's head enters
## other_next, as the end of a sentence ("ran into the wall"), or "" if nothing does.
## A dragon standing still (cell is its own head) can only be bumped into.
func _crash(mover: Dragon, cell: Vector2i, other_next: Vector2i) -> String:
	var still := cell == mover.body[0]
	if not still and board.is_solid(cell):
		return "ran into the %s" % board.kind_at(cell)
	if not still and mover.blocks(cell) and not (ghost and mover == dragon):
		return "bit %s own tail" % ("your" if mover == dragon else "its")
	var other := opponent(mover)
	if other == null or ghost:  # Ghost passes through the rival too, both ways
		return ""
	return _collide(mover, cell, other, other_next)


## Dragon against dragon. Head to head (the same cell, or swapping cells), the longer
## dragon wins, so every ember is armor too, and equals both fall. Otherwise the body
## is a wall, except a tail tip about to move away, as with your own tail.
func _collide(mover: Dragon, cell: Vector2i, other: Dragon, other_next: Vector2i) -> String:
	var swapped := cell == other.body[0] and other_next == mover.body[0]
	if cell == other_next or swapped:
		var size := mover.body.size()
		if size == other.body.size():
			return "met a dragon %s size head-on" % ("your" if mover == dragon else "its")
		return "met a bigger dragon head-on" if size < other.body.size() else ""
	if other.blocks(cell, other_next != other.body[0]):  # a wading tail stays put
		return "flew into the rival" if mover == dragon else "flew into you"
	return ""


func _eat() -> void:
	score += 1
	dragon.grow(GROWTH_PER_FOOD)
	ate.emit(food)
	if goal > 0 and score >= goal:
		state = State.WON
		won.emit()
		return
	_new_food()


## The rival eats like the player and races to the same goal.
func _rival_eat() -> void:
	rival_score += 1
	rival.grow(GROWTH_PER_FOOD)
	rival_ate.emit(food)
	if goal > 0 and rival_score >= goal:
		_die("The rival ate %d embers first" % goal)
		return
	_new_food()


func _new_food() -> void:
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
func is_clear(cell: Vector2i) -> bool:
	var taken := cell == food or cell == pickup_cell or on_a_dragon(cell)
	return board.spawns_at(cell) and not taken


## Ground a dragon could fly over now: not solid, not deadly, no body on it.
func is_open(cell: Vector2i) -> bool:
	return not (board.is_solid(cell) or board.is_deadly(cell) or on_a_dragon(cell))


## Whether either dragon's body covers this cell.
func on_a_dragon(cell: Vector2i) -> bool:
	return dragon.body.has(cell) or (rival != null and rival.body.has(cell))


## Whether a dragon entering this cell next tick would end it, whatever the other
## dragon does. The rival's AI asks this before every move.
func crashes(mover: Dragon, cell: Vector2i) -> bool:
	return board.is_deadly(cell) or not _crash(mover, cell, NOWHERE).is_empty()


## The other dragon, or null when there is only one.
func opponent(of: Dragon) -> Dragon:
	return rival if of == dragon else dragon


## Whether a cell is within reach of either head in a few moves; changing the ground
## there would be a trap no one could see coming.
func near_head(cell: Vector2i, moves := 3) -> bool:
	for head in [dragon.body[0], rival.body[0] if rival != null else NOWHERE]:
		var gap: Vector2i = (cell - head).abs()
		if gap.x + gap.y <= moves:
			return true
	return false


## Hatch a rival far from the player, on clear ground with room for its body behind
## it, steered by the given controller (the AI by default). Returns false if no spot
## is free. The spot is picked with the seeded rng, like everything else that is random.
func summon_rival(steering: Controller = null) -> bool:
	if rival != null:
		return false
	var spots := []  # [head, facing]
	for cell in board.tiles:
		var gap: Vector2i = (cell - dragon.body[0]).abs()
		if gap.x + gap.y < RIVAL_DISTANCE:
			continue
		for facing in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			if _room_to_hatch(cell, facing):
				spots.append([cell, facing])
	if spots.is_empty():
		return false
	var spot: Array = spots[rng.randi_range(0, spots.size() - 1)]
	rival = Dragon.new(spot[0], dragon.body.size(), spot[1])
	rival_controller = steering if steering != null else GreedyController.new()
	return true


## The head, the body behind it, and two cells ahead, all clear.
func _room_to_hatch(head: Vector2i, facing: Vector2i) -> bool:
	for i in range(-2, Level.START_LENGTH):
		if not is_clear(head - facing * i):
			return false
	return true


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


## The rival is out of the level; the player flies on alone.
func _rival_down(reason: String, cell: Vector2i) -> void:
	rival = null
	rival_controller = null
	announce(reason + "!")
	rival_crashed.emit(cell)


## A random clear cell for food or a pickup.
func _empty_cell() -> Vector2i:
	while true:
		var cell := Vector2i(
			rng.randi_range(0, board.size.x - 1), rng.randi_range(0, board.size.y - 1)
		)
		if is_clear(cell):
			return cell
	return Vector2i.ZERO
