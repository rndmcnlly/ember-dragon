## The playtest driver behind `deno task playtest` (see PLAYTEST.md). It plays a plan,
## which is a replay file written by hand, through the real game and keeps the evidence:
## log.txt and path.txt (from PlaytestLog), summary.txt, and, while Godot records a
## movie (--write-movie), PNG snapshots of the screen at the moments that matter.
## With --dry it plays the plan without drawing anything, in a blink: the same rules
## and the same seed, so the same log.
extends Node

const MAIN := preload("res://main.tscn")
const TRAIL := preload("res://levels/campaign.gd")
const SNAP_DELAY := 8  # frames after an event, so its message and sparks are on screen
const LINGER := 45  # frames to keep recording after the end, for the result banner
const MAX_SNAPS := 10  # a handful: the start, the events, three progress shots, the end

var plan: Replay
var session: Session
var notes: PlaytestLog
var level_title := ""
var out := ""  # the evidence folder
var video := ""  # where the movie goes, as the summary should name it
var snaps: Array[String] = []  # snapshot files saved so far
var _source := ""
var _queue := {}  # frame -> labels to snapshot on that frame
var _queued := 0
var _frame := 0
var _seen := 0  # notes.moments already queued
var _progress: Array[int] = []  # ticks for the progress shots
var _ended := false


func _ready() -> void:
	var args := _args()
	_source = args.get("plan", "")
	out = args.get("out", "")
	video = args.get("video", "")
	var text := FileAccess.get_file_as_string(_source)
	plan = Replay.parse(text, _source.get_file())
	if text.strip_edges().is_empty():
		plan.errors.append("%s: no such plan, or it is empty" % _source)
	if args.has("dry"):
		_dry_run(text)
		return
	var game: Node = MAIN.instantiate()
	add_child(game)
	if plan.errors.is_empty():
		game.watch(plan)
	if game.watching != plan:
		_fail()
		return
	session = game.session
	level_title = game.level.title
	notes = PlaytestLog.new(session, plan, text, level_title)
	_progress = [plan.ticks / 4, plan.ticks / 2, plan.ticks * 3 / 4]


## The rules alone, as fast as they run: no window, no movie, no snapshots.
func _dry_run(text: String) -> void:
	var campaign: Campaign = TRAIL.ember_trail()
	session = plan.restage(campaign) if plan.errors.is_empty() else null
	if session == null:
		_fail()
		return
	level_title = campaign.steps[plan.level - 1].load_level(plan.seed).title
	notes = PlaytestLog.new(session, plan, text, level_title)
	notes.play_out()
	_finish()


## Runs only while recording: the game ticks itself (app/main.gd); we watch the clock.
func _process(_delta: float) -> void:
	if notes == null or _ended:
		return
	_frame += 1
	while _seen < notes.moments.size():
		var moment: Array = notes.moments[_seen]
		_seen += 1
		if _seen > 1 and moment[0] == notes.moments[_seen - 2][0]:
			continue  # one picture per tick, named for its first event
		var delay := SNAP_DELAY if moment[0] > 0 else 0  # the start, before the first move
		_plan_snap(_frame + delay, "tick-%04d-%s" % moment)
	if not _progress.is_empty() and session.ticks >= _progress[0]:
		_plan_snap(_frame, "tick-%04d-progress" % _progress.pop_front())
	if session.state != Session.State.PLAYING or session.ticks >= plan.ticks:
		_ended = true
		notes.finish()  # the dry run's play_out() calls it too
		_plan_snap(_frame + LINGER, "tick-%04d-end" % session.ticks, true)
	for label in _queue.get(_frame, []):
		_snap(label)


func _plan_snap(frame: int, label: String, last := false) -> void:
	if _queued >= MAX_SNAPS - 1 and not last:
		return
	_queued += 1
	_queue[frame] = _queue.get(frame, []) + [label]
	if last:  # after the run, frames still count, but only here
		_linger(frame)


## Keep drawing after the end until the last snapshot, then wrap up.
func _linger(until: int) -> void:
	while _frame < until:
		await get_tree().process_frame
		_frame += 1
		for label in _queue.get(_frame, []):
			_snap(label)


## Save what is on screen once this frame is drawn. The last one wraps up the run.
func _snap(label: String) -> void:
	await RenderingServer.frame_post_draw
	var file := "%02d-%s.png" % [snaps.size() + 1, label]
	get_viewport().get_texture().get_image().save_png(out.path_join(file))
	snaps.append(file)
	if label.ends_with("-end"):
		_finish()


func _finish() -> void:
	notes.save(out)
	var file := FileAccess.open(out.path_join("summary.txt"), FileAccess.WRITE)
	file.store_string("\n".join(_summary()) + "\n")
	file.close()
	if not _args().has("quiet"):  # the recording's summary is the one to read
		print("\n".join(_summary()))
	get_tree().quit()


func _fail() -> void:
	for problem in plan.errors:
		printerr(problem)
	printerr("playtest: the plan cannot be played; fix the lines above and run it again")
	get_tree().quit(1)


## One screen: what was planned, how it ended, and what to open next.
func _summary() -> Array[String]:
	var lines: Array[String] = ["Playtest   %s" % _source.get_file()]
	var said := notes.intent()
	for i in mini(said.size(), 4):
		lines.append(("Intent     " if i == 0 else "           ") + said[i])
	lines.append("Level      %d %s (%s), seed %d" % [plan.level, plan.map, level_title, plan.seed])
	lines.append("Plan       %d ticks, turns on %d of them" % [plan.ticks, plan.turns.size()])
	lines.append("Ending     %s" % notes.ending)
	var goal := " of %d to clear" % session.goal if session.goal > 0 else ""
	lines.append(
		"Score      %d embers%s, length %d" % [session.score, goal, session.dragon.body.size()]
	)
	lines.append("Rival      %s" % _rival())
	var counted: Array[String] = []
	for word in notes.counts:
		if word not in ["start", "status", "end"]:
			counted.append("%s %d" % [word, notes.counts[word]])
	lines.append("Events     %s" % ", ".join(counted))
	for result in notes.expectations():
		lines.append("Expect     %s" % result)
	if notes.warnings.is_empty():
		lines.append("Warnings   none")
	for warning in notes.warnings:
		lines.append("Warning    %s" % warning)
	lines.append("Read       log.txt first (events), path.txt for any tick (where the head was)")
	if snaps.is_empty() and video.is_empty():
		lines.append("Pictures   none: this was a dry run (no window, no video)")
	for i in snaps.size():
		lines.append(("Snapshots  " if i == 0 else "           ") + snaps[i])
	if not video.is_empty():
		lines.append("Video      %s (30 fps; the HUD's Replay N is the tick)" % video)
	return lines


func _rival() -> String:
	if session.rival != null:
		return "alive, %d embers" % session.rival_score
	if notes.counts.has("rival"):
		return "crashed, after %d embers" % session.rival_score
	return "none"


## The words after `--` on Godot's command line:
## --plan=PATH --out=DIR, and optionally --video=PATH, --dry, --quiet
func _args() -> Dictionary:
	var found := {}
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=", true, 1)
		found[pair[0]] = pair[1] if pair.size() > 1 else ""
	return found
