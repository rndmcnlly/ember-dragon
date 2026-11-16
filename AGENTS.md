# Ember Dragon: notes for coding agents (and curious humans)

This is the course staff's own showcase for CMPM 121's D4 project, so agents may edit
it as directed by its author. Students' own D4 repositories carry the course's agent
policy in their AGENTS.md; that policy, not this file, governs work on them.

A Godot 4.7 + Blender (`bpy`) game driven entirely from text and `deno task`.
Read README.md for the task list and DESIGN.md for the vocabulary and one section per
menu item. Ground answers in this project's files and in version-matched official
docs (Godot 4.7, Blender 5.2 Python API); link them.

## Map

- `core/`: the rules as plain GDScript (`RefCounted`, no Nodes). Tested headless by
  `deno task test`. Keep engine calls out of here. `session.gd` is one run at one
  level (`Session`): it owns the board, both dragons, food, pickups, and rules that
  involve more than one of them. `campaign.gd` sequences levels and builds every
  Session through `Step.play()`. `controllers/` says who steers a dragon.
- `levels/`: maps (`*.txt`), event scripts (`*.rules`), and the campaign written in
  the internal DSL (`campaign.gd`); `levels/README.md` is the legend and rules reference.
- `app/`: the engine adapter. `main.gd` keeps the clock, ticks the session, and draws;
  `stage.gd` builds sky, light, and tiles, and loads the kit (`Stage.load_kit()`);
  `dragon_view.gd` draws one dragon; `effects.gd` is juice driven by Session signals;
  `kit_viewer.gd` is `deno task kit`. It reads core state; it never decides rules.
- `tools/build_art.py`: all 3D art, as code; `tools/build_sfx.py`: all sound.
  `art/dragon_kit.glb` and `sfx/*.wav` are their outputs: regenerate them with
  `deno task art` and `deno task sfx`, never edit them by hand.
- `playtests/`: plans and the driver for `deno task playtest`; start at PLAYTEST.md.
  Throwaway scripts go in the gitignored `playtests/scratch/`.
- `tests/`: `*_test.gd`, run by `tests/run_tests.gd`, plus golden files.

## Conventions that are easy to break

- Godot exits 0 even when scripts fail to parse. Trust `deno task ci` (its wrapper
  fails on script errors), not Godot's exit code.
- Piece names are the contract between Blender and Godot: the registries in
  `build_art.py` (`PIECES`, `RIVAL_PIECES`, `PROPS`, `TILES`), `Kit.Piece` and
  `Board.TILES` in `core/`. Openings in `Kit.OPENINGS` must match how pieces are
  modeled. The game uses only each object's mesh; the rows in the .glb are for viewers.
- A new tile kind is three small edits: a row in `Board.TILES` (what it means to the
  rules), a builder in `TILES` (what it looks like), and a legend character in
  `Level.LEGEND` and `levels/README.md`.
- Every random choice draws from the Session's seeded `rng` (or `Terrain`'s), in a
  fixed order. Breaking that breaks `tests/golden.replay` and shared seeds.
- Files the game reads at run time that are not Godot resources must be listed in
  `include_filter` in `export_presets.cfg`, or the web build will not find them.
- Run `deno task fmt` before `deno task ci`; gdlint caps lines at 100 characters.
- Do not open windows unasked (`deno task dev`, `kit`, recorded playtests). A dry-run
  playtest (`--dry`) and `deno task ci` are headless.
- When an item changes, keep its DESIGN.md section and the Menu table true.
