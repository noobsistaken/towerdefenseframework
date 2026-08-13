# SETUP-LOG

Build record for this template. Everything below was resolved against a live
source on **2026-08-13** and verified by running it, not by recall.

---

## 1. Resolved versions

### Toolchain (`rokit.toml`)

Each resolved from the GitHub Releases API, latest **stable** (drafts and
prereleases excluded), then installed and executed to confirm.

| Tool | Repo | Version | Released |
|---|---|---|---|
| rojo | `rojo-rbx/rojo` | 7.7.0 | 2026-07-02 |
| wally | `UpliftGames/wally` | 0.3.2 | 2023-06-05 |
| selene | `Kampfkarren/selene` | 0.31.0 | 2026-05-21 |
| stylua | `JohnnyMorganz/StyLua` | 2.5.2 | 2026-05-16 |
| luau-lsp | `JohnnyMorganz/luau-lsp` | 1.69.0 | 2026-07-18 |
| lune | `lune-org/lune` | 0.10.5 | 2026-07-02 |
| zap | `red-blox/zap` | 0.6.29 | 2026-06-23 |

`rokit` itself is 1.2.0 (2025-09-30) — latest stable at time of writing.
Wally 0.3.2 is genuinely the newest stable release; the gap since 2023 is
upstream's, not a resolution error.

### Dependencies (`wally.toml`)

Resolved by shallow-cloning `UpliftGames/wally-index` and reading each
package file directly. Versions are the latest entry with no prerelease
suffix. Realms were read from the index and determine which section each
package belongs in.

| Wally name | Version | Realm | Section |
|---|---|---|---|
| `evaera/promise` | 4.0.0 | shared | `[dependencies]` |
| `sleitnick/signal` | 2.0.3 | shared | `[dependencies]` |
| `howmanysmall/janitor` | 1.18.3 | shared | `[dependencies]` |
| `littensy/charm` | 0.11.0 | shared | `[dependencies]` |
| `jsdotlua/react` | 17.2.1 | shared | `[dependencies]` |
| `jsdotlua/react-roblox` | 17.2.1 | shared | `[dependencies]` |
| `lm-loleris/profilestore` | 1.0.3 | **server** | `[server-dependencies]` |
| `jsdotlua/jest` | 3.10.0 | shared | `[dev-dependencies]` |
| `jsdotlua/jest-globals` | 3.10.0 | shared | `[dev-dependencies]` |

`wally install` downloads **58** packages total (9 direct + 49 transitive).

---

## 2. Two package names did not resolve as given

Per the brief, flagging rather than substituting silently.

### `jsdotlua/jest-lua` does not exist

There is no `jest-lua` package under the `jsdotlua` scope. The project *is*
called Jest-Lua, but it publishes to Wally as **`jsdotlua/jest`**, alongside
~40 sibling packages (`jest-globals`, `jest-circus`, `jest-runner`, …).

**Used:** `jsdotlua/jest@3.10.0` + `jsdotlua/jest-globals@3.10.0`. Both are
required — `jest` provides `runCLI` for the runner, `jest-globals` provides
`describe`/`it`/`expect` for the specs. This is the same library the brief
asked for, under its real registry name.

### ProfileStore is not published under `loleris` or `MadStudioRoblox`

Neither scope exists in the registry. The index does contain ~120 packages
with "profile" in the name, almost all third-party forks and personal
re-uploads — exactly the trap the "do not invent packages" rule exists for.

The authentic package is **`lm-loleris/profilestore`**, confirmed by reading
`wally.toml` in `MadStudioRoblox/ProfileStore` itself:

```toml
name = "lm-loleris/profilestore"
version = "1.0.3"
realm = "server"
```

Name, version, description and realm all match the index entry exactly, so
this is the author's own publication under a differently-named scope. **No
fork or re-upload was used.**

---

## 3. Deviations from the brief

Each of these is a place where following the instruction literally would have
produced something broken. Flagging, per the brief's own rules.

### 3.1 `globIgnorePaths` does not exclude all of `Packages/`

**Asked:** add `globIgnorePaths` for `Packages/`.
**Did:** ignore `.git`, `.github`, `node_modules`, nested `default.project.json`
files, and `*.spec.luau` **inside** the package trees.

**Why:** `Packages/` is mapped into `ReplicatedStorage.Packages` in the Rojo
tree, and every `require` in the project resolves through it. Glob-ignoring
the whole directory removes it from the built place and breaks every require
at runtime with no build-time error. The intent — keep dependency noise out of
the place — is met by ignoring the artifacts that actually cause problems.

### 3.2 The hook exits 2 on real defects, not always 0

**Asked:** always `exit 0`, so a formatter crash cannot halt the session.
**Did:** exit 0 for *infrastructure* failure (tool missing, tool crashed,
unparseable payload). Exit 2 when a tool ran successfully and found a genuine
defect in project code.

