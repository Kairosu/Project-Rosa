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
	-- upright: compliant torque spring per unit mass (the anti-gyroscope)
	UP_K = 55, UP_D = 10, UP_CAP = 120,
	YAW_K = 35, YAW_D = 6,
	-- drive toward MovingDirection * SPEED (* the Running SpeedMultiplier)
	DRIVE_K = 5, DRIVE_CAP = 70, SPEED = 16,
	-- rise assist multiplier. 2.5 was the pre-clip crutch (a bare spring
	-- cannot right a lying body); WITH the GetupPose clip the legs and arms do
	-- the real work and the assist is 1 (none) — which is exactly what lets a
	-- health-capped ramp genuinely buckle (Gate 3 item 3: at RC 0.4 with
	-- boost, clip + 40% legs still stood — verified live, twice).
	RISE_BOOST = 1,
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
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local mass = 0
	for _, p in character:GetChildren() do
		if p:IsA("BasePart") then
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
	}
end

-- called every step the mode is OFF: a toggle must not strand stale forces
function PelvisDrive.idle(character: Model)
	local r = rigCache[character]
	if r and (r.vf.Force ~= Vector3.zero or r.tq.Torque ~= Vector3.zero) then
		r.vf.Force = Vector3.zero
		r.tq.Torque = Vector3.zero
	end
end

function PelvisDrive.step(character: Model, _dt: number)
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
	local powered = character:GetAttribute("Powered") == true
	local mt = tonumber(character:GetAttribute("MT")) or 1
	if not powered or mt <= 0.05 then
		r.vf.Force = Vector3.zero
		r.tq.Torque = Vector3.zero
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
	if fs == "getup" then
		local t = tonumber(character:GetAttribute(GetupPose.CONFIG.TIME_ATTR)) or 0
		local p = GetupPose.progress(t)
		local curve = p * p * p * (4 - 3 * p)
		height = CONFIG.CROUCH + (CONFIG.HEIGHT - CONFIG.CROUCH) * curve
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
		force = Vector3.new(0, math.clamp(fy, 0, m * g * CONFIG.HOVER_CAP_G * mt * boost), 0)
		-- drive, grounded only
		local mult = 1
		if r.running then
			mult = tonumber(r.running:GetAttribute("SpeedMultiplier")) or 1
		end
		local target = if driveOK then Vector3.new(move.X, 0, move.Z) * CONFIG.SPEED * mult else Vector3.zero
		local fd = (target - Vector3.new(v.X, 0, v.Z)) * m * CONFIG.DRIVE_K
		local dcap = m * CONFIG.DRIVE_CAP * mt
		if fd.Magnitude > dcap then
			fd = fd.Unit * dcap
		end
		force += fd
	end
	r.vf.Force = force

	-- compliant upright spring: axis = up × Y rights it, sin(tilt)-weighted.
	-- STUMBLE dips it with the impact factor — a hit genuinely wobbles the
	-- body now (this is the pelvis-mode half of the stagger system)
	local dip = math.max(MuscleSystem.impactFactor(character), MuscleSystem.CONFIG.IMPACT.knockdownFactor)
	local up = pelvis.CFrame.UpVector
	local torque = (up:Cross(Vector3.yAxis) * CONFIG.UP_K * boost * dip - Vector3.new(w.X, 0, w.Z) * CONFIG.UP_D) * m
	local mh = Vector3.new(move.X, 0, move.Z)
	if driveOK and mh.Magnitude > 0.1 then
		local look = pelvis.CFrame.LookVector
		local lh = Vector3.new(look.X, 0, look.Z)
		if lh.Magnitude > 0.1 then
			lh = lh.Unit
			mh = mh.Unit
			local ang = math.atan2(lh:Cross(mh).Y, lh:Dot(mh))
			torque += Vector3.new(0, ang * CONFIG.YAW_K - w.Y * CONFIG.YAW_D, 0) * m
		end
	end
	local tcap = m * CONFIG.UP_CAP * mt * boost
	if torque.Magnitude > tcap then
		torque = torque.Unit * tcap
	end
	r.tq.Torque = torque
end

return PelvisDrive
