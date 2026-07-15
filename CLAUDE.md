# PROJECT: SUB ROSA — POWERED RAGDOLL BODY

You are the primary programmer on a physically-simulated character system for a
Sub Rosa–inspired multiplayer game on Roblox.

**This repo builds ONE THING: the body.** Nothing else.

---

## ⛔ STOP — READ `docs/00_ENGINE_FACTS.md` BEFORE WRITING ANY CODE

**Your training data is out of date for this project.** The APIs this project depends
on shipped between January and July 2026. If you write character code from memory,
you will write it wrong.

Specifically, you will be tempted to use `Motor6D`, `Humanoid.WalkSpeed`,
`BallSocketConstraint`-swap ragdolls, and client-authoritative movement.

**All four are wrong here. All four are deprecated, superseded, or forbidden.**

Read `docs/00_ENGINE_FACTS.md`. It is not optional context. It is the spec.

---

## THE SCOPE FENCE

We are building a character that is **fully physically simulated** — every joint is a
powered constraint that *strives* toward an animated pose and can fail to reach it.

### ✅ IN SCOPE
- Powered joints (`AnimationConstraint`, `IsKinematic = false`)
- The muscle system (per-joint strength, and everything that modulates it)
- Balance & locomotion (**pelvis-driven forces** — `Shared/PelvisDrive.luau`,
  the Gate 2 pivot; CCL retained as input conduit + legacy A/B toggle)
- Collapse & emergent recovery (the state machine)
- Trauma (limb damage, bleed) expressed as muscle failure
- Two independent IK arms
- Procedural animation layering
- Server-authoritative replication of all of the above

### ❌ OUT OF SCOPE — DO NOT BUILD THESE. DO NOT BUILD *TOWARD* THESE.
- Items, inventory, the economy
- Weapons (a raycast that applies limb damage is a **test harness**, not a weapon system)
- The map (a test room is a test room)
- Vehicles
- Voice, phones, radios
- Rounds, corporations, missions
- Menus, HUD, any non-debug UI
- Data persistence
- Anything described as a "framework", "backbone", "foundation for later", or "extensible base"

**If you catch yourself writing an abstraction because "we'll need it later" — stop.**
Later is not this repo. Premature generality here costs us the thing that actually
matters, which is getting a body to stand up without exploding.

Write the simplest thing that makes the current phase's gate pass.

---

## THE ARCHITECTURE, IN ONE PICTURE

```
LAYER 1 · INTENT     what the body is TRYING to do
                     → written into AnimationConstraint.Transform
                     → Animator + IKControl + procedural layer
                              │
                              ▼  joints "strive" toward Transform
LAYER 2 · MUSCLE     how HARD it's trying, per joint
                     → AngularStrength (tone) + MaxTorque (ceiling)
                     → ★ THIS LAYER IS THE GAME ★
                              │
                              ▼
LAYER 3 · WORLD      what ACTUALLY happens
                     → physics decides. gravity, collisions, mass, force.
```

**The character proposes. Physics disposes.**

Full detail: `docs/01_ARCHITECTURE.md`

---

## HOW TO WORK

**Phases are in `docs/02_PHASES.md`.** Each has a hard gate. Do not proceed past a
failing gate — tell the user it failed and why.

When the user says *"start phase N"*:
1. Re-read `docs/00_ENGINE_FACTS.md` (yes, again — it prevents API hallucination)
2. Read the phase spec in `docs/02_PHASES.md`
3. Read `docs/03_TUNING_LOG.md` for values already established
4. Build only what that phase needs
5. Run the gate. Report honestly whether it passed.
6. **Append any tuned values to `docs/03_TUNING_LOG.md`**
7. **Commit and push at the gate** (`gate N passed: <one line of what held>`). The repo's
   script folders ARE the live code (Studio file sync), so the commit is the snapshot.
   Non-script state (workspace instances, place settings) lives only in the place —
   remind the user to **publish** at every gate; Roblox version history is its rollback.

### The tuning log is not optional
This is a coupled PD-controller system across 15 joints. The stable region is found
**empirically** and the values are **precious**. If a good configuration is discovered
and not written down, it is lost. Log every value that survives a gate.

---

## THE ENVIRONMENT — STUDIO FILE SYNC FOR CODE, MCP FOR EVERYTHING ELSE.

