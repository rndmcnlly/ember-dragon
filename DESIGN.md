# Ember Dragon: design notes

Instructor reference solution for D4: the baseline plus two menu items
(powerups, sound made with code). Written as a pair might write it for a teammate
joining the project.

## Words we use

| Word | Meaning | In code |
| --- | --- | --- |
| cell | one square of the grid | `Vector2i` |
| board | the ground: one tile kind per cell | `Board.tiles` |
| tile kind | what a cell is made of (floor, wall, lava, water, bridge) and what that means to the rules | `Board.TILES` |
| level | a map in `levels/*.txt`: headers, then one character per cell | `Level` |
| pace | how fast the dragon flies right now: Haste times the ground under its head | `Arena.pace()` |
| tick | one step of the rules; the dragon moves one cell | `Arena.tick()` |
| body | the dragon's cells, head first | `Dragon.body` |
| piece | one of the kit's models: head, straight, turn, tail | `Kit.Piece` |
| kit | all pieces, built by `tools/build_art.py` | `art/dragon_kit.glb` |
| ember | food; eating one scores 1 and grows 3 cells | `Arena.food` |
| campaign | the levels in order, each with a goal and tuning | `Campaign.steps` |
| rule | one line of a `.rules` file: when, then what | `Rulebook.Rule` |
| pickup | a powerup waiting on the board | `Arena.pickup` |
| effect | a powerup in progress, counting down ticks | `Arena.active` |
| controller | whoever steers a dragon: the keyboard, the AI, or a replay | `Controller` |
| rival | a second dragon, steered by the AI, racing you for embers | `Arena.rival` |

## Where things live

- **Rules** live in `core/` and never touch a Node. That's why `deno task test` can
  check them without a window, and why the game could move to another engine.
- **Pictures and sound** live in `game/main.gd`. It reads the Arena's state every
  frame and listens to its signals; it never decides what happens.
- **Assets are code too.** `deno task art` rebuilds the models, `deno task sfx`
  rebuilds the sounds; we commit the outputs so Godot and CI don't need Blender.

## Patterns, and what they bought us

- **Command:** `Dragon.turn()` queues turns and `steer()` applies one per tick, so
  two quick key presses become two turns instead of a U-turn into the neck.
- **Observer:** `Arena` emits `ate`, `powered`, `died`; sound subscribes. Adding
  particles later means adding a listener, not editing the rules.
- **Strategy:** each `Powerup` subclass changes the arena its own way. A new one is
  a new file plus one line in `Arena.pickup_kinds`; no `match` on powerup names.
  Controllers are Strategy too: the keyboard, the rival's AI, and a replay each steer
  a dragon through the same one-method interface (see Rival dragon).
- **Flyweight:** every segment shares one of four meshes.
- **Type Object:** `Board.TILES` says what each tile kind means (`solid`, `deadly`,
  `pace`, `spawns`). The Arena asks `board.is_solid(cell)`, never "is this a wall?",
  so a new kind of ground is a new row there plus a builder of the same name in
  `build_art.py`.
- **Data-driven:** `Kit.OPENINGS` says which sides each piece connects; one lookup
  picks the piece and rotation for every cell, so there is no case per corner.
- **Game loop:** rules tick at a fixed rate (doubled by Haste) while drawing runs
  every frame; the camera eases toward the head between ticks.

## Decisions we argued about

- **Input as events, not polling.** Checking `Input.is_action_just_pressed` each
  frame missed fast taps on a slow machine. `_unhandled_input` never does.
- **The dragon waits for the first key.** The web build takes a few seconds to load,
  and the dragon used to fly into the wall before anyone was looking.
- **Ghost can end mid-overlap.** We kept it: the countdown is in the corner, and
  the risk makes the powerup interesting.
- **Seeded randomness.** `Arena.new(board, seed)` makes food placement (and every rule that rolls dice) repeatable,
  which the tests rely on.

## Next, if we had another week

Terrain generation as another Strategy (rocks the dragon must avoid).

## Look and feel

