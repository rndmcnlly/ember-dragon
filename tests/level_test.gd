extends "res://tests/test_case.gd"

const TINY := """title: Tiny
blurb: A test.

######
#....#
#...>#
######
"""


func test_reads_headers_and_map() -> void:
	var level := Level.parse(TINY, "tiny.txt")
	assert_eq(level.errors, [] as Array[String])
	assert_eq(level.title, "Tiny")
	assert_eq(level.board.size, Vector2i(6, 4))
	assert_eq(level.board.kind_at(Vector2i(0, 0)), "wall")
	assert_eq(level.board.kind_at(Vector2i(2, 1)), "floor")


func test_the_arrow_places_and_points_the_dragon() -> void:
	var level := Level.parse(TINY, "tiny.txt")
	assert_eq(level.board.start, Vector2i(4, 2))
	assert_eq(level.board.facing, Vector2i.RIGHT)
	assert_eq(level.board.kind_at(level.board.start), "floor")
	var arena := Arena.new(level.board)
	assert_eq(arena.dragon.body[0], Vector2i(4, 2))
	assert_eq(arena.dragon.body[1], Vector2i(3, 2))


func test_every_legend_symbol_names_a_tile_kind() -> void:
	for symbol in Level.LEGEND:
		assert_true(Level.LEGEND[symbol] in Board.TILES)


func test_a_ragged_row_cites_its_line() -> void:
	var level := Level.parse("######\n#...>#\n#....\n######\n", "ragged.txt")
	assert_eq(
		level.errors, ["ragged.txt:3: this row is 5 wide but the first is 6"] as Array[String]
	)


func test_an_unknown_symbol_cites_line_and_column() -> void:
	var level := Level.parse("title: X\n\n######\n#...>#\n#.?..#\n", "odd.txt")
	assert_eq(level.errors.size(), 1)
	assert_true(level.errors[0].begins_with("odd.txt:5: unknown tile '?' in column 3"))


func test_a_map_needs_exactly_one_start() -> void:
	assert_eq(Level.parse("#....#", "none.txt").errors.size(), 1)
	var twice := Level.parse("#...>.....>#", "two.txt")
	assert_eq(twice.errors, ["two.txt:1: a second dragon start; the map needs exactly one"])


func test_the_body_needs_room_behind_the_head() -> void:
	var level := Level.parse("####\n#.>#\n####", "cramped.txt")
	assert_eq(level.errors, ["cramped.txt:2: the dragon needs 3 open cells behind its head"])


func test_headers_are_checked() -> void:
	var level := Level.parse("titel: Oops\n#...>#", "typo.txt")
	assert_eq(level.errors, ["typo.txt:1: unknown header 'titel' (try title, blurb)"])


## Every shipped level loads cleanly, and every cell where an ember may appear can be
## reached from the start without touching walls or lava. A sealed pocket fails here.
func test_every_level_is_clean_and_reachable() -> void:
	var names := Level.catalog()
	assert_true(names.size() >= 3)
	for level_name in names:
		var level := Level.load_file("res://levels/%s.txt" % level_name)
		assert_eq(level.errors, [] as Array[String])
		var reached := _reachable(level.board)
		for cell in level.board.tiles:
			if level.board.spawns_at(cell) and not reached.has(cell):
				failures.append("%s: ember spot %s cannot be reached" % [level_name, cell])
				break


func _reachable(board: Board) -> Dictionary:
	var seen := {board.start: true}
	var frontier: Array[Vector2i] = [board.start]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		for step in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = cell + step
			if seen.has(next) or board.is_solid(next) or board.is_deadly(next):
				continue
			seen[next] = true
			frontier.append(next)
	return seen
