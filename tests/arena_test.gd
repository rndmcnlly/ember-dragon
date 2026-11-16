extends "res://tests/test_case.gd"

const SIZE := Vector2i(12, 12)
var board := Board.bordered(SIZE)  # walls on the edge, floor from (1, 1) to (10, 10)


func test_waits_for_the_first_move() -> void:
	var arena := Arena.new(board)
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
	assert_eq(arena.death, "You ran into the wall")


func test_a_wall_inside_the_board_ends_the_game() -> void:
	var arena := _started()
	arena.board.tiles[arena.dragon.body[0] + Vector2i.RIGHT] = "wall"
	arena.tick()
	assert_eq(arena.death, "You ran into the wall")


func test_food_never_lands_on_a_wall() -> void:
	for seed in 50:
		var arena := Arena.new(Board.bordered(SIZE), seed)
		assert_true(not arena.board.is_solid(arena.food))


func test_biting_the_body_ends_the_game() -> void:
	var arena := _coiled(Vector2i(4, 5))
	arena.tick()
	assert_eq(arena.death, "You bit your own tail")


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
	assert_eq(Arena.new(board, 121).food, Arena.new(board, 121).food)


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
	var arena := Arena.new(board)
	arena.start()
	return arena


func test_lava_lets_the_head_in_then_ends_the_game() -> void:
	var arena := _started()
	var ahead := arena.dragon.body[0] + Vector2i.RIGHT
	arena.board.tiles[ahead] = "lava"
	arena.tick()
	assert_eq(arena.dragon.body[0], ahead)
	assert_eq(arena.death, "You fell into the lava")


func test_water_halves_the_pace_even_with_haste() -> void:
	var arena := _started()
	arena.food = Vector2i(1, 1)
	arena.board.tiles[arena.dragon.body[0] + Vector2i.RIGHT] = "water"
	assert_eq(arena.pace(), 1.0)
	arena.tick()
	assert_eq(arena.pace(), 0.5)
	arena._activate(HastePowerup.new())
	assert_eq(arena.pace(), 1.0)


func test_embers_only_land_where_the_tile_allows() -> void:
	var ground := Board.bordered(SIZE)
	for x in range(1, SIZE.x - 1):
		for y in range(1, 5):
			ground.tiles[Vector2i(x, y)] = ["water", "lava"][x % 2]
	for seed in 50:
		var arena := Arena.new(ground, seed)
		assert_true(ground.spawns_at(arena.food))
