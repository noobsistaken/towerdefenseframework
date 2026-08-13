---
name: build
description: Implement exactly one planned unit of work and verify it. Use after /plan has produced units, or for a change small enough that its scope is already unambiguous. Ends with a passing gate and a commit.
---

# /build

Implement **one** unit. Not the unit plus the obvious next one.

## Before

- Know which unit. If there is no plan and the change touches more than one
  file or crosses a realm, run `/plan` first.
- `git status` should be clean. Build on top of a known-good tree so that when
  the gate fails you know which change caused it.

## While building

**Read before you write.** Open the files you are about to change and the
modules you are about to call. In a strict-mode project the typechecker will
catch a wrong API eventually — reading catches it now, without a round trip.

**Check the real API rather than recalling it.** Every dependency's source is
in `Packages/` / `ServerPackages/`. Reading `ProfileStore.luau` takes ten
seconds and is the difference between working code and a plausible-looking
call that does not exist.

**Respect the boundaries:**

- Networking → `/net`. Never a hand-written remote.
- Data shape → `src/shared/DataSchema.luau`, version bump + migration step.
- New dependency → almost certainly no. See ARCHITECTURE.md "Locked Dependencies".
- Never edit inside `Packages/`, `ServerPackages/`, `DevPackages/`, or
  `net/generated/`.

**Write it the way the surrounding code is written.** Match the existing
comment density, naming, and idiom. A file that reads as though a different
author wrote each half is harder for a reviewer to trust.

**Keep it the smallest correct change.** Do not refactor adjacent code, do not
add abstraction for a second caller that does not exist yet, do not "improve"
something you were not asked about. If you spot a genuine problem outside the
unit, note it in one sentence at the end — do not fix it here.

## Types

Strict mode is on. This is a feature, not an obstacle.

- Shared shapes go in `src/shared/Types.luau` so both realms agree.
- `SomePackage.SomeType` will not resolve — Wally link files do not re-export
  types. Use `type T = typeof(Pkg.new())`.
- Never reach for `:: any` to make an error go away. A cast is acceptable only
  when you have read the source, confirmed the annotation is wrong, and
  written a comment saying so.

## Cleanup

Anything with a lifetime gets a `Janitor`. Connections, instances, Charm
subscriptions, Zap listeners. A leaked connection in a player-scoped handler
is a memory leak that grows with session count and will not show up in any
gate here.

## After

```bash
/verify
```

Then commit — one unit, one commit, message describing behaviour rather than
mechanics:

```bash
git add -A
git commit -m "Add shop purchase validation"
```

Report what you built and the actual gate output. If the unit needs Studio to
be genuinely verified, say so explicitly rather than letting a green
typecheck imply it works.
