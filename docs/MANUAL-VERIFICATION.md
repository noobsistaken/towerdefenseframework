# Manual verification

Everything in this file is here because **static analysis and Jest cannot
reach it**. If a step below could be automated, it would be a test instead.

Run through this after any change to `src/lobby/`, `TeleportGate`,
`ReturnGate`, `ArrivalGate`, or `Config/Places.luau`.

---

## Why this exists

`TeleportService` does not function in Roblox Studio. `TeleportAsync` raises
there every time, whatever the arguments. So the lobby → match → lobby loop —
the thing that makes this a two-place game rather than one place — is
**unverifiable by the gate**, and no amount of green CI says otherwise.

That cost was accepted deliberately when two places were chosen over a single
round-based place. It is contained as far as it can be:

| Concern | Where it lives | Verified by |
|---|---|---|
| Is the payload well-formed? | `ArrivalGate.parse` | `tests/ArrivalGate.spec.luau` |
| Is a forged payload safe? | `ArrivalGate.parse` | same — 16 malformed shapes |
| Are the place ids set? | `TeleportGate.preflight` | ordinary code, no teleport |
| Is anyone left to send? | `TeleportGate.preflight` | ordinary code, no teleport |
| Does the vote resolve right? | `Poll` | `tests/Poll.spec.luau` |
| **Does the teleport happen?** | `TeleportGate.send` | **this document only** |
| **Does the return happen?** | `ReturnGate.send` | **this document only** |

Two function calls. Everything else around them is testable and tested.

---

## One-time setup

1. **Create one experience with two places.** They must be in the *same*
   experience. Reserved-server teleports across experiences are a different
   API with different permissions, and this code does not use it.

   In Studio: `File → Publish to Roblox As...` for the match place, then in
   the Asset Manager add a second place for the lobby.

2. **Record both place ids.** Asset Manager → Places → right-click → *Copy ID*.

3. **Write them into [`src/shared/Config/Places.luau`](../src/shared/Config/Places.luau):**

   ```luau
   Places.LOBBY_PLACE_ID = 0  -- <- the lobby place id
   Places.MATCH_PLACE_ID = 0  -- <- the match place id
   ```

   Until both are non-zero, `Places.isConfigured()` is false and
   `TeleportGate.preflight` refuses to attempt anything. That refusal is
   deliberate: `TeleportAsync` to place id `0` fails with an error that reads
   like a Roblox outage rather than a missing constant, and that
   misdiagnosis costs hours.

4. **Rebuild and upload both places.**

   ```bash
   rojo build lobby.project.json --output build/lobby.rbxl
   ```

   ```bash
   rojo build default.project.json --output build/game.rbxl
   ```

   Open each in Studio and publish it to the matching place. The lobby
   `.rbxl` goes to the lobby place id, the match `.rbxl` to the match place
   id — swapping them produces a lobby that teleports into a lobby.

5. **Studio Settings → Security → Enable Studio Access to API Services.**
   ProfileStore needs it, so rewards will not persist without it.

---

## The procedure

Run this **in a published server**, not in Studio. `Play` in Studio exercises
the simulated path, which is a different code branch by design.

### 1. Lobby loads

Join the lobby place from the Roblox client.

- [ ] Map row shows **Crossroads, Switchback, Fork**
- [ ] Difficulty row shows **Casual, Normal, Nightmare**
- [ ] Header counts down from 30 and reads `N in lobby · 0 ready`
- [ ] Three plinths stand in the world, labelled with the map names

### 2. Voting

- [ ] Clicking a map highlights it and its vote count goes to 1
- [ ] The winning option carries a green outline
- [ ] Clicking a second map moves your vote — the first drops back to 0
- [ ] With a second player, both votes appear and the tally agrees on both
      screens

### 3. Ready-up

- [ ] Pressing **READY UP** turns the button green and the header count rises
- [ ] With everyone ready, the countdown collapses to 5 seconds
- [ ] Un-readying before it fires restores the original countdown

### 4. The teleport — the unverifiable step

Let the countdown reach zero.

- [ ] Every player is moved to the match place
- [ ] The match loads **the map that won the vote**, not Crossroads-by-default
- [ ] The difficulty that won is in effect — check starting cash: Casual 750,
      Normal 550, Nightmare 400
- [ ] Everyone lands in the **same** server, not one server each

> **If they each land alone**, `ShouldReserveServer` is not taking effect and
> each player reserved their own server. Check that `TeleportGate.send`
> passes the whole player list in one call rather than looping.

> **If the map is always Crossroads**, the payload is not surviving.
> `ArrivalGate.parse` is tested, so suspect the send side: confirm
> `SetTeleportData` is called before `TeleportAsync`, not after.

### 5. Return to lobby

Lose the match deliberately — build nothing and let the base fall.

- [ ] `DEFEATED` shows with waves cleared and coins/XP awarded
- [ ] After the results seconds, everyone is returned to the lobby place
- [ ] The lobby is in `Gathering` and voting has reset

### 6. Rewards persisted

- [ ] Rejoin. Coins and level are what the results screen said.
- [ ] Play a second match. Coins accumulate rather than resetting.

> **If rewards are always zero**, check Studio API access (setup step 5), and
> that the player was still in the server when the match ended —
> `awardRewards` deliberately skips a player whose profile has been released,
> because writing to a released profile corrupts the next session.

---

## Testing the lobby without publishing

For lobby work that does not involve the teleport itself:

1. Set `Places.STUDIO_ROLE = "Lobby"` in `Config/Places.luau`
2. Rebuild the test place and press **Play**

The lobby runs fully — voting, ready-up, countdown, tally. At launch,
`TeleportGate` prints the payload it *would* have sent:

```
[TeleportGate] Studio: would teleport 1 player(s) [You] to place 0 with mapId="Fork" difficultyId="Normal"
```

Then the lobby returns to `Gathering` after six seconds so it stays usable.

**That line is the closest Studio can get to verifying the teleport.** It
proves the vote resolved and the payload was assembled correctly. It proves
nothing about whether `TeleportAsync` would accept it.

Set `STUDIO_ROLE` back to `"Match"` when you are done, or the test place will
stop booting the game.

---

## UI motion

Not part of the teleport loop, and listed here for the same reason it is: no
gate in this repo can see it. selene, stylua and luau-lsp prove the tween
compiles. They cannot prove it reads as motion rather than as a glitch.

Select one of your own towers below max level, in the match place.

1. **The preview is hidden until hovered.** Selecting a tower shows the main
   panel only. The NEXT / LEVEL n panel above it should be invisible.
2. **Hover the UPGRADE button.** The preview fades in over ~0.16s and a thin
   off-white stroke fades onto the button. Moving off fades both back.
3. **Nothing moves.** The panel holds its layout slot whether shown or hidden,
   so the UPGRADE button must not shift under the cursor. If it does, the
   reveal will flicker on and off - that is the failure to watch for.
4. **Whip the cursor on and off the button.** The fade should reverse from
   wherever it had reached, never snap to fully open first.
5. **Select a different tower while hovering.** The preview must be hidden on
   the new tower, not still showing from the old one.
6. **Upgrade to max level while hovering.** The preview and the button both
   disappear; nothing should error in Output.

**Touch and gamepad have no hover.** There the preview stays visible at all
times instead, so the information is never unreachable - but that means the
panel behaves differently per input device, which is a deliberate trade and
worth eyeballing on a phone if this ever ships to one.
