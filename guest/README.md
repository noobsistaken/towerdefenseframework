# Working inside someone else's Roblox project

The rest of this template assumes you own the repo. This folder is for when
you do not.

The default posture flips: **your tooling must be invisible to them.** Any
change of yours that alters their build, their CI, or their tree is a problem
you created, and you will be the one who has to explain it.

---

## Before touching anything

1. **Ask what is yours.** Which folders you own, which branch to work on, and
   who reviews. Get it in writing in the ticket or the chat, not inferred from
   the file layout.
2. **Read their conventions first.** If they use Roact and you prefer React,
   you use Roact. If they indent with spaces and you prefer tabs, you use
   spaces. Their codebase, their call.
3. **Find out whether they already use Rojo.** This changes the whole workflow
   — see "Sync" below.

---

## MCP: read-only, always

**Never point a write-capable MCP server at someone else's place.**

A write-capable MCP can modify or delete instances in a live place. On your
own project that is a recoverable mistake. On theirs it is data loss in a
place you do not own, possibly with players in it, and possibly with no
backup you can reach.

Read-only MCP is fine and genuinely useful for inspecting their tree. Confirm
the mode before you connect, not after.

---

## Config files: do not change their CI

Adding a root-level `.luaurc`, `selene.toml`, or `stylua.toml` to someone
else's repo will change what their CI checks for **every other contributor**.
A `stylua.toml` you add can reformat the entire codebase on someone else's
next commit and bury their diff.

Pick one:

**A. Scope config to your folder** (preferred, if they already lint)

Put `.luaurc` / `selene.toml` / `stylua.toml` inside *your* subtree only.
Both selene and StyLua resolve config from the nearest ancestor directory, so
your rules apply to your files and nothing else. Mention it in the PR.

**B. Keep config out of the repo entirely** (preferred, if they do not lint)

Run the checks locally via this template's hook and never commit the config.
Add nothing to their tree. You still get the safety net; they see only Luau.

Either way: **never** add a workflow to `.github/workflows/`, and never edit
one, without being asked.

---

## Sync

**If they already use Rojo:** use *their* project file. Do not add a second
one. Ask which one to serve.

**If they do not use Rojo:** consider Roblox's built-in **Script Sync**
(Studio → File → Script Sync) instead of introducing Rojo. It syncs script
text between Studio and disk without a project file, without a plugin they
have to install, and without changing their repo. It only handles scripts, not
instances — which for a guest contributor is usually exactly the right amount
of power.

**If you must use Rojo:** use `guest.project.json` here. It maps only your
subtree and sets `$ignoreUnknownInstances: true` at every level above your
folders, so Rojo will not delete instances of theirs that have no counterpart
on disk.

Replace `YourName` in that file with your actual folder name, and create those
folders in Studio by hand once before serving.

> **`$ignoreUnknownInstances` is the important part.** Without it, a broad
> mapping tells Rojo it owns that container, and anything in Studio that is
> not on disk gets removed on sync. That is how a guest deletes another
> developer's work while believing they are only syncing their own.

---

## Rules

**Work on a branch.** Never commit to their default branch. Branch from their
latest, keep it rebased, open a PR.

**Never restructure their tree.** No moving files into a layout you prefer, no
renaming their folders, no "while I was in there" reorganisation. If their
structure genuinely blocks the work, say so and ask.

**Never commit their `Packages/`.** Check `git status` before every commit. If
their `Packages/` is gitignored, it stays that way — the "commit `Packages/`"
rule from the main template is *our* convention, not a universal one.

**Never edit inside `Packages/`.** Same as always, and it matters more here:
you will not be around when it silently disappears on their next install.

**Never touch their data or networking layers without being asked.** A change
to their save schema or their remotes can break live players. This is the
category most likely to cause real damage.

**Keep the diff small and readable.** Assume the reviewer knows the codebase
better than you and has less patience than you would like. Unrelated
formatting churn in a guest PR is the fastest way to get it rejected.

---

## What still applies from the main template

- `/verify` before claiming anything works — adapted to whatever gates they
  actually have.
- Never leave unverified code at the end of a turn.
- Read the real API in their code instead of assuming it.
- Say what you verified and what you did not.

## What does not apply

- The package list. Use theirs.
- Schema-first networking via Zap. Use their networking layer.
- Committing `Packages/`. Follow their `.gitignore`.
- `ARCHITECTURE.md`. Do not add one to their repo uninvited.
