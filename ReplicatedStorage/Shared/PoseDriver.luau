--!strict
-- Layer 1 · INTENT, presentation-side driver. Two jobs, both keyed off the
-- replicated FS state machine, both running in PreSimulation:
--
-- 1. GETUP: drive the rise through IKCONTROLS — ground-anchored effector
--    goals (hands plant on the ground beside the hips, feet plant under the
--    body), weights scheduled by the replicated GT clock. WHY IK AND NOT A
--    POSE CLIP (the ☠️ Transform-ownership saga, ENGINE_FACTS §1 + tuning
--    log Addendum 8/9): script Transform writes never survive on the
--    SA-predicted client; runtime AnimationTracks are gated by the SA
--    animate state machine (numeric asset ids only); and a server-only clip
--    left the actor's own prediction striving toward targets it couldn't
--    see — the correction war read as a "possessed spasm". IKControl is the
--    ONE target channel the engine applies on EVERY peer (verified live:
--    client shoulder target 82°, hand 0.5 studs from goal). Both peers
--    compute the same goals from the same replicated state → matched
--    targets, matched impedance, nothing to fight.
--    The muscles still have to physically REACH those goals through the
--    quadratic torque ceiling — the buckle mechanism is untouched.
-- 2. STUMBLE: arm flail via the same IK channel — targets driven from a
--    counter of the pelvis's angular velocity.
--
-- Wire once per peer with PoseDriver.wire(getCharacters): the server passes
-- all player characters, the client passes only its own (prediction).

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local IS_SERVER = RunService:IsServer()

local MuscleSystem = require(script.Parent:WaitForChild("MuscleSystem"))
local GetupPose = require(script.Parent:WaitForChild("GetupPose"))

local CONFIG = {
	FLAIL_WEIGHT_RATE = 8, -- IK weight ramp per second (never snap Weight)
	FLAIL_COUNTER = 0.35, -- studs of hand-target throw per rad/s of pelvis spin
	FLAIL_SIDE = 1.9, -- resting flail target distance out from the pelvis
	FLAIL_UP = 1.8,
	FLAIL_SMOOTH = 0.06,
	-- getup IK choreography (pelvis-relative, ground-anchored)
	GETUP_WEIGHT_RATE = 6, -- weight ramp per second into/out of the plant
	GETUP_HAND_SIDE = 0.85, -- hands plant this far out from the pelvis
	GETUP_HAND_BACK = 0.25, -- ... and slightly behind it (the push-off line)
	GETUP_FOOT_SIDE = 0.35, -- feet plant at stance width
	GETUP_FOOT_FWD = 0.55, -- ... ahead of the pelvis (knees-bent plant)
	GETUP_LIFT = 0.12, -- target height above the ground hit
	GETUP_HANDS_OFF = 0.75, -- hands release at this clip progress (arms ease off)
	GETUP_FEET_OFF = 0.97, -- feet release right at the stand
	GETUP_SMOOTH = 0.1,
	GETUP_RAY = 6,
}

local PoseDriver = {}
PoseDriver.CONFIG = CONFIG

type Rig = {
	-- stumble flail
	ikL: IKControl?,
	ikR: IKControl?,
	attL: Attachment?,
	attR: Attachment?,
	weight: number,
	-- getup plant
	gIK: { IKControl }?,
	gAtt: { Attachment }?,
	gWeight: number,
	params: RaycastParams?,
}
local rigs: { [Model]: Rig } = setmetatable({}, { __mode = "k" }) :: any

local function ensureRig(character: Model): Rig
	local r = rigs[character]
	if r then
		return r
	end
	r = { weight = 0, gWeight = 0 }
	rigs[character] = r
	return r
end

-- IK instances: created by the SERVER (they replicate); the client just
-- finds them. Runs in PreSimulation, so instance creation is unrestricted.
local function buildIK(character: Model, humanoid: Humanoid, pelvis: BasePart, name: string, rootName: string, effectorName: string, smooth: number): (IKControl?, Attachment?)
	local existIK = humanoid:FindFirstChild(name) :: IKControl?
	local existAtt = pelvis:FindFirstChild(name .. "Target") :: Attachment?
	if existIK and existAtt then
		return existIK, existAtt
	end
	if not IS_SERVER then
		return nil, nil -- replication will deliver them
	end
	local root = character:FindFirstChild(rootName)
	local effector = character:FindFirstChild(effectorName)
	if not (root and effector) then
		return nil, nil
	end
	local att = existAtt or Instance.new("Attachment")
	att.Name = name .. "Target"
	att.Parent = pelvis
	local ik = existIK or Instance.new("IKControl")
	ik.Name = name
	ik.Type = Enum.IKControlType.Position
	ik.ChainRoot = root
	ik.EndEffector = effector
	ik.Target = att
	ik.Weight = 0
	ik.SmoothTime = smooth
	ik.Parent = humanoid
	return ik, att
