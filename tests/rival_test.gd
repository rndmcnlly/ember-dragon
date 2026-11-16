extends "res://tests/test_case.gd"

const SIZE := Vector2i(16, 16)


func test_a_rival_hatches_far_away_on_clear_ground() -> void:
	for seed in 20:
		var session := Session.new(Board.bordered(SIZE), seed)
		assert_true(session.summon_rival())
		var gap := (session.rival.body[0] - session.dragon.body[0]).abs()
		assert_true(gap.x + gap.y >= Session.RIVAL_DISTANCE)
		assert_eq(session.rival.body.size(), session.dragon.body.size())
		for cell in session.rival.body:
			assert_true(session.board.spawns_at(cell) and not session.dragon.body.has(cell))


func test_no_room_means_no_rival() -> void:
	var session := Session.new(Board.bordered(Vector2i(8, 8)))
	assert_true(not session.summon_rival())
	assert_eq(session.rival, null)


func test_embers_never_land_on_the_rival() -> void:
	var session := _duel(Vector2i(10, 4), Vector2i.LEFT)
	for i in 200:
		session.move_food()
		assert_true(not session.rival.body.has(session.food))


func test_the_ai_turns_toward_the_ember() -> void:
	var session := _duel(Vector2i(10, 10), Vector2i.LEFT)
	session.food = Vector2i(10, 3)  # straight up from the rival's head
	session.tick()
	assert_eq(session.rival.body[0], Vector2i(10, 9))


func test_the_ai_turns_away_from_a_wall() -> void:
	var session := _duel(Vector2i(14, 10), Vector2i.RIGHT)  # the border is one cell ahead
	session.food = Vector2i(14, 2)
	session.tick()
	assert_eq(session.rival.body[0], Vector2i(14, 9))


## The ember sits in a pocket too small for the rival's body. A plain greedy dragon
## would fly in and die there; the flood fill sees the trap and goes around.
func test_the_ai_will_not_enter_a_dead_end() -> void:
	var session := _duel(Vector2i(8, 9), Vector2i.UP)
	for cell in [Vector2i(7, 8), Vector2i(9, 8), Vector2i(8, 7)]:
		session.board.tiles[cell] = "wall"  # a one-cell pocket, open toward the rival
	session.food = Vector2i(8, 8)
	session.tick()
	assert_true(session.rival.body[0] != Vector2i(8, 8))
	assert_eq(session.rival.body.size(), 4)  # and it did not crash


func test_the_player_crashes_into_the_rival() -> void:
	var session := _duel(Vector2i(8, 6), Vector2i.DOWN)  # the rival crosses in front
	session.rival_controller = Controller.new()
	session.dragon.body = [Vector2i(7, 4), Vector2i(6, 4), Vector2i(5, 4), Vector2i(4, 4)]
	session.dragon.heading = Vector2i.RIGHT
	session.rival.body = [Vector2i(8, 5), Vector2i(8, 4), Vector2i(8, 3), Vector2i(8, 2)]
	session.tick()
	assert_eq(session.death, "You flew into the rival")


func test_the_rival_crashes_into_the_player_and_is_gone() -> void:
	var session := _duel(Vector2i(8, 6), Vector2i.DOWN)
	session.rival_controller = Controller.new()  # fly straight, into the player
	session.rival.body = [Vector2i(5, 3), Vector2i(5, 2), Vector2i(5, 1)]
	session.rival.heading = Vector2i.DOWN
	session.dragon.body = [Vector2i(7, 4), Vector2i(6, 4), Vector2i(5, 4), Vector2i(4, 4)]
	var heard := []
	session.announced.connect(func(text): heard.append(text))
	session.rival_crashed.connect(func(cell): heard.append(cell))
	session.tick()
	assert_eq(session.state, Session.State.PLAYING)
	assert_eq(session.rival, null)
	assert_eq(heard, ["The rival flew into you!", Vector2i(5, 4)])


func test_head_on_the_longer_dragon_wins() -> void:
	var session := _head_on(5, 4)  # the player is longer
	session.tick()
	assert_eq(session.state, Session.State.PLAYING)
	assert_eq(session.rival, null)
	assert_eq(session.dragon.body[0], Vector2i(8, 5))


func test_head_on_a_bigger_rival_ends_the_run() -> void:
	var session := _head_on(3, 4)
	session.tick()
	assert_eq(session.death, "You met a bigger dragon head-on")


func test_head_on_between_equals_ends_the_run() -> void:
	var session := _head_on(4, 4)
	session.tick()
	assert_eq(session.death, "You met a dragon your size head-on")


