## An external DSL: a tiny language for what happens during a level, read from
## levels/*.rules. One rule per line, "when: what":
##
##     # eruption.rules
##     at tick 3: say "The caldera rumbles."
##     every 40 ticks: spread lava 2
##     at score 7: replace lava with water
##
## Parsing turns each line into a Rule: a Trigger and an Action object (the GoF
## Interpreter pattern: the parsed lines become a little tree of objects that run
## themselves). Each verb is one Action class that reads its own words and does its
## own job, so a new verb is a new class plus one line in VERBS. Mistakes become
## messages naming the file and line, never a crash. levels/README.md lists the verbs.
class_name Rulebook
extends RefCounted

const TRIGGERS := '"at tick 10", "every 40 ticks", or "at score 5"'

var rules: Array[Rule] = []
var errors: Array[String] = []  # "eruption.rules:3: what went wrong"


## One line of a rules file, parsed.
class Rule:
	var trigger: Trigger
	var action: Action


## When a rule fires. Each is asked once per tick of play.
class Trigger:
	enum Kind { AT_TICK, EVERY, AT_SCORE }
	var kind: Kind
	var n := 0  # the tick or score to wait for, or the period of EVERY
	var fired := false

	func fires(arena: Arena) -> bool:
		match kind:
			Kind.AT_TICK:
				return arena.ticks == n
			Kind.EVERY:
				return arena.ticks % n == 0
		if fired or arena.score < n:  # AT_SCORE: once, as soon as the score gets there
			return false
		fired = true
		return true

	## "at tick 10", "every 40 ticks", "at score 5": a Trigger, or what is wrong.
	static func read(words: PackedStringArray) -> Variant:
		var trigger := Trigger.new()
		var shape := " ".join(words)
		if words.size() == 3 and words[0] == "at" and words[1] in ["tick", "score"]:
			trigger.kind = Kind.AT_TICK if words[1] == "tick" else Kind.AT_SCORE
			trigger.n = Rulebook.parse_number(words[2])
		elif words.size() == 3 and words[0] == "every" and words[2] in ["tick", "ticks"]:
			trigger.kind = Kind.EVERY
			trigger.n = Rulebook.parse_number(words[1])
		else:
			return 'unknown trigger "%s" (try %s)' % [shape, TRIGGERS]
		if trigger.n <= 0:
			return 'expected a whole number above 0 in "%s"' % shape
		return trigger


## What a rule does. Each subclass is one verb: a static read() that turns the words
## after the colon into an instance (or an error message), and run() that does it.
class Action:
	func run(_arena: Arena) -> void:
		pass

	## The tile kinds this action names, so the parser can check them in one place.
	func kinds() -> Array:
		return []


## say "The caldera rumbles."
class Say:
	extends Action
	var text := ""

	static func read(words: PackedStringArray) -> Variant:
		var quoted := " ".join(words.slice(1))
		if quoted.length() < 2 or not (quoted.begins_with('"') and quoted.ends_with('"')):
			return 'say needs its words in quotes, like say "Watch out!"'
		var say := Say.new()
		say.text = quoted.substr(1, quoted.length() - 2)
		return say

	func run(arena: Arena) -> void:
		arena.announce(text)


## spread lava 2: that many clear cells next to the kind become the kind. Lava and
## walls never spread where they would cut the dragon off from ground it could reach,
## so an ember can never land somewhere hopeless.
class Spread:
	extends Action
	var kind := ""
	var count := 0

	static func read(words: PackedStringArray) -> Variant:
		var spread := Spread.new()
		if words.size() == 3:
			spread.kind = words[1]
			spread.count = Rulebook.parse_number(words[2])
		if spread.count <= 0:
			return 'expected "spread KIND COUNT", like "spread lava 2"'
		return spread

	func kinds() -> Array:
		return [kind]

	func run(arena: Arena) -> void:
		var edge := []
		for cell in arena.board.tiles:
			if arena.is_clear(cell) and not arena.near_head(cell) and _touches(arena, cell):
				edge.append(cell)
		var grown := 0
		while grown < count and not edge.is_empty():
			var cell: Vector2i = edge.pop_at(arena.rng.randi_range(0, edge.size() - 1))
			if not _seals(arena, cell):
				arena.board.set_kinds([cell], kind)
				grown += 1

	func _touches(arena: Arena, cell: Vector2i) -> bool:
		for step in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if arena.board.kind_at(cell + step) == kind:
				return true
		return false

	## Whether turning this cell into the kind would wall off more than the cell itself.
	func _seals(arena: Arena, cell: Vector2i) -> bool:
		var board := arena.board
		var row: Dictionary = Board.TILES[kind]
		if not (row.solid or row.deadly):
			return false
		var before := board.reachable(arena.dragon.body[0]).size()
		var was: String = board.tiles[cell]
		board.tiles[cell] = kind  # try it, count, and put it back
		var after := board.reachable(arena.dragon.body[0]).size()
		board.tiles[cell] = was
		return after < before - 1


## replace lava with water: every cell of one kind becomes another.
class Replace:
	extends Action
	var from := ""
	var to := ""

	static func read(words: PackedStringArray) -> Variant:
		if words.size() != 4 or words[2] != "with":
			return 'expected "replace KIND with KIND", like "replace lava with water"'
		var replace := Replace.new()
		replace.from = words[1]
		replace.to = words[3]
		return replace

	func kinds() -> Array:
		return [from, to]

	func run(arena: Arena) -> void:
		var cells := arena.board.tiles.keys().filter(
			func(cell): return arena.board.kind_at(cell) == from and Rulebook.safe(arena, cell, to)
		)
		arena.board.set_kinds(cells, to)


