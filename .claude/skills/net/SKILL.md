---
name: net
description: Change the networking contract by editing net/schema.zap and regenerating. Use for any client-server message - adding, changing, or removing one. Enforces schema-first networking; hand-written RemoteEvents are banned in this project.
---

# /net

All networking changes go through `net/schema.zap`. There are no exceptions.

**Never** create a `RemoteEvent`, `RemoteFunction`, `UnreliableRemoteEvent`,
`BindableEvent`-as-remote, or an `Instance.new("RemoteEvent")` anywhere in
`src/`. If you are reaching for one, the schema is the answer instead.

**Never** hand-edit `net/generated/`. It is overwritten on the next run.

## Why

The schema is the entire trust boundary in one reviewable file. Zap validates
every inbound payload against it, so a client physically cannot deliver a
shape the server did not declare. Hand-rolled remotes push that validation
into scattered handlers where a missing check looks exactly like a present
one, and the failure only shows up when someone exploits it.

## Procedure

1. **Read the current schema.** `net/schema.zap`.

2. **Edit it.** Choose deliberately:

   | Choice | When |
   |---|---|
   | `from: Client` | player → server. Assume the payload is hostile. |
   | `from: Server` | server → player(s). |
   | `type: Reliable` | must arrive; state changes, purchases, results. |
   | `type: Unreliable` | high frequency, latest-wins; input, positions. Drops are fine. |
   | `event` | fire-and-forget. |
   | `funct` | request/response. Prefer over RemoteFunction — typed both ends, cannot hang the caller. |

   Constrain types as tightly as the domain allows. `u8 (1..99)` is a free
   server-side validation that `number` is not. Use `string.utf8` for
   anything that will be stored, `string.binary` for packed data.

3. **Regenerate.**

   ```bash
   zap --no-warnings net/schema.zap
   ```

   `--no-warnings` turns warnings into errors. Zap's warnings are deprecation
   notices that become breakage later — fix them now, do not ship past them.
   Output paths in the schema are relative to `net/`, not the repo root.

4. **Bind the handlers.**

   - Server: `require(ServerScriptService.Net)` — `.On(cb)` for events,
     `.SetCallback(cb)` for `funct`, `.Fire/.FireAll/.FireExcept/.FireList/.FireSet`.
   - Client: `require(ReplicatedStorage.Net)` — `.Fire(value)`, `.On(cb)`,
     `.Call(value)` for `funct`.

   Zap validated the *shape*. It cannot validate *permission*. Ownership,
   affordability, cooldown, and range checks are yours and belong in the
   server handler.

5. **Verify, and commit the generated files.**

   ```bash
   /verify
   git add net/schema.zap net/generated/
   ```

   Generated output is committed. A schema change with uncommitted output
   means the next clone builds a different game than you tested.

6. **Update `ARCHITECTURE.md` § Networking** — the message inventory table.
   That table is how a reviewer sees the whole trust boundary at once, and it
   is worthless the moment it drifts.

## Removing a message

Delete it from the schema, regenerate, then fix every call site the
typechecker flags. Do not leave a dead message "in case" — an unused declared
message is still an open door.
