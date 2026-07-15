--!strict
-- Layer 1 · INTENT, presentation-side driver. Two jobs, both keyed off the
-- replicated FS state machine, both running in PreSimulation (the official
-- procedural hook: after the Animator writes Transform, before the batch
-- application — our write wins without breaking retargeting):
--
-- 1. GETUP: overwrite all 15 joint Transforms with the GetupPose clip at the
--    replicated GT clock — SERVER ONLY (see the Transform-ownership law in
--    step below: client Transform writes are placebo under SA prediction; the
--    actor's own client renders the getup from replicated physics, limp).
--    The muscles strive toward it at ramping tone — the body physically
--    pushes itself up. No blend exists anywhere.
-- 2. STUMBLE: arm flail via IKControl — targets driven from a counter of the
--    pelvis's angular velocity. IK is applied by the engine's own animation
--    layer, so it works on every peer; each peer solves from the same
--    replicated state.
--
-- Wire once per peer with PoseDriver.wire(getCharacters): the server passes
-- all player characters, the client passes only its own (flail prediction).

local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()

local MuscleSystem = require(script.Parent:WaitForChild("MuscleSystem"))
local GetupPose = require(script.Parent:WaitForChild("GetupPose"))

local CONFIG = {
	FLAIL_WEIGHT_RATE = 8, -- IK weight ramp per second (never snap Weight)
	FLAIL_COUNTER = 0.35, -- studs of hand-target throw per rad/s of pelvis spin
	FLAIL_SIDE = 1.9, -- resting flail target distance out from the pelvis
	FLAIL_UP = 1.8,
	FLAIL_SMOOTH = 0.06,
}

local PoseDriver = {}
PoseDriver.CONFIG = CONFIG

type Rig = {
	ikL: IKControl?,
	ikR: IKControl?,
	attL: Attachment?,
	attR: Attachment?,
	faceUp: boolean,
	wasGetup: boolean,
	weight: number,
	entryPose: GetupPose.Pose?,
}
local rigs: { [Model]: Rig } = setmetatable({}, { __mode = "k" }) :: any

local function ensureRig(character: Model): Rig
	local r = rigs[character]
	if r then
		return r
	end
	r = { faceUp = true, wasGetup = false, weight = 0 }
	rigs[character] = r
	return r
end

-- flail IK instances: created by the SERVER (they replicate); the client just
-- finds them. Runs in PreSimulation, so instance creation is unrestricted.
local function ensureFlail(character: Model, r: Rig)
	if r.ikL and r.ikL.Parent then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local pelvis = character:FindFirstChild("LowerTorso")
	if not humanoid or not pelvis then
		return
	end
	r.ikL = humanoid:FindFirstChild("FlailL") :: IKControl?
	r.ikR = humanoid:FindFirstChild("FlailR") :: IKControl?
	r.attL = pelvis:FindFirstChild("FlailTargetL") :: Attachment?
	r.attR = pelvis:FindFirstChild("FlailTargetR") :: Attachment?
	if r.ikL and r.ikR and r.attL and r.attR then
		return
	end
	if not RunService:IsServer() then
		return -- replication will deliver them
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

function PoseDriver.step(character: Model, dt: number)
	local fs = character:GetAttribute(MuscleSystem.CONFIG.STATE_ATTR)
	local r = ensureRig(character)
	local pelvis = character:FindFirstChild("LowerTorso") :: BasePart?
	if not pelvis then
		return
	end

	-- ☠️ TRANSFORM OWNERSHIP (verified live 15 JUL, four instrumented rounds):
	-- with ANY track playing, the Animator's apply lands AFTER every script
	-- hook — PreSimulation and BindToSimulation, BOTH peers — and eats the
	-- clip. On the SA-predicted client even track-less script writes never
	-- survive the frame. Consequences, both handled here:
	--   1. the clip writes are SERVER-ONLY (the actor's own client goes
	--      muscle-limp during getup — MuscleSystem.step — and reads the rise
	--      as replicated physics, like observers always have);
	--   2. the server must STOP the tracks itself for the clip to win.
	--      FallingDown used to do this by accident, but that state is driven
	--      by the platform ability scripts via ChangeState — not ours, not
	--      deterministic: one Running-flagged getup let idle eat the clip and
	--      the body popped up straight-legged in 0.6 s (caught on the probe).
	if IS_SERVER and (fs == "getup" or fs == "down") then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in animator:GetPlayingAnimationTracks() do
				-- Stop(0), not a fade: when the platform flips the humanoid to
				-- Running mid-getup the animate script restarts tracks, and a
				-- fading track still OWNS Transform while it dies — idle ate
				-- clip frames through the fade (verified on the retest probe)
				track:Stop(0)
			end
		end
	end

	-- GETUP: write the clip pose into every joint Transform (server only)
	if fs == "getup" and IS_SERVER then
		if not r.wasGetup then
			r.wasGetup = true
			r.faceUp = GetupPose.isFaceUp(pelvis) -- latched: no mid-clip flips
			-- capture the ACTUAL landed pose as the clip's first keyframe.
			-- NOT joint.Transform — the Animator kept writing idle into it
			-- while the body lay limp; the physical truth is the relative
			-- attachment frame.
			local joints = MuscleSystem.getJoints(character)
			local entry: GetupPose.Pose = {}
			if joints then
				for name, joint in joints do
					local a0 = (joint :: any).Attachment0 :: Attachment?
					local a1 = (joint :: any).Attachment1 :: Attachment?
					if a0 and a1 then
						entry[name] = a0.WorldCFrame:ToObjectSpace(a1.WorldCFrame)
					end
				end
			end
			r.entryPose = entry
		end
		local t = tonumber(character:GetAttribute(GetupPose.CONFIG.TIME_ATTR)) or 0
		local pose = GetupPose.poseAt(r.faceUp, t, MuscleSystem.JOINTS, r.entryPose)
		if pose then
			local joints = MuscleSystem.getJoints(character)
			if joints then
				for name, joint in joints do
					joint.Transform = pose[name] :: CFrame
				end
			end
		end
	else
		r.wasGetup = false
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
