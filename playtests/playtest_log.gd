## A playtest's notebook. It listens to one Arena (Observer, like the sound and the
## level's rules) and writes down what happened on which tick, in words an agent can
## search, so the agent reads text first and only then looks at pictures. It never
## changes the game: it watches, and it wraps the plan's controller to see which
## turns landed (Witness, a Decorator).
##
##     log.txt    one line per event: "tick 14   ate      ember at (12,3) ..."
##     path.txt   one line per tick: where the head was and what it stood on
class_name PlaytestLog
extends RefCounted

const STATUS_EVERY := 10  # a "status" line this often, between events
const WORDS := {
	Vector2i.UP: "up", Vector2i.DOWN: "down", Vector2i.LEFT: "left", Vector2i.RIGHT: "right"
}

var arena: Arena
var plan: Replay
var plan_text := ""  # the plan file as written, for its comments
var title := ""  # the level's title, for the summary
var lines: Array[String] = []  # log.txt
var path: Array[String] = []  # path.txt
var warnings: Array[String] = []  # plan turns that did nothing, and why
var moments: Array = []  # [tick, label]: events worth a snapshot
var counts := {}  # event word -> how many times it happened
var ending := ""  # how the run ended, one line
var _witness: Witness
var _food: Vector2i
var _pickup_cell := Vector2i(-1, -1)
var _rival: Dragon
var _ground := ""
var _heading: Vector2i  # before this tick's turns
var _tick_start := 0  # where this tick's lines begin in log.txt


## Steers exactly as the controller it wraps (the plan's Playback), and notes the ticks
## on which it was asked. A wading dragon is not steered, so a turn planned for a
## wading tick never happens; this is how the log can say so.
class Witness:
	extends Controller
	var inner: Controller
	var steered := {}  # tick -> true

	func _init(wrapped: Controller) -> void:
		inner = wrapped

	func steer(game: Arena, dragon: Dragon) -> void:
		steered[game.ticks] = true
		inner.steer(game, dragon)


## Start listening to a game the plan is about to play (after Replay.restage()).
func _init(game: Arena, played: Replay, text: String, level_title := "") -> void:
	arena = game
	plan = played
	plan_text = text
	title = level_title
	_witness = Witness.new(arena.controller)
	arena.controller = _witness
	arena.ate.connect(_on_ate)
	arena.powered.connect(_on_powered)
	arena.announced.connect(_on_announced)
	arena.rival_ate.connect(_on_rival_ate)
	arena.rival_crashed.connect(_on_rival_crashed)
	arena.ticked.connect(_after_tick)
	arena.died.connect(_on_died)
	arena.won.connect(_on_won)
	arena.board.changed.connect(_on_ground_changed)
	_food = arena.food
	_rival = arena.rival
	_ground = arena.board.kind_at(arena.dragon.body[0])
	var head := arena.dragon.body[0]
	_note(
		"start",
		(
			"head %s heading %s, length %d, on %s; ember at %s (%s); goal %s"
			% [
				_cell(head),
				WORDS[arena.dragon.heading],
				arena.dragon.body.size(),
				_ground,
				_cell(_food),
				_offset(_food),
				"%d embers" % arena.goal if arena.goal > 0 else "none",
			]
		)
	)
	if _rival != null:
		_note(
			"rival",
			"already here: head %s heading %s" % [_cell(_rival.body[0]), WORDS[_rival.heading]]
		)
	moments.append([0, "start"])
	_tick_start = lines.size()
	_heading = arena.dragon.heading


## Play the rest of the plan at once, without drawing (the dry run, and the tests).
func play_out() -> void:
	while arena.state == Arena.State.PLAYING and arena.ticks < plan.ticks:
		arena.tick()
	finish()