The adapter is now three files: `game/main.gd` (loop, input, dragon, HUD),
`game/stage.gd` (sky, sun, tiles), and `game/effects.gd` (juice).

- **One Environment does most of the mood:** a dusk procedural sky lights the
  scene (ambient from sky), AgX tonemapping keeps embers orange as they brighten,
  depth fog in the horizon color hides the edge of the world, and glow with a
  threshold of 0.85 makes only emissive things bloom. The web renderer's color
  buffer is low dynamic range, so that threshold was tuned by eye, not by physics.
- **The board is data:** `core/board.gd` maps each cell to a kind name ("floor",
  "wall"); the Arena collides with it and the Stage draws each kind as one
  MultiMesh, with a kit mesh of the same name.
  A missing mesh becomes a plain box (magenta for unknown kinds), never a crash.
- **Smooth motion without changing the rules:** the rules still jump one cell per
  tick. Between ticks only the ends of the body move (the head slides out of the
  neck, the old tail slides forward), and a sine wave keyed to each cell's age
  makes the body ripple without jumping when a tick lands.
- **Juice is a listener:** `Effects.watch(arena)` subscribes to `ate`, `powered`,
  and `died` for sparks, screen flashes, camera shake, and slow motion. Deleting
  `effects.gd` and its two lines in `main.gd` leaves a working, quieter game.
  Its listeners read the Arena from a field instead of capturing it: a lambda that
  captures the Arena it listens to is a cycle RefCounted never frees, and every
  finished game used to stay in memory (`tests/effects_test.gd` guards this).
- **Not available on the web renderer:** screen-space reflections, volumetric fog,
  depth of field, and glow levels or blend modes. We left them out.

## Levels in text files

**Where:** `levels/*.txt` (the maps, with `levels/README.md` as the legend),
`core/level.gd` (the parser), `tests/level_test.gd`.
**Pattern:** data-driven design over a Type Object. A level file says *where* things
are; `Board.TILES` says *what they mean*; nothing in between knows any tile by name.

```
title: First Flight
blurb: Eat embers to grow.

#########
#..~~=..#
#>..%%..#
#########
```

- **Five tile kinds, four columns.** Wall is `solid` (you crash against it), lava is
  `deadly` (your head goes in first, which is why it reads differently from a wall),
  water has `pace` 0.5 (Haste in water comes out even), and `spawns` decides where
  embers may land (not in water or lava). Bridges are floor that looks like a bridge:
  their only rule is "not water".
- **Errors cite the line.** `Level.parse` never crashes and never guesses: a ragged
  row, a stray symbol, a missing or doubled start arrow, or a start with no room
  for the body each become `ford.txt:7: ...`. The game shows them on the title
  banner and falls back to an empty field, so a typo costs a glance, not a debugger.
- **Every level is checked as winnable.** A test loads every file in `levels/` and
  flood-fills from the start: any cell where an ember could appear but the dragon
  could never reach fails CI. It caught two of our own maps whose start arrow sat
  too close to a wall.
- **The art follows the vocabulary.** `build_lava`, `build_water`, and `build_bridge`
  in `tools/build_art.py` use the same helpers as the floor (`rounded_box`, `mottle`,
  `sweep`). Blender names two materials "Lava" and "Water"; `game/stage.gd` finds
  them by name and swaps in `game/lava.gdshader` (cracks of light that drift under
  a crust) and `game/water.gdshader` (wobbling reflections), both driven by world
  position so neighboring tiles flow as one surface. Bridges turn to span whatever
  river they sit in (`Stage._bridge_yaw`).
- **Export needs a nudge.** Godot only packs resources it knows; `include_filter` in
  `export_presets.cfg` adds `levels/*.txt` to the web build.

**Try it:** press 1 to 5 on the title banner to pick a level. Copy `meadow.txt` to
`mine.txt`, draw something, and it appears as a sixth level next time the game runs
(the campaign adds any map it does not name, endless, at the end).

## Internal DSL

**Where:** `core/campaign.gd` (the builder), `levels/campaign.gd` (the campaign we
ship, written in it), `tests/campaign_test.gd`.
**Pattern:** fluent builder, which Fowler calls an internal DSL: ordinary GDScript
calls, chosen and chained so the code reads like the design doc.

