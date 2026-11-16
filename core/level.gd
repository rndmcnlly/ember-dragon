## A level read from a text file in levels/: a few "key: value" lines, then the map,
## one character per cell. Data-driven: a new level is a new .txt file and no code.
## Mistakes become messages that name the file and line, never a crash.
class_name Level
extends RefCounted

## Map characters and the tile kind each one stands for (levels/README.md shows them).
const LEGEND := {
	".": "floor",
	"#": "wall",
	"~": "water",
	"=": "bridge",
	"%": "lava",
}
## The dragon's head: an arrow pointing the way it faces. It stands on floor.
const STARTS := {
	">": Vector2i.RIGHT,
	"<": Vector2i.LEFT,
	"^": Vector2i.UP,
	"v": Vector2i.DOWN,
}
const HEADERS := ["title", "blurb"]
const START_LENGTH := 4  # the Arena's new dragon; its body needs room behind the head

var name := ""  # the file name without .txt, e.g. "ford"
var title := ""
var blurb := ""
var board := Board.new()
var errors: Array[String] = []  # "ford.txt:7: what went wrong"; empty when the level is good


## Every level file in a folder, by name ("ford"), in alphabetical order.
static func catalog(folder := "res://levels") -> Array[String]:
	var names: Array[String] = []
	for file in DirAccess.get_files_at(folder):
		if file.ends_with(".txt"):
			names.append(file.get_basename())
	names.sort()
	return names


static func load_file(path: String) -> Level:
	if not FileAccess.file_exists(path):
		var missing := Level.new()
		missing.errors.append("%s: no such level file" % path)
		return missing
	return parse(FileAccess.get_file_as_string(path), path.get_file())


## Read a level from its text. source names it in error messages.
static func parse(text: String, source := "level.txt") -> Level:
	var level := Level.new()
	level.name = source.get_basename()
	level.title = level.name.capitalize()
	var rows := []  # [line number, text] for each row of the map
	var lines := text.split("\n")
	for i in lines.size():
		var line := lines[i].strip_edges(false, true)  # drops "\r" from Windows line endings
		var at := "%s:%d: " % [source, i + 1]
		if line.is_empty():
			if not rows.is_empty() and _more_after(lines, i):
				level.errors.append(at + "blank line inside the map")
			continue
		var colon := line.find(":")
		if colon > 0 and line.substr(0, colon).is_valid_ascii_identifier():
			if not rows.is_empty():
				level.errors.append(at + "headers like '%s' go above the map" % line)
			elif line.substr(0, colon) in HEADERS:
				level.set(line.substr(0, colon), line.substr(colon + 1).strip_edges())
			else:
				level.errors.append(
					(
						at
						+ (
							"unknown header '%s' (try %s)"
							% [line.substr(0, colon), ", ".join(HEADERS)]
						)
					)
				)
			continue
		rows.append([i + 1, line])
	if rows.is_empty():
		level.errors.append("%s: no map; draw one below the headers" % source)
		return level
	level._read_map(rows, source)
	return level


static func _more_after(lines: PackedStringArray, i: int) -> bool:
	for j in range(i + 1, lines.size()):
		if not lines[j].strip_edges().is_empty():
			return true
	return false


func _read_map(rows: Array, source: String) -> void:
	var width: int = rows[0][1].length()
	board.size = Vector2i(width, rows.size())
	var starts := 0
	for y in rows.size():
		var number: int = rows[y][0]
		var row: String = rows[y][1]
		var at := "%s:%d: " % [source, number]
		if row.length() != width:
			errors.append(at + "this row is %d wide but the first is %d" % [row.length(), width])
		for x in mini(row.length(), width):
			var symbol := row[x]
			var cell := Vector2i(x, y)
			if LEGEND.has(symbol):
				board.tiles[cell] = LEGEND[symbol]
			elif STARTS.has(symbol):
				board.tiles[cell] = "floor"
				board.start = cell
				board.facing = STARTS[symbol]
				starts += 1
				if starts == 2:
					errors.append(at + "a second dragon start; the map needs exactly one")
			else:
				errors.append(
					at + "unknown tile '%s' in column %d (%s)" % [symbol, x + 1, _legend()]
				)
	if starts == 0:
		errors.append("%s: no dragon start; put one of > < ^ v on the floor" % source)
		return
	for i in range(1, START_LENGTH):
		var behind := board.start - board.facing * i
		if not Board.TILES[board.kind_at(behind)].spawns:
			var at := "%s:%d: " % [source, rows[board.start.y][0]]
			errors.append(
				at + "the dragon needs %d open cells behind its head" % (START_LENGTH - 1)
			)
			return


## The level as text that parse() reads back as the same level: how a grown map
## (see Terrain) can be saved into levels/ and edited by hand.
func to_text() -> String:
	var symbols := {}
	for symbol in LEGEND:
		symbols[LEGEND[symbol]] = symbol
	var lines := ["title: " + title, "blurb: " + blurb, ""]
	for y in board.size.y:
		var row := ""
		for x in board.size.x:
			var cell := Vector2i(x, y)
			if cell == board.start:
				row += STARTS.find_key(board.facing)
			else:
				row += symbols[board.kind_at(cell)]
		lines.append(row)
	return "\n".join(lines) + "\n"


static func _legend() -> String:
	var parts := []
	for symbol in LEGEND:
		parts.append("%s %s" % [symbol, LEGEND[symbol]])
	return "legend: " + ", ".join(parts) + ", > < ^ v start"