## Call once the run is over (died, won, or the plan's ticks ran out).
func finish() -> void:
	match arena.state:
		Arena.State.OVER:
			ending = "tick %d: died: %s" % [arena.ticks, arena.death]
		Arena.State.WON:
			ending = "tick %d: level clear (%d embers)" % [arena.ticks, arena.score]
		_:
			ending = "tick %d: plan ran out, still flying" % arena.ticks
	for tick in plan.turns:  # turns planned after the game had already ended
		if tick > arena.ticks:
			warnings.append(
				"tick %d: turn never happened: the run ended on tick %d" % [tick, arena.ticks]
			)
	_note("end", ending.substr(ending.find(":") + 2))


## Each "expect:" comment in the plan, with whether log.txt contains its words, in
## order, ignoring quotes and how many spaces sit between them ("say The Wilds"
## finds 'say      "The Wilds').
func expectations() -> Array[String]:
	var results: Array[String] = []
	var text := _loose("\n".join(lines))
	for line in plan_text.split("\n"):
		if line.strip_edges().begins_with("# expect:"):
			var wanted := _loose(line.strip_edges().trim_prefix("# expect:"))
			results.append(("met      " if wanted in text else "NOT MET  ") + wanted)
	return results


## The plan's own words: its comment lines, minus expectations.
func intent() -> Array[String]:
	var said: Array[String] = []
	for line in plan_text.split("\n"):
		var text := line.strip_edges()
		if text.begins_with("#") and not text.begins_with("# expect:"):
			said.append(text.trim_prefix("#").strip_edges())
	return said


func save(folder: String) -> void:
	_write(folder.path_join("log.txt"), lines)
	_write(folder.path_join("path.txt"), path)


func _after_tick() -> void:
	var t := arena.ticks
	var head := arena.dragon.body[0]
	if plan.turns.has(t):
		_check_turns(t)
	var ground := arena.board.kind_at(head)
	if ground != _ground:
		_ground = ground
		var wading := (
			" (wading: one cell every other tick)" if arena.board.pace_at(head) < 1.0 else ""
		)
		_note("ground", "head on %s at %s%s" % [ground, _cell(head), wading])
	if arena.food != _food:
		_food = arena.food
		_note("ember", "now at %s (%s)" % [_cell(_food), _offset(_food)])
	if arena.pickup != null and arena.pickup_cell != _pickup_cell:
		_note(
			"pickup",
			(
				"%s waiting at %s (%s)"
				% [arena.pickup.title, _cell(arena.pickup_cell), _offset(arena.pickup_cell)]
			)
		)
	_pickup_cell = arena.pickup_cell if arena.pickup != null else Vector2i(-1, -1)
	if arena.rival != null and _rival == null:
		_note(
			"rival",
			"hatched: head %s heading %s" % [_cell(arena.rival.body[0]), WORDS[arena.rival.heading]]
		)
		moments.append([t, "rival"])
	_rival = arena.rival
	if t % STATUS_EVERY == 0 and arena.state == Arena.State.PLAYING:
		_note("status", _state())
	path.append("tick %-4d %s" % [t, _state()])
	_tick_start = lines.size()
	_heading = arena.dragon.heading


## Turns at this tick: did the dragon take them? If it was wading, it was never asked.
## Otherwise each turn is checked as Dragon.turn() checks it: a turn the way it already
## flies, or straight back into its neck, is ignored.
func _check_turns(t: int) -> void:
	var wanted: Array = plan.turns[t]
	var names := " ".join(wanted.map(func(d): return WORDS[d]))
	var last := _heading
	var taken := 0
	for direction in wanted:
		if direction != last and direction != -last:
			taken += 1
			last = direction
	if not _witness.steered.has(t):
		var wading := "the dragon was wading, and turns only land on ticks it moves"
		warnings.append("tick %d: turn %s skipped: %s (try tick %d)" % [t, names, wading, t + 1])
		_note("turn", "%s SKIPPED (wading)" % names, _tick_start)
	elif taken == 0:
		var why := "it cannot turn the way it flies or reverse"
		warnings.append(
			"tick %d: turn %s did nothing: heading %s, %s" % [t, names, WORDS[_heading], why]
		)
		_note("turn", "%s IGNORED (heading %s)" % [names, WORDS[_heading]], _tick_start)
	else:
		_note("turn", "%s, head now %s" % [names, _cell(arena.dragon.body[0])], _tick_start)


