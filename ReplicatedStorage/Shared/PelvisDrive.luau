--!strict
-- PELVIS-DRIVEN LOCOMOTION — the A/B spike vs the CCL capsule (panel toggle).
--
-- Why it exists: under balance the capsule is orientation-LOCKED (verified
-- live: a driven 2 rad/s spin sustained 1.5 s left its up at 1.00 — it is a
-- gyroscope, not a spring) and it drives through an invisible collidable box
-- socketed to the pelvis. This mode makes the BODY the character: support,
-- balance, and drive are COMPLIANT forces on the pelvis, all scaled by muscle
-- tone — so weakness, stagger, and collapse fall out of Layer 2 for free, and
-- balance can be genuinely overpowered instead of servo-cancelled.
--
-- The ControllerManager stays as the INPUT conduit only (MovingDirection);
-- its own forces are zeroed through the same release path falls use, and the
-- HRP rides along as a non-collidable ghost.
--
-- Both peers run step() for their simulated characters (same replicated
-- inputs, deterministic writes — the muscle-system pattern). Only the SERVER
-- creates the force instances; they replicate.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local IS_SERVER = RunService:IsServer()

local MuscleSystem = require(script.Parent:WaitForChild("MuscleSystem"))
local GetupPose = require(script.Parent:WaitForChild("GetupPose"))

local CONFIG = {
	MODE_ATTR = "PelvisMode",
	REMOTE_KEY = "PELVIS",
	-- pelvis center over ground. R15 stands with LowerTorso ~2.8 up; a hair
	-- lower reads as a live stance instead of tiptoe stilts
	HEIGHT = 2.7,
	RAY = 8,
	-- hover: spring-damper per unit mass, capped in multiples of gravity and
	-- scaled by tone — tone below ~0.55 cannot carry body weight and sinks
	HOVER_K = 30, HOVER_D = 9, HOVER_CAP_G = 1.8,
	-- upright: a solver-integrated AlignOrientation servo (PrimaryAxisOnly —
	-- vertical-only, yaw-free), NOT an explicit K/D Torque. The old sampled
	-- PD (55/10/120, then 100/14/220) was updated at sim rate against a body
	-- whose effective inertia collapses whenever the chain is limp or
	-- grounded (getup, knockdown): the damper overshot per frame, flipped
	-- sign, and the cap bounded a standing ~30 rad/s pelvis oscillation
	-- through every mid-getup — the "seizure on the ground" (measured live;
	-- the idle stand survived only because a full-tone chain adds inertia).
	-- The servo cannot self-oscillate; tone, dip, and the getup schedule
	-- scale its BUDGET, so weakness and staggers read exactly as before.
	UP_TORQUE = 220, UP_RESP = 35,
	YAW_K = 35, YAW_D = 6, YAW_CAP = 80,
	-- getup pitch pacing: the pelvis servo IS the pitch actuator (its budget
	-- dwarfs the Root muscle at body mass) — unscheduled it rammed a lying
	-- pelvis at full stance authority from the first toned frame. Soft while
	-- the plants organize, full through the clip's second half.
	UP_SCHED_FLOOR = 0.25, UP_SCHED_FROM = 0.4, UP_SCHED_TO = 0.85,
	-- getup height is gated on ACHIEVED pitch (pelvis up-vector), not just
	-- the clock: the clock-only ramp hoisted a still-horizontal body to 1.8
	-- studs mid-clip — feet swinging in the air, the rise reading as a
	-- hip-pinned midair rotation (measured; user report ×3). You don't rise
	-- until you're over your feet: crouch-low until the body is actually
	-- pitching up, then the ramp is a squat-to-stand on planted feet.
	GETUP_PITCH_FROM = 0.35, GETUP_PITCH_TO = 0.85,
	-- drive toward MovingDirection * SPEED (* the Running SpeedMultiplier).
	-- The TARGET velocity ramps at DRIVE_RAMP stud/s² — instant full drive
	-- shoved 0.36 g into the pelvis at sprint launch and genuinely pitched
	-- the body over (pUp 0.94→0.50→−0.58, measured; the capsule had
	-- ACCEL_TIME smoothing, the pelvis had none — a human winds up)
	DRIVE_K = 5, DRIVE_CAP = 70, SPEED = 16, DRIVE_RAMP = 40,
	-- rise assist multiplier. 2.5 was the pre-clip crutch (a bare spring
	-- cannot right a lying body); WITH the GetupPose clip the legs and arms do
	-- the real work and the assist is 1 (none) — which is exactly what lets a
	-- health-capped ramp genuinely buckle (Gate 3 item 3: at RC 0.4 with
	-- boost, clip + 40% legs still stood — verified live, twice).
	RISE_BOOST = 1,
	-- upright-TORQUE-only rise assist lever. Torque only, never support:
	-- boosting support would re-mask the RC buckle and break the
	-- stand-on-him pin (both live in the vertical force margin). At 2 with
	-- a de-toned Root it whipped the pelvis (midair spasm, user-reported);
	-- 1 since the ghost-righting fix — the ROOT MUSCLE does the righting
	-- against an upright ghost, damped like any other muscle.
	RISE_UP_BOOST = 1,
	-- getup support height: the pelvis is pulled from crouch height to stand
	-- height ACROSS the clip, so the body rises through the sequence instead
	-- of popping to full hover
	CROUCH = 1.0,
}

