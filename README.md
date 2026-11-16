# D4 reference solution (instructor only)

Not for students. A worked example built from `../d4-dev`: baseline plus two menu items.
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
| Play it | `deno task dev` | Runs the game in a native window |
| Open the editor | `deno task edit` | The graphical editor is still there when you want it |
| Check before commit | `deno task ci` | Format check, lint, import, tests, web export into `dist/` |
| See the web build | `deno task preview` | Serves `dist/` locally |

Push to `main` and `.github/workflows/deploy.yml` runs the same `deno task ci`
on GitHub and deploys `dist/` to Pages.

## Layout

- `project.godot`, `main.tscn`, `export_presets.cfg`: Godot's own config, plain text, editable by hand.
- `core/dragon.gd`: the dragon's rules on the grid (movement, a turn queue). No Nodes; tested headless.
- `core/controllers/`: who steers a dragon: the keyboard, the rival's AI.
- `levels/`: maps (`*.txt`), event scripts (`*.rules`), and the campaign that orders
  them (`campaign.gd`); `levels/README.md` is the legend and the rules reference.
- `core/kit.gd`: which piece (head, straight, turn, tail) goes in each cell and how far to rotate it.
- `game/main.gd`: the engine adapter. Builds the stage in code, ticks the dragon, draws it with
  four shared meshes.
- `tools/build_art.py`: Blender as code. The dragon kit is drawn as ASCII voxel layers; edit, run
  `deno task art`, replay.
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
