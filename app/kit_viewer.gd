## deno task kit: see the kit as the game will, under the game's own lighting.
## On a small map with every tile kind (lava and water animated, as in play), the
## hero and the rival bend through turns both ways, drawn by the game's own
## DragonView. In front of the board, every piece in the kit stands in a row with
## its name: the dragon, the rival, props, then tiles (the .glb's own rows).
extends Node3D

## Drawn with the level legend (levels/README.md), so the board is a Level like any other.
const MAP := """
##############
#.......>....#
#............#
#..........%%#
#.........%%%#
#............#
#............#
#.~~=~~......#
#.~~=~~......#
##############
"""
## Bodies, head first like Dragon.body, each with a left and a right turn.
const HERO: Array[Vector2i] = [
	Vector2i(8, 1),
	Vector2i(7, 1),
	Vector2i(6, 1),
	Vector2i(5, 1),
	Vector2i(5, 2),
	Vector2i(5, 3),
	Vector2i(4, 3),
	Vector2i(3, 3),
	Vector2i(3, 4),
	Vector2i(3, 5),
]
const RIVAL: Array[Vector2i] = [
	Vector2i(12, 6),
	Vector2i(11, 6),
	Vector2i(10, 6),
	Vector2i(10, 7),
	Vector2i(10, 8),
	Vector2i(9, 8),
	Vector2i(8, 8),
]
const SPACING := 1.8  # between pieces in a catalog row; wide enough for "rival_straight"

var meshes := {}
var views: Array[DragonView] = []
var camera := Camera3D.new()
var _angle := 0.0
var _center := Vector3.ZERO


func _ready() -> void:
	meshes = Stage.load_kit()
	var level := Level.parse(MAP, "kit_viewer")
	for problem in level.errors:
		push_warning(problem)
	var stage := Stage.new(meshes)
	add_child(stage)
	stage.draw_board(level.board)
	for body in [HERO, RIVAL]:
		var view := DragonView.new(meshes, "rival_" if body == RIVAL else "")
		add_child(view)
		view.reset(body)
		views.append(view)
	var rows := _catalog()
	for row in rows.size():
		for column in rows[row].size():
			var spot := Vector3(1.0 + column * SPACING, 0, level.board.size.y + 1.5 + row * 1.6)
			_show(rows[row][column], spot)
	# Orbit the middle of everything: the board and the catalog in front of it.
	_center = Vector3(level.board.size.x / 2.0, 0, (level.board.size.y + 1.5 + rows.size()) / 2.0)
	add_child(camera)


func _process(delta: float) -> void:
	views[0].draw(HERO, 1.0, delta)  # t = 1: at rest on its cells, rippling as in play
	views[1].draw(RIVAL, 1.0, delta)
	_angle += delta * 0.2  # a slow orbit, so every side of every piece comes around
	camera.position = _center + Vector3(sin(_angle) * 12.0, 9.0, cos(_angle) * 12.0)
	camera.look_at(_center)


## The kit's piece names in rows: the dragon (Kit.Piece), the rival's versions, tile
## kinds (Board.TILES), and whatever else the kit holds (props such as food).
func _catalog() -> Array:
	var dragon: Array = Kit.Piece.keys().map(func(piece): return piece.to_lower())
	var rival: Array = dragon.map(func(piece): return "rival_" + piece)
	var tiles: Array = Board.TILES.keys()
	var props: Array = meshes.keys().filter(
		func(piece): return piece not in dragon and piece not in rival and piece not in tiles
	)
	props.sort()
	return [dragon, rival, props, tiles]


## One raw kit mesh with a caption. Lava and water stand still here: Stage swaps in
## their shaders only when it draws a board.
func _show(piece: String, spot: Vector3) -> void:
	if piece not in meshes:
		push_warning("The kit has no piece named %s; run deno task art" % piece)
		return
	var node := MeshInstance3D.new()
	node.mesh = meshes[piece]
	node.position = spot
	add_child(node)
	var label := Label3D.new()
	label.text = piece
	label.font_size = 40
	label.outline_size = 10
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = spot + Vector3(0, 0.1, 0.8)  # a caption just in front of its piece
	add_child(label)