## Heads in neighboring cells flying at each other swap places without ever sharing
## a cell; that is still head-on.
func test_swapping_heads_is_head_on() -> void:
	var session := _head_on(5, 4)
	session.rival.body = [Vector2i(8, 5), Vector2i(9, 5), Vector2i(10, 5), Vector2i(11, 5)]
	session.tick()
	assert_eq(session.rival, null)


## One rule for both: the rival wades at half pace while the player, on dry ground,
## keeps flying every tick.
func test_the_rival_wades_through_water_too() -> void:
	var session := _duel(Vector2i(6, 10), Vector2i.RIGHT)
	session.rival_controller = Controller.new()
	for x in range(7, 12):
		session.board.tiles[Vector2i(x, 10)] = "water"
	var player_head := session.dragon.body[0]
	for i in 6:
		session.tick()
	assert_eq(session.dragon.body[0], player_head + Vector2i.RIGHT * 6)
	assert_eq(session.rival.body[0], Vector2i(9, 10))  # one cell in, then two in five ticks
	assert_eq(session.rival.body.size(), 4)


## A wading dragon's tail does not move away this tick, so it is no longer safe to
## follow into.
func test_a_wading_rivals_tail_stays_put() -> void:
	var session := _duel(Vector2i(8, 6), Vector2i.DOWN)
	session.rival_controller = Controller.new()
	session.rival.body = [Vector2i(8, 6), Vector2i(8, 5), Vector2i(8, 4), Vector2i(8, 3)]
	session.board.tiles[Vector2i(8, 6)] = "water"  # its head wades; it will not move
	session.rival.stride = 0.0
	session.dragon.body = [Vector2i(7, 3), Vector2i(6, 3), Vector2i(5, 3), Vector2i(4, 3)]
	session.tick()
	assert_eq(session.death, "You flew into the rival")


func test_ghost_passes_through_the_rival() -> void:
	var session := _duel(Vector2i(8, 6), Vector2i.DOWN)
	session.rival_controller = Controller.new()
	session.dragon.body = [Vector2i(7, 4), Vector2i(6, 4), Vector2i(5, 4), Vector2i(4, 4)]
	session.rival.body = [Vector2i(8, 5), Vector2i(8, 4), Vector2i(8, 3), Vector2i(8, 2)]
	session._activate(GhostPowerup.new())
	session.tick()
	assert_eq(session.state, Session.State.PLAYING)
	assert_true(session.rival != null)


func test_the_rival_eats_and_can_win_the_race() -> void:
	var session := _duel(Vector2i(10, 10), Vector2i.UP)
	session.rival_controller = Controller.new()
	session.goal = 2
	session.food = Vector2i(10, 9)
	var length := session.rival.body.size()
	session.tick()
	assert_eq(session.rival_score, 1)
	assert_eq(session.score, 0)
	session.food = Vector2i(10, 7)
	session.tick()
	session.tick()
	assert_eq(session.rival.body.size(), length + 2)  # growing one cell a tick
	assert_eq(session.death, "The rival ate 2 embers first")


func test_a_campaign_step_or_a_rule_brings_a_rival() -> void:
	var trial := Campaign.new()
	trial.level("meadow").with_rival()
	var session := Session.new(Board.bordered(SIZE))
	trial.steps[0].prepare(session)
	assert_true(session.rival != null)
	var later := Session.new(Board.bordered(SIZE))
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
			var session := Session.new(level.board.copy(), 7)
			session.controller = GreedyController.new()
			assert_true(session.summon_rival())
			session.start()
			for i in 300:
				session.tick()
			runs.append([session.ticks, session.score, session.rival_score, session.dragon.body])
		assert_eq(runs[0], runs[1])


## A rival flying the given way from head, and a player at the board's top left.
func _duel(head: Vector2i, facing: Vector2i) -> Session:
	var session := Session.new(Board.bordered(SIZE))
	session.dragon.body = [Vector2i(4, 2), Vector2i(3, 2), Vector2i(2, 2), Vector2i(1, 2)]
	session.rival = Dragon.new(head, 4, facing)
	session.rival_controller = GreedyController.new()
	session.food = Vector2i(14, 14)
	session.start()
	return session


## Player heading right with this many cells, rival heading left with that many, their
## heads two cells apart on row 5 so both enter (8, 5) on the next tick.
func _head_on(player_length: int, rival_length: int) -> Session:
	var session := _duel(Vector2i(9, 5), Vector2i.LEFT)
	session.rival_controller = Controller.new()
	session.rival = Dragon.new(Vector2i(9, 5), rival_length, Vector2i.LEFT)
	session.dragon = Dragon.new(Vector2i(7, 5), player_length, Vector2i.RIGHT)
	return session
