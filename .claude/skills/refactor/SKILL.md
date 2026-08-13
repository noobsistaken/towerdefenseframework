---
name: refactor
description: Restructure code without changing behaviour. Use for renames, extractions, moves, and deduplication. Gated on a passing /verify both before and after, because a refactor with no behavioural intent has no other definition of success.
---

# /refactor

Behaviour-preserving by definition. If behaviour changes, it is not a
refactor — it is a change, and it needs `/plan`.

## Hard gate: verify before you start

```bash
/verify
```

**If the gate is red, stop.** Do not refactor on top of a broken tree. You
will not be able to tell which failures you introduced and which were already
there, and neither will anyone reviewing it.

Commit first, so the refactor is a diff against a known-good state:

```bash
git status          # must be clean
```

## Rules

**One kind of change at a time.** Rename, or extract, or move — not all
three in one commit. A mixed refactor is unreviewable, and the whole reason
this is a separate skill is that nobody here is reading the diff line by line.

**Never change behaviour while restructuring.** No "while I'm here" fixes, no
tightening a check, no reordering calls that could yield. If you find a real
bug mid-refactor: note it, finish or abandon the refactor cleanly, then fix
the bug as its own change with its own commit.

**Let the typechecker do the work.** In strict mode, a rename that breaks a
call site is a build error, not a silent runtime failure. This is the one
place the safety net is genuinely comprehensive — use it by making the change
and reading what breaks.

**Watch what the typechecker cannot see:**

| Blind spot | Why |
|---|---|
| Rojo path mappings | `default.project.json` / `test.project.json` reference paths as strings |
| `wally.toml` `[place]` | must keep matching the Rojo tree or requires break at runtime only |
| Instance names in `WaitForChild("...")` | strings, unchecked |
| `net/schema.zap` message names | change the schema, not the generated output |
| String keys in DataStore data | renaming a data field is a **migration**, not a refactor |

That last one matters most: renaming a field in `DataSchema.luau` changes what
is written to live player data. That is never a refactor. It needs a version
bump and a migration step.

## After

```bash
/verify
```

Both gates must be green, and the diff must contain no behavioural change.
Re-read your own diff and check that claim specifically — a refactor that
"looks fine" and quietly reorders a yield is the exact failure this skill
exists to prevent.

Then commit with a message that says it was a refactor:

```bash
git commit -m "Extract purchase validation into ShopValidation module (no behaviour change)"
```

## Reporting

Say what moved, what the gate said before, and what it said after. If you
cannot claim "no behavioural change" honestly, say which behaviour changed and
why it was unavoidable.
