# auto_add_paths

Determine the set of relative subdirectories of a MATLAB package that a user
must `addpath` in order to "install" the package, and compare two methods
against each other.

## The three roles

There are **three** distinct actors in this project. Do not confuse them.

### 1. The MATLAB script — `auto_add_paths.m`

A pure-heuristic MATLAB function. Walks the directory tree, decides which
dirs to include based on filenames and folder names only. Never reads the
content of a `.m` file, never reads the README. Called as:

```matlab
auto_add_paths('/path/to/package', '/path/to/output.txt')
```

Output goes to `results/<pkg>.matlab.txt`. Fast, reproducible, coarse.

### 2. The strict AI agent — follows `auto_add_paths.prompt`

A sub-agent spawned (e.g. via the `Agent` tool with
`subagent_type=general-purpose`) and given **only** the contents of
`auto_add_paths.prompt` plus the package path. It is free to list dirs,
read the `README`, read any install/setup script, skim `.m` files, and
then emit a list of paths. This agent does **not** have access to this
`README.md`, does **not** know about the ground truth, and does **not**
iterate or reflect on prior packages. It runs the prompt, writes its
answer to `results/<pkg>.ai.txt`, and finishes.

Output goes to `results/<pkg>.ai.txt`. Slower, smarter, prompt-limited.

### 3. The orchestrator AI — `you`, reading this README

Drives the whole comparison. The orchestrator is a full Claude Code
session with broader context and access to this `README.md`. Its
responsibilities:

- **Establish ground truth.** Read the package thoroughly — README,
  install script, main entry point, any `addpath` calls in the code,
  the structure of subfolders — and write `results/<pkg>.truth.txt`
  by hand. The orchestrator is the arbiter. When the other two methods
  disagree, the orchestrator decides who is right, based on evidence
  from the package itself.
- **Run both methods** (MATLAB script via `matlab -batch`, strict AI
  agent via the `Agent` tool) and score them with `eval.sh`.
- **Iterate on `auto_add_paths.m` and `auto_add_paths.prompt`** to
  close accuracy gaps, re-running `run_all.sh` after every change to
  guard against regressions.

**Critically:** nothing in the ground-truth step is done by a human. The
user supplies packages; the orchestrator AI reads them and writes the
`.truth.txt` files. If a `.truth.txt` is wrong, that is the orchestrator's
fault and should be fixed.

## Files

- `auto_add_paths.m` — the MATLAB script (role 1).
- `auto_add_paths.prompt` — the prompt the strict AI agent (role 2) follows.
- `eval.sh` — `eval.sh truth.txt candidate.txt` → prints matched / missing /
  extra / precision / recall / F1 for one package.
- `run_all.sh` — runs the MATLAB script across every package with a
  `results/*.truth.txt` and prints a summary table comparing `matlab` vs
  `ai` for each one.
- `packages/` — cloned test packages (git-cloned, not committed).
- `results/<pkg>.truth.txt` — ground truth written by the orchestrator.
- `results/<pkg>.matlab.txt` — output of the MATLAB script.
- `results/<pkg>.ai.txt` — output of the strict AI agent.

## Iteration loop (what the orchestrator does)

1. **Pick a package.** The user will usually name one (often by FEX URL).
   - If the submission publishes to GitHub, `git clone --depth 1` into
     `packages/<pkg>/`.
   - Otherwise, download the zip straight from File Exchange by
     resolving the redirect that the FEX landing page emits when you
     append `?download=true`:
     ```
     curl -sIL "<fex-url>?download=true" | grep -i '^location:' | tail -1
     ```
     That redirect target has the form
     `https://www.mathworks.com/matlabcentral/mlc-downloads/downloads/<uuid>/<uuid>/packages/zip/<pkgname><version>.zip?src=&license=`.
     Strip the `?src=&license=` query string, download with `curl -sL`,
     and `unzip` into `packages/<pkg>/`. Two gotchas:
     * Do **not** send `User-Agent: Mozilla/...` — Akamai returns 403
       for spoofed browser UAs. Default `curl/x.y` works.
     * The versioned `.../submissions/<id>/versions/<n>/download/zip`
       endpoint exists but only goes up to a fixed old version and does
       not track the current FEX release. Always use the redirect-
       based URL above for the latest.
2. **Establish ground truth.** Read the `README`, any install script, the
   main entry point, and enough of the structure to know what actually
   needs to be on the path. Write `results/<pkg>.truth.txt`. One relative
   path per line, `.` for package root, forward slashes.
3. **Run both methods.**
   - `matlab -batch "addpath(pwd); auto_add_paths('packages/<pkg>','results/<pkg>.matlab.txt')"`
   - Spawn a sub-agent with `auto_add_paths.prompt` and have it write
     `results/<pkg>.ai.txt`. The sub-agent must not be told about the
     truth file or given any hints beyond the prompt and the package
     path.
