# ARCHITECTURE — {{PROJECT_NAME}}

> **This is a template. Fill it in as the project takes shape.**
> `AGENTS.md` says *what to do*. This file says *why*, and it is where
> decisions get recorded so they stop being re-litigated every session.
>
> Placeholders look like `{{THIS}}`. An unfilled section is a real gap, not a
> formatting problem — if an agent asks a question this file should have
> answered, the answer belongs here afterwards.

---

## 1. What this game is

{{ One paragraph. What the player does, and the core loop. An agent that does
not know this will make locally-sensible, globally-wrong choices. }}

**Target platform(s):** {{ PC / mobile / console }}
**Expected concurrent players per server:** {{ N }}

---

## 2. Module layout

| Path | Datamodel location | Owns |
|---|---|---|
| `src/server/` | `ServerScriptService.Server` | authority, data sessions, validation |
| `src/client/` | `StarterPlayer.StarterPlayerScripts.Client` | input, UI, prediction |
| `src/shared/` | `ReplicatedStorage.Shared` | types, pure logic, constants |
| `net/generated/` | `ReplicatedStorage.Net` / `ServerScriptService.Net` | wire format |

**Rules that hold regardless of feature:**

- `src/shared/` must stay free of side effects at require time. It is loaded
  on both realms; anything that touches `Players` or DataStores at module
  scope will break one of them.
- The server never trusts a client value. Zap validates *shape*; it cannot
  validate *permission*. Ownership and affordability checks are ours.
- The client never holds authoritative state. It holds a replica.

**Module conventions for this project:**

