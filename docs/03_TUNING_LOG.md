# 03 · TUNING LOG

## ⚡ CURRENT STATUS (update at every session end)

**As of 2026-07-14, end of Phase 1 session 3:**
- **Phase 0: GATE PASSED** (solo items; 2-client sanity ran together with Phase 1 work).
- **Phase 1: all solo criteria pass.** Stands 5 min (soak: worst 1.41 stud/s, zero
  drift), collapses limp, recovers, proportional shove response (hold / stagger /
  ragdoll fall+rise). Falls are limp via the fall reflex; arms softened; stop-whip
  fixed — **all three user-feel-confirmed.**
- **Gate 1 OPEN on items 5–6 only:** observing-client readability + receive rate.
  Needs the user to run Test → Clients and Servers → 2 Players, netsim 150 ms +
  jitter + 2 % loss, SA Visualizer on. During that session, check whether
  `list_roblox_studios` can see the test-server/client instances (open question from
  04_PREFLIGHT §2). **User should publish the place at gate-pass.**
- Next phase after that: **Phase 2 (balance & locomotion).**
- All code lives in the repo (file sync); 4 commits pushed to GitHub main.
- Read the two ☠️ workflow laws in CLAUDE.md § THE ENVIRONMENT before touching
  anything: execute_luau VM isolation, and sync-verify (`script_grep`) before play.

---

## WHY THIS FILE EXISTS

This is a **coupled PD-controller system across 15 joints.** The stable region is found
**empirically**, over many iterations, and the values are **precious**.

If a good configuration is discovered and not written down, **it is lost** — and rediscovering
it costs hours. There is no analytical solution. There is only the log.

**Append every value that survives a gate. Never delete a row — supersede it.**

---

## FORMAT

Record what you changed, what it did, and whether it survived. Failures are as valuable as
successes: knowing that `AngularStrength = 1.4` on the neck explodes the sim is worth as
much as knowing that `0.6` works.

---

## JOINT VALUES — CURRENT

> **Official tuning recipe (API reference):** a joint at the **root of the chain**
> (hips/waist) doesn't "see" the effective mass of everything downstream, so it can
> oscillate at low frequency **even critically damped.** Fix: raise **both**
> `AngularStrength` **and** `AngularDamping` above defaults on root-ward joints.
> **Tune root-out: waist → hips → shoulders → distal.**
> Starting stance: `AngularDamping = 1` (critical) everywhere, then adjust.

| Joint | AngularStrength | AngularDamping | MaxTorque | Density | Notes |
|---|---|---|---|---|---|
| Root | 1.0 | 1.25 | 3000 | n/a (HRP 2.0 mass) | + RootBallSocket (ours) |
| Waist | 1.0 | 1.25 | 3000 | LowerTorso 1.2 | |
| Neck | 1.0 | 1.0 | 3000 | Head 0.7 | |
| LeftShoulder | 1.0 | 1.0 | 3000 | UpperArm 0.6 | |
| LeftElbow | 1.0 | 1.0 | 3000 | LowerArm 0.4 | |
| LeftWrist | 1.0 | 1.0 | 3000 | Hand 0.3 | |
| RightShoulder | 1.0 | 1.0 | 3000 | UpperArm 0.6 | |
| RightElbow | 1.0 | 1.0 | 3000 | LowerArm 0.4 | |
| RightWrist | 1.0 | 1.0 | 3000 | Hand 0.3 | |
| LeftHip | 1.0 | 1.25 | 3000 | UpperLeg 1.0 | |
| LeftKnee | 1.0 | 1.0 | 3000 | LowerLeg 0.7 | |
| LeftAnkle | 1.0 | 1.0 | 3000 | Foot 0.6 | |
| RightHip | 1.0 | 1.25 | 3000 | UpperLeg 1.0 | |
| RightKnee | 1.0 | 1.0 | 3000 | LowerLeg 0.7 | |
| RightAnkle | 1.0 | 1.0 | 3000 | Foot 0.6 | |

> **2026-07-14 status:** the above (= AJU factory defaults + 1.25 damping root-ward, on
> the listed densities) stands rock-solid: settles ≤1 frame after power-on, steady-state
> max |v| ≈ 1.4–5.7 across all parts including idle sway. UpperTorso density 1.0.
> Torque raises to 50k root-ward were tested and are NOT needed for standing.

## BALANCE (GroundController)

| Property | Value | Notes |
|---|---|---|
| BalanceMaxTorque | 2000 × masterTone | 10000 and 2000 equally stable. Even 2000 is unknockable while chain mass is 1.8 — knockdown sweep pending (see change log) |
| BalanceSpeed | 100 (stock) | untouched so far |
| BalanceRigidityEnabled | `false` | non-negotiable — CONFIRMED live: rigid balance + powered body = perpetual flail (hard reaction impulses through the Root socket) |

## MUSCLE MODIFIERS

| Constant | Value | Notes |
|---|---|---|
| BLEED_TONE_LOSS | | |
| BLEED_TORQUE_LOSS | | |
| TRAUMA_TONE_LOSS | | |
| TRAUMA_TORQUE_LOSS | | |
| LOAD_TONE_LOSS | | |
| STUMBLE_ANGLE | | |
| DOWN_ANGLE | | |
| GETUP_RAMP_TIME | | |

