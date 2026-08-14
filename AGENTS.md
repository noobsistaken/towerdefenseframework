# AGENTS.md

Operating rules for AI agents working in this repo. Commands are exact — copy
them, do not improvise flags.

The human directing this project does not read Luau. He cannot catch a bad
line by eye. The verification layer below is the only thing between a
hallucinated API and shipped code. Treat a failing gate as a hard stop.

Why any of this is shaped the way it is: **[ARCHITECTURE.md](ARCHITECTURE.md)**.

---

## The golden rule

**Never end a turn with code that has not passed `/verify`.**

Not "it looks right". Not "the edit was small". Run the gate. If it fails,
fix it or revert it before you reply. Reporting "done" on unverified code is
the single most expensive thing you can do here.

---

## Commands

Setup (once per clone):

```bash
rokit install     # pinned toolchain: rojo wally selene stylua luau-lsp lune zap
wally install     # dependencies -> Packages/ ServerPackages/ DevPackages/
mkdir -p build    # rojo will NOT create the output directory itself
```

**Check that the toolchain is actually reachable before trusting any gate:**

```bash
for t in rojo wally selene stylua luau-lsp lune zap; do printf '%-10s ' "$t"; $t --version 2>&1 | head -1; done
```

> Rokit installs its shims to `~/.rokit/bin`. If that is not on `PATH` — or if
> a stale `~/.aftman/bin` sits ahead of it — every command in this file
> silently does nothing useful, and `.claude/hooks/post-edit-luau.sh` exits 0
> having verified **zero** files. A green gate that ran no checks is worse than
> a red one. If the loop above does not print seven versions, fix `PATH` first:
>
> ```bash
> export PATH="$HOME/.rokit/bin:$PATH"
> ```

Sourcemap — regenerate after any file add/move/rename, before typechecking:

```bash
rojo sourcemap test.project.json --output sourcemap.json
```

> Built from `test.project.json`, not `default.project.json`. The test tree is
> a superset (it also has `DevPackages/` and `tests/`), so one sourcemap
> resolves requires for everything.

Lint:

```bash
selene src tests
```

Format (write, then check):

```bash
stylua .
stylua --check .
```

Typecheck — the gate that catches hallucinated APIs:

```bash
luau-lsp analyze \
  --sourcemap=sourcemap.json \
  --defs=types/globalTypes.d.luau \
  --ignore="**/Packages/**" \
  --ignore="**/ServerPackages/**" \
  --ignore="**/DevPackages/**" \
  src tests
```

Networking codegen — after editing `net/schema.zap`:

```bash
zap --no-warnings net/schema.zap
```

Build:

```bash
rojo build default.project.json --output build/game.rbxl   # shipping place
rojo build test.project.json    --output build/test.rbxl   # test place
```

Tests:

```bash
rojo build test.project.json --output build/test.rbxl
# open build/test.rbxl in Studio -> Run -> read the Output window
```

> Jest-Lua runs inside a Roblox VM. There is **no** way to run it on a
> GitHub-hosted runner without a Roblox Studio install. CI therefore proves
> lint + format + types + build, and **not** runtime behaviour. Anything
> behavioural must be run in Studio. Do not claim tests passed in CI.

---

## Hooks

`.claude/hooks/post-edit-luau.sh` runs automatically after every
Edit/Write/MultiEdit on a `.luau`/`.lua` file: stylua → selene → sourcemap →
luau-lsp, on that one file.

- Missing or crashed tool → exits 0, never blocks.
- Real defect in your code → exits 2 and hands you the diagnostics. Fix them.

The hook is not a substitute for `/verify`. It checks one file; `/verify`
checks the tree.

---

## Packages

Installed and available:

| Package | Use |
|---|---|
| `evaera/promise` | async primitive |
| `sleitnick/signal` | events |
| `howmanysmall/janitor` | cleanup |
| `lm-loleris/profilestore` | player data (server realm) |
| `littensy/charm` | reactive client state |
| `jsdotlua/react` + `jsdotlua/react-roblox` | UI |
| `jsdotlua/jest` + `jsdotlua/jest-globals` | testing (dev only) |

**Never add, swap, or upgrade a dependency without being asked.** Record any
per-project constraint in ARCHITECTURE.md → "Locked Dependencies".

### Do not use these — they are dead or superseded

| Package | Why not |
|---|---|
| Knit | unmaintained since ~2024 |
| ProfileService | retired upstream in favour of ProfileStore |
| BridgeNet2 | archived by the author |
| `sleitnick/comm` | Knit-era; replaced by Zap schema codegen |
| `howmanysmall/typed-promise` | never run two Promise implementations |

If you find any of these in a codebase, that is a migration task
(`/migrate`), not a thing to build on.

---

## Rules

**Git from the first commit.** Commit before you start a unit of work, and
after it verifies. No large uncommitted piles.

**`Packages/`, `ServerPackages/`, `DevPackages/` are committed.** Deliberately
— builds stay deterministic and offline-resolvable.

**Never edit anything inside `Packages/`, `ServerPackages/`, or
`DevPackages/`.** A bug there is either ours (fix our call site) or upstream's
(pin around it and note it in ARCHITECTURE.md). An edit inside a vendored
package is silently destroyed by the next `wally install`.

**Networking goes through `net/schema.zap`.** Never hand-write a RemoteEvent,
RemoteFunction, or UnreliableRemoteEvent. Edit the schema, run `zap`, commit
the regenerated `net/generated/`. Never edit `net/generated/` by hand.

**Strict mode is on** (`.luaurc`). Do not add `--!nocheck`, do not silence a
type error with `:: any` to make a gate pass. If a cast is genuinely required,
it gets a comment saying why, like the ProfileStore one in
`src/server/init.server.luau`.

**Wally link files do not re-export types.** `SomePackage.SomeType` will not
resolve. Derive it from a value instead: `type T = typeof(Pkg.new())`.

**Data shape changes go through `src/shared/DataSchema.luau`** — bump
`CURRENT_VERSION` and add exactly one migration step. Never change the meaning
of a shipped field.

---

## Skills

| Skill | Use it for |
|---|---|
| `/verify` | full gate — run before claiming anything works |
| `/plan` | decompose before implementing |
| `/build` | implement one planned unit |
| `/net` | change the networking schema |
| `/debug` | reproduce and isolate a defect |
| `/refactor` | behaviour-preserving change |
| `/migrate` | ProfileService → ProfileStore, Knit removal |

---

## Layout

```
net/schema.zap        networking contract (source of truth)
net/generated/        zap output — committed, never hand-edited
src/match/server/     ServerScriptService.Server      (match place)
src/match/client/     StarterPlayer...Client          (match place)
src/lobby/            lobby place — added in Phase 4
src/shared/           ReplicatedStorage.Shared        (both places)
tests/                ServerScriptService.Tests (test place only)
types/                vendored Roblox API defs for luau-lsp
guest/                joining someone else's project — read guest/README.md
```
