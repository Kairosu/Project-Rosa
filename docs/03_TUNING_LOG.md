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
| Root | | | | | |
| Waist | | | | | |
| Neck | | | | | |
| LeftShoulder | | | | | |
| LeftElbow | | | | | |
| LeftWrist | | | | | |
| RightShoulder | | | | | |
| RightElbow | | | | | |
| RightWrist | | | | | |
| LeftHip | | | | | |
| LeftKnee | | | | | |
| LeftAnkle | | | | | |
| RightHip | | | | | |
| RightKnee | | | | | |
| RightAnkle | | | | | |

## BALANCE (GroundController)

| Property | Value | Notes |
|---|---|---|
| BalanceMaxTorque | | |
| BalanceSpeed | | |
| BalanceRigidityEnabled | `false` | non-negotiable |

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
