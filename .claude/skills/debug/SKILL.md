---
name: debug
description: Reproduce and isolate a defect before attempting any fix. Use when something is broken, behaves unexpectedly, errors at runtime, or a test fails. Produces a diagnosis with evidence, not a speculative patch.
---

# /debug

Reproduce first. Diagnose second. Fix third. Skipping to the fix is how a
session spends an hour changing correct code.

## 1. Reproduce

Get a deterministic repro before changing anything.

- **What exactly happens?** The literal error text and stack, not a paraphrase.
- **Where?** Server, client, or Studio-only. Roblox behaves differently across
  all three, and a bug that only appears in one narrows the cause immediately.
- **When?** On join, on a specific action, after N minutes, only with 2+
  players. Session-dependent bugs are usually lifetime/cleanup bugs.
- **How often?** Every time, or intermittently. Intermittent almost always
  means a race, a yield across a state change, or a leaked connection firing
  after its owner is gone.

If you cannot reproduce it, say so and ask for the missing detail. Do not
"fix" a bug you have never seen.

## 2. Isolate

**Read the actual error location.** Roblox stack traces are accurate. Start
at the top frame and work down.

**Bisect the change, not the code**, when it worked before:

```bash
git log --oneline -20
git diff <last-known-good>..HEAD -- src/
```

**Narrow with evidence, not intuition.** Add a `print` that shows the value
you believe is wrong, and confirm it is actually wrong. Roughly half of
"obvious" diagnoses in a strict-typed codebase turn out to be one frame away
from where the reasoning said they were.

**Check the usual suspects, in this order:**

| Symptom | Look at first |
|---|---|
| `nil` where a value should be | a yield between check and use — the player may have left |
| Works in Studio, not live | DataStore access, `RunService:IsStudio()` branches, ProfileStore mock |
| Works for one player, breaks with two | shared mutable state that should be per-player |
| Fires more than once | a connection made inside a handler, never disconnected |
| Grows worse over a session | leaked connections/instances — should have been on a `Janitor` |
| Client sees stale data | replication never sent, or Charm atom written on the wrong realm |
| Payload rejected | Zap type constraint in `net/schema.zap` is tighter than the sender |

**Server vs client authority.** If the client shows one thing and the server
another, the server is right by definition. The bug is in replication or in
the client's copy — not in the server's value.

## 3. State the diagnosis

Before fixing, say plainly:

> **Cause:** `<file:line>` — `<what is actually wrong>`
> **Evidence:** `<the print output / the stack / the diff that proves it>`
> **Fix:** `<the smallest change that addresses the cause>`

If you cannot fill in *Evidence*, you have a hypothesis, not a diagnosis. Say
that, and say what would confirm it.

## 4. Fix

Smallest change that addresses the **cause**. Not the symptom, not a
defensive `if` that hides it.

Then:

```bash
/verify
```

and re-run the original reproduction. A gate passing is not the same as the
bug being gone — the repro is the only thing that proves that.

## 5. Prevent

If the bug was a class of thing rather than a typo, add a test in `tests/`.
Data-migration bugs and validation bugs always earn a test; they are the ones
that cost real player data.
