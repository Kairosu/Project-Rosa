# 03 · TUNING LOG

## ⚡ CURRENT STATUS (update at every session end)

**As of 2026-07-14, end of Phase 2 session 3:**
- **Phase 0: GATE PASSED. Phase 1: GATE PASSED** (2-client netsim, user-verified).
- **Phase 2 build COMPLETE.** Sprint, wall-crash knockdown, real falls (hips heap
  with the body), assisted get-up with watchdog, BT/TS/AL live knobs + sliders.
- **Session 3 (user feedback pass #2): no more pinned-marionette states.**
  A rise that topples re-releases IMMEDIATELY (was: up to ~1 s downed on a fully
  powered, walkable capsule — the "pinned by the hips" report); balance dips
  floor at the knockdown threshold (was: near-zero balance on a standing capsule
  = "limbs ragdolled, hips pinned, still walkable"); knockdown band widened
  (knockdownFactor 0.3→0.45 — you either wobble readably or you GO DOWN);
  capsule release now enforced every step; walking locked during the get-up;
  turn speed halved (BaseTurnSpeed 16→8) for the ice-skate pivot feel.
- **User playtest items for Gate 2** (feel checks, minutes of play):
  1. **When ANYTHING feels pinned/wrong: press "Capture last 7 s"** in the
     panel (fall recorder — it also auto-captures every knockdown). Then just
     say so; the capture holds the exact client-side frames.
  2. Turn feel — **TurnSpeed slider** (default 8, stock was 16) and
     **AccelLean slider**. Tune live; report the values that feel right.
  3. Knockdowns — walls are binary now (walk-bump nothing, ≥ brisk jog DOWN);
     body + hips heap together. Get-up is still an assisted pivot (Phase 3
     makes it physical); walking locked until ~1.5 s after standing — say if
     that lockout feels too long.
  4. **Hover ladder** (leg-supported locomotion direction): drop the
     **StandForce slider** 10000 → 5000 → 2500 → 0 and walk/stairs at each.
     Standing at 0 already holds (legs carry the body through the Root
     socket); we're mapping where walking breaks.
  5. Sprint feel, stairs up/down, walk-stop feel (unchanged since session 2).
- **Then the Gate 2 netsim run** (2 players, 150 ms + jitter + 2 % loss):
  observing-client readability of all of the above, **numeric recv KB/s**
  (carried from Gate 1 — note it from the panel), and check whether
  `list_roblox_studios` sees test-server/client instances (04_PREFLIGHT §2).
- Read the ☠️ workflow laws in CLAUDE.md § THE ENVIRONMENT before touching
  anything, plus the **MCP live-testing laws** in the Phase 2 session-1 entry
  below (custom IAS instances wedge input sync; one keyboard burst per play
  session; file sync pauses during Play mode).

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

## BALANCE & CAPSULE (GroundController)

| Property | Value | Notes |
|---|---|---|
| BalanceMaxTorque | BT attr (default 800) × tone × max(impactFactor, 0.45) (× riseBoost 4 while Rising) | BT is live-tunable (panel slider, remote-validated 0–20000). The 0.45 stagger floor (= knockdownFactor) keeps a standing body from reading as ragdolled (session 3). Ladder: impulse 250 → min up 0.91 @ 800 / 0.82 @ 250 / 0.81 @ 100 (saturates — socket decouples) |
| BalanceSpeed | 100 (stock) | untouched so far |
| BalanceRigidityEnabled | `false` | non-negotiable — CONFIRMED live: rigid balance + powered body = perpetual flail (hard reaction impulses through the Root socket) |
| AccelerationTime | 0.2 | stop/launch whip fix (session 3) |
| DecelerationTime | 0.2 | symmetric smoothing (Phase 2); also keeps normal stops under the wall channel's 400 stud/s² |
| Sprint | Running.SpeedMultiplier = 1.6 → 25.5 stud/s | server-only writer; ability applies it via MoveSpeedFactor |
| BaseTurnSpeed | TS attr (default 8; stock 16) | live-tunable (panel slider, 0–40) — stock 16 is an instant pivot, the "ice skate" turn feel (session 3) |
| AccelerationLean | AL attr (default 1 = stock) | live-tunable (panel slider, 0–4) — lean into accel/decel, feel knob |
| StandForce / BaseMoveSpeed | 10000 / 16; **released per step** while fallTimer > 0 (both → 0); BaseMoveSpeed also 0 while Rising (move lock) | enforcement is per-step write-on-change, not transition-time (session 3) |
| GroundOffset | 2.925 (stock, observed live) | earlier log rows saying 1 were wrong |

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

## 2026-07-14 — Phase 1 — ✅ GATE 1 PASSED (2-client netsim run)

**Conditions:** Test → Clients and Servers → 2 Players, netsim 150 ms + jitter +
2 % packet loss, SA Visualizer on.
**Result:** user-verified — the observing client reads stand / collapse / rise /
shove response cleanly. Nothing buggy or broken reported.
**Carried (not silently dropped):** the numeric recv KB/s was not noted during the
run, and the `list_roblox_studios` multi-instance question went unchecked. Both roll
into the Gate 2 netsim run, which uses identical conditions.
**Verdict:** GATE 1 CLOSED. The Phase 1 configuration (joint table + densities +
reflexes above) is the frozen baseline. Phase 2 begins.
**Observing-client check:** PASS

---

## 2026-07-14 — Phase 2 (session 1) — sprint, wall crash, balance knob

### What shipped
- **Sprint** (`Shared/Locomotion.luau`): LeftShift → walk 16 → **25.5 measured**.
  Mechanism: the AvatarAbilities **Running ability's `SpeedMultiplier` attribute**
  (Configuration under `character.AbilityManagerActor.Abilities.Running`), which
  the ability applies via `GroundController.MoveSpeedFactor`. Never touch
  WalkSpeed/BaseMoveSpeed. SPRINT_MULT = 1.6.
- **Sprint intent path**: client reads `UserInputService:IsKeyDown` (plain,
  local), fires the MuscleDebug remote on change; **the server is the ONLY
  writer of SpeedMultiplier**, inside the sim.
- **Wall-crash knockdown**: `noteImpact` gained a **wall channel** — horizontal
  capsule decel (>400 stud/s², measured ~1250 on a sprint-wall hit vs ~130 for a
  smoothed stop) with severity from pre-impact speed (WALL = accelMin 400,
  speedMin 18, speedFallAt 26). A dip below **knockdownFactor 0.3** makes
  MuscleServer trigger the fall reflex: tone crash → limp → one boosted rise.
  Verified in server telemetry: hit at 25.6 → MT 1→0.08 → bal 0 → down 1.6 s →
  Rising → stand. Walk-into-wall (16) triggers nothing.
- **FALL.tone 0.15 → 0.08** — must sit BELOW COLLAPSE_BALANCE_THRESHOLD (0.1) or
  an upright knockdown leaves him slumped-but-standing at bal 120 (verified).
- **Body-rel reflex self-motion gates**: a 180° turn swings the body up to
  **~53 stud/s relative** (more than any crate hit) and the swing peaks AFTER
  the turn ends. Gates: turnCooldown 0.4 s after |ωy| ≥ 3, hAccel < 250,
  |speed − 0.5 s-EMA| < 10. Without these the launch dip's rearm swallowed the
  real wall impact.
- **DecelerationTime 0 → 0.2** (matches AccelerationTime; new since the user's
  last feel pass) — removes residual stop-whip AND keeps normal stops out of
  the wall channel.
- **BT attribute** (default 800, remote-validated, panel slider): impulse-250
  ladder → min up **0.91 @ BT 800, 0.82 @ BT 250, 0.81 @ BT 100** — measurably
  deeper stagger, saturating below ~250 because the Root socket decouples body
  hits from the capsule (Phase 1 discovery). The DESIGNED fall boundary lives in
  the impact reflex + knockdownFactor, not raw BT.
- **setupBody race fix**: the ControllerManager can arrive AFTER the joints —
  a session latched setupDone with AccelerationTime still 0. setupBody now
  returns false until the GroundController is configured.
- **VOID_Y = −50 reset** in MuscleServer (a runaway walked off the world and
  fell forever at y = −500).
- Locomotion clips: **stock Animate module** (RunAnimate.Server/.Client pair,
  SA-aware) already blends walk/run into Transform. Animation Graph beta not
  needed for Gate 2.

### ☠️ ENGINE FACTS learned (Server Authority, verified live)
1. **Custom InputAction state does NOT sync client→server** — not even read
   inside the server's BindToSimulation. Only the engine's own input pipeline
   rides the sim timeline. Custom binary intent goes over a validated remote.
2. **Custom InputAction/InputContext instances near the stock input tree can
   WEDGE the engine's input sync for the whole session** — server receives
   MovingDirection (0,0,0) forever while the client walks in place (rubber-band
   pin). Also: a foreign action inside the stock CharacterContext makes the
   AvatarAbilities mapper spam "Unknown action" every frame. **Do not create
   IAS instances** until Roblox documents support. Keybinds via
   UserInputService.
3. **Writing the Running SpeedMultiplier from BOTH peers compounds it**
   (16 → 41 stud/s measured): under SA the writes land as separate
   attribute-change events and the ability multiplies on each. One writer only.
4. Ability system: stock abilities are Configurations (Climbing, Running,
   Jumping, …) under `AbilityManagerActor.Abilities`; `Running.SpeedMultiplier`
   + `SyncedState` child; AbilityAction1–10 exist pre-bound in the runtime
   PlayerModule's `Player.InputContexts.CharacterContext`.

### ☠️ MCP LIVE-TESTING LAWS (cost most of this session — respect them)
- **`character_navigation` does not work under CCL** (rides Humanoid:MoveTo,
  which CCL dropped). Returns "Success", moves nothing.
- **Scripted `MoveAction:Fire()` is unreliable**: the first fire in a session
  may reach the server; later fires (including zeroing!) may not — one runaway
  walked off the world. Do not drive the character with Fire().
- **Real key injection (`user_keyboard_input`) works — ONE burst per play
  session.** Later bursts silently die (input channel/viewport focus). Compose
  everything (flush keyUps first! stuck keys leak across sessions) into a
  single call's action list. Never run an execute in parallel with keyboard
  input (focus flip kills it).
- **Telemetry pattern**: arm a background `task.spawn` sampler (writes to a
  StringValue) BEFORE the keyboard burst; read it after. `execute_luau` can
  RETURN values directly — use that instead of print/console (console output
  is shared, spammy, and truncates).
- **File sync PAUSES while Studio is in Play mode** — `script_grep` verifies
  only in Edit mode. Stop play before editing + verifying. (A stale-file
  session this way produced the 41-stud/s ghost.)

### Open / deferred
- Wall crash: capsule stays planted against the wall during the limp (hover +
  wall prop it up; balance 0 alone cannot tip a static upright capsule —
  verified at bal 0 for 0.9 s). The body goes limp and reads as a crash; the
  full slide-down-the-wall release is **Phase 3's DOWN state** (controller
  release), not Phase 2 tuning.
