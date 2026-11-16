extends "res://tests/test_case.gd"

const SIZE := Vector2i(16, 16)


func test_a_rival_hatches_far_away_on_clear_ground() -> void:
	for seed in 20:
		var arena := Arena.new(Board.bordered(SIZE), seed)
		assert_true(arena.summon_rival())
		var gap := (arena.rival.body[0] - arena.dragon.body[0]).abs()
		assert_true(gap.x + gap.y >= Arena.RIVAL_DISTANCE)
		assert_eq(arena.rival.body.size(), arena.dragon.body.size())
		for cell in arena.rival.body:
			assert_true(arena.board.spawns_at(cell) and not arena.dragon.body.has(cell))


func test_no_room_means_no_rival() -> void:
	var arena := Arena.new(Board.bordered(Vector2i(8, 8)))
	assert_true(not arena.summon_rival())
	assert_eq(arena.rival, null)


func test_embers_never_land_on_the_rival() -> void:
	var arena := _duel(Vector2i(10, 4), Vector2i.LEFT)
	for i in 200:
		arena.move_food()
		assert_true(not arena.rival.body.has(arena.food))


func test_the_ai_turns_toward_the_ember() -> void:
	var arena := _duel(Vector2i(10, 10), Vector2i.LEFT)
	arena.food = Vector2i(10, 3)  # straight up from the rival's head
	arena.tick()
	assert_eq(arena.rival.body[0], Vector2i(10, 9))


func test_the_ai_turns_away_from_a_wall() -> void:
	var arena := _duel(Vector2i(14, 10), Vector2i.RIGHT)  # the border is one cell ahead
	arena.food = Vector2i(14, 2)
	arena.tick()
	assert_eq(arena.rival.body[0], Vector2i(14, 9))


## The ember sits in a pocket too small for the rival's body. A plain greedy dragon
## would fly in and die there; the flood fill sees the trap and goes around.
func test_the_ai_will_not_enter_a_dead_end() -> void:
	var arena := _duel(Vector2i(8, 9), Vector2i.UP)
	for cell in [Vector2i(7, 8), Vector2i(9, 8), Vector2i(8, 7)]:
		arena.board.tiles[cell] = "wall"  # a one-cell pocket, open toward the rival
	arena.food = Vector2i(8, 8)
	arena.tick()
	assert_true(arena.rival.body[0] != Vector2i(8, 8))
	assert_eq(arena.rival.body.size(), 4)  # and it did not crash


func test_the_player_crashes_into_the_rival() -> void:
	var arena := _duel(Vector2i(8, 6), Vector2i.DOWN)  # the rival crosses in front
	arena.rival_controller = Controller.new()
	arena.dragon.body = [Vector2i(7, 4), Vector2i(6, 4), Vector2i(5, 4), Vector2i(4, 4)]
	arena.dragon.heading = Vector2i.RIGHT
	arena.rival.body = [Vector2i(8, 5), Vector2i(8, 4), Vector2i(8, 3), Vector2i(8, 2)]
	arena.tick()
	assert_eq(arena.death, "You flew into the rival")


func test_the_rival_crashes_into_the_player_and_is_gone() -> void:
	var arena := _duel(Vector2i(8, 6), Vector2i.DOWN)
	arena.rival_controller = Controller.new()  # fly straight, into the player
	arena.rival.body = [Vector2i(5, 3), Vector2i(5, 2), Vector2i(5, 1)]
	arena.rival.heading = Vector2i.DOWN
	arena.dragon.body = [Vector2i(7, 4), Vector2i(6, 4), Vector2i(5, 4), Vector2i(4, 4)]
	var heard := []
	arena.announced.connect(func(text): heard.append(text))
	arena.rival_crashed.connect(func(cell): heard.append(cell))
	arena.tick()
	assert_eq(arena.state, Arena.State.PLAYING)
	assert_eq(arena.rival, null)
	assert_eq(heard, ["The rival flew into you!", Vector2i(5, 4)])


func test_head_on_the_longer_dragon_wins() -> void:
	var arena := _head_on(5, 4)  # the player is longer
	arena.tick()
	assert_eq(arena.state, Arena.State.PLAYING)
	assert_eq(arena.rival, null)
	assert_eq(arena.dragon.body[0], Vector2i(8, 5))


func test_head_on_a_bigger_rival_ends_the_game() -> void:
	var arena := _head_on(3, 4)
	arena.tick()
	assert_eq(arena.death, "You met a bigger dragon head-on")


func test_head_on_between_equals_ends_the_game() -> void:
	var arena := _head_on(4, 4)
	arena.tick()
	assert_eq(arena.death, "You met a dragon your size head-on")


## Heads in neighboring cells flying at each other swap places without ever sharing
## a cell; that is still head-on.
func test_swapping_heads_is_head_on() -> void:
	var arena := _head_on(5, 4)
	arena.rival.body = [Vector2i(8, 5), Vector2i(9, 5), Vector2i(10, 5), Vector2i(11, 5)]
	arena.tick()
	assert_eq(arena.rival, null)


