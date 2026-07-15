# 03 · TUNING LOG

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
