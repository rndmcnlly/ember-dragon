extends "res://tests/test_case.gd"


func test_moves_one_cell_per_tick() -> void:
	var dragon := Dragon.new(Vector2i(5, 5), 3)
	dragon.steer()
	dragon.advance()
	assert_eq(dragon.body, [Vector2i(6, 5), Vector2i(5, 5), Vector2i(4, 5)])


func test_reversing_into_the_neck_is_ignored() -> void:
	var dragon := Dragon.new(Vector2i(5, 5))
	dragon.turn(Vector2i.LEFT)
	dragon.steer()
	assert_eq(dragon.heading, Vector2i.RIGHT)


func test_two_quick_turns_apply_on_successive_ticks() -> void:
	var dragon := Dragon.new(Vector2i(5, 5))
	dragon.turn(Vector2i.UP)
	dragon.turn(Vector2i.LEFT)
	dragon.steer()
	assert_eq(dragon.heading, Vector2i.UP)
	dragon.steer()
	assert_eq(dragon.heading, Vector2i.LEFT)


func test_grows_one_cell_per_tick() -> void:
	var dragon := Dragon.new(Vector2i(5, 5), 3)
	dragon.grow(2)
	for i in 3:
		dragon.steer()
		dragon.advance()
	assert_eq(dragon.body.size(), 5)


func test_shrink_keeps_a_head_and_tail() -> void:
	var dragon := Dragon.new(Vector2i(5, 5), 4)
	dragon.shrink(10)
	assert_eq(dragon.body.size(), Dragon.MIN_LENGTH)
