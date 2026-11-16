extends "res://tests/test_case.gd"

const SIZE := Vector2i(12, 12)
var board := Board.bordered(SIZE)  # walls on the edge, floor from (1, 1) to (10, 10)


func test_waits_for_the_first_move() -> void:
	var session := Session.new(board)
	var head := session.dragon.body[0]
	session.tick()
	assert_eq(session.dragon.body[0], head)


func test_eating_scores_and_grows() -> void:
	var session := _started()
	session.food = session.dragon.body[0] + Vector2i.RIGHT
	var length := session.dragon.body.size()
	for i in 1 + Session.GROWTH_PER_FOOD:
		session.tick()
	assert_eq(session.score, 1)
	assert_eq(session.dragon.body.size(), length + Session.GROWTH_PER_FOOD)


func test_the_wall_ends_the_run() -> void:
	var session := _started()
	session.food = Vector2i(0, 0)
	for i in SIZE.x:
		session.tick()
	assert_eq(session.state, Session.State.OVER)
	assert_eq(session.death, "You ran into the wall")


func test_a_wall_inside_the_board_ends_the_run() -> void:
	var session := _started()
	session.board.tiles[session.dragon.body[0] + Vector2i.RIGHT] = "wall"
	session.tick()
	assert_eq(session.death, "You ran into the wall")


func test_food_never_lands_on_a_wall() -> void:
	for seed in 50:
		var session := Session.new(Board.bordered(SIZE), seed)
		assert_true(not session.board.is_solid(session.food))


func test_biting_the_body_ends_the_run() -> void:
	var session := _coiled(Vector2i(4, 5))
	session.tick()
	assert_eq(session.death, "You bit your own tail")


func test_chasing_the_tail_tip_is_safe() -> void:
	var session := _coiled(Vector2i(4, 4))
	session.dragon.body.resize(4)  # now the tail tip is (4, 5), right where the head goes
	session.tick()
	assert_eq(session.state, Session.State.PLAYING)


func test_ghost_passes_through_the_body() -> void:
	var session := _coiled(Vector2i(4, 5))
	session._activate(GhostPowerup.new())
	session.tick()
	assert_eq(session.state, Session.State.PLAYING)


func test_haste_wears_off() -> void:
	var session := _started()
	session.food = Vector2i(0, 0)
	var haste := HastePowerup.new()
	haste.duration = 2
	session._activate(haste)
	assert_eq(session.speed, 2.0)
	session.tick()
	session.tick()
	assert_eq(session.speed, 1.0)


func test_same_seed_same_food() -> void:
	assert_eq(Session.new(board, 121).food, Session.new(board, 121).food)


## A dragon curled so that heading left from (5, 5) runs into (4, 5).
func _coiled(away_from_food: Vector2i) -> Session:
	var session := _started()
	session.food = away_from_food + Vector2i(0, 3)
	session.dragon.body = [
		Vector2i(5, 5),
		Vector2i(5, 6),
		Vector2i(4, 6),
		Vector2i(4, 5),
		Vector2i(4, 4),
		Vector2i(5, 4)
	]
	session.dragon.heading = Vector2i.LEFT
	return session


func _started() -> Session:
	var session := Session.new(board)
	session.start()
	return session


func test_lava_lets_the_head_in_then_ends_the_run() -> void:
	var session := _started()
	var ahead := session.dragon.body[0] + Vector2i.RIGHT
	session.board.tiles[ahead] = "lava"
	session.tick()
	assert_eq(session.dragon.body[0], ahead)
	assert_eq(session.death, "You fell into the lava")


## Haste speeds up the clock; water makes the dragon move on every other tick of it,
## so wading with Haste comes out even.
func test_water_halves_the_pace_even_with_haste() -> void:
	var session := _started()
	session.food = Vector2i(1, 1)
	var head := session.dragon.body[0]
	for i in 3:
		session.board.tiles[head + Vector2i.RIGHT * (i + 1)] = "water"
	session.tick()  # into the water at full pace
	assert_eq(session.dragon.body[0], head + Vector2i.RIGHT)
	session.tick()  # half a stride
	assert_eq(session.dragon.body[0], head + Vector2i.RIGHT)
	session.tick()
	assert_eq(session.dragon.body[0], head + Vector2i.RIGHT * 2)
	assert_eq(session.pace(), 1.0)
	session._activate(HastePowerup.new())
	assert_eq(session.pace(), 2.0)  # twice the ticks, half of them spent wading


func test_embers_only_land_where_the_tile_allows() -> void:
	var ground := Board.bordered(SIZE)
	for x in range(1, SIZE.x - 1):
		for y in range(1, 5):
			ground.tiles[Vector2i(x, y)] = ["water", "lava"][x % 2]
	for seed in 50:
		var session := Session.new(ground, seed)
		assert_true(ground.spawns_at(session.food))
