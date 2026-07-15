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
	JOINT_ATTR_PREFIX = "MJ_",
	-- master tone below this releases CCL balance so the body can actually heap
	COLLAPSE_BALANCE_THRESHOLD = 0.1,
	-- stability guard trip-wires; generous — a real fall is well under these
	RUNAWAY_LINEAR = 512,
	RUNAWAY_ANGULAR = 250,
	-- per-joint driver defaults {strength, damping, torque}. Baseline = AJU factory
	-- values (tuning log 2026-07-14). Root-ward joints get extra damping per the official
	-- anti-oscillation recipe: they don't "see" downstream chain mass.
	DEFAULTS = {
		Root = { 1.0, 1.25, 3000 },
		Waist = { 1.0, 1.25, 3000 },
		Neck = { 1.0, 1.0, 3000 },
		LeftShoulder = { 1.0, 1.0, 3000 },
		LeftElbow = { 1.0, 1.0, 3000 },
		LeftWrist = { 1.0, 1.0, 3000 },
		RightShoulder = { 1.0, 1.0, 3000 },
		RightElbow = { 1.0, 1.0, 3000 },
		RightWrist = { 1.0, 1.0, 3000 },
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
	-- 2000 verified as stable as 10000; still unknockable because chain mass is tiny —
	-- the knockdown sweep (density × balance × muscle rescale) is next session's work.
	BALANCE_TORQUE = 2000,
	-- Human-ish mass distribution; a shove must move MASS, not feather-limbs. R15
	-- blocky part volumes are minuscule (chain = 1.8 vs HRP 2.0 even at these
	-- densities) — expect to raise these ×10-20 during knockdown tuning.
	DENSITY = {
		LowerTorso = 1.2, UpperTorso = 1.0, Head = 0.7,
		LeftUpperLeg = 1.0, RightUpperLeg = 1.0, LeftLowerLeg = 0.7, RightLowerLeg = 0.7,
		LeftFoot = 0.6, RightFoot = 0.6,
		LeftUpperArm = 0.6, RightUpperArm = 0.6, LeftLowerArm = 0.4, RightLowerArm = 0.4,
		LeftHand = 0.3, RightHand = 0.3,
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
	if key == CONFIG.MASTER_TONE_ATTR then
		return true
	end
	local joint, field = key:match("^M_(%a+)_([sdt])$")
	return joint ~= nil and field ~= nil and CONFIG.DEFAULTS[joint :: string] ~= nil
end

function MuscleSystem.clampAttr(key: string, value: number): number
	if key == CONFIG.MASTER_TONE_ATTR then
		return math.clamp(value, 0, 1)
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
	for _, j in MuscleSystem.JOINTS do
		local attr = MuscleSystem.jointAttr(j)
		if character:GetAttribute(attr) == nil then
			character:SetAttribute(attr, MuscleSystem.packTriple(CONFIG.DEFAULTS[j]))
		end
	end
end

-- server, inside sim: land one validated+clamped debug write
function MuscleSystem.applyDebugWrite(character: Model, key: string, value: number)
	if key == CONFIG.MASTER_TONE_ATTR then
		character:SetAttribute(CONFIG.MASTER_TONE_ATTR, value)
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
	return true
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
		local g = gc :: any
		g.BalanceRigidityEnabled = false
		if powered and mt <= CONFIG.COLLAPSE_BALANCE_THRESHOLD then
			g.BalanceMaxTorque = 0
		else
			g.BalanceMaxTorque = CONFIG.BALANCE_TORQUE * (if powered then mt else 1)
		end
	end)
	MuscleSystem.lastBalanceError = if ok then nil else tostring(err)
end

-- server-only trip-wire: NaN or runaway velocity on any body part
function MuscleSystem.guard(character: Model): string?
	for _, part in character:GetChildren() do
		if part:IsA("BasePart") then
			local v = part.AssemblyLinearVelocity
			local w = part.AssemblyAngularVelocity
			if v.X ~= v.X or w.X ~= w.X then
				return part.Name .. " velocity is NaN"
			end
			if v.Magnitude > CONFIG.RUNAWAY_LINEAR or w.Magnitude > CONFIG.RUNAWAY_ANGULAR then
				return ("%s v=%.0f w=%.0f"):format(part.Name, v.Magnitude, w.Magnitude)
			end
		end
	end
	return nil
end

return MuscleSystem
