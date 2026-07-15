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
- Balance & locomotion (Character Controller Library)
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
7. **Snapshot every project script (via `script_read`) into `snapshots/gateN_<name>/` and
   commit.** That is the code's version history — skipping it means the gate's code exists
   only inside one .rbxl.

### The tuning log is not optional
This is a coupled PD-controller system across 15 joints. The stable region is found
**empirically** and the values are **precious**. If a good configuration is discovered
and not written down, it is lost. Log every value that survives a gate.

---

## THE ENVIRONMENT — MCP-FIRST. NO FILESYSTEM SYNC.

**The Studio place is the single source of truth for all code.** There is no Rojo. You
work on scripts directly inside Studio through the Roblox Studio MCP: `script_read`,
`multi_edit`, `script_search`, `script_grep`, `execute_luau`, `inspect_instance`,
`search_game_tree`, playtest control, screen capture. **Use them.** Do not ask the user
to verify something you can verify yourself.

- **The MCP must be alive before any work.** It is your only access to the code. If it is
  not connected, or a call times out, STOP and tell the user — do not improvise a
  copy-paste workflow, and do not write code into this repo expecting someone to move it.
- **Iris** is the one dependency, installed as an rbxm in `ReplicatedStorage` (no package
  manager).
- **This repo holds docs, the tuning log, and script snapshots — never live code.**

### The snapshot ritual (this is the code's version control)
At every passed gate: `script_read` every project script and write them to
`snapshots/gateN_<name>/` in this repo, preserving the Studio hierarchy in the folder
structure. Then commit. That is the diffable history. Between snapshots, the published
place's own version history on Roblox is the rollback point — remind the user to publish
at each gate.

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