**Why:** the stated reason — a crashing formatter must not halt the session —
is honoured exactly and was tested (`TEST E` below runs the hook with an empty
`PATH` and exits 0). But a PostToolUse hook that exits 0 on a real type error
discards the diagnostic: the agent never sees it and moves on. For a user who
cannot read Luau, a silent gate is worse than no gate, because it looks like
one. Broken tooling never blocks; broken code always does.

**Confirmed by Alexei, 2026-08-13: keep the `exit 2`.** This is a settled
decision, not an open deviation. Do not "restore" the literal `exit 0`
behaviour, and do not raise it again as a finding — the reason behind the
original instruction is fully satisfied by the infrastructure-vs-code split
above.

### 3.3 Three files exist that the brief's tree did not list

- **`.claude/hooks/post-edit-luau.sh`** — the hook logic. Embedding ~100 lines
  of shell inside a JSON string is unreadable and fragile to quote-escaping.
  `settings.json` invokes it via `$CLAUDE_PROJECT_DIR`.
- **`test.project.json`** — a second Rojo tree containing `DevPackages/` and
  `tests/`. `default.project.json` must stay free of both so dev dependencies
  and test code cannot ship. The test tree is a strict superset, so a single
  sourcemap generated from it resolves requires for `src` *and* `tests`.
- **`types/globalTypes.d.luau`** — vendored Roblox API definitions (831 KB).
  Required by `luau-lsp analyze --defs`; **without it acceptance test 7 fails**
  and the typechecker cannot catch a hallucinated Roblox API. Committed for
  the same reason as `Packages/`. Refresh from
  `https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau`.

Also generated: **`roblox.yml`** (740 KB), selene's Roblox standard library,
via `selene generate-roblox-std`. Committed so CI needs no network. Refresh
with `selene update-roblox-std`.

### 3.4 `.luaurc` uses `"lint": { "*": true }`

I first hand-enumerated lint names and got two wrong (`UnusedVariable`,
`UserDefinedTypeError` are not real Luau lints — luau-lsp rejected them). The
wildcard is self-maintaining across Luau versions and cannot drift. Only
`LocalShadow` is disabled, because it fires on idiomatic Roblox shadowing.

### 3.5 `sourcemap.json` in `.gitignore` is anchored

An unanchored `sourcemap.json` pattern also matched
`ServerPackages/_Index/lm-loleris_profilestore@1.0.3/profilestore/sourcemap.json`,
silently dropping a file out of a committed dependency tree. Caught by
`git status --ignored`. Every pattern in `.gitignore` is now root-anchored;
tracked-file count went 1269 → 1270.

---

## 4. Tests cannot run in CI, and CI does not claim they do

**This is the one real hole in the verification layer. It is not fixable from
the CLI.**

Jest-Lua executes inside a Roblox VM. Running it headlessly needs
`run-in-roblox`, which needs a Roblox Studio installation. GitHub-hosted
runners are Linux and have no Studio, so **no test in `tests/` executes in
CI**.

What CI actually proves: lint, format, types, schema freshness, and that both
places build. What it does not prove: that anything behaves correctly.

The workflow says this in a comment at the top, and the "Build test place"
step is named so it cannot be misread as a test run. `AGENTS.md` and
`/verify` both state that a green CI tick is not a passing test suite.

To close the gap properly you need a self-hosted Windows runner with Studio
installed, plus `run-in-roblox`. `tests/init.server.luau` already calls
`ProcessService:ExitAsync` with the right code when it is present, so it will
work under `run-in-roblox` without modification.

Until then: build the test place and run it in Studio.

```bash
rojo build test.project.json --output build/test.rbxl
```

---

## 5. Things found by reading source, not by assuming

Both are documented in `AGENTS.md` and `ARCHITECTURE.md` because an agent will
hit them repeatedly.

**Wally link files do not re-export Luau types.** Wally installs each package
behind `return require(script.Parent._Index[...])`, and Luau propagates
*values* through a re-export but not *types*. So `ProfileStore.Profile`,
`Janitor.Janitor` and `React.ReactNode` all fail with `Unknown type`, despite
all three libraries exporting them. Workaround used throughout:
`type T = typeof(Pkg.new())`.

**`ProfileStore:StartSessionAsync`'s published type is narrower than its
documented API.** The type says `params: { Steal: boolean? }`; the
documentation in the same file also specifies `Cancel`, which is genuinely
supported at runtime. `src/server/init.server.luau` casts around this with a
comment explaining precisely why, so the cast does not get copied as a general
pattern for silencing errors.

**Zap output paths are relative to the `.zap` file**, not the repo root. The
first run silently produced `net/net/generated/`. Fixed to
`opt server_output = "generated/server.luau"`.