{{ e.g. "one folder per feature under src/server/Features/, each exporting
`start()`" — write the actual convention once you have one. }}

---

## 3. Networking

**Schema:** [`net/schema.zap`](net/schema.zap) — the single source of truth.
**Generated:** `net/generated/{server,client}.luau` — committed, never edited.
**Regenerate:** `zap --no-warnings net/schema.zap`

Hand-written `RemoteEvent`s are banned. The reason is specific: a schema is a
small typed surface that an agent edits in one place and a human can review in
under a minute. Hand-rolled remotes are an unbounded surface whose failure
modes — a typo'd event name, an unvalidated payload from an exploiter — are
invisible at build time.

**Message inventory:**

| Message | Direction | Reliability | Purpose |
|---|---|---|---|
| `PlayerScoreChanged` | S→C | reliable | {{ replace }} |
| `RequestPurchase` | C→S | reliable | {{ replace }} |
| `ReportInput` | C→S | unreliable | {{ replace }} |
| `GetLeaderboard` | C→S→C | funct | {{ replace }} |

{{ Keep this table current. It is the fastest way for a reviewer to see the
entire trust boundary at once. }}

---

## 4. Data schema and versioning

**Schema:** [`src/shared/DataSchema.luau`](src/shared/DataSchema.luau)
**Store:** ProfileStore, store name `{{ PlayerData_v1 }}`
**Current version:** `{{ 1 }}`

Versioning contract:

1. Never change the meaning of an existing field. Add a new one.
2. Every shape change bumps `CURRENT_VERSION` **and** adds exactly one
   migration step for the previous version.
3. Migrations run oldest → newest, one version at a time.
4. A missing migration step is a hard error, never a guess. A wrong guess
   silently corrupts data belonging to real players, and there is no undo.

**Version history:**

| Version | Date | Change | Migration |
|---|---|---|---|
| 1 | {{ date }} | initial shape | — |

**DataStore-safety constraints** (ProfileStore will reject or silently drop
these): no Instances, no userdata (`Vector3`/`CFrame`/`Color3`), no functions,
no mixed tables, no sparse arrays. Serialise before storing.

---

## 5. Replication model

**Client state:** Charm atoms in `src/client/`. The client renders from atoms;
React reads them and stores no second copy.

{{ Decide and record: }}

- **What replicates:** {{ which state the server pushes, and when }}
- **How:** {{ full snapshot on join + deltas? per-message? }}
- **Rate:** {{ e.g. "score changes are event-driven; position is unreliable at
  20Hz" }}
- **What is client-authoritative:** {{ ideally nothing; if something is, say
  so explicitly and say why it is acceptable }}

---

## 6. Locked Dependencies

> **Read this before proposing any dependency change.**
>
> Everything here was decided once, deliberately. An agent that proposes a
> migration mid-task is burning the session on a settled question. If you
> think one of these is wrong, say so in one sentence and continue with the
> task — do not start the migration.

| Package | Version | Locked because |
|---|---|---|
| `evaera/promise` | 4.0.0 | async primitive; only Promise implementation allowed |
| `sleitnick/signal` | 2.0.3 | events |
| `howmanysmall/janitor` | 1.18.3 | cleanup |
| `lm-loleris/profilestore` | 1.0.3 | player data; server realm |
| `littensy/charm` | 0.11.0 | reactive client state |
| `jsdotlua/react` | 17.2.1 | UI |
| `jsdotlua/react-roblox` | 17.2.1 | UI renderer |
| `jsdotlua/jest` | 3.10.0 | tests (dev only) |
| `jsdotlua/jest-globals` | 3.10.0 | tests (dev only) |

**Banned, with reasons:**

| Package | Reason |
|---|---|
| Knit | unmaintained since ~2024 |
| ProfileService | retired upstream in favour of ProfileStore |
| BridgeNet2 | archived by the author |
| `sleitnick/comm` | Knit-era; superseded by Zap schema codegen |
| `howmanysmall/typed-promise` | would mean two Promise implementations |

**Toolchain** is pinned in [`rokit.toml`](rokit.toml). A tool version bump is a
change to the verification layer — treat it as a real change, not maintenance.

**Known upstream quirks** (add to this list as you hit them):

- Wally's re-export link files do not propagate Luau **type** exports. Write
  `type T = typeof(Pkg.new())` instead of `Pkg.T`.
- `ProfileStore:StartSessionAsync`'s published type omits the documented
  `Cancel` param. `src/match/server/init.server.luau` casts around it
  deliberately.

- **`Signal` is generic and the link file hides it.** `Signal.new<T...>():
  Signal<T...>`, but Wally's re-export means `Signal.Signal<Enemy>` does not
  resolve. The usual workaround, `type S = typeof(Signal.new())`, yields ONE
  instantiation — so several fields typed `S` all share the same `T`. Observed
  concretely: three signals on `EnemySimulation` collapsed together, Luau
  pinned `T` to `number` from the first `Fire`, and rejected `Fire(enemy)` on
  the other two. Use Signal freely for a single payload type; where a module
  needs several differently-typed events, explicit listener lists are the
  cheaper fix.

- **Zap refuses unbounded strings inside unreliable events.** An unreliable
  packet must stay under 998 bytes, so `string.utf8` needs an explicit bound
  like `string.utf8(..32)`. Arrays take `[..N]`.

- **Literal unions widen to `string` in four places.** This cost more time
  than anything else in Phase 2. `Types.MatchState` and
  `Types.TargetingMode` are unions of string literals, and each of these
  silently turns one into plain `string`, after which it no longer satisfies
  the enum Zap generated:

  | Widens | Fix |
  |---|---|
  | An unannotated `local x = f()` | annotate the **local**, not the function |
  | `a or "Literal"` | two separate `return`s instead |
  | **Iterating** `{ Union }` — both `for _, v in t` and `ipairs` | annotate the loop variable: `for _, v: Union in t do` |
  | `React.useState` / any generic `f<T>(atom: () -> T)` | accept `string` at the leaf and keep the union on the wire |

  The iteration entry was measured, not assumed — a probe file established
  that `t[1]` and `for i = 1, #t do t[i] end` both **preserve** the union
  while `for _, v in t` and `ipairs(t)` widen it, and that annotating the
  loop variable rescues it. Indexing is safe; iterating is not.

  The union is worth keeping where it does work — the schema, and atom
  declarations. At a leaf that only compares or formats, taking `string` with
  an explicit fallback is the honest trade; a cast purely to re-narrow is
  what the strict-mode rule forbids.

- **`React.useState(nil)` infers the state type as exactly `nil`,** and the
  setter then rejects every real value. Hold the optional inside a table
  (`useState({ value = nil } :: State)`).

- **A React dependency array containing `nil` has length 0,** so React reads
  it as an empty array and the effect never re-runs. Use a sentinel:
  `{ id or 0 }`.

- **Zap output is not byte-reproducible.** zap 0.6.29 emits `export type`
  aliases in a nondeterministic order — six runs against an unchanged
  `net/schema.zap` produced three distinct orderings. So *every* regeneration
  can show a diff in `net/generated/` even when nothing changed.

  This matters because those files are committed and are meant to be
  reviewable. Before concluding a schema change did something, check whether
  the diff is only reordered `export type` lines:

  ```bash
  git diff -U0 net/generated/ | grep -E '^[+-]' | grep -v '^[+-][+-]' | grep -v '^[+-]export type' 
  ```

  Empty output means the regeneration was cosmetic. Do **not** "fix" this by
  post-processing the generated files — sorting them by hand would break the
  rule that `net/generated/` is exactly what zap produced, and the ordering
  has no effect on behaviour.

---

## 7. Project-specific decisions

{{ Append here as decisions get made. Date them. One line each is fine —
the value is that nobody re-argues them next session. }}

| Date | Decision | Why |
|---|---|---|
| 2026-08-14 | Two places (lobby + match) over a single round-based place | Alexei's call. Cost accepted: `TeleportAsync` cannot run in Studio, so that seam ships unverified until both places are published. |
| 2026-08-14 | Enemies: numeric simulation **plus** server hitbox parts | Alexei's call. Kept honest by making the parts a one-way projection of the sim — position is never read back off a part. |
| 2026-08-14 | OOP: one concrete class per family + behaviour vtable in a field | Classical inheritance is not expressible in strict Luau without casts at every call site. See below. |
| 2026-08-14 | Instance-resident state replicates via Attributes, not Zap | Free, read-only to clients, and removes enemy position/HP/damage messages from the wire entirely. |
| 2026-08-14 | Maps are Luau config modules built at runtime | A `.rbxmx` is neither diffable nor agent-editable. |

### Why there is no `BaseTower` subclass hierarchy

This was tested against the compiler, not decided by taste. Findings:

1. `typeof(setmetatable({} :: A & B, Class))` **degrades**: the metatable is
   silently dropped and the result is just `A & B`, so no method resolves.
   Never pass an intersection as the fields argument.
2. Casting a metatable type into `Parent & { ... }` fails with *"the types
   are unrelated"*.
3. With **flat** field records the metatable *is* modelled correctly —
   `__index` chains resolve and inherited methods are found.
4. But a derived metatable type is **not** a subtype of the parent's
   (`Expected 'V3Base', got 'V3Derived'`), and not a subtype of a plain
   structural record either (`Expected 'V4Damageable', got 'V4Derived'`).
5. Leaving `self` unannotated so it generalises fails too:
   `Unknown type used in - operation`.

(4) is the blocker. Luau finds the inherited method and then rejects the
receiver, so `sniper:step()` against `BaseTower.step(self: BaseTower)` needs
a cast — not once at construction, but at **every inherited call site**,
which are the per-frame hot paths. That is the `:: any` this project's strict
mode rule exists to forbid.

**The pattern instead:** one concrete class per family (`BaseTower`,
`BaseEnemy`) holding all shared state and all shared implementations, plus a
`behavior` field carrying a table of optional override hooks. It keeps every
semantic property of single inheritance — shared state, shared base methods,
per-kind override, override-calls-super via `Base.methodBase(self)`, and
polymorphic dispatch over a mixed `{ Tower }` array — with zero casts. What it
gives up is a distinct static type per kind, which config-driven content never
needed: you write `local t: Tower`, never `local t: Sniper`.
