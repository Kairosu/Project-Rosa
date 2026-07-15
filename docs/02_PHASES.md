# 02 · PHASES

**Say "start phase N" and I'll build it.**

Each phase has a **hard gate**. A phase is not done because the code compiles — it is done
because the gate passes on **two clients under network simulation**.

**If a gate fails, say so.** Do not proceed. Do not paper over it. A body that limps into
Phase 4 on a broken Phase 1 foundation will cost us the project.

---

## THE STANDING TEST CONDITIONS
### *Every gate is run like this. No exceptions.*

- **Two clients** (Studio → Test → 2 Players)
- **Network simulation ON**: **150 ms latency, jitter enabled, 2% packet loss**
  *(Verified real: "Expanding Network Simulation in Studio," 2 June 2026 — latency, jitter,
  and packet loss, built for testing Server Authority. If the option isn't where expected,
  check Studio settings/beta features rather than assuming it doesn't exist.)*
- **Server Authority Visualizer on** (`Ctrl+Shift+F6`)
- **Record receive rate (KB/s) and client frame time** at every gate from Phase 1 onward.
  Staff-confirmed: NGR replicates physics at 60 Hz (~4× old bandwidth), and rollback at
  ~100 ms RTT can raise client sim load ~6×. A fully physical character is the expensive
  case for both. **We are generating the first real numbers for this architecture — log them.**
- **At every passed gate:** snapshot all scripts to `snapshots/gateN_<name>/`, commit,
  and have the user **publish the place** (Roblox's version history = the rollback point
  between snapshots).
- **The observing client is the one that matters.** A body that looks right locally and
  choppy to a remote player is a **FAILED** body. This game is about reading other people.

---

# PHASE 0 · HARNESS
### *Goal: a correctly-configured, observable, empty body. No muscle behavior yet.*

**Build:**
- **MCP proven first:** list Studio instances, read the game tree, run a trivial
  `execute_luau`, and round-trip a script edit (write → read back → matches). The MCP is
  the only path to the code — prove the pipe before building anything on it.
- **Iris** dropped into `ReplicatedStorage` as an rbxm (latest GitHub release — it has no
  dependencies)
- `StarterPlayer.AvatarJointUpgrade = Enabled`
- `Workspace.AuthorityMode = Server`
- Character Controller Library ON (Avatar Settings → Movement)
- `StarterPlayer.CharacterBreakJointsOnDeath = false`
- **StarterCharacter: default R15 blocky rig is fine.** Do not wait on art. The rig is
  a test fixture until Phase 5.
- **Iris debug panel** that enumerates every joint on the local character and displays
  its ClassName, `IsKinematic`, `AngularStrength`, `MaxTorque`
- **Test room**: flat floor · stairs · a ramp · a shovable crate · a wall to sprint into ·
  a heavy pickupable object

### ✅ GATE 0
1. Character spawns with **15 `AnimationConstraint`s** — the debug panel confirms this.
   **If it lists `Motor6D`, AJU is not on. Stop and fix.**
2. Server Authority Visualizer shows authority active.
3. Both clients see each other.
4. Iris panel reads and writes joint properties live.

---

# PHASE 1 · POWERED JOINTS ★ THE HARD ONE ★
### *Goal: the character is fully physical and does not explode.*

**This is where the real experimentation is. Budget the most time here. Everything
downstream is a consequence of getting this right.**

**Build:**
- `MuscleSystem` module — per-joint `{ tone, ceiling }` table
- **`IsKinematic = false` on ALL 15 joints.** No mixing. Ever. (See ENGINE_FACTS §1.)
- Iris: a slider per joint for `AngularStrength` (0 → 2) and `MaxTorque` (log scale)
- Iris: a **master tone** slider (0 → 1) that scales every joint
- A stability guard: detect NaN / runaway velocity, log the offending joint, reset

### The actual problem
This is a **coupled PD controller across 15 joints.** The stable region is found
**empirically**. Known hazards:

| Hazard | Symptom | Cause |
|---|---|---|
| `AngularStrength` too high | Oscillation → explosion | Roblox explicitly warns >1 "may cause the simulation to become unstable" |
| `MaxTorque` too low | Character melts into the floor | Joints can't lift their own limbs against gravity |
| Coupled amplification | Two joints fight, whole body vibrates | Neighbouring joints resonating. **Official fix exists:** root-of-chain joints (hips/waist) don't "see" downstream mass — raise BOTH `AngularStrength` AND `AngularDamping` there, above defaults. Tune root-out. |
| Under-damping | Limb overshoots and rings around the target | `AngularDamping < 1`. Start at 1 (critical) everywhere. |
| Bad `PhysicalProperties` | Limbs fling or refuse to move | Density wrong. Mass is a first-class tuning surface. |

A neck is not a hip. **Do not use one value for all joints.**

### ✅ GATE 1
1. Character **stands upright, unassisted, for 5 minutes.** No jitter. No drift.
   No explosion.
2. Master tone `1.0 → 0.0` → he **collapses smoothly** into a limp heap.
3. Master tone `0.0 → 1.0` → he **pushes himself back up.**
4. Shove him with the crate → he staggers and recovers, or falls, proportional to force.
5. **Observing client sees all of the above cleanly.** ← the one that can fail
6. **Receive rate logged** with both characters fully physical. This is the first real
   bandwidth number for this architecture — it decides server size later.
7. **Every surviving value is written to `03_TUNING_LOG.md`.**

---

# PHASE 2 · BALANCE & LOCOMOTION
### *Goal: he walks, he runs, and he can be knocked over.*

**Build:**
- `ControllerManager` / `GroundController` wired
- `BalanceRigidityEnabled = false`
- `BalanceMaxTorque` driven from muscle tone
- Locomotion clips into `Transform` (walk / run)
- Evaluate the **Animation Graph** beta for the blend tree. If it's not ready, hand-write
  a blend controller. **Do not block on it.**

### ✅ GATE 2
1. Walks and runs. No jitter.
2. **Sprints into a wall → stumbles or falls.** Does not rigidly bounce.
3. Walks up and down stairs without jittering.
4. Lowering `BalanceMaxTorque` makes him measurably easier to knock over.
5. Observing client sees it cleanly.

---

# PHASE 3 · COLLAPSE & RECOVERY
### *Goal: the four-state machine, and get-up that emerges instead of snapping.*

**Build:**
- `UPRIGHT / STUMBLE / DOWN / GETUP` state machine (see `01_ARCHITECTURE.md`)
- STUMBLE: leg tone dips, **arms auto-flail** (IK targets driven from root angular velocity)
- DOWN: tone → 0
- GETUP: tone ramps 0 → 1 while a get-up clip plays into `Transform`.
  **The body pushes itself up. There is no blend. Do not write a blend.**
- Face-up / face-down detection from the root's up-vector → two get-up clips

### ✅ GATE 3
1. Knocked over from any angle → goes down believably.
2. **Gets back up physically, no snap, from both face-up and face-down.**
3. Cap the tone ramp at 0.4 → he **tries to get up and fails.** Buckles. Goes back down.
4. **Stand on him → he can't get up.** (Because you're heavy. This should require zero code.)
5. Observing client sees it cleanly.