end

local function ensureFlail(character: Model, r: Rig)
	if r.ikL and r.ikL.Parent and r.attL and r.attL.Parent then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local pelvis = character:FindFirstChild("LowerTorso") :: BasePart?
	if not humanoid or not pelvis then
		return
	end
	-- legacy names kept: FlailL/FlailR with FlailTargetL/FlailTargetR
	r.ikL = humanoid:FindFirstChild("FlailL") :: IKControl?
	r.attL = pelvis:FindFirstChild("FlailTargetL") :: Attachment?
	r.ikR = humanoid:FindFirstChild("FlailR") :: IKControl?
	r.attR = pelvis:FindFirstChild("FlailTargetR") :: Attachment?
	if r.ikL and r.ikR and r.attL and r.attR then
		return
	end
	if not IS_SERVER then
		return
	end
	local function build(side: string): (IKControl?, Attachment?)
		local upper = character:FindFirstChild(side .. "UpperArm")
		local hand = character:FindFirstChild(side .. "Hand")
		if not (upper and hand) then
			return nil, nil
		end
		local att = Instance.new("Attachment")
		att.Name = "FlailTarget" .. side:sub(1, 1)
		att.Parent = pelvis
		local ik = Instance.new("IKControl")
		ik.Name = "Flail" .. side:sub(1, 1)
		ik.Type = Enum.IKControlType.Position
		ik.ChainRoot = upper
		ik.EndEffector = hand
		ik.Target = att
		ik.Weight = 0
		ik.SmoothTime = CONFIG.FLAIL_SMOOTH
		ik.Parent = humanoid
		return ik, att
	end
	r.ikL, r.attL = build("Left")
	r.ikR, r.attR = build("Right")
end

local function ensureGetupIK(character: Model, r: Rig): boolean
	if r.gIK and #r.gIK == 4 then
		local alive = true
		for _, ik in r.gIK do
			if not ik.Parent then
				alive = false
			end
		end
		if alive then
			return true
		end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	local pelvis = character:FindFirstChild("LowerTorso") :: BasePart?
	if not humanoid or not pelvis then
		return false
	end
	local hl, al = buildIK(character, humanoid, pelvis, "GetupHandL", "LeftUpperArm", "LeftHand", CONFIG.GETUP_SMOOTH)
	local hr, ar = buildIK(character, humanoid, pelvis, "GetupHandR", "RightUpperArm", "RightHand", CONFIG.GETUP_SMOOTH)
	local fl, bl = buildIK(character, humanoid, pelvis, "GetupFootL", "LeftUpperLeg", "LeftFoot", CONFIG.GETUP_SMOOTH)
	local fr, br = buildIK(character, humanoid, pelvis, "GetupFootR", "RightUpperLeg", "RightFoot", CONFIG.GETUP_SMOOTH)
	if hl and hr and fl and fr and al and ar and bl and br then
		r.gIK = { hl, hr, fl, fr }
		r.gAtt = { al, ar, bl, br }
		return true
	end
	return false
end

