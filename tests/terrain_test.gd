extends "res://tests/test_case.gd"

const TRAIL := preload("res://levels/campaign.gd")
const SEEDS := 60  # every property below must hold for each of these seeds


func test_the_same_seed_grows_the_same_map() -> void:
	for seed in [0, 7, 4821, 20261115]:
		var first := Terrain.new(seed).grow()
		var again := Terrain.new(seed).grow()
		assert_eq(first.tiles, again.tiles)
		assert_eq([first.start, first.facing], [again.start, again.facing])
	assert_true(Terrain.new(1).grow().tiles != Terrain.new(2).grow().tiles)


## Seed 4821 as grown when the Wilds shipped. A change to the generator that moves
## a single cell changes every shared seed and every saved replay of the Wilds; if
## that is on purpose, regenerate this file and say so in the commit.
func test_a_shared_seed_still_grows_the_same_map() -> void:
	var golden := FileAccess.get_file_as_string("res://tests/golden-wilds.txt")
	assert_eq(Terrain.new(4821).level().to_text(), golden)


## The dragon hatches on floor with open floor all around and a runway ahead: nothing
## solid, deadly, or slow within reach of its first few moves.
func test_the_start_is_clear() -> void:
	for seed in SEEDS:
		var board := Terrain.new(seed).grow()
		for cell in board.tiles:
			var gap: Vector2i = (cell - board.start).abs()
			if gap.x + gap.y <= Terrain.CLEARING:
				_expect_floor(board, cell, seed)
		for i in range(1 - Level.START_LENGTH, Terrain.RUNWAY + 1):
			_expect_floor(board, board.start + board.facing * i, seed)


## The same check the drawn levels pass (tests/level_test.gd): every cell where an
## ember could land can be reached from the start.
func test_every_ember_spot_is_reachable() -> void:
	for seed in SEEDS:
		var board := Terrain.new(seed).grow()
		var reached := board.reachable(board.start)
		for cell in board.tiles:
			if board.spawns_at(cell) and not reached.has(cell):
				failures.append("seed %d: ember spot %s cannot be reached" % [seed, cell])
				break


## A grown map speaks the same tile vocabulary as a drawn one: a river with bridges,
## rocks, and lava, inside a wall.
func test_a_grown_map_uses_every_tile_kind() -> void:
	for seed in SEEDS:
		var kinds := {}
		for kind in Terrain.new(seed).grow().tiles.values():
			kinds[kind] = true
		assert_eq(kinds.keys().size(), Board.TILES.size())


## Written out as a level file and read back, a grown map is the same level: the
## parser accepts it (start, body room, legend), and it could be saved into levels/.
func test_a_grown_map_is_a_valid_level_file() -> void:
	for seed in [3, 121]:
		var grown := Terrain.new(seed).level()
		var read := Level.parse(grown.to_text(), "wilds.txt")
		assert_eq(read.errors, [] as Array[String])
		assert_eq(read.board.tiles, grown.board.tiles)
		assert_eq([read.board.start, read.board.facing], [grown.board.start, grown.board.facing])


## The campaign's Wilds step grows its map from the game's seed, so a replay (level,
## seed, turns) regrows the same map before it replays the same session.
func test_the_wilds_step_and_its_replays_grow_from_the_seed() -> void:
	var trail: Campaign = TRAIL.ember_trail()
	var wilds := trail.steps.map(func(s): return s.map).find(Terrain.NAME)
	assert_true(wilds >= 0)
	var replay := Replay.parse("level: %d wilds\nseed: 4821\nticks: 1" % (wilds + 1))
	var session := replay.run(trail)
	assert_eq(session.board.tiles, Terrain.new(4821).grow().tiles)


## Two AIs fly grown maps for a while: they behave as on drawn maps, rival and all.
func test_two_ais_fly_grown_maps() -> void:
	for seed in 5:
		var session := Session.new(Terrain.new(seed).grow(), seed)
		session.controller = GreedyController.new()
		assert_true(session.summon_rival())
		session.start()
		for i in 200:
			session.tick()
		assert_true(session.ticks > 20)  # nobody crashed at the first wall


func _expect_floor(board: Board, cell: Vector2i, seed: int) -> void:
	if board.kind_at(cell) != "floor":
		failures.append("seed %d: %s is %s, in the clearing" % [seed, cell, board.kind_at(cell)])
