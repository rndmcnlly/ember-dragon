extends "res://tests/test_case.gd"

const TRAIL := preload("res://levels/campaign.gd")
const SAMPLES := ["ford-embers.replay", "caldera-lava.replay", "wilds-wade.replay"]
const WILDS := "level: 6 wilds\nseed: 4821\n"  # start (31,17) heading left; river at x 4-6


## The sample plans are evidence we point people at, so CI keeps them honest: each
## one still plays without warnings and still shows what its "expect:" lines promise.
## Named one by one: an agent's plan in progress, next to them, must not fail CI.
func test_the_sample_plans_still_do_what_they_say() -> void:
	for file in SAMPLES:
		var notes := _play(FileAccess.get_file_as_string("res://playtests/" + file))
		assert_eq(notes.warnings, [] as Array[String])
		assert_true(notes.expectations().size() >= 3)
		for result in notes.expectations():
			if not result.begins_with("met"):
				failures.append("%s: %s" % [file, result])


## In water a dragon is steered every other tick, so a turn planned for a wading tick
## would vanish without a word. The log says so, and which tick to use instead.
func test_a_turn_while_wading_is_reported_as_skipped() -> void:
	var notes := _play(WILDS + "ticks: 30\n1: up\n2: left\n27: up\n")  # wading on 27
	assert_eq(notes.warnings.size(), 1)
	assert_true(notes.warnings[0].begins_with("tick 27: turn up skipped"))
	assert_true("try tick 28" in notes.warnings[0])


func test_a_turn_the_dragon_cannot_take_is_reported() -> void:
	var notes := _play(WILDS + "ticks: 5\n2: left\n3: right\n")  # it flies left already
	assert_eq(notes.warnings.size(), 2)
	assert_true(notes.warnings[1].begins_with("tick 3: turn right did nothing"))
	assert_true(notes.warnings[0].begins_with("tick 2: turn left did nothing"))


## The playtest compares its recorded session with a dry run; that only works if two
## runs of one plan write the same log, word for word.
func test_the_same_plan_writes_the_same_log() -> void:
	var text := FileAccess.get_file_as_string("res://playtests/caldera-lava.replay")
	assert_eq(_play(text).lines, _play(text).lines)


func test_expectations_ignore_spacing_and_report_misses() -> void:
	var notes := _play("# expect: say   The Wilds\n# expect: won\n" + WILDS + "ticks: 5\n")
	assert_eq(notes.expectations(), ["met      say The Wilds", "NOT MET  won"] as Array[String])


func _play(text: String) -> PlaytestLog:
	var plan := Replay.parse(text)
	var notes := PlaytestLog.new(plan.restage(TRAIL.ember_trail()), plan, text)
	notes.play_out()
	return notes
