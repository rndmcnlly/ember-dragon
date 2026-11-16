## The ground the dragon moves over: one tile kind per cell (Type Object).
## Rules ask what a kind means, never which kind it is, so a new kind is a new
## row in TILES plus a piece of the same name in tools/build_art.py.
class_name Board
extends RefCounted

signal changed(cells: Array)  # tiles changed during play; the Stage redraws

## What each tile kind means to the rules. Every row has every column, so the table
## reads like a spreadsheet:
##   solid   the head cannot enter; it crashes against the tile
##   deadly  the head may enter, and that is the end of it
##   pace    how fast the dragon flies while its head is here (1.0 is normal)
##   spawns  embers and pickups may appear here
const TILES := {
	"floor": {"solid": false, "deadly": false, "pace": 1.0, "spawns": true},
	"wall": {"solid": true, "deadly": false, "pace": 1.0, "spawns": false},
	"lava": {"solid": false, "deadly": true, "pace": 1.0, "spawns": false},
	"water": {"solid": false, "deadly": false, "pace": 0.5, "spawns": false},
	"bridge": {"solid": false, "deadly": false, "pace": 1.0, "spawns": true},
}

var size: Vector2i
var tiles := {}  # Vector2i cell -> tile kind name
var start := Vector2i.ZERO  # where the dragon's head hatches
var facing := Vector2i.RIGHT  # and which way it looks; the body trails behind


## A floor ringed by walls: the default when no level file is loaded.
static func bordered(grid_size: Vector2i) -> Board:
	var board := Board.new()
	board.size = grid_size
	board.start = grid_size / 2
	for x in grid_size.x:
		for y in grid_size.y:
			var edge := x == 0 or y == 0 or x == grid_size.x - 1 or y == grid_size.y - 1
			board.tiles[Vector2i(x, y)] = "wall" if edge else "floor"
	return board


## A fresh copy to play on, so changes during one game never reach the next.
func copy() -> Board:
	var board := Board.new()
	board.size = size
	board.tiles = tiles.duplicate()
	board.start = start
	board.facing = facing
	return board


## Change many cells at once and tell listeners once.
func set_kinds(cells: Array, kind: String) -> void:
	for cell in cells:
		tiles[cell] = kind
	if not cells.is_empty():
		changed.emit(cells)


## Every cell the dragon could fly to from here, avoiding walls and lava (a flood fill).
func reachable(from: Vector2i) -> Dictionary:
	var seen := {from: true}
	var frontier: Array[Vector2i] = [from]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		for step in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = cell + step
			if not (seen.has(next) or is_solid(next) or is_deadly(next)):
				seen[next] = true
				frontier.append(next)
	return seen


func kind_at(cell: Vector2i) -> String:
	return tiles.get(cell, "wall")  # off the board counts as wall


func is_solid(cell: Vector2i) -> bool:
	return TILES[kind_at(cell)].solid


func is_deadly(cell: Vector2i) -> bool:
	return TILES[kind_at(cell)].deadly


func pace_at(cell: Vector2i) -> float:
	return TILES[kind_at(cell)].pace


func spawns_at(cell: Vector2i) -> bool:
	return TILES[kind_at(cell)].spawns