4. **Score.** `./eval.sh results/<pkg>.truth.txt results/<pkg>.{matlab,ai}.txt`.
5. **Diagnose failures.**
   - MATLAB script missed / over-included a directory → can you describe
     the fix as a **structural signal** (dir name, filename pattern,
     special-folder presence)? If yes, patch `auto_add_paths.m`. If no
     (the signal is in the source code content), document it as a known
     limitation and move on.
   - Strict AI agent missed / over-included → update the relevant rule
     in `auto_add_paths.prompt`. Prefer adding a clarifying rule over
     rewriting; the prompt is the closest thing to a spec for what
     "install paths" means.
6. **Regression-check.** Run `./run_all.sh` (re-runs the MATLAB script
   against every known truth file). Every change must be improvement or
   neutral on every package.
7. **Repeat** with a new package.

## Script's heuristic rules (as of current version)

Include a directory if either:
- It directly contains `.m` or `.mex*` files whose names don't look like
  build/install scripts.
- It contains a MATLAB special subfolder (`@Class`, `+namespace`, or
  `private`) whose name is a valid MATLAB identifier.

Exclude a directory if any of:
- Its name matches the hard-coded skip list (`test`, `tests`, `demo`,
  `demos`, `example`, `examples`, `tutorial`, `doc`, `docs`, `html`,
  `build`, `buildutils`, `bin`, `obj`, `dist`, `target`, `node_modules`,
  `__pycache__`, `paper`, `dev`, `sandbox`, `scratch`, `.git`, `.github`,
  `.svn`, `.hg`, `.circleci`, `.vscode`, `.idea`, …).
- Its name starts with a skip prefix (`example*`, `demo*`, `tutorial*`,
  `benchmark*`, `sandbox*`).
- It is an OS-arch prebuilt-binary directory (e.g. `glnxa64`, `maci64`,
  `win64`, `darwin-x86_64`, `gnu-linux-x86_64`, `mingw32-x86_64`, …).
- It is a MATLAB special folder (`@Class`, `+namespace`, `private`) —
  these are auto-resolved from the parent.
- All of its `.m` files look like build / install / compile scripts
  (`buildfile.m`, `createMLTBX.m`, `install.m`, `setup.m`, `*_dev.m`,
  `compile*.m`, `mex_compile*.m`, `make_*.m`, …) and it has no special
  subfolders.

## Known structural-walk limitations

These are cases where the MATLAB script is expected to lose to the AI
agent, because the correct answer lives in source-code content or prose
that the script refuses to read.

- **Data folders loaded by bare filename.** A folder of `.png`/`.mat`/`.fig`
  resources that runtime code loads by bare filename (no path) must be on
  the MATLAB path but has no structural signal. Seen in PIVlab (`images/`).
- **`addpath(genpath(...))`-style installs.** Some packages genpath-add a
  whole subtree. The script emits every leaf as its own entry rather than
  the one genpath root. Functionally equivalent but the eval penalizes it.
  Seen in PIVlab (`OptimizationSolvers/`).
- **Demo-support utility libraries.** A subdir of real utility `.m`
  functions used only by demos, where the demo itself `addpath`s them at
  runtime, should be excluded. The script includes them because they have
  real `.m` files. Seen in inpoly (`mesh-file/`).
- **Documentation folders with example `.m` files.** A folder whose name
  doesn't match the skip list (e.g. `layoutdoc`) but whose `.m` files are
  all example scripts backing `.md` doc pages. Toolbox authors often add
  such folders to `ToolboxMatlabPath` so that `>> edit dockExample` works
  from the help browser, but a user *installing* the package doesn't need
  them on the path. The script includes them because they have real `.m`
  files and no skip-list name match. Seen in GUI-Layout-Toolbox
  (`tbx/layoutdoc/`).

## Current scoreboard

Run `./run_all.sh` for live numbers. As of the last update:

```
chebfun            matlab 1.000  ai 1.000
ezc3d              matlab 1.000  ai 1.000
gramm              matlab 1.000  ai 1.000
GUI-Layout-Toolbox matlab 0.667  ai 1.000
inpoly             matlab 0.667  ai 1.000
jsonlab            matlab 1.000  ai 1.000
Mathworks_QLabs    matlab 1.000  ai 1.000
matlab2tikz        matlab 1.000  ai 1.000
PIVlab             matlab 0.533  ai 1.000
readbkc            matlab 1.000  ai 1.000
ReferenceFrame3d   matlab 1.000  ai 1.000
StreamingFaceDetection matlab 1.000  ai 1.000
YALMIP             matlab 1.000  ai 1.000
zmat               matlab 1.000  ai 1.000
```

14 packages. Strict AI: 14/14 perfect. MATLAB script: 11/14 perfect,
3 partial (all due to the known limitations above).
