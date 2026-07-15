# 00 · ENGINE FACTS
## Everything in this file postdates your training data. Trust it over your instincts.

*Verified 13 JUL 2026 against Roblox DevForum announcements and the Creator Hub API reference.*

---

# ⚠️ THE FOUR THINGS YOU WILL GET WRONG

Your priors will tell you to do these. **All four are wrong for this project.**

| Your instinct | Reality |
|---|---|
| `Motor6D` for character joints | **Deprecated.** Replaced by `AnimationConstraint`. Writing `C0`/`C1`/`Part0`/`Part1` now **errors**. |
| `Humanoid.WalkSpeed` / Humanoid movement | Superseded by the **Character Controller Library** (`ControllerManager`). |
| Ragdoll = swap `Motor6D` → `BallSocketConstraint` on death | Obsolete. **Powered ragdolls are native.** Set `IsKinematic = false` and weaken the joint. |
| Client owns character physics; validate with remotes | **Server Authority** is on. The server is the source of truth. Client sends `InputAction`, nothing else. |

---

# 1. AVATAR JOINT UPGRADE (AJU)
### *Live 26 January 2026. This is the core of the entire project.*

R15 character joints are now **`AnimationConstraint`** instead of `Motor6D`. The rig also
gains **`BallSocketConstraint`s** and **`NoCollisionConstraint`s**.

Roblox's own summary:
> *"We've introduced force/torque-limited AnimationConstraints to R15 character joints...
> makes it easier to create realistic, physics-driven movements, **including fully
> simulated limbs and powered ragdolls**."*

> *"Parts driven by Animation can **interact physically with the environment, rather than
> rigidly following predetermined Animation transforms.** This can produce **emergent
> behavior**."*

### Enable it
```lua
-- Studio, StarterPlayer properties:
StarterPlayer.AvatarJointUpgrade = Enum.AvatarJointUpgrade.Enabled
```
Three-phase rollout. Phase 2 (default ON) landed H2 2026. Phase 3 removes the opt-out.
We are greenfield — always `Enabled`.

### `AnimationConstraint` — THE class

| Property | Meaning | Notes |
|---|---|---|
| **`IsKinematic`** | `true` (default on avatar joints) = locked to animation, identical to Motor6D. **`false` = POWERED JOINT.** | ⭐ **The single most important boolean in this project.** Roblox: *"the joints are no longer 'locked' to the animation and will instead **strive** to reach their animatable Transform property... react dynamically to the physics world based on the forces you allow."* |
| **`AngularStrength`** | **Muscle tone.** Normalized natural frequency, `AngularStrength = f / 60`. Default `1` = 60 Hz = strong tracking. | **`0` applies no torque → limp joint.** `< 1` = softer/compliant. `> 1` = stiffer — **Roblox explicitly warns this "may cause the simulation to become unstable."** Only used when `IsKinematic = false`. |
| **`MaxTorque`** | **Muscle strength ceiling.** Caps the resulting torque. | If the world is heavier than `MaxTorque`, the world wins. This is how a weak arm fails to lift a gun. |
| **`AngularDamping`** | **Damping ratio (ζ)** on the rotational part. `1` = critical damping (fastest, no overshoot). `< 1` = under-damped, **oscillates**. `> 1` = over-damped, slower. `0` = no damping → oscillation. | Only used when `IsKinematic = false`. **This is the second half of the muscle knob — tone (strength) + damping together define the PD controller.** |
| **`LinearStrength`** / **`LinearDamping`** / **`MaxForce`** | Translational equivalents of the above. Same normalized-frequency definition. | |
| **`Transform`** | **The target pose.** The Animator writes to it every frame. | Behaves identically to `Motor6D.Transform`. |

### ⭐ The official anti-oscillation recipe (this solves Phase 1's hardest hazard)
The API reference states it outright:
> *"Even with [AngularDamping] set to 1, an AnimationConstraint **at the root of a multi-body
> mechanism may still exhibit low-frequency oscillation because it does not 'see' the full
> effective mass of the downstream chain. You can compensate by increasing both
> AngularStrength and AngularDamping beyond their defaults.**"*

