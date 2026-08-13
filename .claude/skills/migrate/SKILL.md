---
name: migrate
description: Move an existing project off a dead or superseded dependency - ProfileService to ProfileStore, or removing Knit. Use when joining a project running the old stack, or when an audit finds a banned package. Contains verified API mappings for both migrations.
---

# /migrate

Recipes for getting an existing codebase onto this stack.

**Migrate only when asked.** Finding ProfileService in a codebase is not
permission to rewrite its data layer mid-task. Note it, finish what you were
doing, and raise it as its own piece of work.

**Data migrations are the dangerous kind.** ProfileService → ProfileStore
touches live player saves. Read the whole recipe before typing.

---

## A. ProfileService → ProfileStore

ProfileService is retired upstream; the author's replacement is ProfileStore.
Both are by loleris and the on-disk data format is compatible — this is an API
migration, not a data migration. Verify that claim against your own store
before trusting it in production.

Wally: `ProfileStore = "lm-loleris/profilestore@1.0.3"` under
`[server-dependencies]` (it is `realm = "server"`).

### API mapping

| ProfileService | ProfileStore |
|---|---|
| `ProfileService.GetProfileStore(name, template)` | `ProfileStore.New(name, template)` |
| `store:LoadProfileAsync(key, "ForceLoad")` | `store:StartSessionAsync(key, {})` |
| `store:LoadProfileAsync(key, "Steal")` | `store:StartSessionAsync(key, {Steal = true})` |
| `not_released_handler` returning `"Cancel"` | `{Cancel = function() ... end}` |
| `profile:ListenToRelease(fn)` | `profile.OnSessionEnd:Connect(fn)` |
| `profile:Release()` | `profile:EndSession()` |
| `profile:Reconcile()` | `profile:Reconcile()` (unchanged) |
| `profile:AddUserId(id)` | `profile:AddUserId(id)` (unchanged) |
| `profile:IsActive()` | `profile:IsActive()` (unchanged) |
| `profile.Data` | `profile.Data` (unchanged) |
| `profile.MetaData.ActiveSession` | `profile.Session` |
| `profile.MetaData.SessionLoadCount` | `profile.SessionLoadCount` |
| `profile.MetaData.ProfileCreateTime` | `profile.FirstSessionTime` |
| `profile:SetMetaTag(k, v)` / `:GetMetaTag(k)` | no equivalent — move the value into `profile.Data` |
| `store:ViewProfileAsync(key)` | `store:GetAsync(key)` |
| `store:WipeProfileAsync(key)` | `store:RemoveAsync(key)` |
| `store:ProfileVersionQuery(...)` | `store:VersionQuery(...)` |
| `store:GlobalUpdateProfileAsync(...)` | `store:MessageAsync(key, message)` + `profile:MessageHandler(fn)` |
| `ProfileService.IssueSignal` | `ProfileStore.OnError` |
| `ProfileService.CorruptionSignal` | `ProfileStore.OnOverwrite` |
| `ProfileService.CriticalStateSignal` | `ProfileStore.OnCriticalToggle` |
| `ProfileService.ServiceLocked` | `ProfileStore.IsClosing` |

### Procedure

1. `/verify` on the untouched tree. If it is already red, fix that first or
   you will not be able to attribute failures.
2. Add ProfileStore to `[server-dependencies]`, `wally install`. Leave
   ProfileService installed for now.
3. Rewrite the session lifecycle in one place — usually a single
   `PlayerData` module. Use `src/server/init.server.luau` here as the shape.
4. Work through the mapping table. Let the typechecker find the call sites:
   `/verify` after each group of edits.
5. `MetaTags` need real thought. There is no equivalent; each tag becomes a
   field in `profile.Data`, which means a `DataSchema` version bump and a
   migration step.
6. Remove ProfileService from `wally.toml`, `wally install`, `/verify`.
7. **Test against a copy of real data before shipping.** Use `store.Mock` in
   Studio. A migration that typechecks and corrupts saves is the worst
   possible outcome and no gate in this repo will catch it.

### Global updates

`GlobalUpdateProfileAsync` and `MessageAsync` are not the same primitive.
Global updates were a locked, hand-cleared queue; messages are delivered to
`profile:MessageHandler(fn)` and acknowledged by calling `processed()`. Any
in-flight global updates must be drained under the old API **before** the
switch — they are not carried over.

---

## B. Removing Knit

Knit is unmaintained. It bundles three separable things: a service/controller
lifecycle, a networking layer (`sleitnick/comm`), and a module loader. Replace
them independently — do not try to swap all three in one pass.

| Knit provides | Replace with |
|---|---|
| `KnitServer.CreateService` / `KnitClient.CreateController` | plain modules exporting `start()` |
| `Knit.Start()` ordering | explicit requires in `init.server.luau` / `init.client.luau` |
| `service.Client` remotes (Comm) | `net/schema.zap` + `/net` |
| `Knit.GetService(name)` | direct `require` |
| `Knit.OnStart():await()` | ordinary sequencing; `Promise` if genuinely async |

### Procedure

1. `/verify` on the untouched tree.
2. **Networking first** — it is the part with a real trust boundary. Inventory
   every `service.Client` method and every `RemoteSignal`, declare each in
   `net/schema.zap`, regenerate with `zap --no-warnings net/schema.zap`.
   Client→server payloads become validated by construction; that is the win.
3. **Then lifecycle.** Convert one service at a time into a module with an
   explicit `start()`. Call them in order from the entry point. Ordering that
   was implicit in `Knit.Start()` becomes visible — expect to discover a
   dependency the old code only satisfied by luck.
4. **Then the loader.** Replace `Knit.GetService("X")` with
   `require(...)`. The typechecker now sees through the call, which usually
   surfaces a handful of long-standing wrong-argument bugs.
5. Remove `knit` and `comm` from `wally.toml`, `wally install`, `/verify`.
6. Studio-test every converted service. Static analysis cannot prove that
   startup ordering is still correct, and ordering is exactly what you changed.

---

## Reporting

Say what moved, what is left, and what you could not verify without Studio.
A half-finished migration that is reported as complete is worse than one that
was never started.
