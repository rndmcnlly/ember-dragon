# Playtesting, for coding agents

You play the game from a plan file and report what happened, with evidence a
human can check. Read this whole file before you start.

**Rules:**

- During a playtest, create or edit only your plan: `playtests/<name>.replay`.
  Do not edit any other file, even if you find a bug. Report the bug instead.
- Always dry-run first (step 2). Record (step 3) once, at the end. Each
  recording opens a window on the human's screen.
- Do not open `video.avi` yourself. It is for humans.

## 1. Write a plan

A plan is a replay file you write by hand (the game's own replays, saved with S,
are plans too). Make `playtests/<name>.replay`, where `<name>` is short,
lowercase, with dashes, such as `meadow-pond`. Start from one of the samples
there (`ford-embers.replay`, `caldera-lava.replay`, `wilds-wade.replay`) or
from this:

```
# What this plan tries to show, in one or two comment lines.
# expect: ate ember
level: 2 ford
seed: 17
ticks: 60
7: up
15: left
```

| Line | Meaning |
| --- | --- |
| `# words` | a comment; the first comments are your intent, copied into `summary.txt` |
| `# expect: words` | optional; `summary.txt` says `met` if `log.txt` contains these words, else `NOT MET` |
| `level: N MAP` | which level: the number *and* the name from the table below |
| `seed: N` | any whole number. The same seed gives the same embers every time |
| `ticks: N` | how long to play. About 9 ticks per second; keep it 120 or less |
| `T: DIRECTION` | on tick `T` the dragon turns `up`, `down`, `left`, or `right`. Put lines in tick order |

| Level line | Map | Has |
| --- | --- | --- |
| `level: 1 meadow` | `levels/meadow.txt` | a pond (water) |
| `level: 2 ford` | `levels/ford.txt` | a river, two bridges; a rival dragon after 3 embers |
| `level: 3 cinders` | `levels/cinders.txt` | lava with two stone crossings; Haste every 120 ticks |
| `level: 4 confluence` | `levels/confluence.txt` | lava west, a rising river east; a rival dragon from the start |
| `level: 5 caldera` | `levels/caldera.txt` | a lava ring that spreads every 40 ticks |
| `level: 6 wilds` | grown from the seed | a river, rocks, lava; different for every seed |

What each level's rules do is in `levels/<map>.rules` (the level's `with_rules`
in `levels/campaign.gd` names the file).

**How the dragon moves:**

- A cell is `(x,y)`. `x` counts columns from 0 at the left. `y` counts rows from
  0 at the top: in `levels/<map>.txt`, the first line of the map (the first line
  of `#`) is `y = 0`; the `title:` and `blurb:` lines above it do not count.
  `up` makes `y` smaller, `down` makes it larger.
- The dragon flies straight. On floor and bridges it moves one cell every tick.
  In water it moves one cell every *other* tick.
- A turn on tick `T` moves the head in the new direction *on* tick `T`. To turn
  when the head is at cell C: find C in `path.txt` (for example
  `tick 6    head (11,12)`) and put the turn on the next tick (`7: up`).
- It cannot reverse, and turning the way it already flies does nothing. Both
  show up as warnings.
- Turns planned for a tick when the dragon stands still in water are skipped.
  The warning names the tick to use instead.
- Embers appear at random from the seed. You cannot know where until you run
  the plan: the log tells you, then you aim (step 2).
- You do not need to read the map to start: plan no turns, dry-run, and the log
  says where the head goes, what ground it crosses (`ground` lines), and where
  it would crash.

## 2. Dry run, then fix the plan, and repeat

```
deno task playtest playtests/<name>.replay --dry
```

No window opens; it takes a few seconds. It prints `summary.txt` and writes
`playtests/out/<name>/`. Then:

1. Read the `Ending` and `Warning` lines in the printed summary.
2. Read `playtests/out/<name>/log.txt`. Every line starts `tick N`, then one word:

   | Word | Means |
   | --- | --- |
   | `start` | where the head starts, which way it faces, where the first ember is |
   | `turn` | a turn from your plan, and where the head is after it |
   | `ember` | where the ember is now, and how far from the head (`8 left, 3 up from head`) |
   | `ate` | the dragon ate an ember |
   | `say` | a level's rules showed a message |
   | `ground` | the head moved onto a different kind of ground (floor, water, bridge, lava) |
   | `terrain` | a level's rules changed the ground |
   | `pickup`, `power` | a powerup appeared, or the dragon took it |
   | `rival` | a rival dragon hatched, ate, or crashed |
   | `status` | every 10 ticks: head, heading, ground, length, score, ember |
   | `died`, `won`, `end` | how the run ended; `died` gives the head's cell and heading |

3. Add or change **one** turn, the earliest one that is wrong, and run the dry
   run again. Everything after a changed turn moves, so the old `path.txt` is
   no longer true after it. Repeat until the summary shows what you wanted,
   every `Expect` line says `met`, and it says `Warnings   none`.
4. A run may end with `died` before `ticks:` runs out. If dying is not what you
   are testing, make `ticks:` smaller so the run stops before the crash.

An `expect:` line is a plain text search in `log.txt` (spaces and quotes do not
matter). Copy words from a log line you want to see, for example
`# expect: ate ember at (12,6)` or `# expect: died You fell into the lava`.

## 3. Record once

```
deno task playtest playtests/<name>.replay
```

It runs the dry run again (silently), then opens the game in a window for a few
seconds and records it. Do not close the window. It is done when it prints the
summary, with `Snapshots` and `Video` lines, and then
`Check      recorded game matches the dry run: yes`.

## 4. Read the evidence, in this order

All files are in `playtests/out/<name>/`.

1. `summary.txt`: one screen. Read it all.
2. `log.txt`: the events, by tick.
3. `path.txt`: one line per tick. Open it only to check a particular tick.
4. Snapshots, named `NN-tick-TTTT-what.png` (for example
   `03-tick-0009-ate.png`). Look only at the ones your findings need. Each is
   taken just after its event, so the `Replay N / M` counter in its top-left
   corner (`N` is the tick) can read a tick or two later.
5. `video.avi`: do not open it. Name it in your report for the human.

## 5. Report to the human

Copy this, fill it in, and keep every finding tied to a tick:

```
Playtest: playtests/<name>.replay (level N MAP, seed S, T ticks)
Goal: <your intent line>
Result: <the Ending line from summary.txt>
Expectations: <each Expect line, met or NOT MET>
Findings:
- tick N: <what happened>, seen in log.txt and <snapshot file>
Bugs or surprises: <each with its tick and evidence, or "none">
Evidence: playtests/out/<name>/video.avi (watch this), summary.txt, log.txt
```

A `NOT MET` expectation is usually a plan mistake: check your turns in
`path.txt` before calling it a bug. Call something a bug only if the log or a
snapshot shows the game breaking its own rules (see `levels/README.md`).

## If something goes wrong

| You see | Do this |
| --- | --- |
| `this replay is of level N (MAP), which the campaign no longer has` | the level number and name do not match: use a line from the table in step 1 |
| `unknown direction` | use only `up`, `down`, `left`, `right` |
| `expected "level: N MAP", ...` | that line is not one of the forms in step 1; comments start with `#` |
| `turn ... skipped: the dragon was wading` | move that turn to the tick the warning suggests |
| `turn ... did nothing` | the dragon already flies that way, or it would reverse: pick another tick or direction |
| `turn never happened: the run ended on tick N` | the dragon died first: read the `died` line in `log.txt` |
| `recorded game matches the dry run: NO` | report it as a bug, with both runs' `log.txt`. Do not keep retrying |
| no window, or a Movie Maker error | report it; the dry run's log is still evidence |