- Stairs + all feel checks: user playtest (self-serve keyboard choreography is
  too fragile to be worth more MCP cycles).

**Verdict:** kept — pending user feel pass + Gate 2 netsim run
**Observing-client check:** NOT RUN — the Gate 2 items

---

## 2026-07-14 — Phase 2 (session 2) — real falls: the capsule goes down too

**User feedback driving this session:** knockdown reaction delayed; "ragdolled but
still standing" — limbs limp while the hips stay pinned upright and WALKABLE.
Both confirmed and fixed; two knockdown cycles verified end-to-end (heap at
hrpY 0.4 → stable stand ≈3.5 s later, repeatable).

**The fixes, in dependency order:**
1. **Asymmetric master-tone slew**: DOWN is instant (muscles switching off can't
   slingshot — the 0.6 s up-slew was the perceived knockdown lag), UP stays
   slewed. While `Rising`, the up-ramp runs at **riseRamp 4**/s (6 made the legs
   snap to power while the feet caught ground → an 8-stud hop, verified).
2. **Capsule release** (`MuscleSystem.setCapsuleReleased`): while `fallTimer` is
   live, `GroundController.StandForce = 0` and `BaseMoveSpeed = 0` — the hips
   fall WITH the body (hrpY 4.8 → 1.4 verified) and walking-while-ragdolled is
   impossible. Restored at the rise.