---

# PHASE 4 · TRAUMA
### *Goal: damage is legible on the body, not on a health bar.*

**Build:**
- `bleed: number` (0–1), drains over time, **server-authoritative** (in the SA simulation)
- `limbDamage: {[JointId]: number}`, server-authoritative
- Both wired into `solveMuscle()`
- **Test harness only:** a keybind that raycasts and applies `limbDamage` to whatever limb
  it hits. **This is not a weapon system. Do not build a weapon system.**

### ✅ GATE 4
1. Damage `RightUpperArm` while he holds the heavy object → **the arm droops and the object
   may drop.** Not animated. The muscle failed.
2. Damage a leg → he limps, then falls.
3. Raise `bleed` → global sag, wandering aim, stumbling, eventual collapse.
4. **The observing client can tell he's hurt without any UI.** ← this is the whole point
5. Observing client sees it cleanly.

---

# PHASE 5 · ARMS
### *Goal: two independent IK arms that compose with powered joints.*

**Build:**
- `IKControl` × 2 (arms). **First task: verify `IKControl` + `AnimationConstraint` compose
  on OUR rig.** Field evidence (Nov 2025) says they do — a dev shipped arms-on-weapon IK on
  an AJU rig — **with a known quirk:** rotating the character by writing the waist
  `Transform` made the IK solve to an offset target. Rotate via the controller/root, and
  reproduce-then-clear that quirk before building anything on top. Report the result.
- Elbow `HingeConstraint` / wrist `BallSocketConstraint` limits — check what AJU already
  provides before adding anything
- Grip attachments on the test object: `PrimaryGrip`, `SupportGrip`
- Grip states: `Idle / Carry / LowReady / Extend / Surrender`
- Hand state replicated via `InputAction` inside the SA simulation (~5 bytes)
- Foot planting IK (`Type = Position`, target = raycast hit)
- Head look IK
- **Custom R15 skinned rig can land here.** Not before.

### ✅ GATE 5
1. Hold the object out toward the other player. **He sees it — steady, correct, readable —
   on 150ms with packet loss.**
2. Two-handed hold on a long object → offhand goes to `SupportGrip` automatically.
3. **Damage the arm holding the object. The IK is still commanding the reach — and the arm
   physically cannot achieve it.** The intent is there; the body fails.

   *That third one is the thesis of the entire architecture. If it works without special-casing,
   the design is correct.*

---

# PHASE 6 · PROCEDURAL POLISH
### *Goal: life.*

**Build:**
- `RunService.PreSimulation` layer, multiplying into `Transform` (see ENGINE_FACTS §1)
- Breath · weapon sway · recoil (spring-damped) · flinch · bleed-tremor · lean
- **Every one of them scaled by muscle tone.**

### ✅ GATE 6
A bleeding man's **hands visibly shake**, his **aim wanders**, and his **shoulders sag** —
and all three come from **the same single number.**

---

# 🏁 THE FINAL GATE — THE BRIEFCASE TEST

> **Two clients. 150 ms. 2% packet loss.**
>
> **Player A stands in a room and holds a heavy briefcase out toward Player B.**
>
> **Player B sees the arm. Steady. Correct. Readable.**
>
> **Then A takes a round in that arm — and B watches the briefcase drop.**
>
> **Not because it was animated. Because the muscle failed and the arm could no longer
> hold the weight.**

If that reads clean, we have the best character system on Roblox, and everything else in
this game is ordinary engineering.

---

## PHASES DELIBERATELY NOT IN THIS REPO

Items · weapons · economy · map · vehicles · voice · phones · rounds · corporations ·
missions · UI · persistence.

They are simple by comparison and they are **not this repo's problem.**
Do not build toward them. Do not leave hooks for them.