func _on_ate(cell: Vector2i) -> void:
	_note(
		"ate",
		(
			"ember at %s; score %d, growing to length %d"
			% [_cell(cell), arena.score, arena.dragon.body.size() + Arena.GROWTH_PER_FOOD]
		)
	)
	if arena.score == 1:
		moments.append([arena.ticks, "ate"])


func _on_powered(powerup: Powerup) -> void:
	var lasting := " for %d ticks" % powerup.duration if powerup.duration > 0 else ""
	_note("power", "%s%s" % [powerup.title, lasting])
	moments.append([arena.ticks, "power"])


func _on_announced(text: String) -> void:
	_note("say", '"%s"' % text)
	moments.append([arena.ticks, "say"])


func _on_rival_ate(cell: Vector2i) -> void:
	_note("rival", "ate ember at %s; rival score %d" % [_cell(cell), arena.rival_score])


func _on_rival_crashed(cell: Vector2i) -> void:
	_note("rival", "crashed at %s" % _cell(cell))
	moments.append([arena.ticks, "rival-crash"])


## Rules changed the ground (spread, replace, place): which cells became what.
func _on_ground_changed(cells: Array) -> void:
	if cells.is_empty():
		return
	var kind := arena.board.kind_at(cells[0])
	var shown := " ".join(cells.slice(0, 6).map(_cell))
	var more := " and %d more" % (cells.size() - 6) if cells.size() > 6 else ""
	var noun := "cell" if cells.size() == 1 else "cells"
	_note("terrain", "%d %s became %s: %s%s" % [cells.size(), noun, kind, shown, more])
	moments.append([arena.ticks, "terrain"])


func _on_died(reason: String) -> void:
	_after_tick()
	var dragon := arena.dragon
	var head := dragon.body[0]  # a crash stops the head short; lava lets it in
	var into := "" if arena.board.is_deadly(head) else " into %s" % _cell(head + dragon.heading)
	_note("died", "%s (head %s, heading %s%s)" % [reason, _cell(head), WORDS[dragon.heading], into])
	moments.append([arena.ticks, "died"])


func _on_won() -> void:
	_after_tick()
	_note("won", "level clear with %d embers" % arena.score)
	moments.append([arena.ticks, "won"])


## Add a line to log.txt, at the end, or at a position (a turn goes first in its tick).
func _note(word: String, text: String, at := -1) -> void:
	counts[word] = counts.get(word, 0) + 1
	var line := "tick %-4d %-8s %s" % [arena.ticks, word, text]
	if at >= 0:
		lines.insert(at, line)
	else:
		lines.append(line)


## One line of where things stand, for status lines and path.txt.
func _state() -> String:
	var dragon := arena.dragon
	var head := dragon.body[0]
	return (
		"head %s heading %-5s on %-6s length %-3d score %d  ember %s (%s)"
		% [
			_cell(head),
			WORDS[dragon.heading],
			arena.board.kind_at(head),
			dragon.body.size(),
			arena.score,
			_cell(arena.food),
			_offset(arena.food),
		]
	)


## Where a cell is from the head, in plan words: "3 right, 5 up".
func _offset(cell: Vector2i) -> String:
	var gap := cell - arena.dragon.body[0]
	var parts: Array[String] = []
	if gap.x != 0:
		parts.append("%d %s" % [absi(gap.x), "right" if gap.x > 0 else "left"])
	if gap.y != 0:
		parts.append("%d %s" % [absi(gap.y), "down" if gap.y > 0 else "up"])
	return ", ".join(parts) + " from head" if not parts.is_empty() else "at head"


func _loose(text: String) -> String:
	return " ".join(text.replace('"', "").split(" ", false))


func _cell(cell: Vector2i) -> String:
	return "(%d,%d)" % [cell.x, cell.y]


func _write(file_path: String, text_lines: Array[String]) -> void:
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(text_lines) + "\n")