---

# CHANGE LOG

## [DATE] — Phase N — <what was being tuned>
**Changed:**
**Result:**
**Verdict:** kept / reverted
**Observing-client check:** pass / fail

---

## 2026-07-14 — Phase 0 — engine baseline facts (not tuning, but load-bearing)

**AJU factory defaults, every one of the 15 R15 joints (read off a live spawn):**

| Property | Default | Note |
|---|---|---|
| `IsKinematic` | `true` | flip to `false` per joint in Phase 1 |
| `AngularStrength` | `1` | |
| `AngularDamping` | `1` | critical |
| `MaxTorque` | `3000` | finite, NOT inf — a plain number |
| `LinearStrength` / `LinearDamping` | `1` / `1` | |
| `MaxForce` | **`0`** | ⚠ linear muscle ceiling is ZERO by default. Translation is held by the paired BallSocketConstraint, not the AnimationConstraint. Phase 1: expect translation to be socket-carried; don't "fix" MaxForce without a measured reason. |

**Rig census on spawn (default R15, AJU active):** 15 `AnimationConstraint`, 0 `Motor6D`,
15 `BallSocketConstraint` (one per joint), 18 `NoCollisionConstraint`.

**Settings state:**
- `AvatarJointUpgrade`: already ACTIVE by default in this Studio build (H2 2026 default-on
  rollout confirmed live) — verified by rig census, since the property itself is
  RobloxScript-protected (unreadable/unwritable from any script context, MCP included).
- `Workspace.AuthorityMode`: RobloxScript-protected too — **must be set to `Server` by hand
  in the Properties panel.** Enum is `{Server, Automatic}`.
- `StarterPlayer.CharacterControlMode = LuaCharacterController` — set via MCP; verified
  live: character spawns with a `ControllerManager`. (Enum:
  `{Default, Legacy, NoCharacterController, LuaCharacterController}`.)
- `StarterPlayer.CharacterBreakJointsOnDeath = false` — set via MCP.

**Verdict:** kept (facts, not choices)
**Observing-client check:** n/a — solo verification; 2-client run is the user's Gate 0 step

---

## 2026-07-14 — Phase 1 — powered joints: the two engine gaps, and the stable region

**The two discoveries that cost the session (both now fixed in `MuscleSystem.setupBody`):**

1. **AJU ships NO BallSocketConstraint on the Root joint** (HRP→LowerTorso; the other 14
   joints each get one). Combined with the factory `MaxForce = 0` on the linear muscle
   channel, powering the rig silently drops the body 2.7 studs out of the capsule
   (Root attachment separation 2.68; all socketed joints hold at ~0.002). **Fix: we add
   `RootBallSocket` ourselves.** Translation is then solver-held like every other joint;
   the linear muscle channel stays at factory zero. (A spring-based Root was tried at
   {2, 1.5, 25000} and {0.75, 2, 8000} — both violently unstable; do not revisit.)

2. **The CCL FloorSensor senses the character's own torso.** Powered bodies get
   world-collidable torso parts (LowerTorso/UpperTorso CanCollide=true), and the
   `ControllerPartSensor` found `SensedPart = UpperTorso` — the hover then chases a
   "floor" that hangs from the hover → feedback loop → the perpetual-breakdance flail
   (~180–260 stud/s, never settles). **Fix: collision groups** — body parts in
   `CharBody`, HRP in `CharRoot`, pair non-collidable, both collide with Default. The
   sensor casts with the root's group, so the body vanishes from its ray
   (SensedPart = actual floor, 10/10 frames). Isolation proof: anchoring the HRP made
   the powered body settle in 4 frames at max |v| 2.06.

**Also confirmed live:** attribute limits are BOTH real — 1024-byte total payload per
instance (46 numeric attrs bust it) AND <50 chars per string value (one packed 300-char
string busts it). Muscle drivers therefore live in 15 per-joint packed triples
("MJ_Waist" = "1,1.25,3000") + MT + Powered = 17 attributes.

**Master tone must SLEW, never step** (1.5/s in MuscleServer): snapping tone onto a
displaced body slingshots it (539 stud/s measured off a 2.7-stud stretch).

**What passed solo (Gate 1 items 1–3 in solo form):**
- Stand: settles ≤1 frame after power-on; steady-state max |v| 1.4–5.7 over repeated
  5 s windows; pose exact (HRP 4.80, Head 6.00, feet planted symmetric); zero guard
  trips; clean console.
- Collapse (remote → MT 0): capsule tips, body heaps face-down, Head Y 0.02,
  settles to max |v| 0.03. Joints read str 0 / torque 0 / still non-kinematic.
- Restore (MT 0→1): gets back up within the ramp window (capsule rights + hover lifts
  + muscles re-pose), no guard trip, returns to clean stand.

