extends "res://tests/test_case.gd"

const TRAIL := preload("res://levels/campaign.gd")


func test_each_level_call_starts_a_step_and_the_rest_tune_it() -> void:
	var trial := Campaign.new("Trial")
	trial.level("meadow").eat(3).without_pickups()
	trial.level("ford").faster(1.5).with_pickups([HastePowerup])
	assert_eq(trial.steps.size(), 2)
	assert_eq(trial.steps[0].map, "meadow")
	assert_eq(trial.steps[0].goal, 3)
	assert_eq(trial.steps[0].pickups.size(), 0)
	assert_eq(trial.steps[1].goal, 0)
	assert_eq(trial.steps[1].tempo, 1.5)
	assert_eq(trial.steps[1].pickups, [HastePowerup] as Array[GDScript])


func test_a_step_tunes_its_arena() -> void:
	var trial := Campaign.new()
	trial.level("meadow").eat(2).without_pickups().faster(1.25)
	var arena := Arena.new(Board.bordered(Vector2i(12, 12)))
	trial.steps[0].prepare(arena)
	assert_eq(arena.goal, 2)
	assert_eq(arena.pickup_kinds.size(), 0)
	assert_eq(arena.pace(), 1.25)


func test_reaching_the_goal_clears_the_level() -> void:
	var arena := Arena.new(Board.bordered(Vector2i(12, 12)))
	var cleared := []
	arena.won.connect(func(): cleared.append(true))
	arena.goal = 1
	arena.start()
	arena.food = arena.dragon.body[0] + Vector2i.RIGHT
	arena.tick()
	assert_eq(arena.state, Arena.State.WON)
	assert_eq(cleared.size(), 1)


func test_without_pickups_none_ever_appear() -> void:
	var arena := Arena.new(Board.bordered(Vector2i(12, 12)), 7)
	arena.pickup_kinds = []
	arena.start()
	for i in 20:
		arena._eat()
	assert_eq(arena.pickup, null)


func test_unnamed_maps_join_at_the_end() -> void:
	var trial := Campaign.new()
	trial.level("ford").eat(4)
	trial.then_any_other(["meadow", "ford"] as Array[String])
	assert_eq(trial.steps.map(func(s): return s.map), ["ford", "meadow"])


## The shipped campaign names real maps, includes every map, and gets harder.
func test_the_ember_trail_covers_every_level_in_order() -> void:
	var trail: Campaign = TRAIL.ember_trail()
	var maps := trail.steps.map(func(s): return s.map)
	for name in Level.catalog():
		assert_true(name in maps)
	assert_eq(maps[0], "meadow")
	var last_goal := 0
	for s in trail.steps.filter(func(s): return s.map != Terrain.NAME):  # the Wilds: endless
		assert_true(s.goal > last_goal)
		last_goal = s.goal
