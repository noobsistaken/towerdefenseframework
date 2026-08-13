---
name: plan
description: Decompose a feature into verifiable units before writing any code. Use when the user asks for something that touches more than one file, spans both realms, changes the data schema, or changes the network schema. Produces a written plan with explicit units, each independently verifiable.
---

# /plan

Decompose first. Write no implementation code during this skill.

A plan exists to make the work reviewable by someone who cannot read the
diff. If a unit cannot be described in one sentence and verified by one
command, it is not decomposed yet.

## Before planning

Read, in this order:

1. `ARCHITECTURE.md` — especially **Locked Dependencies** and **Data schema**.
2. `net/schema.zap` — if the feature crosses the client/server boundary.
3. The existing code you are about to touch. Actually read it; do not infer
   its shape from its filename.

State any assumption you are making that the repo does not already answer. If
an assumption is load-bearing and you cannot verify it by reading, ask one
precise question rather than guessing.

## The plan format

```markdown
## Goal
One sentence. What the player can do afterwards that they cannot do now.

## Constraints
- Data schema change? yes/no  (if yes: version bump + migration step)
- Network schema change? yes/no  (if yes: which messages)
- New dependency? Almost certainly no — see ARCHITECTURE.md "Locked Dependencies"

## Units
1. **<name>** — <one sentence>
   - Files: <exact paths>
   - Verified by: <exact command, or "Studio: <what to click, what to see>">
2. ...

## Risks
- <what could break that the gate cannot catch>
```

## Rules for units

**Each unit must be independently verifiable.** "Add the shop UI" is not a
unit. "Add `ShopPanel.luau` rendering a static list from `Types.ShopItem`,
verified by `/verify` plus Studio render" is.

**Order units so the tree is always green.** Schema before the code that uses
it. Types before implementations. Never leave a planned intermediate state
that does not typecheck.

**Say which units need Studio.** Static analysis cannot prove behaviour. Any
unit whose real verification is "run it and look" must say so, with what to
look at — otherwise it will get reported as done on the strength of a passing
typecheck, which proves nothing about whether it works.

**Call out schema changes loudly.** A data schema change is the one thing in
this project that can destroy real players' data. It gets its own unit, its
own migration step, and its own test in `tests/`.

## After the plan

Stop. Show the plan and wait. Do not start building because the plan seems
obviously right — the point of writing it down is that the user gets to
disagree before the code exists, not after.

Then implement one unit at a time with `/build`.
