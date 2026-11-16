extends "res://tests/test_case.gd"


## Effects listens to every game; a finished game must still be freed. (Its listeners
## once captured the Arena, a cycle that kept every old game in memory.)
func test_a_finished_game_is_freed() -> void:
	var camera := Camera3D.new()
	var effects := Effects.new(camera)
	var arena := Arena.new(Board.bordered(Vector2i(12, 12)))
	Rulebook.parse('every 2 ticks: say "hi"').attach(arena)
	effects.watch(arena)
	var gone: WeakRef = weakref(arena)
	effects.watch(Arena.new(Board.bordered(Vector2i(12, 12))))  # the next game
	arena = null
	assert_eq(gone.get_ref(), null)
	effects.free()
	camera.free()
