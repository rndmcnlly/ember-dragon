# D4 reference solution (instructor only)

Not for students. A worked example built from `../d4-dev`: the baseline plus every menu item.
See DESIGN.md. The original starter README follows.

---


A voxel dragon on a grid, snake rules: Godot and Blender, driven from text, with the same task
habits as D3. The dragon moves and turns; food, growth, and collisions are yours to add.

| You want to | Run | What happens |
| --- | --- | --- |
| Get the tools | `deno task setup` | Downloads pinned Godot 4.7.2 and only its web export template into `.tools/` |
| Make the art | `deno task art` | Runs `tools/build_art.py` with Blender as a Python library (`bpy`), writes `art/*.glb` |
| Make the art on an Intel Mac | `deno task art:lts` | Same script, Blender 4.5 LTS |
| Check this computer | `deno task doctor` | Tries every step and prints a report to paste into Canvas |
| See the kit in the game's lighting | `deno task kit` | Every piece in rows, plus the hero and the rival bending through turns on a board with every tile kind |
| Play it | `deno task dev` | Runs the game in a native window |
| Open the editor | `deno task edit` | The graphical editor is still there when you want it |
| Playtest with an agent | `deno task playtest playtests/ford-embers.replay` | Plays a plan through the game, records `video.avi`, a log, and snapshots (see PLAYTEST.md) |
| Check before commit | `deno task ci` | Format check, lint, import, tests, web export into `dist/` |
| See the web build | `deno task preview` | Serves `dist/` locally |

Push to `main` and `.github/workflows/deploy.yml` runs the same `deno task ci`
on GitHub and deploys `dist/` to Pages. The optional review bot
(`.github/workflows/review-bot.yml`, guided by `REVIEWBOT.md`) comments on each push
once it is set up; until then it shows a red X that says nothing about the code.

## Editor

Open this folder in VS Code and accept the recommended extensions
(`.vscode/extensions.json`):

- **godot-tools:** GDScript completion, hover docs, and go-to-definition. It starts a
  windowless Godot from `.tools/godot` (made by `deno task setup`), so no editor needs
  to be open. Format GDScript with `deno task fmt`, not this extension.
- **Python:** completion for `bpy` and `bmesh` in `tools/build_art.py`, from Blender 5.2
  stubs that `deno task setup` installs into `.tools/python-stubs`.
- **GLB Viewer:** click `art/dragon_kit.glb` to orbit the kit. `build_art.py` lays the
  pieces out in rows (the dragon, the rival, props, then tile kinds) just for viewers
  like this; the game uses only each piece's mesh, so the layout never affects play.
- **Deno:** for the TypeScript in `scripts/`.

`Cmd/Ctrl+Shift+B` runs `deno task ci`. The tasks list (`.vscode/tasks.json`) also
plays, shows the kit, rebuilds art and sound, and playtests the plan open in the editor.

## Releasing

Pages always shows `main`. A version tag also publishes to itch.io through
`.github/workflows/release.yml` (butler):

1. In `CHANGELOG.md`, rename `## Unreleased` to the version and date, e.g.
   `## 1.0.0 (2026-12-04)`, and start a new empty `## Unreleased` above it.
2. `deno task ci`, then commit.
3. `git tag v1.0.0 && git push origin main v1.0.0`.

The workflow checks that `CHANGELOG.md` has a section for the tag, runs
`deno task ci`, and pushes `dist/` to itch.io as that version. Until the repository
has a `BUTLER_API_KEY` secret (an itch.io API key) and an `ITCH_TARGET` variable
(`user/game:channel`, e.g. `rndmcnlly/ember-dragon:html5`), it skips with a notice
instead. On itch.io, set the project's kind to HTML and tick "This file will be
played in the browser" on the uploaded `html5` channel once.

## Layout

- `DESIGN.md`: the words the project uses and one section per menu item. `AGENTS.md`
  is a map for coding agents; `REVIEWBOT.md` guides the optional review bot.
- `project.godot`, `main.tscn`, `export_presets.cfg`: Godot's own config, plain text, editable by hand.
- `core/session.gd`: one run at one level: food, score, collisions, powerups, and the rival.
  No Nodes; tested headless.
- `core/campaign.gd`: the levels in order; each step makes a fresh `Session` for every try.
- `core/dragon.gd`: the dragon's body and steering (a turn queue). No Nodes; tested headless.
- `core/controllers/`: who steers a dragon: the keyboard, the rival's AI.
- `core/replay.gd`: a recorded session (level, seed, turns per tick) and its playback.
- `core/terrain.gd`: grows a map from a seed (river, rocks, lava), for the Wilds.
- `levels/`: maps (`*.txt`), event scripts (`*.rules`), and the campaign that orders
  them (`campaign.gd`); `levels/README.md` is the legend and the rules reference.
- `core/kit.gd`: which piece (head, straight, turn, tail) goes in each cell and how far to rotate it.
- `app/main.gd`: the engine adapter. Builds the stage in code, ticks the session, draws the
  dragons and the HUD. `app/stage.gd` loads the kit and draws the board;
  `app/kit_viewer.gd` is `deno task kit`.
- `tools/build_art.py`: Blender as code. Every piece is swept, beveled, and painted by a small
  builder function; edit, run `deno task art`, replay. `tools/build_sfx.py` does the same for sound.
- `playtests/`: plans for agentic playtests and the driver that plays them; evidence
  lands in `playtests/out/` (not committed). Agents start at `PLAYTEST.md`.
- `tests/`: `*_test.gd` files, run by `tests/run_tests.gd` (a tiny runner, no plugin).
- `scripts/godot.ts`: finds Godot, and fails the task when Godot prints script errors.

## Why `scripts/godot.ts` is strict

Godot exits with code 0 even when a script fails to parse, so a plain
`godot --headless ...` would let a broken commit pass CI. The wrapper watches
Godot's output for script errors and fails instead, and the test runner treats
an unloadable test file or zero tests run as failure.

## Requirements

Deno and uv. The first `deno task art` downloads Blender's `bpy` package
(a few hundred MB; minutes on slow networks), so run it once before you need it.
Set `GODOT=/path/to/godot` to use your own Godot 4.7.2 instead of `.tools/`.

| Platform | Godot tasks | `deno task art` |
| --- | --- | --- |
| Mac (Apple Silicon), Windows (x64 or ARM) | yes | yes |
| Mac (Intel) | yes | use `deno task art:lts` (Blender 5 dropped Intel Macs) |
| Linux x86_64, including x86 Chromebooks | yes | yes, after installing the libraries below |
| Linux ARM, including ARM Chromebooks | yes | no: Blender's Python package has no ARM Linux build |

On Linux (Debian, Ubuntu, Chromebook), install what minimal systems lack:

    sudo apt install libfontconfig1                       # quiets harmless Godot font errors
    sudo apt install libx11-6 libxrender1 libxfixes3 libxi6 libxkbcommon0 libsm6 libgl1   # for art

Run `deno task doctor` to try every step and print a report of what works on your computer.