```gdscript
var trail := Campaign.new("The Ember Trail")
trail.level("meadow").eat(5).without_pickups()
trail.level("ford").eat(8).with_pickups([HastePowerup])
trail.level("cinders").eat(10).with_pickups([HastePowerup, TrimPowerup])
trail.level("confluence").eat(12).with_pickups([GhostPowerup, TrimPowerup])
trail.level("caldera").eat(15).faster(1.15)
return trail.then_any_other(Level.catalog())
```

- **Each call returns the builder**, so calls chain; `level()` starts a step and the
  rest tune the latest one. The builder's output is plain data (`Campaign.Step`),
  and `Step.prepare(arena)` is the only place it touches the rules: the Arena
  learned `goal`, `tempo`, and a `WON` state, and knows nothing about campaigns.
- **One chain per line, on purpose.** Our first draft was one long chain in
  parentheses; `gdformat` split it into a column of `. eat(5)` lines that read like
  nothing. A statement per level keeps every line a sentence and the formatter happy.
- **The DSLs meet here.** `.with_rules("eruption")` picks a level's rules file, so
  the same map can be replayed with different events, and the rules language
  never needs to know which map it runs on.
- **Why internal, not another text file?** The campaign refers to code (powerup
  classes), gets autocompletion and type checks for free, and changes rarely. Maps
  change constantly and are drawn by people who should not need GDScript; that is
  why they are text (see Levels in text files), and why the per-level events below
  get their own language (see External DSL).
- **Progression:** eat the goal and the level clears (gold burst, Enter for the
  next). Number keys still jump anywhere; the last level loops back to the first.

**Try it:** add `trail.level("meadow").eat(30).faster(1.5)` as a sixth line and play
level 6: the same map, retuned as a speed trial, with no new files.

## External DSL

**Where:** `core/rulebook.gd` (parser and interpreter), `levels/*.rules` (five
scripts), the language reference at the end of `levels/README.md`,
`tests/rulebook_test.gd`.
**Pattern:** Interpreter (GoF). Parsing turns each line into a `Rule` holding a
`Trigger` and an `Action`; at run time those objects run themselves against the Arena.

```
# eruption.rules: the caldera wakes as you feed it
at tick 3: say "The caldera rumbles. Feed quickly."
every 40 ticks: spread lava 2
at score 7: say "Rain! The lava hisses into pools."
at score 7: replace lava with water
at score 11: place lava from 19,12 to 20,13
```

