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
	var map := ""  # a file in levels/, without .txt
	var goal := 0  # embers to clear the level; 0 means fly for as long as you like
	var pickups: Array[GDScript] = [HastePowerup, GhostPowerup, TrimPowerup]  # all, unless told
	var tempo := 1.0  # the level's base speed; Haste and water multiply it
	var rules := ""  # a file in levels/, without .rules, scripting events (see Rulebook)

	## Tune a fresh Arena to this step.
	func prepare(arena: Arena) -> void:
		arena.goal = goal
		arena.pickup_kinds = pickups.duplicate()
		arena.tempo = tempo


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