## place bridge at 20,9   or   place bridge from 20,9 to 23,9
class Place:
	extends Action
	var kind := ""
	var corners := Rect2i()

	static func read(words: PackedStringArray) -> Variant:
		var place := Place.new()
		var a := Vector2i(-1, -1)
		var b := Vector2i(-1, -1)
		if words.size() == 4 and words[2] == "at":
			a = Rulebook.parse_cell(words[3])
			b = a
		elif words.size() == 6 and words[2] == "from" and words[4] == "to":
			a = Rulebook.parse_cell(words[3])
			b = Rulebook.parse_cell(words[5])
		if a.x < 0 or b.x < 0:
			return 'expected "place KIND at X,Y" or "place KIND from X,Y to X,Y"'
		place.kind = words[1]
		place.corners = Rect2i(a.min(b), (b - a).abs())
		return place

	func kinds() -> Array:
		return [kind]

	func run(arena: Arena) -> void:
		var cells := []
		for x in range(corners.position.x, corners.end.x + 1):
			for y in range(corners.position.y, corners.end.y + 1):
				var cell := Vector2i(x, y)
				if arena.board.tiles.has(cell) and Rulebook.safe(arena, cell, kind):
					cells.append(cell)
		arena.board.set_kinds(cells, kind)


## move ember
class Move:
	extends Action

	static func read(words: PackedStringArray) -> Variant:
		return Move.new() if " ".join(words) == "move ember" else 'expected "move ember"'

	func run(arena: Arena) -> void:
		arena.move_food()


## drop haste   (or ghost, or trim)
class Drop:
	extends Action
	var powerup: GDScript

	static func read(words: PackedStringArray) -> Variant:
		var named := {"haste": HastePowerup, "ghost": GhostPowerup, "trim": TrimPowerup}
		if words.size() != 2 or not named.has(words[1]):
			return 'expected "drop" and a powerup: haste, ghost, or trim'
		var drop := Drop.new()
		drop.powerup = named[words[1]]
		return drop

	func run(arena: Arena) -> void:
		arena.drop(powerup)


## Each verb of the language and the Action class that reads it.
static func verbs() -> Dictionary:
	return {
		"say": Say, "spread": Spread, "replace": Replace, "place": Place, "move": Move, "drop": Drop
	}


static func load_file(path: String) -> Rulebook:
	if not FileAccess.file_exists(path):
		var missing := Rulebook.new()
		missing.errors.append("%s: no such rules file" % path)
		return missing
	return parse(FileAccess.get_file_as_string(path), path.get_file())


## Read rules from text. source names the file in error messages.
static func parse(text: String, source := "level.rules") -> Rulebook:
	var book := Rulebook.new()
	var lines := text.split("\n")
	for i in lines.size():
		var line := lines[i].strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var problem := book._read_rule(line)
		if not problem.is_empty():
			book.errors.append("%s:%d: %s" % [source, i + 1, problem])
	return book


## Follow the arena: every tick of play, run the rules. The arena holds this
## connection, so the connection holds the arena only weakly: RefCounted objects that
## point at each other are never freed.
func attach(arena: Arena) -> void:
	var weak: WeakRef = weakref(arena)
	arena.ticked.connect(func(): run(weak.get_ref()))


## Run each rule whose trigger fires on this tick.
func run(arena: Arena) -> void:
	for rule in rules:
		if rule.trigger.fires(arena):
			rule.action.run(arena)


## Parse one line into a Rule and keep it; return what is wrong, or "" if nothing.
func _read_rule(line: String) -> String:
	var colon := line.find(":")
	if colon < 0:
		return 'expected "when: what", like "every 40 ticks: spread lava 2"'
	var trigger: Variant = Trigger.read(line.left(colon).split(" ", false))
	if trigger is String:
		return trigger
	var words := line.substr(colon + 1).strip_edges().split(" ", false)
	var verb := words[0] if not words.is_empty() else ""
	if not verbs().has(verb):
		return 'unknown action "%s" (try %s)' % [verb, ", ".join(verbs().keys())]
	var action: Variant = verbs()[verb].read(words)
	if action is String:
		return action
	for kind in action.kinds():
		if not Board.TILES.has(kind):
			return 'unknown tile kind "%s" (try %s)' % [kind, ", ".join(Board.TILES.keys())]
	var rule := Rule.new()
	rule.trigger = trigger
	rule.action = action
	rules.append(rule)
	return ""


## Rules never drop a wall or lava on the dragon or right in front of it, and never
## put the ember or a pickup on ground where it could not have appeared.
static func safe(arena: Arena, cell: Vector2i, kind: String) -> bool:
	var row: Dictionary = Board.TILES[kind]
	if cell == arena.food or cell == arena.pickup_cell:
		return row.spawns
	if row.solid or row.deadly:
		return not (arena.dragon.body.has(cell) or arena.near_head(cell))
	return true


static func parse_number(word: String) -> int:
	return word.to_int() if word.is_valid_int() else 0


## "20,9" as a cell, or (-1, -1) when it is not two whole numbers.
static func parse_cell(word: String) -> Vector2i:
	var parts := word.split(",")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i(-1, -1)
	return Vector2i(parts[0].to_int(), parts[1].to_int())
