# 03 · TUNING LOG

## ⚡ CURRENT STATUS (update at every session end)

**As of 2026-07-15 (later night): GETUP IS NOW IK PLANT CHOREOGRAPHY
(Addendum 9). The limp-client design below read as a "possessed spasm"
(user-reported, then measured: 65 % whip-frames on the actor's screen vs the
server's 14.5 % — SA corrections whipping zero-ceiling joints). Every
mitigation was measured and failed (tone floors, SetPredictionMode both
sides, runtime AnimationTracks — all in the whip table, Addendum 9); the fix
is the one target channel the engine applies on every peer: IKControl. Hands
plant on the ground beside the hips, feet plant under the body, both peers
compute identical goals from GT/GF — matched targets + matched tone schedule,
client whips 65 % → 34.7 %, client/server motion ratio 5.5× → 1.7×. The
joint-space clip is deleted (git @ c75f542 keeps it); the buckle mechanism is
untouched. Kept from Addendum 8: rise-fail all-part velocity bleed,
FallingDown→Running enforcement (walking fix, user-confirmed "okay better").
NEEDS: user eyes-test (does the spasm read as gone? do the plants read as
pushing?), face-UP getup eyeball (this session's crates all landed him
prone), then the 2-client Gate 3 run.**

---

*(superseded by Addendum 9 — kept for the record)*
**As of 2026-07-15 (night): PHASE 3 REWIRED after the user's regression report
— the getup clip was NEVER VISIBLE on the actor's own screen. Root cause found
by live instrumentation (Addendum 8, and the new ☠️ Transform-ownership law in
00_ENGINE_FACTS §1): under SA, the client cannot write joint Transforms at all,
and a playing track eats them on the server too. Fix set (this commit):
server-only clip + server stops tracks during down/getup + actor's client goes
muscle-limp during getup (reads the rise as replicated physics, like the down
phase always has) + rise-fail pelvis-velocity bleed (kills the "flung inverted
between attempts" hit) + per-step FallingDown→Running enforcement while upright
(kills the post-fall jittery/fall-anim walk).**

---

**As of 2026-07-15 (late): PHASE 3 BUILD COMPLETE, solo-verified. Awaiting
user feel pass + the 2-client Gate 3 run.** *(superseded above — "solo-verified"
was an illusion: every solo check read SERVER state, and the server-side look
never reached the actor's client.)*
- **The four-state machine is live** (FS: upright/stumble/down/getup), and the
  get-up is PHYSICAL — the teleport pivot is a loud last-resort only (fired
  once in ~15 knockdown cycles today, on a prone attempt).
- Solo Gate 3 status: (1) falls from any angle ✓; (2) physical get-up both
  orientations ✓ — supine 4.6 s/1 attempt, prone 8.2 s/3 attempts (works,
  clip needs polish); (3) RC 0.4 → tries, buckles, never stands, recovers
  instantly at RC 1 ✓; (4) stand-on-him DEFERRED to the 2-client run (solo
  props slide off the light body — the spec's test is literally a player);
  (5) observing-client = the netsim run.
- **User pass items:** knockdown → watch him TUCK and PUSH himself up (no
  teleport); get hit mid-run → stumble (knees soften, arms flail via IK) →
  recover; RiseCap slider at 0.4 → he must visibly try-and-buckle; then the
  2-client run: stand on him (he must NOT get up), observing-client
  readability, recv KB/s number.
- Known rough edges: prone get-up slower (clip iteration next session), jump
  still dead, stairs unpolished, animations read confused during getup
  (ability system thinks it's falling — cosmetic).

**Get-up LOOK pass (same day, user: "ragdoll → stiff limbs → we just rotate
up — is that intended?"):** four changes, all aimed at the read:
1. **Entry-pose capture**: the clip's first keyframe is now the CAPTURED
   landed pose (physical relative attachment frames at GETUP entry — NOT
   joint.Transform, which the Animator kept filling with idle while limp).
   The sequence literally starts from the sprawl. Kills the snap.
2. **Staggered keyframes** (CLIP_TIME 1.6): gather (0.35) → push (0.8) →
   crouch (1.2) → stand; arms plant beside hips / under shoulders per
   orientation before anything rises.
3. **Scheduled tone in step()**: arms full from entry (they push), legs ease
   in 15–50 % of the clip (0.45→1), spine 30–75 % (0.35→1) — the torso
   UNFURLS instead of pivoting as a slab.
4. **Back-loaded hover** (progress²): body organizes LOW first; the visible
   rise happens in the clip's second half.
Reliability after the pass: supine sometimes 1 attempt (4.6 s), otherwise
2–3 attempts ≈ 8.3 s both orientations; buckle at RC 0.4 intact (never
stands, recovers 1.7 s at RC 1); zero last-resort pivots this matrix.
**The look-vs-reliability balance is now a FEEL CALL — user judges whether
the struggle reads right or the knobs (tone curves, keys, hover curve) need
another turn.**

---

**As of 2026-07-15: Phase 0, 1, and 2 GATES PASSED. ARCHITECTURE PIVOTED.**
- **GATE 2 PASSED** (user-run: full feel pass + 2-client netsim, "testing
  complete no issues"). Walks/runs clean, wall crash fells, trips fell
  (contact-gated), whole body heaps including hips, recovers repeatably.
- **⚡ THE PIVOT: locomotion is now PELVIS-DRIVEN** (`Shared/PelvisDrive.luau`,
  **default ON at spawn**; panel "locomotion A/B" toggles back to the legacy
  CCL capsule). Decided by A/B verdict ("feels way better, less like it's
  fighting itself, doesn't pin on walls") + netsim. Deciding fact: the CCL
  capsule is orientation-LOCKED under balance (servo, not spring) and its
  collidable HRP box caused the entire "pinned hips" bug family. CCL remains
  as input conduit (MovingDirection, Running.SpeedMultiplier). Details:
  00_ENGINE_FACTS § 2 pivot block + Addenda 5–7 below.
- **Current pelvis gains** (PelvisDrive CONFIG, first-gains stable): HOVER
  30/9 cap 1.8 g · UP 55/10 cap 120 · YAW 35/6 · DRIVE 5 cap 70 · SPEED 16 ·
  RISE_BOOST 2.5 · HEIGHT 2.7. Knockdown cycle: fell 0.05 s, stable stand
  3.15 s, repeatable.
- **NEXT: PHASE 3 — collapse & recovery on the pelvis architecture**
  (UPRIGHT/STUMBLE/DOWN/GETUP; physical get-up replaces the assisted pivot).
  Known pelvis gaps to absorb into Phase 3 planning: **jump is dead**
  (Jumping ability drove the capsule), **stairs** = single-ray hover (user
  passed it, but expect polish), **sprint multiplier in pelvis mode**
  works per-link but never end-to-end verified, animations may read
  confused (ability state machine thinks it's falling), and the BT slider
  is capsule-only — the pelvis equivalents are UP_* / tone.
- Carried bookkeeping (now for Gate 3): numeric **recv KB/s** was never
  recorded at a gate; `list_roblox_studios` test-instance question
  (04_PREFLIGHT §2) still open.
- Read the ☠️ workflow laws in CLAUDE.md § THE ENVIRONMENT before touching
  anything, plus the **MCP live-testing laws** in the Phase 2 session-1 entry
  below (custom IAS instances wedge input sync; one keyboard burst per play
  session; file sync pauses during Play mode; no Touched:Connect inside
  simulation callbacks).

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

**Addendum 4 (same day) — THE MID-AIR PIN: the HRP is a collidable box.**
User capture (prop collision, with Pwr/FS columns): knockdown fired INSTANTLY
and correctly (FS=down, SF=0, MT=0.08 at the hit) — yet the body hung 1.3 s
at standing height, near-upright, fully released. Nothing in the force system
held it. What held it: **the HumanoidRootPart is an invisible 2×2×1
COLLIDABLE box with the pelvis ball-socketed to it** — the box landed on top
of the prop and the limp body dangled from it. Same mechanism as the earlier
"pinned INTO the wall by the hips" (box leans on wall). The force-side
releases were never enough; the pin was collision GEOMETRY, not forces.
- Fix: while released, `HumanoidRootPart.CanCollide = false` (per-step
  enforced in setCapsuleReleased). The 18.5-mass body drags the 2.0-mass
  ghost box wherever it heaps; nothing can snag. Restored with the rise
  (getUpAssist pivots +3 first, same step, so it re-collides above ground).
- Verified on a reproduced prop knockdown (dropped tilted onto a 4-stud
  crate): dangling signature 1.3 s → **0.28 s** (residue = the body itself
  sliding off the crate), and it recovered to a legitimate stand ON the
  crate. The DOWN state is now a true free ragdoll — an architecture-
  independent property any future locomotion system also needs.

**Addendum 5 (same day) — THE 0.5 s ONSET PIN: the capsule never tips.**
User: "still pins ~0.5 s then falls like normal ragdoll." Instrumented
discovery that rewrites the fall model: **under balance the capsule is
orientation-LOCKED** — a driven 2 rad/s spin sustained for 1.5 s left
up=1.00 (the balance servo cancels rotation within each step; it is a
gyroscope, not a spring). Consequences:
- The tilt trigger (upY < 0.65) can barely ever fire in a real trip — the
  capsule does not tip; the BODY folds over the obstacle while the hips
  hang from the locked capsule. The ~0.5 s pin was the body-rel reflex
  slowly noticing what the tilt path never would.
- **Torso-divergence trigger** (the trip detector): armed AND
  `UpperTorso.UpVector.Y < torsoDiverge (0.55)` sustained `torsoTime
  (0.15 s)` → fall. The body's pose is the truth; the capsule's tilt is
  propaganda. Walk/sprint torso pitch stays > ~0.9; stop-whips are shorter
  than torsoTime.
- Also added committed-topple trigger (tipUp 0.9 + tipRate 1.5 rad/s
  horizontal) for capsules that physically lose the lock (sensor lost) —
  verified it cannot false-fire from nudges (w=1.0 → recovered, no fall).
- Verified trip emulation (sustained 30 stud/s forward fold on torso+head):
  fold start → release **0.135 s** (was ~0.5 s+ user-felt); capsule up was
  still 0.75 at release — the old path would still have been waiting.
  Clean recovery to stand afterwards (FS=up, MT 1.0).

**Addendum 6 (same day) — random falls while sprinting + THE PELVIS SPIKE.**
User: "still falls randomly when running around, didn't hit anything."
1. **Measured: sprint STRAFES whip the body to rel ~70** (vs hit threshold
   25/fallAt 55) — the dip escalation had unmasked animation/locomotion whip
   as "hits". No threshold separates self-motion from impacts at speed.
   Structural fix: **falls require a cause** — the body-rel channel AND the
   trip detector only fire within `contactWindow` (0.5 s) of a FOREIGN touch
   on a non-leg part (`MuscleSystem.recentContact`; feet/shins excluded —
   they touch the world constantly). Walls keep the decel channel, true tilt
   stays contact-free. Verified: identical sprint+strafe pattern (rel 70.2)
   → zero falls, balance never dipped; crate trip → release in 0.165 s.
   Also: swing-scaled hit line (`swingPerSpeed 0.7`), torsoTime 0.15 → 0.1,
   and the capsule inherits the pelvis's downward velocity at release (the
   hover-zero lag read as onset pin).
2. **PELVIS-DRIVEN LOCOMOTION SPIKE IS LIVE** (`Shared/PelvisDrive.luau`,
   panel "locomotion A/B" toggle, remote "PELVIS", attr "PelvisMode").
   Compliant forces on the LowerTorso — hover spring (cap 1.8 g × tone),
   upright torque spring (COMPLIANT, tone-scaled — the anti-gyroscope), yaw
   toward MovingDirection, drive toward input × 16 × SpeedMultiplier.
   Capsule stays permanently released as input conduit (MovingDirection
   flows ✓ verified); HRP rides as ghost. Fall machine reads the PELVIS for
   posture in this mode. RISE_BOOST 2.5 on spring+caps while Rising (without
   it: fell clean, never rose — verified).
   **First-gains results (HOVER 30/9 cap 1.8 g · UP 55/10 cap 120 · YAW 35/6
   · DRIVE 5 cap 70): stands dead-stable (support force = body weight,
   3935 ≈ 20 m × g), walks 16.8 max with minUp 0.96 (it LEANS — alive),
   full knockdown cycle fell 0.35 s / heap flat / stable stand 4.60 s.**
   Known spike gaps: jump dead (Jumping ability drove the capsule), stairs
   likely bad (single-ray hover doesn't step-climb), sprint multiplier
   unconfirmed in this mode (keyboard burst died; links verified
   individually), stock animations may look confused (ability state machine
   thinks it's falling). A/B verdict + netsim decide the pivot.

**Addendum 7 (2026-07-15) — USER A/B VERDICT + the dead contact gate.**
**User: "Pelvis driven feels way better — walking feels a lot less like it's
fighting itself, and it doesn't pin when hitting a wall."** The remaining
pelvis-mode complaint (occasional get-up pin) + one console error, all fixed:
1. **☠️ `.Touched:Connect` is FORBIDDEN inside simulation callbacks** (engine
   error, user-captured). ensureTouchArming ran from noteImpact inside the
   sim step → the error aborted wiring once per spawn AND killed the rest of
   that sim step → the whole contact gate was silently DEAD server-side
   (recentContact always false — capsule-mode prop trips couldn't fire at
   all; pelvis-mode falls still worked because the pelvis physically tips
   through the contact-free tilt path). Fix: `task.defer` the wiring off the
   sim timeline. Law added to CLAUDE.md next to the no-yield rule.
   Verified: crate trip releases in 0.218 s, console clean.
2. **Pelvis-mode get-up pinned because getUpAssist oriented by the GHOST
   HRP's frame** — after a ragdoll the ghost is spun arbitrarily on the
   socket, so the "upright" pivot could land the body sideways/tangled.
   Now the PELVIS is the reference and the pivot places the PELVIS at the
   target (delta transform). Also: PelvisDrive ignores input (drive + yaw)
   unless FS == "up" — driving a half-risen body dragged/wedged it.
   Verified: two consecutive pelvis knockdown cycles, both **fell 0.05 s /
   stable stand 3.15 s** — faster and now perfectly repeatable (was 4.6 s
   with occasional pin).
**Next: 2-client netsim A/B (observing-client readability) → pivot decision
→ if pelvis wins, docs update (00_ENGINE_FACTS locomotion section, CLAUDE.md
scope line) and the capsule path becomes legacy.**

---

## 2026-07-15 — ✅ GATE 2 PASSED — and the architecture pivoted

User ran the full pass (feel + 2-client netsim): **"Good to go, testing
complete no issues."** Gate items: walks/runs no jitter ✓ (pelvis mode);
sprint-into-wall stumbles/falls ✓; stairs ✓ (user pass; single-ray hover —
expect Phase 3 polish); balance-knob-eases-knockdown ✓ (verified on the
capsule BT ladder; pelvis equivalent is tone/UP_*); observing client clean ✓.

**Pivot made official at this gate:** PelvisMode defaults ON at spawn
(seeded in MuscleServer sim step); CLAUDE.md scope line and
00_ENGINE_FACTS § 2 updated; the CCL capsule is the legacy A/B toggle and
input conduit. Recv-KB/s number + list_roblox_studios check carry to Gate 3.

**Verdict:** gate closed, pelvis-driven is the architecture, Phase 3 builds
the state machine on it.

**Verdict:** kept — awaiting user feel pass (turn feel is user-tunable now via
the TurnSpeed slider; report the value that feels right)
**Observing-client check:** NOT RUN — Gate 2 items

---

## ADDENDUM 8 — 15 JUL (night), Phase 3 session 2: the clip was invisible to its own actor

**User report after the look pass:** walking "super jittery… like we're only
walking with our right leg, the left leg stays to the rear up in the air";
getup "sometimes stiff… pinned at the hips and just rotating up… limbs pull
into regular idle pos's… sometimes it's like we get hit again."

**Instrumented live (fire-and-forget samplers in both DMs, thrown-crate
knockdowns, force-write probes). Findings, in discovery order:**

1. **Server clip was perfect; the client never saw it.** During getup the
   server's joint targets tracked the authored keys exactly; the client's sat
   at IDENTITY the whole clip. The actor's screen = client sim → muscles at
   ramping tone pulling limbs to the neutral pose while hover lifts =
   literally "limbs pull to regular spots, go stiff, rotate up".
2. **Force-write experiments** (60° into LeftHip.Transform every frame during
   getup, read back at Heartbeat): client PreSimulation write → 0. Client
   BindToSimulation write → 0. Even with humanoid Running (tracks playing),
   the idle values won. On the server, disabling FallingDown let idle KEEP
   playing through a getup — and the idle track ate the clip THERE too (body
   popped up straight-legged in 0.6 s). Full law → 00_ENGINE_FACTS §1
   "TRANSFORM OWNERSHIP UNDER SA".
3. **The walking bug is the humanoid state machine.** FallingDown (engine
   trip state, fired by the platform ability scripts via ChangeState —
   SetStateEnabled is bypassed and the state REPLICATES) stops every
   animation track; the flapping in/out after falls = jittery gait + the
   stock fall pose (one leg trailing up behind). A clean gentle walk sampled
   Running + walk/run blend the whole way — contamination is post-fall.
4. **The "hit again mid-getup" read**: between failed rise attempts the tone
   cut released hover+spring momentum ballistically — probe caught the pelvis
   at standing height, INVERTED, at tone 0.
5. Two more laws for the book: client SetAttribute on the character is
   reverted by server sync within a frame (a live limp-prototype via MJ_
   attrs silently never applied); LogService:GetLogHistory() returns empty in
   both play DMs — hook LogService.MessageOut / ScriptContext.Error live
   instead.

**Fix set (commit this session):**
- `PoseDriver`: clip writes SERVER-ONLY; server stops all playing tracks
  every step while FS ∈ {down, getup} (Stop(0.1)) — determinism instead of
  the FallingDown accident. Flail (IKControl) untouched — engine-applied,
  works on every peer.
- `MuscleSystem.step`: on the CLIENT, getup ⇒ legF/armF/spineF = 0 (limp).
  The actor reads their own rise as replicated physics — the same channel
  that already made the down phase and every observer's view read clean.
  (Down needed nothing: MT is already 0 there, which is WHY it always looked
  right.)
- `MuscleServer`: rise-fail transition bleeds pelvis velocity (×0.3
  horizontal, Y clamped ≤0, angular ×0.3); per-step while FS
  upright/stumble: humanoid FallingDown/GettingUp/Ragdoll → ChangeState
  Running via task.defer (state writes are wiring — off the sim timeline).
- Docs: ENGINE_FACTS §1 new ☠️ block (the four sub-laws above).

**Open questions for the retest:** does the limp-follow getup read organic on
the actor's screen in solo (expected: yes at 0 latency — it IS the server
pose) and at 150 ms netsim (expected: slightly delayed but coherent; the
actor has no control during getup anyway)? Does track-stopping fight the
platform animate script visibly on recovery (idle should resume on the
Running events)?

**Retest (same night, instrumented solo — crate knockdowns, dual-DM samplers):**
- **Actor's-eye getup FIXED.** Client AS = 0 through the whole down+getup; the
  client hip now arcs organically through the push (37→73→87° following the
  server's clip-driven body) instead of pulling straight to identity. Stands
  on attempt 1–3; transitions between failed attempts read as a buckle-and-
  collapse (no launch, no inversion) after widening the velocity bleed to
  EVERY part — under AJU each body part is its OWN assembly; a pelvis-only
  bleed let the other 14 parts yank it right back up.
- `track:Stop(0)` not `Stop(0.1)`: a fading track still owns Transform while
  it dies and idle ate clip frames through the fade when the platform flipped
  the humanoid to Running mid-getup.
- **Post-fall walking verified clean** (keyboard burst): speed 15–16, full
  gait swing both legs, humanoid pinned Running, no fall-anim contamination.
- **Watch items (cosmetic, user should eyeball):** (1) after recovery the
  idle track sits at partial weight (~0.4 vs 1.0 fresh-spawn) so the standing
  pose reads slightly straighter-legged until the next movement; gait itself
  fully normal. (2) GT attr stays stale between falls (harmless, writes are
  FS-gated). (3) `script_grep` can lag `script_read` after rapid file edits —
  trust script_read when they disagree.

## ADDENDUM 9 — 15 JUL (late night): the "possessed" getup → IK plant redesign

**User report on the Addendum-8 build:** "spasms… looks like he's being
possessed, goes crazy and eventually gets to the standing position."

**Metric built for this hunt** (the whip meter): per-Heartbeat displacement of
LeftHand/RightFoot while FS == getup; a frame is a "whip" above 0.35 studs
(legit rise motion ≈ 0.05–0.15). All rounds: thrown-crate knockdowns, Studio
solo (RTT ≈ 0 — every number below gets WORSE with real latency).

| build | client mean | client whips | notes |
|---|---|---|---|
| clip + limp client (Add. 8) | 0.897 | 65 % | the user's spasm |
| + client tone floor 0.3 | 0.519 | 42 % | attr A/B |
| + client tone floor 0.6 | 0.359 | 36 % | best mitigation |
| + SetPredictionMode Off (client) | 0.713 | 56 % | no effect |
| + SetPredictionMode Off (server, per-part) | 0.771 | 53 % | no effect |
| **IK plant getup (this commit)** | **0.428** | **34.7 %** | motion now MEANS something |
| server truth (clip build) | 0.162 | 14.5 % | what observers see |
| server truth (IK build) | 0.249 | 21.5 % | livelier — muscles strain at plants |

Client/server motion ratio: 5.5× (limp) → **1.7× (IK)** — the correction war
is mostly gone; what remains on the actor's screen is largely real physics.

**Why every mitigation failed** (all laws in ENGINE_FACTS §1, verified live):
client Transform writes never survive; runtime AnimationTracks are zombies on
both peers (the SA "[AnimRepl]" Animate module owns all playback from rollback
state attributes, NUMERIC asset ids only — temp-registered clips can never
ride it); SetPredictionMode(Off) has no observable effect on the local
character; tone floors only damp the whip, they can't remove the divergence.
The spasm mechanism: at tone 0 the QUADRATIC ceiling is 0, so limp joints have
no damping authority and SA corrections whip free-swinging parts every frame.

**The fix — matched targets + matched impedance:** IKControl is the ONE
target channel the engine applies on every peer (verified: client shoulder
target 82°, hand 0.5 studs from goal, vs Transform writes reading back 0).
The getup is now IK PLANT CHOREOGRAPHY (PoseDriver): GetupHandL/R (UpperArm→
Hand) plant on the ground beside the hips, GetupFootL/R (UpperLeg→Foot) plant
under the body — ground-anchored world targets computed identically on both
peers from GT/GF + the pelvis frame + a per-peer raycast. Weights slew at 6/s;
hands release at 75 % progress, feet at 97 %. The joint-space keyframe clip is
DELETED (git history @ c75f542 keeps it); GetupPose is now just the shared
clock (GT), the server-latched face flag (GF, set at the rise moment), and
progress(). Both peers run the full tone schedule again (no client limp, no
CGF knob). The BUCKLE is untouched: muscles still physically strain toward
the plants through the tone² ceiling (measured: hand 1.43 studs short of its
plant mid-rise at full tone — Layer 2 doing real work).

**IK plant values (first pass, all in PoseDriver CONFIG):** HAND_SIDE 0.85 ·
HAND_BACK 0.25 (behind pelvis face-up, ahead face-down) · FOOT_SIDE 0.35 ·
FOOT_FWD 0.55 (×0.4 face-down) · LIFT 0.12 · WEIGHT_RATE 6 · SMOOTH 0.1 ·
HANDS_OFF 0.75 · FEET_OFF 0.97 · RAY 6.

**Open items:** user eyes-test (both orientations — this session's crate
rounds landed face-down every time, GF=false; face-up path is code-shared but
unwatched); rise reliability unchanged (2–3 attempts typical); the arms may
read "reachy" instead of "pushy" (Position IK doesn't know about pressing —
tune HAND_BACK/HANDS_OFF first); netsim numbers at 150 ms still unknown.

**Addendum 9 · v2 choreography (same night, user eyes-test verdict on v1):**
"back bridge" face-up, "downward dog, driving with its head" face-down,
1+ retries, spasm-ish final catch. All three are v1 plant geometry, not IK
failure: feet planted AHEAD of a rising pelvis have exactly one kinematic
solution (bridge); hands beside the HIPS of a prone body push the hips up
first (downward dog). v2:
- Plant axes now keyed off the lying body's HEAD-WARD direction = pelvis UP
  projected flat (the spine line). The look vector points into/out of the
  ground on a lying body and lies about facing — that was half of v1's sin.
- FACE-UP: hands ±0.8 beside / 0.10 butt-ward of the hips; feet TUCKED
  0.30 butt-ward at ±0.35 — rise over tucked feet = sit-up → squat.
  Hands off at 65 %.
- FACE-DOWN: hands ±0.5 at 0.95 HEAD-ward (under the shoulders — press-up);
  feet start 0.45 behind, knees drag under to 0.15 across 20–60 % of the
  clip. Hands off at 85 % (the press carries longer).
- Both: foot offsets ease to directly under the pelvis across 65–95 %.
- CLIP_TIME 1.6 → 2.0 (phases were crowded); riseTimeout 2.2 → 2.6 keeps the
  0.6 s post-clip grace.
Untested by instrument (user was already in a play session) — user verdict
pending on: bridge gone? press-up reads? retry count down?

**Addendum 9 · v2 verdicts + terminal-pop fix (user: "doesn't do the retry
thing anymore but still has kind of the quick get into place after it pushes
for a bit"):** retries FIXED by the v2 choreography. The terminal pop was the
end-of-clip pile-up: the p² hover curve ends at MAX slope right as the plants
release and full-tone muscles snap to idle. Two-value fix:
- hover height curve p² → **p³(4−3p)** (PelvisDrive): still low early
  (0.08 vs 0.09 at p=0.3), near-zero slope at the end — the rise SETTLES.
- spine tone ease 0.3–0.75 → **0.35–0.9** (MuscleSystem): the straighten is
  the spine unfurling through the clip tail, not snapping before it ends.
Sanity crate after the change: ONE attempt, hit→standing 3.7 s, height
settles 2.88→2.83. riseTimeout 2.6 / CLIP_TIME 2.0 confirmed compatible.

## ADDENDUM 10 — 15 JUL (late): Gate 3 run #1 — stand-on-him FAILED → hover weight transfer

**User's 2-client run:** falls/stumbles/getups read well on the observing
client ("works well with the two clients"); RC 0.4 buckle reads correctly
(tries and buckles). **Stand-on-him FAILED: the downed player got up with a
player standing on him.** Root cause is structural, not tuning: the pelvis
hover is a VIRTUAL leg — it carries a character with an external VectorForce
instead of pressing through the feet, so a hovering character weighs almost
NOTHING on whatever is under him. B's weight never reached A's body.

**Fix (PelvisDrive):** the hover support force now applies its reaction —
`ApplyImpulseAtPosition(-support·dt)` at the ray hit, server-only, skipped
for anchored parts/terrain (no-op there anyway). Verified by instrument:
identical plates given identical 12-stud/s kicks, the one under a hovering
character slid 0.41× the control's distance (friction from the transferred
normal force). Static-margin math for the retest: A's getup support cap is
1.8 g × 20 mass ≈ 36 units of lift vs A's own 20 + B's transferred ~20 = 40
pressing down — A should stay pinned, and rise when B steps off.

**Emergent side effect (intended, watch it):** characters now press down on
PROPS they stand on — loose crates tip/shoot underfoot. That is Sub Rosa
physicality, but it changes any test that involved standing on objects.

**Bookkeeping:** the multi-client test instances do NOT register with the MCP
(`list_roblox_studios` shows only the editing Studio — 04_PREFLIGHT §2 now
answered); the recv KB/s number therefore comes from the DebugPanel line
("recv: N KB/s", already on screen) during the user's run — READ IT ALOUD at
the retest. Gate 3 remains OPEN pending: stand-on-him retest + recv KB/s.

## ADDENDUM 11 — 15 JUL (later): intermittent retry + late-rise leg spasm — two mechanisms, both fixed

**User report post-weight-transfer:** "sometimes collapses and retries,
sometimes while getting up it gets jittery/spazs out a bit." Both traced to
code, not tuning:

1. **Plant releases SNAPPED.** PoseDriver's `hands = gWeight * handsWant`
   zeroed a plant's IK weight in ONE frame at its off-mark (the slew only
   applied on the way in — the comment lied). For a face-down body the hand
   release (85 %) lands at the SAME moment clipDone starts judging (1.7 s),
   and the judgment was a SINGLE-FRAME upY read: one release jolt under
   tiltUp scrapped a succeeding rise → retry, intermittently.
2. **The head-ward axis was recomputed live and REVERSES mid-rise.** As a
   face-up body sits up, facing genuinely flips 180° relative to the lying
   spine line; the up-projection→look-projection threshold switch (0.15)
   flickered the axis frame-to-frame near vertical, teleporting foot targets
   ±0.6 studs → the late-rise leg spasm. (Face-down rises are continuous
   through the switch — why the spasm was intermittent.)

**Fixes (all live-verified):**
- **GA attribute**: the server latches the head-ward axis ONCE at the rise
  moment (same latch as GF, `GetupPose.headAxis`); every peer's plants anchor
  to one ground frame for the whole rise. Plants no longer swivel with pelvis
  wobble — they are genuinely ground-anchored now.
- **PoseDriver GETUP_RELEASE_RATE 3** (engage stays 6): hands and feet slew
  independently, both directions. Max per-frame weight step measured 0.096
  (was 1.0 — the snap).
- **MuscleSystem FALL.failHold 0.2**: the clipDone fast-fail needs upY under
  tiltUp for 0.2 s CONTINUOUSLY (MuscleServer st.lowHold). Successful rises
  hold ≥ 0.94; genuine failures lie low far longer.

**Instrument run (solo, 7 crate knockdowns, 4 directions):** 7/7 single-
attempt rises, 0 retries, 0 assists. Server getup whip 6.8 % (was 21.5 %);
ACTOR-SCREEN (client) whip 18.2 % (was 34.7 %), one 3.5-stud correction
spike remains. minUpAfterDone 0.98 — posture rock-solid through the judged
window. Console clean. Residual client whip is SA correction noise — that is
the deferred post-gate netsim smoothing pass, not these mechanisms.

## ADDENDUM 12 — 15 JUL (night): "jumping up" + residual spasm — the stock recover ability was the jump

**User report:** "Limbs still kind of spasm and we get up really quick, feels
more like we're jumping up." Instrumented autopsy (states + tracks + pelvis
height profile per getup):

**THE JUMP MECHANISM (caught live):** the platform's stock recover ability
owns a ~3 s FallingDown→GettingUp timer that runs from the KNOCKDOWN — it
fires GettingUp→Running at ~GT 1.4, MID-getup, and the SA animate module
starts walk/run/idle tracks. Every joint snaps toward the locomotion pose at
near-full tone while the feet are still planted: pelvis 1.89→3.59 in 0.3 s,
0.76 studs ABOVE standing height, peakVy 10.5. The rise was never our hover
curve — the curve was irrelevant once the pose snapped to standing.

**Dead ends measured before the fix (do not retry):**
- ChangeState wars are UNWINNABLE: per-step forcing of Physics flapped
  Physics↔FallingDown every single step (the ability manager re-asserts on
  its own rollback clock) and ADDED track-restart strobing. Removed.
- Disabling the FallingDown ability kills the FALL itself: the capsule never
  releases, a knocked-down body hangs at pelvisY 2.8 (its activation — not
  our StandForce/balance zeroing — is what actually releases the capsule
  under SA). It must STAY enabled.
- NoLocomotion ability (Active=true sticks when the server writes it) gates
  movement only — idle track kept playing at weight 1. Not an anim switch.

**THE FIX SET (all four required):**
1. **GettingUp ability disabled** (SyncedState Enabled=false, server, once
   per character in MuscleServer): the recover timer can never flip the
   state mid-getup. Verified: zero locomotion tracks during down/getup
   (only the Freefall "fall" clip during the tumble). Our existing
   upright/stumble block already forces Running back after the stand.
2. With tracks dead the rise went HONEST and stalled at ~50° (3 straight
   watchdog fails): nothing told the body to STAND — joints strove toward
   the stale pre-fall pose (Transform writes are client-placebo, ENGINE
   FACTS §1). **GetupHead IK** (5th control, LowerTorso→Head = Waist+Neck,
   PoseDriver): head target climbs from a curled lean to standing head
   height (HEAD_H 1.6→4.35, ease 0.25–0.95, lean 0.5 toward the stand
   direction — which is MINUS the lying head-ward axis for face-up bodies).
   Standing intent through the one legal cross-peer channel; weight rides
   the foot schedule.
3. **PelvisDrive RISE_UP_BOOST 2** — upright-TORQUE-only rise assist.
   Never boost support: the RC buckle and the stand-on-him pin both live in
   the vertical force margin.
4. **Root muscle neutralized during getup (rootF 0.15, MuscleSystem)**: the
   ghost HRP lies where it fell until AFTER the rise, so Root strove toward
   a stale pose relative to a tumbled frame at the tone² ceiling and fought
   the pelvis spring — the intermittent stalls (3/10 retries measured with
   fixes 1–3 only). Retro-explains the old "success": the mid-clip Running
   restart re-righted the capsule and the ROOT MUSCLE yanked the body up in
   0.2 s — the jump WAS the Root muscle. The pelvis belongs to the
   spring + hover during a rise.
5. Feel: CLIP_TIME 2.0→2.4 (riseTimeout 2.6→3.0 keeps the 0.6 s grace),
   GETUP_WEIGHT_RATE 6→3.5 (plant engage read as the body gathering, not a
   yank — hands whipped 1.0–1.6 studs/frame at GT 0.1–0.3 at rate 6),
   GETUP_SMOOTH 0.1→0.15.

**Verification state:** fixes 1–3 measured live (tracks NONE, heights track
the hover curve with no overshoot, server whip 4.3%); fix 4 (rootF) synced
and play-tested but the MCP bridge dropped mid-battery — final retry-rate and
client-whip numbers pending next session. If retries persist, next levers:
RISE_UP_BOOST 2→3, rootF 0.15→0.05, head-IK lean up.