**Open for next session — the knockdown sweep:** shoves are proportional (crate at
25/60 stud/s → peak body |v| 31/98, head dips) but he cannot be knocked DOWN: chain
mass is only 1.8 vs HRP 2.0 (R15 blocky part volumes are tiny), so hits fling
feather-limbs without moving the mass. BalanceMaxTorque 10000→2000 changed nothing.
Plan: raise DENSITY ×10–20 (chain toward ~10–20 mass), re-scale MaxTorque per joint to
the new loads, re-sweep BALANCE_TORQUE for the stagger/fall boundary. All three knobs
are in `MuscleSystem.CONFIG`.

**Verdict:** kept (architecture + fixes); knockdown values still open
**Observing-client check:** NOT RUN — solo only. Gate 1 items 5–6 (observing client,
receive rate) plus the full 5-minute soak remain for the 2-client netsim run.

---

## 2026-07-14 — Phase 1 (session 2) — knockdown sweep + the 5-minute soak

**Density ×10 is the knockdown enabler and costs nothing.** Chain mass 1.8 → **18.5**
(vs HRP 2.0) and the stand is *identical* — settles ≤1 frame, steady ≈1.4 stud/s —
because `AngularStrength` is frequency-normalized (gains track mass automatically) and
levers are short (torque 3000 ceilings still never saturate). Final densities are in
`MuscleSystem.CONFIG.DENSITY` (LowerTorso 12 … Hand 3).

**✅ 5-MINUTE STAND SOAK PASSED** (solo, gate item 1): six consecutive 50 s windows,
worst window max |v| = **1.41 stud/s** (= the idle-sway animation), up-vector 1.00
throughout, total drift 0.02 studs. Zero guard trips.

**Impulse ladder (UpperTorso, horizontal), the proportional response (gate item 4):**

| Impulse | peak rel speed | Result |
|---|---|---|
| 100 | ~17 | holds footing (below reflex threshold) |
| 250 | ~28 | staggers to up≈0.87, recovers cleanly |
| 400 | ~108 | **knocked flat** (up→−0.3), stays down |

Staying down at full tone leaves the body "paddling" (muscles chase the standing idle
pose against the ground, ~85 stud/s churn) — that is the **missing Phase 3 DOWN state**,
not a Phase 1 defect. A tone cycle (MT 0 → 1) rescues from ANY state back to a clean
stand — verified from the paddling-flat state.

**The impact reflex** (in `MuscleSystem`, CONFIG.IMPACT = threshold 25 / fallAt 55 /
staggerTime 0.6 / uprightGate 0.7 / rearm 2.0): body-relative speed above threshold
dips balance torque proportionally (zero at fallAt). Three rules learned the hard way:
- threshold must clear recovery-motion noise (18 self-triggered; 25 with the ladder
  above is clean),
- **upright-gated**: a tilted/rising body must never re-dip itself,
- **one dip per window (rearm)**: without a 2 s lockout it re-fires the instant the
  body crosses back over the upright gate and it struggles at the boundary forever.

**BalanceMaxTorque = 800** baked (stand is solid even at 300; raw-physics knockdowns
exist at any value once the chain is heavy — the reflex just makes the fall threshold
designable).

**⚠ WORKFLOW LAW (cost half this session): `execute_luau` runs in a separate Luau VM
from game scripts.** Module/CONFIG mutations from a command are placebo for the live
loop; require() there builds a fresh module instance. Only instances/properties/
attributes cross. All "live sweeps" of module values earlier this session were placebo —
by luck, everything validated ran on the baked file values. Also: per-file sync can lag
several seconds; `script_grep` a changed symbol before starting any play session (one
stale-file session produced 30 minutes of false diagnosis).

**Verdict:** kept — this is the Phase 1 solo configuration
**Observing-client check:** NOT RUN — items 5–6 need the 2-client netsim session

---

## 2026-07-14 — Phase 1 (session 3) — feel pass: ragdoll falls, soft arms, stop-whip

**User feedback driving this session:** falls too rigid; arms too stiff; forward-then-back
lean when stopping a walk.

**Fall reflex (Phase 3 seed, in MuscleServer + CONFIG.FALL):** tilt below up=0.55 →
master tone slews to 0.15 (limp DURING the fall — this is what makes falls ragdoll) →
1.6 s down → `Rising` attribute set → balance ×4 while rising → one committed rise →
re-arm only after 0.5 s continuously upright. Full cycle measured: hit → limp fall →
heap → single clean rise → stable stand in ~3.5 s, zero guard trips.
Two failure modes tuned out, in order:
- re-trigger while lying (re-arm gated on having STOOD, not on time),
- rise half-completes → topples → re-limps forever (fixed by riseBoost=4 + riseHold).

**Arms softened** (they bear no load): shoulders/elbows 1.0 → **0.65** strength,
wrists → **0.5**, damping 1.0 unchanged. Stand unaffected (max |v| 6.3 incl. arm swing).

**Stop-whip:** `GroundController.AccelerationTime` 0 → **0.2** (set in setupBody).
The instant capsule brake was whipping the 18.5-mass body forward-then-back on every
stop. Feel verdict pending user playtest.

**Verdict:** kept — user feel-checked all three ("looks good to go", 2026-07-14)
**Observing-client check:** NOT RUN — still the open Gate 1 item

---