3. **Get-up assist** (`MuscleSystem.getUpAssist`): a capsule that fell with the
   body lies flat, its floor sensor points sideways, and the GroundController
   can NEVER right it (verified: stuck lying forever). Until Phase 3's physical
   get-up: one server-side pivot — velocities zeroed, yaw kept, pelvis lifted
   +3.0 (at +2.5 sprawled limbs snag the ground and flop the capsule back).
4. **Rise watchdog** (riseTimeout 2.0, retryDown 0.8): a failed rise retries the
   whole down-and-right cycle. MUST check posture at expiry — a blind retry
   knocked down successful stands (verified).
5. **riseGrace 1.0 + riseHold 1.5**: the impact reflex is fully deaf while
   Rising and for 1 s after — get-up motion exceeds every impact threshold and
   re-felled the body in a loop (verified); and 0.5 s of upright re-armed the
   tilt trigger mid-wobble (verified).

**Engine facts (verified live, all dead ends — do not revisit):**
- `Humanoid:ChangeState(Physics)` is a NO-OP under the CCL ability state
  machine — state reverts to Running the same frame.
- Writing ability `SyncedState` attributes (`Active`/`Enabled`) from outside
  the AbilityManagerActor changes the attributes and nothing else.
- `StandForce = 0` alone does nothing at full tone — the LEGS hold the capsule
  through the Root socket; hover only matters once the body is limp.
