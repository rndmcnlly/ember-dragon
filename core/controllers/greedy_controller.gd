## The rival's AI: fly toward the ember, but never into a dead end. Each tick it scores
## the three ways it could go (straight, left, right) and takes the best:
##   - never a move that crashes this tick (wall, lava, either dragon's body);
##   - a move whose open space (a flood fill) could not hold its own body is a trap,
##     taken only when every move is one;
##   - avoid cells a head-on bump could happen in, unless it is the longer dragon;
##   - then, closest to the ember as the crow flies (not by path, so walls and rivers
##     fool it, which is what makes it beatable).
## It reads the Arena and never rolls dice, so the same game always plays out the same
## way, which is what lets a replay record only the player's keys.
class_name GreedyController
extends Controller

const TRAPPED := -1000  # a move into a pocket too small for the body
const RISKY := -500  # a move the other dragon's head could also take


func steer(arena: Arena, dragon: Dragon) -> void:
	var best := dragon.heading
	var best_score := -INF
	# Straight first: on a tie it keeps going, which looks calmer than zig-zagging.
	for direction in [
		dragon.heading, Kit.quarter_turn(dragon.heading), -Kit.quarter_turn(dragon.heading)
	]:
		var cell: Vector2i = dragon.body[0] + direction
		if arena.crashes(dragon, cell):
			continue
		var score := -float(_distance(cell, arena.food))
		var room := _room(arena, cell, dragon.body.size())
		if room < dragon.body.size():
			score += TRAPPED + room  # if every way is a trap, pick the roomiest
		var other := arena.opponent(dragon)
		if other != null and other.body.size() >= dragon.body.size():
			if _distance(cell, other.body[0]) == 1:
				score += RISKY
		if score > best_score:
			best_score = score
			best = direction
	if best != dragon.heading:
		dragon.turn(best)


## How many cells are open from here, counting up to enough. Both bodies count as
## walls, which is cautious: tails move away, but not before the head gets there.
func _room(arena: Arena, from: Vector2i, enough: int) -> int:
	var seen := {from: true}
	var frontier: Array[Vector2i] = [from]
	while not frontier.is_empty() and seen.size() < enough:
		var cell: Vector2i = frontier.pop_back()
		for step in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = cell + step
			if not seen.has(next) and arena.is_open(next):
				seen[next] = true
				frontier.append(next)
	return seen.size()


func _distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
