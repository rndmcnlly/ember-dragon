extends "res://tests/test_case.gd"


## Effects listens to every session; a finished one must still be freed. (Its listeners
## once captured the Session, a cycle that kept every old session in memory.)
func test_a_finished_session_is_freed() -> void:
	var camera := Camera3D.new()
	var effects := Effects.new(camera)
	var session := Session.new(Board.bordered(Vector2i(12, 12)))
	Rulebook.parse('every 2 ticks: say "hi"').attach(session)
	effects.watch(session)
	var gone: WeakRef = weakref(session)
	effects.watch(Session.new(Board.bordered(Vector2i(12, 12))))  # the next session
	session = null
	assert_eq(gone.get_ref(), null)
	effects.free()
	camera.free()