- A direct `SetAttribute("MT", x)` from an execute is overwritten by the server
  slew loop within a step — force limpness via impulse-triggered reflex or the
  remote, never by poking MT.

**Verdict:** kept — awaiting user feel pass (knockdown → heap → scramble-up;
the get-up is an assisted pivot until Phase 3, expect it to read as functional,
not beautiful)
**Observing-client check:** NOT RUN — Gate 2 items

---

## 2026-07-14 — Phase 2 (session 3) — killing the pinned-marionette states

**User feedback driving this session:** (a) walking/turning feels like ice
skates — "movement through an invisible core, not driven by the legs";
(b) wall knockdowns leave the body "pinned into the wall by the hips";
(c) walking knockdowns sometimes leave limbs limp but hips upright and walkable.

**Diagnosis (server telemetry, 50–120 ms sampling through forced fall cycles):**
1. **The marionette window.** The fall trigger is disarmed while `Rising`, so a
   rise that TOPPLED lay on the ground with the capsule at FULL power —
   StandForce 10000, BaseMoveSpeed 16, walkable — until the watchdog expired.
   Measured: 0.9 s at up=0.00 fully powered. Against a wall this is exactly
   "pinned by the hips". Ability-stomp theory CLEARED: `FallingDown` goes
   Active during our falls but touches none of our properties.
2. **The mid-band dip.** An impact factor between knockdownFactor and 1 zeroed
   `BalanceMaxTorque`-ish on a body that STAYS standing: root orientation goes
   free, limbs flop, capsule keeps height and accepts WASD. A jog-speed wall
   hit (19–24 stud/s, below the sprint knockdown band) lands exactly here.
3. **Turn speed.** Stock `ControllerManager.BaseTurnSpeed = 16` ≈ instant pivot
   about the capsule axis — the "invisible core" turning feel.
   (Also corrected: live `GroundOffset` reads **2.925**, not the 1 recorded
   earlier.)

**Fixes (all verified live this session):**
1. **Rise fast-fail**: while `Rising`, `upY < tiltUp` retries the down-and-right
   cycle IMMEDIATELY instead of waiting out the watchdog. Verified: failed rise
   re-released within one 100 ms sample (was 0.9 s+).
2. **Stagger floor = knockdownFactor, raised 0.3 → 0.45**: `updateBalance`
   clamps the applied dip to ≥ 0.45, so balance never collapses on a standing
   body; a RAW factor below 0.45 is now a real knockdown (fall reflex, capsule
   release). Binary outcome: readable wobble or actually down. Verified:
   moderate hit (rel ≈ 29) → BMT 800→691 wobble, no fall; hard hit → down at
   0.37 s, walkable stand at 4.57 s.
3. **Per-step release enforcement**: `setCapsuleReleased(char, released,
   moveLock)` runs EVERY server step (write-on-change), not at transitions —
   no state path can strand a limp body on a live capsule.
4. **Move lock through the get-up**: `BaseMoveSpeed = 0` while `fallTimer > 0`
   OR `Rising` — walking mid-rise yanked the half-risen body over, and the
   get-up should read as committed. Restores when upright re-arms (~1.5 s
   after standing). Walk verified clean after: max 17.2 stud/s, up 1.00.
5. **TS / AL live knobs** (attrs + panel sliders, clamps 0–40 / 0–4):
   `BaseTurnSpeed` default **8** (stock 16) — the ice-skate lever;
   `AccelerationLean` default 1 (stock). Applied in `updateBalance`
   write-on-change, both peers, deterministic.

