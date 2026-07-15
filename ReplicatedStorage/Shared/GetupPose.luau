--!strict
-- Layer 1 · INTENT, get-up half: procedural pose sequences for GETUP.
--
-- No Animation assets: the "clip" is authored keyframes written into
-- AnimationConstraint.Transform during PreSimulation (the official procedural
-- hook — last writer before the batch application, stacks correctly with the
-- Animator). The muscles STRIVE toward these poses at whatever tone the state
-- machine allows — the body physically pushes itself up, or physically fails
-- to. There is no blend, because there is nothing to blend from.
--
-- Both peers evaluate the same sequence from the same replicated clock (the
-- "GT" attribute, server-written elapsed getup time), so prediction agrees.
--
-- Signs/angles are empirical (verified against the live R15 rig, 15 JUL);
-- tune here, not in the driver.

local CONFIG = {
	CLIP_TIME = 1.5, -- total sequence length; PelvisDrive ramps hover height across it
	TIME_ATTR = "GT",
}

export type Pose = { [string]: CFrame }
type Key = { t: number, joints: Pose }

local GetupPose = {}
GetupPose.CONFIG = CONFIG

-- shorthand: rotations in degrees
local function ang(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

-- FACE-UP (supine): tuck knees, sit up through the waist, roll onto feet.
local FACE_UP: { Key } = {
	{ t = 0.0, joints = {
		LeftHip = ang(-70, 0, 0), RightHip = ang(-70, 0, 0),
		LeftKnee = ang(90, 0, 0), RightKnee = ang(90, 0, 0),
		Waist = ang(-30, 0, 0), Neck = ang(-20, 0, 0),
		LeftShoulder = ang(-40, 0, -20), RightShoulder = ang(-40, 0, 20),
	} },
	{ t = 0.6, joints = {
		LeftHip = ang(-90, 0, 0), RightHip = ang(-90, 0, 0),
		LeftKnee = ang(100, 0, 0), RightKnee = ang(100, 0, 0),
		Waist = ang(-40, 0, 0), Neck = ang(-10, 0, 0),
		LeftShoulder = ang(-60, 0, -10), RightShoulder = ang(-60, 0, 10),
		LeftElbow = ang(20, 0, 0), RightElbow = ang(20, 0, 0),
	} },
	{ t = 1.1, joints = {
		-- crouch: feet under the pelvis, torso coming upright
		LeftHip = ang(-60, 0, 0), RightHip = ang(-60, 0, 0),
		LeftKnee = ang(70, 0, 0), RightKnee = ang(70, 0, 0),
		Waist = ang(-15, 0, 0),
	} },
	{ t = 1.5, joints = {} }, -- stand: identity, the Animator's idle takes over
}

-- FACE-DOWN (prone): arms push the chest up, knees walk under, rise.
local FACE_DOWN: { Key } = {
	{ t = 0.0, joints = {
		LeftShoulder = ang(-50, 0, -30), RightShoulder = ang(-50, 0, 30),
		LeftElbow = ang(60, 0, 0), RightElbow = ang(60, 0, 0),
		Waist = ang(20, 0, 0), Neck = ang(30, 0, 0),
		LeftHip = ang(-20, 0, 0), RightHip = ang(-20, 0, 0),
	} },
	{ t = 0.6, joints = {
		-- push-up: elbows extend, hips flex to bring knees under
		LeftShoulder = ang(-80, 0, -15), RightShoulder = ang(-80, 0, 15),
		LeftElbow = ang(10, 0, 0), RightElbow = ang(10, 0, 0),
		Waist = ang(10, 0, 0),
		LeftHip = ang(-80, 0, 0), RightHip = ang(-80, 0, 0),
		LeftKnee = ang(90, 0, 0), RightKnee = ang(90, 0, 0),
	} },
	{ t = 1.1, joints = {
		LeftHip = ang(-60, 0, 0), RightHip = ang(-60, 0, 0),
		LeftKnee = ang(70, 0, 0), RightKnee = ang(70, 0, 0),
		Waist = ang(-10, 0, 0),
	} },
	{ t = 1.5, joints = {} },
}

local IDENTITY = CFrame.identity

-- lying orientation from the PELVIS frame: LookVector points out the belly.
-- Belly toward the sky = supine. On the side counts as supine (the tuck
-- sequence rolls it the rest of the way).
function GetupPose.isFaceUp(pelvis: BasePart): boolean
	return pelvis.CFrame.LookVector.Y > -0.3
end

local function evaluate(keys: { Key }, t: number, jointNames: { string }): Pose
	local a, b = keys[1], keys[#keys]
	for i = 1, #keys - 1 do
		if t >= keys[i].t and t <= keys[i + 1].t then
			a, b = keys[i], keys[i + 1]
			break
		end
	end
	local span = math.max(b.t - a.t, 1e-3)
	local alpha = math.clamp((t - a.t) / span, 0, 1)
	local pose: Pose = {}
	for _, name in jointNames do
		local ca = a.joints[name] or IDENTITY
		local cb = b.joints[name] or IDENTITY
		pose[name] = ca:Lerp(cb, alpha)
	end
	return pose
end

-- the full target pose at elapsed time t; nil once the clip is over
function GetupPose.poseAt(faceUp: boolean, t: number, jointNames: { string }): Pose?
	if t >= CONFIG.CLIP_TIME then
		return nil
	end
	return evaluate(if faceUp then FACE_UP else FACE_DOWN, math.max(t, 0), jointNames)
end

function GetupPose.progress(t: number): number
	return math.clamp(t / CONFIG.CLIP_TIME, 0, 1)
end

return GetupPose
