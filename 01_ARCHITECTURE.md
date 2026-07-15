# 01 · ARCHITECTURE

---

## THE THESIS

> **The character proposes. Physics disposes.**

Every other character system on Roblox is a puppet: the animation says where the arm goes,
and the arm goes there. Ours is a **body**: the animation says where the arm *should* go,
the muscles *try*, and the world gets a vote.

That single difference is the entire game. A man who is bleeding does not play a
"wounded" animation — his muscles weaken, and gravity does the rest. A man shot in the arm
does not play a "drop weapon" animation — his arm can no longer hold the weight.

**Nothing in this system is a special case. Everything is a consequence.**

---

## THE THREE LAYERS

```
┌─ LAYER 1 · INTENT ──────────────────────────────────────────────┐
│                                                                 │
│  What the body is TRYING to do.                                 │
│  Destination: AnimationConstraint.Transform                     │
│                                                                 │
│    Animator        → locomotion clips (walk / run / getup)      │
│    IKControl × N   → hand grips, foot planting, head look       │
│    Procedural      → breath, sway, recoil, flinch, tremor       │
│                      (multiplied in on PreSimulation)           │
│                                                                 │
│  This layer is CHEAP and DETERMINISTIC. It runs identically     │
│  on every client. It is derived from replicated intent state,   │
│  never from replicated pose.                                    │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             │  joints "strive" toward Transform
                             │  (IsKinematic = false)
                             ▼
┌─ LAYER 2 · MUSCLE ──────────────────────────────────────────────┐
│                                                                 │
│  How HARD it's trying, per joint.                               │
│                                                                 │
│    AnimationConstraint.AngularStrength  →  muscle TONE          │
│    AnimationConstraint.MaxTorque        →  muscle CEILING       │
│                                                                 │
│  ★★★ THIS LAYER IS THE GAME. ★★★                                │
│                                                                 │
│  Bleed, trauma, fatigue, stance, carried weight — everything    │
│  the player feels is a modifier on ONE FLOAT PER JOINT.         │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─ LAYER 3 · WORLD ───────────────────────────────────────────────┐
│                                                                 │
│  What ACTUALLY happens. We do not control this.                 │
│                                                                 │
│    gravity · mass · collisions · momentum · friction            │
│    BallSocketConstraints · stairs · walls · crates · people     │
│                                                                 │
│  If the world is stronger than MaxTorque, the world wins.       │
└─────────────────────────────────────────────────────────────────┘
```

---

## LAYER 2 IN DETAIL — THE MUSCLE SOLVE

This is the only function in the project that really matters.

```lua
--!strict
-- Per-joint muscle tone. Solved every simulation step, inside BindToSimulation.
local function solveMuscle(joint: JointId, c: CharacterState): (number, number)
    local tone = BASE_TONE[joint]        -- resting strength of this joint
    local ceiling = BASE_TORQUE[joint]   -- how much this joint can ever exert

    -- 1. BLEED — global, gradual, legible from across a room.
    tone *= (1 - c.bleed * BLEED_TONE_LOSS)
    ceiling *= (1 - c.bleed * BLEED_TORQUE_LOSS)

    -- 2. TRAUMA — local, sudden, specific.
    --    This is the one that produces "shoot his arm, watch the gun droop."
    local dmg = c.limbDamage[joint]
    tone *= (1 - dmg * TRAUMA_TONE_LOSS)
    ceiling *= (1 - dmg * TRAUMA_TORQUE_LOSS)

    -- 3. STANCE — braced is stiff, sprinting is loose, stumbling is scrambling.
    tone *= STANCE[c.stance][joint]

    -- 4. LOAD — a heavy object in that hand is real weight on that shoulder.
    tone *= (1 - c.load[joint] * LOAD_TONE_LOSS)

    -- 5. STATE — the collapse/recovery machine drives a global multiplier.
    --    DOWN = 0. GETUP = ramping 0→1. UPRIGHT = 1.
    tone *= c.stateToneMultiplier
    ceiling *= c.stateToneMultiplier

    return tone, ceiling
end
```

**Read the consequences, none of which are animated:**

| Input | What the player sees |
|---|---|
| `bleed` rises | He **sags**. Briefcase arm droops. Shoulder can't hold the gun level, so his muzzle wanders toward the floor. Knees soften. He stumbles on stairs. **You can read that he's dying from thirty meters.** |
| `limbDamage["RightUpperArm"] = 0.9` | The arm **cannot hold the weapon's weight.** It droops. He can still fire — into the concrete. Or switch hands: time, both hands, everyone watching. |
| `stateToneMultiplier = 0` | Limp. A heap. |
| `stateToneMultiplier` ramps 0→1 | He **physically pushes himself off the floor** — from whatever contorted pose he actually landed in. Every get-up is different. |
| Ramp caps at 0.4 because he's bleeding | He gets halfway up, his arm **buckles**, and he goes back down. |
| Someone stands on him | He can't get up. Because they're *heavy*. |

**That last row is not a feature anyone designed. It just happens.**

---