*(Updated 14 JUL 2026 — verified live. This supersedes the original "MCP-only, no
filesystem sync" plan: Roblox's built-in script file sync is ON for this place.)*

**Scripts are edited as local `.luau` files in this repo.** Studio's built-in file sync
mirrors them into the place, both directions, near-instantly. Verified conventions:

- Mapped subtrees: `ReplicatedStorage/Shared/` · `ServerScriptService/Server/` ·
  `StarterPlayer/StarterPlayerScripts/Client/`. **New files sync ONLY inside these three
  folders** — a new top-level child of a service dir (e.g. `ReplicatedStorage/Foo.luau`)
  is silently ignored. All project code lives under Shared / Server / Client.
- Naming: `Name.luau` = ModuleScript · `Name.local.luau` = LocalScript ·
  `Name.legacy.luau` = legacy Script · script-with-children = `Name/init.luau` + siblings
  (Rojo-style). Edits, creations, and deletions all sync both ways.
- **Iris** is the one dependency, vendored as source at `ReplicatedStorage/Shared/Iris/`
  (SirMallard/Iris, commit 1836220, May 2026).

**The MCP is for everything that is not script source:** `execute_luau`, playtest control
(`start_stop_play`), `inspect_instance`, `search_game_tree`, console output, screen
capture, `user_mouse_input` (UI clicks — use `instance_path`, screen coords are
DPI-unreliable). **Use them.** Do not ask the user to verify something you can verify
yourself.

☠️ **`execute_luau` runs in a SEPARATE Luau VM from game scripts** (verified 14 JUL
2026: a monkey-patched module function was never called by the live loop; a sentinel
persisted only execute↔execute). `require` in an execute gets a *fresh module instance*
— mutating module tables/CONFIG from an execute is a **placebo** for the running game.
Only instances, properties, and attributes cross the boundary. Live-tune through those
(the muscle attributes exist for exactly this); code changes go through the files +
a play-session restart, and **always `script_grep` a changed symbol before starting
play** — the session snapshots whatever the Edit DM has, and per-file sync can lag.
**File sync PAUSES while Studio is in Play mode** (verified): edits made mid-play reach
the Edit DM only after stopping — stop play, edit, grep-verify, then restart; a grep
during play checks the stale snapshot and lies. Two more live-testing laws (details in
tuning log, Phase 2 session 1): **never create custom InputAction/InputContext
instances** (they can wedge SA input sync for the whole session — keybinds go through
UserInputService), and **`user_keyboard_input` works for ONE burst per play session**
(flush keyUps first; stuck keys leak across sessions; `character_navigation` and
scripted `MoveAction:Fire()` do not work under CCL/SA — don't drive the character with
them). Known capability limits of `execute_luau` (verified): `Workspace.AuthorityMode`
and `StarterPlayer.AvatarJointUpgrade` are RobloxScript-protected — read AND write — in
every DataModel. Those are Properties-panel-only; ask the user. It CAN write
`CharacterControlMode`, `CharacterBreakJointsOnDeath`, create instances, and set
`Script.Source`.

### Version control
The repo holds the live scripts, so **plain git commits are the code history** — commit
at every passed gate. Non-script state (test room instances, place settings) exists only
in the place: the user **publishes at every gate** and Roblox place version history is
that layer's rollback point.

### Testing is two-client, laggy, always
Every gate is tested with **two clients** under **network simulation** (150ms latency,
2% packet loss). A body that looks right in solo Studio and choppy to a remote player
is a **failed** body. This game is about reading other people's bodies. Local fidelity
is worth nothing.

---

## CODE CONVENTIONS

- **Luau, strict mode.** `--!strict` at the top of every script.
- Tabs, consistently. No formatter in this workflow — you are the formatter.
- Modules are `PascalCase` ModuleScripts. They return a table. No OOP ceremony.
- **No `wait()`. No `spawn()`.** Use `task.*`.
- **No yielding inside `BindToSimulation`.** It will error. See ENGINE_FACTS.
  **No `.Touched:Connect` in there either** (engine error, verified live 15 JUL —
  it also aborts the rest of that sim step). `task.defer` the wiring off the
  simulation timeline.
- Comments explain *why*, never *what*.
- If a magic number exists, it goes in a `CONFIG` table at the top of the file, and
  it gets an Iris slider.

---

## THE ONE TEST THAT MATTERS

Everything in this repo exists to pass this:

> **Player A stands in a room holding a heavy object out toward Player B.**
> **Player B — on 150ms with packet loss — sees the arm. Steady. Correct. Readable.**
> **Then A takes a bullet in that arm, and B watches the object drop.**

Not because it was animated. Because the muscle failed and the arm could no longer
hold the weight.

If that reads clean, we have the best character system on Roblox.
Every phase gate is a step toward it.
