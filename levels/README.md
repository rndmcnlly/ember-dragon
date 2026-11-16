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
