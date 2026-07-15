--!strict
-- Layer 2 · MUSCLE. One solve, both peers. Drivers are attributes (replicated intent);
-- this module turns them into AngularStrength / AngularDamping / MaxTorque writes every
-- simulation step. Runs inside BindToSimulation — no yields, no GUI, no remotes in here.
--
-- The 45 per-joint drivers live in 15 packed string attributes, one triple per joint
-- ("MJ_Waist" = "1,1.25,3000"). Both attribute limits are real and verified live
-- (2026-07-14): 1024 bytes TOTAL payload per instance AND every string value < 50
-- chars. 46 separate attributes bust the first; one big packed string busts the
-- second. Per-joint triples fit both. Strings re-parse only when they change.

local CONFIG = {
	MASTER_TONE_ATTR = "MT",
	POWERED_ATTR = "Powered",
	-- balance ceiling as a live attribute (Gate 2: lowering it must measurably ease
	-- knockdowns). Falls back to BALANCE_TORQUE when unseeded.
	BALANCE_ATTR = "BT",
	JOINT_ATTR_PREFIX = "MJ_",
	-- master tone below this releases CCL balance so the body can actually heap
	COLLAPSE_BALANCE_THRESHOLD = 0.1,
	-- stability guard trip-wires. These catch EXPLOSIONS (NaN, compounding
	-- runaway), not lively ragdolls: an ordinary user flop spun a foot at 516
	-- and a hand at 333 rad/s (captured live), tripped the old 250, and the
	-- mid-fall reset was the door into the frozen-pin deadlock.
	RUNAWAY_LINEAR = 512,
	RUNAWAY_ANGULAR = 800,
	-- impact reflex: the ball socket decouples body hits from the capsule, so passive
	-- knockdowns don't exist — balance must DIP when the body takes a hit. Body-part
	-- speed relative to the root above `threshold` dips balance torque linearly,
	-- reaching zero (a guaranteed fall) at `fallAt`. Proportionality lives here.
	-- threshold 25: getup/recovery motions reach ~20 rel and must NOT re-trigger —
	-- an 18 threshold made the reflex sabotage its own recoveries (perpetual stumble
	-- cycle, verified live). Also upright-gated in noteImpact for the same reason.
	-- rearm: after any firing the reflex is locked out until the window fully expires
	-- (stagger + rearm) — without it, crossing back over the upright gate while still
	-- moving fast re-triggers the dip and the body struggles at the boundary forever.
	IMPACT = {
		threshold = 25, fallAt = 55, staggerTime = 0.6, uprightGate = 0.7, rearm = 2.0,
		-- self-motion gates: a fast 180° turn swings the body around the capsule at
		-- up to ~53 stud/s relative (measured live — far MORE than a hard crate
		-- hit), and the swing PEAKS just after the turn ends, exactly when the
		-- instantaneous gates re-open. So: while turning hard the channel is deaf,
		-- and it STAYS deaf for turnCooldown afterwards. The speed-EMA gate covers
		-- straight-line launch/brake transients the same way.
		selfOmega = 3, selfAccel = 250, selfSpeedDelta = 10, turnCooldown = 0.4,
		-- animated limb swing scales with ground speed: a sprint foot-plant
		-- whip hits rel ~40 LEGITIMATELY (the dip escalation unmasked it —
		-- random falls while running, user-reported). The hit line rides the
		-- swing envelope; severity width stays constant so real hits map the
		-- same. Sprint 25.5 → line at ~42.9, observed sprint peak 40.7.
		swingPerSpeed = 0.7,
		-- ☠️ measured: sprint STRAFES whip the body to rel ~70 — no threshold
		-- can separate self-motion from hits at speed. Structural gate
		-- instead: the body-rel channel (and the trip detector) may only fire
		-- within contactWindow of a FOREIGN touch on a non-leg body part.
		-- External falls require external contact; open-field sprinting is
		-- immune BY CONSTRUCTION. Walls (capsule decel) and true capsule tilt
		-- remain contact-free evidence.
		contactWindow = 0.5,
		-- fully deaf while Rising and for riseGrace after: the get-up swings body
		-- parts far past every threshold, and a reflex that fires on the recovery
		-- knocks the body straight back down (verified live — rise→fall loop)
		riseGrace = 1.0,
		-- a dip this deep is a KNOCKDOWN: the server triggers the fall reflex
		-- (tone crash → crumple → limp → rise). Balance dip alone can NEVER
		-- topple the capsule on a wall hit — the Root socket absorbs the body's
		-- momentum and the wall blocks the tip (verified live at 41 stud/s,
		-- balance 55: capsule stood like a statue). Readability comes from tone.
		-- This is ALSO the stagger floor (updateBalance): a dip that stays above
		-- it is clamped to it, so balance never collapses on a body that stays
		-- standing. The near-zero-balance-while-standing middle band read as
		-- "limbs ragdolled but hips pinned, still walkable" (user feedback) —
		-- now you either wobble readably or you actually go down.
		knockdownFactor = 0.45,
	},
	-- wall channel: a wall hit stops the CAPSULE, and the body stops with it —
	-- body-rel speed stays near zero, so the impact reflex above never sees it
	-- (verified live: sprint into wall = 26→0 in one step, up=1.00, no reaction).
	-- The signal is horizontal capsule deceleration: ~1500 stud/s² on a wall hit
	-- vs ~130 for a DecelerationTime-smoothed stop. Dip severity scales with the
	-- speed thrown away: walking into a wall (16) is nothing, sprinting (25.6) is
	-- a real stagger.
	-- speedMin 17 / speedFallAt 22: with knockdownFactor 0.45 the knockdown
	-- starts at ~20 stud/s. The old 18–26 band left mid-speed wall hits as
	-- deep staggers — body slumped against the wall, hips held at standing
	-- height, walkable: the user's recurring "pinned into the wall by the
	-- hips". Walls are binary now: a walk-speed bump (16) is nothing, a brisk
	-- jog (≥20) or sprint puts you DOWN.
	WALL = { accelMin = 400, speedMin = 17, speedFallAt = 22 },
	-- the capsule brakes/launches instantly by default; the heavy body keeps its
	-- momentum and whips on every transition (user feedback). Symmetric smoothing
	-- removes the whip AND keeps normal stops out of the wall channel.
	ACCEL_TIME = 0.2,
	DECEL_TIME = 0.2,
	-- fall reflex (Phase 3 seed): a body that is going down goes LIMP — tone slews
	-- toward `tone` while tilted past `tiltUp`, held for `downTime`, then restores
	-- (which is also what lifts him back up). This is what makes falls ragdoll.
	-- riseBoost: balance is multiplied while getting up (set via the "Rising"
	-- attribute) — without it the rise half-completes, topples, re-limps, forever.
	-- riseHold: must stay upright this long before the fall trigger re-arms.
	-- tone 0.08, deliberately BELOW COLLAPSE_BALANCE_THRESHOLD (0.1): during the
	-- limp window the capsule must give up too, or an upright knockdown (wall
	-- crash) leaves him slumped-but-standing at balance 120 (verified live).
	-- riseHold 1.5: with the capsule now truly falling, rises wobble — 0.5 s of
	-- upright re-armed the tilt trigger mid-wobble and re-felled him (verified).
	-- riseRamp: while Rising, tone ramps fast (the capsule was just righted with
	-- velocities zeroed, so joint-space error is rotation, not stretch — the
	-- slingshot hazard needs a stretched constraint); at the normal 1.5/s the
	-- limp body yanks the righted capsule back down before tone arrives.
	-- riseTimeout/retryDown: a failed rise must retry the whole down-and-right
	-- cycle, or a bad landing deadlocks lying at full tone (verified).
	FALL = {
		-- tiltUp 0.65: at 0.55 the trigger waited until ~56° — the body read as
		-- fully going over while the capsule stayed pinned (user: "still pins
		-- briefly"). Successful rises hold upY ≥ 0.94 (telemetry), so 0.65 does
		-- not false-fail them.
		tiltUp = 0.65, tone = 0.08, downTime = 1.6, riseUp = 0.85, riseHold = 1.5,
		-- riseRamp 4: at 6 the legs snap to full power while the feet catch the
		-- ground and the rise becomes an 8-stud hop (verified live)
		riseBoost = 4, riseRamp = 4, riseTimeout = 2.0, retryDown = 0.8,
		-- committed-topple trigger: tilted past tipUp AND tipping faster than
		-- tipRate (rad/s, horizontal axes) = it is going over NOW. Both gates
		-- together cannot false-fire on AccelerationLean or normal wobble.
		-- NOTE: under balance the capsule is orientation-LOCKED (verified: a
		-- driven 2 rad/s spin for 1.5 s left up at 1.00) — so this only
		-- catches capsules that physically lose the lock (sensor lost, etc).
		tipUp = 0.9, tipRate = 1.5,
		-- torso-divergence trigger — THE trip detector. In a real trip the
		-- capsule never tips (see above); the BODY folds over the obstacle
		-- while the hips hang from a gyroscope, and the reflex only noticed
		-- ~0.5 s later (user-reported "pins then falls"). Torso up-vector
		-- below torsoDiverge for torsoTime = the muscles have lost the pose;
		-- the human is falling, whatever the capsule thinks. Walk/sprint
		-- torso pitch stays above ~0.9; stop-whips are shorter than
		-- torsoTime.
		torsoDiverge = 0.55, torsoTime = 0.1,
		-- stranded catch-all: a body down this long triggers the fall cycle
		-- regardless of arming. NO reachable state may lie powered on the
		-- ground — the frozen pin (lying at full tone, disarmed, forever) the
		-- recorder caught got in through a guard reset mid-fall; this makes
		-- the entire class self-healing instead of chasing each door.
		strandedDown = 0.75,
	},
	RISING_ATTR = "Rising",
	-- server-mirrored fall-machine state ("up"/"down"/"rising") so client-side
	-- instruments (fall recorder) can see what the server THINKS it's doing
	STATE_ATTR = "FS",
	-- capsule feel knobs, live-tunable attributes (user feedback: stock turn speed 16
	-- reads as pivoting an invisible core — the body never swings through a turn)
	TURN_ATTR = "TS",
	LEAN_ATTR = "AL",
	TURN_SPEED = 8, -- cm.BaseTurnSpeed; stock 16
	ACCEL_LEAN = 1, -- gc.AccelerationLean; stock 1
	-- hover ladder knob: how much of the body's weight the capsule carries.
	-- Standing holds at 0 with full tone (verified — the LEGS hold the capsule
	-- through the Root socket), so this is the experiment lane toward
	-- leg-supported locomotion: lower it, walk, find where it breaks.
	STAND_ATTR = "SF",
	STAND_FORCE = 10000,
	-- per-joint driver defaults {strength, damping, torque}. Baseline = AJU factory
	-- values (tuning log 2026-07-14). Root-ward joints get extra damping per the official
	-- anti-oscillation recipe: they don't "see" downstream chain mass.
	DEFAULTS = {
		Root = { 1.0, 1.25, 3000 },
		Waist = { 1.0, 1.25, 3000 },
		Neck = { 1.0, 1.0, 3000 },
		-- arms carry no load, so they can afford to be loose: lower strength gives
		-- them natural lag and swing instead of rigid pose-tracking (user feedback)
		LeftShoulder = { 0.65, 1.0, 3000 },
		LeftElbow = { 0.65, 1.0, 3000 },
		LeftWrist = { 0.5, 1.0, 3000 },
		RightShoulder = { 0.65, 1.0, 3000 },
		RightElbow = { 0.65, 1.0, 3000 },
		RightWrist = { 0.5, 1.0, 3000 },
		LeftHip = { 1.0, 1.25, 3000 },
		LeftKnee = { 1.0, 1.0, 3000 },
		LeftAnkle = { 1.0, 1.0, 3000 },
		RightHip = { 1.0, 1.25, 3000 },
		RightKnee = { 1.0, 1.0, 3000 },
		RightAnkle = { 1.0, 1.0, 3000 },
	} :: { [string]: { number } },
	-- clamps for the debug-remote write path (untrusted input)
	LIMITS = { s = { 0, 4 }, d = { 0, 8 }, t = { 0, 1e7 } } :: { [string]: { number } },
	-- Compliant balance ceiling. Scaled by tone: weak body = easy to topple. Rigid
	-- balance is FORBIDDEN on a powered body — it injects hard reaction impulses
	-- through the Root socket every solver step (verified live: perpetual flail).
	-- Baseline balance. Stand is solid all the way down to 300; passive knockdowns
	-- never happen at ANY value (the Root socket decouples body hits from the
	-- capsule) — falls come from the impact reflex dipping this, not from lowering it.
	BALANCE_TORQUE = 800,
	-- Human-ish mass distribution at chain ≈ 18.5 vs HRP 2.0. Stand quality is
	-- IDENTICAL to the near-massless rig (strength is frequency-normalized, gains
	-- track mass automatically) but hits now transfer real momentum.
	DENSITY = {
		LowerTorso = 12, UpperTorso = 10, Head = 7,
		LeftUpperLeg = 10, RightUpperLeg = 10, LeftLowerLeg = 7, RightLowerLeg = 7,
		LeftFoot = 6, RightFoot = 6,
		LeftUpperArm = 6, RightUpperArm = 6, LeftLowerArm = 4, RightLowerArm = 4,
		LeftHand = 3, RightHand = 3,
	} :: { [string]: number },
}

export type JointMap = { [string]: AnimationConstraint }
export type JointValues = { [string]: { number } } -- { joint: {strength, damping, torque} }

local MuscleSystem = {}
MuscleSystem.CONFIG = CONFIG
MuscleSystem.lastBalanceError = nil :: string?

MuscleSystem.JOINTS = {
	"Root", "Waist", "Neck",
	"LeftShoulder", "LeftElbow", "LeftWrist",
	"RightShoulder", "RightElbow", "RightWrist",
	"LeftHip", "LeftKnee", "LeftAnkle",
	"RightHip", "RightKnee", "RightAnkle",
}

-- weak keys so despawned rigs drop out of the caches
local jointCache: { [Model]: JointMap } = setmetatable({}, { __mode = "k" }) :: any
local valueCache: { [Model]: { strs: { [string]: string }, values: JointValues } } = setmetatable({}, { __mode = "k" }) :: any

function MuscleSystem.fieldKey(joint: string, field: string): string
	return "M_" .. joint .. "_" .. field
end

function MuscleSystem.isValidAttr(key: string): boolean
	if
		key == CONFIG.MASTER_TONE_ATTR
		or key == CONFIG.BALANCE_ATTR
		or key == CONFIG.TURN_ATTR
		or key == CONFIG.LEAN_ATTR
		or key == CONFIG.STAND_ATTR
	then
		return true
	end
	local joint, field = key:match("^M_(%a+)_([sdt])$")
	return joint ~= nil and field ~= nil and CONFIG.DEFAULTS[joint :: string] ~= nil
end

function MuscleSystem.clampAttr(key: string, value: number): number
	if key == CONFIG.MASTER_TONE_ATTR then
		return math.clamp(value, 0, 1)
	end
	if key == CONFIG.BALANCE_ATTR then
		return math.clamp(value, 0, 20000)
	end
	if key == CONFIG.TURN_ATTR then
		return math.clamp(value, 0, 40)
	end
	if key == CONFIG.LEAN_ATTR then
		return math.clamp(value, 0, 4)
	end
	if key == CONFIG.STAND_ATTR then
		return math.clamp(value, 0, 20000)
	end
	local lim = CONFIG.LIMITS[key:sub(-1)]
	return math.clamp(value, lim[1], lim[2])
end

local function defaultsCopy(): JointValues
	local t: JointValues = {}
	for j, def in CONFIG.DEFAULTS do
		t[j] = { def[1], def[2], def[3] }
	end
	return t
end

function MuscleSystem.jointAttr(joint: string): string
	return CONFIG.JOINT_ATTR_PREFIX .. joint
end

function MuscleSystem.packTriple(v: { number }): string
	return ("%.4g,%.4g,%.4g"):format(v[1], v[2], v[3])
end

function MuscleSystem.unpackTriple(str: string): { number }?
	local a, b, c = str:match("^([^,]+),([^,]+),([^,]+)$")
	local s, d, t = tonumber(a), tonumber(b), tonumber(c)
	if s and d and t then
		return { s, d, t }
	end
	return nil
end

-- both peers: current joint drivers. Each joint's triple re-parses only when its
-- attribute string changes; unseeded joints fall back to DEFAULTS (read-only!).
function MuscleSystem.getValues(character: Model): JointValues
	local c = valueCache[character]
	if not c then
		c = { strs = {}, values = defaultsCopy() }
		valueCache[character] = c
	end
	for _, j in MuscleSystem.JOINTS do
		local str = character:GetAttribute(MuscleSystem.jointAttr(j))
		if type(str) == "string" and c.strs[j] ~= str then
			c.strs[j] = str
			local triple = MuscleSystem.unpackTriple(str)
			if triple then
				c.values[j] = triple
			end
		end
	end
	return c.values
end

function MuscleSystem.getJoints(character: Model): (JointMap?, number)
	local cached = jointCache[character]
	if cached then
		return cached, #MuscleSystem.JOINTS
	end
	local found: JointMap = {}
	local n = 0
	for _, name in MuscleSystem.JOINTS do
		local j = character:FindFirstChild(name, true)
		if j and j:IsA("AnimationConstraint") then
			found[name] = j
			n += 1
		end
	end
	if n == #MuscleSystem.JOINTS then
		jointCache[character] = found
		return found, n
	end
	return nil, n
end

-- server, inside sim: seed the driver attributes so both peers solve from real data
function MuscleSystem.ensureDefaults(character: Model)
	if character:GetAttribute(CONFIG.MASTER_TONE_ATTR) == nil then
		character:SetAttribute(CONFIG.MASTER_TONE_ATTR, 1)
	end
	if character:GetAttribute(CONFIG.BALANCE_ATTR) == nil then
		character:SetAttribute(CONFIG.BALANCE_ATTR, CONFIG.BALANCE_TORQUE)
	end
	if character:GetAttribute(CONFIG.TURN_ATTR) == nil then
		character:SetAttribute(CONFIG.TURN_ATTR, CONFIG.TURN_SPEED)
	end
	if character:GetAttribute(CONFIG.LEAN_ATTR) == nil then
		character:SetAttribute(CONFIG.LEAN_ATTR, CONFIG.ACCEL_LEAN)
	end
	if character:GetAttribute(CONFIG.STAND_ATTR) == nil then
		character:SetAttribute(CONFIG.STAND_ATTR, CONFIG.STAND_FORCE)
	end
	for _, j in MuscleSystem.JOINTS do
		local attr = MuscleSystem.jointAttr(j)
		if character:GetAttribute(attr) == nil then
			character:SetAttribute(attr, MuscleSystem.packTriple(CONFIG.DEFAULTS[j]))
		end
	end
end

-- server, inside sim: land one validated+clamped debug write
function MuscleSystem.applyDebugWrite(character: Model, key: string, value: number)
	if
		key == CONFIG.MASTER_TONE_ATTR
		or key == CONFIG.BALANCE_ATTR
		or key == CONFIG.TURN_ATTR
		or key == CONFIG.LEAN_ATTR
		or key == CONFIG.STAND_ATTR
	then
		character:SetAttribute(key, value)
		return
	end
	local joint, field = key:match("^M_(%a+)_([sdt])$")
	if not joint then
		return
	end
	local cur = MuscleSystem.getValues(character)[joint :: string]
	local triple = { cur[1], cur[2], cur[3] }
	local idx = if field == "s" then 1 elseif field == "d" then 2 else 3
	triple[idx] = value
	character:SetAttribute(MuscleSystem.jointAttr(joint :: string), MuscleSystem.packTriple(triple))
end

-- both peers, inside sim. Deterministic: reads only replicated attributes, so client
-- prediction and server truth compute identical writes and rollback stays quiet.
function MuscleSystem.step(character: Model)
	local joints = MuscleSystem.getJoints(character)
	if not joints then
		return
	end
	local powered = character:GetAttribute(CONFIG.POWERED_ATTR) == true
	local mt = tonumber(character:GetAttribute(CONFIG.MASTER_TONE_ATTR)) or 1
	local values = MuscleSystem.getValues(character)
	local wantKinematic = not powered
	for name, joint in joints do
		-- enforced every step: self-heals the known AJU stuck-joint bug and any
		-- spawn-flow property stomp (ENGINE_FACTS field reports)
		if joint.IsKinematic ~= wantKinematic then
			joint.IsKinematic = wantKinematic
		end
		if powered then
			local v = values[name]
			-- tone scales strength AND ceiling: a weak muscle both tracks slower and
			-- cannot hold weight (01_ARCHITECTURE). Damping is ζ — never tone-scaled.
			joint.AngularStrength = v[1] * mt
			joint.AngularDamping = v[2]
			joint.MaxTorque = v[3] * mt
		end
	end
end

-- one-time per character, server side. Two engine gaps found live (2026-07-14):
-- 1. AJU ships a BallSocketConstraint for 14 joints but NOT Root (HRP→LowerTorso),
--    and the linear muscle channel defaults to MaxForce=0 — a powered body silently
--    falls 2.7 studs out of the capsule. We add the missing socket; translation is
--    then solver-held exactly like the other 14 joints.
-- 2. A powered body's torso parts are world-collidable, and the CCL FloorSensor
--    senses them as ground (SensedPart = own UpperTorso) → hover feedback loop →
--    perpetual flail. The sensor casts with the root part's collision group, so
--    body parts go in CharBody, HRP in CharRoot, mutually non-collidable.
-- Returns true once complete; call again until it is.
function MuscleSystem.setupBody(character: Model): boolean
	local joints = MuscleSystem.getJoints(character)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not joints or not hrp then
		return false
	end
	if not hrp:FindFirstChild("RootBallSocket") then
		local sock = Instance.new("BallSocketConstraint")
		sock.Name = "RootBallSocket"
		sock.Attachment0 = (joints.Root :: any).Attachment0
		sock.Attachment1 = (joints.Root :: any).Attachment1
		sock.LimitsEnabled = false
		sock.Parent = hrp
	end
	for _, p in character:GetChildren() do
		if p:IsA("BasePart") then
			p.CollisionGroup = if p.Name == "HumanoidRootPart" then "CharRoot" else "CharBody"
			local density = CONFIG.DENSITY[p.Name]
			if density then
				p.CustomPhysicalProperties = PhysicalProperties.new(density, 0.35, 0.2)
			end
		end
	end
	-- the ControllerManager can arrive AFTER the joints (verified live: a session
	-- latched setupDone with AccelerationTime still 0). Not done until it's here.
	local cm = character:FindFirstChildOfClass("ControllerManager")
	local gc = cm and cm:FindFirstChildWhichIsA("GroundController", true)
	if not gc then
		return false
	end
	local ok = pcall(function()
		(gc :: any).AccelerationTime = CONFIG.ACCEL_TIME;
		(gc :: any).DecelerationTime = CONFIG.DECEL_TIME
	end)
	return ok
end

-- server, EVERY sim step: a limp body's capsule must actually GO DOWN.
-- StandForce=0 kills the hover (the legs no longer hold anything at fall tone) and
-- BaseMoveSpeed=0 kills walking-while-ragdolled. Verified live: with these released
-- the whole body heaps INCLUDING the hips (hrpY 4.8 → 1.4); without them the body
-- dangles from a hovering, walkable capsule (the "standing marionette" bug).
-- moveLock outlives released: the get-up keeps hover (the capsule assists the rise)
-- but walking mid-rise yanks the half-risen body — locked until fully re-armed.
-- Enforced per step, not at transitions, so nothing (ability state changes, resets)
-- can leave a limp body pinned to a live capsule. Writes only on change.
function MuscleSystem.setCapsuleReleased(character: Model, released: boolean, moveLock: boolean)
	local cm = character:FindFirstChildOfClass("ControllerManager")
	local gc = cm and cm:FindFirstChildWhichIsA("GroundController", true)
	if not cm or not gc then
		return
	end
	pcall(function()
		local g, m = gc :: any, cm :: any
		-- restore value comes from the SF attr (hover-ladder slider), not a constant
		local force = if released then 0 else (tonumber(character:GetAttribute(CONFIG.STAND_ATTR)) or CONFIG.STAND_FORCE)
		local speed = if released or moveLock then 0 else 16
		if g.StandForce ~= force then
			g.StandForce = force
		end
		if m.BaseMoveSpeed ~= speed then
			m.BaseMoveSpeed = speed
		end
		-- the HRP is an INVISIBLE COLLIDABLE BOX with the pelvis ball-socketed
		-- to it. Zero forces is not enough: the box physically rests on props
		-- and leans on walls, and the limp body dangles from it ("pinned mid
		-- air", caught on the recorder — released, up≈0.9, hanging at prop
		-- height for 1.3 s). While ragdolled it must be a GHOST: the heavy
		-- body (18.5 vs 2.0) drags it wherever the body heaps.
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") and hrp.CanCollide ~= not released then
			hrp.CanCollide = not released
		end
	end)
end

-- server, once at the rise moment: a capsule that fell with the body lies flat, its
-- floor sensor points sideways, and the GroundController can never right it again
-- (verified live: stuck lying with Rising=true forever). Until Phase 3's physical
-- get-up, the server rights the capsule in one pivot — velocities zeroed, yaw kept —
-- and the muscles pull the body up from there.
function MuscleSystem.getUpAssist(character: Model)
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end
	for _, part in character:GetChildren() do
		if part:IsA("BasePart") then
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
	local look = hrp.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, -1)
	-- +3.0: high enough that the sprawled limbs mostly clear the ground while the
	-- muscles yank them to pose — snagged limbs transmit >StandForce through the
	-- socket and flop the capsule back down (main first-attempt failure mode)
	local base = Vector3.new(hrp.Position.X, hrp.Position.Y + 3.0, hrp.Position.Z)
	character:PivotTo(CFrame.lookAt(base, base + flat))