## One rule for both: the rival wades at half pace while the player, on dry ground,
## keeps flying every tick.
func test_the_rival_wades_through_water_too() -> void:
	var arena := _duel(Vector2i(6, 10), Vector2i.RIGHT)
	arena.rival_controller = Controller.new()
	for x in range(7, 12):
		arena.board.tiles[Vector2i(x, 10)] = "water"
	var player_head := arena.dragon.body[0]
	for i in 6:
		arena.tick()
	assert_eq(arena.dragon.body[0], player_head + Vector2i.RIGHT * 6)
	assert_eq(arena.rival.body[0], Vector2i(9, 10))  # one cell in, then two in five ticks
	assert_eq(arena.rival.body.size(), 4)


## A wading dragon's tail does not move away this tick, so it is no longer safe to
## follow into.
func test_a_wading_rivals_tail_stays_put() -> void:
	var arena := _duel(Vector2i(8, 6), Vector2i.DOWN)
	arena.rival_controller = Controller.new()
	arena.rival.body = [Vector2i(8, 6), Vector2i(8, 5), Vector2i(8, 4), Vector2i(8, 3)]
	arena.board.tiles[Vector2i(8, 6)] = "water"  # its head wades; it will not move
	arena.rival.stride = 0.0
	arena.dragon.body = [Vector2i(7, 3), Vector2i(6, 3), Vector2i(5, 3), Vector2i(4, 3)]
	arena.tick()
	assert_eq(arena.death, "You flew into the rival")


func test_ghost_passes_through_the_rival() -> void:
	var arena := _duel(Vector2i(8, 6), Vector2i.DOWN)
	arena.rival_controller = Controller.new()
	arena.dragon.body = [Vector2i(7, 4), Vector2i(6, 4), Vector2i(5, 4), Vector2i(4, 4)]
	arena.rival.body = [Vector2i(8, 5), Vector2i(8, 4), Vector2i(8, 3), Vector2i(8, 2)]
	arena._activate(GhostPowerup.new())
	arena.tick()
	assert_eq(arena.state, Arena.State.PLAYING)
	assert_true(arena.rival != null)


func test_the_rival_eats_and_can_win_the_race() -> void:
	var arena := _duel(Vector2i(10, 10), Vector2i.UP)
	arena.rival_controller = Controller.new()
	arena.goal = 2
	arena.food = Vector2i(10, 9)
	var length := arena.rival.body.size()
	arena.tick()
	assert_eq(arena.rival_score, 1)
	assert_eq(arena.score, 0)
	arena.food = Vector2i(10, 7)
	arena.tick()
	arena.tick()
	assert_eq(arena.rival.body.size(), length + 2)  # growing one cell a tick
	assert_eq(arena.death, "The rival ate 2 embers first")


func test_a_campaign_step_or_a_rule_brings_a_rival() -> void:
	var trial := Campaign.new()
	trial.level("meadow").with_rival()
	var arena := Arena.new(Board.bordered(SIZE))
	trial.steps[0].prepare(arena)
	assert_true(arena.rival != null)
	var later := Arena.new(Board.bordered(SIZE))
	Rulebook.parse("at tick 2: summon rival").attach(later)
	later.start()
	later.tick()
	assert_eq(later.rival, null)
	later.tick()
	assert_true(later.rival != null)


## The same rules drive both dragons: give the player the AI too and let two dragons
## fly every shipped map. Nothing breaks, and the same seed plays out the same way.
func test_two_ais_play_every_map_the_same_way_twice() -> void:
	for map in Level.catalog():
		var runs := []
		for attempt in 2:
			var level := Level.load_file("res://levels/%s.txt" % map)
			var arena := Arena.new(level.board.copy(), 7)
			arena.controller = GreedyController.new()
			assert_true(arena.summon_rival())
			arena.start()
			for i in 300:
				arena.tick()
			runs.append([arena.ticks, arena.score, arena.rival_score, arena.dragon.body])
		assert_eq(runs[0], runs[1])


## A rival flying the given way from head, and a player at the board's top left.
func _duel(head: Vector2i, facing: Vector2i) -> Arena:
	var arena := Arena.new(Board.bordered(SIZE))
	arena.dragon.body = [Vector2i(4, 2), Vector2i(3, 2), Vector2i(2, 2), Vector2i(1, 2)]
	arena.rival = Dragon.new(head, 4, facing)
	arena.rival_controller = GreedyController.new()
	arena.food = Vector2i(14, 14)
	arena.start()
	return arena


## Player heading right with this many cells, rival heading left with that many, their
## heads two cells apart on row 5 so both enter (8, 5) on the next tick.
func _head_on(player_length: int, rival_length: int) -> Arena:
	var arena := _duel(Vector2i(9, 5), Vector2i.LEFT)
	arena.rival_controller = Controller.new()
	arena.rival = Dragon.new(Vector2i(9, 5), rival_length, Vector2i.LEFT)
	arena.dragon = Dragon.new(Vector2i(7, 5), player_length, Vector2i.RIGHT)
	return arena