local PelvisDrive = {}
PelvisDrive.CONFIG = CONFIG

type Rig = {
	vf: VectorForce,
	tq: Torque,
	params: RaycastParams,
	running: Instance?,
	mass: number,
	follow: AlignPosition?, -- follower-ghost servo (lazy: replication may lag)
	rootAtt: Attachment?, -- pelvis-side Root attach = the follow goal
	upright: AlignOrientation?, -- pelvis upright servo (lazy, same reason)
	tgtVel: Vector3, -- ramped drive target (see DRIVE_RAMP)
}
local rigCache: { [Model]: Rig } = setmetatable({}, { __mode = "k" }) :: any

local function buildRig(character: Model, pelvis: BasePart): Rig?
	local vf = pelvis:FindFirstChild("PelvisForce") :: VectorForce?
	local tq = pelvis:FindFirstChild("PelvisTorque") :: Torque?
	if not (vf and tq) then
		if not RunService:IsServer() then
			return nil -- server creates, replication delivers
		end
		local att = pelvis:FindFirstChild("PelvisDriveAttachment") :: Attachment?
		if not att then
			att = Instance.new("Attachment")
			att.Name = "PelvisDriveAttachment"
			att.Parent = pelvis
		end
		vf = Instance.new("VectorForce")
		vf.Name = "PelvisForce"
		vf.Attachment0 = att
		vf.RelativeTo = Enum.ActuatorRelativeTo.World
		vf.ApplyAtCenterOfMass = true
		vf.Force = Vector3.zero
		vf.Parent = pelvis
		tq = Instance.new("Torque")
		tq.Name = "PelvisTorque"
		tq.Attachment0 = att
		tq.RelativeTo = Enum.ActuatorRelativeTo.World
		tq.Torque = Vector3.zero
		tq.Parent = pelvis
	end
	if RunService:IsServer() and not pelvis:FindFirstChild("PelvisUpright") then
		local upAtt = Instance.new("Attachment")
		upAtt.Name = "PelvisUprightAtt"
		upAtt.CFrame = CFrame.Angles(0, 0, math.rad(90)) -- primary axis = pelvis up
		upAtt.Parent = pelvis
		local ao = Instance.new("AlignOrientation")
		ao.Name = "PelvisUpright"
		ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
		ao.Attachment0 = upAtt
		ao.PrimaryAxisOnly = true
		ao.CFrame = CFrame.Angles(0, 0, math.rad(90)) -- goal: pelvis up = world +Y
		ao.RigidityEnabled = false
		ao.Responsiveness = CONFIG.UP_RESP
		ao.MaxTorque = 0
		ao.Enabled = false
		ao.Parent = pelvis
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	-- BODY mass only — the ghost carries itself (follower capsule; the
	-- ability system hovers it). Counting the HRP's 2.0 handed the body its
	-- weight-share as free lift: the stand floated 0.63 studs above target,
	-- feet clear of the ground (measured; 2·g ÷ (K·m) = 0.63 exactly).
	local mass = 0
	for _, p in character:GetChildren() do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			mass += p:GetMass()
		end
	end
	local manager = character:FindFirstChild("AbilityManagerActor")
	local abilities = manager and manager:FindFirstChild("Abilities")
	return {
		vf = vf :: VectorForce,
		tq = tq :: Torque,
		params = params,
		running = abilities and abilities:FindFirstChild("Running"),
		mass = mass,
		upright = pelvis:FindFirstChild("PelvisUpright") :: AlignOrientation?,
		tgtVel = Vector3.zero,
	}
end

-- called every step the mode is OFF: a toggle must not strand stale forces
function PelvisDrive.idle(character: Model)
	local r = rigCache[character]
	if r and (r.vf.Force ~= Vector3.zero or r.tq.Torque ~= Vector3.zero) then
		r.vf.Force = Vector3.zero
		r.tq.Torque = Vector3.zero
	end
	if r and r.upright and r.upright.Enabled then
		r.upright.Enabled = false
	end