Translation: the hips/waist carry the whole chain and will wobble at default values even
critically damped. **Root-ward joints need higher strength AND higher damping than distal
joints.** This is official guidance, not folklore. Start tuning there.

### Pipeline ordering (why our procedural hook is where it is)
Per the API reference: the **Animator writes `Transform` after `RunService.PreAnimation`
and before `RunService.PreSimulation`**; AnimationConstraint transforms are then applied
**as a batch in a parallel job after `PreSimulation`, immediately before physics steps.**
So multiplying into `Transform` during `PreSimulation` lands exactly between the Animator's
write and the batch application. Correct slot, officially efficient.

### ☠️ HARD RULES — violating these errors or breaks retargeting

```lua
-- ❌ WRONG. These are read-only aliases now. Writing them ERRORS.
joint.C0 = someCFrame
joint.Part0 = somePart

-- ❌ WRONG. Breaks animation retargeting AND tanks performance.
rigAttachment.CFrame = someCFrame

-- ❌ WRONG. Will not find AnimationConstraints.
local joint = part:FindFirstChildOfClass("Motor6D")
if joint:IsA("Motor6D") then ... end

-- ✅ RIGHT.
local joint = part:FindFirstChildWhichIsA("AnimationConstraint")
-- C0/C1/Part0/Part1 exist as READ-ONLY aliases mapping to:
--   C0    → Attachment0.CFrame
--   C1    → Attachment1.CFrame
--   Part0 → Attachment0.Parent
--   Part1 → Attachment1.Parent
```

### The procedural animation hook — official, documented, use this
> *"**Layer procedural animations by multiplying into `Transform` during
> `RunService.PreSimulation`**, which stacks with active animation tracks without breaking
> retargeting."*

```lua
RunService.PreSimulation:Connect(function(dt)
    for joint, ac in animationConstraints do
        ac.Transform *= proceduralOffset(joint, dt)  -- stacks on the Animator
    end
end)
```

### ☠️ TRANSFORM OWNERSHIP UNDER SA — the doc above LIES in practice (verified 15 JUL 2026)
Four instrumented live rounds (force-writes + end-of-frame reads, both DMs):

