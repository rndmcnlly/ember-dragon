# Ember Dragon: design notes

Instructor reference solution for D4: the baseline plus two menu items
(powerups, sound made with code). Written as a pair might write it for a teammate
joining the project.

## Words we use

| Word | Meaning | In code |
| --- | --- | --- |
| cell | one square of the grid | `Vector2i` |
| tick | one step of the rules; the dragon moves one cell | `Arena.tick()` |
| body | the dragon's cells, head first | `Dragon.body` |
| piece | one of the kit's models: head, straight, turn, tail | `Kit.Piece` |
| kit | all pieces, built by `tools/build_art.py` | `art/dragon_kit.glb` |
| ember | food; eating one scores 1 and grows 3 cells | `Arena.food` |
| pickup | a powerup waiting on the board | `Arena.pickup` |
| effect | a powerup in progress, counting down ticks | `Arena.active` |

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
- **Flyweight:** every segment shares one of four meshes.
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
- **Seeded randomness.** `Arena.new(size, seed)` makes food placement repeatable,
  which the tests rely on.

## Next, if we had another week

Terrain generation as another Strategy (rocks the dragon must avoid), and a
rival dragon steered by a simple AI using the same `Dragon` class.

## Look and feel

The adapter is now three files: `game/main.gd` (loop, input, dragon, HUD),
`game/stage.gd` (sky, sun, tiles), and `game/effects.gd` (juice).

- **One Environment does most of the mood:** a dusk procedural sky lights the
  scene (ambient from sky), AgX tonemapping keeps embers orange as they brighten,
  depth fog in the horizon color hides the edge of the world, and glow with a
  threshold of 0.85 makes only emissive things bloom. The web renderer's color
  buffer is low dynamic range, so that threshold was tuned by eye, not by physics.
- **The board is data:** `_board()` maps each cell to a kind name ("floor", "wall"),
  and the Stage draws each kind as one MultiMesh, with a kit mesh of the same name.
  A missing mesh becomes a plain box (magenta for unknown kinds), never a crash.
- **Smooth motion without changing the rules:** the rules still jump one cell per
  tick. Between ticks only the ends of the body move (the head slides out of the
  neck, the old tail slides forward), and a sine wave keyed to each cell's age
  makes the body ripple without jumping when a tick lands.
- **Juice is a listener:** `Effects.watch(arena)` subscribes to `ate`, `powered`,
  and `died` for sparks, screen flashes, camera shake, and slow motion. Deleting
  `effects.gd` and its two lines in `main.gd` leaves a working, quieter game.
- **Not available on the web renderer:** screen-space reflections, volumetric fog,
  depth of field, and glow levels or blend modes. We left them out.