**Zap deprecations were fixed rather than suppressed** — `Instance(Player)` →
`Instance.Player`, and `string` → `string.utf8`. The build runs with
`--no-warnings`, which promotes warnings to errors, so it stays clean.

---

## 6. Acceptance test results

All eight run against the finished template. Every result below is copied from
a real run.

| # | Test | Result |
|---|---|---|
| 1 | `rokit install`, all tools resolve | **PASS** |
| 2 | `wally install`, all deps resolve | **PASS** |
| 3 | `rojo build default.project.json` | **PASS** |
| 4 | `selene src` clean | **PASS** |
| 5 | `stylua --check .` clean | **PASS** |
| 6 | `luau-lsp analyze` clean | **PASS** |
| 7 | Typechecker catches a hallucination | **PASS** |
| 8 | `new-project.sh testproj` works | **PASS** |

**1.** All seven tools installed and reported their pinned versions:
`Rojo 7.7.0`, `wally 0.3.2`, `selene 0.31.0`, `stylua 2.5.2`, `luau-lsp
1.69.0`, `lune 0.10.5`, `zap cli 0.6.29`.

**2.** `Downloaded 58 packages!` — `Packages/`, `ServerPackages/` and
`DevPackages/` all populated. Required adding a `[place]` section to
`wally.toml`; without it wally refuses to link cross-realm dependencies. Those
paths must stay in sync with `default.project.json`.

**3.** `/tmp/test.rbxl`, 664,670 bytes.

**4.** `0 errors, 0 warnings, 0 parse errors`.

**5.** Clean. (Two files needed reformatting on first run; `stylua .` fixed
them and the check has been clean since.)

**6.** Exit 0 over `src` and `tests`.

**7. The important one.** A file calling a non-existent method was written to
`src/shared/`, and all three hallucination classes were caught:

```
BrokenSmokeTest.luau(5,1): TypeError: Key 'MakeItGlow' not found in external type 'Part'
BrokenSmokeTest.luau(6,1): TypeError: Key 'definitelyNotAFunction' not found in table 'DataSchema'
BrokenSmokeTest.luau(7,1): TypeError: Expected this to be 'number', but got 'string'
exit=1
```

Line 5 proves `--defs` is wired (fake Roblox API caught). Line 6 proves
`--sourcemap` require-resolution works (fake *project* API caught — this is the
one that catches an agent inventing a function in your own codebase). Line 7
proves strict mode is active. File deleted; analyze returns to exit 0.

**8.** `new-project.sh testproj` in a clean temp dir: copied the tree,
substituted tokens (`wally.toml` → `template/testproj`, both project files,
`ARCHITECTURE.md` heading), ran `rokit install` and `wally install`
(58 packages), and made an initial commit of 1,270 files. The generated
project then passed the entire gate independently — selene clean, stylua
clean, `luau-lsp analyze` exit 0, `zap` regeneration produced no diff, and
both places built (`game.rbxl` 664 KB, `test.rbxl` 1.2 MB).

### Hook tests (not in the brief's list, but it is the load-bearing file)

| | Case | Result |
|---|---|---|
| A | clean `.luau` file | exit 0, silent |
| B | non-Luau file | exit 0, skipped |
| C | file inside `Packages/` | exit 0, skipped |
| D | file with a hallucinated API + type error | **exit 2**, both diagnostics on stderr, and the file was reformatted in place (proving stylua ran first) |
| E | same broken file, empty `PATH` | **exit 0** — degrades gracefully with no tools installed |

---

## 7. Manual steps — I could not do these from the CLI

1. **Install the Rojo Studio plugin.**
   <https://create.roblox.com/store/asset/6415005344>, or `rojo plugin install`.
   Then `rojo serve` and connect from the Studio plugin.

2. **Verify Studio sync actually works.** Nothing in the acceptance tests
   above exercises live sync. `rojo build` producing a valid place is good
   evidence the tree is correct, but it is not the same test.

3. **Run the test suite at least once.** Build `test.project.json`, open it in
   Studio, press Run, and confirm the four `DataSchema` specs pass. Until
   that happens, the Jest wiring is verified only to the extent that it
   typechecks and the place builds.

4. **Enable DataStore access** (Game Settings → Security → Enable Studio
   Access to API Services) before testing ProfileStore, or use
   `ProfileStore.Mock`.

5. **Set `git config user.name` / `user.email`** if `new-project.sh` reports a
   failed initial commit.

---

## 8. Environment note

The host machine had no Roblox toolchain at all when this started — no rokit,
wally, rojo, selene, stylua, luau-lsp, lune, or zap. Rokit 1.2.0 was installed
to `~/.rokit/bin` to run the acceptance tests. Everything else came from
`rokit install` against the pinned manifest.