end

-- CCL balance follows tone, always compliant (never rigid — see setupBody note).
-- Below the collapse threshold the capsule gives up entirely and falls with the body.
function MuscleSystem.updateBalance(character: Model)
	local cm = character:FindFirstChildOfClass("ControllerManager")
	if not cm then
		return
	end
	local gc = cm:FindFirstChildWhichIsA("GroundController", true)
	if not gc then
		return
	end
	local powered = character:GetAttribute(CONFIG.POWERED_ATTR) == true
	local mt = tonumber(character:GetAttribute(CONFIG.MASTER_TONE_ATTR)) or 1
	local ok, err = pcall(function()
		local g, m = gc :: any, cm :: any
		g.BalanceRigidityEnabled = false
		if powered and mt <= CONFIG.COLLAPSE_BALANCE_THRESHOLD then
			g.BalanceMaxTorque = 0
		else
			-- stagger floor: a dip that doesn't knock you DOWN never collapses
			-- balance — near-zero balance on a standing capsule is the "hips
			-- pinned, limbs flopping, still walkable" look (user feedback)
			local dip = math.max(MuscleSystem.impactFactor(character), CONFIG.IMPACT.knockdownFactor)
			local factor = if powered then mt * dip else 1
			if character:GetAttribute(CONFIG.RISING_ATTR) == true then
				factor *= CONFIG.FALL.riseBoost
			end
			local base = tonumber(character:GetAttribute(CONFIG.BALANCE_ATTR)) or CONFIG.BALANCE_TORQUE
			g.BalanceMaxTorque = base * factor
		end
		-- capsule feel knobs (live-tunable; write-on-change keeps replication quiet)
		local turn = tonumber(character:GetAttribute(CONFIG.TURN_ATTR)) or CONFIG.TURN_SPEED
		if m.BaseTurnSpeed ~= turn then
			m.BaseTurnSpeed = turn
		end
		local lean = tonumber(character:GetAttribute(CONFIG.LEAN_ATTR)) or CONFIG.ACCEL_LEAN
		if g.AccelerationLean ~= lean then
			g.AccelerationLean = lean
		end
	end)
	MuscleSystem.lastBalanceError = if ok then nil else tostring(err)
