# Ember Dragon showcase: build plan (instructor-side, delete before publishing)

This repo becomes the public inspiring version `https://github.com/rndmcnlly/ember-dragon`
for CMPM 121 D4 (Fall 2026, UC Santa Cruz). Students start from a much simpler
starter (`../d4-dev`); in lecture the instructor shows the starter, then this game,
to make each optional requirement concrete. Staff must be able to point at one
clear, findable example per menu item. Students may browse it but should find it
too interwoven to lift files from; that is fine, but each item's example must be
easy to *locate* and *read* (one file or folder where possible, named after the item).

## Ground rules for every agent working here

- Read README.md, DESIGN.md, AGENTS.md (in ../d4-dev, for conventions), and the
  code you touch. Keep `deno task ci` green (format check, gdlint, import, tests,
  web export). Run `deno task fmt` first. Godot exits 0 on script errors; trust the
  task's exit code, which watches for them.
- Rules live in `core/` (engine-free `RefCounted`, tested headless in `tests/`);
  `app/` only draws, plays sound, and forwards input. Every new rule gets tests.
- Art only via `tools/build_art.py` builders registered in `PIECES`/`TILES`
  (run `deno task art`, ~10 s, cached). Sound only via `tools/build_sfx.py`.
- Don't use `deno task dev` (it opens windows). For visual checks, export
  (`deno task build`), serve on a port of your own, e.g.
  `deno run -A jsr:@std/http@1/file-server dist --port 85xx`, and screenshot with
  Playwright using installed Chrome (`channel="chrome"`, args
  `--use-angle=swiftshader --enable-unsafe-swiftshader`). Wait ~9 s for load,
  click, then press keys; the dragon waits for the first arrow key. Kill only your
  own server (by PID). Keep scripts and screenshots in /tmp, not in the repo.
  Combine screenshots into one contact sheet before reading them (saves context).
- Commit after each item with a clear message (`git add -A && git commit`). No pushes.
- House style for comments and docs: no emdashes (use colons, commas, parentheses);
  short comments that explain why. Pedagogical single-purpose files over clever ones.
- Update DESIGN.md: one short subsection per menu item, titled with the item's
  name, saying where it lives, which pattern it shows, and how to try it.
  Also keep the "Menu" table at the end of DESIGN.md current (item, group, files).

## The D4 menu (pairs choose 2, from different groups)

| Group | Item | Pattern | Done when (students' bar; ours should exceed it) |
|---|---|---|---|
| Language | Levels in text files | data-driven, Type Object | 3+ ASCII levels in `levels/*.txt` with a legend; a new level needs no code; parser tests |
| Language | Internal DSL | fluent builder (Fowler) | waves/powerups/level events written as chained GDScript calls that read like a design doc; 3+ uses; tests |
| Language | External DSL | Interpreter (GoF), parsing | a small rule/event language in its own files; parse errors cite the line; tests |
| Systems | Powerups | Strategy | DONE: `core/powerup.gd`, `core/powerups/` |
| Systems | Rival dragon | Strategy for controllers | a second Dragon with its own controller (AI or local 2P); one rules core drives both |
| Systems | Replays | Command, seeded RNG | record turns per tick; same seed + record reproduces the session; golden replay test in CI |
| Content | Sound as code | Observer | DONE: `tools/build_sfx.py`, sounds wired to Session signals |
| Content | Procedural terrain | Strategy, seeded generation | obstacle generator; same seed, same map; tests prove the start is clear |
| Content | Showcase art | Blender as code | DONE: `tools/build_art.py` |
| Process | Release pipeline | CI/CD | tagged releases publish to itch.io from CI (butler) as well as Pages; changelog |
| Process | Agentic playtest | agentic manual testing | `deno task playtest <plan>` records a gameplay video locally (Godot Movie Maker) plus an event log and PNG snapshots; agent instructions; sample evidence |

## Phases (one agent each, in order)

0. **Board.** Port `core/board.gd` from `../d4-dev` (tile vocabulary, `Board.TILES`
   with `solid`, `Board.bordered`). The Session takes a Board, collides with
   `is_solid` instead of a bounds check, and never spawns food/pickups on solid
   cells. `app/main.gd` passes `board.tiles` to `Stage` instead of its own
   `_board()`. Today walls sit outside the 40x40 grid; switching to
   `Board.bordered(Vector2i(42, 42))` keeps the play area. Update tests.
1. **Language:** text levels with a broader tile vocabulary (at least lava = deadly,
   water = deadly or slowing, bridge = walkable over water; each with a Blender
   builder that looks good next to the existing kit), internal DSL, external DSL.
   Keep them distinct: levels are data; the internal DSL is GDScript calls; the
   external DSL is its own text language with a parser. A sensible split: levels
   define the map; the external DSL scripts events on a level (e.g. "at score 5:
   spawn lava ring", "every 30 ticks: ember at random"); the internal DSL builds
   powerup waves or level sequences in code. A level select or progression in game.
2. **Systems:** rival dragon (AI controller; the player's keyboard becomes one
   controller among others), replays (record, replay, golden test).
3. **Content:** procedural terrain as a level source alongside text levels.
4. **Process:** agentic playtest harness (a prototype exists in
   `/Users/adam/Desktop/CMPM 121-f26/research/2026-11-15-godot-blender-as-code/agentic-playtest/`;
   Movie Maker needs a window, so it flashes one briefly: acceptable, keep runs short),
   and a release pipeline: a GitHub Actions workflow publishing to itch.io with
   butler on tags, which stays inert without an `BUTLER_API_KEY` secret (no account
   exists yet; do not try to publish), plus `CHANGELOG.md`.

Each phase ends with: CI green, a contact-sheet screenshot of the new features,
DESIGN.md updated, a commit, and a short report (under 300 words) naming files
per item and anything left rough.