**Addendum (same day, user: "still pins briefly when going ragdoll"):**
1. **Dip escalation.** A hit RAMPS across frames: the first threshold crossing
   locked the window at that frame's MILD severity and the true peak (2–3
   frames later) was swallowed by one-dip-per-window — so real knockdowns
   registered as wobbles and the fall waited for the slow tilt trigger. Now a
   deeper factor escalates an ACTIVE window in place (never during the re-arm
   tail — that would re-open the boundary-struggle loop; timer NOT refreshed —
   escalation can't self-chain off the flop). Verified: mild hit (rel 32) +
   deep hit 0.15 s later inside the window → knockdown 80 ms after the peak
   (previously swallowed entirely, no fall).
2. **tiltUp 0.55 → 0.65.** At 0.55 the tilt trigger waited until ~56° — the
   body read as fully going over while the capsule stayed pinned. Successful
   rises hold upY ≥ 0.94, so 0.65 does not false-fail them. Reference tilt
   cycle after both changes: fell 0.35 s, walkable stand 4.75 s, 1 retry —
   recovery unchanged.
3. A brutal double hit (rel 32 then 85+25) needed several retry cycles
   (>8.5 s) but recovered clean — clumsy-but-alive is the accepted Phase 2
   bar; the physical get-up is Phase 3.

**Addendum 2 (same day, user: "still pins", "3rd fix and not fixed — better
debugging?"):**
1. **Client-side verification (new instrument class).** All prior verification
   sampled the SERVER; the user plays the CLIENT. A client-DM sampler during a
   forced fall settled it: controller property replication is FINE — client
   StandForce/BMS/BMT track the server within ≤1 sample (~70 ms at client
   frame rate), pelvis heaps with the capsule (3.8 → 1.6), worst transient
   marionette moment ≤150 ms. Both sims agree; the remaining user-felt pin is
   a real designed state my synthetic repros don't hit.
2. **Prime suspect: the wall stagger band.** 18–22 stud/s wall hits produced a
   deep stagger (no knockdown): body slumps against the wall, hips held at
   stand height by design = reads exactly as "pinned into the wall by the
   hips". WALL now speedMin 17 / speedFallAt 22 → knockdown from ~20 stud/s.
   Walls are binary: walk-bump nothing, brisk jog+ DOWN.
3. **Fall recorder (DebugPanel).** Client-side ring buffer (~7 s at frame
   rate: hrpY, pelvisY, upY, SF, BMS, BMT, MT, Rising, speed) → freezes to the
   client-side `FallCapture` StringValue 3 s after any tone crash, or via the
   panel button "Capture last 7 s" when a moment merely feels wrong. Read it
   with an execute in the **Client** DM. Verified end-to-end (auto-capture of
   a live knockdown). THE tool for feel-report triage — no more guessing.
4. **StandForce slider ("SF" attr, 0–20000)** — the hover-ladder experiment
   lane toward leg-supported locomotion (user direction). setCapsuleReleased
   restores to the attr, not a constant. Standing at SF=0 full tone already
   verified; next: walk/stairs at 5000/2500/0.

**Addendum 3 (same day) — THE FROZEN PIN, root-caused by the recorder:**
The user's first real capture showed the bug in full: body lying flat for
seconds at MT=1.00, capsule "standing" (SF 10000, BMS 16, BMT 800), Rising=0
— the fall machine believed all was well. Console had the missing link: **two
stability-guard resets** during ordinary play (RightFoot w=516, RightHand
w=333 tripped RUNAWAY_ANGULAR 250 during limp flops). The guard reset cleared
the fall state but did NOT re-arm `fallArmed` — a reset that toppled after
re-pinning landed in a state NO code path could ever leave: the frozen pin.
1. **Guard reset now re-arms** (`fallArmed = true`, downHold = 0).
2. **RUNAWAY_ANGULAR 250 → 800**: the guard catches explosions, not lively
   ragdolls — 333/516 rad/s occur in ordinary user flops (measured).
3. **Stranded catch-all (`FALL.strandedDown = 0.75`)**: ANY body down that
   long at power triggers the full fall cycle regardless of arming. No
   reachable state may lie powered on the ground — the class is self-healing
   now, not just the known doors.
4. **knockedDown no longer requires `fallArmed`** — the reflex is
   upright-gated + rise-deaf so it can't loop on a lying body; wall hits
   during the post-recovery window were being silently ignored
   (user: "running into the wall no longer ragdolls" — partially this).
5. **FS attribute** ("up"/"down"/"rising", server-mirrored on change) +
   recorder columns Pwr/FS — server state machine is now visible in every
   client capture.
6. Insight from the failed disarm-window repro: `Rising` clears at the exact
   step `fallArmed` re-arms (atomic) — so the rise fast-fail already covers
   every topple between stand and re-arm (verified: 0.00 s release). The
   guard reset was the ONLY door into disarmed+lying; it is closed and
   backstopped.
Verified: forced explosion-reset mid-fall → back standing armed (up 1.00,
FS=up), next tilt releases in 0.03 s (old code: never — the eternal pin).

**Verdict:** kept — awaiting user feel pass (turn feel is user-tunable now via
the TurnSpeed slider; report the value that feels right)
**Observing-client check:** NOT RUN — Gate 2 items

---
