# Changelog

What changed, for players and for whoever works on the game next. Newest first.
Versions match git tags without the `v`: tag `v1.0.0` publishes the section
`## 1.0.0`, and `.github/workflows/release.yml` refuses a tag with no section.
To release, rename "Unreleased" to the version and date, commit, then tag (see
README.md, "Releasing").

## Unreleased

Nothing has been tagged yet. Everything below is on `main` and on Pages.

### Process

- **Names match E5.** `game/` is now `app/` (the engine adapter: views and input)
  and `Arena` is now `Session` (one run at one level), the words the course's E5
  starter uses, so "game" means only the product. Nothing changes in play.
- **Release pipeline.** Version tags publish the web build to itch.io with butler
  (`release.yml`), after the same checks as every push. It skips, with a notice
  in the run's log, until the `BUTLER_API_KEY` secret and `ITCH_TARGET` variable
  exist. Pages still deploys every push to `main`.
- **Agentic playtest.** `deno task playtest <plan>` plays a hand-written replay
  through the game, headless first, then recorded with Godot's Movie Maker:
  `video.avi`, an event log, a per-tick path, PNG snapshots, and a one-screen
  summary in `playtests/out/`. `PLAYTEST.md` tells a coding agent how to write
  plans, run them, and report. Three sample plans are checked in CI.

### Content

- **The Wilds.** An endless last level on a map grown from a seed: a river with
  bridges, rock, lava pools, always a clear start and every ember reachable.
  Today's map by default, N for another, `?seed=4821` to share one.

### Systems

- **Camera** frames both dragons while a rival lives.
- **Water slows both dragons** the same way: each wades at half pace on the
  shared clock.
- **Replays.** R watches your last game again, S saves it (it survives a reload).
  A recorded game of The Ford is replayed in CI and must end exactly as recorded.
- **Rival dragon.** An AI dragon races you for embers on The Ford (after 3) and
  Fire Meets Water (from the start). Head-on, the longer dragon wins.

### Language

- **Rules files.** Levels script their own events (`levels/*.rules`): messages,
  spreading lava, rain that turns lava to water, a rival's arrival. Mistakes are
  shown by file and line.
- **The Ember Trail.** Levels come in order, each with a goal; clear one with
  Enter for the next, or press 1 to 6 to pick any.
- **Levels in text files.** Five maps in `levels/*.txt` with lava, water, and
  bridges; a new file is a new level without code.
- **Board.** The ground is made of tile kinds, and the rules ask a tile what it
  means instead of checking for walls.

### The starting point

- Ember Dragon: the D4 baseline (a voxel dragon, embers, growth, collisions)
  plus powerups (Haste, Ghost, Trim), sound made with code, and Blender-built art
  with lighting and effects.
