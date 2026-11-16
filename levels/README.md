# Levels

Each `*.txt` here is one level: a few `key: value` headers, a blank line, then the
map, one character per cell. Save a new file and it shows up in the game's level
select; no code needed. `core/level.gd` reads these, and a mistake becomes a message
naming the file and line (shown in the game and by `deno task test`).

```
title: First Flight
blurb: Eat embers to grow.

##########
#..~~=~..#
#>.......#
##########
```

| Character | Tile | What it means (`Board.TILES`) |
| --- | --- | --- |
| `.` | floor | open ground; embers appear here |
| `#` | wall | solid: running into it ends the flight |
| `~` | water | wading halves your speed; embers never land in it |
| `=` | bridge | full speed over water; embers can land on it |
| `%` | lava | the head goes in, the dragon does not come out |
| `>` `<` `^` `v` | floor | where the dragon starts, pointing the way it faces |

Rules the parser checks:

- Every map row is as wide as the first one.
- Exactly one start arrow, with three open cells behind it for the body.
- Headers (`title`, `blurb`) go above the map.

`tests/level_test.gd` also loads every file here and checks that each ember spot
can be reached from the start, so a level with a sealed-off pocket fails CI.

## Rules files

A `*.rules` file scripts what happens *during* a level, one rule per line,
`when: what`. The campaign (`campaign.gd`) picks one per level with
`with_rules("eruption")`. `core/rulebook.gd` reads them; mistakes are reported by
file and line, like maps. Lines starting with `#` are comments.

```
# eruption.rules
at tick 3: say "The caldera rumbles. Feed quickly."
every 40 ticks: spread lava 2
at score 7: replace lava with water
at score 11: place lava from 19,12 to 20,13
```

| When | Fires |
| --- | --- |
| `at tick N` | once, N ticks after the first move (about nine ticks a second) |
| `every N ticks` | on every Nth tick |
| `at score N` | once, as soon as the score reaches N |

| What | Does |
| --- | --- |
| `say "text"` | shows the text under the dragon for a few seconds |
| `spread KIND N` | N clear cells touching KIND become KIND; lava never seals off ground you could reach |
| `replace KIND with KIND` | every cell of the first kind becomes the second |
| `place KIND at X,Y` | one cell (X across, Y down, counting from 0 at the map's top left) |
| `place KIND from X,Y to X,Y` | a rectangle of cells |
| `move ember` | the ember jumps somewhere new |
| `drop POWERUP` | a `haste`, `ghost`, or `trim` pickup appears |

Rules never put a wall or lava on the dragon or within three moves of its head,
and never strand the ember on ground where it could not have appeared.
