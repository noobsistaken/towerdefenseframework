---
name: verify
description: Run the full verification gate - selene, stylua --check, luau-lsp analyze, and tests. Use before claiming any code works, before committing, and after any edit the PostToolUse hook did not cover. This is the gate that stands in for a human who cannot read Luau, so run it rather than reasoning about whether it would pass.
---

# /verify

The full gate. The per-file hook checks one file; this checks the tree.

**Run this before you say anything works.** Not because it is procedure —
because the person reading your reply cannot check your claim by reading the
code, and a passing gate is the only evidence that means anything.

## Run it

```bash
set -e

# 1. Sourcemap first. Everything downstream resolves requires through it, and
#    a stale sourcemap produces confident, wrong "module not found" errors.
rojo sourcemap test.project.json --output sourcemap.json

# 2. Lint
selene src tests

# 3. Format (check only - never rewrite files inside a verification run)
stylua --check .

# 4. Typecheck. This is the one that catches hallucinated APIs.
luau-lsp analyze \
  --sourcemap=sourcemap.json \
  --defs=types/globalTypes.d.luau \
  --ignore="**/Packages/**" \
  --ignore="**/ServerPackages/**" \
  --ignore="**/DevPackages/**" \
  src tests

# 5. Both places must build
rojo build default.project.json --output build/game.rbxl
rojo build test.project.json    --output build/test.rbxl
```

If `net/schema.zap` changed, regenerate and confirm the output is committed:

```bash
zap --no-warnings net/schema.zap
git diff --exit-code net/generated/   # non-empty diff = you forgot to commit
```

## Reporting

State what ran and what it said. Concretely:

> `selene src tests` — 0 errors, 0 warnings.
> `stylua --check .` — clean.
> `luau-lsp analyze` — clean.
> `rojo build` — both places built.

Do **not** write "verified" or "all checks pass" without the actual results
next to it. If you skipped a step, say which one and why.

## When something fails

1. **Read the error.** luau-lsp gives you file, line, and the exact key or
   type. It is almost always literally correct.
2. **Fix the code, not the gate.** Do not add `--!nocheck`, do not cast to
   `any`, do not add a selene `allow` to make a message disappear. If a
   suppression is genuinely correct it needs a comment explaining why, and it
   goes in the narrowest possible scope.
3. **Re-run the whole gate**, not just the step that failed. Fixes cause new
   failures elsewhere often enough that partial re-runs are a false pass.

## Known-good failure modes

| Symptom | Cause | Fix |
|---|---|---|
| `Unknown type 'Pkg.Thing'` | Wally link files do not re-export types | `type Thing = typeof(Pkg.new())` |
| `Unknown require` after adding a file | stale sourcemap | re-run step 1 |
| `Key 'X' not found` on a Roblox class | the API does not exist | you hallucinated it — check the real API |
| stylua rewrites on every run | you edited without the hook | run `stylua .` once, commit |

## Tests

`selene`/`stylua`/`luau-lsp` do not run any code. They cannot tell you the
game works.

```bash
rojo build test.project.json --output build/test.rbxl
# open build/test.rbxl in Studio -> Run -> read Output
```

Jest-Lua needs a Roblox VM, so it does not run on a GitHub-hosted runner and
CI does not execute it. **Never report tests as passing unless you or the user
actually ran them in Studio.** "CI is green" means types and build are green;
it says nothing about behaviour.