end

-- one body scan per step, both peers: returns (guard offender or nil, peak body-part
-- speed relative to the root). The relative speed feeds the impact reflex; walking
-- moves everything together so it stays near zero, a crate hit spikes it.
function MuscleSystem.scanBody(character: Model): (string?, number)
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local rootVel = if hrp then hrp.AssemblyLinearVelocity else Vector3.zero
	local offender: string? = nil
	local peakRel = 0
	for _, part in character:GetChildren() do
		if part:IsA("BasePart") then
			local v = part.AssemblyLinearVelocity
			local w = part.AssemblyAngularVelocity
			if v.X ~= v.X or w.X ~= w.X then
				offender = part.Name .. " velocity is NaN"
			elseif v.Magnitude > CONFIG.RUNAWAY_LINEAR or w.Magnitude > CONFIG.RUNAWAY_ANGULAR then
				offender = ("%s v=%.0f w=%.0f"):format(part.Name, v.Magnitude, w.Magnitude)
			end
			peakRel = math.max(peakRel, (v - rootVel).Magnitude)
		end
	end
	return offender, peakRel
end

-- impact reflex state, per character per peer
local impactState: { [Model]: { factor: number, timer: number } } = setmetatable({}, { __mode = "k" }) :: any
local lastHVel: { [Model]: Vector3 } = setmetatable({}, { __mode = "k" }) :: any
local slowSpeed: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local turnDeaf: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local riseGrace: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local touchArm: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local touchWired: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- feet and shins touch the world constantly (ground, stairs); everything else
-- touching something foreign is evidence of an actual event
local TOUCH_EXCLUDE: { [string]: boolean } = {
	LeftFoot = true, RightFoot = true, LeftLowerLeg = true, RightLowerLeg = true,
	HumanoidRootPart = true,
}

