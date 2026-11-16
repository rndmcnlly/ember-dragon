extends "res://tests/test_case.gd"

const RULES := """# a comment, then a blank line

at tick 2: say "Hello, dragon."
every 3 ticks: spread lava 1
at score 1: replace lava with water
at score 2: place wall from 2,2 to 3,2
at tick 5: move ember
at tick 6: drop ghost
"""


func test_reads_one_rule_per_line() -> void:
	var book := Rulebook.parse(RULES, "test.rules")
	assert_eq(book.errors, [] as Array[String])
	assert_eq(book.rules.size(), 6)
	assert_true(book.rules[0].action is Rulebook.Say)
	assert_eq(book.rules[0].action.text, "Hello, dragon.")
	assert_eq(book.rules[1].trigger.kind, Rulebook.Trigger.Kind.EVERY)
	assert_eq(book.rules[1].trigger.n, 3)
	assert_eq(book.rules[3].action.corners, Rect2i(2, 2, 1, 0))
	assert_eq(book.rules[5].action.powerup, GhostPowerup)


func test_mistakes_cite_the_line() -> void:
	var cases := {
		"every 40 ticks spread lava 2": 'expected "when: what"',
		'sometimes: say "hi"': 'unknown trigger "sometimes"',
		"every zero ticks: move ember": "expected a whole number above 0",
		"at tick 1: sprad lava 2": 'unknown action "sprad"',
		"at tick 1: spread magma 2": 'unknown tile kind "magma"',
		"at tick 1: say hello": "say needs its words in quotes",
		"at tick 1: drop speed": 'expected "drop" and a powerup',
		"at tick 1: place lava at 3": 'expected "place KIND at X,Y"',
		"at tick 1: summon dragon": 'expected "summon rival"',
	}
	for line in cases:
		var book := Rulebook.parse("# first line\n" + line, "bad.rules")
		assert_eq(book.errors.size(), 1)
		if (
			book.errors.size() == 1
			and not book.errors[0].begins_with("bad.rules:2: " + cases[line])
		):
			failures.append("for %s got %s" % [line, book.errors[0]])


func test_triggers_fire_on_their_ticks() -> void:
	var arena := _arena('every 3 ticks: say "tick"\nat score 1: say "one"')
	var heard := []
	arena.announced.connect(func(text): heard.append(text))
	var each_tick := []
	for i in 9:
		if i == 7:
			arena.score = 1
		arena.tick()
		each_tick.append(" ".join(heard))
		heard.clear()
	assert_eq(each_tick, ["", "", "tick", "", "", "tick", "", "one", "tick"])


func test_spread_grows_next_to_its_kind_and_never_near_the_head() -> void:
	var arena := _arena("every 1 tick: spread lava 2")
	arena.board.set_kinds([Vector2i(1, 1)], "lava")
	arena.tick()
	var lava := arena.board.tiles.keys().filter(func(c): return arena.board.kind_at(c) == "lava")
	assert_eq(lava.size(), 3)
	for cell in lava:
		assert_true(not arena.near_head(cell))


func test_spread_never_seals_off_reachable_ground() -> void:
	# A corridor along the top row, whose only way in is down the left edge past (1, 3).
	var arena := _arena("every 1 tick: spread lava 50")
	for x in range(2, 23):
		arena.board.tiles[Vector2i(x, 2)] = "wall"
	arena.board.tiles[Vector2i(2, 3)] = "lava"  # right beside that chokepoint
	for i in 4:
		arena.tick()
	assert_eq(arena.board.kind_at(Vector2i(1, 3)), "floor")
	assert_true(arena.board.reachable(arena.dragon.body[0]).has(Vector2i(20, 1)))


func test_replace_and_place_change_the_board() -> void:
	var arena := _arena(
		"at tick 1: replace lava with water\nat tick 1: place bridge from 2,2 to 3,3"
	)
	arena.board.set_kinds([Vector2i(20, 20), Vector2i(20, 19)], "lava")
	var changed := []
	arena.board.changed.connect(func(cells): changed.append_array(cells))
	arena.tick()
	assert_eq(arena.board.kind_at(Vector2i(20, 20)), "water")
	assert_eq(arena.board.kind_at(Vector2i(3, 3)), "bridge")
	assert_eq(changed.size(), 6)


func test_every_shipped_rules_file_is_clean() -> void:
	var trail: Campaign = preload("res://levels/campaign.gd").ember_trail()
	for step in trail.steps:
		if not step.rules.is_empty():
			var book := Rulebook.load_file("res://levels/%s.rules" % step.rules)
			assert_eq(book.errors, [] as Array[String])
			assert_true(book.rules.size() > 0)


## A started arena running these rules: the dragon flies down the middle from near
## the top, and the ember waits in a far corner.
func _arena(rules: String) -> Arena:
	var board := Board.bordered(Vector2i(24, 24))
	board.start = Vector2i(12, 5)
	board.facing = Vector2i.DOWN
	var arena := Arena.new(board)
	var book := Rulebook.parse(rules)
	assert_eq(book.errors, [] as Array[String])
	book.attach(arena)
	arena.food = Vector2i(1, 22)
	arena.start()
	return arena
