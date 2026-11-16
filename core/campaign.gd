## An internal DSL (Fowler's fluent builder): a run of levels and how each one plays,
## written as chained GDScript calls that read like the design doc. Every call
## returns the Campaign itself, so the next call can follow it on the same line:
##
##     var tutorial := Campaign.new("Tutorial")
##     tutorial.level("meadow").eat(5).without_pickups()
##     tutorial.level("ford").eat(8).faster(1.2)
##
## level() starts a new step; the calls after it tune that step. The result is plain
## data (the steps), which the game reads; the shipped campaign is levels/campaign.gd.
class_name Campaign
extends RefCounted


## One level of the campaign: which map, and the knobs that tune it.
class Step:
	var map := ""  # a file in levels/, without .txt; or Terrain.NAME for a grown map
	var goal := 0  # embers to clear the level; 0 means fly for as long as you like
	var pickups: Array[GDScript] = [HastePowerup, GhostPowerup, TrimPowerup]  # all, unless told
	var tempo := 1.0  # the level's base speed; Haste and water multiply it
	var rules := ""  # a file in levels/, without .rules, scripting events (see Rulebook)
	var rival := false  # a rival dragon from the start (rules can also summon one later)

	## Tune a fresh Arena to this step.
	func prepare(arena: Arena) -> void:
		arena.goal = goal
		arena.pickup_kinds = pickups.duplicate()
		arena.tempo = tempo
		if rival:
			arena.summon_rival()

	## This step's map, from one of two sources (Strategy): grown by Terrain from the
	## game's seed, or read from levels/. A broken file still gives a playable field
	## (an empty one), with its errors listed so the game can show them.
	func load_level(seed := 0) -> Level:
		if map == Terrain.NAME:
			return Terrain.new(seed).level()
		var level := Level.load_file("res://levels/%s.txt" % map)
		if not level.errors.is_empty():
			level.board = Board.bordered(Vector2i(42, 42))
		return level

	## This step's events, read fresh: a rulebook remembers which rules have fired.
	func rulebook() -> Rulebook:
		if rules.is_empty():
			return Rulebook.new()
		return Rulebook.load_file("res://levels/%s.rules" % rules)

	## A new game of this step on its level, with every random choice drawn from seed.
	## The game and Replay both start games here, which is why a replay matches.
	func play(on: Level, seed: int) -> Arena:
		var arena := Arena.new(on.board.copy(), seed)  # a copy: rules may change the ground
		prepare(arena)
		rulebook().attach(arena)
		return arena


var title := ""
var steps: Array[Step] = []


func _init(name := "Campaign") -> void:
	title = name


## Start a new step on a map from levels/. Every other call tunes the latest step.
func level(map: String) -> Campaign:
	var step := Step.new()
	step.map = map
	steps.append(step)
	return self


## Clear the level by eating this many embers.
func eat(embers: int) -> Campaign:
	_latest().goal = embers
	return self


## Only these powerups appear, e.g. with_pickups([HastePowerup]).
func with_pickups(kinds: Array[GDScript]) -> Campaign:
	_latest().pickups = kinds.duplicate()
	return self


func without_pickups() -> Campaign:
	_latest().pickups = []
	return self


## Fly this much faster than normal for the whole level (1.2 is 20% faster).
func faster(factor: float) -> Campaign:
	_latest().tempo = factor
	return self


## Script the level's events with a rules file from levels/, e.g. "eruption".
func with_rules(file: String) -> Campaign:
	_latest().rules = file
	return self


## A rival dragon races you for the same embers from the first move.
func with_rival() -> Campaign:
	_latest().rival = true
	return self


## Start a step on a map grown from the game's seed (see Terrain): a new map for every
## seed, the same map for the same seed. Tune it like any other step.
func wilds() -> Campaign:
	return level(Terrain.NAME)


## Add an endless step for every map not named yet, so a new levels/*.txt file
## still shows up in the game without touching code.
func then_any_other(maps: Array[String]) -> Campaign:
	for map in maps:
		if not steps.any(func(step: Step) -> bool: return step.map == map):
			level(map)
	return self


func _latest() -> Step:
	assert(not steps.is_empty(), "start with level(): the other calls tune the latest level")
	return steps.back()
