## A recorded game: which level, the seed, and the player's turn commands per tick.
## Nothing else needs saving. Every random choice comes from the Arena's seeded rng,
## the rival's AI reads the board and never rolls dice, and a turn is a Command the
## dragon applies on a tick, never in between; so replaying the same commands on the
## same ticks from the same seed plays the same game, down to the last ember.
##
## Saved as text, one command line per tick that had any:
##
##     level: 2 ford
##     seed: 121
##     ticks: 412
##     0: right
##     9: down left
##
## Playing it back is just another Controller (Playback), steering the player's dragon
## in place of the keyboard.
class_name Replay
extends RefCounted

const WORDS := {
	"up": Vector2i.UP, "down": Vector2i.DOWN, "left": Vector2i.LEFT, "right": Vector2i.RIGHT
}

var level := 1  # the campaign step, counting from 1 as the player does
var map := ""  # that step's map, to notice when the campaign has changed since
var seed := 0
var ticks := 0  # how long the game ran
var turns := {}  # tick -> Array of directions, in the order they were pressed
var errors: Array[String] = []  # problems reading the file


## Plays the recorded turns back on their ticks, in place of the keyboard.
class Playback:
	extends Controller
	var turns: Dictionary

	func _init(recorded: Dictionary) -> void:
		turns = recorded

	func steer(arena: Arena, dragon: Dragon) -> void:
		for direction in turns.get(arena.ticks, []):
			dragon.turn(direction)


## The game as it stood before the first move, steered by the recording and started.
## Null, with a message in errors, when the campaign no longer has this level.
func restage(campaign: Campaign) -> Arena:
	if level < 1 or level > campaign.steps.size() or campaign.steps[level - 1].map != map:
		errors.append(
			"this replay is of level %d (%s), which the campaign no longer has" % [level, map]
		)
		return null
	var step := campaign.steps[level - 1]
	var arena := step.play(step.load_level(), seed)
	arena.controller = Playback.new(turns)
	arena.start()
	return arena


## Play the whole recording at once, without drawing anything, and return the game as
## it ended. The golden replay test is this plus a few asserts.
func run(campaign: Campaign) -> Arena:
	var arena := restage(campaign)
	while arena != null and arena.state == Arena.State.PLAYING and arena.ticks < ticks:
		arena.tick()
	return arena


func to_text() -> String:
	var lines := ["level: %d %s" % [level, map], "seed: %d" % seed, "ticks: %d" % ticks]
	var named := {}
	for word in WORDS:
		named[WORDS[word]] = word
	for tick in turns:
		lines.append("%d: %s" % [tick, " ".join(turns[tick].map(func(d): return named[d]))])
	return "\n".join(lines) + "\n"


static func parse(text: String, source := "replay") -> Replay:
	var replay := Replay.new()
	var lines := text.split("\n")
	for i in lines.size():
		var line := lines[i].strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var problem := replay._read_line(line)
		if not problem.is_empty():
			replay.errors.append("%s:%d: %s" % [source, i + 1, problem])
	return replay


static func load_file(path: String) -> Replay:
	if not FileAccess.file_exists(path):
		var missing := Replay.new()
		missing.errors.append("%s: no such replay" % path)
		return missing
	return parse(FileAccess.get_file_as_string(path), path.get_file())


func save(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(to_text())
	return true


## One "key: words" line; returns what is wrong with it, or "".
func _read_line(line: String) -> String:
	var colon := line.find(":")
	var key := line.left(colon).strip_edges() if colon > 0 else ""
	var words := line.substr(colon + 1).split(" ", false)
	if key.is_valid_int():
		var directions: Array[Vector2i] = []
		for word in words:
			if not WORDS.has(word):
				return 'unknown direction "%s" (try up, down, left, right)' % word
			directions.append(WORDS[word])
		turns[key.to_int()] = directions
	elif key == "level" and words.size() == 2 and words[0].is_valid_int():
		level = words[0].to_int()
		map = words[1]
	elif key in ["seed", "ticks"] and words.size() == 1 and words[0].is_valid_int():
		set(key, words[0].to_int())
	else:
		return 'expected "level: N MAP", "seed: N", "ticks: N", or "TICK: DIRECTIONS"'
	return ""