local function ensureTouchArming(character: Model)
	if touchWired[character] then
		return
	end
	touchWired[character] = true
	for _, p in character:GetChildren() do
		if p:IsA("BasePart") and not TOUCH_EXCLUDE[p.Name] then
			p.Touched:Connect(function(other)
				if other and not other:IsDescendantOf(character) then
					touchArm[character] = os.clock()
				end
			end)
		end
	end
end

-- both peers: has a non-leg body part touched something foreign recently?
function MuscleSystem.recentContact(character: Model): boolean
	ensureTouchArming(character)
	local t = touchArm[character]
	return t ~= nil and os.clock() - t < CONFIG.IMPACT.contactWindow
end

function MuscleSystem.noteImpact(character: Model, peakRel: number, dt: number)
	local st = impactState[character]
	if st then
		st.timer -= dt
		if st.timer <= 0 then
			impactState[character] = nil
			st = nil
		end
	end
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end
	local v = hrp.AssemblyLinearVelocity
	local hVel = Vector3.new(v.X, 0, v.Z)
	local prev = lastHVel[character]
	lastHVel[character] = hVel
	local hAccel = if prev then (hVel - prev).Magnitude / math.max(dt, 1e-4) else 0
	local hSpeed = hVel.Magnitude
	local slow = slowSpeed[character]
	if slow == nil then
		slow = hSpeed
	end
	slow += (hSpeed - slow) * math.min(dt / 0.5, 1)
	slowSpeed[character] = slow

	local imp = CONFIG.IMPACT
	-- deaf during recovery: while Rising and for a grace period after (get-up
	-- motion exceeds every impact threshold and must never re-fell the body)
	local grace = riseGrace[character] or 0
	grace = if character:GetAttribute(CONFIG.RISING_ATTR) == true then imp.riseGrace else math.max(grace - dt, 0)
	riseGrace[character] = grace
	if grace > 0 then
		return
	end
	-- only a STANDING body can be knocked off balance; while tilted or rising the
	-- reflex stays silent so it cannot sabotage its own recovery
	if hrp.CFrame.UpVector.Y < imp.uprightGate then
		return
	end

	-- wall channel: violent horizontal capsule stop while moving fast (measured:
	-- ~1250 stud/s² in one step on a sprint-wall hit vs ~130 for a smoothed stop).
	-- A wall hit is a fresh physical event — it OVERRIDES any active dip window,
	-- otherwise a launch-transient dip's rearm swallows the real impact.
	local wall = CONFIG.WALL
	local preSpeed = if prev then prev.Magnitude else 0
	if hAccel > wall.accelMin and preSpeed > wall.speedMin then
		local factor = math.clamp(1 - (preSpeed - wall.speedMin) / (wall.speedFallAt - wall.speedMin), 0, 1)
		impactState[character] = { factor = factor, timer = imp.staggerTime + imp.rearm }
		return
	end

	-- body-rel channel: external hits, deaf during self-motion transients
	local omegaY = math.abs(hrp.AssemblyAngularVelocity.Y)
	local deaf = turnDeaf[character] or 0
	deaf = if omegaY >= imp.selfOmega then imp.turnCooldown else math.max(deaf - dt, 0)
	turnDeaf[character] = deaf
	local swingBase = imp.threshold + hSpeed * imp.swingPerSpeed
	if
		peakRel > swingBase
		and MuscleSystem.recentContact(character)
		and deaf <= 0
		and hAccel < imp.selfAccel
		and math.abs(hSpeed - slow) < imp.selfSpeedDelta
	then
		local factor = math.clamp(1 - (peakRel - swingBase) / (imp.fallAt - imp.threshold), 0, 1)
		if not st then
			impactState[character] = { factor = factor, timer = imp.staggerTime + imp.rearm }
		elseif st.timer > imp.rearm and factor < st.factor then
			-- a hit RAMPS across frames: the first threshold crossing locks a
			-- mild dip and the true peak lands INSIDE the window, swallowed —
			-- so knockdowns waited for the slow tilt trigger instead (the
			-- "brief pin at ragdoll onset", user-reported). A deeper factor
			-- escalates an ACTIVE window in place; never during the re-arm
			-- tail (that re-opens the boundary-struggle loop re-arm kills),
			-- and the timer is not refreshed (escalation stays bounded to the
			-- original stagger window, so it cannot self-chain off the flop).
			st.factor = factor
		end
	end
end

function MuscleSystem.impactFactor(character: Model): number
	local st = impactState[character]
	if not st then
		return 1
	end
	-- the dip only bites during the stagger window; the tail of the timer is re-arm
	return if st.timer > CONFIG.IMPACT.rearm then st.factor else 1
end

-- kept for compatibility with callers that only want the trip-wire
function MuscleSystem.guard(character: Model): string?
	local offender = MuscleSystem.scanBody(character)
	return offender
end

return MuscleSystem

