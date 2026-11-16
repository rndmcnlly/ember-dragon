extends "res://tests/test_case.gd"

const SIZE := Vector2i(10, 10)


func test_waits_for_the_first_move() -> void:
	var arena := Arena.new(SIZE)
	var head := arena.dragon.body[0]
	arena.tick()
	assert_eq(arena.dragon.body[0], head)


func test_eating_scores_and_grows() -> void:
	var arena := _started()
	arena.food = arena.dragon.body[0] + Vector2i.RIGHT
	var length := arena.dragon.body.size()
	for i in 1 + Arena.GROWTH_PER_FOOD:
		arena.tick()
	assert_eq(arena.score, 1)
	assert_eq(arena.dragon.body.size(), length + Arena.GROWTH_PER_FOOD)


func test_the_wall_ends_the_game() -> void:
	var arena := _started()
	arena.food = Vector2i(0, 0)
	for i in SIZE.x:
		arena.tick()
	assert_eq(arena.state, Arena.State.OVER)
	assert_eq(arena.death, "the wall")


func test_biting_the_body_ends_the_game() -> void:
	var arena := _coiled(Vector2i(4, 5))
	arena.tick()
	assert_eq(arena.death, "your own tail")


func test_chasing_the_tail_tip_is_safe() -> void:
	var arena := _coiled(Vector2i(4, 4))
	arena.dragon.body.resize(4)  # now the tail tip is (4, 5), right where the head goes
	arena.tick()
	assert_eq(arena.state, Arena.State.PLAYING)


func test_ghost_passes_through_the_body() -> void:
	var arena := _coiled(Vector2i(4, 5))
	arena._activate(GhostPowerup.new())
	arena.tick()
	assert_eq(arena.state, Arena.State.PLAYING)


func test_haste_wears_off() -> void:
	var arena := _started()
	arena.food = Vector2i(0, 0)
	var haste := HastePowerup.new()
	haste.duration = 2
	arena._activate(haste)
	assert_eq(arena.speed, 2.0)
	arena.tick()
	arena.tick()
	assert_eq(arena.speed, 1.0)


func test_same_seed_same_food() -> void:
	assert_eq(Arena.new(SIZE, 121).food, Arena.new(SIZE, 121).food)


## A dragon curled so that heading left from (5, 5) runs into (4, 5).
func _coiled(away_from_food: Vector2i) -> Arena:
	var arena := _started()
	arena.food = away_from_food + Vector2i(0, 3)
	arena.dragon.body = [
		Vector2i(5, 5),
		Vector2i(5, 6),
		Vector2i(4, 6),
		Vector2i(4, 5),
		Vector2i(4, 4),
		Vector2i(5, 4)
	]
	arena.dragon.heading = Vector2i.LEFT
	return arena


func _started() -> Arena:
	var arena := Arena.new(SIZE)
	arena.start()
	return arena
