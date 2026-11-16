extends "res://tests/test_case.gd"

const TRAIL := preload("res://levels/campaign.gd")
const HEAD := Vector2i(29, 6)  # where the golden replay's dragon ends
const LENGTH := 25  # 4 to start, 3 per ember; the eighth's growth never comes


## The golden test: a recorded session, replayed, must end exactly as it did when it was
## recorded. Rules changes that alter play (on purpose or not) show up here first.
func test_the_golden_replay_ends_as_recorded() -> void:
	var replay := Replay.load_file("res://tests/golden.replay")
	assert_eq(replay.errors, [] as Array[String])
	var session := replay.run(TRAIL.ember_trail())
	assert_eq(session.ticks, 386)
	assert_eq(session.state, Session.State.WON)
	assert_eq(session.score, 8)
	assert_eq(session.rival_score, 7)  # one short of winning the race
	assert_eq(session.rival, null)  # it crashed along the way
	assert_eq(session.dragon.body[0], HEAD)
	assert_eq(session.dragon.body.size(), LENGTH)


## Record a session through the keyboard's controller, save it as text, read it back, and
## replay it: same body, same ember, same ground. The Caldera's lava spreads at random,
## so this only passes if every random roll comes back the same.
func test_a_recorded_game_replays_exactly() -> void:
	var campaign: Campaign = TRAIL.ember_trail()
	var step := campaign.steps[4]
	var session := step.play(step.load_level(), 2026)
	var keys := AiAtTheKeys.new()
	session.controller = keys
	session.start()
	while session.state == Session.State.PLAYING and session.ticks < 400:
		session.tick()
	var recorded := Replay.new()
	recorded.level = 5
	recorded.map = step.map
	recorded.seed = 2026
	recorded.ticks = session.ticks
	recorded.turns = keys.player.log
	var replayed := Replay.parse(recorded.to_text()).run(campaign)
	assert_true(session.ticks > 120)  # long enough for the lava to spread three times
	for field in ["ticks", "score", "state", "death", "food", "pickup_cell"]:
		assert_eq(replayed.get(field), session.get(field))
	assert_eq(replayed.dragon.body, session.dragon.body)
	assert_eq(replayed.board.tiles, session.board.tiles)


## Presses keys the way the AI would steer, through a real PlayerController: a
## tireless player whose every key press lands in the controller's log.
class AiAtTheKeys:
	extends Controller
	var ai := GreedyController.new()
	var player := PlayerController.new()

	func steer(session: Session, dragon: Dragon) -> void:
		var heading := dragon.heading
		ai.steer(session, dragon)
		var wanted := dragon.steer()  # peek at the AI's turn, then undo it
		dragon.heading = heading
		if wanted - dragon.body[0] != heading:
			player.press(wanted - dragon.body[0])
		player.steer(session, dragon)


func test_text_round_trip() -> void:
	var replay := Replay.new()
	replay.level = 3
	replay.map = "cinders"
	replay.seed = 99
	replay.ticks = 40
	replay.turns = {0: [Vector2i.UP], 12: [Vector2i.LEFT, Vector2i.DOWN]}
	var text := replay.to_text()
	assert_eq(text, "level: 3 cinders\nseed: 99\nticks: 40\n0: up\n12: left down\n")
	var back := Replay.parse(text)
	assert_eq(back.errors, [] as Array[String])
	assert_eq([back.level, back.map, back.seed, back.ticks], [3, "cinders", 99, 40])
	assert_eq(back.turns, replay.turns)


func test_mistakes_cite_the_line() -> void:
	var replay := Replay.parse("seed: 4\n\n7: up sideways\nspeed: 3", "mine.replay")
	assert_eq(replay.errors.size(), 2)
	assert_true(replay.errors[0].begins_with('mine.replay:3: unknown direction "sideways"'))
	assert_true(replay.errors[1].begins_with("mine.replay:4: expected"))


func test_a_replay_of_a_level_that_changed_says_so() -> void:
	var replay := Replay.parse("level: 1 ford\nseed: 1\nticks: 5")  # level 1 is the meadow
	assert_eq(replay.run(TRAIL.ember_trail()), null)
	assert_eq(replay.errors.size(), 1)