- **A verb is a class.** `Say`, `Spread`, `Replace`, `Place`, `Move`, `Drop` each have
  a static `read(words)` that parses their own grammar and returns an instance or an
  error message, and a `run(arena)` that does the work. A new verb is one class and
  one entry in `Rulebook.verbs()`. (This shape came from `gdlint` refusing our first
  draft's 13-return `match`: the linter was right.)
- **Errors cite the line** and suggest what was meant:
  `eruption.rules:4: unknown action "sprad" (try say, spread, replace, place, move, drop)`.
  Unknown tile kinds are checked against `Board.TILES`, so the language grows with
  the tile vocabulary for free.
- **Observer, again.** The Arena now emits `ticked` after each tick of play and
  `announced` for `say`; `Rulebook.attach(arena)` subscribes. The connection holds the
  Arena through a `WeakRef`: a lambda capturing the Arena it listens to is a cycle
  that RefCounted never frees, which our test runner flagged as leaked objects.
- **The ground can change now**, so `Board.set_kinds()` emits `changed`. The Stage
  redraws at most once a frame (seeded per cell, so nothing shuffles), Effects puffs
  sparks where a few tiles changed and flashes the screen when many did, and each
  game plays on `level.board.copy()`, so a retry starts from the map as drawn.
- **Fair by construction.** `spread` refuses any cell whose loss would cut the
  dragon off from ground it could reach (a flood fill before and after, via
  `Board.reachable`), and no rule drops lava or walls within three moves of the
  head. Randomness comes from the Arena's seeded `rng`, so a replay of the same
  seed and turns sees the same eruption.

**Try it:** play The Caldera (5): lava creeps every few seconds, rain at 7 embers
turns the ring into a lake, and at 11 the island cracks open. Then break a line in
`eruption.rules` and watch the title banner name it.

## Rival dragon

**Where:** `core/controllers/` (`controller.gd`, `player_controller.gd`,
`greedy_controller.gd`), the two-dragon tick in `core/arena.gd` (`tick`, `_crash`,
`_collide`, `summon_rival`), `game/dragon_view.gd`, the `rival()` palette swap at the end
of `tools/build_art.py`, `tests/rival_test.gd`.
**Pattern:** Strategy, for who steers. A `Controller` has one method,
`steer(arena, dragon)`, called once per tick just before that dragon moves. The
keyboard is one controller (`PlayerController`: keys wait there until the tick), the
AI is another (`GreedyController`), and the Arena treats both dragons with the same
rules, in the same function.

```gdscript
controller.steer(self, dragon)
if rival != null:
	rival_controller.steer(self, rival)
var next := dragon.steer()
var rival_next := rival.steer() if rival != null else NOWHERE
```

- **The AI is greedy, with a flood fill for safety.** Of straight, left, and right it
  never takes a move that crashes, avoids a move whose open space (counted by flood
  fill) could not hold its body, steers clear of a head-on it would lose, and then
  heads for the ember as the crow flies. As the crow flies, not by path: rivers and
  walls fool it, which is what makes it beatable. A test proves it will not dive into
  a one-cell pocket for an ember, and another hands the *player's* dragon to the AI
  too and lets two AIs fly every map: the rules do not care who is steering.
- **Collisions, decided.** Both dragons decide, then both crashes are judged on where
  everything was before anyone moved, so neither has the first move. Into the other's
  body: that dragon crashes (a tail tip about to move away is safe, as with your own).
  Head to head, in the same cell or swapping cells: the longer dragon wins, so every
  ember is armor; equals both fall, and since the player falls, the game ends. Ghost
  passes through the rival, both ways. A crashed rival is gone for the level.
- **What the rival does not share.** Pickups are the player's alone (the rival flies
  over them), and there is one clock: the rival keeps the player's pace, Haste and
  water included. The rival does race you to the level's goal: if it eats that many
  embers first, you lose.
- **Optional per level, two ways.** `.with_rival()` in the campaign (the internal DSL)
  starts a level with one, as Fire Meets Water does; `summon rival` in a rules file
  (the external DSL) brings one mid-level, as The Ford does at 3 embers. Either way it
  hatches at least 12 moves away, at a spot picked by the Arena's seeded `rng`.
- **A distinct look from the same kit.** `rival()` in `build_art.py` wraps any piece
  builder and repaints its faces from `RIVAL_PALETTE` (obsidian scales, crimson belly
  and spikes, red eyes and flame), so `rival_head` and friends share every shape with
  the hero and no geometry is copied. `DragonView` draws either set, by name prefix.

**Try it:** play The Ford (2) and eat three embers, or Fire Meets Water (4) from the
start. Tempt the rival across your body, or let it grow and meet it head-on.

## Menu

| Item | Group | Files |
| --- | --- | --- |
| Levels in text files | Language | `levels/`, `core/level.gd`, `core/board.gd`, `tests/level_test.gd` |
| Internal DSL | Language | `core/campaign.gd`, `levels/campaign.gd`, `tests/campaign_test.gd` |
| External DSL | Language | `core/rulebook.gd`, `levels/*.rules`, `levels/README.md`, `tests/rulebook_test.gd` |
| Powerups | Systems | `core/powerup.gd`, `core/powerups/` |
| Rival dragon | Systems | `core/controllers/`, `core/arena.gd`, `game/dragon_view.gd`, `tools/build_art.py` (`rival()`), `tests/rival_test.gd` |
| Sound as code | Content | `tools/build_sfx.py`, `sfx/` |
| Showcase art | Content | `tools/build_art.py`, `art/`, `game/stage.gd`, `game/effects.gd` |
