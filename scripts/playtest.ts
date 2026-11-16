// deno task playtest <plan> [--dry]: play a plan through the real game and keep the
// evidence in playtests/out/<plan name>/. See PLAYTEST.md.
//
// 1. A dry run, headless: checks the plan and writes log.txt, path.txt, summary.txt.
//    A broken plan stops here, before any window opens.
// 2. Unless --dry: the same plan again in a window, recorded by Godot's Movie Maker
//    into video.avi, with PNG snapshots. The two logs must match (same seed, same session).
//
// Movie Maker needs a real window and GPU, so step 2 flashes a window for a few seconds
// and does not run on CI runners. Both steps go through scripts/godot.ts, which fails
// when Godot prints script errors.

const SCENE = "res://playtests/playtest.tscn";
const FPS = 30;
const TICK_SECONDS = 0.11; // app/main.gd's tick at normal speed; faster levels need fewer frames

const [planArg, ...flags] = Deno.args;
if (!planArg || !planArg.endsWith(".replay")) {
  console.error("usage: deno task playtest playtests/<name>.replay [--dry]");
  Deno.exit(2);
}
const dry = flags.includes("--dry");
const plan = await Deno.realPath(planArg).catch(() => {
  console.error(`playtest: no plan at ${planArg}`);
  Deno.exit(2);
});
const name = plan.replace(/^.*[/\\]/, "").replace(/\.replay$/, "");
const out = `playtests/out/${name}`;

// A fresh folder per run, so nothing in it is left over from an older one. The
// .gdignore keeps Godot from importing the snapshots as game assets.
await Deno.remove(out, { recursive: true }).catch(() => {});
await Deno.mkdir(out, { recursive: true });
await Deno.writeTextFile("playtests/out/.gdignore", "");
const outPath = await Deno.realPath(out);

async function godot(args: string[]): Promise<number> {
  const { code } = await new Deno.Command("deno", {
    args: ["run", "-A", "scripts/godot.ts", "--", ...args],
    stdout: "inherit",
    stderr: "inherit",
  }).spawn().status;
  return code;
}

const user = ["--", `--plan=${plan}`, `--out=${outPath}`];
console.log(`playtest: dry run of ${planArg} (headless, no window)`);
const quiet = dry ? [] : ["--quiet"]; // when recording, print only the final summary
if (await godot(["--headless", "--path", ".", SCENE, ...user, "--dry", ...quiet]) !== 0) {
  console.error("playtest: stopped before recording; fix the plan (see the lines above)");
  Deno.exit(1);
}
if (dry) {
  console.log(`\nplaytest: dry run done; evidence in ${out}/ (no video: --dry)`);
  Deno.exit(0);
}

const dryLog = await Deno.readTextFile(`${out}/log.txt`);
const ticks = Number(/^ticks:\s*(\d+)/m.exec(await Deno.readTextFile(plan))?.[1] ?? 0);
// A safety net only: the driver quits by itself after the last snapshot.
const frames = Math.ceil(ticks * TICK_SECONDS * FPS * 1.5) + 300;
const video = `${out}/video.avi`;
console.log(`\nplaytest: recording ${video} (a window opens for a few seconds)`);
const code = await godot([
  "--path", ".", "--resolution", "960x540",
  "--write-movie", `${outPath}/video.avi`, "--fixed-fps", String(FPS), "--quit-after", String(frames),
  SCENE, ...user, `--video=${video}`,
]);
if (code !== 0) {
  console.error("playtest: the recording failed (see the lines above)");
  Deno.exit(1);
}

// Same plan, same seed, same rules: the recorded session must be the dry run's session.
const same = (await Deno.readTextFile(`${out}/log.txt`)) === dryLog;
const size = (await Deno.stat(`${outPath}/video.avi`)).size / 1e6;
const checks = [
  `Check      recorded game matches the dry run: ${same ? "yes" : "NO (something random escaped the seed)"}`,
  `Check      video.avi is ${size.toFixed(1)} MB`,
];
await Deno.writeTextFile(`${out}/summary.txt`, checks.join("\n") + "\n", { append: true });
console.log(checks.join("\n"));
console.log(`\nplaytest: done; evidence in ${out}/ (start with summary.txt)`);
Deno.exit(same ? 0 : 1);