end

function PelvisDrive.step(character: Model, dt: number)
	local pelvis = character:FindFirstChild("LowerTorso") :: BasePart?
	local cm = character:FindFirstChildOfClass("ControllerManager")
	if not pelvis or not cm then
		return
	end
	local r = rigCache[character]
	if not r then
		r = buildRig(character, pelvis)
		if not r then
			return
		end
		rigCache[character] = r
	end
	-- follower-ghost goal: the capsule chases the pelvis attach point, one
	-- directional — force on the GHOST only (MuscleSystem.setupBody). BOTH
	-- peers, every step, tone or no tone: a limp body still drags its
	-- camera/input ghost with it.
	if not r.follow or not r.follow.Parent then
		local hrp = character:FindFirstChild("HumanoidRootPart")
		r.follow = if hrp then hrp:FindFirstChild("GhostFollow") :: AlignPosition? else nil
	end
	if not r.rootAtt or not r.rootAtt.Parent then
		r.rootAtt = pelvis:FindFirstChild("RootRigAttachment") :: Attachment?
	end
	if not r.upright or not r.upright.Parent then
		r.upright = pelvis:FindFirstChild("PelvisUpright") :: AlignOrientation?
	end
	if r.follow and r.follow.Enabled then
		local goal = if r.rootAtt then r.rootAtt.WorldPosition else pelvis.Position
		if (r.follow.Position - goal).Magnitude > 0.01 then
			r.follow.Position = goal
		end
	end
	local powered = character:GetAttribute("Powered") == true
	local mt = tonumber(character:GetAttribute("MT")) or 1
	if not powered or mt <= 0.05 then
		r.vf.Force = Vector3.zero
		r.tq.Torque = Vector3.zero
		-- a limp body is not held upright by anything
		if r.upright and r.upright.Enabled then
			r.upright.Enabled = false
		end
		return
	end
	local m = r.mass
	local g = Workspace.Gravity
	local v = pelvis.AssemblyLinearVelocity
	local w = pelvis.AssemblyAngularVelocity
	local move = (cm :: any).MovingDirection :: Vector3
	-- boost scales with tone SQUARED: at full tone the assist is full (4.5 g
	-- cap); at tone 0.4 the support lands under body weight (0.89 g) and the
	-- rise genuinely BUCKLES — linear scaling still carried a 0.4-tone body
	-- up (verified live, Gate 3 item 3 failed). Crossover ≈ tone 0.45.
	local rising = character:GetAttribute("Rising") == true
	local boost = if rising then 1 + (CONFIG.RISE_BOOST - 1) * mt * mt else 1

	-- input only counts while the fall machine says so: drive on a downed or
	-- half-risen body drags it around and wedges the get-up (user-reported)
	local fs = character:GetAttribute(MuscleSystem.CONFIG.STATE_ATTR)
	local driveOK = fs == nil or fs == "upright" or fs == "stumble"

	-- getup: support height climbs across the clip — back-loaded so the body
	-- organizes low first (a linear ramp levitated the pelvis while the limbs
	-- were still gathering), but with a SOFT LANDING: p³(4−3p) has near-zero
	-- slope at the end, so the last stretch of the rise settles instead of
	-- yanking to full height (p² ended at max slope — the terminal "quick
	-- get into place" pop, user-reported on the IK v2 pass)
	local height = CONFIG.HEIGHT
	local upSched = 1
	if fs == "getup" then
		local t = tonumber(character:GetAttribute(GetupPose.CONFIG.TIME_ATTR)) or 0
		local p = GetupPose.progress(t)
		local curve = p * p * p * (4 - 3 * p)
		-- upright budget paced by the clip (see UP_SCHED_*): the servo owns
		-- the pitch-up, and full stance authority on a lying body was the
		-- grind that threw the heap around while the plants were organizing
		local sx = math.clamp((p - CONFIG.UP_SCHED_FROM) / (CONFIG.UP_SCHED_TO - CONFIG.UP_SCHED_FROM), 0, 1)
		upSched = CONFIG.UP_SCHED_FLOOR + (1 - CONFIG.UP_SCHED_FLOOR) * sx * sx * (3 - 2 * sx)
		-- height gated on ACHIEVED pitch (see GETUP_PITCH_*): stay crouched
		-- until the body is genuinely coming upright, then squat-to-stand
		local pu = pelvis.CFrame.UpVector.Y
		local pitch = math.clamp((pu - CONFIG.GETUP_PITCH_FROM) / (CONFIG.GETUP_PITCH_TO - CONFIG.GETUP_PITCH_FROM), 0, 1)
		pitch = pitch * pitch * (3 - 2 * pitch)
		height = CONFIG.CROUCH + (CONFIG.HEIGHT - CONFIG.CROUCH) * curve * pitch
	end

	local force = Vector3.zero
	local hit = Workspace:Raycast(pelvis.Position, Vector3.new(0, -CONFIG.RAY, 0), r.params)
	if hit then
		-- support: carries the whole chain through the joints, like legs would.
		-- (A tone² cap here was tried for the buckle test and reverted: it
		-- strangled FULL-tone rises mid-ramp — the buckle lives in the muscle
		-- torque ceiling now, where the architecture doc always put it.)
		local err = height - (pelvis.Position.Y - hit.Position.Y)
		local fy = m * (g + err * CONFIG.HOVER_K - v.Y * CONFIG.HOVER_D)
		local support = math.clamp(fy, 0, m * g * CONFIG.HOVER_CAP_G * mt * boost)
		force = Vector3.new(0, support, 0)
		-- WEIGHT TRANSFER: the hover is a virtual leg, and a leg PRESSES on
		-- what it stands on. Without the reaction, a hovering character
		-- weighs ~nothing on whatever is under him — Gate 3 stand-on-him
		-- failed exactly this way: the pinning player's weight never reached
		-- the downed body, and it lifted him like air. Server-only (the
		-- pressed body is server-simulated; a client-side press on someone
		-- else's parts would just be a misprediction).
		if IS_SERVER and hit.Instance and hit.Instance:IsA("BasePart") and not hit.Instance.Anchored then
			local stepDt = if type(dt) == "number" then dt else 1 / 60
			hit.Instance:ApplyImpulseAtPosition(Vector3.new(0, -support * stepDt, 0), hit.Position)
		end
		-- drive, grounded only
		local mult = 1
		if r.running then
			mult = tonumber(r.running:GetAttribute("SpeedMultiplier")) or 1
		end
		local want = if driveOK then Vector3.new(move.X, 0, move.Z) * CONFIG.SPEED * mult else Vector3.zero
		-- ramped target: wind up instead of shove (see DRIVE_RAMP)
		local dv = want - r.tgtVel
		local maxStep = CONFIG.DRIVE_RAMP * (if type(dt) == "number" then dt else 1 / 60)
		r.tgtVel += if dv.Magnitude > maxStep then dv.Unit * maxStep else dv
		local fd = (r.tgtVel - Vector3.new(v.X, 0, v.Z)) * m * CONFIG.DRIVE_K
		local dcap = m * CONFIG.DRIVE_CAP * mt
		if fd.Magnitude > dcap then
			fd = fd.Unit * dcap
		end
		force += fd
	end
	r.vf.Force = force

	-- compliant upright hold: the servo's BUDGET carries every readability
	-- channel — tone (weak = toppleable), the STUMBLE dip (a hit genuinely
	-- wobbles the body), and the getup schedule. The servo itself is
	-- solver-stable at any budget (see CONFIG.UP_TORQUE).
	local dip = math.max(MuscleSystem.impactFactor(character), MuscleSystem.CONFIG.IMPACT.knockdownFactor)
	local upB = if rising then CONFIG.RISE_UP_BOOST else 1
	if r.upright then
		local budget = m * CONFIG.UP_TORQUE * mt * boost * upB * dip * upSched
		if r.upright.MaxTorque ~= budget then
			r.upright.MaxTorque = budget
		end
		if not r.upright.Enabled then
			r.upright.Enabled = true
		end
	end
	-- yaw stays an explicit torque (the servo is yaw-free by construction):
	-- face MovingDirection while driving
	local torque = Vector3.zero
	local mh = Vector3.new(move.X, 0, move.Z)
	if driveOK and mh.Magnitude > 0.1 then
		local look = pelvis.CFrame.LookVector
		local lh = Vector3.new(look.X, 0, look.Z)
		if lh.Magnitude > 0.1 then
			lh = lh.Unit
			mh = mh.Unit
			local ang = math.atan2(lh:Cross(mh).Y, lh:Dot(mh))
			torque = Vector3.new(0, ang * CONFIG.YAW_K - w.Y * CONFIG.YAW_D, 0) * m
			local ycap = m * CONFIG.YAW_CAP * mt
			if torque.Magnitude > ycap then
				torque = torque.Unit * ycap
			end
		end
	end
	r.tq.Torque = torque
end

return PelvisDrive
