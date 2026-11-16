## Procedural terrain: a map grown from a seed instead of drawn in a text file. The
## same seed always grows the same map, so a seed is a level you can share.
##
## A second level source next to levels/*.txt (Strategy): Campaign.Step.load_level()
## asks a file or this generator, and either way hands back a Level. Nothing after
## that knows the difference, so the Arena, the Stage, replays, and the reachability
## test treat a grown map exactly like a drawn one.
##
## Four steps, in order, each a few lines and each drawing from the same seeded rng:
##   carve    floor ringed by wall, a start for the dragon, and a clearing around it
##   river    a band of water winding from top to bottom, crossed by bridges
##   scatter  rock clusters and lava pools on open floor, never in the clearing
##   verify   flood-fill from the start; floor it cannot reach becomes rock
class_name Terrain
extends RefCounted

const NAME := "wilds"  # the campaign's name for a grown map (see Campaign.wilds)
const SIZE := Vector2i(38, 24)  # The Ford's size, walls included
const CLEARING := 3  # only floor within this many moves of the start...
const RUNWAY := 6  # ...and this many cells straight ahead of it
const RIVER_WIDTH := 3
const BRIDGES := 2
const ROCKS := 12  # clusters of wall
const POOLS := 3  # pools of lava
const STEPS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

var seed := 0
var board: Board
var rng := RandomNumberGenerator.new()  # every step draws from it, in order
var _clearing := {}  # cells the later steps leave alone


func _init(from_seed: int) -> void:
	seed = from_seed
	rng.seed = from_seed


## The grown map as a Level, titled with its seed so a screenshot is enough to share it.
func level() -> Level:
	var grown := Level.new()
	grown.name = NAME
	grown.title = "The Wilds, seed %d" % seed
	grown.blurb = "A map grown from its seed. Same seed, same map: pass it on."
	grown.board = grow()
	return grown


func grow() -> Board:
	_carve()
	_river()
	_scatter()
	_verify()
	return board


## Floor ringed by wall, and a start near one side facing across the map. The start,
## the body behind it, its runway ahead, and every cell a few moves away are the
## clearing: open floor no later step may paint, so the first seconds are always fair.
func _carve() -> void:
	board = Board.bordered(SIZE)
	board.facing = Vector2i.RIGHT if rng.randi_range(0, 1) == 0 else Vector2i.LEFT
	var inset := rng.randi_range(5, 9)  # from the side behind the dragon
	var x := inset if board.facing == Vector2i.RIGHT else SIZE.x - 1 - inset
	board.start = Vector2i(x, rng.randi_range(5, SIZE.y - 6))
	for cell in board.tiles:
		if _distance(cell, board.start) <= CLEARING:
			_clearing[cell] = true
	for i in range(1 - Level.START_LENGTH, RUNWAY + 1):
		_clearing[board.start + board.facing * i] = true


## A river from the top wall to the bottom one, in the half of the map the dragon flies
## toward, so it never touches the clearing. It drifts a column at a time (diagonal
## rows stay joined, as in The Ford) and is crossed by bridges on a few rows.
func _river() -> void:
	var eastward := board.start.x < SIZE.x / 2
	var lowest := SIZE.x / 2 if eastward else 3
	var highest := SIZE.x - 3 - RIVER_WIDTH if eastward else SIZE.x / 2 - RIVER_WIDTH - 1
	var x := rng.randi_range(lowest, highest)
	var drift := 0
	var spans := {}  # row -> the river's cells on it
	for y in range(1, SIZE.y - 1):
		if rng.randf() < 0.5:  # often keep going the same way: long, lazy bends
			drift = rng.randi_range(-1, 1)
		x = clampi(x + drift, lowest, highest)
		spans[y] = []
		for i in RIVER_WIDTH:
			spans[y].append(Vector2i(x + i, y))
		board.set_kinds(spans[y], "water")
	var band := (SIZE.y - 4) / BRIDGES  # one bridge per band of rows, so they spread out
	for i in BRIDGES:
		board.set_kinds(spans[2 + band * i + rng.randi_range(0, band - 1)], "bridge")


## Rocks and lava as short random walks over open floor: lumpy blobs, not squares.
func _scatter() -> void:
	for i in ROCKS:
		_blob("wall", rng.randi_range(5, 14))
	for i in POOLS:
		_blob("lava", rng.randi_range(4, 10))


func _blob(kind: String, cells: int) -> void:
	var cell := Vector2i(rng.randi_range(1, SIZE.x - 2), rng.randi_range(1, SIZE.y - 2))
	for i in cells:
		if _paintable(cell):
			board.tiles[cell] = kind
		cell += STEPS[rng.randi_range(0, STEPS.size() - 1)]


## Open floor outside the clearing, and not at a bridge's end (a bridge that lands on
## a rock is a bridge to nowhere).
func _paintable(cell: Vector2i) -> bool:
	if board.kind_at(cell) != "floor" or _clearing.has(cell):
		return false
	return not STEPS.any(
		func(step: Vector2i) -> bool: return board.kind_at(cell + step) == "bridge"
	)


## Rocks and lava can wall off a pocket of floor. Rather than hope they did not, fill
## every cell where an ember could land but the dragon could never reach (the same
## flood fill that checks the drawn levels) with rock.
func _verify() -> void:
	var reached := board.reachable(board.start)
	var sealed := []
	for cell in board.tiles:
		if board.spawns_at(cell) and not reached.has(cell):
			sealed.append(cell)
	board.set_kinds(sealed, "wall")


func _distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