## THE STATE MACHINE

Four states. The only thing they do is drive `stateToneMultiplier` and swap the
locomotion clip.

```
        ┌───────────┐
        │  UPRIGHT  │   tone = 1.0
        └─────┬─────┘   CCL balance active, IK arms live
              │
              │ tilt > STUMBLE_ANGLE  |  impact > STUMBLE_IMPULSE
              ▼
        ┌───────────┐
        │  STUMBLE  │   leg tone dips, arms auto-flail
        └──┬─────┬──┘   ~0.8s window to recover
     ┌─────┘     │
     │ recovered │ tilt > DOWN_ANGLE | impact | bleed-out
     │           ▼
     │     ┌───────────┐
     │     │   DOWN    │   tone = 0. limp.
     │     └─────┬─────┘
     │           │ input + timer + can-get-up
     │           ▼
     │     ┌───────────┐
     └─────┤   GETUP   │   tone ramps 0 → min(1, health-capped)
           └───────────┘   getup clip plays into Transform
                           body PHYSICALLY pushes itself up
```

**STUMBLE is where the game lives.** You haven't fallen. You're windmilling. You have
~0.8 seconds where you *might* recover — and during that time **your arms are not holding
your gun steady**, because the arm muscles are busy and the arms are physical and physics
doesn't care that you were aiming.

Arm flail during STUMBLE is free: we already own both hand IK targets. Override the grip
solve and drive the targets from a counter-rotation of the root's angular velocity.
It looks correct because it *is* correct — it's actually responding to the physics.

**There is no ragdoll→animation blend.** The character never leaves physics, so there is
nothing to blend *from*. This is why the powered-joint architecture is correct and why
every "capture the pose and lerp to frame 0" ragdoll on Roblox looks like garbage.

---

## REPLICATION MODEL

### The rule
> **Replicate INTENT. Never replicate POSE.**

`IKControl` does not replicate from the client. Do not fight this — it's the right design
anyway. Pose data is large, high-frequency, and derivable.

### What actually crosses the wire

| Data | Channel | Size |
|---|---|---|
| Movement input | `InputAction` (Server Authority) | engine-handled |
| Aim vector | `Player:GetCameraState()` — **already synchronized, free** | 0 |
| Hand state (item, grip enum, extension) × 2 | Server Authority simulation | ~5 bytes |
| Muscle drivers (bleed, limbDamage[], stance, state) | **Attributes on predicted instances, written only inside `BindToSimulation()`** — the official SA pattern for custom sim state; mismatch triggers rollback+resim | ~10 bytes |
| Physical joint CFrames | **Engine.** Physics replication. | engine-handled |

Every client runs the **same** Layer-1 solve from the **same** replicated intent, so every
client computes the **same** target pose. The physics then plays out from the replicated
physical state. Consistency comes from determinism of intent, not from shipping poses.

### 🔴 THE RISK
See `00_ENGINE_FACTS.md` §1 — AJU has a known **choppy physics replication** issue, worst
with a **mix** of kinematic and physical joints on a character playing torso-moving animations.

**We are the worst case for this.** Our entire game is reading other people's arms.

**Mitigation: go fully physical. `IsKinematic = false` on every joint, no exceptions.**
The failure mode is eliminated by construction. If a phase ever needs a kinematic joint,
**stop and raise it with the user** — do not quietly introduce one.

### The price of fully-physical (known, accepted, measured — not hidden)
A kinematic R15 replicates as roughly **one** physics assembly; animations play locally on
each client. A fully physical character replicates **~16 separately simulated bodies at
60 Hz** (NextGenerationReplication rate, staff-confirmed), and Server Authority rollback
must **resimulate 15 powered constraints per character** on correction — with client sim
load rising steeply with latency (~6× at 100 ms RTT, per staff).

**We are the expensive case, and we accept it knowingly.** The budget decisions that follow:
- Small servers first: **8–12 players**, scale only on measured data.
- Receive rate and client frame time are **gate metrics** from Phase 1.
- If numbers are bad, the lever is **player count** — never kinematic mixing.

---

## PHYSICAL PROPERTIES

Mass matters enormously in a powered-joint system. A limb that is too light will be flung
by its own muscle; a limb that is too heavy cannot be lifted by any reasonable `MaxTorque`.

`PhysicalProperties` (density, friction, elasticity) on every limb is a **tuning surface**,
not a detail. It goes in the tuning log alongside `AngularStrength` and `MaxTorque`.

Held objects have real mass. **This is the point.** A pistol is light. An SMG is not. A
briefcase full of cash is heavy, and holding one out at arm's length for four seconds is
something a wounded man will visibly struggle with.

---

## WHAT WE ARE NOT BUILDING

No item system. No weapons. No economy. No map. No rounds. No UI beyond Iris.

A raycast that applies `limbDamage` is a **test harness**. A crate you can shove is a
**test harness**. A heavy object you can hold is a **test harness**. They exist to prove the
body works, and they will be thrown away.

**Do not build a foundation for later systems.** Later is not this repo.