function PoseDriver.step(character: Model, dt: number)
	local fs = character:GetAttribute(MuscleSystem.CONFIG.STATE_ATTR)
	local r = ensureRig(character)
	local pelvis = character:FindFirstChild("LowerTorso") :: BasePart?
	if not pelvis then
		return
	end

	-- GETUP: plant targets on the ground around the pelvis; weights scheduled
	-- from the replicated GT clock. Same computation on every peer.
	local wantGetup = 0
	local handsWant, feetWant = 0, 0
	if fs == "getup" and ensureGetupIK(character, r) then
		local t = tonumber(character:GetAttribute(GetupPose.CONFIG.TIME_ATTR)) or 0
		local p = GetupPose.progress(t)
		handsWant = if p < CONFIG.GETUP_HANDS_OFF then 1 else 0
		feetWant = if p < CONFIG.GETUP_FEET_OFF then 1 else 0
	end
	if r.gIK and r.gAtt then
		-- weight slews (never snaps); one rate for in and out
		local blend = math.min(dt * CONFIG.GETUP_WEIGHT_RATE, 1)
		r.gWeight += ((math.max(handsWant, feetWant)) - r.gWeight) * blend
		local hands = r.gWeight * handsWant
		local feet = r.gWeight * feetWant
		-- fs left getup: everything decays through the same slew
		if fs ~= "getup" then
			hands, feet = 0, 0
			r.gWeight += (0 - r.gWeight) * blend
		end
		local gs = r.gIK :: { IKControl }
		if math.abs(gs[1].Weight - hands) > 0.005 then
			gs[1].Weight = hands
			gs[2].Weight = hands
		end
		if math.abs(gs[3].Weight - feet) > 0.005 then
			gs[3].Weight = feet
			gs[4].Weight = feet
		end
		if r.gWeight > 0.02 and fs == "getup" then
			-- ground under the pelvis: the plant surface
			if not r.params then
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = { character }
				r.params = params
			end
			local hit = Workspace:Raycast(pelvis.Position, Vector3.new(0, -CONFIG.GETUP_RAY, 0), r.params)
			local groundY = if hit then hit.Position.Y else pelvis.Position.Y - 2.7
			-- body-relative horizontal frame (degenerate look → use right×Y)
			local look = pelvis.CFrame.LookVector
			local fwd = Vector3.new(look.X, 0, look.Z)
			if fwd.Magnitude < 0.15 then
				local rgt = pelvis.CFrame.RightVector
				fwd = Vector3.new(rgt.Z, 0, -rgt.X) -- right rotated -90° about Y
			end
			if fwd.Magnitude > 0.001 then
				fwd = fwd.Unit
			else
				fwd = Vector3.zAxis
			end
			-- face-down bodies push the other way: hands forward, feet drag back
			local faceUp = character:GetAttribute(GetupPose.CONFIG.FACE_ATTR) ~= false
			local handFwd = if faceUp then -CONFIG.GETUP_HAND_BACK else CONFIG.GETUP_HAND_BACK
			local footFwd = if faceUp then CONFIG.GETUP_FOOT_FWD else CONFIG.GETUP_FOOT_FWD * 0.4
			local right = Vector3.new(fwd.Z, 0, -fwd.X) -- fwd rotated; horizontal right
			local base = Vector3.new(pelvis.Position.X, groundY + CONFIG.GETUP_LIFT, pelvis.Position.Z)
			local ga = r.gAtt :: { Attachment }
			ga[1].WorldPosition = base - right * CONFIG.GETUP_HAND_SIDE + fwd * handFwd
			ga[2].WorldPosition = base + right * CONFIG.GETUP_HAND_SIDE + fwd * handFwd
			ga[3].WorldPosition = base - right * CONFIG.GETUP_FOOT_SIDE + fwd * footFwd
			ga[4].WorldPosition = base + right * CONFIG.GETUP_FOOT_SIDE + fwd * footFwd
		end
	end

	-- STUMBLE: flail. Weight ramps (never snaps); targets counter the spin.
	ensureFlail(character, r)
	local goal = if fs == "stumble" then 1 else 0
	r.weight += (goal - r.weight) * math.min(dt * CONFIG.FLAIL_WEIGHT_RATE, 1)
	if r.ikL and r.ikR and r.attL and r.attR then
		local ikL, ikR = r.ikL :: IKControl, r.ikR :: IKControl
		if math.abs(ikL.Weight - r.weight) > 0.005 then
			ikL.Weight = r.weight
			ikR.Weight = r.weight
		end
		if r.weight > 0.02 then
			local w = pelvis.AssemblyAngularVelocity
			local counter = w:Cross(Vector3.yAxis) * CONFIG.FLAIL_COUNTER
			local cf = pelvis.CFrame
			local up = Vector3.new(0, CONFIG.FLAIL_UP, 0);
			(r.attL :: Attachment).WorldPosition = pelvis.Position - cf.RightVector * CONFIG.FLAIL_SIDE + up + counter;
			(r.attR :: Attachment).WorldPosition = pelvis.Position + cf.RightVector * CONFIG.FLAIL_SIDE + up + counter
		end
	end
end

-- once per peer: getCharacters returns the characters THIS peer simulates
function PoseDriver.wire(getCharacters: () -> { Model })
	RunService.PreSimulation:Connect(function(dt)
		for _, character in getCharacters() do
			if character.Parent then
				PoseDriver.step(character, dt)
			end
		end
	end)
end

return PoseDriver