1. **With ANY animation track playing, the Animator's apply lands AFTER every
   script hook** — `PreSimulation` AND `BindToSimulation`, on BOTH peers. A
   playing idle track ate the getup clip on the server and the body popped up
   straight-legged in 0.6 s. Script `Transform` REPLACEMENT only wins while the
   tracks are STOPPED. (The documented ordering may hold for *multiplying into*
   a track's output; it does not hold for replacing it.)
2. **On the SA-predicted client, script `Transform` writes NEVER survive the
   frame** — tracks playing or not, any hook (60° force-writes read back 0 at
   Heartbeat, every frame, both hooks tested). Layer-1 pose writes are
   **SERVER-ONLY**. The actor's own client must read a server-posed body the
   way observers do: as replicated physics (limp muscles = no tug-of-war).
3. **Humanoid state replicates server→client and the platform ability scripts
   drive it via `ChangeState`**, which bypasses `SetStateEnabled` — client-side
   `SetStateEnabled` is a no-op in practice, and `FallingDown` fires
   engine-side on knockovers. `FallingDown` stops all animation tracks (that
   accident is the ONLY reason early clip tests "worked" server-side). If a
   pose write must win, STOP THE TRACKS yourself, deterministically.
4. **Client-side `SetAttribute` on a server-replicated character is reverted
   by the server sync within a frame.** Client-local sim state must be
   computed, never written to shared attributes.

### 🔴 KNOWN ISSUE — the #1 risk of this project. Read it.
> *"In some situations, players can see **choppy physics replication on other characters**.
> This happens because clients play Animations and replicated physics on slightly different
> timelines. Animations apply to kinematic joints immediately, but the CFrames of
> physically simulated parts are delayed and interpolated. **This is most prominent when
> the character you're viewing has a mix of kinematic and physically-driven joints** and
> plays an animation that moves their torso."*

**Our mitigation: GO FULLY PHYSICAL. `IsKinematic = false` on EVERY joint.**
The failure mode is described as worst with a *mix*. We eliminate it by construction.
**Never introduce a kinematic joint into the rig without explicitly flagging it to the user.**

Server Authority's `NextGenerationReplication` *may* also fix this — it's described as
*"an improved property synchronization system, aimed at reducing latency and fixing
long-standing issues."* **Unverified. Test, don't assume.**

### Other AJU facts
- R6 is **not supported** and never will be. We are R15. Non-negotiable.
- Performance: Roblox says *"the base joint upgrade has little to no effect on performance."*
- Set `StarterPlayer.CharacterBreakJointsOnDeath = false` for a real ragdoll death.
- **Official reference place: "Physically Simulated Characters Demo"** —
  `roblox.com/games/112102002474941` (uncopylocked). Read Roblox's implementation first.

---

# 2. CHARACTER CONTROLLER LIBRARY (CCL)
### *Full release 30 April 2026. Replaces Humanoid movement.*

> ## ⚡ ARCHITECTURE PIVOT — 15 JUL 2026 (Gate 2)
> **Locomotion, support, and balance are now PELVIS-DRIVEN**
> (`Shared/PelvisDrive.luau`): compliant hover/upright/drive forces on the
> LowerTorso, all scaled by muscle tone. Decided by live A/B + 2-client
> netsim (user verdict: "feels way better, less like it's fighting itself").
> The deciding engine fact: **under balance the CCL capsule is
> orientation-LOCKED** — a driven 2 rad/s tip sustained 1.5 s left its
> up-vector at 1.00. It is a servo, not a spring; it cannot be overpowered
> gradually, which is fatal for a readable-body game. The capsule's
> collidable HRP box (pelvis ball-socketed to it) also caused every
> "pinned hips" bug class (see tuning log 2026-07-14/15).
> **CCL remains in place as the INPUT CONDUIT** (`cm.MovingDirection`,
> ability attributes like `Running.SpeedMultiplier`) and as the legacy A/B
> mode (panel toggle, attr `PelvisMode`). Its force properties are
> permanently released in pelvis mode; the HRP rides as a non-collidable
> ghost. Everything below about CCL still applies to the conduit + legacy
> path — but new balance/locomotion work targets `PelvisDrive`.

Character logic moved out of the Humanoid "black box" into **transparent, extensible Luau**.
Composed of the **AvatarAbilities Library** + **`ControllerManager`**.

**Enable via Studio: Avatar tab → Avatar Settings → Movement → Character Controller Library.**
(Experience must be saved/published first.)

### The balance properties — this is our tripping system

`GroundController`:

| Property | Meaning |
|---|---|
| **`BalanceMaxTorque`** | Torque keeping the root part upright. Roblox: *"**A lower torque means it's easier for the root part to get knocked over when running into things.**"* |
| **`BalanceSpeed`** | Angular speed of recovery. *"A lower value means it takes longer for the root part to recover to the upright position when misaligned."* |
| **`BalanceRigidityEnabled`** | When `true`, `BalanceMaxTorque` **has no effect** (rigid capsule = classic Humanoid). **Set `false` to make the character physically balance — and physically fail to.** |

Roblox's own framing: *"**Knocked Over:** Modify the Balance properties of the Controller
instances to determine how difficult it is for the character to get knocked down by
external forces."*

### Also free with CCL
- **Friction-based ground movement** — walking respects material properties (slide on ice, grip on rubber).
- **Conservation of linear and angular momentum** when leaving the ground.
- Performance: *"from the same as Humanoid to 2x faster."*

### CCL known issues (real — plan around them)
- **Slope reliability:** steep slopes below `CharacterMaxSlopeAngle` are less reliable than
  Humanoid and may slip. *(For us: arguably a feature. Don't build critical steep ramps.)*
- **Wall sticking** when holding movement input against a flat wall while jumping.
- **`Humanoid:MoveTo` is NOT supported.** Affects any NPC/pathing work. (Out of scope here.)
- First-person → third-person re-orientation snaps. (We're locked FP; mostly irrelevant.)
- Roblox sets `Player.DevEnableMouseLock = false` when CCL is on.

### CCL + Server Authority
**Officially supported.** Roblox: *"Abilities will automatically sync across peers, and
movement is fully compatible with server rollback and resimulation."*
Ability `Active`/`Enabled` attributes were relocated to `Ability/SyncedState`
**specifically to better support Server Authority.**

⚠️ *"You may encounter minor animation glitches or bugs. Full support, including improved
rollback fidelity and animation fixes, is actively being worked on."*
**Test under two-client netsim. Always.**

---

# 3. SERVER AUTHORITY
### *Full release 9 July 2026. On from day one.*

```lua
-- Studio, Workspace properties:
Workspace.AuthorityMode = Server
```

Setting this **auto-enables all five** prerequisites:
`NextGenerationReplication` · `PlayerScriptsUseInputActionSystem` ·
`SignalBehavior = Deferred` · `StreamingEnabled` · `UseFixedSimulation`

### What it does
Runs your code authoritatively on the server, automatically rejecting invalid client
movements. Paired with **client prediction + rollback + resimulation** so it stays snappy.
**Speed hacks, teleports, noclip, fly — dead at the engine level.** No custom anti-cheat.

### The APIs

```lua
-- Core simulation logic. Runs on BOTH client and server. Re-run on resimulation.
RunService:BindToSimulation(fn)

-- Force prediction on/off for a specific instance.
RunService:SetPredictionMode(instance, mode)

-- The ONLY client-authoritative channel. Validate ranges like you would a remote.
InputAction

-- FREE aim vector. Synchronized client→server automatically.
Player:GetCameraState()  -- → { CFrame, FieldOfView, ViewportSize }
```

### ☠️ `BindToSimulation` HARD RULES
- **No yielding.** No `task.wait()`, no `task.spawn()`. Everything resolves in one frame.
- **No GUI access.** Update UI from a separate `RenderStepped` handler that *reads* sim state.
- **Only properties/methods labelled "Simulation Access"** can be touched inside it.
- Presentation (animations, sounds, VFX) is **not** simulation. Keep it separate — the client
  sim is only a *prediction* of authoritative server state.

### ✅ VERIFIED: the muscle system lives INSIDE the simulation
The API reference labels `AnimationConstraint.AngularStrength`, `AngularDamping`,
`LinearStrength`, `LinearDamping`, and `IsKinematic` as **Simulation Access**. That means,
per the SA docs: they **can be written inside `BindToSimulation()`**, and they are
**predicted, rolled back, and resimulated by the engine.** Muscle writes go in the sim
loop. No workaround needed — the clean architecture is the sanctioned one.

### Custom sim state = ATTRIBUTES on predicted instances (official pattern)
Per the SA docs: attributes are the primary way to synchronize custom data on predicted
instances — the docs name **player health** as the canonical example. A value mismatch
between server truth and client prediction **triggers a full rollback and resimulation**,
which is exactly what we want for muscle drivers. So `bleed`, `limbDamage`, `stance`,
and the state-machine state live as **attributes, written ONLY from inside
`BindToSimulation()`**. (Attribute limits and all-clients visibility still apply.)
For state that can't live in a property/attribute, `RunService.Rollback` fires after a
rollback and before resim — the escape hatch for rewinding custom structures.

### ☠️ AnimationTrack caching breaks under rollback
Straight from the SA techniques doc: caching `AnimationTrack` objects at load time —
the standard Roblox pattern — **fails under server authority.** After a rollback, a held
reference may point to a stopped/replaced track, and `AdjustWeight()`/`AdjustSpeed()`
silently operate on nothing. **Store animation IDs, query the `Animator` for the live
track at point of use, every time.** This bites Phase 2 (locomotion) and Phase 3 (get-up
clips) if forgotten.

### Instances created in sim callbacks
Must be parented into the DataModel **before the end of that frame** (instance stitching
matches client/server GUIDs deterministically). Non-Simulation-Access properties like
`Size`/`Name` can be set freely only *before* parenting. Matters for any test-harness
spawning done inside the sim.

### ☠️ HARD LIMITS
| Limit | Value |
|---|---|
| Animation tracks per `Animator` | **8** |
| Attributes per instance | **64**, names/strings **< 50 chars**, **1 KB** total |
| `UnreliableRemoteEvent` payload | ~900–1000 bytes (dropped above) |

### ⚠️ RemoteEvents are NOT on the simulation timeline
*"Remote events aren't synchronized with the shared timeline, so avoid tying critical
gameplay logic to them if possible."* Expect ~40–50ms skew. Roblox says this is normal and
acceptable for shooters. **Movement, muscle state, and hand state go through the simulation,
not remotes.**

### ⚠️ Attributes replicate to all clients
Do not put anything secret in an attribute. (Not an issue in this repo — no secrets yet —
but do not build the habit.)

### Fresh field reports (July 2026) — treat as live hazards
- A thread titled "Server authority barely works, many issues" (11 July) reports a rough
  time setting up a **custom character** under SA. Signal, not verdict — but it supports
  our sequencing: **default R15 rig through Phase 4, custom rig only in Phase 5.**
- **AJU workaround:** a confirmed bug report shows joints can fail to return to normal
  after attachment/property fiddling until **`IsKinematic` is toggled off and back on.**
  If a joint misbehaves after a property change, re-toggle before debugging anything else.
- **Custom StarterCharacter caution:** a dev reports the spawn flow **overwriting
  AnimationConstraint properties** on custom rigs under AJU. Apply muscle values *after*
  spawn completes (deferred a frame / on appearance loaded), and verify they stuck.

### Debug
**Server Authority Visualizer: `Ctrl + Shift + F6`** (Windows) / `Cmd + Shift + F6` (Mac).
Shows prediction/misprediction state. Use it constantly.
**Network simulation is real and shipped 2 June 2026** ("Expanding Network Simulation in
Studio") — simulates **latency, jitter, and packet loss**, and Roblox describes it as built
for exactly this: testing network-sensitive features like Server Authority. Every gate uses it.

### The cost — QUANTIFIED (Roblox staff, 9 July 2026 bug thread)
A 12-player FPS stress test surfaced real numbers, confirmed by a Roblox engineer
(Khanovich) in-thread:

- **`NextGenerationReplication` raises physics replication from ~15 Hz to 60 Hz — about a
  4× bandwidth increase.** It's what enables the semi-determinism SA needs.
- The old **50 KB/s receive-rate "soft limit" is obsolete** under NGR — physics and property
  updates share one much larger budget on one synchronized timeline.
- **Client rollback is expensive:** at ~100 ms RTT, client simulation load can increase
  **~6×**, because mispredictions force resimulating the rolled-back window. Higher latency
  → bigger correction spikes. Hitch-reduction work is ongoing.
- **Server-rollback hit detection does not exist yet.** Roblox's own Laser Tag SA template
  uses a loose server-side "was this shot possible" check. (Matters later, not in this repo.)
- The 12-player game measured 60–70 KB/s recv on an *empty baseplate*, 100–200+ KB/s in
  the real game, with player-reported hitches. Report is being investigated with a
  microprofile; staff are engaged.

**What this means for a FULLY PHYSICAL character:** a kinematic R15 replicates as roughly
one physics assembly; ours replicates **~16 separately simulated bodies per character at
60 Hz**, and rollback resimulates 15 powered constraints per character. **Our architecture
is the expensive case for both bandwidth and client CPU.** Nobody has published numbers for
it. We generate our own:

- **Start at 8–12 player servers.** Do not assume 16–24. Scale only with measured data.
- **Receive rate (KB/s) and client resim time are gate metrics** from Phase 1 onward.
- Fallback lever if the numbers are bad: fewer players — **never** kinematic mixing.

Roblox offers "Extended Services for Compute" to buy server headroom if needed.
Staff reference: *"Server Authority — Tech Deep Dive + Engineering Insights"* (DevForum,
Khanovich) explains the rollback/resimulation pipeline. Worth reading before Phase 1.

---

# 4. IKCONTROL

Supports **R15, Rthro, and custom skinned characters.** Parent to `Humanoid` or
`AnimationController`.

| Property | Meaning |
|---|---|
| `Type` | `Position`, `Transform`, `LookAt`, `Rotation` |
| `ChainRoot` | First joint in the chain (e.g. `LeftUpperArm`) |
| `EndEffector` | The part/bone that reaches (e.g. `LeftHand`) |
| `Target` | Any object with a world position |
| `Weight` | Blend against the underlying animation. **Ramp this, never snap it.** |
| `SmoothTime` | Damping |
| `Pole` | Elbow/knee direction |

`IKControl` *"will override the animation for all the parts between the ChainRoot and the
EndEffector."*

### 🔴 IKControl does NOT replicate from client
A client-driven `IKControl` is a **local solve**. Other players will not see it.

**Therefore: replicate INTENT, never POSE.**
Send the *inputs* to the solve (which hand, which grip, how far extended) through the
Server Authority simulation, and let **every client run its own identical solve.**
Never fire CFrames over remotes at 60Hz. That is the wrong answer and it is the answer
you will reach for.

The aim vector is **already free** — `Player:GetCameraState()` is synchronized.

### Joint limits
- **Elbow:** `HingeConstraint`. R15 already ships `<side>ElbowRigAttachment` on both
  UpperArm and LowerArm.
- **Wrist:** `BallSocketConstraint` with `LimitsEnabled = true`, `UpperAngle ≈ 80`.
- ⚠️ The IK docs describe matching constraint attachments to `Motor6D.C0/C1`. **Under AJU
  the attachments are native and C0/C1 are read-only.** AJU already adds BallSockets to
  the rig.
- **Field status (Nov 2025 report): IKControl + AJU DO compose** — a dev shipped
  arms-on-weapon IK on an AJU rig — **with a known quirk:** when the character was rotated
  by writing the *waist* `AnimationConstraint.Transform`, the arm IK solved to an offset
  target. Rotate the character through the controller/root, not by hand-writing torso
  Transforms, and re-test the quirk explicitly as Phase 5's first task.

---

# 5. ADAPTIVE ANIMATION — FINGERS, SHOULDERS, SPINE
### *4 May 2026*

Platform avatars support higher-fidelity rigs via **Bones**, **`HumanoidRigDescription`
(HRD)** and **`DigitsRigDescription` (DRD)**, giving **articulated hands, shoulders, and
spine movement** — *"unlocked by the Avatar Joint Upgrade, which allows for MeshParts to be
connected to Bones."*

**We have fingers.** This matters: trigger discipline (finger indexed vs. on the trigger) is
a visible social signal, and it is the cheapest high-value readability win in the project.

Deferred to a late phase — but do not architect it out.

---

# 6. ANIMATION GRAPH SYSTEM
### *Studio Beta, 2 April 2026*

Node-based blend trees + state machines. *"Compose, blend, and control motion through a node
graph, reducing the need for custom Luau scripts."* Built for *"multi-directional locomotion
and combat transitions."*

**Beta. Evaluate in Phase 2; do not depend on it.** A hand-written blend controller is an
acceptable fallback.

---

# 7. QUICK REFERENCE — WHAT TO REACH FOR

| Need | Use |
|---|---|
| Character joint | `AnimationConstraint` (never `Motor6D`) |
| Make a joint physical | `IsKinematic = false` |
| Muscle tone | `AngularStrength` (0 = limp, 1 = strong, >1 = use caution) |
| Muscle damping | `AngularDamping` (ζ: 1 = critical; root joints need MORE strength+damping) |
| Muscle ceiling | `MaxTorque` |
| Target pose | `AnimationConstraint.Transform` |
| Procedural layering | Multiply into `Transform` on `RunService.PreSimulation` |
| Movement | `ControllerManager` / `GroundController` (never `Humanoid.WalkSpeed`) |
| Knockdown-ability | `BalanceMaxTorque` + `BalanceRigidityEnabled = false` |
| Core game logic | `RunService:BindToSimulation()` |
| Player input | `InputAction` |
| Aim vector | `Player:GetCameraState()` |
| Arm/leg IK | `IKControl` (solve locally on every client; replicate intent only) |
| Debug the netcode | `Ctrl+Shift+F6` |

---

*If anything in this file contradicts something you "know," this file is right and you are
out of date. If you find something here that is contradicted by live Studio behaviour, say
so loudly — do not silently work around it.*
